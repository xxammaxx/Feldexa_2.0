// T062 SIMULATED browser recognition pipeline.
//
// EVIDENCE CLASS: SIMULATED (browser). This file runs the production
// recognition use case `AnalyzeDocument` in a real Chrome browser against the
// committed deterministic fixture mirror and the T028 SIMULATED page-raster
// and OCR adapters. It is browser SIMULATED evidence only: not Android
// runtime evidence, not an Android acceptance result, not EMULATOR or DEVICE
// evidence, and not proof of the Android PDFium/ML Kit path
// (FR-086/FR-087/FR-088). A complete envelope with zero suggestions is the
// measured behaviour of the placeholder SIMULATED raster only; it is not a
// completeness claim, not a recognition-quality claim, and not Android
// evidence.
//
// WHY THIS FILE LIVES UNDER `test/` (measured, not preferred)
// ----------------------------------------------------------
// T062 is specified as `integration_test/web_recognition_test.dart`, and this
// suite was first committed there with a `test/` symlink entry. Neither form
// can stand: `.specify/init-options.json` sets `"allow_symlinks": false`, so
// no symlink entry and no second tracked path for the same content, and
// `flutter test --platform chrome` cannot compile anything outside `test/`.
// Both constraints were measured on this worktree:
//
//   1. Direct execution of the `integration_test/` path fails at compile time:
//
//        $ cd apps/feldexa_app
//        $ flutter test --no-pub --platform chrome \
//            integration_test/web_recognition_test.dart
//        org-dartlang-app:///main.dart:3:8: Error: Error when reading
//        'org-dartlang-app:///integration_test/web_recognition_test.dart':
//        File not found
//        import 'org-dartlang-app:///../integration_test/web_recognition_test.dart'
//               as test_0 show main;
//               ^
//        org-dartlang-app:///main.dart:11:24: Error: Undefined name 'main'.
//            entryPoint: test_0.main,
//                               ^^^^
//        Failed to compile
//
//      The web test runner compiles a generated entrypoint whose
//      `org-dartlang-app` multi-root is `[<project>/test, <test-output-dir>]`
//      (`flutter_tools/lib/src/test/web_test_compiler.dart`), so every import
//      that leaves `test/` — `../integration_test/...` included — is
//      unresolvable and the run never reaches an assertion.
//
//   2. A thin `test/` wrapper that only does
//      `import '../integration_test/web_recognition_test.dart' as t062;` plus
//      `void main() => t062.main();` fails with the same `File not found`: the
//      multi-root does not collapse `..` out of `test/`.
//
// The only Chrome-compilable arrangement with a single source of truth is this
// one real file (mode 100644) inside `test/`, carrying the suite itself: one
// real file, no symlink, no wrapper, and no duplicated copy that could drift.
// The test body below is unchanged from the suite's previous location; only the
// path moved. The T062 task row is owned by the coordinator and is deliberately
// not edited by this correction.
//
// Working commands (the fixture server is a prerequisite, and a skipped run
// is not evidence):
//
//   dart run tools/corpus/synthetic/serve_web_fixtures.dart \
//     --root apps/feldexa_app/web --port 8765
//   cd apps/feldexa_app
//   flutter test --no-pub --platform chrome test/web_recognition_browser_entry_test.dart
//
// The fixture server is a loopback-only, no-cache static mirror of the
// committed `apps/feldexa_app/web/fixtures/` files. No product backend and no
// external network are used. Without the server these tests fail instead of
// silently skipping; a skipped run is not evidence.
//
// OBSERVED SHIPPED BEHAVIOR (recorded, never invented)
// ---------------------------------------------------
// The T028 `SimulatedPageRasterAdapter` substitutes a content-free
// deterministic page placeholder for a real PDFium render: a white page, a
// 1-pixel gray frame, and a 16x16 marker derived from the request. Its own
// header states that it "intentionally does not claim visual fidelity to the
// source PDF". `GeometryDetector` therefore finds no geometry candidate on it
// (an all-white/all-black page returns an empty candidate list), so
// `AnalyzeDocument` emits a complete, valid per-page envelope with ZERO
// suggestions, even though the fixture-backed OCR adapter returns the
// non-empty committed expected-OCR blocks.
//
// Observed in Chrome (deterministic, identical on every page and on repeat):
//   * every analysed page: status = complete, evidenceClass = simulated,
//     failure = none, suggestion count = 0, types = none, page indexes = none,
//     confidences = none;
//   * OCR ran: language hint "de", gray8, page indexes 0..n-1, block counts
//     sf-001 = 25/28, sf-002 = 16/16/17/16/16, sf-003 = 10/10/10/10/10,
//     sf-004 = 24;
//   * the one-page source sf-004 requested for two pages: page 0 completes
//     (0 suggestions) and page 1 fails with PAGE-001 / rasterization while
//     page 0 stays complete and unchanged.
// The non-zero-suggestion assertion the T062 brief asks for is therefore NOT
// satisfied by the shipped adapters; it stays a reported gap and is not faked
// here. This test pins exactly what the shipped pipeline returns.
//
// `dart:html` is used intentionally: this file only compiles for the browser,
// and the app does not take a dependency on a web interop package.

