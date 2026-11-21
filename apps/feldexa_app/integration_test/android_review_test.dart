// T071 EMULATOR Android touch move/resize review test (issue #71).
//
// Evidence class: `EMULATOR` only. Run only through the host driver, which
// owns the fixture staging, the screenshot handshake, the device identity, and
// the APK/git evidence:
//
//   tools/android/t071_drive_touch.sh
//
// The test uses the production `main()` composition end to end: the debug-only
// `de.feldexa/test.import` hook arms the deterministic T061 damaged-page-2
// variant of the committed synthetic `sf-001.pdf` fixture, the production
// import action performs the real encrypted staging, preflight, and verified
// commit, the real analysis run produces suggestions, and one suggestion is
// confirmed through the production T066 command path. The selected confirmed
// field is then edited through the real composed T071B touch geometry layer on
// the emulator's touch surface. No fake adapter, renderer, detector, OCR
// result, store, route, or geometry implementation is injected, and no
// production behavior is bypassed or faked.
//
// What is proven here (`contracts/editor-interactions.md` §4, FR-023/FR-024,
// FR-094, SC-017):
//   * a body drag moves the selected confirmed field by the gesture-start
//     pointer delta divided by the current view scale exactly once, clamped to
//     the page, at 0.5×, 1×, 3×, and 8× fit-width — and one further 8× drag is
//     dragged far enough to hit the page clamp and stays the same size;
//   * all four corner handles and all four edge handles resize the field, the
//     diagonally opposite corner / opposite edge stays bit-for-bit fixed, the
//     aspect ratio stays free, and a handle is reachable from a touch point
//     outside the stored rectangle (the 24 dp hit region);
//   * the minimum committed size of 4 × 4 pt is enforced against the fixed
//     anchor;
//   * every gesture produces exactly one verified store commit, never one per
//     frame: the head revision and the visible content are asserted unchanged
//     on every pumped frame while the pointer is down, and exactly one new
//     revision lands after the pointer lifts;
//   * a pointer cancel discards the preview and commits nothing;
//   * undo restores the exact previous rectangle (bit-for-bit, not re-derived);
//   * two-finger pan and pinch never edit geometry, while the page still pans
//     and zooms.
//
// Markers are content-free: phase name, zero-based page index, the opaque
// generated field id, the view scale in milli-units, the field rectangle in
// 1/8 pt integer units, a frame/commit count, and the target scale. No label,
// OCR text, title, path, URI, or entered value is printed. Screenshots are
// captured by the host driver at the marked phases; each `_waitForDriver`
// deletes any stale acknowledgement file first, so a capture can never show a
// state from an earlier phase.

import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_app/features/editor/durability_status.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/page_view.dart';
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/features/start/stored_items.dart';
import 'package:feldexa_app/main.dart' as app;
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

/// Minimum committed field size and minimum handle hit region from
/// `contracts/editor-interactions.md` §4, restated here as the acceptance
/// values the gestures below prove behaviorally. The production constants live
/// in `feldexa_ui`'s `field_geometry.dart`; this test observes them through the
/// composed surface instead of importing that private library.
const double _contractMinSizePt = 4;
const double _contractHandleHitDp = 24;

/// Host-driver screenshot phases. The value is the marker the test emits; the
/// driver answers with an `ack-<name>` file, and only then does the test
/// continue.
const Map<String, String> _screenshots = <String, String>{
  'resize-corners': 'T071_SCREENSHOT_RESIZE_CORNERS',
  'resize-edges': 'T071_SCREENSHOT_RESIZE_EDGES',
  'move-0.5x': 'T071_SCREENSHOT_MOVE_0_5X',
  'move-1x': 'T071_SCREENSHOT_MOVE_1X',
  'move-3x': 'T071_SCREENSHOT_MOVE_3X',
  'move-8x': 'T071_SCREENSHOT_MOVE_8X',
  'move-clamped': 'T071_SCREENSHOT_MOVE_CLAMPED',
  'undo': 'T071_SCREENSHOT_UNDO',
  'cancel': 'T071_SCREENSHOT_CANCEL',
  'two-finger-pinch': 'T071_SCREENSHOT_TWO_FINGER_PINCH',
  'two-finger-pan': 'T071_SCREENSHOT_TWO_FINGER_PAN',
  'min-size': 'T071_SCREENSHOT_MIN_SIZE',
};

