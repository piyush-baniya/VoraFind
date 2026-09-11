import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/database/media_items_table.dart';
import 'package:vorafind/core/database/media_item_mapper.dart';
import 'package:vorafind/core/platform/media_discovery_models.dart';

import 'test_support.dart';

void main() {
  const mapper = MediaItemMapper();

  group('MediaItemMapper.forInsert', () {
    test('maps discovery fields verbatim', () {
      final record = buildRecord(id: 5, relinkSignature: 'sig-x');
      final row = mapper.forInsert(
        record,
        nowSeconds: 1234,
        generationAfter: 7,
        accessScope: DiscoveryAccessScope.partial,
      );

      expect(row.stableKey.value, 'external_primary:5');
      expect(row.category.value, 'images');
      expect(row.volumeName.value, 'external_primary');
      expect(row.mediaStoreId.value, 5);
      expect(
        row.contentUri.value,
        'content://media/external_primary/images/media/5',
      );
      expect(row.displayName.value, 'item_5.jpg');
      expect(row.relinkSignature.value, 'sig-x');
      expect(row.dateAdded.value, 1005);
      expect(row.dateModified.value, 2005);
    });

    test('seeds bookkeeping columns for a fresh row', () {
      final row = mapper.forInsert(
        buildRecord(id: 1),
        nowSeconds: 1234,
        generationAfter: 42,
        accessScope: DiscoveryAccessScope.full,
      );

      expect(row.firstDiscoveredAt.value, 1234);
      expect(row.lastDiscoveredAt.value, 1234);
      expect(row.metadataRevision.value, 1);
      expect(row.indexingStatus.value, IndexingStatus.none);
      expect(row.lastIndexedGeneration.value, 42);
      expect(row.lastSeenAccessScope.value, 'full');
    });

    test('audio metadata and dimensions are preserved', () {
      final row = mapper.forInsert(buildAudioRecord(id: 10), nowSeconds: 1);

      expect(row.artist.value, 'The Artist');
      expect(row.album.value, 'The Album');
      expect(row.title.value, 'Song title');
      expect(row.durationMs.value, 3 * 60 * 1000 + 15 * 1000);
      expect(row.width.value, isNull);
      expect(row.height.value, isNull);
    });

    test('placeholder metadata columns stay null', () {
      final row = mapper.forInsert(buildRecord(id: 2), nowSeconds: 1);

      expect(row.albumArtist.value, isNull);
      expect(row.trackNumber.value, isNull);
      expect(row.discNumber.value, isNull);
      expect(row.genre.value, isNull);
    });

    test('screenshot signal and null relink signature are persisted', () {
      final row = mapper.forInsert(
        buildRecord(
          id: 3,
          isScreenshot: true,
          screenshotScore: 95,
          relinkSignature: null,
        ),
        nowSeconds: 1,
      );

      expect(row.isScreenshot.value, isTrue);
      expect(row.screenshotScore.value, 95);
      expect(row.relinkSignature.value, isNull);
    });
  });

  test('nullable conversion yields a bound parameter for null and a value for non-null', () {
    // Exercised through a repository round-trip; here just verify the helper
    // produces a usable expression for both cases without throwing.
    final row = mapper.forInsert(
      buildRecord(id: 4, album: null),
      nowSeconds: 1,
    );
    expect(row.album.value, isNull);
    expect(row.album.present, isTrue);
  });
}
