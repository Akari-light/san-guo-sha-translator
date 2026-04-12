// lib/core/services/scanner_service.dart
//
// Multimodal scanner service.
//
// Current product scope remains general-card scanning, but the matching engine
// now runs OCR retrieval and visual retrieval as separate tracks and fuses them
// in a calibrated reranker.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    show RecognizedText, TextLine;
import 'package:image/image.dart' as img;

import 'fuzzy_matcher.dart';
import 'image_embedding_matcher.dart';
import 'recently_viewed_service.dart';
import 'text_normaliser.dart';
import '../../features/generals/data/repository/general_loader.dart';

class MatchCandidate {
  final String cardId;
  final RecordType recordType;
  final String nameCn;
  final String nameEn;
  final String imagePath;
  final double confidence;
  final double ocrConfidence;
  final double visualConfidence;
  final double qualityConfidence;
  final bool fromOcrShortlist;
  final bool fromVisualShortlist;

  const MatchCandidate({
    required this.cardId,
    required this.recordType,
    required this.nameCn,
    required this.nameEn,
    required this.imagePath,
    required this.confidence,
    required this.ocrConfidence,
    required this.visualConfidence,
    required this.qualityConfidence,
    required this.fromOcrShortlist,
    required this.fromVisualShortlist,
  });
}

enum ScannerOutcome { autoSelect, rankedResults, retake }

enum ScannerFailureReason {
  none,
  lowQuality,
  noSignal,
  noCandidates,
  ambiguous,
  ocrVisualDisagreement,
}

class ScannerResult {
  final List<MatchCandidate> candidates;
  final String debugMessage;
  final String guidanceMessage;
  final ScannerOutcome outcome;
  final ScannerFailureReason failureReason;
  final double scanQuality;
  final String? detectedFaction;
  final List<String> ocrTokens;
  final List<String> ocrShortlistIds;
  final List<String> visualShortlistIds;

  const ScannerResult({
    this.candidates = const [],
    required this.debugMessage,
    required this.guidanceMessage,
    required this.outcome,
    this.failureReason = ScannerFailureReason.none,
    this.scanQuality = 0.0,
    this.detectedFaction,
    this.ocrTokens = const [],
    this.ocrShortlistIds = const [],
    this.visualShortlistIds = const [],
  });

  bool get hasMatch => candidates.isNotEmpty;
  bool get fastPath => outcome == ScannerOutcome.autoSelect;
  MatchCandidate? get topCandidate => candidates.isEmpty ? null : candidates.first;
}

enum ScanSource { camera, gallery, userCrop, straightened }

enum CardZone { name, id, type, body, unknown }

class ZonedToken {
  final String text;
  final CardZone zone;
  const ZonedToken({required this.text, required this.zone});

  @override
  String toString() => 'ZonedToken($text, ${zone.name})';
}

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

class _TrackCandidate {
  final _CardEntry entry;
  final double score;

  const _TrackCandidate({required this.entry, required this.score});
}

class _ScanQualityMetrics {
  final double focus;
  final double contrast;
  final double exposure;
  final double overall;

  const _ScanQualityMetrics({
    required this.focus,
    required this.contrast,
    required this.exposure,
    required this.overall,
  });

  bool get isLow => overall < 0.28;
}

class _ScoredFusionCandidate {
  final _CardEntry entry;
  final double sText;
  final double sVisual;
  final double quality;
  final double finalScore;
  final bool fromOcrShortlist;
  final bool fromVisualShortlist;

  const _ScoredFusionCandidate({
    required this.entry,
    required this.sText,
    required this.sVisual,
    required this.quality,
    required this.finalScore,
    required this.fromOcrShortlist,
    required this.fromVisualShortlist,
  });
}

const _zoneWeights = <CardZone, double>{
  CardZone.name: 3.0,
  CardZone.id: 2.5,
  CardZone.type: 2.0,
  CardZone.body: 0.5,
  CardZone.unknown: 1.0,
};
const _maxZoneWeight = 3.0;
const _ocrShortlistSize = 8;
const _visualShortlistSize = 8;
const _resultListSize = 5;

