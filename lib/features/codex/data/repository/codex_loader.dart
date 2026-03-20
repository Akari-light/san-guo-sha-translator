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
    return all.where((e) => e.matchesQuery(q)).toList();
  }

  void clearCache() => _cache.clear();
}