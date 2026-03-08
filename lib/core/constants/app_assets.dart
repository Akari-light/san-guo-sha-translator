/// Central registry for all static asset paths used across the app.
///
/// Presentation widgets import this file instead of referencing asset
/// paths on model classes or hardcoding strings locally. When real card
/// images are uploaded, only the models' [imagePath] instance getters
/// need updating — placeholder fallbacks are changed here once.
abstract final class AppAssets {
  // ── Placeholder images 
  static const String generalPlaceholder =
      'assets/images/generals_placeholder.webp';
  static const String libraryPlaceholder =
      'assets/images/library_placeholder.webp';
}