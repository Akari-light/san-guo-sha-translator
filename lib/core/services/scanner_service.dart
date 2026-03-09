import 'dart:typed_data';

/// Result returned by [ScannerService.match].
class ScannerResult {
  /// Matched card ID or null if no match found.
  final String? cardId;

  /// 'general' | 'library' — null when [cardId] is null.
  final String? recordType;

  /// Confidence score 0.0–1.0. Always 0.0 while stub.
  final double confidence;

  /// Human-readable status for the dev debug panel.
  final String debugMessage;

  const ScannerResult({
    this.cardId,
    this.recordType,
    this.confidence = 0.0,
    required this.debugMessage,
  });

  bool get hasMatch => cardId != null;
}

/// One entry in the match candidates bottom sheet.
class MatchCandidate {
  final String cardId;
  final String recordType; // 'general' | 'library'
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

/// Card image matching service.
///
/// Stub — [match] always returns no candidates.
/// When vector matching is ready: replace [_runMatching] only.
/// [AiScreen] API contract stays unchanged.
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
    return ScannerResult(
      debugMessage:
          '[STUB] match() called — $sourceLabel, ${bytes.lengthInBytes} bytes. '
          'Vector matching not yet implemented.',
    );
  }
}