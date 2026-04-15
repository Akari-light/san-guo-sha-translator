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
          if (entry.roleDistribution.isNotEmpty || entry.roles.isNotEmpty) ...[
            const SizedBox(height: 12),
            _StructuredDetailsBlock(
              entry: entry,
              showChinese: showCn,
              isDark: isDark,
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

class _StructuredDetailsBlock extends StatelessWidget {
  final CodexEntryDTO entry;
  final bool showChinese;
  final bool isDark;

  const _StructuredDetailsBlock({
    required this.entry,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    if (entry.roleDistribution.isNotEmpty) {
      children.add(_ContentBlock(
        title: showChinese ? '身份分配' : 'Role Distribution',
        subtitle: showChinese
            ? '按人数矩阵查看每局使用的身份牌配置。'
            : 'Read the role mix by player count in a compact matrix.',
        isDark: isDark,
        child: _DistributionRail(
          rows: entry.roleDistribution,
          showChinese: showChinese,
          isDark: isDark,
        ),
      ));
    }

    if (entry.roles.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 12));
      }
      children.add(_ContentBlock(
        title: showChinese ? '身份角色' : 'Role Profiles',
        subtitle: showChinese
            ? '按身份逐一阅读目标与技巧，图片只做角色识别。'
            : 'Read each role as a profile with a clear objective and play guidance.',
        isDark: isDark,
        child: Column(
          children: entry.roles
              .map(
                (role) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RoleDetailPanel(
                    role: role,
                    showChinese: showChinese,
                    isDark: isDark,
                  ),
                ),
              )
              .toList(),
        ),
      ));
    }

    return Column(children: children);
  }
}

class _DistributionRail extends StatelessWidget {
  final List<CodexRoleDistributionRow> rows;
  final bool showChinese;
  final bool isDark;

  const _DistributionRail({
    required this.rows,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.codexTagFill(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.codexDivider(isDark),
          width: 0.8,
        ),
      ),
      child: _DistributionMatrix(
        rows: rows,
        showChinese: showChinese,
        isDark: isDark,
      ),
    );
  }
}

class _DistributionMatrix extends StatelessWidget {
  final List<CodexRoleDistributionRow> rows;
  final bool showChinese;
  final bool isDark;

  const _DistributionMatrix({
    required this.rows,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      _DistributionMatrixHeader(showChinese: showChinese, isDark: isDark),
    ];

    for (var i = 0; i < rows.length; i++) {
      children.add(
        _DistributionMatrixGroup(
          row: rows[i],
          isDark: isDark,
        ),
      );
      if (i < rows.length - 1) {
        children.add(
          Divider(
            height: 14,
            thickness: 0.7,
            color: AppTheme.codexDivider(isDark),
          ),
        );
      }
    }

    return Column(children: children);
  }
}

class _DistributionMatrixHeader extends StatelessWidget {
  final bool showChinese;
  final bool isDark;

  const _DistributionMatrixHeader({
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      color: AppTheme.codexSecondaryText(isDark),
      letterSpacing: 0.2,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              showChinese ? '人数' : 'P',
              style: style,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              showChinese ? '主公' : 'Lord',
              style: style.copyWith(color: AppTheme.codexLord(isDark)),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              showChinese ? '忠臣' : 'Loyalist',
              style: style.copyWith(color: AppTheme.codexLoyalist(isDark)),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              showChinese ? '反贼' : 'Rebel',
              style: style.copyWith(color: AppTheme.codexRebel(isDark)),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              showChinese ? '内奸' : 'Spy',
              style: style.copyWith(color: AppTheme.codexSpy(isDark)),
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

  const _DistributionMatrixGroup({
    required this.row,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final leftStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppTheme.codexDefinition(isDark),
    );
    final valueStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: AppTheme.codexTerm(isDark),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: IntrinsicHeight(
        child: Row(
          children: [
            SizedBox(
              width: 40,
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
                        bottom: optionIndex == row.options.length - 1 ? 0 : 6,
                      ),
                      child: _DistributionOptionRow(
                        option: row.options[optionIndex],
                        optionIndex: optionIndex,
                        isDark: isDark,
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
  final TextStyle valueStyle;

  const _DistributionOptionRow({
    required this.option,
    required this.optionIndex,
    required this.isDark,
    required this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      decoration: BoxDecoration(
        color: AppTheme.codexDistributionOptionFill(isDark, optionIndex),
        borderRadius: BorderRadius.circular(10),
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

class _RoleDetailPanel extends StatelessWidget {
  final CodexRoleData role;
  final bool showChinese;
  final bool isDark;

  const _RoleDetailPanel({
    required this.role,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final primaryRole = showChinese ? role.roleCn : role.roleEn;
    final secondaryRole = showChinese ? role.roleEn : role.roleCn;
    final goal = showChinese ? role.goalCn : role.goalEn;
    final tips = showChinese ? role.tipsCn : role.tipsEn;
    final imagePath = _roleImagePath(role);
    final accent = AppTheme.codexRoleAccent(primaryRole, isDark);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.codexSectionHeaderBg(isDark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.codexDivider(isDark),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              color: AppTheme.codexTagFill(isDark),
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.codexDivider(isDark),
                  width: 0.8,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 114,
                  height: 160,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.codexSectionHeaderBg(isDark),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.codexDivider(isDark),
                      width: 0.8,
                    ),
                  ),
                  child: Center(
                    child: Image.asset(
                      imagePath,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Container(
                        alignment: Alignment.center,
                        child: Text(
                          primaryRole.isEmpty ? '?' : primaryRole.substring(0, 1),
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.codexSecondaryText(isDark),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.codexNumBg('setup', isDark),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppTheme.codexNumBorder('setup', isDark),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            showChinese ? '身份' : 'Role',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.codexNumText('setup', isDark),
                              letterSpacing: 0.25,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          primaryRole,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                        if (secondaryRole.isNotEmpty && secondaryRole != primaryRole)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              secondaryRole,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.codexSecondaryText(isDark),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (goal.isNotEmpty) ...[
                  _DetailLabel(
                    text: showChinese ? '游戏目标' : 'Objective',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    goal,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: AppTheme.codexDefinition(isDark),
                    ),
                  ),
                ],
                if (goal.isNotEmpty && tips.isNotEmpty) const SizedBox(height: 14),
                if (tips.isNotEmpty) ...[
                  _DetailLabel(
                    text: showChinese ? '技巧' : 'Tips',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tips,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.65,
                      color: AppTheme.codexDefinition(isDark),
                    ),
                  ),
                ],
              ],
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

class _DetailLabel extends StatelessWidget {
  final String text;
  final bool isDark;

  const _DetailLabel({
    required this.text,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        color: AppTheme.codexSubText('setup', isDark),
      ),
    );
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
