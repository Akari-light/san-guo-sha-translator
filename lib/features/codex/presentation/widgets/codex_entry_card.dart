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
    final hasStructuredPreview =
        e.roleDistribution.isNotEmpty || e.roles.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
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
          if (hasStructuredPreview)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: _StructuredPreview(
                entry: e,
                showChinese: showCn,
                isDark: isDark,
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

class _StructuredPreview extends StatelessWidget {
  final CodexEntryDTO entry;
  final bool showChinese;
  final bool isDark;

  const _StructuredPreview({
    required this.entry,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    if (entry.roleDistribution.isNotEmpty) {
      children.add(_DistributionPreview(
        rows: entry.roleDistribution,
        showChinese: showChinese,
        isDark: isDark,
      ));
    }

    if (entry.roles.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 12));
      }
      children.add(_RoleStrip(
        roles: entry.roles,
        showChinese: showChinese,
        isDark: isDark,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _DistributionPreview extends StatelessWidget {
  final List<CodexRoleDistributionRow> rows;
  final bool showChinese;
  final bool isDark;

  const _DistributionPreview({
    required this.rows,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final previewRows = rows.length > 3 ? rows.take(3).toList() : rows;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.codexSectionHeaderBg(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.codexDivider(isDark), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DistributionMatrix(
            rows: previewRows,
            showChinese: showChinese,
            isDark: isDark,
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _DistributionMatrix extends StatelessWidget {
  final List<CodexRoleDistributionRow> rows;
  final bool showChinese;
  final bool isDark;
  final bool compact;

  const _DistributionMatrix({
    required this.rows,
    required this.showChinese,
    required this.isDark,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[
      _DistributionMatrixHeader(
        showChinese: showChinese,
        isDark: isDark,
        compact: compact,
      ),
    ];

    for (var i = 0; i < rows.length; i++) {
      lines.add(
        _DistributionMatrixGroup(
          row: rows[i],
          isDark: isDark,
          compact: compact,
        ),
      );
      if (i < rows.length - 1) {
        lines.add(
          Divider(
            height: compact ? 10 : 12,
            thickness: 0.6,
            color: AppTheme.codexDivider(isDark),
          ),
        );
      }
    }

    return Column(children: lines);
  }
}

class _DistributionMatrixHeader extends StatelessWidget {
  final bool showChinese;
  final bool isDark;
  final bool compact;

  const _DistributionMatrixHeader({
    required this.showChinese,
    required this.isDark,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      fontSize: compact ? 10.5 : 11.5,
      fontWeight: FontWeight.w700,
      color: AppTheme.codexSecondaryText(isDark),
      letterSpacing: 0.2,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 6 : 8),
      child: Row(
        children: [
          SizedBox(
            width: compact ? 34 : 40,
            child: Text(
              showChinese ? '人数' : 'P',
              style: textStyle,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              showChinese ? '主公' : 'Lord',
              style: textStyle.copyWith(color: AppTheme.codexLord(isDark)),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              showChinese ? '忠臣' : 'Loyalist',
              style: textStyle.copyWith(color: AppTheme.codexLoyalist(isDark)),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              showChinese ? '反贼' : 'Rebel',
              style: textStyle.copyWith(color: AppTheme.codexRebel(isDark)),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              showChinese ? '内奸' : 'Spy',
              style: textStyle.copyWith(color: AppTheme.codexSpy(isDark)),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _DistributionMatrixGroup extends StatelessWidget {
  final CodexRoleDistributionRow row;
  final bool isDark;
  final bool compact;

  const _DistributionMatrixGroup({
    required this.row,
    required this.isDark,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = TextStyle(
      fontSize: compact ? 11.5 : 13,
      fontWeight: FontWeight.w700,
      color: AppTheme.codexTerm(isDark),
    );
    final leftStyle = TextStyle(
      fontSize: compact ? 11 : 12,
      fontWeight: FontWeight.w700,
      color: AppTheme.codexDefinition(isDark),
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 2 : 4),
      child: IntrinsicHeight(
        child: Row(
          children: [
            SizedBox(
              width: compact ? 34 : 40,
              child: Center(
                child: Text(
                  '${row.players}',
                  style: leftStyle,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                children: [
                  for (var optionIndex = 0; optionIndex < row.options.length; optionIndex++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: optionIndex == row.options.length - 1
                            ? 0
                            : (compact ? 4 : 6),
                      ),
                      child: _DistributionOptionRow(
                        option: row.options[optionIndex],
                        optionIndex: optionIndex,
                        isDark: isDark,
                        compact: compact,
                        valueStyle: valueStyle,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DistributionOptionRow extends StatelessWidget {
  final CodexRoleDistributionOption option;
  final int optionIndex;
  final bool isDark;
  final bool compact;
  final TextStyle valueStyle;

  const _DistributionOptionRow({
    required this.option,
    required this.optionIndex,
    required this.isDark,
    required this.compact,
    required this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: compact ? 4 : 6,
        horizontal: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: AppTheme.codexDistributionOptionFill(isDark, optionIndex),
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${option.lord}',
              style: valueStyle.copyWith(color: AppTheme.codexLord(isDark)),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              '${option.loyalist}',
              style: valueStyle.copyWith(color: AppTheme.codexLoyalist(isDark)),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              '${option.rebel}',
              style: valueStyle.copyWith(color: AppTheme.codexRebel(isDark)),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              '${option.spy}',
              style: valueStyle.copyWith(color: AppTheme.codexSpy(isDark)),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleStrip extends StatelessWidget {
  final List<CodexRoleData> roles;
  final bool showChinese;
  final bool isDark;

  const _RoleStrip({
    required this.roles,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 106,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: roles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) => _RolePoster(
          role: roles[index],
          showChinese: showChinese,
          isDark: isDark,
        ),
      ),
    );
  }
}

class _RolePoster extends StatelessWidget {
  final CodexRoleData role;
  final bool showChinese;
  final bool isDark;

  const _RolePoster({
    required this.role,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final label = showChinese ? role.roleCn : role.roleEn;
    final secondary = showChinese ? role.roleEn : role.roleCn;
    final imagePath = _roleImagePath(role);
    final accent = AppTheme.codexRoleAccent(label, isDark);

    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    imagePath,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: AppTheme.codexSectionHeaderBg(isDark),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withAlpha(170),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                          ),
                          if (secondary.isNotEmpty && secondary != label)
                            Text(
                              secondary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFDADADA),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _roleImagePath(CodexRoleData role) {
    final roleEn = role.roleEn.trim().toLowerCase();
    final roleCn = role.roleCn.trim();

    if (roleEn == 'lord' || roleCn == '主公') {
      return 'assets/images/miscellaneous/lord.webp';
    }
    if (roleEn == 'loyalist' || roleCn == '忠臣') {
      return 'assets/images/miscellaneous/loyalist.webp';
    }
    if (roleEn == 'rebel' || roleCn == '反贼') {
      return 'assets/images/miscellaneous/rebel.webp';
    }
    if (roleEn == 'spy' || roleCn == '内奸') {
      return 'assets/images/miscellaneous/spy.webp';
    }
    return 'assets/images/miscellaneous/lord.webp';
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

