import 'package:lpinyin/lpinyin.dart';

/// SearchService — fuzzy text search utilities.
///
/// Phase 1: Trigram-based fuzzy matching + pinyin conversion via lpinyin.
/// Phase 2 (future): Vector/semantic search against pre-computed embeddings.
///
/// Usage — call [fuzzyMatch] directly in model matchesQuery() methods:
///   SearchService.fuzzyMatch('liu bei', '刘备')      // → true (pinyin)
///   SearchService.fuzzyMatch('sha', '杀')            // → true (pinyin)
///   SearchService.fuzzyMatch('benev', 'Benevolence') // → true (trigram)
///   SearchService.fuzzyMatch('luu bei', 'Liu Bei')   // → true (typo tolerance)
abstract final class SearchService {
  // ── Thresholds ────────────────────────────────────────────────────────────

  /// Minimum query length before fuzzy matching is attempted.
  /// Queries shorter than this use exact contains only — avoids false
  /// positives on single-character queries.
  static const int _fuzzyMinLength = 3;

  /// Minimum trigram similarity score (0.0 – 1.0) to count as a match.
  /// 0.25 is deliberately permissive — raise to 0.35 if too many false
  /// positives appear in practice.
  static const double _fuzzyThreshold = 0.25;

  // ── Public API ────────────────────────────────────────────────────────────

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
    if (query.isEmpty) { return true; }
    final q = query.toLowerCase().trim();
    final t = target.toLowerCase();

    // 1. Fast path — exact substring
    if (t.contains(q)) { return true; }

    // 2. Pinyin path — only for targets containing CJK characters
    if (_hasCjk(target)) {
      // No-space pinyin: "杀" → "sha", "刘备" → "liebei"
      final pinyin = _toPinyin(target);
      if (pinyin.contains(q)) { return true; }

      // Spaced pinyin: "刘备" → "liu bei", "南蛮入侵" → "nan man ru qin"
      final spacedPinyin = _toSpacedPinyin(target);
      if (spacedPinyin.contains(q)) { return true; }
    }

    // 3. Short queries: exact + pinyin only beyond this point
    if (q.length < _fuzzyMinLength) { return false; }

    // 4. Trigram fuzzy — handles typos and partial Latin matches
    if (_trigramSimilarity(q, t) >= _fuzzyThreshold) { return true; }

    // 5. Trigram against spaced pinyin — e.g. typo "liu bai" still finds "刘备"
    if (_hasCjk(target)) {
      final spacedPinyin = _toSpacedPinyin(target);
      if (_trigramSimilarity(q, spacedPinyin) >= _fuzzyThreshold) { return true; }
    }

    return false;
  }

  /// Returns true if [query] matches ANY string in [targets].
  static bool fuzzyMatchAny(String query, Iterable<String> targets) {
    return targets.any((t) => fuzzyMatch(query, t));
  }

  // ── Pinyin helpers ────────────────────────────────────────────────────────

  /// Returns true if [s] contains at least one CJK Unified Ideograph.
  static bool _hasCjk(String s) {
    return s.runes.any((r) => r >= 0x4E00 && r <= 0x9FFF);
  }

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

  // ── Trigram engine ────────────────────────────────────────────────────────

  /// Dice coefficient on character trigrams.
  /// Score = 2 * |intersection| / (|A| + |B|)
  static double _trigramSimilarity(String a, String b) {
    final triA = _trigrams(a);
    final triB = _trigrams(b);
    if (triA.isEmpty || triB.isEmpty) { return 0.0; }

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

  /// Generates all overlapping trigrams from [s].
  /// Pads short strings so single/double-char inputs produce at least one trigram.
  static List<String> _trigrams(String s) {
    final padded = ' $s ';
    if (padded.length < 3) { return [padded.padRight(3)]; }
    final result = <String>[];
    for (int i = 0; i <= padded.length - 3; i++) {
      result.add(padded.substring(i, i + 3));
    }
    return result;
  }
}