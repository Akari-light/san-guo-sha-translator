// lib/features/codex/presentation/screens/codex_entry_screen.dart

import 'package:flutter/material.dart';
import '../../data/models/codex_entry_dto.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/codex_rule_block_widget.dart';

class CodexEntryScreen extends StatefulWidget {
  final CodexEntryDTO entry;
  final bool showChinese;

  const CodexEntryScreen({
    super.key,
    required this.entry,
    required this.showChinese,
  });

  @override
  State<CodexEntryScreen> createState() => _CodexEntryScreenState();
}

class _CodexEntryScreenState extends State<CodexEntryScreen> {
  late bool _showChinese;

  @override
  void initState() {
    super.initState();
    _showChinese = widget.showChinese;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final e      = widget.entry;
    final showCn = _showChinese;

    final primaryTerm   = showCn ? e.termCn   : e.termEn;
    final secondaryTerm = showCn ? e.termEn   : e.termCn;
    final primaryDef    = showCn ? e.definitionCn : e.definitionEn;
    final secondaryDef  = showCn ? e.definitionEn : e.definitionCn;

    return Scaffold(
      appBar: AppBar(
        // Chapter breadcrumb + section number
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.codexNumBg(e.chapter, isDark),
                border: Border.all(
                    color: AppTheme.codexNumBorder(e.chapter, isDark),
                    width: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _chapterLabel(e.chapter),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.codexNumText(e.chapter, isDark),
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '§${e.sectionNum}',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.codexSecondaryText(isDark),
              ),
            ),
          ],
        ),
        actions: [
          // Lang toggle — same style as CodexScreen
          _LangToggle(
            showChinese: showCn,
            isDark: isDark,
            onToggle: () => setState(() => _showChinese = !_showChinese),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          // ── Term header
          Container(
            color: AppTheme.codexSectionHeaderBg(isDark),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primaryTerm,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.codexTerm(isDark),
                  ),
                ),
                if (secondaryTerm.isNotEmpty && secondaryTerm != primaryTerm) ...[
                  const SizedBox(height: 3),
                  Text(
                    secondaryTerm,
                    style: TextStyle(
                      fontSize: 15,
                      color: AppTheme.codexSecondaryText(isDark),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  showCn ? e.sectionTitleCn : e.sectionTitleEn,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.codexChapterAccent(e.chapter, isDark)
                        .withAlpha(179),
                  ),
                ),
              ],
            ),
          ),
          Divider(
              height: 0.5,
              thickness: 0.5,
              color: AppTheme.codexDivider(isDark)),

          // ── Primary definition
          if (primaryDef.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                primaryDef,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.75,
                  color: AppTheme.codexDefinition(isDark),
                ),
              ),
            ),

          // ── Secondary definition (opposite language, muted)
          if (secondaryDef.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                secondaryDef,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.65,
                  color: AppTheme.codexSecondaryText(isDark),
                ),
              ),
            ),
          ],

          // ── Rules / notes
          if (e.rules.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(
                height: 0.5,
                thickness: 0.5,
                color: AppTheme.codexDivider(isDark)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Text(
                showCn ? '规则与注释' : 'Rules & Notes',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: AppTheme.codexSecondaryText(isDark),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: e.rules
                    .map((b) => CodexRuleBlockWidget(
                          block: b,
                          chapter: e.chapter,
                          showChinese: showCn,
                          isDark: isDark,
                        ))
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _chapterLabel(String chapter) {
    switch (chapter) {
      case 'setup':    return 'Setup';
      case 'glossary': return 'Glossary';
      case 'flow':     return 'Flow';
      case 'rules':    return 'Rules';
      default:         return chapter;
    }
  }
}

// ── Lang toggle widget (shared between CodexScreen and CodexEntryScreen) ──────

class LangToggle extends StatelessWidget {
  final bool showChinese;
  final bool isDark;
  final VoidCallback onToggle;

  const LangToggle({
    super.key,
    required this.showChinese,
    required this.isDark,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AppTheme.codexLangToggleBorder(isDark), width: 1),
          color: AppTheme.codexLangToggleFill(isDark),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.language,
              size: 13,
              color: const Color(0xFF007ACC),
            ),
            const SizedBox(width: 4),
            Text(
              showChinese ? '中文' : 'EN',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF007ACC),
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Private alias so codex_entry_screen.dart can use it without export conflicts
class _LangToggle extends LangToggle {
  const _LangToggle({
    required super.showChinese,
    required super.isDark,
    required super.onToggle,
  });
}