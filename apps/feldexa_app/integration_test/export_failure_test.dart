// T108 failed or interrupted export leaves no final artifact (FR-072; SC-010).
//
// EMULATOR (`emulator-5554`) journey through the production composition:
//
//   1. import the committed synthetic two-page `sf-001.pdf`, analyze both real
//      pages, confirm the fixture-declared „Familienname“ field by its label,
//      and fill it through the production value sheet;
//   2. **IO-failure leg**: toggle the debug-only owner-write fault on the real
//      session artifact directory and run the production `ExportController`.
//      The native applier cannot create its temp file, fails with `EXP-002`,
//      and the probe proves no `.pdf` and no `.pdf.tmp` was left behind;
//   3. **preflight-failure leg**: add one real confirmed field outside the page
//      and prepare again. The plan is blocked (`EXP-003`) before any native
//      write, and the probe proves the artifact directory is still empty;
//   4. **success control**: a valid export still succeeds and publishes exactly
//      one artifact (so the empty directories above are not a probe artefact);
//   5. **interrupted delivery**: open the production preview, tap „Speichern“,
//      and let the host driver cancel the system picker with BACK. The preview
//      must not report a failure or success, must keep the artifact readable,
//      and the subsequent close must delete it (`EXP-002`), leaving the
//      artifact directory empty again.
//
// The artifact-directory probe (`ImportTestHooks`) is a declared debug-only
// test seam: content-free counts and one real owner-write toggle. It exists
// only in debuggable builds and never returns a path, file name, or byte.
//
// Markers carry phase names and content-free counts only. Every marker follows
// the `expect` that proves its fact.

// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/field_value_sheet.dart';
import 'package:feldexa_app/features/editor/page_view.dart';
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/features/export/export_controller.dart';
import 'package:feldexa_app/features/export/export_preview.dart';
import 'package:feldexa_app/features/fill/text_control.dart';
import 'package:feldexa_app/features/start/stored_items.dart';
import 'package:feldexa_app/main.dart' as app;
import 'package:feldexa_application/src/review/set_value.dart' as value_edit;
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart' hide PageView;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const String _fixtureRoot = '/data/local/tmp/t108-fixtures';
const String _fixtureId = 'sf-001';
const String _fixtureSha256 =
    '22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038';
const int _fixtureSizeBytes = 5956;
const int _pageCount = 2;
const String _displayName = 't108-failure.pdf';
const String _fieldLabel = 'Familienname';
const String _fieldValue = 'Müller';

const MethodChannel _testHooks = MethodChannel('de.feldexa/test.import');

const ValueKey<String> _startScreenKey = ValueKey<String>('start-screen');
const ValueKey<String> _editorScreenKey = ValueKey<String>('editor-screen');
const ValueKey<String> _importActionKey = ValueKey<String>('import-action');
const ValueKey<String> _importFailureKey = ValueKey<String>('import-failure');
const ValueKey<String> _editorPageViewKey = ValueKey<String>(
  'editor-page-view',
);
const ValueKey<String> _saveKey = ValueKey<String>('export-preview-save');
const ValueKey<String> _previewCloseKey = ValueKey<String>(
  'export-preview-close',
);

void _marker(String phase) {
  debugPrint('T108_$phase');
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

Future<void> _armFile(File source) async {
  final Map<Object?, Object?>? reply = await _testHooks
      .invokeMethod<Map<Object?, Object?>>('armFile', <String, Object?>{
        'path': source.path,
        'displayName': _displayName,
        'forceUnknownPreflight': false,
      });
  expect(reply?['armed'], isTrue);
}

Uint8List _loadFixture() {
  final File file = File(
    '$_fixtureRoot${Platform.pathSeparator}$_fixtureId.pdf',
  );
  if (!file.existsSync()) {
    fail(
      'Fixture staging directory $_fixtureRoot is missing $_fixtureId.pdf. '
      'Run tools/android/t108_drive_export_failure.sh.',
    );
  }
  final Uint8List bytes = file.readAsBytesSync();
  expect(bytes.length, _fixtureSizeBytes);
  expect(crypto.sha256.convert(bytes).toString(), _fixtureSha256);
  return bytes;
}

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
  expect(find.byKey(_importFailureKey), findsNothing);
  final EditorScreenState state = tester.state<EditorScreenState>(
    find.byType(EditorScreen),
  );
  _marker('EDITOR_READY');
  await _waitForAnalysisTerminal(tester, state);
  expect(state.content!.pageCount, _pageCount);
  _marker('ANALYSIS_READY:PAGES=${state.content!.pageCount}');
  return state;
}

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
  expect(matches.length, 1);
  final core.FieldSuggestion suggestion = matches.single;
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
    'FIELD_CONFIRMED:PAGE=${field.pageIndex + 1}:'
    'X_MPT=${(field.rect.left * 1000).round()}:'
    'Y_MPT=${(field.rect.top * 1000).round()}',
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