// ignore_for_file: avoid_print, avoid_web_libraries_in_flutter, deprecated_member_use, implementation_imports

@TestOn('browser')
library;

import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_application/src/recognition/analyze_document.dart'
    as analysis;
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:feldexa_recognition/src/page_analysis.dart';
import 'package:feldexa_recognition/src/raster.dart' show RasterSize;
import 'package:feldexa_recognition/src/suggestion_schema.dart'
    show PageDisplaySize;
import 'package:flutter_test/flutter_test.dart';

/// Loopback base URL of the committed fixture mirror.
const String _fixtureBaseUrl = String.fromEnvironment(
  'FIXTURE_BASE_URL',
  defaultValue: 'http://127.0.0.1:8765',
);

/// Prerequisite printed by every fixture-fetch failure.
const String _fixturePrerequisite =
    'the committed fixture mirror must be served on 127.0.0.1:8765 with '
    'dart run tools/corpus/synthetic/serve_web_fixtures.dart '
    '--root apps/feldexa_app/web --port 8765';

/// UUID run ids shared by the envelopes of one pinned request.
const String _primaryRunId = '22222222-2222-4222-8222-222222222222';
const String _isolationRunId = '44444444-4444-4444-8444-444444444444';
const String _degradedRunId = '55555555-5555-4555-8555-555555555555';

/// The production OCR language hint (`contracts/ports.md` §2.3).
const String _expectedLanguageHint = 'de';

/// Content-free SIMULATED marker prefix written to the browser log.
const String _logPrefix = '[T062-SIMULATED]';

/// Writes one content-free marker (counts, indexes, tokens only).
///
/// Suggestion labels and OCR text are document content and are never logged.
void _marker(String message) {
  print('$_logPrefix $message');
}

Map<String, Object?> _map(Object? value) {
  return (value as Map<Object?, Object?>).cast<String, Object?>();
}

List<Object?> _list(Object? value) => value as List<Object?>;

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
  return _map(jsonDecode(utf8.decode(await _fetch(path))));
}

/// Loads and verifies the committed fixture catalogue in the browser.
///
/// `SimulatedFixtureCatalog.parse` re-checks every SHA-256 and byte-size pin,
/// the page geometry, the typed rejection expectations, and the expected-OCR
/// shapes. A drifting fixture therefore fails before any analysis runs.
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

/// Stages [fixtureId] exactly like the browser import journey does.
///
/// The SIMULATED import adapter copies the committed bytes, re-hashes them,
/// reads them back, and verifies the SHA-256 before the source becomes
/// visible. Every result carries the SIMULATED evidence class.
Future<ImportedSource> _stage(
  SimulatedFixtureCatalog catalog,
  SimulatedBackend backend,
  String fixtureId,
) async {
  final SimulatedDocumentImportAdapter adapter = SimulatedDocumentImportAdapter(
    backend: backend,
    catalog: catalog,
  );
  adapter.picker.enqueueFixture(fixtureId);
  return adapter.pickAndImport(ImportRequest());
}

