// T071 EMULATOR Android touch move/resize review test (issue #71).
//
// Evidence class: `EMULATOR` only. Run only through the host driver, which
// owns the fixture staging, the screenshot handshake, the device identity, and
// the APK/git evidence:
//
//   tools/android/t071_drive_touch.sh
//
// The test starts the real `FeldexaApp` (the same root widget `main()` builds)
// with the production `createImportRuntime()` Android composition: the
// debug-only `de.feldexa/test.import` hook arms the deterministic T061
// damaged-page-2 variant of the committed synthetic `sf-001.pdf` fixture, the
// production import action performs the real encrypted staging, preflight, and
// verified commit, the real analysis run produces suggestions, and one
// suggestion is confirmed through the production T066 command path. The
// confirmed field is selected through the real T077 tap path (tap -> value
// sheet -> close), and is then edited through the real composed T071B touch
// geometry layer with real pointer events on the emulator's touch surface.
//
// Two deliberate, documented test seams exist and neither replaces behavior:
//   * the app is started with `FeldexaApp(importRuntimeFactory: ...)` instead of
//     `main()` so the *same* production composition can be wrapped in a
//     counting facade around the real editor runtime (see `_StoreSpy`); the
//     facade forwards every call unchanged to the real raster, OCR, id, clock,
//     store, load, save, and dispose implementations and only counts
//     `saveRevision` invocations. The startup sweep of `main()` is not part of
//     this touch journey and is not exercised.
//   * the last gesture deliberately arms a double-commit fault injection as a
//     negative control for the exactly-one-revision assertion (see
//     `NEGATIVE_CONTROL:DOUBLE_COMMIT`); it is the final action before teardown
//     and leaves the stored head one revision ahead, which the driver's app-data
//     cleanup removes.
// No fake adapter, renderer, detector, OCR result, store, route, or geometry
// implementation replaces a production one.
//
// What is proven here (`contracts/editor-interactions.md` §4, FR-023/FR-024,
// FR-094, SC-017):
//   * a body drag moves the selected confirmed field by the gesture-start
//     pointer delta divided by the current view scale exactly once, clamped to
//     the page, at 0.5x, 1x, 3x, and 8x fit-width — and one further 8x drag is
//     dragged far enough to hit the page clamp and keeps its size exactly;
//   * all four corner handles and all four edge handles resize the field, the
//     diagonally opposite corner / opposite edge stays bit-for-bit fixed, the
//     aspect ratio stays free, and one edge handle is claimed from a touch point
//     measured 8.29 dp *outside* the stored rectangle; 24 dp is the contract
//     constant the production hit test uses, not a measurement of this run;
//   * the minimum committed size of 4 x 4 pt is enforced against the fixed
//     anchor;
//   * every gesture produces exactly one verified store commit, never one per
//     frame: a counting facade around the real editor runtime counts
//     `saveRevision` calls, and the test asserts zero calls during a hold window
//     that is longer than the fastest measured commit latency (at least 1 s,
//     with the slowest observed latency recorded in the marker), exactly one
//     call per gesture, and no in-flight commit (`reviewBusy` false, preview
//     painted, gesture active) while the pointer is held. A pure assertion
//     negative control and a real double-commit fault injection prove the
//     assertion is not vacuous and that it fails on two store calls;
//   * a pointer cancel discards the preview and commits nothing;
//   * undo restores the exact previous rectangle (bit-for-bit, not re-derived);
//   * two-finger pan and pinch never edit geometry, while the page still pans
//     and zooms.
//
// The resize phases run at a documented gesture zoom (`3 x fit-width`) so that
// a 20 pt edge movement is a pointer delta above Flutter's 36 px pan slop. The
// zoom is never assumed from the viewport: the test asserts
// `20 pt * 3 * fitWidth > 36 px` as an explicit precondition, raises the zoom to
// at least `40 px / 20 pt` if the viewport is narrower than the nominal 3x, and
// records the nominal and used margins in `T071_RESIZE_ZOOM`. The page-display
// delta, not the zoom, is what the assertions fix. Every phase keeps its
// expected rectangle inside the page display box, asserted as an explicit
// precondition, so a phase that would silently hit the page clamp fails loudly
// instead.
//
// Markers are content-free: phase name, handle, zero-based page index, the
// opaque generated field id, the view scale in milli-units, rectangles in
// 1/8 pt integer units, frame/save/commit counts, and measured latencies. No
// label, OCR text, title, path, URI, or entered value is printed. Screenshots
// are captured by the host driver at the marked phases; each `_waitForDriver`
// first removes any stale acknowledgement file and *fails closed* with an
// explicit `T071_HANDSHAKE_FAIL:` marker when that file exists and cannot be
// removed, so a capture can never show a state from an earlier phase. The
// screenshot markers have exactly one `T071_` prefix
// (`T071_SCREENSHOT_<PHASE>`), and the driver matches them as exact shapes
// rather than substrings.

import 'dart:io';
import 'dart:math' as math;

import 'package:feldexa_application/src/recognition/raster_page_stage_runner.dart'
    show RecognitionExecution;
import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_app/features/editor/durability_status.dart';
import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/field_value_sheet.dart';
import 'package:feldexa_app/features/editor/page_view.dart';
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/features/export/export_progress.dart';
import 'package:feldexa_app/features/start/import_runtime.dart';
import 'package:feldexa_app/features/start/stored_items.dart';
import 'package:feldexa_app/main.dart' show FeldexaApp;
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart' hide PageView;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// App-readable staging directory prepared by the host driver.
const String _fixtureRoot = '/data/local/tmp/t071-fixtures';
const String _fixtureId = 'sf-001';
const String _fixtureSha256 =
    '22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038';
const String _damagedFixtureSha256 =
    '57c1ade1ab2c00375ac61703db3d4ce5d27b996ea067647aba585866dc6ec221';
const int _fixtureSizeBytes = 5956;
const String _displayName = 't071-touch.pdf';

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

/// Zero-based page the touch journey edits.
const int _pageIndex = 0;

/// Acceptance values from `contracts/editor-interactions.md` §4, restated here
/// as the values the gestures below prove behaviorally. The production
/// constants live in `feldexa_ui`'s `field_geometry.dart`; this test observes
/// them through the composed surface instead of importing that private library.
const double _contractMinSizePt = 4;
const double _contractHandleHitDp = 24;

/// Gesture zoom for the resize phases, as a multiple of fit-width.
///
/// A 20 pt edge movement is then a pointer delta of at least 40 logical pixels,
/// which is above Flutter's 36 px pan slop, while the page-display delta the
/// test asserts stays 20 pt. The zoom itself is not part of any expectation.
const double _resizeGestureZoom = 3;

/// Display-point size of one corner/edge movement in the resize phases.
const double _resizeStepPt = 20;

/// Display-point centre-right shrink that gives the body drags page room.
const double _narrowStepPt = 200;

/// Display-point bottom growth that gives the field a real body at 0.5x.
const double _growStepPt = 150;

/// Host-driver screenshot phases.
///
/// The value is the phase suffix; `_waitForDriver` emits
/// `T071_SCREENSHOT_<suffix>` through `_marker`, which adds the single `T071_`
/// prefix, and the driver answers with an `ack-<name>` file. Keeping only the
/// suffix here is what prevents the historical doubled
/// `T071_T071_SCREENSHOT_...` marker.
const Map<String, String> _screenshotPhases = <String, String>{
  'resize-corners': 'RESIZE_CORNERS',
  'resize-edges': 'RESIZE_EDGES',
  'move-0.5x': 'MOVE_0_5X',
  'move-1x': 'MOVE_1X',
  'move-3x': 'MOVE_3X',
  'move-8x': 'MOVE_8X',
  'move-clamped': 'MOVE_CLAMPED',
  'undo': 'UNDO',
  'cancel': 'CANCEL',
  'two-finger-pinch': 'TWO_FINGER_PINCH',
  'two-finger-pan': 'TWO_FINGER_PAN',
  'min-size': 'MIN_SIZE',
};

/// Flutter's pan slop for the scale recognizer (`kPanSlop`, twice the touch
/// slop), in logical pixels.
const double _panSlopPx = 36;

/// Required pointer margin above the pan slop for a one-axis resize movement.
const double _requiredEdgePointerPx = 40;

/// Base hold window: the pointer stays down at least this long before it lifts.
const Duration _holdWindowBase = Duration(milliseconds: 1000);

/// Upper bound for the derived hold window so the journey stays bounded.
const Duration _maxHoldWindow = Duration(milliseconds: 3000);

/// The opaque generated id of the confirmed field under test.
String _targetFieldId = '';

/// The counting store spy of this test process.
///
/// Created once and handed to the counting editor-runtime facade, which the
/// production import composition builds for the editor route.
final _StoreSpy _storeSpy = _StoreSpy();

/// Counts the real editor runtime's store operations.
///
/// This is observation only: every counted call is forwarded unchanged to the
/// real implementation, so the counted revisions are the revisions the
/// encrypted store actually wrote.
final class _StoreSpy {
  int saves = 0;
  int loads = 0;

  /// When true, the next [saveRevision] forwards the same request a second
  /// time to the real store. Used only by the deliberate double-commit negative
  /// control at the end of the journey.
  bool duplicateNextSave = false;

  /// What the real store did with the injected second call: `ACCEPTED`,
  /// `REJECTED`, or `NONE` when no duplicate was armed.
  String duplicateOutcome = 'NONE';

  int get consumeDuplicateFlag {
    final bool armed = duplicateNextSave;
    duplicateNextSave = false;
    return armed ? 1 : 0;
  }
}

/// `EditorRuntime` facade that counts store calls and forwards everything.
final class _CountingEditorRuntime implements EditorRuntime {
  _CountingEditorRuntime(this._inner, this._spy);

  final EditorRuntime _inner;
  final _StoreSpy _spy;

