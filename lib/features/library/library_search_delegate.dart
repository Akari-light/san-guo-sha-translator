import 'package:flutter/material.dart';
import '../../../data/models/library_card.dart';
import '../../../data/repositories/library_repository.dart';

class LibraryScreen extends StatelessWidget {
  final String searchQuery;
  const LibraryScreen({super.key, required this.searchQuery});

  Map<String, List<LibraryCard>> _groupCards(List<LibraryCard> cards) {
    Map<String, List<LibraryCard>> grouped = {};
    for (var card in cards) {
      grouped.putIfAbsent(card.categoryEn, () => []).add(card);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LibraryCard>>(
      future: LibraryRepository().getCards(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        // LIVE FILTER LOGIC
        final filteredCards = snapshot.data!.where((card) {
          final query = searchQuery.toLowerCase();
          return card.nameEn.toLowerCase().contains(query) || 
                 card.nameCn.contains(query);
        }).toList();

        if (filteredCards.isEmpty) {
          return const Center(child: Text('No matching cards found.'));
        }

        final groupedCards = _groupCards(filteredCards);

        return CustomScrollView(
          slivers: groupedCards.entries.map((entry) {
            return SliverMainAxisGroup(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SectionHeaderDelegate(title: entry.key),
                ),
                SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.7,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildCard(entry.value[index]),
                    childCount: entry.value.length,
                  ),
                ),
              ],
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildCard(LibraryCard card) {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Image.asset(card.imagePath, fit: BoxFit.contain),
    );
  }
}

// Keep your _SectionHeaderDelegate at the bottom...