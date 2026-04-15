import 'dart:async';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/contracts/game_session_repository.dart';
import '../../domain/models/game_session_invite.dart';
import '../../domain/models/game_session_player.dart';
import '../../domain/models/game_session_room.dart';
import '../../domain/models/pending_session_selection.dart';
import '../services/local_room_game_session_client.dart';
import '../services/local_room_game_session_host_server.dart';
import '../services/local_room_game_session_invite_codec.dart';

class LocalRoomGameSessionRepository implements GameSessionRepository {
  LocalRoomGameSessionRepository._();

  static final LocalRoomGameSessionRepository instance = LocalRoomGameSessionRepository._();

  static const LocalRoomGameSessionInviteCodec _inviteCodec = LocalRoomGameSessionInviteCodec();
  static const String _playerIdPrefsKey = 'game_session.local_room.player_id';

  final StreamController<GameSessionRoom?> _controller = StreamController<GameSessionRoom?>.broadcast();
  final Map<String, String> _cachedInvitesByRoomCode = <String, String>{};
  final Random _random = Random.secure();

  LocalRoomGameSessionHostServer? _hostServer;
  LocalRoomGameSessionClient? _client;
  StreamSubscription<GameSessionRoom?>? _clientWatchSubscription;
  GameSessionRoom? _currentRoom;
  GameSessionInvite? _activeInvite;
  String? _localPlayerId;
  bool _isSuspended = false;

  @override
  Stream<GameSessionRoom?> watchRoom() => _controller.stream;

  @override
  GameSessionRoom? get currentRoom => _currentRoom;

  @override
  bool get hasActiveSession => _currentRoom != null;

  @override
  String? get activeRoomCode => _currentRoom?.roomCode;

  @override
  String? get activeInvitePayload => _currentRoom?.invitePayload ?? _invitePayloadForActiveInvite;

  @override
  Future<GameSessionRoom> createRoom({
    required String displayName,
    PendingSessionSelection? pendingSelection,
  }) async {
    await _clearSession(closeConnections: true);

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
      _applyRoom(room);
      return room;
    } catch (_) {
      await hostServer.close();
      rethrow;
    }
  }

  @override
  Future<GameSessionRoom> joinFromInvite({
    required String invitePayload,
    required String displayName,
    PendingSessionSelection? pendingSelection,
  }) async {
    await cacheInvitePayload(invitePayload);
    final invite = decodeInvite(invitePayload);
    final client = LocalRoomGameSessionClient(
      invite: invite,
      playerId: await _ensurePlayerId(),
    );

    await _clearSession(closeConnections: true);
    try {
      final room = await client.joinRoom(
        displayName: _normalizeDisplayName(displayName),
        pendingSelection: pendingSelection,
      );
      _client = client;
      _activeInvite = invite;
      _localPlayerId ??= await _ensurePlayerId();
      _applyRoom(room);
      await _startClientWatch(client);
      if (_isSuspended) {
        await _setPresence(GameSessionPresence.away);
      }
      return room;
    } catch (_) {
      await client.close();
      rethrow;
    }
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
    final room = _requireRoom();
    final playerId = await _ensurePlayerId();

    if (_isHostingRoom) {
      final nextRoom = await _hostServer!.setMyGeneral(
        roomCode: room.roomCode,
        playerId: playerId,
        generalId: generalId,
        skinId: skinId,
      );
      _applyRoom(nextRoom);
      return;
    }

    final client = _requireClient();
    final nextRoom = await client.setMyGeneral(
      generalId: generalId,
      skinId: skinId,
    );
    _applyRoom(nextRoom);
  }

  @override
  Future<void> leaveRoom() async {
    if (_currentRoom == null) {
      await _clearSession(closeConnections: true);
      return;
    }

    final roomCode = _currentRoom!.roomCode;
    final playerId = await _ensurePlayerId();

    if (_isHostingRoom) {
      try {
        await _hostServer!.leaveRoom(
          roomCode: roomCode,
          playerId: playerId,
        );
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
  }

  @override
  Future<void> suspend() async {
    _isSuspended = true;
    if (_currentRoom == null) return;

    try {
      await _setPresence(GameSessionPresence.away);
    } catch (_) {
      // Best effort only during lifecycle transitions.
    }

    await _stopClientWatch(closeClient: false);
  }

  @override
  Future<void> resume() async {
    _isSuspended = false;
    if (_currentRoom == null) return;

    if (_isHostingRoom) {
      try {
        final client = _client;
        if (client != null) {
          await _startClientWatch(client);
        }
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
      await _clearSession(closeConnections: true);
    }
  }

  @override
  GameSessionInvite decodeInvite(String invitePayload) => _inviteCodec.decode(invitePayload);

  bool get _isHostingRoom => _hostServer != null && _currentRoom != null;

  String? get _invitePayloadForActiveInvite {
    final invite = _activeInvite;
    if (invite == null) return null;
    return _inviteCodec.encode(invite);
  }

  Future<void> _startClientWatch(LocalRoomGameSessionClient client) async {
    await _stopClientWatch(closeClient: false);
    _clientWatchSubscription = client.watchRoom().listen(
      (room) {
        if (room == null) {
          unawaited(_clearSession(closeConnections: true));
          return;
        }
        _applyRoom(room);
      },
      onError: (_) {
        if (_isSuspended) return;
        unawaited(_clearSession(closeConnections: true));
      },
    );
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
      _applyRoom(nextRoom);
      return;
    }

    final client = _requireClient();
    final nextRoom = await client.setPresence(presence);
    _applyRoom(nextRoom);
  }

  void _applyRoom(GameSessionRoom room) {
    _currentRoom = room;
    if (room.invitePayload.trim().isNotEmpty) {
      _cachedInvitesByRoomCode[room.roomCode] = room.invitePayload.trim();
      _activeInvite = decodeInvite(room.invitePayload);
    }
    _controller.add(room);
  }

  Future<void> _clearSession({required bool closeConnections}) async {
    if (closeConnections) {
      await _stopClientWatch(closeClient: true);
      final hostServer = _hostServer;
      _hostServer = null;
      if (hostServer != null) {
        await hostServer.close();
      }
    } else {
      await _stopClientWatch(closeClient: false);
    }
    _currentRoom = null;
    _activeInvite = null;
    _controller.add(null);
  }

  LocalRoomGameSessionClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError('No active Game Session join is available on this device.');
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
      if (!_cachedInvitesByRoomCode.containsKey(code) && _currentRoom?.roomCode != code) {
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
