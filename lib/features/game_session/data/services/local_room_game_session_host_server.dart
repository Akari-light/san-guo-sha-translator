import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/models/game_session_player.dart';
import '../../domain/models/game_session_room.dart';
import '../../domain/models/pending_session_selection.dart';
import 'local_room_game_session_invite_codec.dart';

class LocalRoomGameSessionHostServer {
  LocalRoomGameSessionHostServer._(this._server, {required this.hostAddress});

  static Future<LocalRoomGameSessionHostServer> bind() async {
    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      0,
      shared: true,
    );
    final hostAddress = await _resolvePreferredHostAddress();
    debugPrint(
      'Bound local room server on 0.0.0.0:${server.port}; '
      'advertising $hostAddress:${server.port}',
    );
    final instance = LocalRoomGameSessionHostServer._(
      server,
      hostAddress: hostAddress,
    );
    unawaited(instance._serve());
    return instance;
  }

  final HttpServer _server;
  final String hostAddress;
  _LocalRoomState? _state;
  bool _isActiveHost = false;
  bool _closed = false;
  final List<_Subscriber> _subscribers = <_Subscriber>[];
  final StreamController<GameSessionRoom?> _roomController =
      StreamController<GameSessionRoom?>.broadcast();

  int get port => _server.port;

  GameSessionRoom? get currentRoom => _state?.room;

  Stream<GameSessionRoom?> watchRoom() => _roomController.stream;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final state = _state;
    _state = null;
    _isActiveHost = false;
    if (state != null) {
      await _broadcastClosed(state.room.roomCode);
    }
    for (final subscriber in [..._subscribers]) {
      await subscriber.close();
    }
    _subscribers.clear();
    await _server.close(force: true);
    if (!_roomController.isClosed) {
      await _roomController.close();
    }
  }

  Future<GameSessionRoom> createRoom({
    required String roomId,
    required String roomCode,
    required String invitePayload,
    required String playerId,
    required String displayName,
    PendingSessionSelection? pendingSelection,
  }) async {
    if (_state != null && _state!.room.status != 'closed') {
      throw StateError('A Game Session is already active on this host.');
    }

    final now = DateTime.now();
    final player = _buildPlayer(
      playerId: playerId,
      displayName: displayName,
      joinedAt: now,
      lastSeenAt: now,
      presence: GameSessionPresence.online,
      pendingSelection: pendingSelection,
      hostAddress: hostAddress,
      hostPort: port,
    );
    _state = _LocalRoomState(
      room: GameSessionRoom(
        roomId: roomId,
        roomCode: roomCode,
        coordinatorPlayerId: playerId,
        revision: 1,
        status: 'active',
        players: <GameSessionPlayer>[player],
        invitePayload: invitePayload,
      ),
      hostPlayerId: playerId,
      accessToken: _requireInviteToken(invitePayload),
    );
    _isActiveHost = true;
    await _broadcastRoom();
    return _state!.room;
  }

  Future<void> updateStandbyRoom({
    required GameSessionRoom room,
    required String localPlayerId,
    required String accessToken,
  }) async {
    if (_isActiveHost) {
      return;
    }
    _state = _LocalRoomState(
      room: room,
      hostPlayerId: localPlayerId,
      accessToken: accessToken,
    );
    _isActiveHost = false;
  }

  Future<GameSessionRoom> promoteStandby({
    required String roomCode,
    required String localPlayerId,
    required String invitePayload,
  }) async {
    final state = _state;
    if (state == null ||
        state.room.roomCode != roomCode ||
        state.room.status == 'closed') {
      throw StateError('No standby Game Session is available to promote.');
    }
    final previousCoordinatorPlayerId = state.room.coordinatorPlayerId;
    final updatedPlayers = [
      for (final player in state.room.players)
        if (player.playerId != previousCoordinatorPlayerId ||
            player.playerId == localPlayerId)
          if (player.playerId == localPlayerId)
            player.copyWith(
              presence: GameSessionPresence.online,
              lastSeenAt: DateTime.now(),
              hostAddress: hostAddress,
              hostPort: port,
            )
          else
            player,
    ];
    state.room = state.room.copyWith(
      coordinatorPlayerId: localPlayerId,
      revision: state.room.revision + 1,
      status: 'active',
      invitePayload: invitePayload,
      players: _orderPlayers(updatedPlayers),
    );
    _isActiveHost = true;
    await _broadcastRoom();
    return state.room;
  }

  Future<GameSessionRoom> joinRoom({
    required String roomCode,
    required String playerId,
    required String displayName,
    PendingSessionSelection? pendingSelection,
    String? hostAddress,
    int? hostPort,
  }) async {
    final state = _requireOpenState(roomCode);
    final existing = state.room.playerById(playerId);
    final now = DateTime.now();
    final nextPlayer = _buildPlayer(
      playerId: playerId,
      displayName: displayName,
      joinedAt: existing?.joinedAt ?? now,
      lastSeenAt: now,
      presence: GameSessionPresence.online,
      pendingSelection: pendingSelection,
      existing: existing,
      hostAddress: hostAddress,
      hostPort: hostPort,
    );
    if (existing == null && state.room.players.length >= 10) {
      throw StateError('This room is already full.');
    }
    final nextPlayers = <GameSessionPlayer>[
      for (final player in state.room.players)
        if (player.playerId != playerId) player,
      nextPlayer,
    ];
    state.room = state.room.copyWith(
      revision: state.room.revision + 1,
      players: _orderPlayers(nextPlayers),
      status: 'active',
    );
    await _broadcastRoom();
    return state.room;
  }

  Future<GameSessionRoom> setMyGeneral({
    required String roomCode,
    required String playerId,
    String? generalId,
    String? skinId,
  }) async {
    final state = _requireOpenState(roomCode);
    final existing = state.room.playerById(playerId);
    if (existing == null) {
      throw StateError('That player is not part of the room.');
    }
    final now = DateTime.now();
    final updatedPlayer = existing.copyWith(
      generalId: generalId,
      skinId: generalId == null ? null : skinId,
      presence: GameSessionPresence.online,
      lastSeenAt: now,
    );
    state.room = state.room.copyWith(
      revision: state.room.revision + 1,
      players: _orderPlayers([
        for (final player in state.room.players)
          if (player.playerId == playerId) updatedPlayer else player,
      ]),
    );
    await _broadcastRoom();
    return state.room;
  }

  Future<GameSessionRoom> setPresence({
    required String roomCode,
    required String playerId,
    required GameSessionPresence presence,
  }) async {
    final state = _requireOpenState(roomCode);
    final existing = state.room.playerById(playerId);
    if (existing == null) {
      throw StateError('That player is not part of the room.');
    }
    final now = DateTime.now();
    final updatedPlayer = existing.copyWith(
      presence: presence,
      lastSeenAt: now,
    );
    state.room = state.room.copyWith(
      revision: state.room.revision + 1,
      players: _orderPlayers([
        for (final player in state.room.players)
          if (player.playerId == playerId) updatedPlayer else player,
      ]),
    );
    await _broadcastRoom();
    return state.room;
  }

  Future<GameSessionRoom> leaveRoom({
    required String roomCode,
    required String playerId,
  }) async {
    final state = _requireOpenState(roomCode);
    final existing = state.room.playerById(playerId);
    if (existing == null) {
      throw StateError('That player is not part of the room.');
    }

    if (playerId == state.hostPlayerId) {
      return _transferHostOrClose(state, playerId);
    }

    final remainingPlayers = [
      for (final player in state.room.players)
        if (player.playerId != playerId) player,
    ];
    if (remainingPlayers.isEmpty) {
      await _closeRoom(state.room.roomCode, keepServerAlive: true);
      return state.room.copyWith(status: 'closed');
    }

    state.room = state.room.copyWith(
      revision: state.room.revision + 1,
      players: _orderPlayers(remainingPlayers),
    );
    await _broadcastRoom();
    return state.room;
  }

  Future<GameSessionRoom?> fetchRoom({required String roomCode}) async {
    final state = _state;
    if (state == null ||
        state.room.roomCode != roomCode ||
        state.room.status == 'closed' ||
        !_isActiveHost) {
      return null;
    }
    return state.room;
  }

  Future<void> _serve() async {
    try {
      await for (final request in _server) {
        unawaited(_handleRequest(request));
      }
    } catch (_) {
      if (!_closed) {
        rethrow;
      }
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    var shouldClose = true;
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/room/snapshot') {
        await _handleSnapshot(request);
        return;
      }
      if (request.method == 'GET' && path == '/room/events') {
        shouldClose = !await _handleEvents(request);
        return;
      }
      if (request.method == 'POST' && path == '/room/join') {
        await _handleJoin(request);
        return;
      }
      if (request.method == 'PATCH' && path == '/room/general') {
        await _handleGeneral(request);
        return;
      }
      if (request.method == 'PATCH' && path == '/room/presence') {
        await _handlePresence(request);
        return;
      }
      if (request.method == 'POST' && path == '/room/leave') {
        await _handleLeave(request);
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await _writeJson(request.response, {
        'error': 'Unknown Game Session route.',
      });
    } catch (error) {
      request.response.statusCode = error is StateError
          ? HttpStatus.badRequest
          : HttpStatus.internalServerError;
      await _writeJson(request.response, {
        'error': error.toString().replaceFirst('Bad state: ', ''),
      });
    } finally {
      if (shouldClose) {
        await request.response.close().catchError((_) {});
      }
    }
  }

  Future<void> _handleJoin(HttpRequest request) async {
    final body = await _readJson(request);
    final roomCode = _requireString(body, 'roomCode').toUpperCase();
    final playerId = _requireString(body, 'playerId');
    final displayName = _requireString(body, 'displayName');
    final pendingSelection = _pendingSelectionFrom(
      _mapFrom(body['pendingSelection']),
    );
    final hostAddress = body['hostAddress'] as String?;
    final hostPort = _intFrom(body['hostPort']);
    if (!_isValidAdvertisedEndpoint(hostAddress, hostPort)) {
      throw StateError('The advertised backup host endpoint is not valid.');
    }
    _verifyToken(request, roomCode);
    final room = await joinRoom(
      roomCode: roomCode,
      playerId: playerId,
      displayName: displayName,
      pendingSelection: pendingSelection,
      hostAddress: hostAddress,
      hostPort: hostPort,
    );
    await _writeJson(request.response, room.toJson());
  }

  Future<void> _handleGeneral(HttpRequest request) async {
    final body = await _readJson(request);
    final roomCode = _requireString(body, 'roomCode').toUpperCase();
    final playerId = _requireString(body, 'playerId');
    final clearSelection = body['clear'] == true;
    final generalId = clearSelection ? null : _requireString(body, 'generalId');
    final skinId = clearSelection ? null : body['skinId'] as String?;
    _verifyToken(request, roomCode);
    final room = await setMyGeneral(
      roomCode: roomCode,
      playerId: playerId,
      generalId: generalId,
      skinId: skinId,
    );
    await _writeJson(request.response, room.toJson());
  }

  Future<void> _handlePresence(HttpRequest request) async {
    final body = await _readJson(request);
    final roomCode = _requireString(body, 'roomCode').toUpperCase();
    final playerId = _requireString(body, 'playerId');
    final presenceName = _requireString(body, 'presence');
    _verifyToken(request, roomCode);
    final presence = GameSessionPresence.values.firstWhere(
      (value) => value.name == presenceName,
      orElse: () => GameSessionPresence.online,
    );
    final room = await setPresence(
      roomCode: roomCode,
      playerId: playerId,
      presence: presence,
    );
    await _writeJson(request.response, room.toJson());
  }

  Future<void> _handleLeave(HttpRequest request) async {
    final body = await _readJson(request);
    final roomCode = _requireString(body, 'roomCode').toUpperCase();
    final playerId = _requireString(body, 'playerId');
    _verifyToken(request, roomCode);
    final room = await leaveRoom(roomCode: roomCode, playerId: playerId);
    await _writeJson(request.response, {
      'closed': room.status == 'closed',
      'room': room.toJson(),
    });
  }

  Future<void> _handleSnapshot(HttpRequest request) async {
    final roomCode =
        request.uri.queryParameters['roomCode']?.toUpperCase() ?? '';
    _verifyToken(request, roomCode);
    if (!_isActiveHost) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await _writeJson(request.response, {
        'error': 'This Game Session backup host is not active yet.',
      });
      return;
    }
    final room = await fetchRoom(roomCode: roomCode);
    if (room == null) {
      request.response.statusCode = HttpStatus.gone;
      await _writeJson(request.response, {
        'error': 'This Game Session is no longer active.',
      });
      return;
    }
    await _writeJson(request.response, room.toJson());
  }

  Future<bool> _handleEvents(HttpRequest request) async {
    final roomCode =
        request.uri.queryParameters['roomCode']?.toUpperCase() ?? '';
    final state = _state;
    if (state == null ||
        state.room.roomCode != roomCode ||
        state.room.status == 'closed') {
      request.response.statusCode = HttpStatus.gone;
      await _writeJson(request.response, {
        'error': 'This Game Session is no longer active.',
      });
      return false;
    }
    _verifyToken(request, roomCode);
    if (!_isActiveHost) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await _writeJson(request.response, {
        'error': 'This Game Session backup host is not active yet.',
      });
      return false;
    }

    final response = request.response;
    response.statusCode = HttpStatus.ok;
    response.bufferOutput = false;
    response.headers
      ..contentType = ContentType('text', 'event-stream', charset: 'utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set(HttpHeaders.connectionHeader, 'keep-alive');
    response.write(_sseEvent('room', state.room.toJson()));
    await response.flush();

    final subscriber = _Subscriber(response);
    _subscribers.add(subscriber);
    response.done.whenComplete(() {
      _subscribers.remove(subscriber);
      subscriber.markClosed();
    });
    return true;
  }

  Future<void> _broadcastRoom() async {
    final state = _state;
    if (state == null || state.room.status == 'closed') return;
    if (!_roomController.isClosed) {
      _roomController.add(state.room);
    }
    for (final subscriber in [..._subscribers]) {
      if (subscriber.isClosed) {
        _subscribers.remove(subscriber);
        continue;
      }
      await subscriber.send('room', state.room.toJson());
      if (subscriber.isClosed) {
        _subscribers.remove(subscriber);
      }
    }
  }

  Future<void> _broadcastClosed(String roomCode) async {
    if (!_roomController.isClosed) {
      _roomController.add(null);
    }
    for (final subscriber in [..._subscribers]) {
      if (subscriber.isClosed) {
        _subscribers.remove(subscriber);
        continue;
      }
      await subscriber.send('closed', {'roomCode': roomCode});
      if (subscriber.isClosed) {
        _subscribers.remove(subscriber);
      }
    }
  }

  Future<GameSessionRoom> _transferHostOrClose(
    _LocalRoomState state,
    String leavingPlayerId,
  ) async {
    final remainingPlayers = [
      for (final player in state.room.players)
        if (player.playerId != leavingPlayerId) player,
    ];
    final nextHost = _nextTransferHost(remainingPlayers);
    if (nextHost == null) {
      await _closeRoom(state.room.roomCode, keepServerAlive: true);
      return state.room.copyWith(status: 'closed');
    }

    state.room = state.room.copyWith(
      revision: state.room.revision + 1,
      coordinatorPlayerId: nextHost.playerId,
      players: _orderPlayers(remainingPlayers),
      status: 'active',
    );
    await _broadcastRoom();
    final transferredRoom = state.room;
    _state = null;
    _isActiveHost = false;
    return transferredRoom;
  }

  GameSessionPlayer? _nextTransferHost(List<GameSessionPlayer> players) {
    for (final player in _orderPlayers(players)) {
      if (player.presence == GameSessionPresence.offline) continue;
      if (player.hostAddress == null || player.hostPort == null) continue;
      if (!_isValidAdvertisedEndpoint(player.hostAddress, player.hostPort)) {
        continue;
      }
      return player;
    }
    return null;
  }

  Future<void> _closeRoom(
    String roomCode, {
    required bool keepServerAlive,
  }) async {
    final state = _state;
    if (state == null || state.room.roomCode != roomCode) {
      return;
    }
    state.room = state.room.copyWith(
      revision: state.room.revision + 1,
      status: 'closed',
      players: const <GameSessionPlayer>[],
    );
    _isActiveHost = false;
    await _broadcastClosed(roomCode);
    for (final subscriber in [..._subscribers]) {
      await subscriber.close();
    }
    _subscribers.clear();
    if (!keepServerAlive) {
      await _server.close(force: true);
    }
  }

  _LocalRoomState _requireOpenState(String roomCode) {
    final state = _state;
    if (state == null ||
        state.room.roomCode != roomCode ||
        state.room.status == 'closed') {
      throw StateError('This Game Session is no longer active.');
    }
    if (!_isActiveHost) {
      throw StateError('This device is not the active Game Session host.');
    }
    return state;
  }

  void _verifyToken(HttpRequest request, String roomCode) {
    final state = _state;
    if (state == null || state.room.roomCode != roomCode) {
      throw StateError('This Game Session is no longer active.');
    }
    final token = request.headers.value('X-Game-Session-Token');
    if (token == null || token.isEmpty || token != state.accessToken) {
      throw StateError('This Game Session invite token is not valid.');
    }
  }

  GameSessionPlayer _buildPlayer({
    required String playerId,
    required String displayName,
    required DateTime joinedAt,
    required DateTime lastSeenAt,
    required GameSessionPresence presence,
    PendingSessionSelection? pendingSelection,
    GameSessionPlayer? existing,
    String? hostAddress,
    int? hostPort,
  }) {
    return GameSessionPlayer(
      playerId: playerId,
      displayName: displayName.trim().isEmpty ? 'Player' : displayName.trim(),
      joinedAt: existing?.joinedAt ?? joinedAt,
      lastSeenAt: lastSeenAt,
      presence: presence,
      generalId: pendingSelection?.generalId ?? existing?.generalId,
      skinId: pendingSelection?.skinId ?? existing?.skinId,
      hostAddress: hostAddress ?? existing?.hostAddress,
      hostPort: hostPort ?? existing?.hostPort,
    );
  }

  List<GameSessionPlayer> _orderPlayers(List<GameSessionPlayer> players) {
    final ordered = [...players]
      ..sort((a, b) {
        final joinedCompare = a.joinedAt.compareTo(b.joinedAt);
        if (joinedCompare != 0) {
          return joinedCompare;
        }
        return a.playerId.compareTo(b.playerId);
      });
    return ordered;
  }
}

