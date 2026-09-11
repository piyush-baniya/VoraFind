import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/semantic/vector_codec.dart';

void main() {
  group('VectorCodec', () {
    test('round-trips a float32 vector', () {
      final original = [1.0, -0.5, 0.0, 3.14159, -2.71828];
      final encoded = VectorCodec.encode(original);
      final decoded = VectorCodec.decode(encoded);
      expect(decoded.length, original.length);
      for (var i = 0; i < original.length; i++) {
        expect(decoded[i], closeTo(original[i], 1e-5));
      }
    });

    test('empty vector cannot be encoded', () {
      expect(() => VectorCodec.encode([]), throwsArgumentError);
    });

    test('empty blob decodes to empty list', () {
      final decoded = VectorCodec.decode(Uint8List(0));
      expect(decoded, isEmpty);
    });

    test('encoded length is 4 bytes per dimension', () {
      final vector = List<double>.generate(384, (i) => i * 0.001);
      final encoded = VectorCodec.encode(vector);
      expect(encoded.length, 384 * 4);
    });

    test('decode rejects truncated data', () {
      expect(VectorCodec.decode(Uint8List.fromList([1, 2, 3])), isEmpty);
    });

    test('decode rejects empty data', () {
      expect(VectorCodec.decode(Uint8List(0)), isEmpty);
    });
  });
}
