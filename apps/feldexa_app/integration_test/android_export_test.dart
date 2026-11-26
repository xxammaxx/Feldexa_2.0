// Issue #334 acceptance criterion 5: the exported PDF of a filled value
// (EMULATOR, `emulator-5554`).
//
// Run only through the host driver, which owns the fixture staging, device
// identity, APK/git evidence, artifact pickup by the host, and cleanup:
//
//   tools/android/t334_drive_export.sh
//
// The test uses the production `main()` composition and the real encrypted
// Android store. The debug-only `de.feldexa/test.import` hook arms the
// committed synthetic `sf-001.pdf` fixture; the production import action then
// performs the real staging, preflight, and verified commit, and both real
// pages are analyzed. No fake adapter, renderer, detector, OCR result, store,
// or route is injected.
//
// Journey:
//   1. arm/import the two-page fixture and wait for both pages to reach a
//      terminal analysis state;
//   2. confirm exactly the fixture-declared field „Familienname“
//      (`assets/fixtures/catalog.json`, `p0-familienname`) by its label — never
//      the queue's first row and never a coordinate;
//   3. fill that field through the real overlay and the production
//      `FieldValueSheet` with a value that carries umlauts and fits the
//      recognised rectangle (no `FLD-001` is expected or accepted here);
//   4. export the live revision through the production `ExportController`
//      (`prepare` from the editor's current content/revision, then `run`) and
//      assert the returned `ExportArtifact`: `succeeded`, positive byte size,
//      SHA-256, an all-passing `ArtifactVerification`, page count 2, and the
//      bytes read back through `export.readArtifact` starting with `%PDF-` and
//      carrying no `/AcroForm`;
//   5. copy those bytes into the app-internal cache path the host driver reads
//      after the run, and print its path and digest as markers;
//   6. open the production `ExportPreviewScreen` for the artifact, close it,
//      and assert the session artifact is gone afterwards;
//   7. reopen the same stored document from the start list, re-assert the
//      confirmed field and its value, and run a second export through the same
//      production controller into `e2e/export-artifact-2.pdf`, again with the
//      preview-open/close/delete cycle;
//   8. import the one-page `sf-acroform-001.pdf`, a source that really carries
//      an AcroForm text field (`/FT /Tx`, widget annotation, normal
//      appearance), and export it unchanged through the same production
//      controller into `e2e/export-artifact-3.pdf`. This leg proves the
//      flattening (`EXP-002`/FR-069): the artifact carries no `/AcroForm`, no
//      `/Widget`, and no `/FT /Tx` byte sequence. It does **not** depend on the
//      analysis offering a field: whatever the queue holds, the export runs on
//      the imported revision and the host driver checks the picked-up bytes.
//
// All artifact cycles hand their bytes to the host one after the other: each
// prints `T334_ARTIFACT_STORED:INDEX=<n>` and waits for the acknowledgement of
// that index, so the driver reads each file while the app is still installed.
//
// The PDF's own media boxes and text are not asserted here: the artifact record
// exposes no geometry, and the external proof on the picked-up file is the
// host's Poppler run (`tools/android/t334_drive_export.sh`). The field rectangle
// the export actually targets is printed as `T334_FIELD_RECT` (plain numbers,
// no label and no value) so the host can measure the drawn value against it
// with `pdftotext -bbox`. The third leg carries no drawn value and therefore no
// placement measurement; its proof is the flattening byte search plus the
// `pdftotext` extraction of the fixture's own field value.
//
// Markers carry phase names, content-free counts, the picked-up artifact's path
// and digest only. No label, OCR text, title, entered value, or source id is
// printed. Every marker is printed after the `expect` that proves its fact, so
// a marker traces an assertion and never replaces one.

