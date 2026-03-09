/// [id]      — unique skin ID
/// [baseId]  — the specific expansion variant this skin belongs to (e.g. "mo.QUN003", NOT the standard_id "char_diaocan")
/// [nameCn]  — display label shown on the art-swap button (Chinese)
/// [nameEn]  — display label shown on the art-swap button (English)
class SkinDTO {
  final String id;
  final String baseId;
  final String nameCn;
  final String nameEn;

  const SkinDTO({
    required this.id,
    required this.baseId,
    required this.nameCn,
    required this.nameEn,
  });

  String get imagePath => 'assets/images/generals/$id.webp';

  factory SkinDTO.fromJson(Map<String, dynamic> json) {
    return SkinDTO(
      id:     json['id']      as String,
      baseId: json['base_id'] as String,
      nameCn: json['name_cn'] as String,
      nameEn: json['name_en'] as String,
    );
  }
}