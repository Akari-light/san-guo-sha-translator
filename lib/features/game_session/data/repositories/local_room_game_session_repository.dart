import 'dart:async';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/contracts/game_session_repository.dart';
import '../../domain/models/game_session_connection_state.dart';
import '../../domain/models/game_session_invite.dart';
import '../../domain/models/game_session_player.dart';
import '../../domain/models/game_session_room.dart';
import '../../domain/models/pending_session_selection.dart';
import '../services/local_room_game_session_client.dart';
import '../services/local_room_game_session_host_server.dart';
import '../services/local_room_game_session_invite_codec.dart';

class LocalRoomGameSessionRepository implements GameSessionRepository {
  LocalRoomGameSessionRepository._();

  static final LocalRoomGameSessionRepository instance =
      LocalRoomGameSessionRepository._();

  static const LocalRoomGameSessionInviteCodec _inviteCodec =
      LocalRoomGameSessionInviteCodec();
  static const String _playerIdPrefsKey = 'game_session.local_room.player_id';

  final StreamController<GameSessionRoom?> _controller =
      StreamController<GameSessionRoom?>.broadcast();
  final StreamController<GameSessionConnectionState> _connectionController =
      StreamController<GameSessionConnectionState>.broadcast();
  final Map<String, String> _cachedInvitesByRoomCode = <String, String>{};
  final Random _random = Random.secure();

  LocalRoomGameSessionHostServer? _hostServer;
  LocalRoomGameSessionHostServer? _standbyServer;
  LocalRoomGameSessionClient? _client;
  StreamSubscription<GameSessionRoom?>? _hostWatchSubscription;
  StreamSubscription<GameSessionRoom?>? _clientWatchSubscription;
  GameSessionRoom? _currentRoom;
  GameSessionInvite? _activeInvite;
  String? _localPlayerId;
  bool _isSuspended = false;
  int _sessionEpoch = 0;
  Future<void> _operationQueue = Future<void>.value();
  GameSessionConnectionState _connection = GameSessionConnectionState.idle;

  @override
  Stream<GameSessionRoom?> watchRoom() => _controller.stream;

  @override
  Stream<GameSessionConnectionState> watchConnection() =>
      _connectionController.stream;

  @override
  GameSessionRoom? get currentRoom => _currentRoom;

  @override
  GameSessionConnectionState get currentConnection => _connection;

  @override
  bool get hasActiveSession => _currentRoom != null;

  @override
  String? get activeRoomCode => _currentRoom?.roomCode;

  @override
  String? get activeInvitePayload =>
      _currentRoom?.invitePayload ?? _invitePayloadForActiveInvite;

  @override
  Future<GameSessionRoom> createRoom({
    required String displayName,
    PendingSessionSelection? pendingSelection,
  }) async {
    return _runExclusive(() async {
      await _clearSession(closeConnections: true);
      _emitConnection(
        const GameSessionConnectionState(
          status: GameSessionConnectionStatus.connecting,
          message: 'Creating room...',
        ),
      );

      final playerId = await _ensurePlayerId();
      final hostServer = await LocalRoomGameSessionHostServer.bind();
      try {
        final invite = GameSessionInvite(
          roomId: _randomToken(12),
          roomCode: _generateRoomCode(),
          createdAt: DateTime.now(),
          hostAddress: hostServer.hostAddress,
          hostPort: hostServer.port,
          accessToken: _randomToken(24),
          issuedByPlayerId: playerId,
        );
        final invitePayload = _inviteCodec.encode(invite);
        final room = await hostServer.createRoom(
          roomId: invite.roomId,
          roomCode: invite.roomCode,
          invitePayload: invitePayload,
          playerId: playerId,
          displayName: _normalizeDisplayName(displayName),
          pendingSelection: pendingSelection,
        );

        _hostServer = hostServer;
        _localPlayerId = playerId;
        _activeInvite = invite;
        _cachedInvitesByRoomCode[invite.roomCode] = invitePayload;
        await _startHostWatch(hostServer);
        _applyRoom(room, status: GameSessionConnectionStatus.hosting);
        return room;
      } catch (_) {
        await hostServer.close();
        _emitConnection(
          const GameSessionConnectionState(
            status: GameSessionConnectionStatus.failed,
            message: 'Could not create room.',
          ),
        );
        rethrow;
      }
    });
  }

