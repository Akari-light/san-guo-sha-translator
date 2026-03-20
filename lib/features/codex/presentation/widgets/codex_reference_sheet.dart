// lib/features/codex/presentation/widgets/codex_reference_sheet.dart
//
// Bottom sheet that surfaces inline reference info when a [card] or [skill]
// segment is tapped in a Codex rule block.
//
// Architecture: pure core-dependent Codex widget.
//   • Imports only core/* — zero cross-feature presentation or data imports.
//   • ResolvedReference carries all display fields directly (set in
//     resolver_service.dart at resolution time), so no LibraryDTO needed here.
//   • Never navigates — displays inline. Caller retains full nav control.

import 'package:flutter/material.dart';
import '../../../../core/services/resolver_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/app_assets.dart';

class CodexReferenceSheet extends StatelessWidget {
  final ResolvedReference ref;
  final bool showChinese;
  final bool isDark;

  const CodexReferenceSheet._({
    required this.ref,
    required this.showChinese,
    required this.isDark,
  });

  // ── Public entry point ──────────────────────────────────────────────────────

  /// Resolves [bracketText] via [ResolverService] and shows the sheet.
  /// Silently does nothing if the text is unresolvable (e.g. a rule keyword).
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
      builder: (_) => CodexReferenceSheet._(
        ref: refs.first,
        showChinese: showChinese,
        isDark: isDark,
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bg      = isDark ? const Color(0xFF252526) : Colors.white;
    final divider = AppTheme.codexDivider(isDark);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withAlpha(40)
                    : Colors.black.withAlpha(25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Divider(height: 1, thickness: 0.5, color: divider),

          // Content — scrollable for long descriptions
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              child: ref.type == ReferenceType.skill
                  ? _SkillContent(
                      ref: ref,
                      showChinese: showChinese,
                      isDark: isDark,
                    )
                  : _LibraryContent(
                      ref: ref,
                      showChinese: showChinese,
                      isDark: isDark,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Skill content ─────────────────────────────────────────────────────────────

class _SkillContent extends StatelessWidget {
  final ResolvedReference ref;
  final bool showChinese;
  final bool isDark;

  const _SkillContent({
    required this.ref,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final primaryName   = showChinese ? ref.nameCn : ref.nameEn;
    final secondaryName = showChinese ? ref.nameEn : ref.nameCn;
    final primaryDesc   = showChinese
        ? (ref.descriptionCn ?? '')
        : (ref.descriptionEn ?? '');
    final secondaryDesc = showChinese
        ? (ref.descriptionEn ?? '')
        : (ref.descriptionCn ?? '');

    final type = ref.skillType;
    final typeColor = (type != null && type.hasBadge)
        ? AppTheme.skillTypeColor(type)
        : AppTheme.codexSecondaryText(isDark);
    final typeLabel = type == null
        ? ''
        : (showChinese ? type.labelCn : type.labelEn);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name + type badge row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    primaryName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.codexTerm(isDark),
                    ),
                  ),
                  if (secondaryName != primaryName) ...[
                    const SizedBox(height: 2),
                    Text(
                      secondaryName,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.codexSecondaryText(isDark),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (type != null && type.hasBadge) ...[
              const SizedBox(width: 10),
              _Pill(label: typeLabel, color: typeColor, isDark: isDark),
            ],
          ],
        ),

        const SizedBox(height: 14),
        Divider(height: 0.5, thickness: 0.5, color: AppTheme.codexDivider(isDark)),
        const SizedBox(height: 12),

        // Primary description
        Text(
          primaryDesc,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.75,
            color: AppTheme.codexDefinition(isDark),
          ),
        ),

        // Secondary description
        if (secondaryDesc.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            secondaryDesc,
            style: TextStyle(
              fontSize: 12,
              height: 1.65,
              color: AppTheme.codexSecondaryText(isDark),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Library card content ──────────────────────────────────────────────────────

class _LibraryContent extends StatelessWidget {
  final ResolvedReference ref;
  final bool showChinese;
  final bool isDark;

  const _LibraryContent({
    required this.ref,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final primaryName   = showChinese ? ref.nameCn   : ref.nameEn;
    final secondaryName = showChinese ? ref.nameEn   : ref.nameCn;
    final primaryCat    = showChinese
        ? (ref.categoryCn ?? '')
        : (ref.categoryEn ?? '');
    final effects = (showChinese
            ? (ref.effectCn ?? <String>[])
            : (ref.effectEn ?? <String>[]))
        .where((e) => e.trim().isNotEmpty)
        .toList();

    final catColor = AppTheme.categoryColor(ref.categoryEn ?? '', isDark);
    final imgPath  = ref.imagePath ?? '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card artwork thumbnail
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            imgPath,
            width: 70,
            height: 98,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 70,
              height: 98,
              decoration: BoxDecoration(
                color: catColor.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: catColor.withAlpha(80), width: 1),
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

        // Text content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name + category pill
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          primaryName,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.codexTerm(isDark),
                          ),
                        ),
                        if (secondaryName != primaryName) ...[
                          const SizedBox(height: 2),
                          Text(
                            secondaryName,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.codexSecondaryText(isDark),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Pill(
                    label: primaryCat,
                    color: catColor,
                    isDark: isDark,
                    rounded: false,
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Range (weapons only)
              if (ref.range != null) ...[
                Row(
                  children: [
                    Text(
                      showChinese ? '攻击范围: ' : 'Range: ',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.codexSecondaryText(isDark),
                      ),
                    ),
                    Text(
                      '${ref.range}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: catColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // Effects
              ...effects.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      e,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.7,
                        color: AppTheme.codexDefinition(isDark),
                      ),
                    ),
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Shared pill badge ─────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final bool isDark;
  final bool rounded;

  const _Pill({
    required this.label,
    required this.color,
    required this.isDark,
    this.rounded = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 35 : 20),
        border: Border.all(color: color.withAlpha(isDark ? 120 : 100), width: 1),
        borderRadius: BorderRadius.circular(rounded ? 20 : 5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
          height: 1,
        ),
      ),
    );
  }
}