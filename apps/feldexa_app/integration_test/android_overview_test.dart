// T086D EMULATOR document overview journey (issue #282, US4 scenario 8).
//
// Run only through the host driver, which owns the fixture staging, screenshot
// handshake, device identity, and APK/git evidence:
//
//   tools/android/t086d_drive_overview.sh
//
// The test uses the production `main()` composition and the real encrypted
// Android store. The debug-only `de.feldexa/test.import` hook arms the
// committed synthetic `sf-001.pdf` fixture; the production import action then
// performs the real staging, preflight, and verified commit. No fake adapter,
// renderer, detector, OCR result, store, or route is injected.
//
// Journey:
//   1. start list loads the existing store state;
//   2. arm/import the two-page fixture and wait for the first analysis revision
//      on both real pages;
//   3. confirm exactly one text suggestion on page 1 and one on page 2 through
//      the real review panel (two confirmed fields on a two-page document);
//   4. open the T086D document overview, tap the page-1 row, enter a German
//      value through the real value sheet, and save it;
//   5. reopen the overview: the completed field is visibly „Vollständig“, the
//      other field is „Leer (optional)“, and the T085 count is visible;
//   6. continue filling the page-2 field from its overview row and save it;
//   7. reopen the overview: both fields are „Vollständig“;
//   8. tap the page-1 row again and verify the visible control still holds the
//      first value; „Weiter ausfüllen“ returns to the same editor and both
//      values remain in the editor state.
//
// Markers carry phase names and content-free counts only. No label, OCR text,
// title, path, URI, entered value, asset id, or digest is printed.

import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_app/features/editor/document_overview.dart';
import 'package:feldexa_app/features/editor/durability_status.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/field_value_sheet.dart';
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/features/fill/text_control.dart';
import 'package:feldexa_app/features/start/stored_items.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_app/main.dart' as app;
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// App-readable staging directory prepared by the host driver.
const String _fixtureRoot = '/data/local/tmp/t086d-fixtures';
const String _fixtureId = 'sf-001';
const String _fixtureSha256 =
    '22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038';
const int _fixtureSizeBytes = 5956;
const int _pageCount = 2;
const String _displayName = 't086d-overview.pdf';
const String _firstValue = 'Antrag Müller';
const String _secondValue = 'Berlin';

const ValueKey<String> _startScreenKey = ValueKey<String>('start-screen');
const ValueKey<String> _editorScreenKey = ValueKey<String>('editor-screen');
const ValueKey<String> _importActionKey = ValueKey<String>('import-action');
const ValueKey<String> _importFailureKey = ValueKey<String>('import-failure');

const MethodChannel _testHooks = MethodChannel('de.feldexa/test.import');

/// Screenshot handshake files the host driver creates after every capture.
const Map<String, String> _screenshots = <String, String>{
  'overview-partial': 'T086D_SCREENSHOT_OVERVIEW_PARTIAL',
  'overview-continued': 'T086D_SCREENSHOT_OVERVIEW_CONTINUED',
  'value-preserved': 'T086D_SCREENSHOT_VALUE_PRESERVED',
};

final AppLocalizations _de = lookupAppLocalizations(const Locale('de'));

void _marker(String phase) {
  debugPrint('T086D_$phase');
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String reason,
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
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
        'the first analysis reached analysis-failed; see the T086D_DIAG '
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

/// Waits until the value sheet exists and the software keyboard is visible.
Future<void> _waitForValueSheetAndIme(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () =>
        find.byKey(fieldValueSheetKey).evaluate().isNotEmpty &&
        tester.view.viewInsets.bottom / tester.view.devicePixelRatio >= 100,
    timeout: const Duration(seconds: 120),
    reason: 'the value sheet and the software keyboard did not appear',
  );
  await tester.pumpAndSettle();
}

