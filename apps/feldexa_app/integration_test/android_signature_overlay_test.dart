// T086A EMULATOR signature + real-page overlay journey (issue #269, US4).
//
// Run only through the host driver, which owns the fixture staging, screenshot
// handshake, device identity, and APK/git evidence:
//
//   tools/android/t086a_drive_signature.sh
//
// The test uses the production `main()` composition and the real encrypted
// Android store. The debug-only `de.feldexa/test.import` hook arms a
// deterministic T061 damaged-page-2 variant of the committed synthetic
// `sf-001.pdf` fixture; the production import action then performs the real
// staging, preflight, and verified commit. No fake adapter, renderer, detector,
// OCR result, store, or route is injected.
//
// Journey:
//   1. start list loads the existing store state;
//   2. arm/import the fixture and wait for the first analysis revision on the
//      real, undamaged page 1;
//   3. leave the editor and seed exactly one confirmed *signature* field on that
//      real page through the existing `addField` application command and one
//      verified revision. This is a documented scope boundary, not a shortcut:
//      the committed detector produces **0** `signature` suggestions for this
//      fixture (see `reports/2026-11-20-us2-integration-emulator.md` §5.1), and
//      T086A may not change recognition or add a field-creation UI. The
//      signature sheet, commit path, overlay, geometry, and store are the real
//      production ones;
//   4. reopen the stored document from the start list, confirm one real machine
//      suggestion, and prove the overlay/geometry path on the real page:
//      painted, selectable, moved, and resized with one verified revision per
//      gesture and no write while the pointer is held;
//   5. tap the seeded signature field, open the T083 sheet, draw, undo, clear,
//      draw again, and apply; the editor encodes the PNG, writes the asset with
//      `store.writeSignature`, and saves one revision carrying both the
//      `SignatureValue` and its `SignatureMark`;
//   6. read the asset and value back from the encrypted store and verify the
//      digest, the PNG, and the field/document binding;
//   7. leave the editor, reopen the document, and verify the signed state and
//      the same asset id survive the round trip.
//
// Markers carry phase names and content-free counts only. No label, OCR text,
// title, path, URI, entered value, asset id, or digest is printed.

// The workspace `feldexa_ui` package is consumed through the workspace package
// config; T086A may not add an app `pubspec.yaml` dependency (same documented
// situation as `editor_screen.dart`).
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/field_value_sheet.dart';
import 'package:feldexa_app/features/editor/page_view.dart';
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/features/fill/signature_png.dart';
import 'package:feldexa_app/features/fill/signature_sheet.dart';
import 'package:feldexa_app/features/start/stored_items.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_app/main.dart' as app;
import 'package:feldexa_application/src/review/edit_field.dart' as edit;
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart' hide PageView;
import 'package:flutter/services.dart';
import 'package:feldexa_ui/feldexa_ui.dart' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;

/// App-readable staging directory prepared by the host driver.
const String _fixtureRoot = '/data/local/tmp/t086a-fixtures';
const String _fixtureId = 'sf-001';
const String _fixtureSha256 =
    '22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038';
const String _damagedFixtureSha256 =
    '57c1ade1ab2c00375ac61703db3d4ce5d27b996ea067647aba585866dc6ec221';
const int _fixtureSizeBytes = 5956;
const String _displayName = 't086a-signature.pdf';

const ValueKey<String> _startScreenKey = ValueKey<String>('start-screen');
const ValueKey<String> _editorScreenKey = ValueKey<String>('editor-screen');
const ValueKey<String> _importActionKey = ValueKey<String>('import-action');
const ValueKey<String> _importFailureKey = ValueKey<String>('import-failure');
const ValueKey<String> _editorPageViewKey = ValueKey<String>(
  'editor-page-view',
);
const ValueKey<String> _geometryPreviewKey = ValueKey<String>(
  'field-geometry-preview',
);

const MethodChannel _testHooks = MethodChannel('de.feldexa/test.import');

/// Screenshot handshake files the host driver creates after every capture.
const Map<String, String> _screenshots = <String, String>{
  'overlay-selection': 'T086A_SCREENSHOT_OVERLAY_SELECTION',
  'field-moved': 'T086A_SCREENSHOT_FIELD_MOVED',
  'field-resized': 'T086A_SCREENSHOT_FIELD_RESIZED',
  'signature-sheet': 'T086A_SCREENSHOT_SIGNATURE_SHEET',
  'signature-signed': 'T086A_SCREENSHOT_SIGNATURE_SIGNED',
  'signature-reopened': 'T086A_SCREENSHOT_SIGNATURE_REOPENED',
};

