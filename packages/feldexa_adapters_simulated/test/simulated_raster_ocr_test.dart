// T028 SIMULATED raster and OCR adapter tests.
//
// These prove deterministic pixel dimensions, byte-stable rasters, and the
// pre-authored OCR mapping. Host-VM evidence; labels stay `SIMULATED`.

import 'dart:typed_data';

import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/simulated_world.dart';

void main() {
  late SimulatedFixtureCatalog catalog;

  setUpAll(() async {
    catalog = await loadCatalog();
  });

  test('raster descriptor is SIMULATED page raster', () async {
    final world = await SimulatedTestWorld.create();
    final descriptor = world.rasterAdapter.descriptor;
    expect(descriptor.kind, CapabilityKind.pageRaster);
    expect(descriptor.isSimulated, isTrue);
    expect(descriptor.evidence.evidenceClass, EvidenceClass.simulated);
    expect(descriptor.adapterId, simulatedRasterAdapterId);
  });

  test('pageDimensions returns the imported display geometry', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-003');
    for (int index = 0; index < imported.pageCount; index++) {
      final geometry = await world.rasterAdapter.pageDimensions(
        imported.sourceId,
        index,
      );
      expect(geometry.rotation, imported.pages[index].rotation);
      expect(
        geometry.displaySize.width,
        closeTo(imported.pages[index].displaySize.width, 0.0001),
      );
      expect(
        geometry.displaySize.height,
        closeTo(imported.pages[index].displaySize.height, 0.0001),
      );
    }
  });

  test('unknown source and out-of-range pages raise PAGE-001', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    await expectLater(
      world.rasterAdapter.pageDimensions(imported.sourceId, 1),
      throwsA(isA<RenderException>().having((e) => e.code, 'code', 'PAGE-001')),
    );
    await expectLater(
      world.rasterAdapter.renderPage(
        RasterRequest(
          sourceId: imported.sourceId,
          pageIndex: 9,
          scale: 1,
          format: RasterFormat.gray8,
        ),
      ),
      throwsA(isA<RenderException>().having((e) => e.code, 'code', 'PAGE-001')),
    );
    await expectLater(
      world.rasterAdapter.pageDimensions(
        '00000000-0000-4000-8000-000000000999',
        0,
      ),
      throwsA(isA<RenderException>()),
    );
  });

  test('gray8 raster dimensions and byte layout follow the request', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-001');
    final RasterImage image = await world.rasterAdapter.renderPage(
      RasterRequest(
        sourceId: imported.sourceId,
        pageIndex: 0,
        scale: 200 / 72,
        format: RasterFormat.gray8,
      ),
    );
    final display = imported.pages[0].displaySize;
    final expectedWidth = (display.width * (200 / 72)).floor();
    final expectedHeight = (display.height * (200 / 72)).floor();
    expect(image.width, expectedWidth);
    expect(image.height, expectedHeight);
    expect(image.bytesPerRow, image.width);
    expect(image.bytes.length, image.width * image.height);
    expect(image.format, RasterFormat.gray8);
    expect(image.evidence.evidenceClass, EvidenceClass.simulated);
  });

  test('rgba8888 raster uses four bytes per pixel', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final RasterImage image = await world.rasterAdapter.renderPage(
      RasterRequest(
        sourceId: imported.sourceId,
        pageIndex: 0,
        scale: 1,
        format: RasterFormat.rgba8888,
      ),
    );
    expect(image.bytesPerRow, image.width * 4);
    expect(image.bytes.length, image.width * image.height * 4);
  });

  test('renders respect the maxDimensionPx safety cap', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-001');
    final RasterImage image = await world.rasterAdapter.renderPage(
      RasterRequest(
        sourceId: imported.sourceId,
        pageIndex: 0,
        scale: 10,
        format: RasterFormat.gray8,
        maxDimensionPx: 100,
      ),
    );
    expect(image.width, lessThanOrEqualTo(100));
    expect(image.height, lessThanOrEqualTo(100));
  });

  test('the same render request produces byte-identical output', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-002');
    final request = RasterRequest(
      sourceId: imported.sourceId,
      pageIndex: 3,
      scale: 1,
      format: RasterFormat.gray8,
    );
    final RasterImage first = await world.rasterAdapter.renderPage(request);
    final RasterImage second = await world.rasterAdapter.renderPage(request);
    expect(first.bytes, orderedEquals(second.bytes));
    expect(second.evidence.evidenceClass, EvidenceClass.simulated);
  });

  test('different pages produce different deterministic rasters', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-002');
    final RasterImage a = await world.rasterAdapter.renderPage(
      RasterRequest(
        sourceId: imported.sourceId,
        pageIndex: 0,
        scale: 1,
        format: RasterFormat.gray8,
      ),
    );
    final RasterImage b = await world.rasterAdapter.renderPage(
      RasterRequest(
        sourceId: imported.sourceId,
        pageIndex: 1,
        scale: 1,
        format: RasterFormat.gray8,
      ),
    );
    expect(a.bytes, isNot(orderedEquals(b.bytes)));
  });

  test(
    'evict forgets raster origins so OCR can no longer resolve them',
    () async {
      final world = await SimulatedTestWorld.create();
      final imported = await world.importFixture('sf-004');
      final RasterImage image = await world.rasterAdapter.renderPage(
        RasterRequest(
          sourceId: imported.sourceId,
          pageIndex: 0,
          scale: 1,
          format: RasterFormat.gray8,
        ),
      );
      await world.rasterAdapter.evict(imported.sourceId);
      await expectLater(
        world.ocrAdapter.recognize(
          OcrRequest(image: image, pageIndex: 0, languageHint: 'de'),
        ),
        throwsA(isA<OcrUnavailableException>()),
      );
    },
  );

  test(
    'OCR returns the pre-authored blocks for the rendered fixture page',
    () async {
      final world = await SimulatedTestWorld.create();
      final imported = await world.importFixture('sf-001');
      final RasterImage image = await world.rasterAdapter.renderPage(
        RasterRequest(
          sourceId: imported.sourceId,
          pageIndex: 0,
          scale: 200 / 72,
          format: RasterFormat.gray8,
        ),
      );
      final List<OcrBlock> blocks = await world.ocrAdapter.recognize(
        OcrRequest(image: image, pageIndex: 0, languageHint: 'de'),
      );
      final SimulatedOcrPage expected = catalog
          .fixture('sf-001')
          .expectedOcr[0];
      expect(blocks.length, expected.blocks.length);
      for (int index = 0; index < blocks.length; index++) {
        expect(blocks[index].text, expected.blocks[index].text);
        expect(blocks[index].confidence, expected.blocks[index].confidence);
        expect(
          blocks[index].rect.left,
          closeTo(expected.blocks[index].rect.left, 0.0001),
        );
        expect(blocks[index].lines.length, expected.blocks[index].lines.length);
      }
      expect(world.ocrAdapter.descriptor.kind, CapabilityKind.ocr);
      expect(
        world.ocrAdapter.descriptor.evidence.evidenceClass,
        EvidenceClass.simulated,
      );
      expect(world.ocrAdapter.descriptor.adapterId, simulatedOcrAdapterId);
    },
  );

  test('OCR is deterministic across repeated calls', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final RasterImage image = await world.rasterAdapter.renderPage(
      RasterRequest(
        sourceId: imported.sourceId,
        pageIndex: 0,
        scale: 1,
        format: RasterFormat.rgba8888,
      ),
    );
    final OcrRequest request = OcrRequest(
      image: image,
      pageIndex: 0,
      languageHint: 'de',
    );
    final List<OcrBlock> first = await world.ocrAdapter.recognize(request);
    final List<OcrBlock> second = await world.ocrAdapter.recognize(request);
    expect(first.length, second.length);
    for (int index = 0; index < first.length; index++) {
      expect(first[index].text, second[index].text);
      expect(first[index].rect, second[index].rect);
    }
  });

  test('OCR rejects an unrasterized image and a non-German hint', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final RasterImage image = await world.rasterAdapter.renderPage(
      RasterRequest(
        sourceId: imported.sourceId,
        pageIndex: 0,
        scale: 1,
        format: RasterFormat.gray8,
      ),
    );
    await expectLater(
      world.ocrAdapter.recognize(
        OcrRequest(image: image, pageIndex: 0, languageHint: 'en'),
      ),
      throwsA(isA<OcrUnavailableException>()),
    );
    final RasterImage foreign = RasterImage(
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      width: 2,
      height: 2,
      bytesPerRow: 2,
      format: RasterFormat.gray8,
      evidence: CapabilityEvidence.simulated(adapterId: 'web.sim.raster.v1'),
    );
    await expectLater(
      world.ocrAdapter.recognize(
        OcrRequest(image: foreign, pageIndex: 0, languageHint: 'de'),
      ),
      throwsA(isA<OcrUnavailableException>()),
    );
  });

  test('dispose makes OCR unavailable', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final RasterImage image = await world.rasterAdapter.renderPage(
      RasterRequest(
        sourceId: imported.sourceId,
        pageIndex: 0,
        scale: 1,
        format: RasterFormat.gray8,
      ),
    );
    await world.ocrAdapter.dispose();
    expect(world.ocrAdapter.isDisposed, isTrue);
    await expectLater(
      world.ocrAdapter.recognize(
        OcrRequest(image: image, pageIndex: 0, languageHint: 'de'),
      ),
      throwsA(isA<OcrUnavailableException>()),
    );
  });
}
