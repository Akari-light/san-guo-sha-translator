import 'package:flutter/foundation.dart';

import '../models/skill_dto.dart';
import '../../features/generals/data/repository/general_loader.dart';
import '../../features/library/data/models/library_dto.dart';
import '../../features/library/data/repository/library_loader.dart';

// ── Result types ──────────────────────────────────────────────────────────────

enum ReferenceType { libraryCard, skill }

/// A single resolved bracket reference from a skill or card description.
/// e.g. 【杀】 → the Kill LibraryDTO,  【武圣】 → the Wusheng SkillDTO
class ResolvedReference {
  final String bracketText; // raw text found inside 【】or []
  final ReferenceType type;
  final LibraryDTO? libraryCard;
  final SkillDTO? skill;

  const ResolvedReference._({
    required this.bracketText,
    required this.type,
    this.libraryCard,
    this.skill,
  });

  factory ResolvedReference.library(String text, LibraryDTO card) =>
      ResolvedReference._(
        bracketText: text,
        type: ReferenceType.libraryCard,
        libraryCard: card,
      );

  factory ResolvedReference.skill(String text, SkillDTO skill) =>
      ResolvedReference._(
        bracketText: text,
        type: ReferenceType.skill,
        skill: skill,
      );

  /// Display name for UI chips — prefers CN, falls back to bracket text.
  String get nameCn => libraryCard?.nameCn ?? skill?.nameCn ?? bracketText;
  String get nameEn => libraryCard?.nameEn ?? skill?.nameEn ?? bracketText;
}

// ── Service ───────────────────────────────────────────────────────────────────

/// Scans skill/card description text for 【bracket】 references and resolves
/// them to known LibraryDTO cards or SkillDTOs.
///
/// Resolution priority:
///   1. Library card name (CN or EN)
///   2. Skill name (CN or EN)
///   3. Logged as unresolved (data gap — check your JSON)
///
/// Lives in core/services/ because it cross-references both features.
class ResolverService {
  // ── Singleton ───────────────────────────────────────────────────────────────
  static final ResolverService _instance = ResolverService._internal();
  factory ResolverService() => _instance;
  ResolverService._internal();

  // ── Regex ───────────────────────────────────────────────────────────────────
  // Matches 【杀】【闪】【桃】etc. — CN descriptions
  static final RegExp _cnBrackets = RegExp(r'【([^】]+)】');
  // Matches [Kill] [Dodge] [Peach] etc. — EN descriptions
  static final RegExp _enBrackets = RegExp(r'\[([^\]]+)\]');

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Resolve all bracket references in [text].
  /// Set [isChinese: false] for EN descriptions.
  /// Returns deduplicated results in order of first appearance.
  Future<List<ResolvedReference>> resolve(
    String text, {
    bool isChinese = true,
  }) async {
    final tokens = _extractTokens(text, isChinese: isChinese);
    if (tokens.isEmpty) return [];

    // Both loaders are cached singletons — no repeated disk I/O
    final libraryCards = await LibraryLoader().getCards();
    final skillMap = await GeneralLoader().getSkillMap();

    // Build fast lookup maps
    final Map<String, LibraryDTO> libByCn = {
      for (final c in libraryCards) c.nameCn: c,
    };
    final Map<String, LibraryDTO> libByEn = {
      for (final c in libraryCards) c.nameEn.toLowerCase(): c,
    };
    // Also index by aliasEn entries (e.g. "Kill" → Kill card)
    for (final c in libraryCards) {
      for (final alias in (c.aliasEn ?? [])) {
        libByEn.putIfAbsent(alias.toLowerCase(), () => c);
      }
    }

    final Map<String, SkillDTO> skillByCn = {
      for (final s in skillMap.values) s.nameCn: s,
    };
    final Map<String, SkillDTO> skillByEn = {
      for (final s in skillMap.values) s.nameEn.toLowerCase(): s,
    };

    final List<ResolvedReference> results = [];
    final Set<String> seen = {};

    for (final token in tokens) {
      if (seen.contains(token)) continue;
      seen.add(token);

      ResolvedReference? ref;

      if (isChinese) {
        if (libByCn.containsKey(token)) {
          ref = ResolvedReference.library(token, libByCn[token]!);
        } else if (skillByCn.containsKey(token)) {
          ref = ResolvedReference.skill(token, skillByCn[token]!);
        }
      } else {
        final lower = token.toLowerCase();
        if (libByEn.containsKey(lower)) {
          ref = ResolvedReference.library(token, libByEn[lower]!);
        } else if (skillByEn.containsKey(lower)) {
          ref = ResolvedReference.skill(token, skillByEn[lower]!);
        }
      }

      if (ref != null) {
        results.add(ref);
      } else {
        // Helps catch missing library/skill data during development
        debugPrint('[ResolverService] Unresolved: 【$token】');
      }
    }

    return results;
  }

  /// Convenience: resolve references from all skills on a general.
  /// Returns a flat deduplicated list across all skill descriptions.
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

  // ── Private ─────────────────────────────────────────────────────────────────

  List<String> _extractTokens(String text, {required bool isChinese}) {
    final pattern = isChinese ? _cnBrackets : _enBrackets;
    return pattern
        .allMatches(text)
        .map((m) => m.group(1)!)
        .where((t) => t.isNotEmpty)
        .toList();
  }
}