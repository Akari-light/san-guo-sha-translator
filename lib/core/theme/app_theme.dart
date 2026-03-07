import 'package:flutter/material.dart';
import '../models/skill_dto.dart';
import '../models/expansion.dart';

class AppTheme {
  AppTheme._();

  // ── VS Code Dark+ Palette
  static const Color _vscodeSidebar = Color(0xFF252526);
  static const Color _vscodeBg     = Color(0xFF1E1E1E);
  static const Color _vscodeBlue   = Color(0xFF007ACC);

  // ── Light Mode Palette
  static const Color _lightSurface = Color(0xFFF3F3F3);
  static const Color _lightBorder  = Color(0xFFE0E0E0);

  // ── Library Category Colors
  /// Dark variants
  static const Color _basicDark    = Color(0xFF89D185); // green
  static const Color _weaponDark   = Color(0xFFF48771); // red
  static const Color _armorDark    = Color(0xFF569CD6); // blue
  static const Color _mountDark    = Color(0xFFD2B48C); // tan
  static const Color _toolDark     = Color(0xFFCE9178); // orange
  static const Color _treasureDark = Color(0xFFC586C0); // purple
  /// Light variants
  static const Color _basicLight    = Color(0xFF388E3C);
  static const Color _weaponLight   = Color(0xFFC62828);
  static const Color _armorLight    = Color(0xFF1565C0);
  static const Color _mountLight    = Color(0xFF5D4037);
  static const Color _toolLight     = Color(0xFFE65100);
  static const Color _treasureLight = Color(0xFF6A1B9A);

  // ── Faction Colors
  static const Color _shuColor  = Color(0xFFFF5722); // Red-Orange
  static const Color _weiColor  = Color(0xFF2196F3); // Blue
  static const Color _wuColor   = Color(0xFF4CAF50); // Green
  static const Color _qunColor  = Color(0xFF9E9E9E); // Grey
  static const Color _godColor  = Color(0xFFFFC107); // Gold

  // ── Description Text Colors
  static const Color descriptionEnDark = Color(0xFF9CDCFE); // VS Code blue
  static const Color descriptionCnDark = Color(0xFFCE9178); // VS Code orange

  // ── UI Component Colors
  static const Color statBadgeColor  = Color(0xFFFF6B6B); // Stat badge (e.g. Range)
  static const Color searchTextColor = Color(0xFFD4D4D4); // AppBar search input text
  static const Color searchHintColor = Color(0xFF858585); // AppBar search hint text

  // ── Theme Data
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _vscodeBg,
      colorScheme: const ColorScheme.dark(
        surface: _vscodeSidebar,
        primary: _vscodeBlue,
        secondary: Color(0xFF4EC9B0),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: _vscodeSidebar,
        selectedItemColor: _vscodeBlue,
        unselectedItemColor: Color(0xFF858585),
        selectedIconTheme: IconThemeData(size: 28),
        unselectedIconTheme: IconThemeData(size: 28),
        selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 12),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      dividerColor: _lightBorder,
      colorScheme: ColorScheme.light(
        surface: _lightSurface,
        primary: const Color(0xFF005FB8),
        secondary: const Color(0xFF0078D4),
        outlineVariant: _lightBorder,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: _lightSurface,
        selectedItemColor: _vscodeBlue,
        unselectedItemColor: Color(0xFF858585),
        selectedIconTheme: IconThemeData(size: 28),
        unselectedIconTheme: IconThemeData(size: 28),
        selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 12),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }

  // ── Color Helpers
  /// Returns the theme-aware color for a library card category.
  static Color categoryColor(String category, bool isDark) {
    switch (category) {
      case 'Basic':    return isDark ? _basicDark    : _basicLight;
      case 'Weapon':   return isDark ? _weaponDark   : _weaponLight;
      case 'Armor':    return isDark ? _armorDark    : _armorLight;
      case 'Mount':    return isDark ? _mountDark    : _mountLight;
      case 'Tool':     return isDark ? _toolDark     : _toolLight;
      case 'Treasure': return isDark ? _treasureDark : _treasureLight;
      default:         return Colors.grey;
    }
  }

  /// Returns the color for a general's faction.
  static Color factionColor(String faction) {
    switch (faction) {
      case 'Shu':  return _shuColor;
      case 'Wei':  return _weiColor;
      case 'Wu':   return _wuColor;
      case 'Qun':  return _qunColor;
      case 'God':  return _godColor;
      default:     return Colors.grey;
    }
  }

  // ── Skill type accent colors
  static const Color skillLord      = Color(0xFFF0A820); // gold
  static const Color skillLimited   = Color(0xFFF25C5C); // red
  static const Color skillAwakening = Color(0xFFB47FEC); // purple
  static const Color skillLocked    = Color(0xFF5BA4F5); // blue
  static const Color skillActive    = Color(0x2EFFFFFF); // subtle white

  /// Returns the accent color for a skill type.
  static Color skillTypeColor(SkillType type) {
    switch (type) {
      case SkillType.lord:      return skillLord;
      case SkillType.limited:   return skillLimited;
      case SkillType.awakening: return skillAwakening;
      case SkillType.locked:    return skillLocked;
      case SkillType.active:    return skillActive;
    }
  }

  // ── Expansion badge colors
  static const Color expansionStandard   = Color(0xFFA0A0A0); // grey   — 标
  static const Color expansionLimitBreak = Color(0xFF4B9FDE); // blue   — 界
  static const Color expansionShenHua    = Color(0xFF4CAF8A); // teal   — 神话
  static const Color expansionDemon      = Color(0xFFE06868); // red    — 魔
  static const Color expansionGod        = Color(0xFFF0A820); // gold   — 神
  static const Color expansionShiji      = Color(0xFF9C7BC4); // purple — 始
  static const Color expansionDoudizhu   = Color(0xFFE07B39); // orange — 斗
  static const Color expansionOther      = Color(0xFF7A8A8A); // slate  — 他

  /// Returns the accent color for an expansion badge.
  static Color expansionColor(Expansion expansion) {
    switch (expansion) {
      case Expansion.standard:   return expansionStandard;
      case Expansion.limitBreak: return expansionLimitBreak;
      case Expansion.shenHua:    return expansionShenHua;
      case Expansion.demon:      return expansionDemon;
      case Expansion.god:        return expansionGod;
      case Expansion.shiji:      return expansionShiji;
      case Expansion.doudizhu:   return expansionDoudizhu;
      case Expansion.other:      return expansionOther;
    }
  }
}