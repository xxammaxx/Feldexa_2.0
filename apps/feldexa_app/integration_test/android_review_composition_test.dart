// T071A EMULATOR review/fill composition journey.
//
// Run only through the host driver, which owns the fixture staging, screenshot
// handshake, device identity, and APK/git evidence:
//
//   tools/android/t071a_drive_composition.sh
//
// The test uses the production `main()` composition. The debug-only
// `de.feldexa/test.import` hook arms a deterministic T061 damaged-page-2
// variant of the committed synthetic `sf-001.pdf` fixture; the production
// import action then performs the real encrypted staging, preflight, and
// verified commit. No fake adapter, renderer, detector, OCR result, store, or
// route is injected.
//
// Journey:
//   1. start list loads the existing store state;
//   2. arm/import the fixture and wait for the first analysis revision;
//   3. confirm one real text suggestion (T066/T065 command path);
//   4. select the confirmed field on the page (T069/T077 overlay and surface);
//   5. correct it through the T079-based value sheet, save through
//      `setFieldValue` + the verified store revision, and observe T091 saved;
//   6. leave the editor, let the T095 start list reload, reopen the same stored
//      document, and verify the saved value and confirmed field state.
//
// Screenshots are captured by the host driver at the five marked phases. The
// test waits for an acknowledgement file after each marker so the screenshot
// belongs to that state. Markers carry phase names and content-free counts only;
// no label, OCR text, title, path, URI, or entered value is printed.

import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_app/features/editor/durability_status.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/field_value_sheet.dart';
import 'package:feldexa_app/features/editor/page_view.dart';
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
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
const String _fixtureRoot = '/data/local/tmp/t071a-fixtures';
const String _fixtureId = 'sf-001';
const String _fixtureSha256 =
    '22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038';
const String _damagedFixtureSha256 =
    '57c1ade1ab2c00375ac61703db3d4ce5d27b996ea067647aba585866dc6ec221';
const int _fixtureSizeBytes = 5956;
const String _displayName = 't071a-composition.pdf';

const ValueKey<String> _startScreenKey = ValueKey<String>('start-screen');
const ValueKey<String> _editorScreenKey = ValueKey<String>('editor-screen');
const ValueKey<String> _importActionKey = ValueKey<String>('import-action');
const ValueKey<String> _importFailureKey = ValueKey<String>('import-failure');
const ValueKey<String> _editorPageViewKey = ValueKey<String>(
  'editor-page-view',
);

const MethodChannel _testHooks = MethodChannel('de.feldexa/test.import');

/// Entered German value; never printed in a marker or log.
const String _enteredValue = 'Müller & Söhne';

/// Screenshot handshake files the host driver creates after every capture.
const Map<String, String> _screenshots = <String, String>{
  'overlay-selection': 'T071A_SCREENSHOT_OVERLAY_SELECTION',
  'value-sheet': 'T071A_SCREENSHOT_VALUE_SHEET',
  'saved-status': 'T071A_SCREENSHOT_SAVED_STATUS',
  'document-list': 'T071A_SCREENSHOT_DOCUMENT_LIST',
  'reopened-value': 'T071A_SCREENSHOT_REOPENED_VALUE',
};

void _marker(String phase) {
  debugPrint('T071A_$phase');
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
///
/// The editor already turns a load/analysis/save failure into the stable
/// `analysis-failed` key. This helper records content-free page diagnostics and
/// stops immediately instead of letting the journey sit in a long pending
/// wait. The test bound leaves one minute of slack after the editor's own
/// bounded analysis guard so that guard reports first.
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
      final core.RevisionContent? content = state.content;
      _marker(
        'ANALYSIS_FAILED:CONTENT=${content == null ? 0 : 1}:PAGES=${content?.pageCount ?? 0}',
      );
      if (content != null) {
        for (final core.Page page in content.pages) {
          _marker(
            'ANALYSIS_PAGE:P=${page.index}:STATE=${page.analysis.name}:KEY=${page.failure?.messageKey ?? 'none'}',
          );
        }
      }
      fail(
        'the first analysis reached analysis-failed; see the T071A_DIAG '
        'markers in the integration log and logcat',
      );
    }
  }
  _marker('ANALYSIS_TIMEOUT:KEY=${state.analysisStateKey ?? 'pending'}');
  fail('the first analysis did not reach a terminal state before the bound');
}

/// Waits for the host driver to capture the named screenshot.
Future<void> _waitForDriver(String name) async {
  _marker(_screenshots[name]!);
  final File ack = File('$_fixtureRoot${Platform.pathSeparator}ack-$name');
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 120));
  while (!ack.existsSync()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('host driver did not acknowledge screenshot phase $name');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
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
      'Run tools/android/t071a_drive_composition.sh.',
    );
  }
  final Uint8List bytes = file.readAsBytesSync();
  expect(bytes.length, _fixtureSizeBytes);
  expect(crypto.sha256.convert(bytes).toString(), _fixtureSha256);
  return bytes;
}

