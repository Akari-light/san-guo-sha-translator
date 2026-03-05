import 'package:flutter/material.dart';

class LibraryDTO {
  final String id;
  final String nameCn;
  final String nameEn;
  final String categoryEn;
  final String categoryCn;
  final List<String> effectCn;
  final List<String> effectEn;
  final List<String>? aliasEn;
  final int? range;
  final List<Map<String, String>> faq;

  LibraryDTO({
    required this.id,
    required this.nameCn,
    required this.nameEn,
    required this.categoryEn,
    required this.categoryCn,
    required this.effectCn,
    required this.effectEn,
    this.aliasEn,
    this.range,
    required this.faq,
  });

  factory LibraryDTO.fromJson(Map<String, dynamic> json) {
    return LibraryDTO(
      id: json['id'],
      nameCn: json['name_cn'],
      nameEn: json['name_en'],
      categoryEn: json['category_en'],
      categoryCn: json['category_cn'],
      effectCn: List<String>.from(json['effect_cn'] ?? []),
      effectEn: List<String>.from(json['effect_en'] ?? []),
      aliasEn: json['alias_en'] != null ? List<String>.from(json['alias_en']) : null,
      range: json['range'],
      faq: (json['faq'] as List).map((item) => Map<String, String>.from(item)).toList(),
    );
  }

  // ── Image
  String get imagePath => 'assets/images/library/$id.webp';
  static const String placeholderImagePath = 'assets/images/library_placeholder.webp';

  // ── Search 
  bool matchesQuery(String query) {
    final q = query.toLowerCase();
    final matchesName = nameEn.toLowerCase().contains(q) || nameCn.contains(query);
    final matchesAlias = aliasEn?.any((a) => a.toLowerCase().contains(q)) ?? false;
    return matchesName || matchesAlias;
  }

  // ── Category 
  /// Defines the display order of categories in the library grid.
  static const List<String> categoryOrder = ['Basic','Weapon','Armor','Mount','Tool','Treasure',];

  // ── Misc
  /// Returns the theme-aware color for this card's category.
  /// Used by both the grid tile and the detail screen.
  Color categoryColor(bool isDark) {
    switch (categoryEn) {
      case 'Basic':   return isDark ? Colors.greenAccent : Colors.green.shade700;
      case 'Weapon':  return isDark ? Colors.redAccent : Colors.red.shade700;
      case 'Armor':   return isDark ? Colors.blueAccent : Colors.blue.shade700;
      case 'Mount':   return isDark ? const Color(0xFFD2B48C) : Colors.brown;
      case 'Tool':    return isDark ? Colors.orangeAccent : Colors.orange.shade800;
      case 'Treasure': return isDark ? Colors.purpleAccent : Colors.purple.shade700;
      default:        return Colors.grey;
    }
  }
}