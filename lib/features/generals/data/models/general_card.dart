import '../../../../core/models/skill_dto.dart';
import '../../../../core/models/expansion.dart';
import '../../../../core/services/search_service.dart';

/// Example JSON entry (from limit_break.json):
/// {
///   "id": "JX_SHU001",
///   "standard_id": "char_liubei",
///   "name_cn": "界刘备",
///   "name_en": "Liu Bei",
///   "gender": "Male",
///   "faction": "Shu",
///   "health": 4,
///   "power_index": 3.0,
///   "traits_cn": ["进攻", "辅助", "回复"],
///   "traits_en": ["Aggressive", "Support", "Recovery"],
///   "expansion": "Limit Break",
///   "skills": [
///     {
///       "skill_type": "active",
///       "name_cn": "仁德",
///       "name_en": "Benevolence",
///       "description_cn": "...",
///       "description_en": "..."
///     }
///   ]
/// }

class GeneralCard {
  final String id;
  final String standardId;
  final String nameCn;
  final String nameEn;
  final String gender;
  final String faction;
  final int health;
  final double powerIndex;
  final List<String> traitsCn;
  final List<String> traitsEn;
  final Expansion expansion;
  final List<SkillDTO> skills;
  final List<Map<String, String>> faq;

  const GeneralCard({
    required this.id,
    required this.standardId,
    required this.nameCn,
    required this.nameEn,
    required this.gender,
    required this.faction,
    required this.health,
    required this.powerIndex,
    required this.traitsCn,
    required this.traitsEn,
    required this.expansion,
    required this.skills,
    this.faq = const [],
  });

  factory GeneralCard.fromJson(
    Map<String, dynamic> json,
    // skillMap retained for API compatibility but is no longer used —
    // skills are now stored as inline objects in each general's JSON entry.
    Map<String, SkillDTO> skillMap,
  ) {
    final rawSkills = json['skills'] as List? ?? [];

    return GeneralCard(
      id:          json['id']          as String,
      standardId:  json['standard_id'] as String,
      nameCn:      json['name_cn']     as String,
      nameEn:      json['name_en']     as String,
      gender:      json['gender']      as String,
      faction:     json['faction']     as String,
      health:      json['health']      as int,
      powerIndex:  (json['power_index'] as num).toDouble(),
      traitsCn:    List<String>.from(json['traits_cn'] ?? []),
      traitsEn:    List<String>.from(json['traits_en'] ?? []),
      expansion:   Expansion.fromString(json['expansion'] as String),
      // Skills are inline objects — parse each one directly.
      // Entries that are plain strings (legacy skill IDs) are looked up in
      // skillMap as a fallback so older data files don't break.
      skills: rawSkills.map<SkillDTO?>((entry) {
        if (entry is Map<String, dynamic>) {
          // Inline skill object — preferred format
          return SkillDTO.fromJson('inline', entry);
        } else if (entry is String) {
          // Legacy: skill ID string referencing skills.json
          return skillMap[entry];
        }
        return null;
      }).whereType<SkillDTO>().toList(),
      faq: (json['faq'] as List? ?? [])
          .map((item) => Map<String, String>.from(item as Map))
          .toList(),
    );
  }

  // ── Search
  /// Fuzzy matches against:
  ///   - English name, Chinese name, serial ID
  ///   - English and Chinese skill names
  ///
  /// Short queries (< 3 chars) use exact contains only.
  /// Longer queries additionally use trigram similarity so typos
  /// and partial matches ("liu bei", "luu bei", "benev") all resolve.
  bool matchesQuery(String query) {
    if (query.isEmpty) return true;
    if (SearchService.fuzzyMatch(query, nameEn)) return true;
    if (SearchService.fuzzyMatch(query, nameCn)) return true;
    if (SearchService.fuzzyMatch(query, id))     return true;
    if (skills.any((s) => SearchService.fuzzyMatch(query, s.nameEn) ||  SearchService.fuzzyMatch(query, s.nameCn))) return true;
    return false;
  }

  // ── Image
  String get imagePath => 'assets/images/generals/$id.webp';

  // ── Expansion
  String get expansionBadge => expansion.badge;

  // ── Faction
  String get factionCn {
    switch (faction) {
      case 'Shu':  return '蜀';
      case 'Wei':  return '魏';
      case 'Wu':   return '吴';
      case 'Qun':  return '群';
      case 'God':  return '神';
      default:     return faction;
    }
  }

  // ── Power Index
  /// Returns half-star increments up to 5 stars.
  String get powerStars {
    final full = powerIndex.floor();
    final half = (powerIndex - full) >= 0.5;
    return '★' * full + (half ? '☆' : '');
  }
}