import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/database/media_repository.dart';
import 'package:vorafind/core/search/search_interpreter.dart';
import 'package:vorafind/core/search/search_normalizer.dart';
import 'package:vorafind/core/search/search_query.dart';
import 'package:vorafind/core/search/search_service.dart';

/// Fixed epoch second: 2023-11-14 22:13:20 UTC. Day boundaries are derived
/// through [DateTime] in local time exactly like the interpreter does, so the
/// tests verify calendar anchoring regardless of the machine's timezone.
const int _now = 1700000000;

int _startOfTodayLocal(int nowEpochSeconds) {
  final now = DateTime.fromMillisecondsSinceEpoch(nowEpochSeconds * 1000)
      .toLocal();
  final start = DateTime(now.year, now.month, now.day);
  return start.millisecondsSinceEpoch ~/ 1000;
}

void main() {
  group('SearchQueryInterpreter — document words', () {
    test('pdf words pin the pdf body type and are dropped', () {
      final i = SearchQueryInterpreter.interpret(
        SearchNormalizer.tokens('find pdfs'),
      );
      expect(i.keywords, ['find']);
      expect(i.documentTypes, {SearchDocumentType.pdf});
      expect(i.categories, isEmpty);
      expect(i.dateFrom, isNull);
    });

    test('pdfs with keywords keep only the keywords', () {
      final i = SearchQueryInterpreter.interpret(
        SearchNormalizer.tokens('pdf machine learning'),
      );
      expect(i.keywords, ['machine', 'learning']);
      expect(i.documentTypes, {SearchDocumentType.pdf});
    });

    test('text and markdown words pin their types', () {
      final text = SearchQueryInterpreter.interpret(
        SearchNormalizer.tokens('txt receipt'),
      );
      expect(text.documentTypes, {SearchDocumentType.text});

      final markdown = SearchQueryInterpreter.interpret(
        SearchNormalizer.tokens('markdown notes'),
      );
      expect(markdown.documentTypes, {SearchDocumentType.markdown});
    });

    test('generic document words become the documents category', () {
      final i = SearchQueryInterpreter.interpret(
        SearchNormalizer.tokens('documents gradle'),
      );
      expect(i.keywords, ['gradle']);
      expect(i.documentTypes, isEmpty);
      expect(i.categories.map((c) => c.name), ['documents']);
    });

    test('multiple typed words merge into one set', () {
      final i = SearchQueryInterpreter.interpret(
        SearchNormalizer.tokens('pdf txt markdown'),
      );
      expect(i.keywords, isEmpty);
      expect(i.documentTypes.length, 3);
    });

    test('without a clock time words stay keywords', () {
      final i = SearchQueryInterpreter.interpret(
        SearchNormalizer.tokens('recent files'),
        nowEpochSeconds: null,
      );
      expect(i.keywords, ['recent', 'files']);
      expect(i.dateFrom, isNull);
      expect(i.dateTo, isNull);
    });
  });

  group('SearchQueryInterpreter — time words', () {
    final startOfToday = _startOfTodayLocal(_now);

    test('today starts at the local start of day', () {
      final i = SearchQueryInterpreter.interpret(
        SearchNormalizer.tokens('find photos today'),
        nowEpochSeconds: _now,
      );
      expect(i.keywords, ['find']);
      expect(i.categories.map((c) => c.name), ['images']);
      expect(i.dateFrom, startOfToday);
      expect(i.dateTo, isNull);
    });

    test('yesterday is bounded to the previous local day', () {
      final i = SearchQueryInterpreter.interpret(
        SearchNormalizer.tokens('yesterday'),
        nowEpochSeconds: _now,
      );
      expect(i.keywords, isEmpty);
      expect(i.dateFrom, startOfToday - 86400);
      expect(i.dateTo, startOfToday);
    });

    test('recent covers the last seven days', () {
      final i = SearchQueryInterpreter.interpret(
        SearchNormalizer.tokens('recent'),
        nowEpochSeconds: _now,
      );
      expect(i.dateFrom, startOfToday - 6 * 86400);
      expect(i.dateTo, isNull);
    });

    test('this week starts on Monday', () {
      final i = SearchQueryInterpreter.interpret(
        SearchNormalizer.tokens('this week'),
        nowEpochSeconds: _now,
      );
      expect(i.keywords, isEmpty);
      final start = DateTime.fromMillisecondsSinceEpoch(i.dateFrom! * 1000);
      expect(start.weekday, DateTime.monday);
      expect(i.dateFrom, lessThanOrEqualTo(startOfToday));
    });

    test('bare week and month stay keywords — phrase required', () {
      final i = SearchQueryInterpreter.interpret(
        SearchNormalizer.tokens('week month'),
        nowEpochSeconds: _now,
      );
      expect(i.keywords, ['week', 'month']);
      expect(i.dateFrom, isNull);
    });

    test('this month starts on the first of the month', () {
      final i = SearchQueryInterpreter.interpret(
        SearchNormalizer.tokens('this month'),
        nowEpochSeconds: _now,
      );
      final start = DateTime.fromMillisecondsSinceEpoch(i.dateFrom! * 1000);
      expect(start.day, 1);
      expect(i.dateFrom, lessThanOrEqualTo(startOfToday));
    });
  });

  group('SearchService.prepare — document types and time words', () {
    late AppDatabase db;
    late SearchService service;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      service = SearchService(
        repository: _UnusedRepository(db),
        nowSeconds: () => _now,
      );
    });

    tearDown(() => db.close());

    test('pdf word reaches the normalized query as a type pin', () {
      final prepared = service.prepare(const SearchQuery(text: 'find pdfs'));
      expect(prepared.documentTypes, {SearchDocumentType.pdf});
      expect(prepared.tokens, ['find']);
      expect(prepared.hasFilters, isTrue);
    });

    test('time word reaches the normalized query as a date filter', () {
      final prepared = service.prepare(const SearchQuery(text: 'recent'));
      expect(prepared.dateFrom, _startOfTodayLocal(_now) - 6 * 86400);
    });

    test('explicit date filters override time words', () {
      final prepared = service.prepare(
        const SearchQuery(text: 'recent', dateFrom: 10),
      );
      expect(prepared.dateFrom, 10);
    });

    test('screenshot queries drop document type pins', () {
      final prepared = service.prepare(
        const SearchQuery(text: 'screenshots pdf'),
      );
      expect(prepared.isScreenshot, isTrue);
      expect(prepared.documentTypes, isEmpty);
    });
  });
}

/// `prepare` never touches the repository; retrieval failures prove it.
class _UnusedRepository extends DriftMediaRepository {
  _UnusedRepository(super.database);

  @override
  Future<List<MediaItem>> searchCandidates(NormalizedSearchQuery query) async {
    throw StateError('should not be reached');
  }
}
