import 'dart:async';

import '../services/pin_service.dart';
import '../services/recently_viewed_service.dart';
import '../../features/generals/data/models/general_card.dart';
import '../../features/generals/data/repository/general_loader.dart';
import '../../features/library/data/models/library_dto.dart';
import '../../features/library/data/repository/library_loader.dart';

// ── Result types 
class PinnedCards {
  final List<GeneralCard> generals;
  final List<LibraryDTO>  library;

  const PinnedCards({required this.generals, required this.library});

  bool get isEmpty => generals.isEmpty && library.isEmpty;
}

class RecentlyViewedCard {
  final RecordType   type;
  final GeneralCard? general;
  final LibraryDTO?  libraryCard;

  const RecentlyViewedCard._({
    required this.type,
    this.general,
    this.libraryCard,
  });

  factory RecentlyViewedCard.fromGeneral(GeneralCard card) =>
      RecentlyViewedCard._(type: RecordType.general, general: card);

  factory RecentlyViewedCard.fromLibrary(LibraryDTO card) =>
      RecentlyViewedCard._(type: RecordType.library, libraryCard: card);

  // Convenience accessors — always valid when accessed after checking [type].
  String get id        => general?.id        ?? libraryCard!.id;
  String get nameCn    => general?.nameCn    ?? libraryCard!.nameCn;
  String get nameEn    => general?.nameEn    ?? libraryCard!.nameEn;
  String get imagePath => general?.imagePath ?? libraryCard!.imagePath;

  bool get isGeneral => type == RecordType.general;
}

/// The full resolved recently-viewed list, most-recent first.
class RecentlyViewed {
  final List<RecentlyViewedCard> cards;

  const RecentlyViewed({required this.cards});

  bool get isEmpty    => cards.isEmpty;
  bool get isNotEmpty => cards.isNotEmpty;
}

// ── Service ────────────────────────────────────────────────────────────────
class HomeService {
  // ── Singleton
  static final HomeService instance = HomeService._();
  HomeService._();

  // ── Change streams ─────────────────────────────────────────────────────
  Stream<PinType> get changes => PinService.instance.changes;
  Stream<void> get recentChanges => RecentlyViewedService.instance.changes;

  // ── Pinned API
  Future<PinnedCards> getPinnedCards() async {
    final results = await Future.wait([
      PinService.instance.getPinnedIds(PinType.general),
      PinService.instance.getPinnedIds(PinType.library),
    ]);
    final generals = await _resolveGenerals(results[0]);
    final library  = await _resolveLibrary(results[1]);
    return PinnedCards(generals: generals, library: library);
  }

  /// Unpins a single general.
  Future<void> unpinGeneral(String id) =>
      PinService.instance.unpin(id, PinType.general);

  /// Unpins a single library card.
  Future<void> unpinLibrary(String id) =>
      PinService.instance.unpin(id, PinType.library);

  /// Clears all pins in both buckets.
  Future<void> clearAll() => PinService.instance.clearAll();

  // ── Recently Viewed API ────────────────────────────────────────────────
  Future<void> recordGeneralView(String id) =>
      RecentlyViewedService.instance.record(id, RecordType.general);

  Future<void> recordLibraryView(String id) =>
      RecentlyViewedService.instance.record(id, RecordType.library);

  Future<RecentlyViewed> getRecentlyViewed() async {
    final entries = await RecentlyViewedService.instance.getEntries();
    if (entries.isEmpty) return const RecentlyViewed(cards: []);

    // Load both data sets in parallel — both loaders are cached singletons.
    final results = await Future.wait([
      GeneralLoader().getGenerals(),
      LibraryLoader().getCards(),
    ]);
    final allGenerals = results[0] as List<GeneralCard>;
    final allLibrary  = results[1] as List<LibraryDTO>;

    // O(1) lookup maps to avoid O(n²) scanning.
    final generalMap = {for (final g in allGenerals) g.id: g};
    final libraryMap  = {for (final c in allLibrary)  c.id: c};

    final resolved = <RecentlyViewedCard>[];
    for (final entry in entries) {
      if (entry.type == RecordType.general) {
        final card = generalMap[entry.id];
        if (card != null) resolved.add(RecentlyViewedCard.fromGeneral(card));
      } else {
        final card = libraryMap[entry.id];
        if (card != null) resolved.add(RecentlyViewedCard.fromLibrary(card));
      }
    }
    return RecentlyViewed(cards: resolved);
  }

  /// Clears all recently-viewed records.
  Future<void> clearRecentlyViewed() =>
      RecentlyViewedService.instance.clearAll();

  // ── Lookup helpers 
  Future<GeneralCard?> findGeneralById(String id) =>
      GeneralLoader().findById(id);

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