/// Asserts the visible sheet, its value, and its actions are above the IME.
void _expectSheetVisibleAboveIme(WidgetTester tester, String value) {
  final double dpr = tester.view.devicePixelRatio;
  final double screenHeight = tester.view.physicalSize.height / dpr;
  final double keyboardTop = screenHeight - tester.view.viewInsets.bottom / dpr;
  final Rect sheetRect = tester.getRect(find.byKey(fieldValueSheetKey));
  expect(sheetRect.top, greaterThanOrEqualTo(0));
  expect(sheetRect.bottom, lessThanOrEqualTo(screenHeight));
  expect(find.text(value), findsOneWidget);
  final Rect inputRect = tester.getRect(find.byKey(fieldTextControlInputKey));
  final Rect saveRect = tester.getRect(find.byKey(fieldValueSaveKey));
  expect(inputRect.bottom, lessThanOrEqualTo(keyboardTop));
  expect(saveRect.bottom, lessThanOrEqualTo(keyboardTop));
  expect(find.byKey(fieldValueErrorKey), findsNothing);
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
      'Run tools/android/t086d_drive_overview.sh.',
    );
  }
  final Uint8List bytes = file.readAsBytesSync();
  expect(bytes.length, _fixtureSizeBytes);
  expect(crypto.sha256.convert(bytes).toString(), _fixtureSha256);
  return bytes;
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

/// Opens the app, imports the two-page fixture, and returns the first editor.
Future<EditorScreenState> _importAndAnalyze(WidgetTester tester) async {
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

  final Uint8List fixtureBytes = _loadFixture();
  final File scratchSource = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}t086d-'
    '${DateTime.now().microsecondsSinceEpoch}.pdf',
  );
  scratchSource.writeAsBytesSync(fixtureBytes, flush: true);
  addTearDown(() {
    try {
      scratchSource.deleteSync();
    } on FileSystemException {
      // The test process may already have been torn down.
    }
  });
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
  expect(state.content!.pageCount, _pageCount);
  _marker(
    'ANALYSIS_READY:STATE=${state.analysisStateKey}:'
    'PAGES=${state.content!.pageCount}:'
    'SUGGESTIONS=${state.content!.suggestions.length}',
  );
  return state;
}

/// Confirms one unresolved text suggestion per page through the review panel.
Future<List<core.ConfirmedField>> _confirmOneFieldPerPage(
  WidgetTester tester,
  EditorScreenState state,
) async {
  for (int pageIndex = 0; pageIndex < _pageCount; pageIndex++) {
    core.FieldSuggestion? suggestion;
    for (final core.FieldSuggestion candidate in state.content!.suggestions) {
      if (candidate.pageIndex == pageIndex &&
          candidate.proposedType == core.FieldType.text &&
          candidate.resolution == core.SuggestionResolution.unresolved) {
        suggestion = candidate;
        break;
      }
    }
    expect(
      suggestion,
      isNotNull,
      reason: 'page $pageIndex has no unresolved text suggestion',
    );
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
      reason: 'confirming the page $pageIndex suggestion did not persist',
    );
  }
  final List<core.ConfirmedField> fields = state.content!.fields;
  expect(fields, hasLength(2));
  expect(
    fields.where((core.ConfirmedField f) => f.pageIndex == 0),
    hasLength(1),
  );
  expect(
    fields.where((core.ConfirmedField f) => f.pageIndex == 1),
    hasLength(1),
  );
  _marker('TWO_FIELDS_CONFIRMED:PAGES=2');
  return fields;
}

/// Opens the T086D overview and waits for the route to settle.
Future<void> _openOverview(WidgetTester tester) async {
  await tester.tap(find.byKey(editorOverviewActionKey));
  await _pumpUntil(
    tester,
    () => find.byKey(documentOverviewScreenKey).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 120),
    reason: 'the document overview did not open',
  );
  await tester.pumpAndSettle();
}

/// Taps one field row in the overview and waits for its value sheet.
Future<void> _openFieldFromOverview(WidgetTester tester, String fieldId) async {
  final Finder row = find.byKey(
    ValueKey<String>('$documentOverviewRowKeyPrefix$fieldId'),
  );
  await tester.ensureVisible(row);
  await tester.tap(row);
  await _pumpUntil(
    tester,
    () =>
        find.byKey(documentOverviewScreenKey).evaluate().isEmpty &&
        find.byKey(fieldValueSheetKey).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 120),
    reason: 'the overview row did not continue into the value sheet',
  );
  await _waitForValueSheetAndIme(tester);
}

