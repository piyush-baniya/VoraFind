import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vorafind/core/platform/content_access_models.dart';

void main() {
  group('ContentCategory', () {
    test('parses wire values', () {
      expect(ContentCategory.fromWire('images'), ContentCategory.images);
      expect(ContentCategory.fromWire('videos'), ContentCategory.videos);
      expect(ContentCategory.fromWire('audio'), ContentCategory.audio);
      expect(ContentCategory.fromWire('documents'), ContentCategory.documents);
    });

    test('rejects unknown wire values', () {
      expect(
        () => ContentCategory.fromWire('files'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ContentAccessState', () {
    test('parses wire values', () {
      expect(
        ContentAccessState.fromWire('notRequired'),
        ContentAccessState.notRequired,
      );
      expect(
        ContentAccessState.fromWire('noAccess'),
        ContentAccessState.noAccess,
      );
      expect(ContentAccessState.fromWire('denied'), ContentAccessState.denied);
      expect(
        ContentAccessState.fromWire('permanentlyDenied'),
        ContentAccessState.permanentlyDenied,
      );
      expect(
        ContentAccessState.fromWire('fullAccess'),
        ContentAccessState.fullAccess,
      );
      expect(
        ContentAccessState.fromWire('partialAccess'),
        ContentAccessState.partialAccess,
      );
    });

    test('rejects unknown wire values', () {
      expect(
        () => ContentAccessState.fromWire('granted'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ContentCategoryAccess', () {
    ContentCategoryAccess access(String state) =>
        ContentCategoryAccess.fromJson({'category': 'images', 'state': state});

    test('full access can query and read everything', () {
      final a = access('fullAccess');
      expect(a.canQuery, isTrue);
      expect(a.canReadAll, isTrue);
      expect(a.canReadSelected, isTrue);
    });

    test('partial access can query but never reads the full library', () {
      final a = access('partialAccess');
      expect(a.canQuery, isTrue);
      expect(a.canReadAll, isFalse);
      expect(a.canReadSelected, isTrue);
    });

    test('no access cannot query anything', () {
      final a = access('noAccess');
      expect(a.canQuery, isFalse);
      expect(a.canReadAll, isFalse);
      expect(a.canReadSelected, isFalse);
    });

    test('denied and permanently denied cannot query', () {
      expect(access('denied').canQuery, isFalse);
      expect(access('permanentlyDenied').canQuery, isFalse);
    });

    test('not required can query without reading treats source as scoped', () {
      final a = access('notRequired');
      expect(a.canQuery, isTrue);
      expect(a.canReadAll, isFalse);
      expect(a.canReadSelected, isFalse);
    });

    test(
      'capabilities are derived from state, not trusting the wire booleans',
      () {
        final a = ContentCategoryAccess.fromJson({
          'category': 'videos',
          'state': 'partialAccess',
          'canQuery': false,
          'canReadAll': true,
          'canReadSelected': false,
        });
        expect(a.canQuery, isTrue);
        expect(a.canReadAll, isFalse);
        expect(a.canReadSelected, isTrue);
      },
    );

    test('rejects an unknown state', () {
      expect(
        () => ContentCategoryAccess.fromJson({
          'category': 'images',
          'state': 'full',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ContentCapabilities', () {
    Map<String, dynamic> fullPayload() => {
      'contractVersion': 1,
      'apiLevel': 36,
      'safCapable': true,
      'mediaStoreGenerationSupported': true,
      'partialMediaAccessSupported': true,
      'externalVolumes': ['external_primary'],
      'categories': [
        {'category': 'images', 'state': 'fullAccess'},
        {'category': 'videos', 'state': 'noAccess'},
        {'category': 'audio', 'state': 'denied'},
        {'category': 'documents', 'state': 'partialAccess'},
      ],
    };

    test('parses a full capability payload', () {
      final capabilities = ContentCapabilities.fromJson(fullPayload());
      expect(capabilities.contractVersion, 1);
      expect(capabilities.apiLevel, 36);
      expect(capabilities.safCapable, isTrue);
      expect(capabilities.mediaStoreGenerationSupported, isTrue);
      expect(capabilities.partialMediaAccessSupported, isTrue);
      expect(capabilities.externalVolumes, ['external_primary']);
      expect(capabilities.categories, hasLength(4));
      expect(
        capabilities.accessFor(ContentCategory.images).state,
        ContentAccessState.fullAccess,
      );
      expect(
        capabilities.accessFor(ContentCategory.documents).state,
        ContentAccessState.partialAccess,
      );
    });

    test('documents partial access never claims to read the whole library', () {
      final capabilities = ContentCapabilities.fromJson(fullPayload());
      final documents = capabilities.accessFor(ContentCategory.documents);
      expect(documents.canQuery, isTrue);
      expect(documents.canReadAll, isFalse);
      expect(documents.canReadSelected, isTrue);
    });

    test('rejects malformed payloads', () {
      final payload = fullPayload()..['categories'] = 'nope';
      expect(
        () => ContentCapabilities.fromJson(payload),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('DocumentGrant / DocumentGrantResult', () {
    test('parses a grant', () {
      final grant = DocumentGrant.fromJson({
        'uri': 'content://authority/tree/x',
        'displayName': 'Documents',
        'persisted': true,
        'readable': true,
        'writable': false,
      });
      expect(grant.uri, 'content://authority/tree/x');
      expect(grant.displayName, 'Documents');
      expect(grant.persisted, isTrue);
      expect(grant.readable, isTrue);
      expect(grant.writable, isFalse);
    });

    test('parses a successful picker result', () {
      final result = DocumentGrantResult.fromJson({
        'cancelled': false,
        'grant': {
          'uri': 'content://a/tree/b',
          'displayName': 'Downloads',
          'persisted': true,
          'readable': true,
          'writable': false,
        },
      });
      expect(result.cancelled, isFalse);
      expect(result.grant, isNotNull);
    });

    test('parses a cancelled picker result without a grant', () {
      final result = DocumentGrantResult.fromJson({
        'cancelled': true,
        'grant': null,
      });
      expect(result.cancelled, isTrue);
      expect(result.grant, isNull);
    });
  });

  group('ContentAccessException', () {
    test('maps a PlatformException to a user-safe code/message', () {
      final exception = ContentAccessException.fromPlatformException(
        PlatformException(code: 'pickUnavailable', message: 'no picker'),
      );
      expect(exception.code, 'pickUnavailable');
      expect(exception.message, 'no picker');
      expect(exception.toString(), contains('pickUnavailable'));
    });

    test('falls back to the code when no message is present', () {
      final exception = ContentAccessException.fromPlatformException(
        PlatformException(code: 'security'),
      );
      expect(exception.message, 'security');
    });
  });
}
