import 'package:flutter/material.dart';
import '../../data/models/general_card.dart';
import '../../data/repository/general_loader.dart';
import '../widgets/general_card_tile.dart';
import '../screens/general_filter_sheet.dart';
import '../screens/general_detail_screen.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/recently_viewed_service.dart';

class GeneralScreen extends StatefulWidget {
  /// Live search notifier. main.dart updates this without rebuilding
  /// the screen widget, so the FutureBuilder cache is never discarded.
  final ValueNotifier<String> searchNotifier;

  /// Called when filter active state changes so main.dart
  /// can update the AppBar filter icon badge.
  final void Function(bool isActive)? onFilterStateChanged;

  /// Called by main.dart when the filter icon is tapped.
  final void Function(VoidCallback openSheet)? onRegisterSheetOpener;

  /// Forwarded to GeneralDetailScreen for Related Card chip navigation.
  /// main.dart resolves the id and pushes LibraryDetailScreen.
  final void Function(String libraryCardId)? onLibraryCardTap;

  /// Called by main.dart when a general card tile is tapped, before the
  /// detail push. main.dart uses this hook to record the view in HomeService.
  /// When null the screen pushes the detail screen directly without recording.
  final void Function(String id, RecordType type)? onCardTap;

  const GeneralScreen({
    super.key,
    required this.searchNotifier,
    this.onFilterStateChanged,
    this.onRegisterSheetOpener,
    this.onLibraryCardTap,
    this.onCardTap,
  });

  @override
  State<GeneralScreen> createState() => _GeneralScreenState();
}

class _GeneralScreenState extends State<GeneralScreen> {
  late final Future<List<GeneralCard>> _generalsFuture;
  GeneralFilterState _filterState = const GeneralFilterState();

  static const List<String> _factionOrder = [
    'Shu', 'Wei', 'Wu', 'Qun', 'God', 'Utilities',
  ];

  @override
  void initState() {
    super.initState();
    _generalsFuture = GeneralLoader().getGenerals();
    widget.onRegisterSheetOpener?.call(_openFilterSheet);
  }

  @override
  void didUpdateWidget(GeneralScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-register if the parent passes a new callback reference.
    // Necessary because onRegisterSheetOpener fires a side effect —
    // it must be re-invoked whenever the prop changes, not only at mount.
    if (widget.onRegisterSheetOpener != oldWidget.onRegisterSheetOpener) {
      widget.onRegisterSheetOpener?.call(_openFilterSheet);
    }
  }

  void _openFilterSheet() {
    GeneralFilterSheet.show(
      context,
      initialState: _filterState,
      onChanged: (newState) {
        setState(() => _filterState = newState);
        widget.onFilterStateChanged?.call(newState.isActive);
      },
    );
  }

  Map<String, List<GeneralCard>> _groupByFaction(List<GeneralCard> generals) {
    final Map<String, List<GeneralCard>> grouped = {};
    for (final g in generals) {
      grouped.putIfAbsent(g.faction, () => []).add(g);
    }
    return Map.fromEntries(
      _factionOrder
          .where((f) => grouped.containsKey(f))
          .map((f) => MapEntry(f, grouped[f]!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: widget.searchNotifier,
      builder: (context, query, _) {
        return FutureBuilder<List<GeneralCard>>(
          future: _generalsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final raw      = snapshot.data ?? [];
            final searched = query.isEmpty
                ? raw
                : raw.where((g) => g.matchesQuery(query)).toList();
            final generals       = _filterState.apply(searched);
            final groupedGenerals = _groupByFaction(generals);

        return CustomScrollView(
          slivers: [
            // ── Active filter summary bar 
            if (_filterState.isActive)
              SliverToBoxAdapter(
                child: _ActiveFilterBar(
                  filterState: _filterState,
                  onClear: () {
                    setState(() => _filterState = const GeneralFilterState());
                    widget.onFilterStateChanged?.call(false);
                  },
                ),
              ),

            // ── Empty state 
            if (generals.isEmpty)
              const SliverFillRemaining(
                child: Center(child: Text('No generals match your search.')),
              )
            else
              for (final entry in groupedGenerals.entries) ...[
                // Faction header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 18,
                          decoration: BoxDecoration(
                            color: AppTheme.factionColor(entry.key),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          entry.key.toUpperCase(),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppTheme.factionColor(entry.key),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${entry.value.length}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Theme.of(context).hintColor),
                        ),
                      ],
                    ),
                  ),
                ),
                // General grid
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.716, // SGS card ratio: 63mm / 88mm = 0.716
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final card = entry.value[index];
                        return GeneralCardTile(
                          card: card,
                          onTap: () {
                            if (widget.onCardTap != null) {
                              // main.dart records the view then pushes the detail.
                              widget.onCardTap!(card.id, RecordType.general);
                            } else {
                              Navigator.push(
                                context,
                                detailRoute(GeneralDetailScreen(
                                  card: card,
                                  onLibraryCardTap: widget.onLibraryCardTap,
                                )),
                              );
                            }
                          },
                        );
                      },
                      childCount: entry.value.length,
                    ),
                  ),
                ),
              ],

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        );
      },
    );
      },
    );
  }
}

// ── Active filter summary bar 
class _ActiveFilterBar extends StatelessWidget {
  final GeneralFilterState filterState;
  final VoidCallback onClear;

  const _ActiveFilterBar({
    required this.filterState,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <String>[];

    if (filterState.factions.isNotEmpty) {
      parts.add(filterState.factions.join(', '));
    }
    if (filterState.expansions.isNotEmpty) {
      parts.add(filterState.expansions.map((e) => e.badge).join(', '));
    }
    if (filterState.lordOnly) parts.add('Lord Only');
    if (filterState.sortOrder != GeneralSortOrder.none) {
      parts.add(filterState.sortOrder.label);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.primary.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(Icons.filter_list, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              parts.join(' · '),
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: Icon(Icons.close, size: 16, color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }
}