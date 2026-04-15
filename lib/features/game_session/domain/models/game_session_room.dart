import 'game_session_player.dart';

class GameSessionRoom {
  const GameSessionRoom({
    required this.roomId,
    required this.roomCode,
    required this.coordinatorPlayerId,
    required this.revision,
    required this.status,
    required this.players,
    required this.invitePayload,
  });

  final String roomId;
  final String roomCode;
  final String coordinatorPlayerId;
  final int revision;
  final String status;
  final List<GameSessionPlayer> players;
  final String invitePayload;

  GameSessionRoom copyWith({
    String? roomId,
    String? roomCode,
    String? coordinatorPlayerId,
    int? revision,
    String? status,
    List<GameSessionPlayer>? players,
    String? invitePayload,
  }) {
    return GameSessionRoom(
      roomId: roomId ?? this.roomId,
      roomCode: roomCode ?? this.roomCode,
      coordinatorPlayerId: coordinatorPlayerId ?? this.coordinatorPlayerId,
      revision: revision ?? this.revision,
      status: status ?? this.status,
      players: players ?? this.players,
      invitePayload: invitePayload ?? this.invitePayload,
    );
  }

  GameSessionPlayer? get coordinator {
    for (final player in players) {
      if (player.playerId == coordinatorPlayerId) return player;
    }
    return null;
  }

  GameSessionPlayer? playerById(String playerId) {
    for (final player in players) {
      if (player.playerId == playerId) return player;
    }
    return null;
  }

  List<GameSessionPlayer> get orderedPlayers {
    final ordered = [...players]
      ..sort((a, b) {
        final joinedCompare = a.joinedAt.compareTo(b.joinedAt);
        if (joinedCompare != 0) return joinedCompare;
        return a.playerId.compareTo(b.playerId);
      });
    return ordered;
  }

  Map<String, dynamic> toJson() => {
        'roomId': roomId,
        'roomCode': roomCode,
        'coordinatorPlayerId': coordinatorPlayerId,
        'revision': revision,
        'status': status,
        'invitePayload': invitePayload,
        'players': players.map((player) => player.toJson()).toList(growable: false),
      };

  factory GameSessionRoom.fromJson(Map<String, dynamic> json) {
    final playersJson = json['players'];
    final players = <GameSessionPlayer>[];
    if (playersJson is List) {
      for (final entry in playersJson) {
        players.add(GameSessionPlayer.fromJson(_mapFrom(entry)));
      }
    } else if (playersJson is Map) {
      for (final entry in playersJson.entries) {
        players.add(GameSessionPlayer.fromJson(_mapFrom(entry.value)));
      }
    }

    return GameSessionRoom(
      roomId: (json['roomId'] as String?) ?? (json['roomCode'] as String? ?? ''),
      roomCode: (json['roomCode'] as String? ?? '').toUpperCase(),
      coordinatorPlayerId: (json['coordinatorPlayerId'] as String?) ?? '',
      revision: _intFrom(json['revision']) ?? 0,
      status: (json['status'] as String?) ?? 'active',
      players: players,
      invitePayload: (json['invitePayload'] as String?) ?? '',
    );
  }
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

int? _intFrom(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
