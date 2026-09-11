import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/search/search_normalizer.dart';

void main() {
  group('SearchNormalizer.canonical', () {
    test('lowercases and folds separators to spaces', () {
      expect(
        SearchNormalizer.canonical('Citizenship_Front.JPG'),
        'citizenship front jpg',
      );
    });

    test('collapses runs of separators', () {
      expect(SearchNormalizer.canonical('A--B  __ C...'), 'a b c');
    });

    test('strips LIKE wildcards entirely', () {
      expect(SearchNormalizer.canonical('100%_done'), '100 done');
    });

    test('handles empty and separator-only input', () {
      expect(SearchNormalizer.canonical(''), '');
      expect(SearchNormalizer.canonical('   - _ . '), '');
    });

    test('keeps unicode letters? no — folds to ascii alnum only', () {
      expect(SearchNormalizer.canonical('café 東京 123'), 'caf 123');
    });
  });

  group('SearchNormalizer.tokens', () {
    test('splits into non-empty alphanumeric tokens', () {
      expect(SearchNormalizer.tokens('  Flutter   ERROR '), [
        'flutter',
        'error',
      ]);
    });

    test('returns empty for empty input', () {
      expect(SearchNormalizer.tokens(''), isEmpty);
      expect(SearchNormalizer.tokens('...'), isEmpty);
    });
  });

  group('SearchNormalizer.storageText', () {
    test('joins present fields and canonicalizes', () {
      expect(
        SearchNormalizer.storageText([
          'My_Photo.JPG',
          'My Photo',
          'DCIM/Camera',
          null,
          '',
          null,
        ]),
        'my photo jpg my photo dcim camera',
      );
    });

    test('returns empty when no field carries text', () {
      expect(SearchNormalizer.storageText([null, '', null]), '');
    });
  });
}
