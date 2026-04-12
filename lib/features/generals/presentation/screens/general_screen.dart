import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/models/expansion.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/recently_viewed_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/general_card.dart';
import '../../data/models/skin_dto.dart';
import '../../data/repository/general_loader.dart';
import '../../data/repository/skin_loader.dart';
import '../screens/general_detail_screen.dart';
import '../screens/general_filter_sheet.dart';
import '../widgets/general_card_tile.dart';

class GeneralScreen extends StatefulWidget {
  final ValueNotifier<String> searchNotifier;
  final void Function(bool isActive)? onFilterStateChanged;
  final void Function(VoidCallback openSheet)? onRegisterSheetOpener;
  final void Function(String libraryCardId)? onLibraryCardTap;
  final void Function(String id, RecordType type)? onCardTap;

  const GeneralScreen({
    super.key,
    required this.searchNotifier,
    this.onFilterStateChanged,
    this.onRegisterSheetOpener,
    this.onLibraryCardTap,
    this.onCardTap,
  });

  @override
  State<GeneralScreen> createState() => _GeneralScreenState();
}

class _GeneralScreenState extends State<GeneralScreen> {
  late final Future<_GeneralGalleryData> _galleryFuture;
  GeneralFilterState _filterState = const GeneralFilterState();

  static const List<String> _factionOrder = [
    'Shu',
    'Wei',
    'Wu',
    'Qun',
    'God',
    'Utilities',
  ];

  @override
  void initState() {
    super.initState();
    _galleryFuture = _loadGalleryData();
    widget.onRegisterSheetOpener?.call(_openFilterSheet);
  }

