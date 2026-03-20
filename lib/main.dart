import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';

// Core
import 'core/services/home_service.dart';
import 'core/services/recently_viewed_service.dart';
import 'core/navigation/app_router.dart';

// Features: Navigation and Screens
import 'features/home/presentation/screens/home_screen.dart';
import 'features/generals/presentation/screens/general_screen.dart';
import 'features/generals/presentation/screens/general_detail_screen.dart';
import 'features/library/presentation/screens/library_screen.dart';
import 'features/library/presentation/screens/library_detail_screen.dart';
import 'features/ai/presentation/screens/ai_screen.dart';
import 'features/codex/presentation/screens/codex_screen.dart';
import 'features/codex/presentation/screens/codex_entry_screen.dart'; // LangToggle

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getString('theme_mode') ?? 'system';

  runApp(MainApp(initialTheme: _parseTheme(savedTheme)));
}

ThemeMode _parseTheme(String theme) {
  switch (theme) {
    case 'light': return ThemeMode.light;
    case 'dark':  return ThemeMode.dark;
    default:      return ThemeMode.system;
  }
}

class MainApp extends StatefulWidget {
  final ThemeMode initialTheme;
  const MainApp({super.key, required this.initialTheme});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialTheme;
  }

  Future<void> _updateTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
    if (mounted) setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '殺',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: MainNavigationScreen(
        currentMode: _themeMode,
        onThemeChanged: _updateTheme,
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  final ThemeMode currentMode;
  final Function(ThemeMode) onThemeChanged;

  const MainNavigationScreen({
    super.key,
    required this.currentMode,
    required this.onThemeChanged,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 4;

  // ── Generals search
  bool _isSearchingGenerals = false;
  final ValueNotifier<String> _generalsSearchNotifier = ValueNotifier('');
  final TextEditingController _generalsSearchController = TextEditingController();

  // ── Library search
  bool _isSearching = false;
  final ValueNotifier<String> _librarySearchNotifier = ValueNotifier('');
  final TextEditingController _searchController = TextEditingController();

  // ── Codex search + lang — same ValueNotifier pattern as Generals/Library
  bool _isSearchingCodex = false;
  final ValueNotifier<String> _codexSearchNotifier = ValueNotifier('');
  final TextEditingController _codexSearchController = TextEditingController();
  final ValueNotifier<bool> _codexLangNotifier = ValueNotifier(false); // false=EN

  // ── Filter state
  bool _generalsFilterActive = false;
  VoidCallback? _openGeneralsFilter;
  bool _libraryFilterActive = false;
  VoidCallback? _openLibraryFilter;

  // ── Screen list — built once, never recreated
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      CodexScreen(
        searchNotifier:      _codexSearchNotifier,
        showChineseNotifier: _codexLangNotifier,
      ),
      GeneralScreen(
        searchNotifier: _generalsSearchNotifier,
        onFilterStateChanged: (isActive) =>
            setState(() => _generalsFilterActive = isActive),
        onRegisterSheetOpener: (opener) => _openGeneralsFilter = opener,
        onLibraryCardTap: (id) => _pushCard(id, RecordType.library),
        onCardTap: _pushCard,
      ),
      LibraryScreen(
        searchNotifier: _librarySearchNotifier,
        onFilterStateChanged: (isActive) =>
            setState(() => _libraryFilterActive = isActive),
        onRegisterSheetOpener: (opener) => _openLibraryFilter = opener,
        onCardTap: _pushCard,
      ),
      AiScreen(onCardTap: _pushCard),
      HomeScreen(
        onGeneralTap: (id) => _pushCard(id, RecordType.general),
        onLibraryTap: (id) => _pushCard(id, RecordType.library),
      ),
    ];
  }

  @override
  void dispose() {
    _librarySearchNotifier.dispose();
    _generalsSearchNotifier.dispose();
    _codexSearchNotifier.dispose();
    _codexLangNotifier.dispose();
    _searchController.dispose();
    _generalsSearchController.dispose();
    _codexSearchController.dispose();
    super.dispose();
  }

  Future<void> _pushCard(String id, RecordType type) async {
    if (type == RecordType.general) {
      final card = await HomeService.instance.findGeneralById(id);
      if (card == null || !mounted) return;
      final nav = Navigator.of(context);
      await HomeService.instance.recordGeneralView(id);
      nav.push(detailRoute(GeneralDetailScreen(
        card: card,
        onLibraryCardTap: (libId) => _pushCard(libId, RecordType.library),
      )));
    } else {
      final card = await HomeService.instance.findLibraryById(id);
      if (card == null || !mounted) return;
      final nav = Navigator.of(context);
      await HomeService.instance.recordLibraryView(id);
      nav.push(detailRoute(LibraryDetailScreen(card: card)));
    }
  }

  // ── AppBar title — TextField when searching, plain Text otherwise ──────────

  Widget _buildAppBarTitle() {
    // Codex search
    if (_selectedIndex == 0 && _isSearchingCodex) {
      return TextField(
        controller: _codexSearchController,
        autofocus: true,
        style: const TextStyle(color: AppTheme.searchTextColor),
        decoration: const InputDecoration(
          hintText: 'Search Codex…  搜索图鉴…',
          border: InputBorder.none,
          hintStyle: TextStyle(color: AppTheme.searchHintColor),
        ),
        onChanged: (v) => _codexSearchNotifier.value = v,
      );
    }
    // Generals search
    if (_selectedIndex == 1 && _isSearchingGenerals) {
      return TextField(
        controller: _generalsSearchController,
        autofocus: true,
        style: const TextStyle(color: AppTheme.searchTextColor),
        decoration: const InputDecoration(
          hintText: 'Search generals...',
          border: InputBorder.none,
          hintStyle: TextStyle(color: AppTheme.searchHintColor),
        ),
        onChanged: (v) => _generalsSearchNotifier.value = v,
      );
    }
    // Library search
    if (_selectedIndex == 2 && _isSearching) {
      return TextField(
        controller: _searchController,
        autofocus: true,
        style: const TextStyle(color: AppTheme.searchTextColor),
        decoration: const InputDecoration(
          hintText: 'Search cards...',
          border: InputBorder.none,
          hintStyle: TextStyle(color: AppTheme.searchHintColor),
        ),
        onChanged: (v) => _librarySearchNotifier.value = v,
      );
    }
    return Text(_getAppBarTitle());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _buildAppBarTitle(),
        actions: [
          // ── Codex: search icon
          if (_selectedIndex == 0)
            IconButton(
              icon: Icon(_isSearchingCodex ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _isSearchingCodex = !_isSearchingCodex;
                  if (!_isSearchingCodex) {
                    _codexSearchNotifier.value = '';
                    _codexSearchController.clear();
                  }
                });
              },
            ),

          // ── Codex: lang toggle
          if (_selectedIndex == 0)
            ValueListenableBuilder<bool>(
              valueListenable: _codexLangNotifier,
              builder: (context, showChinese, _) {
                final isDark =
                    Theme.of(context).brightness == Brightness.dark;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: LangToggle(
                    showChinese: showChinese,
                    isDark: isDark,
                    onToggle: () =>
                        _codexLangNotifier.value = !_codexLangNotifier.value,
                  ),
                );
              },
            ),

          // ── Generals: search
          if (_selectedIndex == 1)
            IconButton(
              icon: Icon(_isSearchingGenerals ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _isSearchingGenerals = !_isSearchingGenerals;
                  if (!_isSearchingGenerals) {
                    _generalsSearchNotifier.value = '';
                    _generalsSearchController.clear();
                  }
                });
              },
            ),

          // ── Library: search
          if (_selectedIndex == 2)
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _librarySearchNotifier.value = '';
                    _searchController.clear();
                  }
                });
              },
            ),

          // ── Generals: filter
          if (_selectedIndex == 1)
            IconButton(
              icon: Icon(
                Icons.filter_list,
                color: _generalsFilterActive ? Colors.orange : null,
              ),
              onPressed: () => _openGeneralsFilter?.call(),
            ),

          // ── Library: filter
          if (_selectedIndex == 2)
            IconButton(
              icon: Icon(
                Icons.filter_list,
                color: _libraryFilterActive ? Colors.orange : null,
              ),
              onPressed: () => _openLibraryFilter?.call(),
            ),

          // ── Theme menu (all tabs)
          PopupMenuButton<ThemeMode>(
            icon: Icon(_getThemeIcon(widget.currentMode)),
            onSelected: (mode) => widget.onThemeChanged(mode),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: ThemeMode.system,
                child: ListTile(
                  leading: Icon(Icons.brightness_auto),
                  title: Text('System'),
                ),
              ),
              const PopupMenuItem(
                value: ThemeMode.light,
                child: ListTile(
                  leading: Icon(Icons.light_mode),
                  title: Text('Light'),
                ),
              ),
              const PopupMenuItem(
                value: ThemeMode.dark,
                child: ListTile(
                  leading: Icon(Icons.dark_mode),
                  title: Text('Dark'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: SizedBox(
        height: 90,
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _selectedIndex,
          onTap: (index) {
            if (index == _selectedIndex) {
              if (index == 1) _openGeneralsFilter?.call();
              if (index == 2) _openLibraryFilter?.call();
              return;
            }
            setState(() {
              _selectedIndex       = index;
              _isSearching         = false;
              _isSearchingGenerals = false;
              _isSearchingCodex    = false;
              _librarySearchNotifier.value  = '';
              _generalsSearchNotifier.value = '';
              _codexSearchNotifier.value    = '';
              _searchController.clear();
              _generalsSearchController.clear();
              _codexSearchController.clear();
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.more_horiz),
              ),
              label: 'Codex',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.person),
              ),
              label: 'Generals',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.menu_book),
              ),
              label: 'Library',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.travel_explore),
              ),
              label: 'Discover',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.info_outline),
              ),
              label: 'Home',
            ),
          ],
        ),
      ),
    );
  }

  IconData _getThemeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:  return Icons.light_mode;
      case ThemeMode.dark:   return Icons.dark_mode;
      case ThemeMode.system: return Icons.brightness_auto;
    }
  }

  String _getAppBarTitle() {
    switch (_selectedIndex) {
      case 0: return 'Codex';
      case 1: return 'Generals';
      case 2: return 'Library';
      case 3: return 'Discover';
      case 4: return '殺 - Stop Hesitating, Attack!';
      default: return '殺';
    }
  }
}