// The workspace `feldexa_application` package is consumed through its `src/`
// path because the repository publishes no barrel file (same documented
// situation as the existing journeys).
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/field_value_sheet.dart';
import 'package:feldexa_app/features/editor/page_view.dart';
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/features/export/export_controller.dart';
import 'package:feldexa_app/features/export/export_preview.dart';
import 'package:feldexa_app/features/fill/overflow_warning.dart';
import 'package:feldexa_app/features/fill/text_control.dart';
import 'package:feldexa_app/features/start/stored_items.dart';
import 'package:feldexa_app/main.dart' as app;
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart' hide PageView;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// App-readable staging directory prepared by the host driver.
const String _fixtureRoot = '/data/local/tmp/t334-fixtures';
const String _fixtureId = 'sf-001';
const String _fixtureSha256 =
    '22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038';
const int _fixtureSizeBytes = 5956;
const int _pageCount = 2;
const String _displayName = 't334-export.pdf';

/// The one-page source of the third leg: the synthetic AcroForm reference
/// (`tools/corpus/synthetic/make_acroform_fixture.py`). Its field value lives in
/// the widget appearance, so the host's `pdftotext` proof after the export shows
/// that the flattening kept the visible content instead of dropping it.
const String _acroFormFixtureId = 'sf-acroform-001';
const String _acroFormFixtureSha256 =
    '7f4e014482425518058e28c497b9e8bcf4a4930dec1dbd5edb74cb8c8992af9a';
const int _acroFormFixtureSizeBytes = 1424;
const int _acroFormPageCount = 1;
const String _acroFormDisplayName = 't334-acroform.pdf';

/// The page count the export of leg [index] must report.
int _expectedPageCount(int index) =>
    index == 3 ? _acroFormPageCount : _pageCount;

/// The fixture-declared text field this journey confirms, named by its label
/// (`assets/fixtures/catalog.json` → `groundTruth.fields[].label`).
const String _fieldLabel = 'Familienname';

/// The value entered into that field. It must carry umlauts: that is the point
/// of the leg. It fits the declared 300 × 18 pt rectangle.
const String _fieldValue = 'Müller';

/// The app-internal copy of the artifact bytes of export cycle [index],
/// relative to the app's temporary directory (`Directory.systemTemp`, which the
/// engine resolves to the app-internal `code_cache` on Android). The host
/// driver reads it with `adb exec-out run-as de.feldexa.app cat <path from the
/// marker>` before it clears the app data, so the driver never guesses the
/// directory name. Cycle 1 keeps the historical file name.
String _artifactRelativePath(int index) =>
    index == 1 ? 'e2e/export-artifact.pdf' : 'e2e/export-artifact-$index.pdf';

const String _pdfHeader = '%PDF-';
const String _acroFormToken = '/AcroForm';
const String _widgetToken = '/Widget';
const String _textFieldToken = '/FT /Tx';

const String _platformChannelName = 'de.feldexa/platform';

const MethodChannel _testHooks = MethodChannel('de.feldexa/test.import');
const MethodChannel _platform = MethodChannel(_platformChannelName);

const ValueKey<String> _startScreenKey = ValueKey<String>('start-screen');
const ValueKey<String> _editorScreenKey = ValueKey<String>('editor-screen');
const ValueKey<String> _importActionKey = ValueKey<String>('import-action');
const ValueKey<String> _importFailureKey = ValueKey<String>('import-failure');
const ValueKey<String> _editorPageViewKey = ValueKey<String>(
  'editor-page-view',
);
const ValueKey<String> _previewCloseKey = ValueKey<String>(
  'export-preview-close',
);

void _marker(String phase) {
  debugPrint('T334_$phase');
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
      fail('the first analysis reached analysis-failed');
    }
  }
  fail('the first analysis did not reach a terminal state before the bound');
}

Future<void> _armFile(File source, {String displayName = _displayName}) async {
  final Map<Object?, Object?>? reply = await _testHooks
      .invokeMethod<Map<Object?, Object?>>('armFile', <String, Object?>{
        'path': source.path,
        'displayName': displayName,
        'forceUnknownPreflight': false,
      });
  expect(reply?['armed'], isTrue);
}

