class GameSessionInvite {
  const GameSessionInvite({
    required this.roomId,
    required this.roomCode,
    required this.createdAt,
    this.hostAddress,
    this.hostPort,
    this.accessToken,
    this.issuedByPlayerId,
    this.kind = 'sgs_sha.game_session.local_room',
    this.version = 2,
  });

  final String roomId;
  final String roomCode;
  final DateTime createdAt;
  final String? hostAddress;
  final int? hostPort;
  final String? accessToken;
  final String? issuedByPlayerId;
  final String kind;
  final int version;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'version': version,
        'roomId': roomId,
        'roomCode': roomCode,
        'createdAt': createdAt.toIso8601String(),
        if (hostAddress != null) 'hostAddress': hostAddress,
        if (hostPort != null) 'hostPort': hostPort,
        if (accessToken != null) 'accessToken': accessToken,
        if (issuedByPlayerId != null) 'issuedByPlayerId': issuedByPlayerId,
      };

  factory GameSessionInvite.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['createdAt'];
    return GameSessionInvite(
      roomId: (json['roomId'] as String?) ?? (json['roomCode'] as String? ?? ''),
      roomCode: (json['roomCode'] as String? ?? '').toUpperCase(),
      createdAt: createdAtRaw is String
          ? DateTime.tryParse(createdAtRaw) ?? DateTime.now()
          : DateTime.now(),
      hostAddress: json['hostAddress'] as String?,
      hostPort: _intFrom(json['hostPort']),
      accessToken: json['accessToken'] as String?,
      issuedByPlayerId: (json['issuedByPlayerId'] ?? json['seedPlayerId']) as String?,
      kind: (json['kind'] as String?) ?? 'sgs_sha.game_session.local_room',
      version: (json['version'] as num?)?.toInt() ?? 2,
    );
  }
}

int? _intFrom(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
