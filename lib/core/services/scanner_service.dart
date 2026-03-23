// lib/core/services/scanner_service.dart
//
// Two-stage card matching pipeline — optimised for speed and accuracy.
//
// ── Optimisations vs the original version ──────────────────────────────────
//
// 1. OCR eliminated from ScannerService entirely.
//    scanner_screen.dart already runs OCR once for the bounding-box overlay.
//    The RecognizedText is passed directly to match() so MLKit never runs twice.
//    The temp-file write / getTemporaryDirectory() call is also gone.
//
// 2. Warmup cache (warmup()).
//    Every general and library card is pre-processed into a flat _CardEntry
//    struct at startup: normalised ID, normalised name, skill name list.
//    Built once, reused every scan. The hot path does zero JSON parsing,
//    zero SkillDTO iteration, and zero TextNormaliser calls per scan.
//    Both buckets warm up in parallel via Future.wait().
//
// 3. Card-type detection before searching.
//    OCR tokens contain definitive signals for General vs Library cards.
//    General: 锁定技 / 限定技 / 觉醒技 / 主公技 / 体力上限 / JX / YJ / SP
//    Library: 锦囊 / 武器 / 防具 / 坐骑 / 宝物 / 攻击范围 / 重铸
//    When one type is detected the other bucket is skipped entirely.
//    Ambiguous = both buckets searched (safe fallback).
//
// 4. Card serial ID matching (+3 score).
//    OCR reads the printed serial reliably (e.g. "SPSHU170" from "SP_SHU170").
//    _idMatches() strips non-alphanumeric chars from each token and compares.
//    Minimum token length 4 prevents bare "170" matching unrelated cards.
//    Score +3 > name match +2, so a serial hit drives the fast-path alone.
//
// 5. Strategy 3 (single shared CJK char) removed.
//    Common chars like '张' in '张牌' matched every Zhang-surnamed general.
//    Only Strategy 1 (direct substring) and Strategy 2 (CJK bigram on
//    short tokens ≤8 chars) remain.
//
// 6. Separate _nameMatchesLibrary().
//    Library name matching restricted to short tokens (≤8 chars) for BOTH
//    strategies. Long OCR tokens are description sentences that contain
//    library card names — e.g. "锁定技南蛮入侵对你无效" contains "南蛮入侵".
//    Short tokens are serial fragments, skill labels, or card names — safe.
//
// 7. Library minimum score = 3 when hint is unknown.
//    A library card with only a name match (+2) during an ambiguous scan is
//    caused by the library card name appearing in skill description text.
//    Require serial ID match (+3) to show library cards in ambiguous mode.
//
// 8. pHash uses 100% of the image — no crop.
//    img.decodeImage() removed; hashFromBytes() accepts raw JPEG directly.
//
// Architecture: core/services only. No feature/*/presentation imports.
// GeneralLoader + LibraryLoader: core→feature/data — permitted.

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    show RecognizedText;

import 'recently_viewed_service.dart';
import 'text_normaliser.dart';
import 'image_hash_matcher.dart';
import '../../../features/generals/data/repository/general_loader.dart';
import '../../../features/library/data/repository/library_loader.dart';

// ── Public types ───────────────────────────────────────────────────────────

class MatchCandidate {
  final String cardId;
  final RecordType recordType;
  final String nameCn;
  final String nameEn;
  final String imagePath;
  final double confidence;

  const MatchCandidate({
    required this.cardId,
    required this.recordType,
    required this.nameCn,
    required this.nameEn,
    required this.imagePath,
    required this.confidence,
  });
}

class ScannerResult {
  final List<MatchCandidate> candidates;
  final String debugMessage;

  const ScannerResult({
    this.candidates = const [],
    required this.debugMessage,
  });

  bool get hasMatch => candidates.isNotEmpty;
}

// ── Card-type hint ─────────────────────────────────────────────────────────

enum _CardTypeHint { general, library, unknown }

// ── Warmup cache entry ─────────────────────────────────────────────────────

class _CardEntry {
  final String cardId;
  final RecordType recordType;
  final String nameCn;
  final String nameEn;
  final String imagePath;
  final String normId;
  final String normName;
  final List<String> skillNames;

  const _CardEntry({
    required this.cardId,
    required this.recordType,
    required this.nameCn,
    required this.nameEn,
    required this.imagePath,
    required this.normId,
    required this.normName,
    required this.skillNames,
  });
}

