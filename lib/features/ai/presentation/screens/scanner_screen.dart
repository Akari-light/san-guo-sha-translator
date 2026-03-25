// lib/features/ai/presentation/screens/scanner_screen.dart
//
// Discover tab — card scanner only.
// Search mode has been extracted to discover_search_screen.dart.
//
// Two explicit screen states:
//   _ScannerState.live      — live camera feed, shutter/gallery/mode pill visible
//   _ScannerState.reviewing — frozen still + OCR overlay + ScannerResultsSheet
//
// Pressing the shutter transitions live → reviewing.
// Pressing back (hardware or back arrow) in reviewing transitions back → live.
// Pressing back in live calls onBack (returns to previous tab).
//
// Top bar (scan mode only, no AppBar):
//   ← (back)   ✗ (flash)   Discover   [spacer to balance left icons]
//   Mirrors Google Lens layout exactly.
//
// Architecture:
//   - No feature/* presentation imports — navigation via onCardTap / onBack
//   - Search mode delegated to DiscoverSearchScreen
//   - onNavBarVisibilityChanged: false in scan mode, true in search mode

import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
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

/// The two explicit scanner screen states.
enum _ScannerState {
  /// Live camera feed is active. Shutter/gallery/mode controls visible.
  live,

  /// Frozen still is showing, OCR running or complete, results sheet visible.
  reviewing,
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

  // ── Screen state (the two explicit states)
  _ScannerState _state = _ScannerState.live;

  /// True when the scanner is showing a frozen still + results sheet.
  /// Read by main.dart's outer PopScope to skip tab navigation while the
  /// scanner is handling the back press internally.
  bool get isReviewing => _state == _ScannerState.reviewing;

  // ── Captured still — set before any setState to prevent blank frame
  File? _capturedFile;
  Uint8List? _capturedImageBytes;

  // ── Processing flag — true while OCR/matching is running in reviewing state
  bool _processing = false;

  // ── Results
  List<MatchCandidate> _candidates = [];
  List<TextBlock> _ocrBlocks = [];

  // ── Mode
  _DiscoverMode _mode = _DiscoverMode.scan;

  // ── Gallery picker
  final ImagePicker _imagePicker = ImagePicker();

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

  // ── Scan ──────────────────────────────────────────────────────────────────

