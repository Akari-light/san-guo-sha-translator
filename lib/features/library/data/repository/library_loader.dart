import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../models/library_dto.dart';

class LibraryLoader {
  // ── Setup
  static final LibraryLoader _instance = LibraryLoader._internal();
  factory LibraryLoader() => _instance;
  LibraryLoader._internal();

  // ── Cache Data
  List<LibraryDTO>? _cachedCards;

  // ── Config
  /// To add a new library type, add its file path here
  static const List<String> _libraryFiles = [
    'assets/data/library/basic.json',
    'assets/data/library/weapons.json',
    'assets/data/library/armor.json',
    'assets/data/library/mounts.json',
    'assets/data/library/tools.json',
    'assets/data/library/treasure.json',
  ];

  // ── Public API ─────────────────────────────────────────────────────────────
   Future<List<LibraryDTO>> getCards() async {
    if (_cachedCards != null) return _cachedCards!;

    final List<LibraryDTO> allCards = [];

    try {
      for (final file in _libraryFiles) {
        final String response = await rootBundle.loadString(file);
        final List<dynamic> data = json.decode(response);
        allCards.addAll(data.map((json) => LibraryDTO.fromJson(json)).toList());
      }
      _cachedCards = allCards;
      debugPrint('[LibraryLoader] Loaded ${allCards.length} cards total');
    } catch (e) {
      debugPrint('[LibraryLoader] Failed to load library files: $e');
    }

    return allCards;
  }

  Future<List<LibraryDTO>> getByCategory(String category) async {
    final all = await getCards();
    return all.where((c) => c.categoryEn == category).toList();
  }

  Future<LibraryDTO?> findById(String id) async {
    final all = await getCards();
    try {
      return all.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  void clearCache() {
    _cachedCards = null;
  }
}