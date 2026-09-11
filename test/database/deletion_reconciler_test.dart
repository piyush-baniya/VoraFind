import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/database/deletion_reconciler.dart';
import 'package:vorafind/core/database/media_repository.dart';
import 'package:vorafind/core/platform/content_access_models.dart';

/// In-memory stand-in for the indexed rows of one (category, volume) unit.
/// Ids must be unique and ascending like MediaStore `_ID`s.
class _FakeIndexedStore {
  final List<({int id, String key, String volume})> _rows = [];
  final List<List<String>> deleteChunks = [];
  int deletedCount = 0;

  void seed(int id, {String volume = 'external_primary'}) {
    _rows.add((id: id, key: '$volume:$id', volume: volume));
    _rows.sort((a, b) => a.id.compareTo(b.id));
  }

  List<IndexedMediaId> fetchPage(String volume, int afterId, int limit) {
    return _rows
        .where((row) => row.id > afterId && row.volume == volume)
        .take(limit)
        .map((row) => IndexedMediaId(stableKey: row.key, mediaStoreId: row.id))
        .toList(growable: false);
  }

  Future<void> delete(Iterable<String> keys) async {
    final chunk = keys.toList(growable: false);
    deleteChunks.add(chunk);
    deletedCount += chunk.length;
    _rows.removeWhere((row) => chunk.contains(row.key));
  }

  Set<String> remainingFor(String volume) =>
      _rows.where((row) => row.volume == volume).map((row) => row.key).toSet();
}

DeletionReconciler _reconciler(
  _FakeIndexedStore store, {
  int pageSize = 500,
  int chunkSize = 500,
}) => DeletionReconciler(
  fetchPage: (category, volume, afterId, limit) async =>
      store.fetchPage(volume, afterId, limit),
  deleteKeys: (keys) => store.delete(keys),
  pageSize: pageSize,
  chunkSize: chunkSize,
);

void main() {
  group('DeletionReconciler', () {
    test('deletes only rows the scan already passed', () async {
      final store = _FakeIndexedStore();
      for (var id = 1; id <= 10; id++) {
        store.seed(id);
      }
      final reconciler = _reconciler(store);

      reconciler.begin(ContentCategory.images, 'external_primary');
      await reconciler.observeMany([4, 5, 6, 7, 8, 9, 10]);

      // Rows 1–3 fall below the lowest observed scan id and are mark-candidates
      // already; rows above 10 have not been passed yet.
      // Mid-run there are exactly three candidates.
      final deleted = await reconciler.apply();

      expect(deleted, 3);
      expect(store.remainingFor('external_primary'), {
        'external_primary:4',
        'external_primary:5',
        'external_primary:6',
        'external_primary:7',
        'external_primary:8',
        'external_primary:9',
        'external_primary:10',
      });
    });

    test('a clean run delete the rows the scan never returned', () async {
      final store = _FakeIndexedStore();
      for (var id = 1; id <= 5; id++) {
        store.seed(id);
      }
      final reconciler = _reconciler(store);

      reconciler.begin(ContentCategory.images, 'external_primary');
      await reconciler.observeMany([1, 3, 5]);

      final deleted = await reconciler.apply();

      // 2 and 4 were passed by the merge but never returned.
      expect(deleted, 2);
      expect(store.remainingFor('external_primary'), {
        'external_primary:1',
        'external_primary:3',
        'external_primary:5',
      });
    });

    test('matches equal rows without deleting them', () async {
      final store = _FakeIndexedStore();
      store.seed(1);
      store.seed(2);
      final reconciler = _reconciler(store);

      reconciler.begin(ContentCategory.images, 'external_primary');
      await reconciler.observeMany([1, 2]);

      final deleted = await reconciler.apply();
      expect(deleted, 0);
      expect(store.remainingFor('external_primary'), {
        'external_primary:1',
        'external_primary:2',
      });
    });

    test('empty scan deletes nothing when there are no rows', () async {
      final store = _FakeIndexedStore();
      final reconciler = _reconciler(store);

      reconciler.begin(ContentCategory.images, 'external_primary');
      await reconciler.observeMany(const [1, 2, 3]);
      expect(await reconciler.apply(), 0);
    });

    test('discard abandons the unit without deleting anything', () async {
      final store = _FakeIndexedStore();
      for (var id = 1; id <= 5; id++) {
        store.seed(id);
      }
      final reconciler = _reconciler(store);

      reconciler.begin(ContentCategory.images, 'external_primary');
      await reconciler.observeMany([1]);

      reconciler.discard();
      expect(store.deletedCount, 0);
      expect(store.remainingFor('external_primary'), {
        'external_primary:1',
        'external_primary:2',
        'external_primary:3',
        'external_primary:4',
        'external_primary:5',
      });
    });

    test('crosses page boundaries with bounded memory', () async {
      final store = _FakeIndexedStore();
      for (var id = 1; id <= 200; id++) {
        store.seed(id);
      }
      final reconciler = _reconciler(store, pageSize: 50, chunkSize: 20);

      reconciler.begin(ContentCategory.images, 'external_primary');
      // Observe ids 1..100 ascending; every scan id matches, nothing deletes
      // yet even though 150 rows remain in the store.
      await reconciler.observeMany([for (var id = 1; id <= 100; id++) id]);
      expect(store.deletedCount, 0);

      final deleted = await reconciler.apply();
      // Scan covered 1..100, the remainder 101..200 were gone.
      expect(deleted, 100);
      expect(store.remainingFor('external_primary'), {
        for (var id = 1; id <= 100; id++) 'external_primary:$id',
      });
    });

    test('chunks deletions by chunkSize', () async {
      final store = _FakeIndexedStore();
      for (var id = 1; id <= 7; id++) {
        store.seed(id);
      }
      final reconciler = _reconciler(store, pageSize: 500, chunkSize: 3);

      reconciler.begin(ContentCategory.images, 'external_primary');
      await reconciler.observeMany(const [1, 2, 3, 4]);
      final deleted = await reconciler.apply();

      expect(deleted, 3);
      expect(store.deleteChunks.every((chunk) => chunk.length <= 3), isTrue);
    });

    test('can be reused for the next unit after apply', () async {
      final store = _FakeIndexedStore();
      for (var id = 1; id <= 3; id++) {
        store.seed(id, volume: 'A');
        store.seed(id + 100, volume: 'B');
      }
      final reconciler = _reconciler(store);

      reconciler.begin(ContentCategory.images, 'A');
      await reconciler.observeMany(const [1, 2, 3]);
      await reconciler.apply();

      reconciler.begin(ContentCategory.images, 'B');
      await reconciler.observeMany(const [101, 102, 103]);
      expect(await reconciler.apply(), 0);
      expect(store.deletedCount, 0);
    });

    test('throws when used without begin', () async {
      final reconciler = _reconciler(_FakeIndexedStore());
      expect(() => reconciler.observeMany(const [1]), throwsStateError);
      expect(() => reconciler.apply(), throwsStateError);
    });
  });
}
