// Issue #217 Phase B1 editor analysis and persistence tests.
//
// Evidence class: NONE. These are host-VM unit/widget tests with injected fake
// ports, an in-memory revision, and synthetic rasters. They construct no
// platform channel, open no PDF, start no browser, emulator, or device, and
// make no Android runtime or performance claim.
//
// They prove the Phase B1 composition:
//   * first open loads the current revision, analyzes pages the import did not
//     mark unreadable, converts complete T057 envelopes into canonical
//     suggestions, validates them through `RevisionContent`, updates each
//     page's analysis state, and saves one autosave revision with the expected
//     head;
//   * symmetric conflicts and both candidates survive persistence;
//   * an existing suggestion set is neither duplicated nor overwritten and no
//     revision is written;
//   * a completed zero-suggestion run is durable across reopen and a partially
//     unreadable first import still analyzes its readable pages;
//   * full loaded/source page geometry equality: page-count, orientation-only,
//     real divergent-box, and quantized-within-tolerance cases;
//   * a page failure is isolated while the healthy page is saved;
//   * the viewer and strip are available while analysis is still running;
//   * a save failure keeps the viewer and the in-memory result;
//   * `applyDocumentAnalysis` leaves the base revision immutable on both the
//     successful path and the non-empty-suggestions guard path;
//   * `ImportRuntime` falls back to the unavailable runtime for any
//     object-level construction failure;
//   * every recognition failure category maps to the fixed core failure
//     contract, and cancelled pages stay pending;
//   * the build-mode evidence label is deterministic and never a hardware
//     claim.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/page_view.dart';
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/features/start/import_runtime.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_application/src/recognition/analyze_document.dart'
    as analysis;
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:feldexa_recognition/src/page_analysis.dart' as recognition;
import 'package:flutter/material.dart' hide PageView;
import 'package:flutter_test/flutter_test.dart';

const String _documentId = '5f0c3a52-3a6a-4f0b-9c2d-1b7e4d8a6c01';
const String _sourceId = '7b2d4c1e-5f3a-4b8c-8a9d-2e6f0c1b3d42';
const String _revisionId = '9a1b2c3d-4e5f-4a6b-8c7d-8e9f0a1b2c3d';
const String _analysisRunId = '22222222-2222-4222-8222-222222222222';
const double _pageWidthPt = 144;
const double _pageHeightPt = 144;
const int _rasterWidth = 400;
const int _rasterHeight = 400;
final String _sha256 = List<String>.filled(64, 'a').join();
final Uint8List _sourceBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

final CapabilityEvidence _noneEvidence = CapabilityEvidence(
  evidenceClass: EvidenceClass.none,
  adapterId: 'test.editor-analysis.v1',
);

final CapabilityDescriptor _rasterDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.pageRaster,
  adapterId: 'test.raster.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final CapabilityDescriptor _ocrDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.ocr,
  adapterId: 'test.ocr.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final CapabilityDescriptor _storeDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.secureStore,
  adapterId: 'test.store.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final CapabilityDescriptor _idsDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.ids,
  adapterId: 'test.ids.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final CapabilityDescriptor _clockDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.clock,
  adapterId: 'test.clock.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final CapabilityDescriptor _importDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.documentImport,
  adapterId: 'test.import.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

/// A deterministic 400 x 400 grayscale canvas for a 144 x 144 pt page.
final class _Canvas {
  _Canvas({int background = 255})
    : _bytes = Uint8List(_rasterWidth * _rasterHeight) {
    _bytes.fillRange(0, _bytes.length, background);
  }

  final Uint8List _bytes;

  void fillRect(int left, int top, int right, int bottom, {int value = 0}) {
    for (int y = top; y < bottom; y++) {
      for (int x = left; x < right; x++) {
        _bytes[y * _rasterWidth + x] = value;
      }
    }
  }

  Uint8List build() => Uint8List.fromList(_bytes);
}

RasterImage _image({int top = 200}) {
  final _Canvas canvas = _Canvas()..fillRect(100, top, 200, top + 2);
  return RasterImage(
    bytes: canvas.build(),
    width: _rasterWidth,
    height: _rasterHeight,
    bytesPerRow: _rasterWidth,
    format: RasterFormat.gray8,
    evidence: _noneEvidence,
  );
}

RasterImage _blankImage() {
  return RasterImage(
    bytes: _Canvas().build(),
    width: _rasterWidth,
    height: _rasterHeight,
    bytesPerRow: _rasterWidth,
    format: RasterFormat.gray8,
    evidence: _noneEvidence,
  );
}

RasterImage _conflictImage() {
  final _Canvas canvas = _Canvas()
    ..fillRect(100, 200, 200, 202)
    ..fillRect(100, 210, 200, 212);
  return RasterImage(
    bytes: canvas.build(),
    width: _rasterWidth,
    height: _rasterHeight,
    bytesPerRow: _rasterWidth,
    format: RasterFormat.gray8,
    evidence: _noneEvidence,
  );
}

OcrBlock _ocrBlock({
  required String text,
  required core.Rect rect,
  double confidence = 0.95,
}) {
  return OcrBlock(
    rect: rect,
    text: text,
    confidence: confidence,
    lines: <OcrLine>[OcrLine(rect: rect, text: text, confidence: confidence)],
  );
}

core.PageGeometry _geometryOf(
  double widthPt,
  double heightPt, {
  int rotation = 0,
}) {
  return core.PageGeometry(
    mediaBox: core.Rect.fromLTWH(0, 0, widthPt, heightPt),
    rotation: rotation,
  );
}

core.PageGeometry _geometry() {
  return _geometryOf(_pageWidthPt, _pageHeightPt);
}

core.RevisionContent _initialContent({
  int pageCount = 1,
  core.PageGeometry? geometry,
}) {
  return core.RevisionContent(
    pages: <core.Page>[
      for (int index = 0; index < pageCount; index++)
        core.Page(index: index, geometry: geometry ?? _geometry()),
    ],
    fieldOrder: const <String>[],
  );
}

core.RevisionContent _partialImportContent() {
  return core.RevisionContent(
    pages: <core.Page>[
      core.Page(index: 0, geometry: _geometry()),
      core.Page(
        index: 1,
        geometry: _geometry(),
        analysis: core.AnalysisState.failed,
        failure: core.PageFailure(
          pageIndex: 1,
          category: core.PageFailureCategory.unreadable,
          messageKey: 'IMP-006',
        ),
        unreadable: true,
      ),
    ],
    fieldOrder: const <String>[],
  );
}

