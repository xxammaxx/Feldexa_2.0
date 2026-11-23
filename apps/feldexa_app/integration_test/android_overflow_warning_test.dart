// T086C EMULATOR FLD-001 overflow journey (issue #281, US4).
//
// Run only through the host driver, which owns the fixture staging, screenshot
// handshake, device identity, and APK/git evidence:
//
//   tools/android/t086c_drive_overflow.sh
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
//   3. confirm one real machine text suggestion through the production review
//      surface, so the field under test carries a real recognised rectangle;
//   4. open its value sheet on the real page, enter a text that cannot fit that
//      rectangle, and save;
//   5. prove the FLD-001 state on the device: the warning is visible, the sheet
//      stays on the field, the complete text is still in the control and in the
//      stored `TextValue`, and `TextValue.overflow` is true;
//   6. close the sheet, leave the editor, reopen the stored document from the
//      start list, and verify the reopened field shows the warning and the same
//      complete text (the flag and the value survived the round trip).
//
// Markers carry phase names and content-free counts only. No label, OCR text,
// title, path, URI, entered value, asset id, or digest is printed.

// The workspace `feldexa_ui` package is consumed through the workspace package
// config; T086C may not add an app `pubspec.yaml` dependency (same documented
// situation as `editor_screen.dart`).
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/field_value_sheet.dart';
import 'package:feldexa_app/features/editor/page_view.dart';
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/features/fill/overflow_warning.dart';
import 'package:feldexa_app/features/fill/text_control.dart';
import 'package:feldexa_app/features/start/stored_items.dart';
import 'package:feldexa_app/main.dart' as app;
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart' hide PageView;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// App-readable staging directory prepared by the host driver.
const String _fixtureRoot = '/data/local/tmp/t086c-fixtures';
const String _fixtureId = 'sf-001';
const String _fixtureSha256 =
    '22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038';
const String _damagedFixtureSha256 =
    '57c1ade1ab2c00375ac61703db3d4ce5d27b996ea067647aba585866dc6ec221';
const int _fixtureSizeBytes = 5956;
const String _displayName = 't086c-overflow.pdf';

const ValueKey<String> _startScreenKey = ValueKey<String>('start-screen');
const ValueKey<String> _editorScreenKey = ValueKey<String>('editor-screen');
const ValueKey<String> _importActionKey = ValueKey<String>('import-action');
const ValueKey<String> _importFailureKey = ValueKey<String>('import-failure');
const ValueKey<String> _editorPageViewKey = ValueKey<String>(
  'editor-page-view',
);

const MethodChannel _testHooks = MethodChannel('de.feldexa/test.import');

/// Screenshot handshake files the host driver creates after every capture.
///
/// The values carry the phase name only; [_waitForDriver] adds the single
/// `T086C_` marker prefix.
const Map<String, String> _screenshots = <String, String>{
  'overflow-warning': 'SCREENSHOT_OVERFLOW_WARNING',
  'overflow-closed': 'SCREENSHOT_OVERFLOW_CLOSED',
  'overflow-reopened': 'SCREENSHOT_OVERFLOW_REOPENED',
};

/// The entered value: 176 runes of German text, far wider than any recognised
/// strip on this page and never shortened by the app.
const String _tooLongText =
    'Der vollständige eingegebene Text darf niemals gekürzt werden, auch dann '
    'nicht, wenn er nicht in das erkannte Feld passt. Grüße, Straße, Ärztin, '
    'Überweisung, Prüfungsordnung, Fußgängerzone, Größe, Müllabfuhr, Zähler';

