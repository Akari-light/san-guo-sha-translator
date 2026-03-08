import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

/// The two pin buckets. Add more here if needed.
enum PinType { general, library }

/// Use [PinService.instance] everywhere.
///
/// Storage keys:
///   generals → 'pinned_generals'   (unchanged — no migration needed)
///   library  → 'pinned_library'    (new)
///
/// Live updates:
///   Listen to [PinService.instance.changes] to react to any pin/unpin
///   without polling. The stream emits the [PinType] that changed.
class PinService {
  PinService._();
  static final PinService instance = PinService._();

  static const _keyGenerals = 'pinned_generals';
  static const _keyLibrary  = 'pinned_library';

  // ── Change stream ─────────────────────────────────────────────────────────
  // Broadcast so multiple listeners (e.g. HomeScreen + a badge counter) can
  // subscribe independently without coordinating lifetimes.
  final _controller = StreamController<PinType>.broadcast();

  /// Emits the [PinType] bucket that changed whenever a pin/unpin/clear
  /// operation completes. Listen in initState, cancel in dispose.
  Stream<PinType> get changes => _controller.stream;

  void _notify(PinType type) => _controller.add(type);

  // ── Key helper ────────────────────────────────────────────────────────────
  String _key(PinType type) =>
      type == PinType.general ? _keyGenerals : _keyLibrary;

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<List<String>> getPinnedIds(PinType type) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key(type)) ?? [];
  }

  Future<bool> isPinned(String id, PinType type) async {
    final ids = await getPinnedIds(type);
    return ids.contains(id);
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Toggles pin state. Returns the new pinned state (true = now pinned).
  Future<bool> toggle(String id, PinType type) async {
    final prefs     = await SharedPreferences.getInstance();
    final ids       = List<String>.from(prefs.getStringList(_key(type)) ?? []);
    final wasPinned = ids.contains(id);
    wasPinned ? ids.remove(id) : ids.add(id);
    await prefs.setStringList(_key(type), ids);
    _notify(type);
    return !wasPinned;
  }

  Future<void> unpin(String id, PinType type) async {
    final prefs = await SharedPreferences.getInstance();
    final ids   = List<String>.from(prefs.getStringList(_key(type)) ?? []);
    ids.remove(id);
    await prefs.setStringList(_key(type), ids);
    _notify(type);
  }

  /// Clears all pins in both buckets at once.
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setStringList(_keyGenerals, []),
      prefs.setStringList(_keyLibrary,  []),
    ]);
    // Notify both buckets so any listener rebuilds correctly.
    _notify(PinType.general);
    _notify(PinType.library);
  }
}