class _LocalRoomState {
  _LocalRoomState({
    required this.room,
    required this.hostPlayerId,
    required this.accessToken,
  });

  GameSessionRoom room;
  final String hostPlayerId;
  final String accessToken;
}

class _Subscriber {
  static const Duration _sseWriteTimeout = Duration(seconds: 2);

  _Subscriber(this.response) {
    _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(sendHeartbeat());
    });
  }

  final HttpResponse response;
  late final Timer _heartbeat;
  bool _closed = false;
  Future<void> _writeQueue = Future<void>.value();

  bool get isClosed => _closed;

  Future<void> send(String event, Object? data) async {
    await _enqueueWrite(_sseEvent(event, data));
  }

  Future<void> sendHeartbeat() async {
    await _enqueueWrite(': keep-alive\n\n');
  }

  Future<void> _enqueueWrite(String value) {
    if (_closed) return Future<void>.value();
    final write = _writeQueue.then((_) async {
      if (_closed) return;
      try {
        response.write(value);
        await response.flush().timeout(_sseWriteTimeout);
      } catch (_) {
        await close();
      }
    });
    _writeQueue = write.catchError((_) {});
    return write;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _heartbeat.cancel();
    try {
      await response.close().timeout(_sseWriteTimeout);
    } catch (_) {
      // The peer may disappear while another SSE write is unwinding.
    }
  }

  void markClosed() {
    if (_closed) return;
    _closed = true;
    _heartbeat.cancel();
  }
}

