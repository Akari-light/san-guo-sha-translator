// lib/core/utils/perspective_warper.dart
//
// PerspectiveWarper — pure Dart 4-point perspective transformation.
//
// Given 4 source corner points on a camera buffer image and a target output
// rectangle, this computes the 3×3 homography matrix and produces a
// "flattened" axis-aligned image of the card.
//
// Used by the Document Scanner workflow (spec v3.0 §5.1):
//   1. User adjusts 4 corner handles on the frozen preview
//   2. Corners are transformed from widget coords to buffer pixel coords
//   3. PerspectiveWarper.warp() produces a straightened card image
//   4. Art zone is cropped from the straightened image for pHash
//   5. OCR is re-run on the straightened image for improved text recognition
//
// Algorithm: Standard 8-parameter projective (homography) transform.
//   For each output pixel (x', y'), we solve:
//     x = (h0*x' + h1*y' + h2) / (h6*x' + h7*y' + 1)
//     y = (h3*x' + h4*y' + h5) / (h6*x' + h7*y' + 1)
//   to find the corresponding source pixel (x, y), then sample via
//   bilinear interpolation.
//
// The homography matrix is computed by solving a system of 8 linear equations
// derived from the 4 corner point correspondences.
//
// No external dependencies beyond the `image` package.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:image/image.dart' as img;

/// SGS standard card aspect ratio: 63mm × 88mm.
/// Default output dimensions maintain this ratio at a reasonable resolution.
const int _defaultOutputWidth = 630;
const int _defaultOutputHeight = 880;

class PerspectiveWarper {
  PerspectiveWarper._();

  /// Warps the quadrilateral region defined by [srcCorners] in [source]
  /// into a flat, axis-aligned rectangle.
  ///
  /// [srcCorners] must contain exactly 4 [Offset] points in clockwise order
  /// starting from the top-left corner of the card:
  ///   [0] = top-left
  ///   [1] = top-right
  ///   [2] = bottom-right
  ///   [3] = bottom-left
  ///
  /// Points are in **buffer pixel coordinates** (not widget coordinates).
  /// The caller must transform widget coords → buffer coords before calling.
  ///
  /// [outputWidth] and [outputHeight] default to 630×880 (SGS card ratio 63:88).
  ///
  /// Returns a new [img.Image] of the straightened card.
  static img.Image warp(
    img.Image source,
    List<Offset> srcCorners, {
    int outputWidth = _defaultOutputWidth,
    int outputHeight = _defaultOutputHeight,
  }) {
    assert(srcCorners.length == 4, 'Exactly 4 corners required');

    // Destination corners: axis-aligned rectangle
    final dstCorners = [
      Offset(0, 0),                                               // top-left
      Offset(outputWidth.toDouble(), 0),                           // top-right
      Offset(outputWidth.toDouble(), outputHeight.toDouble()),     // bottom-right
      Offset(0, outputHeight.toDouble()),                          // bottom-left
    ];

    // Compute the inverse homography: dst → src
    // We need the inverse because for each output pixel we look up
    // where it came from in the source image.
    final h = _computeHomography(dstCorners, srcCorners);

    // Create the output image
    final output = img.Image(width: outputWidth, height: outputHeight);

    final srcW = source.width;
    final srcH = source.height;

    // For each output pixel, find the corresponding source pixel
    for (var y = 0; y < outputHeight; y++) {
      for (var x = 0; x < outputWidth; x++) {
        // Apply the homography to get source coordinates
        final dx = x.toDouble();
        final dy = y.toDouble();
        final w = h[6] * dx + h[7] * dy + 1.0;

        if (w.abs() < 1e-10) {
          // Degenerate — skip pixel
          output.setPixel(x, y, img.ColorRgba8(0, 0, 0, 0));
          continue;
        }

        final srcX = (h[0] * dx + h[1] * dy + h[2]) / w;
        final srcY = (h[3] * dx + h[4] * dy + h[5]) / w;

        // Bilinear interpolation
        final pixel = _bilinearSample(source, srcX, srcY, srcW, srcH);
        output.setPixel(x, y, pixel);
      }
    }

    return output;
  }

  /// Extracts the "Art Zone" from a straightened card image.
  ///
  /// The art zone is the vertical slice from 15% to 65% of the card height
  /// (spec v3.0 §5.2). This is where the character artwork or card
  /// illustration lives, free from text, borders, and category labels.
  ///
  /// The cropped art zone is used for pHash comparison against reference
  /// images in `assets/images/generals/*.webp` and `assets/images/library/*.webp`.
  static img.Image extractArtZone(img.Image straightened) {
    final w = straightened.width;
    final h = straightened.height;
    final top = (h * 0.15).round();
    final artH = (h * 0.50).round(); // 15% to 65% = 50% of height
    return img.copyCrop(straightened, x: 0, y: top, width: w, height: artH);
  }

