import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Entry type ─────────────────────────────────────────────────────────────

/// Which feature bucket a recently-viewed entry belongs to.
enum RecordType { general, library }

/// A single recently-viewed record as persisted in SharedPreferences.
///
/// Stored as JSON: {"id":"jx.SHU001","type":"general","ts":1718000000000}
class RecentlyViewedEntry {
  final String id;
  final RecordType type;
  final DateTime viewedAt;

  const RecentlyViewedEntry({
    required this.id,
    required this.type,
    required this.viewedAt,
  });

  factory RecentlyViewedEntry.fromJson(Map<String, dynamic> json) =>
      RecentlyViewedEntry(
        id:       json['id'] as String,
        type:     json['type'] == 'library'
                    ? RecordType.library
                    : RecordType.general,
        viewedAt: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
      );

  Map<String, dynamic> toJson() => {
    'id':   id,
    'type': type == RecordType.library ? 'library' : 'general',
    'ts':   viewedAt.millisecondsSinceEpoch,
  };
}

// ── Service ────────────────────────────────────────────────────────────────

/// Persists a capped, deduplicating list of recently-viewed card IDs.
///
/// Rules:
///   • Stores at most [maxEntries] records (oldest dropped when full).
///   • Recording an ID already in the list moves it to the front — no dupes.
///   • Emits on [changes] after every successful write.
///
/// This service is feature-agnostic — it stores only primitive IDs and
/// [RecordType]. Resolution into typed card objects is done by [HomeService],
/// which is the only layer permitted to cross feature data-layer boundaries.
///
/// Call sites:
///   • main.dart  — calls [record] via HomeService before every push.
///   • home_service.dart — calls [getEntries] / [clearAll].
class RecentlyViewedService {
  // ── Singleton
  static final RecentlyViewedService instance = RecentlyViewedService._();
  RecentlyViewedService._();

  static const _prefsKey  = 'recently_viewed';
  static const maxEntries = 20;

  // ── Change stream ────────────────────────────────────────────────────────
  /// Fires (void) after every successful write so listeners can reload.
  final _controller = StreamController<void>.broadcast();
  Stream<void> get changes => _controller.stream;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns all stored entries, most-recent first.
  Future<List<RecentlyViewedEntry>> getEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw) as List<dynamic>;
      return list
          .map((e) => RecentlyViewedEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Corrupt data — reset silently rather than crash.
      debugPrint('[RecentlyViewedService] corrupt data, resetting: $e');
      await prefs.remove(_prefsKey);
      return [];
    }
  }

  /// Records a view. If [id]+[type] already exists it is moved to the front.
  /// Trims the list to [maxEntries] after inserting.
  Future<void> record(String id, RecordType type) async {
    final prefs   = await SharedPreferences.getInstance();
    final entries = await getEntries();

    // Deduplication — remove existing entry so it can be reinserted at front.
    entries.removeWhere((e) => e.id == id && e.type == type);

    entries.insert(
      0,
      RecentlyViewedEntry(id: id, type: type, viewedAt: DateTime.now()),
    );

    final capped = entries.take(maxEntries).toList();
    await prefs.setString(
      _prefsKey,
      json.encode(capped.map((e) => e.toJson()).toList()),
    );
    _controller.add(null);
  }

  /// Clears all recently-viewed records.
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    _controller.add(null);
  }
}