import 'package:flutter/material.dart';
import '../../data/models/general_card.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/app_assets.dart';

/// Reusable grid tile for a single general card.
/// Shows the card image with a faction colour accent bar,
/// name, health, and expansion badge overlaid at the bottom.
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
                errorBuilder: (context, error, stackTrace) => Container(
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
                    horizontal: 7,
                    vertical: 4,
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
                      fontSize: 14,
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