// T061 EMULATOR recognition integration test (US2 Independent Test).
//
// Run only on the exclusively allocated Android emulator through the host
// driver, which stages the fixture and owns the screenshot handshake:
//
//   tools/android/t061_drive_recognition.sh
//
// The test covers the production recognition path, not a substitute:
//   * the committed synthetic `sf-001.pdf` is read from the device-side staging
//     directory the driver prepared;
//   * page 2's `/MediaBox` is damaged deterministically with the same
//     same-length-space algorithm as `android_import_test.dart`;
//   * the debug-only `de.feldexa/test.import` channel arms that app-private
//     scratch file and the production `main()` import action is tapped, so the
//     real encrypted staging, preflight, and verified commit run;
//   * the production `EditorScreen`/`EditorRuntime` performs the first analysis
//     through the real pdfrx raster port and the bundled ML Kit OCR port;
//   * the protected store is read back through `AndroidStoreClient`.
//
// No system picker is driven (T046/T149 own the picker); no production file is
// changed and no fake adapter, renderer, detector, or OCR result is injected.
//
// Per-page failure isolation: page index 1 is import-unreadable (`IMP-006`,
// `unsupportedStructure`) and stays failed; page index 0 is analyzed, reaches
// `complete`, and keeps real suggestions. Navigation to page 2 and back must
// not change either result.
//
// Privacy: the damaged fixture is synthetic. Markers carry phase names,
// content-free ids, page indexes, types, 1/8 pt display geometry, confidence,
// and counts only; no label, OCR text, title, path, URI, or document content is
// printed. The test uses local files and platform channels only; it opens no
// network socket.

import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/page_strip.dart';
import 'package:feldexa_app/features/editor/page_view.dart' as viewer;
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_app/main.dart' as app;
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// App-readable staging directory prepared by the host driver.
const String _fixtureRoot = '/data/local/tmp/t061-fixtures';
const String _fixtureId = 'sf-001';
const String _fixtureSha256 =
    '22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038';
const int _fixtureSizeBytes = 5956;

const String _displayName = 't061-recognition.pdf';

const ValueKey<String> _startScreenKey = ValueKey<String>('start-screen');
const ValueKey<String> _editorScreenKey = ValueKey<String>('editor-screen');
const ValueKey<String> _importActionKey = ValueKey<String>('import-action');
const ValueKey<String> _importFailureKey = ValueKey<String>('import-failure');
const ValueKey<String> _warningKey = ValueKey<String>('imp006-warning');

const MethodChannel _testHooks = MethodChannel('de.feldexa/test.import');

/// Screenshot handshake files the host driver creates after every capture.
const Map<String, String> _screenshots = <String, String>{
  'page0-suggestions': 'T061_SCREENSHOT_PAGE0_SUGGESTIONS',
  'page1-failure': 'T061_SCREENSHOT_PAGE1_FAILURE',
  'navigation': 'T061_SCREENSHOT_NAVIGATION',
};

final List<String> _emittedMarkers = <String>[];

void _marker(String phase) {
  final String line = 'T061_$phase';
  _emittedMarkers.add(line);
  debugPrint(line);
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

/// Waits for the host driver to capture the named screenshot.
Future<void> _waitForDriver(String name) async {
  final String marker = _screenshots[name]!;
  _marker(marker.substring('T061_'.length));
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
      'Run tools/android/t061_drive_recognition.sh.',
    );
  }
  final Uint8List bytes = file.readAsBytesSync();
  expect(bytes.length, _fixtureSizeBytes);
  expect(crypto.sha256.convert(bytes).toString(), _fixtureSha256);
  return bytes;
}

String _sha256(List<int> bytes) => crypto.sha256.convert(bytes).toString();

/// Zero-based page-0 anchor suggestions observed on the documented emulator.
///
/// These are real first-run detector outputs for the committed synthetic
/// fixture, not ground-truth claims. Confidence values are asserted in bands
/// because the persisted value is two-decimal.
final class _AnchorSuggestion {
  const _AnchorSuggestion({
    required this.id,
    required this.type,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.minConfidence,
    required this.maxConfidence,
  });

