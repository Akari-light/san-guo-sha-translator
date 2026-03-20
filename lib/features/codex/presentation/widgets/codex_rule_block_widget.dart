// lib/features/codex/presentation/widgets/codex_rule_block_widget.dart

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../data/models/codex_entry_dto.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/resolver_service.dart';

// ── Tap callback type ─────────────────────────────────────────────────────────
//
// Called when a [card] or [skill] segment is tapped.
// [rawCn] is always the original Chinese bracket text (used for resolution),
// [isChinese] reflects the display language so the sheet resolves correctly.
typedef SegmentTapCallback = void Function(String rawCn, bool isChinese);

// ── Public widget ─────────────────────────────────────────────────────────────

class CodexRuleBlockWidget extends StatelessWidget {
  final CodexRuleBlock block;

  /// Chapter key ('setup' | 'glossary' | 'flow' | 'rules') — tints
  /// [label] and [number] segments with the chapter accent colour.
  final String chapter;

  final bool showChinese;
  final bool isDark;

  /// Optional. When provided, [card] and [skill] segments become tappable.
  /// The callback receives the original CN bracket text and the active language.
  final SegmentTapCallback? onSegmentTap;

  const CodexRuleBlockWidget({
    super.key,
    required this.block,
    required this.chapter,
    required this.showChinese,
    required this.isDark,
    this.onSegmentTap,
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
          onSegmentTap: onSegmentTap,
        );
      case CodexRuleBlockType.note:
        return _NoteBlock(
          block: block,
          chapter: chapter,
          showChinese: showChinese,
          isDark: isDark,
          onSegmentTap: onSegmentTap,
        );
      case CodexRuleBlockType.caution:
        return _CautionBlock(
          block: block,
          chapter: chapter,
          showChinese: showChinese,
          isDark: isDark,
          onSegmentTap: onSegmentTap,
        );
    }
  }
}

// ── Segment rich-text builder ─────────────────────────────────────────────────
//
// [segments] must already have been localised via [_localised] before calling —
// the builder always reads seg.cn as the display text.
//
// [originalSegments] carries the original (pre-localisation) segments so we
// can read the true CN text for resolution even when displaying in EN.
// When null (unmigrated JSON), tap recognition is skipped.

TextSpan buildSegmentSpan({
  required List<CodexSegment> segments,
  required String fallback,
  required String chapter,
  required bool isDark,
  required TextStyle baseStyle,
  List<CodexSegment>? originalSegments, // pre-localisation, for tap resolution
  bool showChinese = true,
  SegmentTapCallback? onSegmentTap,
}) {
  if (segments.isEmpty) {
    return TextSpan(text: fallback, style: baseStyle);
  }

  final accentColor = AppTheme.codexChapterAccent(chapter, isDark);
  final cardColor   = AppTheme.codexCardRef(isDark);
  final skillColor  = AppTheme.codexSkillRef(isDark);
  final tokenColor  = AppTheme.codexTokenRef(isDark);

  return TextSpan(
    children: segments.asMap().entries.map((entry) {
      final i   = entry.key;
      final seg = entry.value;
      final text = seg.cn; // already localised into display slot

      // For tappable kinds: get the original CN text for ResolverService.
      // originalSegments[i].cn is always the CN text regardless of display lang.
      final rawCn = (originalSegments != null && i < originalSegments.length)
          ? originalSegments[i].cn
          : seg.cn;

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
          final tap = onSegmentTap;
          // Only tappable if a tap handler is provided AND we know data exists.
          // canResolve returns null before the cache is warm (first app load) —
          // treat null as resolvable so taps still work during the brief warm-up.
          final cardResolvable = tap != null &&
              (ResolverService().canResolve(rawCn) != false);
          return TextSpan(
            text: text,
            style: baseStyle.copyWith(
              fontWeight: FontWeight.w600,
              color: cardResolvable ? cardColor : baseStyle.color,
              decoration: cardResolvable
                  ? TextDecoration.underline
                  : TextDecoration.none,
              decorationColor: cardColor.withAlpha(120),
            ),
            recognizer: cardResolvable
                ? (TapGestureRecognizer()
                  ..onTap = () => tap(rawCn, showChinese))
                : null,
          );

        case CodexSegmentKind.skill:
          final tap = onSegmentTap;
          final skillResolvable = tap != null &&
              (ResolverService().canResolve(rawCn) != false);
          return TextSpan(
            text: text,
            style: baseStyle.copyWith(
              fontWeight: FontWeight.w500,
              color: skillResolvable ? skillColor : baseStyle.color,
              decoration: skillResolvable
                  ? TextDecoration.underline
                  : TextDecoration.none,
              decorationColor: skillColor.withAlpha(120),
            ),
            recognizer: skillResolvable
                ? (TapGestureRecognizer()
                  ..onTap = () => tap(rawCn, showChinese))
                : null,
          );

        case CodexSegmentKind.token:
          // Tokens are game markers, not resolvable — not tappable.
          return TextSpan(
            text: text,
            style: baseStyle.copyWith(
              fontWeight: FontWeight.w500,
              color: tokenColor,
            ),
          );

        case CodexSegmentKind.body:
          return TextSpan(text: text, style: baseStyle);
      }
    }).toList(),
  );
}

// ── Localisation helper ────────────────────────────────────────────────────────
//
// Returns segments with the display text in the `cn` slot so buildSegmentSpan
// always reads seg.cn. The original list is preserved as [originalSegments].

List<CodexSegment> _localised(List<CodexSegment> segments, bool showChinese) {
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
  final SegmentTapCallback? onSegmentTap;

  const _RuleBlock({
    required this.block,
    required this.chapter,
    required this.showChinese,
    required this.isDark,
    this.onSegmentTap,
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
      originalSegments: block.segments,
      showChinese: showChinese,
      onSegmentTap: onSegmentTap,
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
  final SegmentTapCallback? onSegmentTap;

  const _NoteBlock({
    required this.block,
    required this.chapter,
    required this.showChinese,
    required this.isDark,
    this.onSegmentTap,
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
      originalSegments: block.segments,
      showChinese: showChinese,
      onSegmentTap: onSegmentTap,
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
  final SegmentTapCallback? onSegmentTap;

  const _CautionBlock({
    required this.block,
    required this.chapter,
    required this.showChinese,
    required this.isDark,
    this.onSegmentTap,
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
      originalSegments: block.segments,
      showChinese: showChinese,
      onSegmentTap: onSegmentTap,
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