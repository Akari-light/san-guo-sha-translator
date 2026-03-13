import 'package:flutter/material.dart';
import '../../data/models/library_dto.dart';
import '../../../../core/constants/app_assets.dart';

/// Reusable grid tile for a single library card.
///
/// Dimensions are driven entirely by the parent grid's childAspectRatio.
/// Uses the canonical SGS card ratio: 63 / 88 ≈ 0.716, matching GeneralCardTile.
class LibraryCardTile extends StatelessWidget {
  final LibraryDTO card;
  final VoidCallback onTap;

  const LibraryCardTile({
    super.key,
    required this.card,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Neutral border that respects theme — library cards have no faction
    // colour, but the border gives visual weight matching GeneralCardTile.
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.12);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          // BoxFit.cover (was .fill) — preserves the image's native aspect
          // ratio and crops to fill the tile without distorting the artwork.
          child: Image.asset(
            card.imagePath,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.04),
              child: Center(
                child: Image.asset(
                  AppAssets.libraryPlaceholder,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}