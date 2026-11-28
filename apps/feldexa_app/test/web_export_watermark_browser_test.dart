// T111 SIMULATED export watermark and non-production labelling (FR-087).
//
// `contracts/export-plan.md` §7 defines the Web applier: the same canonical
// `ExportPlan` is rendered into a preview PDF, every page carrying a visible
// `SIMULATED` watermark and the German `SIMULATED` footer, and the result is
// reported with `evidenceClass: simulated`. It must never claim flattening
// verification, PDFBox compatibility, or print fidelity, and it must not be
// used for SC-005/SC-006 or any Android acceptance claim.
//
// This is the Chrome-lane copy (`TestOn('browser')`) of
// `test/web_export_browser_entry_test.dart`. The VM suite reads the committed
// fixtures from disk through `dart:io`; this second entry keeps the same
// watermark and determinism assertions but loads the committed fixture mirror
// over loopback (`dart:html.HttpRequest`), so a real Chrome executes the
// assertions instead of a browser row that stays `NOT_RUN`. Evidence class is
// `SIMULATED`; it makes no DEVICE or EMULATOR claim, and the fixture server
// must be running (`dart run tools/corpus/synthetic/serve_web_fixtures.dart
// --root apps/feldexa_app/web --port 8765`).

@TestOn('browser')
library;

// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';

const String _fixtureId = 'sf-001';
const String _fixtureBaseUrl = String.fromEnvironment(
  'FIXTURE_BASE_URL',
  defaultValue: 'http://127.0.0.1:8765',
);
const String _fixturePrerequisite =
    'the committed fixture mirror must be served on 127.0.0.1:8765 with '
    'dart run tools/corpus/synthetic/serve_web_fixtures.dart '
    '--root apps/feldexa_app/web --port 8765';

String _sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();

Future<Uint8List> _fetch(String path) async {
  final html.HttpRequest request = await html.HttpRequest.request(
    '$_fixtureBaseUrl/fixtures/$path',
    method: 'GET',
    responseType: 'arraybuffer',
  );
  if (request.status != 200) {
    throw StateError(
      'GET $path failed with HTTP ${request.status}; $_fixturePrerequisite',
    );
  }
  final Object? response = request.response;
  if (response is ByteBuffer) {
    return response.asUint8List();
  }
  if (response is Uint8List) {
    return response;
  }
  throw StateError(
    'GET $path returned unexpected ${response.runtimeType}; '
    '$_fixturePrerequisite',
  );
}

Future<Map<String, Object?>> _fetchJson(String path) async {
  return (jsonDecode(utf8.decode(await _fetch(path))) as Map<Object?, Object?>)
      .cast<String, Object?>();
}

/// Loads the committed SIMULATED catalogue from the loopback fixture mirror.
Future<SimulatedFixtureCatalog> _loadCatalog() async {
  final Map<String, Object?> catalog = await _fetchJson('catalog.json');
  final Map<String, Uint8List> pdfBytes = <String, Uint8List>{};
  final Map<String, Map<String, Object?>> expectedOcr =
      <String, Map<String, Object?>>{};
  for (final Object? value in catalog['fixtures'] as List<Object?>) {
    final Map<String, Object?> fixture = value! as Map<String, Object?>;
    final String id = fixture['id']! as String;
    pdfBytes[id] = await _fetch('$id.pdf');
    final Object? ocr = fixture['expectedOcr'];
    if (ocr is Map<String, Object?>) {
      expectedOcr[id] = await _fetchJson(ocr['path']! as String);
    }
  }
  return SimulatedFixtureCatalog.parse(
    catalogJson: jsonEncode(catalog),
    pdfBytesById: pdfBytes,
    expectedOcrById: expectedOcr,
  );
}

/// One imported fixture plus the saved document/revision the export targets.
final class _World {
  _World({
    required this.backend,
    required this.importAdapter,
    required this.storeAdapter,
    required this.exportAdapter,
  });

  final SimulatedBackend backend;
  final SimulatedDocumentImportAdapter importAdapter;
  final SimulatedSecureStoreAdapter storeAdapter;
  final SimulatedPdfExportAdapter exportAdapter;