  Future<void> _scan() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _processing) return;
    if (_state != _ScannerState.live) return;

    try {
      try { await ctrl.setFocusMode(FocusMode.locked); } catch (_) {}

      final xFile = await ctrl.takePicture();
      final bytes = await File(xFile.path).readAsBytes();

      // ── Critical: assign bytes BEFORE setState so the widget tree already
      // has the image data when it first rebuilds for the reviewing state.
      // This prevents any intermediate blank/black frame.
      _capturedFile = File(xFile.path);
      _capturedImageBytes = bytes;

      // Single setState: live → reviewing. The frozen image is already loaded.
      if (!mounted) return;
      setState(() {
        _state = _ScannerState.reviewing;
        _processing = true;
        _candidates = [];
        _ocrBlocks = [];
      });

      ctrl.setFocusMode(FocusMode.auto).ignore();

      // OCR + matching run in the background while the frozen image is shown
      final recogniser = TextRecognizer(script: TextRecognitionScript.chinese);
      final inputImage = InputImage.fromFilePath(xFile.path);
      final recognised = await recogniser.processImage(inputImage);
      await recogniser.close();

      final result = await ScannerService.instance.match(
        bytes,
        recognisedText: recognised,
      );

      if (!mounted) return;
      setState(() {
        _processing = false;
        _ocrBlocks = recognised.blocks;
        _candidates = result.candidates;
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
        _returnToLive();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _processing = false; _capturedImageBytes = null; });
      _returnToLive();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan failed: $e'), behavior: SnackBarBehavior.floating),
      );
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
    });

    try {
      final recogniser = TextRecognizer(script: TextRecognitionScript.chinese);
      final inputImage = InputImage.fromFilePath(picked.path);
      final recognised = await recogniser.processImage(inputImage);
      await recogniser.close();

      final result = await ScannerService.instance.match(bytes, recognisedText: recognised);

      if (!mounted) return;
      setState(() {
        _processing = false;
        _ocrBlocks = recognised.blocks;
        _candidates = result.candidates;
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
        _returnToLive();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _processing = false; _capturedImageBytes = null; });
      _returnToLive();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan failed: $e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  // ── State transitions ─────────────────────────────────────────────────────

  /// reviewing → live. Discards captured image and resumes live feed.
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
    });
  }

  void _deleteCapturedFile() {
    final f = _capturedFile;
    if (f != null) {
      f.exists().then((exists) { if (exists) f.delete(); });
      _capturedFile = null;
    }
  }

  /// Called by main.dart via GlobalKey on tab re-entry.
  void resetSession() {
    _returnToLive();
    _controller?.dispose();
    _controller = null;
    _initCamera();
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

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

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
      // Always intercept — never let this bubble to main.dart's PopScope.
      // main.dart reads isReviewing directly to decide what to do.
      canPop: false,
      onPopInvokedWithResult: (_, _) {
        if (_state == _ScannerState.reviewing) {
          _returnToLive();
        } else {
          // Live state: delegate to onBack (tap-driven; main.dart handles
          // hardware back via the outer PopScope + isReviewing check).
          widget.onBack();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── 1. Camera feed (always present as base layer) ─────────────────
          // Live feed stays in the tree even in reviewing state so there is
          // no rebuild cost when returning to live. The frozen image sits on
          // top of it in reviewing state.
          Positioned.fill(child: _buildLiveFeed()),

          // ── 2. Frozen still — fades in instantly when reviewing ───────────
          if (_capturedImageBytes != null)
            Positioned.fill(
              child: Image.memory(
                _capturedImageBytes!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),

          // ── 3. OCR highlight overlay ──────────────────────────────────────
          if (_state == _ScannerState.reviewing && _ocrBlocks.isNotEmpty)
            Positioned.fill(child: _OcrHighlightOverlay(blocks: _ocrBlocks)),

          // ── 4. Top bar — explicitly anchored to top ───────────────────────
          Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),

          // ── 5. Bottom controls (live state only) ──────────────────────────
          if (_state == _ScannerState.live)
            _buildBottomControls(),

          // ── 6. Processing spinner (reviewing, still waiting for results) ──
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

          // ── 7. Results sheet ──────────────────────────────────────────────
          if (_state == _ScannerState.reviewing && _candidates.isNotEmpty)
            Positioned.fill(
              child: ScannerResultsSheet(
                candidates: _candidates,
                onSelect: (c) {
                  _returnToLive();
                  widget.onCardTap(c.cardId, c.recordType);
                },
                onDismiss: _returnToLive,
              ),
            ),
        ],
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────
  // Matches Google Lens layout:
  //   [← back] [flash icon]   Discover   [right spacer]
  // Back and flash are anchored left; title is centred across full width.

  Widget _buildTopBar() {
    return SafeArea(
      child: SizedBox(
        height: 56,
        child: Stack(
          children: [
            // Centred title
            const Center(
              child: Text(
                'Discover',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                ),
              ),
            ),

            // Left: back arrow + flash
            Positioned(
              left: 12,
              top: 0, bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Back arrow
                  GestureDetector(
                    onTap: () {
                      if (_state == _ScannerState.reviewing) {
                        _returnToLive();
                      } else {
                        widget.onBack();
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 24,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                      ),
                    ),
                  ),

                  const SizedBox(width: 4),

                  // Flash — only relevant in live state
                  if (_controller?.value.isInitialized == true)
                    GestureDetector(
                      onTap: _state == _ScannerState.live ? () => _cycleFlash() : null,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          _flashIcon(),
                          color: _state == _ScannerState.live
                              ? Colors.white
                              : Colors.white38,
                          size: 26,
                          shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
                        ),
                      ),
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
          // Button row: [gallery] [shutter] [mirror spacer]
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
                    child: Icon(
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
                setState(() => _mode = _DiscoverMode.search);
                widget.onNavBarVisibilityChanged(true);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mode pill
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// OCR highlight overlay
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

// ─────────────────────────────────────────────────────────────────────────────
// Zoom badge
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Focus square
// ─────────────────────────────────────────────────────────────────────────────

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