/// Builds one page descriptor from the staged display geometry.
analysis.DocumentAnalysisPage _page(
  ImportedSource source,
  int pageIndex, {
  int geometryPageIndex = -1,
}) {
  return analysis.DocumentAnalysisPage.fromGeometry(
    pageIndex: pageIndex,
    geometry:
        source.pages[geometryPageIndex < 0 ? pageIndex : geometryPageIndex],
  );
}

/// Builds one SIMULATED analysis request over the staged source.
analysis.DocumentAnalysisRequest _request({
  required String sourceId,
  required String analysisRunId,
  required List<analysis.DocumentAnalysisPage> pages,
  required PageRasterPort rasterPort,
  required OcrPort ocrPort,
}) {
  return analysis.DocumentAnalysisRequest(
    sourceId: sourceId,
    analysisRunId: analysisRunId,
    pages: pages,
    evidenceClass: EvidenceClass.simulated.name,
    rasterPort: rasterPort,
    ocrPort: ocrPort,
  );
}

/// Content-free deterministic fingerprint of one terminal envelope.
///
/// Timings are intentionally excluded: they are wall-clock measurements, not
/// recognition output. Everything else that the browser run must reproduce is
/// included: page identity, status, evidence class, geometry, failure key, and
/// every suggestion id, page index, type, and confidence.
String _fingerprint(FieldSuggestionSet page) {
  final StringBuffer buffer = StringBuffer()
    ..write('p${page.pageIndex}|${page.status}|${page.evidenceClass}|')
    ..write('rot=${page.rotation}|')
    ..write('size=${page.pageSizePt.width}x${page.pageSizePt.height}|')
    ..write('uncertain=${page.pageUncertain}|')
    ..write('failure=${page.failure?.messageKey ?? 'none'}|')
    ..write('suggestions=${page.suggestions.length}');
  for (final Map<String, Object?> suggestion in page.suggestions) {
    buffer
      ..write('|id=${suggestion['id']}')
      ..write(',page=${suggestion['pageIndex']}')
      ..write(',type=${suggestion['proposedType']}')
      ..write(',conf=${suggestion['confidence']}');
  }
  return buffer.toString();
}

/// Asserts the shared per-page envelope invariants of one terminal envelope.
///
/// This re-checks the `recognition-output.md` §1/§2/§4 shape independently of
/// the envelope factory: status/failure exclusivity, geometry, rotation, the
/// SIMULATED evidence class, and (for the shipped zero-suggestion output) an
/// empty, therefore vacuously in-page, suggestion list.
void _expectValidEnvelope(
  FieldSuggestionSet page, {
  required int pageIndex,
  required PageDisplaySize expectedSize,
  required int expectedRotation,
}) {
  expect(page.pageIndex, pageIndex, reason: 'page $pageIndex index');
  expect(page.status, anyOf('complete', 'failed'), reason: 'page $pageIndex');
  expect(page.evidenceClass, EvidenceClass.simulated.name);
  expect(EvidenceClass.parse(page.evidenceClass), EvidenceClass.simulated);
  expect(page.pageSizePt.width, closeTo(expectedSize.width, 1e-9));
  expect(page.pageSizePt.height, closeTo(expectedSize.height, 1e-9));
  expect(page.rotation, expectedRotation);
  expect(page.rotation, anyOf(0, 90, 180, 270));

  if (page.status == FieldSuggestionSet.statusComplete) {
    expect(page.failure, isNull, reason: 'page $pageIndex complete');
  } else {
    expect(page.failure, isNotNull, reason: 'page $pageIndex failed');
    expect(page.suggestions, isEmpty);
  }

  for (final Map<String, Object?> suggestion in page.suggestions) {
    expect(suggestion['pageIndex'], pageIndex);
    expect(suggestion['id'], matches(RegExp(r'^s_p\d+_\d{4}$')));
    expect(suggestion['confidence'], isA<num>());
    final double confidence = (suggestion['confidence']! as num).toDouble();
    expect(confidence, inInclusiveRange(0.0, 1.0));
    final Map<String, Object?> rect =
        (suggestion['rect']! as Map<Object?, Object?>).cast<String, Object?>();
    final double x = (rect['x']! as num).toDouble();
    final double y = (rect['y']! as num).toDouble();
    final double width = (rect['width']! as num).toDouble();
    final double height = (rect['height']! as num).toDouble();
    expect(x, greaterThanOrEqualTo(0.0));
    expect(y, greaterThanOrEqualTo(0.0));
    expect(x + width, lessThanOrEqualTo(page.pageSizePt.width + 1e-6));
    expect(y + height, lessThanOrEqualTo(page.pageSizePt.height + 1e-6));
  }
}