  @override
  PageRasterPort get raster => _inner.raster;

  @override
  OcrPort? get ocr => _inner.ocr;

  @override
  SecureStorePort get store => _inner.store;

  @override
  IdPort get ids => _inner.ids;

  @override
  ClockPort get clock => _inner.clock;

  @override
  PdfExportPort get export => _inner.export;

  @override
  ExportOperationControl get exportOperation => _inner.exportOperation;

  @override
  DeliveryPort get delivery => _inner.delivery;

  @override
  Future<bool> setSensitiveRoute(SensitiveRoute route) =>
      _inner.setSensitiveRoute(route);

  /// The real Android composition: the recognition stage stays off the UI
  /// isolate during this journey.
  @override
  RecognitionExecution get recognitionExecution => _inner.recognitionExecution;

  @override
  Future<LoadedDocument> loadDocument(String documentId) {
    _spy.loads++;
    return _inner.loadDocument(documentId);
  }

  @override
  Future<StoredMeta> saveRevision(SaveRevisionRequest request) async {
    _spy.saves++;
    final StoredMeta first = await _inner.saveRevision(request);
    if (_spy.consumeDuplicateFlag == 1) {
      // Deliberate fault injection for the negative control: the same request
      // is forwarded to the real store a second time, exactly as a buggy
      // per-frame commit would. The outcome is recorded (the real store's
      // expectedHead guard normally rejects the stale chain) and is never
      // allowed to fail the editor's own commit, so the gesture still lands its
      // one revision and the assertion is judged on the real call count.
      _spy.saves++;
      try {
        await _inner.saveRevision(request);
        _spy.duplicateOutcome = 'ACCEPTED';
      } catch (_) {
        _spy.duplicateOutcome = 'REJECTED';
      }
    }
    return first;
  }

  @override
  Future<void> dispose() => _inner.dispose();
}

/// The production import composition with a counting editor-runtime facade.
///
/// The real `createImportRuntime()` composition supplies the import port, the
/// source-bytes resolver, the encrypted store, and the real editor-runtime
/// factory; only the factory result is wrapped.
ImportRuntime _countingImportRuntime() {
  final ImportRuntime base = createImportRuntime();
  final EditorRuntime Function()? factory = base.editorRuntimeFactory;
  return ImportRuntime(
    importPort: base.importPort,
    readSourceBytes: base.readSourceBytes,
    store: base.store,
    editorRuntimeFactory: factory == null
        ? null
        : () => _CountingEditorRuntime(factory(), _storeSpy),
  );
}

/// Starts the real app root with the counting production composition.
///
/// `main()` builds `FeldexaApp` with the default factory; this call builds the
/// same widget so the runtime facade can be composed. The startup sweep is not
/// part of the touch journey.
void _startApp() {
  runApp(FeldexaApp(importRuntimeFactory: _countingImportRuntime));
}

/// Every marker emitted in this process, without the `T071_` prefix.
///
/// The negative controls assert that their explicit failure markers were
/// actually emitted, which a log line alone cannot prove to the test.
final List<String> _emittedMarkers = <String>[];

void _marker(String phase) {
  _emittedMarkers.add(phase);
  debugPrint('T071_$phase');
}

int _eighths(double value) => (value * 8).round();

/// A page-display rectangle as integer 1/8 pt units, content-free.
String _rectEighths(Rect rect) {
  return '${_eighths(rect.left)}:${_eighths(rect.top)}:'
      '${_eighths(rect.width)}:${_eighths(rect.height)}';
}

String _coreRectEighths(core.Rect rect) {
  return _rectEighths(
    Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height),
  );
}

/// A view scale as an integer in milli-units, content-free.
int _scaleMilli(double scale) => (scale * 1000).round();

Rect _flutterRect(core.Rect rect) {
  return Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height);
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
/// Mirrors the T071A waiter: the editor turns a load/analysis/save failure into
/// the stable `analysis-failed` key, and the content-free page diagnostics are
/// recorded before the journey stops.
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
        'ANALYSIS_FAILED:CONTENT=${content == null ? 0 : 1}:'
        'PAGES=${content?.pageCount ?? 0}',
      );
      if (content != null) {
        for (final core.Page page in content.pages) {
          _marker(
            'ANALYSIS_PAGE:P=${page.index}:STATE=${page.analysis.name}:'
            'KEY=${page.failure?.messageKey ?? 'none'}',
          );
        }
      }
      fail(
        'the first analysis reached analysis-failed; see the T071_ANALYSIS_* '
        'markers in the integration log',
      );
    }
  }
  _marker('ANALYSIS_TIMEOUT:KEY=${state.analysisStateKey ?? 'pending'}');
  fail('the first analysis did not reach a terminal state before the bound');
}

/// Removes one stale acknowledgement file, or reports why it could not.
///
/// Returns `null` when the file is absent or was removed and verified absent,
/// and a content-free failure marker otherwise. The caller must fail closed on
/// a marker: a stale acknowledgement that survives deletion would let the test
/// emit its screenshot marker while an old `ack-<name>` file is still present,
/// so the driver could capture a later state under an earlier phase name.
///
/// [delete] is injectable so the negative control below can force a
/// [FileSystemException] without touching the device permissions.
String? _clearStaleAck({required File ack, void Function(File file)? delete}) {
  final void Function(File file) remove =
      delete ?? (File file) => file.deleteSync();
  try {
    if (!ack.existsSync()) {
      return null;
    }
  } on FileSystemException {
    return 'STALE_ACK_EXISTS_FAILED';
  }
  try {
    remove(ack);
  } on FileSystemException {
    return 'STALE_ACK_DELETE_FAILED';
  }
  try {
    if (ack.existsSync()) {
      return 'STALE_ACK_SURVIVED_DELETE';
    }
  } on FileSystemException {
    return 'STALE_ACK_VERIFY_FAILED';
  }
  return null;
}

