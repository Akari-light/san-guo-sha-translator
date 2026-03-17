/// Expansion taxonomy for general cards.
///
/// Lives in core/models/ so both app_theme.dart and the generals feature
/// can import it without creating a cross-feature dependency.
///
/// ID format rules:
///   limitBreak    — prefix: JX_   (e.g. JX_SHU001)
///   demon         — prefix: MO_   (e.g. MO_WEI001)
///   god           — prefix: LE    (e.g. LE001)  ← no separator; SP008-1/SP008-2 are documented exceptions
///   heroesSoul    — prefix: YJ_   (e.g. YJ_SHU022)
///   mouGong       — prefix: MG_   (e.g. MG_SHU001)
///   all others    — original card index (e.g. SHU001, WEI011)
enum Expansion {
  standard,      // 标准版       — original card index
  mythReturns,   // 神话再临     — original card index   (was: shenHua)
  heroesSoul,    // 一将之魂     — prefix: YJ_
  limitBreak,    // 界限突破     — prefix: JX_
  demon,         // 魔武将       — prefix: MO_
  god,           // 神将         — prefix: LE  (no separator)
  shiji,         // 始计篇       — original card index
  mouGong,       // 谋攻篇       — prefix: MG_
  doudizhu,      // 斗地主       — original card index
  other;         // 其他         — original card index

  static Expansion fromString(String value) {
    switch (value) {
      case 'Standard':          return Expansion.standard;
      case 'Myth Returns':      return Expansion.mythReturns;
      case 'Hero\'s Soul':      return Expansion.heroesSoul;
      case 'Limit Break':       return Expansion.limitBreak;
      case 'Demon':             return Expansion.demon;
      case 'God':               return Expansion.god;
      case 'Art of War':        return Expansion.shiji;
      case 'Strategic Assault': return Expansion.mouGong;
      case 'Doudizhu':          return Expansion.doudizhu;
      case 'Other':             return Expansion.other;
      default:                  return Expansion.standard;
    }
  }

  String get badge {
    switch (this) {
      case Expansion.standard:    return '标';
      case Expansion.mythReturns: return '临';
      case Expansion.heroesSoul:  return '魂';
      case Expansion.limitBreak:  return '界';
      case Expansion.demon:       return '魔';
      case Expansion.god:         return '神';
      case Expansion.shiji:       return '计';
      case Expansion.mouGong:     return '谋';
      case Expansion.doudizhu:    return '斗';
      case Expansion.other:       return 'SP';
    }
  }

  String get labelEn {
    switch (this) {
      case Expansion.standard:    return 'Standard';
      case Expansion.mythReturns: return 'Myth Returns';
      case Expansion.heroesSoul:  return 'Hero\'s Soul';
      case Expansion.limitBreak:  return 'Limit Break';
      case Expansion.demon:       return 'Demon';
      case Expansion.god:         return 'God';
      case Expansion.shiji:       return 'Art of War';
      case Expansion.mouGong:     return 'Strategic Assault';
      case Expansion.doudizhu:    return 'Doudizhu';
      case Expansion.other:       return 'Other';
    }
  }

  String get labelCn {
    switch (this) {
      case Expansion.standard:    return '标准版';
      case Expansion.mythReturns: return '神话再临';
      case Expansion.heroesSoul:  return '一将之魂';
      case Expansion.limitBreak:  return '界限突破';
      case Expansion.demon:       return '魔武将';
      case Expansion.god:         return '神将';
      case Expansion.shiji:       return '始计篇';
      case Expansion.mouGong:     return '谋攻篇';
      case Expansion.doudizhu:    return '斗地主';
      case Expansion.other:       return '其他';
    }
  }
}