// ── _ScoredCandidate ───────────────────────────────────────────────────────

class _ScoredCandidate {
  final _CardEntry entry;
  int score = 0;
  _ScoredCandidate(this.entry);
}

// ── ScannerService ─────────────────────────────────────────────────────────

class ScannerService {
  ScannerService._();
  static final ScannerService instance = ScannerService._();

  List<_CardEntry>? _generalEntries;
  List<_CardEntry>? _libraryEntries;
  bool _warmingUp = false;

  static const _generalSignals = <String>[
    '锁定技', '限定技', '觉醒技', '主公技', '使命技', '转换技',
    '体力上限', '体力值',
    'JXSHU', 'JXWEI', 'JXWU', 'JXQUN',
    'YJSHU', 'YJWEI', 'YJWU', 'YJQUN',
    'MGSHU', 'MGWEI', 'MGWU', 'MGQUN',
    'MOSHU', 'MOWEI', 'MOWU', 'MOQUN',
    'SPSHU', 'SPWEI', 'SPWU', 'SPQUN',
  ];

  static const _librarySignals = <String>[
    '锦囊', '武器', '防具', '坐骑', '宝物',
    '攻击范围', '装备区', '重铸',
    '基本牌', '锦囊牌', '武器牌', '防具牌', '坐骑牌', '宝物牌',
  ];

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> warmup() async {
    if (_generalEntries != null || _warmingUp) return;
    _warmingUp = true;
    try {
      await Future.wait([_warmupGenerals(), _warmupLibrary()]);
      debugPrint('[Scanner] Warmup complete: '
          '${_generalEntries!.length} generals, '
          '${_libraryEntries!.length} library cards.');
    } finally {
      _warmingUp = false;
    }
  }

  Future<ScannerResult> match(
    Uint8List bytes, {
    RecognizedText? recognisedText,
    String sourceLabel = 'camera',
  }) async {
    return _runMatching(bytes, recognisedText, sourceLabel);
  }

  void dispose() {
    // No TextRecognizer to close — OCR lives in scanner_screen.dart.
  }

  // ── Warmup ────────────────────────────────────────────────────────────────

  Future<void> _warmupGenerals() async {
    final generals = await GeneralLoader().getGenerals();
    _generalEntries = generals.map((g) {
      final skillNames = g.skills
          .map((s) => TextNormaliser.normalise(s.nameCn))
          .where((n) => n.length >= 2)
          .toList();
      return _CardEntry(
        cardId:     g.id,
        recordType: RecordType.general,
        nameCn:     g.nameCn,
        nameEn:     g.nameEn,
        imagePath:  g.imagePath,
        normId:     _normaliseId(g.id),
        normName:   TextNormaliser.normalise(g.nameCn),
        skillNames: skillNames,
      );
    }).toList();
  }

  Future<void> _warmupLibrary() async {
    final cards = await LibraryLoader().getCards();
    _libraryEntries = cards.map((c) {
      return _CardEntry(
        cardId:     c.id,
        recordType: RecordType.library,
        nameCn:     c.nameCn,
        nameEn:     c.nameEn,
        imagePath:  c.imagePath,
        normId:     _normaliseId(c.id),
        normName:   TextNormaliser.normalise(c.nameCn),
        skillNames: const [],
      );
    }).toList();
  }

  // ── Pipeline ──────────────────────────────────────────────────────────────

