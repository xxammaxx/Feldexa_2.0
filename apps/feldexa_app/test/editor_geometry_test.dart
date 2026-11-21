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
//   * a two-finger gesture pans/zooms the page and never edits geometry, a drag
//     that starts outside the selected field still pans the page, and lifting
//     one finger of a pinch cannot re-arm a geometry claim: the remaining
//     finger keeps panning and a cancelled claim never commits (B1 correction);
//   * the geometry preview stays painted until the gesture's commit resolves
//     (F4 correction);
//   * the T067 `CommandHistory` entry makes undo restore the exact previous
//     rectangle;
//   * a value edit is recorded as its own T067 entry, so undo after
//     confirm → value edit reverses only the value and never drops the
//     confirmed field (B2 correction);
//   * an undo whose newest entry no longer matches the visible content is
//     refused instead of dropping newer content (B2 correction, guard branch).

@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/field_value_sheet.dart';
import 'package:feldexa_app/features/fill/text_control.dart';
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

/// The unresolved-suggestion fixture used by the undo-history regression.
const String _suggestionId = 's_p0_0001';

core.Rect _suggestionRect() => core.Rect.fromLTWH(40, 20, 100, 20);

core.FieldSuggestion _suggestion() {
  return core.FieldSuggestion(
    id: _suggestionId,
    pageIndex: 0,
    rect: _suggestionRect(),
    proposedType: core.FieldType.text,
    confidence: 0.6,
    labelText: 'Vorschlag',
    evidence: core.SuggestionEvidence(
      cues: const <core.SuggestionCue>[core.SuggestionCue.underline],
      ocrUsed: false,
    ),
  );
}

core.RevisionContent _content({
  bool withField = true,
  bool withSuggestion = false,
}) {
  final List<core.ConfirmedField> fields = withField
      ? <core.ConfirmedField>[_field()]
      : const <core.ConfirmedField>[];
  return core.RevisionContent(
    pages: <core.Page>[_page()],
    suggestions: withSuggestion
        ? <core.FieldSuggestion>[_suggestion()]
        : const <core.FieldSuggestion>[],
    fields: fields,
    fieldOrder: <String>[
      for (final core.ConfirmedField field in fields) field.id,
    ],
  );
}

