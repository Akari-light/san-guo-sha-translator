import 'game_session_room.dart';

enum GameSessionConnectionStatus {
  idle,
  connecting,
  hosting,
  connected,
  reconnecting,
  handoff,
  closed,
  failed,
}

class GameSessionConnectionState {
  const GameSessionConnectionState({
    required this.status,
    this.room,
    this.isHost = false,
    this.message,
    this.retryAttempt = 0,
    this.updatedAt,
  });

  final GameSessionConnectionStatus status;
  final GameSessionRoom? room;
  final bool isHost;
  final String? message;
  final int retryAttempt;
  final DateTime? updatedAt;

  static const idle = GameSessionConnectionState(
    status: GameSessionConnectionStatus.idle,
  );

  bool get isRecovering =>
      status == GameSessionConnectionStatus.reconnecting ||
      status == GameSessionConnectionStatus.handoff;

  bool get isActive =>
      status == GameSessionConnectionStatus.hosting ||
      status == GameSessionConnectionStatus.connected ||
      isRecovering;

  bool get allowsRoomMutations =>
      status == GameSessionConnectionStatus.hosting ||
      status == GameSessionConnectionStatus.connected;

  GameSessionConnectionState copyWith({
    GameSessionConnectionStatus? status,
    Object? room = _sentinel,
    bool? isHost,
    Object? message = _sentinel,
    int? retryAttempt,
    Object? updatedAt = _sentinel,
  }) {
    return GameSessionConnectionState(
      status: status ?? this.status,
      room: identical(room, _sentinel) ? this.room : room as GameSessionRoom?,
      isHost: isHost ?? this.isHost,
      message: identical(message, _sentinel)
          ? this.message
          : message as String?,
      retryAttempt: retryAttempt ?? this.retryAttempt,
      updatedAt: identical(updatedAt, _sentinel)
          ? this.updatedAt
          : updatedAt as DateTime?,
    );
  }
}

const Object _sentinel = Object();
