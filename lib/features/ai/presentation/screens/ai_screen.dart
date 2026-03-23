// lib/features/ai/presentation/screens/ai_screen.dart
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
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/services/recently_viewed_service.dart';
import '../../../../core/services/scanner_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AiScreen
// ─────────────────────────────────────────────────────────────────────────────

class AiScreen extends StatefulWidget {
  final void Function(String id, RecordType type) onCardTap;
  const AiScreen({super.key, required this.onCardTap});

  @override
  State<AiScreen> createState() => _AiScreenState();
}

enum _DiscoverMode { scan, search }

class _AiScreenState extends State<AiScreen> with WidgetsBindingObserver {
  // ── Camera
  CameraController? _controller;
  String? _cameraError;
  bool _initialising = true;
  bool _scanning = false;
  bool _flashOn = false;

  // ── Mode
  _DiscoverMode _mode = _DiscoverMode.scan;

  // ── Scan results
  List<MatchCandidate> _candidates = [];
  List<TextBlock> _ocrBlocks = []; // for highlight overlay
  bool _showingResults = false;

  // ── DraggableScrollableController for results sheet
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

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
    _sheetController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    ScannerService.instance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
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
        back, ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      if (!mounted) return;
      setState(() { _controller = ctrl; _initialising = false; });
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

    setState(() { _scanning = true; _showingResults = false; _candidates = []; _ocrBlocks = []; });

    try {
      final file  = await ctrl.takePicture();
      final bytes = await file.readAsBytes();

      // Run matching — ScannerService also runs OCR internally.
      // We separately run OCR to get bounding boxes for the highlight overlay.
      final recogniser = TextRecognizer(script: TextRecognitionScript.chinese);
      final inputImage = InputImage.fromFilePath(file.path);
      final recognisedText = await recogniser.processImage(inputImage);
      await recogniser.close();

      final result = await ScannerService.instance.match(bytes);

      if (!mounted) return;
      setState(() {
        _scanning = false;
        _ocrBlocks = recognisedText.blocks;
        _candidates = result.candidates;
        _showingResults = true;
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
        _dismissResults();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scan failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _dismissResults() {
    setState(() { _showingResults = false; _candidates = []; _ocrBlocks = []; });
  }

  void _toggleFlash() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    setState(() => _flashOn = !_flashOn);
    await ctrl.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
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
    return Stack(
      children: [
        // Full-screen viewfinder
        Positioned.fill(child: _buildViewfinder()),

        // OCR highlight overlay (shown after scan)
        if (_showingResults && _ocrBlocks.isNotEmpty)
          Positioned.fill(child: _OcrHighlightOverlay(blocks: _ocrBlocks)),

        // Top controls bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _LiveBadge(active: !_scanning && !_showingResults),
                if (_controller?.value.isInitialized == true)
                  _IconButton(
                    icon: _flashOn ? Icons.flash_on : Icons.flash_off,
                    onTap: _toggleFlash,
                  ),
              ],
            ),
          ),
        ),

        // Bottom controls: shutter + mode pill
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: _buildBottomBar(),
        ),

        // Scanning overlay
        if (_scanning)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 14),
                    Text('Scanning…',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),

        // Results sheet
        if (_showingResults && _candidates.isNotEmpty)
          _ResultsSheet(
            candidates: _candidates,
            onSelect: (c) {
              _dismissResults();
              widget.onCardTap(c.cardId, c.recordType);
            },
            onDismiss: _dismissResults,
          ),
      ],
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
    final ctrl = _controller!;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Live feed — fills entire screen
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
          // Reticle only shown when not displaying results
          if (!_showingResults) const _ReticleOverlay(),
        ],
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
                        onTap: _dismissResults,
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
                onTap: ready ? _scan : (_showingResults ? _dismissResults : null),
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
                  _dismissResults();
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
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
                  ? _SearchEmptyState()
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
// Results DraggableScrollableSheet
// Peeks at ~30% height showing top candidate prominently.
// Expand to ~80% for full ranked list.
// Swipe down or tap backdrop to dismiss.
// ─────────────────────────────────────────────────────────────────────────────

class _ResultsSheet extends StatelessWidget {
  final List<MatchCandidate> candidates;
  final void Function(MatchCandidate) onSelect;
  final VoidCallback onDismiss;

  const _ResultsSheet({
    required this.candidates,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return DraggableScrollableSheet(
      initialChildSize: 0.38,
      minChildSize: 0.20,
      maxChildSize: 0.82,
      snap: true,
      snapSizes: const [0.38, 0.82],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Handle + header
              GestureDetector(
                onTap: onDismiss,
                behavior: HitTestBehavior.translucent,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Column(
                    children: [
                      Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: theme.hintColor.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            candidates.length == 1
                                ? 'Match Found'
                                : '${candidates.length} Possible Matches',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          // Confidence badge of top result
                          _ConfidenceBadge(
                            confidence: candidates.first.confidence,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              // Top candidate — prominent card
              _TopCandidateCard(
                candidate: candidates.first,
                onTap: () => onSelect(candidates.first),
              ),
              // Remaining candidates
              if (candidates.length > 1) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Row(
                    children: [
                      Text(
                        'Other possibilities',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.hintColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    controller: scrollController,
                    shrinkWrap: true,
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom + 12,
                    ),
                    itemCount: candidates.length - 1,
                    itemBuilder: (context, i) => _CandidateTile(
                      candidate: candidates[i + 1],
                      onTap: () => onSelect(candidates[i + 1]),
                    ),
                  ),
                ),
              ] else
                SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
            ],
          ),
        );
      },
    );
  }
}

