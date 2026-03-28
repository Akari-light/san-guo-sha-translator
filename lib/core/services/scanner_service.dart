// lib/core/services/scanner_service.dart
//
// Multimodal Fusion Engine — v3.0 (spec: scanner_spec_v3.md)
//
// Phase 2 additions over v2.0:
//
//   1. ScanSource.straightened — new source mode for perspective-warped scans.
//      Triggers 0.50/0.50 weight split (text and visual equally trustworthy
//      after card has been flattened and background removed).
//
//   2. Faction colour detection — _detectFaction() samples the top-left 5%
//      of a straightened image to detect the kingdom emblem colour. Feeds
//      into the boost term: +0.05 for matching faction candidates.
//
//   3. Art-zone pHash — when source is .straightened, the query hash is
//      computed from the art zone (15–65% height) of the warped image,
//      not the full frame. Dramatically improves Hamming distance accuracy
//      because the reference images in assets/ are art-only.
//
// Architecture: core/services only. No feature/*/presentation imports.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    show RecognizedText, TextBlock, TextLine;
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

/// Source mode affects adaptive weight selection.
enum ScanSource {
  camera,       // Phase 1 — raw frame from camera
  gallery,      // Phase 1 — image picked from gallery
  userCrop,     // Phase 1 — rectangular crop (legacy, kept for compat)
  straightened, // Phase 2 — perspective-warped card
}