String _sseEvent(String event, Object? data) {
  return 'event: $event\n'
      'data: ${jsonEncode(data)}\n\n';
}

Future<String> _resolvePreferredHostAddress() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
      includeLoopback: false,
    );
    final candidates = [
      for (final networkInterface in interfaces)
        for (final address in networkInterface.addresses)
          '${networkInterface.name}=${address.address}',
    ];
    debugPrint('Local room host address candidates: ${candidates.join(', ')}');
    final preferredInterfaces = interfaces.toList()
      ..sort(
        (left, right) => _hostInterfacePriority(
          left.name,
        ).compareTo(_hostInterfacePriority(right.name)),
      );
    for (final networkInterface in preferredInterfaces) {
      if (_isVirtualHostInterface(networkInterface.name)) continue;
      for (final address in networkInterface.addresses) {
        if (_isPrivateIpv4(address.address)) {
          return address.address;
        }
      }
    }
    for (final networkInterface in preferredInterfaces) {
      if (_isVirtualHostInterface(networkInterface.name)) continue;
      if (networkInterface.addresses.isNotEmpty) {
        return networkInterface.addresses.first.address;
      }
    }
    debugPrint(
      'No non-virtual local room host address found; falling back to loopback.',
    );
  } catch (_) {
    // Fall back below.
  }
  return InternetAddress.loopbackIPv4.address;
}