  @override
  void didUpdateWidget(GeneralScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onRegisterSheetOpener != oldWidget.onRegisterSheetOpener) {
      widget.onRegisterSheetOpener?.call(_openFilterSheet);
    }
  }

  void _openFilterSheet() {
    GeneralFilterSheet.show(
      context,
      initialState: _filterState,
      onChanged: (newState) {
        setState(() => _filterState = newState);
        widget.onFilterStateChanged?.call(newState.isActive);
      },
    );
  }

  Future<_GeneralGalleryData> _loadGalleryData() async {
    final results = await Future.wait<dynamic>([
      GeneralLoader().getGenerals(),
      SkinLoader().getAllSkins(),
      _loadBundledImageIds(),
    ]);

    final generals = results[0] as List<GeneralCard>;
    final skins = results[1] as List<SkinDTO>;
    final imageIds = results[2] as Set<String>;
    final generalIds = generals.map((g) => g.id).toSet();
    final skinsByBaseId = <String, List<SkinDTO>>{};

    for (final skin in skins) {
      final resolvedBaseId = _resolveSkinBaseId(skin, generalIds);
      skinsByBaseId.putIfAbsent(resolvedBaseId, () => []).add(skin);
    }
    for (final entry in skinsByBaseId.values) {
      entry.sort((a, b) => a.id.compareTo(b.id));
    }

    final knownImageIds = <String>{
      ...generalIds,
      ...skins.map((skin) => skin.id),
    };

    return _GeneralGalleryData(
      generals: generals,
      skinsByBaseId: skinsByBaseId,
      orphanImageIds: imageIds.difference(knownImageIds),
    );
  }

  Future<Set<String>> _loadBundledImageIds() async {
    final manifestRaw = await rootBundle.loadString('AssetManifest.json');
    final manifest = json.decode(manifestRaw) as Map<String, dynamic>;

    return manifest.keys
        .where(
          (path) =>
              path.startsWith('assets/images/generals/') &&
              path.endsWith('.webp'),
        )
        .map((path) => path.split('/').last.replaceFirst('.webp', ''))
        .toSet();
  }

  String _resolveSkinBaseId(SkinDTO skin, Set<String> generalIds) {
    if (generalIds.contains(skin.baseId)) {
      return skin.baseId;
    }

    final inferredBaseId = skin.id.replaceFirst(RegExp(r'_skin\d+$'), '');
    if (generalIds.contains(inferredBaseId)) {
      return inferredBaseId;
    }

    return skin.baseId;
  }

  bool get _hasRestrictiveFilters =>
      _filterState.factions.isNotEmpty ||
      _filterState.genders.isNotEmpty ||
      _filterState.expansions.isNotEmpty ||
      _filterState.lordOnly;

  List<_GeneralGalleryEntry> _buildGalleryEntries(
    List<GeneralCard> generals,
    Map<String, List<SkinDTO>> skinsByBaseId,
  ) {
    final entries = <_GeneralGalleryEntry>[];

    for (final general in generals) {
      entries.add(_GeneralGalleryEntry.base(general));
      for (final skin in skinsByBaseId[general.id] ?? const <SkinDTO>[]) {
        entries.add(_GeneralGalleryEntry.skin(general, skin));
      }
    }

    return entries;
  }

  List<_GeneralGalleryEntry> _buildOrphanEntries(
    Set<String> orphanImageIds,
    String query,
  ) {
    if (_hasRestrictiveFilters && query.trim().isEmpty) {
      return const [];
    }

    final ids = orphanImageIds.toList()..sort();
    return ids
        .map(_GeneralGalleryEntry.orphan)
        .where((entry) => entry.matchesQuery(query))
        .toList(growable: false);
  }

  Map<String, List<_GeneralGalleryEntry>> _groupByFaction(
    List<_GeneralGalleryEntry> entries,
  ) {
    final grouped = <String, List<_GeneralGalleryEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(entry.faction, () => []).add(entry);
    }

    final extraKeys = grouped.keys
        .where((key) => !_factionOrder.contains(key))
        .toList()
      ..sort();
    final orderedKeys = <String>[
      ..._factionOrder.where(grouped.containsKey),
      ...extraKeys,
    ];

    return Map.fromEntries(
      orderedKeys.map((key) => MapEntry(key, grouped[key]!)),
    );
  }

  void _openGalleryEntry(_GeneralGalleryEntry entry) {
    final card = entry.card;
    if (card == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${entry.imageId} is bundled but not mapped to general data yet.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (entry.initialSkinId != null) {
      RecentlyViewedService.instance.record(card.id, RecordType.general);
      Navigator.push(
        context,
        detailRoute(
          GeneralDetailScreen(
            card: card,
            initialSkinId: entry.initialSkinId,
            onLibraryCardTap: widget.onLibraryCardTap,
          ),
        ),
      );
      return;
    }

    if (widget.onCardTap != null) {
      widget.onCardTap!(card.id, RecordType.general);
      return;
    }

    Navigator.push(
      context,
      detailRoute(
        GeneralDetailScreen(
          card: card,
          onLibraryCardTap: widget.onLibraryCardTap,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: widget.searchNotifier,
      builder: (context, query, _) {
        return FutureBuilder<_GeneralGalleryData>(
          future: _galleryFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final galleryData = snapshot.data;
            if (galleryData == null) {
              return const Center(child: Text('Failed to load generals.'));
            }

            final filteredGenerals = _filterState.apply(galleryData.generals);
            final knownEntries = _buildGalleryEntries(
              filteredGenerals,
              galleryData.skinsByBaseId,
            ).where((entry) => entry.matchesQuery(query)).toList(growable: false);
            final orphanEntries = _buildOrphanEntries(
              galleryData.orphanImageIds,
              query,
            );
            final visibleEntries = <_GeneralGalleryEntry>[
              ...knownEntries,
              ...orphanEntries,
            ];
            final groupedEntries = _groupByFaction(visibleEntries);

            return CustomScrollView(
              slivers: [
                if (_filterState.isActive)
                  SliverToBoxAdapter(
                    child: _ActiveFilterBar(
                      filterState: _filterState,
                      onClear: () {
                        setState(() => _filterState = const GeneralFilterState());
                        widget.onFilterStateChanged?.call(false);
                      },
                    ),
                  ),
                if (visibleEntries.isEmpty)
                  const SliverFillRemaining(
                    child: Center(child: Text('No general art matches your search.')),
                  )
                else
                  for (final section in groupedEntries.entries) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 18,
                              decoration: BoxDecoration(
                                color: AppTheme.factionColor(section.key),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              section.key.toUpperCase(),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                    color: AppTheme.factionColor(section.key),
                                  ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${section.value.length}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Theme.of(context).hintColor),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.716,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final entry = section.value[index];
                            return GeneralCardTile(
                              imagePath: entry.imagePath,
                              faction: entry.faction,
                              expansionBadge: entry.expansionBadge,
                              isSkin: entry.isSkin,
                              isFallback: entry.isFallback,
                              onTap: () => _openGalleryEntry(entry),
                            );
                          },
                          childCount: section.value.length,
                        ),
                      ),
                    ),
                  ],
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            );
          },
        );
      },
    );
  }
}

class _ActiveFilterBar extends StatelessWidget {
  final GeneralFilterState filterState;
  final VoidCallback onClear;