Future<void> _clearHook() async {
  await _testHooks.invokeMethod<void>('clear');
}

Uint8List _loadFixture(String id, int sizeBytes, String sha256) {
  final File file = File('$_fixtureRoot${Platform.pathSeparator}$id.pdf');
  if (!file.existsSync()) {
    fail(
      'Fixture staging directory $_fixtureRoot is missing $id.pdf. '
      'Run tools/android/t334_drive_export.sh.',
    );
  }
  final Uint8List bytes = file.readAsBytesSync();
  expect(bytes.length, sizeBytes);
  expect(crypto.sha256.convert(bytes).toString(), sha256);
  return bytes;
}

/// The runtime of the editor that is on screen right now.
EditorRuntime _liveRuntime(WidgetTester tester) =>
    tester.widget<EditorScreen>(find.byType(EditorScreen)).runtime;

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
  expect(state.content!.pageCount, _pageCount);
  _marker(
    'ANALYSIS_READY:PAGES=${state.content!.pageCount}:'
    'SUGGESTIONS=${state.content!.suggestions.length}',
  );
  return state;
}

/// Confirms exactly the fixture-declared „Familienname“ suggestion.
///
/// The row is selected by the declared label, never by position: issue #340
/// removed an unfillable candidate from the queue, so "the first row" silently
/// became a different field.
Future<core.ConfirmedField> _confirmNamedTextField(
  WidgetTester tester,
  EditorScreenState state,
) async {
  final List<core.FieldSuggestion> matches = state.content!.suggestions
      .where(
        (core.FieldSuggestion candidate) =>
            candidate.labelText == _fieldLabel &&
            candidate.proposedType == core.FieldType.text &&
            candidate.resolution == core.SuggestionResolution.unresolved,
      )
      .toList(growable: false);
  expect(
    matches.length,
    1,
    reason: 'the fixture declares exactly one unresolved „$_fieldLabel“ field',
  );
  final core.FieldSuggestion suggestion = matches.single;
  expect(suggestion.pageIndex, 0);
  _marker('NAMED_SUGGESTION_FOUND:PAGE=${suggestion.pageIndex + 1}');

  final Finder confirm = find.byKey(
    ValueKey<String>('$confirmSuggestionKeyPrefix${suggestion.id}'),
  );
  expect(confirm, findsOneWidget);
  await tester.ensureVisible(confirm);
  await tester.pumpAndSettle();
  final String? headBefore = state.headRevisionId;
  await tester.tap(confirm);
  await _waitForCommit(
    tester,
    state,
    headBefore: headBefore,
    reason: 'confirming the named suggestion did not persist',
  );
  final core.ConfirmedField field = state.content!.fields.firstWhere(
    (core.ConfirmedField candidate) =>
        candidate.sourceSuggestionId == suggestion.id,
  );
  _marker(
    'MACHINE_FIELD_CONFIRMED:PAGE=${field.pageIndex + 1}:'
    'W_MILLI=${(field.rect.width * 1000).round()}:'
    'H_MILLI=${(field.rect.height * 1000).round()}',
  );
  // The rectangle the export layout targets, as plain numbers for the host's
  // placement measurement. Convention: display space, i.e. the origin is the
  // page's top-left corner, x grows to the right, y grows downwards, and the
  // unit is the PDF point (1/72 in) — the same convention Poppler's
  // `pdftotext -bbox` reports. The marker carries no label, no value, and no
  // text.
  _marker(
    'FIELD_RECT:PAGE=${field.pageIndex + 1}:'
    'X_MPT=${(field.rect.left * 1000).round()}:'
    'Y_MPT=${(field.rect.top * 1000).round()}:'
    'W_MPT=${(field.rect.width * 1000).round()}:'
    'H_MPT=${(field.rect.height * 1000).round()}',
  );
  return field;
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

/// Opens the production value sheet of [field] by tapping its overlay rect.
Future<void> _openValueSheet(
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
  await _pumpUntil(
    tester,
    () => find.byKey(fieldValueSheetKey).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 120),
    reason: 'tapping the ${field.type.name} field did not open the value sheet',
  );
  expect(state.selection.selectedId, field.id);
}

