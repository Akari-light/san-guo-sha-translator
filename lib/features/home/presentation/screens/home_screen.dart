import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/services/home_service.dart';
import '../../../../core/services/pin_service.dart';
import '../../../../core/theme/app_theme.dart';

// ── HomeScreen 
class HomeScreen extends StatefulWidget {
  final void Function(String generalId) onGeneralTap;
  final void Function(String libraryId) onLibraryTap;

  const HomeScreen({
    super.key,
    required this.onGeneralTap,
    required this.onLibraryTap,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  PinnedCards    _pins   = const PinnedCards(generals: [], library: []);
  RecentlyViewed _recent = const RecentlyViewed(cards: []);
  bool _loading = true;

  StreamSubscription<PinType>? _pinSub;
  StreamSubscription<void>?    _recentSub;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
    _pinSub    = HomeService.instance.changes.listen((_) => _loadPins());
    _recentSub = HomeService.instance.recentChanges.listen((_) => _loadRecent());
  }

  @override
  void dispose() {
    _pinSub?.cancel();
    _recentSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    if (initial && mounted) setState(() => _loading = true);
    final results = await Future.wait([
      HomeService.instance.getPinnedCards(),
      HomeService.instance.getRecentlyViewed(),
    ]);
    if (mounted) {
      setState(() {
        _pins    = results[0] as PinnedCards;
        _recent  = results[1] as RecentlyViewed;
        _loading = false;
      });
    }
  }

  Future<void> _loadPins() async {
    final pins = await HomeService.instance.getPinnedCards();
    if (mounted) setState(() => _pins = pins);
  }

  Future<void> _loadRecent() async {
    final recent = await HomeService.instance.getRecentlyViewed();
    if (mounted) setState(() => _recent = recent);
  }

  Future<void> _clearAllPins() async {
    await HomeService.instance.clearAll();
  }

  Future<void> _clearGeneralPins() async {
    for (final g in List.of(_pins.generals)) {
      await HomeService.instance.unpinGeneral(g.id);
    }
  }

  Future<void> _clearLibraryPins() async {
    for (final c in List.of(_pins.library)) {
      await HomeService.instance.unpinLibrary(c.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _ShaWatermark(isDark: isDark)),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            Column(
              children: [
                _RecentSection(
                  recent: _recent,
                  isDark: isDark,
                  onClear: () async {
                    await HomeService.instance.clearRecentlyViewed();
                  },
                  onCardTap: (card) => card.isGeneral
                      ? widget.onGeneralTap(card.id)
                      : widget.onLibraryTap(card.id),
                ),
                Expanded(
                  child: _PinnedSection(
                    pins: _pins,
                    isDark: isDark,
                    onClearAll: _clearAllPins,
                    onClearGenerals: _clearGeneralPins,
                    onClearLibrary: _clearLibraryPins,
                    onRemoveGeneral: (id) =>
                        HomeService.instance.unpinGeneral(id),
                    onRemoveLibrary: (id) =>
                        HomeService.instance.unpinLibrary(id),
                    onGeneralTap: widget.onGeneralTap,
                    onLibraryTap: widget.onLibraryTap,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ShaWatermark extends StatelessWidget {
  final bool isDark;
  const _ShaWatermark({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/images/logo.png', fit: BoxFit.cover, color: Colors.white.withValues(alpha: isDark ? 0.072 : 0.055), colorBlendMode: BlendMode.modulate);
  }
}

// ── Recently Viewed Section 
class _RecentSection extends StatefulWidget {
  final RecentlyViewed recent;
  final bool isDark;
  final VoidCallback onClear;
  final void Function(RecentlyViewedCard card) onCardTap;

  const _RecentSection({
    required this.recent,
    required this.isDark,
    required this.onClear,
    required this.onCardTap,
  });

  @override
  State<_RecentSection> createState() => _RecentSectionState();
}

class _RecentSectionState extends State<_RecentSection> {
  int _focusIdx = 0;

  Color _accentFor(RecentlyViewedCard card) {
    if (card.isGeneral) {
      return AppTheme.factionColor(card.general?.faction ?? '');
    }
    return AppTheme.categoryColor(
      card.libraryCard?.categoryEn ?? '',
      widget.isDark,
    );
  }

  @override
  void didUpdateWidget(_RecentSection old) {
    super.didUpdateWidget(old);
    if (widget.recent.cards.isNotEmpty &&
        _focusIdx >= widget.recent.cards.length) {
      setState(() => _focusIdx = widget.recent.cards.length - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final T      = widget.isDark;
    final cards  = widget.recent.cards;
    final hasAny  = cards.isNotEmpty;
    final safeIdx = hasAny ? _focusIdx.clamp(0, cards.length - 1) : 0;
    // Non-nullable when hasAny — promoted explicitly so all usages below are safe.
    final RecentlyViewedCard? focusedOrNull = hasAny ? cards[safeIdx] : null;
    final fAcc = focusedOrNull != null ? _accentFor(focusedOrNull) : Colors.grey;

    // ── Recently Viewed: solid header bar + gradient body below 
    final headerBg = T ? const Color(0xFF1E1E1E) : const Color(0xFFF0F0F0);
    final borderCol = (T ? Colors.white : Colors.black).withValues(alpha: 0.07);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Solid header row
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 9),
          decoration: BoxDecoration(
            color: headerBg,
            border: Border(bottom: BorderSide(color: borderCol)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'RECENTLY VIEWED ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: (T ? Colors.white : Colors.black)
                              .withValues(alpha: 0.70),
                          letterSpacing: 0.9,
                        ),
                      ),
                      TextSpan(
                        text: '${cards.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: (T ? Colors.white : Colors.black)
                              .withValues(alpha: 0.40),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (hasAny)
                GestureDetector(
                  onTap: widget.onClear,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF44747).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFFF44747).withValues(alpha: 0.42),
                      ),
                    ),
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF44747),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Card content area — gradient tint behind spotlight
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            gradient: focusedOrNull != null
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      fAcc.withValues(alpha: T ? 0.12 : 0.07),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 1.0],
                  )
                : null,
            border: Border(bottom: BorderSide(color: borderCol)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!hasAny) ...[
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'No recently viewed cards yet.',
                    style: TextStyle(
                      fontSize: 13,
                      color: (T ? Colors.white : Colors.black)
                          .withValues(alpha: 0.28),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ] else if (focusedOrNull != null) ...[
                _SpotlightCard(
                  focused: focusedOrNull,
                  fAcc: fAcc,
                  isDark: T,
                  onTap: () => widget.onCardTap(focusedOrNull),
                ),
                // Thumbnail strip
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (int i = 0; i < cards.length; i++)
                        _ThumbnailChip(
                          card: cards[i],
                          isActive: i == safeIdx,
                          isDark: T,
                          onTap: () => setState(() => _focusIdx = i),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Spotlight card 
class _SpotlightCard extends StatelessWidget {
  final RecentlyViewedCard focused;
  final Color fAcc;
  final bool isDark;
  final VoidCallback onTap;

  const _SpotlightCard({
    required this.focused,
    required this.fAcc,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final T = isDark;
    // Expansion badge data — generals only
    final expBadge = focused.isGeneral ? focused.general?.expansionBadge : null;
    final expColor = (focused.isGeneral && focused.general != null)
        ? AppTheme.expansionColor(focused.general!.expansion)
        : fAcc;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: T ? const Color(0xFF252526) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: fAcc.withValues(alpha: 0.42), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: fAcc.withValues(alpha: T ? 0.16 : 0.10),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Art thumbnail
            Container(
              width: 84,
              height: 118,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    fAcc.withValues(alpha: 0.38),
                    fAcc.withValues(alpha: 0.10),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: fAcc.withValues(alpha: 0.55), width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      focused.imagePath,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Center(
                        child: Text(
                          focused.isGeneral
                              ? (focused.general?.faction ?? '?')[0]
                              : (focused.libraryCard?.categoryEn ?? '?')[0],
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            color: fAcc.withValues(alpha: 0.82),
                          ),
                        ),
                      ),
                    ),
                    // Expansion badge — top-right, generals only
                    if (expBadge != null)
                      Positioned(
                        top: 3,
                        right: 3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            expBadge,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: expColor,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Text info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    focused.nameCn,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: T ? Colors.white : Colors.black,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    focused.nameEn,
                    style: TextStyle(
                      fontSize: 13,
                      color: (T ? Colors.white : Colors.black)
                          .withValues(alpha: 0.42),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: fAcc.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: fAcc.withValues(alpha: 0.32)),
                    ),
                    child: Text(
                      focused.isGeneral
                          ? (focused.general?.faction ?? '')
                          : (focused.libraryCard?.categoryEn ?? ''),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: fAcc,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: (T ? Colors.white : Colors.black).withValues(alpha: 0.22),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Thumbnail chip 
class _ThumbnailChip extends StatelessWidget {
  final RecentlyViewedCard card;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _ThumbnailChip({
    required this.card,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  Color _accent() {
    if (card.isGeneral) return AppTheme.factionColor(card.general?.faction ?? '');
    return AppTheme.categoryColor(card.libraryCard?.categoryEn ?? '', isDark);
  }

  @override
  Widget build(BuildContext context) {
    final acc = _accent();
    // ② Expansion badge — generals only
    final expBadge = card.isGeneral ? card.general?.expansionBadge : null;
    final expColor = (card.isGeneral && card.general != null)
        ? AppTheme.expansionColor(card.general!.expansion)
        : acc;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 101,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    acc.withValues(alpha: isActive ? 0.44 : 0.18),
                    acc.withValues(alpha: 0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isActive ? acc : acc.withValues(alpha: 0.32),
                  width: 1.5,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: acc.withValues(alpha: 0.45),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      card.imagePath,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Center(
                        child: Text(
                          card.isGeneral
                              ? (card.general?.faction ?? '?')[0]
                              : (card.libraryCard?.categoryEn ?? '?')[0],
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: acc.withValues(
                                alpha: isActive ? 0.88 : 0.52),
                          ),
                        ),
                      ),
                    ),
                    if (!isActive)
                      Container(color: const Color(0x590A0A0A)),
                    // Expansion badge top-right — generals only
                    if (expBadge != null)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            expBadge,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: expColor,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: isActive ? 21 : 6,
              height: 3,
              decoration: BoxDecoration(
                color: isActive
                    ? acc
                    : (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pinned Section 
class _PinnedSection extends StatefulWidget {
  final PinnedCards pins;
  final bool isDark;
  final Future<void> Function() onClearAll;
  final Future<void> Function() onClearGenerals;
  final Future<void> Function() onClearLibrary;
  final Future<void> Function(String id) onRemoveGeneral;
  final Future<void> Function(String id) onRemoveLibrary;
  final void Function(String id) onGeneralTap;
  final void Function(String id) onLibraryTap;

  const _PinnedSection({
    required this.pins,
    required this.isDark,
    required this.onClearAll,
    required this.onClearGenerals,
    required this.onClearLibrary,
    required this.onRemoveGeneral,
    required this.onRemoveLibrary,
    required this.onGeneralTap,
    required this.onLibraryTap,
  });

  @override
  State<_PinnedSection> createState() => _PinnedSectionState();
}

class _PinnedSectionState extends State<_PinnedSection> {
  bool    _dragging         = false;
  bool    _showHint         = true;
  Offset  _dragPos          = Offset.zero;
  String? _hoverZone;
  bool    _isDraggingActive = false;

  final _generalsKey = GlobalKey();
  final _libraryKey  = GlobalKey();
  // Key on the Stack so we can convert global pointer coords → local Stack coords for the drag ghost. Without this the ghost is offset by the height of _RecentSection above the Stack's local origin.
  final _stackKey    = GlobalKey();

  String? _toastMsg;
  Timer?  _toastTimer;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showHint = false);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  void _showToast(String msg) {
    _toastTimer?.cancel();
    if (mounted) setState(() => _toastMsg = msg);
    _toastTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _toastMsg = null);
    });
  }

  String? _zoneAt(Offset globalPos) {
    for (final entry in [
      ('generals', _generalsKey),
      ('library', _libraryKey),
    ]) {
      final ctx = entry.$2.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final origin = box.localToGlobal(Offset.zero);
      final rect   = origin & box.size;
      if (rect.contains(globalPos)) return entry.$1;
    }
    return null;
  }

  void _onDragMove(Offset globalPos) {
    if (!_isDraggingActive) return;
    final zone = _zoneAt(globalPos);
    setState(() {
      _dragPos   = globalPos;
      _hoverZone = zone;
    });
  }

  Future<void> _onDragEnd(Offset globalPos) async {
    if (!_isDraggingActive) return;
    _isDraggingActive = false;
    final zone = _zoneAt(globalPos);
    setState(() {
      _dragging  = false;
      _hoverZone = null;
    });
    if (zone == 'generals') {
      await widget.onClearGenerals();
      _showToast('Generals cleared');
    } else if (zone == 'library') {
      await widget.onClearLibrary();
      _showToast('Library cleared');
    }
  }

  bool get _hasPinned =>
      widget.pins.generals.isNotEmpty || widget.pins.library.isNotEmpty;

  BoxDecoration? _zoneDecoration(String zone) {
    if (!_dragging) return null;
    final active = _hoverZone == zone;
    return BoxDecoration(
      color: active
          ? const Color(0xFFF44747).withValues(alpha: 0.09)
          : Colors.transparent,
      border: active
          ? Border.all(
              color: const Color(0xFFF44747).withValues(alpha: 0.55),
              width: 2,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final T       = widget.isDark;
    final divider = (T ? Colors.white : Colors.black).withValues(alpha: 0.07);

    return Listener(
      onPointerMove: (e) => _onDragMove(e.position),
      onPointerUp:   (e) => _onDragEnd(e.position),
      child: Stack(
      key: _stackKey,
      children: [
        Column(
          children: [
            // ── Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 9),
              decoration: BoxDecoration(
                color: T
                    ? const Color(0xFF1E1E1E)
                    : const Color(0xFFEAEAEA),
                border: Border(bottom: BorderSide(color: divider)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'PINNED ',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: (T ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.70),
                              letterSpacing: 0.9,
                            ),
                          ),
                          TextSpan(
                            text:
                                '${widget.pins.generals.length + widget.pins.library.length}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: (T ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_hasPinned) ...[
                    // Hint tooltip (auto-dismisses after 4s)
                    if (_showHint)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: T
                              ? const Color(0xFF2E2E2E)
                              : const Color(0xFFE4E4E4),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (T ? Colors.white : Colors.black)
                                .withValues(alpha: 0.08),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: T ? 0.5 : 0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          '💡 Tap to clear all · Long press to drag',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: T ? Colors.white : Colors.black,
                          ),
                        ),
                      ),

                    // 🗑 trash-can button (tap = clear all, long-press = drag)
                    GestureDetector(
                      onTap: () async {
                        if (!_dragging) {
                          await widget.onClearAll();
                          if (mounted) _showToast('All pins cleared');
                        }
                      },
                      onLongPressStart: (details) {
                        if (!_hasPinned) return;
                        setState(() {
                          _isDraggingActive = true;
                          _dragging         = true;
                          _showHint         = false;
                          _dragPos          = details.globalPosition;
                        });
                      },
                      // Move + end are handled by the Listener above, which fires globally regardless of where the pointer travels.
                      child: AnimatedOpacity(
                        opacity: _dragging ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 150),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF44747)
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFF44747)
                                  .withValues(alpha: 0.42),
                            ),
                          ),
                          child: const Text('🗑', style: TextStyle(fontSize: 14)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Body
            Expanded(
              child: !_hasPinned
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.push_pin_outlined,
                            size: 32,
                            color: (T ? Colors.white : Colors.black)
                                .withValues(alpha: 0.18),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Nothing pinned yet',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: (T ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.30),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Open any general or library card\nand tap the pin icon.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.6,
                              color: (T ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.20),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // LEFT — Generals
                        Expanded(
                          child: _DragZoneWrapper(
                            zoneKey: _generalsKey,
                            dragging: _dragging,
                            hoverActive: _hoverZone == 'generals',
                            columnLabel: '将 Generals',
                            count: widget.pins.generals.length,
                            isDark: T,
                            rightBorderColor: divider,
                            decoration: _zoneDecoration('generals'),
                            child: widget.pins.generals.isEmpty
                                ? _emptyMsg('No generals pinned', T)
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                        8, 4, 8, 10),
                                    itemCount:
                                        widget.pins.generals.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 7),
                                    itemBuilder: (_, i) {
                                      final g = widget.pins.generals[i];
                                      return _PinnedGeneralTile(
                                        id: g.id,
                                        nameCn: g.nameCn,
                                        nameEn: g.nameEn,
                                        imagePath: g.imagePath,
                                        faction: g.faction,
                                        isDark: T,
                                        onTap: () => widget
                                            .onGeneralTap(g.id),
                                        onRemove: () => widget
                                            .onRemoveGeneral(g.id),
                                      );
                                    },
                                  ),
                          ),
                        ),

                        // RIGHT — Library
                        Expanded(
                          child: _DragZoneWrapper(
                            zoneKey: _libraryKey,
                            dragging: _dragging,
                            hoverActive: _hoverZone == 'library',
                            columnLabel: '牌 Library',
                            count: widget.pins.library.length,
                            isDark: T,
                            decoration: _zoneDecoration('library'),
                            child: widget.pins.library.isEmpty
                                ? _emptyMsg('No cards pinned', T)
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                        8, 4, 8, 10),
                                    itemCount: widget.pins.library.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 7),
                                    itemBuilder: (_, i) {
                                      final c = widget.pins.library[i];
                                      return _PinnedLibraryTile(
                                        id: c.id,
                                        nameCn: c.nameCn,
                                        nameEn: c.nameEn,
                                        imagePath: c.imagePath,
                                        categoryEn: c.categoryEn,
                                        isDark: T,
                                        onTap: () => widget
                                            .onLibraryTap(c.id),
                                        onRemove: () => widget
                                            .onRemoveLibrary(c.id),
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),

        // Toast
        if (_toastMsg != null)
          Positioned(
            top: 50,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: T
                        ? const Color(0xFF333333)
                        : const Color(0xFFDDDDDD),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (T ? Colors.white : Colors.black)
                          .withValues(alpha: 0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: T ? 0.5 : 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    _toastMsg!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: T ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Drag ghost
        if (_dragging)
          Builder(
            builder: (context) {
              final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
              final local = box != null
                  ? box.globalToLocal(_dragPos)
                  : _dragPos;
              return Positioned(
                left: local.dx - 44,
                top:  local.dy - 16,
                child: IgnorePointer(
              child: Transform.rotate(
                angle: -0.052,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A1010),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFF44747)
                          .withValues(alpha: 0.85),
                      width: 1.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 24,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Text(
                    '🗑 Clear pins',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF44747),
                    ),
                  ),
                ),
              ),
            ),
              );
            },
          ),
      ],
    ), // Stack
    ); // Listener
  }

  Widget _emptyMsg(String msg, bool isDark) => Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          msg,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: (isDark ? Colors.white : Colors.black)
                .withValues(alpha: 0.20),
          ),
        ),
      );
}

// ── Drag zone wrapper 
class _DragZoneWrapper extends StatelessWidget {
  final GlobalKey zoneKey;
  final bool dragging;
  final bool hoverActive;
  final String columnLabel;
  final int count;
  final bool isDark;
  final Color? rightBorderColor;
  final BoxDecoration? decoration;
  final Widget child;

  const _DragZoneWrapper({
    required this.zoneKey,
    required this.dragging,
    required this.hoverActive,
    required this.columnLabel,
    required this.count,
    required this.isDark,
    this.rightBorderColor,
    this.decoration,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final T = isDark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      key: zoneKey,
      decoration: decoration ??
          (rightBorderColor != null
              ? BoxDecoration(
                  border: Border(
                    right: BorderSide(color: rightBorderColor!),
                  ),
                )
              : null),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedOpacity(
                opacity: dragging ? 0.2 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  child: Row(
                    children: [
                      Text(
                        columnLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: (T ? Colors.white : Colors.black)
                              .withValues(alpha: 0.32),
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 14,
                          color: (T ? Colors.white : Colors.black)
                              .withValues(alpha: 0.20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: AnimatedOpacity(
                  opacity: dragging ? 0.18 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  child: child,
                ),
              ),
            ],
          ),
          if (dragging)
            Center(
              child: Text(
                hoverActive ? '🗑 Drop to clear' : columnLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: hoverActive
                      ? const Color(0xFFF44747)
                      : const Color(0xFFF44747).withValues(alpha: 0.38),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Pinned general tile 
class _PinnedGeneralTile extends StatelessWidget {
  final String id;
  final String nameCn;
  final String nameEn;
  final String imagePath;
  final String faction;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _PinnedGeneralTile({
    required this.id,
    required this.nameCn,
    required this.nameEn,
    required this.imagePath,
    required this.faction,
    required this.isDark,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final fc = AppTheme.factionColor(faction);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 62,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: fc.withValues(alpha: 0.55), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: fc.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Full-tile character image
                Image.asset(
                  imagePath,
                  fit: BoxFit.cover,
                  alignment: Alignment(0, -0.6),
                  errorBuilder: (_, _, _) => Container(
                    color: fc.withValues(alpha: 0.12),
                    child: Center(
                      child: Text(
                        faction.isNotEmpty ? faction[0] : '?',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: fc.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ),
                ),
                // Left-to-right gradient so text on left side is legible
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.55),
                          Colors.black.withValues(alpha: 0.80),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
                // Name text — left-aligned, leave gap for ✕ on right
                Positioned(
                  left: 8,
                  right: 26,
                  top: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nameCn,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                        ),
                      ),
                      Text(
                        nameEn,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.60),
                          shadows: const [
                            Shadow(color: Colors.black, blurRadius: 4)
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // ✕ quick-delete — plain X, middle-right, no circle
                Positioned(
                  right: 6,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onRemove,
                      child: Text(
                        '✕',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFF44747)
                              .withValues(alpha: 0.85),
                          shadows: const [
                            Shadow(color: Colors.black, blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Pinned library tile 
class _PinnedLibraryTile extends StatelessWidget {
  final String id;
  final String nameCn;
  final String nameEn;
  final String imagePath;
  final String categoryEn;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _PinnedLibraryTile({
    required this.id,
    required this.nameCn,
    required this.nameEn,
    required this.imagePath,
    required this.categoryEn,
    required this.isDark,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cc = AppTheme.categoryColor(categoryEn, isDark);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF252526) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cc.withValues(alpha: 0.30)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category colour band
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [cc, cc.withValues(alpha: 0.28)],
                      ),
                    ),
                  ),
                  // Right padding makes room for the ✕
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 28, 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          categoryEn.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: cc,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          nameCn,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          nameEn,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.38),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // ✕ quick-delete — plain X, middle-right, no circle
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onRemove,
                    child: Text(
                      '✕',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFFF44747)
                            .withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}