/// Delegating OCR port that records what the pipeline actually asked for.
///
/// It is test-local composition, not a product adapter: it forwards to the
/// committed `SimulatedOcrAdapter` and never changes a block. It records only
/// counts and request metadata; OCR text is never copied, compared, or logged.
final class _RecordingOcrPort implements OcrPort {
  _RecordingOcrPort(this.inner, {this.failingPageIndexes = const <int>{}});

  final OcrPort inner;
  final Set<int> failingPageIndexes;

  final List<int> pageIndexes = <int>[];
  final List<String> languageHints = <String>[];
  final List<int> widthsPx = <int>[];
  final List<int> heightsPx = <int>[];
  final List<String> formats = <String>[];
  final List<String> evidenceClasses = <String>[];
  final List<int> blockCounts = <int>[];

  @override
  CapabilityDescriptor get descriptor => inner.descriptor;

  @override
  Future<List<OcrBlock>> recognize(OcrRequest request) async {
    pageIndexes.add(request.pageIndex);
    languageHints.add(request.languageHint);
    widthsPx.add(request.image.width);
    heightsPx.add(request.image.height);
    formats.add(request.image.format.name);
    evidenceClasses.add(request.image.evidence.evidenceClass.label);
    if (failingPageIndexes.contains(request.pageIndex)) {
      // The pipeline must treat this as recoverable (REC-001) and continue
      // geometry-only instead of failing the page.
      throw OcrUnavailableException();
    }
    final List<OcrBlock> blocks = await inner.recognize(request);
    blockCounts.add(blocks.length);
    return blocks;
  }

  @override
  Future<void> dispose() => inner.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('serves the committed SIMULATED fixture catalogue in Chrome', () async {
    final SimulatedFixtureCatalog catalog = await _loadCatalog();

    expect(catalog.catalogVersion, 'fixtures-1.1.0');
    expect(catalog.fixtures, hasLength(7));
    expect(catalog.ids, <String>[
      'sf-001',
      'sf-002',
      'sf-003',
      'sf-004',
      'sf-protected',
      'sf-truncated',
      'sf-not-a-pdf',
    ]);
    expect(
      catalog.fixtures.where((SimulatedFixture value) => value.isImportable),
      hasLength(4),
    );

    final SimulatedFixture geometryFixture = catalog.fixture('sf-003');
    expect(geometryFixture.pageCount, 5);
    expect(geometryFixture.role, SimulatedFixtureRole.geometry);
    expect(geometryFixture.expectedOcr, hasLength(5));
    expect(
      geometryFixture.pages
          .map((SimulatedFixturePage page) => page.rotation)
          .toList(),
      <int>[0, 0, 90, 180, 270],
    );

    _marker(
      'catalogue version=${catalog.catalogVersion} fixtures=${catalog.fixtures.length} '
      'importable=${catalog.fixtures.where((SimulatedFixture f) => f.isImportable).length} '
      'sf-003 pages=${geometryFixture.pageCount} '
      'sf-003 rotations=${geometryFixture.pages.map((SimulatedFixturePage p) => p.rotation).toList()}',
    );
  });

