// T071A editor composition host tests.
//
// Evidence class: NONE. These are host-VM widget tests with injected fake
// ports and an in-memory store. They construct no platform channel, open no
// PDF, start no browser, emulator, or device, and make no Android runtime,
// screen-reader, or visual claim.
//
// They prove the T071A composition:
//   * the `PageView` overlay hook receives the visible page index, its viewport
//     rectangle, and the current mapping, without changing page rendering;
//   * the editor builds per-page T069 overlays from confirmed fields and
//     unresolved suggestions, taps a confirmed field to open the type-correct
//     sheet, taps a suggestion without inventing a value, and clears on empty;
//   * a value save uses `setFieldValue`, saves with `expectedHead`, updates the
//     content/head/durability status only after the verified commit, and a
//     failed save keeps the sheet open with `saveFailed(SAVE-003)`;
//   * the T095 start list loads stored documents through the runtime store,
//     opens a readable document, re-reads the list after return, and refuses
//     an unreadable entry;
//   * barrier taps, drag-down, and system back on the value sheet are cancels:
//     they save nothing, never pop the editor, and the focus-loss commit still
//     works while the sheet is current;
//   * a save that completes after the sheet route is gone does not pop the
//     next route (the deterministic F7-R1 race);
//   * 200 % text scale composes the editor and the value sheet without a
//     RenderFlex overflow.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:feldexa_app/features/editor/durability_status.dart';
import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/field_value_sheet.dart';
import 'package:feldexa_app/features/editor/page_view.dart' as viewer;
import 'package:feldexa_app/features/fill/text_control.dart';
import 'package:feldexa_app/features/start/import_runtime.dart';
import 'package:feldexa_app/features/start/start_screen.dart';
import 'package:feldexa_app/features/start/stored_items.dart';
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
const String _unreadableDocumentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
final String _sha256 = List<String>.filled(64, 'a').join();
final Uint8List _sourceBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

final CapabilityEvidence _noneEvidence = CapabilityEvidence(
  evidenceClass: EvidenceClass.none,
  adapterId: 'test.t071a.v1',
);

final CapabilityDescriptor _storeDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.secureStore,
  adapterId: 'test.t071a.store.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final CapabilityDescriptor _idsDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.ids,
  adapterId: 'test.t071a.ids.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final CapabilityDescriptor _clockDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.clock,
  adapterId: 'test.t071a.clock.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final CapabilityDescriptor _importDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.documentImport,
  adapterId: 'test.t071a.import.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final DateTime _createdAt = DateTime.utc(2026, 11, 20, 8);
final DateTime _savedAt = DateTime.utc(2026, 11, 21, 10, 15);

final AppLocalizations _de = lookupAppLocalizations(const Locale('de'));

const ValueKey<String> _editorPageViewKey = ValueKey<String>(
  'editor-page-view',
);

core.Rect _fieldRect() => core.Rect.fromLTWH(40, 60, 100, 30);
core.Rect _suggestionRect() => core.Rect.fromLTWH(40, 20, 100, 20);

core.Page _page() {
  return core.Page(
    index: 0,
    geometry: core.PageGeometry(mediaBox: core.Rect.fromLTWH(0, 0, 300, 300)),
    analysis: core.AnalysisState.complete,
  );
}

core.ConfirmedField _field([core.FieldType type = core.FieldType.text]) {
  return core.ConfirmedField(
    id: _fieldId,
    pageIndex: 0,
    rect: _fieldRect(),
    type: type,
    provenance: core.Provenance.user,
    label: 'Name',
    order: 0,
    createdAt: _createdAt,
    updatedAt: _createdAt,
  );
}

core.FieldSuggestion _suggestion() {
  return core.FieldSuggestion(
    id: 's_p0_0001',
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
  core.FieldType fieldType = core.FieldType.text,
  core.FieldValue? value,
}) {
  final List<core.ConfirmedField> fields = withField
      ? <core.ConfirmedField>[_field(fieldType)]
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
    values: value == null
        ? const <String, core.FieldValue>{}
        : <String, core.FieldValue>{_fieldId: value},
  );
}

