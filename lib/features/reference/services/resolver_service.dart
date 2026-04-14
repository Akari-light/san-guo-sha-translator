import 'package:flutter/foundation.dart';

import '../../../core/models/skill_dto.dart';
import '../../generals/data/repository/general_loader.dart';
import '../../library/data/models/library_dto.dart';
import '../../library/data/repository/library_loader.dart';

enum ReferenceType { libraryCard, skill }

class ResolvedReference {
  final String bracketText;
  final ReferenceType type;
  final String nameCn;
  final String nameEn;
  final SkillType? skillType;
  final String? descriptionCn;
  final String? descriptionEn;
  final String? id;
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
        type: ReferenceType.libraryCard,
        nameCn: card.nameCn,
        nameEn: card.nameEn,
        id: card.id,
        categoryCn: card.categoryCn,
        categoryEn: card.categoryEn,
        imagePath: card.imagePath,
        effectCn: List<String>.from(card.effectCn),
        effectEn: List<String>.from(card.effectEn),
        range: card.range,
      );

  factory ResolvedReference.fromSkill(String text, SkillDTO skill) =>
      ResolvedReference._(
        bracketText: text,
        type: ReferenceType.skill,
        nameCn: skill.nameCn,
        nameEn: skill.nameEn,
        skillType: skill.skillType,
        descriptionCn: skill.descriptionCn,
        descriptionEn: skill.descriptionEn,
      );
}

class ResolverService {
  static final ResolverService _instance = ResolverService._internal();
  factory ResolverService() => _instance;
  ResolverService._internal();

  static final RegExp _cnBrackets = RegExp(
    '(?:\u3010([^\u3011]+)\u3011|\u3016([^\u3017]+)\u3017)',
  );
  static final RegExp _enBrackets = RegExp(
    '(?:\\[([^\\]]+)\\]|\u3016([^\u3017]+)\u3017)',
  );

  Set<String>? _resolvableCn;
  Map<String, LibraryDTO>? _libByCn;
  Map<String, LibraryDTO>? _libByEn;
  Map<String, SkillDTO>? _skillByCn;
  Map<String, SkillDTO>? _skillByEn;

  bool? canResolve(String bracketText, {bool isChinese = true}) {
    if (_resolvableCn == null || _libByEn == null || _skillByEn == null) {
      return null;
    }

    final bare = bracketText.length >= 2 &&
            ((bracketText.startsWith('\u3010') &&
                    bracketText.endsWith('\u3011')) ||
                (bracketText.startsWith('\u3016') &&
                    bracketText.endsWith('\u3017')) ||
                (bracketText.startsWith('[') && bracketText.endsWith(']')))
        ? bracketText.substring(1, bracketText.length - 1)
        : bracketText;

    if (isChinese) {
      return _resolvableCn!.contains(bare);
    }

    final lower = bare.toLowerCase();
    return _libByEn!.containsKey(lower) || _skillByEn!.containsKey(lower);
  }

  Future<void> _ensureCache() async {
    if (_resolvableCn != null) return;

    final libraryCards = await LibraryLoader().getCards();
    final skillMap = await GeneralLoader().getSkillMap();

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

    final results = <ResolvedReference>[];
    final seen = <String>{};

    for (final token in tokens) {
      if (!seen.add(token)) continue;

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
        debugPrint('[ResolverService] Unresolved reference: $token');
      }
    }

    return results;
  }

  Future<List<ResolvedReference>> resolveGeneralSkills(
    List<SkillDTO> skills, {
    bool isChinese = true,
  }) async {
    final seen = <String>{};
    final results = <ResolvedReference>[];

    for (final skill in skills) {
      final text = isChinese ? skill.descriptionCn : skill.descriptionEn;
      final refs = await resolve(text, isChinese: isChinese);
      for (final ref in refs) {
        if (seen.add(ref.bracketText)) {
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
        .map((m) => m.group(1) ?? m.group(2) ?? '')
        .where((t) => t.isNotEmpty)
        .toList();
  }
}
