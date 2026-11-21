// T071B editor touch move/resize composition host tests.
//
// Evidence class: NONE. These are host-VM widget tests with injected fake
// ports and an in-memory store. They construct no platform channel, open no
// PDF, start no browser, emulator, or device, and make no Android runtime,
// screen-reader, or visual claim. Real Android touch acceptance stays T071.
//
// They prove the composed T071B behaviour of
// `contracts/editor-interactions.md` §4:
//   * a body drag on the selected confirmed field previews the move and
//     commits exactly one T066 `moveField` through the verified save path;
//   * a corner drag resizes from the opposite anchor with the 24 dp hit region
//     and the 4 × 4 pt minimum;
//   * no store write happens per frame, and the preview disappears with the
//     gesture;
//   * a pointer cancel discards the preview and commits nothing;
//   * a two-finger gesture pans/zooms the page and never edits geometry, and a
//     drag that starts outside the selected field still pans the page;
//   * the T067 `CommandHistory` entry makes undo restore the exact previous
//     rectangle.

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/page_view.dart' as viewer;
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart' hide PageView;
import 'package:flutter_test/flutter_test.dart';

const String _documentId = '5f0c3a52-3a6a-4f0b-9c2d-1b7e4d8a6c01';
const String _sourceId = '7b2d4c1e-5f3a-4b8c-8a9d-2e6f0c1b3d42';
const String _revisionId = '9a1b2c3d-4e5f-4a6b-8c7d-8e9f0a1b2c3d';
const String _savedRevisionId = '9a1b2c3d-4e5f-4a6b-8c7d-8e9f0a1b2c3e';
const String _fieldId = '11111111-1111-4111-8111-111111111111';
final String _sha256 = List<String>.filled(64, 'a').join();
final Uint8List _sourceBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

final CapabilityEvidence _noneEvidence = CapabilityEvidence(
  evidenceClass: EvidenceClass.none,
  adapterId: 'test.t071b.v1',
);

final CapabilityDescriptor _storeDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.secureStore,
  adapterId: 'test.t071b.store.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final CapabilityDescriptor _idsDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.ids,
  adapterId: 'test.t071b.ids.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final CapabilityDescriptor _clockDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.clock,
  adapterId: 'test.t071b.clock.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final DateTime _createdAt = DateTime.utc(2026, 11, 21, 8);
final DateTime _savedAt = DateTime.utc(2026, 11, 21, 10, 15);

const ValueKey<String> _editorPageViewKey = ValueKey<String>(
  'editor-page-view',
);

/// The selected field used by every gesture test, in page-display points.
const double _fieldLeft = 40;
const double _fieldTop = 60;
const double _fieldWidth = 120;
const double _fieldHeight = 90;

core.Rect _fieldRect() =>
    core.Rect.fromLTWH(_fieldLeft, _fieldTop, _fieldWidth, _fieldHeight);

core.Page _page() {
  return core.Page(
    index: 0,
    geometry: core.PageGeometry(mediaBox: core.Rect.fromLTWH(0, 0, 300, 300)),
    analysis: core.AnalysisState.complete,
  );
}

core.ConfirmedField _field() {
  return core.ConfirmedField(
    id: _fieldId,
    pageIndex: 0,
    rect: _fieldRect(),
    type: core.FieldType.text,
    provenance: core.Provenance.user,
    label: 'Name',
    order: 0,
    createdAt: _createdAt,
    updatedAt: _createdAt,
  );
}

core.RevisionContent _content() {
  return core.RevisionContent(
    pages: <core.Page>[_page()],
    suggestions: const <core.FieldSuggestion>[],
    fields: <core.ConfirmedField>[_field()],
    fieldOrder: <String>[_fieldId],
  );
}

LoadedDocument _loaded() {
  return LoadedDocument(
    meta: core.DocumentMeta(
      id: _documentId,
      title: 'Testdokument',
      createdAt: _createdAt,
      updatedAt: _createdAt,
      source: core.SourceFileRef(
        id: _sourceId,
        sha256: _sha256,
        sizeBytes: _sourceBytes.length,
        pageCount: 1,
        importedAt: _createdAt,
      ),
      latestRevisionId: _revisionId,
      lastDurableAt: _createdAt,
    ),
    content: _content(),
    sourceBytes: _sourceBytes,
    evidence: _noneEvidence,
  );
}

