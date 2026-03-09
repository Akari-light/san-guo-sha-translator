import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../../../../core/services/recently_viewed_service.dart';
import '../../../../../core/services/scanner_service.dart';
import '../../../../../core/constants/app_assets.dart';

/// Discover tab — card image scanner + (future) vector search.
///
/// Flow:
///   1. Continuous live camera feed with animated corner-bracket reticle.
///   2. User taps the shutter button to freeze frame + run matching.
///   3. Bottom sheet shows a ranked list of candidate cards.
///   4. Tapping a candidate calls [onCardTap] → main.dart pushes detail.
///
/// [onCardTap] is the same unified callback used by GeneralScreen and
/// LibraryScreen — main.dart is the only file that knows detail screens.
class AiScreen extends StatefulWidget {
  final void Function(String id, RecordType type) onCardTap;

  const AiScreen({super.key, required this.onCardTap});

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  String? _cameraError;
  bool _initialising = true;
  bool _scanning = false;

  // Dev debug log (most-recent first, capped at 20 lines)
  final List<String> _log = [];

  // ── Mock candidates — replace with real ScannerResult data when vectors land
  static const List<MatchCandidate> _mockCandidates = [
    MatchCandidate(
      cardId: 'jx.SHU001',
      recordType: RecordType.general,
      nameCn: '界刘备',
      nameEn: 'Liu Bei (Limit Break)',
      imagePath: 'assets/images/generals/jx.SHU001.webp',
      confidence: 0.91,
    ),
    MatchCandidate(
      cardId: 'jx.WEI001',
      recordType: RecordType.general,
      nameCn: '界曹操',
      nameEn: 'Cao Cao (Limit Break)',
      imagePath: 'assets/images/generals/jx.WEI001.webp',
      confidence: 0.74,
    ),
    MatchCandidate(
      cardId: 'weapon_qing_gang_sword',
      recordType: RecordType.library,
      nameCn: '青釭剑',
      nameEn: 'Qing Gang Sword',
      imagePath: 'assets/images/library/weapons/weapon_qing_gang_sword.webp',
      confidence: 0.52,
    ),
  ];

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