final _idTokenRe = RegExp(r'^(?=.*[A-Za-z])(?=.*[0-9])[A-Za-z0-9]{4,}$');

class ScannerService {
  ScannerService._();
  static final ScannerService instance = ScannerService._();

  List<_CardEntry>? _allEntries;
  final Map<String, _CardEntry> _entriesById = {};
  bool _warmingUp = false;
  bool _embeddingsReady = false;

  Future<void> warmup() async {
    if (_allEntries != null || _warmingUp) {
      return;
    }
    _warmingUp = true;
    try {
      final generals = await GeneralLoader().getGenerals();
      _allEntries = generals
          .map(
            (g) => _CardEntry(
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
            ),
          )
          .toList();
      _entriesById
        ..clear()
        ..addEntries(_allEntries!.map((e) => MapEntry(e.cardId, e)));

      debugPrint('[Scanner] Warmup: ${_allEntries!.length} generals.');

      await ImageEmbeddingMatcher.instance.loadModel();
      await ImageEmbeddingMatcher.instance.loadReferenceEmbeddings();
      _embeddingsReady = ImageEmbeddingMatcher.instance.referenceCount > 0;
      debugPrint('[Scanner] ML embeddings ready: $_embeddingsReady '
          '(${ImageEmbeddingMatcher.instance.referenceCount} refs / '
          '${ImageEmbeddingMatcher.instance.logicalCardCount} logical cards)');
    } finally {
      _warmingUp = false;
    }
  }

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

