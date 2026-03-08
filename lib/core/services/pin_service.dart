import 'package:shared_preferences/shared_preferences.dart';

/// The two pin buckets. Add more here if needed.
enum PinType { general, library }

/// Use [PinService.instance] everywhere.
///
/// Storage keys:
///   generals → 'pinned_generals'   (unchanged — no migration needed)
///   library  → 'pinned_library'    (new)
class PinService {
  PinService._();
  static final PinService instance = PinService._();

  static const _keyGenerals = 'pinned_generals';
  static const _keyLibrary  = 'pinned_library';

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
    return !wasPinned;
  }

  Future<void> unpin(String id, PinType type) async {
    final prefs = await SharedPreferences.getInstance();
    final ids   = List<String>.from(prefs.getStringList(_key(type)) ?? []);
    ids.remove(id);
    await prefs.setStringList(_key(type), ids);
  }
}