core.RevisionContent _contentWithSuggestion() {
  return core.RevisionContent(
    pages: <core.Page>[
      core.Page(
        index: 0,
        geometry: _geometry(),
        analysis: core.AnalysisState.complete,
      ),
    ],
    suggestions: <core.FieldSuggestion>[
      core.FieldSuggestion(
        id: 's_p0_0001',
        pageIndex: 0,
        rect: core.Rect.fromLTWH(36, 54, 36, 18),
        proposedType: core.FieldType.text,
        confidence: 0.5,
        labelText: null,
        evidence: core.SuggestionEvidence(
          cues: const <core.SuggestionCue>[core.SuggestionCue.underline],
          ocrUsed: false,
        ),
      ),
    ],
    fieldOrder: const <String>[],
  );
}

core.RevisionContent _contentWithTwoSuggestions() {
  return core.RevisionContent(
    pages: <core.Page>[
      core.Page(
        index: 0,
        geometry: _geometry(),
        analysis: core.AnalysisState.complete,
      ),
    ],
    suggestions: <core.FieldSuggestion>[
      core.FieldSuggestion(
        id: 's_p0_0001',
        pageIndex: 0,
        rect: core.Rect.fromLTWH(36, 54, 36, 18),
        proposedType: core.FieldType.text,
        confidence: 0.5,
        labelText: null,
        evidence: core.SuggestionEvidence(
          cues: const <core.SuggestionCue>[core.SuggestionCue.underline],
          ocrUsed: false,
        ),
      ),
      core.FieldSuggestion(
        id: 's_p0_0002',
        pageIndex: 0,
        rect: core.Rect.fromLTWH(36, 90, 36, 18),
        proposedType: core.FieldType.number,
        confidence: 0.4,
        labelText: 'Betrag',
        evidence: core.SuggestionEvidence(
          cues: const <core.SuggestionCue>[core.SuggestionCue.underline],
          ocrUsed: false,
        ),
      ),
    ],
    fieldOrder: const <String>[],
  );
}

LoadedDocument _loaded({int pageCount = 1, core.RevisionContent? content}) {
  return LoadedDocument(
    meta: core.DocumentMeta(
      id: _documentId,
      title: 'Testdokument',
      createdAt: DateTime.utc(2026, 11, 20),
      updatedAt: DateTime.utc(2026, 11, 20),
      source: core.SourceFileRef(
        id: _sourceId,
        sha256: _sha256,
        sizeBytes: _sourceBytes.length,
        pageCount: pageCount,
        importedAt: DateTime.utc(2026, 11, 20),
      ),
      latestRevisionId: _revisionId,
      lastDurableAt: DateTime.utc(2026, 11, 20),
    ),
    content: content ?? _initialContent(pageCount: pageCount),
    sourceBytes: _sourceBytes,
    evidence: _noneEvidence,
  );
}

ImportedSource _source({
  int pageCount = 1,
  List<int> unreadablePages = const <int>[],
  core.PageGeometry? geometry,
}) {
  return ImportedSource(
    documentId: _documentId,
    sourceId: _sourceId,
    sha256: _sha256,
    sizeBytes: _sourceBytes.length,
    pageCount: pageCount,
    pages: <core.PageGeometry>[
      for (int index = 0; index < pageCount; index++) geometry ?? _geometry(),
    ],
    pageFailures: <core.PageFailure>[
      for (final int pageIndex in unreadablePages)
        core.PageFailure(
          pageIndex: pageIndex,
          category: core.PageFailureCategory.unreadable,
          messageKey: 'IMP-006',
        ),
    ],
    evidence: _noneEvidence,
  );
}

final class _FakeRaster implements PageRasterPort {
  _FakeRaster({
    required this.images,
    this.failingPages = const <int>{},
    this.gate,
  });

  final Map<int, RasterImage> images;
  final Set<int> failingPages;
  final Completer<void>? gate;
  final List<RasterRequest> requests = <RasterRequest>[];

  @override
  CapabilityDescriptor get descriptor => _rasterDescriptor;

  @override
  Future<core.PageGeometry> pageDimensions(
    String sourceId,
    int pageIndex,
  ) async {
    return _geometry();
  }

  @override
  Future<RasterImage> renderPage(RasterRequest request) async {
    requests.add(request);
    final Completer<void>? pending = gate;
    if (pending != null) {
      await pending.future;
    }
    if (failingPages.contains(request.pageIndex)) {
      throw RenderException(pageIndex: request.pageIndex);
    }
    final RasterImage? image = images[request.pageIndex];
    if (image == null) {
      throw RenderException(pageIndex: request.pageIndex);
    }
    return image;
  }

  @override
  Future<void> evict(String sourceId) async {}
}

final class _FakeOcr implements OcrPort {
  _FakeOcr({this.blocksByPage = const <int, List<OcrBlock>>{}});

  final Map<int, List<OcrBlock>> blocksByPage;
  final List<OcrRequest> requests = <OcrRequest>[];

  @override
  CapabilityDescriptor get descriptor => _ocrDescriptor;

  @override
  Future<List<OcrBlock>> recognize(OcrRequest request) async {
    requests.add(request);
    return blocksByPage[request.pageIndex] ?? const <OcrBlock>[];
  }

  @override
  Future<void> dispose() async {}
}

/// Fake store covering the two editor paths; other members are unused.
///
/// A successful save replaces [loaded] with the committed snapshot so a second
/// editor open in the same test sees exactly what a reopen would see.
final class _FakeStore implements SecureStorePort {
  _FakeStore({required this.loaded, this.saveError, this.loadGate});

  LoadedDocument loaded;
  final Object? saveError;
  final Completer<void>? loadGate;
  int loads = 0;
  int _saveCount = 0;
  final List<SaveRevisionRequest> saves = <SaveRevisionRequest>[];
  final List<String> savedHeads = <String>[];

  @override
  CapabilityDescriptor get descriptor => _storeDescriptor;

  @override
  Future<LoadedDocument> loadDocument(String documentId) async {
    loads++;
    final Completer<void>? gate = loadGate;
    if (gate != null) {
      await gate.future;
    }
    return loaded;
  }

