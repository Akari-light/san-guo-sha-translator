import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/models/game_session_player.dart';
import '../../domain/models/game_session_room.dart';
import '../../domain/models/pending_session_selection.dart';

class LocalRoomGameSessionHostServer {
  LocalRoomGameSessionHostServer._(
    this._server, {
    required this.hostAddress,
  });

  static Future<LocalRoomGameSessionHostServer> bind() async {
    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      0,
      shared: true,
    );
    final hostAddress = await _resolvePreferredHostAddress();
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
  final List<_Subscriber> _subscribers = <_Subscriber>[];

  int get port => _server.port;

  GameSessionRoom? get currentRoom => _state?.room;

  Future<void> close() async {
    final state = _state;
    _state = null;
    if (state != null) {
      await _broadcastClosed(state.room.roomCode);
    }
    for (final subscriber in [..._subscribers]) {
      await subscriber.close();
    }
    _subscribers.clear();
    await _server.close(force: true);
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
    await _broadcastRoom();
    return _state!.room;
  }

  Future<GameSessionRoom> joinRoom({
    required String roomCode,
    required String playerId,
    required String displayName,
    PendingSessionSelection? pendingSelection,
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
    required String generalId,
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
      skinId: skinId,
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
      await _closeRoom(state.room.roomCode, keepServerAlive: true);
      return state.room.copyWith(status: 'closed');
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

  Future<GameSessionRoom?> fetchRoom({
    required String roomCode,
  }) async {
    final state = _state;
    if (state == null || state.room.roomCode != roomCode || state.room.status == 'closed') {
      return null;
    }
    return state.room;
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      unawaited(_handleRequest(request));
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
        shouldClose = false;
        await _handleEvents(request);
        return;
      }
      if (request.method == 'POST' && path == '/room/create') {
        await _handleCreate(request);
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
      await _writeJson(request.response, {'error': 'Unknown Game Session route.'});
    } catch (error) {
      request.response.statusCode = error is StateError ? HttpStatus.badRequest : HttpStatus.internalServerError;
      await _writeJson(
        request.response,
        {
          'error': error.toString().replaceFirst('Bad state: ', ''),
        },
      );
    } finally {
      if (shouldClose) {
        await request.response.close().catchError((_) {});
      }
    }
  }

  Future<void> _handleCreate(HttpRequest request) async {
    final body = await _readJson(request);
    final roomId = _requireString(body, 'roomId');
    final roomCode = _requireString(body, 'roomCode').toUpperCase();
    final invitePayload = _requireString(body, 'invitePayload');
    final playerId = _requireString(body, 'playerId');
    final displayName = _requireString(body, 'displayName');
    final pendingSelection = _pendingSelectionFrom(_mapFrom(body['pendingSelection']));
    final room = await createRoom(
      roomId: roomId,
      roomCode: roomCode,
      invitePayload: invitePayload,
      playerId: playerId,
      displayName: displayName,
      pendingSelection: pendingSelection,
    );
    await _writeJson(request.response, room.toJson());
  }

  Future<void> _handleJoin(HttpRequest request) async {
    final body = await _readJson(request);
    final roomCode = _requireString(body, 'roomCode').toUpperCase();
    final playerId = _requireString(body, 'playerId');
    final displayName = _requireString(body, 'displayName');
    final pendingSelection = _pendingSelectionFrom(_mapFrom(body['pendingSelection']));
    _verifyToken(request, roomCode);
    final room = await joinRoom(
      roomCode: roomCode,
      playerId: playerId,
      displayName: displayName,
      pendingSelection: pendingSelection,
    );
    await _writeJson(request.response, room.toJson());
  }

  Future<void> _handleGeneral(HttpRequest request) async {
    final body = await _readJson(request);
    final roomCode = _requireString(body, 'roomCode').toUpperCase();
    final playerId = _requireString(body, 'playerId');
    final generalId = _requireString(body, 'generalId');
    final skinId = body['skinId'] as String?;
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
    final room = await leaveRoom(
      roomCode: roomCode,
      playerId: playerId,
    );
    await _writeJson(
      request.response,
      {
        'closed': room.status == 'closed',
        'room': room.toJson(),
      },
    );
  }

  Future<void> _handleSnapshot(HttpRequest request) async {
    final roomCode = request.uri.queryParameters['roomCode']?.toUpperCase() ?? '';
    _verifyToken(request, roomCode);
    final room = await fetchRoom(roomCode: roomCode);
    if (room == null) {
      request.response.statusCode = HttpStatus.gone;
      await _writeJson(request.response, {'error': 'This Game Session is no longer active.'});
      return;
    }
    await _writeJson(request.response, room.toJson());
  }

  Future<void> _handleEvents(HttpRequest request) async {
    final roomCode = request.uri.queryParameters['roomCode']?.toUpperCase() ?? '';
    final state = _state;
    if (state == null || state.room.roomCode != roomCode || state.room.status == 'closed') {
      request.response.statusCode = HttpStatus.gone;
      await _writeJson(request.response, {'error': 'This Game Session is no longer active.'});
      return;
    }
    _verifyToken(request, roomCode);

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
    });
  }

  Future<void> _broadcastRoom() async {
    final state = _state;
    if (state == null || state.room.status == 'closed') return;
    for (final subscriber in [..._subscribers]) {
      await subscriber.send('room', state.room.toJson());
    }
  }

  Future<void> _broadcastClosed(String roomCode) async {
    for (final subscriber in [..._subscribers]) {
      await subscriber.send('closed', {'roomCode': roomCode});
    }
  }

  Future<void> _closeRoom(String roomCode, {required bool keepServerAlive}) async {
    final state = _state;
    if (state == null || state.room.roomCode != roomCode) {
      return;
    }
    state.room = state.room.copyWith(
      revision: state.room.revision + 1,
      status: 'closed',
      players: const <GameSessionPlayer>[],
    );
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
    if (state == null || state.room.roomCode != roomCode || state.room.status == 'closed') {
      throw StateError('This Game Session is no longer active.');
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
  }) {
    return GameSessionPlayer(
      playerId: playerId,
      displayName: displayName.trim().isEmpty ? 'Player' : displayName.trim(),
      joinedAt: existing?.joinedAt ?? joinedAt,
      lastSeenAt: lastSeenAt,
      presence: presence,
      generalId: pendingSelection?.generalId ?? existing?.generalId,
      skinId: pendingSelection?.skinId ?? existing?.skinId,
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
  _Subscriber(this.response);

  final HttpResponse response;

  Future<void> send(String event, Object? data) async {
    try {
      response.write(_sseEvent(event, data));
      await response.flush();
    } catch (_) {
      await close();
    }
  }

  Future<void> close() async {
    await response.close().catchError((_) {});
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
    for (final networkInterface in interfaces) {
      for (final address in networkInterface.addresses) {
        if (_isPrivateIpv4(address.address)) {
          return address.address;
        }
      }
    }
    for (final networkInterface in interfaces) {
      if (networkInterface.addresses.isNotEmpty) {
        return networkInterface.addresses.first.address;
      }
    }
  } catch (_) {
    // Fall back below.
  }
  return InternetAddress.loopbackIPv4.address;
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

Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
  final body = await utf8.decodeStream(request);
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
    final decoded = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(invitePayload.trim()))));
    if (decoded is Map && decoded['accessToken'] is String) {
      return decoded['accessToken'] as String;
    }
  } catch (_) {
    // The request body already carries the invite payload, so fallback below.
  }
  throw StateError('The invite payload does not include a room access token.');
}