  final String id;
  final core.FieldType type;
  final double left;
  final double top;
  final double width;
  final double height;
  final double minConfidence;
  final double maxConfidence;
}

const List<_AnchorSuggestion> _pageZeroAnchors = <_AnchorSuggestion>[
  _AnchorSuggestion(
    id: 's_p0_0010',
    type: core.FieldType.text,
    left: 190.125,
    top: 147.625,
    width: 299.875,
    height: 18,
    minConfidence: 0.55,
    maxConfidence: 0.65,
  ),
  _AnchorSuggestion(
    id: 's_p0_0012',
    type: core.FieldType.date,
    left: 190.125,
    top: 215.625,
    width: 299.875,
    height: 18,
    minConfidence: 0.65,
    maxConfidence: 0.75,
  ),
  _AnchorSuggestion(
    id: 's_p0_0020',
    type: core.FieldType.checkbox,
    left: 190.5,
    top: 502.5,
    width: 9.25,
    height: 9.375,
    minConfidence: 0.75,
    maxConfidence: 0.90,
  ),
];

/// A content-free fingerprint of the suggestion set used to prove isolation.
List<String> _suggestionFingerprint(Iterable<core.FieldSuggestion> input) {
  final List<core.FieldSuggestion> ordered =
      List<core.FieldSuggestion>.of(input)
        ..sort((core.FieldSuggestion a, core.FieldSuggestion b) {
          final int page = a.pageIndex.compareTo(b.pageIndex);
          return page != 0 ? page : a.id.compareTo(b.id);
        });
  return <String>[
    for (final core.FieldSuggestion suggestion in ordered)
      '${suggestion.id}|${suggestion.pageIndex}|'
          '${suggestion.proposedType.wireName}|'
          '${suggestion.rect.left},${suggestion.rect.top},'
          '${suggestion.rect.width},${suggestion.rect.height}|'
          '${suggestion.confidence.toStringAsFixed(2)}|'
          '${suggestion.resolution.wireName}',
  ];
}

void _expectNoContentInMarkers(core.RevisionContent content) {
  expect(_emittedMarkers, isNotEmpty);
  final List<String> labels = <String>[
    for (final core.FieldSuggestion suggestion in content.suggestions)
      if (suggestion.labelText case final String label when label.length >= 3)
        label,
  ];
  for (final String marker in _emittedMarkers) {
    expect(
      RegExp(r'^T061_[A-Za-z0-9_.,:=-]+$').hasMatch(marker),
      isTrue,
      reason: 'marker must be a content-free T061_ token',
    );
    for (final String forbidden in <String>[
      _fixtureRoot,
      _displayName,
      'sf-001',
      'Meldebescheinigung',
      'Musterstadt',
      ...labels,
    ]) {
      expect(
        marker.contains(forbidden),
        isFalse,
        reason: 'marker must not carry document content',
      );
    }
  }
}

/// Copies the reference algorithm from `android_import_test.dart`.
///
/// Replaces the second `/MediaBox [0 0 595.28 841.89]` occurrence in sf-001
/// with spaces of exactly the same length. All xref offsets stay valid, page 0
/// keeps its real geometry, and page 1 has no inheritable MediaBox.
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

