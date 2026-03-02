import 'package:flutter/material.dart';
import 'dart:convert'; // Add this for json.decode
import 'package:flutter/services.dart'; // Add this for rootBundle
import 'features/library/library_search_delegate.dart'; // Adjust path if needed
import 'data/models/library_card.dart'; // Required for type casting
import 'data/repositories/library_repository.dart';

// 1. Imports: We now link to the separate files in your feature folders
import 'features/home/screens/home_screen.dart';
import 'features/generals/screens/general_screen.dart';
import 'features/library/screens/library_screen.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  // variable stores our current theme choice. Default - system to match phone settings
  ThemeMode _themeMode = ThemeMode.system;

  void _updateTheme(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '殺',
      // debugShowCheckedModeBanner: false, // Professional touch: removes the "Debug" banner
      theme: ThemeData(
        brightness: Brightness.light,
        colorSchemeSeed: Colors.red, 
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.red,
        useMaterial3: true,
      ),
      themeMode: _themeMode, 
      // pass the theme logic down to the MainScreen (the scaffold)
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
    required this.onThemeChanged
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  bool _isSearching = false; // Tracks if search bar is open
  String _searchQuery = ""; // Tracks the keystrokes
  final TextEditingController _searchController = TextEditingController();

  List<Widget> get _screens => [
    const HomeScreen(),   
    const GeneralScreen(), 
    LibraryScreen(searchQuery: _searchQuery), // Pass the live query
    const Center(child: Text('AI Feature (TBC)')),
    const Center(child: Text('More (TBC)')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Toggle between the Title and the Search Field
        title: !_isSearching 
          ? Text(_getAppBarTitle()) 
          : TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search cards...',
                border: InputBorder.none,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value; // This filters the background live
                });
              },
            ),
        actions: [
          if (_selectedIndex == 2) // Library only
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchQuery = ""; // Reset filter on close
                    _searchController.clear();
                  }
                });
              },
            ),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: _screens),
      // ... keep your BottomNavigationBar as is ...
    );
  }

  String _getAppBarTitle() {
    switch (_selectedIndex) {
      case 1: return 'Generals';
      case 2: return 'Library';
      case 3: return 'Scanner';
      default: return '殺 - Stop Hesitating, Attack!';
    }
  }
}