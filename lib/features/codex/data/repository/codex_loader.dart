// lib/features/codex/data/repository/codex_loader.dart

import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/codex_entry_dto.dart';

class _Chapter {
  final String key;
  final String filename;
  const _Chapter(this.key, this.filename);
}

const _kChapters = [
  _Chapter('setup',    'setup'),
  _Chapter('glossary', 'glossary'),
  _Chapter('flow',     'flow'),
  _Chapter('rules',    'rules'),
];

class CodexLoader {
  CodexLoader._();
  static final CodexLoader instance = CodexLoader._();

  final Map<String, List<CodexEntryDTO>> _cache = {};

  Future<List<CodexEntryDTO>> _load(_Chapter ch) async {
    if (_cache.containsKey(ch.key)) return _cache[ch.key]!;
    final raw = await rootBundle
        .loadString('assets/data/ruleset/${ch.filename}.json');
    final entries = (jsonDecode(raw) as List<dynamic>)
        .map((e) => CodexEntryDTO.fromJson(e as Map<String, dynamic>, ch.key))
        .toList();
    _cache[ch.key] = entries;
    return entries;
  }

  Future<List<CodexEntryDTO>> getChapter(String key) async {
    final ch = _kChapters.firstWhere((c) => c.key == key);
    return _load(ch);
  }

  Future<List<CodexEntryDTO>> getAll() async {
    final results = await Future.wait(_kChapters.map(_load));
    return results.expand((l) => l).toList();
  }

  // Live search called on every keystroke.
  // Future vector search: replace this body only — callers unchanged.
  Future<List<CodexEntryDTO>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    final all = await getAll();
    final q = query.trim().toLowerCase();
    final matches = all.where((e) => e.matchesQuery(q)).toList();
    matches.sort((a, b) => _scoreEntry(b, q).compareTo(_scoreEntry(a, q)));
    return matches;
  }

  int _scoreEntry(CodexEntryDTO entry, String query) {
    var score = 0;

    final termCn = entry.termCn.toLowerCase();
    final termEn = entry.termEn.toLowerCase();
    final titleCn = entry.sectionTitleCn.toLowerCase();
    final titleEn = entry.sectionTitleEn.toLowerCase();
    final searchCn = entry.searchTextCn.toLowerCase();
    final searchEn = entry.searchTextEn.toLowerCase();

    if (termCn == query || termEn == query) score += 120;
    if (termCn.startsWith(query) || termEn.startsWith(query)) score += 80;
    if (termCn.contains(query) || termEn.contains(query)) score += 45;
    if (titleCn.contains(query) || titleEn.contains(query)) score += 20;
    if (searchCn.contains(query) || searchEn.contains(query)) score += 10;

    score += switch (entry.chapter) {
      'glossary' => 8,
      'setup' => 4,
      'flow' => 2,
      _ => 0,
    };

    return score;
  }

  void clearCache() => _cache.clear();
}
