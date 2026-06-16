import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/contracts/game_session_repository.dart';
import '../../domain/models/game_session_connection_state.dart';
import '../../domain/models/game_session_room.dart';
import '../../domain/models/pending_session_selection.dart';

enum GameSessionPage { launcher, room, scanner }

class GameSessionController extends ChangeNotifier {
  GameSessionController({
    required GameSessionRepository repository,
    this.pendingSelection,
  }) : _repository = repository {
    _subscription = _repository.watchConnection().listen((connection) {
      _connection = connection;
      _room = connection.room;
      _page = connection.room == null
          ? GameSessionPage.launcher
          : GameSessionPage.room;
      _notifyIfAlive();
    });
    _connection = _repository.currentConnection;
    _room = _connection.room;
    _page = _room == null ? GameSessionPage.launcher : GameSessionPage.room;
  }

  final GameSessionRepository _repository;
  final PendingSessionSelection? pendingSelection;
  late final StreamSubscription<GameSessionConnectionState> _subscription;

  GameSessionPage _page = GameSessionPage.launcher;
  GameSessionConnectionState _connection = GameSessionConnectionState.idle;
  GameSessionRoom? _room;
  bool _busy = false;
  bool _disposed = false;
  String? _error;
  String? _importedInvitePayload;

  GameSessionPage get page => _page;
  GameSessionConnectionState get connection => _connection;
  GameSessionRoom? get room => _room;
  bool get busy => _busy;
  String? get error => _error;
  String? get activeInvitePayload => _repository.activeInvitePayload;
  String? get importedInvitePayload => _importedInvitePayload;

  void showLauncher() {
    _page = GameSessionPage.launcher;
    _notifyIfAlive();
  }

  void showRoom() {
    if (_room == null) return;
    _page = GameSessionPage.room;
    _notifyIfAlive();
  }

  void showScanner() {
    _page = GameSessionPage.scanner;
    _notifyIfAlive();
  }

  Future<void> createRoom(String displayName) async {
    await _run(
      () => _repository.createRoom(
        displayName: displayName,
        pendingSelection: pendingSelection,
      ),
    );
  }

  Future<void> joinByInvite(String invitePayload, String displayName) async {
    await _run(() async {
      await _repository.cacheInvitePayload(invitePayload);
      await _repository.joinFromInvite(
        invitePayload: invitePayload,
        displayName: displayName,
        pendingSelection: pendingSelection,
      );
      _importedInvitePayload = invitePayload.trim();
    });
  }

  Future<void> joinByRoomCode(String roomCode, String displayName) async {
    await _run(
      () => _repository.joinFromRoomCode(
        roomCode: roomCode,
        displayName: displayName,
        pendingSelection: pendingSelection,
      ),
    );
  }

  Future<void> importInvite(String invitePayload) async {
    await _run(() async {
      final trimmed = invitePayload.trim();
      await _repository.cacheInvitePayload(trimmed);
      _importedInvitePayload = trimmed;
    });
  }

  Future<void> setMyGeneral(String generalId, {String? skinId}) async {
    await _run(
      () => _repository.setMyGeneral(generalId: generalId, skinId: skinId),
    );
  }

  Future<void> leaveRoom() async {
    await _run(_repository.leaveRoom);
  }

  Future<void> suspend() => _repository.suspend();

  Future<void> resume() async {
    await _repository.resume();
    if (_room != null && _page != GameSessionPage.scanner) {
      _page = GameSessionPage.room;
      _notifyIfAlive();
    }
  }

  void clearError() {
    _error = null;
    _notifyIfAlive();
  }

  Future<void> _run(Future<dynamic> Function() action) async {
    _busy = true;
    _error = null;
    _notifyIfAlive();
    try {
      await action();
    } catch (error) {
      _error = error.toString().replaceFirst('Bad state: ', '');
    } finally {
      _busy = false;
      _notifyIfAlive();
    }
  }

  void _notifyIfAlive() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription.cancel();
    super.dispose();
  }
}
