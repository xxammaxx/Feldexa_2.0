// T086 EMULATOR two-page touch fill journey (US4 Independent Test, issue #86).
//
// Run only through the host driver, which owns the fixture staging, screenshot
// handshake, device identity, APK/git evidence, and cleanup:
//
//   tools/android/t086_drive_fill.sh
//
// The test uses the production `main()` composition and the real encrypted
// Android store. The debug-only `de.feldexa/test.import` hook arms the
// committed synthetic `sf-001.pdf` fixture; the production import action then
// performs the real staging, preflight, and verified commit. Both real pages
// are analyzed, and no fake adapter, renderer, detector, OCR result, store, or
// route is injected.
//
// Journey:
//   1. start list loads the existing store state;
//   2. arm/import the two-page fixture and wait for the first analysis revision
//      on both real pages;
//   3. confirm exactly one real machine text suggestion on page 1 and one on
//      page 2 through the production review surface;
//   4. seed the remaining field types (text, number, date, checkbox, multiline,
//      signature) on the real pages through the existing `addField` application
//      command and one verified revision. This is the same documented scope
//      boundary T086A used: the committed detector produces no number, date,
//      checkbox, multiline, or signature suggestion for this fixture, and T086
//      may not change recognition or add a field-creation UI. The overlay,
//      value sheet, type-appropriate controls, commit path, and store are the
//      real production ones;
//   5. reopen the stored document from the start list, fill the page-1 fields by
//      touch through the overlay and the production `FieldValueSheet`: the real
//      machine field with a text that deliberately exceeds its region (FLD-001,
//      complete value kept), a German text with umlauts and ß, a German number,
//      a German date, and a checkbox;
//   6. navigate to page 2 with the real page strip, fill a text, a multiline
//      value, and a drawn signature;
//   7. navigate back to page 1, verify every entered value survived the page
//      navigation unchanged, reopen every filled field (both pages) to verify
//      the visible control still holds the value and stays editable, then edit
//      the page-1 text again and verify the updated value is stored;
//   8. read every value and the signature mark back from the real encrypted
//      store and verify nothing was truncated.
//
// Markers carry phase names and content-free counts only. No label, OCR text,
// title, path, URI, entered value, asset id, or digest is printed.

// The workspace `feldexa_application` package is consumed through its `src/`
// path because the repository publishes no barrel file; T086 may not add an
// app dependency or a new public application surface (same documented
// situation as `editor_screen.dart` and the T086A journey).
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/field_value_sheet.dart';
import 'package:feldexa_app/features/editor/page_view.dart';
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/features/fill/checkbox_control.dart';
import 'package:feldexa_app/features/fill/overflow_warning.dart';
import 'package:feldexa_app/features/fill/signature_png.dart';
import 'package:feldexa_app/features/fill/signature_sheet.dart';
import 'package:feldexa_app/features/fill/text_control.dart';
import 'package:feldexa_app/features/start/stored_items.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_app/main.dart' as app;
import 'package:feldexa_application/src/review/edit_field.dart' as edit;
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:feldexa_ui/feldexa_ui.dart'
    show
        FieldOverlayItem,
        FieldOverlayProvenance,
        FieldSelectionSurface,
        hitTestFieldSelection;
import 'package:flutter/gestures.dart'
    show HitTestEntry, HitTestResult, HitTestTarget;
import 'package:flutter/material.dart' hide PageView;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// App-readable staging directory prepared by the host driver.
const String _fixtureRoot = '/data/local/tmp/t086-fixtures';
const String _fixtureId = 'sf-001';
const String _fixtureSha256 =
    '22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038';
const int _fixtureSizeBytes = 5956;
const int _pageCount = 2;
const String _displayName = 't086-fill.pdf';

const ValueKey<String> _startScreenKey = ValueKey<String>('start-screen');
const ValueKey<String> _editorScreenKey = ValueKey<String>('editor-screen');
const ValueKey<String> _importActionKey = ValueKey<String>('import-action');
const ValueKey<String> _importFailureKey = ValueKey<String>('import-failure');
const ValueKey<String> _editorPageViewKey = ValueKey<String>(
  'editor-page-view',
);
const ValueKey<String> _pageStripPreviousKey = ValueKey<String>(
  'page-strip-previous',
);
const ValueKey<String> _pageStripNextKey = ValueKey<String>('page-strip-next');

const MethodChannel _testHooks = MethodChannel('de.feldexa/test.import');

/// Screenshot handshake files the host driver creates after every capture.
const Map<String, String> _screenshots = <String, String>{
  'page1-values': 'T086_SCREENSHOT_PAGE1_VALUES',
  'overflow-warning': 'T086_SCREENSHOT_OVERFLOW_WARNING',
  'page2-signed': 'T086_SCREENSHOT_PAGE2_SIGNED',
  'page1-preserved': 'T086_SCREENSHOT_PAGE1_PRESERVED',
};

/// Entered values; document content, never printed in a marker or log.
const String _overflowText =
    'Der vollständige eingegebene Text darf niemals gekürzt werden, auch dann '
    'nicht, wenn er nicht in das erkannte Feld passt. Grüße, Straße, Ärztin, '
    'Überweisung, Prüfungsordnung, Fußgängerzone, Größe, Müllabfuhr, Zähler';
