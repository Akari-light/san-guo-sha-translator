// lib/features/codex/presentation/widgets/codex_flow_step_tile.dart

import 'package:flutter/material.dart';
import '../../data/models/codex_entry_dto.dart';
import '../../../../core/theme/app_theme.dart';

class CodexFlowStepTile extends StatelessWidget {
  final CodexRuleBlock block;
  final int index;
  final bool showChinese;
  final bool isDark;

  const CodexFlowStepTile({
    super.key,
    required this.block,
    required this.index,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final text = showChinese ? block.cn : block.en;

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
          // Numbered circle — flow chapter accent colors
          Container(
            width: 26, height: 26,
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

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.75,
                    color: AppTheme.codexDefinition(isDark),
                  ),
                ),
                // Skill ref chips from examples
                if (block.examples.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 5, runSpacing: 5,
                    children: block.examples
                        .where((ex) => (showChinese ? ex.cn : ex.en).isNotEmpty)
                        .map((ex) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.codexTagFill(isDark),
                                border: Border.all(
                                    color: AppTheme.codexTagBorder(isDark),
                                    width: 0.5),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                showChinese ? ex.cn : ex.en,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: AppTheme.codexTagText(isDark),
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}