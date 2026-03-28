// lib/features/ai/presentation/screens/scanner_screen.dart
//
// Discover tab — card scanner with live-cropping workflow.
//
// State machine (v5.2):
//   _ScannerState.live      — live camera feed
//   _ScannerState.adjusting — frozen still + live-cropping rect overlay
//                              Results sheet shows when _candidates is non-empty.
//                              Drag start dismisses the sheet; release re-processes.
//
// Camera lifecycle (fully self-contained):
//   Parent passes [isActive] — true when this tab is selected.
//   didUpdateWidget reacts to isActive changes to start/stop camera.
//   No public API — parent has zero knowledge of camera internals.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
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

enum _ScannerState {
  live,       // Camera feed active
  adjusting,  // Frozen still + rect overlay + optional results sheet
}

// ─────────────────────────────────────────────────────────────────────────────
// ScannerScreen
// ─────────────────────────────────────────────────────────────────────────────

class ScannerScreen extends StatefulWidget {
  final void Function(String id, RecordType type) onCardTap;
  final VoidCallback onBack;
  final void Function(bool visible) onNavBarVisibilityChanged;
  final bool isActive;

  const ScannerScreen({
    super.key,
    required this.onCardTap,
    required this.onBack,
    required this.onNavBarVisibilityChanged,
    required this.isActive,
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  // ── Camera
  CameraController? _controller;
  String? _cameraError;
  bool _initialising = false;
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

  // ── Captured image
  File? _capturedFile;
  Uint8List? _capturedImageBytes;

  // ── Processing
  bool _processing = false;

  // ── Results
  List<MatchCandidate> _candidates = [];

  // ── Adjustable rectangle overlay
  Rect _adjustRect = Rect.zero;
  bool _rectReady = false; // Prevents showing _defaultRect() flash
  int? _activeDragIndex;

  // ── Mode
  _DiscoverMode _mode = _DiscoverMode.scan;

  // ── Gallery
  final ImagePicker _imagePicker = ImagePicker();

  // ── Widget size (set on every build from LayoutBuilder)
  Size _widgetSize = Size.zero;

  // ── Live anchor dots
  List<Offset> _liveAnchorPoints = [];
  bool _liveOcrRunning = false;

  // ── Serialises all takePicture() calls
  bool _captureLock = false;

  // ── Tab-active gate (driven by widget.isActive via didUpdateWidget)
  bool _tabActive = false;

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
  void didUpdateWidget(covariant ScannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _tabActive = true;
      if (_controller == null && !_initialising) { _initCamera(); }
      else if (_state == _ScannerState.live) { _startLiveOcrStream(); }
    } else if (!widget.isActive && oldWidget.isActive) {
      _tabActive = false;
      _stopCamera();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (widget.isActive) {
        _tabActive = true;
        _initCamera();
      }
    }
  }

  void _stopCamera() {
    final ctrl = _controller;
    if (ctrl != null && ctrl.value.isInitialized) {
      ctrl.dispose();
      _controller = null;
    }
    if (mounted) { setState(() => _liveAnchorPoints = []); }
  }

  // ── Camera init ───────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    if (!_tabActive) { return; }
    if (mounted) { setState(() { _initialising = true; _cameraError = null; }); }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) { _setError('No cameras found.'); return; }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        back, ResolutionPreset.high,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();

      if (!_tabActive) {
        ctrl.dispose();
        if (mounted) { setState(() => _initialising = false); }
        return;
      }

      await ctrl.setFocusMode(FocusMode.auto);
      await ctrl.setExposureMode(ExposureMode.auto);
      // Flash stays off during preview/live-OCR. User's flash preference
      // is only applied momentarily during _scan() and tap-to-focus.
      await ctrl.setFlashMode(FlashMode.off);
      final minZ = await ctrl.getMinZoomLevel();
      final maxZ = await ctrl.getMaxZoomLevel();

