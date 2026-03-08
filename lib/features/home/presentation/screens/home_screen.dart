import 'dart:async';
import 'package:flutter/material.dart';

import '../../../../core/services/home_service.dart';
import '../../../../core/services/pin_service.dart';
import '../../../../core/constants/app_assets.dart';

class HomeScreen extends StatefulWidget {
  /// Called when a pinned general card is tapped.
  /// main.dart pushes GeneralDetailScreen — HomeScreen never imports it.
  final void Function(String generalId) onGeneralTap;

  /// Called when a pinned library card is tapped.
  /// main.dart pushes LibraryDetailScreen — HomeScreen never imports it.
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

  // ── Loaders ───────────────────────────────────────────────────────────────

  /// Initial full load — fetches pins and recently viewed in parallel.
  Future<void> _load({bool initial = false}) async {
    if (initial && mounted) setState(() => _loading = true);
    final results = await Future.wait([
      HomeService.instance.getPinnedCards(),
      HomeService.instance.getRecentlyViewed(),
    ]);
    if (mounted) {
      setState(() {
        _pins   = results[0] as PinnedCards;
        _recent = results[1] as RecentlyViewed;
        _loading = false;
      });
    }
  }

  /// Called when pin state changes — reloads only the pins bucket.
  Future<void> _loadPins() async {
    final pins = await HomeService.instance.getPinnedCards();
    if (mounted) setState(() => _pins = pins);
  }

  /// Called when recently-viewed state changes — reloads only that bucket.
  Future<void> _loadRecent() async {
    final recent = await HomeService.instance.getRecentlyViewed();
    if (mounted) setState(() => _recent = recent);
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear all pins?'),
        content: const Text(
            'This will remove all pinned generals and library cards.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Clear All',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) await HomeService.instance.clearAll();
    // Pin stream fires → _loadPins() runs automatically.
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [

            // ── Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pin Debug',
                            style: TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Pinned cards appear here instantly.',
                            style:
                                TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    if (!_loading && !_pins.isEmpty)
                      TextButton.icon(
                        onPressed: _clearAll,
                        icon: Icon(Icons.clear_all,
                            size: 18, color: theme.colorScheme.error),
                        label: Text(
                          'Clear All',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // ── Loading
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )

            // ── Empty state
            else if (_pins.isEmpty && _recent.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.push_pin_outlined,
                          size: 48, color: theme.hintColor),
                      const SizedBox(height: 12),
                      Text(
                        'Nothing pinned yet.',
                        style: TextStyle(
                            color: theme.hintColor, fontSize: 15),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Open any general or library card and tap the pin icon.',
                        style: TextStyle(
                            color: theme.hintColor, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )

            else ...[

              // ── Pinned generals section
              if (_pins.generals.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    label: 'Generals',
                    icon: Icons.person,
                    count: _pins.generals.length,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.72,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final card = _pins.generals[i];
                        return _PinnedGeneralTile(
                          id: card.id,
                          nameCn: card.nameCn,
                          nameEn: card.nameEn,
                          imagePath: card.imagePath,
                          faction: card.faction,
                          expansionBadge: card.expansionBadge,
                          onTap: () => widget.onGeneralTap(card.id),
                        );
                      },
                      childCount: _pins.generals.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
              ],

              // ── Pinned library section
              if (_pins.library.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    label: 'Library',
                    icon: Icons.menu_book,
                    count: _pins.library.length,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.7,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final card = _pins.library[i];
                        return _PinnedLibraryTile(
                          id: card.id,
                          nameCn: card.nameCn,
                          nameEn: card.nameEn,
                          imagePath: card.imagePath,
                          onTap: () => widget.onLibraryTap(card.id),
                        );
                      },
                      childCount: _pins.library.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
              ],

              // ── Recently viewed section
              if (_recent.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Row(
                      children: [
                        Icon(Icons.history, size: 15, color: theme.hintColor),
                        const SizedBox(width: 6),
                        Text(
                          'RECENTLY VIEWED',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(${_recent.cards.length})',
                          style: TextStyle(fontSize: 11, color: theme.hintColor),
                        ),
                        const Spacer(),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            await HomeService.instance.clearRecentlyViewed();
                            // recentChanges stream fires → _loadRecent() auto-runs.
                          },
                          child: Text(
                            'Clear',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final card = _recent.cards[i];
                        final isGeneral = card.isGeneral;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => isGeneral
                              ? widget.onGeneralTap(card.id)
                              : widget.onLibraryTap(card.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                // Type badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: (isGeneral
                                            ? Colors.orange
                                            : Colors.blueAccent)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: (isGeneral
                                              ? Colors.orange
                                              : Colors.blueAccent)
                                          .withValues(alpha: 0.45),
                                    ),
                                  ),
                                  child: Text(
                                    isGeneral ? 'G' : 'L',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: isGeneral
                                          ? Colors.orange
                                          : Colors.blueAccent,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Names
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        card.nameCn,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        card.nameEn,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme.hintColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // ID — useful for debugging
                                Text(
                                  card.id,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.hintColor,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: _recent.cards.length,
                    ),
                  ),
                ),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Pinned general tile ────────────────────────────────────────────────────
// Mirrors GeneralCardTile visually but takes primitive fields only —
// no GeneralCard import required.

class _PinnedGeneralTile extends StatelessWidget {
  final String id;
  final String nameCn;
  final String nameEn;
  final String imagePath;
  final String faction;
  final String expansionBadge;
  final VoidCallback onTap;

  const _PinnedGeneralTile({
    required this.id,
    required this.nameCn,
    required this.nameEn,
    required this.imagePath,
    required this.faction,
    required this.expansionBadge,
    required this.onTap,
  });

  Color _factionColor() {
    switch (faction) {
      case 'Shu': return const Color(0xFFFF5722);
      case 'Wei': return const Color(0xFF2196F3);
      case 'Wu':  return const Color(0xFF4CAF50);
      case 'Qun': return const Color(0xFF9E9E9E);
      case 'God': return const Color(0xFFFFC107);
      default:    return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _factionColor();
    return GestureDetector(
      onTap: onTap,
      child: Hero(
        tag: 'home_general_$id',
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  imagePath,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: color.withValues(alpha: 0.1),
                    child: Center(
                      child: Image.asset(
                        AppAssets.generalPlaceholder,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(6),
                      border:
                          Border.all(color: Colors.white54, width: 0.5),
                    ),
                    child: Text(
                      expansionBadge,
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
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

// ── Pinned library tile ────────────────────────────────────────────────────
// Mirrors LibraryCardTile visually but takes primitive fields only —
// no LibraryDTO import required.

class _PinnedLibraryTile extends StatelessWidget {
  final String id;
  final String nameCn;
  final String nameEn;
  final String imagePath;
  final VoidCallback onTap;

  const _PinnedLibraryTile({
    required this.id,
    required this.nameCn,
    required this.nameEn,
    required this.imagePath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Hero(
        tag: 'home_library_$id',
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              imagePath,
              fit: BoxFit.fill,
              errorBuilder: (_, _, _) => Container(
                color: Colors.black12,
                child: Center(
                  child: Image.asset(
                    AppAssets.libraryPlaceholder,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final int count;

  const _SectionHeader({
    required this.label,
    required this.icon,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Icon(icon, size: 15, color: theme.hintColor),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '($count)',
            style: TextStyle(fontSize: 11, color: theme.hintColor),
          ),
        ],
      ),
    );
  }
}