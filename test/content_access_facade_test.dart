import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vorafind/core/platform/content_access.dart';
import 'package:vorafind/core/platform/content_access_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final channel = const MethodChannel(
    MethodChannelContentAccess.contentAccessChannelName,
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

  ContentAccess buildAccess() => MethodChannelContentAccess(channel: channel);

  Map<String, dynamic> categoryAccess(
    String category,
    String state, {
    bool canQuery = true,
    bool canReadAll = true,
    bool canReadSelected = true,
  }) => {
    'category': category,
    'state': state,
    'canQuery': canQuery,
    'canReadAll': canReadAll,
    'canReadSelected': canReadSelected,
  };

  test(
    'getCapabilities maps to the method channel and parses the response',
    () async {
      await mockChannel(
        (call) => {
          'contractVersion': 1,
          'apiLevel': 36,
          'safCapable': true,
          'mediaStoreGenerationSupported': true,
          'partialMediaAccessSupported': true,
          'externalVolumes': ['external_primary'],
          'categories': [
            categoryAccess('images', 'fullAccess'),
            categoryAccess('videos', 'noAccess', canQuery: false),
            categoryAccess('audio', 'denied', canQuery: false),
            categoryAccess('documents', 'partialAccess', canReadAll: false),
          ],
        },
      );

      final capabilities = await buildAccess().getCapabilities();

      expect(calls.single.method, 'getCapabilities');
      expect(capabilities.apiLevel, 36);
      expect(
        capabilities.accessFor(ContentCategory.images).state,
        ContentAccessState.fullAccess,
      );
      expect(
        capabilities.accessFor(ContentCategory.documents).canReadAll,
        isFalse,
      );
    },
  );

  test('getPermissionState sends the category argument', () async {
    await mockChannel((call) => categoryAccess('audio', 'fullAccess'));

    final access = await buildAccess().getPermissionState(
      ContentCategory.audio,
    );

    expect(calls.single.method, 'getPermissionState');
    expect(calls.single.arguments, {'category': 'audio'});
    expect(access.state, ContentAccessState.fullAccess);
  });

  test(
    'requestMediaAccess sends the category and parses the resulting state',
    () async {
      await mockChannel(
        (call) => categoryAccess('videos', 'partialAccess', canReadAll: false),
      );

      final access = await buildAccess().requestMediaAccess(
        ContentCategory.videos,
      );

      expect(calls.single.method, 'requestMediaAccess');
      expect(calls.single.arguments, {'category': 'videos'});
      expect(access.state, ContentAccessState.partialAccess);
      expect(access.canReadAll, isFalse);
      expect(access.canReadSelected, isTrue);
    },
  );

  test(
    'requestMediaAccess refuses documents without touching the channel',
    () async {
      await mockChannel((call) => categoryAccess('images', 'fullAccess'));

      expect(
        () => buildAccess().requestMediaAccess(ContentCategory.documents),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    },
  );

  test(
    'requestMediaAccess maps platform errors to ContentAccessException',
    () async {
      await mockChannel((call) {
        throw PlatformException(code: 'permissionRequestFailed');
      });

      expect(
        buildAccess().requestMediaAccess(ContentCategory.images),
        throwsA(
          isA<ContentAccessException>().having(
            (e) => e.code,
            'code',
            'permissionRequestFailed',
          ),
        ),
      );
    },
  );

  test('requestDocumentTree parses a successful grant', () async {
    await mockChannel(
      (call) => {
        'cancelled': false,
        'grant': {
          'uri': 'content://authority/tree/folder',
          'displayName': 'Documents',
          'persisted': true,
          'readable': true,
          'writable': false,
        },
      },
    );

    final result = await buildAccess().requestDocumentTree();

    expect(calls.single.method, 'requestDocumentTree');
    expect(result.cancelled, isFalse);
    expect(result.grant?.displayName, 'Documents');
  });

  test('requestDocumentTree parses cancellation', () async {
    await mockChannel((call) => {'cancelled': true, 'grant': null});

    final result = await buildAccess().requestDocumentTree();

    expect(result.cancelled, isTrue);
    expect(result.grant, isNull);
  });

  test('listDocumentTreeGrants parses the grant list', () async {
    await mockChannel(
      (call) => [
        {
          'uri': 'content://a/tree/x',
          'displayName': 'X',
          'persisted': true,
          'readable': true,
          'writable': false,
        },
      ],
    );

    final grants = await buildAccess().listDocumentTreeGrants();

    expect(calls.single.method, 'listDocumentTreeGrants');
    expect(grants, hasLength(1));
    expect(grants.single.displayName, 'X');
  });

  test(
    'releaseDocumentTreeGrant sends the uri and returns the boolean',
    () async {
      await mockChannel((call) => true);

      final released = await buildAccess().releaseDocumentTreeGrant(
        'content://authority/tree/x',
      );

      expect(calls.single.method, 'releaseDocumentTreeGrant');
      expect(calls.single.arguments, {'uri': 'content://authority/tree/x'});
      expect(released, isTrue);
    },
  );
}