bool _isVirtualHostInterface(String interfaceName) =>
    _hostInterfacePriority(interfaceName) >= 20;

int _hostInterfacePriority(String interfaceName) {
  final name = interfaceName.toLowerCase();
  if (name.contains('vethernet') ||
      name.contains('virtual') ||
      name.contains('vpn') ||
      name.contains('wsl') ||
      name.contains('default switch') ||
      name.contains('host-only') ||
      name.contains('vmware') ||
      name.contains('vmnet') ||
      name.contains('virtualbox') ||
      name.contains('vbox') ||
      name.contains('hyper-v') ||
      name.contains('hyperv') ||
      name.contains('docker') ||
      name.startsWith('tun') ||
      name.startsWith('tap')) {
    return 20;
  }
  if (name.contains('wlan') ||
      name.contains('wifi') ||
      name.contains('wi-fi') ||
      name.contains('wireless')) {
    return 0;
  }
  if (name.contains('ethernet') || name.startsWith('eth')) {
    return 10;
  }
  return 15;
}

bool _isPrivateIpv4(String address) {
  if (address.startsWith('10.')) return true;
  if (address.startsWith('192.168.')) return true;
  if (address.startsWith('172.')) {
    final parts = address.split('.');
    if (parts.length >= 2) {
      final second = int.tryParse(parts[1]) ?? -1;
      return second >= 16 && second <= 31;
    }
  }
  return false;
}