void _marker(String phase) {
  debugPrint('T086C_$phase');
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
        'the first analysis reached analysis-failed; see the T086C_DIAG '
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
  final Finder close = find.byKey(fieldValueCloseKey);
  await tester.ensureVisible(close);
  await tester.pumpAndSettle();
  await tester.tap(close);
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
      'Run tools/android/t086c_drive_overflow.sh.',
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

/// Centres [field] at a readable 1x scale and taps it on the real page.
///
/// The review header and the page scroll move a stored field out of the viewport
/// after a route change, and a tap only reaches the overlay when its display
/// point is inside the visible page rectangle. Centring first is the documented
/// viewer seam (`PageViewController.setView`), not a geometry shortcut.
Future<void> _centreAndTapField(
  WidgetTester tester,
  EditorScreenState state,
  core.ConfirmedField field,
) async {
  await _setScaleOnPoint(
    tester,
    state,
    field.pageIndex,
    Offset(
      field.rect.left + field.rect.width / 2,
      field.rect.top + field.rect.height / 2,
    ),
    1,
  );
  await tester.tapAt(_screenPoint(tester, state, field));
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
    'SUGGESTIONS=${state.content!.suggestions.length}',
  );
  return state;
}

/// Confirms the first unresolved real machine text suggestion on page 1.
Future<core.ConfirmedField> _confirmMachineTextField(
  WidgetTester tester,
  EditorScreenState state,
) async {
  core.FieldSuggestion? suggestion;
  for (final core.FieldSuggestion candidate in state.content!.suggestions) {
    if (candidate.pageIndex == 0 &&
        candidate.proposedType == core.FieldType.text &&
        candidate.resolution == core.SuggestionResolution.unresolved) {
      suggestion = candidate;
      break;
    }
  }
  expect(suggestion, isNotNull, reason: 'no unresolved text suggestion');
  final Finder confirm = find.byKey(
    ValueKey<String>('$confirmSuggestionKeyPrefix${suggestion!.id}'),
  );
  await tester.ensureVisible(confirm);
  await tester.pumpAndSettle();
  final String? headBefore = state.headRevisionId;
  await tester.tap(confirm);
  await _waitForCommit(
    tester,
    state,
    headBefore: headBefore,
    reason: 'confirming the real suggestion did not persist a field',
  );
  final core.ConfirmedField field = state.content!.fields.firstWhere(
    (core.ConfirmedField candidate) =>
        candidate.sourceSuggestionId == suggestion!.id,
  );
  _marker(
    'MACHINE_FIELD_CONFIRMED:OVERLAY=1:'
    'W_MILLI=${(field.rect.width * 1000).round()}:'
    'H_MILLI=${(field.rect.height * 1000).round()}',
  );
  return field;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final Directory fixtureDirectory = Directory(_fixtureRoot);
  String documentId = '';
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
      '${Directory.systemTemp.path}${Platform.pathSeparator}t086c-'
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

  testWidgets('a too-long entry shows FLD-001, keeps the value, and reopens', (
    tester,
  ) async {
    await _importAndAnalyze(tester, scratchSource!);
    hookArmed = true;
    final EditorScreen firstEditor = tester.widget<EditorScreen>(
      find.byType(EditorScreen),
    );
    documentId = firstEditor.source.documentId;

    // --- One real machine text field on the real page -----------------------
    final EditorScreenState state = tester.state<EditorScreenState>(
      find.byType(EditorScreen),
    );
    core.ConfirmedField field = await _confirmMachineTextField(tester, state);

    // --- Enter a text the field cannot hold and commit it -------------------
    await _centreAndTapField(tester, state, field);
    await _pumpUntil(
      tester,
      () => find.byKey(fieldValueSheetKey).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 120),
      reason: 'tapping the confirmed field did not open the value sheet',
    );
    expect(state.selection.selectedId, field.id);
    _marker(
      'SHEET_OPEN:OVERFLOW_BEFORE='
      '${state.content!.values[field.id]?.overflow == true ? 1 : 0}',
    );
    expect(
      find.byKey(fieldOverflowWarningKey),
      findsNothing,
      reason: 'the fresh field has no stored overflow yet',
    );

    await tester.enterText(find.byKey(fieldTextControlInputKey), _tooLongText);
    await tester.pumpAndSettle();
    final String? headBeforeSave = state.headRevisionId;
    await tester.tap(find.byKey(fieldValueSaveKey));
    await _waitForCommit(
      tester,
      state,
      headBefore: headBeforeSave,
      reason: 'the overflowing value did not commit one verified revision',
    );
    await _pumpUntil(
      tester,
      () => find.byKey(fieldOverflowWarningKey).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 120),
      reason: 'the FLD-001 warning did not appear after the commit',
    );

    final core.TextValue storedNow =
        state.content!.values[field.id]! as core.TextValue;
    expect(storedNow.overflow, isTrue);
    expect(storedNow.text, _tooLongText);
    _marker(
      'OVERFLOW_WARNING_VISIBLE:OVERFLOW=1:SHEET_OPEN=1:'
      'RUNES=${storedNow.text.runes.length}:'
      'ENTERED_RUNES=${_tooLongText.runes.length}:'
      'W_MILLI=${(field.rect.width * 1000).round()}:'
      'H_MILLI=${(field.rect.height * 1000).round()}',
    );

    // The complete draft is still in the control: nothing was truncated.
    final TextField control = tester.widget<TextField>(
      find.byKey(fieldTextControlInputKey),
    );
    expect(control.controller!.text, _tooLongText);
    _marker(
      'VALUE_RETAINED:IN_CONTROL=1:RUNES=${control.controller!.text.runes.length}',
    );
    await _waitForDriver('overflow-warning');

    // --- Close, leave, reopen from the real start list ----------------------
    await _closeValueSheet(tester);
    _marker('SHEET_CLOSED');
    await tester.pumpAndSettle();
    await _waitForDriver('overflow-closed');

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
        final EditorScreenState reopened = tester.state<EditorScreenState>(
          find.byType(EditorScreen),
        );
        // The editor route exists before its document content is loaded, so the
        // content and the value lookup are both guarded here.
        final core.RevisionContent? content = reopened.content;
        return content != null && content.values[field.id] is core.TextValue;
      },
      timeout: const Duration(minutes: 3),
      reason: 'the reopened document did not show the stored value',
    );
    await tester.pumpAndSettle();
    final EditorScreenState reopenedState = tester.state<EditorScreenState>(
      find.byType(EditorScreen),
    );
    final core.RevisionContent reopenedContent = reopenedState.content!;
    field = reopenedContent.fields.firstWhere(
      (core.ConfirmedField candidate) => candidate.id == field.id,
    );

    // --- The reopened field shows the warning and the full text -------------
    await _centreAndTapField(tester, reopenedState, field);
    await _pumpUntil(
      tester,
      () => find.byKey(fieldValueSheetKey).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 120),
      reason: 'reopening the stored field did not open the value sheet',
    );
    await _pumpUntil(
      tester,
      () => find.byKey(fieldOverflowWarningKey).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 120),
      reason: 'the reopened field did not show the persisted FLD-001 warning',
    );
    final TextField reopenedControl = tester.widget<TextField>(
      find.byKey(fieldTextControlInputKey),
    );
    expect(reopenedControl.controller!.text, _tooLongText);
    final core.TextValue reopenedValue =
        reopenedState.content!.values[field.id]! as core.TextValue;
    expect(reopenedValue.overflow, isTrue);
    expect(reopenedValue.text, _tooLongText);
    _marker(
      'OVERFLOW_REOPENED:OK:WARNING=1:RUNES='
      '${reopenedControl.controller!.text.runes.length}:OVERFLOW=1',
    );
    await _waitForDriver('overflow-reopened');

    // --- Read the stored value back from the real encrypted store ----------
    final LoadedDocument reloaded = await _liveRuntime(tester)
        .loadDocument(documentId);
    final core.FieldValue? persisted = reloaded.content.values[field.id];
    expect(persisted, isA<core.TextValue>());
    final core.TextValue persistedText = persisted! as core.TextValue;
    expect(persistedText.overflow, isTrue);
    expect(persistedText.text, _tooLongText);
    _marker(
      'OVERFLOW_PERSISTED:STORED=1:RUNES=${persistedText.text.runes.length}:'
      'OVERFLOW=1:TRUNCATED=0',
    );

    await _closeValueSheet(tester);
    _marker('CLEANUP_DONE');
  });
}
