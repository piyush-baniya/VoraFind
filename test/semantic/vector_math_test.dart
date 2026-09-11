import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/semantic/vector_math.dart';

void main() {
  group('VectorMath.cosine', () {
    test('identical vectors return 1.0', () {
      expect(VectorMath.cosine([1.0, 2.0, 3.0], [1.0, 2.0, 3.0]), 1.0);
    });

    test('opposite vectors return -1.0', () {
      expect(VectorMath.cosine([1.0, 0.0], [-1.0, 0.0]), -1.0);
    });

    test('orthogonal vectors return 0.0', () {
      expect(VectorMath.cosine([1.0, 0.0], [0.0, 1.0]), 0.0);
    });

    test('zero vector returns null', () {
      expect(VectorMath.cosine([0.0, 0.0], [1.0, 2.0]), isNull);
    });

    test('mismatched dimensions return null', () {
      expect(VectorMath.cosine([1.0, 2.0], [1.0, 2.0, 3.0]), isNull);
    });

    test('NaN in input returns null', () {
      expect(VectorMath.cosine([double.nan, 1.0], [1.0, 2.0]), isNull);
    });

    test('Infinity in input returns null', () {
      expect(VectorMath.cosine([double.infinity, 1.0], [1.0, 2.0]), isNull);
    });

    test('similarity is symmetric', () {
      const a = [1.0, 2.0, 3.0];
      const b = [4.0, 5.0, 6.0];
      expect(VectorMath.cosine(a, b), VectorMath.cosine(b, a));
    });

    test('partial similarity is between -1 and 1', () {
      final sim = VectorMath.cosine([1.0, 2.0], [2.0, 1.0]);
      expect(sim, isNotNull);
      expect(sim! >= -1.0 && sim <= 1.0, isTrue);
    });
  });

  group('VectorMath.normalized', () {
    test('already normalized vector stays normalized', () {
      final result = VectorMath.normalized([1.0, 0.0, 0.0]);
      expect(result![0], closeTo(1.0, 1e-9));
      expect(result[1], closeTo(0.0, 1e-9));
      expect(result[2], closeTo(0.0, 1e-9));
    });

    test('zero vector returns null', () {
      final result = VectorMath.normalized([0.0, 0.0]);
      expect(result, isNull);
    });

    test('non-unit vector becomes unit length', () {
      final result = VectorMath.normalized([3.0, 4.0]);
      final magnitude = (result![0] * result[0] + result[1] * result[1]);
      expect(magnitude, closeTo(1.0, 1e-9));
    });
  });
}