  @override
  Future<StoredMeta> saveRevision(SaveRevisionRequest request) async {
    saves.add(request);
    if (saveError != null) {
      throw saveError!;
    }
    _saveCount++;
    final String head =
        '9a1b2c3d-4e5f-4a6b-8c7d-'
        '${_saveCount.toString().padLeft(12, '0')}';
    savedHeads.add(head);
    final StoredMeta meta = StoredMeta(
      id: request.documentId,
      kind: StoreKind.document,
      title: 'Testdokument',
      createdAt: DateTime.utc(2026, 11, 20),
      updatedAt: DateTime.utc(2026, 11, 20),
      latestRevisionId: head,
      readable: true,
    );
    loaded = LoadedDocument(
      meta: core.DocumentMeta(
        id: loaded.meta.id,
        title: loaded.meta.title,
        createdAt: loaded.meta.createdAt,
        updatedAt: loaded.meta.updatedAt,
        source: loaded.meta.source,
        latestRevisionId: head,
        lastDurableAt: loaded.meta.lastDurableAt,
        readable: loaded.meta.readable,
        unreadableReasonCode: loaded.meta.unreadableReasonCode,
      ),
      content: request.content,
      sourceBytes: loaded.sourceBytes,
      evidence: loaded.evidence,
    );
    return meta;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedOperationException();
  }
}

/// Import port used only to construct an `ImportRuntime` in the factory test.
final class _ThrowImportPort implements DocumentImportPort {
  @override
  CapabilityDescriptor get descriptor => _importDescriptor;

  @override
  Future<ImportedSource> pickAndImport(ImportRequest request) async {
    throw UnsupportedOperationException();
  }

  @override
  Future<SourceIntegrity> verifySource(String sourceId) async {
    throw UnsupportedOperationException();
  }
}

final class _FakeIds implements IdPort {
  int calls = 0;

  @override
  CapabilityDescriptor get descriptor => _idsDescriptor;

  @override
  String newId() {
    calls++;
    return _analysisRunId;
  }

  @override
  String newIdempotencyKey() => _revisionId;
}

final class _FakeClock implements ClockPort {
  DateTime now = DateTime.utc(2026, 11, 20, 12);

  @override
  CapabilityDescriptor get descriptor => _clockDescriptor;

  @override
  DateTime nowUtc() => now;
}

final class _FakeEditorRuntime implements EditorRuntime {
  _FakeEditorRuntime({
    required this.raster,
    required this.ocr,
    required this.store,
    _FakeIds? ids,
    _FakeClock? clock,
  }) : ids = ids ?? _FakeIds(),
       clock = clock ?? _FakeClock();

  @override
  final PageRasterPort raster;

  @override
  final OcrPort? ocr;

  @override
  final SecureStorePort store;

  @override
  final IdPort ids;

  @override
  final ClockPort clock;

  bool disposed = false;

  @override
  Future<LoadedDocument> loadDocument(String documentId) {
    return store.loadDocument(documentId);
  }

  @override
  Future<StoredMeta> saveRevision(SaveRevisionRequest request) {
    return store.saveRevision(request);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

final class _FakeRendererFactory {
  _FakeRendererFactory(this.pageCount);

  final int pageCount;
  int calls = 0;
  Uint8List? lastBytes;

  Future<PageViewRenderer> call(Uint8List bytes) async {
    calls++;
    lastBytes = bytes;
    return _FakePageRenderer(pageCount);
  }
}

final class _FakePageRenderer implements PageViewRenderer {
  _FakePageRenderer(this.pageCount);

  @override
  final int pageCount;

  @override
  Widget buildPage(
    BuildContext context,
    int pageIndex, {
    required ValueChanged<PageViewLoadException> onFailure,
  }) {
    return ColoredBox(
      key: ValueKey<String>('fake-page-$pageIndex'),
      color: const Color(0xFF00FF00),
    );
  }

  @override
  Future<void> dispose() async {}
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required EditorRuntime runtime,
  required ImportedSource source,
  _FakeRendererFactory? rendererFactory,
  Duration? loadTimeout,
  Duration? analysisTimeout,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const <Locale>[Locale('de')],
      home: EditorScreen(
        source: source,
        sourceBytes: (String _) async => _sourceBytes,
        runtime: runtime,
        rendererFactory:
            (rendererFactory ?? _FakeRendererFactory(source.pageCount)).call,
        loadTimeout: loadTimeout ?? editorLoadTimeout,
        analysisTimeout: analysisTimeout ?? editorAnalysisTimeout,
      ),
    ),
  );
}

EditorScreenState _editorState(WidgetTester tester) {
  return tester.state<EditorScreenState>(find.byType(EditorScreen));
}

