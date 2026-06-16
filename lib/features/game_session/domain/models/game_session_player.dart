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
    this.hostAddress,
    this.hostPort,
  });

  final String playerId;
  final String displayName;
  final DateTime joinedAt;
  final DateTime lastSeenAt;
  final GameSessionPresence presence;
  final String? generalId;
  final String? skinId;
  final String? hostAddress;
  final int? hostPort;

  GameSessionPlayer copyWith({
    String? playerId,
    String? displayName,
    DateTime? joinedAt,
    DateTime? lastSeenAt,
    GameSessionPresence? presence,
    Object? generalId = _sentinel,
    Object? skinId = _sentinel,
    Object? hostAddress = _sentinel,
    Object? hostPort = _sentinel,
  }) {
    return GameSessionPlayer(
      playerId: playerId ?? this.playerId,
      displayName: displayName ?? this.displayName,
      joinedAt: joinedAt ?? this.joinedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      presence: presence ?? this.presence,
      generalId: identical(generalId, _sentinel)
          ? this.generalId
          : generalId as String?,
      skinId: identical(skinId, _sentinel) ? this.skinId : skinId as String?,
      hostAddress: identical(hostAddress, _sentinel)
          ? this.hostAddress
          : hostAddress as String?,
      hostPort: identical(hostPort, _sentinel)
          ? this.hostPort
          : hostPort as int?,
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
    if (hostAddress != null) 'hostAddress': hostAddress,
    if (hostPort != null) 'hostPort': hostPort,
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
      hostAddress: json['hostAddress'] as String?,
      hostPort: _intFrom(json['hostPort']),
    );
  }
}

DateTime? _parseDateTime(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      value.toInt(),
      isUtc: true,
    ).toLocal();
  }
  return null;
}

int? _intFrom(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

const Object _sentinel = Object();
