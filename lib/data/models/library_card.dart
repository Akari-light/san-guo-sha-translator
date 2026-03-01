class LibraryCard {
  final String id;
  final String nameCn;
  final String nameEn;
  final String categoryEn;
  final String effectEn;
  final List<String>? aliasEn;
  final int? range;
  final List<Map<String, String>> faq;

  LibraryCard({
    required this.id,
    required this.nameCn,
    required this.nameEn,
    required this.categoryEn,
    required this.effectEn,
    this.aliasEn,
    this.range,
    required this.faq,
  });

  // Factory to create a Card object from JSON
  factory LibraryCard.fromJson(Map<String, dynamic> json) {
    return LibraryCard(
      id: json['id'],
      nameCn: json['name_cn'],
      nameEn: json['name_en'],
      categoryEn: json['category_en'],
      effectEn: json['effect_en'],
      aliasEn: json['alias_en'] != null ? List<String>.from(json['alias_en']) : null,
      range: json['range'],
      // Maps the list of FAQ objects from the JSON
      faq: (json['faq'] as List).map((item) => Map<String, String>.from(item)).toList(),
    );
  }

  // Helper to get the image path. Professionally, we use the ID to find the file.
  String get imagePath => 'assets/images/cards/$id.webp';
}