import 'package:flutter/material.dart';

import '../../../../core/services/fuzzy_matcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../generals/data/models/general_card.dart';
import '../../../generals/data/models/skin_dto.dart';
import '../../../generals/data/repository/general_loader.dart';
import '../../../generals/data/repository/skin_loader.dart';
import '../../../generals/presentation/screens/general_filter_sheet.dart';
import '../../../generals/presentation/widgets/general_card_tile.dart';
import '../../domain/models/pending_session_selection.dart';

class GameSessionGeneralPickerScreen extends StatefulWidget {
  const GameSessionGeneralPickerScreen({super.key});

  @override
  State<GameSessionGeneralPickerScreen> createState() =>
      _GameSessionGeneralPickerScreenState();
}

class _GameSessionGeneralPickerScreenState
    extends State<GameSessionGeneralPickerScreen> {
  late final Future<_GeneralGalleryData> _galleryFuture;
  final TextEditingController _queryController = TextEditingController();
  GeneralFilterState _filterState = const GeneralFilterState();
  String _query = '';

  static const List<String> _factionOrder = <String>[
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
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<_GeneralGalleryData> _loadGalleryData() async {
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      GeneralLoader().getGenerals(),
      SkinLoader().getAllSkins(),
    ]);

    final generals = results[0] as List<GeneralCard>;
    final skins = results[1] as List<SkinDTO>;
    final generalIds = generals.map((general) => general.id).toSet();
    final skinsByBaseId = <String, List<SkinDTO>>{};

    for (final skin in skins) {
      final resolvedBaseId = _resolveSkinBaseId(skin, generalIds);
      skinsByBaseId.putIfAbsent(resolvedBaseId, () => <SkinDTO>[]).add(skin);
    }

    for (final entry in skinsByBaseId.values) {
      entry.sort((a, b) => a.id.compareTo(b.id));
    }

    return _GeneralGalleryData(
      generals: generals,
      skinsByBaseId: skinsByBaseId,
    );
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

  bool _shouldUseIdOnlySearch(
    String query,
    List<_GeneralGalleryEntry> entries,
  ) {
    final q = query.trim().toLowerCase();
    if (!_isIdStyleQuery(q)) {
      return false;
    }

    return entries.any((entry) => entry.imageId.toLowerCase().contains(q));
  }

  bool _isIdStyleQuery(String q) =>
      q.isNotEmpty &&
      !q.contains(RegExp(r'\s')) &&
      !FuzzyMatcher.hasCjk(q) &&
      RegExp(r'^[a-z0-9_-]+$').hasMatch(q);

  Map<String, List<_GeneralGalleryEntry>> _groupByFaction(
    List<_GeneralGalleryEntry> entries,
  ) {
    final grouped = <String, List<_GeneralGalleryEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(entry.faction, () => <_GeneralGalleryEntry>[])
          .add(entry);
    }

    final extraKeys = grouped.keys
        .where((key) => !_factionOrder.contains(key))
        .toList()
      ..sort();
    final orderedKeys = <String>[
      ..._factionOrder.where(grouped.containsKey),
      ...extraKeys,
    ];

    return Map<String, List<_GeneralGalleryEntry>>.fromEntries(
      orderedKeys.map((key) => MapEntry<String, List<_GeneralGalleryEntry>>(
            key,
            grouped[key]!,
          )),
    );
  }

  void _openFilterSheet() {
    GeneralFilterSheet.show(
      context,
      initialState: _filterState,
      onChanged: (newState) {
        setState(() => _filterState = newState);
      },
    );
  }

  void _selectEntry(_GeneralGalleryEntry entry) {
    final card = entry.card;
    if (card == null) return;
    Navigator.of(context).pop(
      PendingSessionSelection(
        generalId: card.id,
        skinId: entry.initialSkinId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set My General'),
        actions: [
          IconButton(
            tooltip: 'Filter generals',
            onPressed: _openFilterSheet,
            icon: Icon(
              Icons.tune_rounded,
              color: _filterState.isActive
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ),
        ],
      ),
      body: FutureBuilder<_GeneralGalleryData>(
        future: _galleryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return const Center(
              child: Text('Failed to load generals for this room.'),
            );
          }

          final galleryData = snapshot.data!;
          final filteredGenerals = _filterState.apply(galleryData.generals);
          final allEntries = _buildGalleryEntries(
            filteredGenerals,
            galleryData.skinsByBaseId,
          );
          final preferIdOnlySearch = _shouldUseIdOnlySearch(_query, allEntries);
          final visibleEntries = allEntries
              .where(
                (entry) => entry.matchesQuery(
                  _query,
                  preferIdOnlySearch: preferIdOnlySearch,
                ),
              )
              .toList(growable: false);
          final groupedEntries = _groupByFaction(visibleEntries);

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _queryController,
                        onChanged: (value) => setState(() => _query = value),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search generals, skins, or IDs',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _queryController.clear();
                                    setState(() => _query = '');
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Choose a general or skin. Tapping a card sets it for this room instead of opening details.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              if (_filterState.isActive)
                SliverToBoxAdapter(
                  child: _ActiveFilterBar(
                    filterState: _filterState,
                    onClear: () {
                      setState(() => _filterState = const GeneralFilterState());
                    },
                  ),
                ),
              if (visibleEntries.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Text('No generals match this room search.'),
                  ),
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
                            isFallback: false,
                            onTap: () => _selectEntry(entry),
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
      ),
    );
  }
}

