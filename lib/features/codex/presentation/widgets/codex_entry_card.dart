import 'package:flutter/material.dart';
import '../../data/models/codex_entry_dto.dart';
import '../../../../core/theme/app_theme.dart';
import 'codex_rule_block_widget.dart';
import 'codex_reference_text.dart';

class CodexEntryCard extends StatefulWidget {
  final CodexEntryDTO entry;
  final bool showChinese;
  final bool isDark;
  final bool showChapterBadge;
  final SegmentTapCallback? onSegmentTap;
  final VoidCallback? onOpenDetails;

  const CodexEntryCard({
    super.key,
    required this.entry,
    required this.showChinese,
    required this.isDark,
    this.showChapterBadge = false,
    this.onSegmentTap,
    this.onOpenDetails,
  });

  @override
  State<CodexEntryCard> createState() => _CodexEntryCardState();
}

class _CodexEntryCardState extends State<CodexEntryCard> {
  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final showCn = widget.showChinese;
    final isDark = widget.isDark;

    final divider = AppTheme.codexDivider(isDark);
    final primaryTerm = showCn ? e.termCn : e.termEn;
    final secondaryTerm = showCn ? e.termEn : e.termCn;
    final definition = showCn ? e.definitionCn : e.definitionEn;
    final preview = definition.replaceAll('\n', ' ').trim();
    final canOpenDetails = widget.onOpenDetails != null && e.rules.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: divider, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: AppTheme.codexTerm(isDark),
                      ),
                    ),
                    if (secondaryTerm.isNotEmpty && secondaryTerm != primaryTerm)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          secondaryTerm,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: AppTheme.codexSecondaryText(isDark),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.showChapterBadge)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: _ChapterBadge(chapter: e.chapter, isDark: isDark),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (e.badge != null)
                _SkillBadge(badge: e.badge!, isDark: isDark),
              _MetaChip(
                label: showCn
                    ? '${e.rules.length}条规则'
                    : '${e.rules.length} ${e.rules.length == 1 ? "rule" : "rules"}',
                isDark: isDark,
              ),
              if (canOpenDetails)
                _MetaChip(
                  label: showCn ? '含完整说明' : 'Has full explanation',
                  isDark: isDark,
                ),
            ],
          ),
          if (preview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: CodexReferenceText(
                text: preview,
                isDark: isDark,
                onReferenceTap: widget.onSegmentTap,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.75,
                  color: AppTheme.codexDefinition(isDark),
                ),
              ),
            ),
          if (canOpenDetails)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: OutlinedButton(
                onPressed: widget.onOpenDetails,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                  side: BorderSide(
                    color: AppTheme.codexTagBorder(isDark),
                    width: 1,
                  ),
                  foregroundColor: AppTheme.codexTerm(isDark),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(
                  showCn ? '查看完整说明' : 'View Full Explanation',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SkillBadge extends StatelessWidget {
  final String badge;
  final bool isDark;
  const _SkillBadge({required this.badge, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final (bg, text, border) = switch (badge) {
      'locked' => (
          AppTheme.codexNumBg('glossary', isDark),
          AppTheme.codexNumText('glossary', isDark),
          AppTheme.codexNumBorder('glossary', isDark),
        ),
      'limited' => (
          isDark ? const Color(0xFF260D06) : const Color(0xFFFAECE7),
          isDark ? AppTheme.skillLimited : const Color(0xFF4A1B0C),
          isDark
              ? AppTheme.skillLimited.withAlpha(100)
              : AppTheme.skillLimited.withAlpha(180),
        ),
      'awakening' => (
          isDark ? const Color(0xFF150F33) : const Color(0xFFEEEDFE),
          isDark ? AppTheme.skillAwakening : const Color(0xFF3C3489),
          isDark
              ? AppTheme.skillAwakening.withAlpha(100)
              : AppTheme.skillAwakening.withAlpha(180),
        ),
      'lord' => (
          AppTheme.codexNumBg('rules', isDark),
          AppTheme.codexNumText('rules', isDark),
          AppTheme.codexNumBorder('rules', isDark),
        ),
      'mission' => (
          isDark ? const Color(0xFF071A19) : const Color(0xFFE3F5F3),
          isDark ? AppTheme.skillMission : const Color(0xFF0B3B36),
          isDark
              ? AppTheme.skillMission.withAlpha(100)
              : AppTheme.skillMission.withAlpha(180),
        ),
      'convert' => (
          isDark ? const Color(0xFF061C22) : const Color(0xFFE4F4FA),
          isDark ? AppTheme.skillConvert : const Color(0xFF0B3444),
          isDark
              ? AppTheme.skillConvert.withAlpha(100)
              : AppTheme.skillConvert.withAlpha(180),
        ),
      'combo' => (
          isDark ? const Color(0xFF221708) : const Color(0xFFFAF1E3),
          isDark ? AppTheme.skillCombo : const Color(0xFF4A2F04),
          isDark
              ? AppTheme.skillCombo.withAlpha(100)
              : AppTheme.skillCombo.withAlpha(180),
        ),
      'clan' => (
          isDark ? const Color(0xFF0D1F0D) : const Color(0xFFEAF4EA),
          isDark ? AppTheme.skillClan : const Color(0xFF1B3D1B),
          isDark
              ? AppTheme.skillClan.withAlpha(100)
              : AppTheme.skillClan.withAlpha(180),
        ),
      'charge' => (
          isDark ? const Color(0xFF220F08) : const Color(0xFFFAEDE8),
          isDark ? AppTheme.skillCharge : const Color(0xFF4A1A0A),
          isDark
              ? AppTheme.skillCharge.withAlpha(100)
              : AppTheme.skillCharge.withAlpha(180),
        ),
      _ => (
          AppTheme.codexNumBg('setup', isDark),
          AppTheme.codexNumText('setup', isDark),
          AppTheme.codexNumBorder('setup', isDark),
        ),
    };
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

class _MetaChip extends StatelessWidget {
  final String label;
  final bool isDark;

  const _MetaChip({
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.codexTagFill(isDark),
        border: Border.all(
          color: AppTheme.codexTagBorder(isDark),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: AppTheme.codexTagText(isDark),
          height: 1,
        ),
      ),
    );
  }
}

