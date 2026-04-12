import 'package:flutter/material.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/theme/app_theme.dart';

class GeneralCardTile extends StatelessWidget {
  final String imagePath;
  final String faction;
  final String expansionBadge;
  final bool isSkin;
  final bool isFallback;
  final VoidCallback onTap;

  const GeneralCardTile({
    super.key,
    required this.imagePath,
    required this.faction,
    required this.expansionBadge,
    this.isSkin = false,
    this.isFallback = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final factionColor = AppTheme.factionColor(faction);
    final variantBadge = isFallback
        ? 'ART'
        : isSkin
            ? 'SKIN'
            : null;

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
              Image.asset(
                imagePath,
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
              if (expansionBadge.isNotEmpty)
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
                      expansionBadge,
                      style: TextStyle(
                        color: factionColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              if (variantBadge != null)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white54, width: 0.5),
                    ),
                    child: Text(
                      variantBadge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
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