/// Copies the T061 deterministic partial-damage helper
/// (`android_recognition_test.dart` `_damageSecondPageMediaBox`).
///
/// Replaces the second `/MediaBox [0 0 595.28 841.89]` occurrence in sf-001
/// with spaces of exactly the same length. All xref offsets stay valid, page 0
/// keeps its usable geometry, and page 1 has no inheritable MediaBox, so it
/// imports as `IMP-006`/`unsupportedStructure` `unreadable`. T061 proved the
/// resulting 5956-byte document reaches analysis-ready with page 1 usable.
Uint8List _damageSecondPageMediaBox(Uint8List source) {
  const List<int> needle = <int>[
    0x2f,
    0x4d,
    0x65,
    0x64,
    0x69,
    0x61,
    0x42,
    0x6f,
    0x78,
    0x20,
    0x5b,
    0x30,
    0x20,
    0x30,
    0x20,
    0x35,
    0x39,
    0x35,
    0x2e,
    0x32,
    0x38,
    0x20,
    0x38,
    0x34,
    0x31,
    0x2e,
    0x38,
    0x39,
    0x5d,
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

/// Converts a stored display-space field rect to a screen point.
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

    // T071A correction 2: import the deterministic T061 damaged page-2 source.
    // The undamaged fixture stalls a real run in the synchronous geometry
    // detector on page 2 before analysis can finish.
    final Uint8List damaged = _damageSecondPageMediaBox(fixtureBytes);
    expect(damaged.length, _fixtureSizeBytes);
    expect(damaged, isNot(orderedEquals(fixtureBytes)));
    expect(crypto.sha256.convert(damaged).toString(), _damagedFixtureSha256);
    scratchSource = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}t071a-'
      '${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    scratchSource!.writeAsBytesSync(damaged, flush: true);
    final Uint8List copied = scratchSource!.readAsBytesSync();
    expect(copied.length, _fixtureSizeBytes);
    expect(crypto.sha256.convert(copied).toString(), _damagedFixtureSha256);
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

  testWidgets('review, correct, save, leave, and reopen a stored document', (
    tester,
  ) async {
    await app.main();
    await _pumpUntil(
      tester,
      () => find.byKey(_startScreenKey).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 180),
      reason: 'the German start surface did not appear',
    );
    expect(find.byKey(_startScreenKey), findsOneWidget);
    await _pumpUntil(
      tester,
      () => find.byType(StoredItemsView).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 180),
      reason: 'the stored document/template list did not load',
    );
    _marker('START_LIST_READY');

    await _armFile(scratchSource!);
    hookArmed = true;
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
    expect(find.byKey(_editorScreenKey), findsOneWidget);
    final EditorScreen editor = tester.widget<EditorScreen>(
      find.byType(EditorScreen),
    );
    documentId = editor.source.documentId;
    _marker('EDITOR_READY');

    final EditorScreenState state = tester.state<EditorScreenState>(
      find.byType(EditorScreen),
    );
    await _waitForAnalysisTerminal(tester, state);
    expect(
      find.byKey(ValueKey<String>(state.analysisStateKey!)),
      findsOneWidget,
    );
    _marker(
      'ANALYSIS_READY:STATE=${state.analysisStateKey}:PAGES=${state.content!.pageCount}:SUGGESTIONS=${state.content!.suggestions.length}:CONFIRMED=${state.content!.fields.length}',
    );

    core.FieldSuggestion? suggestion;
    for (final core.FieldSuggestion candidate in state.content!.suggestions) {
      if (candidate.pageIndex == 0 &&
          candidate.proposedType == core.FieldType.text &&
          candidate.resolution == core.SuggestionResolution.unresolved) {
        suggestion = candidate;
        break;
      }
    }
    expect(
      suggestion,
      isNotNull,
      reason: 'the fixture must provide an unresolved text suggestion',
    );
    final core.FieldSuggestion confirmedSuggestion = suggestion!;
    final Finder confirm = find.byKey(
      ValueKey<String>('$confirmSuggestionKeyPrefix${confirmedSuggestion.id}'),
    );
    expect(confirm, findsOneWidget);
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await _pumpUntil(
      tester,
      () =>
          !state.reviewBusy &&
          state.content!.fields.any(
            (core.ConfirmedField field) =>
                field.sourceSuggestionId == confirmedSuggestion.id,
          ),
      timeout: const Duration(seconds: 180),
      reason: 'confirming the suggestion did not persist a machine field',
    );
    final core.ConfirmedField field = state.content!.fields.firstWhere(
      (core.ConfirmedField candidate) =>
          candidate.sourceSuggestionId == confirmedSuggestion.id,
    );
    expect(field.type, core.FieldType.text);
    _marker('FIELD_CONFIRMED');

    // Select the field, close the sheet so the selection/highlight is the
    // visible state for the screenshot, then reopen it for the correction.
    await tester.tapAt(_screenPoint(tester, state, field));
    await _pumpUntil(
      tester,
      () => find.byKey(fieldValueSheetKey).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 120),
      reason: 'tapping the confirmed field did not open the value sheet',
    );
    expect(state.selection.selectedId, field.id);
    await tester.tap(find.byKey(fieldValueCloseKey));
    await _pumpUntil(
      tester,
      () => find.byKey(fieldValueSheetKey).evaluate().isEmpty,
      timeout: const Duration(seconds: 120),
      reason: 'the value sheet did not close',
    );
    expect(state.selection.selectedId, field.id);
    await _waitForDriver('overlay-selection');

    await tester.tapAt(_screenPoint(tester, state, field));
    await _pumpUntil(
      tester,
      () => find.byKey(fieldValueSheetKey).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 120),
      reason: 'the reopened value sheet did not appear',
    );
    await _waitForDriver('value-sheet');

    await tester.enterText(find.byKey(fieldTextControlInputKey), _enteredValue);
    await tester.pump();
    await tester.tap(find.byKey(fieldValueSaveKey));
    await _pumpUntil(
      tester,
      () {
        final core.FieldValue? value = state.content?.values[field.id];
        return find.byKey(fieldValueSheetKey).evaluate().isEmpty &&
            !state.reviewBusy &&
            value is core.TextValue &&
            value.text == _enteredValue &&
            state.durabilityStatus is core.SavedDurabilityStatus;
      },
      timeout: const Duration(seconds: 300),
      reason: 'the corrected value was not saved as a verified revision',
    );
    expect(state.headRevisionId, isNotNull);
    expect(find.byKey(durabilityStatusLabelKey), findsOneWidget);
    expect(find.byKey(fieldValueErrorKey), findsNothing);
    _marker('VALUE_SAVED');

    final LoadedDocument savedReadBack = await editor.runtime.store
        .loadDocument(documentId);
    final core.FieldValue? savedValue = savedReadBack.content.values[field.id];
    expect(savedValue, isA<core.TextValue>());
    expect((savedValue! as core.TextValue).text, _enteredValue);
    expect(
      savedReadBack.content.fields.any(
        (core.ConfirmedField candidate) =>
            candidate.id == field.id && candidate.type == core.FieldType.text,
      ),
      isTrue,
    );
    _marker('SAVED_READBACK:OK');
    await _waitForDriver('saved-status');

    Navigator.of(tester.element(find.byType(EditorScreen))).pop();
    await _pumpUntil(
      tester,
      () =>
          find.byKey(_startScreenKey).evaluate().isNotEmpty &&
          find.byType(StoredItemsView).evaluate().isNotEmpty &&
          find
              .byKey(ValueKey<String>('stored-item-$documentId'))
              .evaluate()
              .isNotEmpty,
      timeout: const Duration(seconds: 180),
      reason: 'the start list did not reload the stored document after return',
    );
    expect(find.byType(EditorScreen), findsNothing);
    _marker('START_LIST_RELOADED');
    await _waitForDriver('document-list');

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
        final core.FieldValue? value = reopened.content?.values[field.id];
        return value is core.TextValue && value.text == _enteredValue;
      },
      timeout: const Duration(seconds: 300),
      reason: 'the reopened document did not show the saved value',
    );
    final EditorScreenState reopened = tester.state<EditorScreenState>(
      find.byType(EditorScreen),
    );
    expect(
      reopened.content!.fields.any(
        (core.ConfirmedField candidate) =>
            candidate.id == field.id && candidate.type == core.FieldType.text,
      ),
      isTrue,
    );
    final LoadedDocument reopenedReadBack = await tester
        .widget<EditorScreen>(find.byType(EditorScreen))
        .runtime
        .store
        .loadDocument(documentId);
    final core.FieldValue? reopenedValue =
        reopenedReadBack.content.values[field.id];
    expect(reopenedValue, isA<core.TextValue>());
    expect((reopenedValue! as core.TextValue).text, _enteredValue);
    expect(
      reopened.durabilityStatus,
      isA<core.SavedDurabilityStatus>(),
      reason: 'the reopened editor must show the verified durable state',
    );
    _marker('REOPENED_READBACK:OK');
    await _waitForDriver('reopened-value');
    _marker('CLEANUP_DONE');
  });
}
