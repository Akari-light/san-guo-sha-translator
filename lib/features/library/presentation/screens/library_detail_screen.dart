import 'package:flutter/material.dart';
import '../../data/models/library_dto.dart';

class LibraryDetailScreen extends StatefulWidget {
  final LibraryDTO card;
  const LibraryDetailScreen({super.key, required this.card});

  @override
  State<LibraryDetailScreen> createState() => _LibraryDetailScreenState();
}

class _LibraryDetailScreenState extends State<LibraryDetailScreen> {
  bool _isEnglish = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final card = widget.card;

    final syntaxColor = isDark
        ? (_isEnglish ? const Color(0xFF9CDCFE) : const Color(0xFFCE9178))
        : theme.textTheme.bodyLarge?.color;

    return Scaffold(
      appBar: AppBar(
        title: Text(card.nameCn),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card image
            Center(
              child: Hero(
                tag: card.id,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    card.imagePath,
                    height: 300,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        Image.asset(LibraryDTO.placeholderImagePath, height: 300),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Header row: name + language toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEnglish ? card.nameEn : card.nameCn,
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _isEnglish ? card.categoryEn : card.categoryCn,
                        style: TextStyle(
                          color: card.categoryColor(isDark),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _isEnglish = !_isEnglish),
                  style: TextButton.styleFrom(
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.1),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(
                    _isEnglish ? "EN ➔ 中" : "中 ➔ EN",
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),

            if (card.range != null) ...[
              const SizedBox(height: 12),
              _buildStatBadge(
                context,
                _isEnglish ? "Range" : "攻击距离",
                card.range.toString(),
              ),
            ],

            const Divider(height: 32),

            // Effect section
            Text(
              _isEnglish ? "EFFECT" : "技能描述",
              style: theme.textTheme.labelLarge?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 12),
            Text(
              _isEnglish
                  ? card.effectEn.join('\n\n')
                  : card.effectCn.join('\n\n'),
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.6,
                color: syntaxColor,
              ),
            ),

            // FAQ section
            if (card.faq.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                _isEnglish ? "RULES & FAQ" : "常见问题",
                style:
                    theme.textTheme.labelLarge?.copyWith(color: theme.hintColor),
              ),
              const SizedBox(height: 12),
              ...card.faq.map((f) => _buildFaqTile(context, f, _isEnglish)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatBadge(BuildContext context, String label, String value) {
    const color = Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ',
              style: const TextStyle(
                  color: color, fontWeight: FontWeight.bold)),
          Text(value,
              style: const TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildFaqTile(
      BuildContext context, Map<String, String> faq, bool isEnglish) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEnglish
                ? "Q: ${faq['q_en']}"
                : "问: ${faq['q_cn'] ?? faq['q_en']}",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark
                  ? const Color(0xFF9CDCFE)
                  : colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isEnglish
                ? "A: ${faq['a_en']}"
                : "答: ${faq['a_cn'] ?? faq['a_en']}",
            style: TextStyle(
              color: isDark
                  ? const Color(0xFFCE9178)
                  : colorScheme.secondary,
            ),
          ),
        ],
      ),
    );
  }
}