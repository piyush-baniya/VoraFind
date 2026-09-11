import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vorafind/core/platform/content_access_models.dart';
import 'package:vorafind/core/platform/media_discovery.dart';
import 'package:vorafind/core/platform/media_discovery_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final channel = const MethodChannel(
    MethodChannelMediaDiscovery.indexingChannelName,
  );
  final events = const EventChannel(
    MethodChannelMediaDiscovery.eventsChannelName,
  );

  final calls = <MethodCall>[];

  Future<void> mockChannel(Object? Function(MethodCall call) responder) async {
    final binding = TestDefaultBinaryMessengerBinding.instance;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return responder(call);
    });
    addTearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      calls.clear();
    });
  }

  MediaDiscovery buildDiscovery() =>
      MethodChannelMediaDiscovery(channel: channel, events: events);

  Map<String, dynamic> startResult({
    String? code,
    List<Map<String, dynamic>> categories = const [],
  }) => {
    'accepted': code == null,
    'contractVersion': 1,
    'code': code,
    'categories': categories,
  };

  test('startDiscovery sends categories and parses the result', () async {
    await mockChannel(
      (call) => startResult(
        categories: [
          {'category': 'images', 'status': 'started', 'accessScope': 'full'},
        ],
      ),
    );

    final result = await buildDiscovery().startDiscovery([
      ContentCategory.images,
    ]);

    expect(calls.single.method, 'startDiscovery');
    expect(calls.single.arguments, {
      'categories': ['images'],
    });
    expect(result.accepted, isTrue);
    expect(result.categories.single.status, CategoryStartStatus.started);
  });

  test('startDiscovery maps a busy refusal', () async {
    await mockChannel((call) => startResult(code: 'busy'));

    final result = await buildDiscovery().startDiscovery([
      ContentCategory.images,
    ]);

    expect(result.accepted, isFalse);
    expect(result.code, 'busy');
  });

  test('startDiscovery sends the volumes filter when provided', () async {
    await mockChannel((call) => startResult());

    final result = await buildDiscovery().startDiscovery(
      [ContentCategory.images],
      volumes: ['external_primary'],
    );

    expect(calls.single.arguments, {
      'categories': ['images'],
      'volumes': ['external_primary'],
    });
    expect(result.accepted, isTrue);
  });

  test(
    'startDiscovery omits the volumes key when no filter is given',
    () async {
      await mockChannel((call) => startResult());

      await buildDiscovery().startDiscovery([
        ContentCategory.images,
      ], volumes: const []);

      expect(calls.single.arguments, {
        'categories': ['images'],
      });
    },
  );

  test('getGeneration round-trips null and a real token', () async {
    await mockChannel(
      (call) => call.arguments['volumeName'] == 'unknown'
          ? {'generation': null}
          : {'generation': 42},
    );

    final discovery = buildDiscovery();
    expect(
      await discovery.getGeneration(ContentCategory.images, 'external_primary'),
      42,
    );
    expect(
      await discovery.getGeneration(ContentCategory.images, 'unknown'),
      isNull,
    );
    expect(calls.map((c) => c.method), ['getGeneration', 'getGeneration']);
    expect(calls.first.arguments, {
      'category': 'images',
      'volumeName': 'external_primary',
    });
  });

  test('ackBatch sends the sequence and parses the boolean', () async {
    await mockChannel((call) => true);

    final acked = await buildDiscovery().ackBatch(7);

    expect(calls.single.method, 'ackBatch');
    expect(calls.single.arguments, {'sequence': 7});
    expect(acked, isTrue);
  });

  test(
    'ackBatch rejects negative sequences without touching the channel',
    () async {
      await mockChannel((call) => true);

      expect(() => buildDiscovery().ackBatch(-1), throwsArgumentError);
      expect(calls, isEmpty);
    },
  );

  test('cancelDiscovery and getDiscoveryStatus round-trip', () async {
    await mockChannel(
      (call) => call.method == 'cancelDiscovery'
          ? true
          : {
              'state': 'running',
              'currentCategory': 'images',
              'currentVolume': 'external_primary',
              'sequence': 1,
              'batchesSent': 1,
              'recordsDiscovered': 500,
              'skippedRecords': 0,
              'lastError': null,
            },
    );

    final discovery = buildDiscovery();
    final cancelled = await discovery.cancelDiscovery();
    expect(cancelled, isTrue);

    final status = await discovery.getDiscoveryStatus();
    expect(status.state, DiscoveryLifecycleState.running);
    expect(status.recordsDiscovered, 500);
  });

  test('platform errors map to DiscoveryException', () async {
    await mockChannel((call) {
      throw PlatformException(code: 'discoveryStartFailed');
    });

    expect(
      buildDiscovery().startDiscovery([ContentCategory.images]),
      throwsA(
        isA<DiscoveryException>().having(
          (e) => e.code,
          'code',
          'discoveryStartFailed',
        ),
      ),
    );
  });

  test('events stream decodes typed discovery events', () async {
    final binding = TestDefaultBinaryMessengerBinding.instance;
    binding.defaultBinaryMessenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (arguments, eventsSink) {
          eventsSink.success({
            'type': 'discoveryBatch',
            'sequence': 1,
            'category': 'images',
            'volume': 'external_primary',
            'accessScope': 'full',
            'records': [
              {
                'category': 'images',
                'volumeName': 'external_primary',
                'mediaStoreId': 1,
                'stableKey': 'external_primary:1',
                'relinkSignature': 'a' * 64,
                'contentUri': 'content://media/external/images/media/1',
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
              },
            ],
            'hasMore': false,
            'skippedCount': 0,
            'generationAfter': null,
          });
          eventsSink.success({
            'type': 'discoveryCompleted',
            'recordsDiscovered': 1,
            'skippedRecords': 0,
            'batchesSent': 1,
            'categories': ['images'],
            'volumes': ['external_primary'],
          });
          eventsSink.endOfStream();
        },
        onCancel: (arguments) {},
      ),
    );
    addTearDown(() {
      binding.defaultBinaryMessenger.setMockStreamHandler(events, null);
    });

    final received = <DiscoveryEvent>[];
    final sub = buildDiscovery().events().listen(received.add);

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(received, hasLength(2));
    expect(received.first, isA<DiscoveryBatchEvent>());
    expect(
      (received.first as DiscoveryBatchEvent).records.single.mediaStoreId,
      1,
    );
    expect(received.last, isA<DiscoveryCompletedEvent>());

    await sub.cancel();
  });
}
