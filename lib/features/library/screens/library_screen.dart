import 'package:flutter/material.dart';
import '../../../data/models/library_card.dart';
import '../../../data/repositories/library_repository.dart';

class LibraryScreen extends StatelessWidget {
  final String? searchQuery;
  const LibraryScreen({super.key, this.searchQuery});

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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        List<LibraryCard> cards = snapshot.data ?? [];
        
        // Filter logic for the grid
        if (searchQuery != null && searchQuery!.isNotEmpty) {
          cards = cards.where((c) => 
            c.nameEn.toLowerCase().contains(searchQuery!.toLowerCase()) || 
            c.nameCn.contains(searchQuery!)
          ).toList();
        }

        if (cards.isEmpty) return const Center(child: Text('No cards match your search.'));
        
        final groupedCards = _groupCards(cards);

        return ScrollConfiguration(
          behavior: const ScrollBehavior().copyWith(overscroll: false),
          child: CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: groupedCards.entries.map((entry) {
              return SliverMainAxisGroup(
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _SectionHeaderDelegate(title: entry.key),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.all(8.0),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.7,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildCard(entry.value[index]),
                        childCount: entry.value.length,
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildCard(LibraryCard card) {
    return AspectRatio(
      aspectRatio: 0.7,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: Colors.black12,
          child: Image.asset(
            card.imagePath,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Stack(
              children: [
                Center(child: Image.asset('assets/images/library_placeholder.webp', fit: BoxFit.contain)),
                const Positioned(top: 4, right: 4, child: Icon(Icons.report_problem, color: Colors.amber, size: 18)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  _SectionHeaderDelegate({required this.title});
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(
    color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.95),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
  );
  @override
  double get maxExtent => 40;
  @override
  double get minExtent => 40;
  @override
  bool shouldRebuild(covariant _SectionHeaderDelegate oldDelegate) => title != oldDelegate.title;
}