  static Future<_World> create() async {
    final SimulatedFixtureCatalog catalog = await _loadCatalog();
    final SimulatedBackend backend = SimulatedBackend();
    return _World(
      backend: backend,
      importAdapter: SimulatedDocumentImportAdapter(
        backend: backend,
        catalog: catalog,
      ),
      storeAdapter: SimulatedSecureStoreAdapter(backend: backend),
      exportAdapter: SimulatedPdfExportAdapter(backend: backend),
    );
  }

  Future<(ImportedSource, String documentId, String revisionId)> importAndSave(
    String fixtureId,
  ) async {
    importAdapter.picker.enqueueFixture(fixtureId);
    final ImportedSource imported = await importAdapter.pickAndImport(
      ImportRequest(),
    );
    final core.SourceFileRef source = core.SourceFileRef(
      id: imported.sourceId,
      sha256: imported.sha256,
      sizeBytes: imported.sizeBytes,
      pageCount: imported.pageCount,
      originalName: imported.displayName,
      importedAt: backend.context.nowUtc(),
    );
    final core.RevisionContent content = core.RevisionContent(
      pages: <core.Page>[
        for (int index = 0; index < imported.pageCount; index++)
          core.Page(index: index, geometry: imported.pages[index]),
      ],
      fieldOrder: const <String>[],
    );
    final String documentId = backend.context.newId();
    final String revisionId = backend.context.newId();
    await storeAdapter.createDocument(
      CreateDocumentRequest(
        documentId: documentId,
        title: 'Simulierte Meldebescheinigung',
        source: source,
        initialRevision: core.Revision(
          id: revisionId,
          documentId: documentId,
          kind: core.RevisionKind.explicit,
          createdAt: backend.context.nowUtc(),
          plaintextSha256: _sha256Hex(
            core.canonicalJsonBytes(content.toJson()),
          ),
          content: content,
        ),
      ),
    );
    return (imported, documentId, revisionId);
  }

  /// A two-page plan with a text value and one checked checkbox.
  ExportPlan plan({
    required ImportedSource imported,
    required String documentId,
    required String revisionId,
  }) {
    final core.PageGeometry first = imported.pages.first;
    final core.Rect textRect = core.Rect.fromLTWH(50, 50, 200, 15);
    final core.Rect checkboxRect = core.Rect.fromLTWH(420, 210, 10, 10);
    final double fontSize =
        ((0.6 * textRect.height).clamp(7.0, 12.0) * 10).round() / 10;
    return ExportPlan(
      documentId: documentId,
      revisionId: revisionId,
      sourceSha256: imported.sha256,
      pageCount: imported.pageCount,
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
          geometry: first,
          ops: <ExportOp>[
            ExportTextOp(
              fieldId: 'field-text',
              provenance: core.Provenance.user,
              rect: textRect,
              pdfRect: first.displayRectToPdf(textRect),
              fontSizePt: fontSize,
              lineHeightPt: (1.2 * fontSize * 100).round() / 100,
              baselineFromTopPt: 1.5 + 0.8 * fontSize,
              lines: const <String>['Müller-Lüdenscheidt'],
            ),
            ExportCheckboxOp(
              fieldId: 'field-checkbox',
              provenance: core.Provenance.user,
              rect: checkboxRect,
              pdfRect: first.displayRectToPdf(checkboxRect),
              checked: true,
              insetPt: 1.5,
              strokeWidthPt: 0.8,
            ),
          ],
        ),
        for (int index = 1; index < imported.pages.length; index++)
          ExportPage(
            index: index,
            geometry: imported.pages[index],
            ops: const <ExportOp>[],
          ),
      ],
      info: ExportPlanInfo(emptyFieldCount: 0, unresolvedSuggestionCount: 0),
    );
  }

  Future<Uint8List> export(ExportPlan plan) async {
    final ExportValidationResult validation = await exportAdapter.validate(
      plan,
    );
    expect(validation.isValid, isTrue);
    expect(validation.warnings, isEmpty);
    expect(validation.evidence.evidenceClass, EvidenceClass.simulated);
    final ExportResult result = await exportAdapter.export(
      ExportRequest(
        documentId: plan.documentId,
        revisionId: plan.revisionId,
        plan: plan,
        // No bundled font: the preview uses the Latin-1 Helvetica substitute
        // and its visible non-production label carries the ASCII hyphen. Font
        // fidelity is explicitly not claimed by §7.
        options: ExportOptions(embedFonts: false),
      ),
    );
    expect(result.artifact.state, ExportArtifactState.succeeded);
    expect(result.evidence.evidenceClass, EvidenceClass.simulated);
    return exportAdapter.readArtifact(result.artifact.id);
  }
}

