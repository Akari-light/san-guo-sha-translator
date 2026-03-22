// lib/core/services/scanner_service.dart
//
// Core scanning service — no feature imports.
// MatchCandidate is the canonical definition; ai_screen.dart imports it from here.
// RecordType is imported from recently_viewed_service.dart (already a core service).

import 'dart:typed_data';
import 'recently_viewed_service.dart'; // for RecordType

// ── MatchCandidate ─────────────────────────────────────────────────────────────
// Single canonical definition. ai_screen.dart imports this; it no longer
// defines its own MatchCandidate.

class MatchCandidate {
  final String cardId;
  final RecordType recordType; // RecordType enum — not a raw string
  final String nameCn;
  final String nameEn;
  final String imagePath;
  final double confidence;

  const MatchCandidate({
    required this.cardId,
    required this.recordType,
    required this.nameCn,
    required this.nameEn,
    required this.imagePath,
    required this.confidence,
  });
}

// ── ScannerResult ──────────────────────────────────────────────────────────────

class ScannerResult {
  /// Ranked match candidates (empty when no match found).
  /// Replaces the old single-match cardId/recordType/confidence fields.
  final List<MatchCandidate> candidates;

  /// Human-readable status for logging.
  final String debugMessage;

  const ScannerResult({
    this.candidates = const [],
    required this.debugMessage,
  });

  bool get hasMatch => candidates.isNotEmpty;
}

// ── ScannerService ─────────────────────────────────────────────────────────────
//
// Stub — match() always returns empty candidates.
// When vector matching is ready: replace _runMatching() body only.
// The public match() API and ScannerResult shape are locked.

class ScannerService {
  ScannerService._();
  static final ScannerService instance = ScannerService._();

  Future<ScannerResult> match(
    Uint8List bytes, {
    String sourceLabel = 'camera',
  }) async {
    await Future.delayed(const Duration(milliseconds: 800));
    return _runMatching(bytes, sourceLabel);
  }

  ScannerResult _runMatching(Uint8List bytes, String sourceLabel) {
    // Replace this body when vectors are ready.
    // Return a ScannerResult with a populated candidates list.
    return ScannerResult(
      debugMessage:
          '[STUB] match() called — $sourceLabel, ${bytes.lengthInBytes} bytes. '
          'Vector matching not yet implemented.',
    );
  }
}