  @override
  Future<GameSessionRoom> joinFromInvite({
    required String invitePayload,
    required String displayName,
    PendingSessionSelection? pendingSelection,
  }) async {
    return _runExclusive(() async {
      await cacheInvitePayload(invitePayload);
      final invite = decodeInvite(invitePayload);
      await _clearSession(closeConnections: true);
      _emitConnection(
        const GameSessionConnectionState(
          status: GameSessionConnectionStatus.connecting,
          message: 'Joining room...',
        ),
      );
      final playerId = await _ensurePlayerId();
      final standbyServer = await LocalRoomGameSessionHostServer.bind();
      final client = LocalRoomGameSessionClient(
        invite: invite,
        playerId: playerId,
      );

      try {
        final room = await client.joinRoom(
          displayName: _normalizeDisplayName(displayName),
          pendingSelection: pendingSelection,
          localHostAddress: standbyServer.hostAddress,
          localHostPort: standbyServer.port,
        );
        _client = client;
        _standbyServer = standbyServer;
        _activeInvite = invite;
        _localPlayerId ??= playerId;
        await _refreshStandbyRoom(room);
        _applyRoom(room, status: GameSessionConnectionStatus.connected);
        await _startClientWatch(client);
        if (_isSuspended) {
          await _setPresence(GameSessionPresence.away);
        }
        return room;
      } catch (_) {
        await client.close();
        await standbyServer.close();
        _emitConnection(
          const GameSessionConnectionState(
            status: GameSessionConnectionStatus.failed,
            message: 'Could not join room.',
          ),
        );
        rethrow;
      }
    });
  }

  @override
  Future<GameSessionRoom> joinFromRoomCode({
    required String roomCode,
    required String displayName,
    PendingSessionSelection? pendingSelection,
  }) async {
    final normalizedRoomCode = roomCode.trim().toUpperCase();
    if (normalizedRoomCode.isEmpty) {
      throw StateError('Enter a room code first.');
    }

    final invitePayload = _cachedInvitesByRoomCode[normalizedRoomCode];
    if (invitePayload == null || invitePayload.trim().isEmpty) {
      throw StateError(
        'Room code alone only works after you have scanned or imported the host room invite on this device.',
      );
    }

    return joinFromInvite(
      invitePayload: invitePayload,
      displayName: displayName,
      pendingSelection: pendingSelection,
    );
  }

  @override
  Future<void> cacheInvitePayload(String invitePayload) async {
    final invite = decodeInvite(invitePayload);
    if (invite.roomCode.isEmpty) {
      throw StateError('This room invite is not valid.');
    }
    _cachedInvitesByRoomCode[invite.roomCode] = invitePayload.trim();
  }

  @override
  Future<void> setMyGeneral({required String generalId, String? skinId}) async {
    return _runExclusive(() async {
      final room = _requireRoom();
      final playerId = await _ensurePlayerId();

      if (_isHostingRoom) {
        final nextRoom = await _hostServer!.setMyGeneral(
          roomCode: room.roomCode,
          playerId: playerId,
          generalId: generalId,
          skinId: skinId,
        );
        _applyRoom(nextRoom, status: GameSessionConnectionStatus.hosting);
        return;
      }

      final client = _requireClient();
      final nextRoom = await client.setMyGeneral(
        generalId: generalId,
        skinId: skinId,
      );
      _applyRoom(nextRoom, status: GameSessionConnectionStatus.connected);
    });
  }

