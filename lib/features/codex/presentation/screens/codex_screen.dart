// lib/features/codex/presentation/screens/codex_screen.dart
//
// Codex tab body — NOT a Scaffold. Mounted by main.dart as:
//   _screens[0] = CodexScreen(
//     searchNotifier:   _codexSearchNotifier,
//     showChineseNotifier: _codexLangNotifier,
//   )
//
// main.dart owns the AppBar (title TextField + search icon + lang toggle
// action). This widget owns only the chapter tab bar and the content below it.
// This is identical in structure to GeneralScreen and LibraryScreen.

import 'package:flutter/material.dart';
import '../../data/models/codex_entry_dto.dart';
import '../../data/repository/codex_loader.dart';
import '../codex_chapter_config.dart';
import '../widgets/codex_section_tile.dart';
import '../widgets/codex_entry_card.dart';
import '../widgets/codex_flow_step_tile.dart';
import 'codex_entry_screen.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/theme/app_theme.dart';

class CodexScreen extends StatefulWidget {
  /// Live search query — updated by main.dart AppBar TextField.
  /// Same pattern as GeneralScreen.searchNotifier.
  final ValueNotifier<String> searchNotifier;

  /// Lang toggle state — updated by main.dart AppBar action button.
  /// false = EN primary, true = 中文 primary.
  final ValueNotifier<bool> showChineseNotifier;

  const CodexScreen({
    super.key,
    required this.searchNotifier,
    required this.showChineseNotifier,
  });

  @override
  State<CodexScreen> createState() => _CodexScreenState();
}

