// T086A editor signature composition host tests (issue #269, US4).
//
// Evidence class: NONE. These are host-VM widget tests with injected fake
// ports and an in-memory store. They construct no platform channel, open no
// PDF, start no browser, emulator, or device, and make no Android runtime,
// screen-reader, or visual claim. The real Android journey is owned by
// `integration_test/android_signature_overlay_test.dart` and its host driver.
//
// They prove the composed T086A behavior of `contracts/editor-interactions.md`
// §5 and `spec.md` FR-036/FR-047 on the real editor widget:
//   * tapping a confirmed signature field opens the value sheet, and its capture
//     action opens the existing T083 full-screen sheet;
//   * drawing, undo, clear, cancel, and apply behave as the sheet promises and
//     an empty apply stores nothing;
//   * applying ink writes exactly one signature asset through
//     `SecureStorePort.writeSignature` whose SHA-256 matches the encoded bytes,
//     and exactly one verified revision that carries both the `SignatureValue`
//     and the `SignatureMark` bound to that field and page;
//   * the encoded asset is a real PNG, its pixels are the drawn ink, and the
//     stored `SignatureMark` dimensions match the encoded image;
//   * the visible content, head, and durability status change only after the
//     verified commit, and reopening the document shows the signed state with
//     the same asset read back;
//   * a failed asset write saves no revision, and a failed revision save leaves
//     the document unsigned while reporting the existing content-free error;
//   * one captured signature is one `addSignature` undo step that restores the
//     previous unsigned snapshot exactly;
//   * two fields (and two documents) never share ink: each commit has its own
//     asset id and its own bytes;
//   * the signature field is painted, selectable, movable, and resizable on the
//     real page surface, not only in a damaged-page fixture.

// The workspace `feldexa_ui` package is consumed through the workspace package
// config; T086A may not add an app `pubspec.yaml` dependency (same documented
// situation as `editor_screen.dart` and `review_degraded_test.dart`).
// ignore_for_file: depend_on_referenced_packages

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/field_value_sheet.dart';
import 'package:feldexa_app/features/editor/page_view.dart' as viewer;
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/features/fill/signature_png.dart';
import 'package:feldexa_app/features/fill/signature_sheet.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:feldexa_ui/feldexa_ui.dart' as ui;
import 'package:flutter/material.dart' hide PageView;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const String _documentId = '5f0c3a52-3a6a-4f0b-9c2d-1b7e4d8a6c01';
const String _sourceId = '7b2d4c1e-5f3a-4b8c-8a9d-2e6f0c1b3d42';
const String _revisionId = '9a1b2c3d-4e5f-4a6b-8c7d-8e9f0a1b2c3d';
const String _savedRevisionId = '9a1b2c3d-4e5f-4a6b-8c7d-8e9f0a1b2c3e';
const String _signatureFieldId = '11111111-1111-4111-8111-111111111111';
const String _textFieldId = '22222222-2222-4222-8222-222222222222';
final String _sha256 = List<String>.filled(64, 'a').join();
final Uint8List _sourceBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

final CapabilityEvidence _noneEvidence = CapabilityEvidence(
  evidenceClass: EvidenceClass.none,
  adapterId: 'test.t086a.v1',
);

final CapabilityDescriptor _storeDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.secureStore,
  adapterId: 'test.t086a.store.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final CapabilityDescriptor _idsDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.ids,
  adapterId: 'test.t086a.ids.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final CapabilityDescriptor _clockDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.clock,
  adapterId: 'test.t086a.clock.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final DateTime _createdAt = DateTime.utc(2026, 11, 20, 8);
final DateTime _savedAt = DateTime.utc(2026, 11, 22, 10, 15);

final AppLocalizations _de = lookupAppLocalizations(const Locale('de'));

const ValueKey<String> _editorPageViewKey = ValueKey<String>(
  'editor-page-view',
);
const double _signatureLeft = 40;
const double _signatureTop = 60;
const double _signatureWidth = 160;
const double _signatureHeight = 50;
const double _textTop = 140;

core.Rect _signatureRect() => core.Rect.fromLTWH(
  _signatureLeft,
  _signatureTop,
  _signatureWidth,
  _signatureHeight,
);

