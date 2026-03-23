// lib/core/services/image_hash_matcher.dart
//
// Pure Dart perceptual hash (pHash) implementation for card artwork comparison.
// Used as Stage 2 of the camera card lookup pipeline to break ties after OCR
// narrows the candidate list to 2–5 cards.
//
// pHash works by:
//   1. Resize image to 32×32 greyscale
//   2. Apply a discrete cosine transform (DCT)
//   3. Take the top-left 8×8 block of DCT coefficients (64 values)
//   4. Compare each value against the median → produces a 64-bit fingerprint
//
// Two images with similar content produce similar hashes. The Hamming distance
// between hashes (number of differing bits) measures visual dissimilarity.
// A distance of ≤10 bits out of 64 reliably indicates the same card artwork.
//
// No external packages beyond `image` (already in pubspec.yaml for image processing).
// No network calls, no model files — runs in ~1–3ms per comparison.

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class ImageHashMatcher {
  ImageHashMatcher._();
  static final ImageHashMatcher instance = ImageHashMatcher._();

  // ── Internal hash cache ──────────────────────────────────────────────────
  // Keyed by asset path. Populated lazily on first comparison per asset.
  // Never invalidated — reference images don't change between app launches.
  final Map<String, int> _hashCache = {};

  // ── Public API ───────────────────────────────────────────────────────────

  /// Computes the 64-bit pHash of [bytes] (any image format supported by the
  /// `image` package — JPEG, WebP, PNG).
  ///
  /// Returns null if [bytes] cannot be decoded.
  int? hashFromBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return _computeHash(decoded);
  }

  /// Loads [assetPath] from the Flutter asset bundle, decodes it, and returns
  /// its 64-bit pHash. Result is cached — subsequent calls for the same path
  /// return immediately without re-loading.
  ///
  /// Returns null if the asset cannot be loaded or decoded.
  Future<int?> hashFromAsset(String assetPath) async {
    if (_hashCache.containsKey(assetPath)) return _hashCache[assetPath];
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final hash = _computeHash(decoded);
      _hashCache[assetPath] = hash;
      return hash;
    } catch (_) {
      return null;
    }
  }

  /// Returns a similarity score in [0.0, 1.0] between two hashes.
  ///
  /// 1.0 = identical images.
  /// ≥0.8 = very likely the same card artwork.
  /// ≤0.5 = clearly different images.
  ///
  /// Computed as: 1.0 − (Hamming distance / 64).
  double similarity(int hashA, int hashB) {
    final distance = _hammingDistance(hashA, hashB);
    return 1.0 - (distance / 64.0);
  }

  /// Clears the internal asset hash cache.
  /// Not needed in normal operation — only for testing.
  void clearCache() => _hashCache.clear();

  // ── pHash implementation ─────────────────────────────────────────────────

  int _computeHash(img.Image source) {
    // Step 1 — resize to 32×32 greyscale
    final resized = img.copyResize(source, width: 32, height: 32);
    final grey = img.grayscale(resized);

    // Step 2 — extract pixel values as doubles
    final pixels = List<double>.generate(32 * 32, (i) {
      final x = i % 32;
      final y = i ~/ 32;
      return grey.getPixel(x, y).r.toDouble();
    });

    // Step 3 — apply 2D DCT (32×32 → keep top-left 8×8)
    final dct = _dct2d(pixels, 32);

    // Step 4 — extract all 64 values from the top-left 8×8 DCT block
    final allBlock = <double>[];
    for (var row = 0; row < 8; row++) {
      for (var col = 0; col < 8; col++) {
        allBlock.add(dct[row * 32 + col]);
      }
    }

    // Step 5 — compute median of all 64 values
    final sorted64 = List<double>.from(allBlock)..sort();
    final median64 = sorted64[32];

    // Step 6 — build 64-bit hash: bit = 1 if value ≥ median
    var hash = 0;
    for (var i = 0; i < 64; i++) {
      if (allBlock[i] >= median64) {
        hash |= (1 << i);
      }
    }
    return hash;
  }

  // 2D DCT using the separable property: DCT-2D = DCT-1D on rows then columns.
  // Input: flat [size × size] pixel array, row-major.
  // Output: flat [size × size] DCT coefficient array.
  List<double> _dct2d(List<double> pixels, int size) {
    // Apply 1D DCT to each row
    final rowDct = List<double>.filled(size * size, 0);
    for (var row = 0; row < size; row++) {
      final rowData = List<double>.generate(size, (i) => pixels[row * size + i]);
      final dctRow = _dct1d(rowData);
      for (var col = 0; col < size; col++) {
        rowDct[row * size + col] = dctRow[col];
      }
    }

    // Apply 1D DCT to each column
    final result = List<double>.filled(size * size, 0);
    for (var col = 0; col < size; col++) {
      final colData = List<double>.generate(size, (i) => rowDct[i * size + col]);
      final dctCol = _dct1d(colData);
      for (var row = 0; row < size; row++) {
        result[row * size + col] = dctCol[row];
      }
    }
    return result;
  }

  // 1D DCT-II (orthonormal form).
  // Standard formula: X[k] = scale(k) × Σ x[n] × cos(π×k×(2n+1) / (2N))
  List<double> _dct1d(List<double> x) {
    final n = x.length;
    final result = List<double>.filled(n, 0);
    final piOverTwoN = math.pi / (2 * n);

    for (var k = 0; k < n; k++) {
      var sum = 0.0;
      for (var i = 0; i < n; i++) {
        sum += x[i] * math.cos(piOverTwoN * k * (2 * i + 1));
      }
      // Orthonormal scaling
      final scale = k == 0
          ? math.sqrt(1.0 / n)
          : math.sqrt(2.0 / n);
      result[k] = sum * scale;
    }
    return result;
  }

  int _hammingDistance(int a, int b) {
    // Count differing bits using Brian Kernighan's algorithm
    var xor = a ^ b;
    var count = 0;
    while (xor != 0) {
      xor &= xor - 1;
      count++;
    }
    return count;
  }
}