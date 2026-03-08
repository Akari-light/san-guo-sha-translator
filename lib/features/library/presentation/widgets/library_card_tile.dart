import 'package:flutter/material.dart';
import '../../data/models/library_dto.dart';
import '../../../../core/constants/app_assets.dart';

/// Reusable grid tile for a single library card.
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
    return GestureDetector(
      onTap: onTap,
      child: Hero(
        tag: card.id,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              card.imagePath,
              fit: BoxFit.fill,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.black12,
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
      ),
    );
  }
}