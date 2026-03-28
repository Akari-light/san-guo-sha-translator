import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../models/general_card.dart';
import '../../../../core/models/skill_dto.dart';

class GeneralLoader {
  // ── Setup
  static final GeneralLoader _instance = GeneralLoader._internal();
  factory GeneralLoader() => _instance;
  GeneralLoader._internal();

  // ── Cache Data
  List<GeneralCard>? _cachedGenerals;
  Map<String, SkillDTO>? _cachedSkillMap;

  // ── Config
  /// To activate a file: uncomment its entry below.
  /// File is loaded as soon as it appears in this list.
  static const List<String> _expansionFiles = [
    'assets/data/generals/limit_break.json',
    'assets/data/generals/demon.json',
    'assets/data/generals/god.json',
    'assets/data/generals/standard.json',         // Uncomment when skill_type filled
    'assets/data/generals/myth_returns.json',      // Uncomment when skill_type filled
    'assets/data/generals/heroes_soul.json',       // Uncomment when skill_type filled
    // 'assets/data/generals/art_of_war.json',        // File not yet created
    'assets/data/generals/strategic_assault.json', // File not yet created
    'assets/data/generals/doudizhu.json',          // File not yet created
    'assets/data/generals/others.json',            // Uncomment when IDs/name_en filled
    // 'assets/data/generals/utilities.json',         // Tokens, markers, identity cards, HP cards
  ];


  static const String _skillsFile = 'assets/data/skills.json';

  // ── Public API
  Future<List<GeneralCard>> getGenerals() async {
    if (_cachedGenerals != null) return _cachedGenerals!;

    final skillMap = await _loadSkillMap();
    final generals = await _loadAllExpansions(skillMap);

    _cachedGenerals = generals;
    return generals;
  }

  Future<Map<String, SkillDTO>> getSkillMap() async {
    if (_cachedSkillMap != null) return _cachedSkillMap!;
    return _loadSkillMap();
  }

  Future<List<GeneralCard>> getVariants(String standardId) async {
    final all = await getGenerals();
    return all.where((g) => g.standardId == standardId).toList();
  }

  Future<List<GeneralCard>> getByFaction(String faction) async {
    final all = await getGenerals();
    return all.where((g) => g.faction == faction).toList();
  }

  Future<GeneralCard?> findById(String id) async {
    final all = await getGenerals();
    try {
      return all.firstWhere((g) => g.id == id);
    } catch (_) {
      return null;
    }
  }

  void clearCache() {
    _cachedGenerals = null;
    _cachedSkillMap = null;
  }

  // ── Private
  Future<Map<String, SkillDTO>> _loadSkillMap() async {
    if (_cachedSkillMap != null) return _cachedSkillMap!;

    try {
      final String response = await rootBundle.loadString(_skillsFile);
      final Map<String, dynamic> data = json.decode(response);

      _cachedSkillMap = data.map(
        (key, value) => MapEntry(
          key,
          SkillDTO.fromJson(key, value as Map<String, dynamic>),
        ),
      );

      return _cachedSkillMap!;
    } catch (e) {
      debugPrint('[GeneralLoader] Failed to load skills.json: $e');
      return {};
    }
  }

  Future<List<GeneralCard>> _loadAllExpansions(
    Map<String, SkillDTO> skillMap,
  ) async {
    final List<GeneralCard> all = [];

    for (final filePath in _expansionFiles) {
      try {
        final String response = await rootBundle.loadString(filePath);
        final List<dynamic> data = json.decode(response);

        final generals = data
            .map((json) => GeneralCard.fromJson(
                  json as Map<String, dynamic>,
                  skillMap,
                ))
            .toList();

        all.addAll(generals);
        debugPrint('[GeneralLoader] Loaded ${generals.length} generals from $filePath');
      } catch (e) {
        debugPrint('[GeneralLoader] Failed to load $filePath: $e');
      }
    }

    return all;
  }
}