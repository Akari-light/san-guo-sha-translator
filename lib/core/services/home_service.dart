import 'dart:async';

import '../services/pin_service.dart';
import '../../features/generals/data/models/general_card.dart';
import '../../features/generals/data/repository/general_loader.dart';
import '../../features/library/data/models/library_dto.dart';
import '../../features/library/data/repository/library_loader.dart';

// ── Result type
class PinnedCards {
  final List<GeneralCard> generals;
  final List<LibraryDTO>  library;

  const PinnedCards({
    required this.generals,
    required this.library,
  });

  bool get isEmpty => generals.isEmpty && library.isEmpty;
}

// ── Service
class HomeService {
  static final HomeService instance = HomeService._();
  HomeService._();

  Stream<PinType> get changes => PinService.instance.changes;

  // ── Public API
  Future<PinnedCards> getPinnedCards() async {
    final results = await Future.wait([
      PinService.instance.getPinnedIds(PinType.general),
      PinService.instance.getPinnedIds(PinType.library),
    ]);

    final generals = await _resolveGenerals(results[0]);
    final library  = await _resolveLibrary(results[1]);

    return PinnedCards(generals: generals, library: library);
  }

  // Unpins a single general.
  Future<void> unpinGeneral(String id) =>
      PinService.instance.unpin(id, PinType.general);

  // Unpins a single library card.
  Future<void> unpinLibrary(String id) =>
      PinService.instance.unpin(id, PinType.library);

  // Clears all pins in both buckets.
  Future<void> clearAll() => PinService.instance.clearAll();

  // Looks up a single general by ID. Used by main.dart to resolve
  // a tapped general ID into a card object before pushing the detail screen.
  Future<GeneralCard?> findGeneralById(String id) =>
      GeneralLoader().findById(id);

  // Looks up a single library card by ID. Used by main.dart to resolve
  // a tapped library ID into a card object before pushing the detail screen.
  Future<LibraryDTO?> findLibraryById(String id) =>
      LibraryLoader().findById(id);

  // ── Private
  Future<List<GeneralCard>> _resolveGenerals(List<String> ids) async {
    if (ids.isEmpty) return [];
    final all = await GeneralLoader().getGenerals();
    return ids
        .map((id) => all.where((g) => g.id == id).firstOrNull)
        .whereType<GeneralCard>()
        .toList();
  }

  Future<List<LibraryDTO>> _resolveLibrary(List<String> ids) async {
    if (ids.isEmpty) return [];
    final all = await LibraryLoader().getCards();
    return ids
        .map((id) => all.where((c) => c.id == id).firstOrNull)
        .whereType<LibraryDTO>()
        .toList();
  }
}