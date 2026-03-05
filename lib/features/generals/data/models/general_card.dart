import '../../../../core/models/skill_dto.dart';

/// Example JSON entry (from limit_break.json):
/// {
///   "id": "jx.SHU001",
///   "standard_id": "char_liubei",
///   "name_cn": "界刘备",
///   "name_en": "Liu Bei",
///   "gender": "Male",
///   "faction": "Shu",
///   "health": 4,
///   "power_index": 3.0,
///   "traits": ["进攻", "辅助", "回复"],
///   "expansion": "Limit Break",
///   "skills": ["skill_rende", "skill_jijiang"]
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
  final List<String> traits;
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
    required this.traits,
    required this.expansion,
    required this.skills,
    this.faq = const [],
  });
  
  factory GeneralCard.fromJson(
    Map<String, dynamic> json,
    Map<String, SkillDTO> skillMap,
  ) {
    final rawSkillIds = List<String>.from(json['skills'] ?? []);

    return GeneralCard(
      id: json['id'] as String,
      standardId: json['standard_id'] as String,
      nameCn: json['name_cn'] as String,
      nameEn: json['name_en'] as String,
      gender: json['gender'] as String,
      faction: json['faction'] as String,
      health: json['health'] as int,
      powerIndex: (json['power_index'] as num).toDouble(),
      traits: List<String>.from(json['traits'] ?? []),
      expansion: Expansion.fromString(json['expansion'] as String),
      skills: rawSkillIds
          .map((id) => skillMap[id])
          .whereType<SkillDTO>()
          .toList(),
      faq: (json['faq'] as List? ?? [])
          .map((item) => Map<String, String>.from(item as Map))
          .toList(),
    );
  }

  // ── Search 
  /// Matches against English name, Chinese name, and serial ID.
  bool matchesQuery(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return nameEn.toLowerCase().contains(q) ||
        nameCn.contains(query) ||
        id.toLowerCase().contains(q);
  }

  // ── Image 
  String get imagePath => 'assets/images/generals/$id.webp';
  static const String placeholderImagePath = 'assets/images/generals_placeholder.webp';

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
  /// Power index as a display string, e.g. "3.0" → "★★★" 
  /// Returns half-star increments up to 5 stars.
  String get powerStars {
    final full = powerIndex.floor();
    final half = (powerIndex - full) >= 0.5;
    return '★' * full + (half ? '☆' : '');
  }
}

enum Expansion {
  limitBreak;  // 界限突破 — prefix: jx

  static Expansion fromString(String value) {
    switch (value) {
      case 'Limit Break': return Expansion.limitBreak;
      default:            return Expansion.limitBreak; // only one for now
    }
  }

  String get badge {
    switch (this) {
      case Expansion.limitBreak: return '界';
    }
  }
}