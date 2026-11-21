// T062P regression: SIMULATED raster dimensions must equal the production
// 200 DPI analysis raster size.
//
// The regression this pins: `SimulatedPageRasterAdapter` truncated
// `displaySize × scale` with `floor()`, while the production analysis raster
// (`RasterSize.fromDisplaySize`, `raster.dart`) rounds half up. A simulated
// page was therefore one pixel narrower and one pixel shorter than the raster
// the EMULATOR/DEVICE path produces for the same display size (for example
// 1653 × 2338 instead of 1654 × 2339 for A4). Both source packages are
// declared dependencies of this app, so the parity assertion between the
// SIMULATED adapter and the recognition rule lives here rather than in either
// package (the SIMULATED package must not gain a recognition dependency, and
// the recognition package must not gain a SIMULATED dependency).
//
// Host-VM evidence only. Every raster stays labelled `SIMULATED`; this test
// makes no EMULATOR or DEVICE claim.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:feldexa_recognition/src/raster.dart';
import 'package:flutter_test/flutter_test.dart';

const String _sourceId = '00000000-0000-4000-8000-000000000062';
const String _fixtureDirectory = 'apps/feldexa_app/assets/fixtures';

late Directory _repositoryRoot;

/// Builds a hash-verified SIMULATED fixture for [widthPt] × [heightPt].
SimulatedFixture _fixture({
  required String id,
  required double widthPt,
  required double heightPt,
  Uint8List? bytes,
  String? sha256Pin,
  int? sizeBytesPin,
  int pageCount = 1,
  int rotation = 0,
}) {
  final Uint8List content =
      bytes ?? Uint8List.fromList(utf8.encode('%PDF-1.4 synthetic $id'));
  return SimulatedFixture(
    id: id,
    role: SimulatedFixtureRole.editor,
    status: SimulatedFixtureStatus.valid,
    title: 'T062P parity fixture $id',
    displayName: '$id.pdf',
    bytes: content,
    sha256: sha256Pin ?? sha256.convert(content).toString(),
    sizeBytes: sizeBytesPin ?? content.length,
    pages: <SimulatedFixturePage>[
      for (int index = 0; index < pageCount; index++)
        SimulatedFixturePage(
          index: index,
          widthPt: widthPt,
          heightPt: heightPt,
          rotation: rotation,
        ),
    ],
    expectedOcr: const <SimulatedOcrPage>[],
    expectedErrorCode: null,
  );
}

/// Renders [fixture] page [pageIndex] at the production analysis scale.
Future<(RasterImage, PageGeometry)> _render(
  SimulatedFixture fixture, {
  int pageIndex = 0,
}) async {
  final SimulatedBackend backend = SimulatedBackend();
  backend.stageSource(sourceId: _sourceId, fixture: fixture);
  final SimulatedPageRasterAdapter adapter = SimulatedPageRasterAdapter(
    backend: backend,
  );
  final RasterImage image = await adapter.renderPage(
    RasterRequest(
      sourceId: _sourceId,
      pageIndex: pageIndex,
      scale: rasterScale,
      format: RasterFormat.gray8,
    ),
  );
  final PageGeometry geometry = await adapter.pageDimensions(
    _sourceId,
    pageIndex,
  );
  return (image, geometry);
}

/// Asserts the SIMULATED raster size equals `RasterSize.fromDisplaySize`.
void _expectParity(RasterImage image, PageGeometry geometry) {
  final RasterSize expected = RasterSize.fromDisplaySize(
    widthPt: geometry.displaySize.width,
    heightPt: geometry.displaySize.height,
  );
  expect(image.width, expected.widthPx, reason: 'width parity');
  expect(image.height, expected.heightPx, reason: 'height parity');
  expect(image.bytesPerRow, image.width);
  expect(image.bytes.length, image.width * image.height);
  expect(image.evidence.evidenceClass, EvidenceClass.simulated);
}

void main() {
  setUpAll(() {
    _repositoryRoot = Directory.current.parent.parent;
    expect(
      File('${_repositoryRoot.path}/pubspec.yaml').readAsStringSync(),
      contains('feldexa_workspace'),
      reason: 'test must run from apps/feldexa_app inside the monorepo',
    );
  });

  test(
    'A4 portrait SIMULATED raster matches RasterSize.fromDisplaySize',
    () async {
      final (RasterImage image, PageGeometry geometry) = await _render(
        _fixture(id: 't062p-a4-portrait', widthPt: 595.28, heightPt: 841.89),
      );
      expect(geometry.displaySize.width, 595.28);
      expect(geometry.displaySize.height, 841.89);
      // round(595.28 × 200/72) = round(1653.56) = 1654 and
      // round(841.89 × 200/72) = round(2338.58) = 2339; floor() gave 1653/2338.
      expect(image.width, 1654);
      expect(image.height, 2339);
      _expectParity(image, geometry);
    },
  );

  test(
    'A4 landscape SIMULATED raster matches RasterSize.fromDisplaySize',
    () async {
      final (RasterImage image, PageGeometry geometry) = await _render(
        _fixture(id: 't062p-a4-landscape', widthPt: 841.89, heightPt: 595.28),
      );
      expect(geometry.displaySize.width, 841.89);
      expect(geometry.displaySize.height, 595.28);
      expect(image.width, 2339);
      expect(image.height, 1654);
      _expectParity(image, geometry);
    },
  );

  test('A4 landscape (90° rotated page) keeps raster parity', () async {
    final (RasterImage image, PageGeometry geometry) = await _render(
      _fixture(
        id: 't062p-a4-rotated',
        widthPt: 841.89,
        heightPt: 595.28,
        rotation: 90,
      ),
    );
    expect(geometry.rotation, 90);
    expect(geometry.displaySize.width, 841.89);
    expect(geometry.displaySize.height, 595.28);
    _expectParity(image, geometry);
  });

  test(
    'committed sf-001 fixture raster matches RasterSize.fromDisplaySize',
    () async {
      final Map<String, Object?> catalog = (jsonDecode(
        File('${_repositoryRoot.path}/$_fixtureDirectory/catalog.json')
            .readAsStringSync(),
      ) as Map<String, Object?>);
      final List<Object?> fixtures = catalog['fixtures'] as List<Object?>;
      final Map<String, Object?> descriptor = fixtures
          .cast<Map<String, Object?>>()
          .firstWhere((Map<String, Object?> entry) => entry['id'] == 'sf-001');
      final List<Map<String, Object?>> pages =
          (descriptor['pages'] as List<Object?>).cast<Map<String, Object?>>();
      final Uint8List pdfBytes = File(
        '${_repositoryRoot.path}/$_fixtureDirectory/sf-001.pdf',
      ).readAsBytesSync();

      final SimulatedFixture fixture = _fixture(
        id: 'sf-001',
        widthPt: pages.first['widthPt']! as double,
        heightPt: pages.first['heightPt']! as double,
        bytes: pdfBytes,
        sha256Pin: descriptor['sha256']! as String,
        sizeBytesPin: descriptor['sizeBytes']! as int,
        pageCount: pages.length,
      );
      expect(fixture.pages.first.widthPt, 595.28);
      expect(fixture.pages.first.heightPt, 841.89);

      final (RasterImage image, PageGeometry geometry) = await _render(fixture);
      expect(image.width, 1654);
      expect(image.height, 2339);
      _expectParity(image, geometry);
    },
  );
}
