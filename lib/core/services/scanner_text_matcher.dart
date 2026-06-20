import 'dart:math' as math;

import 'fuzzy_matcher.dart';

abstract final class ScannerTextMatcher {
  static final RegExp _separatorRe = RegExp(r'[\s._\-:：·•,，]+');
  static final RegExp _idLikeRe = RegExp(
    r'(?:[A-Z]{1,4})?(?:WEI|SHU|WU|QUN|LE|GOD)[A-Z0-9]{2,8}(?:SKIN[0-9]+|BETA)?',
  );
  static final RegExp _suffixRe = RegExp(r'(WEI|SHU|WU|QUN|LE|GOD)[A-Z0-9]{2,5}$');

  static Set<String> extractPrintedIdCandidates(Iterable<String> rawLines) {
    final candidates = <String>{};
    final normalisedLines = rawLines
        .map(_normaliseOcrIdText)
        .where((line) => line.length >= 3)
        .toList(growable: false);

    for (final line in normalisedLines) {
      _addIdMatches(line, candidates);
    }

    for (var i = 0; i < normalisedLines.length; i++) {
      final buffer = StringBuffer(normalisedLines[i]);
      for (var j = i + 1; j < normalisedLines.length && j < i + 4; j++) {
        buffer.write(normalisedLines[j]);
        _addIdMatches(buffer.toString(), candidates);
      }
    }

    return candidates;
  }

  static double scoreIdEvidence({
    required String normalisedEntryId,
    required Set<String> printedIdCandidates,
  }) {
    if (normalisedEntryId.isEmpty || printedIdCandidates.isEmpty) {
      return 0.0;
    }

    final entryId = _normaliseEntryId(normalisedEntryId);
    final aliases = _entryIdAliases(entryId);
    var best = 0.0;

    for (final candidate in printedIdCandidates) {
      if (candidate == entryId) {
        best = math.max(best, 1.0);
        continue;
      }

      if (aliases.contains(candidate)) {
        best = math.max(best, candidate.contains('XXX') ? 0.74 : 0.84);
        continue;
      }

      for (final alias in aliases) {
        if (candidate.length >= 5 && alias.length >= 5) {
          final dist = FuzzyMatcher.levenshteinDistance(candidate, alias);
          if (dist == 1) {
            best = math.max(best, 0.82);
          } else if (dist == 2 && math.min(candidate.length, alias.length) >= 7) {
            best = math.max(best, 0.72);
          }
        }
      }
    }

    return best.clamp(0.0, 1.0);
  }

  static String _normaliseEntryId(String value) =>
      value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static String _normaliseOcrIdText(String value) {
    var out = value.toUpperCase().replaceAll(_separatorRe, '');
    out = out
        .replaceAll('Ｓ', 'S')
        .replaceAll('Ｐ', 'P')
        .replaceAll('Ｗ', 'W')
        .replaceAll('Ｅ', 'E')
        .replaceAll('Ｉ', 'I')
        .replaceAll('Ｏ', 'O')
        .replaceAll('Ｑ', 'Q')
        .replaceAll('Ｕ', 'U')
        .replaceAll('Ｎ', 'N');
    out = out.replaceAll(RegExp(r'[^A-Z0-9]'), '');

    final chars = out.split('');
    final digitStart = _idDigitStart(out);
    for (var i = 0; i < chars.length; i++) {
      if (i >= digitStart) {
        chars[i] = switch (chars[i]) {
          'O' => '0',
          'I' || 'L' => '1',
          'Z' => '2',
          'S' => '5',
          'B' => '8',
          _ => chars[i],
        };
      }
    }
    return chars.join();
  }

  static int _idDigitStart(String value) {
    var best = value.length;
    for (final faction in const ['WEI', 'SHU', 'QUN', 'GOD', 'WU', 'LE']) {
      final index = value.lastIndexOf(faction);
      if (index >= 0) {
        best = math.min(best, index + faction.length);
      }
    }
    return best;
  }

  static void _addIdMatches(String text, Set<String> candidates) {
    for (final match in _idLikeRe.allMatches(text)) {
      final value = match.group(0);
      if (value != null && value.length >= 5) {
        candidates.add(value);
      }
    }
  }

  static Set<String> _entryIdAliases(String normalisedEntryId) {
    final aliases = <String>{normalisedEntryId};
    final suffix = _suffixRe.firstMatch(normalisedEntryId)?.group(0);
    if (suffix != null) {
      aliases.add(suffix);
      if (suffix.contains(RegExp(r'\d'))) {
        aliases.add(suffix.replaceAll(RegExp(r'^GOD'), 'LE'));
      }
    }

    if (normalisedEntryId.startsWith('SPWEI') &&
        normalisedEntryId.substring(5).contains(RegExp(r'^\d+$'))) {
      aliases.add('SPWEIXXX');
    }
    return aliases;
  }
}