ImportedSource _source() {
  return ImportedSource(
    documentId: _documentId,
    sourceId: _sourceId,
    sha256: _sha256,
    sizeBytes: _sourceBytes.length,
    pageCount: 1,
    pages: <core.PageGeometry>[
      core.PageGeometry(mediaBox: core.Rect.fromLTWH(0, 0, 300, 300)),
    ],
    evidence: _noneEvidence,
  );
}

StoredMeta _storedMeta() {
  return StoredMeta(
    id: _documentId,
    kind: StoreKind.document,
    title: 'Testdokument',
    createdAt: _createdAt,
    updatedAt: _createdAt,
    latestRevisionId: _revisionId,
    lastDurableAt: _createdAt,
  );
}

final class _FakeStore implements SecureStorePort {
  _FakeStore({required this.loaded});

  LoadedDocument loaded;
  final List<SaveRevisionRequest> saves = <SaveRevisionRequest>[];
  final List<String?> savedHeads = <String?>[];

  @override
  CapabilityDescriptor get descriptor => _storeDescriptor;

  @override
  Future<List<StoredMeta>> list(StoreKind kind) async {
    if (kind == StoreKind.template) {
      return const <StoredMeta>[];
    }
    return <StoredMeta>[_storedMeta()];
  }

  @override
  Future<LoadedDocument> loadDocument(String documentId) async {
    if (documentId != loaded.meta.id) {
      throw KeyUnavailableException();
    }
    return loaded;
  }

  @override
  Future<StoredMeta> saveRevision(SaveRevisionRequest request) async {
    saves.add(request);
    savedHeads.add(request.expectedHead);
    final core.DocumentMeta meta = loaded.meta.copyWith(
      updatedAt: _savedAt,
      latestRevisionId: _savedRevisionId,
      lastDurableAt: _savedAt,
    );
    loaded = LoadedDocument(
      meta: meta,
      content: request.content,
      sourceBytes: loaded.sourceBytes,
      evidence: loaded.evidence,
    );
    return StoredMeta(
      id: request.documentId,
      kind: StoreKind.document,
      title: meta.title,
      createdAt: meta.createdAt,
      updatedAt: meta.updatedAt,
      latestRevisionId: _savedRevisionId,
      lastDurableAt: _savedAt,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedOperationException();
  }
}

final class _UnavailableRaster implements PageRasterPort {
  @override
  CapabilityDescriptor get descriptor => throw UnsupportedOperationException();

  @override
  Future<core.PageGeometry> pageDimensions(String sourceId, int pageIndex) {
    throw UnsupportedOperationException();
  }

  @override
  Future<RasterImage> renderPage(RasterRequest request) {
    throw UnsupportedOperationException();
  }

  @override
  Future<void> evict(String sourceId) async {}
}

final class _FakeIds implements IdPort {
  int _calls = 0;

  @override
  CapabilityDescriptor get descriptor => _idsDescriptor;

  @override
  String newId() {
    _calls++;
    final String suffix = _calls.toString().padLeft(12, '0');
    return '9a1b2c3d-4e5f-4a6b-8c7d-$suffix';
  }

  @override
  String newIdempotencyKey() => newId();
}

final class _FakeClock implements ClockPort {
  DateTime now = _savedAt;

  @override
  CapabilityDescriptor get descriptor => _clockDescriptor;

  @override
  DateTime nowUtc() => now;
}

final class _FakeEditorRuntime implements EditorRuntime {
  _FakeEditorRuntime(this.fakeStore);

  final _FakeStore fakeStore;

  @override
  PageRasterPort get raster => _UnavailableRaster();

  @override
  OcrPort? get ocr => null;

  @override
  SecureStorePort get store => fakeStore;

  @override
  IdPort get ids => _FakeIds();

  @override
  ClockPort get clock => _FakeClock();

  @override
  Future<LoadedDocument> loadDocument(String documentId) {
    return fakeStore.loadDocument(documentId);
  }

  @override
  Future<StoredMeta> saveRevision(SaveRevisionRequest request) {
    return fakeStore.saveRevision(request);
  }

  @override
  Future<void> dispose() async {}
}

final class _FakePageRenderer implements viewer.PageViewRenderer {
  @override
  int get pageCount => 1;