Future<void> _setScaleOnPoint(
  WidgetTester tester,
  EditorScreenState state,
  core.ConfirmedField field,
) async {
  final Size? viewport = state.viewController.viewportSize;
  expect(viewport, isNotNull);
  final PageViewMapping mapping = state.viewController.mappingFor(
    field.pageIndex,
  );
  final Offset center = Offset(
    mapping.pageRect.left + field.rect.left + field.rect.width / 2,
    mapping.pageRect.top + field.rect.top + field.rect.height / 2,
  );
  state.viewController.setView(
    scale: 1,
    pan: Offset(
      viewport!.width / 2 - center.dx,
      viewport.height / 2 - center.dy,
    ),
    clampToViewport: true,
  );
  await tester.pumpAndSettle();
}

Future<void> _fillField(
  WidgetTester tester,
  EditorScreenState state,
  core.ConfirmedField field,
  String value,
) async {
  await _setScaleOnPoint(tester, state, field);
  await tester.tapAt(_screenPoint(tester, state, field));
  await _pumpUntil(
    tester,
    () => find.byKey(fieldValueSheetKey).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 120),
    reason: 'tapping the text field did not open the value sheet',
  );
  await tester.enterText(find.byKey(fieldTextControlInputKey), value);
  await tester.pumpAndSettle();
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
  final core.FieldValue stored = state.content!.values[field.id]!;
  expect(stored, isA<core.TextValue>());
  expect((stored as core.TextValue).text, value);
  await _pumpUntil(
    tester,
    () => find.byKey(fieldValueSheetKey).evaluate().isEmpty,
    timeout: const Duration(seconds: 120),
    reason: 'the saved value sheet did not close',
  );
  _marker('VALUE_SAVED:RUNES=${value.runes.length}');
}

/// Reads the debug-only, content-free artifact-directory probe.
Future<Map<String, Object?>> _probeArtifacts() async {
  final Map<Object?, Object?>? reply = await _testHooks
      .invokeMethod<Map<Object?, Object?>>('artifactProbe');
  expect(reply, isNotNull);
  final Map<String, Object?> probe = reply!.cast<String, Object?>();
  expect(probe['wired'], isTrue);
  return probe;
}

Future<void> _expectEmptyArtifactDirectory({required String phase}) async {
  final Map<String, Object?> probe = await _probeArtifacts();
  expect(probe['pdfCount'], 0, reason: '$phase left a final .pdf behind');
  expect(probe['tmpCount'], 0, reason: '$phase left a .pdf.tmp behind');
  expect(probe['fileCount'], 0);
  _marker('NO_ARTIFACT:PHASE=$phase:PDF=0:TMP=0');
}

Future<void> _setArtifactWriteFault({required bool enabled}) async {
  final Map<Object?, Object?>? reply = await _testHooks
      .invokeMethod<Map<Object?, Object?>>(
        'setArtifactWriteFault',
        <String, Object?>{'enabled': enabled},
      );
  final Map<String, Object?> result = reply!.cast<String, Object?>();
  expect(result['wired'], isTrue);
  expect(result['applied'], isTrue);
}

ExportController _controller(EditorRuntime runtime, ExportFontMetrics metrics) {
  return ExportController(
    exportPort: runtime.export,
    clock: runtime.clock,
    metrics: metrics,
    evidenceClass: editorEvidenceClass(),
  );
}

