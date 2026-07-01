import 'dart:convert';

import '../../domain/models/game_session_invite.dart';

class LocalRoomGameSessionInviteCodec {
  const LocalRoomGameSessionInviteCodec();

  String encode(GameSessionInvite invite) {
    final payload = jsonEncode(invite.toJson());
    return base64Url.encode(utf8.encode(payload));
  }

  GameSessionInvite decode(String payload) {
    final trimmed = payload.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Invite payload is empty.');
    }

    final json = utf8.decode(base64Url.decode(base64Url.normalize(trimmed)));
    final map = jsonDecode(json) as Map<String, dynamic>;
    return GameSessionInvite.fromJson(map);
  }
}