/// Enters [value] in the open sheet and commits it as one verified revision.
///
/// `FLD-001` is a product finding here: a value that fits the recognised
/// rectangle must not overflow, so the warning is asserted absent.
Future<void> _fillField(
  WidgetTester tester,
  EditorScreenState state,
  core.ConfirmedField field,
  String value,
) async {
  await _openValueSheet(tester, state, field);
  await tester.enterText(find.byKey(fieldTextControlInputKey), value);
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<TextField>(find.byKey(fieldTextControlInputKey))
        .controller!
        .text,
    value,
  );
  expect(find.byKey(fieldValueErrorKey), findsNothing);
  await tester.ensureVisible(find.byKey(fieldValueSaveKey));
  await tester.pumpAndSettle();
  final String? headBefore = state.headRevisionId;
  await tester.tap(find.byKey(fieldValueSaveKey));
  await _waitForCommit(
    tester,
    state,
    headBefore: headBefore,
    reason: 'the value did not commit a verified revision',
  );
  expect(
    find.byKey(fieldOverflowWarningKey),
    findsNothing,
    reason: 'a value that fits the recognised rect must not raise FLD-001',
  );
  final core.FieldValue stored = state.content!.values[field.id]!;
  expect(stored, isA<core.TextValue>());
  expect(stored.overflow, isFalse);
  expect((stored as core.TextValue).text, value);
  await _pumpUntil(
    tester,
    () => find.byKey(fieldValueSheetKey).evaluate().isEmpty,
    timeout: const Duration(seconds: 120),
    reason: 'the saved value sheet did not close',
  );
  await tester.pumpAndSettle();
  _marker('VALUE_SAVED:RUNES=${value.runes.length}:OVERFLOW=0');
}

/// Reads the artifact bytes of [artifactId] through the production channel.
Future<Uint8List> _readArtifactBytes(String artifactId) async {
  final Object? raw = await _platform.invokeMethod<Object?>(
    'export.readArtifact',
    <String, Object?>{'schemaVersion': 1, 'artifactId': artifactId},
  );
  final Object? value = androidEnvelopeValue(
    raw,
    method: 'export.readArtifact',
  );
  final Uint8List? bytes = androidBytes(value);
  if (bytes == null || bytes.isEmpty) {
    fail('export.readArtifact returned no artifact bytes');
  }
  return bytes;
}

/// The app-internal cache file the host driver picks up after the run.
File _artifactPickupFile(int index) => File(
  '${Directory.systemTemp.path}${Platform.pathSeparator}'
  '${_artifactRelativePath(index).replaceAll('/', Platform.pathSeparator)}',
);

/// The acknowledgement the host driver writes after it picked up [index].
File _pickupAckFile(int index) =>
    File('$_fixtureRoot${Platform.pathSeparator}ack-artifact-picked-up-$index');

