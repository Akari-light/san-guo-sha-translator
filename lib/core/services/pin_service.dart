import 'package:shared_preferences/shared_preferences.dart';

/// Use [PinService.instance] everywhere
class PinService {
  PinService._();
  static final PinService instance = PinService._();

  static const _key = 'pinned_generals';

  Future<List<String>> getPinnedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  Future<bool> isPinned(String id) async {
    final ids = await getPinnedIds();
    return ids.contains(id);
  }

  /// Returns the new pinned state (true = now pinned).
  Future<bool> toggle(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = List<String>.from(prefs.getStringList(_key) ?? []);
    final wasPinned = ids.contains(id);
    wasPinned ? ids.remove(id) : ids.add(id);
    await prefs.setStringList(_key, ids);
    return !wasPinned;
  }

  Future<void> unpin(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = List<String>.from(prefs.getStringList(_key) ?? []);
    ids.remove(id);
    await prefs.setStringList(_key, ids);
  }
}