const String _textValue = 'Müller & Söhne';
const String _editedTextValue = 'Müller & Söhne GmbH';
const String _numberValue = '1.234,56';
const String _dateValue = '24.12.2025';
const String _pageTwoTextValue = 'Berlin';
const String _multilineValue = 'Zeile eins – Grüße\nZeile zwei – Straße';

/// The page-2 text/date/number canonical forms the sheet's parsers produce.
const String _numberCanonical = '1234.56';
const String _dateCanonical = '2025-12-24';

/// Field roles seeded through the existing `addField` command.
enum _SeededRole {
  text('text', core.FieldType.text, 'Bezeichnung', 0.45, 0.05),
  number('number', core.FieldType.number, 'Betrag', 0.30, 0.04),
  date('date', core.FieldType.date, 'Datum', 0.25, 0.04),
  checkbox('checkbox', core.FieldType.checkbox, 'Zustimmung', 0.08, 0.03),
  pageTwoText('page2-text', core.FieldType.text, 'Ort', 0.40, 0.05),
  multiline('multiline', core.FieldType.multiline, 'Bemerkung', 0.55, 0.12),
  signature('signature', core.FieldType.signature, 'Unterschrift', 0.50, 0.08);

  const _SeededRole(
    this.role,
    this.type,
    this.label,
    this.widthFraction,
    this.heightFraction,
  );

  final String role;
  final core.FieldType type;
  final String label;
  final double widthFraction;
  final double heightFraction;
}

final AppLocalizations _de = lookupAppLocalizations(const Locale('de'));

void _marker(String phase) {
  debugPrint('T086_$phase');
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String reason,
  String Function()? diagnosis,
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await tester.pump();
    if (condition()) {
      return;
    }
  }
  final String detail = diagnosis == null ? '' : '\n${diagnosis()}';
  fail('$reason (bounded wait ${timeout.inSeconds}s expired)$detail');
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
        'the first analysis reached analysis-failed; see the T086_DIAG '
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
  // The FLD-001 warning card grows the sheet, so the close action can sit below
  // the visible box until the scroll view is brought to it.
  await tester.ensureVisible(find.byKey(fieldValueCloseKey));
  await tester.pumpAndSettle();
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
      'Run tools/android/t086_drive_fill.sh.',
    );
  }
  final Uint8List bytes = file.readAsBytesSync();
  expect(bytes.length, _fixtureSizeBytes);
  expect(crypto.sha256.convert(bytes).toString(), _fixtureSha256);
  return bytes;
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
/// The review header and the page scroll move a stored field out of the
/// viewport after a route change, and a tap only reaches the overlay when its
/// display point is inside the visible page rectangle. Centring first is the
/// documented viewer seam (`PageViewController.setView`), not a geometry
/// shortcut.
///
/// Returns the global point that was tapped so the caller can report the exact
/// tap seam when the value sheet does not open.
Future<Offset> _centreAndTapField(
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
  final Offset tapPoint = _screenPoint(tester, state, field);
  await tester.tapAt(tapPoint);
  return tapPoint;
}

String _diagNumber(double value) => value.toStringAsFixed(1);

String _diagBox(double left, double top, double right, double bottom) =>
    '${_diagNumber(left)},${_diagNumber(top)},'
    '${_diagNumber(right)},${_diagNumber(bottom)}';

String _diagFlag(bool value) => value ? '1' : '0';

