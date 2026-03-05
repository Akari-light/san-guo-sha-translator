import 'package:flutter/material.dart';
import '../../data/models/library_dto.dart';
import '../../data/repository/library_loader.dart';
import '../widgets/library_card_tile.dart';
import 'library_detail_screen.dart';

class LibraryScreen extends StatefulWidget {
  final String? searchQuery;
  const LibraryScreen({super.key, this.searchQuery});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final Future<List<LibraryDTO>> _cardsFuture;

  @override
  void initState() {
    super.initState();
    _cardsFuture = LibraryLoader().getCards();
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
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<List<LibraryDTO>>(
      future: _cardsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        List<LibraryDTO> cards = snapshot.data ?? [];
        final query = widget.searchQuery;
        if (query != null && query.isNotEmpty) {
          cards = cards.where((c) => c.matchesQuery(query)).toList();
        }

        if (cards.isEmpty) {
          return const Center(child: Text('No cards match your search.'));
        }

        final groupedCards = _groupCards(cards);

        return CustomScrollView(
          slivers: [
            for (final entry in groupedCards.entries) ...[
              // Category header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text(
                    entry.key.toUpperCase(),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
              // Card grid
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                            builder: (context) => LibraryDetailScreen(card: card),
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