import 'package:flutter/material.dart';

import '../../data/repositories/local_room_game_session_repository.dart';
import '../../domain/models/pending_session_selection.dart';
import '../controllers/game_session_controller.dart';
import 'game_session_launcher_screen.dart';
import 'game_session_qr_scanner_screen.dart';
import 'game_session_room_screen.dart';

class GameSessionShellScreen extends StatefulWidget {
  const GameSessionShellScreen({
    super.key,
    this.pendingSelection,
  });

  final PendingSessionSelection? pendingSelection;

  @override
  State<GameSessionShellScreen> createState() => _GameSessionShellScreenState();
}

class _GameSessionShellScreenState extends State<GameSessionShellScreen>
    with WidgetsBindingObserver {
  late final GameSessionController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = GameSessionController(
      repository: LocalRoomGameSessionRepository.instance,
      pendingSelection: widget.pendingSelection,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _controller.suspend();
    } else if (state == AppLifecycleState.resumed) {
      _controller.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.page == GameSessionPage.room && _controller.room != null) {
          return GameSessionRoomScreen(controller: _controller);
        }
        if (_controller.page == GameSessionPage.scanner) {
          return GameSessionQrScannerScreen(controller: _controller);
        }
        return GameSessionLauncherScreen(controller: _controller);
      },
    );
  }
}
