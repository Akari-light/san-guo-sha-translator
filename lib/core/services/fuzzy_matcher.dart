// lib/core/services/fuzzy_matcher.dart
//
// FuzzyMatcher — high-performance fuzzy string matching utilities.
//
// Renamed from search_service.dart (v2.0 spec §9.1).
// The class performs fuzzy string matching, not "search" — the old name was
// misleading since the scanner, browse screens, and future features all use
// it for different purposes.
//
// Two public API tiers:
//   1. Bool API (unchanged) — fuzzyMatch() / fuzzyMatchAny()
//      Used by GeneralCard.matchesQuery() and LibraryDTO.matchesQuery()
//      for the browse/search feature.
//
//   2. Score API (NEW) — scannerFuzzyScore()
//      Returns a continuous [0.0, 1.0] match quality score for the scanner
//      hot path, where we need to distinguish "exact match" from "decent
//      fuzzy match" from "no match."
//
// Also exposes:
//   - levenshteinDistance() — edit distance between two strings
//   - trigramSimilarity()  — Dice coefficient on character trigrams
//   - hasCjk()             — CJK character detection
//
// All methods are static on an abstract final class — zero allocation,
// no instance state, tree-shakeable.

import 'dart:math' as math;

import 'package:lpinyin/lpinyin.dart';

abstract final class FuzzyMatcher {
  // ── Thresholds ────────────────────────────────────────────────────────────

  /// Minimum query length before fuzzy matching is attempted.
  /// Queries shorter than this use exact contains only — avoids false
  /// positives on single-character queries.
  static const int _fuzzyMinLength = 3;

  /// Minimum trigram similarity score (0.0 – 1.0) to count as a match.
  /// 0.25 is deliberately permissive — raise to 0.35 if too many false
  /// positives appear in practice.
  static const double _fuzzyThreshold = 0.25;

  // ════════════════════════════════════════════════════════════════════════════
  // TIER 1 — Bool API (backwards-compatible with old SearchService)
  // ════════════════════════════════════════════════════════════════════════════

  /// Returns true if [query] matches [target] via any of:
  ///   1. Exact substring match (fast path)
  ///   2. Pinyin conversion — converts Chinese [target] to tone-stripped
  ///      pinyin and compares against [query], so "sha" finds "杀" and
  ///      "liu bei" finds "刘备"
  ///   3. Trigram similarity — tolerates typos and partial matches
  ///      for queries of 3+ characters
  ///
  /// Both strings are lowercased before comparison.
  static bool fuzzyMatch(String query, String target) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase().trim();
    final t = target.toLowerCase();

    // 1. Fast path — exact substring
    if (t.contains(q)) return true;

    // 2. Pinyin path — only for targets containing CJK characters
    if (hasCjk(target)) {
      final pinyin = _toPinyin(target);
      if (pinyin.contains(q)) return true;

      final spacedPinyin = _toSpacedPinyin(target);
      if (spacedPinyin.contains(q)) return true;
    }

    // 3. Short queries: exact + pinyin only beyond this point
    if (q.length < _fuzzyMinLength) return false;

    // 4. Trigram fuzzy — handles typos and partial Latin matches
    if (trigramSimilarity(q, t) >= _fuzzyThreshold) return true;

    // 5. Trigram against spaced pinyin — e.g. typo "liu bai" still finds "刘备"
    if (hasCjk(target)) {
      final spacedPinyin = _toSpacedPinyin(target);
      if (trigramSimilarity(q, spacedPinyin) >= _fuzzyThreshold) return true;
    }

