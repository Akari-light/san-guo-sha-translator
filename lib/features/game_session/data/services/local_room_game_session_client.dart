import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/models/game_session_invite.dart';
import '../../domain/models/game_session_player.dart';
import '../../domain/models/game_session_room.dart';
import '../../domain/models/pending_session_selection.dart';
import 'local_room_game_session_invite_codec.dart';

class LocalRoomGameSessionClient {
  static const LocalRoomGameSessionInviteCodec _inviteCodec =
      LocalRoomGameSessionInviteCodec();

  LocalRoomGameSessionClient({
    required GameSessionInvite invite,
    required String playerId,
  }) : _invite = invite,
       _playerId = playerId,
       _httpClient = HttpClient()..idleTimeout = const Duration(seconds: 20);

  static const Duration _requestTimeout = Duration(seconds: 5);

  final GameSessionInvite _invite;
  final String _playerId;
  final HttpClient _httpClient;

  Uri get _baseUri {
    final hostAddress = _invite.hostAddress;
    final hostPort = _invite.hostPort;
    if (hostAddress == null ||
        hostAddress.trim().isEmpty ||
        hostPort == null ||
        hostPort <= 0) {
      throw StateError(
        'This invite does not include a reachable host address.',
      );
    }
    return Uri(scheme: 'http', host: hostAddress, port: hostPort);
  }

  Future<GameSessionRoom> joinRoom({
    required String displayName,
    PendingSessionSelection? pendingSelection,
    String? localHostAddress,
    int? localHostPort,
  }) async {
    final body = <String, dynamic>{
      'roomCode': _invite.roomCode,
      'playerId': _playerId,
      'displayName': displayName,
      if (pendingSelection != null)
        'pendingSelection': {
          'generalId': pendingSelection.generalId,
          if (pendingSelection.skinId != null)
            'skinId': pendingSelection.skinId,
        },
    };
    if (localHostAddress != null) {
      body['hostAddress'] = localHostAddress;
    }
    if (localHostPort != null) {
      body['hostPort'] = localHostPort;
    }
    return _sendRoomRequest('POST', '/room/join', body);
  }

  Future<GameSessionRoom> setMyGeneral({
    required String generalId,
    String? skinId,
  }) async {
    final body = <String, dynamic>{
      'roomCode': _invite.roomCode,
      'playerId': _playerId,
      'generalId': generalId,
    };
    if (skinId case final value?) {
      body['skinId'] = value;
    }

    return _sendRoomRequest('PATCH', '/room/general', body);
  }

  Future<GameSessionRoom> setPresence(GameSessionPresence presence) async {
    return _sendRoomRequest('PATCH', '/room/presence', {
      'roomCode': _invite.roomCode,
      'playerId': _playerId,
      'presence': presence.name,
    });
  }

  Future<void> leaveRoom() async {
    await _sendRoomRequest('POST', '/room/leave', {
      'roomCode': _invite.roomCode,
      'playerId': _playerId,
    }, expectRoom: false);
  }

  Future<GameSessionRoom?> fetchRoom() async {
    final response = await _sendHttpRequest(
      'GET',
      '/room/snapshot',
      queryParameters: {'roomCode': _invite.roomCode},
    );
    if (response.statusCode == HttpStatus.gone ||
        response.statusCode == HttpStatus.notFound) {
      return null;
    }
    if (response.statusCode >= 400) {
      throw StateError(await _readErrorMessage(response));
    }
    final json = await _readJsonResponse(response);
    return GameSessionRoom.fromJson(json);
  }

  Stream<GameSessionRoom?> watchRoom() async* {
    HttpClientRequest? request;
    HttpClientResponse? response;
    try {
      request = await _httpClient
          .getUrl(
            _baseUri.replace(
              path: '/room/events',
              queryParameters: <String, String>{'roomCode': _invite.roomCode},
            ),
          )
          .timeout(_requestTimeout);
      request.headers.set('X-Game-Session-Token', _invite.accessToken ?? '');
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      response = await request.close().timeout(_requestTimeout);
      if (response.statusCode == HttpStatus.gone ||
          response.statusCode == HttpStatus.notFound) {
        yield null;
        return;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw StateError(await _readErrorMessage(response));
      }

      var eventName = 'room';
      final dataLines = <String>[];
      await for (final line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.startsWith(':')) continue;
        if (line.isEmpty) {
          if (dataLines.isNotEmpty) {
            yield _decodeEvent(eventName, dataLines.join('\n'));
            dataLines.clear();
          }
          eventName = 'room';
          continue;
        }
        if (line.startsWith('event:')) {
          eventName = line.substring(6).trim();
          continue;
        }
        if (line.startsWith('data:')) {
          dataLines.add(line.substring(5).trimLeft());
        }
      }
      if (dataLines.isNotEmpty) {
        yield _decodeEvent(eventName, dataLines.join('\n'));
      }
    } finally {
      try {
        request?.abort();
      } catch (_) {
        // The stream is already ending.
      }
    }
  }

  Future<void> close() async {
    _httpClient.close(force: true);
  }

  Future<GameSessionRoom> _sendRoomRequest(
    String method,
    String path,
    Map<String, dynamic> body, {
    bool expectRoom = true,
  }) async {
    final response = await _sendHttpRequest(method, path, body: body);
    if (response.statusCode >= 400) {
      throw StateError(await _readErrorMessage(response));
    }
    if (!expectRoom) {
      await response.drain();
      return GameSessionRoom(
        roomId: _invite.roomId,
        roomCode: _invite.roomCode,
        coordinatorPlayerId: _playerId,
        revision: 0,
        status: 'closed',
        players: const <GameSessionPlayer>[],
        invitePayload: _inviteCodec.encode(_invite),
      );
    }
    final json = await _readJsonResponse(response);
    return GameSessionRoom.fromJson(json);
  }

  Future<HttpClientResponse> _sendHttpRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
  }) async {
    final uri = _baseUri.replace(path: path, queryParameters: queryParameters);
    final request = await _httpClient
        .openUrl(method, uri)
        .timeout(_requestTimeout);
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      ContentType.json.mimeType,
    );
    request.headers.set('X-Game-Session-Token', _invite.accessToken ?? '');
    if (body != null) {
      request.add(utf8.encode(jsonEncode(body)));
    }
    return request.close().timeout(_requestTimeout);
  }

  Future<Map<String, dynamic>> _readJsonResponse(
    HttpClientResponse response,
  ) async {
    final body = await _readResponseBody(response);
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    throw StateError('The Game Session host returned an unexpected payload.');
  }

  Future<String> _readErrorMessage(HttpClientResponse response) async {
    final body = await _readResponseBody(response);
    if (body.trim().isEmpty) {
      return 'The Game Session host rejected the request.';
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {
      // Fall through to the raw body below.
    }
    return body.trim();
  }

  Future<String> _readResponseBody(HttpClientResponse response) async {
    const maxBodyBytes = 64 * 1024;
    var totalBytes = 0;
    final bytes = <int>[];
    await for (final chunk in response) {
      totalBytes += chunk.length;
      if (totalBytes > maxBodyBytes) {
        throw StateError('The Game Session host returned too much data.');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  GameSessionRoom? _decodeEvent(String eventName, String data) {
    if (eventName == 'closed') {
      return null;
    }
    final decoded = jsonDecode(data);
    if (decoded is Map<String, dynamic>) {
      return GameSessionRoom.fromJson(decoded);
    }
    if (decoded is Map) {
      return GameSessionRoom.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return null;
  }
}
