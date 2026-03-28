// lib/features/ai/presentation/screens/scanner_screen.dart
//
// Discover tab — card scanner with Document Scanner workflow (Phase 2).
//
// State machine (v3.0 — .selecting replaced by .adjusting):
//   _ScannerState.live      — live camera feed
//   _ScannerState.adjusting — frozen still + quadrilateral handle overlay
//   _ScannerState.reviewing — frozen still + results sheet
//
// Document Scanner flow:
//   1. Shutter → capture + OCR in background
//   2. Auto-edge detection estimates card quad from OCR TextBlock corners
//   3. State → .adjusting — 4 draggable corner handles appear
//   4. User refines corners (magnifier bubble provides precision)
//   5. "Scan" → perspective warp → re-OCR on straightened → fusion pipeline
//   6. Or "Skip" → full-frame fusion (Phase 1 path, no warp)
//
// Coordinate Transformation (Widget → Buffer):
//   Same BoxFit.cover inverse as Phase 1 (spec v3.0 §Pillar 6.2).
//   For each corner point p in widget coords:
//     scale  = max(widget_w / buffer_w, widget_h / buffer_h)
//     crop_x = (buffer_w * scale - widget_w) / 2
//     crop_y = (buffer_h * scale - widget_h) / 2
//     p_buffer = Offset((p.dx + crop_x) / scale, (p.dy + crop_y) / scale)
//
// Architecture:
//   - No feature/* presentation imports — navigation via onCardTap / onBack
//   - Search mode delegated to DiscoverSearchScreen

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/recently_viewed_service.dart';
import '../../../../core/services/scanner_service.dart';
import '../../../../core/utils/perspective_warper.dart';
import 'discover_search_screen.dart';
import 'scanner_results_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

enum _FlashMode { off, auto, on }

enum _DiscoverMode { scan, search }

/// v3.0 state machine: .selecting removed, .adjusting added.
enum _ScannerState {
  live,       // Camera feed active
  adjusting,  // Frozen still + quad-handle overlay (Document Scanner)
  reviewing,  // Frozen still + results sheet
}

// ─────────────────────────────────────────────────────────────────────────────
// ScannerScreen
// ─────────────────────────────────────────────────────────────────────────────

class ScannerScreen extends StatefulWidget {
  final void Function(String id, RecordType type) onCardTap;
  final VoidCallback onBack;
  final void Function(bool visible) onNavBarVisibilityChanged;

  const ScannerScreen({
    super.key,
    required this.onCardTap,
    required this.onBack,
    required this.onNavBarVisibilityChanged,
  });

  @override
  State<ScannerScreen> createState() => ScannerScreenState();
}

class ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  // ── Camera
  CameraController? _controller;
  String? _cameraError;
  bool _initialising = true;
  _FlashMode _flashMode = _FlashMode.off;

  // ── Focus indicator
  Offset? _focusPoint;
  bool _focusAcquired = false;

  // ── Zoom
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 8.0;
  double _baseZoom = 1.0;

  // ── Screen state
  _ScannerState _state = _ScannerState.live;

  bool get isReviewing =>
      _state == _ScannerState.reviewing || _state == _ScannerState.adjusting;

  // ── Captured image
  File? _capturedFile;
  Uint8List? _capturedImageBytes;

  // ── Processing
  bool _processing = false;

  // ── Results
  List<MatchCandidate> _candidates = [];
  List<TextBlock> _ocrBlocks = [];

  // ── Quad handles (4 corners in widget coordinates, clockwise from top-left)
  List<Offset> _quadCorners = [];

  // ── Active drag state for magnifier
  int? _activeDragIndex;
  Offset? _activeDragPosition;

  // ── Mode
  _DiscoverMode _mode = _DiscoverMode.scan;

  // ── Gallery
  final ImagePicker _imagePicker = ImagePicker();

  // ── Widget size
  Size _widgetSize = Size.zero;

  // ── OCR result retained for re-use during adjusting → scan
  RecognizedText? _lastRecognisedText;

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
    ScannerService.instance.dispose();
    _deleteCapturedFile();
    _capturedImageBytes = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
      _controller = null;
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
      final ctrl = CameraController(back, ResolutionPreset.high,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await ctrl.initialize();
      await ctrl.setFocusMode(FocusMode.auto);
      await ctrl.setExposureMode(ExposureMode.auto);
      await ctrl.setFlashMode(_flashModeToCamera(_flashMode));
      final minZ = await ctrl.getMinZoomLevel();
      final maxZ = await ctrl.getMaxZoomLevel();
      if (!mounted) return;
      setState(() {
        _controller = ctrl;
        _initialising = false;
        _minZoom = minZ;
        _maxZoom = maxZ.clamp(1.0, 8.0);
        _currentZoom = 1.0;
      });
      ScannerService.instance.warmup();
    } catch (e) { _setError(e.toString()); }
  }

  void _setError(String msg) {
    if (!mounted) return;
    setState(() { _cameraError = msg; _initialising = false; });
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CAPTURE → AUTO-EDGE → .adjusting
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _scan() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _processing) return;
    if (_state != _ScannerState.live) return;

    try {
      try { await ctrl.setFocusMode(FocusMode.locked); } catch (_) {}

      final xFile = await ctrl.takePicture();
      final bytes = await File(xFile.path).readAsBytes();
      _capturedFile = File(xFile.path);
      _capturedImageBytes = bytes;

      if (!mounted) return;
      setState(() {
        _state = _ScannerState.adjusting;
        _processing = true;
        _candidates = [];
        _ocrBlocks = [];
        _quadCorners = _defaultQuad(); // fallback until OCR finishes
      });

      ctrl.setFocusMode(FocusMode.auto).ignore();

      // Run OCR in background to get text block corners for auto-edge hint
      final recogniser = TextRecognizer(script: TextRecognitionScript.chinese);
      final inputImage = InputImage.fromFilePath(xFile.path);
      final recognised = await recogniser.processImage(inputImage);
      await recogniser.close();

      if (!mounted) return;

      _lastRecognisedText = recognised;
      _ocrBlocks = recognised.blocks;

      // Auto-edge detection: convex hull of OCR corners + 5% margin
      final autoQuad = _estimateCardQuad(recognised);

      setState(() {
        _processing = false;
        _quadCorners = autoQuad;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _processing = false; _capturedImageBytes = null; });
      _returnToLive();
      _showSnack('Scan failed: $e');
    }
  }

  Future<void> _scanFromGallery() async {
    if (_processing || _state != _ScannerState.live) return;

    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    _capturedImageBytes = bytes;

    if (!mounted) return;
    setState(() {
      _state = _ScannerState.adjusting;
      _processing = true;
      _candidates = [];
      _ocrBlocks = [];
      _quadCorners = _defaultQuad();
    });

    try {
      final recogniser = TextRecognizer(script: TextRecognitionScript.chinese);
      final inputImage = InputImage.fromFilePath(picked.path);
      final recognised = await recogniser.processImage(inputImage);
      await recogniser.close();

      if (!mounted) return;
      _lastRecognisedText = recognised;
      _ocrBlocks = recognised.blocks;
      setState(() {
        _processing = false;
        _quadCorners = _estimateCardQuad(recognised);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _processing = false; _capturedImageBytes = null; });
      _returnToLive();
      _showSnack('Scan failed: $e');
    }
  }

  /// Default quad: 70% × 85% centered rectangle (fallback before OCR completes)
  List<Offset> _defaultQuad() {
    final w = _widgetSize.width;
    final h = _widgetSize.height;
    final l = w * 0.15, r = w * 0.85;
    final t = h * 0.075, b = h * 0.925;
    return [Offset(l, t), Offset(r, t), Offset(r, b), Offset(l, b)];
  }

  /// Estimates card quadrilateral from OCR text block bounding corners.
  /// Returns 4 Offset points in widget coordinates, clockwise from top-left.
  List<Offset> _estimateCardQuad(RecognizedText recognised) {
    if (recognised.blocks.isEmpty) return _defaultQuad();

    // Collect all corner points in buffer pixel space
    double minX = double.infinity, minY = double.infinity;
    double maxX = 0, maxY = 0;
    for (final block in recognised.blocks) {
      for (final pt in block.cornerPoints) {
        if (pt.x < minX) minX = pt.x.toDouble();
        if (pt.x > maxX) maxX = pt.x.toDouble();
        if (pt.y < minY) minY = pt.y.toDouble();
        if (pt.y > maxY) maxY = pt.y.toDouble();
      }
    }

    // Add 5% margin
    final rangeX = maxX - minX;
    final rangeY = maxY - minY;
    minX = (minX - rangeX * 0.05).clamp(0, double.infinity);
    minY = (minY - rangeY * 0.05).clamp(0, double.infinity);
    maxX += rangeX * 0.05;
    maxY += rangeY * 0.05;

    // Transform buffer coords → widget coords (inverse of the BoxFit.cover)
    final bytes = _capturedImageBytes;
    if (bytes == null || _widgetSize == Size.zero) return _defaultQuad();

    final decoded = img.decodeImage(bytes);
    if (decoded == null) return _defaultQuad();

    final bufW = decoded.width.toDouble();
    final bufH = decoded.height.toDouble();
    final wW = _widgetSize.width;
    final wH = _widgetSize.height;

    final scale = math.max(wW / bufW, wH / bufH);
    final cropX = (bufW * scale - wW) / 2.0;
    final cropY = (bufH * scale - wH) / 2.0;

    Offset bufToWidget(double bx, double by) {
      return Offset(
        (bx * scale - cropX).clamp(0, wW),
        (by * scale - cropY).clamp(0, wH),
      );
    }

    return [
      bufToWidget(minX, minY), // top-left
      bufToWidget(maxX, minY), // top-right
      bufToWidget(maxX, maxY), // bottom-right
      bufToWidget(minX, maxY), // bottom-left
    ];
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ADJUSTING → PERSPECTIVE WARP → FUSION
  // ═════════════════════════════════════════════════════════════════════════

  /// "Scan" button: warp the card, re-OCR, run fusion with straightened mode.
  Future<void> _confirmAndWarp() async {
    final bytes = _capturedImageBytes;
    if (bytes == null || _processing) return;

    setState(() { _processing = true; });

    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        _showSnack('Failed to decode image');
        setState(() { _processing = false; });
        return;
      }

      // ── Transform 4 widget-space corners → buffer pixel space ──────────
      final bufW = decoded.width.toDouble();
      final bufH = decoded.height.toDouble();
      final wW = _widgetSize.width;
      final wH = _widgetSize.height;
      final scale = math.max(wW / bufW, wH / bufH);
      final cropX = (bufW * scale - wW) / 2.0;
      final cropY = (bufH * scale - wH) / 2.0;

      final bufferCorners = _quadCorners.map((p) {
        return Offset(
          ((p.dx + cropX) / scale).clamp(0, bufW),
          ((p.dy + cropY) / scale).clamp(0, bufH),
        );
      }).toList();

      // ── Perspective warp → straightened card image ─────────────────────
      final straightened = PerspectiveWarper.warp(decoded, bufferCorners);

      // ── Encode to JPEG for MLKit + ScannerService ──────────────────────
      final straightenedJpeg = PerspectiveWarper.encodeJpeg(straightened);

      // ── Write temp file for MLKit (requires file path) ─────────────────
      final tempDir = await Directory.systemTemp.createTemp('sha_warp_');
      final tempFile = File('${tempDir.path}/warped.jpg');
      await tempFile.writeAsBytes(straightenedJpeg);

      // ── Re-run OCR on the straightened image ───────────────────────────
      final recogniser = TextRecognizer(script: TextRecognitionScript.chinese);
      final inputImage = InputImage.fromFilePath(tempFile.path);
      final recognised = await recogniser.processImage(inputImage);
      await recogniser.close();

      // ── Run fusion pipeline with straightened source + decoded image ────
      final result = await ScannerService.instance.match(
        straightenedJpeg,
        recognisedText: recognised,
        source: ScanSource.straightened,
        straightenedImage: straightened,
      );

      // Cleanup
      tempFile.delete().ignore();
      tempDir.delete().ignore();

      if (!mounted) return;
      setState(() {
        _processing = false;
        _state = _ScannerState.reviewing;
        _candidates = result.candidates;
      });

      if (result.candidates.isEmpty) {
        _showSnack('Card not recognised — try adjusting corners');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _processing = false; });
      _showSnack('Warp failed: $e');
    }
  }

  /// "Skip" button: run fusion on the full frame without perspective warp.
  Future<void> _skipWarp() async {
    final bytes = _capturedImageBytes;
    final recognised = _lastRecognisedText;
    if (bytes == null || recognised == null) { _returnToLive(); return; }

    setState(() { _processing = true; });

    try {
      final result = await ScannerService.instance.match(
        bytes,
        recognisedText: recognised,
        source: ScanSource.camera,
      );

      if (!mounted) return;
      setState(() {
        _processing = false;
        _state = _ScannerState.reviewing;
        _candidates = result.candidates;
      });

      if (result.candidates.isEmpty) {
        _showSnack('Card not recognised — try again');
        _returnToLive();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _processing = false; });
      _returnToLive();
      _showSnack('Scan failed: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // STATE TRANSITIONS
  // ═════════════════════════════════════════════════════════════════════════

  void _returnToLive() {
    _deleteCapturedFile();
    _controller?.setFocusMode(FocusMode.auto).ignore();
    if (_currentZoom != 1.0) _controller?.setZoomLevel(1.0).ignore();
    setState(() {
      _state = _ScannerState.live;
      _processing = false;
      _candidates = [];
      _ocrBlocks = [];
      _capturedImageBytes = null;
      _currentZoom = 1.0;
      _quadCorners = [];
      _activeDragIndex = null;
      _activeDragPosition = null;
      _lastRecognisedText = null;
    });
  }

  void _deleteCapturedFile() {
    final f = _capturedFile;
    if (f != null) {
      f.exists().then((exists) { if (exists) f.delete(); });
      _capturedFile = null;
    }
  }

  void resetSession() {
    _returnToLive();
    _controller?.dispose();
    _controller = null;
    _initCamera();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2)),
    );
  }

  // ── Flash / Zoom / Focus (unchanged from Phase 1) ─────────────────────

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

  void _onScaleStart(ScaleStartDetails _) { _baseZoom = _currentZoom; }

  Future<void> _onScaleUpdate(ScaleUpdateDetails details) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _state != _ScannerState.live) return;
    final newZoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
    if ((newZoom - _currentZoom).abs() < 0.01) return;
    setState(() => _currentZoom = newZoom);
    await ctrl.setZoomLevel(newZoom);
  }

  Future<void> _onViewfinderTap(TapDownDetails details, BoxConstraints box) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _state != _ScannerState.live) return;

    final widgetW = box.maxWidth;
    final widgetH = box.maxHeight;
    setState(() {
      _focusPoint = Offset(details.localPosition.dx / widgetW, details.localPosition.dy / widgetH);
      _focusAcquired = false;
    });

    try {
      final previewSize = ctrl.value.previewSize!;
      final sensorW = previewSize.height;
      final sensorH = previewSize.width;
      final widgetAspect = widgetW / widgetH;
      final sensorAspect = sensorW / sensorH;

      double sensorX, sensorY;
      if (sensorAspect > widgetAspect) {
        final s = widgetH / sensorH;
        final rendered = sensorW * s;
        sensorX = (details.localPosition.dx + (rendered - widgetW) / 2) / rendered;
        sensorY = details.localPosition.dy / widgetH;
      } else {
        final s = widgetW / sensorW;
        final rendered = sensorH * s;
        sensorX = details.localPosition.dx / widgetW;
        sensorY = (details.localPosition.dy + (rendered - widgetH) / 2) / rendered;
      }

      await ctrl.setFocusPoint(Offset(sensorX.clamp(0, 1), sensorY.clamp(0, 1)));
      await ctrl.setExposurePoint(Offset(sensorX.clamp(0, 1), sensorY.clamp(0, 1)));
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) setState(() => _focusAcquired = true);
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) setState(() => _focusPoint = null);
    } catch (_) {
      if (mounted) setState(() => _focusPoint = null);
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_mode == _DiscoverMode.search) {
      return DiscoverSearchScreen(
        onSwitchToScan: () {
          setState(() => _mode = _DiscoverMode.scan);
          widget.onNavBarVisibilityChanged(false);
        },
      );
    }
    return _buildScanMode();
  }

  Widget _buildScanMode() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) {
        if (_state == _ScannerState.adjusting) { _returnToLive(); }
        else if (_state == _ScannerState.reviewing) { _returnToLive(); }
        else { widget.onBack(); }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          _widgetSize = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Camera feed
              Positioned.fill(child: _buildLiveFeed()),

              // 2. Frozen still
              if (_capturedImageBytes != null)
                Positioned.fill(
                  child: Image.memory(_capturedImageBytes!,
                      fit: BoxFit.cover, gaplessPlayback: true),
                ),

              // 3. Quad-handle overlay (adjusting state)
              if (_state == _ScannerState.adjusting && _quadCorners.length == 4)
                Positioned.fill(
                  child: _QuadHandleOverlay(
                    corners: _quadCorners,
                    activeIndex: _activeDragIndex,
                    activePosition: _activeDragPosition,
                    capturedBytes: _capturedImageBytes,
                    widgetSize: _widgetSize,
                    onCornerDragStart: (index, pos) {
                      setState(() {
                        _activeDragIndex = index;
                        _activeDragPosition = pos;
                      });
                    },
                    onCornerDragUpdate: (index, pos) {
                      setState(() {
                        _quadCorners[index] = pos;
                        _activeDragPosition = pos;
                      });
                    },
                    onCornerDragEnd: () {
                      setState(() {
                        _activeDragIndex = null;
                        _activeDragPosition = null;
                      });
                    },
                  ),
                ),

              // 4. Adjusting action bar
              if (_state == _ScannerState.adjusting && !_processing)
                Positioned(
                  left: 0, right: 0, bottom: 40,
                  child: _AdjustingActionBar(
                    onScan: () => _confirmAndWarp(),
                    onSkip: () => _skipWarp(),
                  ),
                ),

              // 5. OCR overlay (reviewing only)
              if (_state == _ScannerState.reviewing && _ocrBlocks.isNotEmpty)
                Positioned.fill(child: _OcrHighlightOverlay(blocks: _ocrBlocks)),

              // 6. Top bar
              Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),

              // 7. Bottom controls (live)
              if (_state == _ScannerState.live) _buildBottomControls(),

              // 8. Processing spinner
              if (_processing)
                const Positioned(
                  bottom: 120, left: 0, right: 0,
                  child: Center(child: SizedBox(width: 36, height: 36,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))),
                ),

              // 9. Results sheet
              if (_state == _ScannerState.reviewing && _candidates.isNotEmpty)
                Positioned.fill(
                  child: ScannerResultsSheet(
                    candidates: _candidates,
                    onSelect: (c) { _returnToLive(); widget.onCardTap(c.cardId, c.recordType); },
                    onDismiss: _returnToLive,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ── Top bar ─────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final isAdj = _state == _ScannerState.adjusting;
    return SafeArea(
      child: SizedBox(
        height: 56,
        child: Stack(
          children: [
            Center(child: Text(
              isAdj ? 'Adjust Card Boundary' : 'Discover',
              style: TextStyle(color: Colors.white, fontSize: isAdj ? 15 : 17,
                  fontWeight: FontWeight.w600,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 8)]),
            )),
            Positioned(left: 4, top: 0, bottom: 0, child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                onPressed: () {
                  if (_state != _ScannerState.live) _returnToLive();
                  else widget.onBack();
                },
              ),
              if (_state == _ScannerState.live)
                IconButton(icon: Icon(_flashIcon(), color: Colors.white, size: 22),
                    onPressed: () => _cycleFlash()),
            ])),
          ],
        ),
      ),
    );
  }

  // ── Live feed / Bottom controls (unchanged from Phase 1) ──────────────

  Widget _buildLiveFeed() {
    if (_initialising) {
      return const ColoredBox(color: Colors.black,
          child: Center(child: CircularProgressIndicator(color: Colors.white)));
    }
    if (_cameraError != null) {
      return _CameraError(error: _cameraError!, onRetry: _initCamera);
    }
    final ctrl = _controller;
    if (ctrl == null) {
      return const ColoredBox(color: Colors.black,
          child: Center(child: CircularProgressIndicator(color: Colors.white)));
    }
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(builder: (context, constraints) {
        return GestureDetector(
          onTapDown: _state != _ScannerState.live ? null
              : (d) => _onViewfinderTap(d, constraints),
          child: GestureDetector(
            onScaleStart: _state != _ScannerState.live ? null : _onScaleStart,
            onScaleUpdate: _state != _ScannerState.live ? null : _onScaleUpdate,
            child: Stack(fit: StackFit.expand, children: [
              ClipRect(child: OverflowBox(alignment: Alignment.center,
                  child: FittedBox(fit: BoxFit.cover, child: SizedBox(
                      width: ctrl.value.previewSize!.height,
                      height: ctrl.value.previewSize!.width,
                      child: CameraPreview(ctrl))))),
              if (_focusPoint != null)
                _FocusSquare(position: _focusPoint!, acquired: _focusAcquired),
              if (_currentZoom > _minZoom + 0.15)
                Positioned(top: 12, right: 12, child: _ZoomBadge(zoom: _currentZoom)),
            ]),
          ),
        );
      }),
    );
  }

  Widget _buildBottomControls() {
    final ready = _controller?.value.isInitialized == true && !_processing;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Positioned(left: 0, right: 0, bottom: 0, child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(32, 0, 32, 16), child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: ready ? () => _scanFromGallery() : null,
              child: Container(width: 52, height: 52,
                  decoration: BoxDecoration(color: Colors.black38,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white30, width: 1.5)),
                  child: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 24)),
            ),
            const SizedBox(width: 40),
            GestureDetector(
              onTap: ready ? _scan : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150), width: 72, height: 72,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    color: ready ? Colors.white : Colors.white30,
                    border: Border.all(color: ready ? Colors.white60 : Colors.white12, width: 4),
                    boxShadow: ready ? [BoxShadow(color: Colors.white.withValues(alpha: 0.25),
                        blurRadius: 16, spreadRadius: 2)] : []),
                child: const Icon(Icons.document_scanner, color: Colors.black87, size: 30),
              ),
            ),
            const SizedBox(width: 40),
            const SizedBox(width: 52, height: 52),
          ],
        )),
        Padding(padding: EdgeInsets.only(bottom: bottom + 8), child: _ModePill(
          onSwitchToSearch: () {
            _returnToLive();
            setState(() => _mode = _DiscoverMode.scan);
            widget.onNavBarVisibilityChanged(true);
          },
        )),
      ],
    ));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// QUAD-HANDLE OVERLAY (Document Scanner UI — Phase 2)
