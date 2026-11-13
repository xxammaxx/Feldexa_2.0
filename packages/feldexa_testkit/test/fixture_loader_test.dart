// T011 fixture-loader tests.
//
// Loads every committed fixture through the real filesystem source, verifies
// size and SHA-256 independently, and checks the three delivery copies are
// byte-identical. Host-VM checks only: the fixtures are SIMULATED input, not
// SIMULATED runtime evidence and never Android evidence.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:feldexa_testkit/feldexa_testkit.dart';
import 'package:feldexa_testkit/io.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture_helpers.dart';

void main() {
  group('canonical loader', () {
    late FixtureCheckout checkout;
    late FixtureLoader loader;

    setUpAll(() async {
      checkout = FixtureCheckout.locate();
      loader = await checkout.openLoader();
    });

    test('opens and validates the canonical catalogue', () {
      expect(loader.catalog.evidenceClass, EvidenceClass.simulated);
      expect(loader.catalog.fixtures, hasLength(7));
      expect(
        loader.source.description,
        contains(checkout.canonicalDevDirectory),
      );
    });

    test('loads every fixture with the declared bytes and hash', () async {
      for (final FixtureDescriptor descriptor in loader.catalog.fixtures) {
        final LoadedFixture fixture = await loader.load(descriptor.id);
        expect(fixture.sizeBytes, descriptor.sizeBytes, reason: descriptor.id);
        expect(
          sha256Hex(fixture.bytes),
          descriptor.sha256,
          reason: descriptor.id,
        );
        expect(fixture.descriptor.id, descriptor.id);
        expect(fixture.bytes, isA<Uint8List>());
      }
    });

    test('keeps the documented PDF shape per status', () async {
      for (final FixtureDescriptor descriptor in loader.catalog.fixtures) {
        final LoadedFixture fixture = await loader.load(descriptor.id);
        final String head = latin1.decode(
          fixture.bytes.take(5).toList(growable: false),
        );
        final String text = latin1.decode(fixture.bytes);
        switch (descriptor.status) {
          case FixtureStatus.valid:
          case FixtureStatus.encrypted:
            expect(head, '%PDF-', reason: descriptor.id);
            expect(text.trimRight(), endsWith('%%EOF'), reason: descriptor.id);
          case FixtureStatus.truncated:
            expect(head, '%PDF-', reason: descriptor.id);
            expect(text.trimRight(), isNot(endsWith('%%EOF')));
          case FixtureStatus.notAPdf:
            expect(head, isNot('%PDF-'), reason: descriptor.id);
            expect(text, contains('keine PDF-Datei'));
        }
      }
    });

    test('loads all fixtures in catalogue order', () async {
      final List<LoadedFixture> fixtures = await loader.loadAll();
      expect(
        fixtures.map((LoadedFixture fixture) => fixture.descriptor.id),
        loader.catalog.fixtures.map(
          (FixtureDescriptor descriptor) => descriptor.id,
        ),
      );
    });

    test('loads and validates every expected-OCR document', () async {
      for (final FixtureDescriptor descriptor in loader.catalog.validFixtures) {
        final Map<String, Object?> document = await loader.loadExpectedOcr(
          descriptor.id,
        );
        expect(document['schemaVersion'], 1);
        expect(document['fixtureId'], descriptor.id);
        expect(document['language'], 'de');
        expect(document['evidenceClass'], 'simulated');
        final List<Object?> pages = document['pages']! as List<Object?>;
        expect(pages, hasLength(descriptor.expectedOcr!.pageCount));
      }
    });

    test('rejects expected OCR for an import-failure fixture', () async {
      await expectLater(
        loader.loadExpectedOcr('sf-protected'),
        throwsA(isA<FixtureLoadException>()),
      );
    });

    test('rejects an unknown fixture id', () async {
      await expectLater(
        loader.load('sf-999'),
        throwsA(
          isA<FixtureLoadException>().having(
            (FixtureLoadException error) => error.message,
            'message',
            contains('sf-001'),
          ),
        ),
      );
    });

    test('canonical, Web, and corpus copies are byte-identical', () async {
      final FixtureLoader webLoader = await FixtureLoader.open(
        checkout.sourceFor(loader.catalog, FixtureDeliveryTarget.web),
      );
      final FixtureLoader corpusLoader = FixtureLoader(
        catalog: loader.catalog,
        source: checkout.sourceFor(
          loader.catalog,
          FixtureDeliveryTarget.corpus,
        ),
      );

      expect(webLoader.catalog.catalogVersion, loader.catalog.catalogVersion);
      for (final FixtureDescriptor descriptor in loader.catalog.fixtures) {
        final LoadedFixture canonical = await loader.load(descriptor.id);
        final LoadedFixture web = await webLoader.load(descriptor.id);
        final LoadedFixture corpus = await corpusLoader.load(descriptor.id);
        expect(web.bytes, canonical.bytes, reason: '${descriptor.id} web');
        expect(
          corpus.bytes,
          canonical.bytes,
          reason: '${descriptor.id} corpus',
        );
      }
    });

    test(
      'Web expected-OCR mirror is byte-identical for valid fixtures',
      () async {
        final FileFixtureSource webSource = checkout.sourceFor(
          loader.catalog,
          FixtureDeliveryTarget.web,
        );
        final FixtureLoader webLoader = await FixtureLoader.open(webSource);
        for (final FixtureDescriptor descriptor
            in loader.catalog.validFixtures) {
          final Uint8List canonicalBytes = await FileFixtureSource(
            checkout.canonicalDevDirectory,
          ).read(descriptor.expectedOcr!.path);
          final Uint8List webBytes = await webSource.read(
            descriptor.expectedOcr!.path,
          );
          expect(webBytes, canonicalBytes, reason: descriptor.id);
          final Map<String, Object?> document = await webLoader.loadExpectedOcr(
            descriptor.id,
          );
          expect(document['fixtureId'], descriptor.id);
        }
      },
    );

    test('marks the catalogue as SIMULATED, never Android evidence', () {
      expect(loader.catalog.evidenceClass, EvidenceClass.simulated);
      expect(loader.catalog.evidenceClass.isAndroid, isFalse);
    });
  });

  group('integrity failures', () {
    late String catalogJson;
    late Uint8List pdfBytes;

    setUpAll(() {
      final FixtureCheckout checkout = FixtureCheckout.locate();
      catalogJson = File('${checkout.canonicalDevDirectory}/catalog.json')
          .readAsStringSync();
      pdfBytes = File('${checkout.canonicalDevDirectory}/sf-001.pdf')
          .readAsBytesSync();
    });

    FixtureLoader memoryLoader(
      Map<String, List<int>> files, {
      FixtureDigest? digest,
    }) => FixtureLoader(
      catalog: FixtureCatalog.parse(catalogJson),
      source: InMemoryFixtureSource(files),
      digest: digest,
    );

    test('detects a checksum mismatch', () async {
      final Uint8List corrupt = Uint8List.fromList(pdfBytes)..[100] ^= 0xff;
      final FixtureLoader loader = memoryLoader(<String, List<int>>{
        'sf-001.pdf': corrupt,
      });
      await expectLater(
        loader.load('sf-001'),
        throwsA(
          isA<FixtureLoadException>().having(
            (FixtureLoadException error) => error.message,
            'message',
            contains('SHA-256 mismatch'),
          ),
        ),
      );
    });

    test('detects a declared-size mismatch', () async {
      final FixtureLoader loader = memoryLoader(<String, List<int>>{
        'sf-001.pdf': pdfBytes.sublist(0, pdfBytes.length - 1),
      });
      await expectLater(
        loader.load('sf-001'),
        throwsA(
          isA<FixtureLoadException>().having(
            (FixtureLoadException error) => error.message,
            'message',
            contains('declared'),
          ),
        ),
      );
    });

    test('detects a missing fixture file', () async {
      final FixtureLoader loader = memoryLoader(const <String, List<int>>{});
      await expectLater(
        loader.load('sf-001'),
        throwsA(
          isA<FixtureLoadException>().having(
            (FixtureLoadException error) => error.path,
            'path',
            'sf-001.pdf',
          ),
        ),
      );
    });

    test('detects a wrong PDF shape even without a checksum', () async {
      final Uint8List notPdf = Uint8List.fromList(pdfBytes);
      notPdf.setRange(0, 5, ascii.encode('XXXXX'));
      final FixtureLoader loader = memoryLoader(<String, List<int>>{
        'sf-001.pdf': notPdf,
      });
      await expectLater(
        loader.load('sf-001', verifyChecksum: false),
        throwsA(
          isA<FixtureLoadException>().having(
            (FixtureLoadException error) => error.message,
            'message',
            contains('%PDF-'),
          ),
        ),
      );
    });

    test('skips the digest only when explicitly asked', () async {
      int digestCalls = 0;
      String countingDigest(List<int> bytes) {
        digestCalls++;
        return sha256Hex(bytes);
      }

      final FixtureLoader loader = memoryLoader(<String, List<int>>{
        'sf-001.pdf': pdfBytes,
      }, digest: countingDigest);
      await loader.load('sf-001', verifyChecksum: false);
      expect(digestCalls, 0);
      await loader.load('sf-001');
      expect(digestCalls, 1);
    });

    test('rejects an invalid expected-OCR document', () async {
      final Map<String, Object?> catalog = catalogMap();
      final List<Map<String, Object?>> fixtures = fixturesIn(catalog);
      final Map<String, Object?> editor = fixtures.first;
      final Map<String, Object?> expectedOcr =
          editor['expectedOcr']! as Map<String, Object?>;
      expectedOcr['blockCount'] = 1;

      final FixtureLoader loader = FixtureLoader(
        catalog: FixtureCatalog.fromJson(catalog),
        source: InMemoryFixtureSource(<String, List<int>>{
          'sf-001.expected-ocr.json': File(
            '${FixtureCheckout.locate().canonicalDevDirectory}/sf-001.expected-ocr.json',
          ).readAsBytesSync(),
        }),
      );
      await expectLater(
        loader.loadExpectedOcr('sf-001'),
        throwsA(
          isA<FixtureLoadException>().having(
            (FixtureLoadException error) => error.message,
            'message',
            contains('blocks'),
          ),
        ),
      );
    });

    test(
      'rejects a catalog with a Windows delivery traversal before I/O',
      () async {
        final Map<String, Object?> catalog = copyOfCatalog();
        final Map<String, Object?> delivery =
            catalog['delivery']! as Map<String, Object?>;
        delivery['webDirectory'] = r'..\..\outside';
        await expectLater(
          FixtureLoader.open(
            InMemoryFixtureSource.fromText(<String, String>{
              'catalog.json': jsonEncode(catalog),
            }),
          ),
          throwsA(
            isA<FixtureLoadException>().having(
              (FixtureLoadException error) => error.message,
              'message',
              contains('backslash'),
            ),
          ),
        );
      },
    );

    test('wraps malformed catalog JSON', () async {
      await expectLater(
        FixtureLoader.open(
          InMemoryFixtureSource.fromText(<String, String>{
            'catalog.json': '{not json',
          }),
        ),
        throwsA(isA<FixtureLoadException>()),
      );
    });
  });
}
