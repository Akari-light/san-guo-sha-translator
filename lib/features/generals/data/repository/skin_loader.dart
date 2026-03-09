import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../models/skin_dto.dart';

/// Loads and caches skin (alt-art) entries from assets/data/generals/skin.json.
class SkinLoader {
  // ── Singleton
  static final SkinLoader _instance = SkinLoader._internal();
  factory SkinLoader() => _instance;
  SkinLoader._internal();

  static const String _skinFile = 'assets/data/generals/skin.json';

  List<SkinDTO>? _cache;

  // ── Public API
  Future<List<SkinDTO>> getSkinsForBase(String baseId) async {
    final all = await _loadAll();
    return all.where((s) => s.baseId == baseId).toList();
  }

  void clearCache() => _cache = null;

  // ── Private
  Future<List<SkinDTO>> _loadAll() async {
    if (_cache != null) return _cache!;

    try {
      final String response = await rootBundle.loadString(_skinFile);
      final List<dynamic> data = json.decode(response);
      _cache = data
          .map((e) => SkinDTO.fromJson(e as Map<String, dynamic>))
          .toList();
      debugPrint('[SkinLoader] Loaded ${_cache!.length} skins');
    } catch (e) {
      debugPrint('[SkinLoader] Failed to load skin.json: $e');
      _cache = [];
    }

    return _cache!;
  }
}