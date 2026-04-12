import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

const int _embeddingDim = 1280;
const int _inputSize = 224;
const _imagenetMean = [0.485, 0.456, 0.406];
const _imagenetStd = [0.229, 0.224, 0.225];
const _bundleMagic = 'SGSV';
const _bundleVersion = 2;

enum ReferenceEmbeddingType {
  canonical,
  augmented,
  photo,
  unknown,
}

class ReferenceEmbeddingEntry {
  final String referenceId;
  final String logicalCardId;
  final ReferenceEmbeddingType type;
  final Float32List embedding;

  const ReferenceEmbeddingEntry({
    required this.referenceId,
    required this.logicalCardId,
    required this.type,
    required this.embedding,
  });
}

class ReferenceEmbeddingMatch {
  final String logicalCardId;
  final String referenceId;
  final ReferenceEmbeddingType type;
  final double similarity;

  const ReferenceEmbeddingMatch({
    required this.logicalCardId,
    required this.referenceId,
    required this.type,
    required this.similarity,
  });
}

class ImageEmbeddingMatcher {
  ImageEmbeddingMatcher._();
  static final ImageEmbeddingMatcher instance = ImageEmbeddingMatcher._();

  Interpreter? _interpreter;
  bool _modelLoaded = false;

  final List<ReferenceEmbeddingEntry> _referenceEntries = [];
  final Map<String, List<ReferenceEmbeddingEntry>> _referencesByLogicalCard = {};
  final Map<String, Float32List> _runtimeCache = {};

  Future<void> loadModel() async {
    if (_modelLoaded) return;
    try {
      _interpreter = await Interpreter.fromAsset('models/mobilenet_v2.tflite');
      debugPrint('[Embedding] Model loaded: '
          'input=${_interpreter!.getInputTensor(0).shape}, '
          'output=${_interpreter!.getOutputTensor(0).shape}');
      _modelLoaded = true;
    } catch (e) {
      debugPrint('[Embedding] Failed to load model: $e');
    }
  }

  Future<void> loadReferenceEmbeddings() async {
    _referenceEntries.clear();
    _referencesByLogicalCard.clear();

    try {
      final data = await rootBundle.load('assets/data/general_embeddings.bin');
      final byteView = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final prefix = data.lengthInBytes >= 4
          ? String.fromCharCodes(byteView.sublist(0, 4))
          : '';

      if (prefix == _bundleMagic) {
        _loadVersionedBundle(data);
      } else {
        _loadLegacyBundle(data);
      }

      debugPrint('[Embedding] Loaded ${_referenceEntries.length} references '
          'across ${_referencesByLogicalCard.length} logical cards.');
    } catch (e) {
      debugPrint('[Embedding] Failed to load reference embeddings: $e '
          '(run tools/generate_embeddings.py to create the file)');
    }
  }

  bool get isReady => _modelLoaded;
  int get referenceCount => _referenceEntries.length;
  int get logicalCardCount => _referencesByLogicalCard.length;

