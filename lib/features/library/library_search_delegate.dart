import 'package:flutter/material.dart';
import '../../data/models/library_card.dart';

class LibrarySearchDelegate extends SearchDelegate<String?> {
  final List<LibraryCard> allCards;

  LibrarySearchDelegate({required this.allCards});

  @override
  String get searchFieldLabel => 'Search (e.g. 杀, Peach)';

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) {
    close(context, query); // Returns the typed text to the main screen
    return const SizedBox.shrink();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) {
      return const Center(child: Text('Type to filter the library grid'));
    }
    return _buildList(context);
  }

  Widget _buildList(BuildContext context) {
    final results = allCards.where((card) {
      final input = query.toLowerCase();
      return card.nameEn.toLowerCase().contains(input) || card.nameCn.contains(input);
    }).toList();

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final card = results[index];
        return ListTile(
          title: Text(card.nameEn),
          subtitle: Text(card.nameCn),
          onTap: () => close(context, card.nameEn), // Return card name to filter grid
        );
      },
    );
  }
}