class SkillDTO {
  final String id;
  final SkillType skillType;
  final String nameCn;
  final String nameEn;
  final String descriptionCn;
  final String descriptionEn;

  const SkillDTO({
    required this.id,
    required this.skillType,
    required this.nameCn,
    required this.nameEn,
    required this.descriptionCn,
    required this.descriptionEn,
  });

  factory SkillDTO.fromJson(String id, Map<String, dynamic> json) {
    return SkillDTO(
      id: id,
      skillType: SkillType.fromString(json['skill_type'] as String),
      nameCn: json['name_cn'] as String,
      nameEn: json['name_en'] as String,
      descriptionCn: json['description_cn'] as String,
      descriptionEn: json['description_en'] as String,
    );
  }
}

enum SkillType {
  active,    // 主动技 — standard skills requiring player action
  locked,    // 锁定技 — always in effect, cannot be declined
  limited,   // 限定技 — can only be used once per game
  awakening, // 觉醒技 — triggers automatically when conditions are met
  lord,      // 主公技 — only usable when playing as the Lord role
  mission;   // 使命技 — has named success/failure condition; success grants a new skill

  static SkillType fromString(String value) {
    switch (value) {
      case 'locked':    return SkillType.locked;
      case 'limited':   return SkillType.limited;
      case 'awakening': return SkillType.awakening;
      case 'lord':      return SkillType.lord;
      case 'mission':   return SkillType.mission;
      default:          return SkillType.active;
    }
  }

  String get labelEn {
    switch (this) {
      case SkillType.locked:    return 'Locked';
      case SkillType.limited:   return 'Limited';
      case SkillType.awakening: return 'Awakening';
      case SkillType.lord:      return 'Lord';
      case SkillType.mission:   return 'Mission';
      case SkillType.active:    return '';
    }
  }

  String get labelCn {
    switch (this) {
      case SkillType.locked:    return '锁定技';
      case SkillType.limited:   return '限定技';
      case SkillType.awakening: return '觉醒技';
      case SkillType.lord:      return '主公技';
      case SkillType.mission:   return '使命技';
      case SkillType.active:    return '';
    }
  }

  bool get hasBadge => this != SkillType.active;
}