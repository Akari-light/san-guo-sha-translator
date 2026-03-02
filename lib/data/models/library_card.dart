class LibraryCard {
  final String id;
  final String nameCn;
  final String nameEn;
  final String categoryEn;
  final List<String> effectCn;
  final List<String> effectEn;
  final List<String>? aliasEn;
  final int? range;
  final List<Map<String, String>> faq;

  LibraryCard({
    required this.id,
    required this.nameCn,
    required this.nameEn,
    required this.categoryEn,
    required this.effectCn,
    required this.effectEn,
    this.aliasEn,
    this.range,
    required this.faq,
  });

  factory LibraryCard.fromJson(Map<String, dynamic> json) {
    return LibraryCard(
      id: json['id'],
      nameCn: json['name_cn'],
      nameEn: json['name_en'],
      categoryEn: json['category_en'],
      // CHANGED: Map as List<String>
      effectCn: List<String>.from(json['effect_cn'] ?? []),
      effectEn: List<String>.from(json['effect_en'] ?? []),
      aliasEn: json['alias_en'] != null ? List<String>.from(json['alias_en']) : null,
      range: json['range'],
      faq: (json['faq'] as List).map((item) => Map<String, String>.from(item)).toList(),
    );
  }

  String get imagePath => 'assets/images/cards/$id.webp';
}