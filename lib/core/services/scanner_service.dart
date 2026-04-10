// lib/core/services/scanner_service.dart
//
// Multimodal Fusion Engine — Phase 9 (ML Embeddings)
//
// Generals-only search.
//
// Library card scanning is deferred: library card names (杀, 闪, 桃, etc.)
// appear verbatim inside general skill text, so OCR cannot distinguish
// "this card is named 杀" from "this skill text mentions 杀". Until visual
// embedding is reliably active at scan time (i.e. warmup completes before
// the first scan), adding library cards to the candidate pool causes them
// to out-score the correct general on every scan that reads skill text.
//
// Phase 9: Replaced pHash with MobileNetV2 feature embeddings via TFLite.
// Pre-computed reference embeddings loaded from assets/data/general_embeddings.bin.
// On-device inference extracts query embedding from the FULL warped card image
// (~30ms). Raw cosine similarity (dot product) provides robust cross-domain
// matching.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    show RecognizedText, TextLine;
import 'package:image/image.dart' as img;

import 'recently_viewed_service.dart';
import 'text_normaliser.dart';
import 'fuzzy_matcher.dart';
import 'image_embedding_matcher.dart';
import '../../features/generals/data/repository/general_loader.dart';

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
  final double boost;
  final double finalScore;

  const _ScoredFusionCandidate({
    required this.entry,
    required this.sText,
    required this.sVisual,
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

/// ID token validator: must contain at least one letter AND one digit,
/// 4+ chars. Filters out "999" (HP dots) and "2020" (copyright year).
final _idTokenRe = RegExp(r'^(?=.*[A-Za-z])(?=.*[0-9])[A-Za-z0-9]{4,}$');

// ═══════════════════════════════════════════════════════════════════════════════
// SCANNER SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

class ScannerService {
  ScannerService._();
  static final ScannerService instance = ScannerService._();

  List<_CardEntry>? _allEntries;
  bool _warmingUp = false;

  // ═════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> warmup() async {
    if (_allEntries != null || _warmingUp) { return; }
    _warmingUp = true;
    try {
      final generals = await GeneralLoader().getGenerals();
      _allEntries = generals.map((g) => _CardEntry(
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
      )).toList();
      debugPrint('[Scanner] Warmup: ${_allEntries!.length} generals.');

      // Load ML model + pre-computed reference embeddings
      await ImageEmbeddingMatcher.instance.loadModel();
      await ImageEmbeddingMatcher.instance.loadReferenceEmbeddings();
      _embeddingsReady = ImageEmbeddingMatcher.instance.referenceCount > 0;
      debugPrint('[Scanner] ML embeddings ready: $_embeddingsReady '
          '(${ImageEmbeddingMatcher.instance.referenceCount} refs)');
    } finally {
      _warmingUp = false;
    }
  }

  bool _embeddingsReady = false;

  // ── Pause/resume stubs (kept for scanner_screen API compatibility) ──
  void pauseHashCache() {}
  void resumeHashCache() {}

  Future<ScannerResult> match(
    Uint8List bytes, {
    RecognizedText? recognisedText,
    ScanSource source = ScanSource.camera,
    img.Image? straightenedImage,
  }) async {
    return _runFusion(bytes, recognisedText, source, straightenedImage);
  }

  void dispose() {
    ImageEmbeddingMatcher.instance.dispose();
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
    pauseHashCache();
    final sw = Stopwatch()..start();
    if (_allEntries == null) { await warmup(); }

    try {
      // img.normalize() intentionally REMOVED — degraded OCR text clarity.

      final zonedTokens = recognisedText != null
          ? _extractZonedTokens(recognisedText)
          : <ZonedToken>[];
      final bool ocrEmpty = zonedTokens.isEmpty;

      debugPrint('╔═══════════════════════════════════════════════════');
      debugPrint('║ [Scanner] PHASE A — INPUT');
      debugPrint('║ Source: ${source.name} | Tokens: ${zonedTokens.length}');
      for (var i = 0; i < zonedTokens.length; i++) {
        debugPrint('║   [$i] "${zonedTokens[i].text}" → ${zonedTokens[i].zone.name}');
      }

      // ── Phase B: Signals ───────────────────────────────────────────────

      // Extract ML feature embedding from the FULL warped card image.
      // Reference embeddings were generated from full-size reference images,
      // so the query must also be full-size. Cropping to an art zone before
      // embedding causes a domain mismatch (query ≈ orthogonal to every
      // reference) which produces ~0.17 scores regardless of card shown.
      // MobileNetV2 inference takes ~30ms on mid-range phones.
      Float32List? queryEmbedding;
      if (_embeddingsReady) {
        if (source == ScanSource.straightened && straightenedImage != null) {
          queryEmbedding = ImageEmbeddingMatcher.instance
              .embeddingFromImage(straightenedImage);
        } else {
          queryEmbedding = ImageEmbeddingMatcher.instance
              .embeddingFromBytes(bytes);
        }
      }

      String? detectedFaction;
      if (source == ScanSource.straightened && straightenedImage != null) {
        detectedFaction = _detectFaction(straightenedImage);
      }

      final (baseWT, baseWV) = ocrEmpty
          ? (0.0, 1.0)
          : _adaptiveWeights(
              tokenCount: zonedTokens.length,
              hasVisual: queryEmbedding != null,
              source: source,
            );

      debugPrint('║ [Scanner] PHASE B — SIGNALS');
      debugPrint('║ W_text=${baseWT.toStringAsFixed(2)} '
          'W_visual=${baseWV.toStringAsFixed(2)}');
      debugPrint('║ Embedding: ${queryEmbedding != null ? "OK" : "NULL"} | '
          'Faction: $detectedFaction');

      // ── Phase C: Score candidates ──────────────────────────────────────

      final scored = <_ScoredFusionCandidate>[];
      for (final e in _allEntries!) {
        final r = _scoreCandidate(
          e, zonedTokens, queryEmbedding,
          baseWT, baseWV, detectedFaction,
        );
        if (r != null) { scored.add(r); }
      }
      scored.sort((a, b) => b.finalScore.compareTo(a.finalScore));

      debugPrint('║ [Scanner] PHASE D — TOP 5 of ${scored.length}');
      for (var i = 0; i < math.min(5, scored.length); i++) {
        final s = scored[i];
        debugPrint('║   #$i ${s.entry.cardId} "${s.entry.nameCn}" '
            'sT=${s.sText.toStringAsFixed(3)} sV=${s.sVisual.toStringAsFixed(3)} '
            'boost=${s.boost.toStringAsFixed(2)} → ${s.finalScore.toStringAsFixed(3)}');
      }
      debugPrint('╚═══════════════════════════════════════════════════');

      if (scored.isEmpty) {
        sw.stop();
        resumeHashCache();
        return ScannerResult(
          debugMessage: '[Scanner] No candidates in ${sw.elapsedMilliseconds}ms.',
        );
      }

      final top = scored.first;
      final gap = scored.length >= 2
          ? top.finalScore - scored[1].finalScore
          : top.finalScore;
      final fast = top.finalScore >= 0.75 && gap >= 0.20;

      if (top.finalScore > 0.85) { HapticFeedback.mediumImpact(); }

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
      resumeHashCache();
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
    final textH = maxY - minY;
    final textW = maxX - minX;
    final tokens = <ZonedToken>[];
    final seen = <String>{};
    final splitRe = RegExp(r'[\s·•\-—\u3000\uff0c\u3001\uff0e]+');
    final cleanRe = RegExp(r'[^\u4e00-\u9fff\u3400-\u4dbfa-zA-Z0-9]');

    for (final block in recognised.blocks) {
      for (final line in block.lines) {
        final raw = line.text.trim();
        if (raw.isEmpty) { continue; }
        final zone = _assignZone(line, minX, minY, textW, textH);
        final norm = TextNormaliser.normalise(raw);

        final parts = <String>[];
        for (final part in norm.split(splitRe)) {
          final c = part.replaceAll(cleanRe, '');
          if (c.length >= 2) { parts.add(c); }
        }
        for (final p in parts) {
          final key = '${p}_${zone.name}';
          if (seen.add(key)) { tokens.add(ZonedToken(text: p, zone: zone)); }
        }
        if (parts.length > 1) {
          final full = norm.replaceAll(cleanRe, '');
          if (full.length >= 4) {
            final key = '${full}_${zone.name}';
            if (seen.add(key)) { tokens.add(ZonedToken(text: full, zone: zone)); }
          }
        }
      }
    }
    return tokens;
  }

  /// Zone assignment for general cards.
  ///
  /// OCR on a warped general card sees the full card. Zones by position
  /// within the detected text bounding box:
  ///
  ///   rY < 0.40, rX < 0.35, CJK-only, 2–5 chars  → name  (character name)
  ///   rY ≥ 0.80, right-side or alphanumeric        → id    (serial number)
  ///   rY ≥ 0.80                                    → type  (copyright line)
  ///   otherwise                                    → body  (skill descriptions)
  ///
  /// Character names (孙鲁班, 关银屏, etc.) appear as vertical calligraphy on
  /// the left side of the card. They fall in the upper-left OCR region.
  /// Assigning them name-zone weight (3.0) rather than body-zone weight (0.5)
  /// makes a correct name match decisive rather than negligible.
  CardZone _assignZone(TextLine line, double cL, double cT, double cW, double cH) {
    if (cH <= 0 || cW <= 0) { return CardZone.body; }
    final pts = line.cornerPoints;
    if (pts.isEmpty) { return CardZone.body; }
    final cy = pts.map((p) => p.y).reduce((a, b) => a + b) / pts.length;
    final cx = pts.map((p) => p.x).reduce((a, b) => a + b) / pts.length;
    final rY = (cy - cT) / cH;
    final rX = (cx - cL) / cW;

    // Name zone: upper-left region, short CJK-only text (2–5 chars).
    // Character names on SGS cards are vertical calligraphy on the left side.
    final cjkOnly = RegExp(r'^[\u4e00-\u9fff\u3400-\u4dbf]+$');
    final rawClean = line.text.replaceAll(RegExp(r'\s'), '');
    if (rY < 0.40 && rX < 0.40 &&
        rawClean.length >= 2 && rawClean.length <= 5 &&
        cjkOnly.hasMatch(rawClean)) {
      return CardZone.name;
    }

    if (rY > 0.80) {
      final cleaned = line.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      if (rX > 0.60 && cleaned.length >= 3) { return CardZone.id; }
      if (_idTokenRe.hasMatch(cleaned)) { return CardZone.id; }
      return CardZone.type;
    }

    return CardZone.body;
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

    if (_embeddingsReady) {
      // OCR on SGS cards reliably reads skill text, serial ID, and copyright
      // line. When present it is a strong, high-precision signal — ID matches
      // are near-deterministic and name/skill matches are highly selective.
      // Visual embedding handles cases where OCR is absent or ambiguous, and
      // acts as a tiebreaker between text-equal candidates.
      //
      // W_text=0.65, W_visual=0.35:
      //   Correct card, strong OCR (sT≈0.8, sV≈0.75): score ≈ 0.78 → fast-path
      //   Correct card, poor OCR  (sT≈0.2, sV≈0.75): score ≈ 0.39 → top-5
      //   Wrong card, no OCR hit  (sT≈0.0, sV≈0.59): score ≈ 0.21 → filtered
      return (0.65, 0.35);
    }

    // Fallback: model not loaded or embeddings not generated yet.
    debugPrint('[Scanner] ML embeddings: NOT ready (text-only mode)');
    return (1.0, 0.0);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CANDIDATE SCORING
  // ═════════════════════════════════════════════════════════════════════════

  _ScoredFusionCandidate? _scoreCandidate(
    _CardEntry entry,
    List<ZonedToken> tokens,
    Float32List? queryEmbedding,
    double baseWT,
    double baseWV,
    String? detectedFaction,
  ) {
    double best = 0.0;
    for (final token in tokens) {
      final zw = _zoneWeights[token.zone] ?? 1.0;

      // Name matching
      final nq = FuzzyMatcher.scannerFuzzyScore(token.text, entry.normName);
      if (nq > 0) { best = math.max(best, zw * nq); }

      // ID matching — ONLY id-zone tokens with ≥1 letter + ≥1 digit
      if (token.zone == CardZone.id) {
        final idClean = token.text
            .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
            .toUpperCase();
        if (_idTokenRe.hasMatch(idClean) && entry.normId.isNotEmpty) {
          if (idClean == entry.normId) {
            best = math.max(best, _zoneWeights[CardZone.id]!);
          } else if (entry.normId.contains(idClean) &&
              idClean.length >= entry.normId.length - 2) {
            best = math.max(best, _zoneWeights[CardZone.id]!);
          } else if (idClean.length >= 4) {
            final dist = FuzzyMatcher.levenshteinDistance(
                idClean, entry.normId);
            if (dist <= 2) {
              best = math.max(best,
                  _zoneWeights[CardZone.id]! * (1.0 - dist * 0.25));
            }
          }
        }
      }

      // Skill name matching with fuzzy tolerance
      for (final sk in entry.skillNames) {
        final skScore = FuzzyMatcher.scannerFuzzyScore(token.text, sk);
        if (skScore > 0) {
          best = math.max(best, _zoneWeights[CardZone.body]! * skScore);
          break;
        }
      }
    }
    final sText = (best / _maxZoneWeight).clamp(0.0, 1.0);

    // Visual scoring via ML feature embedding cosine similarity.
    double sVisual = 0.0;
    if (queryEmbedding != null) {
      final refEmb = ImageEmbeddingMatcher.instance
          .getReferenceEmbedding(entry.cardId);
      if (refEmb != null) {
        sVisual = ImageEmbeddingMatcher.instance
            .similarity(queryEmbedding, refEmb);
      }
    }

    double boost = 0.0;
    if (detectedFaction != null && entry.faction == detectedFaction) {
      boost += 0.05;
    }

    final finalScore = baseWT * sText + baseWV * sVisual + boost;
    // Adaptive noise-floor cutoff.
    // In fused mode (visual active): cutoff=0.25. Wrong cards with no OCR
    //   hit score ≈ 0.35*0.59_mean=0.21 and are filtered cleanly.
    // In text-only mode (visual not ready): cutoff=0.10. Max achievable
    //   score from body-zone skill match = 1.0*0.5/3.0=0.167, which cannot
    //   clear 0.25 — using 0.25 here silently eliminates every candidate.
    final cutoff = (baseWV > 0) ? 0.25 : 0.10;
    if (finalScore < cutoff) { return null; }

    return _ScoredFusionCandidate(
      entry: entry, sText: sText, sVisual: sVisual,
      boost: boost, finalScore: finalScore,
    );
  }

  String _normaliseId(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
}