class _ActiveFilterBar extends StatelessWidget {
  const _ActiveFilterBar({
    required this.filterState,
    required this.onClear,
  });

  final GeneralFilterState filterState;
  final VoidCallback onClear;

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
            child:
                Icon(Icons.close, size: 16, color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }
}

class _GeneralGalleryData {
  const _GeneralGalleryData({
    required this.generals,
    required this.skinsByBaseId,
  });

  final List<GeneralCard> generals;
  final Map<String, List<SkinDTO>> skinsByBaseId;
}

class _GeneralGalleryEntry {
  const _GeneralGalleryEntry({
    required this.imageId,
    required this.imagePath,
    required this.card,
    required this.faction,
    required this.expansionBadge,
    required this.isSkin,
    this.initialSkinId,
    this.searchLabelEn,
    this.searchLabelCn,
  });

  final String imageId;
  final String imagePath;
  final GeneralCard? card;
  final String faction;
  final String expansionBadge;
  final bool isSkin;
  final String? initialSkinId;
  final String? searchLabelEn;
  final String? searchLabelCn;

  factory _GeneralGalleryEntry.base(GeneralCard card) {
    return _GeneralGalleryEntry(
      imageId: card.id,
      imagePath: card.imagePath,
      card: card,
      faction: card.faction,
      expansionBadge: card.expansionBadge,
      isSkin: false,
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
      initialSkinId: skin.id,
      searchLabelEn: skin.nameEn,
      searchLabelCn: skin.nameCn,
    );
  }

  bool matchesQuery(
    String query, {
    required bool preferIdOnlySearch,
  }) {
    if (query.isEmpty) {
      return true;
    }

    final trimmed = query.trim();
    final lower = trimmed.toLowerCase();
    if (preferIdOnlySearch) {
      return imageId.toLowerCase().contains(lower);
    }

    if (card != null) {
      if (_matchesDisplayLabel(trimmed, card!.nameEn)) {
        return true;
      }
      if (_matchesDisplayLabel(trimmed, card!.nameCn)) {
        return true;
      }
    }

    if (imageId.toLowerCase().contains(lower)) {
      return true;
    }
    if (_matchesDisplayLabel(trimmed, searchLabelEn)) {
      return true;
    }
    if (_matchesDisplayLabel(trimmed, searchLabelCn)) {
      return true;
    }
    return false;
  }

  static bool _matchesDisplayLabel(String query, String? target) {
    if (target == null || target.isEmpty) {
      return false;
    }

    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return true;
    }

    final lowerQuery = trimmedQuery.toLowerCase();
    final lowerTarget = target.toLowerCase();
    if (lowerTarget.contains(lowerQuery)) {
      return true;
    }

    final compactQuery = _compactAscii(lowerQuery);
    if (compactQuery.isEmpty) {
      return false;
    }

    final compactTarget = _compactAscii(lowerTarget);
    return compactTarget.contains(compactQuery);
  }

  static String _compactAscii(String value) =>
      value.replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '');
}