// ═══════════════════════════════════════════════════════════════════════════════
// ZONED TOKEN (Pillar 4)
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
  CardZone.name:    3.0,
  CardZone.id:      2.5,
  CardZone.type:    2.0,
  CardZone.body:    0.5,
  CardZone.unknown: 1.0,
};
const _maxZoneWeight = 3.0;

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
    '锦囊', '武器', '防具', '坐骑', '宝物',
    '攻击范围', '装备区', '重铸',
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

  /// Main entry point — runs the Multimodal Fusion pipeline.
  ///
  /// [bytes]: raw JPEG of the full frame, user crop, or straightened card.
  /// [recognisedText]: MLKit RecognizedText.
  /// [source]: affects adaptive weight selection and art-zone extraction.
  /// [straightenedImage]: when [source] is .straightened, pass the decoded
  ///   warped img.Image directly to avoid re-decoding. Used for art-zone
  ///   pHash and faction detection.
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
        faction:    g.faction,
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
      // ── Phase A: Input conditioning ────────────────────────────────────

      final zonedTokens = recognisedText != null
          ? _extractZonedTokens(recognisedText)
          : <ZonedToken>[];

      debugPrint('[Scanner] ${zonedTokens.length} zoned tokens');

      if (zonedTokens.isEmpty) {
        return ScannerResult(
          debugMessage: '[Scanner] No text tokens from OCR.',
        );
      }

      // ── Phase B: Signal extraction ─────────────────────────────────────

      final domain = _classifyDomain(zonedTokens);
      debugPrint('[Scanner] Domain: ${domain.name}');

      // Visual hash: art-zone for straightened, full frame otherwise
      int? queryHash;
      if (source == ScanSource.straightened && straightenedImage != null) {
        final artZone = PerspectiveWarper.extractArtZone(straightenedImage);
        queryHash = ImageHashMatcher.instance.hashFromImage(artZone);
        debugPrint('[Scanner] Art-zone pHash computed');
      } else {
        queryHash = ImageHashMatcher.instance.hashFromBytes(bytes);
      }

      // Faction colour detection (straightened only)
      String? detectedFaction;
      if (source == ScanSource.straightened && straightenedImage != null) {
        detectedFaction = _detectFaction(straightenedImage);
        if (detectedFaction != null) {
          debugPrint('[Scanner] Detected faction: $detectedFaction');
        }
      }

      final (wText, wVisual) = _adaptiveWeights(
        tokenCount: zonedTokens.length,
        hasVisual:  queryHash != null,
        source:     source,
      );
      debugPrint('[Scanner] Weights: text=$wText visual=$wVisual');

      // ── Phase C: Candidate scoring ─────────────────────────────────────

      final searchGenerals = domain != _DomainType.library;
      final searchLibrary  = domain != _DomainType.general;
      final scored = <_ScoredFusionCandidate>[];

      if (searchGenerals) {
        for (final entry in _generalEntries!) {
          final r = _scoreCandidate(
            entry, zonedTokens, queryHash, domain,
            wText, wVisual, detectedFaction,
          );
          if (r != null) scored.add(r);
        }
      }
      if (searchLibrary) {
        for (final entry in _libraryEntries!) {
          final r = _scoreCandidate(
            entry, zonedTokens, queryHash, domain,
            wText, wVisual, detectedFaction,
          );
          if (r != null) scored.add(r);
        }
      }

      scored.sort((a, b) => b.finalScore.compareTo(a.finalScore));

      if (scored.isEmpty) {
        sw.stop();
        return ScannerResult(
          debugMessage: '[Scanner] No candidates above threshold '
              'in ${sw.elapsedMilliseconds}ms.',
        );
      }

      // ── Phase D: Output ────────────────────────────────────────────────

      final top = scored.first;
      final gap = scored.length >= 2
          ? top.finalScore - scored[1].finalScore
          : top.finalScore;
      final isFastPath = top.finalScore >= 0.75 && gap >= 0.20;

      final candidates = (isFastPath ? [top] : scored.take(5))
          .map((s) => MatchCandidate(
                cardId:     s.entry.cardId,
                recordType: s.entry.recordType,
                nameCn:     s.entry.nameCn,
                nameEn:     s.entry.nameEn,
                imagePath:  s.entry.imagePath,
                confidence: s.finalScore,
              ))
          .toList();

      sw.stop();
      debugPrint('[Scanner] ${candidates.length} result(s) '
          '${isFastPath ? "(fast-path) " : ""}'
          'top=${top.entry.cardId}(${top.finalScore.toStringAsFixed(3)}) '
          'sT=${top.sText.toStringAsFixed(2)} sV=${top.sVisual.toStringAsFixed(2)} '
          'dom=${top.domainGate.toStringAsFixed(1)} boost=${top.boost.toStringAsFixed(2)} '
          'in ${sw.elapsedMilliseconds}ms');

      return ScannerResult(
        candidates: candidates,
        fastPath:   isFastPath,
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
    double minY = double.infinity, maxY = 0;
    double minX = double.infinity, maxX = 0;
    for (final block in recognised.blocks) {
      for (final pt in block.cornerPoints) {
        if (pt.x < minX) minX = pt.x.toDouble();
        if (pt.x > maxX) maxX = pt.x.toDouble();
        if (pt.y < minY) minY = pt.y.toDouble();
        if (pt.y > maxY) maxY = pt.y.toDouble();
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
        if (raw.isEmpty) continue;
        final zone = _assignZone(line, minX, minY, cardW, cardH);
        final normalised = TextNormaliser.normalise(raw);

        for (final part in normalised.split(splitRe)) {
          final clean = part.replaceAll(cleanRe, '');
          if (clean.length >= 2) {
            tokens.add(ZonedToken(text: clean, zone: zone));
          }
        }
        final fullClean = normalised.replaceAll(cleanRe, '');
        if (fullClean.length >= 4) {
          tokens.add(ZonedToken(text: fullClean, zone: zone));
        }
      }
    }
    return tokens;
  }

  CardZone _assignZone(
    TextLine line,
    double cardLeft, double cardTop,
    double cardWidth, double cardHeight,
  ) {
    if (cardHeight <= 0 || cardWidth <= 0) return CardZone.unknown;
    final pts = line.cornerPoints;
    if (pts.isEmpty) return CardZone.unknown;

    final cx = pts.map((p) => p.x).reduce((a, b) => a + b) / pts.length;
    final cy = pts.map((p) => p.y).reduce((a, b) => a + b) / pts.length;
    final relY = (cy - cardTop) / cardHeight;
    final relX = (cx - cardLeft) / cardWidth;

    if (relY < 0.25 && relX < 0.15) return CardZone.id;
    if (relY > 0.80 && relX > 0.60) return CardZone.id;
    if (relY < 0.25) return CardZone.name;
    if (relY > 0.85) return CardZone.type;
    return CardZone.body;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // DOMAIN CLASSIFIER
  // ═════════════════════════════════════════════════════════════════════════

  _DomainType _classifyDomain(List<ZonedToken> tokens) {
    double gs = 0.0, ls = 0.0;
    for (final token in tokens) {
      final t = token.text;
      final upper = t.toUpperCase();

      if ((token.zone == CardZone.id || token.zone == CardZone.name) &&
          _suitRankRe.hasMatch(t)) {
        ls += 0.35; continue;
      }
      if (token.zone == CardZone.name && (t.contains('【') || t.contains('】'))) {
        ls += 0.15;
      }
      if (_expansionPrefixRe.hasMatch(upper)) { gs += 0.30; continue; }

      for (final kw in _libraryKeywords) {
        if (t.contains(kw)) {
          ls += (token.zone == CardZone.type) ? 0.25 : 0.12;
          break;
        }
      }
      for (final kw in _generalKeywords) {
        if (t.contains(kw)) { gs += 0.15; break; }
      }
    }
    if (gs > ls + 0.10) return _DomainType.general;
    if (ls > gs + 0.10) return _DomainType.library;
    return _DomainType.unknown;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // FACTION COLOUR DETECTION (Phase 2 — Pillar 7)
  // ═════════════════════════════════════════════════════════════════════════

  /// Samples the top-left 5% region of a straightened card to detect the
  /// kingdom faction emblem colour.
  ///
  /// Returns "Wei"/"Shu"/"Wu"/"Qun"/"God" or null if ambiguous.
  String? _detectFaction(img.Image straightened) {
    final w = straightened.width;
    final h = straightened.height;
    final sW = math.max(4, (w * 0.05).round());
    final sH = math.max(4, (h * 0.05).round());

    int tR = 0, tG = 0, tB = 0, count = 0;
    for (var y = 0; y < sH && y < h; y++) {
      for (var x = 0; x < sW && x < w; x++) {
        final px = straightened.getPixel(x, y);
        tR += px.r.toInt();
        tG += px.g.toInt();
        tB += px.b.toInt();
        count++;
      }
    }
    if (count == 0) return null;

    final aR = tR / count, aG = tG / count, aB = tB / count;

    if (aB > 120 && aR < 100 && aB > aG) return 'Wei';
    if (aR > 150 && aB < 100 && aR > aG) return 'Shu';
    if (aG > 120 && aR < 100 && aB < 100) return 'Wu';
    if (aR > 180 && aG > 150 && aB < 100) return 'God';

    final maxC = math.max(aR, math.max(aG, aB));
    final minC = math.min(aR, math.min(aG, aB));
    if (maxC - minC < 30 && minC > 120) return 'Qun';

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
    if (!hasVisual) return (1.0, 0.0);
    if (source == ScanSource.straightened) return (0.50, 0.50);
    if (source == ScanSource.userCrop) return (0.55, 0.45);
    if (tokenCount < 3) return (0.40, 0.60);
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
    double wText,
    double wVisual,
    String? detectedFaction,
  ) {
    double bestTextScore = 0.0;

    for (final token in tokens) {
      final zw = _zoneWeights[token.zone] ?? 1.0;

      final nq = FuzzyMatcher.scannerFuzzyScore(token.text, entry.normName);
      if (nq > 0) bestTextScore = math.max(bestTextScore, zw * nq);

      final idClean = token.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
      if (idClean.length >= 4 && entry.normId.isNotEmpty) {
        if (idClean == entry.normId ||
            (entry.normId.contains(idClean) && idClean.length >= entry.normId.length - 2)) {
          bestTextScore = math.max(bestTextScore, _zoneWeights[CardZone.id]!);
        }
      }

      if (entry.recordType == RecordType.general) {
        for (final sk in entry.skillNames) {
          if (token.text == sk || token.text.contains(sk)) {
            bestTextScore = math.max(bestTextScore, _zoneWeights[CardZone.body]! * 0.3);
            break;
          }
        }
      }
    }

    final sText = (bestTextScore / _maxZoneWeight).clamp(0.0, 1.0);

    double sVisual = 0.5;
    if (queryHash != null) {
      final rh = ImageHashMatcher.instance.getCachedHash(entry.imagePath);
      if (rh != null) sVisual = ImageHashMatcher.instance.similarity(queryHash, rh);
    }

    final entryType = entry.recordType == RecordType.general
        ? _DomainType.general : _DomainType.library;
    final double dg;
    if (domain == entryType) { dg = 1.0; }
    else if (domain == _DomainType.unknown) { dg = 0.8; }
    else { dg = 0.0; }
    if (dg == 0.0) return null;

    double boost = 0.0;
    if (detectedFaction != null &&
        entry.recordType == RecordType.general &&
        entry.faction == detectedFaction) {
      boost += 0.05;
    }

    final fs = (wText * sText + wVisual * sVisual) * dg + boost;
    if (fs < 0.35) return null;

    return _ScoredFusionCandidate(
      entry: entry, sText: sText, sVisual: sVisual,
      domainGate: dg, boost: boost, finalScore: fs,
    );
  }

  String _normaliseId(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
}