  @override
  Future<void> leaveRoom() async {
    return _runExclusive(() async {
      if (_currentRoom == null) {
        await _clearSession(closeConnections: true);
        return;
      }

      final roomCode = _currentRoom!.roomCode;
      final playerId = await _ensurePlayerId();

      if (_isHostingRoom) {
        try {
          await _hostServer!.leaveRoom(roomCode: roomCode, playerId: playerId);
        } finally {
          await _clearSession(closeConnections: true);
        }
        return;
      }

      try {
        await _client?.leaveRoom();
      } catch (_) {
        // If the host is already gone, we still clear local session state.
      } finally {
        await _clearSession(closeConnections: true);
      }
    });
  }

  @override
  Future<void> suspend() async {
    return _runExclusive(() async {
      _isSuspended = true;
      if (_currentRoom == null) return;

      try {
        await _setPresence(GameSessionPresence.away);
      } catch (_) {
        // Best effort only during lifecycle transitions.
      }

      await _stopClientWatch(closeClient: false);
    });
  }

  @override
  Future<void> resume() async {
    return _runExclusive(() async {
      _isSuspended = false;
      if (_currentRoom == null) return;

      if (_isHostingRoom) {
        try {
          await _setPresence(GameSessionPresence.online);
        } catch (_) {
          // Best effort only.
        }
        return;
      }

      final client = _client;
      if (client == null) {
        await _clearSession(closeConnections: true);
        return;
      }

      try {
        final room = await client.fetchRoom();
        if (room == null) {
          await _clearSession(closeConnections: true);
          return;
        }
        _applyRoom(room);
        await _setPresence(GameSessionPresence.online);
        await _startClientWatch(client);
      } catch (_) {
        await _recoverClientWatchLoss(_sessionEpoch);
      }
    });
  }

  @override
  GameSessionInvite decodeInvite(String invitePayload) =>
      _inviteCodec.decode(invitePayload);

  bool get _isHostingRoom => _hostServer != null && _currentRoom != null;

  String? get _invitePayloadForActiveInvite {
    final invite = _activeInvite;
    if (invite == null) return null;
    return _inviteCodec.encode(invite);
  }

  Future<void> _startClientWatch(LocalRoomGameSessionClient client) async {
    await _stopClientWatch(closeClient: false);
    final epoch = _sessionEpoch;
    _clientWatchSubscription = client.watchRoom().listen(
      (room) {
        if (epoch != _sessionEpoch) return;
        if (room == null) {
          unawaited(_handleRoomClosed(epoch));
          return;
        }
        _applyRoom(room, status: GameSessionConnectionStatus.connected);
      },
      onError: (_) {
        if (_isSuspended) return;
        unawaited(_recoverClientWatchLoss(epoch));
      },
      onDone: () {
        if (_isSuspended) return;
        unawaited(_recoverClientWatchLoss(epoch));
      },
    );
  }

  Future<void> _startHostWatch(
    LocalRoomGameSessionHostServer hostServer,
  ) async {
    await _hostWatchSubscription?.cancel();
    _hostWatchSubscription = hostServer.watchRoom().listen((room) {
      if (room == null) {
        _currentRoom = null;
        _activeInvite = null;
        _controller.add(null);
        _emitConnection(
          const GameSessionConnectionState(
            status: GameSessionConnectionStatus.closed,
            message: 'Room closed.',
          ),
        );
        return;
      }
      _applyRoom(room, status: GameSessionConnectionStatus.hosting);
    });
  }

  Future<void> _stopClientWatch({required bool closeClient}) async {
    await _clientWatchSubscription?.cancel();
    _clientWatchSubscription = null;
    if (closeClient) {
      await _client?.close();
      _client = null;
    }
  }

