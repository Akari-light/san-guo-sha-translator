/// Expansion taxonomy for general cards.
///
/// Lives in core/models/ so both app_theme.dart and the generals feature
/// can import it without creating a cross-feature dependency.
///
/// ID format rules:
///   limitBreak — prefix: jx   (e.g. jx.SHU001)
///   demon      — prefix: mo   (e.g. mo.WEI001)
///   god        — prefix: LE   (e.g. LE001)   ← note: SP008-1/SP008-2 are
///                                               documented exceptions to this rule
///   all others — original card index          (e.g. SHU001, WEI011)
enum Expansion {
  standard,   // 标准版     — original card index
  limitBreak, // 界限突破   — prefix: jx
  shenHua,    // 神话再临   — original card index
  demon,      // 魔武将     — prefix: mo
  god,        // 神将       — prefix: LE
  shiji,      // 始计篇     — original card index
  doudizhu,   // 斗地主     — original card index
  other;      // 其他       — original card index

  static Expansion fromString(String value) {
    switch (value) {
      case 'Standard':    return Expansion.standard;
      case 'Limit Break': return Expansion.limitBreak;
      case 'Shen Hua':    return Expansion.shenHua;
      case 'Demon':       return Expansion.demon;
      case 'God':         return Expansion.god;
      case 'Shiji':       return Expansion.shiji;
      case 'Doudizhu':    return Expansion.doudizhu;
      case 'Other':       return Expansion.other;
      default:            return Expansion.standard;
    }
  }

  String get badge {
    switch (this) {
      case Expansion.standard:   return '标';
      case Expansion.limitBreak: return '界';
      case Expansion.shenHua:    return '神话';
      case Expansion.demon:      return '魔';
      case Expansion.god:        return '神';
      case Expansion.shiji:      return '始';
      case Expansion.doudizhu:   return '斗';
      case Expansion.other:      return '他';
    }
  }

  String get labelEn {
    switch (this) {
      case Expansion.standard:   return 'Standard';
      case Expansion.limitBreak: return 'Limit Break';
      case Expansion.shenHua:    return 'Shen Hua';
      case Expansion.demon:      return 'Demon';
      case Expansion.god:        return 'God';
      case Expansion.shiji:      return 'Shiji';
      case Expansion.doudizhu:   return 'Doudizhu';
      case Expansion.other:      return 'Other';
    }
  }

  String get labelCn {
    switch (this) {
      case Expansion.standard:   return '标准版';
      case Expansion.limitBreak: return '界限突破';
      case Expansion.shenHua:    return '神话再临';
      case Expansion.demon:      return '魔武将';
      case Expansion.god:        return '神将';
      case Expansion.shiji:      return '始计篇';
      case Expansion.doudizhu:   return '斗地主';
      case Expansion.other:      return '其他';
    }
  }
}