  Future<ScannerResult> _runFusion(
    Uint8List bytes,
    RecognizedText? recognisedText,
    ScanSource source,
    img.Image? straightenedImage,
  ) async {
    pauseHashCache();
    final sw = Stopwatch()..start();
    if (_allEntries == null) {
      await warmup();
    }

    try {
      final zonedTokens = recognisedText != null
          ? _extractZonedTokens(recognisedText)
          : <ZonedToken>[];
      final queryEmbedding = _extractQueryEmbedding(bytes, source, straightenedImage);
      final scanImage = straightenedImage ?? img.decodeImage(bytes);
      final quality = scanImage != null
          ? _estimateScanQuality(scanImage)
          : const _ScanQualityMetrics(focus: 0, contrast: 0, exposure: 0, overall: 0);

      String? detectedFaction;
      if (source == ScanSource.straightened && straightenedImage != null) {
        detectedFaction = _detectFaction(straightenedImage);
      }

      final ocrTrack = _buildOcrShortlist(zonedTokens);
      final visualTrack = queryEmbedding != null
          ? _buildVisualShortlist(queryEmbedding)
          : const <_TrackCandidate>[];

      final ocrScores = {
        for (final candidate in ocrTrack) candidate.entry.cardId: candidate.score,
      };
      final visualScores = {
        for (final candidate in visualTrack) candidate.entry.cardId: candidate.score,
      };

      final ocrLeaderId = ocrTrack.isNotEmpty ? ocrTrack.first.entry.cardId : null;
      final visualLeaderId = visualTrack.isNotEmpty ? visualTrack.first.entry.cardId : null;
      final trackLeadersDisagree =
          ocrLeaderId != null && visualLeaderId != null && ocrLeaderId != visualLeaderId;

      final candidateIds = <String>{
        ...ocrScores.keys,
        ...visualScores.keys,
      };

      debugPrint('+----------------------------------------------------------');
      debugPrint('| [Scanner] PHASE A - INPUT');
      debugPrint('| Source: ${source.name} | Tokens: ${zonedTokens.length}');
      debugPrint('| Quality=${quality.overall.toStringAsFixed(3)} '
          '(focus=${quality.focus.toStringAsFixed(3)} '
          'contrast=${quality.contrast.toStringAsFixed(3)} '
          'exposure=${quality.exposure.toStringAsFixed(3)})');
      debugPrint('| Embedding: ${queryEmbedding != null ? 'OK' : 'NULL'} | '
          'Faction: $detectedFaction');
      debugPrint('| OCR shortlist: ${ocrTrack.map((c) => '${c.entry.cardId}:${c.score.toStringAsFixed(3)}').join(', ')}');
      debugPrint('| Visual shortlist: ${visualTrack.map((c) => '${c.entry.cardId}:${c.score.toStringAsFixed(3)}').join(', ')}');

      if (candidateIds.isEmpty) {
        sw.stop();
        resumeHashCache();
        return _emptyResult(
          elapsedMs: sw.elapsedMilliseconds,
          quality: quality,
          detectedFaction: detectedFaction,
          zonedTokens: zonedTokens,
          failureReason: quality.isLow
              ? ScannerFailureReason.lowQuality
              : ScannerFailureReason.noSignal,
          debugMessage: '[Scanner] No OCR or visual candidates.',
        );
      }

      final fused = <_ScoredFusionCandidate>[];
      for (final cardId in candidateIds) {
        final entry = _entriesById[cardId];
        if (entry == null) {
          continue;
        }
        final textScore = ocrScores[cardId] ?? 0.0;
        final visualScore = visualScores[cardId] ?? 0.0;
        fused.add(
          _fuseCandidate(
            entry,
            textScore: textScore,
            visualScore: visualScore,
            quality: quality.overall,
            detectedFaction: detectedFaction,
            fromOcrShortlist: ocrScores.containsKey(cardId),
            fromVisualShortlist: visualScores.containsKey(cardId),
          ),
        );
      }
      fused.sort((a, b) => b.finalScore.compareTo(a.finalScore));

      debugPrint('| [Scanner] PHASE B - FUSION TOP ${math.min(5, fused.length)}');
      for (var i = 0; i < math.min(5, fused.length); i++) {
        final s = fused[i];
        debugPrint('|   #$i ${s.entry.cardId} '
            'sT=${s.sText.toStringAsFixed(3)} '
            'sV=${s.sVisual.toStringAsFixed(3)} '
            'q=${s.quality.toStringAsFixed(3)} '
            '-> ${s.finalScore.toStringAsFixed(3)}');
      }
      debugPrint('+----------------------------------------------------------');

      if (fused.isEmpty) {
        sw.stop();
        resumeHashCache();
        return _emptyResult(
          elapsedMs: sw.elapsedMilliseconds,
          quality: quality,
          detectedFaction: detectedFaction,
          zonedTokens: zonedTokens,
          failureReason: quality.isLow
              ? ScannerFailureReason.lowQuality
              : ScannerFailureReason.noCandidates,
          debugMessage: '[Scanner] Candidate union collapsed.',
        );
      }

      final top = fused.first;
      final gap = fused.length >= 2
          ? top.finalScore - fused[1].finalScore
          : top.finalScore;

      final outcome = _decideOutcome(
        top: top,
        gap: gap,
        quality: quality,
        trackLeadersDisagree: trackLeadersDisagree,
      );
      final failureReason = _resolveFailureReason(
        outcome: outcome,
        quality: quality,
        trackLeadersDisagree: trackLeadersDisagree,
        gap: gap,
      );

      final candidates = (outcome == ScannerOutcome.autoSelect
              ? fused.take(1)
              : fused.take(_resultListSize))
          .map(
            (s) => MatchCandidate(
              cardId: s.entry.cardId,
              recordType: s.entry.recordType,
              nameCn: s.entry.nameCn,
              nameEn: s.entry.nameEn,
              imagePath: s.entry.imagePath,
              confidence: s.finalScore,
              ocrConfidence: s.sText,
              visualConfidence: s.sVisual,
              qualityConfidence: s.quality,
              fromOcrShortlist: s.fromOcrShortlist,
              fromVisualShortlist: s.fromVisualShortlist,
            ),
          )
          .toList();

      sw.stop();

      if (outcome == ScannerOutcome.autoSelect && top.finalScore >= 0.88) {
        HapticFeedback.mediumImpact();
      } else if (outcome == ScannerOutcome.rankedResults && top.finalScore >= 0.62) {
        HapticFeedback.lightImpact();
      }

      return ScannerResult(
        candidates: candidates,
        outcome: outcome,
        failureReason: failureReason,
        scanQuality: quality.overall,
        detectedFaction: detectedFaction,
        ocrTokens: zonedTokens.map((t) => t.text).toList(growable: false),
        ocrShortlistIds: ocrTrack.map((c) => c.entry.cardId).toList(growable: false),
        visualShortlistIds: visualTrack.map((c) => c.entry.cardId).toList(growable: false),
        guidanceMessage: _guidanceMessage(outcome, failureReason),
        debugMessage: '[Scanner] ${outcome.name} with ${candidates.length} '
            'candidate(s) in ${sw.elapsedMilliseconds}ms.',
      );
    } catch (e, stack) {
      debugPrint('[Scanner] Error: $e\n$stack');
      resumeHashCache();
      return ScannerResult(
        outcome: ScannerOutcome.retake,
        failureReason: ScannerFailureReason.noCandidates,
        guidanceMessage: 'Scan failed. Try again with a flatter crop.',
        debugMessage: '[Scanner] Error: $e',
      );
    }
  }

