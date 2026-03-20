// lib/features/codex/presentation/widgets/codex_entry_card.dart

import 'package:flutter/material.dart';
import '../../data/models/codex_entry_dto.dart';
import '../../../../core/theme/app_theme.dart';
import 'codex_rule_block_widget.dart';

class CodexEntryCard extends StatefulWidget {
  final CodexEntryDTO entry;
  final bool showChinese;
  final bool isDark;
  final bool showChapterBadge;
  final VoidCallback onTap;

  const CodexEntryCard({
    super.key,
    required this.entry,
    required this.showChinese,
    required this.isDark,
    this.showChapterBadge = false,
    required this.onTap,
  });

  @override
  State<CodexEntryCard> createState() => _CodexEntryCardState();
}

class _CodexEntryCardState extends State<CodexEntryCard> {
  @override
  Widget build(BuildContext context) {
    final e      = widget.entry;
    final isDark = widget.isDark;
    final showCn = widget.showChinese;

    final divider    = AppTheme.codexDivider(isDark);
    final bgColor    = isDark ? AppTheme.codexSectionHeaderBgDark.withAlpha(0) : Colors.white;
    final primaryTerm   = showCn ? e.termCn   : e.termEn;
    final secondaryTerm = showCn ? e.termEn   : e.termCn;
    final definition    = showCn ? e.definitionCn : e.definitionEn;

    return InkWell(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(bottom: BorderSide(color: divider, width: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Term row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        primaryTerm,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: AppTheme.codexTerm(isDark),
                        ),
                      ),
                      if (secondaryTerm.isNotEmpty &&
                          secondaryTerm != primaryTerm)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            secondaryTerm,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.codexSecondaryText(isDark),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (e.badge != null)
                      _SkillBadge(badge: e.badge!, isDark: isDark),
                    if (widget.showChapterBadge) ...[
                      if (e.badge != null) const SizedBox(height: 4),
                      _ChapterBadge(chapter: e.chapter, isDark: isDark),
                    ],
                  ],
                ),
              ],
            ),

            // Definition
            if (definition.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  definition,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.9,
                    color: AppTheme.codexDefinition(isDark),
                  ),
                ),
              ),

            // Rule blocks (◆ rules, notes, cautions — examples rendered inline within each block)
            if (e.rules.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
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
        ),
      ),
    );
  }
}

// ── Skill-type badge pill ─────────────────────────────────────────────────────
// Maps badge string from glossary.json to AppTheme skill type colors.

class _SkillBadge extends StatelessWidget {
  final String badge;
  final bool isDark;
  const _SkillBadge({required this.badge, required this.isDark});

  @override
  Widget build(BuildContext context) {
    // Badge values: "locked" | "limited" | "awakening" | "lord"
    // Re-use the existing AppTheme skill type color system.
    Color bg, text, border;
    switch (badge) {
      case 'locked':
        bg = AppTheme.codexNumBg('glossary', isDark);
        text = AppTheme.codexNumText('glossary', isDark);
        border = AppTheme.codexNumBorder('glossary', isDark);
      case 'limited':
        bg = isDark ? const Color(0xFF260D06) : const Color(0xFFFAECE7);
        text = isDark ? AppTheme.skillLimited : const Color(0xFF4A1B0C);
        border = isDark ? AppTheme.skillLimited.withAlpha(100) : AppTheme.skillLimited.withAlpha(180);
      case 'awakening':
        bg = isDark ? const Color(0xFF150F33) : const Color(0xFFEEEDFE);
        text = isDark ? AppTheme.skillAwakening : const Color(0xFF3C3489);
        border = isDark ? AppTheme.skillAwakening.withAlpha(100) : AppTheme.skillAwakening.withAlpha(180);
      case 'lord':
        bg = AppTheme.codexNumBg('rules', isDark);
        text = AppTheme.codexNumText('rules', isDark);
        border = AppTheme.codexNumBorder('rules', isDark);
      default:
        bg = AppTheme.codexNumBg('setup', isDark);
        text = AppTheme.codexNumText('setup', isDark);
        border = AppTheme.codexNumBorder('setup', isDark);
    }
    final label = badge[0].toUpperCase() + badge.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border, width: 1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: text,
          letterSpacing: 0.3,
          height: 1,
        ),
      ),
    );
  }
}

// ── Chapter badge (search results only) ──────────────────────────────────────

class _ChapterBadge extends StatelessWidget {
  final String chapter;
  final bool isDark;
  const _ChapterBadge({required this.chapter, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.codexNumBg(chapter, isDark),
        border: Border.all(
            color: AppTheme.codexNumBorder(chapter, isDark), width: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        chapter.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: AppTheme.codexNumText(chapter, isDark),
          letterSpacing: 0.4,
          height: 1,
        ),
      ),
    );
  }
}