bool _isValidAdvertisedEndpoint(String? address, int? port) {
  if (address == null && port == null) return true;
  if (address == null || address.trim().isEmpty || port == null) return false;
  if (port <= 0 || port > 65535) return false;
  final trimmed = address.trim();
  if (trimmed == InternetAddress.loopbackIPv4.address) return false;
  return _isPrivateIpv4(trimmed) || trimmed.startsWith('169.254.');
}

Map<String, dynamic> _mapFrom(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, nested) => MapEntry(key.toString(), nested));
  }
  return <String, dynamic>{};
}

PendingSessionSelection? _pendingSelectionFrom(Map<String, dynamic> json) {
  final generalId = json['generalId'] as String?;
  if (generalId == null || generalId.isEmpty) {
    return null;
  }
  return PendingSessionSelection(
    generalId: generalId,
    skinId: json['skinId'] as String?,
  );
}

String _requireString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  throw StateError('Missing required field: $key');
}

int? _intFrom(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
  const maxBodyBytes = 64 * 1024;
  var totalBytes = 0;
  final bytes = <int>[];
  await for (final chunk in request) {
    totalBytes += chunk.length;
    if (totalBytes > maxBodyBytes) {
      throw StateError('The Game Session request is too large.');
    }
    bytes.addAll(chunk);
  }
  final body = utf8.decode(bytes);
  if (body.trim().isEmpty) {
    return <String, dynamic>{};
  }
  final decoded = jsonDecode(body);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  if (decoded is Map) {
    return decoded.map((key, nested) => MapEntry(key.toString(), nested));
  }
  throw StateError('The Game Session host expected a JSON object.');
}

Future<void> _writeJson(HttpResponse response, Object? payload) async {
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(payload));
  await response.flush();
}

String _requireInviteToken(String invitePayload) {
  try {
    final invite = const LocalRoomGameSessionInviteCodec().decode(
      invitePayload,
    );
    final accessToken = invite.accessToken;
    if (accessToken != null && accessToken.isNotEmpty) {
      return accessToken;
    }
  } catch (_) {
    // The request body already carries the invite payload, so fallback below.
  }
  throw StateError('The invite payload does not include a room access token.');
}
