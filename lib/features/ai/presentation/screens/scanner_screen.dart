// lib/features/ai/presentation/screens/scanner_screen.dart
//
// Discover tab — Google Lens-inspired layout.
//
// Layout:
//   Landing (Camera mode):
//     - Full-screen camera viewfinder
//     - Shutter button (centre bottom)
//     - Mode pill navbar: [Scan Card] [Search]
//     - Flash toggle (top right)
//     - LIVE / PAUSED badge (top left)
//
//   After scan:
//     - Camera freezes with scanned frame still visible
//     - OCR highlight overlay: amber boxes drawn around detected text regions
//     - DraggableScrollableSheet slides up from bottom showing ranked candidates
//       → Peek state shows top candidate card prominently (like Google Lens "Select text")
//       → Expanded state shows full ranked list
//     - Tap any candidate → onCardTap → main.dart pushes detail screen
//     - Tap outside or swipe down → dismiss results, camera resumes live
//
//   Search mode (semantic search placeholder):
//     - Full-screen search bar with hint text
//     - Results list (placeholder — Feature 2)
//
// Architecture:
//   - No feature/* presentation imports — navigation via onCardTap callback only
//   - ScannerService, TextNormaliser, ImageHashMatcher live in core/services
//   - MatchCandidate / RecordType imported from core/services
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../../core/services/recently_viewed_service.dart';
import '../../../../core/services/scanner_service.dart';
import 'scanner_results_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ScannerScreen
// ─────────────────────────────────────────────────────────────────────────────

/// Three-position flash control.
/// - off:  flash never fires
/// - auto: camera decides based on scene brightness (FlashMode.auto)
/// - on:   flash fires on every capture (FlashMode.always)
///         NOT torch — torch keeps the light on continuously and
///         triggers on every app event; "always" only fires during
///         the actual still capture, so no random flash.
enum _FlashMode { off, auto, on }

class ScannerScreen extends StatefulWidget {
  final void Function(String id, RecordType type) onCardTap;
  const ScannerScreen({super.key, required this.onCardTap});

  @override
  State<ScannerScreen> createState() => ScannerScreenState();
}

enum _DiscoverMode { scan, search }

// Tracks what the scanner is doing — drives the processing feedback UI.
enum _ScanStatus {
  idle,          // camera live, nothing happening
  capturing,     // shutter pressed, taking picture
  readingText,   // MLKit OCR running
  matchingCard,  // ScannerService comparing candidates
  done,          // results ready
}

// Public — main.dart accesses resetSession() via GlobalKey<ScannerScreenState>.
class ScannerScreenState extends State<ScannerScreen> with WidgetsBindingObserver {
  // ── Camera
  CameraController? _controller;
  String? _cameraError;
  bool _initialising = true;
  bool _scanning = false;
  _FlashMode _flashMode = _FlashMode.off;

  // ── Focus indicator — tap-to-focus
  Offset? _focusPoint;
  bool    _focusAcquired = false;

  // ── Zoom
  double _currentZoom = 1.0;
  double _minZoom     = 1.0;
  double _maxZoom     = 8.0;
  double _baseZoom    = 1.0;

  // ── Temp file management
  // The captured still is cached here and deleted when backToScan() is called
  // or when the widget is disposed — whichever comes first.
  File? _capturedFile;

  // Raw bytes of the captured JPEG — shown as a frozen image while processing.
  // Null while the camera is live.
  Uint8List? _capturedImageBytes;

  // OCR tokens streamed in during the readingText phase — shown as pills
  // above the processing card so the user sees what text was detected.
  List<String> _liveOcrTokens = [];

  // ── Scan status — drives processing feedback label
  _ScanStatus _scanStatus = _ScanStatus.idle;

  // True during the brief moment after capture but before scanning starts —
  // the frozen image is shown fullscreen with no overlay, so the user
  // sees their captured photo before processing begins.
  bool _showingFrozenPreview = false;

  // ── Mode
  _DiscoverMode _mode = _DiscoverMode.scan;

  // ── Scan results
  List<MatchCandidate> _candidates = [];
  List<TextBlock> _ocrBlocks = []; // for highlight overlay
  bool _showingResults = false;

