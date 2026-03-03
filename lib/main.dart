import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Core & Theme
import 'core/theme/app_theme.dart';

// Features: Navigation and Screens
import 'features/home/presentation/screens/home_screen.dart';
import 'features/generals/presentation/screens/general_screen.dart';
import 'features/library/presentation/screens/library_screen.dart';

void main() async {
  // Ensure Flutter is initialized before calling SharedPreferences
  WidgetsFlutterBinding.ensureInitialized();
  
  final prefs = await SharedPreferences.getInstance();
  
  // Load the saved string, default to 'system' if nothing is saved
  final savedTheme = prefs.getString('theme_mode') ?? 'system';
  
  runApp(MainApp(initialTheme: _parseTheme(savedTheme)));
}

// Helper to convert saved String back into a ThemeMode object
ThemeMode _parseTheme(String theme) {
  switch (theme) {
    case 'light': return ThemeMode.light;
    case 'dark': return ThemeMode.dark;
    default: return ThemeMode.system;
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

  // Updates the UI and saves the preference to disk
  Future<void> _updateTheme(ThemeMode mode) async {
    setState(() {
      _themeMode = mode;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name); 
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '殺',
      debugShowCheckedModeBanner: false,
      // Using your VS Code Dark+ Theme from the core folder
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
  int _selectedIndex = 0;
  bool _isSearching = false;
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  List<Widget> get _screens => [
        const HomeScreen(),
        const GeneralScreen(),
        LibraryScreen(searchQuery: _searchQuery),
        const Center(child: Text('AI Feature (TBC)')),
        const Center(child: Text('More (TBC)')),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: !_isSearching
            ? Text(_getAppBarTitle())
            : TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Color(0xFFD4D4D4)), // VS Code Text Color
                decoration: const InputDecoration(
                  hintText: 'Search cards...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Color(0xFF858585)),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
        actions: [
          // Theme Selection Menu
          PopupMenuButton<ThemeMode>(
            icon: Icon(_getThemeIcon(widget.currentMode)),
            onSelected: (ThemeMode mode) => widget.onThemeChanged(mode),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: ThemeMode.system,
                child: ListTile(
                  leading: Icon(Icons.brightness_auto),
                  title: Text("System"),
                ),
              ),
              const PopupMenuItem(
                value: ThemeMode.light,
                child: ListTile(
                  leading: Icon(Icons.light_mode),
                  title: Text("Light"),
                ),
              ),
              const PopupMenuItem(
                value: ThemeMode.dark,
                child: ListTile(
                  leading: Icon(Icons.dark_mode),
                  title: Text("Dark"),
                ),
              ),
            ],
          ),

          // Library Search Toggle
          if (_selectedIndex == 2)
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchQuery = "";
                    _searchController.clear();
                  }
                });
              },
            ),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: SizedBox(
        height: 90, // Increased height to give the bigger icons room
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
              _isSearching = false; 
              _searchQuery = "";
              _searchController.clear();
            });
          },
          items: const [
            BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(bottom: 4),child: Icon(Icons.info_outline),),label: 'Home',),
            BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(bottom: 4),child: Icon(Icons.person),),label: 'Generals',),
            BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(bottom: 4),child: Icon(Icons.menu_book),),label: 'Library',),
            BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(bottom: 4),child: Icon(Icons.document_scanner),),label: 'Scanner',),
            BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(bottom: 4),child: Icon(Icons.more_horiz),),label: 'More',),
          ],
        ),
      ),
    );
  }

  IconData _getThemeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light: return Icons.light_mode;
      case ThemeMode.dark: return Icons.dark_mode;
      case ThemeMode.system: return Icons.brightness_auto;
    }
  }

  String _getAppBarTitle() {
    switch (_selectedIndex) {
      case 1: return 'Generals';
      case 2: return 'Library';
      case 3: return 'Scanner';
      case 4: return 'More';
      default: return '殺 - Stop Hesitating, Attack!';
    }
  }
}