int _count(String haystack, String needle) {
  int count = 0;
  int index = haystack.indexOf(needle);
  while (index >= 0) {
    count++;
    index = haystack.indexOf(needle, index + needle.length);
  }
  return count;
}

void main() {
  late _World world;
  late ImportedSource imported;
  late String documentId;
  late String revisionId;

  setUpAll(() async {
    world = await _World.create();
    (imported, documentId, revisionId) = await world.importAndSave(_fixtureId);
  });

  test('descriptor is a SIMULATED export adapter', () {
    final CapabilityDescriptor descriptor = world.exportAdapter.descriptor;
    expect(descriptor.kind, CapabilityKind.pdfExport);
    expect(descriptor.isSimulated, isTrue);
    expect(descriptor.evidence.evidenceClass, EvidenceClass.simulated);
    expect(descriptor.adapterId, simulatedExportAdapterId);
    expect(descriptor.supportedFeatures, contains('simulated-watermark'));
    // §7: the preview must not claim PDFBox compatibility or print fidelity.
    expect(descriptor.supportedFeatures, isNot(contains('pdfbox')));
    expect(descriptor.supportedFeatures, isNot(contains('print-fidelity')));
  });

  test(
    'every preview page carries the SIMULATED watermark and footer',
    () async {
      final ExportPlan plan = world.plan(
        imported: imported,
        documentId: documentId,
        revisionId: revisionId,
      );
      expect(plan.evidenceClass, 'simulated');
      expect(plan.pageCount, 2);

      final Uint8List bytes = await world.export(plan);
      final String pdf = latin1.decode(bytes);
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');

      // The `pdf` package emits text word by word, so the footer is counted by
      // its fixed words, not as one contiguous string. The `42 Tf` operator is
      // the central watermark's font size; the content streams are uncompressed
      // by the SIMULATED applier, so these counts are deterministic.
      expect(
        _count(pdf, 'SIMULATED'),
        greaterThanOrEqualTo(plan.pageCount * 2),
      );
      expect(
        _count(pdf, 'kein'),
        plan.pageCount,
        reason: 'the German non-production footer belongs on every page',
      );
      expect(_count(pdf, 'Produktions-PDF'), plan.pageCount);
      expect(_count(pdf, '42 Tf'), plan.pageCount, reason: 'one watermark');
      expect(_count(pdf, 'Quellseite'), plan.pageCount);
      expect(
        _count(pdf, '/Type/Page'),
        greaterThanOrEqualTo(plan.pageCount),
        reason: 'the preview has at least the planned page objects',
      );
      expect(
        _count(pdf, '595.28 841.89'),
        greaterThanOrEqualTo(plan.pageCount),
      );
      // SIMULATED self-check only; §7 forbids claiming Android flattening.
      expect(pdf.contains('/AcroForm'), isFalse);
      expect(pdf.contains('/Widget'), isFalse);
    },
  );

  test('the preview bytes are deterministic across exports', () async {
    final ExportPlan plan = world.plan(
      imported: imported,
      documentId: documentId,
      revisionId: revisionId,
    );
    final Uint8List first = await world.export(plan);
    final Uint8List second = await world.export(plan);
    expect(_sha256Hex(first), _sha256Hex(second));
    expect(first, orderedEquals(second));
  });
}