  Future<ScannerResult> _runMatching(
    Uint8List bytes,
    RecognizedText? recognisedText,
    String sourceLabel,
  ) async {
    final sw = Stopwatch()..start();

    if (_generalEntries == null || _libraryEntries == null) {
      await warmup();
    }

    try {
      final ocrTokens = recognisedText != null
          ? _extractTokens(recognisedText)
          : <String>{};

      debugPrint('[Scanner] OCR tokens (${ocrTokens.length}): $ocrTokens');

      if (ocrTokens.isEmpty) {
        return ScannerResult(debugMessage: '[Scanner] No text tokens provided.');
      }

      final hint = _classifyCardType(ocrTokens);
      debugPrint('[Scanner] Card-type hint: ${hint.name}');

      final shortlist = _buildShortlist(ocrTokens, hint);
      debugPrint('[Scanner] Stage 1: ${shortlist.length} candidates'
          '${shortlist.isNotEmpty ? " top=${shortlist.first.entry.cardId}(${shortlist.first.score})" : ""}');

      if (shortlist.isEmpty) {
        return ScannerResult(debugMessage: '[Scanner] No match found.');
      }

      final top = shortlist.first;
      final gap = shortlist.length > 1 ? top.score - shortlist[1].score : top.score;

      if (top.score >= 2 && gap >= 2) {
        debugPrint('[Scanner] Fast-path: ${top.entry.cardId} '
            'score=${top.score} gap=$gap in ${sw.elapsedMilliseconds}ms');
        return ScannerResult(
          candidates: [_toCandidate(top, confidence: 1.0)],
          debugMessage: '[Scanner] Fast-path in ${sw.elapsedMilliseconds}ms.',
        );
      }

      final ranked = await _rankByImageHash(bytes, shortlist);
      debugPrint('[Scanner] Stage 2: ${ranked.length} passed threshold');

      if (ranked.isEmpty) {
        return ScannerResult(
          candidates: shortlist.take(3).map((c) =>
              _toCandidate(c, confidence: c.score / (top.score + 1.0))
          ).toList(),
          debugMessage:
              '[Scanner] Stage 1 fallback in ${sw.elapsedMilliseconds}ms.',
        );
      }

      sw.stop();
      return ScannerResult(
        candidates: ranked,
        debugMessage:
            '[Scanner] ${ranked.length} match(es) in ${sw.elapsedMilliseconds}ms.',
      );
    } catch (e, stack) {
      debugPrint('[Scanner] Error: $e\n$stack');
      return ScannerResult(debugMessage: '[Scanner] Error: $e');
    }
  }

  // ── Token extraction ──────────────────────────────────────────────────────

  Set<String> _extractTokens(RecognizedText recognised) {
    final tokens = <String>{};
    for (final block in recognised.blocks) {
      for (final line in block.lines) {
        final raw = line.text.trim();
        if (raw.isEmpty) continue;
        final normalised = TextNormaliser.normalise(raw);
        final parts = normalised.split(
          RegExp(r'[\s·•\-—\u3000\uff0c\u3001\uff0e]+'),
        );
        for (final part in parts) {
          final clean = part.replaceAll(
            RegExp(r'[^\u4e00-\u9fff\u3400-\u4dbfa-zA-Z0-9]'), '');
          if (clean.length >= 2) tokens.add(clean);
        }
        final fullClean = normalised.replaceAll(
          RegExp(r'[^\u4e00-\u9fff\u3400-\u4dbfa-zA-Z0-9]'), '');
        if (fullClean.length >= 4) tokens.add(fullClean);
      }
    }
    return tokens;
  }

  // ── Card-type classification ──────────────────────────────────────────────

  _CardTypeHint _classifyCardType(Set<String> tokens) {
    final allText  = tokens.join('');
    final allUpper = allText.toUpperCase();

    bool hasGeneral = false;
    bool hasLibrary = false;

    for (final sig in _generalSignals) {
      if (allText.contains(sig) || allUpper.contains(sig)) {
        hasGeneral = true;
        break;
      }
    }
    if (!hasGeneral) {
      for (final t in tokens) {
        final u = t.toUpperCase();
        if (u.startsWith('JX') || u.startsWith('YJ') || u.startsWith('MG') ||
            u.startsWith('MO') || u.startsWith('LE') || u.startsWith('SP')) {
          hasGeneral = true;
          break;
        }
      }
    }
    for (final sig in _librarySignals) {
      if (allText.contains(sig)) {
        hasLibrary = true;
        break;
      }
    }

    if (hasGeneral && !hasLibrary) return _CardTypeHint.general;
    if (hasLibrary && !hasGeneral) return _CardTypeHint.library;
    return _CardTypeHint.unknown;
  }

  // ── Scoring ───────────────────────────────────────────────────────────────

