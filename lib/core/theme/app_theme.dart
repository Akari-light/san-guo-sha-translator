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
  static const Color _shuColor       = Color(0xFFFF5722); // Red-Orange
  static const Color _weiColor       = Color(0xFF2196F3); // Blue
  static const Color _wuColor        = Color(0xFF4CAF50); // Green
  static const Color _qunColor       = Color(0xFF9E9E9E); // Grey
  static const Color _godColor       = Color(0xFFFFC107); // Gold
  static const Color _utilitiesColor = Color(0xFF78909C); // Blue-Grey

  // ── Description Text Colors
  static const Color descriptionEnDark = Color(0xFF9CDCFE); // VS Code blue
  static const Color descriptionCnDark = Color(0xFFCE9178); // VS Code orange

  // ── UI Component Colors
  static const Color statBadgeColor  = Color(0xFFFF6B6B);
  static const Color searchTextColor = Color(0xFFD4D4D4);
  static const Color searchHintColor = Color(0xFF858585);

  // ────────────────────────────────────────────────────────────────────────────
  // Codex Colors
  // All color literals used by the Codex feature live here.
  // Codex widgets reference AppTheme.codex*() helpers — no Color(0x…) inline.
  // ────────────────────────────────────────────────────────────────────────────

  // ── Codex: Chapter accent colors (tab underline + active tab text)
  static const Color _codexSetupAccentDark     = Color(0xFF888780);
  static const Color _codexSetupAccentLight    = Color(0xFF5A5956);
  static const Color _codexGlossaryAccentDark  = Color(0xFF4DA6E8);
  static const Color _codexGlossaryAccentLight = Color(0xFF007ACC);
  static const Color _codexFlowAccentDark      = Color(0xFF3AAA88);
  static const Color _codexFlowAccentLight     = Color(0xFF0F6E56);
  static const Color _codexRulesAccentDark     = Color(0xFFD4901A);
  static const Color _codexRulesAccentLight    = Color(0xFF854F0B);

  // ── Codex: Section number badge (bg / text / border)
  static const Color _codexSetupNumBgDark       = Color(0xFF2A2A27);
  static const Color _codexSetupNumTextDark     = Color(0xFFCCC9B8);
  static const Color _codexSetupNumBorderDark   = Color(0xFF5F5E5A);
  static const Color _codexSetupNumBgLight      = Color(0xFFF1EFE8);
  static const Color _codexSetupNumTextLight    = Color(0xFF444441);
  static const Color _codexSetupNumBorderLight  = Color(0xFFB4B2A9);

  static const Color _codexGlossaryNumBgDark       = Color(0xFF0B1D30);
  static const Color _codexGlossaryNumTextDark     = Color(0xFF85B7EB);
  static const Color _codexGlossaryNumBorderDark   = Color(0xFF2A6AAD);
  static const Color _codexGlossaryNumBgLight      = Color(0xFFE6F1FB);
  static const Color _codexGlossaryNumTextLight    = Color(0xFF0C447C);
  static const Color _codexGlossaryNumBorderLight  = Color(0xFF85B7EB);

  static const Color _codexFlowNumBgDark       = Color(0xFF082820);
  static const Color _codexFlowNumTextDark     = Color(0xFF5EC9A8);
  static const Color _codexFlowNumBorderDark   = Color(0xFF1A7A60);
  static const Color _codexFlowNumBgLight      = Color(0xFFE1F5EE);
  static const Color _codexFlowNumTextLight    = Color(0xFF085041);
  static const Color _codexFlowNumBorderLight  = Color(0xFF5DCAA5);

  static const Color _codexRulesNumBgDark       = Color(0xFF261900);
  static const Color _codexRulesNumTextDark     = Color(0xFFFAC775);
  static const Color _codexRulesNumBorderDark   = Color(0xFFC98020);
  static const Color _codexRulesNumBgLight      = Color(0xFFFAEEDA);
  static const Color _codexRulesNumTextLight    = Color(0xFF633806);
  static const Color _codexRulesNumBorderLight  = Color(0xFFEF9F27);

  // ── Codex: Section subtitle pill (secondary language label)
  static const Color _codexSetupSubBgDark      = Color(0xFF3A3A36);
  static const Color _codexSetupSubTextDark    = Color(0xFFC8C5B4);
  static const Color _codexSetupSubBgLight     = Color(0xFFDDDBD3);
  static const Color _codexSetupSubTextLight   = Color(0xFF3A3936);

  static const Color _codexGlossarySubBgDark   = Color(0xFF0D2D4A);
  static const Color _codexGlossarySubTextDark = Color(0xFF85C8F0);
  static const Color _codexGlossarySubBgLight  = Color(0xFFB5D4F4);
  static const Color _codexGlossarySubTextLight= Color(0xFF042C53);

  static const Color _codexFlowSubBgDark       = Color(0xFF0E3828);
  static const Color _codexFlowSubTextDark     = Color(0xFF5ECFAC);
  static const Color _codexFlowSubBgLight      = Color(0xFF9FE1CB);
  static const Color _codexFlowSubTextLight    = Color(0xFF04342C);

  static const Color _codexRulesSubBgDark      = Color(0xFF361E00);
  static const Color _codexRulesSubTextDark    = Color(0xFFF0B65A);
  static const Color _codexRulesSubBgLight     = Color(0xFFFAC775);
  static const Color _codexRulesSubTextLight   = Color(0xFF412402);

  // ── Codex: Content text
  static const Color codexTermDark         = Color(0xFFE8E6E2); // CN term / primary heading
  static const Color codexTermLight        = Color(0xFF111111);
  static const Color codexDefinitionDark   = Color(0xFFC0BFBA); // body prose
  static const Color codexDefinitionLight  = Color(0xFF333333);
  static const Color codexSecondaryTextDark  = Color(0xFF5A5A5A); // EN secondary under CN
  static const Color codexSecondaryTextLight = Color(0xFF999999);
  static const Color codexExampleTextDark  = descriptionEnDark;  // 0xFF9CDCFE reuse
  static const Color codexExampleTextLight = Color(0xFF1565C0);
  static const Color codexExamplePanelTextDark  = Color(0xFF888888);
  static const Color codexExamplePanelTextLight = Color(0xFF555555);

  // ── Codex: Structural surfaces
  static const Color codexSectionHeaderBgDark  = _vscodeSidebar; // 0xFF252526
  static const Color codexSectionHeaderBgLight = _lightSurface;  // 0xFFF3F3F3

  // ── Codex: Dividers
  static const Color codexDividerDark  = Color(0x12FFFFFF); // ~7% white
  static const Color codexDividerLight = _lightBorder;

  // ── Codex: Input / tag / overlay fills
  static const Color codexTagFillDark      = Color(0x0FFFFFFF);
  static const Color codexTagFillLight     = Color(0xFFF3F3F3);
  static const Color codexTagBorderDark    = Color(0x1AFFFFFF);
  static const Color codexTagBorderLight   = _lightBorder;
  static const Color codexTagTextDark      = Color(0xFF666666);
  static const Color codexTagTextLight     = Color(0xFF777777);
  static const Color codexExampleFillDark  = Color(0x0AFFFFFF);
  static const Color codexExampleFillLight = Color(0xFFF9F9F9);
  static const Color codexExampleAccentDark  = Color(0x1EFFFFFF);
  static const Color codexExampleAccentLight = Color(0x14000000);
  static const Color codexIconMutedDark  = Color(0xFF555555);
  static const Color codexIconMutedLight = Color(0xFFCCCCCC);

  // ── Codex: Note block (amber left-border)
  static const Color codexNoteAccentDark  = Color(0xFFC98020);
  static const Color codexNoteAccentLight = Color(0xFFEF9F27);
  static const Color codexNoteFillDark    = Color(0x14C98020);
  static const Color codexNoteFillLight   = Color(0x0CEF9F27);
  static const Color codexNoteTextDark    = Color(0xFFFAC775);
  static const Color codexNoteTextLight   = Color(0xFF7A4A0A);

  // ── Codex: Caution block (red left-border)
  static const Color codexCautionAccentDark  = Color(0xFFF09595);
  static const Color codexCautionAccentLight = Color(0xFFE24B4A);
  static const Color codexCautionFillDark    = Color(0x12E24B4A);
  static const Color codexCautionFillLight   = Color(0x0AE24B4A);
  static const Color codexCautionTextDark    = Color(0xFFF09595);
  static const Color codexCautionTextLight   = Color(0xFF9B0000);

  // ── Codex: Lang toggle (VS Code blue pill)
  static const Color codexLangToggleFillDark    = Color(0x1E007ACC);
  static const Color codexLangToggleFillLight   = Color(0x12007ACC);
  static const Color codexLangToggleBorderDark  = Color(0x80007ACC);
  static const Color codexLangToggleBorderLight = Color(0x59007ACC);

  // ────────────────────────────────────────────────────────────────────────────
  // Codex Helpers
  // Each returns the correct dark/light value given isDark.
  // ────────────────────────────────────────────────────────────────────────────

  static Color codexChapterAccent(String chapter, bool isDark) {
    switch (chapter) {
      case 'setup':    return isDark ? _codexSetupAccentDark    : _codexSetupAccentLight;
      case 'glossary': return isDark ? _codexGlossaryAccentDark : _codexGlossaryAccentLight;
      case 'flow':     return isDark ? _codexFlowAccentDark     : _codexFlowAccentLight;
      case 'rules':    return isDark ? _codexRulesAccentDark    : _codexRulesAccentLight;
      default:         return isDark ? _codexGlossaryAccentDark : _codexGlossaryAccentLight;
    }
  }

  static Color codexNumBg(String chapter, bool isDark) {
    switch (chapter) {
      case 'setup':    return isDark ? _codexSetupNumBgDark     : _codexSetupNumBgLight;
      case 'glossary': return isDark ? _codexGlossaryNumBgDark  : _codexGlossaryNumBgLight;
      case 'flow':     return isDark ? _codexFlowNumBgDark      : _codexFlowNumBgLight;
      case 'rules':    return isDark ? _codexRulesNumBgDark     : _codexRulesNumBgLight;
      default:         return isDark ? _codexGlossaryNumBgDark  : _codexGlossaryNumBgLight;
    }
  }

  static Color codexNumText(String chapter, bool isDark) {
    switch (chapter) {
      case 'setup':    return isDark ? _codexSetupNumTextDark    : _codexSetupNumTextLight;
      case 'glossary': return isDark ? _codexGlossaryNumTextDark : _codexGlossaryNumTextLight;
      case 'flow':     return isDark ? _codexFlowNumTextDark     : _codexFlowNumTextLight;
      case 'rules':    return isDark ? _codexRulesNumTextDark    : _codexRulesNumTextLight;
      default:         return isDark ? _codexGlossaryNumTextDark : _codexGlossaryNumTextLight;
    }
  }

  static Color codexNumBorder(String chapter, bool isDark) {
    switch (chapter) {
      case 'setup':    return isDark ? _codexSetupNumBorderDark    : _codexSetupNumBorderLight;
      case 'glossary': return isDark ? _codexGlossaryNumBorderDark : _codexGlossaryNumBorderLight;
      case 'flow':     return isDark ? _codexFlowNumBorderDark     : _codexFlowNumBorderLight;
      case 'rules':    return isDark ? _codexRulesNumBorderDark    : _codexRulesNumBorderLight;
      default:         return isDark ? _codexGlossaryNumBorderDark : _codexGlossaryNumBorderLight;
    }
  }

  static Color codexSubBg(String chapter, bool isDark) {
    switch (chapter) {
      case 'setup':    return isDark ? _codexSetupSubBgDark     : _codexSetupSubBgLight;
      case 'glossary': return isDark ? _codexGlossarySubBgDark  : _codexGlossarySubBgLight;
      case 'flow':     return isDark ? _codexFlowSubBgDark      : _codexFlowSubBgLight;
      case 'rules':    return isDark ? _codexRulesSubBgDark     : _codexRulesSubBgLight;
      default:         return isDark ? _codexGlossarySubBgDark  : _codexGlossarySubBgLight;
    }
  }

  static Color codexSubText(String chapter, bool isDark) {
    switch (chapter) {
      case 'setup':    return isDark ? _codexSetupSubTextDark    : _codexSetupSubTextLight;
      case 'glossary': return isDark ? _codexGlossarySubTextDark : _codexGlossarySubTextLight;
      case 'flow':     return isDark ? _codexFlowSubTextDark     : _codexFlowSubTextLight;
      case 'rules':    return isDark ? _codexRulesSubTextDark    : _codexRulesSubTextLight;
      default:         return isDark ? _codexGlossarySubTextDark : _codexGlossarySubTextLight;
    }
  }

  static Color codexTerm(bool isDark)           => isDark ? codexTermDark          : codexTermLight;
  static Color codexDefinition(bool isDark)     => isDark ? codexDefinitionDark    : codexDefinitionLight;
  static Color codexSecondaryText(bool isDark)  => isDark ? codexSecondaryTextDark : codexSecondaryTextLight;
  static Color codexExampleText(bool isDark)    => isDark ? codexExampleTextDark   : codexExampleTextLight;
  static Color codexExamplePanelText(bool isDark) => isDark ? codexExamplePanelTextDark : codexExamplePanelTextLight;
  static Color codexSectionHeaderBg(bool isDark)  => isDark ? codexSectionHeaderBgDark  : codexSectionHeaderBgLight;
  static Color codexDivider(bool isDark)        => isDark ? codexDividerDark       : codexDividerLight;
  static Color codexTagFill(bool isDark)        => isDark ? codexTagFillDark       : codexTagFillLight;
  static Color codexTagBorder(bool isDark)      => isDark ? codexTagBorderDark     : codexTagBorderLight;
  static Color codexTagText(bool isDark)        => isDark ? codexTagTextDark       : codexTagTextLight;
  static Color codexExampleFill(bool isDark)    => isDark ? codexExampleFillDark   : codexExampleFillLight;
  static Color codexExampleAccent(bool isDark)  => isDark ? codexExampleAccentDark : codexExampleAccentLight;
  static Color codexIconMuted(bool isDark)      => isDark ? codexIconMutedDark     : codexIconMutedLight;
  static Color codexNoteAccent(bool isDark)     => isDark ? codexNoteAccentDark    : codexNoteAccentLight;
  static Color codexNoteFill(bool isDark)       => isDark ? codexNoteFillDark      : codexNoteFillLight;
  static Color codexNoteText(bool isDark)       => isDark ? codexNoteTextDark      : codexNoteTextLight;
  static Color codexCautionAccent(bool isDark)  => isDark ? codexCautionAccentDark : codexCautionAccentLight;
  static Color codexCautionFill(bool isDark)    => isDark ? codexCautionFillDark   : codexCautionFillLight;
  static Color codexCautionText(bool isDark)    => isDark ? codexCautionTextDark   : codexCautionTextLight;
  static Color codexLangToggleFill(bool isDark)   => isDark ? codexLangToggleFillDark   : codexLangToggleFillLight;
  static Color codexLangToggleBorder(bool isDark) => isDark ? codexLangToggleBorderDark : codexLangToggleBorderLight;

  // ── Codex inline segment ref colors ──────────────────────────────────────
  // [CardName] segments — reuse VS Code blue (same as descriptionEnDark)
  static const Color _codexCardRefDark  = Color(0xFF9CDCFE);
  static const Color _codexCardRefLight = Color(0xFF1565C0);
  // 〖SkillName〗 segments — reuse VS Code orange (same as descriptionCnDark)
  static const Color _codexSkillRefDark  = Color(0xFFCE9178);
  static const Color _codexSkillRefLight = Color(0xFFBF5B00);
  // 「TokenName」 segments — reuse awakening purple
  static const Color _codexTokenRefDark  = Color(0xFFB47FEC);
  static const Color _codexTokenRefLight = Color(0xFF7B3FC4);

  static Color codexCardRef(bool isDark)  => isDark ? _codexCardRefDark  : _codexCardRefLight;
  static Color codexSkillRef(bool isDark) => isDark ? _codexSkillRefDark : _codexSkillRefLight;
  static Color codexTokenRef(bool isDark) => isDark ? _codexTokenRefDark : _codexTokenRefLight;

  // ── Theme Data ────────────────────────────────────────────────────────────--
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

  // ── Color Helpers ─────────────────────────────────────────────────────────--
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

  static Color factionColor(String faction) {
    switch (faction) {
      case 'Shu':       return _shuColor;
      case 'Wei':       return _weiColor;
      case 'Wu':        return _wuColor;
      case 'Qun':       return _qunColor;
      case 'God':       return _godColor;
      case 'Utilities': return _utilitiesColor;
      default:          return Colors.grey;
    }
  }

  // ── Skill type accent colors
  static const Color skillLord      = Color(0xFFF0A820); // Amber/Gold
  static const Color skillLimited   = Color(0xFFF25C5C); // Red
  static const Color skillAwakening = Color(0xFFB47FEC); // Purple
  static const Color skillLocked    = Color(0xFF5BA4F5); // Blue
  static const Color skillActive    = Color(0x2EFFFFFF); // (no badge)
  static const Color skillMission   = Color(0xFF26A99A); // Teal
  static const Color skillConvert   = Color(0xFF78C8E6); // Sky blue
  static const Color skillCombo     = Color(0xFFE8A44A); // Warm orange
  static const Color skillClan      = Color(0xFF85C285); // Muted green
  static const Color skillCharge    = Color(0xFFFF8C69); // Coral

  static Color skillTypeColor(SkillType type) {
    switch (type) {
      case SkillType.lord:      return skillLord;
      case SkillType.limited:   return skillLimited;
      case SkillType.awakening: return skillAwakening;
      case SkillType.locked:    return skillLocked;
      case SkillType.mission:   return skillMission;
      case SkillType.convert:   return skillConvert;
      case SkillType.combo:     return skillCombo;
      case SkillType.clan:      return skillClan;
      case SkillType.charge:    return skillCharge;
      case SkillType.active:    return skillActive;
    }
  }

  // ── Expansion badge colors
  static const Color expansionStandard    = Color(0xFFA0A0A0);
  static const Color expansionMythReturns = Color(0xFF4CAF8A);
  static const Color expansionHeroesSoul  = Color(0xFFE8971A);
  static const Color expansionLimitBreak  = Color(0xFF4B9FDE);
  static const Color expansionDemon       = Color(0xFFE06868);
  static const Color expansionGod         = Color(0xFFF0A820);
  static const Color expansionShiji       = Color(0xFF9C7BC4);
  static const Color expansionMouGong     = Color(0xFF4AABCC);
  static const Color expansionDoudizhu    = Color(0xFFE07B39);
  static const Color expansionOther       = Color(0xFF7A8A8A);

  static Color expansionColor(Expansion expansion) {
    switch (expansion) {
      case Expansion.standard:    return expansionStandard;
      case Expansion.mythReturns: return expansionMythReturns;
      case Expansion.heroesSoul:  return expansionHeroesSoul;
      case Expansion.limitBreak:  return expansionLimitBreak;
      case Expansion.demon:       return expansionDemon;
      case Expansion.god:         return expansionGod;
      case Expansion.shiji:       return expansionShiji;
      case Expansion.mouGong:     return expansionMouGong;
      case Expansion.doudizhu:    return expansionDoudizhu;
      case Expansion.other:       return expansionOther;
    }
  }
}