  Future<void> _initCamera() async {
    setState(() { _initialising = true; _cameraError = null; });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setError('No cameras found on this device.');
        return;
      }
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
      _addLog('Camera ready (${back.lensDirection.name})');
    } catch (e) {
      _setError(e.toString());
    }
  }

  void _setError(String msg) {
    if (!mounted) return;
    setState(() { _cameraError = msg; _initialising = false; });
    _addLog('ERROR: $msg');
  }

  Future<void> _scan() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _scanning) return;
    setState(() => _scanning = true);
    _addLog('Capturing frame...');
    try {
      final file  = await ctrl.takePicture();
      final bytes = await file.readAsBytes();
      _addLog('${bytes.lengthInBytes ~/ 1024} KB captured');
      _addLog('Calling ScannerService.match()...');
      final result = await ScannerService.instance.match(bytes);
      _addLog(result.debugMessage);
      if (!mounted) return;
      setState(() => _scanning = false);
      // Stub: always show mock candidates.
      // Real: build from result.candidates when vectors are ready.
      await _showResults(_mockCandidates);
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      _addLog('Scan ERROR: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan failed: $e')),
      );
    }
  }

  Future<void> _showResults(List<MatchCandidate> candidates) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ResultsSheet(
        candidates: candidates,
        onSelect: (c) {
          Navigator.pop(context);
          widget.onCardTap(c.cardId, c.recordType);
        },
      ),
    );
  }

  void _addLog(String message) {
    final t = DateTime.now();
    final line =
        '[${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}] $message';
    setState(() {
      _log.insert(0, line);
      if (_log.length > 20) _log.removeLast();
    });
    debugPrint('[AiScreen] $line');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(flex: 55, child: _buildViewfinder()),
        _buildShutterButton(),
        Expanded(flex: 35, child: _buildDebugPanel()),
      ],
    );
  }

  Widget _buildViewfinder() {
    if (_initialising) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_cameraError != null) {
      return _CameraError(error: _cameraError!, onRetry: _initCamera);
    }
    final ctrl = _controller!;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Live feed — fills the box
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
        // Animated reticle + dim vignette
        const _ReticleOverlay(),
        // LIVE badge
        Positioned(
          top: 10, left: 12,
          child: _LiveBadge(active: !_scanning),
        ),
        // Scanning overlay
        if (_scanning)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 12),
                  Text('Scanning...', style: TextStyle(color: Colors.white, fontSize: 14)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildShutterButton() {
    final ready = _controller?.value.isInitialized == true && !_scanning;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: GestureDetector(
        onTap: ready ? _scan : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 68, height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ready ? Colors.white : Colors.white38,
            border: Border.all(
              color: ready ? Colors.white54 : Colors.white24,
              width: 4,
            ),
            boxShadow: ready
                ? [BoxShadow(
                    color: Colors.white.withValues(alpha: 0.3),
                    blurRadius: 12, spreadRadius: 2,
                  )]
                : [],
          ),
          child: _scanning
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                )
              : const Icon(Icons.document_scanner, color: Colors.black87, size: 28),
        ),
      ),
    );
  }

  Widget _buildDebugPanel() {
    final camReady = _controller?.value.isInitialized ?? false;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                const Text(
                  'DEV — Discover Debug',
                  style: TextStyle(
                    color: Colors.greenAccent, fontSize: 11,
                    fontWeight: FontWeight.bold, letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                _StatusDot(label: 'CAM', active: camReady),
                const SizedBox(width: 8),
                const _StatusDot(label: 'STUB', active: true),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              itemCount: _log.length,
              itemBuilder: (_, i) => Text(
                _log[i],
                style: TextStyle(
                  color: _log[i].contains('ERROR')
                      ? Colors.redAccent
                      : Colors.white54,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data model — one candidate in the results sheet
// ─────────────────────────────────────────────────────────────────────────────

class MatchCandidate {
  final String cardId;
  final RecordType recordType;
  final String nameCn;
  final String nameEn;
  final String imagePath;
  final double confidence;

  const MatchCandidate({
    required this.cardId,
    required this.recordType,
    required this.nameCn,
    required this.nameEn,
    required this.imagePath,
    required this.confidence,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Results bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ResultsSheet extends StatelessWidget {
  final List<MatchCandidate> candidates;
  final void Function(MatchCandidate) onSelect;

  const _ResultsSheet({required this.candidates, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tap-outside dismiss area
        Flexible(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: theme.hintColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Row(
                  children: [
                    Text(
                      'Possible Matches',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                      ),
                      child: const Text(
                        'STUB DATA',
                        style: TextStyle(
                          color: Colors.orange, fontSize: 9,
                          fontWeight: FontWeight.bold, letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Candidates
              ...candidates.map((c) => _CandidateTile(
                candidate: c,
                onTap: () => onSelect(c),
              )),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
            ],
          ),
        ),
      ],
    );
  }
}

class _CandidateTile extends StatelessWidget {
  final MatchCandidate candidate;
  final VoidCallback onTap;

  const _CandidateTile({required this.candidate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme      = Theme.of(context);
    final pct        = (candidate.confidence * 100).toStringAsFixed(0);
    final confColor  = candidate.confidence >= 0.80 ? Colors.green : Colors.orange;
    final isGeneral  = candidate.recordType == RecordType.general;
    final placeholder = isGeneral
        ? AppAssets.generalPlaceholder
        : AppAssets.libraryPlaceholder;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                candidate.imagePath,
                width: 44, height: 60, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Image.asset(
                  placeholder,
                  width: 44, height: 60, fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Names + type badge
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    candidate.nameCn,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    candidate.nameEn,
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isGeneral ? 'General' : 'Library Card',
                      style: TextStyle(
                        fontSize: 10, color: theme.hintColor, fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Confidence + chevron
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$pct%',
                  style: TextStyle(
                    color: confColor, fontWeight: FontWeight.w800, fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Supporting widgets
// ─────────────────────────────────────────────────────────────────────────────

class _CameraError extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _CameraError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('Camera unavailable',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
    );
  }
}

/// Animated corner-bracket reticle — signals continuous live analysis.
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
    final w  = size.width * 0.62;
    final h  = size.height * 0.55;
    final l  = cx - w / 2;
    final t  = cy - h / 2;
    final r  = cx + w / 2;
    final b  = cy + h / 2;
    const arm = 28.0;
    const rc  = 6.0;

    // Dim vignette outside reticle
    final vignette = Paint()
      ..color = Colors.black.withValues(alpha: 0.38)
      ..style = PaintingStyle.fill;
    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addRect(Rect.fromLTRB(l, t, r, b))
        ..fillType = PathFillType.evenOdd,
      vignette,
    );

    // Corner brackets
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    void corner(double ox, double oy, double sx, double sy) {
      // ox,oy = outer corner; sx,sy = sign for arm direction
      canvas.drawLine(Offset(ox + rc * sx, oy), Offset(ox + arm * sx, oy), paint);
      canvas.drawLine(Offset(ox, oy + rc * sy), Offset(ox, oy + arm * sy), paint);
      // Arc: sweep sign follows the corner quadrant
      final arcRect = Rect.fromLTWH(
        ox + (sx > 0 ? 0 : -rc * 2),
        oy + (sy > 0 ? 0 : -rc * 2),
        rc * 2, rc * 2,
      );
      // Start/sweep chosen so arc always runs inward
      final startAngle = (sx > 0 && sy > 0) ? 3.14159
          : (sx < 0 && sy > 0) ? -3.14159 / 2
          : (sx > 0 && sy < 0) ?  3.14159 / 2
          : 0.0;
      canvas.drawArc(arcRect, startAngle, 3.14159 / 2 * sx * sy, false, paint);
    }

    corner(l, t,  1,  1);   // top-left
    corner(r, t, -1,  1);   // top-right
    corner(l, b,  1, -1);   // bottom-left
    corner(r, b, -1, -1);   // bottom-right
  }

  @override
  bool shouldRepaint(_ReticlePainter old) => old.opacity != opacity;
}

class _LiveBadge extends StatelessWidget {
  final bool active;
  const _LiveBadge({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black87, borderRadius: BorderRadius.circular(6),
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
              color: Colors.white, fontSize: 10,
              fontWeight: FontWeight.bold, letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final String label;
  final bool active;
  const _StatusDot({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7, height: 7,
          decoration: BoxDecoration(
            color: active ? Colors.greenAccent : Colors.grey,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9)),
      ],
    );
  }
}