// ═══════════════════════════════════════════════════════════════════════════════

class _QuadHandleOverlay extends StatelessWidget {
  final List<Offset> corners;
  final int? activeIndex;
  final Offset? activePosition;
  final Uint8List? capturedBytes;
  final Size widgetSize;
  final void Function(int index, Offset position) onCornerDragStart;
  final void Function(int index, Offset position) onCornerDragUpdate;
  final VoidCallback onCornerDragEnd;

  const _QuadHandleOverlay({
    required this.corners,
    required this.activeIndex,
    required this.activePosition,
    required this.capturedBytes,
    required this.widgetSize,
    required this.onCornerDragStart,
    required this.onCornerDragUpdate,
    required this.onCornerDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Quad outline + dimmed exterior
        CustomPaint(
          painter: _QuadOverlayPainter(corners: corners, activeIndex: activeIndex),
          child: const SizedBox.expand(),
        ),

        // 4 draggable corner handles
        for (var i = 0; i < 4; i++)
          Positioned(
            left: corners[i].dx - 22,
            top: corners[i].dy - 22,
            child: GestureDetector(
              onPanStart: (d) => onCornerDragStart(i, corners[i]),
              onPanUpdate: (d) {
                final newPos = Offset(
                  (corners[i].dx + d.delta.dx).clamp(0, widgetSize.width),
                  (corners[i].dy + d.delta.dy).clamp(0, widgetSize.height),
                );
                onCornerDragUpdate(i, newPos);
              },
              onPanEnd: (_) => onCornerDragEnd(),
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: activeIndex == i
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.85),
                  border: Border.all(
                    color: const Color(0xFF448AFF),
                    width: activeIndex == i ? 3.5 : 2.5,
                  ),
                  boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 8, spreadRadius: 1,
                  )],
                ),
                child: activeIndex == i
                    ? const Icon(Icons.open_with, size: 18, color: Color(0xFF448AFF))
                    : null,
              ),
            ),
          ),

        // Magnifier bubble — appears during active drag, 60px above finger
        if (activeIndex != null && activePosition != null && capturedBytes != null)
          Positioned(
            left: activePosition!.dx - 50,
            top: activePosition!.dy - 130,
            child: _MagnifierBubble(
              touchPoint: activePosition!,
              capturedBytes: capturedBytes!,
              widgetSize: widgetSize,
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quad overlay painter — draws the quad outline + semi-transparent mask
// ─────────────────────────────────────────────────────────────────────────────

class _QuadOverlayPainter extends CustomPainter {
  final List<Offset> corners;
  final int? activeIndex;

  const _QuadOverlayPainter({required this.corners, this.activeIndex});

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length < 4) return;

    // Semi-transparent dark overlay covering entire frame
    final dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.45);
    canvas.drawRect(Offset.zero & size, dimPaint);

    // Cut out the quad region (draw it back as clear)
    final quadPath = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();

    canvas.drawPath(quadPath, Paint()
      ..blendMode = BlendMode.clear);

    // Quad outline
    final linePaint = Paint()
      ..color = const Color(0xFF448AFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(quadPath, linePaint);

    // Edge midpoint dots (visual affordance)
    final dotPaint = Paint()..color = const Color(0xFF448AFF);
    for (var i = 0; i < 4; i++) {
      final mid = Offset(
        (corners[i].dx + corners[(i + 1) % 4].dx) / 2,
        (corners[i].dy + corners[(i + 1) % 4].dy) / 2,
      );
      canvas.drawCircle(mid, 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_QuadOverlayPainter old) =>
      old.corners != corners || old.activeIndex != activeIndex;
}

// ─────────────────────────────────────────────────────────────────────────────
// Magnifier bubble — 2× zoom, 100px diameter, positioned above the finger
// ─────────────────────────────────────────────────────────────────────────────

class _MagnifierBubble extends StatelessWidget {
  final Offset touchPoint;
  final Uint8List capturedBytes;
  final Size widgetSize;

  static const double _diameter = 100;
  static const double _zoom = 2.0;

  const _MagnifierBubble({
    required this.touchPoint,
    required this.capturedBytes,
    required this.widgetSize,
  });

  @override
  Widget build(BuildContext context) {
    // The magnifier shows a 2× zoomed crop of the frozen image centered
    // on the touch point. We use a ClipOval + Transform.scale + fractional
    // alignment offset to achieve this without decoding the image again.
    //
    // The Image.memory widget with BoxFit.cover fills the full widget area,
    // then we scale 2× and translate to center on the touch point.

    final normX = touchPoint.dx / widgetSize.width;
    final normY = touchPoint.dy / widgetSize.height;

    return Container(
      width: _diameter,
      height: _diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.5),
          blurRadius: 12, spreadRadius: 2,
        )],
      ),
      child: ClipOval(
        child: OverflowBox(
          maxWidth: widgetSize.width,
          maxHeight: widgetSize.height,
          child: Transform.scale(
            scale: _zoom,
            alignment: Alignment(
              (normX * 2 - 1).clamp(-1.0, 1.0),
              (normY * 2 - 1).clamp(-1.0, 1.0),
            ),
            child: Image.memory(
              capturedBytes,
              fit: BoxFit.cover,
              width: widgetSize.width,
              height: widgetSize.height,
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Adjusting action bar — Scan + Skip buttons
// ─────────────────────────────────────────────────────────────────────────────

class _AdjustingActionBar extends StatelessWidget {
  final VoidCallback onScan;
  final VoidCallback onSkip;
  const _AdjustingActionBar({required this.onScan, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ActionChip(label: 'Skip', icon: Icons.fast_forward, onTap: onSkip, isPrimary: false),
        const SizedBox(width: 20),
        _ActionChip(label: 'Scan', icon: Icons.crop_free, onTap: onScan, isPrimary: true),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;
  const _ActionChip({required this.label, required this.icon,
      required this.onTap, required this.isPrimary});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: isPrimary ? Colors.white : Colors.black54,
          borderRadius: BorderRadius.circular(28),
          border: isPrimary ? null : Border.all(color: Colors.white30),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: isPrimary ? Colors.black87 : Colors.white),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
              color: isPrimary ? Colors.black87 : Colors.white)),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXISTING WIDGETS (unchanged)
// ═══════════════════════════════════════════════════════════════════════════════

class _ModePill extends StatelessWidget {
  final VoidCallback onSwitchToSearch;
  const _ModePill({required this.onSwitchToSearch});
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _PillItem(icon: Icons.document_scanner_outlined, label: 'Scan Card', selected: true, onTap: () {}),
        _PillItem(icon: Icons.search, label: 'Search', selected: false, onTap: onSwitchToSearch),
      ]));
  }
}

class _PillItem extends StatelessWidget {
  final IconData icon; final String label; final bool selected; final VoidCallback onTap;
  const _PillItem({required this.icon, required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap, child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(26)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: selected ? Colors.black87 : Colors.white70),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.black87 : Colors.white70)),
      ])));
  }
}

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
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _fade, child: CustomPaint(
        painter: _OcrHighlightPainter(blocks: widget.blocks),
        child: const SizedBox.expand()));
  }
}

