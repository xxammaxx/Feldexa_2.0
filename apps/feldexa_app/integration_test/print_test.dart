// T110 Android print preview + two-engine printability (SC-005; CHK019).
//
// EMULATOR (`emulator-5554`) journey through the production composition:
//
//   1. import the committed synthetic two-page `sf-001.pdf`, analyze both real
//      pages, confirm the fixture-declared „Familienname“ field by its label,
//      fill it through the production value sheet, and export the live
//      revision through the production `ExportController`;
//   2. open the production preview and tap „Drucken“. The production
//      `DeliveryService` hands the verified artifact to Android's print UI; the
//      test waits for the host driver to prove the system print preview is on
//      screen (activity/`dumpsys print` + screenshot) and to cancel it with
//      BACK, then asserts that no failed-delivery marker appeared and the
//      action is usable again;
//   3. copy the artifact bytes into the app-internal temp directory the host
//      driver reads with `run-as` while the artifact still exists, and wait for
//      the pickup acknowledgement;
//   4. close the preview and assert the session artifact is deleted (`EXP-002`).
//
// The print verification itself is host-side and belongs to the T105 harness:
// `tools/pdf_verify/verify_artifact.py` runs `qpdf`, Poppler and MuPDF at
// 300 dpi, and the driver additionally pixel-compares the Poppler and MuPDF
// renderings of every page. That comparison is the "two independent engines"
// proof; this test makes no claim about the result of the system print job.

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
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart' hide PageView;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const String _fixtureRoot = '/data/local/tmp/t110-fixtures';
const String _fixtureId = 'sf-001';
const String _fixtureSha256 =
    '22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038';
const int _fixtureSizeBytes = 5956;
const int _pageCount = 2;
const String _displayName = 't110-print.pdf';
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
const ValueKey<String> _printKey = ValueKey<String>('export-preview-print');
const ValueKey<String> _previewCloseKey = ValueKey<String>(
  'export-preview-close',
);

void _marker(String phase) {
  debugPrint('T110_$phase');
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
      'Run tools/android/t108_t110_drive.py print.',
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
  _marker('FIELD_CONFIRMED:PAGE=${field.pageIndex + 1}');
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

Future<void> _fillField(
  WidgetTester tester,
  EditorScreenState state,
  core.ConfirmedField field,
  String value,
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

File _ackFile(String name) =>
    File('$_fixtureRoot${Platform.pathSeparator}$name');

Future<void> _waitForAck(
  String name, {
  required Duration timeout,
  required String reason,
}) async {
  final File ack = _ackFile(name);
  final DateTime start = DateTime.now();
  try {
    if (ack.existsSync()) {
      ack.deleteSync();
    }
  } on FileSystemException {
    // Read-only staging still rejects stale acks by the freshness check.
  }
  final DateTime deadline = start.add(timeout);
  while (true) {
    try {
      final DateTime threshold = start.subtract(const Duration(seconds: 1));
      if (ack.existsSync() && !ack.lastModifiedSync().isBefore(threshold)) {
        return;
      }
    } on FileSystemException {
      // Not yet written.
    }
    if (DateTime.now().isAfter(deadline)) {
      fail(reason);
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

Future<Uint8List> _readArtifactBytes(EditorRuntime runtime, String id) async {
  return runtime.export.readArtifact(id);
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
      '${Directory.systemTemp.path}${Platform.pathSeparator}t110-'
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

  testWidgets('the verified artifact prints and survives the preview cycle', (
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
    final core.ConfirmedField field = await _confirmNamedTextField(
      tester,
      state,
    );
    await _fillField(tester, state, field, _fieldValue);

    final LoadedDocument loaded = await runtime.loadDocument(documentId);
    final ExportController controller = ExportController(
      exportPort: runtime.export,
      clock: runtime.clock,
      metrics: await loadExportFontMetrics(),
      evidenceClass: editorEvidenceClass(),
    );
    final ExportPreparation preparation = controller.prepare(
      loaded,
      content: state.content,
      revisionId: state.headRevisionId,
    );
    expect(preparation, isA<ExportPreparationReady>());
    final ExportAttempt attempt = await controller.run(
      preparation as ExportPreparationReady,
    );
    expect(attempt, isA<ExportAttemptSucceeded>());
    final ExportArtifact artifact =
        (attempt as ExportAttemptSucceeded).artifact;
    expect(artifact.state, ExportArtifactState.succeeded);
    expect(artifact.pageCount, _pageCount);
    expect(artifact.verification!.allChecksPassed, isTrue);
    _marker('EXPORT_VERIFIED:PAGES=${artifact.pageCount}:ALL_CHECKS_PASSED=1');

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

    // --- The production print action hands the artifact to the print UI -----
    await tester.tap(find.byKey(_printKey));
    _marker('PRINT_REQUESTED');
    await _waitForAck(
      'ack-print-preview',
      timeout: const Duration(minutes: 3),
      reason: 'the host driver did not confirm and close the print preview',
    );
    _marker('PRINT_PREVIEW_OBSERVED');
    await _pumpUntil(
      tester,
      () {
        final Finder print = find.byKey(_printKey);
        if (print.evaluate().isEmpty) {
          return false;
        }
        return tester.widget<OutlinedButton>(print).onPressed != null;
      },
      timeout: const Duration(minutes: 2),
      reason: 'the print action did not become usable again',
    );
    expect(find.byKey(exportPreviewRouteKey), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>(exportPreviewDeliveryFailedKey)),
      findsNothing,
      reason: 'print must not report a failed delivery',
    );
    _marker('PRINT_COMPLETED:DELIVERY_FAILED=0');

    // --- Pick the bytes up before the preview deletes the session artifact --
    final Uint8List bytes = await _readArtifactBytes(runtime, artifact.id);
    expect(bytes.length, artifact.byteSize);
    final File pickup = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'e2e${Platform.pathSeparator}print-artifact.pdf',
    );
    pickup.parent.createSync(recursive: true);
    pickup.writeAsBytesSync(bytes, flush: true);
    final Uint8List reread = pickup.readAsBytesSync();
    final String sha256 = crypto.sha256.convert(reread).toString();
    expect(reread.length, artifact.byteSize);
    expect(sha256, artifact.sha256);
    _marker(
      'ARTIFACT_STORED:PATH=${pickup.path}:BYTES=${reread.length}:'
      'SHA256=$sha256',
    );
    await _waitForAck(
      'ack-artifact-picked-up',
      timeout: const Duration(minutes: 10),
      reason: 'the host driver did not pick the print artifact up',
    );
    _marker('HOST_PICKUP_ACKED');

    // --- The preview still owns and then deletes the session artifact -------
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
        await _readArtifactBytes(runtime, artifact.id);
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
    _marker('CLEANUP_DONE');
  });
}
