import 'package:flutter/material.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  // variable to stores our current theme choice. Default - system to match phone settings
  ThemeMode _themeMode = ThemeMode.system;

  // button obj to change the theme 
  void _updateTheme(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '殺',
      // define light mode theme
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.red,
        useMaterial3: true,
      ),
      // define dark mode theme
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.red,
        useMaterial3: true,
      ),
      // tell the app which mode to currently display
      themeMode: _themeMode, 
      home: HomeScreen(
        currentMode: _themeMode,
        onThemeChanged: _updateTheme,
      ),
    );
  }
}

// New: Changed to StatefulWidget to track navigation
class HomeScreen extends StatefulWidget { 
  final ThemeMode currentMode;
  final Function(ThemeMode) onThemeChanged;

  const HomeScreen({
    super.key, 
    required this.currentMode, 
    required this.onThemeChanged
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // New: This variable tracks which tab is currently selected
  int _selectedIndex = 1; // Set to 1 so 'Library' is selected by default like your screenshot

  // New: List of screens to show for each tab
  static const List<Widget> _widgetOptions = <Widget>[
    Center(child: Text('General')),
    Center(child: Text('Library')),
    Center(child: Text('TBC')),
    Center(child: Text('TBC')),
    Center(child: Text('More')),
  ];

  // function to process tapping on the nav bar
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('殺 (Sanguosha Translator)'),
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
      // The body now changes based on which index is selected
      body: _widgetOptions.elementAt(_selectedIndex),

      // New: Adding the Bottom Navigation Bar
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed, // Necessary when you have 5 items
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.red, // Traditional Sanguosha Red
        onTap: _onItemTapped,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.info_outline), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.library_books), label: 'Generals'),
          BottomNavigationBarItem(icon: Icon(Icons.new_releases), label: 'Library'),
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'TBC'),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'TBC'),
        ],
      ),
    );
  }
}