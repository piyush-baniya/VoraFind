import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/platform/content_access_models.dart';
import 'package:vorafind/core/search/search_interpreter.dart';
import 'package:vorafind/core/search/search_normalizer.dart';

void main() {
  group('SearchQueryInterpreter.interpret', () {
    test('screenshot words become a screenshot filter and are dropped', () {
      final i = SearchQueryInterpreter.interpret(
        SearchNormalizer.tokens('screenshot flutter'),
      );
      expect(i.keywords, ['flutter']);
      expect(i.categories, isEmpty);
      expect(i.isScreenshot, isTrue);
    });

    test('media words become category filters and are dropped', () {
      final i = SearchQueryInterpreter.interpret(
        SearchNormalizer.tokens('my video song'),
      );
      expect(i.keywords, ['my']);
      expect(
        i.categories,
        containsAll([ContentCategory.videos, ContentCategory.audio]),
      );
      expect(i.isScreenshot, isNull);
    });

    test('synonyms map to the same categories', () {
      final images = SearchQueryInterpreter.interpret(
        SearchNormalizer.tokens('photo images pics'),
      );
      expect(images.categories, [ContentCategory.images]);
      expect(images.keywords, ['pics']);
    });

    test('an empty query yields no interpretation', () {
      final i = SearchQueryInterpreter.interpret(const []);
      expect(i.keywords, isEmpty);
      expect(i.categories, isEmpty);
      expect(i.isScreenshot, isNull);
    });

    test('ambiguous words stay keywords — never guesses', () {
      final i = SearchQueryInterpreter.interpret(['state', 'audio']);
      expect(i.keywords, ['state']);
      expect(i.categories, [ContentCategory.audio]);
    });
  });
}