/// Saves [value] in the open value sheet and waits for the verified commit.
Future<void> _saveValue(
  WidgetTester tester,
  EditorScreenState state,
  String fieldId,
  String value,
) async {
  await tester.enterText(find.byKey(fieldTextControlInputKey), value);
  await tester.pumpAndSettle();
  _expectSheetVisibleAboveIme(tester, value);
  await tester.tap(find.byKey(fieldValueSaveKey));
  await _pumpUntil(
    tester,
    () {
      final core.FieldValue? saved = state.content?.values[fieldId];
      return find.byKey(fieldValueSheetKey).evaluate().isEmpty &&
          !state.reviewBusy &&
          saved is core.TextValue &&
          saved.text == value &&
          state.durabilityStatus is core.SavedDurabilityStatus;
    },
    timeout: const Duration(minutes: 5),
    reason: 'the entered value was not saved as a verified revision',
  );
  expect(find.byKey(durabilityStatusLabelKey), findsOneWidget);
  _marker('VALUE_SAVED:CHARS=${value.length}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final Directory fixtureDirectory = Directory(_fixtureRoot);
  bool hookArmed = false;

  setUpAll(() {
    expect(fixtureDirectory.existsSync(), isTrue);
    _loadFixture();
    hookArmed = true;
  });

  tearDownAll(() async {
    if (hookArmed) {
      await _clearHook();
    }
  });

  testWidgets('T086D document overview completion, continue, and values', (
    tester,
  ) async {
    final EditorScreenState state = await _importAndAnalyze(tester);
    final List<core.ConfirmedField> fields = await _confirmOneFieldPerPage(
      tester,
      state,
    );
    final core.ConfirmedField firstField = fields.firstWhere(
      (core.ConfirmedField field) => field.pageIndex == 0,
    );
    final core.ConfirmedField secondField = fields.firstWhere(
      (core.ConfirmedField field) => field.pageIndex == 1,
    );

    // Overview -> page-1 field: fill the first value through the real sheet.
    await _openOverview(tester);
    expect(find.text(_de.fieldCompletionOptionalEmpty), findsNWidgets(2));
    await _openFieldFromOverview(tester, firstField.id);
    await _saveValue(tester, state, firstField.id, _firstValue);

    // Partially filled two-page document: per-field completion is visible.
    await _openOverview(tester);
    expect(find.text(_de.fieldCompletionComplete), findsOneWidget);
    expect(find.text(_de.fieldCompletionOptionalEmpty), findsOneWidget);
    expect(find.byKey(documentOverviewCountsKey), findsOneWidget);
    // T085 counts optional-empty as complete, so the summary stays 2/2 while
    // the per-field states distinguish the filled from the empty field.
    expect(find.text(_de.fieldCount(2, 2)), findsOneWidget);
    expect(
      find.byKey(
        ValueKey<String>(
          '$documentOverviewCompletionKeyPrefix${firstField.id}',
        ),
      ),
      findsOneWidget,
    );
    await _waitForDriver('overview-partial');
    _marker('OVERVIEW_PARTIAL:COMPLETE=1:OPTIONAL_EMPTY=1');

    // Continue filling the page-2 field directly from its overview row.
    await _openFieldFromOverview(tester, secondField.id);
    await _saveValue(tester, state, secondField.id, _secondValue);

    await _openOverview(tester);
    expect(find.text(_de.fieldCompletionComplete), findsNWidgets(2));
    expect(find.text(_de.fieldCompletionOptionalEmpty), findsNothing);
    expect(find.text(_de.fieldCount(2, 2)), findsOneWidget);
    await _waitForDriver('overview-continued');
    _marker('OVERVIEW_CONTINUED:COMPLETE=2');

    // Reopen the first field: its visible control still holds the value.
    await _openFieldFromOverview(tester, firstField.id);
    expect(
      tester
          .widget<TextField>(find.byKey(fieldTextControlInputKey))
          .controller!
          .text,
      _firstValue,
    );
    await _waitForDriver('value-preserved');
    _marker('VALUE_PRESERVED:FIRST=1');
    await _closeValueSheet(tester);

    // „Weiter ausfüllen“ returns to the same editor with both values intact.
    await _openOverview(tester);
    await tester.tap(find.byKey(documentOverviewContinueKey));
    await _pumpUntil(
      tester,
      () =>
          find.byKey(documentOverviewScreenKey).evaluate().isEmpty &&
          find.byKey(_editorScreenKey).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 120),
      reason: 'continue did not return to the same editor route',
    );
    await tester.pumpAndSettle();
    expect(
      (state.content!.values[firstField.id]! as core.TextValue).text,
      _firstValue,
    );
    expect(
      (state.content!.values[secondField.id]! as core.TextValue).text,
      _secondValue,
    );
    _marker('CONTINUED_VALUES_OK:COUNT=2');
    _marker('CLEANUP_DONE');
  });
}