  Future<void> _setPresence(GameSessionPresence presence) async {
    final room = _requireRoom();
    final playerId = await _ensurePlayerId();

    if (_isHostingRoom) {
      final nextRoom = await _hostServer!.setPresence(
        roomCode: room.roomCode,
        playerId: playerId,
        presence: presence,
      );
      _applyRoom(nextRoom, status: GameSessionConnectionStatus.hosting);
      return;
    }

    final client = _requireClient();
    final nextRoom = await client.setPresence(presence);
    _applyRoom(nextRoom, status: GameSessionConnectionStatus.connected);
  }

  void _applyRoom(
    GameSessionRoom room, {
    GameSessionConnectionStatus? status,
    String? message,
    bool preserveActiveInvite = false,
  }) {
    _currentRoom = room;
    if (!preserveActiveInvite && room.invitePayload.trim().isNotEmpty) {
      _cachedInvitesByRoomCode[room.roomCode] = room.invitePayload.trim();
      _activeInvite = decodeInvite(room.invitePayload);
    }
    unawaited(_refreshStandbyRoom(room));
    _controller.add(room);
    _emitConnection(
      GameSessionConnectionState(
        status:
            status ??
            (_isHostingRoom
                ? GameSessionConnectionStatus.hosting
                : GameSessionConnectionStatus.connected),
        room: room,
        isHost: _isHostingRoom,
        message: message,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _clearSession({
    required bool closeConnections,
    bool emitIdle = true,
  }) async {
    _sessionEpoch += 1;
    if (closeConnections) {
      await _hostWatchSubscription?.cancel();
      _hostWatchSubscription = null;
      await _stopClientWatch(closeClient: true);
      final hostServer = _hostServer;
      _hostServer = null;
      if (hostServer != null) {
        await hostServer.close();
      }
      final standbyServer = _standbyServer;
      _standbyServer = null;
      if (standbyServer != null) {
        await standbyServer.close();
      }
    } else {
      await _stopClientWatch(closeClient: false);
    }
    _currentRoom = null;
    _activeInvite = null;
    _controller.add(null);
    if (emitIdle) {
      _emitConnection(GameSessionConnectionState.idle);
    }
  }

  Future<void> _handleRoomClosed(int epoch) async {
    if (epoch != _sessionEpoch) return;
    _emitConnection(
      GameSessionConnectionState(
        status: GameSessionConnectionStatus.closed,
        room: _currentRoom,
        message: 'Host closed the room.',
        updatedAt: DateTime.now(),
      ),
    );
    await _clearSession(closeConnections: true, emitIdle: false);
  }

  Future<void> _recoverClientWatchLoss(int epoch) async {
    if (epoch != _sessionEpoch || _isHostingRoom || _isSuspended) return;
    final client = _client;
    if (client == null) return;

    for (var attempt = 1; attempt <= 3; attempt += 1) {
      if (epoch != _sessionEpoch || _isSuspended) return;
      _emitConnection(
        GameSessionConnectionState(
          status: GameSessionConnectionStatus.reconnecting,
          room: _currentRoom,
          retryAttempt: attempt,
          message: 'Reconnecting to host...',
          updatedAt: DateTime.now(),
        ),
      );
      await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
      try {
        final room = await client.fetchRoom();
        if (epoch != _sessionEpoch || _isSuspended) return;
        if (room == null) {
          await _handleRoomClosed(epoch);
          return;
        }
        _applyRoom(
          room,
          status: GameSessionConnectionStatus.connected,
          message: 'Reconnected.',
        );
        await _startClientWatch(client);
        return;
      } catch (_) {
        // Try again or fall through to host handoff.
      }
    }

    await _attemptHostHandoff(epoch);
  }

  Future<void> _attemptHostHandoff(int epoch) async {
    if (epoch != _sessionEpoch || _isHostingRoom || _isSuspended) return;
    final room = _currentRoom;
    final invite = _activeInvite;
    final localPlayerId = await _ensurePlayerId();
    if (epoch != _sessionEpoch || _isSuspended) return;
    if (room == null || invite == null) {
      await _clearSession(closeConnections: true);
      return;
    }

    final candidate = _nextHandoffPlayer(room);
    if (candidate == null) {
      _emitConnection(
        GameSessionConnectionState(
          status: GameSessionConnectionStatus.failed,
          room: room,
          message: 'Host is unreachable.',
          updatedAt: DateTime.now(),
        ),
      );
      return;
    }

    if (candidate.playerId == localPlayerId) {
      await _promoteLocalStandby(room, invite, localPlayerId, epoch);
      return;
    }

    await _followHandoffHost(room, invite, candidate, epoch);
  }

  Future<void> _promoteLocalStandby(
    GameSessionRoom room,
    GameSessionInvite invite,
    String localPlayerId,
    int epoch,
  ) async {
    final standbyServer = _standbyServer;
    if (standbyServer == null || epoch != _sessionEpoch) {
      await _clearSession(closeConnections: true);
      return;
    }
    _emitConnection(
      GameSessionConnectionState(
        status: GameSessionConnectionStatus.handoff,
        room: room,
        isHost: true,
        message: 'Taking over as host...',
        updatedAt: DateTime.now(),
      ),
    );
    final nextInvite = GameSessionInvite(
      roomId: invite.roomId,
      roomCode: invite.roomCode,
      createdAt: DateTime.now(),
      hostAddress: standbyServer.hostAddress,
      hostPort: standbyServer.port,
      accessToken: invite.accessToken,
      issuedByPlayerId: localPlayerId,
      kind: invite.kind,
      version: invite.version,
    );
    final invitePayload = _inviteCodec.encode(nextInvite);
    final nextRoom = await standbyServer.promoteStandby(
      roomCode: room.roomCode,
      localPlayerId: localPlayerId,
      invitePayload: invitePayload,
    );
    if (epoch != _sessionEpoch || _isSuspended) return;
    await _stopClientWatch(closeClient: true);
    _hostServer = standbyServer;
    _standbyServer = null;
    _activeInvite = nextInvite;
    _cachedInvitesByRoomCode[nextInvite.roomCode] = invitePayload;
    await _startHostWatch(standbyServer);
    _applyRoom(
      nextRoom,
      status: GameSessionConnectionStatus.hosting,
      message: 'This device is now hosting the room.',
    );
  }

  Future<void> _followHandoffHost(
    GameSessionRoom room,
    GameSessionInvite invite,
    GameSessionPlayer candidate,
    int epoch,
  ) async {
    final hostAddress = candidate.hostAddress;
    final hostPort = candidate.hostPort;
    if (hostAddress == null || hostAddress.isEmpty || hostPort == null) {
      _emitConnection(
        GameSessionConnectionState(
          status: GameSessionConnectionStatus.failed,
          room: room,
          message: 'Backup host is not reachable.',
          updatedAt: DateTime.now(),
        ),
      );
      return;
    }

    _emitConnection(
      GameSessionConnectionState(
        status: GameSessionConnectionStatus.handoff,
        room: room,
        message: 'Connecting to new host...',
        updatedAt: DateTime.now(),
      ),
    );
    final handoffInvite = GameSessionInvite(
      roomId: invite.roomId,
      roomCode: invite.roomCode,
      createdAt: invite.createdAt,
      hostAddress: hostAddress,
      hostPort: hostPort,
      accessToken: invite.accessToken,
      issuedByPlayerId: candidate.playerId,
      kind: invite.kind,
      version: invite.version,
    );
    final nextClient = LocalRoomGameSessionClient(
      invite: handoffInvite,
      playerId: await _ensurePlayerId(),
    );

    for (var attempt = 1; attempt <= 5; attempt += 1) {
      if (epoch != _sessionEpoch || _isSuspended) {
        await nextClient.close();
        return;
      }
      try {
        await Future<void>.delayed(Duration(milliseconds: 450 * attempt));
        final nextRoom = await nextClient.fetchRoom();
        if (epoch != _sessionEpoch || _isSuspended) {
          await nextClient.close();
          return;
        }
        if (nextRoom == null) continue;
        if (nextRoom.coordinatorPlayerId != candidate.playerId) continue;
        await _stopClientWatch(closeClient: true);
        _client = nextClient;
        _activeInvite = handoffInvite;
        _applyRoom(
          nextRoom,
          status: GameSessionConnectionStatus.connected,
          message: 'Connected to new host.',
          preserveActiveInvite: true,
        );
        await _startClientWatch(nextClient);
        return;
      } catch (_) {
        // Retry while the elected device promotes itself.
      }
    }

    await nextClient.close();
    _emitConnection(
      GameSessionConnectionState(
        status: GameSessionConnectionStatus.failed,
        room: room,
        message: 'Could not reach the backup host.',
        updatedAt: DateTime.now(),
      ),
    );
  }

  GameSessionPlayer? _nextHandoffPlayer(GameSessionRoom room) {
    final players = room.orderedPlayers;
    if (players.isEmpty) return null;
    final coordinatorIndex = players.indexWhere(
      (player) => player.playerId == room.coordinatorPlayerId,
    );
    final startIndex = coordinatorIndex < 0 ? 0 : coordinatorIndex + 1;
    for (var offset = 0; offset < players.length; offset += 1) {
      final player = players[(startIndex + offset) % players.length];
      if (player.playerId == room.coordinatorPlayerId) continue;
      if (player.presence == GameSessionPresence.offline) continue;
      if (player.hostAddress == null || player.hostPort == null) continue;
      return player;
    }
    return null;
  }

  Future<void> _refreshStandbyRoom(GameSessionRoom room) async {
    final standbyServer = _standbyServer;
    final invite = _activeInvite;
    final accessToken = invite?.accessToken;
    if (standbyServer == null || accessToken == null || accessToken.isEmpty) {
      return;
    }
    final epoch = _sessionEpoch;
    final localPlayerId = await _ensurePlayerId();
    if (epoch != _sessionEpoch || _standbyServer != standbyServer) {
      return;
    }
    await standbyServer.updateStandbyRoom(
      room: room,
      localPlayerId: localPlayerId,
      accessToken: accessToken,
    );
  }

  void _emitConnection(GameSessionConnectionState state) {
    _connection = state;
    _connectionController.add(state);
  }

  Future<T> _runExclusive<T>(Future<T> Function() action) {
    final previous = _operationQueue;
    final completer = Completer<T>();
    _operationQueue = previous.catchError((_) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  LocalRoomGameSessionClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError(
        'No active Game Session join is available on this device.',
      );
    }
    return client;
  }

  GameSessionRoom _requireRoom() {
    final room = _currentRoom;
    if (room == null) {
      throw StateError('Open or join a Game Session first.');
    }
    return room;
  }

  Future<String> _ensurePlayerId() async {
    final existing = _localPlayerId;
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_playerIdPrefsKey);
    if (stored != null && stored.isNotEmpty) {
      _localPlayerId = stored;
      return stored;
    }

    final created = _randomToken(16);
    await prefs.setString(_playerIdPrefsKey, created);
    _localPlayerId = created;
    return created;
  }

  String _generateRoomCode() {
    const characters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    for (var attempt = 0; attempt < 12; attempt += 1) {
      final code = List<String>.generate(
        6,
        (_) => characters[_random.nextInt(characters.length)],
        growable: false,
      ).join();
      if (!_cachedInvitesByRoomCode.containsKey(code) &&
          _currentRoom?.roomCode != code) {
        return code;
      }
    }
    return _randomToken(6).toUpperCase();
  }

  String _randomToken(int length) {
    const characters = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List<String>.generate(
      length,
      (_) => characters[_random.nextInt(characters.length)],
      growable: false,
    ).join();
  }

  String _normalizeDisplayName(String displayName) {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) {
      return 'Player';
    }
    return trimmed;
  }
}