  @override
  Widget buildPage(
    BuildContext context,
    int pageIndex, {
    required ValueChanged<viewer.PageViewLoadException> onFailure,
  }) {
    return ColoredBox(
      key: ValueKey<String>('fake-page-$pageIndex'),
      color: const Color(0xFF00FF00),
    );
  }

  @override
  Future<void> dispose() async {}
}

Future<viewer.PageViewRenderer> _renderer(Uint8List bytes) async {
  return _FakePageRenderer();
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required _FakeEditorRuntime runtime,
}) async {
  // A tall surface keeps the whole 300 × 300 pt test page inside the page
  // viewport, so every gesture point below is a real on-page touch point.
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const <Locale>[Locale('de')],
      home: EditorScreen(
        source: _source(),
        sourceBytes: (String _) async => _sourceBytes,
        runtime: runtime,
        rendererFactory: _renderer,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

EditorScreenState _state(WidgetTester tester) {
  return tester.state<EditorScreenState>(find.byType(EditorScreen));
}

/// The screen point of one page-display point of page 0.
Offset _screenPoint(
  WidgetTester tester,
  EditorScreenState state,
  Offset displayPoint,
) {
  final viewer.PageViewMapping mapping = state.viewController.mappingFor(0);
  final Offset local = mapping.displayToView(displayPoint);
  return tester.getTopLeft(find.byKey(_editorPageViewKey)) + local;
}

/// Selects the only confirmed field without opening a value sheet.
Future<void> _selectField(WidgetTester tester, EditorScreenState state) async {
  state.selection.select(_fieldId);
  await tester.pumpAndSettle();
}

core.Rect _storedRect(EditorScreenState state) =>
    state.content!.fields.single.rect;

/// Starts a drag on [displayPoint] and crosses the pan slop once.
///
/// The claimed drag is measured from the touch-down point, so every later
/// cumulative delta in a test is the sum of the moves it performs.
Future<TestGesture> _startDrag(
  WidgetTester tester,
  EditorScreenState state,
  Offset displayPoint, {
  Offset firstMove = const Offset(60, 0),
}) async {
  final TestGesture gesture = await tester.startGesture(
    _screenPoint(tester, state, displayPoint),
  );
  await gesture.moveBy(firstMove);
  await tester.pump();
  return gesture;
}

void main() {
  testWidgets('a body drag previews, saves once, and commits the exact move', (
    WidgetTester tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);
    await _selectField(tester, state);
    final double scale = state.viewController.mappingFor(0).scale;
    const Offset centre = Offset(
      _fieldLeft + _fieldWidth / 2,
      _fieldTop + _fieldHeight / 2,
    );

    final TestGesture gesture = await _startDrag(tester, state, centre);
    expect(state.geometryGestureActive, isTrue);
    expect(
      find.byKey(const ValueKey<String>('field-geometry-preview')),
      findsWidgets,
      reason: 'the geometry preview must be painted during the gesture',
    );
    expect(store.saves, isEmpty, reason: 'no per-frame store save');

    // Second cumulative move: 24 × 18 pt at the current scale.
    await gesture.moveBy(Offset(24 * scale, 18 * scale));
    await tester.pump();
    expect(
      store.saves,
      isEmpty,
      reason: 'preview updates never write the store',
    );
    expect(
      _storedRect(state),
      _fieldRect(),
      reason: 'the stored rectangle is untouched during the gesture',
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(store.saves, hasLength(1));
    expect(state.geometryGestureActive, isFalse);
    final core.Rect expected = core.Rect.fromLTWH(
      _fieldLeft + 60 / scale + 24,
      _fieldTop + 18,
      _fieldWidth,
      _fieldHeight,
    );
    final core.Rect stored = _storedRect(state);
    expect(stored.left, closeTo(expected.left, 1e-6));
    expect(stored.top, closeTo(expected.top, 1e-6));
    expect(stored.width, _fieldWidth);
    expect(stored.height, _fieldHeight);
    expect(state.canUndoReview, isTrue);
    expect(state.durabilityStatus, isA<core.DurabilityStatus>());
  });

  testWidgets('a corner drag resizes from the opposite anchor with one save', (
    WidgetTester tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);
    await _selectField(tester, state);
    final double scale = state.viewController.mappingFor(0).scale;

    final TestGesture gesture = await _startDrag(
      tester,
      state,
      const Offset(_fieldLeft + _fieldWidth, _fieldTop + _fieldHeight),
    );
    expect(state.geometryGestureActive, isTrue);
    await gesture.moveBy(Offset(30 * scale, 20 * scale));
    await tester.pump();
    expect(store.saves, isEmpty);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(store.saves, hasLength(1));
    final core.Rect stored = _storedRect(state);
    expect(stored.left, _fieldLeft);
    expect(stored.top, _fieldTop);
    expect(stored.width, closeTo(_fieldWidth + 30 + 60 / scale, 1e-6));
    expect(stored.height, closeTo(_fieldHeight + 20, 1e-6));
  });

  testWidgets('undo restores the exact previous rectangle', (
    WidgetTester tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);
    await _selectField(tester, state);

    final TestGesture gesture = await _startDrag(
      tester,
      state,
      const Offset(_fieldLeft + _fieldWidth / 2, _fieldTop + _fieldHeight / 2),
      firstMove: const Offset(0, 60),
    );
    await gesture.moveBy(const Offset(20, 10));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(store.saves, hasLength(1));
    expect(_storedRect(state), isNot(_fieldRect()));

    final Finder undoFinder = find.byKey(const ValueKey<String>(undoReviewKey));
    expect(undoFinder, findsOneWidget);
    await tester.tap(undoFinder);
    await tester.pumpAndSettle();

    expect(store.saves, hasLength(2));
    final core.Rect restored = _storedRect(state);
    expect(restored.left, _fieldLeft);
    expect(restored.top, _fieldTop);
    expect(restored.width, _fieldWidth);
    expect(restored.height, _fieldHeight);
    expect(restored, _fieldRect());
    expect(state.canUndoReview, isFalse);
    expect(state.selection.selectedId, _fieldId);
  });

  testWidgets('a pointer cancel discards the preview and commits nothing', (
    WidgetTester tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);
    await _selectField(tester, state);

    final TestGesture gesture = await _startDrag(
      tester,
      state,
      const Offset(_fieldLeft + _fieldWidth / 2, _fieldTop + _fieldHeight / 2),
    );
    await gesture.moveBy(const Offset(30, 20));
    await tester.pump();
    expect(state.geometryGestureActive, isTrue);

    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(state.geometryGestureActive, isFalse);
    expect(store.saves, isEmpty);
    expect(_storedRect(state), _fieldRect());
    expect(state.canUndoReview, isFalse);
  });

  testWidgets('two fingers pan and zoom the page and never edit geometry', (
    WidgetTester tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);
    await _selectField(tester, state);
    final double initialScale = state.viewController.scale;
    const Offset centre = Offset(
      _fieldLeft + _fieldWidth / 2,
      _fieldTop + _fieldHeight / 2,
    );

    final TestGesture first = await _startDrag(tester, state, centre);
    expect(state.geometryGestureActive, isTrue);

    final TestGesture second = await tester.startGesture(
      _screenPoint(tester, state, centre + const Offset(0, 60)),
    );
    await tester.pump();
    await first.moveBy(const Offset(-40, -40));
    await second.moveBy(const Offset(40, 40));
    await tester.pump();
    // The second pointer cancelled the geometry claim before it could commit.
    expect(state.geometryGestureActive, isFalse);

    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    expect(store.saves, isEmpty);
    expect(_storedRect(state), _fieldRect());
    expect(
      state.viewController.scale,
      greaterThan(initialScale),
      reason: 'a two-finger gesture must keep zooming the page',
    );
  });

  testWidgets('a drag outside the selected field still pans the page', (
    WidgetTester tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);
    await _selectField(tester, state);
    // Zoom in first: at fit-width the whole page is visible and the view
    // transform is clamped, so a pan could not be observed.
    state.viewController.setView(
      scale: state.viewController.scale * 1.5,
      pan: Offset.zero,
      clampToViewport: true,
    );
    await tester.pumpAndSettle();
    final Offset initialPan = state.viewController.pan;

    // Page-display (190, 200) is inside the page, outside the field, and
    // still inside the viewport at the zoomed-in view transform.
    final TestGesture gesture = await _startDrag(
      tester,
      state,
      const Offset(190, 200),
      firstMove: const Offset(-60, -60),
    );
    expect(state.geometryGestureActive, isFalse);
    await gesture.moveBy(const Offset(-30, -10));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(store.saves, isEmpty);
    expect(_storedRect(state), _fieldRect());
    expect(state.viewController.pan, isNot(initialPan));
  });
}
