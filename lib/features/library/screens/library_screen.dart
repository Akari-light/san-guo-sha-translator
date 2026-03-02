import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/models/library_card.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  // Function to load and parse the JSON file
  Future<List<LibraryCard>> _loadCards() async {
    final String response = await rootBundle.loadString('assets/data/library.json');
    final List<dynamic> data = json.decode(response);
    return data.map((json) => LibraryCard.fromJson(json)).toList();
  }

  // Helper to group cards by category
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
    future: _loadCards(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      } else if (snapshot.hasError) {
        return Center(child: Text('Error: ${snapshot.error}'));
      }

      if (!snapshot.hasData || snapshot.data!.isEmpty) {
        return const Center(child: Text('No cards found in library.'));
      }
      
      final groupedCards = _groupCards(snapshot.data!);

      // THE FIX: ScrollConfiguration removes the stretching at scroll limits
      return ScrollConfiguration(
        behavior: const ScrollBehavior().copyWith(overscroll: false),
        child: CustomScrollView(
          physics: const ClampingScrollPhysics(), // Stops the 'bounce'
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
                      childAspectRatio: 0.7, // Fixed ratio
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
          fit: BoxFit.contain, // Fixed image fitting
          errorBuilder: (context, error, stackTrace) => Stack(
            // Removed Alignment.center to allow Positioned to work
            children: [
              Center(
                child: Image.asset(
                  'assets/images/library_placeholder.webp', 
                  fit: BoxFit.contain
                ),
              ),
              // THE FIX: Pins the icon to the top right
              const Positioned(
                top: 4,
                right: 4,
                child: Icon(Icons.report_problem, color: Colors.amber, size: 18),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}

// Header Delegate for Sticky Headers
class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  _SectionHeaderDelegate({required this.title});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.95),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
      ),
    );
  }

  @override
  double get maxExtent => 40;
  @override
  double get minExtent => 40;
  @override
  bool shouldRebuild(covariant _SectionHeaderDelegate oldDelegate) => title != oldDelegate.title;
}