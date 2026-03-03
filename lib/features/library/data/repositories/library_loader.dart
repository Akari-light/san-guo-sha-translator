import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/library_dto.dart';

class LibraryLoader { // Renamed from LibraryRepository
  static final LibraryLoader _instance = LibraryLoader._internal();
  factory LibraryLoader() => _instance;
  LibraryLoader._internal();

  List<LibraryDTO>? _cachedCards;

  Future<List<LibraryDTO>> getCards() async {
    if (_cachedCards != null) return _cachedCards!;

    final List<String> jsonFiles = [
      'assets/data/library/basic.json',
      'assets/data/library/tools.json',
      'assets/data/library/weapons.json',
      'assets/data/library/armor.json',
      'assets/data/library/mounts.json',
      'assets/data/library/treasure.json',
    ];

    List<LibraryDTO> allCards = [];

    try {
      for (var file in jsonFiles) {
        final String response = await rootBundle.loadString(file);
        final List<dynamic> data = json.decode(response);
        allCards.addAll(data.map((json) => LibraryDTO.fromJson(json)).toList());
      }
      _cachedCards = allCards;
    } catch (e) {
      print("Error loading JSON files: $e");
    }
    
    return allCards;
  }
}