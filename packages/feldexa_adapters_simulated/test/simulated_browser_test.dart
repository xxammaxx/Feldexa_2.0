// T028 SIMULATED browser runtime journey.
//
// This test runs in a real Chrome browser, fetches the committed fixture
// catalogue from the same `/fixtures/...` layout the Web dev server uses, and
// exercises all six simulated adapters end to end. It is skipped unless
// `--dart-define=SIMULATED_RUNTIME=true` and a fixture server are supplied,
// because a skipped run is not evidence.
//
// Evidence class: SIMULATED browser runtime. It proves the deterministic
// browser substitute and its labels; it proves nothing about Android runtime
// behavior and is never aggregated with EMULATOR or DEVICE results
// (FR-087/FR-088).

// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

@TestOn('browser')
library;

import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:feldexa_testkit/feldexa_testkit.dart' show sha256Hex;
import 'package:flutter_test/flutter_test.dart';

const bool _runtimeEnabled = bool.fromEnvironment('SIMULATED_RUNTIME');
const String _baseUrl = String.fromEnvironment(
  'FIXTURE_BASE_URL',
  defaultValue: 'http://127.0.0.1:8765',
);
const String _skipReason =
    'requires the fixture server and --dart-define=SIMULATED_RUNTIME=true';

Map<String, Object?> _map(Object? value) {
  return (value as Map<Object?, Object?>).cast<String, Object?>();
}

List<Object?> _list(Object? value) => value as List<Object?>;

Future<Uint8List> _fetch(String path) async {
  final html.HttpRequest request = await html.HttpRequest.request(
    '$_baseUrl/fixtures/$path',
    method: 'GET',
    responseType: 'arraybuffer',
  );
  if (request.status != 200) {
    throw StateError('GET $path failed with HTTP ${request.status}');
  }
  final Object? response = request.response;
  if (response is ByteBuffer) {
    return response.asUint8List();
  }
  if (response is Uint8List) {
    return response;
  }
  throw StateError('GET $path returned unexpected ${response.runtimeType}');
}

Future<Map<String, Object?>> _fetchJson(String path) async {
  return _map(jsonDecode(utf8.decode(await _fetch(path))));
}

Future<SimulatedFixtureCatalog> _loadCatalog() async {
  final Map<String, Object?> catalog = await _fetchJson('catalog.json');
  final Map<String, Uint8List> pdfBytes = <String, Uint8List>{};
  final Map<String, Map<String, Object?>> expectedOcr =
      <String, Map<String, Object?>>{};
  for (final Object? value in _list(catalog['fixtures'])) {
    final Map<String, Object?> fixture = _map(value);
    final String id = fixture['id'] as String;
    pdfBytes[id] = await _fetch('$id.pdf');
    final Object? ocr = fixture['expectedOcr'];
    if (ocr != null) {
      expectedOcr[id] = await _fetchJson('$id.expected-ocr.json');
    }
  }
  return SimulatedFixtureCatalog.parse(
    catalogJson: jsonEncode(catalog),
    pdfBytesById: pdfBytes,
    expectedOcrById: expectedOcr,
  );
}

