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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LibraryCard>>(
      future: _loadCards(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Error: ${snapshot.error}'), 
            ),
          );
        }

        final cards = snapshot.data ?? [];

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, // 3 columns for professional card layout
            childAspectRatio: 0.7, // Rectangular card shape
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: cards.length,
          itemBuilder: (context, index) {
            final card = cards[index];
            return Card(
              elevation: 4,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Expanded(
                    child: Image.asset(
                      'assets/images/library_placeholder.webp', // Placeholder from your assets
                      fit: BoxFit.cover,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(
                      card.nameEn,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}