Future<File> _writeScratchSource(Uint8List bytes) async {
  final Directory scratch = Directory.systemTemp;
  final File file = File(
    '${scratch.path}${Platform.pathSeparator}t061-damaged-'
    '${DateTime.now().microsecondsSinceEpoch}.pdf',
  );
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final Directory fixtureDirectory = Directory(_fixtureRoot);

  setUpAll(() async {
    if (!fixtureDirectory.existsSync()) {
      fail(
        'Fixture staging directory $_fixtureRoot is missing. '
        'Run tools/android/t061_drive_recognition.sh.',
      );
    }
    await pdfrxFlutterInitialize();
  });

  testWidgets('T061 damaged page 2 isolates the recognition failure', (
    WidgetTester tester,
  ) async {
    final Uint8List fixtureBytes = _loadFixture();
    final Uint8List damaged = _damageSecondPageMediaBox(fixtureBytes);
    expect(damaged.length, fixtureBytes.length);
    expect(damaged, isNot(orderedEquals(fixtureBytes)));
    expect(_sha256(damaged), isNot(_fixtureSha256));
    _marker('FIXTURE_LOADED:BYTES=$_fixtureSizeBytes:MATCH=1');

    final File scratchSource = await _writeScratchSource(damaged);
    addTearDown(() async {
      if (await scratchSource.exists()) {
        await scratchSource.delete();
      }
    });

    // Baseline before the production app starts. This client is disposed so
    // the app's own result listener owns `de.feldexa/results` during the run.
    final AndroidOperationClient baselineOperations = AndroidOperationClient();
    final AndroidStoreClient baselineStore = AndroidStoreClient(
      operations: baselineOperations,
    );
    final Set<String> documentIdsBefore = (await baselineStore.list(
      StoreKind.document,
    )).map((StoredMeta meta) => meta.id).toSet();
    await baselineOperations.dispose();

    String? createdDocumentId;
    bool hookArmed = false;

    try {
      await app.main();
      await _pumpUntil(
        tester,
        () => find.byKey(_startScreenKey).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 120),
        reason: 'the German start surface did not appear',
      );
      expect(find.byKey(_startScreenKey), findsOneWidget);
      _marker('START_READY');

      await _armFile(scratchSource);
      hookArmed = true;
      _marker('IMPORT_ARMED');

      await tester.tap(find.byKey(_importActionKey));
      await tester.pump();

      await _pumpUntil(
        tester,
        () =>
            find.byKey(_editorScreenKey).evaluate().isNotEmpty ||
            find.byKey(_importFailureKey).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 180),
        reason: 'no editor route or rejection after the armed import',
      );
      expect(
        find.byKey(_importFailureKey),
        findsNothing,
        reason: 'the partially damaged fixture must be accepted with IMP-006',
      );
      expect(find.byKey(_editorScreenKey), findsOneWidget);

      final EditorScreen editor = tester.widget<EditorScreen>(
        find.byType(EditorScreen),
      );
      createdDocumentId = editor.source.documentId;
      expect(editor.source.pageCount, 2);
      expect(editor.source.pageFailures, hasLength(1));
      final core.PageFailure importFailure = editor.source.pageFailures.single;
      expect(importFailure.pageIndex, 1);
      expect(importFailure.messageKey, 'IMP-006');
      expect(
        importFailure.category,
        core.PageFailureCategory.unsupportedStructure,
      );
      // Page 0 keeps its real geometry; page 1 keeps the documented 1x1
      // import placeholder and is never given fabricated original geometry.
      expect(editor.source.pages[0].displaySize.width, closeTo(595.28, 0.01));
      expect(editor.source.pages[0].displaySize.height, closeTo(841.89, 0.01));
      expect(editor.source.pages[0].mediaBox.width, closeTo(595.28, 0.01));
      expect(editor.source.pages[0].mediaBox.height, closeTo(841.89, 0.01));
      expect(editor.source.pages[1].mediaBox.width, 1);
      expect(editor.source.pages[1].mediaBox.height, 1);
      _marker('EDITOR_READY:PAGES=2:FAILURES=1');
      _marker(
        'IMPORT_ACCEPTED:PAGE1=IMP-006:unsupportedStructure:UNREADABLE=1',
      );
      _marker(
        'PAGE0_GEOMETRY:'
        '${editor.source.pages[0].displaySize.width.toStringAsFixed(2)}x'
        '${editor.source.pages[0].displaySize.height.toStringAsFixed(2)}',
      );

      // The strip is built from the imported source before analysis finishes
      // and must mark both pages. A portrait Pixel 7 is narrower than the
      // documented 600 dp breakpoint, so the compact presentation (indicator
      // plus previous/next controls) is the deterministic real-device surface.
      final AppLocalizations de = lookupAppLocalizations(const Locale('de'));
      expect(
        find.byKey(const ValueKey<String>('page-strip-indicator')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('page-strip-previous')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('page-strip-next')),
        findsOneWidget,
      );
      final Semantics pageOne = tester.widget<Semantics>(
        find.byKey(const ValueKey<String>('page-strip-indicator')),
      );
      expect(pageOne.properties.label, 'Seite 1 von 2');
      expect(
        tester
            .widget<Semantics>(
              find.byKey(const ValueKey<String>('page-strip-previous')),
            )
            .properties
            .enabled,
        isFalse,
        reason: 'page 1 has no previous page',
      );
      expect(
        tester
            .widget<Semantics>(
              find.byKey(const ValueKey<String>('page-strip-next')),
            )
            .properties
            .enabled,
        isTrue,
      );

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
        reason:
            'the readable page must produce a persisted analysis revision '
            '(observed ${state.analysisStateKey})',
      );
      _marker('ANALYSIS_READY');

      final core.RevisionContent analyzed = state.content!;
      expect(analyzed.pages, hasLength(2));
      expect(analyzed.pages[0].index, 0);
      expect(analyzed.pages[0].analysis, core.AnalysisState.complete);
      expect(analyzed.pages[0].failure, isNull);
      expect(analyzed.pages[0].unreadable, isFalse);
      expect(analyzed.pages[1].index, 1);
      expect(analyzed.pages[1].analysis, core.AnalysisState.failed);
      expect(analyzed.pages[1].unreadable, isTrue);
      final core.PageFailure? pageOneFailure = analyzed.pages[1].failure;
      expect(pageOneFailure, isNotNull);
      expect(pageOneFailure!.pageIndex, 1);
      expect(pageOneFailure.messageKey, 'IMP-006');
      expect(
        pageOneFailure.category,
        core.PageFailureCategory.unsupportedStructure,
      );
      _marker('PAGE0_ANALYSIS:complete');

      // The German IMP-006 warning is the canonical T044 surface and names the
      // failed second page; the message text is never used in a marker.
      expect(find.byKey(_warningKey), findsOneWidget);
      expect(find.text(de.imp006('2')), findsWidgets);

      final List<core.FieldSuggestion> suggestions = analyzed.suggestions
          .toList(growable: false);
      expect(
        suggestions,
        isNotEmpty,
        reason: 'the readable page must yield at least one suggestion',
      );
      expect(
        suggestions.every(
          (core.FieldSuggestion suggestion) => suggestion.pageIndex == 0,
        ),
        isTrue,
        reason: 'a failed page must contribute no suggestions',
      );
      expect(
        suggestions.every(
          (core.FieldSuggestion suggestion) =>
              suggestion.resolution == core.SuggestionResolution.unresolved,
        ),
        isTrue,
      );
      expect(
        suggestions.where(
          (core.FieldSuggestion suggestion) => suggestion.pageIndex == 1,
        ),
        isEmpty,
      );
      for (final core.FieldSuggestion suggestion in suggestions) {
        expect(suggestion.rect.width, greaterThan(0));
        expect(suggestion.rect.height, greaterThan(0));
        expect(suggestion.confidence, inInclusiveRange(0.0, 1.0));
        expect(
          (suggestion.confidence * 100).round() / 100,
          suggestion.confidence,
        );
      }
      _marker('PAGE0_SUGGESTIONS:${suggestions.length}');
      _marker(
        'PAGE1_ANALYSIS:failed:IMP-006:unsupportedStructure:SUGGESTIONS=0',
      );

      // Exact anchor assertions on real detector output: id, type, 1/8 pt
      // position, and confidence band.
      for (final _AnchorSuggestion anchor in _pageZeroAnchors) {
        final core.FieldSuggestion actual = suggestions.singleWhere(
          (core.FieldSuggestion suggestion) => suggestion.id == anchor.id,
          orElse: () => fail('expected page-0 suggestion ${anchor.id} missing'),
        );
        expect(actual.pageIndex, 0);
        expect(actual.proposedType, anchor.type, reason: '${anchor.id} type');
        expect(actual.rect.left, closeTo(anchor.left, 0.001));
        expect(actual.rect.top, closeTo(anchor.top, 0.001));
        expect(actual.rect.width, closeTo(anchor.width, 0.001));
        expect(actual.rect.height, closeTo(anchor.height, 0.001));
        expect(
          actual.confidence,
          inInclusiveRange(anchor.minConfidence, anchor.maxConfidence),
          reason: '${anchor.id} confidence band',
        );
      }

      // The visible B2 panel renders the page-0 queue and no page-1 row.
      final Finder panelFinder = find.byType(SuggestionReviewPanel);
      expect(panelFinder, findsOneWidget);
      final SuggestionReviewPanel panel = tester.widget<SuggestionReviewPanel>(
        panelFinder,
      );
      expect(panel.suggestions, isNotEmpty);
      expect(
        panel.suggestions.every(
          (core.FieldSuggestion suggestion) => suggestion.pageIndex == 0,
        ),
        isTrue,
      );
      expect(
        find.byKey(
          ValueKey<String>(
            '$suggestionRowKeyPrefix${_pageZeroAnchors.first.id}',
          ),
        ),
        findsOneWidget,
      );
      const String earlierPageOneSuggestion = 's_p1_0009';
      expect(
        find.byKey(
          const ValueKey<String>(
            '$suggestionRowKeyPrefix$earlierPageOneSuggestion',
          ),
        ),
        findsNothing,
        reason: 'a failed page must not render a suggestion row',
      );
      _marker('PANEL_PAGE0_ASSERTED');

      await _waitForDriver('page0-suggestions');

      // ---------------- Navigate to the failed page and back -------------
      final PageStrip strip = tester.widget<PageStrip>(find.byType(PageStrip));
      expect(strip.controller.pageCount, 2);
      expect(strip.controller.selectedPageIndex, 0);
      final viewer.PageView pageViewWidget = tester.widget<viewer.PageView>(
        find.byType(viewer.PageView),
      );
      expect(pageViewWidget.controller.pageCount, 2);

      final double pageTwoTopBefore = pageViewWidget.controller
          .mappingFor(1)
          .pageRectInViewport
          .top;
      await tester.tap(find.byKey(const ValueKey<String>('page-strip-next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(strip.controller.selectedPageIndex, 1);
      final Semantics selectedPageTwo = tester.widget<Semantics>(
        find.byKey(const ValueKey<String>('page-strip-indicator')),
      );
      expect(selectedPageTwo.properties.label, 'Seite 2 von 2');
      expect(selectedPageTwo.properties.hint, contains(de.statusUnreadable));
      // Page 2 is the documented 1x1 pt import placeholder, so the viewer
      // clamps its scroll at the content bottom instead of forcing the tiny
      // page top to 0. The failed page must nevertheless be brought into view.
      final double pageTwoTopAfter = pageViewWidget.controller
          .mappingFor(1)
          .pageRectInViewport
          .top;
      expect(
        pageTwoTopAfter,
        lessThan(pageTwoTopBefore),
        reason: 'selecting page 2 must scroll toward page 2',
      );
      expect(
        pageViewWidget.controller.mappingFor(0).pageRectInViewport.top,
        lessThan(0),
        reason: 'page 1 must have moved above the viewport',
      );
      expect(pageTwoTopAfter, greaterThanOrEqualTo(0));
      expect(
        pageTwoTopAfter,
        lessThan(pageViewWidget.controller.viewportSize!.height),
        reason: 'the failed page slot must be inside the viewport',
      );
      expect(find.byKey(const ValueKey<int>(1)), findsOneWidget);
      // The strip stays usable at the end of the document: the current-page
      // indicator and the previous control remain mounted, and next is
      // disabled rather than removed.
      expect(
        find.byKey(const ValueKey<String>('page-strip-indicator')),
        findsOneWidget,
      );
      final Semantics pageTwoNext = tester.widget<Semantics>(
        find.byKey(const ValueKey<String>('page-strip-next')),
      );
      expect(pageTwoNext.properties.enabled, isFalse);
      expect(
        tester
            .widget<Semantics>(
              find.byKey(const ValueKey<String>('page-strip-previous')),
            )
            .properties
            .enabled,
        isTrue,
      );
      _marker('PAGE1_VIEW_ASSERTED');

      await _waitForDriver('page1-failure');

      await tester.tap(
        find.byKey(const ValueKey<String>('page-strip-previous')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(strip.controller.selectedPageIndex, 0);
      final Semantics selectedPageOne = tester.widget<Semantics>(
        find.byKey(const ValueKey<String>('page-strip-indicator')),
      );
      expect(selectedPageOne.properties.label, 'Seite 1 von 2');
      expect(
        pageViewWidget.controller.mappingFor(0).pageRectInViewport.top,
        closeTo(0, 1),
        reason: 'selecting page 1 must scroll the viewer back to page 1',
      );
      expect(
        pageViewWidget.controller.mappingFor(1).pageRectInViewport.top,
        greaterThan(0),
      );
      _marker('NAVIGATION_BACK_ASSERTED');

      // Failure isolation: navigation changed no analysis page state and no
      // suggestion (id, type, position, confidence, resolution).
      final List<String> beforeNavigation = _suggestionFingerprint(suggestions);
      final List<String> afterNavigation = _suggestionFingerprint(
        state.content!.suggestions,
      );
      expect(afterNavigation, beforeNavigation);
      expect(
        state.content!.pages.map((core.Page page) => page.analysis),
        <core.AnalysisState>[
          core.AnalysisState.complete,
          core.AnalysisState.failed,
        ],
      );
      expect(state.content!.pages[1].failure?.messageKey, 'IMP-006');
      expect(panelFinder, findsOneWidget);
      expect(
        find.byKey(
          ValueKey<String>(
            '$suggestionRowKeyPrefix${_pageZeroAnchors.first.id}',
          ),
        ),
        findsOneWidget,
      );
      _marker('FAILURE_ISOLATION_ASSERTED');

      await _waitForDriver('navigation');

      // ---------------- Leave the editor and read the store back ----------
      final Finder backButton = find.byType(BackButton);
      expect(backButton, findsOneWidget, reason: 'editor back control');
      await tester.tap(backButton);
      await tester.pump();
      await _pumpUntil(
        tester,
        () => find.byKey(_startScreenKey).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60),
        reason: 'the editor did not return to the start surface',
      );
      _marker('BACK_TO_START');

      final AndroidOperationClient operations = AndroidOperationClient();
      final AndroidStoreClient store = AndroidStoreClient(
        operations: operations,
      );
      try {
        final LoadedDocument loaded = await store.loadDocument(
          createdDocumentId,
        );
        expect(loaded.content.pages, hasLength(2));
        expect(loaded.content.pages[0].analysis, core.AnalysisState.complete);
        expect(loaded.content.pages[0].failure, isNull);
        expect(loaded.content.pages[1].analysis, core.AnalysisState.failed);
        expect(loaded.content.pages[1].unreadable, isTrue);
        expect(loaded.content.pages[1].failure?.pageIndex, 1);
        expect(loaded.content.pages[1].failure?.messageKey, 'IMP-006');
        expect(
          loaded.content.pages[1].failure?.category,
          core.PageFailureCategory.unsupportedStructure,
        );
        expect(
          _suggestionFingerprint(loaded.content.suggestions),
          beforeNavigation,
          reason: 'the store must preserve the page-0 suggestion set exactly',
        );
        expect(
          loaded.content.suggestions.where(
            (core.FieldSuggestion suggestion) => suggestion.pageIndex == 1,
          ),
          isEmpty,
        );
        expect(_sha256(loaded.sourceBytes), _sha256(damaged));
        _marker(
          'STORE_VERIFIED:SUGGESTIONS=${loaded.content.suggestions.length}:'
          'PAGE1=IMP-006',
        );
      } finally {
        await operations.dispose();
      }

      _expectNoContentInMarkers(state.content!);
      _marker('PRIVACY_MARKERS_ASSERTED');

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
      if (hookArmed) {
        await _clearHook();
      }
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
