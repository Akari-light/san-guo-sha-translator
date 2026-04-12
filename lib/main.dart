import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'features/ai/presentation/screens/scanner_screen.dart';
import 'features/codex/presentation/screens/codex_screen.dart';
import 'features/codex/presentation/screens/codex_entry_screen.dart'; // LangToggle

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getString('theme_mode') ?? 'system';

  runApp(MainApp(initialTheme: _parseTheme(savedTheme)));
}

ThemeMode _parseTheme(String theme) {
  switch (theme) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
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
      home: SplashScreen(
        themeMode: _themeMode,
        onThemeChanged: _updateTheme,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Splash Screen
//
// Timeline (2 400 ms total):
//   0 –  500 ms   logo fades in      (easeIn,  Interval 0.00–0.21)
//   500 – 1 800   logo holds
//   1 800 – 2 400 screen fades out   (easeOut, Interval 0.75–1.00)
//                 → pushReplacement with zero-duration route transition
//
// The native launch screen (Android launch_background.xml / iOS storyboard)
// already shows #1A1A1C, so there is no visible jump when Flutter takes over.
// The logo fades in on top of the identical background, giving the illusion
// of one continuous launch experience.
// ─────────────────────────────────────────────────────────────────────────────

class SplashScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final Function(ThemeMode) onThemeChanged;

  const SplashScreen({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  /// Logo fades in: opacity 0 → 1 over the first 500 ms.
  late final Animation<double> _logoOpacity;

  /// Whole Flutter layer fades out: opacity 1 → 0 over the last 600 ms.
  late final Animation<double> _screenOpacity;

  /// Must exactly match android/app/src/main/res/values/colors.xml
  /// and the iOS LaunchScreen.storyboard backgroundColor.
  static const Color _bg = Color(0xFF1A1A1C);

  @override
  void initState() {
    super.initState();

    // Keep status-bar icons white over the dark splash background.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _logoOpacity = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.00, 0.21, curve: Curves.easeIn),
    );

    _screenOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.75, 1.00, curve: Curves.easeOut),
      ),
    );

    _ctrl.forward().then((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          // The visual fade already completed via _screenOpacity,
          // so no additional route animation is needed.
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, _, _) => MainNavigationScreen(
            currentMode: widget.themeMode,
            onThemeChanged: widget.onThemeChanged,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Opacity(
          opacity: _screenOpacity.value,
          child: Scaffold(
            backgroundColor: _bg,
            body: Center(
              child: FadeTransition(
                opacity: _logoOpacity,
                child: const _SplashLogo(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SplashLogo extends StatelessWidget {
  const _SplashLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 殺 — large, white, bold
        Text(
          '殺',
          style: TextStyle(
            fontSize: 96,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 4,
            height: 1.0,
            shadows: [
              Shadow(
                color: Colors.white.withValues(alpha: 0.15),
                blurRadius: 32,
                offset: Offset.zero,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // ── SHA — thin, muted, wide letter-spacing
        Text(
          'SHA',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w300,
            color: Colors.white.withValues(alpha: 0.35),
            letterSpacing: 8,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Navigation
// ─────────────────────────────────────────────────────────────────────────────

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
  int _previousIndex = 4;

  bool _scannerShowsNavBar = false;

  // ── Double-back-to-exit
  DateTime? _lastBackPress;

  // ── Discover tab index constant — single source of truth.
  static const int _discoverTabIndex = 3;

  // ── Generals search
  bool _isSearchingGenerals = false;
  final ValueNotifier<String> _generalsSearchNotifier = ValueNotifier('');
  final TextEditingController _generalsSearchController =
      TextEditingController();

  // ── Library search
  bool _isSearching = false;
  final ValueNotifier<String> _librarySearchNotifier = ValueNotifier('');
  final TextEditingController _searchController = TextEditingController();

  // ── Codex search + lang
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
  late final List<Widget> _staticScreens;

  // ── Scanner activation notifier — replaces the isActive parameter.
  //    The old _buildScreens() created a NEW ScannerScreen widget on every
  //    setState() because isActive was a constructor parameter that changed.
  //    This triggered didUpdateWidget cascades, camera reinit attempts,
  //    and live OCR restarts on every frame across the ENTIRE app.
  final ValueNotifier<bool> _scannerActiveNotifier = ValueNotifier(false);

  // Built once in initState, returned on every build. ScannerScreen is
  // never recreated — it listens to _scannerActiveNotifier instead.
  late final List<Widget> _allScreens;

  List<Widget> _buildScreens() => _allScreens;

  @override
  void initState() {
    super.initState();
    _staticScreens = [
      CodexScreen(
        searchNotifier: _codexSearchNotifier,
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
      HomeScreen(
        onGeneralTap: (id) => _pushCard(id, RecordType.general),
        onLibraryTap: (id) => _pushCard(id, RecordType.library),
      ),
    ];
    // App starts on Home (index 4). Scanner starts dormant because
    // _scannerActiveNotifier is false. It activates when _switchTab(3) fires.
    _allScreens = [
      _staticScreens[0], // Codex
      _staticScreens[1], // Generals
      _staticScreens[2], // Library
      ScannerScreen(
        onCardTap: _pushCard,
        onBack: () => setState(() => _selectedIndex = _previousIndex),
        onNavBarVisibilityChanged: (visible) =>
            setState(() => _scannerShowsNavBar = visible),
        activeNotifier: _scannerActiveNotifier,
      ),
      _staticScreens[3], // Home
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
    _scannerActiveNotifier.dispose();
    super.dispose();
  }

  /// Switches to [index]. Scanner camera starts/stops automatically
  /// via its isActive parameter reacting to _selectedIndex changes.
  void _switchTab(int index) {
    if (index == _selectedIndex) {
      if (index == 1) _openGeneralsFilter?.call();
      if (index == 2) _openLibraryFilter?.call();
      return;
    }

    setState(() {
      _previousIndex = _selectedIndex;
      _selectedIndex = index;
      _scannerShowsNavBar = false;
      _isSearching = false;
      _isSearchingGenerals = false;
      _isSearchingCodex = false;
      _librarySearchNotifier.value = '';
      _generalsSearchNotifier.value = '';
      _codexSearchNotifier.value = '';
      _searchController.clear();
      _generalsSearchController.clear();
      _codexSearchController.clear();
    });
    // Update scanner activation AFTER setState — no widget recreation needed.
    _scannerActiveNotifier.value = (index == _discoverTabIndex);
  }

  Future<void> _pushCard(String id, RecordType type) async {
    if (type == RecordType.general) {
      final card = await HomeService.instance.findGeneralById(id);
      if (card == null || !mounted) return;
      final nav = Navigator.of(context);
      await HomeService.instance.recordGeneralView(id);
      nav.push(
        detailRoute(
          GeneralDetailScreen(
            card: card,
            onLibraryCardTap: (libId) => _pushCard(libId, RecordType.library),
          ),
        ),
      );
    } else {
      final card = await HomeService.instance.findLibraryById(id);
      if (card == null || !mounted) return;
      final nav = Navigator.of(context);
      await HomeService.instance.recordLibraryView(id);
      nav.push(detailRoute(LibraryDetailScreen(card: card)));
    }
  }

  // ── AppBar title ──────────────────────────────────────────────────────────

  Widget _buildAppBarTitle() {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor:
            isDark ? const Color(0xFF252526) : const Color(0xFFF3F3F3),
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
      child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) {
        // Scanner tab: scanner's inner PopScope (canPop: false) handles
        // everything — adjusting→live or live→onBack(). Both PopScopes fire
        // on a back press, but the scanner's onBack callback already switches
        // the tab via setState, so we just return here to avoid double-handling.
        if (_selectedIndex == _discoverTabIndex) {
          return;
        }

        // All other tabs: back navigates to Home first.
        if (_selectedIndex != 4) {
          setState(() {
            _previousIndex = _selectedIndex;
            _selectedIndex = 4;
            _isSearching = false;
            _isSearchingGenerals = false;
            _isSearchingCodex = false;
            _librarySearchNotifier.value = '';
            _generalsSearchNotifier.value = '';
            _codexSearchNotifier.value = '';
            _searchController.clear();
            _generalsSearchController.clear();
            _codexSearchController.clear();
          });
          return;
        }

        // Already on Home — double-back to exit.
        final now = DateTime.now();
        final lastPress = _lastBackPress;
        if (lastPress == null ||
            now.difference(lastPress) > const Duration(seconds: 2)) {
          _lastBackPress = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          // ignore: deprecated_member_use
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: (_selectedIndex == _discoverTabIndex && !_scannerShowsNavBar)
            ? null
            : AppBar(
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
                      icon: Icon(Icons.filter_list,
                          color: _generalsFilterActive ? Colors.orange : null),
                      onPressed: () => _openGeneralsFilter?.call(),
                    ),

                  // ── Library: filter
                  if (_selectedIndex == 2)
                    IconButton(
                      icon: Icon(Icons.filter_list,
                          color: _libraryFilterActive ? Colors.orange : null),
                      onPressed: () => _openLibraryFilter?.call(),
                    ),

                  // ── Theme menu (all tabs)
                  PopupMenuButton<ThemeMode>(
                    icon: Icon(_getThemeIcon(widget.currentMode)),
                    onSelected: (mode) => widget.onThemeChanged(mode),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: ThemeMode.system,
                        child: ListTile(leading: Icon(Icons.brightness_auto), title: Text('System')),
                      ),
                      const PopupMenuItem(
                        value: ThemeMode.light,
                        child: ListTile(leading: Icon(Icons.light_mode), title: Text('Light')),
                      ),
                      const PopupMenuItem(
                        value: ThemeMode.dark,
                        child: ListTile(leading: Icon(Icons.dark_mode), title: Text('Dark')),
                      ),
                    ],
                  ),
                ],
              ),
        body: IndexedStack(index: _selectedIndex, children: _buildScreens()),
        bottomNavigationBar:
            (_selectedIndex == _discoverTabIndex && !_scannerShowsNavBar)
                ? null
                : SafeArea(
                    top: false,
                    child: BottomNavigationBar(
                      type: BottomNavigationBarType.fixed,
                      currentIndex: _selectedIndex,
                      // ── KEY FIX: all tab switches go through _switchTab()
                      // which correctly calls pause()/resume() on the scanner.
                      onTap: _switchTab,
                      items: [
                        BottomNavigationBarItem(
                          icon: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: const Icon(Icons.menu_book),
                          ),
                          label: 'Codex',
                        ),
                        BottomNavigationBarItem(
                          icon: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: SizedBox(
                              width: 28, height: 28,
                              child: Center(child: Text('將',
                                  style: const TextStyle(fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF858585), height: 1.0))),
                            ),
                          ),
                          activeIcon: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: SizedBox(
                              width: 28, height: 28,
                              child: Center(child: Text('將',
                                  style: const TextStyle(fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF007ACC), height: 1.0))),
                            ),
                          ),
                          label: 'Generals',
                        ),
                        BottomNavigationBarItem(
                          icon: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: SizedBox(
                              width: 28, height: 28,
                              child: Center(child: Text('牌',
                                  style: const TextStyle(fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF858585), height: 1.0))),
                            ),
                          ),
                          activeIcon: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: SizedBox(
                              width: 28, height: 28,
                              child: Center(child: Text('牌',
                                  style: const TextStyle(fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF007ACC), height: 1.0))),
                            ),
                          ),
                          label: 'Library',
                        ),
                        BottomNavigationBarItem(
                          icon: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: const Icon(Icons.travel_explore),
                          ),
                          label: 'Discover',
                        ),
                        BottomNavigationBarItem(
                          icon: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: const Icon(Icons.home_rounded),
                          ),
                          label: 'Home',
                        ),
                      ],
                    ),
                  ),
      ),
    ), // PopScope
    ); // AnnotatedRegion
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
      case 0:  return 'Codex';
      case 1:  return 'Generals';
      case 2:  return 'Library';
      case 3:  return 'Discover';
      case 4:  return '殺 - Stop Hesitating, Attack!';
      default: return '殺';
    }
  }
}