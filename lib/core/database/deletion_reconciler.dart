import '../platform/content_access_models.dart' show ContentCategory;
import 'media_repository.dart' show IndexedMediaId;

/// Fetches one bounded page of indexed rows for a (category, volume) pair.
typedef IndexedPageFetcher = Future<List<IndexedMediaId>> Function(
  ContentCategory category,
  String volumeName,
  int afterId,
  int limit,
);

/// Deletes rows by stable key. The reconciler chunks calls via [chunkSize].
typedef StableKeyDeleter = Future<void> Function(Iterable<String> stableKeys);

/// Detects rows that a full-scope scan no longer returned, without ever
/// holding a whole (category, volume) unit in memory.
///
/// This is a merge over two ascending id streams — the indexed database rows
/// of one unit and the MediaStore scan ids — not a set difference:
///
///  * A database row is only ever marked for deletion once a scan id greater
///    than it has been observed, so a row the scan simply has not reached yet
///    can never be deleted.
///  * Rows still queued in the database walk when the scan stops are only
///    treated as gone after the unit concluded cleanly (see [apply]), which
///    the coordinator calls exclusively for full-scope units whose scan ran to
///    completion (architecture §15).
///
/// Memory stays bounded to one database page plus one delete chunk of stable
/// keys. Not thread-safe; drive it from a single event consumer.
class DeletionReconciler {
  DeletionReconciler({
    required this.fetchPage,
    required this.deleteKeys,
    this.pageSize = 500,
    this.chunkSize = 500,
  });

  final IndexedPageFetcher fetchPage;
  final StableKeyDeleter deleteKeys;
  final int pageSize;
  final int chunkSize;

  ContentCategory? _category;
  String? _volumeName;
  final Set<String> _candidates = <String>{};
  List<IndexedMediaId> _page = const [];
  int _pageIndex = 0;
  bool _pageLoaded = false;

  /// Prepares reconciliation for one unit. Call once before its first batch
  /// (or before [apply] for an empty unit).
  void begin(ContentCategory category, String volumeName) {
    _category = category;
    _volumeName = volumeName;
    _candidates.clear();
    _page = const [];
    _pageIndex = 0;
    _pageLoaded = false;
  }

  /// Feeds the scan's MediaStore ids for one unit. Ids within a unit arrive
  /// ascending (keyset paging), which the merge depends on.
  Future<void> observeMany(Iterable<int> mediaStoreIds) async {
    final category = _category;
    final volumeName = _volumeName;
    if (category == null || volumeName == null) {
      throw StateError('DeletionReconciler.begin must be called first');
    }
    await _ensurePage(category, volumeName);
    for (final scanId in mediaStoreIds) {
      if (_page.isEmpty) break;
      while (_pageIndex < _page.length &&
          _page[_pageIndex].mediaStoreId < scanId) {
        _candidates.add(_page[_pageIndex].stableKey);
        _pageIndex += 1;
        if (_pageIndex == _page.length) {
          await _loadNextPage(category, volumeName);
          if (_page.isEmpty) break;
        }
      }
      if (_pageIndex < _page.length &&
          _page[_pageIndex].mediaStoreId == scanId) {
        _pageIndex += 1;
        if (_pageIndex == _page.length) {
          await _loadNextPage(category, volumeName);
        }
      }
    }
  }

  /// Finishes a cleanly-concluded full-scope unit: every indexed row the scan
  /// never returned is deleted in [chunkSize]-sized batches. Returns the number
  /// of deleted rows and resets this reconciler for the next unit.
  Future<int> apply() async {
    final category = _category;
    final volumeName = _volumeName;
    if (category == null || volumeName == null) {
      throw StateError('DeletionReconciler.begin must be called first');
    }
    await _ensurePage(category, volumeName);
    while (_page.isNotEmpty) {
      for (var i = _pageIndex; i < _page.length; i++) {
        _candidates.add(_page[i].stableKey);
      }
      _pageIndex = _page.length;
      await _loadNextPage(category, volumeName);
    }

    final keys = _candidates.toList(growable: false);
    _candidates.clear();
    var deleted = 0;
    for (var start = 0; start < keys.length; start += chunkSize) {
      final end = (start + chunkSize < keys.length)
          ? start + chunkSize
          : keys.length;
      await deleteKeys(keys.sublist(start, end));
      deleted += end - start;
    }

    _category = null;
    _volumeName = null;
    _page = const [];
    _pageIndex = 0;
    _pageLoaded = false;
    return deleted;
  }

  /// Abandons a unit that did not conclude cleanly; no rows are deleted.
  void discard() {
    _candidates.clear();
    _category = null;
    _volumeName = null;
    _page = const [];
    _pageIndex = 0;
    _pageLoaded = false;
  }

  Future<void> _ensurePage(ContentCategory category, String volumeName) async {
    if (_pageLoaded) return;
    _page = await fetchPage(category, volumeName, 0, pageSize);
    _pageIndex = 0;
    _pageLoaded = true;
  }

  Future<void> _loadNextPage(
    ContentCategory category,
    String volumeName,
  ) async {
    if (_page.isEmpty) {
      _pageIndex = 0;
      return;
    }
    final afterId = _page.last.mediaStoreId;
    _page = await fetchPage(category, volumeName, afterId, pageSize);
    _pageIndex = 0;
  }
}
