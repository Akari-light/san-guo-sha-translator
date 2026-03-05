import 'package:flutter/material.dart';
import '../../../../core/models/skill_dto.dart';

// Example JSON entry (from limit_break.json):
// {
//   "id": "jx.SHU001",
//   "standard_id": "char_liubei",
//   "name_cn": "界刘备",
//   "name_en": "Liu Bei",
//   "gender": "Male",
//   "faction": "Shu",
//   "health": 4,
//   "power_index": 3.0,
//   "traits": ["进攻", "辅助", "回复"],
//   "expansion": "Limit Break",
//   "skills": ["skill_rende", "skill_jijiang"]
// }

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
  });

  /// Parses a JSON object and resolves skill IDs using [skillMap].
  /// [skillMap] is the full map loaded from skills.json, keyed by skill_id.
  /// Any skill ID not found in the map is silently dropped — protects
  /// against data gaps during development.
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
    );
  }

  String get imagePath => 'assets/images/generals/$id.webp';
  static const String placeholderImagePath = 'assets/images/generals_placeholder.webp';

  // expansion
  String get expansionBadge => expansion.badge;
  
  // faction
  Color get factionColor {
    switch (faction) {
      case 'Shu':  return const Color(0xFF4CAF50); // Green
      case 'Wei':  return const Color(0xFF2196F3); // Blue
      case 'Wu':   return const Color(0xFFFF5722); // Red-Orange
      case 'Qun':  return const Color(0xFF9E9E9E); // Grey
      case 'God':  return const Color(0xFFFFc107); // Gold
      default:     return const Color(0xFF757575);
    }
  }

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

  // power index
  String get powerStars {
    final full = powerIndex.floor();
    final half = (powerIndex - full) >= 0.5;
    return '★' * full + (half ? '½' : '');
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