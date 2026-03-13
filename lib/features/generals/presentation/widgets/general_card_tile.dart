import 'package:flutter/material.dart';
import '../../data/models/general_card.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/app_assets.dart';

/// Reusable grid tile for a single general card.
/// Shows the card image with a faction colour accent border,
/// name badge and expansion badge overlaid on the image.
///
/// Dimensions are driven entirely by the parent grid's childAspectRatio.
/// All three grids (GeneralScreen, LibraryScreen, HomeScreen thumbnails)
/// use the canonical SGS card ratio: 63 / 88 ≈ 0.716.
class GeneralCardTile extends StatelessWidget {
  final GeneralCard card;
  final VoidCallback onTap;

  const GeneralCardTile({
    super.key,
    required this.card,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final factionColor = AppTheme.factionColor(card.faction);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: factionColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: factionColor.withValues(alpha: 0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Card image
              Image.asset(
                card.imagePath,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: factionColor.withValues(alpha: 0.1),
                  child: Center(
                    child: Image.asset(
                      AppAssets.generalPlaceholder,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),

              // ── Expansion badge (top-right)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white54, width: 0.5),
                  ),
                  child: Text(
                    card.expansionBadge,
                    style: TextStyle(
                      color: factionColor,
                      // 11pt fits both single-char badges (界, 神, 魔)
                      // and two-char badges (神话) without overflow.
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}