import '../models/game_session_invite.dart';
import '../models/game_session_room.dart';
import '../models/pending_session_selection.dart';

abstract class GameSessionRepository {
  Stream<GameSessionRoom?> watchRoom();

  GameSessionRoom? get currentRoom;
  bool get hasActiveSession;
  String? get activeRoomCode;
  String? get activeInvitePayload;

  Future<GameSessionRoom> createRoom({
    required String displayName,
    PendingSessionSelection? pendingSelection,
  });

  Future<GameSessionRoom> joinFromInvite({
    required String invitePayload,
    required String displayName,
    PendingSessionSelection? pendingSelection,
  });

  Future<GameSessionRoom> joinFromRoomCode({
    required String roomCode,
    required String displayName,
    PendingSessionSelection? pendingSelection,
  });

  Future<void> cacheInvitePayload(String invitePayload);
  Future<void> setMyGeneral({required String generalId, String? skinId});
  Future<void> leaveRoom();
  Future<void> suspend();
  Future<void> resume();
  GameSessionInvite decodeInvite(String invitePayload);
}
