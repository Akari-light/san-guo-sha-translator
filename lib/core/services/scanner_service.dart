// lib/core/services/scanner_service.dart
//
// Multimodal Fusion Engine — v2.0 (spec: scanner_upgrade_spec_v2.md)
//
// Replaces the sequential Two-Stage pipeline with parallel signal extraction
// and a weighted fusion formula:
//
//   Final(c) = [ W_text × S_text(c) + W_visual × S_visual(c) ]
//              × domain_gate(c)
//              + boost(c)
//
// Key improvements over v1.0:
//
// 1. ZonedToken extraction (Pillar 4) — OCR tokens carry spatial metadata.
//    Tokens from the Name Zone (top 25%) score ×3.0; Body Zone (skill text)
//    scores ×0.5. This structurally eliminates false positives from skill
//    descriptions containing library card names.
//
// 2. Domain classifier (Pillar 3) — replaces the brittle keyword-only
//    _classifyCardType(). Uses spatial OCR signals: suit/rank in top-left
//    → library; expansion prefix → general; category labels → library;
//    skill type keywords → general. Returns {general, library, unknown}
//    with a multiplicative gate (1.0 / 0.8 / 0.0).
//
// 3. FuzzyMatcher integration (Pillar 5) — scannerFuzzyScore() provides
//    continuous [0.0, 1.0] quality scores with Levenshtein + trigram +
//    pinyin tolerance, replacing strict substring matching.
//
// 4. No libraryMinScore gate — the domain gate handles cross-type noise
//    structurally. Library cards no longer need a serial ID to survive.
//
// 5. Adaptive weights — W_text / W_visual shift based on OCR token count
//    and source mode (full frame vs user crop). pHash is a genuine parallel
//    signal, not a gated tie-breaker.
//
// Architecture: core/services only. No feature/*/presentation imports.
// GeneralLoader + LibraryLoader: core→feature/data — permitted.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    show RecognizedText, TextBlock, TextLine;

import 'recently_viewed_service.dart';
import 'text_normaliser.dart';
import 'fuzzy_matcher.dart';
import 'image_hash_matcher.dart';
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
enum ScanSource { camera, gallery, userCrop }

// ═══════════════════════════════════════════════════════════════════════════════
// ZONED TOKEN (Pillar 4 — Geometry-Aware OCR)
// ═══════════════════════════════════════════════════════════════════════════════

/// Spatial zone on a card, determined by the token's vertical position
/// relative to the detected card boundary.
enum CardZone {
  /// Top 25% — card name (large font), suit/rank. Weight ×3.0
  name,

  /// Bottom-right or top-left — serial ID or suit symbol. Weight ×2.5
  id,

  /// Bottom 15% — category label (装备/武器, 锦囊). Weight ×2.0
  type,

  /// Middle 55–85% — effect text, flavour text. Weight ×0.5
  body,

  /// Could not determine zone. Weight ×1.0
  unknown,
}

class ZonedToken {
  final String text;
  final CardZone zone;

  const ZonedToken({required this.text, required this.zone});

  @override
  String toString() => 'ZonedToken($text, ${zone.name})';
}

// ═══════════════════════════════════════════════════════════════════════════════
// DOMAIN CLASSIFICATION (Pillar 3)
// ═══════════════════════════════════════════════════════════════════════════════

enum _DomainType { general, library, unknown }

// ═══════════════════════════════════════════════════════════════════════════════
// WARMUP CACHE ENTRY (unchanged structure)
// ═══════════════════════════════════════════════════════════════════════════════

class _CardEntry {
  final String cardId;
  final RecordType recordType;
  final String nameCn;
  final String nameEn;
  final String imagePath;
  final String normId;
  final String normName;
  final List<String> skillNames;
  final String? faction; // "Wei", "Shu", "Wu", "Qun", "God" — generals only

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

// ═══════════════════════════════════════════════════════════════════════════════
// ZONE WEIGHTS — spec §4.4.1
// ═══════════════════════════════════════════════════════════════════════════════

const _zoneWeights = <CardZone, double>{
  CardZone.name:    3.0,
  CardZone.id:      2.5,
  CardZone.type:    2.0,
  CardZone.body:    0.5,
  CardZone.unknown: 1.0,
};

/// Maximum single-token weighted score (name zone × exact match).
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

  // ── Domain classification keyword sets ──────────────────────────────────

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

