import 'package:flutter/material.dart';

void main() {
  runApp(const MainApp());
}

// 1. We changed StatelessWidget to StatefulWidget so the app can "remember" 
// which theme you picked and redraw the screen.
class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  // 2. This variable stores our current theme choice. 
  // We start with 'system' so it matches your phone's settings.
  ThemeMode _themeMode = ThemeMode.system;

  // 3. This function will be called when we click a button to change the theme.
  void _updateTheme(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '殺',
      // 4. Define what "Light Mode" looks like
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.red,
        useMaterial3: true,
      ),
      // 5. Define what "Dark Mode" looks like (Perfect for night games!)
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.red,
        useMaterial3: true,
      ),
      // 6. Tell the app which mode to currently display
      themeMode: _themeMode, 
      home: HomeScreen(
        currentMode: _themeMode,
        onThemeChanged: _updateTheme,
      ),
    );
  }
}

// 7. We moved the UI into its own Widget called HomeScreen to keep things clean.
class HomeScreen extends StatelessWidget {
  final ThemeMode currentMode;
  final Function(ThemeMode) onThemeChanged;

  const HomeScreen({
    super.key, 
    required this.currentMode, 
    required this.onThemeChanged
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('殺 (Sanguosha Translator)'),
        actions: [
          // 8. This button creates a dropdown menu in the top right corner
          PopupMenuButton<ThemeMode>(
            icon: const Icon(Icons.palette),
            onSelected: onThemeChanged,
            itemBuilder: (context) => [
              const PopupMenuItem(value: ThemeMode.system, child: Text('System')),
              const PopupMenuItem(value: ThemeMode.light, child: Text('Light')),
              const PopupMenuItem(value: ThemeMode.dark, child: Text('Dark')),
            ],
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Welcome to the Translator',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Text('Current Mode: ${currentMode.name.toUpperCase()}'),
          ],
        ),
      ),
    );
  }
}