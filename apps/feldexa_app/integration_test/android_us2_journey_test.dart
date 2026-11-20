// Issue #217 Phase B2 EMULATOR US2 acceptance journey.
//
// Run only on the exclusively allocated Android emulator with the host driver
// that drives DocumentsUI (the Flutter test cannot tap another app's window):
//
//   tools/android/us2_drive_journey.sh
//
// The driver pushes the committed synthetic `sf-001.pdf` fixture to the device,
// starts `flutter test integration_test/android_us2_journey_test.dart -d
// emulator-5554`, waits for `US2_PICKER_READY`, navigates DocumentsUI to
// Downloads, and taps the exact file row. The production `main()` composition
// is used: no injected runtime, no fake renderer, and no import or analysis
// seam.
//
// The journey:
//   * real system picker -> editor -> first analysis -> visible review panel;
//   * observation of the real suggestion set (counts/types/pages/positions/
//     confidence and conflict graph);
//   * confirm one suggestion and reject another, then undo each action and
//     assert reversibility through the real store;
//   * final confirm + reject, a protected-store `loadDocument` read-back that
//     proves suggestions, resolutions, and machine provenance persisted, and
//     cleanup back to the pre-run document set.
//
// Privacy: the fixture is synthetic. Markers carry phase names, stable ids,
// types, page indexes, display points, confidence, and counts only; no label,
// OCR text, path, URI, title, or document content is printed.

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_app/main.dart' as app;
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart' hide Page, Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:pdfrx/pdfrx.dart';

/// App-readable staging directory prepared by the host driver.
const String _fixtureRoot = '/data/local/tmp/us2-fixtures';
const String _fixtureId = 'sf-001';
const String _fixtureSha256 =
    '22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038';
const int _fixtureSizeBytes = 5956;

const ValueKey<String> _startScreenKey = ValueKey<String>('start-screen');
const ValueKey<String> _editorScreenKey = ValueKey<String>('editor-screen');
const ValueKey<String> _importActionKey = ValueKey<String>('import-action');
const ValueKey<String> _importFailureKey = ValueKey<String>('import-failure');

/// One observed detector suggestion that this journey asserts exactly.
///
/// These are the real first-run outputs of the committed `sf-001` fixture on
/// the documented emulator, not ground-truth field claims. The confidence
/// ranges are bands around the deterministic two-decimal detector output.
final class _ExpectedSuggestion {
  const _ExpectedSuggestion({
    required this.id,
    required this.pageIndex,
    required this.type,
    required this.rect,
    required this.minConfidence,
    required this.maxConfidence,
  });

  final String id;
  final int pageIndex;
  final FieldType type;
  final Rect rect;
  final double minConfidence;
  final double maxConfidence;
}