LoadedDocument _loaded({
  core.RevisionContent? content,
  String title = 'Testdokument',
}) {
  return LoadedDocument(
    meta: core.DocumentMeta(
      id: _documentId,
      title: title,
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

final class _FakeStore implements SecureStorePort {
  _FakeStore({required this.loaded, this.saveError, this.documents});

  LoadedDocument loaded;
  final Object? saveError;
  final List<StoredMeta>? documents;
  Completer<StoredMeta>? saveGate;
  int listCalls = 0;
  int loads = 0;
  final List<SaveRevisionRequest> saves = <SaveRevisionRequest>[];

  @override
  CapabilityDescriptor get descriptor => _storeDescriptor;

  @override
  Future<List<StoredMeta>> list(StoreKind kind) async {
    listCalls++;
    if (kind == StoreKind.template) {
      return const <StoredMeta>[];
    }
    return documents ?? <StoredMeta>[_storedMeta()];
  }

  @override
  Future<LoadedDocument> loadDocument(String documentId) async {
    loads++;
    if (documentId != loaded.meta.id) {
      throw KeyUnavailableException();
    }
    return loaded;
  }

  @override
  Future<StoredMeta> saveRevision(SaveRevisionRequest request) async {
    saves.add(request);
    if (saveError != null) {
      throw saveError!;
    }
    final Completer<StoredMeta>? gate = saveGate;
    if (gate != null) {
      await gate.future;
    }
    final core.DocumentMeta meta = core.DocumentMeta(
      id: loaded.meta.id,
      title: loaded.meta.title,
      createdAt: loaded.meta.createdAt,
      updatedAt: _savedAt,
      source: loaded.meta.source,
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
  @override
  CapabilityDescriptor get descriptor => _idsDescriptor;

  @override
  String newId() => _savedRevisionId;

  @override
  String newIdempotencyKey() => _savedRevisionId;
}

final class _FakeClock implements ClockPort {
  @override
  CapabilityDescriptor get descriptor => _clockDescriptor;

  @override
  DateTime nowUtc() => _savedAt;
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

  bool disposed = false;

  @override
  Future<LoadedDocument> loadDocument(String documentId) {
    return fakeStore.loadDocument(documentId);
  }

  @override
  Future<StoredMeta> saveRevision(SaveRevisionRequest request) {
    return fakeStore.saveRevision(request);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

final class _FakeImportPort implements DocumentImportPort {
  @override
  CapabilityDescriptor get descriptor => _importDescriptor;

  @override
  Future<ImportedSource> pickAndImport(ImportRequest request) {
    throw UnsupportedOperationException();
  }

  @override
  Future<SourceIntegrity> verifySource(String sourceId) {
    throw UnsupportedOperationException();
  }
}

final class _FakePageRenderer implements viewer.PageViewRenderer {
  _FakePageRenderer(this.pageCount);

  @override
  final int pageCount;

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
  return _FakePageRenderer(1);
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required _FakeEditorRuntime runtime,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const <Locale>[Locale('de')],
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        );
      },
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

/// Pumps the real editor above a host route so an extra pop is observable.
///
/// The host route is the only route below the editor; a leaked
/// `Navigator.pop(true)` after the value sheet is dismissed would remove the
/// editor and reveal the host.
Future<GlobalKey<NavigatorState>> _pumpEditorOverHost(
  WidgetTester tester, {
  required _FakeEditorRuntime runtime,
}) async {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const <Locale>[Locale('de')],
      home: const Scaffold(body: Center(child: Text('Startseite'))),
    ),
  );
  unawaited(
    navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => EditorScreen(
          source: _source(),
          sourceBytes: (String _) async => _sourceBytes,
          runtime: runtime,
          rendererFactory: _renderer,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return navigatorKey;
}

void _expectEditorOverHost(GlobalKey<NavigatorState> navigatorKey) {
  expect(find.byType(EditorScreen), findsOneWidget);
  expect(find.text('Startseite'), findsNothing);
  expect(navigatorKey.currentState!.canPop(), isTrue);
}

Offset _screenPoint(
  WidgetTester tester,
  EditorScreenState state,
  core.Rect displayRect,
) {
  final viewer.PageViewMapping mapping = state.viewController.mappingFor(0);
  final Offset local = mapping.displayToView(
    Offset(
      displayRect.left + displayRect.width / 2,
      displayRect.top + displayRect.height / 2,
    ),
  );
  return tester.getTopLeft(find.byKey(_editorPageViewKey)) + local;
}

void main() {
  testWidgets(
    'PageView overlay builder receives page, viewport rect, mapping',
    (tester) async {
      final viewer.PageViewController controller = viewer.PageViewController(
        pages: <viewer.PageViewPageSize>[
          viewer.PageViewPageSize(widthPt: 100, heightPt: 30),
          viewer.PageViewPageSize(widthPt: 100, heightPt: 30),
        ],
      );
      final List<({int pageIndex, Rect rect, viewer.PageViewMapping mapping})>
      calls = <({int pageIndex, Rect rect, viewer.PageViewMapping mapping})>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: viewer.PageView(
              sourceId: 'overlay-source',
              sourceBytes: (String _) async => _sourceBytes,
              controller: controller,
              rendererFactory: (Uint8List bytes) async => _FakePageRenderer(2),
              overlayBuilder:
                  (int pageIndex, Rect rect, viewer.PageViewMapping mapping) {
                    calls.add((
                      pageIndex: pageIndex,
                      rect: rect,
                      mapping: mapping,
                    ));
                    return const SizedBox.expand();
                  },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(calls, isNotEmpty);
      final Set<int> pages = calls.map((record) => record.pageIndex).toSet();
      expect(pages, contains(0));
      for (final record in calls) {
        expect(
          record.rect,
          controller.mappingFor(record.pageIndex).pageRectInViewport,
        );
        expect(record.mapping.pageIndex, record.pageIndex);
        expect(record.mapping.pageSize.contentSize, const Size(100, 30));
        expect(record.rect.size, record.mapping.pageRectInViewport.size);
        expect(record.rect.left, greaterThanOrEqualTo(0));
      }

      controller.scrollToPage(1);
      await tester.pumpAndSettle();
      expect(calls.map((record) => record.pageIndex).toSet(), contains(1));
      final ({int pageIndex, Rect rect, viewer.PageViewMapping mapping})
      pageOne = calls.lastWhere((record) => record.pageIndex == 1);
      expect(pageOne.rect, controller.mappingFor(1).pageRectInViewport);
    },
  );

  testWidgets(
    'tapping a confirmed field selects it and opens its value sheet',
    (tester) async {
      final _FakeStore store = _FakeStore(loaded: _loaded());
      final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
      await _pumpEditor(tester, runtime: runtime);

      final EditorScreenState state = _state(tester);
      await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
      await tester.pumpAndSettle();

      expect(state.selection.selectedId, _fieldId);
      expect(find.byKey(fieldValueSheetKey), findsOneWidget);
      expect(find.byKey(fieldTextControlInputKey), findsOneWidget);
      expect(find.text('Name'), findsWidgets);

      await tester.tap(find.byKey(fieldValueCloseKey));
      await tester.pumpAndSettle();
      expect(find.byKey(fieldValueSheetKey), findsNothing);
    },
  );

  testWidgets('the value sheet lays out above the software keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);

    final EditorScreenState state = _state(tester);
    await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
    await tester.pumpAndSettle();

    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    const double keyboardTop = 600;
    final Rect sheetRect = tester.getRect(find.byKey(fieldValueSheetKey));
    expect(sheetRect.top, greaterThanOrEqualTo(0));
    expect(sheetRect.bottom, lessThanOrEqualTo(keyboardTop));
    final Rect saveRect = tester.getRect(find.byKey(fieldValueSaveKey));
    expect(saveRect.bottom, lessThanOrEqualTo(keyboardTop));
    expect(find.byKey(fieldTextControlInputKey), findsOneWidget);
  });

  testWidgets('tapping a suggestion highlights it without a value sheet', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(
      loaded: _loaded(
        content: _content(withField: false, withSuggestion: true),
      ),
    );
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);

    final EditorScreenState state = _state(tester);
    await tester.tapAt(_screenPoint(tester, state, _suggestionRect()));
    await tester.pumpAndSettle();

    expect(state.selection.selectedId, 's_p0_0001');
    expect(find.byKey(fieldValueSheetKey), findsNothing);

    await tester.tapAt(
      _screenPoint(tester, state, core.Rect.fromLTWH(270, 10, 4, 4)),
    );
    await tester.pumpAndSettle();
    expect(state.selection.selectedId, isNull);
  });

  testWidgets('an empty page still clears a stale selection', (tester) async {
    final _FakeStore store = _FakeStore(
      loaded: _loaded(
        content: _content(withField: false, withSuggestion: false),
      ),
    );
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);

    final EditorScreenState state = _state(tester);
    // A transient selection can outlive a page's items; the selection surface
    // must still be composed and clear it.
    state.selection.select('stale-selection');
    expect(state.selection.selectedId, 'stale-selection');

    await tester.tapAt(
      _screenPoint(tester, state, core.Rect.fromLTWH(270, 10, 4, 4)),
    );
    await tester.pumpAndSettle();
    expect(state.selection.selectedId, isNull);
  });

  testWidgets('invalid number input stays open and valid German is stored', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(
      loaded: _loaded(content: _content(fieldType: core.FieldType.number)),
    );
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);

    final EditorScreenState state = _state(tester);
    await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(fieldTextControlInputKey), 'keine Zahl');
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();
    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(find.text(_de.num001), findsOneWidget);
    expect(store.saves, isEmpty);
    expect(state.content!.values.containsKey(_fieldId), isFalse);

    await tester.enterText(find.byKey(fieldTextControlInputKey), '1.234,56');
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();
    expect(find.byKey(fieldValueSheetKey), findsNothing);
    final core.FieldValue? value = store.saves.single.content.values[_fieldId];
    expect(value, isA<core.NumberValue>());
    expect((value! as core.NumberValue).canonical, '1234.56');
    expect((value as core.NumberValue).rawGerman, '1.234,56');
  });

  testWidgets('impossible date keeps the sheet open and a real date saves', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(
      loaded: _loaded(content: _content(fieldType: core.FieldType.date)),
    );
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);

    final EditorScreenState state = _state(tester);
    await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(fieldTextControlInputKey), '31.02.2025');
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();
    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(find.text(_de.date002), findsOneWidget);
    expect(store.saves, isEmpty);

    await tester.enterText(find.byKey(fieldTextControlInputKey), '31.12.2025');
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();
    expect(find.byKey(fieldValueSheetKey), findsNothing);
    final core.FieldValue? value = store.saves.single.content.values[_fieldId];
    expect(value, isA<core.DateValue>());
    expect((value! as core.DateValue).canonical, '2025-12-31');
  });

  testWidgets('a verified save updates content, head, and durability status', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);

    final EditorScreenState state = _state(tester);
    await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(fieldTextControlInputKey),
      'Müller & Söhne',
    );
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();

    expect(find.byKey(fieldValueSheetKey), findsNothing);
    expect(store.saves, hasLength(1));
    final SaveRevisionRequest saved = store.saves.single;
    expect(saved.expectedHead, _revisionId);
    expect(saved.kind, core.RevisionKind.autosave);
    final core.FieldValue? value = saved.content.values[_fieldId];
    expect(value, isA<core.TextValue>());
    expect((value! as core.TextValue).text, 'Müller & Söhne');
    expect(state.content!.values[_fieldId], value);
    expect(state.headRevisionId, _savedRevisionId);
    expect(state.durabilityStatus, isA<core.SavedDurabilityStatus>());
    expect(
      (state.durabilityStatus as core.SavedDurabilityStatus).lastDurableAt,
      _savedAt,
    );
    expect(find.byKey(durabilityStatusLabelKey), findsOneWidget);
  });

  testWidgets('a failed save keeps the sheet open and claims no saved state', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(
      loaded: _loaded(),
      saveError: StorageWriteException(),
    );
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);

    final EditorScreenState state = _state(tester);
    final core.RevisionContent before = state.content!;
    await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(fieldTextControlInputKey), 'Neu');
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();

    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(find.byKey(fieldValueErrorKey), findsOneWidget);
    expect(find.text(_de.save003), findsOneWidget);
    expect(state.content, same(before));
    expect(state.content!.values.containsKey(_fieldId), isFalse);
    expect(state.durabilityStatus, isA<core.SaveFailedDurabilityStatus>());
    expect(
      (state.durabilityStatus as core.SaveFailedDurabilityStatus).errorCode,
      'SAVE-003',
    );
  });

  testWidgets('a barrier tap saves nothing and keeps the editor', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    final GlobalKey<NavigatorState> navigatorKey = await _pumpEditorOverHost(
      tester,
      runtime: runtime,
    );
    final EditorScreenState state = _state(tester);
    await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(fieldTextControlInputKey), 'Entwurf');

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(store.saves, isEmpty);
    expect(state.content!.values.containsKey(_fieldId), isFalse);
    _expectEditorOverHost(navigatorKey);
  });

  testWidgets('dragging the sheet down saves nothing and keeps the editor', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    final GlobalKey<NavigatorState> navigatorKey = await _pumpEditorOverHost(
      tester,
      runtime: runtime,
    );
    final EditorScreenState state = _state(tester);
    await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(fieldTextControlInputKey), 'Entwurf');

    final Rect sheetRect = tester.getRect(find.byKey(fieldValueSheetKey));
    await tester.dragFrom(
      sheetRect.topCenter + const Offset(0, 16),
      const Offset(0, 320),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(store.saves, isEmpty);
    expect(state.content!.values.containsKey(_fieldId), isFalse);
    _expectEditorOverHost(navigatorKey);
  });

  testWidgets('system back cancels without saving or popping the editor', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    final GlobalKey<NavigatorState> navigatorKey = await _pumpEditorOverHost(
      tester,
      runtime: runtime,
    );
    final EditorScreenState state = _state(tester);
    await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(fieldTextControlInputKey), 'Entwurf');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(fieldValueSheetKey), findsNothing);
    expect(store.saves, isEmpty);
    expect(state.content!.values.containsKey(_fieldId), isFalse);
    _expectEditorOverHost(navigatorKey);
  });

  testWidgets('explicit close cancels without saving or popping the editor', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    final GlobalKey<NavigatorState> navigatorKey = await _pumpEditorOverHost(
      tester,
      runtime: runtime,
    );
    final EditorScreenState state = _state(tester);
    await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(fieldTextControlInputKey), 'Entwurf');

    await tester.tap(find.byKey(fieldValueCloseKey));
    await tester.pumpAndSettle();

    expect(find.byKey(fieldValueSheetKey), findsNothing);
    expect(store.saves, isEmpty);
    expect(state.content!.values.containsKey(_fieldId), isFalse);
    _expectEditorOverHost(navigatorKey);
  });

  testWidgets('focus loss still saves when the sheet is current', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    final GlobalKey<NavigatorState> navigatorKey = await _pumpEditorOverHost(
      tester,
      runtime: runtime,
    );
    final EditorScreenState state = _state(tester);
    await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(fieldTextControlInputKey),
      'Müller & Söhne',
    );
    FocusScope.of(tester.element(find.byKey(fieldTextControlInputKey)))
        .unfocus();
    await tester.pumpAndSettle();

    expect(store.saves, hasLength(1));
    expect(find.byKey(fieldValueSheetKey), findsNothing);
    final core.FieldValue? value = state.content!.values[_fieldId];
    expect(value, isA<core.TextValue>());
    expect((value! as core.TextValue).text, 'Müller & Söhne');
    _expectEditorOverHost(navigatorKey);
  });

  testWidgets(
    'a save completing after the sheet route is gone does not pop the editor',
    (tester) async {
      final _FakeStore store = _FakeStore(loaded: _loaded());
      final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
      final GlobalKey<NavigatorState> navigatorKey = await _pumpEditorOverHost(
        tester,
        runtime: runtime,
      );
      final EditorScreenState state = _state(tester);
      await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(fieldTextControlInputKey), 'Entwurf');

      // Gate the verified store commit so the save is still in flight while
      // system back dismisses the sheet (the deterministic F7-R1 race).
      final Completer<StoredMeta> gate = Completer<StoredMeta>();
      store.saveGate = gate;
      await tester.tap(find.byKey(fieldValueSaveKey));
      await tester.pump();
      expect(store.saves, hasLength(1));
      expect(find.byKey(fieldValueSheetKey), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byKey(fieldValueSheetKey), findsOneWidget);
      gate.complete(_storedMeta());
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(fieldValueSheetKey), findsNothing);
      _expectEditorOverHost(navigatorKey);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the production value-sheet route disables barrier and drag', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);
    await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
    await tester.pumpAndSettle();

    final ModalRoute<dynamic>? route = ModalRoute.of(
      tester.element(find.byKey(fieldValueSheetKey)),
    );
    expect(route, isA<ModalBottomSheetRoute<bool>>());
    final ModalBottomSheetRoute<bool> sheetRoute =
        route! as ModalBottomSheetRoute<bool>;
    expect(sheetRoute.isDismissible, isFalse);
    expect(sheetRoute.enableDrag, isFalse);
  });

  testWidgets(
    'a readable stored document opens and the list reloads on return',
    (tester) async {
      final _FakeStore store = _FakeStore(
        loaded: _loaded(
          content: _content(
            value: core.TextValue(
              text: 'Persistiert',
              lastEditedAt: _createdAt,
            ),
          ),
        ),
      );
      final ImportRuntime runtime = ImportRuntime(
        importPort: _FakeImportPort(),
        readSourceBytes: (String _) async => _sourceBytes,
        store: store,
        editorRuntimeFactory: () => _FakeEditorRuntime(store),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const <Locale>[Locale('de')],
          home: StartScreen(
            importRuntimeFactory: () => runtime,
            pageRendererFactory: _renderer,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(StoredItemsView), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('stored-item-$_documentId')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('stored-item-$_documentId')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EditorScreen), findsOneWidget);
      final core.RevisionContent content = _state(tester).content!;
      expect(content.pages.single.geometry.displaySize, core.Size(300, 300));
      expect((content.values[_fieldId]! as core.TextValue).text, 'Persistiert');
      expect(store.loads, greaterThanOrEqualTo(1));
      final int listsBeforeReturn = store.listCalls;

      Navigator.of(tester.element(find.byType(EditorScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(EditorScreen), findsNothing);
      expect(find.byType(StoredItemsView), findsOneWidget);
      expect(store.listCalls, greaterThan(listsBeforeReturn));

      await tester.tap(
        find.byKey(const ValueKey<String>('stored-item-$_documentId')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EditorScreen), findsOneWidget);
      final core.RevisionContent reopened = _state(tester).content!;
      expect(
        (reopened.values[_fieldId]! as core.TextValue).text,
        'Persistiert',
      );
    },
  );

  testWidgets('an unreadable stored document is not opened', (tester) async {
    final _FakeStore store = _FakeStore(
      loaded: _loaded(),
      documents: <StoredMeta>[
        StoredMeta(
          id: _documentId,
          kind: StoreKind.document,
          title: 'Testdokument',
          createdAt: _createdAt,
          updatedAt: _createdAt,
          latestRevisionId: _revisionId,
          lastDurableAt: _createdAt,
        ),
        StoredMeta(
          id: _unreadableDocumentId,
          kind: StoreKind.document,
          title: 'Nicht lesbar',
          createdAt: _createdAt,
          updatedAt: _createdAt,
          readable: false,
          unreadableReasonCode: 'SAVE-002',
        ),
      ],
    );
    final ImportRuntime runtime = ImportRuntime(
      importPort: _FakeImportPort(),
      readSourceBytes: (String _) async => _sourceBytes,
      store: store,
      editorRuntimeFactory: () => _FakeEditorRuntime(store),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const <Locale>[Locale('de')],
        home: StartScreen(
          importRuntimeFactory: () => runtime,
          pageRendererFactory: _renderer,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(_de.statusUnreadable), findsWidgets);
    final Finder unreadableRow = find.byKey(
      const ValueKey<String>('stored-item-$_unreadableDocumentId'),
    );
    expect(unreadableRow, findsOneWidget);
    expect(tester.widget<InkWell>(unreadableRow).onTap, isNull);
    await tester.tap(unreadableRow);
    await tester.pumpAndSettle();

    expect(find.byType(EditorScreen), findsNothing);
    expect(store.loads, 0);
  });

  testWidgets(
    '200 percent text scale composes editor and sheet without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final _FakeStore store = _FakeStore(loaded: _loaded());
      final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
      await _pumpEditor(tester, runtime: runtime, textScale: 2);
      expect(tester.takeException(), isNull);

      final EditorScreenState state = _state(tester);
      await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
      await tester.pumpAndSettle();
      expect(find.byKey(fieldValueSheetKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