LoadedDocument _loaded({core.RevisionContent? content}) {
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
    content: content ?? _content(),
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
  _FakeStore({required this.loaded, this.saveGate});

  LoadedDocument loaded;

  /// Optional gate that holds the next [saveRevision] open, so a test can
  /// observe the editor while one commit is still in flight.
  Completer<void>? saveGate;
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
    final Completer<void>? gate = saveGate;
    if (gate != null) {
      saveGate = null;
      await gate.future;
    }
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

  /// The single clock instance of this runtime, so a test can advance it and
  /// make consecutive commands strictly monotonic (or deliberately not).
  final _FakeClock fakeClock = _FakeClock();

  @override
  PageRasterPort get raster => _UnavailableRaster();

  @override
  OcrPort? get ocr => null;

  @override
  SecureStorePort get store => fakeStore;

  @override
  IdPort get ids => _FakeIds();

  @override
  ClockPort get clock => fakeClock;

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
    expect(
      find.byKey(const ValueKey<String>('field-geometry-preview')),
      findsNothing,
      reason: 'the preview is transient and must not outlive the gesture',
    );
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

  testWidgets(
    'lifting one finger of a pinch does not re-arm the geometry claim',
    (WidgetTester tester) async {
      final _FakeStore store = _FakeStore(loaded: _loaded());
      final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
      await _pumpEditor(tester, runtime: runtime);
      final EditorScreenState state = _state(tester);
      await _selectField(tester, state);
      // Zoom in first: at fit-width the page fits the viewport and the pan is
      // clamped, so a page pan would not be observable.
      state.viewController.setView(
        scale: state.viewController.scale * 1.5,
        pan: Offset.zero,
        clampToViewport: true,
      );
      await tester.pumpAndSettle();
      final double initialScale = state.viewController.scale;
      const Offset centre = Offset(
        _fieldLeft + _fieldWidth / 2,
        _fieldTop + _fieldHeight / 2,
      );
      final Finder preview = find.byKey(
        const ValueKey<String>('field-geometry-preview'),
      );

      // One-finger geometry drag, then a second finger cancels the claim.
      final TestGesture first = await _startDrag(tester, state, centre);
      expect(state.geometryGestureActive, isTrue);
      final TestGesture second = await tester.startGesture(
        _screenPoint(tester, state, centre + const Offset(0, 60)),
      );
      await tester.pump();
      expect(
        state.geometryGestureActive,
        isFalse,
        reason: 'a second pointer cancels the geometry claim',
      );
      expect(preview, findsNothing);

      // Two-finger pan/zoom must continue normally after the cancellation.
      await first.moveBy(const Offset(-30, -30));
      await second.moveBy(const Offset(30, 30));
      await tester.pump();
      expect(
        state.viewController.scale,
        greaterThan(initialScale),
        reason: 'the page still zooms with two pointers',
      );

      // Lift the second finger and keep moving the remaining one: the claim
      // must stay suppressed for the whole pointer sequence, not just until
      // the next one-pointer onScaleStart, and the page must keep panning.
      await second.up();
      await tester.pump();
      final Offset panAfterPinch = state.viewController.pan;
      // The first move after the pointer-set change only re-baselines the pan:
      // the recognizer restarts and dispatches onScaleStart and onScaleUpdate for
      // the same focal point. The second move pans the page.
      await first.moveBy(const Offset(-20, -20));
      await tester.pump();
      await first.moveBy(const Offset(-40, -40));
      await tester.pump();

      expect(
        state.geometryGestureActive,
        isFalse,
        reason: 'a cancelled pinch must not re-arm geometry after one lift',
      );
      expect(preview, findsNothing);
      expect(
        state.viewController.pan,
        isNot(panAfterPinch),
        reason: 'the remaining finger still pans the page',
      );

      await first.up();
      await tester.pumpAndSettle();

      expect(store.saves, isEmpty);
      expect(_storedRect(state), _fieldRect());

      // A brand-new single-pointer gesture may claim again.
      final TestGesture fresh = await _startDrag(tester, state, centre);
      expect(state.geometryGestureActive, isTrue);
      await fresh.cancel();
      await tester.pumpAndSettle();
      expect(store.saves, isEmpty);
    },
  );

  testWidgets('the geometry preview stays visible until the commit resolves', (
    WidgetTester tester,
  ) async {
    final Completer<void> gate = Completer<void>();
    final _FakeStore store = _FakeStore(loaded: _loaded(), saveGate: gate);
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);
    await _selectField(tester, state);
    final Finder preview = find.byKey(
      const ValueKey<String>('field-geometry-preview'),
    );

    final TestGesture gesture = await _startDrag(
      tester,
      state,
      const Offset(_fieldLeft + _fieldWidth / 2, _fieldTop + _fieldHeight / 2),
    );
    await gesture.up();
    await tester.pump();

    // The gesture is over (one save in flight) but the stored content has not
    // changed yet: the preview must stay painted so the field does not snap
    // back to its previous rectangle.
    expect(state.geometryGestureActive, isFalse);
    expect(store.saves, hasLength(1));
    expect(_storedRect(state), _fieldRect());
    expect(preview, findsOneWidget);
    final core.Rect committed = store.saves.single.content.fields.single.rect;
    expect(
      committed,
      isNot(_fieldRect()),
      reason: 'the pending commit carries the dragged rectangle',
    );

    gate.complete();
    await tester.pumpAndSettle();

    expect(store.saves, hasLength(1));
    expect(preview, findsNothing);
    expect(
      _storedRect(state),
      core.Rect.fromLTWH(
        committed.left,
        committed.top,
        committed.width,
        committed.height,
      ),
    );
  });

  testWidgets(
    'undo refuses a stale snapshot instead of dropping newer content',
    (WidgetTester tester) async {
      final _FakeStore store = _FakeStore(
        loaded: _loaded(
          content: _content(withField: false, withSuggestion: true),
        ),
      );
      final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
      await _pumpEditor(tester, runtime: runtime);
      final EditorScreenState state = _state(tester);
      final AppLocalizations de = lookupAppLocalizations(const Locale('de'));

      // 1) Confirm the suggestion: one durable revision and one undo step.
      await tester.tap(
        find.byKey(
          const ValueKey<String>('$confirmSuggestionKeyPrefix$_suggestionId'),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.saves, hasLength(1));
      final String confirmedId = state.content!.fields.single.id;

      // 2) A value edit whose history record is rejected (the clock moved
      //    backwards, so the command is older than the newest entry) still
      //    persists durably. That is exactly the unrecorded mutation class the
      //    undo guard must survive.
      runtime.fakeClock.now = _savedAt.subtract(const Duration(seconds: 1));
      final core.Rect suggestion = _suggestionRect();
      await tester.tapAt(
        _screenPoint(
          tester,
          state,
          Offset(
            suggestion.left + suggestion.width / 2,
            suggestion.top + suggestion.height / 2,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(fieldValueSheetKey), findsOneWidget);
      await tester.enterText(find.byKey(fieldTextControlInputKey), 'Hallo');
      await tester.tap(find.byKey(fieldValueSaveKey));
      await tester.pumpAndSettle();
      expect(store.saves, hasLength(2));
      expect(
        (state.content!.values[confirmedId]! as core.TextValue).text,
        'Hallo',
      );

      // 3) Undo: the newest entry no longer describes the visible content, so
      //    the reversal is refused instead of writing a revision that drops
      //    the field or the value.
      await tester.tap(find.byKey(const ValueKey<String>(undoReviewKey)));
      await tester.pumpAndSettle();

      expect(
        store.saves,
        hasLength(2),
        reason: 'a refused undo writes no revision',
      );
      expect(find.text(de.save006), findsOneWidget);
      expect(
        state.content!.fields.map((core.ConfirmedField field) => field.id),
        <String>[confirmedId],
        reason: 'the confirmed field must survive the refused undo',
      );
      expect(
        (state.content!.values[confirmedId]! as core.TextValue).text,
        'Hallo',
        reason: 'the newer value must survive the refused undo',
      );
      expect(
        state.canUndoReview,
        isTrue,
        reason: 'the refused entry is re-armed, not lost',
      );
    },
  );

  testWidgets(
    'undo after a value edit keeps the field and reverses only the value',
    (WidgetTester tester) async {
      final _FakeStore store = _FakeStore(
        loaded: _loaded(
          content: _content(withField: false, withSuggestion: true),
        ),
      );
      final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
      await _pumpEditor(tester, runtime: runtime);
      final EditorScreenState state = _state(tester);

      // 1) Confirm the suggestion: one durable revision and one undo step.
      await tester.tap(
        find.byKey(
          const ValueKey<String>('$confirmSuggestionKeyPrefix$_suggestionId'),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.saves, hasLength(1));
      expect(state.content!.fields, hasLength(1));
      final String confirmedId = state.content!.fields.single.id;
      expect(state.canUndoReview, isTrue);

      // 2) Edit the value through the sheet: a second durable revision. The
      //    clock advances so the value edit is its own strictly newer T067
      //    entry instead of relying on equal timestamps.
      runtime.fakeClock.now = _savedAt.add(const Duration(seconds: 1));
      final core.Rect suggestion = _suggestionRect();
      await tester.tapAt(
        _screenPoint(
          tester,
          state,
          Offset(
            suggestion.left + suggestion.width / 2,
            suggestion.top + suggestion.height / 2,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(fieldValueSheetKey), findsOneWidget);
      await tester.enterText(find.byKey(fieldTextControlInputKey), 'Hallo');
      await tester.tap(find.byKey(fieldValueSaveKey));
      await tester.pumpAndSettle();
      expect(store.saves, hasLength(2));
      final core.FieldValue? typed = state.content!.values[confirmedId];
      expect(typed, isA<core.TextValue>());
      expect((typed! as core.TextValue).text, 'Hallo');

      // 3) Undo: only the newest entry (the value edit) is reversed. The
      //    confirmed field must survive and no revision may drop it.
      await tester.tap(find.byKey(const ValueKey<String>(undoReviewKey)));
      await tester.pumpAndSettle();

      expect(store.saves, hasLength(3));
      expect(
        state.content!.fields.map((core.ConfirmedField field) => field.id),
        <String>[confirmedId],
        reason: 'undo must not drop the confirmed field',
      );
      expect(
        store.saves.last.content.fields.map(
          (core.ConfirmedField field) => field.id,
        ),
        <String>[confirmedId],
        reason: 'the written revision must keep the confirmed field',
      );
      expect(
        state.content!.values.containsKey(confirmedId),
        isFalse,
        reason: 'undo reverses the value edit back to the pre-edit state',
      );
      expect(
        state.content!.suggestions.single.resolution,
        core.SuggestionResolution.confirmed,
        reason: 'the older confirmation is untouched',
      );
      expect(state.canUndoReview, isTrue);

      // 4) The older confirmation entry is still undoable and removes the
      //    field only now, exactly once.
      await tester.tap(find.byKey(const ValueKey<String>(undoReviewKey)));
      await tester.pumpAndSettle();
      expect(store.saves, hasLength(4));
      expect(store.saves.last.content.fields, isEmpty);
      expect(state.content!.fields, isEmpty);
      expect(state.canUndoReview, isFalse);
    },
  );

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
