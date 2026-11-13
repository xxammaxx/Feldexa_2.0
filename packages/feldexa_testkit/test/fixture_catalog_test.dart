// T011 fixture-catalogue tests.
//
// Validates the committed T009 catalogue contract and the parser's rejection
// paths. Host-VM checks only; the catalogue is SIMULATED input, not runtime
// evidence.

import 'package:feldexa_testkit/feldexa_testkit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture_helpers.dart';

void main() {
  group('committed catalogue', () {
    late FixtureCatalog catalog;

    setUpAll(() {
      catalog = FixtureCatalog.parse(catalogSource());
    });

    test('is schema 1, fixtures-1.0.0, and SIMULATED', () {
      expect(catalog.schemaVersion, 1);
      expect(catalog.catalogVersion, 'fixtures-1.0.0');
      expect(catalog.evidenceClass, EvidenceClass.simulated);
      expect(catalog.evidenceClass.isAndroid, isFalse);
      expect(catalog.fixtures, hasLength(7));
    });

    test('declares dev-only delivery and no Flutter assets', () {
      final FixtureDeliveryPaths delivery = catalog.delivery;
      expect(delivery.flutterAssetsDeclared, isFalse);
      expect(
        delivery.canonicalDevDirectory,
        'apps/feldexa_app/assets/fixtures',
      );
      expect(delivery.webDirectory, 'apps/feldexa_app/web/fixtures');
      expect(delivery.corpusDirectory, 'tools/corpus/synthetic');
      expect(delivery.webBaseUrl, '/fixtures');
      expect(delivery.androidRelease, contains('never packaged'));
      expect(delivery.androidTestDelivery, contains('adb push'));
    });

    test('exposes four valid fixtures and three import failures', () {
      expect(catalog.validFixtures, hasLength(4));
      expect(catalog.importFailures, hasLength(3));
      expect(catalog.byRole(FixtureRole.editor), hasLength(1));
      expect(catalog.byRole(FixtureRole.navigation), hasLength(1));
      expect(catalog.byRole(FixtureRole.geometry), hasLength(1));
      expect(catalog.byRole(FixtureRole.fields), hasLength(1));
      expect(catalog.byRole(FixtureRole.importFailure), hasLength(3));
    });

    test('exposes typed pages and ground truth', () {
      final FixtureDescriptor descriptor = catalog.fixture('sf-001');
      expect(descriptor.role, FixtureRole.editor);
      expect(descriptor.status, FixtureStatus.valid);
      expect(descriptor.pageCount, 2);
      expect(descriptor.pages.map((FixturePage page) => page.index), <int>[
        0,
        1,
      ]);
      expect(descriptor.groundTruthFields, hasLength(23));
      expect(descriptor.expectedOcr?.blockCount, 53);
      expect(descriptor.expectedError, isNull);

      final FixtureDescriptor geometry = catalog.fixture('sf-003');
      expect(geometry.pages.map((FixturePage page) => page.rotation), <int>[
        0,
        0,
        90,
        180,
        270,
      ]);
    });

    test('maps each delivery target to its declared path', () {
      final FixtureDescriptor descriptor = catalog.fixture('sf-001');
      expect(
        descriptor.pathFor(FixtureDeliveryTarget.canonicalDev),
        'apps/feldexa_app/assets/fixtures/sf-001.pdf',
      );
      expect(
        descriptor.pathFor(FixtureDeliveryTarget.web),
        'apps/feldexa_app/web/fixtures/sf-001.pdf',
      );
      expect(
        descriptor.pathFor(FixtureDeliveryTarget.corpus),
        'tools/corpus/synthetic/sf-001.pdf',
      );
      for (final FixtureDeliveryTarget target in FixtureDeliveryTarget.values) {
        expect(
          target.inputEvidenceClass,
          EvidenceClass.simulated,
          reason: 'fixtures are SIMULATED inputs in every target',
        );
        expect(target.inputEvidenceClass.isAndroid, isFalse);
        expect(descriptor.pathFor(target), endsWith('/${descriptor.path}'));
      }
    });

    test('failure fixtures declare their catalog codes', () {
      expect(catalog.fixture('sf-protected').expectedError, 'IMP-001');
      expect(catalog.fixture('sf-truncated').expectedError, 'IMP-002');
      expect(catalog.fixture('sf-not-a-pdf').expectedError, 'IMP-004');
      expect(catalog.fixture('sf-protected').status, FixtureStatus.encrypted);
      expect(catalog.fixture('sf-truncated').status, FixtureStatus.truncated);
      expect(catalog.fixture('sf-not-a-pdf').status, FixtureStatus.notAPdf);
    });

    test('exposes the catalogue entry as deeply immutable data', () {
      final FixtureDescriptor descriptor = catalog.fixture('sf-001');
      expect(() => descriptor.raw['id'] = 'changed', throwsUnsupportedError);
      expect(
        () => descriptor.groundTruth['fields'] = const <Object?>[],
        throwsUnsupportedError,
      );
      expect(descriptor.raw['id'], 'sf-001');
    });

    test('looks up fixtures by id and reports unknown ids', () {
      expect(catalog.fixture('sf-004').role, FixtureRole.fields);
      expect(
        () => catalog.fixture('sf-999'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message.toString(),
            'message',
            contains('sf-001'),
          ),
        ),
      );
    });

    test('round-trips to a stable string summary', () {
      expect(
        catalog.toString(),
        'FixtureCatalog(fixtures-1.0.0, 7 SIMULATED fixtures)',
      );
    });
  });

  group('validation', () {
    test('rejects an unsupported schema version', () {
      final Map<String, Object?> catalog = copyOfCatalog();
      catalog['schemaVersion'] = 2;
      expect(
        () => FixtureCatalog.fromJson(catalog),
        throwsFormatWith('schemaVersion'),
      );
    });

    test('rejects non-SIMULATED evidence, including Android classes', () {
      for (final String value in <String>['EMULATOR', 'DEVICE', 'NONE']) {
        final Map<String, Object?> catalog = copyOfCatalog();
        catalog['evidenceClass'] = value;
        expect(
          () => FixtureCatalog.fromJson(catalog),
          throwsFormatWith('SIMULATED'),
          reason: value,
        );
      }
    });

    test('rejects a fixture count that does not match', () {
      final Map<String, Object?> catalog = copyOfCatalog();
      catalog['fixtureCount'] = 8;
      expect(
        () => FixtureCatalog.fromJson(catalog),
        throwsFormatWith('fixtureCount'),
      );
    });

    test('rejects duplicate fixture ids', () {
      final Map<String, Object?> catalog = copyOfCatalog();
      final List<Map<String, Object?>> fixtures = fixturesIn(catalog);
      fixtures.add(fixtures.first);
      catalog['fixtureCount'] = fixtures.length;
      expect(
        () => FixtureCatalog.fromJson(catalog),
        throwsFormatWith('duplicate id'),
      );
    });

    test('rejects a malformed SHA-256 pin', () {
      final Map<String, Object?> catalog = copyOfCatalog();
      fixturesIn(catalog).first['sha256'] = 'ABC';
      expect(
        () => FixtureCatalog.fromJson(catalog),
        throwsFormatWith('sha256'),
      );
    });

    test('rejects a wrong failure code', () {
      final Map<String, Object?> catalog = copyOfCatalog();
      final List<Map<String, Object?>> fixtures = fixturesIn(catalog);
      final Map<String, Object?> protectedFixture = fixtures.firstWhere(
        (Map<String, Object?> fixture) => fixture['id'] == 'sf-protected',
      );
      protectedFixture['expectedError'] = 'IMP-999';
      expect(
        () => FixtureCatalog.fromJson(catalog),
        throwsFormatWith('expectedError'),
      );
    });

    test('rejects Flutter-asset fixture delivery', () {
      final Map<String, Object?> catalog = copyOfCatalog();
      final Map<String, Object?> delivery =
          catalog['delivery']! as Map<String, Object?>;
      delivery['flutterAssetsDeclared'] = true;
      expect(
        () => FixtureCatalog.fromJson(catalog),
        throwsFormatWith('flutterAssetsDeclared'),
      );
    });

    test('rejects personal data in the synthetic catalogue', () {
      final Map<String, Object?> catalog = copyOfCatalog();
      final Map<String, Object?> rights =
          catalog['rights']! as Map<String, Object?>;
      rights['containsPersonalData'] = true;
      expect(
        () => FixtureCatalog.fromJson(catalog),
        throwsFormatWith('containsPersonalData'),
      );
    });

    test('rejects a page-count mismatch', () {
      final Map<String, Object?> catalog = copyOfCatalog();
      fixturesIn(catalog).first['pageCount'] = 3;
      expect(
        () => FixtureCatalog.fromJson(catalog),
        throwsFormatWith('pageCount'),
      );
    });

    test('rejects an invalid page rotation', () {
      final Map<String, Object?> catalog = copyOfCatalog();
      pagesIn(fixturesIn(catalog).first).first['rotation'] = 45;
      expect(
        () => FixtureCatalog.fromJson(catalog),
        throwsFormatWith('rotation'),
      );
    });

    test('rejects an unexpected OCR document on a failure fixture', () {
      final Map<String, Object?> catalog = copyOfCatalog();
      final Map<String, Object?> protectedFixture = fixturesIn(catalog)
          .firstWhere(
            (Map<String, Object?> fixture) => fixture['id'] == 'sf-protected',
          );
      protectedFixture['expectedOcr'] = <String, Object?>{
        'path': 'sf-protected.expected-ocr.json',
        'schemaVersion': 1,
        'language': 'de',
        'pageCount': 1,
        'blockCount': 1,
      };
      expect(
        () => FixtureCatalog.fromJson(catalog),
        throwsFormatWith('must not declare expectedOcr'),
      );
    });

    test('rejects a path that does not match the id', () {
      final Map<String, Object?> catalog = copyOfCatalog();
      fixturesIn(catalog).first['path'] = 'other.pdf';
      expect(
        () => FixtureCatalog.fromJson(catalog),
        throwsFormatWith('sf-001.pdf'),
      );
    });

    test('rejects unknown roles and statuses', () {
      final Map<String, Object?> roleCatalog = copyOfCatalog();
      fixturesIn(roleCatalog).first['role'] = 'mystery';
      expect(
        () => FixtureCatalog.fromJson(roleCatalog),
        throwsFormatWith('role'),
      );

      final Map<String, Object?> statusCatalog = copyOfCatalog();
      fixturesIn(statusCatalog).first['status'] = 'mystery';
      expect(
        () => FixtureCatalog.fromJson(statusCatalog),
        throwsFormatWith('status'),
      );
    });

    test('rejects a missing required string', () {
      final Map<String, Object?> catalog = copyOfCatalog();
      fixturesIn(catalog).first.remove('title');
      expect(() => FixtureCatalog.fromJson(catalog), throwsFormatWith('title'));
    });

    test('rejects expectedError on a valid fixture', () {
      final Map<String, Object?> catalog = copyOfCatalog();
      fixturesIn(catalog).first['expectedError'] = 'IMP-001';
      expect(
        () => FixtureCatalog.fromJson(catalog),
        throwsFormatWith('expectedError'),
      );
    });

    test('rejects non-synthetic fixture kinds', () {
      final Map<String, Object?> catalog = copyOfCatalog();
      fixturesIn(catalog).first['kind'] = 'real';
      expect(
        () => FixtureCatalog.fromJson(catalog),
        throwsFormatWith('synthetic'),
      );
    });

    test('rejects a valid fixture without ground truth', () {
      final Map<String, Object?> catalog = copyOfCatalog();
      final Map<String, Object?> fixture = fixturesIn(catalog).first;
      final Map<String, Object?> groundTruth =
          fixture['groundTruth']! as Map<String, Object?>;
      groundTruth['fields'] = <Object?>[];
      expect(
        () => FixtureCatalog.fromJson(catalog),
        throwsFormatWith('ground-truth'),
      );
    });

    test('rejects malformed JSON', () {
      expect(
        () => FixtureCatalog.parse('{not json'),
        throwsFormatWith('not valid JSON'),
      );
      expect(() => FixtureCatalog.parse('[]'), throwsFormatWith('JSON object'));
    });
  });

  group('path safety', () {
    test('rejects Windows backslash traversal in every delivery directory', () {
      for (final String key in <String>[
        'canonicalDevDirectory',
        'webDirectory',
        'corpusDirectory',
      ]) {
        final Map<String, Object?> catalog = copyOfCatalog();
        final Map<String, Object?> delivery =
            catalog['delivery']! as Map<String, Object?>;
        delivery[key] = r'..\..\outside';
        expect(
          () => FixtureCatalog.fromJson(catalog),
          throwsFormatWith('backslash'),
          reason: key,
        );
      }
    });

    test(
      'rejects absolute, drive, UNC, and traversal delivery directories',
      () {
        for (final String badValue in <String>[
          '/tmp/outside',
          r'C:\outside',
          'C:/outside',
          r'\\server\share',
          '//server/share',
          '../outside',
          'dir//outside',
          'dir/',
          'dir./outside',
          'dir /outside',
          '.. /outside',
          '.../outside',
          'apps/\u0001outside',
        ]) {
          for (final String key in <String>[
            'canonicalDevDirectory',
            'webDirectory',
            'corpusDirectory',
          ]) {
            final Map<String, Object?> catalog = copyOfCatalog();
            final Map<String, Object?> delivery =
                catalog['delivery']! as Map<String, Object?>;
            delivery[key] = badValue;
            expect(
              () => FixtureCatalog.fromJson(catalog),
              throwsFormatException,
              reason: '$key = $badValue',
            );
          }
        }
      },
    );

    test('rejects unsafe Web base paths', () {
      for (final String badValue in <String>[
        'fixtures',
        'https://evil.example/fixtures',
        '//evil.example/fixtures',
        '/fixtures/../outside',
        r'/fixtures\..\outside',
        r'/..\..\outside',
        '/fixtures?x=1',
        '/fixtures#fragment',
      ]) {
        final Map<String, Object?> catalog = copyOfCatalog();
        final Map<String, Object?> delivery =
            catalog['delivery']! as Map<String, Object?>;
        delivery['webBaseUrl'] = badValue;
        expect(
          () => FixtureCatalog.fromJson(catalog),
          throwsFormatException,
          reason: badValue,
        );
      }
    });

    test('rejects traversal-shaped expected-OCR paths', () {
      for (final String badValue in <String>[
        r'..\..\outside.expected-ocr.json',
        '../outside.expected-ocr.json',
        '/tmp/outside.expected-ocr.json',
        r'C:\outside.expected-ocr.json',
        'other.expected-ocr.json',
      ]) {
        final Map<String, Object?> catalog = copyOfCatalog();
        final Map<String, Object?> editor = fixturesIn(catalog).first;
        final Map<String, Object?> expectedOcr =
            editor['expectedOcr']! as Map<String, Object?>;
        expectedOcr['path'] = badValue;
        expect(
          () => FixtureCatalog.fromJson(catalog),
          throwsFormatWith('expected-ocr.json'),
          reason: badValue,
        );
      }
    });

    test('rejects unsafe generator and fixture paths', () {
      final Map<String, Object?> generatorCatalog = copyOfCatalog();
      final Map<String, Object?> generator =
          generatorCatalog['generator']! as Map<String, Object?>;
      generator['path'] = r'..\..\outside.dart';
      expect(
        () => FixtureCatalog.fromJson(generatorCatalog),
        throwsFormatWith('backslash'),
      );

      final Map<String, Object?> fixtureCatalog = copyOfCatalog();
      fixturesIn(fixtureCatalog).first['path'] = r'..\..\sf-001.pdf';
      expect(
        () => FixtureCatalog.fromJson(fixtureCatalog),
        throwsFormatWith('sf-001.pdf'),
      );

      final Map<String, Object?> assetCatalog = copyOfCatalog();
      fixturesIn(assetCatalog).first['assetPath'] = r'..\..\outside\sf-001.pdf';
      expect(
        () => FixtureCatalog.fromJson(assetCatalog),
        throwsFormatException,
      );

      final Map<String, Object?> syntheticCatalog = copyOfCatalog();
      final Map<String, Object?> synthetic =
          fixturesIn(syntheticCatalog).first['synthetic']!
              as Map<String, Object?>;
      synthetic['generator'] = r'..\..\outside.dart';
      expect(
        () => FixtureCatalog.fromJson(syntheticCatalog),
        throwsFormatWith('backslash'),
      );
    });
  });
}
