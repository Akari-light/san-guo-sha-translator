import 'package:flutter/material.dart';
import '../../data/models/codex_entry_dto.dart';
import '../../data/repository/codex_loader.dart';
import '../codex_chapter_config.dart';
import 'codex_entry_screen.dart';
import '../widgets/codex_section_tile.dart';
import '../widgets/codex_entry_card.dart';
import '../widgets/codex_reference_sheet.dart';
import '../widgets/codex_rule_block_widget.dart';
import '../../../../core/theme/app_theme.dart';

class CodexScreen extends StatefulWidget {
  final ValueNotifier<String> searchNotifier;
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
  int _activeChapterIndex = 1;

  final Map<String, List<CodexEntryDTO>> _data = {};
  final Map<String, bool> _loading = {};

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

  void _onSearchChanged() {
    final query = widget.searchNotifier.value;
    if (query == _lastQuery) return;
    _lastQuery = query;

    if (query.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _searchLoading = false;
        });
      }
      return;
    }

    for (final ch in kCodexChapters) {
      _loadChapter(ch.key);
    }

    if (mounted) setState(() => _searchLoading = true);
    CodexLoader.instance.search(query).then((results) {
      if (mounted && widget.searchNotifier.value == query) {
        setState(() {
          _searchResults = results;
          _searchLoading = false;
        });
      }
    });
  }

  void _showReferenceSheet(String bracketText, bool isChinese) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    CodexReferenceSheet.show(
      context: context,
      bracketText: bracketText,
      isChinese: isChinese,
      isDark: isDark,
      showChinese: widget.showChineseNotifier.value,
    );
  }

  SegmentTapCallback get _segmentTap =>
      (rawCn, isChinese) => _showReferenceSheet(rawCn, isChinese);

  void _openEntry(CodexEntryDTO entry, bool showChinese) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CodexEntryScreen(
          entry: entry,
          showChinese: showChinese,
          onSegmentTap: _segmentTap,
        ),
      ),
    );
  }

  Map<String, List<CodexEntryDTO>> _groupBySection(List<CodexEntryDTO> entries) {
    final map = <String, List<CodexEntryDTO>>{};
    for (final e in entries) {
      final key = '${e.sectionNum}|${e.sectionTitleCn}|${e.sectionTitleEn}';
      map.putIfAbsent(key, () => []).add(e);
    }
    return map;
  }

  ({
    String titleEn,
    String titleCn,
    String summaryEn,
    String summaryCn,
    String scanHintEn,
    String scanHintCn,
  })
      _chapterMeta(String key) {
    return switch (key) {
      'setup' => (
          titleEn: 'Setup Reference',
          titleCn: '身份局资料',
          summaryEn:
              'Identity Mode counts and card lists, kept separate from card encyclopedia pages.',
          summaryCn: '收录身份局卡牌数量与游戏牌一览，作为身份局专用资料索引。',
          scanHintEn:
              'Use this for counts and inclusions.',
          scanHintCn: '用于核对数量与收录范围。',
        ),
      'glossary' => (
          titleEn: 'Terminology',
          titleCn: '用语规范',
          summaryEn:
              'Canonical rules language for operations, values, timing, and state changes.',
          summaryCn: '收录官方用语及其操作规范，作为全项目翻译与释义的中文基准。',
          scanHintEn:
              'Use this first when wording feels close but not identical.',
          scanHintCn: '遇到措辞接近但不完全相同时，先回本章核对术语。',
        ),
      'flow' => (
          titleEn: 'Resolution Flow',
          titleCn: '结算流程',
          summaryEn:
              'Turn timings, event sequencing, inserted resolutions, and dying/death handling.',
          summaryCn: '按官方流程整理回合时机、事件结算、濒死与死亡处理。',
          scanHintEn:
              'Read sections top-to-bottom when debugging timing or order.',
          scanHintCn: '处理时机、顺序或插入结算时，按章节自上而下阅读。',
        ),
      'rules' => (
          titleEn: 'Resolution Rules',
          titleCn: '规则原则',
          summaryEn:
              'Priority, conflict handling, state effects, and execution rules.',
          summaryCn: '集中说明结算原则、技能要素与冲突处理。',
          scanHintEn:
              'Use when two effects seem to contradict each other.',
          scanHintCn: '当两个效果看似冲突时，先回本章判断优先级。',
        ),
      _ => (
          titleEn: 'Codex',
          titleCn: '规则索引',
          summaryEn: 'Structured rules reference.',
          summaryCn: '结构化规则索引。',
          scanHintEn: 'Browse by chapter, then drill into the exact term.',
          scanHintCn: '先按章节定位，再展开到具体条目。',
        ),
    };
  }

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
                if (!isSearching) _buildTabBar(isDark, showChinese),
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

  Widget _buildTabBar(bool isDark, bool showChinese) {
    return ColoredBox(
      color: AppTheme.codexSectionHeaderBg(isDark),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
                  final i = e.key;
                  final ch = e.value;
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
          Divider(height: 1, thickness: 1, color: AppTheme.codexDivider(isDark)),
        ],
      ),
    );
  }

  Widget _buildChapterView(String key, bool isDark, bool showChinese) {
    final entries = _data[key];
    if (entries == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final isFlow = key == 'flow';
    final grouped = _groupBySection(entries);
    final meta = _chapterMeta(key);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: grouped.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return _ChapterHero(
            chapterKey: key,
            title: showChinese ? meta.titleCn : meta.titleEn,
            counterpart: showChinese ? meta.titleEn : meta.titleCn,
            summary: showChinese ? meta.summaryCn : meta.summaryEn,
            scanHint: showChinese ? meta.scanHintCn : meta.scanHintEn,
            sectionCount: grouped.length,
            entryCount: entries.length,
            showChinese: showChinese,
            isDark: isDark,
          );
        }

        final sectionKey = grouped.keys.elementAt(i - 1);
        final parts = sectionKey.split('|');
        final sectionEntries = grouped[sectionKey]!;
        CodexEntryDTO? guideEntry;
        for (final entry in sectionEntries) {
          if (entry.id.contains('guide') || entry.sectionNum.endsWith('.0')) {
            guideEntry = entry;
            break;
          }
        }
        final summarySource = guideEntry ?? sectionEntries.first;
        return CodexSectionTile(
          sectionNum: parts[0],
          titleCn: parts[1],
          titleEn: parts[2],
          chapterKey: key,
          showChinese: showChinese,
          isDark: isDark,
          entries: sectionEntries,
          sectionSummary: showChinese
              ? summarySource.definitionCn
              : summarySource.definitionEn,
          isFlow: isFlow,
          onSegmentTap: _segmentTap,
          onOpenEntry: (entry) => _openEntry(entry, showChinese),
        );
      },
    );
  }

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

    final chapters = _searchResults.map((e) => e.chapter).toSet().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SearchHero(
          query: query,
          resultCount: _searchResults.length,
          chapterCount: chapters,
          isDark: isDark,
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _searchResults.length,
             itemBuilder: (context, i) {
               final entry = _searchResults[i];
               return CodexEntryCard(
                 entry: entry,
                 showChinese: showChinese,
                isDark: isDark,
                showChapterBadge: true,
                onSegmentTap: _segmentTap,
                onOpenDetails: () => _openEntry(entry, showChinese),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChapterHero extends StatelessWidget {
  final String chapterKey;
  final String title;
  final String counterpart;
  final String summary;
  final String scanHint;
  final int sectionCount;
  final int entryCount;
  final bool showChinese;
  final bool isDark;

  const _ChapterHero({
    required this.chapterKey,
    required this.title,
    required this.counterpart,
    required this.summary,
    required this.scanHint,
    required this.sectionCount,
    required this.entryCount,
    required this.showChinese,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.codexChapterAccent(chapterKey, isDark);

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 14, 0, 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.codexSectionHeaderBg(isDark),
        border: Border.all(
          color: accent.withAlpha(isDark ? 90 : 70),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.codexTerm(isDark),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            counterpart,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.codexSubText(chapterKey, isDark),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            summary,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.6,
              color: AppTheme.codexDefinition(isDark),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroStat(
                label: showChinese ? '节' : 'Sections',
                value: '$sectionCount',
                accent: accent,
                isDark: isDark,
              ),
              _HeroStat(
                label: showChinese ? '条目' : 'Entries',
                value: '$entryCount',
                accent: accent,
                isDark: isDark,
              )
            ],
          ),
          const SizedBox(height: 12),
          Text(
            scanHint,
            style: TextStyle(
              fontSize: 12,
              height: 1.55,
              color: AppTheme.codexSecondaryText(isDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  final bool isDark;

  const _HeroStat({
    required this.label,
    required this.value,
    required this.accent,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.codexTagFill(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.codexTagBorder(isDark),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.codexSecondaryText(isDark),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchHero extends StatelessWidget {
  final String query;
  final int resultCount;
  final int chapterCount;
  final bool isDark;

  const _SearchHero({
    required this.query,
    required this.resultCount,
    required this.chapterCount,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.codexSectionHeaderBg(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.codexTagBorder(isDark),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Search results',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppTheme.codexTerm(isDark),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$resultCount ${resultCount == 1 ? "match" : "matches"} across $chapterCount ${chapterCount == 1 ? "chapter" : "chapters"} for "$query".',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppTheme.codexDefinition(isDark),
            ),
          ),
        ],
      ),
    );
  }
}

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