/// Content-free state of the value-sheet tap seam.
///
/// `_openValueSheet` once waited out its bound on page 2 with no sheet, no
/// error, and no exception, so every silent path in that seam is made
/// observable: viewport and page geometry, finder state, identity
/// comparisons, and the overlay hit test the tap would resolve. Only numbers,
/// counts, flags, and type/role names are emitted — never a label, entered
/// value, id, path, or document content.
List<String> _valueSheetTapDiagnosis(
  WidgetTester tester,
  EditorScreenState state,
  core.ConfirmedField field,
  Offset tapPoint,
  String phase,
) {
  final PageViewController controller = state.viewController;
  final Size? viewport = controller.viewportSize;
  final Finder pageView = find.byKey(_editorPageViewKey);
  final Rect pageViewRect = tester.getRect(pageView);
  final MediaQueryData media = MediaQuery.of(tester.element(pageView));
  final PageViewMapping mapping = controller.mappingFor(field.pageIndex);
  final Rect pageInView = mapping.pageRectInViewport;
  final Offset pageOrigin = pageViewRect.topLeft + pageInView.topLeft;
  final Offset pageLocal = tapPoint - pageOrigin;
  final core.RevisionContent? content = state.content;
  final bool fieldInContent =
      content != null &&
      content.fields.any(
        (core.ConfirmedField candidate) => candidate.id == field.id,
      );
  final int pageSuggestions = content == null
      ? 0
      : content.suggestions
            .where(
              (core.FieldSuggestion suggestion) =>
                  suggestion.pageIndex == field.pageIndex &&
                  suggestion.resolution == core.SuggestionResolution.unresolved,
            )
            .length;

  final List<String> lines = <String>[
    'DIAG_SHEET_GEOM_$phase:PAGE=${field.pageIndex + 1}:TYPE=${field.type.name}'
        ':VIEWPORT=${_diagNumber(viewport!.width)}x${_diagNumber(viewport.height)}'
        ':MEDIA=${_diagNumber(media.size.width)}x${_diagNumber(media.size.height)}'
        ':IME_BOTTOM=${_diagNumber(media.viewInsets.bottom)}'
        ':SCALE=${controller.scale.toStringAsFixed(3)}'
        ':PAN=${_diagNumber(controller.pan.dx)},${_diagNumber(controller.pan.dy)}'
        ':PAGEVIEW=${_diagBox(pageViewRect.left, pageViewRect.top, pageViewRect.right, pageViewRect.bottom)}'
        ':TAP=${_diagNumber(tapPoint.dx)},${_diagNumber(tapPoint.dy)}'
        ':TAP_IN_PAGEVIEW=${_diagFlag(pageViewRect.contains(tapPoint))}'
        ':PAGE_IN_VIEW=${_diagBox(pageInView.left, pageInView.top, pageInView.right, pageInView.bottom)}'
        ':TAP_IN_PAGE=${_diagFlag((pageOrigin & pageInView.size).contains(tapPoint))}'
        ':TAP_PAGE_LOCAL=${_diagNumber(pageLocal.dx)},${_diagNumber(pageLocal.dy)}'
        ':FIELD=${_diagBox(field.rect.left, field.rect.top, field.rect.right, field.rect.bottom)}',
  ];

  final Finder surfaceFinder = find.byType(FieldSelectionSurface);
  final List<String> surfaces = <String>[];
  for (int index = 0; index < surfaceFinder.evaluate().length; index++) {
    final FieldSelectionSurface surface = tester.widget<FieldSelectionSurface>(
      surfaceFinder.at(index),
    );
    final Rect surfaceRect = tester.getRect(surfaceFinder.at(index));
    final List<FieldOverlayItem> items = surface.items.toList(growable: false);
    final FieldOverlayItem? hit = hitTestFieldSelection(
      items: items,
      pageSize: surface.pageSize,
      pageRect: surface.pageRect,
      viewPoint: tapPoint - surfaceRect.topLeft,
    );
    final String outcome = hit == null
        ? 'MISS'
        : hit.id == field.id
        ? 'TARGET@${_diagBox(hit.rect.left, hit.rect.top, hit.rect.right, hit.rect.bottom)}'
        : hit.provenance == FieldOverlayProvenance.machineSuggestion
        ? 'SUGGESTION@${_diagBox(hit.rect.left, hit.rect.top, hit.rect.right, hit.rect.bottom)}'
        : 'FIELD@${_diagBox(hit.rect.left, hit.rect.top, hit.rect.right, hit.rect.bottom)}';
    surfaces.add(
      'SURF$index=IN${_diagFlag(surfaceRect.contains(tapPoint))}'
      '/ITEMS${items.length}'
      '/HASFIELD${_diagFlag(items.any((FieldOverlayItem item) => item.id == field.id))}'
      '/HIT:$outcome',
    );
  }

  final String selection = state.selection.selectedId == null
      ? 'NONE'
      : state.selection.selectedId == field.id
      ? 'THIS'
      : 'OTHER';
  final bool sheetOpen = find.byKey(fieldValueSheetKey).evaluate().isNotEmpty;
  final int barriers = find.byType(ModalBarrier).evaluate().length;
  String deduced;
  if (sheetOpen) {
    deduced = 'SHEET_OPEN';
  } else if (selection == 'THIS') {
    deduced = fieldInContent ? 'GATE_STUCK_OPEN' : 'FIELD_NOT_IN_LIVE_CONTENT';
  } else if (surfaces.any((String entry) => entry.contains('/HIT:TARGET'))) {
    deduced = 'TARGET_HIT_NOT_SELECTED';
  } else if (surfaces.any(
    (String entry) =>
        entry.contains('/HIT:SUGGESTION') || entry.contains('/HIT:FIELD'),
  )) {
    deduced = 'OTHER_ITEM_ON_TOP';
  } else if (surfaces.any((String entry) => entry.contains('=IN1/'))) {
    deduced = 'SURFACE_MISS';
  } else {
    deduced = 'NO_SURFACE_AT_POINT';
  }
  lines.add(
    'DIAG_SHEET_STATE_$phase:SELECTION=$selection'
    ':SHEET=${sheetOpen ? 'OPEN' : 'CLOSED'}'
    ':TEXT_INPUT=${find.byKey(fieldTextControlInputKey).evaluate().isEmpty ? 'EMPTY' : 'FOUND'}'
    ':BARRIERS=$barriers'
    ':FIELD_IN_CONTENT=${_diagFlag(fieldInContent)}'
    ':PAGE_SUGGESTIONS=$pageSuggestions'
    ':SURFACES=${surfaces.length}'
    ':${surfaces.join(':')}'
    ':HITPATH=${_diagHitPath(tester, tapPoint)}'
    ':DEDUCED=$deduced',
  );
  return lines;
}

/// Render-object types of the first entries the tap point resolves to.
///
/// The tap only opens a value sheet when it reaches the page's selection
/// surface, so the top of the hit-test path separates a swallowed tap from a
/// hit-test miss. Type names carry no document content.
String _diagHitPath(WidgetTester tester, Offset tapPoint) {
  final HitTestResult result = tester.hitTestOnBinding(tapPoint);
  final List<String> types = <String>[];
  for (final HitTestEntry<HitTestTarget> entry in result.path.take(6)) {
    types.add(entry.target.runtimeType.toString());
  }
  return types.isEmpty ? 'EMPTY' : types.join('>');
}

