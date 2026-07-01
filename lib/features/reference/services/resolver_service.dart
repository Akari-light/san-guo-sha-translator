import 'package:flutter/foundation.dart';

import '../../../core/models/skill_dto.dart';
import '../../generals/data/models/general_card.dart';
import '../../generals/data/repository/general_loader.dart';
import '../../library/data/models/library_dto.dart';
import '../../library/data/repository/library_loader.dart';

enum ReferenceType { libraryCard, skill, token }

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

  factory ResolvedReference.fromToken(String text) => ResolvedReference._(
    bracketText: text,
    type: ReferenceType.token,
    nameCn: text,
    nameEn: text,
  );

  factory ResolvedReference.fromNamedToken({
    required String nameCn,
    required String nameEn,
  }) => ResolvedReference._(
    bracketText: nameCn,
    type: ReferenceType.token,
    nameCn: nameCn,
    nameEn: nameEn,
  );

  factory ResolvedReference.fromTokenCard(String text, GeneralCard token) {
    final skill = token.skills.isEmpty ? null : token.skills.first;
    return ResolvedReference._(
      bracketText: text,
      type: ReferenceType.token,
      nameCn: token.nameCn,
      nameEn: token.nameEn,
      id: token.id,
      categoryCn: token.traitsCn.isEmpty ? '标记牌' : token.traitsCn.first,
      categoryEn: token.traitsEn.isEmpty ? 'Token' : token.traitsEn.first,
      imagePath: token.imagePath,
      effectCn: skill == null ? null : [skill.descriptionCn],
      effectEn: skill == null ? null : [skill.descriptionEn],
    );
  }
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
  static final RegExp _tokens = RegExp('\u300c([^\u300d]+)\u300d');

  Set<String>? _resolvableCn;
  Map<String, LibraryDTO>? _libByCn;
  Map<String, LibraryDTO>? _libByEn;
  Map<String, SkillDTO>? _skillByCn;
  Map<String, SkillDTO>? _skillByEn;
  Map<String, GeneralCard>? _tokenByCn;
  Map<String, GeneralCard>? _tokenByEn;
  Map<String, List<GeneralCard>>? _tokensBySourceSkillId;

  bool? canResolve(String bracketText, {bool isChinese = true}) {
    if (_resolvableCn == null || _libByEn == null || _skillByEn == null) {
      return null;
    }

    final bare =
        bracketText.length >= 2 &&
            ((bracketText.startsWith('\u3010') &&
                    bracketText.endsWith('\u3011')) ||
                (bracketText.startsWith('\u3016') &&
                    bracketText.endsWith('\u3017')) ||
                (bracketText.startsWith('[') && bracketText.endsWith(']')) ||
                (bracketText.startsWith('\u300c') &&
                    bracketText.endsWith('\u300d')))
        ? bracketText.substring(1, bracketText.length - 1)
        : bracketText;

    if (isChinese) {
      if (bracketText.startsWith('\u300c') && bracketText.endsWith('\u300d')) {
        return bare.isNotEmpty;
      }
      return _resolvableCn!.contains(bare);
    }

    if (bracketText.startsWith('\u300c') && bracketText.endsWith('\u300d')) {
      return bare.isNotEmpty;
    }

    final lower = bare.toLowerCase();
    return _libByEn!.containsKey(lower) || _skillByEn!.containsKey(lower);
  }

  Future<void> _ensureCache() async {
    if (_resolvableCn != null) return;

    final libraryCards = await LibraryLoader().getCards();
    final skillMap = await GeneralLoader().getSkillMap();
    final generals = await GeneralLoader().getGenerals();
    final tokenCards = generals
        .where((card) => card.id.startsWith('TOKEN_'))
        .toList(growable: false);

    _resolvableCn = {
      for (final c in libraryCards) c.nameCn,
      for (final s in skillMap.values) s.nameCn,
      for (final token in tokenCards) token.nameCn,
      for (final token in tokenCards) ...token.aliases,
    };
    _libByCn = {for (final card in libraryCards) card.nameCn: card};
    _libByEn = {
      for (final card in libraryCards) card.nameEn.toLowerCase(): card,
    };
    _skillByCn = {for (final skill in skillMap.values) skill.nameCn: skill};
    _skillByEn = {
      for (final skill in skillMap.values) skill.nameEn.toLowerCase(): skill,
    };
    _tokenByCn = {
      for (final token in tokenCards) _normalizeTokenKey(token.nameCn): token,
      for (final token in tokenCards)
        for (final alias in token.aliases) _normalizeTokenKey(alias): token,
    };
    _tokenByEn = {
      for (final token in tokenCards)
        _normalizeTokenKey(token.nameEn).toLowerCase(): token,
      for (final token in tokenCards)
        for (final alias in token.aliases)
          _normalizeTokenKey(alias).toLowerCase(): token,
    };
    _tokensBySourceSkillId = {};
    for (final token in tokenCards) {
      for (final sourceSkillId in token.sourceSkillIds) {
        _tokensBySourceSkillId
            ?.putIfAbsent(sourceSkillId, () => <GeneralCard>[])
            .add(token);
      }
    }
  }

  Future<List<ResolvedReference>> resolve(
    String text, {
    bool isChinese = true,
  }) async {
    await _ensureCache();
    final tokens = _extractBracketTokens(text, isChinese: isChinese);
    final tokenRefs = _extractTokenRefs(text);
    if (tokens.isEmpty && tokenRefs.isEmpty) return [];

    final results = <ResolvedReference>[];
    final seen = <String>{};

    for (final token in tokens) {
      if (!seen.add(token)) continue;

      ResolvedReference? ref;

      if (isChinese) {
        final libraryCard = _libByCn?[token];
        final skill = _skillByCn?[token];
        final tokenCard = _tokenByCn == null
            ? null
            : _tokenByCn![_normalizeTokenKey(token)];
        if (libraryCard != null) {
          ref = ResolvedReference.fromLibrary(token, libraryCard);
        } else if (skill != null) {
          ref = ResolvedReference.fromSkill(token, skill);
        } else if (tokenCard != null) {
          ref = ResolvedReference.fromTokenCard(token, tokenCard);
        }
      } else {
        final lower = token.toLowerCase();
        final libraryCard = _libByEn?[lower];
        final skill = _skillByEn?[lower];
        final tokenCard = _tokenByEn == null
            ? null
            : _tokenByEn![_normalizeTokenKey(token).toLowerCase()];
        if (libraryCard != null) {
          ref = ResolvedReference.fromLibrary(token, libraryCard);
        } else if (skill != null) {
          ref = ResolvedReference.fromSkill(token, skill);
        } else if (tokenCard != null) {
          ref = ResolvedReference.fromTokenCard(token, tokenCard);
        }
      }

      if (ref != null) {
        if (seen.add('${ref.type.name}:${ref.bracketText}')) {
          results.add(ref);
        }
      } else {
        debugPrint('[ResolverService] Unresolved reference: $token');
      }
    }

    for (final token in tokenRefs) {
      final tokenCard = isChinese
          ? (_tokenByCn == null ? null : _tokenByCn![_normalizeTokenKey(token)])
          : (_tokenByEn == null
                ? null
                : _tokenByEn![_normalizeTokenKey(token).toLowerCase()]);
      final ref = tokenCard == null
          ? ResolvedReference.fromToken(token)
          : ResolvedReference.fromTokenCard(token, tokenCard);
      if (seen.add('${ref.type.name}:${ref.bracketText}')) {
        results.add(ref);
      }
    }

    return results;
  }

  Future<List<ResolvedReference>> resolveGeneralSkills(
    List<SkillDTO> skills, {
    bool isChinese = true,
  }) async {
    await _ensureCache();
    final seen = <String>{};
    final results = <ResolvedReference>[];

    for (final skill in skills) {
      final text = isChinese ? skill.descriptionCn : skill.descriptionEn;
      final refs = await resolve(text, isChinese: isChinese);
      for (final ref in refs) {
        if (seen.add('${ref.type.name}:${ref.bracketText}')) {
          results.add(ref);
        }
      }
    }

    for (final skill in skills) {
      final tokens = _tokensBySourceSkillId?[skill.id] ?? const <GeneralCard>[];
      for (final token in tokens) {
        final ref = ResolvedReference.fromTokenCard(
          isChinese ? token.nameCn : token.nameEn,
          token,
        );
        if (seen.add('${ref.type.name}:${ref.id ?? ref.bracketText}')) {
          results.add(ref);
        }
      }
    }

    return results;
  }

  Future<List<ResolvedReference>> resolveLibraryEffects(
    List<String> effects, {
    bool isChinese = true,
  }) async {
    final seen = <String>{};
    final results = <ResolvedReference>[];

    for (final text in effects) {
      final refs = await resolve(text, isChinese: isChinese);
      for (final ref in refs) {
        if (seen.add('${ref.type.name}:${ref.bracketText}')) {
          results.add(ref);
        }
      }
    }

    return results;
  }

  List<String> _extractBracketTokens(String text, {required bool isChinese}) {
    final pattern = isChinese ? _cnBrackets : _enBrackets;
    return pattern
        .allMatches(text)
        .map((m) => m.group(1) ?? m.group(2) ?? '')
        .where((t) => t.isNotEmpty)
        .toList();
  }

  List<String> _extractTokenRefs(String text) {
    return _tokens
        .allMatches(text)
        .map((m) => m.group(1) ?? '')
        .where((t) => t.isNotEmpty)
        .toList();
  }

  String _normalizeTokenKey(String value) {
    return value
        .replaceAll('※', '')
        .replaceAll('\u300c', '')
        .replaceAll('\u300d', '')
        .trim();
  }
}
