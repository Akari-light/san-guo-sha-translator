import 'package:flutter/material.dart';
import '../../../data/models/library_card.dart';

class LibraryDetailScreen extends StatelessWidget {
  final LibraryCard card;

  const LibraryDetailScreen({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    // Access the global theme and brightness state
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(card.nameEn),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Visual
            Center(
              child: Hero(
                tag: card.id,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      card.imagePath,
                      height: 300,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.asset(
                            'assets/images/library_placeholder.webp',
                            height: 300,
                            fit: BoxFit.contain,
                          ),
                          const Icon(Icons.report_problem, color: Colors.amber, size: 40),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Identification Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // CN Name uses default headline/body color from theme
                    Text(card.nameCn, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                    Text(
                      card.categoryEn, 
                      style: TextStyle(
                        color: _getCategoryColor(card.categoryEn, isDark), 
                        fontWeight: FontWeight.w600
                      )
                    ),
                  ],
                ),
                if (card.range != null)
                  _buildStatBadge(context, "Range", card.range.toString(), Colors.redAccent),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Divider(),
            ),

            // Effect Section
            Text(
              "EFFECT", 
              style: theme.textTheme.labelLarge?.copyWith(color: theme.hintColor)
            ),
            const SizedBox(height: 8),
            ...card.effectEn.map((effect) => Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Text(
                effect,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
              ),
            )),

            // FAQ Section
            if (card.faq.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                "RULES & FAQ", 
                style: theme.textTheme.labelLarge?.copyWith(color: theme.hintColor)
              ),
              const SizedBox(height: 12),
              ...card.faq.map((f) => _buildFaqTile(context, f)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatBadge(BuildContext context, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1), 
        borderRadius: BorderRadius.circular(8), 
        border: Border.all(color: color)
      ),
      child: Row(
        children: [
          Text("$label: ", style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildFaqTile(BuildContext context, Map<String, String> faq) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Dynamic: Pulls from 'surfaceContainer' or 'surfaceVariant'
        color: colorScheme.surfaceContainerHighest, 
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant, // Dynamic border color
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Q: ${faq['q_en']}", 
            style: TextStyle(
              fontWeight: FontWeight.bold, 
              // Dynamic: Uses the theme's Primary color (Blue in your Dark+ theme)
              color: colorScheme.primary, 
            )
          ),
          const SizedBox(height: 8),
          Text(
            "A: ${faq['a_en']}", 
            style: TextStyle(
              // Dynamic: Uses the theme's Secondary color (Teal/Orange in your Dark+ theme)
              color: colorScheme.secondary, 
            )
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(String category, bool isDark) {
    // Slightly brighter versions for dark mode visibility
    switch (category) {
      case "Basic": return isDark ? Colors.greenAccent : Colors.green.shade700;
      case "Weapon": return isDark ? Colors.redAccent : Colors.red.shade700;
      case "Armor": return isDark ? Colors.blueAccent : Colors.blue.shade700;
      case "Mount": return isDark ? const Color(0xFFD2B48C) : Colors.brown;
      case "Tool": return isDark ? Colors.orangeAccent : Colors.orange.shade800;
      default: return Colors.grey;
    }
  }
}