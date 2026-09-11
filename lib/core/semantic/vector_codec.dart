import 'dart:typed_data';

/// Serializes bounded float vectors to/from byte blobs for the
/// `semantic_embeddings` store (docs `semantic-search.md` §Storage).
///
/// Today only little-endian Float32 (tag `SemanticDefaults.quantizationF32`)
/// is written. A future INT8 quantization adds a second tag + codec pairs;
/// rows written under an unrecognized tag are treated as stale and
/// regenerated rather than mis-decoded.
abstract final class VectorCodec {
  /// Encodes [vector] into a 4-byte-per-element Float32LE blob.
  ///
  /// Throws [ArgumentError] for an empty vector (a zero-length blob is
  /// ambiguous with "not completed"). Non-finite values are preserved by the
  /// codec but rejected by [VectorMath] at retrieval time — they are stored
  /// as-is so the failure is diagnosable, not silently dropped.
  static Uint8List encode(List<double> vector) {
    if (vector.isEmpty) {
      throw ArgumentError.value(vector, 'vector', 'cannot encode empty vector');
    }
    final bytes = ByteData(vector.length * 4);
    for (var i = 0; i < vector.length; i++) {
      bytes.setFloat32(i * 4, vector[i], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  /// Decodes [blob] written by [encode] (Float32LE). Returns an empty list
  /// for null/empty input so the caller can treat it as "no vector".
  static List<double> decode(Uint8List? blob) {
    if (blob == null || blob.isEmpty) return const [];
    if (blob.length % 4 != 0) return const []; // corrupt → treat as absent.
    final data = ByteData.sublistView(blob);
    final result = List<double>.filled(blob.length ~/ 4, 0);
    for (var i = 0; i < result.length; i++) {
      result[i] = data.getFloat32(i * 4, Endian.little);
    }
    return result;
  }
}
