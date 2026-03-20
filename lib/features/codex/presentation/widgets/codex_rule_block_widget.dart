// lib/features/codex/presentation/widgets/codex_rule_block_widget.dart

import 'package:flutter/material.dart';
import '../../data/models/codex_entry_dto.dart';
import '../../../../core/theme/app_theme.dart';

// ── Public widget ─────────────────────────────────────────────────────────────

class CodexRuleBlockWidget extends StatelessWidget {
  final CodexRuleBlock block;

  /// Chapter key ('setup' | 'glossary' | 'flow' | 'rules') — used to tint
  /// [label] and [number] segments with the chapter accent colour.
  final String chapter;

  final bool showChinese;
  final bool isDark;

  const CodexRuleBlockWidget({
    super.key,
    required this.block,
    required this.chapter,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _blockBody(),
          if (block.examples.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: block.examples
                    .map((ex) => _ExampleTile(
                          ex: ex,
                          depth: 0,
                          showChinese: showChinese,
                          isDark: isDark,
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _blockBody() {
    switch (block.type) {
      case CodexRuleBlockType.rule:
        return _RuleBlock(
          block: block,
          chapter: chapter,
          showChinese: showChinese,
          isDark: isDark,
        );
      case CodexRuleBlockType.note:
        return _NoteBlock(
          block: block,
          chapter: chapter,
          showChinese: showChinese,
          isDark: isDark,
        );
      case CodexRuleBlockType.caution:
        return _CautionBlock(
          block: block,
          chapter: chapter,
          showChinese: showChinese,
          isDark: isDark,
        );
    }
  }
}

// ── Segment rich-text builder ─────────────────────────────────────────────────

/// Builds a [TextSpan] tree from [segments].
/// Falls back to a single [TextSpan] wrapping the flat [fallback] string when
/// the segment list is empty (backward-compatible with unmigrated JSON).
TextSpan buildSegmentSpan({
  required List<CodexSegment> segments,
  required String fallback,
  required String chapter,
  required bool isDark,
  required TextStyle baseStyle,
}) {
  if (segments.isEmpty) {
    return TextSpan(text: fallback, style: baseStyle);
  }

  final accentColor = AppTheme.codexChapterAccent(chapter, isDark);

  return TextSpan(
    children: segments.map((seg) {
      final text = seg.cn; // caller swaps cn/en before calling — see _textFor()
      switch (seg.kind) {
        case CodexSegmentKind.label:
          return TextSpan(
            text: text,
            style: baseStyle.copyWith(
              fontWeight: FontWeight.w700,
              color: accentColor,
            ),
          );
        case CodexSegmentKind.number:
          return TextSpan(
            text: text,
            style: baseStyle.copyWith(
              fontWeight: FontWeight.w700,
              color: accentColor,
            ),
          );
        case CodexSegmentKind.card:
          return TextSpan(
            text: text,
            style: baseStyle.copyWith(
              fontWeight: FontWeight.w600,
              color: AppTheme.codexCardRef(isDark),
            ),
          );
        case CodexSegmentKind.skill:
          return TextSpan(
            text: text,
            style: baseStyle.copyWith(
              fontWeight: FontWeight.w500,
              color: AppTheme.codexSkillRef(isDark),
            ),
          );
        case CodexSegmentKind.token:
          return TextSpan(
            text: text,
            style: baseStyle.copyWith(
              fontWeight: FontWeight.w500,
              color: AppTheme.codexTokenRef(isDark),
            ),
          );
        case CodexSegmentKind.body:
          return TextSpan(text: text, style: baseStyle);
      }
    }).toList(),
  );
}

/// Returns the correct CN or EN text from a segment based on [showChinese].
List<CodexSegment> _localised(List<CodexSegment> segments, bool showChinese) {
  // Swap the `cn` field into the active slot so buildSegmentSpan always reads
  // seg.cn — avoids a second branch inside the span builder.
  if (showChinese) return segments;
  return segments
      .map((s) => CodexSegment(kind: s.kind, cn: s.en, en: s.cn))
      .toList();
}

// ── Block sub-widgets ─────────────────────────────────────────────────────────

class _RuleBlock extends StatelessWidget {
  final CodexRuleBlock block;
  final String chapter;
  final bool showChinese;
  final bool isDark;
  const _RuleBlock({
    required this.block,
    required this.chapter,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontSize: 13,
      height: 1.65,
      color: AppTheme.codexDefinition(isDark),
    );
    final fallback = showChinese ? block.cn : block.en;
    final span = buildSegmentSpan(
      segments: _localised(block.segments, showChinese),
      fallback: fallback,
      chapter: chapter,
      isDark: isDark,
      baseStyle: baseStyle,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3, right: 6),
          child: Text(
            '◆',
            style: TextStyle(
              fontSize: 9,
              color: AppTheme.codexChapterAccent(chapter, isDark),
            ),
          ),
        ),
        Expanded(child: Text.rich(span)),
      ],
    );
  }
}

class _NoteBlock extends StatelessWidget {
  final CodexRuleBlock block;
  final String chapter;
  final bool showChinese;
  final bool isDark;
  const _NoteBlock({
    required this.block,
    required this.chapter,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontSize: 12,
      height: 1.65,
      color: AppTheme.codexNoteText(isDark),
    );
    final fallback = showChinese ? block.cn : block.en;
    final span = buildSegmentSpan(
      segments: _localised(block.segments, showChinese),
      fallback: fallback,
      chapter: chapter,
      isDark: isDark,
      baseStyle: baseStyle,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: AppTheme.codexNoteAccent(isDark), width: 2),
        ),
        color: AppTheme.codexNoteFill(isDark),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: Text.rich(span),
    );
  }
}

class _CautionBlock extends StatelessWidget {
  final CodexRuleBlock block;
  final String chapter;
  final bool showChinese;
  final bool isDark;
  const _CautionBlock({
    required this.block,
    required this.chapter,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontSize: 12,
      height: 1.65,
      color: AppTheme.codexCautionText(isDark),
    );
    final fallback = showChinese ? block.cn : block.en;
    final span = buildSegmentSpan(
      segments: _localised(block.segments, showChinese),
      fallback: fallback,
      chapter: chapter,
      isDark: isDark,
      baseStyle: baseStyle,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        border: Border(
          left:
              BorderSide(color: AppTheme.codexCautionAccent(isDark), width: 2),
        ),
        color: AppTheme.codexCautionFill(isDark),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: Text.rich(span),
    );
  }
}

// ── Example tile ──────────────────────────────────────────────────────────────

class _ExampleTile extends StatelessWidget {
  final CodexExample ex;
  final int depth;
  final bool showChinese;
  final bool isDark;

  const _ExampleTile({
    required this.ex,
    required this.depth,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final text = showChinese ? ex.cn : ex.en;
    return Padding(
      padding: EdgeInsets.only(bottom: 5, left: depth * 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 7),
                child: Container(
                  width: 3,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppTheme.codexExampleText(isDark),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.codexExampleText(isDark),
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
          if (ex.subExamples.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: ex.subExamples
                    .map((sub) => _ExampleTile(
                          ex: sub,
                          depth: depth + 1,
                          showChinese: showChinese,
                          isDark: isDark,
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}