final AppLocalizations _de = lookupAppLocalizations(const Locale('de'));

void _marker(String phase) {
  debugPrint('T086A_$phase');
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String reason,
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
    if (condition()) {
      return;
    }
  }
  fail('$reason (bounded wait ${timeout.inSeconds}s expired)');
}

/// Waits for a terminal first-analysis state and fails fast on `analysis-failed`.
Future<void> _waitForAnalysisTerminal(
  WidgetTester tester,
  EditorScreenState state,
) async {
  final DateTime deadline = DateTime.now().add(
    editorAnalysisTimeout + const Duration(minutes: 1),
  );
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await tester.pump();
    final String? key = state.analysisStateKey;
    if (key == editorAnalysisReadyKey || key == editorAnalysisSkippedKey) {
      return;
    }
    if (key == editorAnalysisFailedKey) {
      fail(
        'the first analysis reached analysis-failed; see the T086A_DIAG '
        'markers in the integration log',
      );
    }
  }
  fail('the first analysis did not reach a terminal state before the bound');
}

/// Waits for the host driver to capture the named screenshot.
Future<void> _waitForDriver(String name) async {
  final File ack = File('$_fixtureRoot${Platform.pathSeparator}ack-$name');
  try {
    if (ack.existsSync()) {
      ack.deleteSync();
    }
  } on FileSystemException {
    // A read-only race cannot delete a stale file; the bounded wait below still
    // fails instead of silently accepting an old acknowledgement.
  }
  _marker(_screenshots[name]!);
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 180));
  while (!ack.existsSync()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('host driver did not acknowledge screenshot phase $name');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

Future<void> _closeValueSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(fieldValueCloseKey));
  await _pumpUntil(
    tester,
    () => find.byKey(fieldValueSheetKey).evaluate().isEmpty,
    timeout: const Duration(seconds: 120),
    reason: 'the value sheet did not close',
  );
  await tester.pumpAndSettle();
}

Future<void> _armFile(File source) async {
  final Map<Object?, Object?>? reply = await _testHooks
      .invokeMethod<Map<Object?, Object?>>('armFile', <String, Object?>{
        'path': source.path,
        'displayName': _displayName,
        'forceUnknownPreflight': false,
      });
  expect(reply?['armed'], isTrue);
}

Future<void> _clearHook() async {
  await _testHooks.invokeMethod<void>('clear');
}

Uint8List _loadFixture() {
  final File file = File(
    '$_fixtureRoot${Platform.pathSeparator}$_fixtureId.pdf',
  );
  if (!file.existsSync()) {
    fail(
      'Fixture staging directory $_fixtureRoot is missing $_fixtureId.pdf. '
      'Run tools/android/t086a_drive_signature.sh.',
    );
  }
  final Uint8List bytes = file.readAsBytesSync();
  expect(bytes.length, _fixtureSizeBytes);
  expect(crypto.sha256.convert(bytes).toString(), _fixtureSha256);
  return bytes;
}

