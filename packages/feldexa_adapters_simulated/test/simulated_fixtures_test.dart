// T028 fixture-catalogue tests.
//
// These tests prove the adapter-local projection agrees with the canonical
// T011 catalogue and that a drifting or tampered fixture is refused. All
// evidence here is host-VM (`NONE`); the catalogue itself stays `SIMULATED`.

import 'dart:convert';
import 'dart:typed_data';

import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_testkit/io.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/simulated_world.dart';

void main() {
  late SimulatedFixtureCatalog catalog;

  setUpAll(() async {
    catalog = await loadCatalog();
  });

  test('parses every committed fixture with canonical pins', () async {
    final FixtureCheckout checkout = FixtureCheckout.locate();
    final loader = await checkout.openLoader();
    expect(catalog.fixtures.length, loader.catalog.fixtures.length);
    expect(catalog.catalogVersion, loader.catalog.catalogVersion);
    for (final descriptor in loader.catalog.fixtures) {
      final SimulatedFixture fixture = catalog.fixture(descriptor.id);
      expect(fixture.sha256, descriptor.sha256);
      expect(fixture.sizeBytes, descriptor.sizeBytes);
      expect(fixture.pageCount, descriptor.pageCount);
      expect(fixture.bytes.length, descriptor.sizeBytes);
      expect(fixture.displayName, descriptor.path);
      expect(fixture.status.wireName, descriptor.status.wireName);
      expect(fixture.role.wireName, descriptor.role.wireName);
      if (descriptor.expectedOcr == null) {
        expect(fixture.expectedOcr, isEmpty);
        expect(fixture.expectedErrorCode, descriptor.expectedError);
      } else {
        final int blocks = fixture.expectedOcr.fold<int>(
          0,
          (int sum, SimulatedOcrPage page) => sum + page.blocks.length,
        );
        expect(blocks, descriptor.expectedOcr!.blockCount);
        expect(fixture.expectedErrorCode, isNull);
      }
    }
  });

  test(
    'page geometry matches the declared display size for every rotation',
    () {
      for (final SimulatedFixture fixture in catalog.fixtures) {
        for (final SimulatedFixturePage page in fixture.pages) {
          final geometry = page.toGeometry();
          expect(geometry.rotation, page.rotation);
          expect(geometry.displaySize.width, closeTo(page.widthPt, 0.01));
          expect(geometry.displaySize.height, closeTo(page.heightPt, 0.01));
        }
      }
    },
  );

  test('expected OCR blocks use display points inside the page', () {
    final SimulatedFixture fixture = catalog.fixture('sf-003');
    for (final SimulatedOcrPage page in fixture.expectedOcr) {
      for (final SimulatedOcrBlock block in page.blocks) {
        expect(block.rect.left, greaterThanOrEqualTo(0));
        expect(block.rect.top, greaterThanOrEqualTo(0));
        expect(block.rect.right, lessThanOrEqualTo(page.widthPt + 0.01));
        expect(block.rect.bottom, lessThanOrEqualTo(page.heightPt + 0.01));
        expect(block.confidence, inInclusiveRange(0, 1));
        expect(block.lines, isNotEmpty);
      }
    }
  });

  test('import-failure fixtures carry the typed expected codes', () {
    expect(catalog.fixture('sf-protected').expectedErrorCode, 'IMP-001');
    expect(catalog.fixture('sf-truncated').expectedErrorCode, 'IMP-002');
    expect(catalog.fixture('sf-not-a-pdf').expectedErrorCode, 'IMP-004');
  });

  test('unknown fixture ids are refused without content', () {
    expect(
      () => catalog.fixture('does-not-exist'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('tampered PDF bytes fail the SHA-256 pin', () async {
    final FixtureCheckout checkout = FixtureCheckout.locate();
    final loader = await checkout.openLoader();
    final Map<String, Uint8List> pdfBytes = <String, Uint8List>{};
    final Map<String, Map<String, Object?>> expectedOcr =
        <String, Map<String, Object?>>{};
    for (final descriptor in loader.catalog.fixtures) {
      pdfBytes[descriptor.id] = (await loader.load(descriptor.id)).bytes;
      if (descriptor.expectedOcr != null) {
        expectedOcr[descriptor.id] = await loader.loadExpectedOcr(
          descriptor.id,
        );
      }
    }
    final Uint8List tampered = Uint8List.fromList(pdfBytes['sf-001']!);
    tampered[tampered.length - 1] ^= 0xFF;
    pdfBytes['sf-001'] = tampered;
    expect(
      () => SimulatedFixtureCatalog.parse(
        catalogJson: jsonEncode(loader.catalog.raw),
        pdfBytesById: pdfBytes,
        expectedOcrById: expectedOcr,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('a non-SIMULATED catalogue is refused', () async {
    final FixtureCheckout checkout = FixtureCheckout.locate();
    final loader = await checkout.openLoader();
    final Map<String, Object?> raw = Map<String, Object?>.from(
      loader.catalog.raw,
    );
    raw['evidenceClass'] = 'emulator';
    final Map<String, Uint8List> pdfBytes = <String, Uint8List>{};
    final Map<String, Map<String, Object?>> expectedOcr =
        <String, Map<String, Object?>>{};
    for (final descriptor in loader.catalog.fixtures) {
      pdfBytes[descriptor.id] = (await loader.load(descriptor.id)).bytes;
      if (descriptor.expectedOcr != null) {
        expectedOcr[descriptor.id] = await loader.loadExpectedOcr(
          descriptor.id,
        );
      }
    }
    expect(
      () => SimulatedFixtureCatalog.parse(
        catalogJson: jsonEncode(raw),
        pdfBytesById: pdfBytes,
        expectedOcrById: expectedOcr,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