  Float32List? embeddingFromBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null || !_modelLoaded) return null;
    return _computeEmbedding(decoded);
  }

  Float32List? embeddingFromImage(img.Image image) {
    if (!_modelLoaded) return null;
    return _computeEmbedding(image);
  }

  Float32List? getReferenceEmbedding(String cardId) {
    final refs = _referencesByLogicalCard[cardId];
    if (refs == null || refs.isEmpty) return null;
    return refs.first.embedding;
  }

  Float32List? getCachedHash(String assetPath) => _runtimeCache[assetPath];

  Future<Float32List?> hashFromAsset(String assetPath) async {
    if (_runtimeCache.containsKey(assetPath)) return _runtimeCache[assetPath];
    if (!_modelLoaded) return null;
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final embedding = _computeEmbedding(decoded);
      if (embedding != null) {
        _runtimeCache[assetPath] = embedding;
      }
      return embedding;
    } catch (_) {
      return null;
    }
  }

  double similarity(Float32List embA, Float32List embB) {
    if (embA.length != embB.length) return 0.0;
    double dot = 0.0;
    for (var i = 0; i < embA.length; i++) {
      dot += embA[i] * embB[i];
    }
    return dot.clamp(0.0, 1.0);
  }

  double similarityToLogicalCard(Float32List queryEmbedding, String logicalCardId) {
    final refs = _referencesByLogicalCard[logicalCardId];
    if (refs == null || refs.isEmpty) return 0.0;

    var best = 0.0;
    for (final ref in refs) {
      final sim = similarity(queryEmbedding, ref.embedding);
      if (sim > best) {
        best = sim;
      }
    }
    return best;
  }

  List<ReferenceEmbeddingMatch> findTopKLogicalCards(
    Float32List queryEmbedding, {
    int k = 5,
  }) {
    final bestByLogicalId = <String, ReferenceEmbeddingMatch>{};

    for (final ref in _referenceEntries) {
      final sim = similarity(queryEmbedding, ref.embedding);
      final current = bestByLogicalId[ref.logicalCardId];
      if (current == null || sim > current.similarity) {
        bestByLogicalId[ref.logicalCardId] = ReferenceEmbeddingMatch(
          logicalCardId: ref.logicalCardId,
          referenceId: ref.referenceId,
          type: ref.type,
          similarity: sim,
        );
      }
    }

    final matches = bestByLogicalId.values.toList()
      ..sort((a, b) => b.similarity.compareTo(a.similarity));
    return matches.take(k).toList();
  }

  void clearCache() {
    _runtimeCache.clear();
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _modelLoaded = false;
  }

  void _loadLegacyBundle(ByteData data) {
    final bytes = data.buffer.asByteData(data.offsetInBytes, data.lengthInBytes);
    var offset = 0;
    final count = bytes.getUint32(offset, Endian.little);
    offset += 4;

    for (var i = 0; i < count; i++) {
      final idLen = bytes.getUint32(offset, Endian.little);
      offset += 4;
      final idBytes = data.buffer.asUint8List(data.offsetInBytes + offset, idLen);
      final id = String.fromCharCodes(idBytes);
      offset += idLen;

      final embedding = Float32List(_embeddingDim);
      for (var j = 0; j < _embeddingDim; j++) {
        embedding[j] = bytes.getFloat32(offset, Endian.little);
        offset += 4;
      }

      _registerReference(ReferenceEmbeddingEntry(
        referenceId: id,
        logicalCardId: id,
        type: ReferenceEmbeddingType.canonical,
        embedding: embedding,
      ));
    }
  }

  void _loadVersionedBundle(ByteData data) {
    final bytes = data.buffer.asByteData(data.offsetInBytes, data.lengthInBytes);
    var offset = 4;
    final version = bytes.getUint32(offset, Endian.little);
    offset += 4;
    if (version != _bundleVersion) {
      throw UnsupportedError(
        'Unsupported embedding bundle version: $version',
      );
    }

    final dim = bytes.getUint32(offset, Endian.little);
    offset += 4;
    if (dim != _embeddingDim) {
      throw UnsupportedError('Unexpected embedding dim: $dim');
    }

    final count = bytes.getUint32(offset, Endian.little);
    offset += 4;

    for (var i = 0; i < count; i++) {
      final referenceIdLen = bytes.getUint32(offset, Endian.little);
      offset += 4;
      final referenceId = String.fromCharCodes(
        data.buffer.asUint8List(data.offsetInBytes + offset, referenceIdLen),
      );
      offset += referenceIdLen;

      final logicalIdLen = bytes.getUint32(offset, Endian.little);
      offset += 4;
      final logicalCardId = String.fromCharCodes(
        data.buffer.asUint8List(data.offsetInBytes + offset, logicalIdLen),
      );
      offset += logicalIdLen;

      final typeIndex = bytes.getUint8(offset);
      offset += 1;
      final type = typeIndex >= 0 && typeIndex < ReferenceEmbeddingType.values.length
          ? ReferenceEmbeddingType.values[typeIndex]
          : ReferenceEmbeddingType.unknown;

      final embedding = Float32List(_embeddingDim);
      for (var j = 0; j < _embeddingDim; j++) {
        embedding[j] = bytes.getFloat32(offset, Endian.little);
        offset += 4;
      }

      _registerReference(ReferenceEmbeddingEntry(
        referenceId: referenceId,
        logicalCardId: logicalCardId,
        type: type,
        embedding: embedding,
      ));
    }
  }

  void _registerReference(ReferenceEmbeddingEntry entry) {
    _referenceEntries.add(entry);
    _referencesByLogicalCard.putIfAbsent(entry.logicalCardId, () => []).add(entry);
  }

  Float32List? _computeEmbedding(img.Image source) {
    if (_interpreter == null) return null;

    final resized = img.copyResize(source, width: _inputSize, height: _inputSize);

    final input = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(
          _inputSize,
          (x) {
            final pixel = resized.getPixel(x, y);
            return [
              (pixel.r.toDouble() / 255.0 - _imagenetMean[0]) / _imagenetStd[0],
              (pixel.g.toDouble() / 255.0 - _imagenetMean[1]) / _imagenetStd[1],
              (pixel.b.toDouble() / 255.0 - _imagenetMean[2]) / _imagenetStd[2],
            ];
          },
        ),
      ),
    );

    final outputShape = _interpreter!.getOutputTensor(0).shape;
    final outputSize = outputShape.last;
    final output = List.generate(1, (_) => List<double>.filled(outputSize, 0));

    try {
      _interpreter!.run(input, output);
    } catch (e) {
      debugPrint('[Embedding] Inference error: $e');
      return null;
    }

    final embedding = Float32List(outputSize);
    double norm = 0.0;
    for (var i = 0; i < outputSize; i++) {
      embedding[i] = output[0][i];
      norm += embedding[i] * embedding[i];
    }
    norm = math.sqrt(norm);
    if (norm > 1e-10) {
      for (var i = 0; i < outputSize; i++) {
        embedding[i] /= norm;
      }
    }

    return embedding;
  }
}

