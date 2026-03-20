// lib/features/codex/presentation/widgets/codex_flow_step_tile.dart
//
// A single rule block rendered as a numbered step row, used exclusively in the
// Flow chapter's list view and search results.
//
// Now segment-aware: uses buildSegmentSpan() from codex_rule_block_widget.dart
// so label/number segments render in the Flow chapter accent colour and body
// prose renders in the standard definition colour — matching the rich-text
// treatment in every other chapter.
//
// The numbered circle uses the external [index] for visual ordering in the
// browse list.  The flat [block.cn]/[block.en] is used as the fallback when
// [block.segments] is empty (backward-compatible with any un-migrated blocks).

import 'package:flutter/material.dart';
import '../../data/models/codex_entry_dto.dart';
import '../../../../core/theme/app_theme.dart';
import 'codex_rule_block_widget.dart';

class CodexFlowStepTile extends StatelessWidget {
  final CodexRuleBlock block;

  /// Sequential index for the numbered circle shown at the left.
  final int index;

  final bool showChinese;
  final bool isDark;

  /// Optional. When provided, [card] and [skill] segments become tappable.
  final SegmentTapCallback? onSegmentTap;

  const CodexFlowStepTile({
    super.key,
    required this.block,
    required this.index,
    required this.showChinese,
    required this.isDark,
    this.onSegmentTap,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontSize: 12.5,
      height: 1.75,
      color: AppTheme.codexDefinition(isDark),
    );

    // Build the rich text span — falls back to flat string when segments empty.
    final segments = showChinese
        ? block.segments
        : block.segments
            .map((s) => CodexSegment(kind: s.kind, cn: s.en, en: s.cn))
            .toList();

    final span = buildSegmentSpan(
      segments: segments,
      fallback: showChinese ? block.cn : block.en,
      chapter: 'flow',
      isDark: isDark,
      baseStyle: baseStyle,
      originalSegments: block.segments,
      showChinese: showChinese,
      onSegmentTap: onSegmentTap,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.codexDivider(isDark), width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Numbered circle ─────────────────────────────────────────────
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(top: 1, right: 12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.codexNumBg('flow', isDark),
              border: Border.all(
                  color: AppTheme.codexNumBorder('flow', isDark), width: 1),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.codexNumText('flow', isDark),
                  height: 1,
                ),
              ),
            ),
          ),

          // ── Content ──────────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rich text body
                Text.rich(span),

                // Examples — rendered as small tag chips (same as before)
                if (block.examples.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  ...block.examples.map((ex) {
                    final text = showChinese ? ex.cn : ex.en;
                    if (text.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ExampleChip(
                          text: text,
                          isDark: isDark,
                        ),
                        // Sub-examples indented
                        if (ex.subExamples.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 10, top: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: ex.subExamples.map((sub) {
                                final subText =
                                    showChinese ? sub.cn : sub.en;
                                if (subText.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                return _ExampleChip(
                                  text: subText,
                                  isDark: isDark,
                                  indent: true,
                                );
                              }).toList(),
                            ),
                          ),
                      ],
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Example chip ──────────────────────────────────────────────────────────────
// Previously a Wrap of tag pills; now rendered as small prose bullets so
// multi-sentence examples display cleanly rather than being cut off in pills.

class _ExampleChip extends StatelessWidget {
  final String text;
  final bool isDark;
  final bool indent;

  const _ExampleChip({
    required this.text,
    required this.isDark,
    this.indent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 5, left: indent ? 0.0 : 0.0),
      child: Row(
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
                fontSize: 11.5,
                height: 1.65,
                color: AppTheme.codexExampleText(isDark),
              ),
            ),
          ),
        ],
      ),
    );
  }
}