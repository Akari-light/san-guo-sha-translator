import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../controllers/game_session_controller.dart';

class GameSessionQrScannerScreen extends StatefulWidget {
  const GameSessionQrScannerScreen({super.key, required this.controller});

  final GameSessionController controller;

  @override
  State<GameSessionQrScannerScreen> createState() =>
      _GameSessionQrScannerScreenState();
}

class _GameSessionQrScannerScreenState
    extends State<GameSessionQrScannerScreen> {
  bool _handledBarcode = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan room QR'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.controller.showLauncher,
        ),
      ),
      body: MobileScanner(
        onDetect: (capture) async {
          if (_handledBarcode) return;
          if (capture.barcodes.isEmpty) return;
          final raw = capture.barcodes.first.rawValue;
          if (raw == null || raw.trim().isEmpty) return;
          _handledBarcode = true;
          await widget.controller.importInvite(raw.trim());
          widget.controller.showLauncher();
        },
      ),
    );
  }
}
