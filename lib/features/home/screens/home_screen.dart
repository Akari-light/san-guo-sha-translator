import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // make the page scrollable if the pinned list gets long
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildWelcomeHeader(),
          const SizedBox(height: 24),
          _buildPinnedSection(),
        ],
      ),
    );
  }

  // Welcome Section: Gives the app a friendly entry point
  Widget _buildWelcomeHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome, Warrior',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        Text(
          'Quickly access your current game cards below.',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      ],
    );
  }

  // Pinned Section: This is the placeholder for your "Quick Access" idea
  Widget _buildPinnedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.push_pin, size: 20, color: Colors.red),
            SizedBox(width: 8),
            Text(
              'Pinned Generals',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // This container acts as the placeholder for your future pinned logic
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey..withValues(alpha: 0.2)),
          ),
          child: const Column(
            children: [
              Icon(Icons.person_add_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'No generals pinned yet.',
                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
              ),
              Text(
                'Go to the Generals tab to pin a card.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}