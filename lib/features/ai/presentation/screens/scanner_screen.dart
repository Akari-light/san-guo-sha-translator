// lib/features/ai/presentation/screens/scanner_screen.dart
//
// Discover tab — card scanner with Interactive Region Selection (Pillar 6).
//
// Three explicit screen states (upgraded from two in v1.0):
//   _ScannerState.live      — live camera feed, shutter/gallery/mode pill
//   _ScannerState.reviewing — frozen still + OCR overlay + ScannerResultsSheet
//   _ScannerState.selecting — frozen still dimmed + region selection overlay
//
// State transitions:
//   live → reviewing         (shutter press or gallery pick)
//   reviewing → selecting    ("Select Region" from results sheet)
//   selecting → reviewing    ("Re-scan" on selected region)
//   selecting → reviewing    (back press — restore original results)
//   reviewing → live         (back press or tap-dismiss)
//
// Pillar 6 Coordinate Transformation (spec §4 Pillar 6.3):
//
//   The frozen preview uses Image.memory(..., fit: BoxFit.cover) which scales
//   the camera buffer to fill the widget and crops the overflow. The user
//   draws a Rect in widget coordinates; we must transform it to buffer pixel
//   coordinates before cropping.
//
//   GIVEN:
//     buffer_w, buffer_h  = raw JPEG dimensions
//     widget_w, widget_h  = LayoutBuilder constraints
//     user_rect           = Rect drawn by user (widget coords)
//
//   STEP 1: BoxFit.cover inverse
//     scale = max(widget_w/buffer_w, widget_h/buffer_h)
//     rendered_w = buffer_w * scale
//     rendered_h = buffer_h * scale
//     crop_x = (rendered_w - widget_w) / 2   (horizontal overflow)
//     crop_y = (rendered_h - widget_h) / 2   (vertical overflow)
//
//   STEP 2: Widget → rendered-image coordinates
//     rendered_rect = user_rect.translate(crop_x, crop_y)
//
//   STEP 3: Rendered-image → buffer pixel coordinates
//     buffer_rect = Rect(
//       rendered_rect.left / scale,
//       rendered_rect.top / scale,
//       rendered_rect.right / scale,
//       rendered_rect.bottom / scale,
//     ).clamped to buffer dimensions
//
// Architecture:
//   - No feature/* presentation imports — navigation via onCardTap / onBack
//   - Search mode delegated to DiscoverSearchScreen
//   - onNavBarVisibilityChanged: false in scan mode, true in search mode

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/recently_viewed_service.dart';
import '../../../../core/services/scanner_service.dart';
import 'discover_search_screen.dart';
import 'scanner_results_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

enum _FlashMode { off, auto, on }

enum _DiscoverMode { scan, search }

/// Three explicit scanner screen states (v2.0 — added [selecting]).
enum _ScannerState {
  /// Live camera feed is active. Shutter/gallery/mode controls visible.
  live,

  /// Frozen still is showing, OCR running or complete, results sheet visible.
  reviewing,

  /// Frozen still dimmed. User is drawing a selection rectangle to isolate
  /// a single card in a multi-card frame. Re-scan button visible.
  selecting,
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

// Public — main.dart accesses resetSession() via GlobalKey<ScannerScreenState>.
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

  /// True when the scanner is in reviewing OR selecting state.
  /// Read by main.dart's outer PopScope to skip tab navigation while the
  /// scanner is handling the back press internally.
  bool get isReviewing =>
      _state == _ScannerState.reviewing || _state == _ScannerState.selecting;

  // ── Captured still — set before any setState to prevent blank frame
  File? _capturedFile;
  Uint8List? _capturedImageBytes;

  // ── Processing flag — true while OCR/matching is running
  bool _processing = false;

  // ── Results
  List<MatchCandidate> _candidates = [];
  List<TextBlock> _ocrBlocks = [];

  // ── Region selection (Pillar 6)
  Rect? _selectionRect;           // in widget coordinates
  Offset? _selectionStart;        // drag start point
  bool _regionScanProcessing = false;

  // ── Preserved results — original results before region re-scan
  List<MatchCandidate>? _originalCandidates;

