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
//   * 200 % text scale composes the editor and the value sheet without a
//     RenderFlex overflow.

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:feldexa_app/features/editor/durability_status.dart';
import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/field_order.dart';
import 'package:feldexa_app/features/editor/field_value_sheet.dart';
import 'package:feldexa_app/features/editor/page_view.dart' as viewer;
import 'package:feldexa_app/features/fill/checkbox_control.dart';
import 'package:feldexa_app/features/fill/field_text_fit.dart';
import 'package:feldexa_app/features/fill/overflow_warning.dart';
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
const String _secondFieldId = '22222222-2222-4222-8222-222222222222';
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

/// A second confirmed field below [_fieldRect] for the T073 order tests.
core.ConfirmedField _secondField([core.FieldType type = core.FieldType.text]) {
  return core.ConfirmedField(
    id: _secondFieldId,
    pageIndex: 0,
    rect: core.Rect.fromLTWH(40, 140, 100, 30),
    type: type,
    provenance: core.Provenance.user,
    label: 'Vorname',
    order: 1,
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
  bool withSecondField = false,
  bool secondFieldFirst = false,
  bool withSuggestion = false,
  core.FieldType fieldType = core.FieldType.text,
  core.FieldType secondFieldType = core.FieldType.text,
  core.FieldValue? value,
}) {
  final List<core.ConfirmedField> fields =
      secondFieldFirst && withField && withSecondField
      ? <core.ConfirmedField>[
          _secondField(secondFieldType).copyWith(order: 0),
          _field(fieldType).copyWith(order: 1),
        ]
      : <core.ConfirmedField>[
          if (withField) _field(fieldType),
          if (withField && withSecondField) _secondField(secondFieldType),
        ];
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
  TestWidgetsFlutterBinding.ensureInitialized();

  // T086C: the productive path reads the bundled Noto Sans advance table at
  // startup; the host tests load the same table so the FLD-001 decision uses
  // the real export metrics instead of a test font.
  setUpAll(() async {
    expect(await initializeFieldTextMeasure(), isTrue);
  });
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

  testWidgets(
    'an overflowing value persists the FLD-001 flag and reopens in full',
    (tester) async {
      final _FakeStore store = _FakeStore(loaded: _loaded());
      final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
      await _pumpEditor(tester, runtime: runtime);

      final EditorScreenState state = _state(tester);
      // 41 characters need roughly 250 pt at 12 pt; the field offers 97 pt.
      const String tooLong = 'Erika Mustermann und Maximilian Mustermann';
      await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(fieldTextControlInputKey), tooLong);
      await tester.tap(find.byKey(fieldValueSaveKey));
      await tester.pumpAndSettle();

      // The warning is visible immediately after the commit and the sheet stays
      // on the field; the complete value was persisted with the flag.
      expect(find.byKey(fieldValueSheetKey), findsOneWidget);
      expect(find.byKey(fieldOverflowWarningKey), findsOneWidget);
      expect(store.saves, hasLength(1));
      final core.TextValue stored =
          store.saves.single.content.values[_fieldId]! as core.TextValue;
      expect(stored.overflow, isTrue);
      expect(stored.text, tooLong);
      expect(state.content!.values[_fieldId], stored);

      // Closing and reopening the stored field shows the same full text and the
      // persisted warning state; no second revision is written.
      await tester.tap(find.byKey(fieldValueCloseKey));
      await tester.pumpAndSettle();
      expect(find.byKey(fieldValueSheetKey), findsNothing);

      await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
      await tester.pumpAndSettle();
      expect(find.byKey(fieldOverflowWarningKey), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(fieldTextControlInputKey))
            .controller!
            .text,
        tooLong,
      );
      expect(store.saves, hasLength(1));
    },
  );

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

  testWidgets(
    'field order sheet reorders in document order and saves one undo step',
    (tester) async {
      final core.TextValue value = core.TextValue(
        text: 'Ada',
        lastEditedAt: _createdAt,
      );
      final _FakeStore store = _FakeStore(
        loaded: _loaded(content: _content(withSecondField: true, value: value)),
      );
      final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
      await _pumpEditor(tester, runtime: runtime);
      final EditorScreenState state = _state(tester);
      expect(state.content!.fieldOrder, <String>[_fieldId, _secondFieldId]);

      await tester.tap(
        find.byKey(const ValueKey<String>('editor-field-order-action')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>(fieldOrderListKey)), findsOne);
      expect(
        find.text(lookupAppLocalizations(const Locale('de')).fieldOrderTitle),
        findsOneWidget,
      );

      // The second field is last, so only move-up is enabled for it.
      await tester.tap(
        find.byKey(
          ValueKey<String>('$fieldOrderMoveUpKeyPrefix$_secondFieldId'),
        ),
      );
      await tester.pumpAndSettle();

      expect(store.saves, hasLength(1));
      final core.RevisionContent saved = store.saves.single.content;
      expect(saved.fieldOrder, <String>[_secondFieldId, _fieldId]);
      expect(
        saved.fields.map((core.ConfirmedField field) => field.order).toList(),
        <int>[0, 1],
      );
      expect(saved.values[_fieldId], value);
      expect(
        saved.fields
            .firstWhere((core.ConfirmedField field) => field.id == _fieldId)
            .rect,
        _fieldRect(),
      );
      expect(state.content!.fieldOrder, <String>[_secondFieldId, _fieldId]);
      expect(state.canUndoReview, isTrue);

      // Previous/next walk the persisted order and never write a revision.
      await tester.tap(find.byKey(const ValueKey<String>('field-order-next')));
      await tester.pumpAndSettle();
      expect(store.saves, hasLength(1));

      await tester.tap(find.byKey(const ValueKey<String>('field-order-close')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>(fieldOrderListKey)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a failed reorder save keeps the previous order untouched', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(
      loaded: _loaded(content: _content(withSecondField: true)),
      saveError: StorageWriteException(),
    );
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);
    final core.RevisionContent before = state.content!;

    await tester.tap(
      find.byKey(const ValueKey<String>('editor-field-order-action')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey<String>('$fieldOrderMoveUpKeyPrefix$_secondFieldId')),
    );
    await tester.pumpAndSettle();

    expect(store.saves, hasLength(1));
    expect(state.content, same(before));
    expect(state.canUndoReview, isFalse);
    expect(find.byKey(const ValueKey<String>(fieldOrderListKey)), findsOne);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(ValueKey<String>('$fieldOrderMoveUpKeyPrefix$_fieldId')),
          )
          .onPressed,
      isNull,
      reason: 'the first row still holds position 0 after the failed save',
    );
    expect(state.durabilityStatus, isA<core.SaveFailedDurabilityStatus>());
    await tester.tap(find.byKey(const ValueKey<String>('field-order-close')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the per-field reorder action opens the field-order review', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(
      loaded: _loaded(content: _content(withSecondField: true)),
    );
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);

    await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
    await tester.pumpAndSettle();
    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(find.byKey(fieldValueReorderKey), findsOneWidget);

    await tester.tap(find.byKey(fieldValueReorderKey));
    await tester.pumpAndSettle();

    expect(find.byKey(fieldValueSheetKey), findsNothing);
    expect(
      find.byKey(const ValueKey<String>(fieldOrderListKey)),
      findsOneWidget,
    );
    expect(find.text('Vorname'), findsWidgets);
    // The field was untouched, so the reorder hand-off adds no setValue
    // revision and no undo step.
    expect(store.saves, isEmpty);
    expect(state.canUndoReview, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'next/previous move focus in field order while the value sheet stays open',
    (tester) async {
      final _FakeStore store = _FakeStore(
        loaded: _loaded(content: _content(withSecondField: true)),
      );
      final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
      await _pumpEditor(tester, runtime: runtime);
      final EditorScreenState state = _state(tester);

      await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
      await tester.pumpAndSettle();
      expect(find.byKey(fieldValueSheetKey), findsOneWidget);
      expect(state.selection.selectedId, _fieldId);
      expect(
        tester.widget<TextButton>(find.byKey(fieldValuePreviousKey)).onPressed,
        isNull,
        reason: 'the first field has no previous field',
      );
      expect(
        tester.widget<TextButton>(find.byKey(fieldValueNextKey)).onPressed,
        isNotNull,
      );

      await tester.enterText(find.byKey(fieldTextControlInputKey), 'Erika');
      await tester.tap(find.byKey(fieldValueNextKey));
      await tester.pumpAndSettle();

      // The same sheet stays open, the next control has focus, and the draft
      // was committed before the move.
      expect(find.byKey(fieldValueSheetKey), findsOneWidget);
      expect(state.selection.selectedId, _secondFieldId);
      expect(find.text('Vorname'), findsWidgets);
      expect(store.saves, hasLength(1));
      expect(
        (store.saves.single.content.values[_fieldId]! as core.TextValue).text,
        'Erika',
      );
      final TextField input = tester.widget<TextField>(
        find.byKey(fieldTextControlInputKey),
      );
      expect(input.controller!.text, isEmpty);
      expect(input.focusNode!.hasFocus, isTrue);
      expect(
        tester.widget<TextButton>(find.byKey(fieldValueNextKey)).onPressed,
        isNull,
        reason: 'the last field has no next field',
      );
      expect(
        tester.widget<TextButton>(find.byKey(fieldValuePreviousKey)).onPressed,
        isNotNull,
      );

      // Moving back keeps the committed value and follows the same order.
      await tester.tap(find.byKey(fieldValuePreviousKey));
      await tester.pumpAndSettle();
      expect(state.selection.selectedId, _fieldId);
      expect(find.byKey(fieldValueSheetKey), findsOneWidget);
      expect(find.text('Erika'), findsWidgets);
      expect(
        tester.widget<TextButton>(find.byKey(fieldValuePreviousKey)).onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the page-order action sorts the order in one revision', (
    tester,
  ) async {
    final _FakeStore store = _FakeStore(
      loaded: _loaded(
        content: _content(withSecondField: true, secondFieldFirst: true),
      ),
    );
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);
    expect(state.content!.fieldOrder, <String>[_secondFieldId, _fieldId]);

    await tester.tap(
      find.byKey(const ValueKey<String>('editor-field-order-action')),
    );
    await tester.pumpAndSettle();
    final Finder applyPageOrder = find.byKey(
      const ValueKey<String>('field-order-apply-page-order'),
    );
    expect(tester.widget<TextButton>(applyPageOrder).onPressed, isNotNull);

    await tester.tap(applyPageOrder);
    await tester.pumpAndSettle();

    expect(store.saves, hasLength(1));
    expect(store.saves.single.content.fieldOrder, <String>[
      _fieldId,
      _secondFieldId,
    ]);
    expect(state.content!.fieldOrder, <String>[_fieldId, _secondFieldId]);
    expect(state.canUndoReview, isTrue);
    expect(
      tester.widget<TextButton>(applyPageOrder).onPressed,
      isNull,
      reason: 'the order already is the page order',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'next from an untouched empty number adds no revision and focuses the next',
    (tester) async {
      final _FakeStore store = _FakeStore(
        loaded: _loaded(
          content: _content(
            withSecondField: true,
            fieldType: core.FieldType.number,
          ),
        ),
      );
      final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
      await _pumpEditor(tester, runtime: runtime);
      final EditorScreenState state = _state(tester);

      await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
      await tester.pumpAndSettle();
      expect(find.byKey(fieldValueSheetKey), findsOneWidget);

      await tester.tap(find.byKey(fieldValueNextKey));
      await tester.pumpAndSettle();

      // An untouched empty number is not validated (no NUM-001) and writes no
      // setValue revision or undo step.
      expect(store.saves, isEmpty);
      expect(state.canUndoReview, isFalse);
      expect(find.byKey(fieldValueErrorKey), findsNothing);
      expect(find.byKey(fieldValueSheetKey), findsOneWidget);
      expect(state.selection.selectedId, _secondFieldId);
      final TextField input = tester.widget<TextField>(
        find.byKey(fieldTextControlInputKey),
      );
      expect(input.focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a checkbox target receives focus after next', (tester) async {
    final _FakeStore store = _FakeStore(
      loaded: _loaded(
        content: _content(
          withSecondField: true,
          secondFieldType: core.FieldType.checkbox,
        ),
      ),
    );
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);

    await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(fieldValueNextKey));
    await tester.pumpAndSettle();

    expect(state.selection.selectedId, _secondFieldId);
    expect(find.byKey(fieldCheckboxControlKey), findsOneWidget);
    final Focus focus = tester.widget<Focus>(
      find.byKey(fieldValueNonTextFocusKey),
    );
    expect(focus.focusNode!.hasFocus, isTrue);
    expect(store.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a signature target receives focus after next', (tester) async {
    final _FakeStore store = _FakeStore(
      loaded: _loaded(
        content: _content(
          withSecondField: true,
          secondFieldType: core.FieldType.signature,
        ),
      ),
    );
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);

    await tester.tapAt(_screenPoint(tester, state, _fieldRect()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(fieldValueNextKey));
    await tester.pumpAndSettle();

    expect(state.selection.selectedId, _secondFieldId);
    expect(find.byKey(fieldValueSignatureActionKey), findsOneWidget);
    final Focus focus = tester.widget<Focus>(
      find.byKey(fieldValueNonTextFocusKey),
    );
    expect(focus.focusNode!.hasFocus, isTrue);
    expect(store.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