ExportTextOp _textOp(PageGeometry geometry, String fieldId) {
  final Rect rect = Rect.fromLTWH(50, 50, 200, 15);
  const double fontSize = 9;
  return ExportTextOp(
    fieldId: fieldId,
    provenance: Provenance.user,
    rect: rect,
    pdfRect: geometry.displayRectToPdf(rect),
    fontSizePt: fontSize,
    lineHeightPt: 10.8,
    baselineFromTopPt: 1.5 + 0.8 * fontSize,
    lines: const <String>['Browser SIMULATED'],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'runs the six SIMULATED adapters in Chrome with SIMULATED evidence',
    () async {
      final SimulatedFixtureCatalog catalog = await _loadCatalog();
      expect(catalog.fixtures.length, 7);

      final SimulatedBackend backend = SimulatedBackend();
      final SimulatedDocumentImportAdapter importAdapter =
          SimulatedDocumentImportAdapter(backend: backend, catalog: catalog);
      final SimulatedPageRasterAdapter rasterAdapter =
          SimulatedPageRasterAdapter(backend: backend);
      final SimulatedOcrAdapter ocrAdapter = SimulatedOcrAdapter(
        backend: backend,
        catalog: catalog,
      );
      final SimulatedSecureStoreAdapter storeAdapter =
          SimulatedSecureStoreAdapter(backend: backend);
      final SimulatedPdfExportAdapter exportAdapter = SimulatedPdfExportAdapter(
        backend: backend,
      );
      final SimulatedDeliveryAdapter deliveryAdapter = SimulatedDeliveryAdapter(
        backend: backend,
      );

      importAdapter.picker.enqueueFixture('sf-004');
      final ImportedSource imported = await importAdapter.pickAndImport(
        ImportRequest(),
      );
      expect(imported.evidence.evidenceClass, EvidenceClass.simulated);
      expect(imported.evidence.simulated, isTrue);
      expect(imported.pageCount, 1);

      final RasterImage raster = await rasterAdapter.renderPage(
        RasterRequest(
          sourceId: imported.sourceId,
          pageIndex: 0,
          scale: 1,
          format: RasterFormat.gray8,
        ),
      );
      expect(raster.evidence.evidenceClass, EvidenceClass.simulated);
      final List<OcrBlock> blocks = await ocrAdapter.recognize(
        OcrRequest(image: raster, pageIndex: 0, languageHint: 'de'),
      );
      expect(blocks, isNotEmpty);
      expect(
        ocrAdapter.descriptor.evidence.evidenceClass,
        EvidenceClass.simulated,
      );

      final SourceFileRef source = SourceFileRef(
        id: imported.sourceId,
        sha256: imported.sha256,
        sizeBytes: imported.sizeBytes,
        pageCount: imported.pageCount,
        importedAt: backend.context.nowUtc(),
      );
      final RevisionContent content = RevisionContent(
        pages: <Page>[
          for (int index = 0; index < imported.pageCount; index++)
            Page(index: index, geometry: imported.pages[index]),
        ],
        fieldOrder: const <String>[],
      );
      final String documentId = imported.documentId;
      final StoredMeta created = await storeAdapter.createDocument(
        CreateDocumentRequest(
          documentId: documentId,
          initialRevision: Revision(
            id: backend.context.newId(),
            documentId: documentId,
            kind: RevisionKind.explicit,
            createdAt: backend.context.nowUtc(),
            plaintextSha256: sha256Hex(canonicalJsonBytes(content.toJson())),
            content: content,
          ),
          title: 'Browser-Dokument',
          source: source,
        ),
      );
      final StoredMeta saved = await storeAdapter.saveRevision(
        SaveRevisionRequest(
          documentId: created.id,
          expectedHead: created.latestRevisionId,
          content: content,
          kind: RevisionKind.explicit,
        ),
      );
      final LoadedDocument loaded = await storeAdapter.loadDocument(saved.id);
      expect(loaded.evidence.evidenceClass, EvidenceClass.simulated);
      expect(loaded.content.pageCount, 1);

      final ExportPlan plan = ExportPlan(
        documentId: saved.id,
        revisionId: saved.latestRevisionId!,
        sourceSha256: imported.sha256,
        pageCount: 1,
        evidenceClass: 'simulated',
        font: ExportFont(
          family: 'NotoSans',
          regularAsset: 'assets/fonts/NotoSans-Regular.ttf',
          boldAsset: 'assets/fonts/NotoSans-Bold.ttf',
          metricsVersion: 'noto-sans-2.013-v1',
        ),
        pages: <ExportPage>[
          ExportPage(
            index: 0,
            geometry: imported.pages.first,
            ops: <ExportOp>[_textOp(imported.pages.first, 'field-1')],
          ),
        ],
        info: ExportPlanInfo(emptyFieldCount: 0, unresolvedSuggestionCount: 0),
      );
      final ExportResult exported = await exportAdapter.export(
        ExportRequest(
          documentId: saved.id,
          revisionId: saved.latestRevisionId!,
          plan: plan,
        ),
      );
      expect(exported.artifact.state, ExportArtifactState.succeeded);
      expect(exported.evidence.evidenceClass, EvidenceClass.simulated);
      final Uint8List bytes = await exportAdapter.readArtifact(
        exported.artifact.id,
      );
      expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(latin1.decode(bytes).contains('SIMULATED'), isTrue);

      final DeliveryOutcome outcome = await deliveryAdapter.deliver(
        action: DeliveryAction.save,
        artifactId: exported.artifact.id,
      );
      expect(outcome.completed, isTrue);
      expect(outcome.evidence.evidenceClass, EvidenceClass.simulated);
      expect(outcome.userVisibleLocationHint, contains('SIMULATED'));

      for (final CapabilityDescriptor descriptor in <CapabilityDescriptor>[
        importAdapter.descriptor,
        rasterAdapter.descriptor,
        ocrAdapter.descriptor,
        storeAdapter.descriptor,
        exportAdapter.descriptor,
        deliveryAdapter.descriptor,
      ]) {
        expect(descriptor.evidence.evidenceClass, EvidenceClass.simulated);
        expect(descriptor.evidence.simulated, isTrue);
      }
    },
    skip: _runtimeEnabled ? false : _skipReason,
  );
}