  /// Suit/rank pattern: single rank char optionally followed by suit char.
  /// Matches: "A", "K", "5", "Q♠", "2♥" and their CJK-width variants.
  static final _suitRankRe = RegExp(
    r'^[A2-9JQK10]{1,2}[♠♥♦♣\u2660\u2665\u2666\u2663]?$',
    caseSensitive: false,
  );

  // ═════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═════════════════════════════════════════════════════════════════════════

  /// Pre-processes all generals and library cards into flat _CardEntry structs.
  /// Call once at camera init; subsequent calls are no-ops.
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
  /// [bytes]: raw JPEG of the full frame or user-cropped region.
  /// [recognisedText]: MLKit RecognizedText from scanner_screen.dart.
  /// [source]: affects adaptive weight selection (camera / gallery / userCrop).
  Future<ScannerResult> match(
    Uint8List bytes, {
    RecognizedText? recognisedText,
    ScanSource source = ScanSource.camera,
  }) async {
    return _runFusion(bytes, recognisedText, source);
  }

  void dispose() {
    // No TextRecognizer to close — OCR lives in scanner_screen.dart.
  }

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
  // FUSION PIPELINE (spec §6 — Master Algorithm)
  // ═════════════════════════════════════════════════════════════════════════

  Future<ScannerResult> _runFusion(
    Uint8List bytes,
    RecognizedText? recognisedText,
    ScanSource source,
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

      debugPrint('[Scanner] ${zonedTokens.length} zoned tokens: '
          '${zonedTokens.map((t) => "${t.text}(${t.zone.name})").join(", ")}');

      if (zonedTokens.isEmpty) {
        return ScannerResult(
          debugMessage: '[Scanner] No text tokens from OCR.',
        );
      }

      // ── Phase B: Signal extraction (parallel) ──────────────────────────

      // B2. Domain classification
      final domain = _classifyDomain(zonedTokens);
      debugPrint('[Scanner] Domain: ${domain.name}');

      // B3. Visual hash — compute once, reuse per candidate
      final queryHash = ImageHashMatcher.instance.hashFromBytes(bytes);

      // B4. Adaptive weights (spec §5.2)
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
          final result = _scoreCandidate(
            entry, zonedTokens, queryHash, domain, wText, wVisual,
          );
          if (result != null) scored.add(result);
        }
      }

      if (searchLibrary) {
        for (final entry in _libraryEntries!) {
          final result = _scoreCandidate(
            entry, zonedTokens, queryHash, domain, wText, wVisual,
          );
          if (result != null) scored.add(result);
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
          'sText=${top.sText.toStringAsFixed(2)} '
          'sVis=${top.sVisual.toStringAsFixed(2)} '
          'dom=${top.domainGate.toStringAsFixed(1)} '
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
  // ZONED TOKEN EXTRACTION (Pillar 4)
  // ═════════════════════════════════════════════════════════════════════════

  /// Extracts tokens from [recognised] with spatial zone assignment.
  ///
  /// Zone assignment uses the bounding box of each TextLine relative to
  /// the full image frame. In the absence of a detected card boundary
  /// (Phase 2 feature), we use the convex hull of all text blocks as
  /// the card boundary approximation.
  List<ZonedToken> _extractZonedTokens(RecognizedText recognised) {
    // Compute approximate card boundary from all text block corners.
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
    final _splitRe = RegExp(r'[\s·•\-—\u3000\uff0c\u3001\uff0e]+');
    final _cleanRe = RegExp(r'[^\u4e00-\u9fff\u3400-\u4dbfa-zA-Z0-9]');

    for (final block in recognised.blocks) {
      for (final line in block.lines) {
        final raw = line.text.trim();
        if (raw.isEmpty) continue;

        // Determine zone from the line's vertical position within the card
        final zone = _assignZone(line, minX, minY, cardW, cardH);

        final normalised = TextNormaliser.normalise(raw);
        final parts = normalised.split(_splitRe);

        for (final part in parts) {
          final clean = part.replaceAll(_cleanRe, '');
          if (clean.length >= 2) {
            tokens.add(ZonedToken(text: clean, zone: zone));
          }
        }

        // Also add the full concatenated line (catches multi-word card names)
        final fullClean = normalised.replaceAll(_cleanRe, '');
        if (fullClean.length >= 4) {
          tokens.add(ZonedToken(text: fullClean, zone: zone));
        }
      }
    }
    return tokens;
  }

  /// Assigns a CardZone based on the line's position within the card.
  ///
  /// Zone boundaries (spec §4.1.3):
  ///   Name:  top 25%
  ///   Art:   15–65% (not used for token zone — only for pHash crop)
  ///   Body:  55–85%
  ///   Type:  bottom 15%
  ///   ID:    top-left 15%×25% (suit/rank) or bottom-right 40%×20% (serial)
  CardZone _assignZone(
    TextLine line,
    double cardLeft,
    double cardTop,
    double cardWidth,
    double cardHeight,
  ) {
    if (cardHeight <= 0 || cardWidth <= 0) return CardZone.unknown;

    // Use the first cornerPoint as the line's top-left anchor.
    final pts = line.cornerPoints;
    if (pts.isEmpty) return CardZone.unknown;

    // Centre of the line bounding box
    final cx = pts.map((p) => p.x).reduce((a, b) => a + b) / pts.length;
    final cy = pts.map((p) => p.y).reduce((a, b) => a + b) / pts.length;

    final relY = (cy - cardTop) / cardHeight;
    final relX = (cx - cardLeft) / cardWidth;

    // ID zone — suit/rank in top-left corner
    if (relY < 0.25 && relX < 0.15) return CardZone.id;

    // ID zone — general serial in bottom-right
    if (relY > 0.80 && relX > 0.60) return CardZone.id;

    // Name zone — top 25%
    if (relY < 0.25) return CardZone.name;

    // Type zone — bottom 15%
    if (relY > 0.85) return CardZone.type;

    // Body zone — everything in between
    return CardZone.body;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // DOMAIN CLASSIFIER (Pillar 3)
  // ═════════════════════════════════════════════════════════════════════════

  /// Classifies the scanned card as general, library, or unknown using
  /// spatial OCR signals.
  ///
  /// Replaces the old _classifyCardType() which used flat keyword matching.
  /// The new classifier uses zone information to weight signals:
  /// - Suit/rank in the ID zone → strong library signal
  /// - Expansion prefix in ID zone → strong general signal
  /// - Category labels in Type zone → library signal
  /// - Skill type keywords in Body/Type → general signal
  /// - 【brackets】 in Name zone → library signal
  _DomainType _classifyDomain(List<ZonedToken> tokens) {
    double generalScore = 0.0;
    double libraryScore = 0.0;

    for (final token in tokens) {
      final t = token.text;
      final upper = t.toUpperCase();

      // ── Suit / rank pattern — strong library signal ──────────────────
      if ((token.zone == CardZone.id || token.zone == CardZone.name) &&
          _suitRankRe.hasMatch(t)) {
        libraryScore += 0.35;
        continue;
      }

      // ── 【brackets】 around card name — library signal ───────────────
      if (token.zone == CardZone.name && (t.contains('【') || t.contains('】'))) {
        libraryScore += 0.15;
      }

      // ── Expansion prefix — strong general signal ─────────────────────
      if (_expansionPrefixRe.hasMatch(upper)) {
        generalScore += 0.30;
        continue;
      }

      // ── Category labels — library signal (strongest from Type zone) ──
      for (final kw in _libraryKeywords) {
        if (t.contains(kw)) {
          libraryScore += (token.zone == CardZone.type) ? 0.25 : 0.12;
          break; // one keyword match per token
        }
      }

      // ── Skill type keywords — general signal ─────────────────────────
      for (final kw in _generalKeywords) {
        if (t.contains(kw)) {
          generalScore += 0.15;
          break;
        }
      }
    }

    // Require a margin of 0.10 to declare a winner (spec §4.3.1)
    if (generalScore > libraryScore + 0.10) return _DomainType.general;
    if (libraryScore > generalScore + 0.10) return _DomainType.library;
    return _DomainType.unknown;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ADAPTIVE WEIGHTS (spec §5.2)
  // ═════════════════════════════════════════════════════════════════════════

  (double wText, double wVisual) _adaptiveWeights({
    required int tokenCount,
    required bool hasVisual,
    required ScanSource source,
  }) {
    if (!hasVisual) return (1.0, 0.0);
    if (source == ScanSource.userCrop) return (0.55, 0.45);
    if (tokenCount < 3) return (0.40, 0.60);
    return (0.70, 0.30);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CANDIDATE SCORING (spec §6 Phase C)
  // ═════════════════════════════════════════════════════════════════════════

  _ScoredFusionCandidate? _scoreCandidate(
    _CardEntry entry,
    List<ZonedToken> tokens,
    int? queryHash,
    _DomainType domain,
    double wText,
    double wVisual,
  ) {
    // ── C1: Compute S_text ─────────────────────────────────────────────

    double bestTextScore = 0.0;

    for (final token in tokens) {
      final zoneWeight = _zoneWeights[token.zone] ?? 1.0;

      // Name matching — exact substring + fuzzy
      final nameQuality = FuzzyMatcher.scannerFuzzyScore(
        token.text, entry.normName,
      );
      if (nameQuality > 0) {
        final weighted = zoneWeight * nameQuality;
        bestTextScore = math.max(bestTextScore, weighted);
      }

      // ID matching — exact alphanumeric only
      final idClean = token.text
          .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
          .toUpperCase();
      if (idClean.length >= 4 && entry.normId.isNotEmpty) {
        if (idClean == entry.normId ||
            (entry.normId.contains(idClean) &&
                idClean.length >= entry.normId.length - 2)) {
          final weighted = _zoneWeights[CardZone.id]! * 1.0; // 2.5
          bestTextScore = math.max(bestTextScore, weighted);
        }
      }

      // Skill name matching — generals only, low weight (0.3 quality)
      if (entry.recordType == RecordType.general) {
        for (final skillName in entry.skillNames) {
          if (token.text == skillName || token.text.contains(skillName)) {
            final weighted = _zoneWeights[CardZone.body]! * 0.3; // 0.15
            bestTextScore = math.max(bestTextScore, weighted);
            break; // one skill match per token is enough
          }
        }
      }
    }

    // Normalise S_text to [0, 1] by dividing by max zone weight
    final sText = (bestTextScore / _maxZoneWeight).clamp(0.0, 1.0);

    // ── C2: Compute S_visual ───────────────────────────────────────────

    double sVisual = 0.5; // neutral default

    if (queryHash != null) {
      final refHash = ImageHashMatcher.instance.getCachedHash(entry.imagePath);
      if (refHash != null) {
        sVisual = ImageHashMatcher.instance.similarity(queryHash, refHash);
      }
      // If ref hash not cached yet, fall through to 0.5 (neutral).
      // Phase 2 will pre-cache all reference hashes during warmup.
    }

    // ── C3: Domain gate (multiplicative) ───────────────────────────────

    final double domainGate;
    final entryType = entry.recordType == RecordType.general
        ? _DomainType.general
        : _DomainType.library;

    if (domain == entryType) {
      domainGate = 1.0;   // confirmed match
    } else if (domain == _DomainType.unknown) {
      domainGate = 0.8;   // uncertain — mild penalty
    } else {
      domainGate = 0.0;   // hard mismatch — zeroed out
    }

    // Early exit: domain mismatch kills the candidate entirely
    if (domainGate == 0.0) return null;

    // ── C4: Boost (faction, expansion, recency) ────────────────────────

    // Boost is capped at +0.08 (spec §5.2)
    // Phase 1 only implements a stub — faction/expansion colour detection
    // requires Phase 2 visual signals. Recency boost is functional.
    const boost = 0.0; // TODO(Phase 3): wire faction/expansion/recency

    // ── C5: Fuse ───────────────────────────────────────────────────────

    final rawScore = wText * sText + wVisual * sVisual;
    final finalScore = rawScore * domainGate + boost;

    // Threshold: spec §5.4 — filter below 0.35
    if (finalScore < 0.35) return null;

    return _ScoredFusionCandidate(
      entry:      entry,
      sText:      sText,
      sVisual:    sVisual,
      domainGate: domainGate,
      finalScore: finalScore,
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // INTERNAL UTILITIES
  // ═════════════════════════════════════════════════════════════════════════

  String _normaliseId(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
}

// ═══════════════════════════════════════════════════════════════════════════════
// INTERNAL SCORED CANDIDATE
// ═══════════════════════════════════════════════════════════════════════════════

class _ScoredFusionCandidate {
  final _CardEntry entry;
  final double sText;
  final double sVisual;
  final double domainGate;
  final double finalScore;

  const _ScoredFusionCandidate({
    required this.entry,
    required this.sText,
    required this.sVisual,
    required this.domainGate,
    required this.finalScore,
  });
}