    return false;
  }

  /// Returns true if [query] matches ANY string in [targets].
  static bool fuzzyMatchAny(String query, Iterable<String> targets) {
    return targets.any((t) => fuzzyMatch(query, t));
  }

  // ════════════════════════════════════════════════════════════════════════════
  // TIER 2 — Score API (scanner hot path)
  // ════════════════════════════════════════════════════════════════════════════

  /// Returns a continuous match quality score ∈ [0.0, 1.0].
  ///
  /// Designed for the scanner hot path where we need to distinguish
  /// "perfect match" from "decent fuzzy match" from "no match."
  ///
  /// Scoring tiers (spec §5.2):
  ///   Exact substring match → 1.0
  ///   Levenshtein within tolerance → 0.6–1.0 (proportional to edit ratio)
  ///   Trigram similarity ≥ 0.40 → clamped to [0.6, 0.8]
  ///   Pinyin match → score × 0.8 discount
  ///   No match → 0.0
  static double scannerFuzzyScore(String ocrToken, String candidateName) {
    if (ocrToken.isEmpty || candidateName.isEmpty) return 0.0;

    final q = ocrToken.toLowerCase().trim();
    final t = candidateName.toLowerCase();

    // 1. Exact substring match (fast path)
    if (t.contains(q) || q.contains(t)) return 1.0;

    // 2. Levenshtein distance — allow 1 edit per 4 characters (25% error rate)
    final maxEdits = math.max(1, t.length ~/ 4);
    final dist = levenshteinDistance(q, t);
    if (dist <= maxEdits) {
      // Score degrades linearly with edits, floored at 0.6
      return math.max(0.6, 1.0 - (dist / t.length));
    }

    // 3. Trigram similarity — handles transpositions, radical swaps
    final triSim = trigramSimilarity(q, t);
    if (triSim >= 0.40) {
      return triSim.clamp(0.6, 0.8);
    }

    // 4. Pinyin fallback — CJK targets only, discounted
    if (hasCjk(candidateName)) {
      // No-space pinyin
      final pinyin = _toPinyin(candidateName);
      if (pinyin.contains(q) || q.contains(pinyin)) return 0.8;

      // Spaced pinyin
      final spacedPinyin = _toSpacedPinyin(candidateName);
      if (spacedPinyin.contains(q) || q.contains(spacedPinyin)) return 0.8;

      // Trigram against pinyin
      final pinyinSim = trigramSimilarity(q, spacedPinyin);
      if (pinyinSim >= 0.50) return (pinyinSim * 0.8).clamp(0.0, 0.8);
    }

    return 0.0;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PUBLIC UTILITIES
  // ════════════════════════════════════════════════════════════════════════════

  /// Returns true if [s] contains at least one CJK Unified Ideograph.
  static bool hasCjk(String s) {
    return s.runes.any((r) => r >= 0x4E00 && r <= 0x9FFF);
  }

  /// Levenshtein (edit) distance between two strings.
  ///
  /// Uses the standard Wagner–Fischer dynamic programming algorithm.
  /// O(n×m) time, O(min(n,m)) space via single-row optimisation.
  static int levenshteinDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    // Ensure a is the shorter string for O(min) space
    if (a.length > b.length) {
      final tmp = a;
      a = b;
      b = tmp;
    }

    final m = a.length;
    final n = b.length;

    // Single-row DP — prev[j] holds the cost for (i-1, j)
    var prev = List<int>.generate(m + 1, (j) => j);
    var curr = List<int>.filled(m + 1, 0);

    for (var i = 1; i <= n; i++) {
      curr[0] = i;
      for (var j = 1; j <= m; j++) {
        final cost = b.codeUnitAt(i - 1) == a.codeUnitAt(j - 1) ? 0 : 1;
        curr[j] = math.min(
          math.min(curr[j - 1] + 1, prev[j] + 1),
          prev[j - 1] + cost,
        );
      }
      // Swap rows
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }

    return prev[m];
  }

  /// Dice coefficient on character trigrams.
  /// Score = 2 × |intersection| / (|A| + |B|)
  /// Returns a value ∈ [0.0, 1.0].
  static double trigramSimilarity(String a, String b) {
    final triA = _trigrams(a);
    final triB = _trigrams(b);
    if (triA.isEmpty || triB.isEmpty) return 0.0;

    final mapB = <String, int>{};
    for (final t in triB) {
      mapB[t] = (mapB[t] ?? 0) + 1;
    }

    int shared = 0;
    final mapBCopy = Map<String, int>.from(mapB);
    for (final t in triA) {
      final count = mapBCopy[t] ?? 0;
      if (count > 0) {
        shared++;
        mapBCopy[t] = count - 1;
      }
    }

    return (2 * shared) / (triA.length + triB.length);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  /// Tone-stripped pinyin, no spaces between characters.
  /// "杀" → "sha"   "刘备" → "liebei"
  static String _toPinyin(String chinese) {
    return PinyinHelper.getPinyin(
      chinese,
      separator: '',
      format: PinyinFormat.WITHOUT_TONE,
    ).toLowerCase();
  }

  /// Tone-stripped pinyin with a space between each character's syllable.
  /// "刘备" → "liu bei"   "南蛮入侵" → "nan man ru qin"
  static String _toSpacedPinyin(String chinese) {
    return PinyinHelper.getPinyin(
      chinese,
      separator: ' ',
      format: PinyinFormat.WITHOUT_TONE,
    ).toLowerCase().trim();
  }

  /// Generates all overlapping trigrams from [s].
  /// Pads short strings so single/double-char inputs produce at least one
  /// trigram.
  static List<String> _trigrams(String s) {
    final padded = ' $s ';
    if (padded.length < 3) return [padded.padRight(3)];
    final result = <String>[];
    for (int i = 0; i <= padded.length - 3; i++) {
      result.add(padded.substring(i, i + 3));
    }
    return result;
  }
}