// T149 EMULATOR US1 acceptance journey through the real Android system picker.
//
// Run only on the exclusively allocated Android emulator, together with the
// host-side driver that drives `DocumentsUI` (the test cannot tap another
// app's window):
//
//   tools/android/t149_drive_picker.sh
//
// The driver pushes the synthetic fixtures to the device, starts
// `flutter test integration_test/android_us1_journey_test.dart -d emulator-5554`
// in the background, waits for the `T149_PICKER_READY:<round>` logcat markers
// printed below, navigates DocumentsUI to Downloads, and taps the exact file
// row. This test never uses `de.feldexa/test.import`, `ImportTestHooks`, or any
// other debug seam: it starts the production `main()` composition and imports
// through `ACTION_OPEN_DOCUMENT` exactly as a user does.
//
// The journey:
//   Round 1 (accepted): start surface -> in-app import action -> real picker ->
//   `sf-001.pdf` (2 pages) -> editor route -> page strip page 1/2 -> German
//   a11y navigation text -> navigation to page 2 -> mounted PageView with two
//   pages and a real pdfrx-rendered first page. After both rounds the test
//   asserts exactly one new committed document, reads it back from the
//   protected store (2 pages, matching SHA-256, identical page-1 render
//   digest), and deletes it.
//   Round 2 (rejected): back to the start surface -> in-app import action ->
//   real picker -> `sf-protected.pdf` -> exact German `IMP-001` catalog text
//   and recovery, no editor route, and no additional document.
//
// Orientation: the host driver sets the emulator to landscape (`user_rotation`
// 1) so the 600 dp breakpoint selects the full page strip with the stable
// `page-strip-page-<n>` keys. That is real device UI, not a simulated
// viewport. The test asserts the effective logical width is at least 600 dp.
//
// Privacy: every fixture is synthetic; the test never logs a path, URI, title,
// document id, or page content. The markers carry only a stable phase name and
// round number.

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/page_view.dart' as viewer;
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_app/main.dart' as app;
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// App-readable staging directory prepared by the host driver.
///
/// The picker itself receives its own copy under the device Downloads
/// directory; the host records both SHA-256 values and asserts they match.
const String _fixtureRoot = '/data/local/tmp/t149-fixtures';

const String _acceptedFixture = 'sf-001';
const String _rejectedFixture = 'sf-protected';

const Map<String, String> _fixtureSha256 = <String, String>{
  'sf-001': '22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038',
  'sf-protected':
      '090290f77e77d904a11870951b06f0139c5abd1d263ad862b60a7b15ff69f221',
};

const Map<String, int> _fixtureSizeBytes = <String, int>{
  'sf-001': 5956,
  'sf-protected': 1513,
};

const ValueKey<String> _startScreenKey = ValueKey<String>('start-screen');
const ValueKey<String> _editorScreenKey = ValueKey<String>('editor-screen');
const ValueKey<String> _importActionKey = ValueKey<String>('import-action');
const ValueKey<String> _importFailureKey = ValueKey<String>('import-failure');