/// [_valueSheetTapDiagnosis] that can never change the journey's outcome.
///
/// The dump is observation only, so a throw inside it must degrade to a note
/// instead of turning a passing fill into a failure.
List<String> _safeValueSheetTapDiagnosis(
  WidgetTester tester,
  EditorScreenState state,
  core.ConfirmedField field,
  Offset tapPoint,
  String phase,
) {
  try {
    return _valueSheetTapDiagnosis(tester, state, field, tapPoint, phase);
  } catch (error) {
    return <String>['DIAG_SHEET_UNAVAILABLE_$phase:ERROR=${error.runtimeType}'];
  }
}

Future<void> _openValueSheet(
  WidgetTester tester,
  EditorScreenState state,
  core.ConfirmedField field,
) async {
  final Offset tapPoint = await _centreAndTapField(tester, state, field);
  for (final String line in _safeValueSheetTapDiagnosis(
    tester,
    state,
    field,
    tapPoint,
    'TAP',
  )) {
    _marker(line);
  }
  await _pumpUntil(
    tester,
    () => find.byKey(fieldValueSheetKey).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 120),
    reason: 'tapping the ${field.type.name} field did not open the value sheet',
    diagnosis: () => _safeValueSheetTapDiagnosis(
      tester,
      state,
      field,
      tapPoint,
      'TIMEOUT',
    ).join('\n'),
  );
  expect(state.selection.selectedId, field.id);
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
    'ANALYSIS_READY:STATE=${state.analysisStateKey}:'
    'PAGES=${state.content!.pageCount}:'
    'SUGGESTIONS=${state.content!.suggestions.length}',
  );
  return state;
}

/// Confirms the first unresolved real machine text suggestion on [pageIndex].
Future<core.ConfirmedField> _confirmMachineTextField(
  WidgetTester tester,
  EditorScreenState state,
  int pageIndex,
) async {
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
    reason: 'page $pageIndex has no unresolved machine text suggestion',
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
  final core.ConfirmedField field = state.content!.fields.firstWhere(
    (core.ConfirmedField candidate) =>
        candidate.sourceSuggestionId == suggestion!.id,
  );
  _marker(
    'MACHINE_FIELD_CONFIRMED:PAGE=$pageIndex:'
    'W_MILLI=${(field.rect.width * 1000).round()}:'
    'H_MILLI=${(field.rect.height * 1000).round()}',
  );
  return field;
}

/// Returns the first free rectangle of the declared size on [pageBox].
///
/// The real page already carries one confirmed machine field, so the seeded
/// production fields are placed on a coarse two-column grid that never
/// intersects an occupied rectangle. No geometry is invented: every returned
/// rectangle lies strictly inside the real page display box.
core.Rect _freeSlot(
  core.Rect pageBox,
  List<core.Rect> used,
  double widthFraction,
  double heightFraction,
) {
  final double width = pageBox.width * widthFraction;
  final double height = pageBox.height * heightFraction;
  const List<double> columns = <double>[0.06, 0.55];
  for (int row = 30; row <= 92; row += 2) {
    for (final double column in columns) {
      final double left = pageBox.left + pageBox.width * column;
      final double top = pageBox.top + pageBox.height * row / 100;
      if (left + width > pageBox.right - 2 ||
          top + height > pageBox.bottom - 2) {
        continue;
      }
      final core.Rect candidate = core.Rect.fromLTWH(left, top, width, height);
      final double candidateRight = candidate.left + candidate.width;
      final double candidateBottom = candidate.top + candidate.height;
      bool overlaps = false;
      for (final core.Rect occupied in used) {
        final double occupiedRight = occupied.left + occupied.width;
        final double occupiedBottom = occupied.top + occupied.height;
        if (candidate.left < occupiedRight + 4 &&
            candidateRight > occupied.left - 4 &&
            candidate.top < occupiedBottom + 4 &&
            candidateBottom > occupied.top - 4) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) {
        return candidate;
      }
    }
  }
  fail('no free seeded field slot on the real page');
}

/// Seeds the typed production fields on both real pages in one revision.
Future<Map<_SeededRole, core.ConfirmedField>> _seedTypedFields(
  WidgetTester tester,
  String documentId,
) async {
  final EditorRuntime runtime = _liveRuntime(tester);
  final LoadedDocument loaded = await runtime.loadDocument(documentId);
  core.RevisionContent content = loaded.content;
  final Map<_SeededRole, core.ConfirmedField> seeded =
      <_SeededRole, core.ConfirmedField>{};
  final List<core.Rect> used = <core.Rect>[
    for (final core.ConfirmedField field in content.fields) field.rect,
  ];
  final DateTime now = runtime.clock.nowUtc().toUtc();
  for (final _SeededRole role in _SeededRole.values) {
    final int pageIndex =
        role == _SeededRole.pageTwoText ||
            role == _SeededRole.multiline ||
            role == _SeededRole.signature
        ? 1
        : 0;
    final core.Rect pageBox = content.pages[pageIndex].geometry.displayBox;
    final double heightFraction = role == _SeededRole.signature
        ? math.max(role.heightFraction, 48 / pageBox.height)
        : role.heightFraction;
    final core.Rect rect = _freeSlot(
      pageBox,
      used,
      role.widthFraction,
      heightFraction,
    );
    final String fieldId = runtime.ids.newId();
    final edit.EditFieldChange change = edit.addField(
      content,
      fieldId,
      pageIndex,
      rect,
      role.type,
      role.label,
      now,
    );
    content = change.content;
    used.add(rect);
    seeded[role] = content.fields.firstWhere(
      (core.ConfirmedField field) => field.id == fieldId,
    );
    _marker(
      'SEEDED_FIELD:ROLE=${role.role}:PAGE=$pageIndex:'
      'W_MILLI=${(rect.width * 1000).round()}:'
      'H_MILLI=${(rect.height * 1000).round()}',
    );
  }
  final StoredMeta saved = await runtime.saveRevision(
    SaveRevisionRequest(
      documentId: documentId,
      expectedHead: loaded.meta.latestRevisionId,
      content: content,
      kind: core.RevisionKind.autosave,
    ),
  );
  _marker(
    'TYPED_FIELDS_SEEDED:COUNT=${seeded.length}:'
    'HEAD_CHANGED=${saved.latestRevisionId != loaded.meta.latestRevisionId ? 1 : 0}',
  );
  return seeded;
}

