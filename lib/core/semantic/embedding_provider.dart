import 'dart:math' as math;

import 'semantic_models.dart';

/// An embedding of one semantic input (a [String]) into a fixed-dimensional
/// float vector.
///
/// This is the **only** thing the rest of VoraFind knows about vectors; the ML
/// runtime (LiteRT/TFLite/ONNX) lives entirely behind implementations of this
/// interface (docs `semantic-search.md` §Embedding provider). `SearchService`
/// and the coordinators never touch ML types.
abstract interface class EmbeddingProvider {
  /// Stable identity of the current model / embedding configuration. Changing
  /// this (or the vector [dimensions]) invalidates every stored embedding —
  /// see `docs/semantic-search.md` §Versioning.
  String get modelId;

  /// Dimensionality of every returned vector.
  int get dimensions;

  /// True when the local model is available and [embed] may be called.
  bool get isAvailable;

  /// Produces one normalized embedding for [text].
  ///
  /// Must return a vector of exactly [dimensions] entries, or throw an
  /// [EmbeddingException] (wrong-dimension/zero/NaN results are surfaced as
  /// exceptions, never as malformed output — callers persist a durable failed
  /// status). Implementations may perform I/O (model load, inference).
  Future<List<double>> embed(String text);

  /// Produces [embeddings] for [texts] in order. Defaults to sequential
  /// [embed] calls; implementations with batched inference override this.
  Future<List<List<double>>> embedBatch(List<String> texts) =>
      Future.wait(texts.map(embed));

  /// Releases any native/model resources. Releasing the only available
  /// provider marks the subsystem unavailable but is never destructive to the
  /// persisted index.
  Future<void> dispose();
}

/// Reasons an embedding could not be produced, mapped to a durable status by
/// the consumer (docs `semantic-search.md` §Indexing lifecycle).
enum EmbeddingErrorCode {
  /// Unsupported/empty input the model will never embed.
  unsupportedInput,

  /// The runtime produced no usable vector (zero, NaN, wrong dimensions).
  invalidOutput,

  /// The local model runtime is unavailable or not yet shipped.
  unavailable,

  /// Any other transient failure (busy, initialization, native error) —
  /// retried after the cooldown.
  failed,
}

class EmbeddingException implements Exception {
  const EmbeddingException(this.code);

  final EmbeddingErrorCode code;

  @override
  String toString() => 'EmbeddingException(${code.name})';
}

/// Production wiring for this prompt: no local model is shipped yet, so the
/// subsystem is honestly unavailable and does no work. A real LiteRT/ONNX
/// provider replaces this class behind the same interface (docs
/// `semantic-search.md` §Selected model).
class UnavailableEmbeddingProvider implements EmbeddingProvider {
  const UnavailableEmbeddingProvider();

  @override
  String get modelId => 'unavailable';

  @override
  int get dimensions => 384;

  @override
  bool get isAvailable => false;

  @override
  Future<List<double>> embed(String text) async {
    throw const EmbeddingException(EmbeddingErrorCode.unavailable);
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) =>
      Future.wait(texts.map(embed));

  @override
  Future<void> dispose() async {}
}

/// Deterministic, vocabulary-free 384-dim feature-hashing embedding used by
/// tests and as a reference implementation of the provider contract.
///
/// This is NOT a semantic model — it is a stable bag-of-words projection over
/// normalized tokens, so two inputs sharing text overlap in cosine space
/// deterministically. It exists so the full pipeline (enrichment → storage →
/// retrieval → hybrid ranking → explanations) is exercised end-to-end and
/// mathematically verified without a real model, and to pin the exact
/// interface a real model must satisfy (docs `semantic-search.md` §Testing).
///
/// Properties:
/// * deterministic — identical input → identical vector (order, case,
///   punctuation-independent via [SemanticInputBuilder]);
/// * bounded — always `dimensions` non-finite doubles;
/// * never throws for ordinary text; an empty input yields a zero vector
///   which the caller treats as unsupported (matches production semantics).
class DeterministicEmbeddingProvider implements EmbeddingProvider {
  const DeterministicEmbeddingProvider({this.dimensions = 384});

  @override
  final int dimensions;

  @override
  String get modelId => 'deterministic-test-$dimensions';

  @override
  bool get isAvailable => true;

  @override
  Future<List<double>> embed(String text) async {
    final vector = List<double>.filled(dimensions, 0);
    // Mirror SearchNormalizer's tokenization so inputs are comparable.
    final tokens = text.toLowerCase().split(
      RegExp(r'[^\p{L}\p{N}]+', unicode: true),
    );
    for (final token in tokens) {
      if (token.isEmpty) continue;
      var hash = 0;
      for (var i = 0; i < token.length; i++) {
        hash = (31 * hash + token.codeUnitAt(i)) & 0x7fffffff;
      }
      final index = hash % dimensions;
      vector[index] += 1;
    }
    // L2-normalize for a stable cosine measure (dot product == cosine).
    var norm = 0.0;
    for (final value in vector) {
      norm += value * value;
    }
    if (norm <= 0) return vector; // zero vector — caller marks unsupported.
    final root = math.sqrt(norm);
    return [for (final value in vector) value / root];
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) =>
      Future.wait(texts.map(embed));

  @override
  Future<void> dispose() async {}
}
