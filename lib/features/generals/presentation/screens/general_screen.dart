import 'package:flutter/material.dart';

class GeneralScreen extends StatelessWidget {
  const GeneralScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          // FIXED: Removed 'Main sniper' syntax error [cite: 3]
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // FIXED: Used .withValues() instead of .withOpacity() to remove deprecation warning [cite: 3]
            Icon(Icons.shield_outlined, size: 80, color: Colors.red.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text(
              'Generals Database',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Under Development: 800+ Heroes Coming Soon',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}