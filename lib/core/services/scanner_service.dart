// lib/core/services/scanner_service.dart
//
// Card image matching service.
// Two-stage pipeline — both stages are fully on-device, no network calls.
//
// Stage 1 — OCR text matching (~200ms)
//   google_mlkit_text_recognition reads the camera frame.
//   TextNormaliser converts any traditional chars to simplified.
//   Extracted tokens are matched against name_cn of every general, skill,
//   and library card using the already-cached loader data.
//   Scoring: +2 for card name match, +1 per matching skill name.
//   If a single card scores ≥2 with no other card at ≥1, returns immediately.
//
// Stage 2 — pHash image similarity (~10ms)
//   The top-60% artwork region of the camera frame is cropped and hashed.
//   The hash is compared against the reference .webp for each shortlist candidate.
//   Candidates below 0.6 similarity are dropped.
//   Remaining candidates are returned sorted by descending similarity.
//
// Architecture rules:
//   - No feature/* imports — core only.
//   - GeneralLoader and LibraryLoader are accessed by type name only;
//     they are singletons and their caches will already be warm.
//   - MatchCandidate is the canonical definition — ai_screen.dart imports it here.
//   - RecordType comes from recently_viewed_service.dart (already core).

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'recently_viewed_service.dart';
import 'text_normaliser.dart';
import 'image_hash_matcher.dart';
import '../../../features/generals/data/repository/general_loader.dart';
import '../../../features/library/data/repository/library_loader.dart';

// ── MatchCandidate ─────────────────────────────────────────────────────────
// Canonical definition — ai_screen.dart imports this.

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

// ── ScannerResult ──────────────────────────────────────────────────────────

class ScannerResult {
  /// Ranked match candidates (empty when no match found).
  final List<MatchCandidate> candidates;

  /// Human-readable status for logging / debug.
  final String debugMessage;

  const ScannerResult({
    this.candidates = const [],
    required this.debugMessage,
  });

  bool get hasMatch => candidates.isNotEmpty;
}

// ── _ScoredCandidate — internal scoring model ──────────────────────────────

class _ScoredCandidate {
  final String cardId;
  final RecordType recordType;
  final String nameCn;
  final String nameEn;
  final String imagePath;
  int score = 0;

  _ScoredCandidate({
    required this.cardId,
    required this.recordType,
    required this.nameCn,
    required this.nameEn,
    required this.imagePath,
  });
}

// ── ScannerService ─────────────────────────────────────────────────────────

class ScannerService {
  ScannerService._();
  static final ScannerService instance = ScannerService._();

  // MLKit recogniser — created once, reused across scans.
  // TextRecognitionScript.chinese recognises both traditional and simplified.
  final TextRecognizer _recogniser = TextRecognizer(
    script: TextRecognitionScript.chinese,
  );

  bool _disposed = false;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Runs the two-stage matching pipeline on [bytes] (JPEG from the camera).
  ///
  /// Returns a [ScannerResult] with up to 5 ranked [MatchCandidate]s.
  /// Returns an empty candidates list if no match is found.
  Future<ScannerResult> match(
    Uint8List bytes, {
    String sourceLabel = 'camera',
  }) async {
    return _runMatching(bytes, sourceLabel);
  }

  /// Releases the MLKit text recogniser. Call when the scanner is permanently
  /// torn down (e.g. when AiScreen is disposed and will not be revisited).
  void dispose() {
    if (!_disposed) {
      _recogniser.close();
      _disposed = true;
    }
  }

  // ── Matching pipeline ─────────────────────────────────────────────────────

  Future<ScannerResult> _runMatching(
    Uint8List bytes,
    String sourceLabel,
  ) async {
    final stopwatch = Stopwatch()..start();

    try {
      // ── Stage 1: OCR text matching ────────────────────────────────────────
      final ocrTokens = await _extractOcrTokens(bytes);
      debugPrint('[Scanner] OCR tokens: $ocrTokens');

      if (ocrTokens.isEmpty) {
        return ScannerResult(
          debugMessage: '[Scanner] No text detected in frame.',
        );
      }

      final shortlist = await _buildShortlist(ocrTokens);
      debugPrint('[Scanner] Stage 1 shortlist: ${shortlist.length} candidates');

      if (shortlist.isEmpty) {
        return ScannerResult(
          debugMessage: '[Scanner] OCR tokens found but no card matched.',
        );
      }

      // Fast path: single confident name match — skip pHash
      if (shortlist.length == 1 && shortlist.first.score >= 2) {
        final c = shortlist.first;
        debugPrint('[Scanner] Fast path match: ${c.cardId} in ${stopwatch.elapsedMilliseconds}ms');
        return ScannerResult(
          candidates: [
            MatchCandidate(
              cardId: c.cardId,
              recordType: c.recordType,
              nameCn: c.nameCn,
              nameEn: c.nameEn,
              imagePath: c.imagePath,
              confidence: 1.0,
            ),
          ],
          debugMessage: '[Scanner] Stage 1 fast-path match in ${stopwatch.elapsedMilliseconds}ms.',
        );
      }

      // ── Stage 2: pHash image similarity ───────────────────────────────────
      final candidates = await _rankByImageHash(bytes, shortlist);
      debugPrint('[Scanner] Stage 2 candidates: ${candidates.length} passed threshold');

      stopwatch.stop();
      return ScannerResult(
        candidates: candidates,
        debugMessage: candidates.isEmpty
            ? '[Scanner] No candidates passed pHash threshold (${stopwatch.elapsedMilliseconds}ms).'
            : '[Scanner] ${candidates.length} match(es) in ${stopwatch.elapsedMilliseconds}ms.',
      );
    } catch (e, stack) {
      debugPrint('[Scanner] Error: $e\n$stack');
      return ScannerResult(
        debugMessage: '[Scanner] Error during matching: $e',
      );
    }
  }

