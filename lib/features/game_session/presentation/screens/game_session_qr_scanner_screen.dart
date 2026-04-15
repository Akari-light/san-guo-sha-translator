import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../controllers/game_session_controller.dart';

class GameSessionQrScannerScreen extends StatelessWidget {
  const GameSessionQrScannerScreen({
    super.key,
    required this.controller,
  });

  final GameSessionController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan room QR'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: controller.showLauncher,
        ),
      ),
      body: MobileScanner(
        onDetect: (capture) async {
          if (capture.barcodes.isEmpty) return;
          final raw = capture.barcodes.first.rawValue;
          if (raw == null || raw.trim().isEmpty) return;
          await controller.importInvite(raw.trim());
          controller.showLauncher();
        },
      ),
    );
  }
}
