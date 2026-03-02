import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/library_card.dart';

class LibraryRepository {
  static final LibraryRepository _instance = LibraryRepository._internal();
  factory LibraryRepository() => _instance;
  LibraryRepository._internal();

  List<LibraryCard>? _cachedCards;

  Future<List<LibraryCard>> getCards() async {
    if (_cachedCards != null) return _cachedCards!;

    // List of all your new split files
    final List<String> jsonFiles = [
      'assets/data/library/basic.json',
      'assets/data/library/tools.json',
      'assets/data/library/weapons.json',
      'assets/data/library/armor.json',
      'assets/data/library/mounts.json',
      'assets/data/library/treasure.json',
    ];

    List<LibraryCard> allCards = [];

    try {
      for (var file in jsonFiles) {
        final String response = await rootBundle.loadString(file);
        final List<dynamic> data = json.decode(response);
        allCards.addAll(data.map((json) => LibraryCard.fromJson(json)).toList());
      }
      _cachedCards = allCards;
    } catch (e) {
      print("Error loading JSON files: $e");
    }
    
    return allCards;
  }
}