  // ── Stage 1 helpers ───────────────────────────────────────────────────────

  /// Runs MLKit OCR on [bytes], normalises each text block to simplified
  /// Chinese, and returns a deduplicated set of non-trivial tokens.
  Future<Set<String>> _extractOcrTokens(Uint8List bytes) async {
    // Write bytes to a temp file — InputImage.fromFilePath is the most
    // reliable cross-platform approach for in-memory JPEG bytes.
    final dir = await getTemporaryDirectory();
    final tmpFile = File('${dir.path}/scanner_frame.jpg');
    await tmpFile.writeAsBytes(bytes);
    final inputImage = InputImage.fromFilePath(tmpFile.path);

    final recognised = await _recogniser.processImage(inputImage);
    final tokens = <String>{};

    for (final block in recognised.blocks) {
      for (final line in block.lines) {
        final raw = line.text.trim();
        if (raw.isEmpty) continue;
        // Normalise: traditional → simplified
        final normalised = TextNormaliser.normalise(raw);
        // Split by whitespace and common punctuation
        final parts = normalised.split(
          RegExp(r'[\s·•·\-—\u3000\uff0c\u3001\uff0e\u300c\u300d]+'),
        );
        for (final part in parts) {
          // Keep only CJK characters + alphanumerics, min length 2
          final clean = part.replaceAll(
            RegExp(r'[^\u4e00-\u9fff\u3400-\u4dbfa-zA-Z0-9]'),
            '',
          );
          if (clean.length >= 2) tokens.add(clean);
        }
      }
    }
    return tokens;
  }

  /// Scores every card in the cached loaders against [ocrTokens].
  /// Returns a shortlist of up to 5 candidates with score ≥ 1,
  /// sorted by descending score.
  Future<List<_ScoredCandidate>> _buildShortlist(
    Set<String> ocrTokens,
  ) async {
    final scores = <String, _ScoredCandidate>{};

    // ── Score generals ────────────────────────────────────────────────────
    final generals = await GeneralLoader().getGenerals();

    for (final general in generals) {
      final nameCn = TextNormaliser.normalise(general.nameCn);

      // +2 for card name match
      if (ocrTokens.any((t) => nameCn.contains(t) || t.contains(nameCn))) {
        _addScore(
          scores, general.id, RecordType.general,
          general.nameCn, general.nameEn, general.imagePath, 2,
        );
      }

      // +1 per matching skill name
      for (final skill in general.skills) {
        final skillNameCn = TextNormaliser.normalise(skill.nameCn);
        if (ocrTokens.any((t) => skillNameCn == t || t.contains(skillNameCn))) {
          _addScore(
            scores, general.id, RecordType.general,
            general.nameCn, general.nameEn, general.imagePath, 1,
          );
        }
      }
    }

    // ── Score library cards ───────────────────────────────────────────────
    final libraryCards = await LibraryLoader().getCards();

    for (final card in libraryCards) {
      final nameCn = TextNormaliser.normalise(card.nameCn);
      if (ocrTokens.any((t) => nameCn.contains(t) || t.contains(nameCn))) {
        _addScore(
          scores, card.id, RecordType.library,
          card.nameCn, card.nameEn, card.imagePath, 2,
        );
      }
    }

    final shortlist = scores.values
        .where((c) => c.score >= 1)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return shortlist.take(5).toList();
  }

  void _addScore(
    Map<String, _ScoredCandidate> scores,
    String id,
    RecordType type,
    String nameCn,
    String nameEn,
    String imagePath,
    int points,
  ) {
    scores.putIfAbsent(
      id,
      () => _ScoredCandidate(
        cardId: id,
        recordType: type,
        nameCn: nameCn,
        nameEn: nameEn,
        imagePath: imagePath,
      ),
    ).score += points;
  }

  // ── Stage 2 helpers ───────────────────────────────────────────────────────

  /// Crops the top 60% of [bytes] (artwork region), hashes it with pHash,
  /// compares against each candidate's reference asset, and returns candidates
  /// with similarity ≥ 0.6 sorted by descending similarity.
  Future<List<MatchCandidate>> _rankByImageHash(
    Uint8List bytes,
    List<_ScoredCandidate> shortlist,
  ) async {
    final source = img.decodeImage(bytes);
    if (source == null) return [];

    // Crop top 60% — artwork region only, avoids text area at the bottom
    final cropHeight = (source.height * 0.60).round();
    final cropped = img.copyCrop(
      source,
      x: 0,
      y: 0,
      width: source.width,
      height: cropHeight,
    );
    final croppedBytes = Uint8List.fromList(img.encodeJpg(cropped));
    final queryHash = ImageHashMatcher.instance.hashFromBytes(croppedBytes);
    if (queryHash == null) return [];

    final results = <MatchCandidate>[];

    for (final candidate in shortlist) {
      final refHash = await ImageHashMatcher.instance.hashFromAsset(
        candidate.imagePath,
      );
      if (refHash == null) continue;

      final sim = ImageHashMatcher.instance.similarity(queryHash, refHash);
      if (sim >= 0.6) {
        results.add(MatchCandidate(
          cardId: candidate.cardId,
          recordType: candidate.recordType,
          nameCn: candidate.nameCn,
          nameEn: candidate.nameEn,
          imagePath: candidate.imagePath,
          confidence: sim,
        ));
      }
    }

    results.sort((a, b) => b.confidence.compareTo(a.confidence));
    return results.take(5).toList();
  }
}