/// The opaque generated id of the confirmed field under test.
String _targetFieldId = '';

void _marker(String phase) {
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
/// Mirrors the T071A driver-side waiter: the editor turns a load/analysis/save
/// failure into the stable `analysis-failed` key, and the content-free page
/// diagnostics are recorded before the journey stops.
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

/// Waits for the host driver to capture the named screenshot.
///
/// A previous aborted run can leave `ack-*` files behind; waiting for a stale
/// file would let the test race ahead of the driver. The stale file is deleted
/// before the marker is emitted.
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
/// real analysis page this touch journey edits; the undamaged page 2 would
/// otherwise block the real run in the synchronous geometry detector.
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

Rect _storedViewRect(EditorScreenState state) {
  final core.Rect rect = _storedRect(state);
  return Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height);
}

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

/// Sets the view scale and centers [rect] in the viewport.
///
/// This is the documented caller entry point of the T042/T078 view transform
/// (`PageViewController.setView`), not a geometry shortcut: it changes only the
/// transient scale/pan and never touches the document. The emitted evidence
/// names the resulting scale so the screenshots and the gesture arithmetic
/// belong to the same transform.
Future<void> _setScaleOnRect(
  WidgetTester tester,
  EditorScreenState state,
  Rect displayRect,
  double scale,
) async {
  final Size? viewport = state.viewController.viewportSize;
  expect(viewport, isNotNull, reason: 'the page viewport must be laid out');
  final PageViewMapping mapping = state.viewController.mappingFor(_pageIndex);
  final Offset center = Offset(
    mapping.pageRect.left + displayRect.center.dx,
    mapping.pageRect.top + displayRect.center.dy,
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

/// A test precondition: [rect] must lie inside the page display box.
///
/// This guards the fixed gesture deltas below against a changed fixture. It is
/// a precondition, not an expectation: if it fails the journey stops instead of
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
  expect(_storedRect(state).width, greaterThan(0));
  expect(_storedRect(state).height, greaterThan(0));
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

/// Drives one claimed geometry gesture and waits for its single commit.
///
/// Asserts the contract's "never per frame" rule on every frame while the
/// pointer is down. Returns the stored rectangle the gesture started from; the
/// caller asserts the committed geometry.
Future<core.Rect> _dragToCommit(
  WidgetTester tester,
  EditorScreenState state, {
  required String phase,
  required Offset startLocal,
  required Offset totalPx,
  int heldFrames = 2,
}) async {
  final core.Rect previous = _storedRect(state);
  final double scale = state.viewController.mappingFor(_pageIndex).scale;
  final String? headBefore = state.headRevisionId;
  final String contentBefore = core.canonicalJsonEncode(
    state.content!.toJson(),
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
        '$phase: the drag on the selected field must be claimed by the '
        'touch geometry layer',
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
  for (int index = 0; index < heldFrames; index++) {
    await tester.pump();
    frames++;
  }
  _expectNoMidGestureWrite(
    state,
    headBefore: headBefore,
    contentBefore: contentBefore,
    phase: phase,
  );

  await gesture.up();
  await tester.pump();
  await _waitForSingleCommit(
    tester,
    state,
    headBefore: headBefore,
    phase: phase,
  );
  _marker(
    'COMMIT:$phase:PAGE=$_pageIndex:FIELD=$_targetFieldId:'
    'SCALE_MILLI=${_scaleMilli(scale)}:HELD_FRAMES=$frames:'
    'MID_WRITE=0:NEW_HEAD=1',
  );
  return previous;
}

/// Selects the confirmed field without opening the value sheet.
///
/// T077's `FieldSelectionController` is the transient selection source of
/// truth the composed overlay reads; tapping the field would additionally open
/// the value sheet, which is not part of the touch-geometry journey.
Future<void> _selectField(WidgetTester tester, EditorScreenState state) async {
  state.selection.select(_targetFieldId);
  await tester.pumpAndSettle();
  expect(state.selection.selectedId, _targetFieldId);
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

  testWidgets('move and resize the selected confirmed field on the touch '
      'surface', (WidgetTester tester) async {
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
      'ANALYSIS_READY:STATE=${state.analysisStateKey}:'
      'PAGES=${state.content!.pageCount}:'
      'SUGGESTIONS=${state.content!.suggestions.length}:'
      'CONFIRMED=${state.content!.fields.length}',
    );

    // Confirm the largest unresolved text suggestion on the edited page. The
    // largest one gives the touch journey a field with a real body, exactly as
    // a user would confirm the most obvious input line first.
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

    await _selectField(tester, state);
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

    // ---------------------------------------------------------------------
    // A. All four corner handles (screenshot: resize-corners).
    //
    // Each corner drag moves 60 pt on the horizontal axis and 10 pt on the
    // vertical axis, so the field grows wide while its height stays positive:
    // the stored rectangle starts 18 pt tall. The diagonal anchor is asserted
    // bit-for-bit, and the free aspect ratio is proved by the width and height
    // changing by different amounts.
    // ---------------------------------------------------------------------
    await _setScaleOnRect(tester, state, _storedViewRect(state), fitScale);
    _marker(
      'PHASE:resize-corners:SCALE_MILLI=${_scaleMilli(fitScale)}:'
      'HANDLES=topLeft,topRight,bottomLeft,bottomRight',
    );

    // topLeft: left and top move, right and bottom are the fixed anchor.
    {
      final core.Rect before = _storedRect(state);
      final Rect r = Rect.fromLTWH(
        before.left,
        before.top,
        before.width,
        before.height,
      );
      final double scale = state.viewController.mappingFor(_pageIndex).scale;
      const Offset delta = Offset(-60, -10);
      final Rect expected = Rect.fromLTRB(
        r.left + delta.dx,
        r.top + delta.dy,
        r.right,
        r.bottom,
      );
      _expectInsidePage(expected, pageBox, 'resize-corners-topLeft');
      await _dragToCommit(
        tester,
        state,
        phase: 'resize-corners-topLeft',
        startLocal: state.viewController
            .mappingFor(_pageIndex)
            .displayToView(r.topLeft),
        totalPx: delta * scale,
      );
      final core.Rect actual = _storedRect(state);
      expect(actual.right, r.right, reason: 'the right edge is the anchor');
      expect(actual.bottom, r.bottom, reason: 'the bottom edge is the anchor');
      _expectRectClose(
        actual,
        expected,
        reason: 'topLeft corner resize keeps the bottom-right anchor',
      );
      expect(
        actual.width - before.width,
        isNot(closeTo(actual.height - before.height, 1e-6)),
        reason: 'a corner drag keeps the aspect ratio free',
      );
    }

    // topRight: right and top move, left and bottom are the fixed anchor.
    {
      final core.Rect before = _storedRect(state);
      final Rect r = Rect.fromLTWH(
        before.left,
        before.top,
        before.width,
        before.height,
      );
      final double scale = state.viewController.mappingFor(_pageIndex).scale;
      const Offset delta = Offset(60, -10);
      final Rect expected = Rect.fromLTRB(
        r.left,
        r.top + delta.dy,
        r.right + delta.dx,
        r.bottom,
      );
      _expectInsidePage(expected, pageBox, 'resize-corners-topRight');
      await _dragToCommit(
        tester,
        state,
        phase: 'resize-corners-topRight',
        startLocal: state.viewController
            .mappingFor(_pageIndex)
            .displayToView(r.topRight),
        totalPx: delta * scale,
      );
      final core.Rect actual = _storedRect(state);
      expect(actual.left, r.left, reason: 'the left edge is the anchor');
      expect(actual.bottom, r.bottom, reason: 'the bottom edge is the anchor');
      _expectRectClose(
        actual,
        expected,
        reason: 'topRight corner resize keeps the bottom-left anchor',
      );
    }

    // bottomLeft: left and bottom move, right and top are the fixed anchor.
    {
      final core.Rect before = _storedRect(state);
      final Rect r = Rect.fromLTWH(
        before.left,
        before.top,
        before.width,
        before.height,
      );
      final double scale = state.viewController.mappingFor(_pageIndex).scale;
      const Offset delta = Offset(-60, 10);
      final Rect expected = Rect.fromLTRB(
        r.left + delta.dx,
        r.top,
        r.right,
        r.bottom + delta.dy,
      );
      _expectInsidePage(expected, pageBox, 'resize-corners-bottomLeft');
      await _dragToCommit(
        tester,
        state,
        phase: 'resize-corners-bottomLeft',
        startLocal: state.viewController
            .mappingFor(_pageIndex)
            .displayToView(r.bottomLeft),
        totalPx: delta * scale,
      );
      final core.Rect actual = _storedRect(state);
      expect(actual.right, r.right, reason: 'the right edge is the anchor');
      expect(actual.top, r.top, reason: 'the top edge is the anchor');
      _expectRectClose(
        actual,
        expected,
        reason: 'bottomLeft corner resize keeps the top-right anchor',
      );
    }

    // bottomRight: right and bottom move, left and top are the fixed anchor.
    {
      final core.Rect before = _storedRect(state);
      final Rect r = Rect.fromLTWH(
        before.left,
        before.top,
        before.width,
        before.height,
      );
      final double scale = state.viewController.mappingFor(_pageIndex).scale;
      const Offset delta = Offset(40, 60);
      final Rect expected = Rect.fromLTRB(
        r.left,
        r.top,
        r.right + delta.dx,
        r.bottom + delta.dy,
      );
      _expectInsidePage(expected, pageBox, 'resize-corners-bottomRight');
      await _dragToCommit(
        tester,
        state,
        phase: 'resize-corners-bottomRight',
        startLocal: state.viewController
            .mappingFor(_pageIndex)
            .displayToView(r.bottomRight),
        totalPx: delta * scale,
      );
      final core.Rect actual = _storedRect(state);
      expect(actual.left, r.left, reason: 'the left edge is the anchor');
      expect(actual.top, r.top, reason: 'the top edge is the anchor');
      _expectRectClose(
        actual,
        expected,
        reason: 'bottomRight corner resize keeps the top-left anchor',
      );
    }

    await _setScaleOnRect(tester, state, _storedViewRect(state), fitScale);
    _marker(
      'RESIZE_CORNERS_DONE:RECT_8TH=${_coreRectEighths(_storedRect(state))}',
    );
    await _waitForDriver('resize-corners');

    // ---------------------------------------------------------------------
    // B. All four edge handles (screenshot: resize-edges).
    //
    // The centerLeft drag deliberately starts 10 *display points* outside the
    // stored rectangle: the view scale keeps that inside the 24 dp handle hit
    // region, so a successful claim proves the hit region extends beyond the
    // stored geometry. Only the dragged edge may move.
    // ---------------------------------------------------------------------
    await _setScaleOnRect(
      tester,
      state,
      _storedViewRect(state),
      fitScale * 1.25,
    );
    _marker(
      'PHASE:resize-edges:SCALE_MILLI=${_scaleMilli(state.viewController.scale)}:'
      'HANDLES=topCenter,bottomCenter,centerLeft,centerRight:'
      'OUTSIDE_DP=10',
    );

    // topCenter: only the top edge moves.
    {
      final core.Rect before = _storedRect(state);
      final Rect r = Rect.fromLTWH(
        before.left,
        before.top,
        before.width,
        before.height,
      );
      final double scale = state.viewController.mappingFor(_pageIndex).scale;
      const Offset delta = Offset(0, -60);
      final Rect expected = Rect.fromLTRB(
        r.left,
        r.top + delta.dy,
        r.right,
        r.bottom,
      );
      _expectInsidePage(expected, pageBox, 'resize-edges-topCenter');
      await _dragToCommit(
        tester,
        state,
        phase: 'resize-edges-topCenter',
        startLocal: state.viewController
            .mappingFor(_pageIndex)
            .displayToView(Offset(r.center.dx, r.top)),
        totalPx: delta * scale,
      );
      final core.Rect actual = _storedRect(state);
      expect(actual.left, r.left);
      expect(actual.right, r.right);
      expect(actual.bottom, r.bottom);
      _expectRectClose(
        actual,
        expected,
        reason: 'topCenter edge resize keeps the bottom edge fixed',
      );
    }

    // bottomCenter: only the bottom edge moves.
    {
      final core.Rect before = _storedRect(state);
      final Rect r = Rect.fromLTWH(
        before.left,
        before.top,
        before.width,
        before.height,
      );
      final double scale = state.viewController.mappingFor(_pageIndex).scale;
      const Offset delta = Offset(0, 60);
      final Rect expected = Rect.fromLTRB(
        r.left,
        r.top,
        r.right,
        r.bottom + delta.dy,
      );
      _expectInsidePage(expected, pageBox, 'resize-edges-bottomCenter');
      await _dragToCommit(
        tester,
        state,
        phase: 'resize-edges-bottomCenter',
        startLocal: state.viewController
            .mappingFor(_pageIndex)
            .displayToView(Offset(r.center.dx, r.bottom)),
        totalPx: delta * scale,
      );
      final core.Rect actual = _storedRect(state);
      expect(actual.left, r.left);
      expect(actual.right, r.right);
      expect(actual.top, r.top);
      _expectRectClose(
        actual,
        expected,
        reason: 'bottomCenter edge resize keeps the top edge fixed',
      );
    }

    // centerLeft: only the left edge moves, and the touch point is outside the
    // stored rectangle but inside the 24 dp handle hit region.
    {
      final core.Rect before = _storedRect(state);
      final Rect r = Rect.fromLTWH(
        before.left,
        before.top,
        before.width,
        before.height,
      );
      final double scale = state.viewController.mappingFor(_pageIndex).scale;
      const Offset delta = Offset(-60, 0);
      const double outsidePt = 10;
      expect(
        outsidePt * scale,
        lessThan(_contractHandleHitDp / 2),
        reason: 'the outside touch point must stay inside the 24 dp region',
      );
      final Rect expected = Rect.fromLTRB(
        r.left + delta.dx,
        r.top,
        r.right,
        r.bottom,
      );
      _expectInsidePage(expected, pageBox, 'resize-edges-centerLeft');
      await _dragToCommit(
        tester,
        state,
        phase: 'resize-edges-centerLeft-outside-hit',
        startLocal: state.viewController
            .mappingFor(_pageIndex)
            .displayToView(Offset(r.left - outsidePt, r.center.dy)),
        totalPx: delta * scale,
      );
      final core.Rect actual = _storedRect(state);
      expect(actual.top, r.top);
      expect(actual.bottom, r.bottom);
      expect(actual.right, r.right);
      _expectRectClose(
        actual,
        expected,
        reason: 'centerLeft edge resize keeps the right edge fixed',
      );
      _marker(
        'HIT_REGION:EDGE=centerLeft:OUTSIDE_PT=$outsidePt:'
        'OUTSIDE_DP=${(outsidePt * scale).toStringAsFixed(2)}:'
        'MIN_BAND_DP=$_contractHandleHitDp:CLAIMED=1',
      );
    }

    // centerRight: only the right edge moves (the field narrows so the body
    // drag below has page room on both sides).
    {
      final core.Rect before = _storedRect(state);
      final Rect r = Rect.fromLTWH(
        before.left,
        before.top,
        before.width,
        before.height,
      );
      final double scale = state.viewController.mappingFor(_pageIndex).scale;
      const Offset delta = Offset(-200, 0);
      final Rect expected = Rect.fromLTRB(
        r.left,
        r.top,
        r.right + delta.dx,
        r.bottom,
      );
      _expectInsidePage(expected, pageBox, 'resize-edges-centerRight');
      await _dragToCommit(
        tester,
        state,
        phase: 'resize-edges-centerRight',
        startLocal: state.viewController
            .mappingFor(_pageIndex)
            .displayToView(Offset(r.right, r.center.dy)),
        totalPx: delta * scale,
      );
      final core.Rect actual = _storedRect(state);
      expect(actual.left, r.left);
      expect(actual.top, r.top);
      expect(actual.bottom, r.bottom);
      _expectRectClose(
        actual,
        expected,
        reason: 'centerRight edge resize keeps the left edge fixed',
      );
    }

    await _setScaleOnRect(
      tester,
      state,
      _storedViewRect(state),
      fitScale * 1.25,
    );
    _marker(
      'RESIZE_EDGES_DONE:RECT_8TH=${_coreRectEighths(_storedRect(state))}',
    );
    await _waitForDriver('resize-edges');

    // ---------------------------------------------------------------------
    // C. Body drag at 0.5×, 1×, 3×, and 8× fit width, plus one clamped drag.
    //
    // Each phase sets an exact view scale, then drags the field body with a
    // single pointer delta whose page-display value is `pointerDelta / scale`.
    // The stored size is unchanged and the expected rectangle is computed from
    // that one division, so a double division (or a per-frame accumulation)
    // cannot pass.
    // ---------------------------------------------------------------------
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
      final Rect r = Rect.fromLTWH(
        before.left,
        before.top,
        before.width,
        before.height,
      );
      final Offset displayDelta = Offset(
        totalPx.dx / scale,
        totalPx.dy / scale,
      );
      final Rect expected = r.shift(displayDelta);
      _expectInsidePage(expected, pageBox, phase);
      _marker(
        'PHASE:$phase:SCALE_MILLI=${_scaleMilli(scale)}:'
        'DELTA_8TH=${_eighths(displayDelta.dx)}:${_eighths(displayDelta.dy)}:'
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
      expect(
        actual.width,
        before.width,
        reason: '$phase: a body drag must not resize the field',
      );
      expect(actual.height, before.height, reason: '$phase: size preserved');
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
      await _setScaleOnRect(
        tester,
        state,
        _storedViewRect(state),
        fitScale * screenshotScaleFactor,
      );
      await _waitForDriver(screenshot);
    }

    // 0.5×: the pointer delta is dominated by the pan slop at this zoom, which
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

    // One more 8× drag far past the page edge: the rectangle keeps its size and
    // stops exactly at the page box, which is the §4 clamp.
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
            .displayToView(
              Offset(
                before.left + before.width / 2,
                before.top + before.height / 2,
              ),
            ),
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
      expect(actual.top, before.top, reason: 'no vertical movement requested');
      _marker(
        'MOVE:move-clamped:PAGE=$_pageIndex:FIELD=$_targetFieldId:'
        'SCALE_MILLI=${_scaleMilli(scale)}:'
        'RECT_8TH=${_coreRectEighths(actual)}:CLAMPED=1',
      );
      await _setScaleOnRect(
        tester,
        state,
        _storedViewRect(state),
        fitScale * 4.5,
      );
      await _waitForDriver('move-clamped');
    }

    // ---------------------------------------------------------------------
    // D. Undo restores the exact previous rectangle (screenshot: undo).
    //
    // The newest history entry is the clamped move, so undo must write back its
    // exact stored `before` snapshot rather than re-deriving a rectangle.
    // ---------------------------------------------------------------------
    {
      final core.Rect current = _storedRect(state);
      final core.Rect restoredExpected = preClampRect;
      expect(
        current,
        isNot(restoredExpected),
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
        restoredExpected,
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
      await _setScaleOnRect(
        tester,
        state,
        _storedViewRect(state),
        fitScale * 2.5,
      );
      await _waitForDriver('undo');
    }

    // ---------------------------------------------------------------------
    // E. A pointer cancel discards the preview and commits nothing.
    // ---------------------------------------------------------------------
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
      final Rect r = Rect.fromLTWH(
        before.left,
        before.top,
        before.width,
        before.height,
      );
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
      _marker(
        'CANCEL:PAGE=$_pageIndex:FIELD=$_targetFieldId:'
        'RECT_8TH=${_coreRectEighths(_storedRect(state))}:COMMITS=0',
      );
      await _waitForDriver('cancel');
    }

    // ---------------------------------------------------------------------
    // F. Two-finger gestures never edit geometry, but still pan and zoom.
    // ---------------------------------------------------------------------
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
      final Rect r = Rect.fromLTWH(
        before.left,
        before.top,
        before.width,
        before.height,
      );
      final Offset centerLocal = state.viewController
          .mappingFor(_pageIndex)
          .displayToView(r.center);
      _marker(
        'PHASE:two-finger-pinch:SCALE_MILLI=${_scaleMilli(state.viewController.scale)}:'
        'RECT_8TH=${_rectEighths(r)}',
      );

      // The first pointer claims a geometry drag on the field body; the second
      // pointer must cancel the claim before anything is committed.
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
        _viewPointToScreen(tester, centerLocal + const Offset(0, 70)),
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
      _marker(
        'TWO_FINGER:pinch:COMMITS=0:SCALE_MILLI=${_scaleMilli(state.viewController.scale)}:'
        'RECT_8TH=${_coreRectEighths(_storedRect(state))}',
      );
      await _waitForDriver('two-finger-pinch');
    }

    {
      // The field stays centered at 2× so the first pointer lands on its body;
      // the pan below then still has room on both axes inside the pan clamp.
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
      final Rect r = Rect.fromLTWH(
        before.left,
        before.top,
        before.width,
        before.height,
      );
      final Offset panBefore = state.viewController.pan;
      final Offset centerLocal = state.viewController
          .mappingFor(_pageIndex)
          .displayToView(r.center);
      _marker(
        'PHASE:two-finger-pan:SCALE_MILLI=${_scaleMilli(state.viewController.scale)}:'
        'RECT_8TH=${_rectEighths(r)}',
      );
      final TestGesture first = await tester.startGesture(
        _viewPointToScreen(tester, centerLocal),
      );
      await _moveByTotal(first, const Offset(40, 0));
      await tester.pump();
      expect(state.geometryGestureActive, isTrue);
      final TestGesture second = await tester.startGesture(
        _viewPointToScreen(tester, centerLocal + const Offset(0, 70)),
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
      _marker(
        'TWO_FINGER:pan:COMMITS=0:PAN_CHANGED=1:'
        'RECT_8TH=${_coreRectEighths(_storedRect(state))}',
      );
      await _waitForDriver('two-finger-pan');
    }

    // ---------------------------------------------------------------------
    // G. The 4 × 4 pt minimum committed size is enforced against the anchor.
    // ---------------------------------------------------------------------
    {
      await _setScaleOnRect(
        tester,
        state,
        _storedViewRect(state),
        fitScale * 1.5,
      );
      final double scale = state.viewController.mappingFor(_pageIndex).scale;
      final core.Rect before = _storedRect(state);
      final Rect r = Rect.fromLTWH(
        before.left,
        before.top,
        before.width,
        before.height,
      );
      const Offset totalPx = Offset(-2000, -2000);
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
        totalPx: totalPx,
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
      // The 4 × 4 pt field is shown at the 8× upper zoom bound so the clamped
      // minimum is actually visible in the screenshot.
      await _setScaleOnRect(
        tester,
        state,
        _storedViewRect(state),
        state.viewController.maxScale,
      );
      await _waitForDriver('min-size');
    }

    // ---------------------------------------------------------------------
    // H. Durable read-back of the final geometry.
    // ---------------------------------------------------------------------
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
      'RECT_8TH=${_coreRectEighths(storedField.rect)}:'
      'HEAD_MATCH=1',
    );
    _marker('CLEANUP_DONE');
  });
}