/// Waits for the host driver to capture the named screenshot.
///
/// A previous aborted run can leave `ack-*` files behind; waiting for a stale
/// file would let the test race ahead of the driver. A stale file that cannot be
/// removed is a hard failure with an explicit marker, never a silent fallback.
Future<void> _waitForDriver(
  String name, {
  void Function(File file)? deleteOverride,
  File? ackOverride,
}) async {
  final File ack =
      ackOverride ?? File('$_fixtureRoot${Platform.pathSeparator}ack-$name');
  final String? staleFailure = _clearStaleAck(ack: ack, delete: deleteOverride);
  if (staleFailure != null) {
    _marker('HANDSHAKE_FAIL:$staleFailure:PHASE=$name');
    fail(
      'the $name handshake cannot be trusted: $staleFailure. A stale '
      'acknowledgement would let this phase race ahead of the driver, so the '
      'screenshot marker is withheld',
    );
  }
  final String? suffix = _screenshotPhases[name];
  expect(suffix, isNotNull, reason: 'unknown screenshot phase $name');
  _marker('SCREENSHOT_$suffix');
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 120));
  while (!ack.existsSync()) {
    if (DateTime.now().isAfter(deadline)) {
      _marker('HANDSHAKE_FAIL:ACK_TIMEOUT:PHASE=$name');
      fail('host driver did not acknowledge screenshot phase $name');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  _marker('HANDSHAKE_OK:PHASE=$name');
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
      'Run tools/android/t071_drive_touch.sh.',
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
/// imports as `IMP-006`/`unsupportedStructure` `unreadable`. Page 0 remains the
/// real analysis page this touch journey edits.
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

/// The stored page-display rectangle of the confirmed field under test.
core.Rect _storedRect(EditorScreenState state) {
  return state.content!.fields
      .firstWhere((core.ConfirmedField field) => field.id == _targetFieldId)
      .rect;
}

Rect _storedViewRect(EditorScreenState state) =>
    _flutterRect(_storedRect(state));

/// The page display box of page [pageIndex], used only for test preconditions.
Rect _pageDisplayBox(EditorScreenState state) {
  final core.PageGeometry geometry = state.content!.pages[_pageIndex].geometry;
  return Rect.fromLTWH(
    geometry.displayBox.left,
    geometry.displayBox.top,
    geometry.displayBox.width,
    geometry.displayBox.height,
  );
}

/// A page-viewport point mapped to a global screen point.
///
/// Asserts the point really lies inside the page viewport, so a gesture can
/// never silently land on the app bar, the page strip, or off-screen.
Offset _viewPointToScreen(WidgetTester tester, Offset local) {
  final Rect viewport = tester.getRect(find.byKey(_editorPageViewKey));
  expect(local.dx.isFinite && local.dy.isFinite, isTrue);
  expect(local.dx, inInclusiveRange(0.0, viewport.width));
  expect(local.dy, inInclusiveRange(0.0, viewport.height));
  return viewport.topLeft + local;
}

/// A page-display point on page [_pageIndex] mapped to a global screen point.
Offset _screenPoint(
  WidgetTester tester,
  EditorScreenState state,
  Offset displayPoint,
) {
  final PageViewMapping mapping = state.viewController.mappingFor(_pageIndex);
  return _viewPointToScreen(tester, mapping.displayToView(displayPoint));
}

/// Sets the view scale and centers [displayPoint] of page [_pageIndex].
///
/// This is the documented caller entry point of the T042/T078 view transform
/// (`PageViewController.setView`), not a geometry shortcut: it changes only the
/// transient scale/pan and never touches the document.
Future<void> _setScaleOnPoint(
  WidgetTester tester,
  EditorScreenState state,
  Offset displayPoint,
  double scale,
) async {
  final Size? viewport = state.viewController.viewportSize;
  expect(viewport, isNotNull, reason: 'the page viewport must be laid out');
  final PageViewMapping mapping = state.viewController.mappingFor(_pageIndex);
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
  expect(state.viewController.scale, scale);
}

/// Sets the view scale and centers [displayRect] in the viewport.
Future<void> _setScaleOnRect(
  WidgetTester tester,
  EditorScreenState state,
  Rect displayRect,
  double scale,
) {
  return _setScaleOnPoint(tester, state, displayRect.center, scale);
}

/// Sets the view for a phase screenshot so the asserted rectangle is visible.
///
/// At the higher gesture zooms the selected field is larger than the page
/// viewport (341.6 x 228 pt at 3x or 8x is far wider than 411 x 206 dp), so a
/// capture centred on the field interior would show no selection outline.
/// [focus] therefore names the evidence-bearing point of the phase — the
/// dragged corner, the clamped page edge, or the whole rectangle when it fits —
/// and the emitted marker records both the capture scale and what the capture
/// is centred on.
Future<void> _setShotView(
  WidgetTester tester,
  EditorScreenState state,
  Rect rect,
  double scale, {
  Offset? focus,
}) async {
  final Size? viewport = state.viewController.viewportSize;
  expect(viewport, isNotNull);
  final bool fits =
      rect.width * scale <= viewport!.width * 0.9 &&
      rect.height * scale <= viewport.height * 0.9;
  final Offset point = focus ?? (fits ? rect.center : rect.topLeft);
  await _setScaleOnPoint(tester, state, point, scale);
  _marker(
    'SHOT:SCALE_MILLI=${_scaleMilli(scale)}:'
    'FOCUS=${focus != null ? 'edge' : (fits ? 'rect' : 'corner')}:'
    'FITS=${{true: 1, false: 0}[fits]}:'
    'RECT_8TH=${_rectEighths(rect)}',
  );
}

/// A test precondition: [rect] must lie inside the page display box.
///
/// This guards the fixed gesture deltas against a changed fixture. It is a
/// precondition, not an expectation: if it fails the journey stops instead of
/// silently accepting a clamp the phase does not claim.
void _expectInsidePage(Rect rect, Rect pageBox, String phase) {
  expect(
    rect.left >= pageBox.left &&
        rect.top >= pageBox.top &&
        rect.right <= pageBox.right &&
        rect.bottom <= pageBox.bottom,
    isTrue,
    reason:
        '$phase precondition: expected $rect must lie inside the page box '
        '$pageBox so the phase proves the scaled delta and not a clamp',
  );
}

/// Asserts [actual] equals [expected] within floating-point noise.
///
/// The pointer delta is divided by the view scale exactly once, so the result
/// equals the intended page-display delta up to the last bits of the double
/// arithmetic (`(delta * scale) / scale`).
void _expectRectClose(
  core.Rect actual,
  Rect expected, {
  required String reason,
}) {
  expect(actual.left, closeTo(expected.left, 1e-6), reason: '$reason left');
  expect(actual.top, closeTo(expected.top, 1e-6), reason: '$reason top');
  expect(actual.width, closeTo(expected.width, 1e-6), reason: '$reason width');
  expect(
    actual.height,
    closeTo(expected.height, 1e-6),
    reason: '$reason height',
  );
}

/// Asserts that no store write happened while the pointer was down.
///
/// The editor sets `_headRevisionId` only from a store-verified commit and
/// `_content` only after that commit returns, so an unchanged head revision and
/// an unchanged canonical content snapshot on every pumped frame is proof that
/// no store save is issued per frame.
void _expectNoMidGestureWrite(
  EditorScreenState state, {
  required String? headBefore,
  required String contentBefore,
  required String phase,
}) {
  expect(
    state.headRevisionId,
    headBefore,
    reason: '$phase: a frame must not commit a revision',
  );
  expect(
    core.canonicalJsonEncode(state.content!.toJson()),
    contentBefore,
    reason: '$phase: the visible content must not change before the pointer up',
  );
}

/// Waits for exactly one store-verified commit and asserts its settled state.
Future<void> _waitForSingleCommit(
  WidgetTester tester,
  EditorScreenState state, {
  required String? headBefore,
  required String phase,
}) async {
  await _pumpUntil(
    tester,
    () => !state.reviewBusy && state.headRevisionId != headBefore,
    timeout: const Duration(seconds: 120),
    reason:
        '$phase: the gesture did not land exactly one verified store commit',
  );
  expect(
    state.durabilityStatus,
    isA<core.SavedDurabilityStatus>(),
    reason: '$phase: the committed revision must be durably saved',
  );
  expect(
    find.byKey(durabilityStatusLabelKey),
    findsOneWidget,
    reason: '$phase: the app bar must show the saved durability state',
  );
  expect(
    state.geometryGestureActive,
    isFalse,
    reason: '$phase: the gesture must be closed exactly once',
  );
  expect(
    find.byKey(_geometryPreviewKey),
    findsNothing,
    reason: '$phase: the transient preview must not outlive the commit',
  );
  expect(state.reviewBusy, isFalse);
}

/// Asserts exactly one store revision per gesture and none while it is held.
///
/// `savesBefore` / `savesAfter` are `_StoreSpy.saves` around the gesture and
/// `savesDuringHold` is the delta observed at the end of the hold window. The
/// editor commits at gesture end only, so a per-frame save (or a second commit)
/// shows up as a non-zero hold delta or as a delta other than one.
void _expectSingleStoreRevision({
  required int savesBefore,
  required int savesAfter,
  required int savesDuringHold,
  required String phase,
}) {
  expect(
    savesDuringHold,
    0,
    reason:
        '$phase: no store saveRevision call may happen while the pointer is '
        'held (observed $savesDuringHold)',
  );
  expect(
    savesAfter - savesBefore,
    1,
    reason:
        '$phase: exactly one store saveRevision call per gesture, observed '
        '${savesAfter - savesBefore}',
  );
}

/// The pointer move that crosses Flutter's pan slop for the scale recognizer.
///
/// `kPanSlop` is twice the touch slop (36 logical pixels). A first move of 40
/// pixels therefore starts the scale gesture, and the second move lands on the
/// exact intended cumulative delta.
const double _slopCrossingPx = 40;

/// Moves [gesture] by [total] in two steps: a slop-crossing step and the
/// remainder, so the cumulative pointer delta from touch-down is exactly
/// [total].
Future<void> _moveByTotal(TestGesture gesture, Offset total) async {
  final double distance = total.distance;
  expect(
    distance,
    greaterThan(36),
    reason:
        'the intended pointer delta must exceed the pan slop so the scale '
        'gesture starts',
  );
  final Offset step = total / distance * math.min(_slopCrossingPx, distance);
  await gesture.moveBy(step);
  final Offset remainder = total - step;
  if (remainder != Offset.zero) {
    await gesture.moveBy(remainder);
  }
}

/// The fastest and slowest pointer-up -> committed-revision latency observed.
///
/// The hold window must exceed the fastest verified commit, which is the
/// physical commit cost of this build on this device. The slowest value is
/// recorded too: a scheduling outlier (one run observed 18 s for a commit that
/// normally takes 40-600 ms) must not be able to force an unbounded journey, and
/// it is reported rather than hidden.
Duration _commitLatencyMin = Duration.zero;
Duration _commitLatencyMax = Duration.zero;

/// The hold window for the next gesture: at least the base window and at least
/// twice the fastest verified commit, bounded by [_maxHoldWindow].
Duration _holdWindow() {
  final Duration doubled = _commitLatencyMin * 2;
  final Duration window = doubled > _holdWindowBase ? doubled : _holdWindowBase;
  return window > _maxHoldWindow ? _maxHoldWindow : window;
}

/// Drives one claimed geometry gesture and waits for its single commit.
///
/// While the pointer is held the test keeps pumping for a window longer than the
/// fastest measured commit latency and asserts, on *every* frame, that the gesture
/// is still active, the preview is painted, no commit is in flight
/// (`reviewBusy` false), the head/content are unchanged, and the count of real
/// `saveRevision` calls has not increased. Returns the stored rectangle the
/// gesture started from; the caller asserts the committed geometry.
Future<core.Rect> _dragToCommit(
  WidgetTester tester,
  EditorScreenState state, {
  required String phase,
  required Offset startLocal,
  required Offset totalPx,
}) async {
  final core.Rect previous = _storedRect(state);
  final double scale = state.viewController.mappingFor(_pageIndex).scale;
  final String? headBefore = state.headRevisionId;
  final String contentBefore = core.canonicalJsonEncode(
    state.content!.toJson(),
  );
  final int savesBefore = _storeSpy.saves;
  final Duration holdWindow = _holdWindow();
  expect(
    holdWindow,
    greaterThan(_commitLatencyMin),
    reason:
        '$phase: the hold window must be longer than the fastest measured '
        'commit latency (${_commitLatencyMin.inMilliseconds} ms); the slowest '
        'observed latency so far is ${_commitLatencyMax.inMilliseconds} ms',
  );

  final TestGesture gesture = await tester.startGesture(
    _viewPointToScreen(tester, startLocal),
  );
  await _moveByTotal(gesture, totalPx);
  await tester.pump();
  expect(
    state.geometryGestureActive,
    isTrue,
    reason:
        '$phase: the drag on the selected field must be claimed by the touch '
        'geometry layer',
  );
  expect(
    find.byKey(_geometryPreviewKey),
    findsWidgets,
    reason: '$phase: the in-gesture preview must be painted',
  );
  expect(
    _storedRect(state),
    previous,
    reason: '$phase: the stored rectangle must not change before the up',
  );

  int frames = 1;
  final DateTime holdStart = DateTime.now();
  while (DateTime.now().difference(holdStart) < holdWindow) {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await tester.pump();
    frames++;
    // Explicit in-flight assertions on every held frame: the gesture must still
    // own the pointer, the preview must still be painted, and no commit may be
    // in flight before the pointer lifts.
    expect(
      state.geometryGestureActive,
      isTrue,
      reason: '$phase: the gesture claim must survive the hold window',
    );
    expect(
      find.byKey(_geometryPreviewKey),
      findsWidgets,
      reason: '$phase: the preview must stay painted during the hold window',
    );
    expect(
      state.reviewBusy,
      isFalse,
      reason: '$phase: no commit may be in flight while the pointer is held',
    );
    _expectNoMidGestureWrite(
      state,
      headBefore: headBefore,
      contentBefore: contentBefore,
      phase: phase,
    );
  }
  final Duration held = DateTime.now().difference(holdStart);
  expect(
    held,
    greaterThanOrEqualTo(holdWindow),
    reason: '$phase: the hold window must actually elapse',
  );
  final int savesDuringHold = _storeSpy.saves - savesBefore;
  expect(
    savesDuringHold,
    0,
    reason:
        '$phase: the held frames must not write a store revision '
        '(observed $savesDuringHold real saveRevision calls)',
  );
  expect(
    _storedRect(state),
    previous,
    reason: '$phase: no preview frame may persist geometry',
  );

  final DateTime upAt = DateTime.now();
  await gesture.up();
  await tester.pump();
  await _waitForSingleCommit(
    tester,
    state,
    headBefore: headBefore,
    phase: phase,
  );
  final Duration latency = DateTime.now().difference(upAt);
  if (_commitLatencyMin == Duration.zero || latency < _commitLatencyMin) {
    _commitLatencyMin = latency;
  }
  if (latency > _commitLatencyMax) {
    _commitLatencyMax = latency;
  }
  final int savesAfter = _storeSpy.saves;
  _expectSingleStoreRevision(
    savesBefore: savesBefore,
    savesAfter: savesAfter,
    savesDuringHold: savesDuringHold,
    phase: phase,
  );
  _marker(
    'COMMIT:$phase:PAGE=$_pageIndex:FIELD=$_targetFieldId:'
    'SCALE_MILLI=${_scaleMilli(scale)}:HELD_FRAMES=$frames:'
    'HOLD_MS=${held.inMilliseconds}:'
    'LATENCY_MS=${latency.inMilliseconds}:'
    'MIN_LATENCY_MS=${_commitLatencyMin.inMilliseconds}:'
    'MAX_LATENCY_MS=${_commitLatencyMax.inMilliseconds}:'
    'SAVES_HELD=$savesDuringHold:SAVES_DELTA=${savesAfter - savesBefore}:'
    'REVIEW_BUSY_HELD=0:PREVIEW_HELD=1',
  );
  return previous;
}

/// Selects the confirmed field through the real T077 tap path.
///
/// A tap on the confirmed field opens the value sheet (the production
/// `_handleOverlaySelection` path); the sheet is then closed and the selection is
/// asserted from the composed controller. This is the same tap -> sheet -> close
/// path T071A proves, so no selection is set directly on the controller.
Future<void> _selectFieldThroughTap(
  WidgetTester tester,
  EditorScreenState state,
) async {
  final Rect rect = _storedViewRect(state);
  await tester.tapAt(_screenPoint(tester, state, rect.center));
  await _pumpUntil(
    tester,
    () => find.byKey(fieldValueSheetKey).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 120),
    reason: 'tapping the confirmed field did not open the value sheet',
  );
  _marker('SELECTION_TAP:PHASE=OPEN:SHEET=1');
  await tester.tap(find.byKey(fieldValueCloseKey));
  await _pumpUntil(
    tester,
    () => find.byKey(fieldValueSheetKey).evaluate().isEmpty,
    timeout: const Duration(seconds: 120),
    reason: 'the value sheet did not close after the selection tap',
  );
  await _pumpUntil(
    tester,
    () => tester.view.viewInsets.bottom == 0,
    timeout: const Duration(seconds: 120),
    reason:
        'the software keyboard did not dismiss after the selection tap, so '
        'the page viewport would not be settled for the touch journey',
  );
  await tester.pumpAndSettle();
  expect(
    state.selection.selectedId,
    _targetFieldId,
    reason: 'the real tap path must select the confirmed field',
  );
  _marker(
    'SELECTION_TAP:PHASE=CLOSED:SELECTED=1:FIELD=$_targetFieldId:'
    'SHEET_OPENED=1',
  );
}

/// One corner or edge resize gesture with its explicit expected rectangle.
///
/// [handleDisplay] is the touched page-display point (possibly outside the
/// stored rectangle for the hit-region proof); [delta] is the exact page-display
/// movement of the dragged edges; [expected] states which edges move. Every edge
/// the gesture does not drag must stay bit-for-bit fixed, which is the
/// "opposite anchor" rule of `contracts/editor-interactions.md` §4.
Future<void> _resizeStep(
  WidgetTester tester,
  EditorScreenState state, {
  required String phase,
  required String handle,
  required Offset handleDisplay,
  required Offset delta,
  required Rect expected,
  required Rect pageBox,
  required bool movesLeft,
  required bool movesTop,
  required bool movesRight,
  required bool movesBottom,
}) async {
  _expectInsidePage(expected, pageBox, phase);
  final double scale = state.viewController.mappingFor(_pageIndex).scale;
  final List<String> moved = <String>[
    if (movesLeft) 'left',
    if (movesTop) 'top',
    if (movesRight) 'right',
    if (movesBottom) 'bottom',
  ];
  _marker(
    'PHASE:$phase:HANDLE=$handle:SCALE_MILLI=${_scaleMilli(scale)}:'
    'BEFORE_RECT_8TH=${_rectEighths(_storedViewRect(state))}:'
    'DELTA_8TH=${_eighths(delta.dx)}:${_eighths(delta.dy)}:'
    'EXPECTED_RECT_8TH=${_rectEighths(expected)}:'
    'MOVED=${moved.join('+')}',
  );
  final core.Rect before = await _dragToCommit(
    tester,
    state,
    phase: phase,
    startLocal: state.viewController
        .mappingFor(_pageIndex)
        .displayToView(handleDisplay),
    totalPx: Offset(delta.dx * scale, delta.dy * scale),
  );
  final core.Rect actual = _storedRect(state);
  final Rect beforeRect = _flutterRect(before);
  if (!movesLeft) {
    expect(
      actual.left,
      beforeRect.left,
      reason: '$phase: the left edge is not dragged and stays fixed',
    );
  }
  if (!movesTop) {
    expect(
      actual.top,
      beforeRect.top,
      reason: '$phase: the top edge is not dragged and stays fixed',
    );
  }
  if (!movesRight) {
    expect(
      actual.right,
      beforeRect.right,
      reason: '$phase: the right edge is the fixed opposite anchor',
    );
  }
  if (!movesBottom) {
    expect(
      actual.bottom,
      beforeRect.bottom,
      reason: '$phase: the bottom edge is the fixed opposite anchor',
    );
  }
  if (movesLeft) {
    expect(
      actual.left,
      isNot(beforeRect.left),
      reason: '$phase: the dragged left edge must move',
    );
  }
  if (movesTop) {
    expect(
      actual.top,
      isNot(beforeRect.top),
      reason: '$phase: the dragged top edge must move',
    );
  }
  if (movesRight) {
    expect(
      actual.right,
      isNot(beforeRect.right),
      reason: '$phase: the dragged right edge must move',
    );
  }
  if (movesBottom) {
    expect(
      actual.bottom,
      isNot(beforeRect.bottom),
      reason: '$phase: the dragged bottom edge must move',
    );
  }
  _expectRectClose(
    actual,
    expected,
    reason: '$phase: only the dragged edges move, by delta / scale once',
  );
  _marker(
    'RESIZE:$phase:HANDLE=$handle:'
    'AFTER_RECT_8TH=${_coreRectEighths(actual)}:'
    'MOVED=${moved.join('+')}:FIXED=${<String>[if (!movesLeft) 'left', if (!movesTop) 'top', if (!movesRight) 'right', if (!movesBottom) 'bottom'].join('+')}:COMMIT=1',
  );
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
    expect(damaged, isNot(orderedEquals(fixtureBytes)));
    expect(crypto.sha256.convert(damaged).toString(), _damagedFixtureSha256);
    scratchSource = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}t071-'
      '${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    scratchSource!.writeAsBytesSync(damaged, flush: true);
    final Uint8List copied = scratchSource!.readAsBytesSync();
    expect(copied.length, _fixtureSizeBytes);
    expect(crypto.sha256.convert(copied).toString(), _damagedFixtureSha256);
    _marker('DAMAGED_FIXTURE_READY:BYTES=$_fixtureSizeBytes:MATCH=1');
  });

  tearDownAll(() async {
    // The test-side cleanup runs first and reports what it actually did; the
    // CLEANUP_DONE marker is emitted only after both steps are verified, so it
    // can never stand for a cleanup that did not happen. The driver verifies the
    // device-side cleanup separately (`cleanup-verification.txt`).
    bool hookCleared = !hookArmed;
    if (hookArmed) {
      try {
        await _clearHook();
        hookCleared = true;
      } catch (_) {
        // The engine may already be detached; the driver clears app data too,
        // but this test must not claim a cleanup it could not perform.
        hookCleared = false;
      }
    }
    bool scratchGone = true;
    final File? scratch = scratchSource;
    if (scratch != null) {
      try {
        if (scratch.existsSync()) {
          scratch.deleteSync();
        }
        scratchGone = !scratch.existsSync();
      } on FileSystemException {
        scratchGone = false;
      }
    }
    _marker(
      'CLEANUP:HOOK_CLEARED=${hookCleared ? 1 : 0}:'
      'SCRATCH_GONE=${scratchGone ? 1 : 0}',
    );
    if (hookCleared && scratchGone) {
      _marker('CLEANUP_DONE');
    } else {
      _marker('CLEANUP_INCOMPLETE');
    }
    expect(hookCleared, isTrue, reason: 'the import hook must be cleared');
    expect(scratchGone, isTrue, reason: 'the scratch source must be deleted');
  });

  // ---------------------------------------------------------------------
  // Negative controls. These run on the device as ordinary tests in the same
  // `flutter test` invocation and prove the two handshake/commit assertions are
  // not vacuous before the journey relies on them.
  // ---------------------------------------------------------------------

  test('the exactly-one-revision assertion rejects a double commit and a '
      'held save', () {
    expect(
      () => _expectSingleStoreRevision(
        savesBefore: 4,
        savesAfter: 5,
        savesDuringHold: 0,
        phase: 'control-pass',
      ),
      returnsNormally,
      reason: 'one save in the gesture and none held must pass',
    );
    expect(
      () => _expectSingleStoreRevision(
        savesBefore: 4,
        savesAfter: 6,
        savesDuringHold: 0,
        phase: 'control-double-commit',
      ),
      throwsA(isA<TestFailure>()),
      reason: 'two saves for one gesture must fail the assertion',
    );
    expect(
      () => _expectSingleStoreRevision(
        savesBefore: 4,
        savesAfter: 5,
        savesDuringHold: 1,
        phase: 'control-held-save',
      ),
      throwsA(isA<TestFailure>()),
      reason: 'a save while the pointer is held must fail the assertion',
    );
    expect(
      () => _expectSingleStoreRevision(
        savesBefore: 4,
        savesAfter: 4,
        savesDuringHold: 0,
        phase: 'control-no-commit',
      ),
      throwsA(isA<TestFailure>()),
      reason: 'zero saves for a committed gesture must fail the assertion',
    );
    _marker(
      'NEGATIVE_CONTROL:REVISION_ASSERTION=1:DOUBLE_REJECTED=1:'
      'HELD_REJECTED=1:ZERO_REJECTED=1',
    );
  });

  test('the stale-ack handshake fails closed', () async {
    // The staging directory is shell-owned and mode 755, so the app can read an
    // acknowledgement but not create or delete one there. The probe therefore
    // uses app-writable storage and an explicit ack override; the production
    // handshake path resolves the same helper against the staging directory.
    final Directory probeDirectory = Directory.systemTemp.createTempSync(
      't071-ack-probe-',
    );
    final File probe = File(
      '${probeDirectory.path}${Platform.pathSeparator}ack-probe',
    );
    addTearDown(() {
      if (probe.existsSync()) {
        probe.deleteSync();
      }
      if (probeDirectory.existsSync()) {
        probeDirectory.deleteSync(recursive: true);
      }
    });

    // Absent acknowledgement: nothing to clear.
    expect(_clearStaleAck(ack: probe), isNull);
    // Stale acknowledgement: removed and verified absent.
    probe.writeAsStringSync('stale');
    expect(_clearStaleAck(ack: probe), isNull);
    expect(probe.existsSync(), isFalse);
    // Injected delete failure: reported, not swallowed.
    probe.writeAsStringSync('stale');
    expect(
      _clearStaleAck(
        ack: probe,
        delete: (File file) =>
            throw const FileSystemException('injected delete failure'),
      ),
      'STALE_ACK_DELETE_FAILED',
    );
    expect(probe.existsSync(), isTrue);

    // The handshake itself must fail closed and withhold the screenshot marker
    // when the stale file cannot be removed.
    final String marker = 'HANDSHAKE_FAIL:STALE_ACK_DELETE_FAILED:PHASE=probe';
    await expectLater(
      _waitForDriver(
        'probe',
        ackOverride: probe,
        deleteOverride: (File file) =>
            throw const FileSystemException('injected delete failure'),
      ),
      throwsA(isA<TestFailure>()),
      reason: 'a stale acknowledgement that cannot be removed must abort',
    );
    expect(_emittedMarkers, contains(marker));
    expect(
      _emittedMarkers.where((String entry) => entry.startsWith('SCREENSHOT_')),
      isNot(contains('SCREENSHOT_null')),
      reason: 'no screenshot marker may be emitted for a failed handshake',
    );
    probe.deleteSync();
    _marker('NEGATIVE_CONTROL:STALE_ACK=1:DELETE_FAILURE_FAILS_CLOSED=1');
  });

  testWidgets('move and resize the confirmed field on the touch surface', (
    WidgetTester tester,
  ) async {
    _startApp();
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
      'ANALYSIS_READY:STATE=${state.analysisStateKey}:'
      'PAGES=${state.content!.pageCount}:'
      'SUGGESTIONS=${state.content!.suggestions.length}:'
      'CONFIRMED=${state.content!.fields.length}',
    );

    // Confirm the largest unresolved text suggestion on the edited page. The
    // largest one gives the touch journey a field with a real body, exactly
    // as a user would confirm the most obvious input line first.
    core.FieldSuggestion? suggestion;
    double bestArea = -1;
    for (final core.FieldSuggestion candidate in state.content!.suggestions) {
      if (candidate.pageIndex != _pageIndex ||
          candidate.proposedType != core.FieldType.text ||
          candidate.resolution != core.SuggestionResolution.unresolved) {
        continue;
      }
      final double area = candidate.rect.width * candidate.rect.height;
      if (area > bestArea) {
        bestArea = area;
        suggestion = candidate;
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
    expect(field.pageIndex, _pageIndex);
    _targetFieldId = field.id;
    _marker(
      'FIELD_CONFIRMED:PAGE=$_pageIndex:FIELD=$_targetFieldId:'
      'RECT_8TH=${_coreRectEighths(field.rect)}',
    );

    await _selectFieldThroughTap(tester, state);
    await _pumpUntil(
      tester,
      () =>
          state.viewController.hasViewport &&
          state.viewController.scale > 0 &&
          state.viewController.mappingFor(_pageIndex).scale > 0,
      timeout: const Duration(seconds: 60),
      reason: 'the page viewer did not report a laid-out viewport',
    );
    final double fitScale = state.viewController.fitWidthScale;
    final Rect pageBox = _pageDisplayBox(state);
    _marker(
      'VIEW_READY:FIT_MILLI=${_scaleMilli(fitScale)}:'
      'MIN_MILLI=${_scaleMilli(state.viewController.minScale)}:'
      'MAX_MILLI=${_scaleMilli(state.viewController.maxScale)}:'
      'VIEWPORT_W=${state.viewController.viewportSize!.width.round()}:'
      'VIEWPORT_H=${state.viewController.viewportSize!.height.round()}',
    );

    // -------------------------------------------------------------------
    // A. All four corner handles (screenshot: resize-corners).
    //
    // Every corner moves its two edges 20 pt outward at the 3 x fit-width
    // gesture zoom, so the pointer delta is above Flutter's 36 px pan slop and
    // the page-display delta stays 20 pt. The zoom is not assumed from the
    // viewport: the nominal 3x margin is asserted as a precondition, the used
    // zoom is raised to at least `40 px / 20 pt` when the viewport is narrower
    // than nominal, and both margins are recorded in `T071_RESIZE_ZOOM`. The
    // diagonally opposite corner is asserted bit-for-bit, and the free aspect
    // ratio is proved by the width and height changing by the same 20 pt here
    // and by different amounts in the edge phase.
    // -------------------------------------------------------------------
    const double step = _resizeStepPt;
    final double nominalResizeScale = fitScale * _resizeGestureZoom;
    final double nominalEdgePointerPx = step * nominalResizeScale;
    expect(
      nominalEdgePointerPx,
      greaterThan(_panSlopPx),
      reason:
          'precondition: the nominal ${_resizeGestureZoom}x fit-width gesture '
          'zoom must put a $step pt edge move above the ${_panSlopPx}px pan '
          'slop on this viewport (observed '
          '${nominalEdgePointerPx.toStringAsFixed(2)}px)',
    );
    final double minResizeScale = _requiredEdgePointerPx / step;
    final double resizeScale = nominalResizeScale > minResizeScale
        ? nominalResizeScale
        : minResizeScale;
    final double usedEdgePointerPx = step * resizeScale;
    expect(
      usedEdgePointerPx,
      greaterThanOrEqualTo(_requiredEdgePointerPx),
      reason:
          'precondition: the used resize zoom must keep a $step pt edge move at '
          'least ${_requiredEdgePointerPx}px, above the ${_panSlopPx}px pan '
          'slop',
    );
    _marker(
      'RESIZE_ZOOM:FIT_MILLI=${_scaleMilli(fitScale)}:'
      'NOMINAL_ZOOM_MILLI=${_scaleMilli(nominalResizeScale)}:'
      'NOMINAL_EDGE_PTR_PX=${nominalEdgePointerPx.toStringAsFixed(2)}:'
      'USED_ZOOM_MILLI=${_scaleMilli(resizeScale)}:'
      'USED_EDGE_PTR_PX=${usedEdgePointerPx.toStringAsFixed(2)}:'
      'PAN_SLOP_PX=${_panSlopPx.round()}:'
      'REQUIRED_PX=${_requiredEdgePointerPx.round()}:OK=1',
    );

    // topLeft: left and top move; right and bottom are the fixed anchor.
    {
      await _setScaleOnPoint(
        tester,
        state,
        _storedViewRect(state).topLeft,
        resizeScale,
      );
      final Rect r = _storedViewRect(state);
      final Rect expected = Rect.fromLTRB(
        r.left - step,
        r.top - step,
        r.right,
        r.bottom,
      );
      await _resizeStep(
        tester,
        state,
        phase: 'resize-corners-topLeft',
        handle: 'topLeft',
        handleDisplay: r.topLeft,
        delta: Offset(-step, -step),
        expected: expected,
        pageBox: pageBox,
        movesLeft: true,
        movesTop: true,
        movesRight: false,
        movesBottom: false,
      );
      expect(
        expected.width / expected.height,
        isNot(closeTo(r.width / r.height, 1e-9)),
        reason: 'a corner drag keeps the aspect ratio free',
      );
    }

    // topRight: right and top move; left and bottom are the fixed anchor.
    {
      await _setScaleOnPoint(
        tester,
        state,
        _storedViewRect(state).topRight,
        resizeScale,
      );
      final Rect r = _storedViewRect(state);
      await _resizeStep(
        tester,
        state,
        phase: 'resize-corners-topRight',
        handle: 'topRight',
        handleDisplay: r.topRight,
        delta: Offset(step, -step),
        expected: Rect.fromLTRB(r.left, r.top - step, r.right + step, r.bottom),
        pageBox: pageBox,
        movesLeft: false,
        movesTop: true,
        movesRight: true,
        movesBottom: false,
      );
    }

    // bottomLeft: left and bottom move; right and top are the fixed anchor.
    {
      await _setScaleOnPoint(
        tester,
        state,
        _storedViewRect(state).bottomLeft,
        resizeScale,
      );
      final Rect r = _storedViewRect(state);
      await _resizeStep(
        tester,
        state,
        phase: 'resize-corners-bottomLeft',
        handle: 'bottomLeft',
        handleDisplay: r.bottomLeft,
        delta: Offset(-step, step),
        expected: Rect.fromLTRB(r.left - step, r.top, r.right, r.bottom + step),
        pageBox: pageBox,
        movesLeft: true,
        movesTop: false,
        movesRight: false,
        movesBottom: true,
      );
    }

    // bottomRight: right and bottom move; left and top are the fixed anchor.
    {
      await _setScaleOnPoint(
        tester,
        state,
        _storedViewRect(state).bottomRight,
        resizeScale,
      );
      final Rect r = _storedViewRect(state);
      await _resizeStep(
        tester,
        state,
        phase: 'resize-corners-bottomRight',
        handle: 'bottomRight',
        handleDisplay: r.bottomRight,
        delta: Offset(step, step),
        expected: Rect.fromLTRB(r.left, r.top, r.right + step, r.bottom + step),
        pageBox: pageBox,
        movesLeft: false,
        movesTop: false,
        movesRight: true,
        movesBottom: true,
      );
    }

    await _setShotView(tester, state, _storedViewRect(state), fitScale);
    _marker(
      'RESIZE_CORNERS_DONE:HANDLES=topLeft,topRight,bottomLeft,bottomRight:'
      'RECT_8TH=${_coreRectEighths(_storedRect(state))}',
    );
    await _waitForDriver('resize-corners');

    // -------------------------------------------------------------------
    // B. All four edge handles (screenshot: resize-edges).
    //
    // The centerLeft drag deliberately starts 4 *display points* outside the
    // stored rectangle: at the 3 x gesture zoom that is ~8.3 dp outside, still
    // inside the 24 dp handle hit region, so a successful claim proves the
    // region extends beyond the stored geometry. Only the dragged edge moves.
    // The bottom edge also grows the field so the body drags below have a real
    // body at 0.5x, and the right edge narrows it so the moves have page room.
    // -------------------------------------------------------------------
    // topCenter: only the top edge moves (inward, keeping the page margin).
    {
      await _setScaleOnPoint(
        tester,
        state,
        Offset(_storedViewRect(state).center.dx, _storedViewRect(state).top),
        resizeScale,
      );
      final Rect r = _storedViewRect(state);
      await _resizeStep(
        tester,
        state,
        phase: 'resize-edges-topCenter',
        handle: 'topCenter',
        handleDisplay: Offset(r.center.dx, r.top),
        delta: Offset(0, step),
        expected: Rect.fromLTRB(r.left, r.top + step, r.right, r.bottom),
        pageBox: pageBox,
        movesLeft: false,
        movesTop: true,
        movesRight: false,
        movesBottom: false,
      );
    }

    // bottomCenter: only the bottom edge moves, and it grows.
    {
      await _setScaleOnPoint(
        tester,
        state,
        Offset(_storedViewRect(state).center.dx, _storedViewRect(state).bottom),
        resizeScale,
      );
      final Rect r = _storedViewRect(state);
      await _resizeStep(
        tester,
        state,
        phase: 'resize-edges-bottomCenter',
        handle: 'bottomCenter',
        handleDisplay: Offset(r.center.dx, r.bottom),
        delta: const Offset(0, _growStepPt),
        expected: Rect.fromLTRB(r.left, r.top, r.right, r.bottom + _growStepPt),
        pageBox: pageBox,
        movesLeft: false,
        movesTop: false,
        movesRight: false,
        movesBottom: true,
      );
    }

    // centerLeft: only the left edge moves, and the touch point is outside the
    // stored rectangle but inside the 24 dp handle hit region.
    {
      const double outsidePt = 4;
      await _setScaleOnPoint(
        tester,
        state,
        Offset(_storedViewRect(state).left, _storedViewRect(state).center.dy),
        resizeScale,
      );
      final Rect r = _storedViewRect(state);
      final double scale = state.viewController.mappingFor(_pageIndex).scale;
      expect(
        outsidePt * scale,
        lessThan(_contractHandleHitDp / 2),
        reason: 'the outside touch point must stay inside the 24 dp region',
      );
      await _resizeStep(
        tester,
        state,
        phase: 'resize-edges-centerLeft-outside-hit',
        handle: 'centerLeft',
        handleDisplay: Offset(r.left - outsidePt, r.center.dy),
        delta: Offset(step, 0),
        expected: Rect.fromLTRB(r.left + step, r.top, r.right, r.bottom),
        pageBox: pageBox,
        movesLeft: true,
        movesTop: false,
        movesRight: false,
        movesBottom: false,
      );
      _marker(
        'HIT_REGION:EDGE=centerLeft:OUTSIDE_PT=$outsidePt:'
        'OUTSIDE_DP=${(outsidePt * scale).toStringAsFixed(2)}:'
        'MIN_BAND_DP=$_contractHandleHitDp:CLAIMED=1',
      );
    }

    // centerRight: only the right edge moves; it narrows the field so the
    // body drags have page room on both sides.
    {
      await _setScaleOnPoint(
        tester,
        state,
        Offset(_storedViewRect(state).right, _storedViewRect(state).center.dy),
        resizeScale,
      );
      final Rect r = _storedViewRect(state);
      await _resizeStep(
        tester,
        state,
        phase: 'resize-edges-centerRight',
        handle: 'centerRight',
        handleDisplay: Offset(r.right, r.center.dy),
        delta: const Offset(-_narrowStepPt, 0),
        expected: Rect.fromLTRB(
          r.left,
          r.top,
          r.right - _narrowStepPt,
          r.bottom,
        ),
        pageBox: pageBox,
        movesLeft: false,
        movesTop: false,
        movesRight: true,
        movesBottom: false,
      );
    }

    await _setShotView(tester, state, _storedViewRect(state), fitScale * 1.25);
    _marker(
      'RESIZE_EDGES_DONE:HANDLES=topCenter,bottomCenter,centerLeft,centerRight:'
      'RECT_8TH=${_coreRectEighths(_storedRect(state))}',
    );
    await _waitForDriver('resize-edges');

    // -------------------------------------------------------------------
    // C. Body drag at 0.5x, 1x, 3x, and 8x fit width, plus one clamped drag.
    //
    // Each phase sets an exact view scale, then drags the field body with a
    // single pointer delta whose page-display value is `pointerDelta / scale`.
    // The stored size is unchanged and the expected rectangle is computed
    // from that one division, so a double division (or a per-frame
    // accumulation) cannot pass.
    // -------------------------------------------------------------------
    Future<void> bodyDragPhase({
      required String phase,
      required String screenshot,
      required double scaleFactor,
      required Offset totalPx,
      required double screenshotScaleFactor,
    }) async {
      final double targetScale = fitScale * scaleFactor;
      await _setScaleOnRect(tester, state, _storedViewRect(state), targetScale);
      final double scale = state.viewController.mappingFor(_pageIndex).scale;
      expect(scale, targetScale);
      final core.Rect before = _storedRect(state);
      final Rect r = _flutterRect(before);
      final Offset displayDelta = Offset(
        totalPx.dx / scale,
        totalPx.dy / scale,
      );
      final Rect expected = r.shift(displayDelta);
      _expectInsidePage(expected, pageBox, phase);
      _marker(
        'PHASE:$phase:SCALE_MILLI=${_scaleMilli(scale)}:'
        'DELTA_8TH=${_eighths(displayDelta.dx)}:'
        '${_eighths(displayDelta.dy)}:'
        'BEFORE_RECT_8TH=${_rectEighths(r)}',
      );
      await _dragToCommit(
        tester,
        state,
        phase: phase,
        startLocal: state.viewController
            .mappingFor(_pageIndex)
            .displayToView(r.center),
        totalPx: totalPx,
      );
      final core.Rect actual = _storedRect(state);
      _expectRectClose(
        actual,
        expected,
        reason:
            '$phase: a body drag moves by pointerDelta / scale exactly once',
      );
      // The size is preserved by the move rule. The tolerance is far below the
      // 1/8 pt evidence grid and below the persisted 0.001 pt quantization: a
      // shift re-derives an edge as `(right + dx) - (left + dx)`, which may
      // differ from `right - left` in the last bits of the double.
      expect(
        actual.width,
        closeTo(before.width, 1e-9),
        reason: '$phase: a body drag must not resize the field',
      );
      expect(
        actual.height,
        closeTo(before.height, 1e-9),
        reason: '$phase: a body drag must not resize the field',
      );
      expect(
        actual.left,
        isNot(before.left),
        reason: '$phase: the field must actually have moved',
      );
      _marker(
        'MOVE:$phase:PAGE=$_pageIndex:FIELD=$_targetFieldId:'
        'SCALE_MILLI=${_scaleMilli(scale)}:'
        'RECT_8TH=${_coreRectEighths(actual)}:CLAMPED=0',
      );
      await _setShotView(
        tester,
        state,
        _storedViewRect(state),
        fitScale * screenshotScaleFactor,
      );
      await _waitForDriver(screenshot);
    }

    // 0.5x: the pointer delta is dominated by the pan slop at this zoom, which
    // is exactly what "divided by the current scale once" means.
    await bodyDragPhase(
      phase: 'move-0.5x',
      screenshot: 'move-0.5x',
      scaleFactor: 0.5,
      totalPx: const Offset(44, 14),
      screenshotScaleFactor: 0.5,
    );
    await bodyDragPhase(
      phase: 'move-1x',
      screenshot: 'move-1x',
      scaleFactor: 1,
      totalPx: const Offset(-44, -14),
      screenshotScaleFactor: 1,
    );
    await bodyDragPhase(
      phase: 'move-3x',
      screenshot: 'move-3x',
      scaleFactor: 3,
      totalPx: const Offset(44, 14),
      screenshotScaleFactor: 3,
    );
    await bodyDragPhase(
      phase: 'move-8x',
      screenshot: 'move-8x',
      scaleFactor: 8,
      totalPx: const Offset(-44, -14),
      screenshotScaleFactor: 8,
    );

    // One more 8x drag far past the page edge: the rectangle keeps its size
    // and stops exactly at the page box, which is the §4 clamp.
    late core.Rect preClampRect;
    {
      await _setScaleOnRect(
        tester,
        state,
        _storedViewRect(state),
        fitScale * 8,
      );
      final double scale = state.viewController.mappingFor(_pageIndex).scale;
      final core.Rect before = _storedRect(state);
      preClampRect = before;
      const Offset totalPx = Offset(900, 0);
      final Offset displayDelta = Offset(totalPx.dx / scale, 0);
      _marker(
        'PHASE:move-clamped:SCALE_MILLI=${_scaleMilli(scale)}:'
        'DELTA_8TH=${_eighths(displayDelta.dx)}:0:'
        'BEFORE_RECT_8TH=${_coreRectEighths(before)}:'
        'PAGE_W_8TH=${_eighths(pageBox.width)}',
      );
      expect(
        before.right + displayDelta.dx,
        greaterThan(pageBox.right),
        reason: 'the clamped phase must actually overshoot the page edge',
      );
      await _dragToCommit(
        tester,
        state,
        phase: 'move-clamped',
        startLocal: state.viewController
            .mappingFor(_pageIndex)
            .displayToView(_flutterRect(before).center),
        totalPx: totalPx,
      );
      final core.Rect actual = _storedRect(state);
      expect(
        actual.width,
        closeTo(before.width, 1e-9),
        reason: 'clamping never resizes the field',
      );
      expect(
        actual.height,
        closeTo(before.height, 1e-9),
        reason: 'clamping never resizes the field',
      );
      expect(
        actual.right,
        closeTo(pageBox.right, 1e-9),
        reason: 'the clamped move stops exactly at the page right edge',
      );
      expect(
        actual.left,
        closeTo(pageBox.right - before.width, 1e-9),
        reason: 'the clamped move keeps the page-relative offset',
      );
      expect(
        actual.top,
        closeTo(before.top, 1e-9),
        reason: 'no vertical movement was requested',
      );
      _marker(
        'MOVE:move-clamped:PAGE=$_pageIndex:FIELD=$_targetFieldId:'
        'SCALE_MILLI=${_scaleMilli(scale)}:'
        'RECT_8TH=${_coreRectEighths(actual)}:CLAMPED=1',
      );
      // The clamp evidence is the field's right edge sitting exactly on the
      // page's right edge, so the capture is centred there.
      await _setShotView(
        tester,
        state,
        _storedViewRect(state),
        fitScale * 4.5,
        focus: _storedViewRect(state).topRight,
      );
      await _waitForDriver('move-clamped');
    }

    // -------------------------------------------------------------------
    // D. Undo restores the exact previous rectangle (screenshot: undo).
    //
    // The newest history entry is the clamped move, so undo must write back
    // its exact stored `before` snapshot rather than re-deriving a rectangle.
    // -------------------------------------------------------------------
    {
      final core.Rect current = _storedRect(state);
      expect(
        current,
        isNot(preClampRect),
        reason: 'the clamped move must still be the newest committed change',
      );
      final String? headBefore = state.headRevisionId;
      final Finder undoFinder = find.byKey(
        const ValueKey<String>(undoReviewKey),
      );
      expect(undoFinder, findsOneWidget);
      expect(state.canUndoReview, isTrue);
      _marker(
        'PHASE:undo:SCALE_MILLI=${_scaleMilli(state.viewController.scale)}:'
        'BEFORE_RECT_8TH=${_coreRectEighths(current)}:UNDO_AVAILABLE=1',
      );
      await tester.ensureVisible(undoFinder);
      await tester.pumpAndSettle();
      await tester.tap(undoFinder);
      await _pumpUntil(
        tester,
        () => !state.reviewBusy && state.headRevisionId != headBefore,
        timeout: const Duration(seconds: 120),
        reason: 'the undo did not write a verified revision',
      );
      expect(state.durabilityStatus, isA<core.SavedDurabilityStatus>());
      final core.Rect actual = _storedRect(state);
      expect(
        actual,
        preClampRect,
        reason: 'undo must restore the exact previous rectangle bit for bit',
      );
      expect(
        actual.right,
        lessThan(pageBox.right),
        reason: 'the restored rectangle is no longer at the page edge',
      );
      _marker(
        'UNDO:RESTORED_EXACT=1:RECT_8TH=${_coreRectEighths(actual)}:'
        'FIELD=$_targetFieldId',
      );
      await _setShotView(tester, state, _storedViewRect(state), fitScale * 2.5);
      await _waitForDriver('undo');
    }

    // -------------------------------------------------------------------
    // E. A pointer cancel discards the preview and commits nothing.
    // -------------------------------------------------------------------
    {
      await _setScaleOnRect(
        tester,
        state,
        _storedViewRect(state),
        fitScale * 1.75,
      );
      final double scale = state.viewController.mappingFor(_pageIndex).scale;
      final core.Rect before = _storedRect(state);
      final String? headBefore = state.headRevisionId;
      final String contentBefore = core.canonicalJsonEncode(
        state.content!.toJson(),
      );
      final int savesBefore = _storeSpy.saves;
      final Rect r = _flutterRect(before);
      _marker(
        'PHASE:pointer-cancel:SCALE_MILLI=${_scaleMilli(scale)}:'
        'RECT_8TH=${_rectEighths(r)}',
      );
      final TestGesture gesture = await tester.startGesture(
        _screenPoint(tester, state, r.center),
      );
      await _moveByTotal(gesture, Offset(84 * scale, 40 * scale));
      await tester.pump();
      expect(
        state.geometryGestureActive,
        isTrue,
        reason: 'the cancel phase must have an active geometry preview',
      );
      expect(find.byKey(_geometryPreviewKey), findsWidgets);
      _expectNoMidGestureWrite(
        state,
        headBefore: headBefore,
        contentBefore: contentBefore,
        phase: 'pointer-cancel',
      );
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(
        state.geometryGestureActive,
        isFalse,
        reason: 'a pointer cancel must close the gesture',
      );
      expect(find.byKey(_geometryPreviewKey), findsNothing);
      expect(
        state.headRevisionId,
        headBefore,
        reason: 'a pointer cancel must not commit a revision',
      );
      expect(
        _storedRect(state),
        before,
        reason: 'a pointer cancel must discard the preview geometry',
      );
      expect(
        _storeSpy.saves,
        savesBefore,
        reason:
            'a pointer cancel must not call the real store saveRevision even '
            'once',
      );
      expect(state.reviewBusy, isFalse);
      _marker(
        'CANCEL:PAGE=$_pageIndex:FIELD=$_targetFieldId:'
        'RECT_8TH=${_coreRectEighths(_storedRect(state))}:COMMITS=0:'
        'SAVES=${_storeSpy.saves - savesBefore}',
      );
      await _setShotView(
        tester,
        state,
        _storedViewRect(state),
        fitScale * 1.75,
      );
      await _waitForDriver('cancel');
    }

    // -------------------------------------------------------------------
    // F. Two-finger gestures never edit geometry, but still pan and zoom.
    // -------------------------------------------------------------------
    {
      await _setScaleOnRect(
        tester,
        state,
        _storedViewRect(state),
        fitScale * 2,
      );
      final core.Rect before = _storedRect(state);
      final String? headBefore = state.headRevisionId;
      final String contentBefore = core.canonicalJsonEncode(
        state.content!.toJson(),
      );
      final int savesBefore = _storeSpy.saves;
      final Offset centerLocal = state.viewController
          .mappingFor(_pageIndex)
          .displayToView(_flutterRect(before).center);
      _marker(
        'PHASE:two-finger-pinch:'
        'SCALE_MILLI=${_scaleMilli(state.viewController.scale)}:'
        'RECT_8TH=${_coreRectEighths(before)}',
      );

      // The first pointer claims a geometry drag on the field body; the
      // second pointer must cancel the claim before anything is committed.
      final TestGesture first = await tester.startGesture(
        _viewPointToScreen(tester, centerLocal),
      );
      await _moveByTotal(first, const Offset(40, 0));
      await tester.pump();
      expect(
        state.geometryGestureActive,
        isTrue,
        reason: 'the first pointer claims a geometry drag on the body',
      );
      final TestGesture second = await tester.startGesture(
        _viewPointToScreen(tester, centerLocal + const Offset(0, 60)),
      );
      await tester.pump();
      expect(
        state.geometryGestureActive,
        isFalse,
        reason: 'a second pointer must cancel the geometry claim',
      );
      expect(
        find.byKey(_geometryPreviewKey),
        findsNothing,
        reason: 'the cancelled preview must be discarded',
      );
      final double scaleBeforePinch = state.viewController.scale;
      await first.moveBy(const Offset(-40, -40));
      await second.moveBy(const Offset(40, 40));
      await tester.pump();
      await tester.pump();
      expect(
        state.viewController.scale,
        greaterThan(scaleBeforePinch),
        reason: 'a two-finger pinch must still zoom the page',
      );
      _expectNoMidGestureWrite(
        state,
        headBefore: headBefore,
        contentBefore: contentBefore,
        phase: 'two-finger-pinch',
      );
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(
        state.headRevisionId,
        headBefore,
        reason: 'two-finger pinch must never commit geometry',
      );
      expect(_storedRect(state), before);
      expect(
        _storeSpy.saves,
        savesBefore,
        reason: 'a two-finger pinch must not call the real store saveRevision',
      );
      _marker(
        'TWO_FINGER:pinch:COMMITS=0:'
        'SAVES=${_storeSpy.saves - savesBefore}:'
        'SCALE_MILLI=${_scaleMilli(state.viewController.scale)}:'
        'RECT_8TH=${_coreRectEighths(_storedRect(state))}',
      );
      await _setShotView(
        tester,
        state,
        _storedViewRect(state),
        state.viewController.scale,
      );
      await _waitForDriver('two-finger-pinch');
    }

    {
      // The field stays centered at 2x so the first pointer lands on its
      // body; the pan below still has room on both axes inside the clamp.
      await _setScaleOnRect(
        tester,
        state,
        _storedViewRect(state),
        fitScale * 2,
      );
      final core.Rect before = _storedRect(state);
      final String? headBefore = state.headRevisionId;
      final String contentBefore = core.canonicalJsonEncode(
        state.content!.toJson(),
      );
      final int savesBefore = _storeSpy.saves;
      final Offset panBefore = state.viewController.pan;
      final Offset centerLocal = state.viewController
          .mappingFor(_pageIndex)
          .displayToView(_flutterRect(before).center);
      _marker(
        'PHASE:two-finger-pan:'
        'SCALE_MILLI=${_scaleMilli(state.viewController.scale)}:'
        'RECT_8TH=${_coreRectEighths(before)}',
      );
      final TestGesture first = await tester.startGesture(
        _viewPointToScreen(tester, centerLocal),
      );
      await _moveByTotal(first, const Offset(40, 0));
      await tester.pump();
      expect(state.geometryGestureActive, isTrue);
      final TestGesture second = await tester.startGesture(
        _viewPointToScreen(tester, centerLocal + const Offset(0, 60)),
      );
      await tester.pump();
      expect(
        state.geometryGestureActive,
        isFalse,
        reason: 'a second pointer must cancel the geometry claim',
      );
      // Both pointers move by the same delta: the span stays constant, so the
      // gesture is a pure two-finger pan.
      await first.moveBy(const Offset(-70, -50));
      await second.moveBy(const Offset(-70, -50));
      await tester.pump();
      await tester.pump();
      expect(
        state.viewController.pan,
        isNot(panBefore),
        reason: 'a two-finger drag must still pan the page',
      );
      _expectNoMidGestureWrite(
        state,
        headBefore: headBefore,
        contentBefore: contentBefore,
        phase: 'two-finger-pan',
      );
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(
        state.headRevisionId,
        headBefore,
        reason: 'two-finger pan must never commit geometry',
      );
      expect(_storedRect(state), before);
      expect(
        _storeSpy.saves,
        savesBefore,
        reason: 'a two-finger pan must not call the real store saveRevision',
      );
      _marker(
        'TWO_FINGER:pan:COMMITS=0:'
        'SAVES=${_storeSpy.saves - savesBefore}:PAN_CHANGED=1:'
        'RECT_8TH=${_coreRectEighths(_storedRect(state))}',
      );
      await _setShotView(
        tester,
        state,
        _storedViewRect(state),
        state.viewController.scale,
      );
      await _waitForDriver('two-finger-pan');
    }

    // -------------------------------------------------------------------
    // G. The 4 x 4 pt minimum committed size is enforced against the anchor.
    // -------------------------------------------------------------------
    {
      await _setScaleOnPoint(
        tester,
        state,
        _storedViewRect(state).bottomRight,
        fitScale * 1.5,
      );
      final double scale = state.viewController.mappingFor(_pageIndex).scale;
      final core.Rect before = _storedRect(state);
      final Rect r = _flutterRect(before);
      _marker(
        'PHASE:min-size:SCALE_MILLI=${_scaleMilli(scale)}:'
        'BEFORE_RECT_8TH=${_rectEighths(r)}:MIN_PT=$_contractMinSizePt',
      );
      await _dragToCommit(
        tester,
        state,
        phase: 'min-size',
        startLocal: state.viewController
            .mappingFor(_pageIndex)
            .displayToView(r.bottomRight),
        totalPx: const Offset(-2000, -2000),
      );
      final core.Rect actual = _storedRect(state);
      expect(
        actual.width,
        closeTo(_contractMinSizePt, 1e-9),
        reason: 'a resize past the anchor stops at the 4 pt minimum width',
      );
      expect(
        actual.height,
        closeTo(_contractMinSizePt, 1e-9),
        reason: 'a resize past the anchor stops at the 4 pt minimum height',
      );
      expect(
        actual.left,
        closeTo(before.left, 1e-9),
        reason: 'the top-left anchor stays fixed at the minimum size',
      );
      expect(
        actual.top,
        closeTo(before.top, 1e-9),
        reason: 'the top-left anchor stays fixed at the minimum size',
      );
      _marker(
        'MIN_SIZE:PT=$_contractMinSizePt:'
        'RECT_8TH=${_coreRectEighths(actual)}:ANCHOR_FIXED=1',
      );
      // The 4 x 4 pt field is shown at the 8x upper zoom bound so the clamped
      // minimum is actually visible in the screenshot.
      await _setShotView(
        tester,
        state,
        _flutterRect(actual),
        state.viewController.maxScale,
      );
      await _waitForDriver('min-size');
    }

    // -------------------------------------------------------------------
    // H. Durable read-back of the final geometry.
    // -------------------------------------------------------------------
    final LoadedDocument readBack = await editor.runtime.store.loadDocument(
      documentId,
    );
    final core.ConfirmedField storedField = readBack.content.fields.firstWhere(
      (core.ConfirmedField candidate) => candidate.id == _targetFieldId,
    );
    final core.Rect visible = _storedRect(state);
    expect(storedField.rect.left, closeTo(visible.left, 1e-3));
    expect(storedField.rect.top, closeTo(visible.top, 1e-3));
    expect(storedField.rect.width, closeTo(visible.width, 1e-3));
    expect(storedField.rect.height, closeTo(visible.height, 1e-3));
    expect(readBack.meta.latestRevisionId, state.headRevisionId);
    _marker(
      'READBACK:OK:PAGE=$_pageIndex:FIELD=$_targetFieldId:'
      'RECT_8TH=${_coreRectEighths(storedField.rect)}:HEAD_MATCH=1',
    );

    // -------------------------------------------------------------------
    // I. Negative control: a real double commit must fail the assertion.
    //
    // The counting facade is armed to forward the same save request to the real
    // store a second time, so this gesture produces two real store
    // `saveRevision` calls (the real store's expectedHead guard decides whether
    // the duplicate call is accepted; the outcome is recorded). The
    // exactly-one-revision assertion must then throw. It is the last action
    // before teardown, and the driver's app-data cleanup removes the store
    // afterwards.
    // -------------------------------------------------------------------
    {
      await _setScaleOnRect(tester, state, _storedViewRect(state), fitScale);
      final int savesBefore = _storeSpy.saves;
      final String? headBefore = state.headRevisionId;
      final Rect r = _storedViewRect(state);
      final int savesAtArm = _storeSpy.saves;
      _storeSpy.duplicateNextSave = true;
      expect(_storeSpy.duplicateNextSave, isTrue);
      final TestGesture gesture = await tester.startGesture(
        _screenPoint(tester, state, r.center),
      );
      // The field is at its 4 x 4 pt minimum here, so the drag must grow it:
      // every point of a minimum-size field resolves to the topLeft handle, and
      // a rightward drag would shrink it straight into the minimum clamp and
      // commit nothing at all.
      await _moveByTotal(gesture, const Offset(-44, 0));
      await tester.pump();
      expect(
        state.geometryGestureActive,
        isTrue,
        reason:
            'the negative-control drag must be claimed by the geometry layer',
      );
      expect(
        _storeSpy.saves,
        savesAtArm,
        reason: 'the armed facade must not save while the pointer is held',
      );
      await gesture.up();
      await tester.pump();
      await _pumpUntil(
        tester,
        () => !state.reviewBusy && state.headRevisionId != headBefore,
        timeout: const Duration(seconds: 60),
        reason:
            'the negative-control gesture must land its own one revision '
            'before the injected duplicate is judged',
      );
      final int savesDelta = _storeSpy.saves - savesBefore;
      expect(
        savesDelta,
        2,
        reason:
            'the fault injection must have produced two real store '
            'saveRevision calls, observed $savesDelta',
      );
      expect(
        () => _expectSingleStoreRevision(
          savesBefore: savesBefore,
          savesAfter: _storeSpy.saves,
          savesDuringHold: 0,
          phase: 'negative-control-double-commit',
        ),
        throwsA(isA<TestFailure>()),
        reason:
            'the exactly-one-revision assertion must fail on two real store '
            'revisions',
      );
      expect(
        _emittedMarkers.where(
          (String entry) => entry.startsWith('COMMIT:negative-control'),
        ),
        isEmpty,
        reason:
            'the journey must not emit a passing commit marker for the '
            'double-commit control',
      );
      _marker(
        'NEGATIVE_CONTROL:DOUBLE_COMMIT=1:SAVES_DELTA=$savesDelta:'
        'ASSERTION_FAILED=1:SECOND_SAVE=${_storeSpy.duplicateOutcome}',
      );
    }
  });
}
