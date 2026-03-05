import 'package:flutter/material.dart';
import '../../data/models/general_card.dart';
import '../../../../core/theme/app_theme.dart';

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
      child: Hero(
        tag: card.id,
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
                // ── Card image ───────────────────────────────────────────────
                Image.asset(
                  card.imagePath,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: factionColor.withValues(alpha: 0.1),
                    child: Center(
                      child: Image.asset(
                        GeneralCard.placeholderImagePath,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),

                // ── Bottom info bar ──────────────────────────────────────────
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.85),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        // Name
                        Expanded(
                          child: Text(
                            card.nameEn,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              shadows: [
                                Shadow(
                                  color: Colors.black,
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Health
                        Text(
                          '♥${card.health}',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Expansion badge (top-right) ──────────────────────────────
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: factionColor.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      card.expansionBadge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}