  List<_ScoredCandidate> _buildShortlist(
    Set<String> ocrTokens,
    _CardTypeHint hint,
  ) {
    final scores = <String, _ScoredCandidate>{};

    final searchGenerals = hint != _CardTypeHint.library;
    final searchLibrary  = hint != _CardTypeHint.general;

    if (searchGenerals) {
      for (final entry in _generalEntries!) {
        var s = 0;
        if (_idMatches(entry.normId, ocrTokens)) s += 3;
        if (_nameMatches(entry.normName, ocrTokens)) s += 2;
        for (final skillName in entry.skillNames) {
          if (ocrTokens.any((t) => skillName == t || t.contains(skillName))) {
            s += 1;
          }
        }
        if (s >= 1) scores[entry.cardId] = _ScoredCandidate(entry)..score = s;
      }
    }

    if (searchLibrary) {
      for (final entry in _libraryEntries!) {
        var s = 0;
        if (_idMatches(entry.normId, ocrTokens)) s += 3;
        if (_nameMatchesLibrary(entry.normName, ocrTokens)) s += 2;
        if (s >= 1) scores[entry.cardId] = _ScoredCandidate(entry)..score = s;
      }
    }

    // When hint is unknown, library cards must have a serial ID match to
    // appear — name-only matches come from skill description text (noise).
    final libraryMinScore = (hint == _CardTypeHint.unknown) ? 3 : 1;

    final shortlist = scores.values
        .where((c) {
          if (c.entry.recordType == RecordType.library) {
            return c.score >= libraryMinScore;
          }
          return c.score >= 1;
        })
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return shortlist.take(5).toList();
  }

  // ── Name matching — Generals ──────────────────────────────────────────────

  bool _nameMatches(String normName, Set<String> ocrTokens) {
    for (final token in ocrTokens) {
      if (normName.contains(token) || token.contains(normName)) return true;
      if (token.length >= 2 && token.length <= 8 && normName.length >= 2) {
        for (var i = 0; i <= token.length - 2; i++) {
          final b = token.substring(i, i + 2);
          if (_isCjk(b[0]) && _isCjk(b[1]) && normName.contains(b)) return true;
        }
      }
    }
    return false;
  }

  // ── Name matching — Library (strict short-token only) ─────────────────────

  bool _nameMatchesLibrary(String normName, Set<String> ocrTokens) {
    for (final token in ocrTokens) {
      if (token.length < 2 || token.length > 8) continue;
      if (normName.contains(token) || token.contains(normName)) return true;
      if (normName.length >= 2) {
        for (var i = 0; i <= token.length - 2; i++) {
          final b = token.substring(i, i + 2);
          if (_isCjk(b[0]) && _isCjk(b[1]) && normName.contains(b)) return true;
        }
      }
    }
    return false;
  }

  // ── ID matching ───────────────────────────────────────────────────────────

  bool _idMatches(String normId, Set<String> ocrTokens) {
    for (final token in ocrTokens) {
      final clean = token.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
      if (clean.length < 4) continue;
      if (clean == normId) return true;
      if (normId.contains(clean) && clean.length >= normId.length - 2) return true;
    }
    return false;
  }

  String _normaliseId(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

  bool _isCjk(String ch) {
    final cp = ch.codeUnitAt(0);
    return (cp >= 0x4e00 && cp <= 0x9fff) || (cp >= 0x3400 && cp <= 0x4dbf);
  }

  // ── Stage 2: pHash tie-breaker (100% image, no crop) ─────────────────────

  Future<List<MatchCandidate>> _rankByImageHash(
    Uint8List bytes,
    List<_ScoredCandidate> shortlist,
  ) async {
    final queryHash = ImageHashMatcher.instance.hashFromBytes(bytes);
    if (queryHash == null) return [];

    final results = <MatchCandidate>[];

    for (final candidate in shortlist) {
      final refHash = await ImageHashMatcher.instance
          .hashFromAsset(candidate.entry.imagePath);

      if (refHash == null) {
        results.add(_toCandidate(
          candidate,
          confidence: candidate.score / (shortlist.first.score + 1.0),
        ));
        continue;
      }

      final sim = ImageHashMatcher.instance.similarity(queryHash, refHash);
      if (sim >= 0.35) {
        results.add(_toCandidate(candidate, confidence: sim));
      }
    }

    results.sort((a, b) => b.confidence.compareTo(a.confidence));
    return results.take(5).toList();
  }

  // ── Utility ───────────────────────────────────────────────────────────────

  MatchCandidate _toCandidate(
    _ScoredCandidate c, {
    required double confidence,
  }) =>
      MatchCandidate(
        cardId:     c.entry.cardId,
        recordType: c.entry.recordType,
        nameCn:     c.entry.nameCn,
        nameEn:     c.entry.nameEn,
        imagePath:  c.entry.imagePath,
        confidence: confidence,
      );
}