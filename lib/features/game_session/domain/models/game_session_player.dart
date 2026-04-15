enum GameSessionPresence { online, away, offline }

class GameSessionPlayer {
  const GameSessionPlayer({
    required this.playerId,
    required this.displayName,
    required this.joinedAt,
    required this.lastSeenAt,
    required this.presence,
    this.generalId,
    this.skinId,
  });

  final String playerId;
  final String displayName;
  final DateTime joinedAt;
  final DateTime lastSeenAt;
  final GameSessionPresence presence;
  final String? generalId;
  final String? skinId;

  GameSessionPlayer copyWith({
    String? playerId,
    String? displayName,
    DateTime? joinedAt,
    DateTime? lastSeenAt,
    GameSessionPresence? presence,
    Object? generalId = _sentinel,
    Object? skinId = _sentinel,
  }) {
    return GameSessionPlayer(
      playerId: playerId ?? this.playerId,
      displayName: displayName ?? this.displayName,
      joinedAt: joinedAt ?? this.joinedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      presence: presence ?? this.presence,
      generalId: identical(generalId, _sentinel) ? this.generalId : generalId as String?,
      skinId: identical(skinId, _sentinel) ? this.skinId : skinId as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'displayName': displayName,
        'joinedAt': joinedAt.toIso8601String(),
        'lastSeenAt': lastSeenAt.toIso8601String(),
        'presence': presence.name,
        'generalId': generalId,
        'skinId': skinId,
      };

  factory GameSessionPlayer.fromJson(Map<String, dynamic> json) {
    final joinedAt = _parseDateTime(json['joinedAt']) ?? DateTime.now();
    return GameSessionPlayer(
      playerId: (json['playerId'] ?? json['uid']) as String,
      displayName: ((json['displayName'] as String?) ?? 'Player').trim(),
      joinedAt: joinedAt,
      lastSeenAt: _parseDateTime(json['lastSeenAt']) ?? joinedAt,
      presence: GameSessionPresence.values.firstWhere(
        (value) => value.name == json['presence'],
        orElse: () => GameSessionPresence.online,
      ),
      generalId: json['generalId'] as String?,
      skinId: json['skinId'] as String?,
    );
  }
}

DateTime? _parseDateTime(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true).toLocal();
  }
  return null;
}

const Object _sentinel = Object();