/// Copies the T061 deterministic partial-damage helper.
///
/// Replaces the second `/MediaBox [0 0 595.28 841.89]` occurrence in sf-001
/// with spaces of exactly the same length, so page 1 (index 0) stays the real,
/// readable analysis target and page 2 imports as `IMP-006`.
Uint8List _damageSecondPageMediaBox(Uint8List source) {
  const List<int> needle = <int>[
    0x2f, 0x4d, 0x65, 0x64, 0x69, 0x61, 0x42, 0x6f, 0x78, 0x20, 0x5b, //
    0x30, 0x20, 0x30, 0x20, 0x35, 0x39, 0x35, 0x2e, 0x32, 0x38, 0x20, //
    0x38, 0x34, 0x31, 0x2e, 0x38, 0x39, 0x5d,
  ];
  int first = -1;
  for (int index = 0; index <= source.length - needle.length; index++) {
    bool matches = true;
    for (int offset = 0; offset < needle.length; offset++) {
      if (source[index + offset] != needle[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      if (first < 0) {
        first = index;
      } else {
        final Uint8List damaged = Uint8List.fromList(source);
        for (int offset = 0; offset < needle.length; offset++) {
          damaged[index + offset] = 0x20;
        }
        return damaged;
      }
    }
  }
  fail(
    'sf-001 did not contain two MediaBox arrays for the partial-damage case',
  );
}

Offset _screenPoint(
  WidgetTester tester,
  EditorScreenState state,
  core.ConfirmedField field,
) {
  final PageViewMapping mapping = state.viewController.mappingFor(
    field.pageIndex,
  );
  final Offset local = mapping.displayToView(
    Offset(
      field.rect.left + field.rect.width / 2,
      field.rect.top + field.rect.height / 2,
    ),
  );
  return tester.getTopLeft(find.byKey(_editorPageViewKey)) + local;
}

/// The runtime of the editor that is on screen right now.
///
/// A popped `EditorScreen` disposes its runtime, so every read-back after a
/// route change must go through the live editor instead of a captured one.
EditorRuntime _liveRuntime(WidgetTester tester) =>
    tester.widget<EditorScreen>(find.byType(EditorScreen)).runtime;

String _contentJson(EditorScreenState state) =>
    core.canonicalJsonEncode(state.content!.toJson());

/// Sets the view scale on one page-display point (documented `setView` seam).
Future<void> _setScaleOnPoint(
  WidgetTester tester,
  EditorScreenState state,
  int pageIndex,
  Offset displayPoint,
  double scale,
) async {
  final Size? viewport = state.viewController.viewportSize;
  expect(viewport, isNotNull, reason: 'the page viewport must be laid out');
  final PageViewMapping mapping = state.viewController.mappingFor(pageIndex);
  final Offset center = Offset(
    mapping.pageRect.left + displayPoint.dx,
    mapping.pageRect.top + displayPoint.dy,
  );
  state.viewController.setView(
    scale: scale,
    pan: Offset(
      viewport!.width / 2 - center.dx * scale,
      viewport.height / 2 - center.dy * scale,
    ),
    clampToViewport: true,
  );
  await tester.pumpAndSettle();
}

/// Resolves the T071B hit region of [field] at [displayPoint].
///
/// This is the same pure rule the editor applies at gesture start
/// (`hitTestFieldGeometry` over `layoutFieldOverlay`), evaluated from the
/// public viewer mapping so the journey can assert which region a real touch-down
/// selects instead of assuming the body.
ui.FieldGeometryHandle? _hitRegionAt(
  WidgetTester tester,
  EditorScreenState state,
  core.ConfirmedField field,
  Offset displayPoint,
) {
  final PageViewMapping mapping = state.viewController.mappingFor(
    field.pageIndex,
  );
  final Rect viewRect = ui
      .layoutFieldOverlay(
        items: <ui.FieldOverlayItem>[
          ui.FieldOverlayItem.fromConfirmedField(field),
        ],
        pageSize: mapping.pageSize.contentSize,
        pageRect: mapping.pageRectInViewport,
      )
      .single
      .viewRect;
  // `pageRectInViewport` and the gesture point share the page-view coordinate
  // space, so the mapped display point is the same value the editor hit-tests.
  final Offset local = mapping.displayToView(displayPoint);
  return ui.hitTestFieldGeometry(viewRect: viewRect, viewPoint: local);
}

/// Waits until the editor is not busy and its head differs from [headBefore].
Future<void> _waitForCommit(
  WidgetTester tester,
  EditorScreenState state, {
  required String? headBefore,
  required String reason,
}) async {
  await _pumpUntil(
    tester,
    () =>
        !state.reviewBusy &&
        state.headRevisionId != null &&
        state.headRevisionId != headBefore,
    timeout: const Duration(minutes: 3),
    reason: reason,
  );
  await tester.pumpAndSettle();
}

/// Opens the app, imports the damaged fixture, and returns the first editor.
Future<EditorScreenState> _importAndAnalyze(
  WidgetTester tester,
  File scratchSource,
) async {
  await app.main();
  await _pumpUntil(
    tester,
    () =>
        find.byKey(_startScreenKey).evaluate().isNotEmpty &&
        find.byType(StoredItemsView).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 300),
    reason: 'the German start surface and stored list did not appear',
  );
  _marker('START_LIST_READY');

  await _armFile(scratchSource);
  _marker('IMPORT_ARMED');
  await tester.tap(find.byKey(_importActionKey));
  await tester.pump();

  await _pumpUntil(
    tester,
    () =>
        find.byKey(_editorScreenKey).evaluate().isNotEmpty ||
        find.byKey(_importFailureKey).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 300),
    reason: 'no editor route or rejection after the armed import',
  );
  expect(
    find.byKey(_importFailureKey),
    findsNothing,
    reason: 'the synthetic fixture must be accepted',
  );
  final EditorScreenState state = tester.state<EditorScreenState>(
    find.byType(EditorScreen),
  );
  _marker('EDITOR_READY');

  await _waitForAnalysisTerminal(tester, state);
  _marker(
    'ANALYSIS_READY:STATE=${state.analysisStateKey}:'
    'PAGES=${state.content!.pageCount}:'
    'SUGGESTIONS=${state.content!.suggestions.length}:'
    'SIGNATURE_SUGGESTIONS='
    '${state.content!.suggestions.where((core.FieldSuggestion s) => s.proposedType == core.FieldType.signature).length}',
  );
  return state;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final Directory fixtureDirectory = Directory(_fixtureRoot);
  String documentId = '';
  String signatureFieldId = '';
  File? scratchSource;
  bool hookArmed = false;

  setUpAll(() {
    expect(fixtureDirectory.existsSync(), isTrue);
    final Uint8List fixtureBytes = _loadFixture();
    _marker('FIXTURE_READY:BYTES=$_fixtureSizeBytes:MATCH=1');
    final Uint8List damaged = _damageSecondPageMediaBox(fixtureBytes);
    expect(damaged.length, _fixtureSizeBytes);
    expect(crypto.sha256.convert(damaged).toString(), _damagedFixtureSha256);
    scratchSource = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}t086a-'
      '${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    scratchSource!.writeAsBytesSync(damaged, flush: true);
    _marker('DAMAGED_FIXTURE_READY:BYTES=$_fixtureSizeBytes:MATCH=1');
  });

  tearDownAll(() async {
    if (hookArmed) {
      try {
        await _clearHook();
      } catch (_) {
        // The engine may already be detached; the driver also clears app data.
      }
    }
    final File? scratch = scratchSource;
    if (scratch != null && scratch.existsSync()) {
      scratch.deleteSync();
    }
  });

  testWidgets('sign a real page, move/resize a field, and reopen both', (
    tester,
  ) async {
    await _importAndAnalyze(tester, scratchSource!);
    hookArmed = true;
    final EditorScreen firstEditor = tester.widget<EditorScreen>(
      find.byType(EditorScreen),
    );
    documentId = firstEditor.source.documentId;
    final EditorRuntime runtime = firstEditor.runtime;

    // --- Seed exactly one confirmed signature field on the real page --------
    final LoadedDocument current = await runtime.loadDocument(documentId);
    expect(
      current.content.suggestions
          .where(
            (core.FieldSuggestion suggestion) =>
                suggestion.proposedType == core.FieldType.signature,
          )
          .length,
      0,
      reason:
          'the committed detector produces no signature suggestion for this '
          'fixture; the seeded field is the documented T086A workaround',
    );
    final core.Rect displayBox = current.content.pages[0].geometry.displayBox;
    final core.Rect seedRect = core.Rect.fromLTWH(
      displayBox.left + displayBox.width * 0.08,
      displayBox.top + displayBox.height * 0.74,
      displayBox.width * 0.5,
      math.max(48, displayBox.height * 0.08),
    );
    signatureFieldId = runtime.ids.newId();
    final edit.EditFieldChange seeded = edit.addField(
      current.content,
      signatureFieldId,
      0,
      seedRect,
      core.FieldType.signature,
      'Unterschrift',
      runtime.clock.nowUtc().toUtc(),
    );
    await runtime.saveRevision(
      SaveRevisionRequest(
        documentId: documentId,
        expectedHead: current.meta.latestRevisionId,
        content: seeded.content,
        kind: core.RevisionKind.autosave,
      ),
    );
    _marker('SIGNATURE_FIELD_SEEDED:ON_REAL_PAGE=1');

    // Leave and reopen through the real start list so the editor loads the
    // seeded revision; the first editor's in-memory head is now stale.
    Navigator.of(tester.element(find.byType(EditorScreen))).pop();
    await _pumpUntil(
      tester,
      () =>
          find.byType(EditorScreen).evaluate().isEmpty &&
          find
              .byKey(ValueKey<String>('stored-item-$documentId'))
              .evaluate()
              .isNotEmpty,
      timeout: const Duration(seconds: 180),
      reason: 'the editor did not leave and the start list did not reload',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>('stored-item-$documentId')));
    await _pumpUntil(
      tester,
      () {
        if (find.byKey(_editorScreenKey).evaluate().isEmpty) {
          return false;
        }
        final EditorScreenState state = tester.state<EditorScreenState>(
          find.byType(EditorScreen),
        );
        return state.content!.fields.any(
          (core.ConfirmedField field) => field.id == signatureFieldId,
        );
      },
      timeout: const Duration(minutes: 3),
      reason: 'the reopened document did not show the seeded signature field',
    );
    await tester.pumpAndSettle();
    final EditorScreenState state = tester.state<EditorScreenState>(
      find.byType(EditorScreen),
    );
    expect(
      state.analysisStateKey,
      editorAnalysisSkippedKey,
      reason: 'the persisted suggestions must skip a second analysis run',
    );
    _marker('SIGNATURE_FIELD_LOADED:OVERLAY=1');

    // --- Real machine field: confirm one suggestion, then edit geometry -----
    core.FieldSuggestion? suggestion;
    for (final core.FieldSuggestion candidate in state.content!.suggestions) {
      if (candidate.pageIndex == 0 &&
          candidate.proposedType == core.FieldType.text &&
          candidate.resolution == core.SuggestionResolution.unresolved) {
        suggestion = candidate;
        break;
      }
    }
    expect(suggestion, isNotNull);
    final Finder confirm = find.byKey(
      ValueKey<String>('$confirmSuggestionKeyPrefix${suggestion!.id}'),
    );
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    final String? headBeforeConfirm = state.headRevisionId;
    await tester.tap(confirm);
    await _waitForCommit(
      tester,
      state,
      headBefore: headBeforeConfirm,
      reason: 'confirming the real suggestion did not persist a field',
    );
    final core.ConfirmedField machineField = state.content!.fields.firstWhere(
      (core.ConfirmedField candidate) =>
          candidate.sourceSuggestionId == suggestion!.id,
    );
    _marker('MACHINE_FIELD_CONFIRMED:OVERLAY=1');

    // Select it through the real tap, then show the painted/selected state.
    await tester.tapAt(_screenPoint(tester, state, machineField));
    await _pumpUntil(
      tester,
      () => find.byKey(fieldValueSheetKey).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 120),
      reason: 'tapping the confirmed field did not open the value sheet',
    );
    expect(state.selection.selectedId, machineField.id);
    await _closeValueSheet(tester);
    expect(state.selection.selectedId, machineField.id);
    await _waitForDriver('overlay-selection');
    _marker('OVERLAY_SELECTED:PAGE=0:FIELD_CONFIRMED=1');

    // --- Geometry on the real page -----------------------------------------
    // The confirmed machine suggestion is a thin strip: at the current scale its
    // view height is below the 24 dp handle hit region, so `hitTestFieldGeometry`
    // resolves its centre to an edge handle by design (contract §4 tests corner
    // and edge regions before the body). The seeded signature field is the field
    // this task composes, it is a confirmed field of the real page too, and its
    // 48 pt height gives it a reachable body region at a 1x view scale. Geometry
    // is therefore exercised on the signature field, after centring it.
    final core.ConfirmedField seededSignature = state.content!.fields
        .firstWhere(
          (core.ConfirmedField field) => field.id == signatureFieldId,
        );
    final ui.FieldGeometryHandle? machineCentreRegion = _hitRegionAt(
      tester,
      state,
      machineField,
      Offset(
        machineField.rect.left + machineField.rect.width / 2,
        machineField.rect.top + machineField.rect.height / 2,
      ),
    );
    _marker('MACHINE_CENTRE_REGION:${machineCentreRegion?.name ?? 'none'}');
    await _setScaleOnPoint(
      tester,
      state,
      0,
      Offset(
        seededSignature.rect.left + seededSignature.rect.width / 2,
        seededSignature.rect.top + seededSignature.rect.height / 2,
      ),
      1,
    );

    core.ConfirmedField signatureFieldNow() => state.content!.fields.firstWhere(
      (core.ConfirmedField field) => field.id == signatureFieldId,
    );
    core.Rect storedRect() => signatureFieldNow().rect;

    // Select the signature field through the real tap path.
    await tester.tapAt(_screenPoint(tester, state, signatureFieldNow()));
    await _pumpUntil(
      tester,
      () => find.byKey(fieldValueSheetKey).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 120),
      reason: 'tapping the signature field did not open the value sheet',
    );
    expect(state.selection.selectedId, signatureFieldId);
    await _closeValueSheet(tester);
    expect(state.selection.selectedId, signatureFieldId);

    final ui.FieldGeometryHandle? bodyRegion = _hitRegionAt(
      tester,
      state,
      signatureFieldNow(),
      Offset(
        signatureFieldNow().rect.left + signatureFieldNow().rect.width / 2,
        signatureFieldNow().rect.top + signatureFieldNow().rect.height / 2,
      ),
    );
    expect(
      bodyRegion,
      ui.FieldGeometryHandle.body,
      reason:
          'the centred signature field must expose a real body region so the '
          'composed move gesture is reachable at 1x',
    );

    Future<void> dragBody(Offset totalPx, {int steps = 12}) async {
      final String contentBefore = _contentJson(state);
      final TestGesture gesture = await tester.startGesture(
        _screenPoint(tester, state, signatureFieldNow()),
      );
      await tester.pump(const Duration(milliseconds: 60));
      for (int step = 0; step < steps; step++) {
        await gesture.moveBy(totalPx / steps.toDouble());
        await tester.pump(const Duration(milliseconds: 40));
        // Every held frame stays transient: the preview may move, the stored
        // revision and the head may not.
        expect(state.reviewBusy, isFalse);
        expect(_contentJson(state), contentBefore);
      }
      expect(
        state.geometryGestureActive,
        isTrue,
        reason: 'the drag on the selected field must be claimed as geometry',
      );
      expect(find.byKey(_geometryPreviewKey), findsWidgets);
      await gesture.up();
      await tester.pump();
    }

    final double dragScale = state.viewController.mappingFor(0).scale;
    final core.Rect beforeMove = storedRect();
    final String? headBeforeMove = state.headRevisionId;
    await dragBody(const Offset(120, 0));
    _marker(
      'MOVE_GESTURE:SCALE_MILLI=${(dragScale * 1000).round()}:'
      'DRAG_PX=120:STEPS=12',
    );
    await _waitForCommit(
      tester,
      state,
      headBefore: headBeforeMove,
      reason: 'the move gesture did not commit one verified revision',
    );
    final core.Rect afterMove = storedRect();
    _marker(
      'MOVE_DIAG:BEFORE_LEFT_MILLI=${(beforeMove.left * 1000).round()}:'
      'AFTER_LEFT_MILLI=${(afterMove.left * 1000).round()}:'
      'BEFORE_TOP_MILLI=${(beforeMove.top * 1000).round()}:'
      'AFTER_TOP_MILLI=${(afterMove.top * 1000).round()}',
    );
    expect(
      afterMove.left - beforeMove.left,
      closeTo(120 / dragScale, 2),
      reason: 'the body drag must move the field by the gesture delta/scale',
    );
    expect(afterMove.top, closeTo(beforeMove.top, 1e-6));
    expect(afterMove.width, beforeMove.width);
    expect(afterMove.height, beforeMove.height);
    _marker(
      'FIELD_MOVED:DELTA_MATCHES_SCALE=1:WIDTH_KEPT=1:HEIGHT_KEPT=1:'
      'SAVES=1:HEAD_CHANGED=1',
    );
    await _waitForDriver('field-moved');

    // Re-centre on the moved field before resizing from its bottom-right corner.
    await _setScaleOnPoint(
      tester,
      state,
      0,
      Offset(
        signatureFieldNow().rect.left + signatureFieldNow().rect.width / 2,
        signatureFieldNow().rect.top + signatureFieldNow().rect.height / 2,
      ),
      1,
    );
    final core.Rect beforeResize = storedRect();
    final String? headBeforeResize = state.headRevisionId;
    final Offset corner = Offset(
      beforeResize.left + beforeResize.width,
      beforeResize.top + beforeResize.height,
    );
    final PageViewMapping mapping = state.viewController.mappingFor(0);
    final Offset cornerScreen =
        tester.getTopLeft(find.byKey(_editorPageViewKey)) +
        mapping.displayToView(corner);
    final String contentBeforeResize = _contentJson(state);
    final TestGesture resize = await tester.startGesture(cornerScreen);
    await tester.pump(const Duration(milliseconds: 60));
    for (int step = 0; step < 12; step++) {
      await resize.moveBy(const Offset(8, 6));
      await tester.pump(const Duration(milliseconds: 40));
      expect(state.reviewBusy, isFalse);
      expect(_contentJson(state), contentBeforeResize);
    }
    expect(state.geometryGestureActive, isTrue);
    await resize.up();
    await _waitForCommit(
      tester,
      state,
      headBefore: headBeforeResize,
      reason: 'the resize gesture did not commit one verified revision',
    );
    final core.Rect afterResize = storedRect();
    expect(afterResize.width, greaterThan(beforeResize.width));
    expect(afterResize.height, greaterThan(beforeResize.height));
    expect(afterResize.left, closeTo(beforeResize.left, 1e-6));
    expect(afterResize.top, closeTo(beforeResize.top, 1e-6));
    _marker(
      'FIELD_RESIZED:WIDTH_GREW=1:HEIGHT_GREW=1:'
      'LEFT_KEPT=1:TOP_KEPT=1:SAVES=1',
    );
    await _waitForDriver('field-resized');

    // --- Signature: draw, undo, clear, draw, apply --------------------------
    final core.ConfirmedField signatureField = signatureFieldNow();
    expect(signatureField.type, core.FieldType.signature);
    await _setScaleOnPoint(
      tester,
      state,
      0,
      Offset(
        signatureField.rect.left + signatureField.rect.width / 2,
        signatureField.rect.top + signatureField.rect.height / 2,
      ),
      1,
    );
    await tester.tapAt(_screenPoint(tester, state, signatureField));
    await _pumpUntil(
      tester,
      () => find.byKey(fieldValueSheetKey).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 120),
      reason: 'tapping the signature field did not open the value sheet',
    );
    expect(find.byKey(fieldValueSignatureActionKey), findsOneWidget);
    expect(find.text('NOT_RUN'), findsNothing);
    await tester.tap(find.byKey(fieldValueSignatureActionKey));
    await _pumpUntil(
      tester,
      () => find.byType(SignatureSheet).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 120),
      reason: 'the value sheet did not open the signature sheet',
    );
    await tester.pumpAndSettle();

    // Draw two strokes, undo one, then clear and draw the final ink.
    Future<void> drawStroke(Offset drift) async {
      final Offset origin =
          tester.getCenter(find.byKey(signatureSheetCanvasKey)) -
          const Offset(120, 40);
      final TestGesture gesture = await tester.startGesture(origin + drift);
      for (int step = 0; step < 6; step++) {
        await gesture.moveBy(const Offset(35, 8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 120));
    }

    IconButton inkAction(ValueKey<String> key) =>
        tester.widget<IconButton>(find.byKey(key));

    await drawStroke(Offset.zero);
    await drawStroke(const Offset(0, 60));
    expect(inkAction(signatureSheetUndoKey).onPressed, isNotNull);
    expect(inkAction(signatureSheetClearKey).onPressed, isNotNull);
    await tester.tap(find.byKey(signatureSheetUndoKey));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.byKey(signatureSheetClearKey));
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      inkAction(signatureSheetUndoKey).onPressed,
      isNull,
      reason: 'clear must empty the canvas',
    );
    await drawStroke(const Offset(20, 30));
    expect(inkAction(signatureSheetUndoKey).onPressed, isNotNull);
    _marker('SIGNATURE_SHEET_INK:DRAW=1:UNDO=1:CLEAR=1:REDRAW=1');
    await _waitForDriver('signature-sheet');

    // Captured before the commit: the saved read-back must name a new revision.
    final String? headBeforeSignature = state.headRevisionId;
    await tester.tap(find.byKey(signatureSheetApplyKey));
    await _pumpUntil(
      tester,
      () =>
          find.byType(SignatureSheet).evaluate().isEmpty &&
          find.byKey(fieldValueSheetKey).evaluate().isEmpty &&
          state.content!.signatures.containsKey(signatureFieldId) &&
          !state.reviewBusy &&
          state.durabilityStatus is core.SavedDurabilityStatus,
      timeout: const Duration(minutes: 5),
      reason: 'the signature asset and revision did not settle as saved',
    );
    await tester.pumpAndSettle();
    expect(state.headRevisionId, isNot(headBeforeSignature));

    final core.FieldValue? signedValue =
        state.content!.values[signatureFieldId];
    expect(signedValue, isA<core.SignatureValue>());
    final core.SignatureMark mark =
        state.content!.signatures[signatureFieldId]!;
    expect(
      mark.assetId,
      (signedValue! as core.SignatureValue).signatureAssetId,
    );
    expect(mark.fieldId, signatureFieldId);
    expect(mark.pageIndex, signatureField.pageIndex);
    expect(mark.widthPx, lessThanOrEqualTo(signaturePngMaxEdgePx));
    expect(mark.heightPx, lessThanOrEqualTo(signaturePngMaxEdgePx));
    _marker(
      'SIGNATURE_STATE:BOUND=1:MARKS=${state.content!.signatures.length}:'
      'WIDTH_LE_1024=1:HEIGHT_LE_1024=1',
    );
    await _waitForDriver('signature-signed');

    // --- Verified store read-back ------------------------------------------
    final LoadedDocument signed = await _liveRuntime(tester).store
        .loadDocument(documentId);
    final core.FieldValue? storedValue =
        signed.content.values[signatureFieldId];
    expect(storedValue, isA<core.SignatureValue>());
    final core.SignatureMark storedMark =
        signed.content.signatures[signatureFieldId]!;
    expect(
      (storedValue! as core.SignatureValue).signatureAssetId,
      storedMark.assetId,
    );
    final Uint8List assetBytes = await _liveRuntime(tester).store
        .readSignature(documentId, storedMark.assetId);
    expect(assetBytes, isNotEmpty);
    expect(
      crypto.sha256.convert(assetBytes).toString(),
      storedMark.sha256,
      reason: 'the stored PNG digest must match the mark',
    );
    expect(
      assetBytes.sublist(0, 8),
      orderedEquals(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
      reason: 'the stored asset must be a real PNG stream',
    );
    final img.Image decoded = img.decodePng(assetBytes)!;
    expect(decoded.width, storedMark.widthPx);
    expect(decoded.height, storedMark.heightPx);
    expect(signed.meta.latestRevisionId, isNotNull);
    expect(signed.meta.latestRevisionId, isNot(headBeforeSignature));
    _marker(
      'SIGNATURE_READBACK:OK:PNG=1:DIGEST_MATCH=1:'
      'DIMS_MATCH=1:VALUE_BOUND=1:MARK_BOUND=1',
    );

    // --- Reopen and verify the binding survives ----------------------------
    Navigator.of(tester.element(find.byType(EditorScreen))).pop();
    await _pumpUntil(
      tester,
      () =>
          find.byType(EditorScreen).evaluate().isEmpty &&
          find
              .byKey(ValueKey<String>('stored-item-$documentId'))
              .evaluate()
              .isNotEmpty,
      timeout: const Duration(seconds: 180),
      reason: 'the editor did not leave after the signature commit',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>('stored-item-$documentId')));
    await _pumpUntil(
      tester,
      () {
        if (find.byKey(_editorScreenKey).evaluate().isEmpty) {
          return false;
        }
        final EditorScreenState reopened = tester.state<EditorScreenState>(
          find.byType(EditorScreen),
        );
        final core.FieldValue? value =
            reopened.content?.values[signatureFieldId];
        return value is core.SignatureValue &&
            value.signatureAssetId == storedMark.assetId;
      },
      timeout: const Duration(minutes: 3),
      reason: 'the reopened document did not show the stored signature',
    );
    await tester.pumpAndSettle();
    final EditorScreenState reopened = tester.state<EditorScreenState>(
      find.byType(EditorScreen),
    );
    expect(
      reopened.content!.signatures[signatureFieldId]!.assetId,
      storedMark.assetId,
    );
    expect(
      reopened.content!.signatures[signatureFieldId]!.sha256,
      storedMark.sha256,
    );
    final Uint8List reopenedAsset = await _liveRuntime(tester).store
        .readSignature(
          documentId,
          reopened.content!.signatures[signatureFieldId]!.assetId,
        );
    expect(crypto.sha256.convert(reopenedAsset).toString(), storedMark.sha256);
    _marker('SIGNATURE_REOPENED_READBACK:OK:ASSET_SAME=1');

    final core.ConfirmedField reopenedSignature = reopened.content!.fields
        .firstWhere(
          (core.ConfirmedField field) => field.id == signatureFieldId,
        );
    // The reopened route starts at fit-width with the page top in view, so the
    // signed field (74 % down the page) must be centred before it can be tapped.
    await _setScaleOnPoint(
      tester,
      reopened,
      0,
      Offset(
        reopenedSignature.rect.left + reopenedSignature.rect.width / 2,
        reopenedSignature.rect.top + reopenedSignature.rect.height / 2,
      ),
      1,
    );
    await tester.tapAt(_screenPoint(tester, reopened, reopenedSignature));
    await _pumpUntil(
      tester,
      () => find.byKey(fieldValueSheetKey).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 120),
      reason: 'the reopened value sheet did not open for the signed field',
    );
    await tester.pumpAndSettle();
    expect(
      find.text(_de.a11ySignatureSigned),
      findsOneWidget,
      reason: 'the reopened sheet must show the signed state from the store',
    );
    expect(
      find.text(_de.a11ySignatureUnsigned),
      findsNothing,
      reason: 'a signed field must never be shown as unsigned',
    );
    await _waitForDriver('signature-reopened');
    await _closeValueSheet(tester);
    _marker('CLEANUP_DONE');
  });
}
