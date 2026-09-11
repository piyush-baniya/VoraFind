import 'dart:math' as math;

/// Cosine similarity and validation for bounded float vectors (docs
/// `semantic-search.md` §Similarity).
///
/// Pure math with no I/O. Every entry point is defensive: a malformed vector
/// (wrong length, NaN, Infinity, zero norm) is rejected with `null` instead of
/// poisoning a ranking or crashing a search (AGENTS.md §19).
abstract final class VectorMath {
  /// Cosine similarity of [a] and [b], or null when either vector is invalid
  /// for retrieval (wrong dimensions, non-finite, or zero norm).
  static double? cosine(List<double> a, List<double> b) {
    if (!_usable(a) || !_usable(b)) return null;
    if (a.length != b.length) return null;
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA <= 0 || normB <= 0) return null;
    final similarity = dot / (math.sqrt(normA) * math.sqrt(normB));
    if (similarity.isNaN || similarity.isInfinite) return null;
    // Floating point can land a hair outside [-1, 1]; clamp so downstream
    // ranking math stays in range.
    return similarity.clamp(-1.0, 1.0);
  }

  /// L2-normalizes [vector]; returns null for an empty, non-finite, or zero
  /// vector (nothing to normalize). Never mutates the input.
  static List<double>? normalized(List<double> vector) {
    if (vector.isEmpty) return null;
    var norm = 0.0;
    for (final value in vector) {
      if (value.isNaN || value.isInfinite) return null;
      norm += value * value;
    }
    if (norm <= 0) return null;
    final root = math.sqrt(norm);
    return [for (final value in vector) value / root];
  }

  static bool _usable(List<double> vector) {
    if (vector.isEmpty) return false;
    for (final value in vector) {
      if (value.isNaN || value.isInfinite) return false;
    }
    return true;
  }
}
