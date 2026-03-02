import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/library_card.dart';

class LibraryRepository {
  static final LibraryRepository _instance = LibraryRepository._internal();
  factory LibraryRepository() => _instance;
  LibraryRepository._internal();

  List<LibraryCard>? _cachedCards;

  Future<List<LibraryCard>> getCards() async {
    // If we already have the cards in memory, return them immediately
    if (_cachedCards != null) return _cachedCards!;

    // Define all the category files to be loaded
    final List<String> categoryFiles = [
      'assets/data/library/basic.json',
      'assets/data/library/tools.json',
      'assets/data/library/equipment.json',
      'assets/data/library/mounts.json',
      'assets/data/library/treasure.json',
    ];

    List<LibraryCard> allLoadedCards = [];

    try {
      for (String filePath in categoryFiles) {
        final String response = await rootBundle.loadString(filePath);
        final List<dynamic> data = json.decode(response);
        
        // Convert the JSON list into LibraryCard objects
        final List<LibraryCard> categoryCards = data.map((json) {
          return LibraryCard.fromJson(json);
        }).toList();

        allLoadedCards.addAll(categoryCards);
      }
      
      _cachedCards = allLoadedCards;
    } catch (e) {
      // Handle potential file loading or parsing errors
      print("Error loading library categories: $e");
      return [];
    }
    
    return _cachedCards!;
  }
}