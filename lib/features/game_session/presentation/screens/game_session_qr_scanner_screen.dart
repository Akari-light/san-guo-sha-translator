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
  String? _error;

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
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            onDetect: (capture) async {
              if (_handledBarcode) return;
              if (capture.barcodes.isEmpty) return;
              final raw = capture.barcodes.first.rawValue;
              if (raw == null || raw.trim().isEmpty) return;
              setState(() {
                _handledBarcode = true;
                _error = null;
              });
              await widget.controller.joinByInvite(
                raw.trim(),
                widget.controller.scannerDisplayName,
              );
              if (!mounted || widget.controller.room != null) return;
              setState(() {
                _handledBarcode = false;
                _error =
                    widget.controller.error ??
                    'Could not join room. Check the invite and try again.';
              });
            },
          ),
          if (_error != null)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: const EdgeInsets.all(18),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
