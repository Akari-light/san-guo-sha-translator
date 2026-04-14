import 'package:flutter/material.dart';
import '../../data/models/codex_entry_dto.dart';
import '../../../../core/theme/app_theme.dart';
import 'codex_entry_card.dart';
import 'codex_flow_step_tile.dart';
import 'codex_rule_block_widget.dart';

class CodexSectionTile extends StatefulWidget {
  final String sectionNum;
  final String titleCn;
  final String titleEn;
  final String chapterKey;
  final bool showChinese;
  final bool isDark;
  final List<CodexEntryDTO> entries;
  final String sectionSummary;
  final bool isFlow;
  final SegmentTapCallback? onSegmentTap;
  final void Function(CodexEntryDTO entry)? onOpenEntry;

  const CodexSectionTile({
    super.key,
    required this.sectionNum,
    required this.titleCn,
    required this.titleEn,
    required this.chapterKey,
    required this.showChinese,
    required this.isDark,
    required this.entries,
    required this.sectionSummary,
    this.isFlow = false,
    this.onSegmentTap,
    this.onOpenEntry,
  });

  @override
  State<CodexSectionTile> createState() => _CodexSectionTileState();
}

class _CodexSectionTileState extends State<CodexSectionTile> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = widget.sectionNum.endsWith('.0') ||
        widget.sectionNum.endsWith('.1') ||
        widget.sectionNum == '1.1';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final showCn = widget.showChinese;
    final chapter = widget.chapterKey;
    final divider = AppTheme.codexDivider(isDark);
    final accent = AppTheme.codexChapterAccent(chapter, isDark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            color: AppTheme.codexSectionHeaderBg(isDark),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 42,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.codexNumBg(chapter, isDark),
                              border: Border.all(
                                color: AppTheme.codexNumBorder(chapter, isDark),
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              widget.sectionNum,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                                color: AppTheme.codexNumText(chapter, isDark),
                                height: 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            showCn
                                ? '${widget.entries.length}条'
                                : '${widget.entries.length} ${widget.entries.length == 1 ? "entry" : "entries"}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.codexSecondaryText(isDark),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        showCn ? widget.titleCn : widget.titleEn,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          color: AppTheme.codexTerm(isDark),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        showCn ? widget.titleEn : widget.titleCn,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.codexSubText(chapter, isDark),
                          height: 1.35,
                        ),
                      ),
                      if (widget.sectionSummary.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          widget.sectionSummary,
                          maxLines: _open ? 4 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.codexSecondaryText(isDark),
                            height: 1.55,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
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
                      onSegmentTap: widget.onSegmentTap,
                    ))
          else
            ...widget.entries.map((entry) => CodexEntryCard(
                  entry: entry,
                  showChinese: showCn,
                  isDark: isDark,
                  showChapterBadge: false,
                  onSegmentTap: widget.onSegmentTap,
                  onOpenDetails: widget.onOpenEntry == null
                      ? null
                      : () => widget.onOpenEntry!(entry),
                )),
      ],
    );
  }
}