  test('analyses every sf-003 page with SIMULATED evidence and stable envelopes', () async {
    final SimulatedFixtureCatalog catalog = await _loadCatalog();
    final SimulatedFixture fixture = catalog.fixture('sf-003');
    final SimulatedBackend backend = SimulatedBackend();
    final ImportedSource source = await _stage(catalog, backend, 'sf-003');

    // The staged source is the committed fixture: same SHA-256, same size,
    // same page order and display geometry.
    expect(source.sha256, fixture.sha256);
    expect(source.sizeBytes, fixture.sizeBytes);
    expect(source.pageCount, fixture.pageCount);
    expect(source.evidence.evidenceClass, EvidenceClass.simulated);
    expect(source.evidence.evidenceClass.isAndroid, isFalse);
    final SimulatedStagedSource? staged = backend.stagedSource(source.sourceId);
    expect(staged, isNotNull);
    expect(sha256.convert(staged!.bytes).toString(), fixture.sha256);

    final SimulatedPageRasterAdapter rasterAdapter = SimulatedPageRasterAdapter(
      backend: backend,
    );
    final SimulatedOcrAdapter ocrAdapter = SimulatedOcrAdapter(
      backend: backend,
      catalog: catalog,
    );
    final _RecordingOcrPort recordingOcr = _RecordingOcrPort(ocrAdapter);

    final List<analysis.DocumentAnalysisPage> pages =
        <analysis.DocumentAnalysisPage>[
          for (int index = 0; index < fixture.pageCount; index++)
            _page(source, index),
        ];
    Future<analysis.DocumentAnalysisResult> run(String runId) {
      return analysis.AnalyzeDocument.run(
        _request(
          sourceId: source.sourceId,
          analysisRunId: runId,
          pages: pages,
          rasterPort: rasterAdapter,
          ocrPort: recordingOcr,
        ),
      );
    }

    final analysis.DocumentAnalysisResult first = await run(_primaryRunId);
    final analysis.DocumentAnalysisResult second = await run(_primaryRunId);

    expect(first.analysisRunId, _primaryRunId);
    expect(first.isComplete, isTrue);
    expect(first.cancelledPageIndexes, isEmpty);
    expect(first.pages, hasLength(fixture.pageCount));

    // Determinism: same input, same output (timings excluded).
    expect(
      second.pages.map(_fingerprint).toList(),
      first.pages.map(_fingerprint).toList(),
    );

    for (int index = 0; index < first.pages.length; index++) {
      final FieldSuggestionSet page = first.pages[index];
      final SimulatedFixturePage expected = fixture.pages[index];
      _expectValidEnvelope(
        page,
        pageIndex: index,
        expectedSize: PageDisplaySize(expected.widthPt, expected.heightPt),
        expectedRotation: expected.rotation,
      );
      // Observed shipped value: zero suggestions on every completed page.
      expect(page.status, FieldSuggestionSet.statusComplete);
      expect(page.failure, isNull);
      expect(page.suggestions, isEmpty);
      // The SIMULATED envelope never claims an Android evidence class.
      expect(EvidenceClass.parse(page.evidenceClass).isAndroid, isFalse);
      _marker(
        'sf-003 page=$index status=${page.status} '
        'suggestions=${page.suggestions.length} '
        'types=${page.suggestions.map((Map<String, Object?> s) => s['proposedType']).toList()} '
        'suggestionPages=${page.suggestions.map((Map<String, Object?> s) => s['pageIndex']).toList()} '
        'confidences=${page.suggestions.map((Map<String, Object?> s) => s['confidence']).toList()} '
        'evidence=${page.evidenceClass} rotation=${page.rotation}',
      );
    }

    // Every descriptor and raster used is SIMULATED (FR-087/FR-088).
    expect(
      rasterAdapter.descriptor.evidence.evidenceClass,
      EvidenceClass.simulated,
    );
    expect(
      ocrAdapter.descriptor.evidence.evidenceClass,
      EvidenceClass.simulated,
    );
    expect(ocrAdapter.descriptor.evidence.evidenceClass.isAndroid, isFalse);
    expect(ocrAdapter.descriptor.isSimulated, isTrue);
    expect(rasterAdapter.descriptor.isSimulated, isTrue);

    // OCR ran for every page at the production 200 DPI analysis size with
    // the production German hint, and returned the committed blocks.
    // `ocrUsed` itself is only materialized on a suggestion's evidence; with
    // the shipped zero suggestions there is no such field to read.
    expect(recordingOcr.pageIndexes, <int>[0, 1, 2, 3, 4, 0, 1, 2, 3, 4]);
    expect(recordingOcr.languageHints.toSet(), <String>{_expectedLanguageHint});
    expect(recordingOcr.formats.toSet(), <String>{'gray8'});
    expect(recordingOcr.evidenceClasses.toSet(), <String>{'SIMULATED'});
    for (int index = 0; index < fixture.pageCount; index++) {
      final SimulatedFixturePage expected = fixture.pages[index];
      final RasterSize expectedSize = RasterSize.fromDisplaySize(
        widthPt: expected.widthPt,
        heightPt: expected.heightPt,
      );
      expect(recordingOcr.widthsPx[index], expectedSize.widthPx);
      expect(recordingOcr.heightsPx[index], expectedSize.heightPx);
      expect(
        recordingOcr.widthsPx[index + fixture.pageCount],
        expectedSize.widthPx,
      );
      expect(
        recordingOcr.heightsPx[index + fixture.pageCount],
        expectedSize.heightPx,
      );
    }
    const List<int> expectedBlocksPerPage = <int>[10, 10, 10, 10, 10];
    expect(
      recordingOcr.blockCounts.sublist(0, fixture.pageCount),
      expectedBlocksPerPage,
    );
    expect(
      recordingOcr.blockCounts.sublist(fixture.pageCount),
      expectedBlocksPerPage,
    );
    _marker(
      'sf-003 ocr pageIndexes=${recordingOcr.pageIndexes} '
      'blocks=${recordingOcr.blockCounts} '
      'rasterSizesPx=${List<String>.generate(fixture.pageCount, (int i) => '${recordingOcr.widthsPx[i]}x${recordingOcr.heightsPx[i]}')} '
      'hint=${recordingOcr.languageHints.toSet()} '
      'format=${recordingOcr.formats.toSet()} '
      'rasterEvidence=${recordingOcr.evidenceClasses.toSet()}',
    );
  });