  Float32List? _extractQueryEmbedding(
    Uint8List bytes,
    ScanSource source,
    img.Image? straightenedImage,
  ) {
    if (!_embeddingsReady) {
      return null;
    }
    if (source == ScanSource.straightened && straightenedImage != null) {
      return ImageEmbeddingMatcher.instance.embeddingFromImage(straightenedImage);
    }
    return ImageEmbeddingMatcher.instance.embeddingFromBytes(bytes);
  }

  List<ZonedToken> _extractZonedTokens(RecognizedText recognised) {
    double minY = double.infinity, maxY = 0, minX = double.infinity, maxX = 0;
    for (final block in recognised.blocks) {
      for (final pt in block.cornerPoints) {
        if (pt.x < minX) {
          minX = pt.x.toDouble();
        }
        if (pt.x > maxX) {
          maxX = pt.x.toDouble();
        }
        if (pt.y < minY) {
          minY = pt.y.toDouble();
        }
        if (pt.y > maxY) {
          maxY = pt.y.toDouble();
        }
      }
    }

    final textH = maxY - minY;
    final textW = maxX - minX;
    final tokens = <ZonedToken>[];
    final seen = <String>{};
    final splitRe = RegExp(r'[\sÂ·â€¢\-â€”\u3000\uff0c\u3001\uff0e]+');
    final cleanRe = RegExp(r'[^\u4e00-\u9fff\u3400-\u4dbfa-zA-Z0-9]');

    for (final block in recognised.blocks) {
      for (final line in block.lines) {
        final raw = line.text.trim();
        if (raw.isEmpty) {
          continue;
        }
        final zone = _assignZone(line, minX, minY, textW, textH);
        final norm = TextNormaliser.normalise(raw);

        final parts = <String>[];
        for (final part in norm.split(splitRe)) {
          final cleaned = part.replaceAll(cleanRe, '');
          if (cleaned.length >= 2) {
            parts.add(cleaned);
          }
        }
        for (final part in parts) {
          final key = '${part}_${zone.name}';
          if (seen.add(key)) {
            tokens.add(ZonedToken(text: part, zone: zone));
          }
        }
        if (parts.length > 1) {
          final full = norm.replaceAll(cleanRe, '');
          if (full.length >= 4) {
            final key = '${full}_${zone.name}';
            if (seen.add(key)) {
              tokens.add(ZonedToken(text: full, zone: zone));
            }
          }
        }
      }
    }
    return tokens;
  }

  CardZone _assignZone(TextLine line, double cL, double cT, double cW, double cH) {
    if (cH <= 0 || cW <= 0) {
      return CardZone.body;
    }
    final pts = line.cornerPoints;
    if (pts.isEmpty) {
      return CardZone.body;
    }
    final cy = pts.map((p) => p.y).reduce((a, b) => a + b) / pts.length;
    final cx = pts.map((p) => p.x).reduce((a, b) => a + b) / pts.length;
    final rY = (cy - cT) / cH;
    final rX = (cx - cL) / cW;

    final cjkOnly = RegExp(r'^[\u4e00-\u9fff\u3400-\u4dbf]+$');
    final rawClean = line.text.replaceAll(RegExp(r'\s'), '');
    if (rY < 0.40 &&
        rX < 0.40 &&
        rawClean.length >= 2 &&
        rawClean.length <= 5 &&
        cjkOnly.hasMatch(rawClean)) {
      return CardZone.name;
    }

    if (rY > 0.80) {
      final cleaned = line.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      if (rX > 0.60 && cleaned.length >= 3) {
        return CardZone.id;
      }
      if (_idTokenRe.hasMatch(cleaned)) {
        return CardZone.id;
      }
      return CardZone.type;
    }

    return CardZone.body;
  }

