import '../models/game_session_connection_state.dart';
import '../models/game_session_room.dart';
import '../models/pending_session_selection.dart';

abstract class GameSessionRepository {
  Stream<GameSessionRoom?> watchRoom();
  Stream<GameSessionConnectionState> watchConnection();

  GameSessionRoom? get currentRoom;
  GameSessionConnectionState get currentConnection;
  bool get hasActiveSession;

  Future<GameSessionRoom> createRoom({
    required String displayName,
    PendingSessionSelection? pendingSelection,
  });

  Future<GameSessionRoom> joinFromInvite({
    required String invitePayload,
    required String displayName,
    PendingSessionSelection? pendingSelection,
  });

  Future<void> setMyGeneral({required String generalId, String? skinId});
  Future<void> clearMyGeneral();
  Future<void> leaveRoom();
  Future<void> suspend();
  Future<void> resume();
}