  /// Encodes a decoded [image] as JPEG bytes.
  ///
  /// Convenience method for passing the warped image to MLKit
  /// (which requires a file path) or to the scanner service
  /// (which accepts Uint8List bytes).
  static Uint8List encodeJpeg(img.Image image, {int quality = 90}) {
    return Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HOMOGRAPHY COMPUTATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Computes the 8-parameter homography matrix that maps points from
  /// [src] to [dst].
  ///
  /// Given 4 point correspondences (src[i] → dst[i]), we solve the system:
  ///
  ///   [ x'_i ]   [ h0  h1  h2 ] [ x_i ]
  ///   [ y'_i ] = [ h3  h4  h5 ] [ y_i ]
  ///   [ w'_i ]   [ h6  h7  1  ] [  1  ]
  ///
  /// Where x_dst = x'/w' and y_dst = y'/w'.
  ///
  /// This yields 8 linear equations in 8 unknowns (h0..h7, with h8=1).
  /// We solve using Gaussian elimination with partial pivoting.
  ///
  /// Returns a List<double> of length 8: [h0, h1, h2, h3, h4, h5, h6, h7].
  static List<double> _computeHomography(
    List<Offset> src,
    List<Offset> dst,
  ) {
    // Build the 8×9 augmented matrix (Ah = b → [A|b])
    //
    // For each point correspondence (x, y) → (u, v):
    //   x*h0 + y*h1 + h2 - x*u*h6 - y*u*h7 = u
    //   x*h3 + y*h4 + h5 - x*v*h6 - y*v*h7 = v

    final a = List.generate(8, (_) => List<double>.filled(9, 0));

    for (var i = 0; i < 4; i++) {
      final sx = src[i].dx;
      final sy = src[i].dy;
      final dx = dst[i].dx;
      final dy = dst[i].dy;

      final r1 = i * 2;
      final r2 = r1 + 1;

      // Row for x equation
      a[r1][0] = sx;
      a[r1][1] = sy;
      a[r1][2] = 1;
      a[r1][3] = 0;
      a[r1][4] = 0;
      a[r1][5] = 0;
      a[r1][6] = -sx * dx;
      a[r1][7] = -sy * dx;
      a[r1][8] = dx; // RHS

      // Row for y equation
      a[r2][0] = 0;
      a[r2][1] = 0;
      a[r2][2] = 0;
      a[r2][3] = sx;
      a[r2][4] = sy;
      a[r2][5] = 1;
      a[r2][6] = -sx * dy;
      a[r2][7] = -sy * dy;
      a[r2][8] = dy; // RHS
    }

    // Gaussian elimination with partial pivoting
    for (var col = 0; col < 8; col++) {
      // Find pivot
      var maxRow = col;
      var maxVal = a[col][col].abs();
      for (var row = col + 1; row < 8; row++) {
        final v = a[row][col].abs();
        if (v > maxVal) {
          maxVal = v;
          maxRow = row;
        }
      }

      // Swap rows
      if (maxRow != col) {
        final tmp = a[col];
        a[col] = a[maxRow];
        a[maxRow] = tmp;
      }

      final pivot = a[col][col];
      if (pivot.abs() < 1e-12) {
        // Singular matrix — return identity-ish fallback
        return [1, 0, 0, 0, 1, 0, 0, 0];
      }

      // Eliminate below
      for (var row = col + 1; row < 8; row++) {
        final factor = a[row][col] / pivot;
        for (var j = col; j < 9; j++) {
          a[row][j] -= factor * a[col][j];
        }
      }
    }

    // Back-substitution
    final h = List<double>.filled(8, 0);
    for (var row = 7; row >= 0; row--) {
      var sum = a[row][8]; // RHS
      for (var col = row + 1; col < 8; col++) {
        sum -= a[row][col] * h[col];
      }
      h[row] = sum / a[row][row];
    }

    return h;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BILINEAR INTERPOLATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Samples a pixel from [source] at fractional coordinates (sx, sy) using
  /// bilinear interpolation. Returns black for out-of-bounds coordinates.
  static img.Color _bilinearSample(
    img.Image source,
    double sx,
    double sy,
    int srcW,
    int srcH,
  ) {
    if (sx < 0 || sy < 0 || sx >= srcW - 1 || sy >= srcH - 1) {
      // Clamp to edge for coordinates slightly out of bounds
      final cx = sx.round().clamp(0, srcW - 1);
      final cy = sy.round().clamp(0, srcH - 1);
      if (cx >= 0 && cx < srcW && cy >= 0 && cy < srcH) {
        return source.getPixel(cx, cy);
      }
      return img.ColorRgba8(0, 0, 0, 255);
    }

    final x0 = sx.floor();
    final y0 = sy.floor();
    final x1 = x0 + 1;
    final y1 = y0 + 1;

    final fx = sx - x0;
    final fy = sy - y0;

    final p00 = source.getPixel(x0, y0);
    final p10 = source.getPixel(x1, y0);
    final p01 = source.getPixel(x0, y1);
    final p11 = source.getPixel(x1, y1);

    // Interpolate each channel
    int lerp(num a, num b, num c, num d) {
      final v = a.toDouble() * (1 - fx) * (1 - fy) +
                b.toDouble() * fx * (1 - fy) +
                c.toDouble() * (1 - fx) * fy +
                d.toDouble() * fx * fy;
      return v.round().clamp(0, 255);
    }

    return img.ColorRgba8(
      lerp(p00.r, p10.r, p01.r, p11.r),
      lerp(p00.g, p10.g, p01.g, p11.g),
      lerp(p00.b, p10.b, p01.b, p11.b),
      lerp(p00.a, p10.a, p01.a, p11.a),
    );
  }
}