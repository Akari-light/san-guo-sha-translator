// lib/core/services/scanner_service.dart
//
// Multimodal Fusion Engine — Phase 5 (Accuracy Diagnostics & Fixes)
//
// 4 root causes diagnosed from real-world scan samples:
//
//   CAUSE 1: Skill description text matches short library card names.
//     A general's skill text "...对处于濒死状态的角色使用一张【桃】..."
//     contains "桃" → FuzzyMatcher returns 1.0 for library card "桃"
//     via substring containment. With body zone weight 0.5, the library
//     card gets sText ≈ 0.167, enough to beat threshold with neutral sVisual.
//     FIX: _nameMatchScore() — when candidate is a library card with a
//     short name (≤4 chars) and the OCR token is much longer, discount
//     the score by 90%.
//
//   CAUSE 2: Domain classifier misses general signals.
//     Skill type labels (锁定技/限定技/主公技) are embedded in long lines
//     and the old +0.15 weight was too weak. Even when detected, the
//     margin might not exceed the 0.10 threshold.
//     FIX: Skill type keywords weighted at +0.40 (near-definitive signal).
//
//   CAUSE 3: Reference image hashes never pre-cached.
//     getCachedHash() returns null for every candidate → sVisual stuck at
//     0.5 (neutral) → pHash contributes ZERO discriminating signal.
//     FIX: Pre-cache ALL reference hashes during warmup().
//
//   CAUSE 4: Insufficient debug logging.
//     FIX: Comprehensive per-phase console logging of every token, domain
//     classification scores, top-5 candidates with full score breakdown.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    show RecognizedText, TextLine;
import 'package:image/image.dart' as img;

import 'recently_viewed_service.dart';
import 'text_normaliser.dart';
import 'fuzzy_matcher.dart';
import 'image_hash_matcher.dart';
import '../utils/perspective_warper.dart';
import '../../features/generals/data/repository/general_loader.dart';
import '../../features/library/data/repository/library_loader.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PUBLIC TYPES
// ═══════════════════════════════════════════════════════════════════════════════

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
  final bool fastPath;

  const ScannerResult({
    this.candidates = const [],
    required this.debugMessage,
    this.fastPath = false,
  });

  bool get hasMatch => candidates.isNotEmpty;
}

enum ScanSource { camera, gallery, userCrop, straightened }

// ═══════════════════════════════════════════════════════════════════════════════
// ZONED TOKEN
// ═══════════════════════════════════════════════════════════════════════════════

enum CardZone { name, id, type, body, unknown }

class ZonedToken {
  final String text;
  final CardZone zone;
  const ZonedToken({required this.text, required this.zone});

  @override
  String toString() => 'ZonedToken($text, ${zone.name})';
}

// ═══════════════════════════════════════════════════════════════════════════════
// INTERNAL TYPES
// ═══════════════════════════════════════════════════════════════════════════════

enum _DomainType { general, library, unknown }

class _CardEntry {
  final String cardId;
  final RecordType recordType;
  final String nameCn;
  final String nameEn;
  final String imagePath;
  final String normId;
  final String normName;
  final List<String> skillNames;
  final String? faction;
  final String? expansionLabel;

  const _CardEntry({
    required this.cardId,
    required this.recordType,
    required this.nameCn,
    required this.nameEn,
    required this.imagePath,
    required this.normId,
    required this.normName,
    required this.skillNames,
    this.faction,
    this.expansionLabel,
  });
}

class _ScoredFusionCandidate {
  final _CardEntry entry;
  final double sText;
  final double sVisual;
  final double domainGate;
  final double boost;
  final double finalScore;

