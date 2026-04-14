import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/codex_entry_dto.dart';
import '../widgets/codex_reference_text.dart';
import '../widgets/codex_rule_block_widget.dart';

class CodexEntryScreen extends StatefulWidget {
  final CodexEntryDTO entry;
  final bool showChinese;
  final SegmentTapCallback? onSegmentTap;

  const CodexEntryScreen({
    super.key,
    required this.entry,
    required this.showChinese,
    this.onSegmentTap,
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
    final entry = widget.entry;
    final showCn = _showChinese;

    final primaryTerm = showCn ? entry.termCn : entry.termEn;
    final secondaryTerm = showCn ? entry.termEn : entry.termCn;
    final primaryDef = showCn ? entry.definitionCn : entry.definitionEn;
    final secondaryDef = showCn ? entry.definitionEn : entry.definitionCn;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.codexNumBg(entry.chapter, isDark),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppTheme.codexNumBorder(entry.chapter, isDark),
                  width: 0.8,
                ),
              ),
              child: Text(
                _chapterLabel(entry.chapter),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.codexNumText(entry.chapter, isDark),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '§${entry.sectionNum}',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.codexSecondaryText(isDark),
              ),
            ),
          ],
        ),
        actions: [
          _LangToggle(
            showChinese: showCn,
            isDark: isDark,
            onToggle: () => setState(() => _showChinese = !_showChinese),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          _EntryHero(
            chapter: entry.chapter,
            primaryTerm: primaryTerm,
            secondaryTerm: secondaryTerm,
            sectionTitle: showCn ? entry.sectionTitleCn : entry.sectionTitleEn,
            counterpartSection:
                showCn ? entry.sectionTitleEn : entry.sectionTitleCn,
            ruleCount: entry.rules.length,
            isDark: isDark,
          ),
          const SizedBox(height: 16),
          if (primaryDef.isNotEmpty)
            _ContentBlock(
              title: showCn ? '简述' : 'Brief',
              isDark: isDark,
              child: CodexReferenceText(
                text: primaryDef,
                isDark: isDark,
                onReferenceTap: widget.onSegmentTap,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.75,
                  color: AppTheme.codexDefinition(isDark),
                ),
              ),
            ),
          if (secondaryDef.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ContentBlock(
              title: showCn ? '对照' : 'Counterpart',
              isDark: isDark,
              child: CodexReferenceText(
                text: secondaryDef,
                isDark: isDark,
                onReferenceTap: widget.onSegmentTap,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.65,
                  color: AppTheme.codexSecondaryText(isDark),
                ),
              ),
            ),
          ],
          if (entry.rules.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ContentBlock(
              title: showCn ? '深入说明' : 'In-Depth Explanation',
              subtitle: showCn
                  ? '按规则块展开，便于逐条阅读和核对。'
                  : 'Expanded into rule blocks for slower, article-style reading.',
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: entry.rules
                    .map(
                      (block) => CodexRuleBlockWidget(
                        block: block,
                        chapter: entry.chapter,
                        showChinese: showCn,
                        isDark: isDark,
                        onSegmentTap: widget.onSegmentTap,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _chapterLabel(String chapter) {
    return switch (chapter) {
      'setup' => 'Setup',
      'glossary' => 'Glossary',
      'flow' => 'Flow',
      'rules' => 'Rules',
      _ => chapter,
    };
  }
}

class _EntryHero extends StatelessWidget {
  final String chapter;
  final String primaryTerm;
  final String secondaryTerm;
  final String sectionTitle;
  final String counterpartSection;
  final int ruleCount;
  final bool isDark;

  const _EntryHero({
    required this.chapter,
    required this.primaryTerm,
    required this.secondaryTerm,
    required this.sectionTitle,
    required this.counterpartSection,
    required this.ruleCount,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.codexChapterAccent(chapter, isDark);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.codexSectionHeaderBg(isDark),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent.withAlpha(isDark ? 90 : 70),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            primaryTerm,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppTheme.codexTerm(isDark),
            ),
          ),
          if (secondaryTerm.isNotEmpty && secondaryTerm != primaryTerm) ...[
            const SizedBox(height: 4),
            Text(
              secondaryTerm,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.codexSecondaryText(isDark),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            sectionTitle,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.codexSubText(chapter, isDark),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            counterpartSection,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.codexSecondaryText(isDark),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.codexTagFill(isDark),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppTheme.codexTagBorder(isDark),
                width: 1,
              ),
            ),
            child: Text(
              '$ruleCount ${ruleCount == 1 ? "rule block" : "rule blocks"}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.codexDefinition(isDark),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentBlock extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final bool isDark;

  const _ContentBlock({
    required this.title,
    required this.child,
    required this.isDark,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.codexSectionHeaderBg(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.codexDivider(isDark),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.35,
              color: AppTheme.codexSecondaryText(isDark),
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppTheme.codexSecondaryText(isDark),
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

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
            color: AppTheme.codexLangToggleBorder(isDark),
            width: 1,
          ),
          color: AppTheme.codexLangToggleFill(isDark),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.language,
              size: 13,
              color: Color(0xFF007ACC),
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

class _LangToggle extends LangToggle {
  const _LangToggle({
    required super.showChinese,
    required super.isDark,
    required super.onToggle,
  });
}