void main() {
  testWidgets(
    'loads, analyzes, and saves the first suggestion revision with symmetric '
    'conflicts',
    (tester) async {
      final _FakeStore store = _FakeStore(loaded: _loaded());
      final _FakeRaster raster = _FakeRaster(
        images: <int, RasterImage>{0: _conflictImage()},
      );
      final _FakeOcr ocr = _FakeOcr(
        blocksByPage: <int, List<OcrBlock>>{
          0: <OcrBlock>[
            _ocrBlock(text: 'Betrag', rect: core.Rect.fromLTWH(10, 56, 22, 10)),
          ],
        },
      );
      final _FakeIds ids = _FakeIds();
      final _FakeEditorRuntime runtime = _FakeEditorRuntime(
        raster: raster,
        ocr: ocr,
        store: store,
        ids: ids,
      );

      await _pumpEditor(tester, runtime: runtime, source: _source());
      await tester.pumpAndSettle();

      final EditorScreenState state = _editorState(tester);
      expect(state.analysisStateKey, editorAnalysisReadyKey);
      expect(state.analysisRunId, _analysisRunId);
      expect(state.analysisElapsedMs, isNotNull);
      expect(state.analysisElapsedMs, greaterThanOrEqualTo(0));
      expect(state.loadedDocument, isNotNull);
      expect(state.content, isNotNull);
      expect(ids.calls, 1);
      expect(store.loads, 1);
      expect(store.saves, hasLength(1));
      expect(raster.requests.single.pageIndex, 0);
      expect(ocr.requests.single.pageIndex, 0);

      final SaveRevisionRequest saved = store.saves.single;
      expect(saved.documentId, _documentId);
      expect(saved.expectedHead, _revisionId);
      expect(saved.kind, core.RevisionKind.autosave);
      expect(saved.content.pages.single.analysis, core.AnalysisState.complete);
      expect(saved.content.pages.single.failure, isNull);
      expect(saved.content.suggestions, hasLength(2));
      expect(state.content!.suggestions, hasLength(2));
      expect(state.content!.suggestions, saved.content.suggestions);

      final core.FieldSuggestion first = saved.content.suggestions[0];
      final core.FieldSuggestion second = saved.content.suggestions[1];
      expect(first.resolution, core.SuggestionResolution.unresolved);
      expect(second.resolution, core.SuggestionResolution.unresolved);
      expect(first.conflictsWith, <String>[second.id]);
      expect(second.conflictsWith, <String>[first.id]);
      expect(first.evidence.ocrUsed, isTrue);
      expect(
        saved.content.suggestions.where(
          (core.FieldSuggestion suggestion) => suggestion.labelText == 'Betrag',
        ),
        isNotEmpty,
      );
      expect(
        saved.content.suggestions.where(
          (core.FieldSuggestion suggestion) =>
              suggestion.proposedType == core.FieldType.number,
        ),
        isNotEmpty,
      );

      expect(
        find.byKey(const ValueKey<String>('editor-screen')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>(editorAnalysisReadyKey)),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('page-strip-page-1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('fake-page-0')), findsOneWidget);
    },
  );

  testWidgets(
    'an existing suggestion set is skipped without analysis or a write',
    (tester) async {
      final core.RevisionContent existing = _contentWithSuggestion();
      final _FakeStore store = _FakeStore(loaded: _loaded(content: existing));
      final _FakeRaster raster = _FakeRaster(
        images: <int, RasterImage>{0: _image()},
      );
      final _FakeOcr ocr = _FakeOcr();
      final _FakeIds ids = _FakeIds();
      final _FakeEditorRuntime runtime = _FakeEditorRuntime(
        raster: raster,
        ocr: ocr,
        store: store,
        ids: ids,
      );

      await _pumpEditor(tester, runtime: runtime, source: _source());
      await tester.pumpAndSettle();

      final EditorScreenState state = _editorState(tester);
      expect(state.analysisStateKey, editorAnalysisSkippedKey);
      expect(state.analysisRunId, isNull);
      expect(state.content, existing);
      expect(state.content!.suggestions.single.id, 's_p0_0001');
      expect(raster.requests, isEmpty);
      expect(ocr.requests, isEmpty);
      expect(ids.calls, 0);
      expect(store.saves, isEmpty);
      expect(
        find.byKey(const ValueKey<String>('editor-screen')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>(editorAnalysisSkippedKey)),
        findsOneWidget,
      );
    },
  );

  testWidgets('a completed zero-suggestion run is durable across reopen', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeRaster firstRaster = _FakeRaster(
      images: <int, RasterImage>{0: _blankImage()},
    );
    final _FakeIds firstIds = _FakeIds();
    final _FakeEditorRuntime firstRuntime = _FakeEditorRuntime(
      raster: firstRaster,
      ocr: null,
      store: store,
      ids: firstIds,
    );

    await _pumpEditor(tester, runtime: firstRuntime, source: _source());
    await tester.pumpAndSettle();

    final EditorScreenState firstOpen = _editorState(tester);
    expect(firstOpen.analysisStateKey, editorAnalysisReadyKey);
    expect(firstOpen.content!.suggestions, isEmpty);
    expect(
      firstOpen.content!.pages.single.analysis,
      core.AnalysisState.complete,
    );
    expect(
      find.byKey(const ValueKey<String>('suggestion-empty')),
      findsOneWidget,
    );
    expect(
      find.text(lookupAppLocalizations(const Locale('de')).suggestionEmpty),
      findsOneWidget,
    );
    expect(firstIds.calls, 1);
    expect(firstRaster.requests, hasLength(1));
    expect(store.saves, hasLength(1));

    // Tear the first editor down so the second pump constructs a fresh state,
    // matching a real reopen rather than an in-place widget update.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    final _FakeRaster secondRaster = _FakeRaster(
      images: <int, RasterImage>{0: _blankImage()},
    );
    final _FakeIds secondIds = _FakeIds();
    final _FakeEditorRuntime secondRuntime = _FakeEditorRuntime(
      raster: secondRaster,
      ocr: null,
      store: store,
      ids: secondIds,
    );

    await _pumpEditor(tester, runtime: secondRuntime, source: _source());
    await tester.pumpAndSettle();

    final EditorScreenState reopened = _editorState(tester);
    expect(reopened.analysisStateKey, editorAnalysisSkippedKey);
    expect(reopened.content!.suggestions, isEmpty);
    expect(
      reopened.content!.pages.single.analysis,
      core.AnalysisState.complete,
    );
    expect(secondIds.calls, 0);
    expect(secondRaster.requests, isEmpty);
    expect(store.saves, hasLength(1));
    expect(store.loads, 2);
    expect(
      find.byKey(const ValueKey<String>('suggestion-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('suggestion-empty')),
      findsOneWidget,
    );
  });

  testWidgets(
    'a partially unreadable first import still analyzes readable pages',
    (tester) async {
      final _FakeStore store = _FakeStore(
        loaded: _loaded(pageCount: 2, content: _partialImportContent()),
      );
      final _FakeRaster raster = _FakeRaster(
        images: <int, RasterImage>{0: _image()},
      );
      final _FakeEditorRuntime runtime = _FakeEditorRuntime(
        raster: raster,
        ocr: null,
        store: store,
      );

      await _pumpEditor(
        tester,
        runtime: runtime,
        source: _source(pageCount: 2, unreadablePages: <int>[1]),
      );
      await tester.pumpAndSettle();

      final EditorScreenState state = _editorState(tester);
      expect(state.analysisStateKey, editorAnalysisReadyKey);
      expect(
        raster.requests.map((RasterRequest request) => request.pageIndex),
        <int>[0],
      );
      expect(store.saves, hasLength(1));
      final core.RevisionContent saved = store.saves.single.content;
      expect(saved.pages[0].analysis, core.AnalysisState.complete);
      expect(saved.pages[1].analysis, core.AnalysisState.failed);
      expect(saved.pages[1].unreadable, isTrue);
      expect(saved.pages[1].failure!.messageKey, 'IMP-006');
    },
  );

  testWidgets('divergent loaded geometry fails before analysis or save', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(
      loaded: _loaded(
        content: _initialContent(geometry: _geometryOf(200, 200)),
      ),
    );
    final _FakeRaster raster = _FakeRaster(
      images: <int, RasterImage>{0: _blankImage()},
    );
    final _FakeIds ids = _FakeIds();
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(
      raster: raster,
      ocr: null,
      store: store,
      ids: ids,
    );

    await _pumpEditor(tester, runtime: runtime, source: _source());
    await tester.pumpAndSettle();

    final EditorScreenState state = _editorState(tester);
    expect(state.analysisStateKey, editorAnalysisFailedKey);
    expect(state.content, isNull);
    expect(raster.requests, isEmpty);
    expect(ids.calls, 0);
    expect(store.saves, isEmpty);
    expect(
      find.byKey(const ValueKey<String>(editorAnalysisFailedKey)),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('editor-screen')), findsOneWidget);
  });

  testWidgets('a loaded/source page-count mismatch fails before analysis', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(
      loaded: _loaded(pageCount: 2, content: _initialContent(pageCount: 1)),
    );
    final _FakeRaster raster = _FakeRaster(
      images: <int, RasterImage>{0: _blankImage()},
    );
    final _FakeIds ids = _FakeIds();
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(
      raster: raster,
      ocr: null,
      store: store,
      ids: ids,
    );

    await _pumpEditor(tester, runtime: runtime, source: _source(pageCount: 2));
    await tester.pumpAndSettle();

    final EditorScreenState state = _editorState(tester);
    expect(state.analysisStateKey, editorAnalysisFailedKey);
    expect(state.content, isNull);
    expect(raster.requests, isEmpty);
    expect(ids.calls, 0);
    expect(store.saves, isEmpty);
    expect(find.byKey(const ValueKey<String>('editor-screen')), findsOneWidget);
  });

  testWidgets('same-size different rotation fails before analysis', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(
      loaded: _loaded(
        content: _initialContent(
          geometry: _geometryOf(_pageWidthPt, _pageHeightPt, rotation: 270),
        ),
      ),
    );
    final _FakeRaster raster = _FakeRaster(
      images: <int, RasterImage>{0: _blankImage()},
    );
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(
      raster: raster,
      ocr: null,
      store: store,
    );

    await _pumpEditor(
      tester,
      runtime: runtime,
      source: _source(
        geometry: _geometryOf(_pageWidthPt, _pageHeightPt, rotation: 90),
      ),
    );
    await tester.pumpAndSettle();

    final EditorScreenState state = _editorState(tester);
    expect(state.analysisStateKey, editorAnalysisFailedKey);
    expect(state.content, isNull);
    expect(raster.requests, isEmpty);
    expect(store.saves, isEmpty);
  });

  testWidgets('quantized geometry within 0.001 pt per edge is accepted', (
    tester,
  ) async {
    final core.PageGeometry quantized = core.PageGeometry(
      mediaBox: core.Rect.fromLTWH(0.0005, 0.0005, _pageWidthPt, _pageHeightPt),
    );
    final _FakeStore store = _FakeStore(
      loaded: _loaded(content: _initialContent(geometry: quantized)),
    );
    final _FakeRaster raster = _FakeRaster(
      images: <int, RasterImage>{0: _image()},
    );
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(
      raster: raster,
      ocr: null,
      store: store,
    );

    await _pumpEditor(tester, runtime: runtime, source: _source());
    await tester.pumpAndSettle();

    final EditorScreenState state = _editorState(tester);
    expect(state.analysisStateKey, editorAnalysisReadyKey);
    expect(raster.requests, hasLength(1));
    expect(store.saves, hasLength(1));
    expect(
      store.saves.single.content.pages.single.geometry.mediaBox.left,
      closeTo(0.0005, 1e-12),
    );
  });

  testWidgets('a page failure is isolated while the healthy page is saved', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded(pageCount: 2));
    final _FakeRaster raster = _FakeRaster(
      images: <int, RasterImage>{0: _image()},
      failingPages: const <int>{1},
    );
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(
      raster: raster,
      ocr: null,
      store: store,
    );

    await _pumpEditor(tester, runtime: runtime, source: _source(pageCount: 2));
    await tester.pumpAndSettle();

    final EditorScreenState state = _editorState(tester);
    expect(state.analysisStateKey, editorAnalysisReadyKey);
    expect(store.saves, hasLength(1));
    final core.RevisionContent saved = store.saves.single.content;
    expect(saved.pages[0].analysis, core.AnalysisState.complete);
    expect(saved.pages[0].failure, isNull);
    expect(saved.pages[1].analysis, core.AnalysisState.failed);
    expect(saved.pages[1].failure, isNotNull);
    expect(
      saved.pages[1].failure!.category,
      core.PageFailureCategory.rasterization,
    );
    expect(saved.pages[1].failure!.messageKey, 'PAGE-001');
    expect(saved.suggestions, isNotEmpty);
    expect(
      saved.suggestions.every(
        (core.FieldSuggestion suggestion) => suggestion.pageIndex == 0,
      ),
      isTrue,
    );
    expect(find.byKey(const ValueKey<String>('editor-screen')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('page-strip-page-2')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('fake-page-0')), findsOneWidget);
  });

  testWidgets('the viewer and strip stay available while analysis runs', (
    tester,
  ) async {
    final Completer<void> gate = Completer<void>();
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeRaster raster = _FakeRaster(
      images: <int, RasterImage>{0: _image()},
      gate: gate,
    );
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(
      raster: raster,
      ocr: null,
      store: store,
    );

    await _pumpEditor(tester, runtime: runtime, source: _source());
    await tester.pump();
    await tester.pump();

    final EditorScreenState state = _editorState(tester);
    expect(state.analysisStateKey, isNull);
    expect(raster.requests, hasLength(1));
    expect(find.byKey(const ValueKey<String>('editor-screen')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('page-strip-page-1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('fake-page-0')), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(_editorState(tester).analysisStateKey, editorAnalysisReadyKey);
  });

  testWidgets('a save failure keeps the viewer and the in-memory result', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(
      loaded: _loaded(),
      saveError: StateError('synthetic save failure'),
    );
    final _FakeRaster raster = _FakeRaster(
      images: <int, RasterImage>{0: _image()},
    );
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(
      raster: raster,
      ocr: null,
      store: store,
    );

    await _pumpEditor(tester, runtime: runtime, source: _source());
    await tester.pumpAndSettle();

    final EditorScreenState state = _editorState(tester);
    expect(tester.takeException(), isNull);
    expect(state.analysisStateKey, editorAnalysisFailedKey);
    expect(state.content, isNotNull);
    expect(state.content!.suggestions, isNotEmpty);
    expect(store.saves, hasLength(1));
    expect(find.byKey(const ValueKey<String>('editor-screen')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>(editorAnalysisFailedKey)),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('page-strip-page-1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('fake-page-0')), findsOneWidget);
  });

  testWidgets(
    'the viewer receives the single protected load without a second store read',
    (WidgetTester tester) async {
      final _FakeStore store = _FakeStore(loaded: _loaded());
      final _FakeRaster raster = _FakeRaster(
        images: <int, RasterImage>{0: _image()},
      );
      final _FakeEditorRuntime runtime = _FakeEditorRuntime(
        raster: raster,
        ocr: null,
        store: store,
      );
      final _FakeRendererFactory rendererFactory = _FakeRendererFactory(1);

      await _pumpEditor(
        tester,
        runtime: runtime,
        source: _source(),
        rendererFactory: rendererFactory,
      );
      await tester.pumpAndSettle();

      expect(store.loads, 1);
      expect(rendererFactory.calls, 1);
      expect(rendererFactory.lastBytes, orderedEquals(_sourceBytes));
      expect(_editorState(tester).analysisStateKey, editorAnalysisReadyKey);
    },
  );

  testWidgets(
    'a hung protected load becomes analysis-failed without a second read',
    (WidgetTester tester) async {
      final Completer<void> gate = Completer<void>();
      final _FakeStore store = _FakeStore(loaded: _loaded(), loadGate: gate);
      final _FakeRaster raster = _FakeRaster(
        images: <int, RasterImage>{0: _image()},
      );
      final _FakeEditorRuntime runtime = _FakeEditorRuntime(
        raster: raster,
        ocr: null,
        store: store,
      );
      final _FakeRendererFactory rendererFactory = _FakeRendererFactory(1);

      await _pumpEditor(
        tester,
        runtime: runtime,
        source: _source(),
        rendererFactory: rendererFactory,
        loadTimeout: const Duration(milliseconds: 100),
      );
      await tester.pump();
      expect(_editorState(tester).analysisStateKey, isNull);
      expect(store.loads, 1);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      final EditorScreenState state = _editorState(tester);
      expect(state.analysisStateKey, editorAnalysisFailedKey);
      expect(state.content, isNull);
      expect(store.loads, 1);
      expect(rendererFactory.calls, 0);
      expect(raster.requests, isEmpty);
      expect(
        find.byKey(const ValueKey<String>('editor-screen')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a hung analysis becomes analysis-failed without losing loaded content',
    (WidgetTester tester) async {
      final Completer<void> gate = Completer<void>();
      final _FakeStore store = _FakeStore(loaded: _loaded());
      final _FakeRaster raster = _FakeRaster(
        images: <int, RasterImage>{0: _image()},
        gate: gate,
      );
      final _FakeEditorRuntime runtime = _FakeEditorRuntime(
        raster: raster,
        ocr: null,
        store: store,
      );

      await _pumpEditor(
        tester,
        runtime: runtime,
        source: _source(),
        analysisTimeout: const Duration(milliseconds: 100),
      );
      await tester.pump();
      expect(_editorState(tester).analysisStateKey, isNull);
      expect(raster.requests, hasLength(1));

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      final EditorScreenState state = _editorState(tester);
      expect(state.analysisStateKey, editorAnalysisFailedKey);
      expect(state.content, isNotNull);
      expect(state.content!.pages.single.analysis, core.AnalysisState.pending);
      expect(store.saves, isEmpty);
      expect(
        find.byKey(const ValueKey<String>(editorAnalysisFailedKey)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      gate.complete();
    },
  );

  testWidgets(
    'confirm, reject, and undo save with the advancing revision head',
    (WidgetTester tester) async {
      final _FakeStore store = _FakeStore(
        loaded: _loaded(content: _contentWithTwoSuggestions()),
      );
      final _FakeClock clock = _FakeClock();
      final _FakeIds ids = _FakeIds();
      final _FakeEditorRuntime runtime = _FakeEditorRuntime(
        raster: _FakeRaster(images: const <int, RasterImage>{}),
        ocr: null,
        store: store,
        ids: ids,
        clock: clock,
      );

      await _pumpEditor(tester, runtime: runtime, source: _source());
      await tester.pumpAndSettle();

      final AppLocalizations de = lookupAppLocalizations(const Locale('de'));
      final EditorScreenState state = _editorState(tester);
      expect(state.analysisStateKey, editorAnalysisSkippedKey);
      expect(store.saves, isEmpty);
      expect(state.content!.suggestions, hasLength(2));
      expect(
        find.byKey(const ValueKey<String>('suggestion-row-s_p0_0001')),
        findsOneWidget,
      );
      expect(find.text(de.suggestionFieldCount(0)), findsOneWidget);

      // Confirm the first suggestion. The deterministic id source returns the
      // same UUID in this fake, which is valid while no field uses it.
      await tester.tap(
        find.byKey(const ValueKey<String>('confirm-suggestion-s_p0_0001')),
      );
      await tester.pumpAndSettle();

      expect(store.saves, hasLength(1));
      expect(store.saves[0].expectedHead, _revisionId);
      expect(store.saves[0].kind, core.RevisionKind.autosave);
      expect(state.content!.fields, hasLength(1));
      final core.ConfirmedField confirmed = state.content!.fields.single;
      expect(confirmed.id, _analysisRunId);
      expect(confirmed.provenance, core.Provenance.machine);
      expect(confirmed.sourceSuggestionId, 's_p0_0001');
      expect(confirmed.suggestionConfidence, 0.5);
      expect(confirmed.label, 'Feld 1');
      expect(confirmed.createdAt, clock.now);
      expect(
        state.content!.suggestions
            .firstWhere(
              (core.FieldSuggestion suggestion) => suggestion.id == 's_p0_0001',
            )
            .resolution,
        core.SuggestionResolution.confirmed,
      );
      expect(
        find.byKey(const ValueKey<String>('suggestion-row-s_p0_0001')),
        findsNothing,
      );
      expect(find.text(de.suggestionFieldCount(1)), findsOneWidget);

      // Reject the second suggestion; the next save must use the head that
      // the first save returned, not the original loaded revision.
      await tester.tap(
        find.byKey(const ValueKey<String>('reject-suggestion-s_p0_0002')),
      );
      await tester.pumpAndSettle();

      expect(store.saves, hasLength(2));
      expect(store.saves[1].expectedHead, store.savedHeads[0]);
      expect(
        state.content!.suggestions
            .firstWhere(
              (core.FieldSuggestion suggestion) => suggestion.id == 's_p0_0002',
            )
            .resolution,
        core.SuggestionResolution.rejected,
      );
      expect(find.text(de.suggestionReviewProgress(1, 1)), findsOneWidget);
      final Finder undoFinder = find.byKey(
        const ValueKey<String>(undoReviewKey),
      );
      expect(undoFinder, findsOneWidget);
      final TextButton undoButton = tester.widget<TextButton>(undoFinder);
      expect(
        undoButton.onPressed,
        isNotNull,
        reason: 'undo must stay enabled after a confirm + reject pair',
      );
      expect(state.canUndoReview, isTrue);
      expect(state.reviewBusy, isFalse);

      // Undo the rejection: rejected -> unresolved, no field change.
      await tester.tap(find.byKey(const ValueKey<String>(undoReviewKey)));
      await tester.pumpAndSettle();

      expect(store.saves, hasLength(3));
      expect(store.saves[2].expectedHead, store.savedHeads[1]);
      expect(
        state.content!.suggestions
            .firstWhere(
              (core.FieldSuggestion suggestion) => suggestion.id == 's_p0_0002',
            )
            .resolution,
        core.SuggestionResolution.unresolved,
      );
      expect(state.content!.fields, hasLength(1));

      // Undo the untouched confirmation: confirmed -> unresolved and the
      // generated field is removed; the suggestion set is not duplicated.
      await tester.tap(find.byKey(const ValueKey<String>(undoReviewKey)));
      await tester.pumpAndSettle();

      expect(store.saves, hasLength(4));
      expect(store.saves[3].expectedHead, store.savedHeads[2]);
      expect(state.content!.fields, isEmpty);
      expect(state.content!.suggestions, hasLength(2));
      expect(
        state.content!.suggestions.every(
          (core.FieldSuggestion suggestion) =>
              suggestion.resolution == core.SuggestionResolution.unresolved,
        ),
        isTrue,
      );
      expect(find.byKey(const ValueKey<String>(undoReviewKey)), findsNothing);
      expect(find.text(de.suggestionFieldCount(0)), findsOneWidget);
    },
  );

  testWidgets('undo after an analysis apply keeps the analysis suggestions', (
    WidgetTester tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeRaster raster = _FakeRaster(
      images: <int, RasterImage>{0: _image()},
    );
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(
      raster: raster,
      ocr: null,
      store: store,
    );

    await _pumpEditor(tester, runtime: runtime, source: _source());
    await tester.pumpAndSettle();

    final EditorScreenState state = _editorState(tester);
    expect(state.analysisStateKey, editorAnalysisReadyKey);
    expect(store.saves, hasLength(1));
    expect(state.content!.suggestions, isNotEmpty);
    final List<String> suggestionIds = <String>[
      for (final core.FieldSuggestion suggestion in state.content!.suggestions)
        suggestion.id,
    ];

    // The analysis apply persists a revision without being a user command.
    // It must not become an undo step: otherwise a single undo could write
    // the unanalyzed revision back and drop the whole suggestion set.
    expect(
      state.canUndoReview,
      isFalse,
      reason: 'the analysis apply is not a user undo step',
    );
    expect(find.byKey(const ValueKey<String>(undoReviewKey)), findsNothing);

    // Confirm one analyzed suggestion, then undo it. Only the confirmation is
    // reversed; the analysis result itself survives intact.
    await tester.tap(
      find.byKey(
        ValueKey<String>('$confirmSuggestionKeyPrefix${suggestionIds.first}'),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.saves, hasLength(2));
    expect(state.content!.fields, hasLength(1));
    expect(state.canUndoReview, isTrue);

    await tester.tap(find.byKey(const ValueKey<String>(undoReviewKey)));
    await tester.pumpAndSettle();

    expect(store.saves, hasLength(3));
    expect(state.content!.fields, isEmpty);
    expect(
      state.content!.suggestions.map(
        (core.FieldSuggestion suggestion) => suggestion.id,
      ),
      suggestionIds,
      reason: 'undo must never drop the analysis suggestions',
    );
    expect(
      state.content!.suggestions.every(
        (core.FieldSuggestion suggestion) =>
            suggestion.resolution == core.SuggestionResolution.unresolved,
      ),
      isTrue,
      reason: 'only the confirmation is reversed',
    );
    expect(
      state.content!.pages.single.analysis,
      core.AnalysisState.complete,
      reason: 'the analyzed page state is preserved',
    );
    expect(
      store.saves.last.content.suggestions.map(
        (core.FieldSuggestion suggestion) => suggestion.id,
      ),
      suggestionIds,
      reason: 'the written revision keeps every analysis suggestion',
    );
    expect(state.canUndoReview, isFalse);
  });

  testWidgets(
    'a review save failure keeps the viewer, panel, and prior revision',
    (WidgetTester tester) async {
      final _FakeStore store = _FakeStore(
        loaded: _loaded(content: _contentWithTwoSuggestions()),
        saveError: StateError('synthetic review save failure'),
      );
      final _FakeEditorRuntime runtime = _FakeEditorRuntime(
        raster: _FakeRaster(images: const <int, RasterImage>{}),
        ocr: null,
        store: store,
      );

      await _pumpEditor(tester, runtime: runtime, source: _source());
      await tester.pumpAndSettle();

      final AppLocalizations de = lookupAppLocalizations(const Locale('de'));
      final EditorScreenState state = _editorState(tester);
      expect(
        find.byKey(const ValueKey<String>('editor-screen')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('suggestion-panel')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('confirm-suggestion-s_p0_0001')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(store.saves, hasLength(1));
      expect(state.content!.fields, isEmpty);
      expect(state.reviewBusy, isFalse);
      expect(find.text(de.save003), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('editor-screen')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('suggestion-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('suggestion-row-s_p0_0001')),
        findsOneWidget,
      );
    },
  );

  test(
    'applyDocumentAnalysis leaves the base revision immutable on success',
    () async {
      final core.RevisionContent base = _initialContent();
      final Map<String, Object?> before = base.toJson();
      final List<core.FieldSuggestion> beforeSuggestions =
          List<core.FieldSuggestion>.of(base.suggestions);
      final _FakeRaster raster = _FakeRaster(
        images: <int, RasterImage>{0: _image()},
      );
      final analysis.DocumentAnalysisResult result =
          await analysis.AnalyzeDocument.run(
            analysis.DocumentAnalysisRequest(
              sourceId: _sourceId,
              analysisRunId: _analysisRunId,
              pages: <analysis.DocumentAnalysisPage>[
                analysis.DocumentAnalysisPage.fromGeometry(
                  pageIndex: 0,
                  geometry: base.pages.single.geometry,
                ),
              ],
              evidenceClass: 'simulated',
              rasterPort: raster,
            ),
          );

      final core.RevisionContent applied = applyDocumentAnalysis(
        base: base,
        result: result,
      );

      expect(identical(applied, base), isFalse);
      expect(applied.suggestions, isNotEmpty);
      expect(base.suggestions, beforeSuggestions);
      expect(base.suggestions, isEmpty);
      expect(base.pages.single.analysis, core.AnalysisState.pending);
      expect(base.toJson(), before);
    },
  );

  test(
    'applyDocumentAnalysis rejects existing suggestions without mutating the '
    'base revision',
    () async {
      final core.RevisionContent base = _contentWithSuggestion();
      final Map<String, Object?> before = base.toJson();
      final _FakeRaster raster = _FakeRaster(
        images: <int, RasterImage>{0: _blankImage()},
      );
      final analysis.DocumentAnalysisResult result =
          await analysis.AnalyzeDocument.run(
            analysis.DocumentAnalysisRequest(
              sourceId: _sourceId,
              analysisRunId: _analysisRunId,
              pages: <analysis.DocumentAnalysisPage>[
                analysis.DocumentAnalysisPage.fromGeometry(
                  pageIndex: 0,
                  geometry: base.pages.single.geometry,
                ),
              ],
              evidenceClass: 'simulated',
              rasterPort: raster,
            ),
          );

      expect(
        () => applyDocumentAnalysis(base: base, result: result),
        throwsStateError,
      );
      expect(base.suggestions, hasLength(1));
      expect(base.suggestions.single.id, 's_p0_0001');
      expect(base.toJson(), before);
    },
  );

  test('every recognition failure category maps to the core contract', () {
    final core.PageFailure rasterization = pageFailureForAnalysis(
      recognition.PageAnalysisFailure.forCategory(
        recognition.PageAnalysisFailure.rasterization,
      ),
      pageIndex: 3,
    );
    expect(rasterization.pageIndex, 3);
    expect(rasterization.category, core.PageFailureCategory.rasterization);
    expect(rasterization.messageKey, 'PAGE-001');

    final core.PageFailure unsupported = pageFailureForAnalysis(
      recognition.PageAnalysisFailure.forCategory(
        recognition.PageAnalysisFailure.unsupportedStructure,
      ),
      pageIndex: 3,
    );
    expect(unsupported.category, core.PageFailureCategory.unsupportedStructure);
    expect(unsupported.messageKey, 'REC-003');

    for (final String category in <String>[
      recognition.PageAnalysisFailure.internal,
      recognition.PageAnalysisFailure.ocr,
    ]) {
      final core.PageFailure mapped = pageFailureForAnalysis(
        recognition.PageAnalysisFailure.forCategory(category),
        pageIndex: 3,
      );
      expect(mapped.category, core.PageFailureCategory.unsupportedStructure);
      expect(mapped.messageKey, 'REC-002');
    }
  });

  test('cancelled pages stay pending and contribute no suggestions', () async {
    final _FakeRaster raster = _FakeRaster(
      images: <int, RasterImage>{0: _image(), 1: _image(top: 100)},
    );
    final core.RevisionContent base = _initialContent(pageCount: 2);
    final analysis.DocumentAnalysisResult result =
        await analysis.AnalyzeDocument.run(
          analysis.DocumentAnalysisRequest(
            sourceId: _sourceId,
            analysisRunId: _analysisRunId,
            pages: <analysis.DocumentAnalysisPage>[
              analysis.DocumentAnalysisPage.fromGeometry(
                pageIndex: 0,
                geometry: base.pages[0].geometry,
              ),
              analysis.DocumentAnalysisPage.fromGeometry(
                pageIndex: 1,
                geometry: base.pages[1].geometry,
              ),
            ],
            evidenceClass: 'simulated',
            rasterPort: raster,
          ),
          isCancelled: (int pageIndex) => pageIndex == 1,
        );

    final core.RevisionContent applied = applyDocumentAnalysis(
      base: base,
      result: result,
    );

    expect(applied.pages[0].analysis, core.AnalysisState.complete);
    expect(applied.pages[0].failure, isNull);
    expect(applied.pages[1].analysis, core.AnalysisState.pending);
    expect(applied.pages[1].failure, isNull);
    expect(applied.suggestions, isNotEmpty);
    expect(
      applied.suggestions.every(
        (core.FieldSuggestion suggestion) => suggestion.pageIndex == 0,
      ),
      isTrue,
    );
  });

  test(
    'ImportRuntime returns the unavailable runtime for a throwing factory',
    () async {
      final ImportRuntime importRuntime = ImportRuntime(
        importPort: _ThrowImportPort(),
        readSourceBytes: (String _) async => null,
        // StateError is an Error, not an Exception; the factory must still fail
        // closed at the composition boundary.
        editorRuntimeFactory: () =>
            throw StateError('synthetic editor construction failure'),
      );

      final EditorRuntime editorRuntime = importRuntime.createEditorRuntime();
      expect(
        () => editorRuntime.raster,
        throwsA(isA<UnsupportedOperationException>()),
      );
      await expectLater(
        editorRuntime.loadDocument(_documentId),
        throwsA(isA<UnsupportedOperationException>()),
      );
    },
  );

  test('the evidence label is a deterministic build-mode label', () {
    expect(editorEvidenceClass(debugMode: true), 'emulator');
    expect(editorEvidenceClass(debugMode: false), 'device');
  });
}
