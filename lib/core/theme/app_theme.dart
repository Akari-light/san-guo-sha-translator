import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // VS Code Dark+ Style Colors
  static const Color _vscodeSidebar = Color(0xFF252526);
  static const Color _vscodeBg = Color(0xFF1E1E1E);
  static const Color _vscodeBlue = Color(0xFF007ACC);

  // New Light Mode colors for better contrast
  static const Color _lightSurface = Color(0xFFF3F3F3); 
  static const Color _lightBorder = Color(0xFFE0E0E0);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _vscodeBg,
      colorScheme: const ColorScheme.dark(
        surface: _vscodeSidebar,
        primary: _vscodeBlue,
        secondary: Color(0xFF4EC9B0),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: _vscodeSidebar,
        selectedItemColor: _vscodeBlue,
        unselectedItemColor: Color(0xFF858585),
        selectedIconTheme: IconThemeData(size: 28), 
        unselectedIconTheme: IconThemeData(size: 28),
        selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 12),
        
        type: BottomNavigationBarType.fixed,
        elevation: 0, 
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      dividerColor: _lightBorder, 
      colorScheme: ColorScheme.light(
        surface: _lightSurface,
        primary: const Color(0xFF005FB8), 
        secondary: const Color(0xFF0078D4),
        outlineVariant: _lightBorder, 
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: _lightSurface, 
        selectedItemColor: _vscodeBlue,
        unselectedItemColor: Color(0xFF858585),
        selectedIconTheme: IconThemeData(size: 28), 
        unselectedIconTheme: IconThemeData(size: 28),
        selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 12),
        
        type: BottomNavigationBarType.fixed,
        elevation: 0, 
      ),
    );
  }
}