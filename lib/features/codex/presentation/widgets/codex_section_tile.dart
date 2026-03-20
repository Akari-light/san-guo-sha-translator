// lib/features/codex/presentation/widgets/codex_section_tile.dart

import 'package:flutter/material.dart';
import '../../data/models/codex_entry_dto.dart';
import '../../../../core/theme/app_theme.dart';
import 'codex_entry_card.dart';
import 'codex_flow_step_tile.dart';

class CodexSectionTile extends StatefulWidget {
  final String sectionNum;
  final String titleCn;
  final String titleEn;
  final String chapterKey;
  final bool showChinese;
  final bool isDark;
  final List<CodexEntryDTO> entries;
  final void Function(CodexEntryDTO) onEntryTap;
  final bool isFlow;

  const CodexSectionTile({
    super.key,
    required this.sectionNum,
    required this.titleCn,
    required this.titleEn,
    required this.chapterKey,
    required this.showChinese,
    required this.isDark,
    required this.entries,
    required this.onEntryTap,
    this.isFlow = false,
  });

  @override
  State<CodexSectionTile> createState() => _CodexSectionTileState();
}

class _CodexSectionTileState extends State<CodexSectionTile> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    // First section of each chapter starts open; rest collapsed
    _open = widget.sectionNum.endsWith('.0') ||
        widget.sectionNum.endsWith('.1') ||
        widget.sectionNum == '1.1';
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = widget.isDark;
    final showCn  = widget.showChinese;
    final chapter = widget.chapterKey;
    final divider = AppTheme.codexDivider(isDark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Header ────────────────────────────────────────────────────────
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
            color: AppTheme.codexSectionHeaderBg(isDark),
            child: Row(
              children: [
                // Section number badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.codexNumBg(chapter, isDark),
                    border: Border.all(
                        color: AppTheme.codexNumBorder(chapter, isDark), width: 1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    widget.sectionNum,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: AppTheme.codexNumText(chapter, isDark),
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Title + subtitle pill
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        showCn ? widget.titleCn : widget.titleEn,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          color: AppTheme.codexTerm(isDark),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.codexSubBg(chapter, isDark),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          showCn ? widget.titleEn : widget.titleCn,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                            color: AppTheme.codexSubText(chapter, isDark),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Chevron
                AnimatedRotation(
                  turns: _open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppTheme.codexIconMuted(isDark),
                  ),
                ),
              ],
            ),
          ),
        ),
        Divider(height: 0.5, thickness: 0.5, color: divider),

        // ── Children ──────────────────────────────────────────────────────
        if (_open)
          if (widget.isFlow)
            ...widget.entries
                .expand((e) => e.rules)
                .toList()
                .asMap()
                .entries
                .map((e) => CodexFlowStepTile(
                      block: e.value,
                      index: e.key,
                      showChinese: showCn,
                      isDark: isDark,
                    ))
          else
            ...widget.entries.map((entry) => CodexEntryCard(
                  entry: entry,
                  showChinese: showCn,
                  isDark: isDark,
                  showChapterBadge: false,
                  onTap: () => widget.onEntryTap(entry),
                )),
      ],
    );
  }
}