/// Leaves the editor and reopens the same stored document from the start list.
Future<EditorScreenState> _leaveAndReopen(
  WidgetTester tester,
  String documentId,
) async {
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
      return reopened.content != null;
    },
    timeout: const Duration(minutes: 3),
    reason: 'the reopened document did not load its content',
  );
  await _pumpUntil(
    tester,
    () {
      final EditorScreenState reopened = tester.state<EditorScreenState>(
        find.byType(EditorScreen),
      );
      return !reopened.reviewBusy &&
          reopened.content!.fields.length >= _expectedFieldCount;
    },
    timeout: const Duration(minutes: 3),
    reason: 'the reopened document did not show every confirmed field',
  );
  await tester.pumpAndSettle();
  return tester.state<EditorScreenState>(find.byType(EditorScreen));
}

/// One confirmed machine field per page plus the seeded typed fields.
const int _expectedFieldCount = 9;

/// The visible page with the largest share of the page viewport.
int _visiblePageIndex(EditorScreenState state) {
  final Size? viewport = state.viewController.viewportSize;
  expect(viewport, isNotNull, reason: 'the page viewport must be laid out');
  int best = 0;
  double bestArea = -1;
  for (int index = 0; index < state.content!.pageCount; index++) {
    final Rect page = state.viewController.mappingFor(index).pageRectInViewport;
    final double height =
        math.min(page.bottom, viewport!.height) - math.max(page.top, 0);
    final double width =
        math.min(page.right, viewport.width) - math.max(page.left, 0);
    final double area = height <= 0 || width <= 0 ? 0 : height * width;
    if (area > bestArea) {
      bestArea = area;
      best = index;
    }
  }
  return best;
}

/// Navigates with the real page strip until [pageIndex] is the visible page.
Future<void> _navigateToPage(
  WidgetTester tester,
  EditorScreenState state,
  int pageIndex,
) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 120));
  while (_visiblePageIndex(state) != pageIndex) {
    if (DateTime.now().isAfter(deadline)) {
      fail('the page strip did not bring page ${pageIndex + 1} into view');
    }
    final int current = _visiblePageIndex(state);
    await tester.tap(
      find.byKey(
        current < pageIndex ? _pageStripNextKey : _pageStripPreviousKey,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }
  _marker('PAGE_VISIBLE:PAGE=${pageIndex + 1}');
}

String _storedText(core.FieldValue? value) {
  if (value is core.TextValue) {
    return value.text;
  }
  if (value is core.MultilineValue) {
    return value.text;
  }
  if (value is core.NumberValue) {
    return value.rawGerman;
  }
  if (value is core.DateValue) {
    return value.canonical;
  }
  fail('the field has no stored text value (${value.runtimeType})');
}

/// Enters [value] in the open sheet and commits it as one verified revision.
Future<void> _commitTextLike(
  WidgetTester tester,
  EditorScreenState state,
  core.ConfirmedField field,
  String value, {
  required bool expectOverflow,
}) async {
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
    reason: 'the ${field.type.name} value did not commit a verified revision',
  );
  final core.FieldValue? stored = state.content!.values[field.id];
  expect(stored, isNotNull, reason: 'the committed value must exist');
  expect(stored!.overflow, expectOverflow);
  expect(
    _storedText(stored),
    field.type == core.FieldType.date ? _dateCanonical : value,
  );

  if (expectOverflow) {
    // The FLD-001 commit keeps the sheet on the field with the complete draft,
    // so the control still holds every rune: nothing was truncated.
    final TextField control = tester.widget<TextField>(
      find.byKey(fieldTextControlInputKey),
    );
    expect(control.controller!.text, value);
    await _pumpUntil(
      tester,
      () => find.byKey(fieldOverflowWarningKey).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 120),
      reason: 'the FLD-001 warning did not appear after the commit',
    );
    _marker(
      'VALUE_OVERFLOW:TYPE=${field.type.name}:'
      'ENTERED_RUNES=${value.runes.length}:'
      'STORED_RUNES=${_storedText(stored).runes.length}:TRUNCATED=0',
    );
  } else {
    // A save without FLD-001 pops the sheet on success
    // (`FieldValueSheet._save`), so the committed draft is verified from the
    // store above and again through the reopened control later in the journey.
    await _pumpUntil(
      tester,
      () => find.byKey(fieldValueSheetKey).evaluate().isEmpty,
      timeout: const Duration(seconds: 120),
      reason: 'the saved value sheet did not close',
    );
    await tester.pumpAndSettle();
  }
  _marker(
    'VALUE_SAVED:TYPE=${field.type.name}:RUNES=${value.runes.length}:'
    'OVERFLOW=${expectOverflow ? 1 : 0}',
  );
}

