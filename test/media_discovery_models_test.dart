import 'package:flutter_test/flutter_test.dart';

import 'package:vorafind/core/platform/content_access_models.dart';
import 'package:vorafind/core/platform/media_discovery_models.dart';

Map<String, dynamic> record({int id = 1}) => {
  'category': 'images',
  'volumeName': 'external_primary',
  'mediaStoreId': id,
  'stableKey': 'external_primary:$id',
  'relinkSignature': 'a' * 64,
  'contentUri': 'content://media/external/images/media/$id',
  'displayName': 'photo.jpg',
  'mimeType': 'image/jpeg',
  'sizeBytes': 1000000,
  'dateAdded': 1000,
  'dateModified': 2000,
  'relativePath': 'DCIM/Camera/',
  'bucketDisplayName': 'Camera',
  'width': 1920,
  'height': 1080,
  'durationMs': null,
  'title': null,
  'artist': null,
  'album': null,
  'screenshotScore': 10,
  'isScreenshot': false,
};

void main() {
  group('MediaDiscoveryRecord', () {
    test('decodes a full image record', () {
      final decoded = MediaDiscoveryRecord.fromJson(record());
      expect(decoded.category, ContentCategory.images);
      expect(decoded.volumeName, 'external_primary');
      expect(decoded.mediaStoreId, 1);
      expect(decoded.stableKey, 'external_primary:1');
      expect(decoded.relinkSignature, hasLength(64));
      expect(decoded.mimeType, 'image/jpeg');
      expect(decoded.width, 1920);
      expect(decoded.screenshotScore, 10);
      expect(decoded.isScreenshot, isFalse);
      expect(decoded.title, isNull);
    });

    test('decodes nullable fields as null', () {
      final decoded = MediaDiscoveryRecord.fromJson({
        'category': 'audio',
        'volumeName': 'external_primary',
        'mediaStoreId': 7,
        'stableKey': 'external_primary:7',
        'relinkSignature': null,
        'contentUri': 'content://media/external/audio/media/7',
        'displayName': 'track.mp3',
        'mimeType': null,
        'sizeBytes': null,
        'dateAdded': null,
        'dateModified': null,
        'relativePath': null,
        'bucketDisplayName': null,
        'width': null,
        'height': null,
        'durationMs': 180000,
        'title': 'My Song',
        'artist': 'An Artist',
        'album': 'The Album',
        'screenshotScore': null,
        'isScreenshot': null,
      });
      expect(decoded.category, ContentCategory.audio);
      expect(decoded.title, 'My Song');
      expect(decoded.durationMs, 180000);
      expect(decoded.relinkSignature, isNull);
      expect(decoded.screenshotScore, isNull);
    });

    test('rejects unknown categories', () {
      expect(
        () => MediaDiscoveryRecord.fromJson({...record(), 'category': 'books'}),
        throwsFormatException,
      );
    });
  });

  group('DiscoveryEvent', () {
    test('decodes discoveryBatch with typed records', () {
      final event = DiscoveryEvent.fromJson({
        'type': 'discoveryBatch',
        'sequence': 3,
        'category': 'images',
        'volume': 'external_primary',
        'accessScope': 'full',
        'records': [record(id: 1), record(id: 2)],
        'hasMore': true,
        'skippedCount': 2,
        'generationAfter': 1234,
      });
      expect(event, isA<DiscoveryBatchEvent>());
      final batch = event as DiscoveryBatchEvent;
      expect(batch.sequence, 3);
      expect(batch.category, ContentCategory.images);
      expect(batch.accessScope, DiscoveryAccessScope.full);
      expect(batch.records, hasLength(2));
      expect(batch.hasMore, isTrue);
      expect(batch.skippedCount, 2);
      expect(batch.generationAfter, 1234);
      expect(batch.records.last.mediaStoreId, 2);
    });

    test('decodes lifecycle events', () {
      expect(
        DiscoveryEvent.fromJson({
          'type': 'discoveryStarted',
          'category': 'videos',
          'volume': 'external_primary',
          'accessScope': 'partial',
        }),
        isA<DiscoveryStartedEvent>(),
      );
      expect(
        DiscoveryEvent.fromJson({
          'type': 'discoveryProgress',
          'sequence': 1,
          'category': 'videos',
          'volume': 'external_primary',
          'accessScope': 'full',
          'recordsDiscovered': 10,
          'skippedRecords': 0,
          'batchesSent': 1,
          'batchesRemaining': 1,
        }),
        isA<DiscoveryProgressEvent>(),
      );
      expect(
        DiscoveryEvent.fromJson({
          'type': 'discoveryCompleted',
          'recordsDiscovered': 10,
          'skippedRecords': 0,
          'batchesSent': 2,
          'categories': ['images'],
          'volumes': ['external_primary'],
        }),
        isA<DiscoveryCompletedEvent>(),
      );
      expect(
        DiscoveryEvent.fromJson({
          'type': 'discoveryCancelled',
          'recordsDiscovered': 1,
          'skippedRecords': 0,
          'batchesSent': 1,
        }),
        isA<DiscoveryCancelledEvent>(),
      );
      expect(
        DiscoveryEvent.fromJson({
          'type': 'discoveryError',
          'code': 'scannerFailed',
          'message': 'disk blip',
        }),
        isA<DiscoveryErrorEvent>(),
      );
    });

    test('rejects unknown event types', () {
      expect(
        () => DiscoveryEvent.fromJson({'type': 'discoveryPaused'}),
        throwsFormatException,
      );
    });

    test('completion event carries category and volume sets', () {
      final event = DiscoveryEvent.fromJson({
        'type': 'discoveryCompleted',
        'recordsDiscovered': 42,
        'skippedRecords': 3,
        'batchesSent': 4,
        'categories': ['images', 'videos', 'audio'],
        'volumes': ['external_primary', 'SD Card'],
      }) as DiscoveryCompletedEvent;
      expect(
        event.categories,
        containsAll([ContentCategory.images, ContentCategory.audio]),
      );
      expect(event.volumes, ['external_primary', 'SD Card']);
    });
  });

  group('DiscoveryStartResult', () {
    test('decodes an accepted start with per-category statuses', () {
      final result = DiscoveryStartResult.fromJson({
        'accepted': true,
        'contractVersion': 1,
        'code': null,
        'categories': [
          {'category': 'images', 'status': 'started', 'accessScope': 'full'},
          {'category': 'audio', 'status': 'unavailable', 'accessScope': null},
        ],
      });
      expect(result.accepted, isTrue);
      expect(result.contractVersion, 1);
      expect(result.code, isNull);
      expect(result.categories, hasLength(2));
      expect(result.categories.first.status, CategoryStartStatus.started);
      expect(result.categories.first.accessScope, DiscoveryAccessScope.full);
      expect(result.categories.last.status, CategoryStartStatus.unavailable);
      expect(result.categories.last.accessScope, isNull);
    });

    test('decodes a refusal with a code', () {
      final result = DiscoveryStartResult.fromJson({
        'accepted': false,
        'contractVersion': 1,
        'code': 'busy',
        'categories': <Object>[],
      });
      expect(result.accepted, isFalse);
      expect(result.code, 'busy');
    });
  });

  group('DiscoveryStatus', () {
    test('decodes a running snapshot', () {
      final status = DiscoveryStatus.fromJson({
        'state': 'running',
        'currentCategory': 'images',
        'currentVolume': 'external_primary',
        'sequence': 2,
        'batchesSent': 1,
        'recordsDiscovered': 500,
        'skippedRecords': 2,
        'lastError': null,
      });
      expect(status.state, DiscoveryLifecycleState.running);
      expect(status.recordsDiscovered, 500);
      expect(status.lastError, isNull);
    });
  });
}