  test('isolates one PAGE-001 page while the other page completes', () async {
    final SimulatedFixtureCatalog catalog = await _loadCatalog();
    final SimulatedFixture fixture = catalog.fixture('sf-004');
    expect(fixture.pageCount, 1);

    final SimulatedBackend backend = SimulatedBackend();
    final ImportedSource source = await _stage(catalog, backend, 'sf-004');
    final SimulatedPageRasterAdapter rasterAdapter = SimulatedPageRasterAdapter(
      backend: backend,
    );
    final SimulatedOcrAdapter ocrAdapter = SimulatedOcrAdapter(
      backend: backend,
      catalog: catalog,
    );
    final _RecordingOcrPort recordingOcr = _RecordingOcrPort(ocrAdapter);

    // Page 1 does not exist in the one-page staged source: the raster port
    // raises RenderException and the pipeline maps it to PAGE-001 without
    // touching page 0.
    final List<analysis.DocumentAnalysisPage> pages =
        <analysis.DocumentAnalysisPage>[
          _page(source, 0),
          _page(source, 1, geometryPageIndex: 0),
        ];
    final analysis.DocumentAnalysisResult isolated =
        await analysis.AnalyzeDocument.run(
          _request(
            sourceId: source.sourceId,
            analysisRunId: _isolationRunId,
            pages: pages,
            rasterPort: rasterAdapter,
            ocrPort: recordingOcr,
          ),
        );

    expect(isolated.pages, hasLength(2));
    expect(isolated.cancelledPageIndexes, isEmpty);

    final FieldSuggestionSet completed = isolated.pages[0];
    final FieldSuggestionSet failed = isolated.pages[1];
    final SimulatedFixturePage geometry = fixture.pages[0];
    final PageDisplaySize pageSize = PageDisplaySize(
      geometry.widthPt,
      geometry.heightPt,
    );

    _expectValidEnvelope(
      completed,
      pageIndex: 0,
      expectedSize: pageSize,
      expectedRotation: geometry.rotation,
    );
    expect(completed.status, FieldSuggestionSet.statusComplete);
    expect(completed.failure, isNull);
    expect(completed.suggestions, isEmpty);

    _expectValidEnvelope(
      failed,
      pageIndex: 1,
      expectedSize: pageSize,
      expectedRotation: geometry.rotation,
    );
    expect(failed.status, FieldSuggestionSet.statusFailed);
    expect(failed.suggestions, isEmpty);
    final PageAnalysisFailure? failure = failed.failure;
    expect(failure, isNotNull);
    expect(failure!.category, PageAnalysisFailure.rasterization);
    expect(failure.messageKey, 'PAGE-001');
    expect(failure.recoverable, isTrue);
    expect(failure.suggestionCount, 0);

    // The failed page never reached OCR; the completed page did.
    expect(recordingOcr.pageIndexes, <int>[0]);
    expect(recordingOcr.blockCounts, <int>[24]);

    // The completed page is identical to analysing it alone: the failed page
    // neither blocks nor corrupts it.
    final analysis.DocumentAnalysisResult standalone =
        await analysis.AnalyzeDocument.run(
          _request(
            sourceId: source.sourceId,
            analysisRunId: _isolationRunId,
            pages: <analysis.DocumentAnalysisPage>[_page(source, 0)],
            rasterPort: rasterAdapter,
            ocrPort: _RecordingOcrPort(ocrAdapter),
          ),
        );
    expect(standalone.pages, hasLength(1));
    expect(_fingerprint(completed), _fingerprint(standalone.pages.single));

    _marker(
      'sf-004 isolation: page0=${completed.status} '
      'suggestions=${completed.suggestions.length} '
      'page1=${failed.status} failure=${failure.messageKey}/'
      '${failure.category} page1Suggestions=${failed.suggestions.length} '
      'ocrPages=${recordingOcr.pageIndexes} ocrBlocks=${recordingOcr.blockCounts}',
    );
  });