class _CodexScreenState extends State<CodexScreen>
    with SingleTickerProviderStateMixin {

  late final TabController _tabController;
  int _activeChapterIndex = 1; // default: Glossary

  // Per-chapter data cache
  final Map<String, List<CodexEntryDTO>> _data = {};
  final Map<String, bool> _loading = {};

  // Search results (cross-chapter, driven by searchNotifier)
  List<CodexEntryDTO> _searchResults = [];
  bool _searchLoading = false;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: kCodexChapters.length,
      vsync: this,
      initialIndex: _activeChapterIndex,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _activeChapterIndex = _tabController.index;
        _loadChapter(kCodexChapters[_tabController.index].key);
      }
    });
    widget.searchNotifier.addListener(_onSearchChanged);
    _loadChapter(kCodexChapters[_activeChapterIndex].key);
  }

  @override
  void didUpdateWidget(CodexScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchNotifier != oldWidget.searchNotifier) {
      oldWidget.searchNotifier.removeListener(_onSearchChanged);
      widget.searchNotifier.addListener(_onSearchChanged);
    }
  }

  @override
  void dispose() {
    widget.searchNotifier.removeListener(_onSearchChanged);
    _tabController.dispose();
    super.dispose();
  }

  // ── Data loading ───────────────────────────────────────────────────────────

  Future<void> _loadChapter(String key) async {
    if (_data.containsKey(key) || _loading[key] == true) return;
    setState(() => _loading[key] = true);
    try {
      final entries = await CodexLoader.instance.getChapter(key);
      if (mounted) setState(() => _data[key] = entries);
    } finally {
      if (mounted) setState(() => _loading[key] = false);
    }
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  void _onSearchChanged() {
    final query = widget.searchNotifier.value;
    if (query == _lastQuery) return;
    _lastQuery = query;

    if (query.trim().isEmpty) {
      if (mounted) setState(() { _searchResults = []; _searchLoading = false; });
      return;
    }

    // Eagerly load all chapters so search is complete
    for (final ch in kCodexChapters) {
      _loadChapter(ch.key);
    }

    if (mounted) setState(() => _searchLoading = true);
    CodexLoader.instance.search(query).then((results) {
      if (mounted && widget.searchNotifier.value == query) {
        setState(() {
          _searchResults  = results;
          _searchLoading  = false;
        });
      }
    });
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _openEntry(CodexEntryDTO entry) {
    Navigator.of(context).push(detailRoute(
      CodexEntryScreen(
        entry: entry,
        showChinese: widget.showChineseNotifier.value,
      ),
    ));
  }

  // ── Section grouping ───────────────────────────────────────────────────────

  Map<String, List<CodexEntryDTO>> _groupBySection(List<CodexEntryDTO> entries) {
    final map = <String, List<CodexEntryDTO>>{};
    for (final e in entries) {
      // Composite key: sectionNum|titleCn|titleEn prevents §1.1 entries with
      // different section_title_en from collapsing into one group.
      final key = '${e.sectionNum}|${e.sectionTitleCn}|${e.sectionTitleEn}';
      map.putIfAbsent(key, () => []).add(e);
    }
    return map;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<String>(
      valueListenable: widget.searchNotifier,
      builder: (context, query, _) {
        final isSearching = query.trim().isNotEmpty;
        return ValueListenableBuilder<bool>(
          valueListenable: widget.showChineseNotifier,
          builder: (context, showChinese, _) {
            return Column(
              children: [
                // Chapter tab bar — hidden when searching (same as Generals
                // hiding faction headers when a search query is active)
                if (!isSearching)
                  _buildTabBar(isDark, showChinese),

                // Content
                Expanded(
                  child: isSearching
                      ? _buildSearchResults(isDark, showChinese, query)
                      : TabBarView(
                          controller: _tabController,
                          children: kCodexChapters
                              .map((ch) =>
                                  _buildChapterView(ch.key, isDark, showChinese))
                              .toList(),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── Chapter tab bar ────────────────────────────────────────────────────────

  Widget _buildTabBar(bool isDark, bool showChinese) {
    return ColoredBox(
      color: AppTheme.codexSectionHeaderBg(isDark),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // AnimatedBuilder on _tabController ensures the tab bar rebuilds on
          // every animation frame while swiping/tapping, keeping the indicator
          // color and active text weight correct at all times.
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              final activeIndex = _tabController.index;
              return TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                padding: const EdgeInsets.only(left: 4),
                labelPadding: const EdgeInsets.symmetric(horizontal: 15),
                indicator: _ChapterIndicator(
                  color: AppTheme.codexChapterAccent(
                      kCodexChapters[activeIndex].key, isDark),
                ),
                tabs: kCodexChapters.asMap().entries.map((e) {
                  final i      = e.key;
                  final ch     = e.value;
                  final active = activeIndex == i;
                  final accent = AppTheme.codexChapterAccent(ch.key, isDark);
                  return Tab(
                    height: 46,
                    child: Text(
                      showChinese ? ch.labelCn : ch.labelEn,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                        color: active
                            ? accent
                            : AppTheme.codexSecondaryText(isDark),
                      ),
                    ),
                  );
                }).toList(),
                onTap: (i) {
                  _activeChapterIndex = i;
                  _loadChapter(kCodexChapters[i].key);
                },
              );
            },
          ),
          Divider(
              height: 1,
              thickness: 1,
              color: AppTheme.codexDivider(isDark)),
        ],
      ),
    );
  }

  // ── Chapter browse view ────────────────────────────────────────────────────

  Widget _buildChapterView(String key, bool isDark, bool showChinese) {
    final entries = _data[key];
    if (_loading[key] == true && entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (entries == null || entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final isFlow  = key == 'flow';
    final grouped = _groupBySection(entries);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: grouped.length,
      itemBuilder: (context, i) {
        final sectionKey = grouped.keys.elementAt(i);
        final parts = sectionKey.split('|');
        return CodexSectionTile(
          sectionNum: parts[0],
          titleCn:    parts[1],
          titleEn:    parts[2],
          chapterKey: key,
          showChinese: showChinese,
          isDark: isDark,
          entries: grouped[sectionKey]!,
          onEntryTap: _openEntry,
          isFlow: isFlow,
        );
      },
    );
  }

  // ── Search results ─────────────────────────────────────────────────────────

  Widget _buildSearchResults(bool isDark, bool showChinese, String query) {
    if (_searchLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          'No results for "$query"',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.codexSecondaryText(isDark),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Text(
            '${_searchResults.length} result'
            '${_searchResults.length != 1 ? 's' : ''} for "$query"',
            style: TextStyle(
              fontSize: 11.5,
              color: AppTheme.codexSecondaryText(isDark),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _searchResults.length,
            itemBuilder: (context, i) {
              final entry = _searchResults[i];
              if (entry.chapter == 'flow') {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: entry.rules
                      .asMap()
                      .entries
                      .map((e) => CodexFlowStepTile(
                            block: e.value,
                            index: e.key,
                            showChinese: showChinese,
                            isDark: isDark,
                          ))
                      .toList(),
                );
              }
              return CodexEntryCard(
                entry: entry,
                showChinese: showChinese,
                isDark: isDark,
                showChapterBadge: true,
                onTap: () => _openEntry(entry),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Tab indicator ─────────────────────────────────────────────────────────────

class _ChapterIndicator extends Decoration {
  final Color color;
  const _ChapterIndicator({required this.color});

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _IndicatorPainter(color: color);
}

class _IndicatorPainter extends BoxPainter {
  final Color color;
  const _IndicatorPainter({required this.color});

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final w = cfg.size?.width ?? 0;
    final h = cfg.size?.height ?? 0;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(offset.dx, offset.dy + h - 2.5, w, 2.5),
        topLeft: const Radius.circular(2),
        topRight: const Radius.circular(2),
      ),
      Paint()..color = color,
    );
  }
}