      if (!mounted || !_tabActive) {
        ctrl.dispose();
        if (mounted) { setState(() => _initialising = false); }
        return;
      }

      setState(() {
        _controller = ctrl;
        _initialising = false;
        _minZoom = minZ;
        _maxZoom = maxZ.clamp(1.0, 8.0);
        _currentZoom = 1.0;
      });

      ScannerService.instance.warmup();
      _startLiveOcrStream();
    } catch (e) {
      _setError(e.toString());
    }
  }

  // ── Live OCR stream for anchor dots ──────────────────────────────────────

  void _startLiveOcrStream() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted || _state != _ScannerState.live || !_tabActive) {
        if (mounted) { setState(() => _liveAnchorPoints = []); }
        return false;
      }
      await _runLiveOcrPass();
      return mounted && _state == _ScannerState.live && _tabActive;
    });
  }

  Future<void> _runLiveOcrPass() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _liveOcrRunning) { return; }
    if (_state != _ScannerState.live || !_tabActive) { return; }
    if (_captureLock) { return; }

    _liveOcrRunning = true;
    _captureLock = true;
    try {
      final xFile = await ctrl.takePicture();

      if (!mounted || _state != _ScannerState.live || !_tabActive) {
        File(xFile.path).delete().ignore();
        return;
      }

      final recogniser = TextRecognizer(script: TextRecognitionScript.chinese);
      final inputImage = InputImage.fromFilePath(xFile.path);
      final recognised = await recogniser.processImage(inputImage);
      await recogniser.close();
      File(xFile.path).delete().ignore();

      if (!mounted || _state != _ScannerState.live || !_tabActive) { return; }

      final points = <Offset>[];
      for (final block in recognised.blocks) {
        final pts = block.cornerPoints;
        if (pts.length < 4) { continue; }
        final cx = pts.map((p) => p.x).reduce((a, b) => a + b) / pts.length;
        final cy = pts.map((p) => p.y).reduce((a, b) => a + b) / pts.length;
        points.add(Offset(cx.toDouble(), cy.toDouble()));
      }

      if (mounted) { setState(() => _liveAnchorPoints = points); }
    } catch (_) {
      // Silently ignore
    } finally {
      _captureLock = false;
      _liveOcrRunning = false;
    }
  }

  void _setError(String msg) {
    if (!mounted) { return; }
    setState(() { _cameraError = msg; _initialising = false; });
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CAPTURE → AUTO-EDGE → .adjusting
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _scan() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _processing) { return; }
    if (_state != _ScannerState.live) { return; }

    while (_captureLock) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted || _state != _ScannerState.live) { return; }
    }
    _captureLock = true;

    try {
      try { await ctrl.setFocusMode(FocusMode.locked); } catch (_) {}

      // Apply user's flash preference only for the shutter capture.
      await ctrl.setFlashMode(_flashModeToCamera(_flashMode));
      final xFile = await ctrl.takePicture();
      // Reset flash to off so live-OCR doesn't trigger it.
      ctrl.setFlashMode(FlashMode.off).ignore();
      _captureLock = false;

      final bytes = await File(xFile.path).readAsBytes();
      _capturedFile = File(xFile.path);
      _capturedImageBytes = bytes;

      if (!mounted) { return; }
      setState(() {
        _state = _ScannerState.adjusting;
        _processing = true;
        _candidates = [];
        _rectReady = false;
        _adjustRect = Rect.zero;
      });

      ctrl.setFocusMode(FocusMode.auto).ignore();

      final recogniser = TextRecognizer(script: TextRecognitionScript.chinese);
      final inputImage = InputImage.fromFilePath(xFile.path);
      final recognised = await recogniser.processImage(inputImage);
      await recogniser.close();

      if (!mounted) { return; }

      final autoRect = _estimateCardRect(recognised);

      setState(() {
        _processing = false;
        _adjustRect = autoRect;
        _rectReady = true;
      });

      _confirmAndWarp();
    } catch (e) {
      _captureLock = false;
      if (!mounted) { return; }
      setState(() { _processing = false; _capturedImageBytes = null; });
      _returnToLive();
      _showSnack('Scan failed: $e');
    }
  }

  Future<void> _scanFromGallery() async {
    if (_processing || _state != _ScannerState.live) { return; }

    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) { return; }

    final bytes = await picked.readAsBytes();
    _capturedImageBytes = bytes;

    if (!mounted) { return; }
    setState(() {
      _state = _ScannerState.adjusting;
      _processing = true;
      _candidates = [];
      _rectReady = false;
      _adjustRect = Rect.zero;
    });

    try {
      final recogniser = TextRecognizer(script: TextRecognitionScript.chinese);
      final inputImage = InputImage.fromFilePath(picked.path);
      final recognised = await recogniser.processImage(inputImage);
      await recogniser.close();

      if (!mounted) { return; }
      setState(() {
        _processing = false;
        _adjustRect = _estimateCardRect(recognised);
        _rectReady = true;
      });

      _confirmAndWarp();
    } catch (e) {
      if (!mounted) { return; }
      setState(() { _processing = false; _capturedImageBytes = null; });
      _returnToLive();
      _showSnack('Scan failed: $e');
    }
  }

  Rect _defaultRect() {
    final w = _widgetSize.width;
    final h = _widgetSize.height;
    return Rect.fromLTRB(w * 0.15, h * 0.075, w * 0.85, h * 0.925);
  }

  /// Estimates a full card bounding rectangle from OCR text blocks.
  /// SGS cards: ~0.63 W:H aspect ratio, text at bottom ~30%.
  Rect _estimateCardRect(RecognizedText recognised) {
    if (recognised.blocks.isEmpty) { return _defaultRect(); }

    double minX = double.infinity, minY = double.infinity;
    double maxX = 0, maxY = 0;
    for (final block in recognised.blocks) {
      for (final pt in block.cornerPoints) {
        if (pt.x < minX) { minX = pt.x.toDouble(); }
        if (pt.x > maxX) { maxX = pt.x.toDouble(); }
        if (pt.y < minY) { minY = pt.y.toDouble(); }
        if (pt.y > maxY) { maxY = pt.y.toDouble(); }
      }
    }

    final textW = maxX - minX;
    final textH = maxY - minY;
    if (textW < 50 || textH < 10) { return _defaultRect(); }

    const cardAspect = 0.63;
    final estimatedCardH = textW / cardAspect;
    final cardBottom = maxY + estimatedCardH * 0.03;
    final cardTop = cardBottom - estimatedCardH;
    final hPad = textW * 0.05;
    final cardLeft = minX - hPad;
    final cardRight = maxX + hPad;

    final bytes = _capturedImageBytes;
    if (bytes == null || _widgetSize == Size.zero) { return _defaultRect(); }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) { return _defaultRect(); }

    final bufW = decoded.width.toDouble();
    final bufH = decoded.height.toDouble();
    final wW = _widgetSize.width;
    final wH = _widgetSize.height;
    final scale = math.max(wW / bufW, wH / bufH);
    final cropX = (bufW * scale - wW) / 2.0;
    final cropY = (bufH * scale - wH) / 2.0;

    // Buffer → widget coordinate transform
    final wLeft   = (cardLeft * scale - cropX).clamp(0.0, wW);
    final wTop    = (cardTop * scale - cropY).clamp(0.0, wH);
    final wRight  = (cardRight * scale - cropX).clamp(0.0, wW);
    final wBottom = (cardBottom * scale - cropY).clamp(0.0, wH);

    return Rect.fromLTRB(wLeft, wTop, wRight, wBottom);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ADJUSTING → PERSPECTIVE WARP → FUSION
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _confirmAndWarp() async {
    final bytes = _capturedImageBytes;
    if (bytes == null || _processing) { return; }
    if (_state != _ScannerState.adjusting) { return; }

    setState(() { _processing = true; });

    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        _showSnack('Failed to decode image');
        setState(() { _processing = false; });
        return;
      }

      // ── Widget Rect → buffer pixel Rect (BoxFit.cover inverse) ─────────
      final bufW = decoded.width.toDouble();
      final bufH = decoded.height.toDouble();
      final wW = _widgetSize.width;
      final wH = _widgetSize.height;
      final scale = math.max(wW / bufW, wH / bufH);
      final cropX = (bufW * scale - wW) / 2.0;
      final cropY = (bufH * scale - wH) / 2.0;

      Offset widgetToBuf(double wx, double wy) {
        return Offset(
          ((wx + cropX) / scale).clamp(0, bufW),
          ((wy + cropY) / scale).clamp(0, bufH),
        );
      }

      // Convert the Rect's 4 corners to Offsets for PerspectiveWarper
      // (clockwise from top-left as required by warp()).
      final r = _adjustRect;
      final bufferCorners = [
        widgetToBuf(r.left, r.top),     // TL
        widgetToBuf(r.right, r.top),    // TR
        widgetToBuf(r.right, r.bottom), // BR
        widgetToBuf(r.left, r.bottom),  // BL
      ];

      final straightened = PerspectiveWarper.warp(decoded, bufferCorners);
      final straightenedJpeg = PerspectiveWarper.encodeJpeg(straightened);

      final tempDir = await Directory.systemTemp.createTemp('sha_warp_');
      final tempFile = File('${tempDir.path}/warped.jpg');
      await tempFile.writeAsBytes(straightenedJpeg);

      final recogniser = TextRecognizer(script: TextRecognitionScript.chinese);
      final inputImage = InputImage.fromFilePath(tempFile.path);
      final recognised = await recogniser.processImage(inputImage);
      await recogniser.close();

      final result = await ScannerService.instance.match(
        straightenedJpeg,
        recognisedText: recognised,
        source: ScanSource.straightened,
        straightenedImage: straightened,
      );

      tempFile.delete().ignore();
      tempDir.delete().ignore();

      if (!mounted) { return; }

      setState(() {
        _processing = false;
        _candidates = result.candidates;
      });

      if (result.candidates.isEmpty) {
        _showSnack('No match — adjust the crop and release');
      }
    } catch (e) {
      if (!mounted) { return; }
      setState(() { _processing = false; });
      _showSnack('Scan failed: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // STATE TRANSITIONS
  // ═════════════════════════════════════════════════════════════════════════

  void _returnToLive() {
    _deleteCapturedFile();
    _captureLock = false;
    _controller?.setFocusMode(FocusMode.auto).ignore();
    if (_currentZoom != 1.0) { _controller?.setZoomLevel(1.0).ignore(); }
    setState(() {
      _state = _ScannerState.live;
      _processing = false;
      _candidates = [];
      _capturedImageBytes = null;
      _currentZoom = 1.0;
      _adjustRect = Rect.zero;
      _rectReady = false;
      _activeDragIndex = null;
      _liveAnchorPoints = [];
    });
    if (_tabActive) { _startLiveOcrStream(); }
  }

  void _deleteCapturedFile() {
    final f = _capturedFile;
    if (f != null) {
      f.exists().then((exists) { if (exists) f.delete(); });
      _capturedFile = null;
    }
  }

  void _showSnack(String message) {
    if (!mounted) { return; }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2)),
    );
  }

  // ── Flash / Zoom / Focus ──────────────────────────────────────────────────

  Future<void> _cycleFlash() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) { return; }
    final next = switch (_flashMode) {
      _FlashMode.off  => _FlashMode.auto,
      _FlashMode.auto => _FlashMode.on,
      _FlashMode.on   => _FlashMode.off,
    };
    // Only update the UI indicator. The actual flash mode is applied
    // momentarily in _scan() and _onViewfinderTap() — not persistently.
    setState(() => _flashMode = next);
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
    if (ctrl == null || !ctrl.value.isInitialized || _state != _ScannerState.live) { return; }
    final newZoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
    if ((newZoom - _currentZoom).abs() < 0.01) { return; }
    setState(() => _currentZoom = newZoom);
    await ctrl.setZoomLevel(newZoom);
  }

  Future<void> _onViewfinderTap(TapDownDetails details, BoxConstraints box) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _state != _ScannerState.live) { return; }

    final widgetW = box.maxWidth;
    final widgetH = box.maxHeight;
    setState(() {
      _focusPoint = Offset(details.localPosition.dx / widgetW, details.localPosition.dy / widgetH);
      _focusAcquired = false;
    });

    try {
      // Flash assist for tap-to-focus: briefly enable flash if user has it on.
      final needsFlash = _flashMode != _FlashMode.off;
      if (needsFlash) {
        await ctrl.setFlashMode(_flashModeToCamera(_flashMode));
      }

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
      if (mounted) { setState(() => _focusAcquired = true); }

      // Turn flash back off after focus assist.
      if (needsFlash) {
        ctrl.setFlashMode(FlashMode.off).ignore();
      }

      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) { setState(() => _focusPoint = null); }
    } catch (_) {
      if (mounted) { setState(() => _focusPoint = null); }
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
      // Always block pop — scanner handles all back navigation internally.
      // Adjusting → _returnToLive(). Live → widget.onBack() (main.dart switches tab).
      // This prevents main.dart's outer PopScope from firing simultaneously.
      canPop: false,
      onPopInvokedWithResult: (_, _) {
        if (_state == _ScannerState.adjusting) {
          _returnToLive();
        } else {
          widget.onBack();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          _widgetSize = Size(constraints.maxWidth, constraints.maxHeight);
          final isAdj = _state == _ScannerState.adjusting;
          final hasResults = isAdj && _candidates.isNotEmpty;
          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Camera feed
              Positioned.fill(child: _buildLiveFeed()),

              // 2. Frozen still
              if (_capturedImageBytes != null && isAdj)
                Positioned.fill(
                  child: Image.memory(_capturedImageBytes!,
                    fit: BoxFit.cover, gaplessPlayback: true),
                ),

              // 3. Rect-handle overlay — only after OCR computes the real rect
              if (isAdj && _rectReady)
                Positioned.fill(
                  child: _RectHandleOverlay(
                    rect: _adjustRect,
                    activeIndex: _activeDragIndex,
                    widgetSize: _widgetSize,
                    processing: _processing,
                    onCornerDragStart: (index) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _activeDragIndex = index;
                        _candidates = []; // Dismiss results while re-cropping
                      });
                    },
                    onRectChanged: (newRect) {
                      setState(() { _adjustRect = newRect; });
                    },
                    onCornerDragEnd: () {
                      HapticFeedback.lightImpact();
                      setState(() { _activeDragIndex = null; });
                      _confirmAndWarp();
                    },
                  ),
                ),

              // 4. Top bar
              Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),

              // 5. Bottom controls
              if (_state == _ScannerState.live) _buildBottomControls(),

              // 6. Processing spinner (only before rect is ready)
              if (_processing && !_rectReady)
                const Positioned(
                  bottom: 120, left: 0, right: 0,
                  child: Center(child: SizedBox(width: 36, height: 36,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))),
                ),

              // 7. Results sheet — coexists with the rect overlay
              if (hasResults)
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

  Widget _buildTopBar() {
    final isAdj = _state == _ScannerState.adjusting;
    final hasResults = isAdj && _candidates.isNotEmpty;
    final String title;
    if (!isAdj) {
      title = 'Discover';
    } else if (_processing) {
      title = 'Matching…';
    } else if (hasResults) {
      title = 'Discover';
    } else {
      title = 'Drag corners to crop';
    }
    return SafeArea(
      child: SizedBox(
        height: 56,
        child: Stack(
          children: [
            Center(child: Text(
              title,
              style: TextStyle(color: Colors.white, fontSize: isAdj && !hasResults ? 15 : 17,
                  fontWeight: FontWeight.w600,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 8)]),
            )),
            Positioned(left: 4, top: 0, bottom: 0, child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                onPressed: () {
                  if (_state != _ScannerState.live) { _returnToLive(); }
                  else { widget.onBack(); }
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

  Widget _buildLiveFeed() {
    if (_initialising) {
      return const ColoredBox(color: Colors.black,
          child: Center(child: CircularProgressIndicator(color: Colors.white)));
    }
    if (_cameraError != null) {
      return _CameraError(error: _cameraError!, onRetry: _initCamera);
    }
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
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
              if (_state == _ScannerState.live && _liveAnchorPoints.isNotEmpty)
                RepaintBoundary(
                  child: _LiveAnchorDots(
                    bufferPoints: _liveAnchorPoints,
                    previewSize: ctrl.value.previewSize!,
                  ),
                ),
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
            setState(() => _mode = _DiscoverMode.search);
            widget.onNavBarVisibilityChanged(true);
          },
        )),
      ],
    ));
  }
}