  const _ScoredFusionCandidate({
    required this.entry,
    required this.sText,
    required this.sVisual,
    required this.domainGate,
    required this.boost,
    required this.finalScore,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

const _zoneWeights = <CardZone, double>{
  CardZone.name: 3.0,
  CardZone.id: 2.5,
  CardZone.type: 2.0,
  CardZone.body: 0.5,
  CardZone.unknown: 1.0,
};
const _maxZoneWeight = 3.0;

const _expansionPrefixToLabel = <String, String>{
  'JX': 'Limit Break',
  'YJ': "Hero's Soul",
  'MG': 'Strategic Assault',
  'MO': 'Demon',
  'LE': 'God',
  'SP': 'Other',
};

/// Skill type keywords that appear ONLY on general cards, never on library
/// cards. A single detection is near-definitive evidence of a general.
const _skillTypeKeywords = <String>{
  '锁定技', '限定技', '觉醒技', '主公技', '使命技', '转换技',
};

// ═══════════════════════════════════════════════════════════════════════════════
// SCANNER SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

class ScannerService {
  ScannerService._();
  static final ScannerService instance = ScannerService._();

  List<_CardEntry>? _generalEntries;
  List<_CardEntry>? _libraryEntries;
  bool _warmingUp = false;

  static const _generalKeywords = <String>[
    '锁定技', '限定技', '觉醒技', '主公技', '使命技', '转换技',
    '体力上限', '体力值',
  ];
  static const _libraryKeywords = <String>[
    '锦囊', '武器', '防具', '坐骑', '宝物', '攻击范围', '装备区', '重铸',
    '基本牌', '锦囊牌', '武器牌', '防具牌', '坐骑牌', '宝物牌',
  ];
  static final _expansionPrefixRe =
      RegExp(r'^(JX|YJ|MG|MO|LE|SP)', caseSensitive: false);
  static final _suitRankRe = RegExp(
    r'^[A2-9JQK10]{1,2}[♠♥♦♣\u2660\u2665\u2666\u2663]?$',
    caseSensitive: false,
  );

  // ═════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═════════════════════════════════════════════════════════════════════════

  /// CAUSE 3 FIX: warmup now pre-caches ALL reference image hashes.
  Future<void> warmup() async {
    if (_generalEntries != null || _warmingUp) { return; }
    _warmingUp = true;
    try {
      await Future.wait([_warmupGenerals(), _warmupLibrary()]);
      debugPrint('[Scanner] Warmup: ${_generalEntries!.length} generals, '
          '${_libraryEntries!.length} library cards');

      // Pre-cache reference image hashes so getCachedHash() returns
      // non-null during scoring. Without this, sVisual is always 0.5.
      int cached = 0;
      for (final e in [..._generalEntries!, ..._libraryEntries!]) {
        final h = await ImageHashMatcher.instance.hashFromAsset(e.imagePath);
        if (h != null) { cached++; }
      }
      debugPrint('[Scanner] Pre-cached $cached reference hashes');
    } finally {
      _warmingUp = false;
    }
  }

  Future<ScannerResult> match(
    Uint8List bytes, {
    RecognizedText? recognisedText,
    ScanSource source = ScanSource.camera,
    img.Image? straightenedImage,
  }) async {
    return _runFusion(bytes, recognisedText, source, straightenedImage);
  }

  void dispose() {}

  // ═════════════════════════════════════════════════════════════════════════
  // WARMUP
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _warmupGenerals() async {
    final generals = await GeneralLoader().getGenerals();
    _generalEntries = generals.map((g) => _CardEntry(
      cardId: g.id,
      recordType: RecordType.general,
      nameCn: g.nameCn,
      nameEn: g.nameEn,
      imagePath: g.imagePath,
      normId: _normaliseId(g.id),
      normName: TextNormaliser.normalise(g.nameCn),
      skillNames: g.skills
          .map((s) => TextNormaliser.normalise(s.nameCn))
          .where((n) => n.length >= 2)
          .toList(),
      faction: g.faction,
      expansionLabel: g.expansion.labelEn,
    )).toList();
  }

  Future<void> _warmupLibrary() async {
    final cards = await LibraryLoader().getCards();
    _libraryEntries = cards.map((c) => _CardEntry(
      cardId: c.id,
      recordType: RecordType.library,
      nameCn: c.nameCn,
      nameEn: c.nameEn,
      imagePath: c.imagePath,
      normId: _normaliseId(c.id),
      normName: TextNormaliser.normalise(c.nameCn),
      skillNames: const [],
    )).toList();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // FUSION PIPELINE
  // ═════════════════════════════════════════════════════════════════════════

  Future<ScannerResult> _runFusion(
    Uint8List bytes,
    RecognizedText? recognisedText,
    ScanSource source,
    img.Image? straightenedImage,
  ) async {
    final sw = Stopwatch()..start();
    if (_generalEntries == null || _libraryEntries == null) {
      await warmup();
    }

    try {
      if (source == ScanSource.straightened && straightenedImage != null) {
        straightenedImage = img.normalize(straightenedImage, min: 0, max: 255);
      }

      final zonedTokens = recognisedText != null
          ? _extractZonedTokens(recognisedText)
          : <ZonedToken>[];

      final bool ocrEmpty = zonedTokens.isEmpty;

      // ── DEBUG: Phase A — Input ────────────────────────────────────────
      debugPrint('╔═══════════════════════════════════════════════════');
      debugPrint('║ [Scanner] PHASE A — INPUT');
      debugPrint('║ Source: ${source.name} | Tokens: ${zonedTokens.length}');
      for (var i = 0; i < zonedTokens.length; i++) {
        debugPrint('║   [$i] "${zonedTokens[i].text}" → ${zonedTokens[i].zone.name}');
      }

      // ── Phase B: Signal extraction ─────────────────────────────────────

      final domain = ocrEmpty
          ? _DomainType.unknown
          : _classifyDomain(zonedTokens);

      int? queryHash;
      if (source == ScanSource.straightened && straightenedImage != null) {
        final artZone = PerspectiveWarper.extractArtZone(straightenedImage);
        queryHash = ImageHashMatcher.instance.hashFromImage(artZone);
      } else {
        queryHash = ImageHashMatcher.instance.hashFromBytes(bytes);
      }

      String? detectedFaction;
      if (source == ScanSource.straightened && straightenedImage != null) {
        detectedFaction = _detectFaction(straightenedImage);
      }

      String? detectedExpansion;
      for (final token in zonedTokens) {
        if (token.zone != CardZone.id && token.zone != CardZone.name) {
          continue;
        }
        final m = _expansionPrefixRe.firstMatch(token.text.toUpperCase());
        if (m != null) {
          detectedExpansion = _expansionPrefixToLabel[m.group(1)!];
          break;
        }
      }

      double baseWT;
      double baseWV;
      if (ocrEmpty) {
        baseWT = 0.0;
        baseWV = 1.0;
      } else {
        final weights = _adaptiveWeights(
          tokenCount: zonedTokens.length,
          hasVisual: queryHash != null,
          source: source,
        );
        baseWT = weights.$1;
        baseWV = weights.$2;
      }

      // ── DEBUG: Phase B — Signals ──────────────────────────────────────
      debugPrint('║ [Scanner] PHASE B — SIGNALS');
      debugPrint('║ Domain: ${domain.name} | W_text=$baseWT W_visual=$baseWV');
      debugPrint('║ Hash: ${queryHash != null ? "OK" : "NULL"} | '
          'Faction: $detectedFaction | Expansion: $detectedExpansion');

      // ── Phase C: Candidate scoring ─────────────────────────────────────

      final searchGen = domain != _DomainType.library;
      final searchLib = domain != _DomainType.general;
      final scored = <_ScoredFusionCandidate>[];

      if (searchGen) {
        for (final e in _generalEntries!) {
          final r = _scoreCandidate(
            e, zonedTokens, queryHash, domain,
            baseWT, baseWV, detectedFaction, detectedExpansion,
          );
          if (r != null) { scored.add(r); }
        }
      }
      if (searchLib) {
        for (final e in _libraryEntries!) {
          final r = _scoreCandidate(
            e, zonedTokens, queryHash, domain,
            baseWT, baseWV, detectedFaction, detectedExpansion,
          );
          if (r != null) { scored.add(r); }
        }
      }

      scored.sort((a, b) => b.finalScore.compareTo(a.finalScore));

      // ── DEBUG: Phase D — Results ──────────────────────────────────────
      debugPrint('║ [Scanner] PHASE D — TOP 5 of ${scored.length}');
      for (var i = 0; i < math.min(5, scored.length); i++) {
        final s = scored[i];
        final tag = s.entry.recordType == RecordType.general ? 'GEN' : 'LIB';
        debugPrint('║   #$i [$tag] ${s.entry.cardId} "${s.entry.nameCn}" '
            'sT=${s.sText.toStringAsFixed(3)} sV=${s.sVisual.toStringAsFixed(3)} '
            'dg=${s.domainGate.toStringAsFixed(2)} boost=${s.boost.toStringAsFixed(2)} '
            '→ FINAL=${s.finalScore.toStringAsFixed(3)}');
      }
      debugPrint('╚═══════════════════════════════════════════════════');

      if (scored.isEmpty) {
        sw.stop();
        return ScannerResult(
          debugMessage: '[Scanner] No candidates in ${sw.elapsedMilliseconds}ms.',
        );
      }

      final top = scored.first;
      final gap = scored.length >= 2
          ? top.finalScore - scored[1].finalScore
          : top.finalScore;
      final fast = top.finalScore >= 0.75 && gap >= 0.20;

      if (top.finalScore > 0.85) {
        HapticFeedback.mediumImpact();
      }

      final candidates = (fast ? [top] : scored.take(5))
          .map((s) => MatchCandidate(
                cardId: s.entry.cardId,
                recordType: s.entry.recordType,
                nameCn: s.entry.nameCn,
                nameEn: s.entry.nameEn,
                imagePath: s.entry.imagePath,
                confidence: s.finalScore,
              ))
          .toList();

      sw.stop();
      return ScannerResult(
        candidates: candidates,
        fastPath: fast,
        debugMessage: '[Scanner] ${candidates.length} match(es) '
            'in ${sw.elapsedMilliseconds}ms.',
      );
    } catch (e, stack) {
      debugPrint('[Scanner] Error: $e\n$stack');
      return ScannerResult(debugMessage: '[Scanner] Error: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ZONED TOKEN EXTRACTION
  // ═════════════════════════════════════════════════════════════════════════

  List<ZonedToken> _extractZonedTokens(RecognizedText recognised) {
    double minY = double.infinity, maxY = 0, minX = double.infinity, maxX = 0;
    for (final block in recognised.blocks) {
      for (final pt in block.cornerPoints) {
        if (pt.x < minX) { minX = pt.x.toDouble(); }
        if (pt.x > maxX) { maxX = pt.x.toDouble(); }
        if (pt.y < minY) { minY = pt.y.toDouble(); }
        if (pt.y > maxY) { maxY = pt.y.toDouble(); }
      }
    }
    final cardH = maxY - minY;
    final cardW = maxX - minX;
    final tokens = <ZonedToken>[];
    final splitRe = RegExp(r'[\s·•\-—\u3000\uff0c\u3001\uff0e]+');
    final cleanRe = RegExp(r'[^\u4e00-\u9fff\u3400-\u4dbfa-zA-Z0-9]');

    for (final block in recognised.blocks) {
      for (final line in block.lines) {
        final raw = line.text.trim();
        if (raw.isEmpty) { continue; }
        final zone = _assignZone(line, minX, minY, cardW, cardH);
        final norm = TextNormaliser.normalise(raw);
        for (final part in norm.split(splitRe)) {
          final c = part.replaceAll(cleanRe, '');
          if (c.length >= 2) { tokens.add(ZonedToken(text: c, zone: zone)); }
        }
        final full = norm.replaceAll(cleanRe, '');
        if (full.length >= 4) { tokens.add(ZonedToken(text: full, zone: zone)); }
      }
    }
    return tokens;
  }

  CardZone _assignZone(TextLine line, double cL, double cT, double cW, double cH) {
    if (cH <= 0 || cW <= 0) { return CardZone.unknown; }
    final pts = line.cornerPoints;
    if (pts.isEmpty) { return CardZone.unknown; }
    final cx = pts.map((p) => p.x).reduce((a, b) => a + b) / pts.length;
    final cy = pts.map((p) => p.y).reduce((a, b) => a + b) / pts.length;
    final rY = (cy - cT) / cH;
    final rX = (cx - cL) / cW;
    if (rY < 0.25 && rX < 0.15) { return CardZone.id; }
    if (rY > 0.80 && rX > 0.60) { return CardZone.id; }
    if (rY < 0.25) { return CardZone.name; }
    if (rY > 0.85) { return CardZone.type; }
    return CardZone.body;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // DOMAIN CLASSIFIER (CAUSE 2 FIX)
  // ═════════════════════════════════════════════════════════════════════════

  _DomainType _classifyDomain(List<ZonedToken> tokens) {
    double gs = 0.0, ls = 0.0;

    for (final token in tokens) {
      final t = token.text;
      final upper = t.toUpperCase();

      if ((token.zone == CardZone.id || token.zone == CardZone.name) &&
          _suitRankRe.hasMatch(t)) {
        ls += 0.35;
        continue;
      }

      if (token.zone == CardZone.name &&
          (t.contains('【') || t.contains('】'))) {
        ls += 0.15;
      }

      if (_expansionPrefixRe.hasMatch(upper)) {
        gs += 0.30;
        continue;
      }

      for (final kw in _libraryKeywords) {
        if (t.contains(kw)) {
          ls += (token.zone == CardZone.type) ? 0.25 : 0.12;
          break;
        }
      }

      // CAUSE 2 FIX: Skill type keywords (锁定技/限定技/觉醒技/主公技/
      // 使命技/转换技) appear on EVERY general card, NEVER on library cards.
      // A single detection is near-definitive. Weight at +0.40.
      // Other general keywords (体力上限/体力值) are weaker at +0.15.
      for (final kw in _generalKeywords) {
        if (t.contains(kw)) {
          gs += _skillTypeKeywords.contains(kw) ? 0.40 : 0.15;
          break;
        }
      }
    }

    debugPrint('[Scanner] Domain scores: general=$gs library=$ls');

    if (gs > ls + 0.10) { return _DomainType.general; }
    if (ls > gs + 0.10) { return _DomainType.library; }
    return _DomainType.unknown;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // FACTION DETECTION
  // ═════════════════════════════════════════════════════════════════════════

  String? _detectFaction(img.Image straightened) {
    final w = straightened.width, h = straightened.height;
    final pL = (w * 0.30).round(), pT = (h * 0.45).round();
    final pW = math.max(4, (w * 0.10).round());
    final pH = math.max(4, (h * 0.10).round());
    int pR = 0, pG = 0, pB = 0, pN = 0;
    for (var y = pT; y < pT + pH && y < h; y++) {
      for (var x = pL; x < pL + pW && x < w; x++) {
        final px = straightened.getPixel(x, y);
        pR += px.r.toInt(); pG += px.g.toInt(); pB += px.b.toInt(); pN++;
      }
    }
    const rR = 210.0, rG = 190.0, rB = 160.0;
    double cR = 1.0, cG = 1.0, cB = 1.0;
    if (pN > 0) {
      final sR = pR / pN, sG = pG / pN, sB = pB / pN;
      if (sR > 80 && sR < 250 && sG > 60 && sG < 250 && sB > 40 && sB < 250) {
        cR = rR / sR; cG = rG / sG; cB = rB / sB;
      }
    }
    final sW = math.max(4, (w * 0.05).round());
    final sH = math.max(4, (h * 0.05).round());
    int tR = 0, tG = 0, tB = 0, cnt = 0;
    for (var y = 0; y < sH && y < h; y++) {
      for (var x = 0; x < sW && x < w; x++) {
        final px = straightened.getPixel(x, y);
        tR += px.r.toInt(); tG += px.g.toInt(); tB += px.b.toInt(); cnt++;
      }
    }
    if (cnt == 0) { return null; }
    final aR = (tR / cnt) * cR, aG = (tG / cnt) * cG, aB = (tB / cnt) * cB;
    if (aB > 120 && aR < 100 && aB > aG) { return 'Wei'; }
    if (aR > 150 && aB < 100 && aR > aG) { return 'Shu'; }
    if (aG > 120 && aR < 100 && aB < 100) { return 'Wu'; }
    if (aR > 180 && aG > 150 && aB < 100) { return 'God'; }
    final maxC = math.max(aR, math.max(aG, aB));
    final minC = math.min(aR, math.min(aG, aB));
    if (maxC - minC < 30 && minC > 120) { return 'Qun'; }
    return null;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ADAPTIVE WEIGHTS
  // ═════════════════════════════════════════════════════════════════════════

  (double, double) _adaptiveWeights({
    required int tokenCount,
    required bool hasVisual,
    required ScanSource source,
  }) {
    if (!hasVisual) { return (1.0, 0.0); }
    if (source == ScanSource.straightened) { return (0.50, 0.50); }
    if (source == ScanSource.userCrop) { return (0.55, 0.45); }
    if (tokenCount < 3) { return (0.40, 0.60); }
    return (0.70, 0.30);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CANDIDATE SCORING
  // ═════════════════════════════════════════════════════════════════════════

  _ScoredFusionCandidate? _scoreCandidate(
    _CardEntry entry,
    List<ZonedToken> tokens,
    int? queryHash,
    _DomainType domain,
    double baseWT,
    double baseWV,
    String? detectedFaction,
    String? detectedExpansion,
  ) {
    double best = 0.0;
    for (final token in tokens) {
      final zw = _zoneWeights[token.zone] ?? 1.0;

      // CAUSE 1 FIX: Use length-aware name matching
      final nq = _nameMatchScore(token.text, entry.normName, entry.recordType);
      if (nq > 0) {
        best = math.max(best, zw * nq);
      }

      final idClean = token.text
          .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
          .toUpperCase();
      if (idClean.length >= 4 &&
          entry.normId.isNotEmpty &&
          (idClean == entry.normId ||
              (entry.normId.contains(idClean) &&
                  idClean.length >= entry.normId.length - 2))) {
        best = math.max(best, _zoneWeights[CardZone.id]!);
      }

      if (entry.recordType == RecordType.general) {
        for (final sk in entry.skillNames) {
          if (token.text == sk || token.text.contains(sk)) {
            best = math.max(best, _zoneWeights[CardZone.body]! * 0.3);
            break;
          }
        }
      }
    }
    final sText = (best / _maxZoneWeight).clamp(0.0, 1.0);

    double sVisual = 0.5;
    if (queryHash != null) {
      final rh = ImageHashMatcher.instance.getCachedHash(entry.imagePath);
      if (rh != null) {
        sVisual = ImageHashMatcher.instance.similarity(queryHash, rh);
      }
    }

    double wT = baseWT;
    double wV = baseWV;
    if (sText < 0.20 && sVisual > 0.80 && baseWV < 0.80) {
      wT = 0.15;
      wV = 0.85;
    }

    final eType = entry.recordType == RecordType.general
        ? _DomainType.general
        : _DomainType.library;
    final double dg;
    if (domain == eType) {
      dg = 1.0;
    } else if (domain == _DomainType.unknown) {
      dg = 0.85;
    } else {
      dg = 0.3;
    }

    double boost = 0.0;
    if (detectedFaction != null &&
        entry.recordType == RecordType.general &&
        entry.faction == detectedFaction) {
      boost += 0.05;
    }
    if (detectedExpansion != null &&
        entry.recordType == RecordType.general &&
        entry.expansionLabel == detectedExpansion) {
      boost += 0.03;
    }

    final rawScore = wT * sText + wV * sVisual;
    final finalScore = rawScore * dg + boost;

    if (finalScore < 0.25) { return null; }

    return _ScoredFusionCandidate(
      entry: entry,
      sText: sText,
      sVisual: sVisual,
      domainGate: dg,
      boost: boost,
      finalScore: finalScore,
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // NAME MATCH SCORING (CAUSE 1 FIX)
  // ═════════════════════════════════════════════════════════════════════════

  /// CAUSE 1 FIX: Prevents long skill-description tokens from matching
  /// short library card names via substring containment.
  ///
  /// Example: OCR token "对处于濒死状态的角色使用一张桃" (20 chars) would
  /// match library card "桃" (1 char) with score 1.0 via `q.contains(t)`.
  /// This caused Image 4's 蔡文姬 → 桃 misidentification.
  ///
  /// Fix: When the candidate is a library card with a short name (≤4 chars)
  /// and the OCR token is much longer (> candidate + 2 chars), discount
  /// the match by 90%. This eliminates false positives from skill text
  /// while preserving legitimate short-token matches.
  double _nameMatchScore(
    String ocrToken,
    String candidateName,
    RecordType candidateType,
  ) {
    final score = FuzzyMatcher.scannerFuzzyScore(ocrToken, candidateName);
    if (score <= 0) { return 0.0; }

    if (candidateType == RecordType.library && candidateName.length <= 4) {
      final lenDiff = ocrToken.length - candidateName.length;
      if (lenDiff > 2) {
        return score * 0.1;
      }
    }

    return score;
  }

  String _normaliseId(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
}