int _indexOfBytes(Uint8List haystack, List<int> needle) {
  if (needle.isEmpty || haystack.length < needle.length) {
    return -1;
  }
  for (int index = 0; index <= haystack.length - needle.length; index++) {
    bool matches = true;
    for (int offset = 0; offset < needle.length; offset++) {
      if (haystack[index + offset] != needle[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return index;
    }
  }
  return -1;
}

/// Waits for the host driver to acknowledge that it picked artifact [index] up.
///
/// `flutter test` uninstalls the app when it exits, so the driver must read the
/// app-internal copy while this test still runs. A stale acknowledgement from an
/// aborted run must never acknowledge this phase, so the wait deletes it first
/// and then accepts only an ack written no earlier than the phase start.
Future<void> _waitForHostPickup(int index) async {
  final File ack = _pickupAckFile(index);
  final DateTime phaseStart = DateTime.now();
  try {
    if (ack.existsSync()) {
      ack.deleteSync();
    }
  } on FileSystemException {
    // A read-only staging directory can refuse the delete; the freshness check
    // below still rejects the older file.
  }
  _marker('WAITING_FOR_HOST_PICKUP:INDEX=$index');
  final DateTime deadline = phaseStart.add(const Duration(minutes: 5));
  while (true) {
    final bool acknowledged = _acknowledgedAfter(ack, phaseStart);
    if (acknowledged) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('the host driver did not acknowledge the pickup of artifact $index');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

/// Whether [ack] is an acknowledgement written no earlier than [phaseStart].
bool _acknowledgedAfter(File ack, DateTime phaseStart) {
  final DateTime threshold = phaseStart.subtract(const Duration(seconds: 1));
  try {
    return !ack.lastModifiedSync().isBefore(threshold);
  } on FileSystemException {
    return false;
  }
}

/// Leaves the editor route and reopens the stored [documentId] from the start
/// list, so the second export runs on a freshly loaded aggregate instead of the
/// in-memory state of the first one.
Future<EditorScreenState> _reopenDocument(
  WidgetTester tester,
  String documentId,
) async {
  final NavigatorState navigator = Navigator.of(
    tester.element(find.byType(EditorScreen)),
  );
  expect(
    navigator.canPop(),
    isTrue,
    reason: 'the editor route must be a poppable route',
  );
  navigator.pop();
  await _pumpUntil(
    tester,
    () =>
        find.byType(EditorScreen).evaluate().isEmpty &&
        find.byKey(_startScreenKey).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 180),
    reason: 'the editor route did not close back to the start surface',
  );
  final Finder row = find.byKey(ValueKey<String>('stored-item-$documentId'));
  await _pumpUntil(
    tester,
    () => row.evaluate().isNotEmpty,
    timeout: const Duration(seconds: 180),
    reason: 'the stored document row did not appear in the start list',
  );
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await _pumpUntil(
    tester,
    () => find.byKey(_editorScreenKey).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 300),
    reason: 'the stored document did not reopen in the editor',
  );
  expect(
    find.byKey(_importFailureKey),
    findsNothing,
    reason: 'reopening the stored document must not report a failure',
  );
  final EditorScreenState state = tester.state<EditorScreenState>(
    find.byType(EditorScreen),
  );
  await _pumpUntil(
    tester,
    () => state.content != null,
    timeout: const Duration(minutes: 3),
    reason: 'the reopened document did not deliver its content',
  );
  await _waitForAnalysisTerminal(tester, state);
  return state;
}

/// Asserts the verified artifact record of export cycle [index].
///
/// The five `ArtifactVerification` flags and the page count are the export
/// acceptance criterion; the marker follows the last assertion that proves its
/// facts.
void _expectVerifiedArtifact(ExportArtifact artifact, {required int index}) {
  expect(artifact.state, ExportArtifactState.succeeded);
  expect(artifact.byteSize, isNotNull);
  expect(artifact.byteSize! > 0, isTrue);
  expect(artifact.sha256, isNotNull);
  expect(artifact.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
  expect(artifact.pageCount, _expectedPageCount(index));
  final ArtifactVerification verification = artifact.verification!;
  expect(verification.pageCountMatches, isTrue);
  expect(verification.mediaBoxesMatch, isTrue);
  expect(verification.fontGlyphsPresent, isTrue);
  expect(verification.noInteractiveFields, isTrue);
  expect(verification.overlayBoundsWithinPage, isTrue);
  expect(verification.allChecksPassed, isTrue);
  _marker(
    'EXPORT_VERIFIED:INDEX=$index:PAGES=${artifact.pageCount}:'
    'BOUND=1:BYTES_GT_0=1:ALL_CHECKS_PASSED=1',
  );
}

/// Exports the live revision of [documentId] through the production
/// [ExportController] of the editor that is on screen.
Future<ExportArtifact> _exportLiveRevision(
  WidgetTester tester,
  EditorScreenState state,
  String documentId, {
  required int index,
}) async {
  final EditorRuntime runtime = _liveRuntime(tester);
  final LoadedDocument loaded = await runtime.loadDocument(documentId);
  final String? revisionId = state.headRevisionId;
  expect(
    revisionId,
    isNotNull,
    reason: 'export cycle $index needs a durable revision',
  );
  final ExportController controller = ExportController(
    exportPort: runtime.export,
    clock: runtime.clock,
    metrics: await loadExportFontMetrics(),
    evidenceClass: editorEvidenceClass(),
  );
  final ExportPreparation preparation = controller.prepare(
    loaded,
    content: state.content,
    revisionId: revisionId,
  );
  expect(
    preparation,
    isA<ExportPreparationReady>(),
    reason: 'the filled revision must pass the export preflight',
  );
  _marker('EXPORT_PLAN_READY:INDEX=$index');

  final ExportAttempt attempt = await controller.run(
    preparation as ExportPreparationReady,
  );
  expect(attempt, isA<ExportAttemptSucceeded>());
  final ExportArtifact artifact = (attempt as ExportAttemptSucceeded).artifact;
  _expectVerifiedArtifact(artifact, index: index);
  return artifact;
}

/// Copies the bytes of [artifact] into the app-internal cache, prints their
/// digest, and waits until the host acknowledged the pickup of [index].
Future<void> _storeArtifactForHostPickup(
  ExportArtifact artifact, {
  required int index,
}) async {
  final Uint8List bytes = await _readArtifactBytes(artifact.id);
  expect(bytes.length, artifact.byteSize);
  expect(crypto.sha256.convert(bytes).toString(), artifact.sha256);
  expect(
    String.fromCharCodes(bytes.take(_pdfHeader.length)),
    _pdfHeader,
    reason: 'the artifact must be a PDF',
  );
  expect(
    _indexOfBytes(bytes, _acroFormToken.codeUnits),
    -1,
    reason: 'a flattened product must carry no AcroForm (byte-level check)',
  );
  expect(
    _indexOfBytes(bytes, _widgetToken.codeUnits),
    -1,
    reason: 'a flattened product must carry no widget annotation',
  );
  expect(
    _indexOfBytes(bytes, _textFieldToken.codeUnits),
    -1,
    reason: 'a flattened product must carry no text form field',
  );
  _marker('ARTIFACT_FIELD_TOKENS:INDEX=$index:ACROFORM=0:WIDGET=0:FT_TX=0');
  _marker(
    'ARTIFACT_BYTES:INDEX=$index:PATH_BYTES=${bytes.length}:SHA256_MATCH=1',
  );

  final File pickup = _artifactPickupFile(index);
  pickup.parent.createSync(recursive: true);
  pickup.writeAsBytesSync(bytes, flush: true);
  final Uint8List reread = pickup.readAsBytesSync();
  final String rereadSha256 = crypto.sha256.convert(reread).toString();
  expect(reread.length, artifact.byteSize);
  expect(rereadSha256, artifact.sha256);
  _marker(
    'ARTIFACT_STORED:INDEX=$index:PATH=${pickup.path}:BYTES=${reread.length}:'
    'SHA256=$rereadSha256',
  );
  await _waitForHostPickup(index);
  _marker('HOST_PICKUP_ACKED:INDEX=$index');
}

/// Opens the production preview for [artifact], closes it, and asserts that the
/// session artifact is no longer readable afterwards.
Future<void> _previewThenAssertDeleted(
  WidgetTester tester,
  EditorRuntime runtime,
  ExportArtifact artifact, {
  required int index,
}) async {
  unawaited(
    Navigator.of(tester.element(find.byType(EditorScreen))).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ExportPreviewScreen(runtime: runtime, artifact: artifact),
      ),
    ),
  );
  await _pumpUntil(
    tester,
    () => find.byKey(exportPreviewRouteKey).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 120),
    reason: 'the production preview route did not open',
  );
  await tester.pumpAndSettle();
  expect(find.byKey(_previewCloseKey), findsOneWidget);
  _marker('PREVIEW_OPEN:INDEX=$index');

  await tester.ensureVisible(find.byKey(_previewCloseKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(_previewCloseKey));
  await _pumpUntil(
    tester,
    () => find.byKey(exportPreviewRouteKey).evaluate().isEmpty,
    timeout: const Duration(seconds: 120),
    reason: 'the preview route did not close',
  );
  _marker('PREVIEW_CLOSED:INDEX=$index');

  String? readErrorCode;
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    try {
      await _readArtifactBytes(artifact.id);
    } on PlatformException catch (error) {
      readErrorCode = error.code;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await tester.pump();
  }
  expect(
    readErrorCode,
    'EXP-002',
    reason: 'a closed preview must leave no readable session artifact',
  );
  _marker('ARTIFACT_DELETED_AFTER_PREVIEW_CLOSE:INDEX=$index:CODE=EXP-002');
}

/// One complete export cycle: production export, verified record, host pickup
/// handshake, preview open/close, and the deletion proof.
Future<void> _runExportCycle(
  WidgetTester tester,
  EditorScreenState state,
  String documentId, {
  required int index,
}) async {
  final ExportArtifact artifact = await _exportLiveRevision(
    tester,
    state,
    documentId,
    index: index,
  );
  await _storeArtifactForHostPickup(artifact, index: index);
  await _previewThenAssertDeleted(
    tester,
    _liveRuntime(tester),
    artifact,
    index: index,
  );
}

/// Imports the AcroForm reference fixture from the start surface and returns
/// its editor state.
///
/// The third leg runs on a second document of the same session, so it first
/// leaves the editor route the first two legs left behind. Nothing is confirmed
/// and nothing is filled here: the leg's claim is the flattening of the source
/// form, which must not depend on the analysis queue offering a field.
Future<EditorScreenState> _importAcroFormFixture(
  WidgetTester tester,
  File scratchSource,
) async {
  final NavigatorState navigator = Navigator.of(
    tester.element(find.byType(EditorScreen)),
  );
  expect(
    navigator.canPop(),
    isTrue,
    reason: 'the second document needs the start surface route',
  );
  navigator.pop();
  await _pumpUntil(
    tester,
    () =>
        find.byType(EditorScreen).evaluate().isEmpty &&
        find.byKey(_startScreenKey).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 180),
    reason: 'the editor route did not close back to the start surface',
  );

  await _armFile(scratchSource, displayName: _acroFormDisplayName);
  _marker('ACROFORM_FIXTURE_ARMED');
  await tester.tap(find.byKey(_importActionKey));
  await tester.pump();
  await _pumpUntil(
    tester,
    () =>
        find.byKey(_editorScreenKey).evaluate().isNotEmpty ||
        find.byKey(_importFailureKey).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 300),
    reason: 'no editor route or rejection after the armed AcroForm import',
  );
  expect(
    find.byKey(_importFailureKey),
    findsNothing,
    reason: 'the synthetic AcroForm fixture must be accepted',
  );
  final EditorScreenState state = tester.state<EditorScreenState>(
    find.byType(EditorScreen),
  );
  _marker('ACROFORM_EDITOR_READY');

  await _waitForAnalysisTerminal(tester, state);
  expect(state.content!.pageCount, _acroFormPageCount);
  _marker(
    'ACROFORM_ANALYSIS_READY:PAGES=${state.content!.pageCount}:'
    'FIELDS=${state.content!.fields.length}',
  );
  return state;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final Directory fixtureDirectory = Directory(_fixtureRoot);
  File? scratchSource;
  File? acroFormScratchSource;
  bool hookArmed = false;

  setUpAll(() {
    expect(fixtureDirectory.existsSync(), isTrue);
    final Uint8List fixtureBytes = _loadFixture(
      _fixtureId,
      _fixtureSizeBytes,
      _fixtureSha256,
    );
    _marker('FIXTURE_READY:BYTES=$_fixtureSizeBytes:MATCH=1');
    scratchSource = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}t334-'
      '${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    scratchSource!.writeAsBytesSync(fixtureBytes, flush: true);

    final Uint8List acroFormBytes = _loadFixture(
      _acroFormFixtureId,
      _acroFormFixtureSizeBytes,
      _acroFormFixtureSha256,
    );
    expect(
      _indexOfBytes(acroFormBytes, _acroFormToken.codeUnits),
      isNonNegative,
      reason: 'the staged AcroForm fixture must really carry /AcroForm',
    );
    _marker('ACROFORM_FIXTURE_READY:BYTES=$_acroFormFixtureSizeBytes:MATCH=1');
    acroFormScratchSource = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}t334-acroform-'
      '${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    acroFormScratchSource!.writeAsBytesSync(acroFormBytes, flush: true);
  });

  tearDownAll(() async {
    if (hookArmed) {
      try {
        await _clearHook();
      } on PlatformException {
        // The engine may already be detached; the driver also clears app data.
      }
    }
    final File? scratch = scratchSource;
    if (scratch != null && scratch.existsSync()) {
      scratch.deleteSync();
    }
    final File? acroFormScratch = acroFormScratchSource;
    if (acroFormScratch != null && acroFormScratch.existsSync()) {
      acroFormScratch.deleteSync();
    }
  });

  testWidgets('a filled umlaut value survives the export and a reopen', (
    tester,
  ) async {
    final EditorScreenState state = await _importAndAnalyze(
      tester,
      scratchSource!,
    );
    hookArmed = true;
    final String documentId = tester
        .widget<EditorScreen>(find.byType(EditorScreen))
        .source
        .documentId;

    // --- 1. The named fixture field, confirmed by its label -----------------
    final core.ConfirmedField field = await _confirmNamedTextField(
      tester,
      state,
    );

    // --- 2. A value with umlauts through the production value sheet ---------
    await _fillField(tester, state, field, _fieldValue);

    // --- 3. First export cycle on the freshly imported document -------------
    await _runExportCycle(tester, state, documentId, index: 1);

    // --- 4. The same document reopened from the start list -----------------
    final EditorScreenState reopened = await _reopenDocument(
      tester,
      documentId,
    );
    expect(reopened.content!.pageCount, _pageCount);
    final core.ConfirmedField reopenedField = reopened.content!.fields
        .singleWhere(
          (core.ConfirmedField candidate) => candidate.id == field.id,
        );
    expect(
      reopenedField.rect,
      field.rect,
      reason: 'the reopened document must keep the confirmed rectangle',
    );
    final core.FieldValue reopenedValue =
        reopened.content!.values[reopenedField.id]!;
    expect(reopenedValue, isA<core.TextValue>());
    expect(reopenedValue.overflow, isFalse);
    expect((reopenedValue as core.TextValue).text, _fieldValue);
    _marker(
      'DOCUMENT_REOPENED:PAGES=${reopened.content!.pageCount}:'
      'FIELD_RECT_MATCH=1:VALUE_MATCH=1',
    );

    // --- 5. Second export cycle on the reopened document -------------------
    await _runExportCycle(tester, reopened, documentId, index: 2);

    // --- 6. Third leg: an AcroForm source, exported unchanged --------------

    _marker('ACROFORM_LEG_START');
    final EditorScreenState acroFormState = await _importAcroFormFixture(
      tester,
      acroFormScratchSource!,
    );
    final String acroFormDocumentId = tester
        .widget<EditorScreen>(find.byType(EditorScreen))
        .source
        .documentId;
    expect(
      acroFormDocumentId,
      isNot(documentId),
      reason: 'the AcroForm fixture must be a second document',
    );
    await _runExportCycle(tester, acroFormState, acroFormDocumentId, index: 3);
    _marker('ACROFORM_FLATTENING_PROVEN');

    _marker('CLEANUP_DONE');
  });
}
