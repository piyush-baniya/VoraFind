import 'dart:math' as math;

import 'embedding_provider.dart';
import 'semantic_models.dart';

/// A fully local, zero-model-file on-device text embedding.
///
/// Technique: character n-gram count sketch with signed hashing (locality-
/// sensitive random projection). Two texts sharing subword characters land
/// closer in cosine space than unrelated text. Used here as the first
/// real embedding VoraFind can ship today — zero model file, zero native
/// runtime, zero APK impact, fully offline.
///
/// Deterministic, bounded to exactly [dimensions] entries, input capped at
/// [SemanticDefaults.maxInputChars]. Replaces the previous placeholder and
/// is wired as the default production provider (docs `semantic-search.md`).
class LocalEmbeddingProvider implements EmbeddingProvider {
  const LocalEmbeddingProvider({this.dimensions = SemanticDefaults.dimensions});

  @override
  final int dimensions;

  static const int _seed = 0x9e3779b9;

  @override
  String get modelId => 'local-ngram-rp-$dimensions';

  @override
  bool get isAvailable => true;

  @override
  Future<List<double>> embed(String text) async => _embed(text);

  List<double> _embed(String text) {
    final canonical = _normalize(text);
    if (canonical.isEmpty) {
      return List<double>.filled(dimensions, 0);
    }

    final vector = List<double>.filled(dimensions, 0);
    final truncated = canonical.length > SemanticDefaults.maxInputChars
        ? canonical.substring(0, SemanticDefaults.maxInputChars)
        : canonical;

    for (int i = 0; i + 4 <= truncated.length; i++) {
      _accumulateHash(truncated.substring(i, i + 4), vector);
    }
    for (int i = 0; i + 3 <= truncated.length; i++) {
      _accumulateHash(truncated.substring(i, i + 3), vector);
    }

    return _l2Normalize(vector);
  }

  void _accumulateHash(String ngram, List<double> vector) {
    final hash = _hash32(ngram);
    final bucket = (hash & 0x7fffffff) % dimensions;
    final sign = (hash & 0x80000000) != 0 ? 1.0 : -1.0;
    vector[bucket] += sign;
  }

  int _hash32(String s) {
    var hash = _seed;
    for (int i = 0; i < s.length; i++) {
      hash ^= s.codeUnitAt(i);
      hash *= 0x1000193;
      hash ^= (hash >> 16);
      hash *= 0x85ebca6b;
      hash ^= (hash >> 13);
      hash *= 0xc2b2ae35;
      hash ^= (hash >> 16);
    }
    return hash;
  }

  String _normalize(String text) {
    final cleaned = text.toLowerCase().replaceAll(
      RegExp(r'[^\p{L}\p{N}]+', unicode: true),
      ' ',
    );
    return cleaned.trim();
  }

  List<double> _l2Normalize(List<double> vector) {
    var norm = 0.0;
    for (final v in vector) {
      norm += v * v;
    }
    if (norm <= 0) return vector;
    final root = math.sqrt(norm);
    return [for (final v in vector) v / root];
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async =>
      texts.map(_embed).toList(growable: false);

  @override
  Future<void> dispose() async {}
}
