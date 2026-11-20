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
//   * a page failure is isolated while the healthy page is saved;
//   * the viewer and strip are available while analysis is still running;
//   * a save failure keeps the viewer and the in-memory result;
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

core.PageGeometry _geometry() {
  return core.PageGeometry(
    mediaBox: core.Rect.fromLTWH(0, 0, _pageWidthPt, _pageHeightPt),
  );
}

core.RevisionContent _initialContent({int pageCount = 1}) {
  return core.RevisionContent(
    pages: <core.Page>[
      for (int index = 0; index < pageCount; index++)
        core.Page(index: index, geometry: _geometry()),
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

ImportedSource _source({int pageCount = 1}) {
  return ImportedSource(
    documentId: _documentId,
    sourceId: _sourceId,
    sha256: _sha256,
    sizeBytes: _sourceBytes.length,
    pageCount: pageCount,
    pages: <core.PageGeometry>[
      for (int index = 0; index < pageCount; index++) _geometry(),
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
final class _FakeStore implements SecureStorePort {
  _FakeStore({required this.loaded, this.saveError});

  final LoadedDocument loaded;
  final Object? saveError;
  int loads = 0;
  final List<SaveRevisionRequest> saves = <SaveRevisionRequest>[];

  @override
  CapabilityDescriptor get descriptor => _storeDescriptor;

  @override
  Future<LoadedDocument> loadDocument(String documentId) async {
    loads++;
    return loaded;
  }

  @override
  Future<StoredMeta> saveRevision(SaveRevisionRequest request) async {
    saves.add(request);
    if (saveError != null) {
      throw saveError!;
    }
    return StoredMeta(
      id: request.documentId,
      kind: StoreKind.document,
      title: 'Testdokument',
      createdAt: DateTime.utc(2026, 11, 20),
      updatedAt: DateTime.utc(2026, 11, 20),
      latestRevisionId: _revisionId,
      readable: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
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

final class _FakeEditorRuntime implements EditorRuntime {
  _FakeEditorRuntime({
    required this.raster,
    required this.ocr,
    required this.store,
    _FakeIds? ids,
  }) : ids = ids ?? _FakeIds();

  @override
  final PageRasterPort raster;

  @override
  final OcrPort? ocr;

  @override
  final SecureStorePort store;

  @override
  final IdPort ids;

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

  Future<PageViewRenderer> call(Uint8List bytes) async {
    calls++;
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

  test('the evidence label is a deterministic build-mode label', () {
    expect(editorEvidenceClass(debugMode: true), 'emulator');
    expect(editorEvidenceClass(debugMode: false), 'device');
  });
}