// ═══════════════════════════════════════════════════════════════════════════════
// RECT-HANDLE OVERLAY
// Maintains a rectangular crop region with 4 draggable corner handles.
// The dimming layer uses saveLayer + BlendMode.clear so the inner rect is
// genuinely transparent — the frozen still image shows through it.
// ═══════════════════════════════════════════════════════════════════════════════

class _RectHandleOverlay extends StatelessWidget {
  final Rect rect;
  final int? activeIndex;
  final Size widgetSize;
  final bool processing;
  final void Function(int index) onCornerDragStart;
  final void Function(Rect newRect) onRectChanged;
  final VoidCallback onCornerDragEnd;

  static const _handleSize = 44.0;
  static const _minDim = 60.0;

  const _RectHandleOverlay({
    required this.rect,
    required this.activeIndex,
    required this.widgetSize,
    required this.processing,
    required this.onCornerDragStart,
    required this.onRectChanged,
    required this.onCornerDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    // Corner positions: 0=TL, 1=TR, 2=BR, 3=BL
    final corners = [
      Offset(rect.left, rect.top),
      Offset(rect.right, rect.top),
      Offset(rect.right, rect.bottom),
      Offset(rect.left, rect.bottom),
    ];

    return Stack(
      fit: StackFit.expand,
      children: [
        // Dimming layer with transparent hole — uses saveLayer so BlendMode.clear
        // actually punches through to whatever is behind this widget (the image).
        RepaintBoundary(
          child: CustomPaint(
            painter: _RectOverlayPainter(rect: rect),
            child: const SizedBox.expand(),
          ),
        ),

        // Processing indicator — centered inside the crop rect
        if (processing)
          Positioned(
            left: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height,
            child: const Center(
              child: _ProcessingBadge(),
            ),
          ),

        // Corner drag handles (disabled while processing)
        if (!processing)
          for (var i = 0; i < 4; i++)
            Positioned(
              left: corners[i].dx - _handleSize / 2,
              top: corners[i].dy - _handleSize / 2,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => onCornerDragStart(i),
                onPanUpdate: (d) => _onCornerDrag(i, d.delta),
                onPanEnd: (_) => onCornerDragEnd(),
                child: SizedBox(
                  width: _handleSize,
                  height: _handleSize,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: activeIndex == i ? 36 : 28,
                      height: activeIndex == i ? 36 : 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: activeIndex == i
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.88),
                        border: Border.all(
                          color: const Color(0xFF448AFF),
                          width: activeIndex == i ? 3.5 : 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: activeIndex == i ? 0.55 : 0.35),
                            blurRadius: activeIndex == i ? 12 : 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: activeIndex == i
                          ? const Icon(Icons.open_with, size: 16, color: Color(0xFF448AFF))
                          : null,
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }

  /// Each corner moves only the two edges it touches, keeping the shape
  /// rectangular. Minimum dimension enforced to prevent degenerate rects.
  void _onCornerDrag(int index, Offset delta) {
    double l = rect.left, t = rect.top, r = rect.right, b = rect.bottom;
    switch (index) {
      case 0: // TL
        l = (l + delta.dx).clamp(0, r - _minDim);
        t = (t + delta.dy).clamp(0, b - _minDim);
      case 1: // TR
        r = (r + delta.dx).clamp(l + _minDim, widgetSize.width);
        t = (t + delta.dy).clamp(0, b - _minDim);
      case 2: // BR
        r = (r + delta.dx).clamp(l + _minDim, widgetSize.width);
        b = (b + delta.dy).clamp(t + _minDim, widgetSize.height);
      case 3: // BL
        l = (l + delta.dx).clamp(0, r - _minDim);
        b = (b + delta.dy).clamp(t + _minDim, widgetSize.height);
    }
    onRectChanged(Rect.fromLTRB(l, t, r, b));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RectOverlayPainter
//
// Draws a semi-transparent scrim over the full canvas, then punches a
// transparent hole at [rect] so the image behind shows through clearly.
//
// The key fix vs the original: we wrap everything in saveLayer() so that
// BlendMode.clear operates against the layer's own alpha channel (which is
// initially transparent), rather than compositing straight to the screen
// (which would produce opaque black). After restore(), Flutter merges the
// layer — the hole remains transparent and the image shows through.
//
// Corner decorations (bracket-style L-shapes + rule-of-thirds grid lines)
// are drawn on top after the clear, so they appear over the image.
// ─────────────────────────────────────────────────────────────────────────────

class _RectOverlayPainter extends CustomPainter {
  final Rect rect;
  const _RectOverlayPainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    // ── 1. Save a layer covering the full canvas.
    //       BlendMode.clear only punches through within a layer.
    canvas.saveLayer(Offset.zero & size, Paint());

    // ── 2. Draw the scrim over the entire surface.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    // ── 3. Punch a transparent hole at the crop rect.
    //       BlendMode.clear replaces pixels with full transparency in the layer.
    canvas.drawRect(
      rect,
      Paint()..blendMode = BlendMode.clear,
    );

    // ── 4. Restore — the layer is composited; the hole is genuinely transparent.
    canvas.restore();

    // ── 5. Draw the blue border on top (over the image inside the hole).
    final borderPaint = Paint()
      ..color = const Color(0xFF448AFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(rect, borderPaint);

    // ── 6. Rule-of-thirds grid lines (subtle, inside the crop rect).
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 0.8;

    final thirdW = rect.width / 3;
    final thirdH = rect.height / 3;
    for (var i = 1; i <= 2; i++) {
      canvas.drawLine(
        Offset(rect.left + thirdW * i, rect.top),
        Offset(rect.left + thirdW * i, rect.bottom),
        gridPaint,
      );
      canvas.drawLine(
        Offset(rect.left, rect.top + thirdH * i),
        Offset(rect.right, rect.top + thirdH * i),
        gridPaint,
      );
    }

    // ── 7. Corner bracket decorations (L-shaped arms in the crop border colour).
    _drawCornerBrackets(canvas, rect);
  }

  void _drawCornerBrackets(Canvas canvas, Rect r) {
    const arm = 20.0;
    const thickness = 3.5;
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    // TL
    canvas.drawLine(Offset(r.left, r.top), Offset(r.left + arm, r.top), p);
    canvas.drawLine(Offset(r.left, r.top), Offset(r.left, r.top + arm), p);
    // TR
    canvas.drawLine(Offset(r.right, r.top), Offset(r.right - arm, r.top), p);
    canvas.drawLine(Offset(r.right, r.top), Offset(r.right, r.top + arm), p);
    // BR
    canvas.drawLine(Offset(r.right, r.bottom), Offset(r.right - arm, r.bottom), p);
    canvas.drawLine(Offset(r.right, r.bottom), Offset(r.right, r.bottom - arm), p);
    // BL
    canvas.drawLine(Offset(r.left, r.bottom), Offset(r.left + arm, r.bottom), p);
    canvas.drawLine(Offset(r.left, r.bottom), Offset(r.left, r.bottom - arm), p);
  }

  @override
  bool shouldRepaint(_RectOverlayPainter old) => old.rect != rect;
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROCESSING BADGE (shown inside crop rect while warp+match runs)
// ═══════════════════════════════════════════════════════════════════════════════

class _ProcessingBadge extends StatelessWidget {
  const _ProcessingBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Matching…',
            style: TextStyle(color: Colors.white, fontSize: 13,
                fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MODE PILL
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

// ═══════════════════════════════════════════════════════════════════════════════
// LIVE ANCHOR DOTS
// ═══════════════════════════════════════════════════════════════════════════════

class _LiveAnchorDots extends StatefulWidget {
  final List<Offset> bufferPoints;
  final Size previewSize;
  const _LiveAnchorDots({required this.bufferPoints, required this.previewSize});
  @override
  State<_LiveAnchorDots> createState() => _LiveAnchorDotsState();
}

class _LiveAnchorDotsState extends State<_LiveAnchorDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;
  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  }
  @override
  void dispose() { _shimmer.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) => CustomPaint(
        painter: _AnchorDotsPainter(bufferPoints: widget.bufferPoints,
            previewSize: widget.previewSize, shimmerValue: _shimmer.value),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _AnchorDotsPainter extends CustomPainter {
  final List<Offset> bufferPoints;
  final Size previewSize;
  final double shimmerValue;

  const _AnchorDotsPainter({required this.bufferPoints, required this.previewSize, required this.shimmerValue});

  @override
  void paint(Canvas canvas, Size size) {
    if (bufferPoints.isEmpty) { return; }
    final opacity = 0.15 + shimmerValue * 0.35;
    final dotPaint = Paint()..color = const Color(0xFFFFB300).withValues(alpha: opacity)..style = PaintingStyle.fill;
    final ringPaint = Paint()..color = const Color(0xFFFFB300).withValues(alpha: opacity * 0.6)..style = PaintingStyle.stroke..strokeWidth = 1.5;
    final bufW = previewSize.height; final bufH = previewSize.width;
    final widgetW = size.width; final widgetH = size.height;
    final scale = math.max(widgetW / bufW, widgetH / bufH);
    final cropX = (bufW * scale - widgetW) / 2.0;
    final cropY = (bufH * scale - widgetH) / 2.0;
    for (final bp in bufferPoints) {
      final wx = bp.dx * scale - cropX;
      final wy = bp.dy * scale - cropY;
      if (wx < -10 || wy < -10 || wx > widgetW + 10 || wy > widgetH + 10) { continue; }
      canvas.drawCircle(Offset(wx, wy), 6, dotPaint);
      canvas.drawCircle(Offset(wx, wy), 10, ringPaint);
    }
  }
  @override
  bool shouldRepaint(_AnchorDotsPainter old) =>
      old.shimmerValue != shimmerValue || old.bufferPoints != bufferPoints;
}

// ═══════════════════════════════════════════════════════════════════════════════
// UTILITY WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

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
    if (acquired) { canvas.drawCircle(Offset(size.width / 2, size.height / 2), 2.5, Paint()..color = color); }
  }
  @override
  bool shouldRepaint(_FocusSquarePainter old) => old.color != color || old.acquired != acquired;
}