core.Page _page() {
  return core.Page(
    index: 0,
    geometry: core.PageGeometry(mediaBox: core.Rect.fromLTWH(0, 0, 300, 300)),
    analysis: core.AnalysisState.complete,
  );
}

core.ConfirmedField _signatureField({int order = 0}) {
  return core.ConfirmedField(
    id: _signatureFieldId,
    pageIndex: 0,
    rect: _signatureRect(),
    type: core.FieldType.signature,
    provenance: core.Provenance.user,
    label: 'Unterschrift',
    order: order,
    createdAt: _createdAt,
    updatedAt: _createdAt,
  );
}

core.ConfirmedField _textField({int order = 1}) {
  return core.ConfirmedField(
    id: _textFieldId,
    pageIndex: 0,
    rect: core.Rect.fromLTWH(40, _textTop, 100, 30),
    type: core.FieldType.text,
    provenance: core.Provenance.user,
    label: 'Ort',
    order: order,
    createdAt: _createdAt,
    updatedAt: _createdAt,
  );
}

core.RevisionContent _content({
  bool signed = false,
  String assetId = '',
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  final List<core.ConfirmedField> fields = <core.ConfirmedField>[
    _signatureField(),
    _textField(),
  ];
  final Map<String, core.FieldValue> values = <String, core.FieldValue>{
    _textFieldId: core.TextValue(text: 'Musterstadt', lastEditedAt: _createdAt),
    if (signed)
      _signatureFieldId: core.SignatureValue(
        signatureAssetId: assetId,
        lastEditedAt: _createdAt,
      ),
  };
  return core.RevisionContent(
    pages: <core.Page>[_page()],
    fields: fields,
    fieldOrder: <String>[
      for (final core.ConfirmedField field in fields) field.id,
    ],
    values: values,
    signatures: signed
        ? <String, core.SignatureMark>{
            _signatureFieldId: core.SignatureMark(
              assetId: assetId,
              fieldId: _signatureFieldId,
              pageIndex: 0,
              rect: _signatureRect(),
              widthPx: 160,
              heightPx: 50,
              capturedAt: _createdAt,
              sha256: _sha256,
            ),
          }
        : const <String, core.SignatureMark>{},
    unknownFields: unknownFields,
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

/// In-memory encrypted-store stand-in that verifies the signature digest the
/// same way the Android adapter does before it accepts a write.
final class _FakeStore implements SecureStorePort {
  _FakeStore({required this.loaded, this.saveError, this.signatureError});

  LoadedDocument loaded;
  final Object? saveError;
  final Object? signatureError;
  final List<SaveRevisionRequest> saves = <SaveRevisionRequest>[];
  final List<String?> savedHeads = <String?>[];
  final List<WriteSignatureRequest> signatureWrites = <WriteSignatureRequest>[];
  final Map<String, Uint8List> assets = <String, Uint8List>{};

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
    if (saveError != null) {
      throw saveError!;
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
  Future<void> writeSignature(WriteSignatureRequest request) async {
    signatureWrites.add(request);
    if (signatureError != null) {
      throw signatureError!;
    }
    // Fail closed exactly like the reverse-verified Android channel.
    final String digest = crypto.sha256.convert(request.bytes).toString();
    if (digest != request.sha256) {
      throw const FormatException('Signature write is not verified');
    }
    assets[request.assetId] = Uint8List.fromList(request.bytes);
  }

  @override
  Future<Uint8List> readSignature(String documentId, String assetId) async {
    final Uint8List? bytes = assets[assetId];
    if (bytes == null) {
      throw const FormatException('missing signature asset');
    }
    return bytes;
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
  final _FakeClock fakeClock = _FakeClock();
  final _FakeIds _ids = _FakeIds();

  @override
  PageRasterPort get raster => _UnavailableRaster();

  @override
  OcrPort? get ocr => null;

  @override
  SecureStorePort get store => fakeStore;

  @override
  IdPort get ids => _ids;

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
  // A tall surface keeps the whole 300 × 300 pt page inside the page viewport.
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

Offset _screenPointAt(
  WidgetTester tester,
  EditorScreenState state,
  Offset displayPoint,
) {
  final viewer.PageViewMapping mapping = state.viewController.mappingFor(0);
  final Offset local = mapping.displayToView(displayPoint);
  return tester.getTopLeft(find.byKey(_editorPageViewKey)) + local;
}

Offset _screenPoint(
  WidgetTester tester,
  EditorScreenState state,
  core.Rect rect,
) {
  return _screenPointAt(
    tester,
    state,
    Offset(rect.left + rect.width / 2, rect.top + rect.height / 2),
  );
}

/// Pumps until [condition] holds, so the asynchronous PNG encoding, store write,
/// and revision save all settle without a fixed sleep.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
  required String reason,
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    // `Picture.toImage` is an engine callback, so the pending PNG encoding only
    // completes on the real event loop; `runAsync` is the documented seam for
    // that in a widget test.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (condition()) {
      return;
    }
  }
  fail('$reason (bounded wait ${timeout.inSeconds}s expired)');
}

/// Opens the value sheet for the signature field and the T083 capture sheet.
Future<void> _openSignatureSurface(
  WidgetTester tester,
  EditorScreenState state,
) async {
  await tester.tapAt(_screenPoint(tester, state, _signatureRect()));
  await tester.pumpAndSettle();
  expect(find.byKey(fieldValueSheetKey), findsOneWidget);
  await tester.tap(find.byKey(fieldValueSignatureActionKey));
  await tester.pumpAndSettle();
  expect(find.byType(SignatureSheet), findsOneWidget);
}

/// Draws one two-point stroke in the middle of the signature canvas.
Future<void> _drawStroke(WidgetTester tester) async {
  final Offset centre = tester.getCenter(find.byKey(signatureSheetCanvasKey));
  final TestGesture gesture = await tester.startGesture(
    centre - const Offset(40, 0),
  );
  await gesture.moveBy(const Offset(20, 8));
  await gesture.moveBy(const Offset(20, -4));
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Draws a stroke, applies it, and waits until the sheet closed again.
Future<void> _drawAndApply(
  WidgetTester tester,
  EditorScreenState state, {
  required bool Function() settled,
  required String reason,
}) async {
  await _openSignatureSurface(tester, state);
  await _drawStroke(tester);
  await tester.tap(find.byKey(signatureSheetApplyKey));
  await _pumpUntil(
    tester,
    () =>
        find.byType(SignatureSheet).evaluate().isEmpty &&
        find.byKey(fieldValueSheetKey).evaluate().isEmpty &&
        settled(),
    reason: reason,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('drawing ink stores one asset and one bound revision', (
    WidgetTester tester,
  ) async {
    final _FakeStore store = _FakeStore(
      loaded: _loaded(
        content: _content(
          unknownFields: <String, Object?>{
            'laterField': <String, Object?>{'enabled': true},
          },
        ),
      ),
    );
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);
    final core.RevisionContent before = state.content!;

    await _drawAndApply(
      tester,
      state,
      settled: () => state.durabilityStatus is core.SavedDurabilityStatus,
      reason: 'the verified signature revision did not settle',
    );

    // Exactly one asset write and exactly one revision save.
    expect(store.signatureWrites, hasLength(1));
    expect(store.saves, hasLength(1));
    expect(store.savedHeads.single, _revisionId);
    final WriteSignatureRequest write = store.signatureWrites.single;
    expect(write.documentId, _documentId);
    expect(write.bytes, isNotEmpty);
    expect(
      crypto.sha256.convert(write.bytes).toString(),
      write.sha256,
      reason: 'the digest must be the real SHA-256 of the stored PNG bytes',
    );
    expect(
      write.bytes.sublist(0, 8),
      orderedEquals(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
      reason: 'the stored asset must be a real PNG stream',
    );

    // The one revision carries both the value and the mark for this field.
    final core.RevisionContent saved = state.content!;
    final core.FieldValue? value = saved.values[_signatureFieldId];
    expect(value, isA<core.SignatureValue>());
    final core.SignatureValue signatureValue = value! as core.SignatureValue;
    expect(signatureValue.signatureAssetId, write.assetId);
    expect(signatureValue.lastEditedAt, _savedAt);
    final core.SignatureMark mark = saved.signatures[_signatureFieldId]!;
    expect(mark.assetId, write.assetId);
    expect(mark.fieldId, _signatureFieldId);
    expect(mark.pageIndex, 0);
    expect(mark.rect, _signatureRect());
    expect(mark.capturedAt, _savedAt);
    expect(mark.sha256, write.sha256);
    expect(saved.signatures, hasLength(1));

    // The encoded image really contains the drawn ink and the recorded size.
    final img.Image decoded = img.decodePng(write.bytes)!;
    expect(decoded.width, mark.widthPx);
    expect(decoded.height, mark.heightPx);
    expect(mark.widthPx, lessThanOrEqualTo(signaturePngMaxEdgePx));
    int darkPixels = 0;
    int opaquePixels = 0;
    for (int y = 0; y < decoded.height; y++) {
      for (int x = 0; x < decoded.width; x++) {
        final img.Pixel pixel = decoded.getPixel(x, y);
        if (pixel.a > 0) {
          opaquePixels++;
          if (pixel.r < 128 && pixel.g < 128 && pixel.b < 128) {
            darkPixels++;
          }
        }
      }
    }
    expect(opaquePixels, greaterThan(0), reason: 'drawn ink must be opaque');
    expect(darkPixels, greaterThan(0), reason: 'drawn ink must be dark');
    expect(
      opaquePixels,
      lessThan(decoded.width * decoded.height),
      reason: 'the background stays transparent, only ink is painted',
    );

    // Everything else in the document is preserved.
    expect(saved.pages, equals(before.pages));
    expect(saved.fields, equals(before.fields));
    expect(saved.fieldOrder, before.fieldOrder);
    expect(saved.suggestions, before.suggestions);
    expect(saved.verification, before.verification);
    expect(saved.unknownFields, before.unknownFields);
    expect(saved.values[_textFieldId], before.values[_textFieldId]);

    // Visible progress is only claimed after the verified commit.
    expect(state.headRevisionId, _savedRevisionId);
    expect(state.durabilityStatus, isA<core.SavedDurabilityStatus>());
    expect(state.canUndoReview, isTrue);
    expect(find.byKey(fieldValueErrorKey), findsNothing);
  });

  testWidgets('reopening shows the signed field and the read-back asset', (
    WidgetTester tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);

    await _drawAndApply(
      tester,
      state,
      settled: () => state.content!.signatures.isNotEmpty,
      reason: 'the signature revision did not settle',
    );
    final String assetId = store.signatureWrites.single.assetId;

    // Reopen the same stored document in a fresh editor and a fresh runtime
    // that has no in-memory document state at all.
    final _FakeStore reopenedStore = _FakeStore(loaded: store.loaded)
      ..assets.addAll(store.assets);
    final _FakeEditorRuntime reopenedRuntime = _FakeEditorRuntime(
      reopenedStore,
    );
    await _pumpEditor(tester, runtime: reopenedRuntime);
    final EditorScreenState reopened = _state(tester);

    final core.FieldValue? value = reopened.content!.values[_signatureFieldId];
    expect(value, isA<core.SignatureValue>());
    expect((value! as core.SignatureValue).signatureAssetId, assetId);
    expect(reopened.content!.signatures[_signatureFieldId]!.assetId, assetId);
    final Uint8List readBack = await reopenedStore.readSignature(
      _documentId,
      assetId,
    );
    expect(
      crypto.sha256.convert(readBack).toString(),
      reopened.content!.signatures[_signatureFieldId]!.sha256,
    );

    // The reopened sheet shows the signed state instead of the unsigned one.
    await tester.tapAt(_screenPoint(tester, reopened, _signatureRect()));
    await tester.pumpAndSettle();
    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(find.text(_de.a11ySignatureSigned), findsOneWidget);
    expect(find.text(_de.a11ySignatureUnsigned), findsNothing);
    expect(find.byKey(fieldValueSignatureActionKey), findsOneWidget);
  });

  testWidgets('undo restores the unsigned revision exactly', (
    WidgetTester tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);
    final core.RevisionContent before = state.content!;

    await _drawAndApply(
      tester,
      state,
      settled: () => state.content!.signatures.isNotEmpty,
      reason: 'the signature revision did not settle',
    );
    expect(state.content!.signatures, hasLength(1));
    final String beforeJson = core.canonicalJsonEncode(before.toJson());

    runtime.fakeClock.now = _savedAt.add(const Duration(minutes: 1));
    await tester.tap(find.byKey(const ValueKey<String>(undoReviewKey)));
    await tester.pumpAndSettle();

    expect(store.saves, hasLength(2));
    expect(
      core.canonicalJsonEncode(state.content!.toJson()),
      beforeJson,
      reason: 'undo must restore the exact previous snapshot',
    );
    expect(state.content!.signatures, isEmpty);
    expect(state.content!.values.containsKey(_signatureFieldId), isFalse);
  });

  testWidgets('a failed asset write saves no revision and stays open', (
    WidgetTester tester,
  ) async {
    final _FakeStore store = _FakeStore(
      loaded: _loaded(),
      signatureError: StorageFullException(),
    );
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);
    final core.RevisionContent before = state.content!;

    await _openSignatureSurface(tester, state);
    await _drawStroke(tester);
    await tester.tap(find.byKey(signatureSheetApplyKey));
    await _pumpUntil(
      tester,
      () => find.byKey(fieldValueErrorKey).evaluate().isNotEmpty,
      reason: 'the failed asset write did not report an error',
    );
    // The capture route pops before the commit result arrives, so let its exit
    // animation finish before asserting on the visible stack.
    await tester.pumpAndSettle();

    expect(store.signatureWrites, hasLength(1));
    expect(store.saves, isEmpty, reason: 'no revision without the asset');
    expect(state.content!.signatures, isEmpty);
    expect(state.content, same(before));
    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(find.byType(SignatureSheet), findsNothing);
    expect(state.durabilityStatus, isA<core.SaveFailedDurabilityStatus>());
    final String? message = tester
        .widget<Text>(find.byKey(fieldValueErrorKey))
        .data;
    expect(message, isNotNull);
    expect(message, isNot(contains(_signatureFieldId)));
  });

  testWidgets('a failed revision save leaves the document unsigned', (
    WidgetTester tester,
  ) async {
    final _FakeStore store = _FakeStore(
      loaded: _loaded(),
      saveError: StorageWriteException(),
    );
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);
    final core.RevisionContent before = state.content!;

    await _openSignatureSurface(tester, state);
    await _drawStroke(tester);
    await tester.tap(find.byKey(signatureSheetApplyKey));
    await _pumpUntil(
      tester,
      () => find.byKey(fieldValueErrorKey).evaluate().isNotEmpty,
      reason: 'the failed revision save did not report an error',
    );
    await tester.pumpAndSettle();

    expect(store.signatureWrites, hasLength(1));
    expect(store.saves, hasLength(1));
    // The asset is unreferenced: no stored mark or value names it.
    expect(state.content!.signatures, isEmpty);
    expect(state.content, same(before));
    expect(state.content!.values.containsKey(_signatureFieldId), isFalse);
    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(state.durabilityStatus, isA<core.SaveFailedDurabilityStatus>());
    expect(state.headRevisionId, _revisionId);
  });

  testWidgets('two fields never share ink (no global signature state)', (
    WidgetTester tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);

    await _drawAndApply(
      tester,
      state,
      settled: () => state.content!.signatures.isNotEmpty,
      reason: 'the first signature revision did not settle',
    );
    final String firstAssetId = store.signatureWrites.single.assetId;
    final Uint8List firstBytes = store.assets[firstAssetId]!;
    final core.SignatureMark firstMark =
        state.content!.signatures[_signatureFieldId]!;

    // Signing the text field is rejected by the command: only a signature
    // field can carry ink, so the document keeps exactly one mark.
    runtime.fakeClock.now = _savedAt.add(const Duration(minutes: 1));
    await tester.tapAt(
      _screenPoint(tester, state, core.Rect.fromLTWH(40, _textTop, 100, 30)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(find.byKey(fieldValueSignatureActionKey), findsNothing);
    await tester.tap(find.byKey(fieldValueCloseKey));
    await tester.pumpAndSettle();

    expect(state.content!.signatures, hasLength(1));
    expect(state.content!.signatures[_signatureFieldId], same(firstMark));
    expect(store.signatureWrites, hasLength(1));
    expect(store.assets[firstAssetId], orderedEquals(firstBytes));

    // A second, independent commit produces a different asset id and bytes.
    await _drawAndApply(
      tester,
      state,
      settled: () => store.signatureWrites.length == 2,
      reason: 'the second signature revision did not settle',
    );
    expect(store.signatureWrites, hasLength(2));
    expect(store.signatureWrites[1].assetId, isNot(firstAssetId));
    expect(
      state.content!.signatures[_signatureFieldId]!.assetId,
      store.signatureWrites[1].assetId,
    );
    expect(state.content!.signatures, hasLength(1));
  });

  testWidgets('the signature field is painted, movable, and resizable', (
    WidgetTester tester,
  ) async {
    final _FakeStore store = _FakeStore(loaded: _loaded());
    final _FakeEditorRuntime runtime = _FakeEditorRuntime(store);
    await _pumpEditor(tester, runtime: runtime);
    final EditorScreenState state = _state(tester);

    // Painted on the real page: the T069 overlay and T077 surface both carry
    // the confirmed signature field.
    final ui.FieldOverlay overlay = tester.widget<ui.FieldOverlay>(
      find.byType(ui.FieldOverlay),
    );
    expect(
      overlay.items.map((ui.FieldOverlayItem item) => item.id),
      contains(_signatureFieldId),
    );
    expect(
      overlay.items.map((ui.FieldOverlayItem item) => item.provenance),
      contains(ui.FieldOverlayProvenance.user),
    );
    expect(find.byType(ui.FieldSelectionSurface), findsWidgets);

    // Selectable: a real tap on the page selects it and opens the sheet.
    await tester.tapAt(_screenPoint(tester, state, _signatureRect()));
    await tester.pumpAndSettle();
    expect(state.selection.selectedId, _signatureFieldId);
    await tester.tap(find.byKey(fieldValueCloseKey));
    await tester.pumpAndSettle();
    expect(state.selection.selectedId, _signatureFieldId);

    // Movable: a body drag commits exactly one move revision.
    final double scale = state.viewController.mappingFor(0).scale;
    final Offset centre = _screenPoint(tester, state, _signatureRect());
    final TestGesture move = await tester.startGesture(centre);
    await move.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(state.geometryGestureActive, isTrue);
    expect(store.saves, isEmpty, reason: 'no per-frame store save');
    await move.moveBy(Offset(24 * scale, 18 * scale));
    await tester.pump();
    expect(store.saves, isEmpty);
    await move.up();
    await tester.pumpAndSettle();

    expect(store.saves, hasLength(1));
    final core.Rect moved = state.content!.fields
        .firstWhere(
          (core.ConfirmedField field) => field.id == _signatureFieldId,
        )
        .rect;
    expect(moved.left, closeTo(_signatureLeft + 60 / scale + 24, 1e-6));
    expect(
      moved.top,
      closeTo(_signatureTop + 18, 1e-6),
      reason: 'the vertical delta is applied at the gesture scale',
    );
    expect(moved.width, _signatureWidth);
    expect(moved.height, _signatureHeight);

    // Resizable: a corner handle drag commits exactly one resize revision.
    runtime.fakeClock.now = _savedAt.add(const Duration(minutes: 1));
    final TestGesture resize = await tester.startGesture(
      _screenPointAt(
        tester,
        state,
        Offset(moved.left + moved.width, moved.top + moved.height),
      ),
    );
    await resize.moveBy(const Offset(30, 20));
    await tester.pump();
    expect(state.geometryGestureActive, isTrue);
    await resize.up();
    await tester.pumpAndSettle();

    expect(store.saves, hasLength(2));
    final core.Rect resized = state.content!.fields
        .firstWhere(
          (core.ConfirmedField field) => field.id == _signatureFieldId,
        )
        .rect;
    expect(resized.width, greaterThan(moved.width));
    expect(resized.height, greaterThan(moved.height));
    expect(resized.left, closeTo(moved.left, 1e-6));
    expect(resized.top, closeTo(moved.top, 1e-6));

    // Undo restores the exact pre-drag rectangle.
    runtime.fakeClock.now = _savedAt.add(const Duration(minutes: 2));
    await tester.tap(find.byKey(const ValueKey<String>(undoReviewKey)));
    await tester.pumpAndSettle();
    expect(store.saves, hasLength(3));
    final core.Rect restored = state.content!.fields
        .firstWhere(
          (core.ConfirmedField field) => field.id == _signatureFieldId,
        )
        .rect;
    expect(restored.left, closeTo(moved.left, 1e-6));
    expect(restored.top, closeTo(moved.top, 1e-6));
    expect(restored.width, closeTo(moved.width, 1e-6));
    expect(restored.height, closeTo(moved.height, 1e-6));
  });
}
