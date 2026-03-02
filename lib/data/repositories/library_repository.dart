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

    final String response = await rootBundle.loadString('assets/data/library.json');
    final List<dynamic> data = json.decode(response);
    _cachedCards = data.map((json) => LibraryCard.fromJson(json)).toList();
    
    return _cachedCards!;
  }
}