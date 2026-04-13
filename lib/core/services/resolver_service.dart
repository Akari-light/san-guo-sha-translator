// lib/core/services/resolver_service.dart
//
// Resolves 【bracket】 references in skill/card descriptions to known
// LibraryDTO cards or SkillDTOs.
//
// ResolvedReference carries all display fields needed by CodexReferenceSheet
// directly — Codex presentation widgets never need to import LibraryDTO.

import 'package:flutter/foundation.dart';
import '../models/skill_dto.dart';
import '../../features/generals/data/repository/general_loader.dart';
import '../../features/library/data/models/library_dto.dart';
import '../../features/library/data/repository/library_loader.dart';

// ── Reference type ─────────────────────────────────────────────────────────────

enum ReferenceType { libraryCard, skill }

// ── Resolved reference ─────────────────────────────────────────────────────────
//
// Carries all display fields directly so callers (including Codex presentation
// widgets) never need to import LibraryDTO or SkillDTO themselves.

class ResolvedReference {
  final String bracketText;
  final ReferenceType type;

  // ── Shared fields ──────────────────────────────────────────────────────────
  final String nameCn;
  final String nameEn;

  // ── Skill fields (non-null when type == skill) ─────────────────────────────
  final SkillType? skillType;
  final String? descriptionCn;
  final String? descriptionEn;

  // ── Library card fields (non-null when type == libraryCard) ───────────────
  final String? id;         // library card id — used for navigation
  final String? categoryCn;
  final String? categoryEn;
  final String? imagePath;
  final List<String>? effectCn;
  final List<String>? effectEn;
  final int? range;

  const ResolvedReference._({
    required this.bracketText,
    required this.type,
    required this.nameCn,
    required this.nameEn,
    this.skillType,
    this.descriptionCn,
    this.descriptionEn,
    this.id,
    this.categoryCn,
    this.categoryEn,
    this.imagePath,
    this.effectCn,
    this.effectEn,
    this.range,
  });

  factory ResolvedReference.fromLibrary(String text, LibraryDTO card) =>
      ResolvedReference._(
        bracketText: text,
        type:        ReferenceType.libraryCard,
        nameCn:      card.nameCn,
        nameEn:      card.nameEn,
        id:          card.id,
        categoryCn:  card.categoryCn,
        categoryEn:  card.categoryEn,
        imagePath:   card.imagePath,
        effectCn:    List<String>.from(card.effectCn),
        effectEn:    List<String>.from(card.effectEn),
        range:       card.range,
      );

  factory ResolvedReference.fromSkill(String text, SkillDTO skill) =>
      ResolvedReference._(
        bracketText:    text,
        type:           ReferenceType.skill,
        nameCn:         skill.nameCn,
        nameEn:         skill.nameEn,
        skillType:      skill.skillType,
        descriptionCn:  skill.descriptionCn,
        descriptionEn:  skill.descriptionEn,
      );
}

// ── Service ────────────────────────────────────────────────────────────────────

class ResolverService {
  static final ResolverService _instance = ResolverService._internal();
  factory ResolverService() => _instance;
  ResolverService._internal();

  static final RegExp _cnBrackets = RegExp(r'【([^】]+)】');
  static final RegExp _enBrackets = RegExp(r'\[([^\]]+)\]');

  // ── Sync resolvability check ───────────────────────────────────────────────
  // Populated on first call to resolve(). Used by buildSegmentSpan to decide
  // whether to attach a TapGestureRecognizer without an async call.
  Set<String>? _resolvableCn; // bare CN names (no brackets)
  Map<String, LibraryDTO>? _libByCn;
  Map<String, LibraryDTO>? _libByEn;
  Map<String, SkillDTO>? _skillByCn;
  Map<String, SkillDTO>? _skillByEn;

  /// Returns true if [bracketText] (e.g. '【杀】') is known to be resolvable.
  /// Returns null if the cache hasn't been populated yet (first load pending).
  bool? canResolve(String bracketText) {
    final cache = _resolvableCn;
    if (cache == null) return null; // not yet populated
    final bare = bracketText.startsWith('【')
        ? bracketText.substring(1, bracketText.length - 1)
        : bracketText;
    return cache.contains(bare);
  }

  Future<void> _ensureCache() async {
    if (_resolvableCn != null) return;
    final libraryCards = await LibraryLoader().getCards();
    final skillMap     = await GeneralLoader().getSkillMap();
    _resolvableCn = {
      for (final c in libraryCards) c.nameCn,
      for (final s in skillMap.values) s.nameCn,
    };
    _libByCn = {
      for (final card in libraryCards) card.nameCn: card,
    };
    _libByEn = {
      for (final card in libraryCards) card.nameEn.toLowerCase(): card,
    };
    _skillByCn = {
      for (final skill in skillMap.values) skill.nameCn: skill,
    };
    _skillByEn = {
      for (final skill in skillMap.values) skill.nameEn.toLowerCase(): skill,
    };
  }

  Future<List<ResolvedReference>> resolve(
    String text, {
    bool isChinese = true,
  }) async {
    await _ensureCache();
    final tokens = _extractTokens(text, isChinese: isChinese);
    if (tokens.isEmpty) return [];

    final List<ResolvedReference> results = [];
    final Set<String> seen = {};

    for (final token in tokens) {
      if (seen.contains(token)) continue;
      seen.add(token);

      ResolvedReference? ref;

      if (isChinese) {
        final libraryCard = _libByCn?[token];
        final skill = _skillByCn?[token];
        if (libraryCard != null) {
          ref = ResolvedReference.fromLibrary(token, libraryCard);
        } else if (skill != null) {
          ref = ResolvedReference.fromSkill(token, skill);
        }
      } else {
        final lower = token.toLowerCase();
        final libraryCard = _libByEn?[lower];
        final skill = _skillByEn?[lower];
        if (libraryCard != null) {
          ref = ResolvedReference.fromLibrary(token, libraryCard);
        } else if (skill != null) {
          ref = ResolvedReference.fromSkill(token, skill);
        }
      }

      if (ref != null) {
        results.add(ref);
      } else {
        debugPrint('[ResolverService] Unresolved: 【$token】');
      }
    }

    return results;
  }

  Future<List<ResolvedReference>> resolveGeneralSkills(
    List<SkillDTO> skills, {
    bool isChinese = true,
  }) async {
    final Set<String> seen = {};
    final List<ResolvedReference> results = [];

    for (final skill in skills) {
      final text = isChinese ? skill.descriptionCn : skill.descriptionEn;
      final refs = await resolve(text, isChinese: isChinese);
      for (final ref in refs) {
        if (!seen.contains(ref.bracketText)) {
          seen.add(ref.bracketText);
          results.add(ref);
        }
      }
    }

    return results;
  }

  List<String> _extractTokens(String text, {required bool isChinese}) {
    final pattern = isChinese ? _cnBrackets : _enBrackets;
    return pattern
        .allMatches(text)
        .map((m) => m.group(1)!)
        .where((t) => t.isNotEmpty)
        .toList();
  }
}