class _OcrHighlightPainter extends CustomPainter {
  final List<TextBlock> blocks;
  const _OcrHighlightPainter({required this.blocks});
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0xFFFFB300).withValues(alpha: 0.22)..style = PaintingStyle.fill;
    final stroke = Paint()..color = const Color(0xFFFFB300).withValues(alpha: 0.75)..style = PaintingStyle.stroke..strokeWidth = 1.5;
    for (final block in blocks) {
      final pts = block.cornerPoints;
      if (pts.length < 4) continue;
      final path = Path()
        ..moveTo(pts[0].x.toDouble(), pts[0].y.toDouble())
        ..lineTo(pts[1].x.toDouble(), pts[1].y.toDouble())
        ..lineTo(pts[2].x.toDouble(), pts[2].y.toDouble())
        ..lineTo(pts[3].x.toDouble(), pts[3].y.toDouble())..close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }
  }
  @override
  bool shouldRepaint(_OcrHighlightPainter old) => old.blocks != blocks;
}

class _CameraError extends StatelessWidget {
  final String error; final VoidCallback onRetry;
  const _CameraError({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: Colors.black, child: Center(child: Padding(
      padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.camera_alt, size: 48, color: Colors.red),
        const SizedBox(height: 12),
        const Text('Camera unavailable', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
        const SizedBox(height: 8),
        Text(error, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 16),
        ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
      ]))));
  }
}

