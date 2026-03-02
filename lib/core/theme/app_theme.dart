import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // VS Code Dark+ Style Colors
  static const Color _vscodeBg = Color(0xFF1E1E1E);
  static const Color _vscodeSidebar = Color(0xFF252526);
  static const Color _vscodeBlue = Color(0xFF007ACC);
  static const Color _vscodeText = Color(0xFFD4D4D4);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _vscodeBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: _vscodeSidebar,
        elevation: 0,
        titleTextStyle: TextStyle(color: _vscodeText, fontSize: 18),
        iconTheme: IconThemeData(color: _vscodeText),
      ),
      colorScheme: const ColorScheme.dark(
        surface: _vscodeSidebar,
        primary: _vscodeBlue,
        onSurface: _vscodeText,
        secondary: Color(0xFF4EC9B0),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: _vscodeBg,
        selectedItemColor: _vscodeBlue,
        unselectedItemColor: Color(0xFF858585),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: Colors.red,
    );
  }
}