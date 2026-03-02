import 'package:flutter/material.dart';
import '../../../data/models/library_card.dart';
import '../../../data/repositories/library_repository.dart';
import 'library_detail_screen.dart';

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
        
        if (searchQuery != null && searchQuery!.isNotEmpty) {
          final query = searchQuery!.toLowerCase();
          cards = cards.where((c) => 
            c.nameEn.toLowerCase().contains(query) || 
            c.nameCn.contains(searchQuery!)
          ).toList();
        }

        if (cards.isEmpty) return const Center(child: Text('No cards match your search.'));
        
        final groupedMap = _groupCards(cards);

        return CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            for (var entry in groupedMap.entries) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Text(
                    entry.key,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.7,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final card = entry.value[index];
                      return GestureDetector(
                        onTap: () async {
                          // 1. Kill keyboard focus to prevent ImeTracker deadlock
                          FocusManager.instance.primaryFocus?.unfocus();

                          // 2. Small delay to allow the keyboard to hide before the Hero animation starts
                          await Future.delayed(const Duration(milliseconds: 50));
                          
                          if (!context.mounted) return;

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LibraryDetailScreen(card: card),
                            ),
                          );
                        },
                        child: Hero(
                          tag: card.id, // Ensure this ID is unique and matches the Detail Screen
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

  Widget _buildCard(LibraryCard card) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: Colors.black12,
        child: Image.asset(
          card.imagePath,
          fit: BoxFit.fill, // Ensures image fills the 0.7 grid cell perfectly
          errorBuilder: (context, error, stackTrace) => Stack(
            children: [
              Center(child: Image.asset('assets/images/library_placeholder.webp', fit: BoxFit.contain)),
              const Positioned(top: 4, right: 4, child: Icon(Icons.report_problem, color: Colors.amber, size: 18)),
            ],
          ),
        ),
      ),
    );
  }
}