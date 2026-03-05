import 'package:flutter/material.dart';
import '../../data/models/library_dto.dart';
import '../../data/repository/library_loader.dart';
import '../widgets/library_card_tile.dart';
import '../screens/library_filter_sheet.dart';
import 'library_detail_screen.dart';
import '../../../../core/theme/app_theme.dart';

class LibraryScreen extends StatefulWidget {
  final String? searchQuery;

  final void Function(bool isActive)? onFilterStateChanged;
  final void Function(VoidCallback openSheet)? onRegisterSheetOpener;

  const LibraryScreen({
    super.key,
    this.searchQuery,
    this.onFilterStateChanged,
    this.onRegisterSheetOpener,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final Future<List<LibraryDTO>> _cardsFuture;
  LibraryFilterState _filterState = const LibraryFilterState();

  @override
  void initState() {
    super.initState();
    _cardsFuture = LibraryLoader().getCards();
    widget.onRegisterSheetOpener?.call(_openFilterSheet);
  }

  void _openFilterSheet() {
    LibraryFilterSheet.show(
      context,
      initialState: _filterState,
      onChanged: (newState) {
        setState(() => _filterState = newState);
        widget.onFilterStateChanged?.call(newState.isActive);
      },
    );
  }

  Map<String, List<LibraryDTO>> _groupCards(List<LibraryDTO> cards) {
    final Map<String, List<LibraryDTO>> grouped = {};
    for (final card in cards) {
      grouped.putIfAbsent(card.categoryEn, () => []).add(card);
    }
    return Map.fromEntries(
      LibraryDTO.categoryOrder
          .where((cat) => grouped.containsKey(cat))
          .map((cat) => MapEntry(cat, grouped[cat]!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FutureBuilder<List<LibraryDTO>>(
      future: _cardsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        List<LibraryDTO> cards = snapshot.data ?? [];

        // Search
        final query = widget.searchQuery ?? '';
        if (query.isNotEmpty) {
          cards = cards.where((c) => c.matchesQuery(query)).toList();
        }

        // Filter + sort
        cards = _filterState.apply(cards);

        final groupedCards = _groupCards(cards);

        return CustomScrollView(
          slivers: [
            // ── Active filter summary bar
            if (_filterState.isActive)
              SliverToBoxAdapter(
                child: _ActiveFilterBar(
                  filterState: _filterState,
                  onClear: () {
                    setState(() => _filterState = const LibraryFilterState());
                    widget.onFilterStateChanged?.call(false);
                  },
                ),
              ),

            // ── Empty state
            if (cards.isEmpty)
              const SliverFillRemaining(
                child: Center(child: Text('No cards match your search.')),
              )
            else
              for (final entry in groupedCards.entries) ...[
                // Category header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 18,
                          decoration: BoxDecoration(
                            color: AppTheme.categoryColor(entry.key, isDark),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          entry.key.toUpperCase(),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppTheme.categoryColor(entry.key, isDark),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${entry.value.length}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor),
                        ),
                      ],
                    ),
                  ),
                ),
                // Card grid
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
                      (context, index) {
                        final card = entry.value[index];
                        return LibraryCardTile(
                          card: card,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => LibraryDetailScreen(card: card),
                            ),
                          ),
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
  }
}

// ── Active filter summary bar 
class _ActiveFilterBar extends StatelessWidget {
  final LibraryFilterState filterState;
  final VoidCallback onClear;

  const _ActiveFilterBar({
    required this.filterState,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <String>[];

    if (filterState.categories.isNotEmpty) {
      parts.add(filterState.categories.join(', '));
    }
    if (filterState.hasRangeOnly) parts.add('Has Range');
    if (filterState.sortOrder != LibrarySortOrder.none) {
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