  String? _detectFaction(img.Image straightened) {
    final w = straightened.width, h = straightened.height;
    final pL = (w * 0.30).round(), pT = (h * 0.45).round();
    final pW = math.max(4, (w * 0.10).round());
    final pH = math.max(4, (h * 0.10).round());
    int pR = 0, pG = 0, pB = 0, pN = 0;
    for (var y = pT; y < pT + pH && y < h; y++) {
      for (var x = pL; x < pL + pW && x < w; x++) {
        final px = straightened.getPixel(x, y);
        pR += px.r.toInt();
        pG += px.g.toInt();
        pB += px.b.toInt();
        pN++;
      }
    }
    const rR = 210.0, rG = 190.0, rB = 160.0;
    double cR = 1.0, cG = 1.0, cB = 1.0;
    if (pN > 0) {
      final sR = pR / pN, sG = pG / pN, sB = pB / pN;
      if (sR > 80 && sR < 250 && sG > 60 && sG < 250 && sB > 40 && sB < 250) {
        cR = rR / sR;
        cG = rG / sG;
        cB = rB / sB;
      }
    }
    final sW = math.max(4, (w * 0.05).round());
    final sH = math.max(4, (h * 0.05).round());
    int tR = 0, tG = 0, tB = 0, cnt = 0;
    for (var y = 0; y < sH && y < h; y++) {
      for (var x = 0; x < sW && x < w; x++) {
        final px = straightened.getPixel(x, y);
        tR += px.r.toInt();
        tG += px.g.toInt();
        tB += px.b.toInt();
        cnt++;
      }
    }
    if (cnt == 0) {
      return null;
    }
    final aR = (tR / cnt) * cR, aG = (tG / cnt) * cG, aB = (tB / cnt) * cB;
    if (aB > 120 && aR < 100 && aB > aG) {
      return 'Wei';
    }
    if (aR > 150 && aB < 100 && aR > aG) {
      return 'Shu';
    }
    if (aG > 120 && aR < 100 && aB < 100) {
      return 'Wu';
    }
    if (aR > 180 && aG > 150 && aB < 100) {
      return 'God';
    }
    final maxC = math.max(aR, math.max(aG, aB));
    final minC = math.min(aR, math.min(aG, aB));
    if (maxC - minC < 30 && minC > 120) {
      return 'Qun';
    }
    return null;
  }

  _ScanQualityMetrics _estimateScanQuality(img.Image image) {
    final stepX = math.max(1, image.width ~/ 120);
    final stepY = math.max(1, image.height ~/ 160);

    double mean = 0.0;
    double m2 = 0.0;
    double edgeSum = 0.0;
    var count = 0;
    var edgeCount = 0;

    for (var y = 0; y < image.height; y += stepY) {
      int? prevLuma;
      for (var x = 0; x < image.width; x += stepX) {
        final px = image.getPixel(x, y);
        final luma = ((px.r.toDouble() * 0.299) +
                (px.g.toDouble() * 0.587) +
                (px.b.toDouble() * 0.114))
            .round();
        count++;
        final delta = luma - mean;
        mean += delta / count;
        m2 += delta * (luma - mean);
        if (prevLuma != null) {
          edgeSum += (luma - prevLuma).abs();
          edgeCount++;
        }
        prevLuma = luma;
      }
    }

    if (count == 0) {
      return const _ScanQualityMetrics(focus: 0, contrast: 0, exposure: 0, overall: 0);
    }

    final variance = count > 1 ? m2 / (count - 1) : 0.0;
    final stdDev = math.sqrt(variance);
    final contrast = (stdDev / 72.0).clamp(0.0, 1.0);
    final focus = edgeCount == 0 ? 0.0 : ((edgeSum / edgeCount) / 42.0).clamp(0.0, 1.0);
    final exposure = (1.0 - ((mean - 132.0).abs() / 132.0)).clamp(0.0, 1.0);
    final overall = (focus * 0.42 + contrast * 0.36 + exposure * 0.22).clamp(0.0, 1.0);

    return _ScanQualityMetrics(
      focus: focus,
      contrast: contrast,
      exposure: exposure,
      overall: overall,
    );
  }