final List<_ExpectedSuggestion> _expectedSuggestions = <_ExpectedSuggestion>[
  _ExpectedSuggestion(
    id: 's_p0_0010',
    pageIndex: 0,
    type: FieldType.text,
    rect: Rect.fromLTWH(190.125, 147.625, 299.875, 18),
    minConfidence: 0.55,
    maxConfidence: 0.65,
  ),
  _ExpectedSuggestion(
    id: 's_p0_0012',
    pageIndex: 0,
    type: FieldType.date,
    rect: Rect.fromLTWH(190.125, 215.625, 299.875, 18),
    minConfidence: 0.65,
    maxConfidence: 0.75,
  ),
  _ExpectedSuggestion(
    id: 's_p0_0015',
    pageIndex: 0,
    type: FieldType.text,
    rect: Rect.fromLTWH(190.125, 353.875, 299.875, 18),
    minConfidence: 0.75,
    maxConfidence: 0.90,
  ),
  _ExpectedSuggestion(
    id: 's_p0_0020',
    pageIndex: 0,
    type: FieldType.checkbox,
    rect: Rect.fromLTWH(190.5, 502.5, 9.25, 9.375),
    minConfidence: 0.75,
    maxConfidence: 0.90,
  ),
  _ExpectedSuggestion(
    id: 's_p0_0022',
    pageIndex: 0,
    type: FieldType.checkbox,
    rect: Rect.fromLTWH(410.375, 502.5, 9.375, 9.375),
    minConfidence: 0.75,
    maxConfidence: 0.90,
  ),
  _ExpectedSuggestion(
    id: 's_p1_0009',
    pageIndex: 1,
    type: FieldType.multiline,
    rect: Rect.fromLTWH(190.5, 152.25, 348, 75.625),
    minConfidence: 0.75,
    maxConfidence: 0.90,
  ),
  _ExpectedSuggestion(
    id: 's_p1_0024',
    pageIndex: 1,
    type: FieldType.number,
    rect: Rect.fromLTWH(427, 314.625, 104, 18),
    minConfidence: 0.85,
    maxConfidence: 0.98,
  ),
  _ExpectedSuggestion(
    id: 's_p1_0041',
    pageIndex: 1,
    type: FieldType.checkbox,
    rect: Rect.fromLTWH(190.5, 480.25, 9.25, 9.75),
    minConfidence: 0.75,
    maxConfidence: 0.90,
  ),
  _ExpectedSuggestion(
    id: 's_p1_0047',
    pageIndex: 1,
    type: FieldType.date,
    rect: Rect.fromLTWH(190.125, 553.625, 299.875, 18),
    minConfidence: 0.85,
    maxConfidence: 0.98,
  ),
];

final NumberFormat _pointFormat = NumberFormat('#,##0.###', 'de');

void _marker(String phase) {
  // Visible in the host `flutter test -d` log and in `adb logcat -s flutter`.
  debugPrint('US2_$phase');
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  String? reason,
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await tester.pump();
    if (condition()) {
      return;
    }
  }
  fail(reason ?? 'timed out after ${timeout.inSeconds}s');
}

