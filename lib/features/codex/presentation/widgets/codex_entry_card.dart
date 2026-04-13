import 'package:flutter/material.dart';
import '../../data/models/codex_entry_dto.dart';
import '../../../../core/theme/app_theme.dart';
import 'codex_rule_block_widget.dart';
import '../../../../core/widgets/inline_suit_text.dart';

class CodexEntryCard extends StatefulWidget {
  final CodexEntryDTO entry;
  final bool showChinese;
  final bool isDark;
  final bool showChapterBadge;
  final SegmentTapCallback? onSegmentTap;

  const CodexEntryCard({
    super.key,
    required this.entry,
    required this.showChinese,
    required this.isDark,
    this.showChapterBadge = false,
    this.onSegmentTap,
  });

  @override
  State<CodexEntryCard> createState() => _CodexEntryCardState();
}

class _CodexEntryCardState extends State<CodexEntryCard> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = widget.entry.id.contains('guide') ||
        widget.entry.sectionNum.endsWith('.0');
  }

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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _open ? AppTheme.codexTagFill(isDark) : Colors.transparent,
        border: Border(bottom: BorderSide(color: divider, width: 0.5)),
      ),
      child: InkWell(
        onTap: () => setState(() => _open = !_open),
        borderRadius: BorderRadius.circular(10),
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
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
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
                              fontSize: 12,
                              color: AppTheme.codexSecondaryText(isDark),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedRotation(
                  turns: _open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppTheme.codexIconMuted(isDark),
                  ),
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
                if (widget.showChapterBadge)
                  _ChapterBadge(chapter: e.chapter, isDark: isDark),
                _MetaChip(
                  label: '${e.rules.length} ${e.rules.length == 1 ? "rule" : "rules"}',
                  isDark: isDark,
                ),
                _MetaChip(
                  label: _open ? 'Expanded' : 'Tap to expand',
                  isDark: isDark,
                ),
              ],
            ),
            if (!_open && preview.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: InlineSuitText(
                  text: preview,
                  isDark: isDark,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.75,
                    color: AppTheme.codexDefinition(isDark),
                  ),
                ),
              ),
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: _open
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (definition.isNotEmpty)
                              InlineSuitText(
                                text: definition,
                                isDark: isDark,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.9,
                                  color: AppTheme.codexDefinition(isDark),
                                ),
                              ),
                            if (e.rules.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: e.rules
                                      .map((b) => CodexRuleBlockWidget(
                                            block: b,
                                            chapter: e.chapter,
                                            showChinese: showCn,
                                            isDark: isDark,
                                            onSegmentTap: widget.onSegmentTap,
                                          ))
                                      .toList(),
                                ),
                              ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
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

