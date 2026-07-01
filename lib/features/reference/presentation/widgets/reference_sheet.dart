import 'package:flutter/material.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/theme/app_theme.dart';
import '../../services/resolver_service.dart';

class ReferenceSheet extends StatelessWidget {
  final ResolvedReference ref;
  final bool showChinese;
  final bool isDark;

  const ReferenceSheet._({
    required this.ref,
    required this.showChinese,
    required this.isDark,
  });

  static Future<void> show({
    required BuildContext context,
    required String bracketText,
    required bool isChinese,
    required bool isDark,
    required bool showChinese,
  }) async {
    final refs = await ResolverService().resolve(
      bracketText,
      isChinese: isChinese,
    );
    if (refs.isEmpty || !context.mounted) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ReferenceSheet._(
        ref: refs.first,
        showChinese: showChinese,
        isDark: isDark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF252526) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.16)
                    : Colors.black.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: AppTheme.codexDivider(isDark),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              child: switch (ref.type) {
                ReferenceType.libraryCard => _LibraryReferenceContent(
                  ref: ref,
                  showChinese: showChinese,
                  isDark: isDark,
                ),
                ReferenceType.skill => _SkillReferenceContent(
                  ref: ref,
                  showChinese: showChinese,
                  isDark: isDark,
                ),
                ReferenceType.token => _TokenReferenceContent(
                  ref: ref,
                  showChinese: showChinese,
                  isDark: isDark,
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SkillReferenceContent extends StatelessWidget {
  final ResolvedReference ref;
  final bool showChinese;
  final bool isDark;

  const _SkillReferenceContent({
    required this.ref,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final primaryName = showChinese ? ref.nameCn : ref.nameEn;
    final secondaryName = showChinese ? ref.nameEn : ref.nameCn;
    final primaryDesc = showChinese
        ? (ref.descriptionCn ?? '')
        : (ref.descriptionEn ?? '');
    final secondaryDesc = showChinese
        ? (ref.descriptionEn ?? '')
        : (ref.descriptionCn ?? '');
    final type = ref.skillType;
    final typeLabel = type == null
        ? ''
        : (showChinese ? type.labelCn : type.labelEn);
    final typeColor = type != null && type.hasBadge
        ? AppTheme.skillTypeColor(type)
        : AppTheme.codexSkillRef(isDark);

    return _ReferenceColumn(
      title: primaryName,
      subtitle: secondaryName == primaryName ? null : secondaryName,
      badge: type != null && type.hasBadge ? typeLabel : null,
      badgeColor: typeColor,
      body: primaryDesc,
      secondaryBody: secondaryDesc,
      isDark: isDark,
    );
  }
}

class _LibraryReferenceContent extends StatelessWidget {
  final ResolvedReference ref;
  final bool showChinese;
  final bool isDark;

  const _LibraryReferenceContent({
    required this.ref,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final primaryName = showChinese ? ref.nameCn : ref.nameEn;
    final secondaryName = showChinese ? ref.nameEn : ref.nameCn;
    final primaryCat = showChinese
        ? ref.categoryCn ?? ''
        : ref.categoryEn ?? '';
    final effects =
        (showChinese ? ref.effectCn ?? const [] : ref.effectEn ?? const [])
            .where((effect) => effect.trim().isNotEmpty)
            .join('\n\n');
    final color = AppTheme.categoryColor(ref.categoryEn ?? '', isDark);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            ref.imagePath ?? '',
            width: 70,
            height: 98,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 70,
              height: 98,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.45)),
              ),
              child: Center(
                child: Image.asset(
                  AppAssets.libraryPlaceholder,
                  width: 40,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _ReferenceColumn(
            title: primaryName,
            subtitle: secondaryName == primaryName ? null : secondaryName,
            badge: primaryCat,
            badgeColor: color,
            body: effects,
            secondaryBody: ref.range == null
                ? null
                : (showChinese ? '攻击范围：${ref.range}' : 'Range: ${ref.range}'),
            isDark: isDark,
          ),
        ),
      ],
    );
  }
}

class _TokenReferenceContent extends StatelessWidget {
  final ResolvedReference ref;
  final bool showChinese;
  final bool isDark;

  const _TokenReferenceContent({
    required this.ref,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final primaryName = showChinese ? ref.nameCn : ref.nameEn;
    final secondaryName = showChinese ? ref.nameEn : ref.nameCn;
    final effects =
        (showChinese ? ref.effectCn ?? const [] : ref.effectEn ?? const [])
            .where((effect) => effect.trim().isNotEmpty)
            .join('\n\n');
    final body = effects.isNotEmpty
        ? effects
        : (showChinese
              ? '这是牌面或问答中引用的命名术语。若该术语影响发动或结算，相关 FAQ 应定义其具体含义。'
              : 'This is a named term referenced by the card text or FAQ. If it affects activation or resolution, the related FAQ should define its exact meaning.');
    final badge = showChinese
        ? ref.categoryCn ?? '标记'
        : ref.categoryEn ?? 'Token';
    final color = AppTheme.codexTokenRef(isDark);

    if (ref.imagePath == null || ref.imagePath!.isEmpty) {
      return _ReferenceColumn(
        title: '「$primaryName」',
        subtitle: secondaryName == primaryName ? null : secondaryName,
        badge: badge,
        badgeColor: color,
        body: body,
        isDark: isDark,
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            ref.imagePath!,
            width: 70,
            height: 98,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 70,
              height: 98,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.45)),
              ),
              child: Center(
                child: Image.asset(
                  AppAssets.generalPlaceholder,
                  width: 40,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _ReferenceColumn(
            title: '「$primaryName」',
            subtitle: secondaryName == primaryName ? null : secondaryName,
            badge: badge,
            badgeColor: color,
            body: body,
            isDark: isDark,
          ),
        ),
      ],
    );
  }
}

class _ReferenceColumn extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? badge;
  final Color badgeColor;
  final String body;
  final String? secondaryBody;
  final bool isDark;

  const _ReferenceColumn({
    required this.title,
    this.subtitle,
    this.badge,
    required this.badgeColor,
    required this.body,
    this.secondaryBody,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.codexTerm(isDark),
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.codexSecondaryText(isDark),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (badge != null && badge!.isNotEmpty) ...[
              const SizedBox(width: 10),
              _ReferencePill(label: badge!, color: badgeColor, isDark: isDark),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Divider(
          height: 0.5,
          thickness: 0.5,
          color: AppTheme.codexDivider(isDark),
        ),
        if (secondaryBody != null && secondaryBody!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            secondaryBody!,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: badgeColor,
            ),
          ),
        ],
        if (body.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            body,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.72,
              color: AppTheme.codexDefinition(isDark),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReferencePill extends StatelessWidget {
  final String label;
  final Color color;
  final bool isDark;

  const _ReferencePill({
    required this.label,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.08),
        border: Border.all(color: color.withValues(alpha: 0.48)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1,
        ),
      ),
    );
  }
}
