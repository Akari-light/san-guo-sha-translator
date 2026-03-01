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
          // physics: Adds that smooth "rebound" feel on iOS/Android
          physics: const BouncingScrollPhysics(), 
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.7, // Keeps the card shape static
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: cards.length,
          itemBuilder: (context, index) {
            final card = cards[index];
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                color: Colors.grey, // Background color while loading
                child: Image.asset(
                  card.imagePath,
                  fit: BoxFit.contain,
                  cacheWidth: 300,
                  // This triggers if the image is missing from the assets folder
                  errorBuilder: (context, error, stackTrace) {
                    // 1. Log the bug internally for debugging
                    debugPrint('BUG: Missing asset for card ${card.id} at ${card.imagePath}');

                    // 2. Return the placeholder image so the UI doesn't break
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.asset('assets/images/library_placeholder.webp', fit: BoxFit.contain),
                        // 3. Visual "Bug" indicator for the user
                        const Positioned(
                          top: 5,
                          right: 5,
                          child: Icon(Icons.report_problem, color: Colors.amber, size: 20),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}