  List<_TrackCandidate> _buildOcrShortlist(List<ZonedToken> tokens) {
    if (tokens.isEmpty || _allEntries == null) {
      return const <_TrackCandidate>[];
    }

    final scored = <_TrackCandidate>[];
    for (final entry in _allEntries!) {
      final score = _scoreTextSignal(entry, tokens);
      if (score > 0.0) {
        scored.add(_TrackCandidate(entry: entry, score: score));
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(_ocrShortlistSize).toList(growable: false);
  }

  List<_TrackCandidate> _buildVisualShortlist(Float32List queryEmbedding) {
    final matches = ImageEmbeddingMatcher.instance.findTopKLogicalCards(
      queryEmbedding,
      k: _visualShortlistSize,
    );

    final candidates = <_TrackCandidate>[];
    for (final match in matches) {
      final entry = _entriesById[match.logicalCardId];
      if (entry != null) {
        candidates.add(_TrackCandidate(entry: entry, score: match.similarity));
      }
    }
    return candidates;
  }

  double _scoreTextSignal(_CardEntry entry, List<ZonedToken> tokens) {
    double best = 0.0;
    for (final token in tokens) {
      final zoneWeight = _zoneWeights[token.zone] ?? 1.0;

      final nameScore = FuzzyMatcher.scannerFuzzyScore(token.text, entry.normName);
      if (nameScore > 0) {
        best = math.max(best, zoneWeight * nameScore);
      }

      if (token.zone == CardZone.id) {
        final idClean = token.text
            .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
            .toUpperCase();
        if (_idTokenRe.hasMatch(idClean) && entry.normId.isNotEmpty) {
          if (idClean == entry.normId) {
            best = math.max(best, _maxZoneWeight);
          } else if (entry.normId.contains(idClean) &&
              idClean.length >= entry.normId.length - 2) {
            best = math.max(best, _maxZoneWeight);
          } else if (idClean.length >= 4) {
            final dist = FuzzyMatcher.levenshteinDistance(idClean, entry.normId);
            if (dist == 1) {
              best = math.max(best, _maxZoneWeight * 0.90);
            } else if (dist == 2) {
              best = math.max(best, _maxZoneWeight * 0.75);
            }
          }
        }
      }

      for (final skill in entry.skillNames) {
        final skillScore = FuzzyMatcher.scannerFuzzyScore(token.text, skill);
        if (skillScore > 0) {
          best = math.max(best, zoneWeight * skillScore);
          break;
        }
      }
    }

    return (best / _maxZoneWeight).clamp(0.0, 1.0);
  }

  _ScoredFusionCandidate _fuseCandidate(
    _CardEntry entry, {
    required double textScore,
    required double visualScore,
    required double quality,
    required String? detectedFaction,
    required bool fromOcrShortlist,
    required bool fromVisualShortlist,
  }) {
    final ocrConfidence = _calibrateOcrScore(textScore);
    final visualConfidence = _calibrateVisualScore(visualScore);
    final qualityConfidence = quality.clamp(0.0, 1.0);

    double score;
    if (ocrConfidence > 0 && visualConfidence > 0) {
      score = 0.52 * ocrConfidence +
          0.36 * visualConfidence +
          0.12 * qualityConfidence;
    } else if (ocrConfidence > 0) {
      score = 0.82 * ocrConfidence + 0.18 * qualityConfidence;
    } else {
      score = 0.78 * visualConfidence + 0.22 * qualityConfidence;
    }

    if (detectedFaction != null && entry.faction == detectedFaction) {
      score += 0.04;
    }
    if (fromOcrShortlist && fromVisualShortlist) {
      score += 0.03;
    }
    if (ocrConfidence > 0 && visualConfidence > 0) {
      final delta = (ocrConfidence - visualConfidence).abs();
      if (delta > 0.45) {
        score -= 0.07;
      }
    }
    if (qualityConfidence < 0.28) {
      score -= 0.08;
    }

    return _ScoredFusionCandidate(
      entry: entry,
      sText: ocrConfidence,
      sVisual: visualConfidence,
      quality: qualityConfidence,
      finalScore: score.clamp(0.0, 1.0),
      fromOcrShortlist: fromOcrShortlist,
      fromVisualShortlist: fromVisualShortlist,
    );
  }

  double _calibrateOcrScore(double rawScore) {
    if (rawScore <= 0.0) {
      return 0.0;
    }
    if (rawScore >= 0.95) {
      return 1.0;
    }
    final normalised = ((rawScore - 0.12) / 0.78).clamp(0.0, 1.0);
    return _smoothstep(normalised);
  }

  double _calibrateVisualScore(double rawSimilarity) {
    if (rawSimilarity <= 0.0) {
      return 0.0;
    }
    final normalised = ((rawSimilarity - 0.42) / 0.40).clamp(0.0, 1.0);
    return _smoothstep(normalised);
  }

  double _smoothstep(double value) {
    final x = value.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  ScannerOutcome _decideOutcome({
    required _ScoredFusionCandidate top,
    required double gap,
    required _ScanQualityMetrics quality,
    required bool trackLeadersDisagree,
  }) {
    if (quality.isLow && top.finalScore < 0.55 && top.sVisual < 0.70) {
      return ScannerOutcome.retake;
    }

    final strongWinner = top.finalScore >= 0.84 && gap >= 0.14;
    final disagreementPenalty =
        trackLeadersDisagree && top.sText >= 0.45 && top.sVisual >= 0.45;
    if (strongWinner && !disagreementPenalty) {
      return ScannerOutcome.autoSelect;
    }

    if (top.finalScore >= 0.34) {
      return ScannerOutcome.rankedResults;
    }

    return ScannerOutcome.retake;
  }

  ScannerFailureReason _resolveFailureReason({
    required ScannerOutcome outcome,
    required _ScanQualityMetrics quality,
    required bool trackLeadersDisagree,
    required double gap,
  }) {
    if (outcome == ScannerOutcome.retake) {
      return quality.isLow
          ? ScannerFailureReason.lowQuality
          : ScannerFailureReason.noCandidates;
    }
    if (trackLeadersDisagree) {
      return ScannerFailureReason.ocrVisualDisagreement;
    }
    if (gap < 0.08) {
      return ScannerFailureReason.ambiguous;
    }
    return ScannerFailureReason.none;
  }

  ScannerResult _emptyResult({
    required int elapsedMs,
    required _ScanQualityMetrics quality,
    required String? detectedFaction,
    required List<ZonedToken> zonedTokens,
    required ScannerFailureReason failureReason,
    required String debugMessage,
  }) {
    return ScannerResult(
      outcome: ScannerOutcome.retake,
      failureReason: failureReason,
      scanQuality: quality.overall,
      detectedFaction: detectedFaction,
      ocrTokens: zonedTokens.map((t) => t.text).toList(growable: false),
      guidanceMessage: _guidanceMessage(ScannerOutcome.retake, failureReason),
      debugMessage: '$debugMessage ($elapsedMs ms)',
    );
  }

  String _guidanceMessage(
    ScannerOutcome outcome,
    ScannerFailureReason failureReason,
  ) {
    if (outcome == ScannerOutcome.autoSelect) {
      return 'Confident match found.';
    }
    switch (failureReason) {
      case ScannerFailureReason.lowQuality:
        return 'Scan looks too soft or dim. Retake with steadier framing and more light.';
      case ScannerFailureReason.ocrVisualDisagreement:
        return 'OCR and image search disagree, so here are the closest matches.';
      case ScannerFailureReason.ambiguous:
        return 'Several cards are close. Pick from the best matches below.';
      case ScannerFailureReason.noSignal:
        return 'Could not read enough text or image detail. Adjust the crop and retry.';
      case ScannerFailureReason.noCandidates:
        return 'No strong match yet. Adjust the crop and retry.';
      case ScannerFailureReason.none:
        return 'Best matches ready.';
    }
  }

  String _normaliseId(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
}

