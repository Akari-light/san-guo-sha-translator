import 'package:flutter/material.dart';

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
  int _selectedIndex = 0; // Defaulting to Home tab

  // This is the variable name you defined
  late final List<Widget> _screens = [
    const HomeScreen(),   
    const GeneralScreen(), 
    const LibraryScreen(), 
    const Center(child: Text('AI Feature (TBC)')),
    const Center(child: Text('More (TBC)')),
  ];

  // 1. Helper to get the title based on the selected index
  String _getAppBarTitle() {
    switch (_selectedIndex) {
      case 0:
        return '殺 - Stop Hesitating, Attack!';
      case 1:
        return 'Generals';
      case 2:
        return 'Library';
      case 3:
        return 'Scanner';
      default:
        return 'More';
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getAppBarTitle()),
        actions: [
          PopupMenuButton<ThemeMode>(
            icon: const Icon(Icons.palette),
            onSelected: widget.onThemeChanged,
            itemBuilder: (context) => [
              const PopupMenuItem(value: ThemeMode.system, child: Text('System')),
              const PopupMenuItem(value: ThemeMode.light, child: Text('Light')),
              const PopupMenuItem(value: ThemeMode.dark, child: Text('Dark')),
            ],
          ),
        ],
      ),
      
      // FIX: Changed _widgetOptions to _screens
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens, 
      ),

      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.red,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.info_outline), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Generals'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'Library'),
          BottomNavigationBarItem(icon: Icon(Icons.document_scanner), label: 'Scanner'),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}