// Top candidate shown as a wider horizontal card with larger artwork
class _TopCandidateCard extends StatelessWidget {
  final MatchCandidate candidate;
  final VoidCallback onTap;

  const _TopCandidateCard({required this.candidate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGeneral = candidate.recordType == RecordType.general;
    final placeholder =
        isGeneral ? AppAssets.generalPlaceholder : AppAssets.libraryPlaceholder;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            // Larger artwork
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                candidate.imagePath,
                width: 60, height: 82, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Image.asset(
                  placeholder, width: 60, height: 82, fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    candidate.nameCn,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    candidate.nameEn,
                    style: TextStyle(fontSize: 13, color: theme.hintColor),
                  ),
                  const SizedBox(height: 6),
                  _TypeBadge(isGeneral: isGeneral),
                ],
              ),
            ),
            // Arrow CTA
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search empty state
// ─────────────────────────────────────────────────────────────────────────────

class _SearchEmptyState extends StatelessWidget {
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
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ConfidenceBadge extends StatelessWidget {
  final double confidence;
  const _ConfidenceBadge({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final pct = (confidence * 100).toStringAsFixed(0);
    final color = confidence >= 0.80 ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$pct% match',
        style: TextStyle(
          color: color, fontSize: 12, fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final bool isGeneral;
  const _TypeBadge({required this.isGeneral});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        isGeneral ? 'General' : 'Library Card',
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).hintColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  final MatchCandidate candidate;
  final VoidCallback onTap;
  const _CandidateTile({required this.candidate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme     = Theme.of(context);
    final pct       = (candidate.confidence * 100).toStringAsFixed(0);
    final confColor = candidate.confidence >= 0.80 ? Colors.green : Colors.orange;
    final isGeneral = candidate.recordType == RecordType.general;
    final placeholder =
        isGeneral ? AppAssets.generalPlaceholder : AppAssets.libraryPlaceholder;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.asset(
                candidate.imagePath,
                width: 40, height: 55, fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Image.asset(placeholder, width: 40, height: 55, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(candidate.nameCn,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(candidate.nameEn,
                      style: TextStyle(fontSize: 12, color: theme.hintColor)),
                  const SizedBox(height: 4),
                  _TypeBadge(isGeneral: isGeneral),
                ],
              ),
            ),
            Text('$pct%',
                style: TextStyle(
                    color: confColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: theme.hintColor),
          ],
        ),
      ),
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
// Animated reticle overlay
// ─────────────────────────────────────────────────────────────────────────────

class _ReticleOverlay extends StatefulWidget {
  const _ReticleOverlay();

  @override
  State<_ReticleOverlay> createState() => _ReticleOverlayState();
}

class _ReticleOverlayState extends State<_ReticleOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) => CustomPaint(
        painter: _ReticlePainter(opacity: _pulse.value),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  final double opacity;
  const _ReticlePainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final w  = size.width * 0.78;
    final h  = size.height * 0.52;
    final l  = cx - w / 2;
    final t  = cy - h / 2;
    final r  = cx + w / 2;
    final b  = cy + h / 2;
    const arm = 32.0;
    const rc  = 7.0;

    // Vignette
    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addRect(Rect.fromLTRB(l, t, r, b))
        ..fillType = PathFillType.evenOdd,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill,
    );

    // Corner brackets
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    void corner(double ox, double oy, double sx, double sy) {
      canvas.drawLine(
          Offset(ox + rc * sx, oy), Offset(ox + arm * sx, oy), paint);
      canvas.drawLine(
          Offset(ox, oy + rc * sy), Offset(ox, oy + arm * sy), paint);
      final arcRect = Rect.fromLTWH(
        ox + (sx > 0 ? 0 : -rc * 2),
        oy + (sy > 0 ? 0 : -rc * 2),
        rc * 2, rc * 2,
      );
      final startAngle = (sx > 0 && sy > 0)   ? 3.14159
          : (sx < 0 && sy > 0) ? -3.14159 / 2
          : (sx > 0 && sy < 0) ?  3.14159 / 2
          : 0.0;
      canvas.drawArc(arcRect, startAngle, 3.14159 / 2 * sx * sy, false, paint);
    }

    corner(l, t,  1,  1);
    corner(r, t, -1,  1);
    corner(l, b,  1, -1);
    corner(r, b, -1, -1);
  }

  @override
  bool shouldRepaint(_ReticlePainter old) => old.opacity != opacity;
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

// ─────────────────────────────────────────────────────────────────────────────
// LIVE / PAUSED badge
// ─────────────────────────────────────────────────────────────────────────────

class _LiveBadge extends StatelessWidget {
  final bool active;
  const _LiveBadge({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54, borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fiber_manual_record,
              color: active ? Colors.red : Colors.grey, size: 10),
          const SizedBox(width: 4),
          Text(
            active ? 'LIVE' : 'PAUSED',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}