/// Fills one seeded field through the real overlay and value sheet.
Future<void> _fillField(
  WidgetTester tester,
  EditorScreenState state,
  core.ConfirmedField field,
  String value, {
  bool expectOverflow = false,
}) async {
  await _openValueSheet(tester, state, field);
  switch (field.type) {
    case core.FieldType.text:
    case core.FieldType.multiline:
    case core.FieldType.number:
    case core.FieldType.date:
      await _commitTextLike(
        tester,
        state,
        field,
        value,
        expectOverflow: expectOverflow,
      );
      break;
    case core.FieldType.checkbox:
      expect(find.byKey(fieldCheckboxControlKey), findsOneWidget);
      expect(
        tester
            .widget<FieldCheckboxControl>(find.byType(FieldCheckboxControl))
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(fieldCheckboxBoxKey));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FieldCheckboxControl>(find.byType(FieldCheckboxControl))
            .value,
        isTrue,
      );
      final String? checkboxHeadBefore = state.headRevisionId;
      await tester.ensureVisible(find.byKey(fieldValueSaveKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(fieldValueSaveKey));
      await _waitForCommit(
        tester,
        state,
        headBefore: checkboxHeadBefore,
        reason: 'the checkbox did not commit a verified revision',
      );
      await _pumpUntil(
        tester,
        () => find.byKey(fieldValueSheetKey).evaluate().isEmpty,
        timeout: const Duration(seconds: 120),
        reason: 'the checkbox value sheet did not close',
      );
      final core.CheckboxValue stored =
          state.content!.values[field.id]! as core.CheckboxValue;
      expect(stored.checked, isTrue);
      _marker('VALUE_SAVED:TYPE=checkbox:CHECKED=1');
      break;
    case core.FieldType.signature:
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
      final Offset origin =
          tester.getCenter(find.byKey(signatureSheetCanvasKey)) -
          const Offset(120, 40);
      final TestGesture stroke = await tester.startGesture(origin);
      for (int step = 0; step < 8; step++) {
        await stroke.moveBy(const Offset(35, 8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await stroke.up();
      await tester.pump(const Duration(milliseconds: 120));
      final String? signatureHeadBefore = state.headRevisionId;
      await tester.tap(find.byKey(signatureSheetApplyKey));
      await _pumpUntil(
        tester,
        () =>
            find.byType(SignatureSheet).evaluate().isEmpty &&
            find.byKey(fieldValueSheetKey).evaluate().isEmpty &&
            state.content!.signatures.containsKey(field.id) &&
            !state.reviewBusy &&
            state.durabilityStatus is core.SavedDurabilityStatus,
        timeout: const Duration(minutes: 5),
        reason: 'the signature asset and revision did not settle as saved',
      );
      await tester.pumpAndSettle();
      expect(state.headRevisionId, isNot(signatureHeadBefore));
      final core.FieldValue? value = state.content!.values[field.id];
      expect(value, isA<core.SignatureValue>());
      final core.SignatureMark mark = state.content!.signatures[field.id]!;
      expect(mark.assetId, (value! as core.SignatureValue).signatureAssetId);
      expect(mark.fieldId, field.id);
      expect(mark.pageIndex, field.pageIndex);
      expect(mark.widthPx, lessThanOrEqualTo(signaturePngMaxEdgePx));
      expect(mark.heightPx, lessThanOrEqualTo(signaturePngMaxEdgePx));
      _marker(
        'VALUE_SAVED:TYPE=signature:BOUND=1:'
        'WIDTH_LE_1024=1:HEIGHT_LE_1024=1',
      );
      break;
  }
}

/// Reopens [field] and verifies the visible control holds the stored value.
Future<void> _expectFieldEditableAndPreserved(
  WidgetTester tester,
  EditorScreenState state,
  core.ConfirmedField field,
  String displayValue,
) async {
  await _openValueSheet(tester, state, field);
  switch (field.type) {
    case core.FieldType.text:
    case core.FieldType.multiline:
    case core.FieldType.number:
    case core.FieldType.date:
      final TextField textControl = tester.widget<TextField>(
        find.byKey(fieldTextControlInputKey),
      );
      expect(textControl.enabled, isTrue);
      expect(textControl.readOnly, isFalse);
      expect(textControl.controller!.text, displayValue);
      break;
    case core.FieldType.checkbox:
      final FieldCheckboxControl checkboxControl = tester
          .widget<FieldCheckboxControl>(find.byType(FieldCheckboxControl));
      expect(checkboxControl.enabled, isTrue);
      expect(checkboxControl.readOnly, isFalse);
      expect(checkboxControl.value, isTrue);
      break;
    case core.FieldType.signature:
      expect(
        find.text(_de.a11ySignatureSigned),
        findsOneWidget,
        reason: 'the reopened sheet must show the signed state from the store',
      );
      expect(find.text(_de.a11ySignatureUnsigned), findsNothing);
      break;
  }
  expect(find.byKey(fieldValueErrorKey), findsNothing);
  _marker(
    'FIELD_REOPENED:TYPE=${field.type.name}:PAGE=${field.pageIndex + 1}:'
    'PRESERVED=1:EDITABLE=1',
  );
  await _closeValueSheet(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final Directory fixtureDirectory = Directory(_fixtureRoot);
  File? scratchSource;
  bool hookArmed = false;

  setUpAll(() {
    expect(fixtureDirectory.existsSync(), isTrue);
    final Uint8List fixtureBytes = _loadFixture();
    _marker('FIXTURE_READY:BYTES=$_fixtureSizeBytes:MATCH=1');
    scratchSource = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}t086-'
      '${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    scratchSource!.writeAsBytesSync(fixtureBytes, flush: true);
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
  });

  testWidgets('two-page touch fill keeps every value and stays editable', (
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

    // --- One real machine field per page through the production review ------
    final core.ConfirmedField machinePageOne = await _confirmMachineTextField(
      tester,
      state,
      0,
    );
    final core.ConfirmedField machinePageTwo = await _confirmMachineTextField(
      tester,
      state,
      1,
    );
    expect(machinePageTwo.pageIndex, 1);
    _marker('TWO_MACHINE_FIELDS_CONFIRMED:PAGES=2');

    // --- Typed production fields on both real pages -------------------------
    final Map<_SeededRole, core.ConfirmedField> seeded = await _seedTypedFields(
      tester,
      documentId,
    );

    final EditorScreenState reopened = await _leaveAndReopen(
      tester,
      documentId,
    );
    expect(
      reopened.analysisStateKey,
      editorAnalysisSkippedKey,
      reason: 'the persisted suggestions must skip a second analysis run',
    );
    expect(reopened.content!.fields.length, _expectedFieldCount);
    expect(
      reopened.content!.fields
          .where((core.ConfirmedField field) => field.pageIndex == 0)
          .length,
      5,
    );
    expect(
      reopened.content!.fields
          .where((core.ConfirmedField field) => field.pageIndex == 1)
          .length,
      4,
    );
    _marker(
      'DOCUMENT_REOPENED:FIELDS=${reopened.content!.fields.length}:'
      'PAGES=2:ANALYSIS=skipped',
    );

    // --- Fill page 1 by touch through the real overlay and value sheet ------
    await _navigateToPage(tester, reopened, 0);

    // The real machine field carries a real recognised rectangle far smaller
    // than this text: FLD-001 must warn, and the complete value must be kept.
    await _fillField(
      tester,
      reopened,
      machinePageOne,
      _overflowText,
      expectOverflow: true,
    );
    await _waitForDriver('overflow-warning');
    await _closeValueSheet(tester);

    await _fillField(tester, reopened, seeded[_SeededRole.text]!, _textValue);
    await _fillField(
      tester,
      reopened,
      seeded[_SeededRole.number]!,
      _numberValue,
    );
    final core.NumberValue numberValue =
        reopened.content!.values[seeded[_SeededRole.number]!.id]!
            as core.NumberValue;
    expect(numberValue.canonical, _numberCanonical);
    _marker('NUMBER_CANONICAL:MATCH=1');

    await _fillField(tester, reopened, seeded[_SeededRole.date]!, _dateValue);
    final core.DateValue dateValue =
        reopened.content!.values[seeded[_SeededRole.date]!.id]!
            as core.DateValue;
    expect(dateValue.canonical, _dateCanonical);
    _marker('DATE_CANONICAL:MATCH=1');

    await _fillField(tester, reopened, seeded[_SeededRole.checkbox]!, '');

    // Screenshot: the real page-1 date sheet with its complete entered value.
    await _openValueSheet(tester, reopened, seeded[_SeededRole.date]!);
    _marker('PAGE1_FILLED:FIELDS=5');
    await _waitForDriver('page1-values');
    await _closeValueSheet(tester);

    // --- Navigate to page 2 and fill it by touch ----------------------------
    await _navigateToPage(tester, reopened, 1);
    await _fillField(
      tester,
      reopened,
      seeded[_SeededRole.pageTwoText]!,
      _pageTwoTextValue,
    );
    await _fillField(
      tester,
      reopened,
      seeded[_SeededRole.multiline]!,
      _multilineValue,
    );
    final core.MultilineValue multilineValue =
        reopened.content!.values[seeded[_SeededRole.multiline]!.id]!
            as core.MultilineValue;
    expect(multilineValue.text, _multilineValue);
    expect(multilineValue.text.contains('\n'), isTrue);
    _marker('MULTILINE_STORED:LINES=2:TRUNCATED=0');

    await _fillField(tester, reopened, seeded[_SeededRole.signature]!, '');

    // Screenshot: the reopened signature field on page 2 shows the signed state.
    await _openValueSheet(tester, reopened, seeded[_SeededRole.signature]!);
    _marker('PAGE2_FILLED:FIELDS=3');
    await _waitForDriver('page2-signed');
    await _closeValueSheet(tester);

    // --- Navigate back: every page-1 value must be unchanged ----------------
    await _navigateToPage(tester, reopened, 0);
    expect(
      (reopened.content!.values[machinePageOne.id]! as core.TextValue).text,
      _overflowText,
    );
    expect(
      (reopened.content!.values[seeded[_SeededRole.text]!.id]!
              as core.TextValue)
          .text,
      _textValue,
    );
    expect(
      (reopened.content!.values[seeded[_SeededRole.number]!.id]!
              as core.NumberValue)
          .canonical,
      _numberCanonical,
    );
    expect(
      (reopened.content!.values[seeded[_SeededRole.date]!.id]!
              as core.DateValue)
          .canonical,
      _dateCanonical,
    );
    expect(
      (reopened.content!.values[seeded[_SeededRole.checkbox]!.id]!
              as core.CheckboxValue)
          .checked,
      isTrue,
    );
    _marker('VALUES_SURVIVED_NAVIGATION:PAGE1=5:PAGE2=3');

    // --- Every filled page-1 field is still editable ------------------------
    await _expectFieldEditableAndPreserved(
      tester,
      reopened,
      machinePageOne,
      _overflowText,
    );
    await _expectFieldEditableAndPreserved(
      tester,
      reopened,
      seeded[_SeededRole.number]!,
      _numberValue,
    );
    await _expectFieldEditableAndPreserved(
      tester,
      reopened,
      seeded[_SeededRole.date]!,
      _dateValue,
    );
    await _expectFieldEditableAndPreserved(
      tester,
      reopened,
      seeded[_SeededRole.checkbox]!,
      '',
    );

    // Screenshot: the page-1 text field after the page round trip.
    await _openValueSheet(tester, reopened, seeded[_SeededRole.text]!);
    expect(
      tester
          .widget<TextField>(find.byKey(fieldTextControlInputKey))
          .controller!
          .text,
      _textValue,
    );
    await _waitForDriver('page1-preserved');
    await _closeValueSheet(tester);

    // --- Every filled page-2 field is still editable ------------------------
    await _navigateToPage(tester, reopened, 1);
    await _expectFieldEditableAndPreserved(
      tester,
      reopened,
      seeded[_SeededRole.pageTwoText]!,
      _pageTwoTextValue,
    );
    await _expectFieldEditableAndPreserved(
      tester,
      reopened,
      seeded[_SeededRole.multiline]!,
      _multilineValue,
    );
    await _expectFieldEditableAndPreserved(
      tester,
      reopened,
      seeded[_SeededRole.signature]!,
      '',
    );

    // --- A real edit after the round trip commits the updated value ---------
    await _navigateToPage(tester, reopened, 0);
    final core.ConfirmedField textField = seeded[_SeededRole.text]!;
    await _openValueSheet(tester, reopened, textField);
    final String? headBeforeEdit = reopened.headRevisionId;
    await _commitTextLike(
      tester,
      reopened,
      textField,
      _editedTextValue,
      expectOverflow: false,
    );
    expect(reopened.headRevisionId, isNot(headBeforeEdit));
    expect(
      (reopened.content!.values[textField.id]! as core.TextValue).text,
      _editedTextValue,
    );
    _marker(
      'FIELD_EDITED_AFTER_NAVIGATION:TYPE=text:'
      'RUNES=${_editedTextValue.runes.length}:TRUNCATED=0',
    );

    // --- Verified store read-back: no value truncated -----------------------
    final LoadedDocument stored = await _liveRuntime(tester).store
        .loadDocument(documentId);
    final core.RevisionContent content = stored.content;
    expect(
      (content.values[machinePageOne.id]! as core.TextValue).text,
      _overflowText,
    );
    expect(
      (content.values[seeded[_SeededRole.text]!.id]! as core.TextValue).text,
      _editedTextValue,
    );
    expect(
      (content.values[seeded[_SeededRole.number]!.id]! as core.NumberValue)
          .canonical,
      _numberCanonical,
    );
    expect(
      (content.values[seeded[_SeededRole.date]!.id]! as core.DateValue)
          .canonical,
      _dateCanonical,
    );
    expect(
      (content.values[seeded[_SeededRole.checkbox]!.id]! as core.CheckboxValue)
          .checked,
      isTrue,
    );
    expect(
      (content.values[seeded[_SeededRole.pageTwoText]!.id]! as core.TextValue)
          .text,
      _pageTwoTextValue,
    );
    final core.MultilineValue storedMultiline =
        content.values[seeded[_SeededRole.multiline]!.id]!
            as core.MultilineValue;
    expect(storedMultiline.text, _multilineValue);
    expect(storedMultiline.text.contains('\n'), isTrue);
    final core.SignatureMark storedMark =
        content.signatures[seeded[_SeededRole.signature]!.id]!;
    final Uint8List asset = await _liveRuntime(tester).store
        .readSignature(documentId, storedMark.assetId);
    expect(asset, isNotEmpty);
    expect(crypto.sha256.convert(asset).toString(), storedMark.sha256);
    expect(
      asset.sublist(0, 8),
      orderedEquals(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
      reason: 'the stored signature asset must be a real PNG stream',
    );
    expect(
      (content.values[seeded[_SeededRole.signature]!.id]!
              as core.SignatureValue)
          .signatureAssetId,
      storedMark.assetId,
    );
    _marker(
      'STORE_READBACK:VALUES=7:SIGNATURE=1:DIGEST_MATCH=1:PNG=1:TRUNCATED=0',
    );
    expect(machinePageTwo.pageIndex, 1);
    _marker('CLEANUP_DONE');
  });
}