  // ── Mode
  _DiscoverMode _mode = _DiscoverMode.scan;

  // ── Gallery picker
  final ImagePicker _imagePicker = ImagePicker();

  // ── Widget size cache (set by LayoutBuilder, used by coordinate transform)
  Size _widgetSize = Size.zero;

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
    setState(() {
      _initialising = true;
      _cameraError = null;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) { _setError('No cameras found.'); return; }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        back,
        ResolutionPreset.high, // high not max — reduces takePicture() latency
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
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
    } catch (e) {
      _setError(e.toString());
    }
  }

  void _setError(String msg) {
    if (!mounted) return;
    setState(() { _cameraError = msg; _initialising = false; });
  }

  // ── Scan (full frame) ────────────────────────────────────────────────────

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
        _state = _ScannerState.reviewing;
        _processing = true;
        _candidates = [];
        _ocrBlocks = [];
        _originalCandidates = null;
        _selectionRect = null;
      });

      ctrl.setFocusMode(FocusMode.auto).ignore();

      final recogniser = TextRecognizer(script: TextRecognitionScript.chinese);
      final inputImage = InputImage.fromFilePath(xFile.path);
      final recognised = await recogniser.processImage(inputImage);
      await recogniser.close();

      final result = await ScannerService.instance.match(
        bytes,
        recognisedText: recognised,
        source: ScanSource.camera,
      );

      if (!mounted) return;
      setState(() {
        _processing = false;
        _ocrBlocks = recognised.blocks;
        _candidates = result.candidates;
      });

      if (result.candidates.isEmpty) {
        _showSnack('Card not recognised — try again');
        _returnToLive();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _processing = false; _capturedImageBytes = null; });
      _returnToLive();
      _showSnack('Scan failed: $e');
    }
  }

  // ── Scan from gallery ─────────────────────────────────────────────────────

  Future<void> _scanFromGallery() async {
    if (_processing || _state != _ScannerState.live) return;

    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    _capturedImageBytes = bytes;

    if (!mounted) return;
    setState(() {
      _state = _ScannerState.reviewing;
      _processing = true;
      _candidates = [];
      _ocrBlocks = [];
      _originalCandidates = null;
      _selectionRect = null;
    });

    try {
      final recogniser = TextRecognizer(script: TextRecognitionScript.chinese);
      final inputImage = InputImage.fromFilePath(picked.path);
      final recognised = await recogniser.processImage(inputImage);
      await recogniser.close();

      final result = await ScannerService.instance.match(
        bytes,
        recognisedText: recognised,
        source: ScanSource.gallery,
      );

      if (!mounted) return;
      setState(() {
        _processing = false;
        _ocrBlocks = recognised.blocks;
        _candidates = result.candidates;
      });

      if (result.candidates.isEmpty) {
        _showSnack('Card not recognised — try again');
        _returnToLive();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _processing = false; _capturedImageBytes = null; });
      _returnToLive();
      _showSnack('Scan failed: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // PILLAR 6 — INTERACTIVE REGION SELECTION
  // ═════════════════════════════════════════════════════════════════════════

  /// Enters region selection mode. Called from the results sheet's
  /// "Select Region" button.
  void _enterSelectionMode() {
    _originalCandidates ??= List.of(_candidates);
    setState(() {
      _state = _ScannerState.selecting;
      _selectionRect = null;
      _selectionStart = null;
    });
  }

  /// Exits region selection without re-scanning. Restores original results.
  void _exitSelectionMode() {
    setState(() {
      _state = _ScannerState.reviewing;
      _selectionRect = null;
      _selectionStart = null;
      if (_originalCandidates != null) {
        _candidates = _originalCandidates!;
      }
    });
  }

  /// Handles pan start for drawing the selection rectangle.
  void _onSelectionPanStart(DragStartDetails details) {
    setState(() {
      _selectionStart = details.localPosition;
      _selectionRect = Rect.fromPoints(
        details.localPosition,
        details.localPosition,
      );
    });
  }

  /// Handles pan update — expands the selection rectangle.
  void _onSelectionPanUpdate(DragUpdateDetails details) {
    if (_selectionStart == null) return;
    setState(() {
      _selectionRect = Rect.fromPoints(
        _selectionStart!,
        details.localPosition,
      );
    });
  }

  /// Re-scans using only the selected region.
  ///
  /// This is the core Pillar 6 flow:
  ///   1. Transform widget Rect → buffer pixel Rect
  ///   2. Crop the JPEG buffer to the selected region
  ///   3. Re-run MLKit OCR on the cropped image
  ///   4. Pass cropped bytes + new OCR to ScannerService.match()
  ///   5. Update results
  Future<void> _rescanSelectedRegion() async {
    final bytes = _capturedImageBytes;
    final rect = _selectionRect;
    if (bytes == null || rect == null || _regionScanProcessing) return;

    // Minimum selection size — prevent accidental tiny taps
    if (rect.width < 40 || rect.height < 40) {
      _showSnack('Selection too small — draw a larger rectangle');
      return;
    }

    setState(() { _regionScanProcessing = true; });

    try {
      // ── Step 1: Decode to get buffer dimensions ──────────────────────
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        _showSnack('Failed to decode image');
        setState(() { _regionScanProcessing = false; });
        return;
      }

      final bufferW = decoded.width.toDouble();
      final bufferH = decoded.height.toDouble();
      final widgetW = _widgetSize.width;
      final widgetH = _widgetSize.height;

      if (widgetW <= 0 || widgetH <= 0) {
        setState(() { _regionScanProcessing = false; });
        return;
      }

      // ── Step 2: BoxFit.cover inverse transform ───────────────────────
      //
      // BoxFit.cover scales the buffer to FILL the widget, then crops
      // the overflow. We reverse this to map widget coords back to
      // buffer pixel coords.
      //
      // scale = whichever axis needs more scaling to fill
      // rendered = buffer × scale (one axis matches widget, other overflows)
      // crop = (rendered - widget) / 2 (symmetric overflow on both sides)

      final scale = math.max(widgetW / bufferW, widgetH / bufferH);
      final renderedW = bufferW * scale;
      final renderedH = bufferH * scale;
      final cropX = (renderedW - widgetW) / 2.0;
      final cropY = (renderedH - widgetH) / 2.0;

      // ── Step 3: Widget rect → buffer rect ────────────────────────────
      //
      // Add the crop offset (translates from the visible widget origin to
      // the rendered-image origin), then divide by scale to get buffer px.

      final bLeft   = ((rect.left   + cropX) / scale).round().clamp(0, decoded.width);
      final bTop    = ((rect.top    + cropY) / scale).round().clamp(0, decoded.height);
      final bRight  = ((rect.right  + cropX) / scale).round().clamp(0, decoded.width);
      final bBottom = ((rect.bottom + cropY) / scale).round().clamp(0, decoded.height);

      final bWidth  = bRight - bLeft;
      final bHeight = bBottom - bTop;

      if (bWidth < 20 || bHeight < 20) {
        _showSnack('Selected region too small after transform');
        setState(() { _regionScanProcessing = false; });
        return;
      }

      // ── Step 4: Crop the buffer ──────────────────────────────────────
      final cropped = img.copyCrop(
        decoded,
        x: bLeft,
        y: bTop,
        width: bWidth,
        height: bHeight,
      );
      final croppedJpeg = Uint8List.fromList(img.encodeJpg(cropped, quality: 90));

      // ── Step 5: Write temp file for MLKit (requires file path) ───────
      final tempDir = await Directory.systemTemp.createTemp('sha_crop_');
      final tempFile = File('${tempDir.path}/crop.jpg');
      await tempFile.writeAsBytes(croppedJpeg);

      // ── Step 6: Re-run OCR on cropped region ─────────────────────────
      final recogniser = TextRecognizer(script: TextRecognitionScript.chinese);
      final inputImage = InputImage.fromFilePath(tempFile.path);
      final recognised = await recogniser.processImage(inputImage);
      await recogniser.close();

      // ── Step 7: Run fusion pipeline with userCrop source ─────────────
      final result = await ScannerService.instance.match(
        croppedJpeg,
        recognisedText: recognised,
        source: ScanSource.userCrop,
      );

      // Clean up temp file
      tempFile.delete().ignore();
      tempDir.delete().ignore();

      if (!mounted) return;
      setState(() {
        _regionScanProcessing = false;
        _state = _ScannerState.reviewing;
        _candidates = result.candidates;
        // Keep _ocrBlocks from original scan for overlay consistency
      });

      if (result.candidates.isEmpty) {
        _showSnack('No match in selected region — try a different area');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _regionScanProcessing = false; });
      _showSnack('Region scan failed: $e');
    }
  }

  // ── State transitions ─────────────────────────────────────────────────────

  void _returnToLive() {
    _deleteCapturedFile();
    _controller?.setFocusMode(FocusMode.auto).ignore();
    if (_currentZoom != 1.0) {
      _controller?.setZoomLevel(1.0).ignore();
    }
    setState(() {
      _state = _ScannerState.live;
      _processing = false;
      _candidates = [];
      _ocrBlocks = [];
      _capturedImageBytes = null;
      _currentZoom = 1.0;
      _selectionRect = null;
      _selectionStart = null;
      _originalCandidates = null;
      _regionScanProcessing = false;
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
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Flash ─────────────────────────────────────────────────────────────────

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

  // ── Pinch-to-zoom ─────────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails _) { _baseZoom = _currentZoom; }

  Future<void> _onScaleUpdate(ScaleUpdateDetails details) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _state != _ScannerState.live) return;
    final newZoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
    if ((newZoom - _currentZoom).abs() < 0.01) return;
    setState(() => _currentZoom = newZoom);
    await ctrl.setZoomLevel(newZoom);
  }

  // ── Tap-to-focus ──────────────────────────────────────────────────────────

  Future<void> _onViewfinderTap(TapDownDetails details, BoxConstraints box) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _state != _ScannerState.live) return;

    final widgetW = box.maxWidth;
    final widgetH = box.maxHeight;
    final widgetNorm = Offset(details.localPosition.dx / widgetW, details.localPosition.dy / widgetH);

    setState(() { _focusPoint = widgetNorm; _focusAcquired = false; });

    try {
      final previewSize = ctrl.value.previewSize!;
      final sensorW = previewSize.height;
      final sensorH = previewSize.width;
      final widgetAspect = widgetW / widgetH;
      final sensorAspect = sensorW / sensorH;

      double sensorX, sensorY;
      if (sensorAspect > widgetAspect) {
        final scale = widgetH / sensorH;
        final rendered = sensorW * scale;
        final cropLeft = (rendered - widgetW) / 2.0;
        sensorX = (details.localPosition.dx + cropLeft) / rendered;
        sensorY = details.localPosition.dy / widgetH;
      } else {
        final scale = widgetW / sensorW;
        final rendered = sensorH * scale;
        final cropTop = (rendered - widgetH) / 2.0;
        sensorX = details.localPosition.dx / widgetW;
        sensorY = (details.localPosition.dy + cropTop) / rendered;
      }

      final sensorOffset = Offset(sensorX.clamp(0.0, 1.0), sensorY.clamp(0.0, 1.0));
      await ctrl.setFocusPoint(sensorOffset);
      await ctrl.setExposurePoint(sensorOffset);

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

  // ── Scan mode ─────────────────────────────────────────────────────────────

  Widget _buildScanMode() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) {
        if (_state == _ScannerState.selecting) {
          _exitSelectionMode();
        } else if (_state == _ScannerState.reviewing) {
          _returnToLive();
        } else {
          widget.onBack();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Cache widget size for Pillar 6 coordinate transform
          _widgetSize = Size(constraints.maxWidth, constraints.maxHeight);

          return Stack(
            fit: StackFit.expand,
            children: [
              // ── 1. Camera feed (always present as base layer) ─────────
              Positioned.fill(child: _buildLiveFeed()),

              // ── 2. Frozen still — shown in reviewing/selecting ────────
              if (_capturedImageBytes != null)
                Positioned.fill(
                  child: Image.memory(
                    _capturedImageBytes!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),

              // ── 3. Dim overlay for selecting state ────────────────────
              if (_state == _ScannerState.selecting)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),

              // ── 4. OCR highlight overlay ──────────────────────────────
              if (_state == _ScannerState.reviewing && _ocrBlocks.isNotEmpty)
                Positioned.fill(child: _OcrHighlightOverlay(blocks: _ocrBlocks)),

              // ── 5. Region selection overlay (Pillar 6) ────────────────
              if (_state == _ScannerState.selecting)
                Positioned.fill(
                  child: _RegionSelectionOverlay(
                    selectionRect:   _selectionRect,
                    capturedBytes:   _capturedImageBytes,
                    onPanStart:      _onSelectionPanStart,
                    onPanUpdate:     _onSelectionPanUpdate,
                    onPanEnd:        (_) {}, // rect stays after finger lifts
                    onRescan:        _selectionRect != null ? () => _rescanSelectedRegion() : null,
                    onCancel:        _exitSelectionMode,
                    isProcessing:    _regionScanProcessing,
                  ),
                ),

              // ── 6. Top bar ────────────────────────────────────────────
              Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),

              // ── 7. Bottom controls (live state only) ──────────────────
              if (_state == _ScannerState.live)
                _buildBottomControls(),

              // ── 8. Processing spinner ─────────────────────────────────
              if (_state == _ScannerState.reviewing && _processing)
                const Positioned(
                  bottom: 120,
                  left: 0, right: 0,
                  child: Center(
                    child: SizedBox(
                      width: 36, height: 36,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                ),

              // ── 9. Results sheet ──────────────────────────────────────
              if (_state == _ScannerState.reviewing && _candidates.isNotEmpty)
                Positioned.fill(
                  child: ScannerResultsSheet(
                    candidates: _candidates,
                    onSelect: (c) {
                      _returnToLive();
                      widget.onCardTap(c.cardId, c.recordType);
                    },
                    onDismiss: _returnToLive,
                    onSelectRegion: _enterSelectionMode,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final isSelecting = _state == _ScannerState.selecting;
    return SafeArea(
      child: SizedBox(
        height: 56,
        child: Stack(
          children: [
            // Centred title
            Center(
              child: Text(
                isSelecting ? 'Select Card Region' : 'Discover',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isSelecting ? 15 : 17,
                  fontWeight: FontWeight.w600,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
                ),
              ),
            ),
            // Left icons
            Positioned(
              left: 4, top: 0, bottom: 0,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                    onPressed: () {
                      if (_state == _ScannerState.selecting) {
                        _exitSelectionMode();
                      } else if (_state == _ScannerState.reviewing) {
                        _returnToLive();
                      } else {
                        widget.onBack();
                      }
                    },
                  ),
                  if (_state == _ScannerState.live)
                    IconButton(
                      icon: Icon(_flashIcon(), color: Colors.white, size: 22),
                      onPressed: () => _cycleFlash(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Live camera feed ──────────────────────────────────────────────────────

  Widget _buildLiveFeed() {
    if (_initialising) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (_cameraError != null) {
      return _CameraError(error: _cameraError!, onRetry: _initCamera);
    }

    final ctrl = _controller;
    if (ctrl == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onTapDown: _state != _ScannerState.live
                ? null
                : (d) => _onViewfinderTap(d, constraints),
            child: GestureDetector(
              onScaleStart: _state != _ScannerState.live ? null : _onScaleStart,
              onScaleUpdate: _state != _ScannerState.live ? null : _onScaleUpdate,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: ctrl.value.previewSize!.height,
                          height: ctrl.value.previewSize!.width,
                          child: CameraPreview(ctrl),
                        ),
                      ),
                    ),
                  ),
                  if (_focusPoint != null)
                    _FocusSquare(position: _focusPoint!, acquired: _focusAcquired),
                  if (_currentZoom > _minZoom + 0.15)
                    Positioned(
                      top: 12, right: 12,
                      child: _ZoomBadge(zoom: _currentZoom),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Bottom controls (live state only) ────────────────────────────────────

  Widget _buildBottomControls() {
    final ready = _controller?.value.isInitialized == true && !_processing;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Gallery
                GestureDetector(
                  onTap: ready ? () => _scanFromGallery() : null,
                  child: Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white30, width: 1.5),
                    ),
                    child: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 24),
                  ),
                ),

                const SizedBox(width: 40),

                // Shutter
                GestureDetector(
                  onTap: ready ? _scan : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ready ? Colors.white : Colors.white30,
                      border: Border.all(
                        color: ready ? Colors.white60 : Colors.white12,
                        width: 4,
                      ),
                      boxShadow: ready ? [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.25),
                          blurRadius: 16, spreadRadius: 2,
                        )
                      ] : [],
                    ),
                    child: const Icon(
                      Icons.document_scanner,
                      color: Colors.black87,
                      size: 30,
                    ),
                  ),
                ),

                const SizedBox(width: 40),

                // Mirror spacer keeps shutter centred
                const SizedBox(width: 52, height: 52),
              ],
            ),
          ),

          // Mode pill
          Padding(
            padding: EdgeInsets.only(bottom: bottom + 8),
            child: _ModePill(
              onSwitchToSearch: () {
                _returnToLive();
                setState(() => _mode = _DiscoverMode.scan);
                widget.onNavBarVisibilityChanged(true);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PILLAR 6 — REGION SELECTION OVERLAY
// ═══════════════════════════════════════════════════════════════════════════════
//
// Displays:
//   • A GestureDetector surface for drawing a selection rectangle
//   • The selected region rendered via CustomPainter (bright cutout in dim bg)
//   • A floating action bar with "Re-scan" and "Cancel" buttons
//   • A processing spinner during region re-scan

class _RegionSelectionOverlay extends StatelessWidget {
  final Rect? selectionRect;
  final Uint8List? capturedBytes;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;
  final VoidCallback? onRescan;
  final VoidCallback onCancel;
  final bool isProcessing;

  const _RegionSelectionOverlay({
    required this.selectionRect,
    required this.capturedBytes,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onRescan,
    required this.onCancel,
    required this.isProcessing,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Draw surface ──────────────────────────────────────────────
        GestureDetector(
          onPanStart: onPanStart,
          onPanUpdate: onPanUpdate,
          onPanEnd: onPanEnd,
          behavior: HitTestBehavior.opaque,
          child: CustomPaint(
            painter: _RegionSelectionPainter(selectionRect: selectionRect),
            child: const SizedBox.expand(),
          ),
        ),

        // ── Instruction text ──────────────────────────────────────────
        if (selectionRect == null)
          const Positioned(
            left: 40, right: 40,
            bottom: 140,
            child: Text(
              'Draw a rectangle around the card you want to scan',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
              ),
            ),
          ),

        // ── Action buttons ────────────────────────────────────────────
        if (selectionRect != null)
          Positioned(
            left: 0, right: 0, bottom: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Cancel
                _SelectionActionButton(
                  icon: Icons.close,
                  label: 'Cancel',
                  onTap: onCancel,
                  isPrimary: false,
                ),
                const SizedBox(width: 24),
                // Re-scan
                if (isProcessing)
                  const SizedBox(
                    width: 48, height: 48,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                else
                  _SelectionActionButton(
                    icon: Icons.crop_free,
                    label: 'Re-scan',
                    onTap: onRescan,
                    isPrimary: true,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Region selection painter — renders the dragged rectangle as a bright cutout
// ─────────────────────────────────────────────────────────────────────────────

class _RegionSelectionPainter extends CustomPainter {
  final Rect? selectionRect;
  const _RegionSelectionPainter({required this.selectionRect});

  @override
  void paint(Canvas canvas, Size size) {
    if (selectionRect == null) return;

    final rect = selectionRect!;

    // Bright cutout: clear the dim overlay inside the selection rect
    // by painting the selected region with a white semi-transparent fill.
    final cutoutPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, cutoutPaint);

    // Border: animated-feel dashed border approximation via solid + corners
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(rect, borderPaint);

    // Corner brackets — visual affordance showing the selection corners
    const arm = 18.0;
    final cornerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    void drawCorner(double cx, double cy, double dx, double dy) {
      canvas.drawLine(Offset(cx, cy), Offset(cx + arm * dx, cy), cornerPaint);
      canvas.drawLine(Offset(cx, cy), Offset(cx, cy + arm * dy), cornerPaint);
    }

    drawCorner(rect.left,  rect.top,     1,  1);
    drawCorner(rect.right, rect.top,    -1,  1);
    drawCorner(rect.left,  rect.bottom,  1, -1);
    drawCorner(rect.right, rect.bottom, -1, -1);
  }

  @override
  bool shouldRepaint(_RegionSelectionPainter old) =>
      old.selectionRect != selectionRect;
}

// ─────────────────────────────────────────────────────────────────────────────
// Selection action button
// ─────────────────────────────────────────────────────────────────────────────

class _SelectionActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isPrimary;

  const _SelectionActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isPrimary ? Colors.white : Colors.black54,
          borderRadius: BorderRadius.circular(28),
          border: isPrimary ? null : Border.all(color: Colors.white30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isPrimary ? Colors.black87 : Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isPrimary ? Colors.black87 : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXISTING WIDGETS (unchanged from v1.0)
// ═══════════════════════════════════════════════════════════════════════════════

// ── Mode pill ───────────────────────────────────────────────────────────────

class _ModePill extends StatelessWidget {
  final VoidCallback onSwitchToSearch;
  const _ModePill({required this.onSwitchToSearch});

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
          _PillItem(icon: Icons.document_scanner_outlined, label: 'Scan Card', selected: true,  onTap: () {}),
          _PillItem(icon: Icons.search,                    label: 'Search',    selected: false, onTap: onSwitchToSearch),
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
  const _PillItem({required this.icon, required this.label, required this.selected, required this.onTap});

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
            Icon(icon, size: 16, color: selected ? Colors.black87 : Colors.white70),
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

// ── OCR highlight overlay ───────────────────────────────────────────────────

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
    final fillPaint   = Paint()..color = const Color(0xFFFFB300).withValues(alpha: 0.22)..style = PaintingStyle.fill;
    final strokePaint = Paint()..color = const Color(0xFFFFB300).withValues(alpha: 0.75)..style = PaintingStyle.stroke..strokeWidth = 1.5;

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

// ── Camera error widget ─────────────────────────────────────────────────────

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
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
              const SizedBox(height: 8),
              Text(error, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Zoom badge ──────────────────────────────────────────────────────────────

class _ZoomBadge extends StatelessWidget {
  final double zoom;
  const _ZoomBadge({required this.zoom});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
      child: Text('${zoom.toStringAsFixed(1)}×',
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }
}

// ── Focus square ────────────────────────────────────────────────────────────

class _FocusSquare extends StatefulWidget {
  final Offset position;
  final bool acquired;
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
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const size = 72.0;
        final px = (widget.position.dx * constraints.maxWidth).clamp(size / 2, constraints.maxWidth  - size / 2);
        final py = (widget.position.dy * constraints.maxHeight).clamp(size / 2, constraints.maxHeight - size / 2);
        final color = widget.acquired ? Colors.white : const Color(0xFFFFB300);
        return FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Stack(children: [
              Positioned(
                left: px - size / 2, top: py - size / 2,
                child: CustomPaint(
                  size: const Size(size, size),
                  painter: _FocusSquarePainter(color: color, acquired: widget.acquired),
                ),
              ),
            ]),
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
    final paint = Paint()..color = color..strokeWidth = 1.8..style = PaintingStyle.stroke;
    const arm = 14.0;
    final l = 0.0, t = 0.0, r = size.width, b = size.height;

    void corner(double cx, double cy, double dx, double dy) {
      canvas.drawLine(Offset(cx, cy), Offset(cx + arm * dx, cy), paint);
      canvas.drawLine(Offset(cx, cy), Offset(cx, cy + arm * dy), paint);
    }
    corner(l, t,  1,  1); corner(r, t, -1,  1);
    corner(l, b,  1, -1); corner(r, b, -1, -1);
    if (acquired) canvas.drawCircle(Offset(size.width / 2, size.height / 2), 2.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_FocusSquarePainter old) => old.color != color || old.acquired != acquired;
}