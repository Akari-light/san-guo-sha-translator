import '../../../../core/services/search_service.dart';

class LibraryDTO {
  final String id;
  final String nameCn;
  final String nameEn;
  final String categoryEn;
  final String categoryCn;
  final String? subCategoryEn;
  final String? subCategoryCn;
  final List<String> effectCn;
  final List<String> effectEn;
  final int? range;
  final List<Map<String, String>> faq;

  LibraryDTO({
    required this.id,
    required this.nameCn,
    required this.nameEn,
    required this.categoryEn,
    required this.categoryCn,
    this.subCategoryEn,
    this.subCategoryCn,
    required this.effectCn,
    required this.effectEn,
    this.range,
    required this.faq,
  });

  factory LibraryDTO.fromJson(Map<String, dynamic> json) {
    return LibraryDTO(
      id:             json['id'],
      nameCn:         json['name_cn'],
      nameEn:         json['name_en'],
      categoryEn:     json['category_en'],
      categoryCn:     json['category_cn'],
      subCategoryEn:  json['sub_category_en'],
      subCategoryCn:  json['sub_category_cn'],
      effectCn:       List<String>.from(json['effect_cn'] ?? []),
      effectEn:       List<String>.from(json['effect_en'] ?? []),
      range:          json['range'],
      faq:            (json['faq'] as List).map((item) => Map<String, String>.from(item)).toList(),
    );
  }

  // ── Derived helpers
  /// True for time-delay tool cards — displayed landscape (rotated).
  bool get isHorizontal =>
      subCategoryEn == 'Time-delay' || subCategoryCn == '延时锦囊牌';

  // ── Image
  String get imagePath => 'assets/images/library/$id.webp';

  // ── Search
  /// Fuzzy matches against English name, Chinese name, and category.
  /// Pinyin conversion in SearchService means Chinese targets are also
  /// searchable by pinyin — "nan man" finds 南蛮入侵, "sha" finds 杀.
  bool matchesQuery(String query) {
    if (query.isEmpty) { return true; }
    if (SearchService.fuzzyMatch(query, nameEn))     { return true; }
    if (SearchService.fuzzyMatch(query, nameCn))     { return true; }
    if (SearchService.fuzzyMatch(query, categoryEn)) { return true; }
    return false;
  }

  // ── Category
  static const List<String> categoryOrder = [
    'Basic',
    'Tool',
    'Weapon',
    'Armor',
    'Treasure',
    'Mount',
  ];
}