import 'package:flutter/material.dart';
import '../../data/models/library_dto.dart';
import '../../data/repositories/library_loader.dart';
import 'library_detail_screen.dart';

class LibraryScreen extends StatelessWidget {
  final String? searchQuery;
  const LibraryScreen({super.key, this.searchQuery});

  Map<String, List<LibraryDTO>> _groupCards(List<LibraryDTO> cards) {
    Map<String, List<LibraryDTO>> grouped = {};
    for (var card in cards) {
      grouped.putIfAbsent(card.categoryEn, () => []).add(card);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    // Accessing the theme's color scheme for responsive colors
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<List<LibraryDTO>>(
      future: LibraryLoader().getCards(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        List<LibraryDTO> cards = snapshot.data ?? [];
        
        if (searchQuery != null && searchQuery!.isNotEmpty) {
          final query = searchQuery!.toLowerCase();
          cards = cards.where((c) => 
            c.nameEn.toLowerCase().contains(query) || 
            c.nameCn.contains(searchQuery!)
          ).toList();
        }

        if (cards.isEmpty) return const Center(child: Text('No cards match your search.'));

        final groupedCards = _groupCards(cards);

        return CustomScrollView(
          slivers: [
            for (var entry in groupedCards.entries) ...[
              SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text(
                  entry.key.toUpperCase(), // Uppercase adds a clean, "section" feel
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800, // Extra bold for contrast
                    letterSpacing: 1.2,
                    // Uses the high-contrast primary color we defined in AppTheme
                    color: Theme.of(context).colorScheme.primary, 
                  ),
                ),
              ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, // Updated to 3 cards per row
                    childAspectRatio: 0.7,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final card = entry.value[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LibraryDetailScreen(card: card),
                            ),
                          );
                        },
                        child: Hero(
                          tag: card.id,
                          child: _buildCard(card),
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

  Widget _buildCard(LibraryDTO card) {
    return Container(
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
          card.imagePath,
          fit: BoxFit.fill,
          errorBuilder: (context, error, stackTrace) => Container(
            color: Colors.black12,
            child: Center(
              child: Image.asset(
                'assets/images/library_placeholder.webp', 
                fit: BoxFit.contain
              ),
            ),
          ),
        ),
      ),
    );
  }
}