  // ── Search
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    ScannerService.instance.dispose();
    _deleteCapturedFile();   // clean up any cached still
    _capturedImageBytes = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
      _controller = null;  // null so _buildViewfinder shows loading, not force-unwrap crash
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ── Camera init ───────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    setState(() { _initialising = true; _cameraError = null; });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) { _setError('No cameras found.'); return; }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        back, ResolutionPreset.max,   // max res for OCR accuracy on still capture
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      // Enable auto-focus and auto-exposure so tap-to-focus works correctly
      await ctrl.setFocusMode(FocusMode.auto);
      await ctrl.setExposureMode(ExposureMode.auto);
      // Sync flash mode to current state — prevents ghost flash on reinit
      await ctrl.setFlashMode(_flashModeToCamera(_flashMode));
      final minZ = await ctrl.getMinZoomLevel();
      final maxZ = await ctrl.getMaxZoomLevel();
      if (!mounted) return;
      setState(() {
        _controller   = ctrl;
        _initialising = false;
        _minZoom      = minZ;
        _maxZoom      = maxZ.clamp(1.0, 8.0);
        _currentZoom  = 1.0;
      });
      // Kick off scanner warmup — builds pre-processed card lookup cache
      ScannerService.instance.warmup();
    } catch (e) {
      _setError(e.toString());
    }
  }

  void _setError(String msg) {
    if (!mounted) return;
    setState(() { _cameraError = msg; _initialising = false; });
  }

  // ── Scan ──────────────────────────────────────────────────────────────────

  Future<void> _scan() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _scanning) return;

    setState(() {
      _scanning           = true;
      _showingResults     = false;
      _candidates         = [];
      _ocrBlocks          = [];
      _liveOcrTokens      = [];
      _capturedImageBytes = null;
      _scanStatus         = _ScanStatus.capturing;
      _focusPoint         = null;
    });

    try {
      // ── Step 1: capture high-res still ────────────────────────────────────
      // Lock focus before firing the shutter.
      try { await ctrl.setFocusMode(FocusMode.locked); } catch (_) {}

      final xFile = await ctrl.takePicture();
      _capturedFile       = File(xFile.path);
      final bytes         = await _capturedFile!.readAsBytes();

      // Phase A: show frozen still fullscreen — user sees their photo.
      // No overlay yet; the image fills the whole screen for 400ms.
      setState(() {
        _capturedImageBytes    = bytes;
        _showingFrozenPreview  = true;
        _scanStatus            = _ScanStatus.capturing;
      });
      await Future.delayed(const Duration(milliseconds: 400));

      // Phase B: begin processing — overlay appears over frozen image.
      if (!mounted) return;
      setState(() {
        _showingFrozenPreview = false;
        _scanStatus           = _ScanStatus.readingText;
      });

      // Restore auto-focus for next session (fire-and-forget)
      ctrl.setFocusMode(FocusMode.auto).ignore();

      // ── Step 2: OCR — run and stream tokens into the UI as they arrive ────
      final recogniser  = TextRecognizer(script: TextRecognitionScript.chinese);
      final inputImage  = InputImage.fromFilePath(xFile.path);
      final recognised  = await recogniser.processImage(inputImage);
      await recogniser.close();

      // Extract the same tokens ScannerService will use, and stream them
      // into _liveOcrTokens so the user sees what text was found.
      final tokens = <String>{};
      for (final block in recognised.blocks) {
        for (final line in block.lines) {
          final raw = line.text.trim();
          if (raw.length >= 2) {
            tokens.add(raw);
            if (mounted) {
              setState(() => _liveOcrTokens = tokens.take(12).toList());
            }
          }
        }
      }

      // ── Step 3: card matching ──────────────────────────────────────────────
      if (mounted) setState(() => _scanStatus = _ScanStatus.matchingCard);

      // Pass pre-run OCR result — avoids a second MLKit call inside ScannerService.
      final result = await ScannerService.instance.match(
        bytes,
        recognisedText: recognised,
      );

      if (!mounted) return;
      setState(() {
        _scanning   = false;
        _scanStatus = _ScanStatus.done;
        _ocrBlocks  = recognised.blocks;
        _candidates = result.candidates;
        // Only show results sheet if there are candidates — prevents
        // an empty sheet flash before _backToScan() resets state.
        _showingResults = result.candidates.isNotEmpty;
      });

      if (result.candidates.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Card not recognised — try again'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
        _backToScan();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning           = false;
        _scanStatus         = _ScanStatus.idle;
        _capturedImageBytes = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scan failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Returns to live camera state and deletes the cached still.
  void _backToScan() {
    _deleteCapturedFile();
    setState(() {
      _showingResults      = false;
      _candidates          = [];
      _ocrBlocks           = [];
      _liveOcrTokens       = [];
      _scanStatus          = _ScanStatus.idle;
      _capturedImageBytes  = null;
      _showingFrozenPreview = false;
    });
    // Re-enable autofocus and reset zoom when returning to live view
    _controller?.setFocusMode(FocusMode.auto).ignore();
    if (_currentZoom != 1.0) {
      _controller?.setZoomLevel(1.0).ignore();
      setState(() => _currentZoom = 1.0);
    }
  }

  // Deletes the temp JPEG produced by takePicture() if it still exists.
  // Called by main.dart via GlobalKey when the user re-enters the Discover tab.
  // Tears down the camera, clears all scan state, and reinitialises fresh.
  void resetSession() {
    _backToScan();
    // Dispose and reinitialise so the camera preview restarts cleanly
    _controller?.dispose();
    _controller = null;
    _initCamera();
  }

  void _deleteCapturedFile() {
    final f = _capturedFile;
    if (f != null) {
      f.exists().then((exists) { if (exists) f.delete(); });
      _capturedFile = null;
    }
  }

  /// Cycles flash: off → auto → on → off.
  /// Sets the camera flash mode immediately so the icon updates in sync.
  Future<void> _cycleFlash() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final next = switch (_flashMode) {
      _FlashMode.off  => _FlashMode.auto,
      _FlashMode.auto => _FlashMode.on,
      _FlashMode.on   => _FlashMode.off,
    };
    setState(() => _flashMode = next);
    await ctrl.setFlashMode(_flashModeToCamera(next));
  }

  /// Maps our _FlashMode to the camera package FlashMode.
  /// torch is intentionally NOT used — it keeps the light on
  /// continuously and was causing random flashes on lifecycle events.
  FlashMode _flashModeToCamera(_FlashMode m) => switch (m) {
    _FlashMode.off  => FlashMode.off,
    _FlashMode.auto => FlashMode.auto,
    _FlashMode.on   => FlashMode.always,
  };

  IconData _flashIcon() => switch (_flashMode) {
    _FlashMode.off  => Icons.flash_off,
    _FlashMode.auto => Icons.flash_auto,
    _FlashMode.on   => Icons.flash_on,
  };

  // ── Pinch-to-zoom ─────────────────────────────────────────────────────────
  void _onScaleStart(ScaleStartDetails _) {
    _baseZoom = _currentZoom;
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails details) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _scanning) return;
    final newZoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
    if ((newZoom - _currentZoom).abs() < 0.01) return;
    setState(() => _currentZoom = newZoom);
    await ctrl.setZoomLevel(newZoom);
  }

  // ── Tap-to-focus ──────────────────────────────────────────────────────────
  //
  // setFocusPoint() expects coordinates in SENSOR space — (0,0) top-left,
  // (1,1) bottom-right of the sensor output — NOT widget-pixel coordinates.
  //
  // The live preview uses FittedBox(fit: BoxFit.cover), which crops the sensor
  // stream to fill the widget. That means the widget's (0,0)→(1,1) range maps
  // to only a sub-rectangle of the sensor. We must invert the crop transform:
  //
  //   widgetAspect = widget w / widget h
  //   sensorAspect = sensor w / sensor h   (previewSize.height × .width because
  //                                          the camera package reports in landscape)
  //
  //   If sensorAspect > widgetAspect  → sensor is wider than widget
  //       → image is cropped left/right  → x needs to be scaled inward
  //   If sensorAspect < widgetAspect  → sensor is taller than widget
  //       → image is cropped top/bottom → y needs to be scaled inward
  //
  // The _FocusSquare position is kept in widget-normalised space (for display),
  // while the sensor-space value is what we send to setFocusPoint/setExposurePoint.
  Future<void> _onViewfinderTap(TapDownDetails details, BoxConstraints box) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _scanning) return;

    final widgetW = box.maxWidth;
    final widgetH = box.maxHeight;
    // Normalised tap in widget space — used for the visual indicator only
    final widgetNorm = Offset(
      details.localPosition.dx / widgetW,
      details.localPosition.dy / widgetH,
    );

    setState(() {
      _focusPoint    = widgetNorm;
      _focusAcquired = false;
    });

    try {
      // Sensor dimensions (camera package reports previewSize as landscape:
      //   previewSize.width  = long edge
      //   previewSize.height = short edge
      // After FittedBox rotates it to portrait we swap them).
      final previewSize = ctrl.value.previewSize!;
      // In the portrait-rotated CameraPreview:
      //   logical sensor width  = previewSize.height  (short edge of landscape)
      //   logical sensor height = previewSize.width   (long edge of landscape)
      final sensorW = previewSize.height;
      final sensorH = previewSize.width;

      final widgetAspect = widgetW / widgetH;
      final sensorAspect = sensorW / sensorH;

      // Sensor-space tap coordinate — apply inverse BoxFit.cover crop
      double sensorX, sensorY;
      if (sensorAspect > widgetAspect) {
        // Sensor is wider → horizontal crop
        // The rendered image height = widgetH, rendered image width = widgetH * sensorAspect
        // Crop offset from the left of the sensor image:
        final scale     = widgetH / sensorH;            // pixels per sensor unit
        final rendered  = sensorW * scale;               // total rendered width in px
        final cropLeft  = (rendered - widgetW) / 2.0;   // px cropped from each side
        sensorX = (details.localPosition.dx + cropLeft) / rendered;
        sensorY = details.localPosition.dy / widgetH;
      } else {
        // Sensor is taller → vertical crop
        final scale     = widgetW / sensorW;
        final rendered  = sensorH * scale;
        final cropTop   = (rendered - widgetH) / 2.0;
        sensorX = details.localPosition.dx / widgetW;
        sensorY = (details.localPosition.dy + cropTop) / rendered;
      }

      // Clamp to [0,1] and send to platform
      final sensorOffset = Offset(
        sensorX.clamp(0.0, 1.0),
        sensorY.clamp(0.0, 1.0),
      );

      await ctrl.setFocusPoint(sensorOffset);
      await ctrl.setExposurePoint(sensorOffset);

      // Brief pause — give the hardware AF system time to converge
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) setState(() => _focusAcquired = true);
      // Auto-dismiss after 1.5 s more
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) setState(() => _focusPoint = null);
    } catch (_) {
      // setFocusPoint / setExposurePoint not supported on all devices
      if (mounted) setState(() => _focusPoint = null);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return _mode == _DiscoverMode.scan
        ? _buildScanMode()
        : _buildSearchMode();
  }

  // ── Scan mode ─────────────────────────────────────────────────────────────

  Widget _buildScanMode() {
    // PopScope intercepts the Android back button when results are showing
    // and returns to the live scan screen instead of leaving the tab.
    return PopScope(
      canPop: !_showingResults && !_scanning && !_showingFrozenPreview,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && (_showingResults || _scanning || _showingFrozenPreview)) {
          _backToScan();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: _buildViewfinder()),

          if (_showingResults && _ocrBlocks.isNotEmpty)
            Positioned.fill(child: _OcrHighlightOverlay(blocks: _ocrBlocks)),

          // Flash anchored top-left
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.topLeft,
                child: _controller?.value.isInitialized == true
                    ? _IconButton(
                        icon: _flashIcon(),
                        onTap: () => _cycleFlash(),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),

          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _buildBottomBar(),
          ),

          // Processing overlay — only shown AFTER the frozen preview phase.
          // During _showingFrozenPreview, the captured image is shown clean.
          if (_scanning && !_showingFrozenPreview)
            Positioned.fill(
              child: _ScanningOverlay(
                status:    _scanStatus,
                ocrTokens: _liveOcrTokens,
              ),
            ),

          // Results sheet — defined in scanner_results_sheet.dart
          if (_showingResults && _candidates.isNotEmpty)
            Positioned.fill(
              child: ScannerResultsSheet(
                candidates: _candidates,
                onSelect: (c) {
                  _backToScan();
                  widget.onCardTap(c.cardId, c.recordType);
                },
                onDismiss: _backToScan,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildViewfinder() {
    if (_initialising) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (_cameraError != null) {
      return _CameraError(error: _cameraError!, onRetry: _initCamera);
    }

    // ── Frozen still: once the shutter fires, swap the live feed out for
    //    the captured JPEG. This "locks" the frame exactly as Google Lens does.
    if (_capturedImageBytes != null) {
      return Image.memory(
        _capturedImageBytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }

    // ── Live camera feed
    final ctrl = _controller;
    if (ctrl == null) {
      // Controller was nulled by lifecycle handler — show spinner until reinit
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final focusableH = constraints.maxHeight - 160.0;
          return GestureDetector(
            onTapDown: _showingResults || _scanning
                ? null
                : (d) {
                    if (d.localPosition.dy < focusableH) {
                      _onViewfinderTap(d, constraints);
                    }
                  },
            child: GestureDetector(
              onScaleStart:  _showingResults || _scanning ? null : _onScaleStart,
              onScaleUpdate: _showingResults || _scanning ? null : _onScaleUpdate,
              child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width:  ctrl.value.previewSize!.height,
                        height: ctrl.value.previewSize!.width,
                        child: CameraPreview(ctrl),
                      ),
                    ),
                  ),
                ),
                if (_focusPoint != null)
                  _FocusSquare(
                    position: _focusPoint!,
                    acquired: _focusAcquired,
                  ),

                // Zoom indicator — visible when zoomed in
                if (_currentZoom > _minZoom + 0.15)
                  Positioned(
                    top: 12, right: 12,
                    child: _ZoomBadge(zoom: _currentZoom),
                  ),
              ],
              ), // Stack
            ), // inner scale GestureDetector
          );
        },
      ),
    );
  }

  Widget _buildBottomBar() {
    final ready = _controller?.value.isInitialized == true && !_scanning && !_showingResults;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Instruction label / dismiss hint
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _showingResults
                    ? GestureDetector(
                        onTap: _backToScan,
                        child: Container(
                          key: const ValueKey('dismiss'),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Tap to scan again',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      )
                    : const Text(
                        key: ValueKey('hint'),
                        'Point at a card and tap to scan',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
              ),
              const SizedBox(height: 16),
              // Shutter button (centre) + mode pill below
              GestureDetector(
                onTap: ready ? _scan : (_showingResults ? _backToScan : null),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 70, height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ready ? Colors.white : Colors.white30,
                    border: Border.all(
                      color: ready ? Colors.white54 : Colors.white12,
                      width: 4,
                    ),
                    boxShadow: ready
                        ? [BoxShadow(
                            color: Colors.white.withValues(alpha: 0.25),
                            blurRadius: 14, spreadRadius: 2,
                          )]
                        : [],
                  ),
                  child: _scanning
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black54),
                        )
                      : Icon(
                          _showingResults ? Icons.close : Icons.document_scanner,
                          color: Colors.black87, size: 28,
                        ),
                ),
              ),
              const SizedBox(height: 20),
              // Mode pill navbar
              _ModePill(
                selected: _mode,
                onChanged: (m) {
                  _backToScan();
                  setState(() => _mode = m);
                  if (m == _DiscoverMode.search) {
                    Future.delayed(
                      const Duration(milliseconds: 300),
                      () => _searchFocus.requestFocus(),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Search mode ───────────────────────────────────────────────────────────

  Widget _buildSearchMode() {
    // Do NOT use Scaffold here — ScannerScreen is already inside main.dart's Scaffold.
    // A nested Scaffold causes double-AppBar / double-SafeArea issues.
    return SizedBox.expand(
      child: SafeArea(
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search rules, generals, card effects…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                ),
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
              ),
            ),
            const SizedBox(height: 8),
            // Results area — placeholder for Feature 2
            Expanded(
              child: _searchController.text.isEmpty
                  ? _DiscoverSearchEmptyState()
                  : const Center(
                      child: Text(
                        'Semantic search\ncoming in Feature 2',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
            ),
            // Mode pill at bottom
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: _ModePill(
                selected: _mode,
                onChanged: (m) {
                  setState(() => _mode = m);
                  if (m == _DiscoverMode.scan) {
                    _searchFocus.unfocus();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mode pill navbar
// ─────────────────────────────────────────────────────────────────────────────

class _ModePill extends StatelessWidget {
  final _DiscoverMode selected;
  final void Function(_DiscoverMode) onChanged;

  const _ModePill({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PillItem(
            icon: Icons.document_scanner_outlined,
            label: 'Scan Card',
            selected: selected == _DiscoverMode.scan,
            onTap: () => onChanged(_DiscoverMode.scan),
          ),
          _PillItem(
            icon: Icons.search,
            label: 'Search',
            selected: selected == _DiscoverMode.search,
            onTap: () => onChanged(_DiscoverMode.search),
          ),
        ],
      ),
    );
  }
}

class _PillItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PillItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.black87 : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? Colors.black87 : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OCR highlight overlay
// Draws amber rounded rectangles over each detected text block,
// mirroring the Google Lens "Select text" highlight behaviour.
// ─────────────────────────────────────────────────────────────────────────────

class _OcrHighlightOverlay extends StatefulWidget {
  final List<TextBlock> blocks;
  const _OcrHighlightOverlay({required this.blocks});

  @override
  State<_OcrHighlightOverlay> createState() => _OcrHighlightOverlayState();
}

class _OcrHighlightOverlayState extends State<_OcrHighlightOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: CustomPaint(
        painter: _OcrHighlightPainter(blocks: widget.blocks),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _OcrHighlightPainter extends CustomPainter {
  final List<TextBlock> blocks;
  const _OcrHighlightPainter({required this.blocks});

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = const Color(0xFFFFB300).withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = const Color(0xFFFFB300).withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final block in blocks) {
      final pts = block.cornerPoints;
      if (pts.length < 4) continue;
      final path = Path()
        ..moveTo(pts[0].x.toDouble(), pts[0].y.toDouble())
        ..lineTo(pts[1].x.toDouble(), pts[1].y.toDouble())
        ..lineTo(pts[2].x.toDouble(), pts[2].y.toDouble())
        ..lineTo(pts[3].x.toDouble(), pts[3].y.toDouble())
        ..close();
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(_OcrHighlightPainter old) => old.blocks != blocks;
}

// ─────────────────────────────────────────────────────────────────────────────
// Scanning feedback overlay
//
// Shown while _scanning == true. The captured JPEG is already visible as the
// viewfinder background (see _buildViewfinder). This overlay adds:
//   • A semi-transparent scrim (light, not opaque — image stays visible)
//   • A bottom sheet-style card with the three pipeline steps
//   • Live OCR token pills that appear as text is detected
// ─────────────────────────────────────────────────────────────────────────────

class _ScanningOverlay extends StatelessWidget {
  final _ScanStatus      status;
  final List<String>     ocrTokens;  // live-streamed as OCR runs

  const _ScanningOverlay({
    required this.status,
    required this.ocrTokens,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Stack(
      children: [
        // Light scrim — the frozen image behind stays legible
        Positioned.fill(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.35),
          ),
        ),

        // Processing card slides up from the bottom
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E1E1E).withValues(alpha: 0.97)
                  : Colors.white.withValues(alpha: 0.97),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: theme.hintColor.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Pipeline steps
                    _StepRow(
                      icon: Icons.camera_alt_outlined,
                      label: 'Image captured',
                      active: status == _ScanStatus.capturing,
                      done:   status.index > _ScanStatus.capturing.index,
                    ),
                    const SizedBox(height: 10),
                    _StepRow(
                      icon: Icons.document_scanner_outlined,
                      label: 'Reading card text',
                      active: status == _ScanStatus.readingText,
                      done:   status.index > _ScanStatus.readingText.index,
                    ),
                    const SizedBox(height: 10),
                    _StepRow(
                      icon: Icons.style_outlined,
                      label: 'Matching card',
                      active: status == _ScanStatus.matchingCard,
                      done:   status == _ScanStatus.done,
                    ),

                    // Live OCR token pills — appear as text is detected
                    if (ocrTokens.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Detected text',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.hintColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: ocrTokens.map((t) => _TokenPill(text: t)).toList(),
                      ),
                    ],
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TokenPill extends StatelessWidget {
  final String text;
  const _TokenPill({required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.black.withValues(alpha: 0.1),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: isDark ? Colors.white70 : Colors.black87,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool done;

  const _StepRow({
    required this.icon,
    required this.label,
    required this.active,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    final color = done
        ? Colors.greenAccent
        : active
            ? Colors.white
            : Colors.white38;
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle_outline : icon,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: color,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        if (active) ...[
          const Spacer(),
          SizedBox(
            width: 12, height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// Camera error widget
// ─────────────────────────────────────────────────────────────────────────────

class _CameraError extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _CameraError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              const Text('Camera unavailable',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white)),
              const SizedBox(height: 8),
              Text(error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Zoom level badge
// ─────────────────────────────────────────────────────────────────────────────

class _ZoomBadge extends StatelessWidget {
  final double zoom;
  const _ZoomBadge({required this.zoom});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${zoom.toStringAsFixed(1)}×',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tap-to-focus square
// Drawn at the tap position in normalised [0,1] coordinates.
// Amber while focusing, white once focus is acquired.
// ─────────────────────────────────────────────────────────────────────────────

class _FocusSquare extends StatefulWidget {
  final Offset position;  // normalised [0,1] within the viewfinder
  final bool acquired;

  const _FocusSquare({required this.position, required this.acquired});

  @override
  State<_FocusSquare> createState() => _FocusSquareState();
}

class _FocusSquareState extends State<_FocusSquare>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..forward();
    // Scale from 1.4 → 1.0 (zoom-in feel when square appears)
    _scale = Tween<double>(begin: 1.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Convert normalised position to pixel offset, clamped so the square
        // doesn't clip outside the viewfinder edges.
        const size = 72.0;
        final px = (widget.position.dx * constraints.maxWidth)
            .clamp(size / 2, constraints.maxWidth  - size / 2);
        final py = (widget.position.dy * constraints.maxHeight)
            .clamp(size / 2, constraints.maxHeight - size / 2);

        final color = widget.acquired
            ? Colors.white
            : const Color(0xFFFFB300); // amber while AF in progress

        return FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Stack(
              children: [
                Positioned(
                  left: px - size / 2,
                  top:  py - size / 2,
                  child: CustomPaint(
                    size: const Size(size, size),
                    painter: _FocusSquarePainter(
                      color: color,
                      acquired: widget.acquired,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FocusSquarePainter extends CustomPainter {
  final Color color;
  final bool acquired;
  const _FocusSquarePainter({required this.color, required this.acquired});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    const arm = 14.0; // corner arm length
    final l = 0.0, t = 0.0, r = size.width, b = size.height;

    // Draw four L-shaped corners — same aesthetic as Google Lens
    void drawCorner(double cx, double cy, double dx, double dy) {
      canvas.drawLine(Offset(cx, cy), Offset(cx + arm * dx, cy), paint);
      canvas.drawLine(Offset(cx, cy), Offset(cx, cy + arm * dy), paint);
    }

    drawCorner(l, t,  1,  1);
    drawCorner(r, t, -1,  1);
    drawCorner(l, b,  1, -1);
    drawCorner(r, b, -1, -1);

    // Centre dot once focus is acquired
    if (acquired) {
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        2.5,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_FocusSquarePainter old) =>
      old.color != color || old.acquired != acquired;
}

// ─────────────────────────────────────────────────────────────────────────────
// Search empty state — placeholder until Feature 2 (semantic search) ships
// ─────────────────────────────────────────────────────────────────────────────

class _DiscoverSearchEmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.manage_search_rounded,
                size: 52, color: Colors.grey.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text(
              'Search for rules, generals,\nor card effects',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'e.g. "skill that draws cards when losing HP"\nor "what is chain damage"',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small icon button (flash toggle etc.)
// ─────────────────────────────────────────────────────────────────────────────

class _IconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}