void _marker(String phase) {
  // Visible in `adb logcat -s flutter`; the host driver waits for these lines.
  debugPrint('T149_$phase');
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

Future<void> _openPicker(WidgetTester tester, int round) async {
  _marker('PICKER_READY:$round');
  await tester.tap(find.byKey(_importActionKey));
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final AppLocalizations de = lookupAppLocalizations(const Locale('de'));
  final Directory fixtureDirectory = Directory(_fixtureRoot);

  setUpAll(() async {
    await pdfrxFlutterInitialize();
  });

  Uint8List loadFixture(String id) {
    final File file = File(
      '${fixtureDirectory.path}${Platform.pathSeparator}$id.pdf',
    );
    if (!file.existsSync()) {
      fail(
        'Fixture staging directory $_fixtureRoot is missing $id.pdf. '
        'Run tools/android/t149_drive_picker.sh, which pushes the committed '
        'synthetic fixtures before starting this test.',
      );
    }
    final Uint8List bytes = file.readAsBytesSync();
    expect(
      _sha256(bytes),
      _fixtureSha256[id],
      reason: 'fixture $id.pdf must match the committed catalogue',
    );
    expect(bytes.length, _fixtureSizeBytes[id]);
    return bytes;
  }

  testWidgets('US1 real picker import, page navigation, and one rejection', (
    WidgetTester tester,
  ) async {
    final Uint8List acceptedBytes = loadFixture(_acceptedFixture);
    // The rejection fixture is only delivered through the picker; staging it
    // here also proves the host pushed the exact committed bytes.
    loadFixture(_rejectedFixture);

    // Baseline before the production app starts. This client is disposed so
    // the app's own result listener owns `de.feldexa/results` during the
    // journey; the test re-attaches only after both rounds.
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

      // The start surface is the production composition: no injected runtime,
      // no fake renderer, and the catalog import action.
      expect(find.byKey(_startScreenKey), findsOneWidget);
      expect(find.text(de.importAction), findsOneWidget);
      expect(find.text(de.startTitle), findsOneWidget);

      // Landscape (host driver) selects the full strip instead of the compact
      // indicator; assert the real logical width crossed the contract boundary.
      final double logicalWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(
        logicalWidth,
        greaterThanOrEqualTo(600),
        reason: 'the full page strip requires at least 600 logical pixels',
      );

      // ---------------- Round 1: accepted import -------------------------
      await _openPicker(tester, 1);
      await _pumpUntil(
        tester,
        () =>
            find.byKey(_editorScreenKey).evaluate().isNotEmpty ||
            find.byKey(_importFailureKey).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 150),
        reason: 'no editor route or rejection after the real picker returned',
      );
      expect(
        find.byKey(_importFailureKey),
        findsNothing,
        reason: 'the accepted fixture must not produce a rejection',
      );
      expect(find.byKey(_editorScreenKey), findsOneWidget);
      _marker('ROUND1_EDITOR');

      final EditorScreen editor = tester.widget<EditorScreen>(
        find.byType(EditorScreen),
      );
      createdDocumentId = editor.source.documentId;
      expect(editor.source.pageCount, 2);
      expect(editor.source.pageFailures, isEmpty);

      // The page strip shows both pages in the full horizontal presentation.
      expect(
        find.byKey(const ValueKey<String>('page-strip-page-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('page-strip-page-2')),
        findsOneWidget,
      );

      Semantics pageOne = tester.widget<Semantics>(
        find.byKey(const ValueKey<String>('page-strip-page-1')),
      );
      final Semantics pageTwo = tester.widget<Semantics>(
        find.byKey(const ValueKey<String>('page-strip-page-2')),
      );
      // Exact German navigation text from `a11yPageNavigation`.
      expect(pageOne.properties.label, de.a11yPageNavigation(1, 2));
      expect(pageOne.properties.label, 'Seite 1 von 2');
      expect(pageTwo.properties.label, de.a11yPageNavigation(2, 2));
      expect(pageTwo.properties.label, 'Seite 2 von 2');
      expect(pageOne.properties.selected, isTrue);
      expect(pageTwo.properties.selected, isFalse);

      // The viewer is mounted and its controller reports the document pages.
      final viewer.PageView pageView = tester.widget<viewer.PageView>(
        find.byType(viewer.PageView),
      );
      expect(pageView.controller.pageCount, 2);
      expect(pageView.sourceId, editor.source.sourceId);

      // The first page is genuinely displayable: the production pdfrx renderer
      // must have produced an image (RawImage inside the page 1 slot).
      await _pumpUntil(
        tester,
        () => find
            .descendant(
              of: find.byKey(const ValueKey<int>(0)),
              matching: find.byType(RawImage),
            )
            .evaluate()
            .isNotEmpty,
        timeout: const Duration(seconds: 60),
        reason: 'pdfrx did not render the first page',
      );
      final RawImage renderedPage = tester.widget<RawImage>(
        find
            .descendant(
              of: find.byKey(const ValueKey<int>(0)),
              matching: find.byType(RawImage),
            )
            .first,
      );
      expect(renderedPage.image, isNotNull);

      // Page navigation: tapping page 2 in the strip selects it and scrolls
      // the viewer to the top of page 2.
      await tester.tap(find.byKey(const ValueKey<String>('page-strip-page-2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final Semantics selectedPage = tester.widget<Semantics>(
        find.byKey(const ValueKey<String>('page-strip-page-2')),
      );
      expect(selectedPage.properties.selected, isTrue);
      pageOne = tester.widget<Semantics>(
        find.byKey(const ValueKey<String>('page-strip-page-1')),
      );
      expect(pageOne.properties.selected, isFalse);
      expect(
        pageView.controller.mappingFor(1).pageRectInViewport.top,
        closeTo(0, 1),
        reason: 'tapping page 2 must scroll the viewer to page 2',
      );
      expect(
        pageView.controller.mappingFor(0).pageRectInViewport.top,
        lessThan(0),
      );
      _marker('ROUND1_OK');

      // ---------------- Round 2: rejected import -------------------------
      // The app bar's Material back control returns to the start surface.
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
      expect(find.byKey(_editorScreenKey), findsNothing);

      await _openPicker(tester, 2);
      await _pumpUntil(
        tester,
        () =>
            find.byKey(_importFailureKey).evaluate().isNotEmpty ||
            find.byKey(_editorScreenKey).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 150),
        reason: 'no rejection after the second real picker selection',
      );

      // No editor navigation; the start surface remains with the exact German
      // catalog text and recovery for a password-protected PDF.
      expect(find.byKey(_editorScreenKey), findsNothing);
      expect(find.byKey(_startScreenKey), findsOneWidget);
      expect(find.byKey(_importFailureKey), findsOneWidget);
      expect(find.text(de.imp001), findsOneWidget);
      expect(find.text(de.imp001Recovery), findsOneWidget);

      // No machine text, code, path, URI, or source file name is visible.
      for (final Text text in tester.widgetList<Text>(find.byType(Text))) {
        final String? value = text.data;
        if (value == null) {
          continue;
        }
        expect(value, isNot(contains('IMP-')));
        expect(value, isNot(contains('content://')));
        expect(value, isNot(contains('file://')));
        expect(value, isNot(contains('.pdf')));
        expect(value, isNot(contains('sf-protected')));
      }
      _marker('ROUND2_REJECTED');

      // ---------------- Store verification and cleanup -------------------
      // Both rounds are done, so the test may now own the result stream again.
      final AndroidOperationClient operations = AndroidOperationClient();
      final AndroidStoreClient store = AndroidStoreClient(
        operations: operations,
      );
      try {
        final List<StoredMeta> documents = await store.list(StoreKind.document);
        final Set<String> documentIdsAfter = documents
            .map((StoredMeta meta) => meta.id)
            .toSet();
        // Exactly one new document across both rounds: round 1 added one and
        // round 2 added none.
        expect(documentIdsAfter.length, documentIdsBefore.length + 1);
        expect(documentIdsAfter.difference(documentIdsBefore), hasLength(1));
        expect(documentIdsBefore.difference(documentIdsAfter), isEmpty);
        _marker(
          'STORE_COUNTS:before=${documentIdsBefore.length},'
          'after=${documentIdsAfter.length}',
        );
        final StoredMeta created = documents.singleWhere(
          (StoredMeta meta) => meta.id == createdDocumentId,
        );

        final LoadedDocument loaded = await store.loadDocument(created.id);
        expect(loaded.content.pages.length, 2);
        expect(_sha256(loaded.sourceBytes), _fixtureSha256[_acceptedFixture]);
        expect(loaded.sourceBytes, orderedEquals(acceptedBytes));

        // Page-1 pixel fidelity: the decrypted protected copy must render
        // identically to the pushed fixture through the production PDFium.
        final PageGeometry firstPage = loaded.content.pages.first.geometry;
        final String pageOneDigest = await _expectPageRenderEquals(
          acceptedBytes,
          loaded.sourceBytes,
          firstPage.displaySize.width,
          firstPage.displaySize.height,
        );
        _marker('RENDER_DIGEST:$pageOneDigest');
        _marker('STORE_VERIFIED');

        await store.delete(
          StoreKind.document,
          created.id,
          DeleteConfirmation(title: created.title, acknowledged: true),
        );
        createdDocumentId = null;
        final Set<String> documentIdsCleaned = (await store.list(
          StoreKind.document,
        )).map((StoredMeta meta) => meta.id).toSet();
        expect(documentIdsCleaned, documentIdsBefore);
        _marker('CLEANUP_DONE');
      } finally {
        await operations.dispose();
      }
    } finally {
      // If an assertion failed after a document was created, still remove it.
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

Future<String> _expectPageRenderEquals(
  Uint8List original,
  Uint8List stored,
  double width,
  double height,
) async {
  final PdfDocument originalDocument = await PdfDocument.openData(
    original,
    sourceName: 't149-original',
  );
  final PdfDocument storedDocument = await PdfDocument.openData(
    stored,
    sourceName: 't149-stored',
  );
  try {
    expect(originalDocument.pages.length, 2);
    expect(storedDocument.pages.length, 2);
    final String originalDigest = await _renderDigest(
      originalDocument,
      0,
      width,
      height,
    );
    final String storedDigest = await _renderDigest(
      storedDocument,
      0,
      width,
      height,
    );
    expect(
      storedDigest,
      originalDigest,
      reason: 'protected copy page 1 must render identically',
    );
    return storedDigest;
  } finally {
    await originalDocument.dispose();
    await storedDocument.dispose();
  }
}

Future<String> _renderDigest(
  PdfDocument document,
  int pageIndex,
  double width,
  double height,
) async {
  final PdfImage? image = await document.pages[pageIndex].render(
    fullWidth: width,
    fullHeight: height,
  );
  if (image == null) {
    fail('PDFium could not render page ${pageIndex + 1}');
  }
  try {
    expect(image.width, closeTo(width, 1));
    expect(image.height, closeTo(height, 1));
    return _sha256(image.pixels);
  } finally {
    image.dispose();
  }
}

String _sha256(List<int> bytes) => crypto.sha256.convert(bytes).toString();