  test('keeps a page completed when OCR is unavailable (ocrUsed=false)', () async {
    final SimulatedFixtureCatalog catalog = await _loadCatalog();
    final SimulatedFixture fixture = catalog.fixture('sf-003');
    expect(fixture.pageCount, 5);
    final SimulatedBackend backend = SimulatedBackend();
    final ImportedSource source = await _stage(catalog, backend, 'sf-003');

    final SimulatedPageRasterAdapter rasterAdapter = SimulatedPageRasterAdapter(
      backend: backend,
    );
    final SimulatedOcrAdapter ocrAdapter = SimulatedOcrAdapter(
      backend: backend,
      catalog: catalog,
    );
    final _RecordingOcrPort failingOcr = _RecordingOcrPort(
      ocrAdapter,
      failingPageIndexes: const <int>{0},
    );

    final analysis.DocumentAnalysisResult degraded =
        await analysis.AnalyzeDocument.run(
          _request(
            sourceId: source.sourceId,
            analysisRunId: _degradedRunId,
            pages: <analysis.DocumentAnalysisPage>[_page(source, 0)],
            rasterPort: rasterAdapter,
            ocrPort: failingOcr,
          ),
        );
    final FieldSuggestionSet page = degraded.pages.single;

    expect(page.status, FieldSuggestionSet.statusComplete);
    expect(page.failure, isNull);
    expect(page.suggestions, isEmpty);
    expect(page.evidenceClass, EvidenceClass.simulated.name);
    expect(failingOcr.pageIndexes, <int>[0]);
    expect(failingOcr.blockCounts, isEmpty);

    // OCR is auxiliary: with the shipped zero-suggestion output the degraded
    // page is observably identical to the OCR-backed page. This test pins the
    // pipeline's "OCR failure is never a page failure" behavior; it cannot
    // observe the per-suggestion `evidence.ocrUsed` flag because the shipped
    // SIMULATED raster produces no suggestion to carry it.
    final analysis.DocumentAnalysisResult healthy =
        await analysis.AnalyzeDocument.run(
          _request(
            sourceId: source.sourceId,
            analysisRunId: _degradedRunId,
            pages: <analysis.DocumentAnalysisPage>[_page(source, 0)],
            rasterPort: rasterAdapter,
            ocrPort: _RecordingOcrPort(ocrAdapter),
          ),
        );
    expect(_fingerprint(healthy.pages.single), _fingerprint(page));

    _marker(
      'sf-003 ocr-unavailable: page=${page.status} '
      'suggestions=${page.suggestions.length} failure=${page.failure?.messageKey ?? 'none'} '
      'ocrCalls=${failingOcr.pageIndexes} ocrBlocks=${failingOcr.blockCounts} '
      'note=ocrUsed-not-materialized-without-suggestions',
    );
  });
}