/// The acknowledgement the host driver writes after it cancelled the picker.
File _cancelAckFile() =>
    File('$_fixtureRoot${Platform.pathSeparator}ack-save-cancel');

Future<void> _waitForSaveCancelAck() async {
  final File ack = _cancelAckFile();
  final DateTime start = DateTime.now();
  try {
    if (ack.existsSync()) {
      ack.deleteSync();
    }
  } on FileSystemException {
    // Read-only staging still rejects stale acks by the freshness check.
  }
  _marker('WAITING_FOR_SAVE_CANCEL');
  final DateTime deadline = start.add(const Duration(minutes: 5));
  while (true) {
    if (_acknowledgedAfter(ack, start)) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('the host driver did not cancel the save picker');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

bool _acknowledgedAfter(File ack, DateTime start) {
  final DateTime threshold = start.subtract(const Duration(seconds: 1));
  try {
    return !ack.lastModifiedSync().isBefore(threshold);
  } on FileSystemException {
    return false;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final Directory fixtureDirectory = Directory(_fixtureRoot);
  File? scratchSource;
  bool hookArmed = false;

  setUpAll(() {
    expect(fixtureDirectory.existsSync(), isTrue);
    final Uint8List bytes = _loadFixture();
    scratchSource = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}t108-'
      '${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    scratchSource!.writeAsBytesSync(bytes, flush: true);
    _marker('FIXTURE_READY:BYTES=$_fixtureSizeBytes:MATCH=1');
  });

  tearDownAll(() async {
    if (hookArmed) {
      try {
        await _testHooks.invokeMethod<void>('clear');
      } on PlatformException {
        // The engine may already be detached; the driver clears app data.
      }
    }
    final File? scratch = scratchSource;
    if (scratch != null && scratch.existsSync()) {
      scratch.deleteSync();
    }
  });

  testWidgets('failed and interrupted exports leave no final artifact', (
    tester,
  ) async {
    final EditorScreenState state = await _importAndAnalyze(
      tester,
      scratchSource!,
    );
    hookArmed = true;
    final EditorRuntime runtime = tester
        .widget<EditorScreen>(find.byType(EditorScreen))
        .runtime;
    final String documentId = tester
        .widget<EditorScreen>(find.byType(EditorScreen))
        .source
        .documentId;
    final ExportFontMetrics metrics = await loadExportFontMetrics();

    final core.ConfirmedField field = await _confirmNamedTextField(
      tester,
      state,
    );
    await _fillField(tester, state, field, _fieldValue);

    expect(await _probeArtifacts(), isNotNull);
    await _expectEmptyArtifactDirectory(phase: 'BASELINE');

    // --- 1. Real IO failure: the native temp file cannot be created ---------
    final LoadedDocument loaded = await runtime.loadDocument(documentId);
    final ExportController controller = _controller(runtime, metrics);
    final ExportPreparation validPreparation = controller.prepare(
      loaded,
      content: state.content,
      revisionId: state.headRevisionId,
    );
    expect(validPreparation, isA<ExportPreparationReady>());

    await _setArtifactWriteFault(enabled: true);
    _marker('ARTIFACT_WRITE_FAULT_ENABLED');
    ExportAttempt failedAttempt;
    try {
      failedAttempt = await controller.run(
        validPreparation as ExportPreparationReady,
      );
    } finally {
      await _setArtifactWriteFault(enabled: false);
      _marker('ARTIFACT_WRITE_FAULT_DISABLED');
    }
    expect(failedAttempt, isA<ExportAttemptFailed>());
    expect((failedAttempt as ExportAttemptFailed).code, 'EXP-002');
    _marker('IO_FAILURE_REPORTED:CODE=${failedAttempt.code}');
    await _expectEmptyArtifactDirectory(phase: 'IO_FAILURE');

    // --- 2. Preflight failure: the value overflows its field ----------------
    // `addField` refuses a rect outside the page, so the blocked snapshot is
    // produced by the production value command: a value far longer than the
    // recognised 300 x 18 pt field must block with EXP-001, never be shrunk or
    // truncated, and never reach a port.
    final core.RevisionContent overflowing = value_edit
        .setFieldValue(
          state.content!,
          field.id,
          value: core.TextValue(
            text: 'Übermaß ' * 80,
            lastEditedAt: runtime.clock.nowUtc().toUtc(),
          ),
          lastEditedAt: runtime.clock.nowUtc().toUtc(),
        )
        .content;
    final ExportPreparation blockedPreparation = controller.prepare(
      await runtime.loadDocument(documentId),
      content: overflowing,
      revisionId: state.headRevisionId,
    );
    // The blocked plan never reaches a port; only the preflight code matters.
    expect(blockedPreparation, isA<ExportPreparationBlocked>());
    final ExportPreparationBlocked blocked =
        blockedPreparation as ExportPreparationBlocked;
    expect(blocked.validation.warnings.map((w) => w.code), contains('EXP-001'));
    expect(blocked.validation.warnings, isNotEmpty);
    _marker(
      'PREFLIGHT_BLOCKED:CODE=EXP-001:'
      'WARNINGS=${blocked.validation.warnings.length}',
    );
    await _expectEmptyArtifactDirectory(phase: 'PREFLIGHT_BLOCKED');

    // --- 3. Success control: a valid snapshot still publishes one artifact --
    final ExportPreparation readyPreparation = controller.prepare(
      await runtime.loadDocument(documentId),
      content: state.content,
      revisionId: state.headRevisionId,
    );
    expect(readyPreparation, isA<ExportPreparationReady>());
    final ExportAttempt succeeded = await controller.run(
      readyPreparation as ExportPreparationReady,
    );
    expect(succeeded, isA<ExportAttemptSucceeded>());
    final ExportArtifact artifact =
        (succeeded as ExportAttemptSucceeded).artifact;
    expect(artifact.state, ExportArtifactState.succeeded);
    expect(artifact.verification!.allChecksPassed, isTrue);
    final Map<String, Object?> published = await _probeArtifacts();
    expect(published['pdfCount'], 1);
    expect(published['tmpCount'], 0);
    _marker('SUCCESS_CONTROL:PAGES=${artifact.pageCount}:PDF=1:TMP=0');

    // --- 4. Interrupted save: the host cancels the SAF picker ---------------
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
    await tester.tap(find.byKey(_saveKey));
    await _waitForSaveCancelAck();
    _marker('SAVE_CANCEL_ACKED');

    // A user cancellation is not a failure, and the preview must not claim a
    // completed save. The action becomes usable again and the artifact stays
    // readable (save does not delete the session artifact).
    await _pumpUntil(
      tester,
      () {
        final Finder save = find.byKey(_saveKey);
        if (save.evaluate().isEmpty) {
          return false;
        }
        return tester.widget<FilledButton>(save).onPressed != null;
      },
      timeout: const Duration(minutes: 2),
      reason: 'the save action did not become usable again after the cancel',
    );
    expect(find.byKey(exportPreviewRouteKey), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>(exportPreviewDeliveryFailedKey)),
      findsNothing,
      reason: 'a cancelled picker is not a failed save',
    );
    final Uint8List stillThere = await runtime.export.readArtifact(artifact.id);
    expect(stillThere.length, artifact.byteSize);
    _marker('SAVE_CANCELLED:REPORTED_SUCCESS=0:ARTIFACT_READABLE=1');

    await tester.tap(find.byKey(_previewCloseKey));
    await _pumpUntil(
      tester,
      () => find.byKey(exportPreviewRouteKey).evaluate().isEmpty,
      timeout: const Duration(seconds: 120),
      reason: 'the preview route did not close',
    );
    String? readErrorCode;
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      try {
        await runtime.export.readArtifact(artifact.id);
      } on PlatformException catch (error) {
        readErrorCode = error.code;
        break;
      } on FeldexaException catch (error) {
        readErrorCode = error.code;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pump();
    }
    expect(readErrorCode, 'EXP-002');
    _marker('ARTIFACT_DELETED_AFTER_PREVIEW_CLOSE:CODE=EXP-002');
    await _expectEmptyArtifactDirectory(phase: 'AFTER_PREVIEW_CLOSE');

    _marker('CLEANUP_DONE');
  });
}