class _ZoomBadge extends StatelessWidget {
  final double zoom;
  const _ZoomBadge({required this.zoom});
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
        child: Text('${zoom.toStringAsFixed(1)}×',
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)));
  }
}

class _FocusSquare extends StatefulWidget {
  final Offset position; final bool acquired;
  const _FocusSquare({required this.position, required this.acquired});
  @override
  State<_FocusSquare> createState() => _FocusSquareState();
}
class _FocusSquareState extends State<_FocusSquare> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))..forward();
    _scale = Tween<double>(begin: 1.4, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const size = 72.0;
      final px = (widget.position.dx * constraints.maxWidth).clamp(size / 2, constraints.maxWidth - size / 2);
      final py = (widget.position.dy * constraints.maxHeight).clamp(size / 2, constraints.maxHeight - size / 2);
      final color = widget.acquired ? Colors.white : const Color(0xFFFFB300);
      return FadeTransition(opacity: _fade, child: ScaleTransition(scale: _scale,
          child: Stack(children: [Positioned(left: px - size / 2, top: py - size / 2,
              child: CustomPaint(size: const Size(size, size),
                  painter: _FocusSquarePainter(color: color, acquired: widget.acquired)))])));
    });
  }
}

class _FocusSquarePainter extends CustomPainter {
  final Color color; final bool acquired;
  const _FocusSquarePainter({required this.color, required this.acquired});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1.8..style = PaintingStyle.stroke;
    const arm = 14.0;
    final l = 0.0, t = 0.0, r = size.width, b = size.height;
    void corner(double cx, double cy, double dx, double dy) {
      canvas.drawLine(Offset(cx, cy), Offset(cx + arm * dx, cy), paint);
      canvas.drawLine(Offset(cx, cy), Offset(cx, cy + arm * dy), paint);
    }
    corner(l, t, 1, 1); corner(r, t, -1, 1);
    corner(l, b, 1, -1); corner(r, b, -1, -1);
    if (acquired) canvas.drawCircle(Offset(size.width / 2, size.height / 2), 2.5, Paint()..color = color);
  }
  @override
  bool shouldRepaint(_FocusSquarePainter old) => old.color != color || old.acquired != acquired;
}