/// Waits for the host driver to capture the named screenshot.
///
/// The driver creates `ack-<phase>` in the app-readable staging directory after
/// `adb exec-out screencap -p` completes. This keeps each screenshot at the
/// intended journey state instead of racing the test.
Future<void> _waitForDriver(String phase) async {
  final File ack = File('$_fixtureRoot${Platform.pathSeparator}ack-$phase');
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 90));
  while (!ack.existsSync()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('host driver did not acknowledge screenshot phase $phase');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

Uint8List _loadFixture() {
  final File file = File(
    '$_fixtureRoot${Platform.pathSeparator}$_fixtureId.pdf',
  );
  if (!file.existsSync()) {
    fail(
      'Fixture staging directory $_fixtureRoot is missing $_fixtureId.pdf. '
      'Run tools/android/us2_drive_journey.sh, which pushes the committed '
      'synthetic fixture before starting this test.',
    );
  }
  final Uint8List bytes = file.readAsBytesSync();
  expect(bytes.length, _fixtureSizeBytes);
  expect(crypto.sha256.convert(bytes).toString(), _fixtureSha256);
  return bytes;
}

List<FieldSuggestion> _ordered(Iterable<FieldSuggestion> input) {
  final List<FieldSuggestion> ordered = List<FieldSuggestion>.of(input)
    ..sort((FieldSuggestion a, FieldSuggestion b) {
      int result = a.pageIndex.compareTo(b.pageIndex);
      if (result != 0) {
        return result;
      }
      result = _roundEighth(a.rect.top).compareTo(_roundEighth(b.rect.top));
      if (result != 0) {
        return result;
      }
      result = _roundEighth(a.rect.left).compareTo(_roundEighth(b.rect.left));
      if (result != 0) {
        return result;
      }
      result = a.proposedType.index.compareTo(b.proposedType.index);
      if (result != 0) {
        return result;
      }
      return a.id.compareTo(b.id);
    });
  return ordered;
}

double _roundEighth(double value) => (value * 8).round() / 8;

String _pointText(double value) => _pointFormat.format(_roundEighth(value));

String _rectText(Rect rect) {
  String point(double value) {
    final double rounded = _roundEighth(value);
    final bool integral = rounded == rounded.roundToDouble();
    return integral
        ? rounded.toInt().toString()
        : rounded.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
  }

  return '${point(rect.left)},${point(rect.top)},'
      '${point(rect.width)},${point(rect.height)}';
}

String _typeName(AppLocalizations l10n, FieldType type) {
  return switch (type) {
    FieldType.text => l10n.suggestionTypeText,
    FieldType.number => l10n.suggestionTypeNumber,
    FieldType.date => l10n.suggestionTypeDate,
    FieldType.checkbox => l10n.suggestionTypeCheckbox,
    FieldType.multiline => l10n.suggestionTypeMultiline,
    FieldType.signature => l10n.suggestionTypeSignature,
  };
}

Future<void> _ensurePanelRowVisible(
  WidgetTester tester,
  String suggestionId,
) async {
  // The panel is a non-lazy Column inside one SingleChildScrollView, so every
  // row context exists even when it is outside the visible 320 dp window.
  // `ensureVisible` scrolls in either direction to the exact row context.
  final Finder row = find.byKey(
    ValueKey<String>('$suggestionRowKeyPrefix$suggestionId'),
  );
  expect(row, findsOneWidget);
  await tester.ensureVisible(row);
  await tester.pump();
}

Future<void> _tapPanelAction(WidgetTester tester, String actionKey) async {
  final String id = actionKey.startsWith(confirmSuggestionKeyPrefix)
      ? actionKey.substring(confirmSuggestionKeyPrefix.length)
      : actionKey.substring(rejectSuggestionKeyPrefix.length);
  await _ensurePanelRowVisible(tester, id);
  final Finder button = find.byKey(ValueKey<String>(actionKey));
  expect(button, findsOneWidget);
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
}

bool _resolutionIs(
  EditorScreenState state,
  String suggestionId,
  SuggestionResolution resolution,
) {
  final RevisionContent? content = state.content;
  if (content == null) {
    return false;
  }
  return content.suggestions.any(
    (FieldSuggestion suggestion) =>
        suggestion.id == suggestionId && suggestion.resolution == resolution,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final Directory fixtureDirectory = Directory(_fixtureRoot);

  setUpAll(() async {
    if (!fixtureDirectory.existsSync()) {
      fail(
        'Fixture staging directory $_fixtureRoot is missing. '
        'Run tools/android/us2_drive_journey.sh.',
      );
    }
    await pdfrxFlutterInitialize();
  });

  testWidgets('US2 real picker import, analysis, review, and persistence', (
    WidgetTester tester,
  ) async {
    final Uint8List fixtureBytes = _loadFixture();
    expect(fixtureBytes, isNotEmpty);

    // Baseline before the production app starts. This client is disposed so
    // the app's own result listener owns `de.feldexa/results` during the
    // journey; the test re-attaches only after the editor closes.
    final AndroidOperationClient baselineOperations = AndroidOperationClient();
    final AndroidStoreClient baselineStore = AndroidStoreClient(
      operations: baselineOperations,
    );
    final Set<String> documentIdsBefore = (await baselineStore.list(
      StoreKind.document,
    )).map((StoredMeta meta) => meta.id).toSet();
    await baselineOperations.dispose();

    String? createdDocumentId;

    try {
      await app.main();
      await _pumpUntil(
        tester,
        () => find.byKey(_startScreenKey).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60),
        reason: 'the German start surface did not appear',
      );
      expect(find.byKey(_startScreenKey), findsOneWidget);

      _marker('PICKER_READY');
      await tester.tap(find.byKey(_importActionKey));
      await tester.pump();

      await _pumpUntil(
        tester,
        () =>
            find.byKey(_editorScreenKey).evaluate().isNotEmpty ||
            find.byKey(_importFailureKey).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 180),
        reason: 'no editor route or rejection after the real picker returned',
      );
      expect(
        find.byKey(_importFailureKey),
        findsNothing,
        reason: 'the accepted fixture must not produce a rejection',
      );
      expect(find.byKey(_editorScreenKey), findsOneWidget);

      final EditorScreen editor = tester.widget<EditorScreen>(
        find.byType(EditorScreen),
      );
      createdDocumentId = editor.source.documentId;
      expect(editor.source.pageCount, 2);
      expect(editor.source.pageFailures, isEmpty);
      _marker('EDITOR_READY');
      _marker('SCREENSHOT_EDITOR_READY');
      await _waitForDriver('editor-ready');

      final EditorScreenState state = tester.state<EditorScreenState>(
        find.byType(EditorScreen),
      );
      await _pumpUntil(
        tester,
        () => state.analysisStateKey != null,
        timeout: const Duration(seconds: 900),
        reason: 'first analysis did not reach a terminal state',
      );
      expect(
        state.analysisStateKey,
        editorAnalysisReadyKey,
        reason: 'the first analysis must complete and save its revision',
      );
      await _pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey<String>(suggestionPanelKey))
            .evaluate()
            .isNotEmpty,
        timeout: const Duration(seconds: 30),
        reason: 'the B2 suggestion panel did not appear after analysis-ready',
      );
      expect(
        find.byKey(const ValueKey<String>(suggestionPanelKey)),
        findsOneWidget,
      );
      expect(find.byKey(_editorScreenKey), findsOneWidget);

      final RevisionContent analyzed = state.content!;
      final List<FieldSuggestion> suggestions = _ordered(analyzed.suggestions);
      expect(
        suggestions,
        isNotEmpty,
        reason: 'the detector must yield at least one suggestion for sf-001',
      );
      _marker('SUGGESTIONS_VISIBLE');
      _marker('SUGGESTION_COUNT:${suggestions.length}');
      _marker(
        'PAGE_COUNTS:'
        '${suggestions.where((FieldSuggestion s) => s.pageIndex == 0).length},'
        '${suggestions.where((FieldSuggestion s) => s.pageIndex == 1).length}',
      );
      _marker(
        'UNSURE_COUNT:'
        '${suggestions.where((FieldSuggestion s) => s.confidence < 0.50).length}',
      );
      _marker(
        'CONFLICT_COUNT:'
        '${suggestions.where((FieldSuggestion s) => s.conflictsWith.isNotEmpty).length}',
      );
      _marker('PAGE_FAILURES:${editor.source.pageFailures.length}');
      for (final FieldSuggestion suggestion in suggestions) {
        _marker(
          'SUGGESTION:${suggestion.id}:'
          'p${suggestion.pageIndex}:'
          '${suggestion.proposedType.wireName}:'
          '${_rectText(suggestion.rect)}:'
          '${suggestion.confidence.toStringAsFixed(2)}:'
          '${suggestion.conflictsWith.join('+')}',
        );
      }

      final AppLocalizations de = lookupAppLocalizations(const Locale('de'));
      final List<FieldSuggestion> unsure = suggestions
          .where((FieldSuggestion suggestion) => suggestion.confidence < 0.50)
          .toList(growable: false);
      final List<FieldSuggestion> nullLabel = suggestions
          .where((FieldSuggestion suggestion) => suggestion.labelText == null)
          .toList(growable: false);
      final double minConfidence = suggestions
          .map((FieldSuggestion suggestion) => suggestion.confidence)
          .reduce((double a, double b) => a < b ? a : b);
      _marker('LABEL_NULL_COUNT:${nullLabel.length}');
      _marker('MIN_CONFIDENCE:${minConfidence.toStringAsFixed(2)}');

      _marker('SCREENSHOT_SUGGESTIONS_VISIBLE');
      await _waitForDriver('suggestions-visible');

      // Observed sf-001 detector output assertions. Both pages must be
      // represented, every suggestion must be a canonical unresolved review
      // item, and the representative expected suggestions below must match the
      // exact 1/8 pt position/type and a confidence band.
      expect(suggestions.map((FieldSuggestion s) => s.pageIndex).toSet(), <int>{
        0,
        1,
      });
      expect(
        suggestions.every(
          (FieldSuggestion s) =>
              s.resolution == SuggestionResolution.unresolved,
        ),
        isTrue,
      );
      for (final _ExpectedSuggestion expected in _expectedSuggestions) {
        final FieldSuggestion actual = suggestions.singleWhere(
          (FieldSuggestion suggestion) => suggestion.id == expected.id,
          orElse: () =>
              fail('expected detector suggestion ${expected.id} is missing'),
        );
        expect(
          actual.pageIndex,
          expected.pageIndex,
          reason: '${expected.id} page',
        );
        expect(
          actual.proposedType,
          expected.type,
          reason: '${expected.id} type',
        );
        expect(actual.rect, expected.rect, reason: '${expected.id} rect');
        expect(
          actual.confidence,
          inInclusiveRange(expected.minConfidence, expected.maxConfidence),
          reason: '${expected.id} confidence band',
        );
      }
      _marker('EXPECTED_FIELDS_ASSERTED:${_expectedSuggestions.length}');

      // Label fallback is visible for at least one real geometry-only
      // candidate. The first unresolved candidate with no label also drives
      // the confirm action, so the confirmed-field fallback label is exercised.
      expect(
        nullLabel,
        isNotEmpty,
        reason: 'sf-001 must include geometry-only candidates without labels',
      );
      await _ensurePanelRowVisible(tester, nullLabel.first.id);
      expect(find.text(de.suggestionRowFallback), findsWidgets);
      _marker('FALLBACK_ROW_ASSERTED');

      // Overlapping candidates: both sides of a symmetric conflict are in the
      // set and the panel renders the conflict marker.
      final List<FieldSuggestion> conflicting = suggestions
          .where(
            (FieldSuggestion suggestion) => suggestion.conflictsWith.isNotEmpty,
          )
          .toList(growable: false);
      expect(
        conflicting,
        isNotEmpty,
        reason: 'sf-001 must yield overlapping candidates',
      );
      final FieldSuggestion conflictA = conflicting.first;
      final FieldSuggestion conflictB = suggestions.singleWhere(
        (FieldSuggestion suggestion) =>
            suggestion.id == conflictA.conflictsWith.first,
      );
      expect(conflictB.conflictsWith, contains(conflictA.id));
      await _ensurePanelRowVisible(tester, conflictA.id);
      expect(
        find.byKey(ValueKey<String>('$suggestionRowKeyPrefix${conflictA.id}')),
        findsOneWidget,
      );
      expect(find.text(de.suggestionConflict), findsWidgets);
      _marker('CONFLICT_MARKERS_ASSERTED');

      if (unsure.isNotEmpty) {
        await _ensurePanelRowVisible(tester, unsure.first.id);
        expect(find.text(de.suggestionUncertain), findsWidgets);
        _marker('UNSURE_MARKER_ASSERTED');
      } else {
        // sf-001's deterministic detector output is above 0.50 on this
        // emulator. The host panel test proves the below-0.50 marker; the
        // report records this emulator sub-check as unverified.
        _marker('UNSURE_MARKER_UNVERIFIED');
      }

      final List<FieldSuggestion> unresolved = suggestions
          .where(
            (FieldSuggestion suggestion) =>
                suggestion.resolution == SuggestionResolution.unresolved,
          )
          .toList(growable: false);
      expect(unresolved.length, greaterThanOrEqualTo(2));
      final FieldSuggestion confirmTarget = unresolved.firstWhere(
        (FieldSuggestion suggestion) => suggestion.labelText == null,
        orElse: () => unresolved.first,
      );
      expect(
        confirmTarget.labelText,
        isNull,
        reason: 'the confirm action must exercise the German fallback label',
      );
      final FieldSuggestion rejectTarget = unresolved.firstWhere(
        (FieldSuggestion suggestion) => suggestion.id != confirmTarget.id,
      );
      _marker(
        'CONFIRM_TARGET:${confirmTarget.id}:'
        'p${confirmTarget.pageIndex}:${confirmTarget.proposedType.wireName}',
      );
      _marker(
        'REJECT_TARGET:${rejectTarget.id}:'
        'p${rejectTarget.pageIndex}:${rejectTarget.proposedType.wireName}',
      );

      // The visible row must carry the German fallback label, type name,
      // one-based page, exact 1/8 pt position, and integer confidence.
      await _ensurePanelRowVisible(tester, confirmTarget.id);
      expect(find.text(de.suggestionRowFallback), findsWidgets);
      expect(
        find.text(_typeName(de, confirmTarget.proposedType)),
        findsWidgets,
      );
      expect(
        find.text(de.suggestionPage(confirmTarget.pageIndex + 1)),
        findsWidgets,
      );
      expect(
        find.text(
          de.suggestionPosition(
            _pointText(confirmTarget.rect.left),
            _pointText(confirmTarget.rect.top),
          ),
        ),
        findsWidgets,
      );
      expect(
        find.text(
          de.suggestionConfidence((confirmTarget.confidence * 100).round()),
        ),
        findsWidgets,
      );
      _marker('PANEL_ROW_METADATA_ASSERTED');

      // ---------------- Confirm and reject -------------------------------
      final int fieldsBefore = analyzed.fields.length;
      await _tapPanelAction(
        tester,
        '$confirmSuggestionKeyPrefix${confirmTarget.id}',
      );
      await _pumpUntil(
        tester,
        () =>
            state.content!.fields.length == fieldsBefore + 1 &&
            _resolutionIs(
              state,
              confirmTarget.id,
              SuggestionResolution.confirmed,
            ),
        timeout: const Duration(seconds: 60),
        reason: 'the confirmed suggestion was not saved',
      );
      final ConfirmedField confirmedField = state.content!.fields.singleWhere(
        (ConfirmedField field) => field.sourceSuggestionId == confirmTarget.id,
      );
      expect(confirmedField.provenance, Provenance.machine);
      expect(confirmedField.pageIndex, confirmTarget.pageIndex);
      expect(confirmedField.rect, confirmTarget.rect);
      expect(confirmedField.type, confirmTarget.proposedType);
      expect(confirmedField.suggestionConfidence, confirmTarget.confidence);
      expect(confirmedField.label, 'Feld ${fieldsBefore + 1}');
      expect(confirmedField.createdAt.isUtc, isTrue);
      expect(confirmedField.updatedAt, confirmedField.createdAt);
      _marker('CONFIRMED_SAVED');
      _marker('FALLBACK_LABEL_CONFIRMED');
      expect(
        find.text(de.suggestionFieldCount(fieldsBefore + 1)),
        findsOneWidget,
      );

      await _tapPanelAction(
        tester,
        '$rejectSuggestionKeyPrefix${rejectTarget.id}',
      );
      await _pumpUntil(
        tester,
        () =>
            _resolutionIs(
              state,
              rejectTarget.id,
              SuggestionResolution.rejected,
            ) &&
            find
                .byKey(const ValueKey<String>(undoReviewKey))
                .evaluate()
                .isNotEmpty,
        timeout: const Duration(seconds: 60),
        reason: 'the rejected suggestion was not saved',
      );
      expect(
        state.content!.fields.any(
          (ConfirmedField field) => field.sourceSuggestionId == rejectTarget.id,
        ),
        isFalse,
      );
      _marker('REJECTED_SAVED');

      // ---------------- Undo the reject and the confirm ------------------
      await tester.tap(find.byKey(const ValueKey<String>(undoReviewKey)));
      await tester.pump();
      await _pumpUntil(
        tester,
        () => _resolutionIs(
          state,
          rejectTarget.id,
          SuggestionResolution.unresolved,
        ),
        timeout: const Duration(seconds: 60),
        reason: 'undoing the rejection was not saved',
      );
      expect(state.content!.fields.length, fieldsBefore + 1);
      _marker('REJECTION_UNDONE');

      await tester.tap(find.byKey(const ValueKey<String>(undoReviewKey)));
      await tester.pump();
      await _pumpUntil(
        tester,
        () =>
            state.content!.fields.length == fieldsBefore &&
            _resolutionIs(
              state,
              confirmTarget.id,
              SuggestionResolution.unresolved,
            ),
        timeout: const Duration(seconds: 60),
        reason: 'undoing the untouched confirmation was not saved',
      );
      expect(
        state.content!.fields.any(
          (ConfirmedField field) =>
              field.sourceSuggestionId == confirmTarget.id,
        ),
        isFalse,
      );
      _marker('CONFIRMATION_UNDONE');

      // ---------------- Final persisted confirm + reject -----------------
      await _tapPanelAction(
        tester,
        '$confirmSuggestionKeyPrefix${confirmTarget.id}',
      );
      await _pumpUntil(
        tester,
        () =>
            state.content!.fields.length == fieldsBefore + 1 &&
            _resolutionIs(
              state,
              confirmTarget.id,
              SuggestionResolution.confirmed,
            ),
        timeout: const Duration(seconds: 60),
        reason: 'the final confirmation was not saved',
      );
      final ConfirmedField finalField = state.content!.fields.singleWhere(
        (ConfirmedField field) => field.sourceSuggestionId == confirmTarget.id,
      );

      await _tapPanelAction(
        tester,
        '$rejectSuggestionKeyPrefix${rejectTarget.id}',
      );
      await _pumpUntil(
        tester,
        () =>
            _resolutionIs(
              state,
              rejectTarget.id,
              SuggestionResolution.rejected,
            ) &&
            !state.reviewBusy &&
            state.canUndoReview,
        timeout: const Duration(seconds: 60),
        reason: 'the final rejection was not saved',
      );

      // The after-review capture must show the real final review state: the
      // undo control enabled after the confirm + reject pair, no save in
      // flight, and a row action still enabled. This is asserted before the
      // screenshot marker; a disabled undo would fail the journey.
      final Finder undoFinder = find.byKey(
        const ValueKey<String>(undoReviewKey),
      );
      expect(undoFinder, findsOneWidget);
      final TextButton undoButton = tester.widget<TextButton>(undoFinder);
      expect(
        undoButton.onPressed,
        isNotNull,
        reason: 'undo must be enabled after the final confirm + reject pair',
      );
      expect(state.reviewBusy, isFalse);
      expect(state.canUndoReview, isTrue);
      expect(
        find.byKey(const ValueKey<String>('suggestion-review-busy')),
        findsNothing,
      );

      final FieldSuggestion stillUnresolved = suggestions.firstWhere(
        (FieldSuggestion suggestion) =>
            suggestion.id != confirmTarget.id &&
            suggestion.id != rejectTarget.id &&
            suggestion.resolution == SuggestionResolution.unresolved,
        orElse: () => confirmTarget,
      );
      await _ensurePanelRowVisible(tester, stillUnresolved.id);
      final Finder rowConfirmFinder = find.byKey(
        ValueKey<String>('$confirmSuggestionKeyPrefix${stillUnresolved.id}'),
      );
      expect(rowConfirmFinder, findsOneWidget);
      final TextButton rowConfirmButton = tester.widget<TextButton>(
        rowConfirmFinder,
      );
      expect(
        rowConfirmButton.onPressed,
        isNotNull,
        reason: 'row actions must stay enabled when undo is enabled',
      );
      _marker('UNDO_ENABLED_ASSERTED');
      await tester.pump();

      _marker('AFTER_REVIEW');
      _marker('SCREENSHOT_AFTER_REVIEW');
      await _waitForDriver('after-review');

      // ---------------- Protected-store read-back ------------------------
      final Finder backButton = find.byType(BackButton);
      expect(backButton, findsOneWidget, reason: 'editor back control');
      await tester.tap(backButton);
      await tester.pump();
      await _pumpUntil(
        tester,
        () => find.byKey(_startScreenKey).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
        reason: 'the editor did not return to the start surface',
      );

      final AndroidOperationClient operations = AndroidOperationClient();
      final AndroidStoreClient store = AndroidStoreClient(
        operations: operations,
      );
      try {
        final LoadedDocument loaded = await store.loadDocument(
          createdDocumentId,
        );
        expect(loaded.content.pages.length, 2);
        expect(loaded.content.suggestions.length, suggestions.length);
        expect(
          loaded.content.suggestions
              .map((FieldSuggestion suggestion) => suggestion.id)
              .toSet(),
          suggestions
              .map((FieldSuggestion suggestion) => suggestion.id)
              .toSet(),
          reason: 'saving must never duplicate or drop a suggestion',
        );
        expect(
          loaded.content.suggestions
              .firstWhere(
                (FieldSuggestion suggestion) =>
                    suggestion.id == confirmTarget.id,
              )
              .resolution,
          SuggestionResolution.confirmed,
        );
        expect(
          loaded.content.suggestions
              .firstWhere(
                (FieldSuggestion suggestion) =>
                    suggestion.id == rejectTarget.id,
              )
              .resolution,
          SuggestionResolution.rejected,
        );
        final ConfirmedField persistedField = loaded.content.fields.singleWhere(
          (ConfirmedField field) =>
              field.sourceSuggestionId == confirmTarget.id,
        );
        expect(persistedField.provenance, Provenance.machine);
        expect(persistedField.id, finalField.id);
        expect(persistedField.rect, confirmTarget.rect);
        expect(persistedField.type, confirmTarget.proposedType);
        expect(persistedField.suggestionConfidence, confirmTarget.confidence);
        expect(persistedField.label, finalField.label);
        expect(loaded.content.fields.length, fieldsBefore + 1);
        expect(
          loaded.content.pages.every(
            (Page page) => page.analysis == AnalysisState.complete,
          ),
          isTrue,
        );
        _marker('STORE_VERIFIED');
      } finally {
        await operations.dispose();
      }

      // ---------------- Cleanup ------------------------------------------
      final AndroidOperationClient cleanupOperations = AndroidOperationClient();
      try {
        final AndroidStoreClient cleanupStore = AndroidStoreClient(
          operations: cleanupOperations,
        );
        final StoredMeta created = (await cleanupStore.list(StoreKind.document))
            .singleWhere((StoredMeta meta) => meta.id == createdDocumentId);
        await cleanupStore.delete(
          StoreKind.document,
          created.id,
          DeleteConfirmation(title: created.title, acknowledged: true),
        );
        createdDocumentId = null;
        final Set<String> documentIdsCleaned = (await cleanupStore.list(
          StoreKind.document,
        )).map((StoredMeta meta) => meta.id).toSet();
        expect(documentIdsCleaned, documentIdsBefore);
      } finally {
        await cleanupOperations.dispose();
      }
      _marker('CLEANUP_DONE');
    } finally {
      if (createdDocumentId != null) {
        final AndroidOperationClient cleanupOperations =
            AndroidOperationClient();
        try {
          final AndroidStoreClient cleanupStore = AndroidStoreClient(
            operations: cleanupOperations,
          );
          final List<StoredMeta> matches = (await cleanupStore.list(
            StoreKind.document,
          )).where((StoredMeta meta) => meta.id == createdDocumentId).toList();
          if (matches.isNotEmpty) {
            await cleanupStore.delete(
              StoreKind.document,
              matches.single.id,
              DeleteConfirmation(
                title: matches.single.title,
                acknowledged: true,
              ),
            );
          }
        } finally {
          await cleanupOperations.dispose();
        }
      }
    }
  });
}