  const _ActiveFilterBar({
    required this.filterState,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <String>[];

    if (filterState.factions.isNotEmpty) {
      parts.add(filterState.factions.join(', '));
    }
    if (filterState.genders.isNotEmpty) {
      parts.add(filterState.genders.join(', '));
    }
    if (filterState.expansions.isNotEmpty) {
      parts.add(filterState.expansions.map((e) => e.badge).join(', '));
    }
    if (filterState.lordOnly) {
      parts.add('Lord Only');
    }
    if (filterState.sortOrder != GeneralSortOrder.none) {
      parts.add(filterState.sortOrder.label);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.primary.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(Icons.filter_list, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              parts.join(' | '),
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: Icon(Icons.close, size: 16, color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }
}

class _GeneralGalleryData {
  final List<GeneralCard> generals;
  final Map<String, List<SkinDTO>> skinsByBaseId;
  final Set<String> orphanImageIds;

  const _GeneralGalleryData({
    required this.generals,
    required this.skinsByBaseId,
    required this.orphanImageIds,
  });
}

class _GeneralGalleryEntry {
  final String imageId;
  final String imagePath;
  final GeneralCard? card;
  final String faction;
  final String expansionBadge;
  final bool isSkin;
  final bool isFallback;
  final String? initialSkinId;
  final String? searchLabelEn;
  final String? searchLabelCn;

  const _GeneralGalleryEntry({
    required this.imageId,
    required this.imagePath,
    required this.card,
    required this.faction,
    required this.expansionBadge,
    required this.isSkin,
    required this.isFallback,
    this.initialSkinId,
    this.searchLabelEn,
    this.searchLabelCn,
  });

  factory _GeneralGalleryEntry.base(GeneralCard card) {
    return _GeneralGalleryEntry(
      imageId: card.id,
      imagePath: card.imagePath,
      card: card,
      faction: card.faction,
      expansionBadge: card.expansionBadge,
      isSkin: false,
      isFallback: false,
    );
  }

  factory _GeneralGalleryEntry.skin(GeneralCard card, SkinDTO skin) {
    return _GeneralGalleryEntry(
      imageId: skin.id,
      imagePath: skin.imagePath,
      card: card,
      faction: card.faction,
      expansionBadge: card.expansionBadge,
      isSkin: true,
      isFallback: false,
      initialSkinId: skin.id,
      searchLabelEn: skin.nameEn,
      searchLabelCn: skin.nameCn,
    );
  }

  factory _GeneralGalleryEntry.orphan(String imageId) {
    return _GeneralGalleryEntry(
      imageId: imageId,
      imagePath: 'assets/images/generals/$imageId.webp',
      card: null,
      faction: _inferFaction(imageId),
      expansionBadge: _inferExpansionBadge(imageId),
      isSkin: false,
      isFallback: true,
    );
  }

  bool matchesQuery(String query) {
    if (query.isEmpty) {
      return true;
    }
    if (card != null && card!.matchesQuery(query)) {
      return true;
    }

    final trimmed = query.trim();
    final lower = trimmed.toLowerCase();
    if (imageId.toLowerCase().contains(lower)) {
      return true;
    }
    if (searchLabelEn != null && searchLabelEn!.toLowerCase().contains(lower)) {
      return true;
    }
    if (searchLabelCn != null && searchLabelCn!.contains(trimmed)) {
      return true;
    }
    return false;
  }

  static String _inferFaction(String imageId) {
    final upper = imageId.toUpperCase();
    if (upper.contains('QUN')) {
      return 'Qun';
    }
    if (upper.contains('SHU')) {
      return 'Shu';
    }
    if (upper.contains('WEI')) {
      return 'Wei';
    }
    if (upper.contains('WU')) {
      return 'Wu';
    }
    if (upper.contains('GOD') || upper.startsWith('LE')) {
      return 'God';
    }
    return 'Utilities';
  }

  static String _inferExpansionBadge(String imageId) {
    final upper = imageId.toUpperCase();
    if (upper.startsWith('JX_')) {
      return Expansion.limitBreak.badge;
    }
    if (upper.startsWith('YJ_')) {
      return Expansion.heroesSoul.badge;
    }
    if (upper.startsWith('LE')) {
      return Expansion.god.badge;
    }
    if (upper.startsWith('MO_')) {
      return Expansion.demon.badge;
    }
    if (upper.startsWith('MG_')) {
      return Expansion.mouGong.badge;
    }
    if (upper.startsWith('DZ_')) {
      return Expansion.doudizhu.badge;
    }
    if (upper.startsWith('SP_') || upper.startsWith('WM_') || upper.startsWith('J_')) {
      return Expansion.other.badge;
    }
    return Expansion.standard.badge;
  }
}
