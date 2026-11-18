// T046 Android import integration test (US1 Independent Test; SC-011).
//
// Run only on the exclusively allocated Android emulator:
//   flutter test integration_test/android_import_test.dart -d emulator-5554
//
// Device-side fixture delivery (once per boot; the fixtures are deliberately
// not Flutter assets, see assets/fixtures/catalog.json):
//   adb -s emulator-5554 shell mkdir -p /data/local/tmp/t046-fixtures
//   adb -s emulator-5554 push apps/feldexa_app/assets/fixtures/sf-001.pdf \
//       /data/local/tmp/t046-fixtures/sf-001.pdf
//   ... (all seven .pdf fixtures; chmod 644 the files and 755 the directory)
//
// This test covers the production path, not a substitute:
//   * the debug-only `de.feldexa/test.import` channel arms one source file
//     (MainActivity/ImportTestHooks; no handler exists in release builds);
//   * `AndroidImportClient` invokes the real `import.pickAndImport`;
//   * the native `ImportService` streams the source through the real encrypted
//     staging, preflight, and verified commit;
//   * `ImportFlow` applies the production German mapper and FR-009 gate;
//   * `AndroidStoreClient` reads the committed document back from the
//     protected store after the picked source file is gone.
//
// The test writes only synthetic fixture copies and deletes every document it
// creates. It never reads or deletes another document.

import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:feldexa_app/features/start/import_error_mapper.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// App-readable staging directory prepared with `adb push` (see file header).
const String _fixtureRoot = '/data/local/tmp/t046-fixtures';

const MethodChannel _testHooks = MethodChannel('de.feldexa/test.import');

/// Expected display geometry and rotation from `assets/fixtures/catalog.json`.
final class _PageExpectation {
  const _PageExpectation(
    this.displayWidthPt,
    this.displayHeightPt,
    this.rotation, {
    required this.mediaWidthPt,
    required this.mediaHeightPt,
  });

  final double displayWidthPt;
  final double displayHeightPt;
  final int rotation;
  final double mediaWidthPt;
  final double mediaHeightPt;
}

const Map<String, String> _fixtureSha256 = <String, String>{
  'sf-001': '22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038',
  'sf-002': 'bd8a0f7b231b0d5ba494b816350144999534c6dbffb151a14dc175f9fe802025',
  'sf-003': 'c19afcf6f86ed21a422426c5f01613bb9643b097d0facad3b3349f9873e4ea4f',
  'sf-004': '009c3babd2013e13fad9ef5977ec3d4c1d5842a52da0718e4ac06e3ff39d171e',
  'sf-protected':
      '090290f77e77d904a11870951b06f0139c5abd1d263ad862b60a7b15ff69f221',
  'sf-truncated':
      '8cebe5b446e8a62915e0c74642a6f1324df8fa055fce327022a33ea37aa8148c',
  'sf-not-a-pdf':
      '09241a5461877ece4bea0d84c80af7477b361d5798533313cd8bb611ec260dbb',
};

const Map<String, int> _fixtureSizeBytes = <String, int>{
  'sf-001': 5956,
  'sf-002': 10094,
  'sf-003': 6610,
  'sf-004': 3275,
  'sf-protected': 1513,
  'sf-truncated': 3573,
  'sf-not-a-pdf': 215,
};

const Map<String, List<_PageExpectation>> _fixturePages =
    <String, List<_PageExpectation>>{
      'sf-001': <_PageExpectation>[
        _PageExpectation(
          595.28,
          841.89,
          0,
          mediaWidthPt: 595.28,
          mediaHeightPt: 841.89,
        ),
        _PageExpectation(
          595.28,
          841.89,
          0,
          mediaWidthPt: 595.28,
          mediaHeightPt: 841.89,
        ),
      ],
      'sf-002': <_PageExpectation>[
        _PageExpectation(
          595.28,
          841.89,
          0,
          mediaWidthPt: 595.28,
          mediaHeightPt: 841.89,
        ),
        _PageExpectation(
          595.28,
          841.89,
          0,
          mediaWidthPt: 595.28,
          mediaHeightPt: 841.89,
        ),
        _PageExpectation(
          595.28,
          841.89,
          0,
          mediaWidthPt: 595.28,
          mediaHeightPt: 841.89,
        ),
        _PageExpectation(
          595.28,
          841.89,
          0,
          mediaWidthPt: 595.28,
          mediaHeightPt: 841.89,
        ),
        _PageExpectation(
          595.28,
          841.89,
          0,
          mediaWidthPt: 595.28,
          mediaHeightPt: 841.89,
        ),
      ],
      'sf-003': <_PageExpectation>[
        _PageExpectation(
          595.28,
          841.89,
          0,
          mediaWidthPt: 595.28,
          mediaHeightPt: 841.89,
        ),
        _PageExpectation(
          841.89,
          595.28,
          0,
          mediaWidthPt: 841.89,
          mediaHeightPt: 595.28,
        ),
        _PageExpectation(
          841.89,
          595.28,
          90,
          mediaWidthPt: 595.28,
          mediaHeightPt: 841.89,
        ),
        _PageExpectation(
          595.28,
          841.89,
          180,
          mediaWidthPt: 595.28,
          mediaHeightPt: 841.89,
        ),
        _PageExpectation(
          595.28,
          419.53,
          270,
          mediaWidthPt: 419.53,
          mediaHeightPt: 595.28,
        ),
      ],
      'sf-004': <_PageExpectation>[
        _PageExpectation(
          595.28,
          841.89,
          0,
          mediaWidthPt: 595.28,
          mediaHeightPt: 841.89,
        ),
      ],
    };

// Exact catalog §1 text (`contracts/error-catalog.de.md`).
const String _imp001 =
    'Diese PDF-Datei ist passwortgeschützt. Feldexa kann geschützte Dateien '
    'nicht öffnen, und Ihr Passwort wird weder abgefragt noch gespeichert.';
const String _imp001Recovery =
    'Bitte entfernen Sie den Schutz in einem PDF-Programm, das Sie dafür '
    'verwenden dürfen, und importieren Sie die Datei erneut.';
const String _imp002 =
    'Die Datei konnte nicht gelesen werden. Sie ist möglicherweise '
    'unvollständig oder beschädigt.';
const String _imp002Recovery =
    'Bitte öffnen Sie die Datei in einem PDF-Programm, speichern Sie sie '
    'erneut und versuchen Sie es noch einmal.';
const String _imp004 =
    'Diese Datei ist kein unterstütztes PDF. Feldexa kann nur PDF-Dokumente '
    'importieren.';
const String _imp004Recovery = 'Bitte wählen Sie eine PDF-Datei aus.';
const String _imp005 =
    'Die Datei konnte nicht gelesen werden. Die Ursache lässt sich nicht '
    'sicher feststellen.';
const String _imp005Recovery =
    'Bitte versuchen Sie es erneut. Wenn das Problem bleibt, öffnen und '
    'speichern Sie die Datei in einem PDF-Programm.';
const String _imp006 =
    'Einige Seiten konnten nicht gelesen werden: 2. Die übrigen Seiten sind '
    'nutzbar. Ein Export des vollständigen Dokuments ist dadurch '
    'beeinträchtigt.';
const String _imp006Recovery =
    'Sie können die betroffenen Seiten prüfen und das Dokument trotzdem '
    'weiterbearbeiten.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final AppLocalizations de = lookupAppLocalizations(const Locale('de'));
  final Directory fixtureDirectory = Directory(_fixtureRoot);
  final Directory scratch = Directory.systemTemp;

  setUpAll(() async {
    await pdfrxFlutterInitialize();
  });

  Map<String, Uint8List> loadFixtures() {
    if (!fixtureDirectory.existsSync()) {
      fail(
        'Fixture staging directory $_fixtureRoot is missing. Push the '
        'committed fixtures with the adb command in this test file header.',
      );
    }
    final Map<String, Uint8List> loaded = <String, Uint8List>{};
    for (final MapEntry<String, String> entry in _fixtureSha256.entries) {
      final File file = File(
        '${fixtureDirectory.path}${Platform.pathSeparator}${entry.key}.pdf',
      );
      if (!file.existsSync()) {
        fail('Missing fixture ${entry.key}.pdf in $_fixtureRoot.');
      }
      final Uint8List bytes = file.readAsBytesSync();
      expect(
        _sha256(bytes),
        entry.value,
        reason: 'fixture ${entry.key}.pdf must match catalog sha256',
      );
      expect(bytes.length, _fixtureSizeBytes[entry.key]);
      loaded[entry.key] = bytes;
    }
    return loaded;
  }

  Future<void> armFile(
    File source, {
    required String displayName,
    bool forceUnknownPreflight = false,
  }) async {
    final Map<Object?, Object?>? reply = await _testHooks
        .invokeMethod<Map<Object?, Object?>>('armFile', <String, Object?>{
          'path': source.path,
          'displayName': displayName,
          'forceUnknownPreflight': forceUnknownPreflight,
        });
    expect(reply?['armed'], isTrue);
  }

  Future<void> clearHook() async {
    await _testHooks.invokeMethod<void>('clear');
  }

  Future<File> writeScratchSource(String name, List<int> bytes) async {
    final File file = File(
      '${scratch.path}${Platform.pathSeparator}t046-$name-'
      '${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> expectSourceUnchanged(
    File source,
    Uint8List beforeBytes,
    DateTime beforeModified,
    String expectedSha256,
  ) async {
    final Uint8List afterBytes = await source.readAsBytes();
    final DateTime afterModified = (await source.stat()).modified;
    expect(_sha256(afterBytes), expectedSha256);
    expect(afterBytes, orderedEquals(beforeBytes));
    expect(
      afterModified,
      beforeModified,
      reason: 'import must not modify the picked source modification time',
    );
  }

  Future<_Attempt> runImport({
    required File source,
    required String displayName,
    required bool forceUnknownPreflight,
    required AndroidImportClient port,
    required AndroidStoreClient store,
  }) async {
    await armFile(
      source,
      displayName: displayName,
      forceUnknownPreflight: forceUnknownPreflight,
    );
    final Set<String> documentsBefore = (await store.list(StoreKind.document))
        .map((StoredMeta meta) => meta.id)
        .toSet();
    int createDocumentCalls = 0;
    final ImportFlow flow = ImportFlow(
      localizations: de,
      createDocument: (ImportedDocumentCandidate document) async {
        createDocumentCalls++;
      },
    );
    final ImportOutcome outcome = await flow.run(
      port: port,
      request: ImportRequest(),
    );
    final Set<String> documentsAfter = (await store.list(StoreKind.document))
        .map((StoredMeta meta) => meta.id)
        .toSet();
    return _Attempt(
      outcome: outcome,
      createDocumentCalls: createDocumentCalls,
      documentsBefore: documentsBefore,
      documentsAfter: documentsAfter,
    );
  }

  Future<void> expectCatalogRejection(
    ImportOutcome outcome, {
    required String code,
    required String message,
    required String recovery,
    required bool passwordProtectionConfirmed,
    required bool isUnrecognized,
    required _Attempt attempt,
  }) async {
    expect(outcome, isA<ImportRejected>());
    final ImportFailurePresentation failure =
        (outcome as ImportRejected).failure;
    expect(failure.code, code);
    expect(failure.presentationCode, code);
    expect(failure.message, message);
    expect(failure.recovery, recovery);
    expect(failure.isCancellation, isFalse);
    expect(failure.passwordProtectionConfirmed, passwordProtectionConfirmed);
    expect(failure.isUnrecognized, isUnrecognized);
    expect(attempt.createDocumentCalls, 0);
    expect(attempt.documentsAfter, attempt.documentsBefore);
  }

  Future<void> disposeDocument(
    AndroidStoreClient store,
    String documentId,
  ) async {
    final List<StoredMeta> matches = (await store.list(StoreKind.document))
        .where((StoredMeta meta) => meta.id == documentId)
        .toList();
    if (matches.isEmpty) {
      return;
    }
    await store.delete(
      StoreKind.document,
      documentId,
      DeleteConfirmation(title: matches.single.title, acknowledged: true),
    );
  }

  Future<void> expectRenderedPagesIdentical(
    Uint8List original,
    Uint8List stored,
    List<PageGeometry> pages,
  ) async {
    final PdfDocument originalDocument = await PdfDocument.openData(
      original,
      sourceName: 't046-original-${DateTime.now().microsecondsSinceEpoch}',
    );
    final PdfDocument storedDocument = await PdfDocument.openData(
      stored,
      sourceName: 't046-stored-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      expect(originalDocument.pages.length, pages.length);
      expect(storedDocument.pages.length, pages.length);
      for (int index = 0; index < pages.length; index++) {
        final double width = pages[index].displaySize.width;
        final double height = pages[index].displaySize.height;
        expect(originalDocument.pages[index].width, closeTo(width, 0.05));
        expect(originalDocument.pages[index].height, closeTo(height, 0.05));
        expect(storedDocument.pages[index].width, closeTo(width, 0.05));
        expect(storedDocument.pages[index].height, closeTo(height, 0.05));
        final String originalDigest = await _renderDigest(
          originalDocument,
          index,
          width,
          height,
        );
        final String storedDigest = await _renderDigest(
          storedDocument,
          index,
          width,
          height,
        );
        expect(
          storedDigest,
          originalDigest,
          reason: 'protected copy page ${index + 1} must render identically',
        );
      }
    } finally {
      await originalDocument.dispose();
      await storedDocument.dispose();
    }
  }

  testWidgets('single-page valid fixture imports with catalog geometry', (
    WidgetTester tester,
  ) async {
    final Map<String, Uint8List> fixtures = loadFixtures();
    final Uint8List bytes = fixtures['sf-004']!;
    final File source = await writeScratchSource('single', bytes);
    final Uint8List before = await source.readAsBytes();
    final DateTime modified = (await source.stat()).modified;
    final AndroidOperationClient operations = AndroidOperationClient();
    final AndroidStoreClient store = AndroidStoreClient(operations: operations);
    final AndroidImportClient port = AndroidImportClient(
      operations: operations,
    );
    addTearDown(operations.dispose);
    addTearDown(() async {
      if (await source.exists()) {
        await source.delete();
      }
    });
    final _Attempt attempt = await runImport(
      source: source,
      displayName: 't046-single.pdf',
      forceUnknownPreflight: false,
      port: port,
      store: store,
    );
    try {
      expect(attempt.outcome, isA<ImportAccepted>());
      final ImportAccepted accepted = attempt.outcome as ImportAccepted;
      expect(accepted.warning, isNull);
      final ImportedSource imported = accepted.document.source;
      expect(attempt.createDocumentCalls, 1);
      expect(imported.sha256, _fixtureSha256['sf-004']);
      expect(imported.sizeBytes, _fixtureSizeBytes['sf-004']);
      expect(imported.pageCount, 1);
      expect(imported.pageFailures, isEmpty);
      expect(imported.displayName, 't046-single.pdf');
      _expectGeometry(imported.pages, _fixturePages['sf-004']!);
      await expectSourceUnchanged(
        source,
        before,
        modified,
        _fixtureSha256['sf-004']!,
      );

      // The picked source is deleted, so the following read can only come
      // from the system's protected internal copy (FR-095/FR-096).
      await source.delete();
      expect(await source.exists(), isFalse);

      final LoadedDocument loaded = await store.loadDocument(
        imported.documentId,
      );
      expect(loaded.meta.id, imported.documentId);
      expect(loaded.meta.title, 't046-single');
      expect(loaded.content.pages.length, 1);
      expect(_sha256(loaded.sourceBytes), imported.sha256);
      expect(loaded.sourceBytes, orderedEquals(bytes));
      _expectGeometry(
        loaded.content.pages.map((Page page) => page.geometry).toList(),
        _fixturePages['sf-004']!,
      );
      await expectRenderedPagesIdentical(
        bytes,
        loaded.sourceBytes,
        loaded.content.pages.map((Page page) => page.geometry).toList(),
      );
    } finally {
      if (attempt.outcome is ImportAccepted) {
        await disposeDocument(
          store,
          (attempt.outcome as ImportAccepted).document.source.documentId,
        );
      }
      await clearHook();
    }
  });

  testWidgets('five-page valid fixture imports all pages in order', (
    WidgetTester tester,
  ) async {
    final Map<String, Uint8List> fixtures = loadFixtures();
    final Uint8List bytes = fixtures['sf-002']!;
    final File source = await writeScratchSource('five-page', bytes);
    final Uint8List before = await source.readAsBytes();
    final DateTime modified = (await source.stat()).modified;
    final AndroidOperationClient operations = AndroidOperationClient();
    final AndroidStoreClient store = AndroidStoreClient(operations: operations);
    final AndroidImportClient port = AndroidImportClient(
      operations: operations,
    );
    addTearDown(operations.dispose);
    addTearDown(() async {
      if (await source.exists()) {
        await source.delete();
      }
    });
    final _Attempt attempt = await runImport(
      source: source,
      displayName: 't046-five-page.pdf',
      forceUnknownPreflight: false,
      port: port,
      store: store,
    );
    try {
      expect(attempt.outcome, isA<ImportAccepted>());
      final ImportAccepted accepted = attempt.outcome as ImportAccepted;
      expect(accepted.warning, isNull);
      final ImportedSource imported = accepted.document.source;
      expect(attempt.createDocumentCalls, 1);
      expect(imported.sha256, _fixtureSha256['sf-002']);
      expect(imported.sizeBytes, _fixtureSizeBytes['sf-002']);
      expect(imported.pageCount, 5);
      expect(imported.pages.map((PageGeometry page) => page.rotation), <int>[
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(imported.pageFailures, isEmpty);
      _expectGeometry(imported.pages, _fixturePages['sf-002']!);
      await expectSourceUnchanged(
        source,
        before,
        modified,
        _fixtureSha256['sf-002']!,
      );

      await source.delete();
      final LoadedDocument loaded = await store.loadDocument(
        imported.documentId,
      );
      expect(loaded.content.pages.length, 5);
      expect(_sha256(loaded.sourceBytes), imported.sha256);
      expect(loaded.sourceBytes, orderedEquals(bytes));
      final List<PageGeometry> storedPages = loaded.content.pages
          .map((Page page) => page.geometry)
          .toList();
      _expectGeometry(storedPages, _fixturePages['sf-002']!);
      await expectRenderedPagesIdentical(
        bytes,
        loaded.sourceBytes,
        storedPages,
      );
    } finally {
      if (attempt.outcome is ImportAccepted) {
        await disposeDocument(
          store,
          (attempt.outcome as ImportAccepted).document.source.documentId,
        );
      }
      await clearHook();
    }
  });

  testWidgets('mixed-geometry fixture preserves rotations and display sizes', (
    WidgetTester tester,
  ) async {
    final Map<String, Uint8List> fixtures = loadFixtures();
    final Uint8List bytes = fixtures['sf-003']!;
    final File source = await writeScratchSource('mixed-geometry', bytes);
    final Uint8List before = await source.readAsBytes();
    final DateTime modified = (await source.stat()).modified;
    final AndroidOperationClient operations = AndroidOperationClient();
    final AndroidStoreClient store = AndroidStoreClient(operations: operations);
    final AndroidImportClient port = AndroidImportClient(
      operations: operations,
    );
    addTearDown(operations.dispose);
    addTearDown(() async {
      if (await source.exists()) {
        await source.delete();
      }
    });
    final _Attempt attempt = await runImport(
      source: source,
      displayName: 't046-mixed-geometry.pdf',
      forceUnknownPreflight: false,
      port: port,
      store: store,
    );
    try {
      expect(attempt.outcome, isA<ImportAccepted>());
      final ImportAccepted accepted = attempt.outcome as ImportAccepted;
      expect(accepted.warning, isNull);
      final ImportedSource imported = accepted.document.source;
      expect(imported.pageCount, 5);
      expect(imported.pageFailures, isEmpty);
      _expectGeometry(imported.pages, _fixturePages['sf-003']!);
      await expectSourceUnchanged(
        source,
        before,
        modified,
        _fixtureSha256['sf-003']!,
      );

      await source.delete();
      final LoadedDocument loaded = await store.loadDocument(
        imported.documentId,
      );
      final List<PageGeometry> storedPages = loaded.content.pages
          .map((Page page) => page.geometry)
          .toList();
      _expectGeometry(storedPages, _fixturePages['sf-003']!);
      expect(_sha256(loaded.sourceBytes), imported.sha256);
      await expectRenderedPagesIdentical(
        bytes,
        loaded.sourceBytes,
        storedPages,
      );
    } finally {
      if (attempt.outcome is ImportAccepted) {
        await disposeDocument(
          store,
          (attempt.outcome as ImportAccepted).document.source.documentId,
        );
      }
      await clearHook();
    }
  });

  testWidgets('protected fixture is rejected with the exact IMP-001 text', (
    WidgetTester tester,
  ) async {
    final Map<String, Uint8List> fixtures = loadFixtures();
    final Uint8List bytes = fixtures['sf-protected']!;
    final File source = File(
      '${fixtureDirectory.path}${Platform.pathSeparator}sf-protected.pdf',
    );
    final DateTime modified = (await source.stat()).modified;
    final AndroidOperationClient operations = AndroidOperationClient();
    final AndroidStoreClient store = AndroidStoreClient(operations: operations);
    final AndroidImportClient port = AndroidImportClient(
      operations: operations,
    );
    addTearDown(operations.dispose);
    final _Attempt attempt = await runImport(
      source: source,
      displayName: 'sf-protected.pdf',
      forceUnknownPreflight: false,
      port: port,
      store: store,
    );
    try {
      await expectCatalogRejection(
        attempt.outcome,
        code: 'IMP-001',
        message: _imp001,
        recovery: _imp001Recovery,
        passwordProtectionConfirmed: true,
        isUnrecognized: false,
        attempt: attempt,
      );
      expect(de.imp001, _imp001);
      expect(de.imp001Recovery, _imp001Recovery);
      await expectSourceUnchanged(
        source,
        bytes,
        modified,
        _fixtureSha256['sf-protected']!,
      );
    } finally {
      await clearHook();
    }
  });

  testWidgets('truncated fixture is rejected with the exact IMP-002 text', (
    WidgetTester tester,
  ) async {
    final Map<String, Uint8List> fixtures = loadFixtures();
    final Uint8List bytes = fixtures['sf-truncated']!;
    final File source = File(
      '${fixtureDirectory.path}${Platform.pathSeparator}sf-truncated.pdf',
    );
    final DateTime modified = (await source.stat()).modified;
    final AndroidOperationClient operations = AndroidOperationClient();
    final AndroidStoreClient store = AndroidStoreClient(operations: operations);
    final AndroidImportClient port = AndroidImportClient(
      operations: operations,
    );
    addTearDown(operations.dispose);
    final _Attempt attempt = await runImport(
      source: source,
      displayName: 'sf-truncated.pdf',
      forceUnknownPreflight: false,
      port: port,
      store: store,
    );
    try {
      await expectCatalogRejection(
        attempt.outcome,
        code: 'IMP-002',
        message: _imp002,
        recovery: _imp002Recovery,
        passwordProtectionConfirmed: false,
        isUnrecognized: false,
        attempt: attempt,
      );
      expect(de.imp002, _imp002);
      expect(de.imp002Recovery, _imp002Recovery);
      await expectSourceUnchanged(
        source,
        bytes,
        modified,
        _fixtureSha256['sf-truncated']!,
      );
    } finally {
      await clearHook();
    }
  });

  testWidgets('non-PDF fixture is rejected with the exact IMP-004 text', (
    WidgetTester tester,
  ) async {
    final Map<String, Uint8List> fixtures = loadFixtures();
    final Uint8List bytes = fixtures['sf-not-a-pdf']!;
    final File source = File(
      '${fixtureDirectory.path}${Platform.pathSeparator}sf-not-a-pdf.pdf',
    );
    final DateTime modified = (await source.stat()).modified;
    final AndroidOperationClient operations = AndroidOperationClient();
    final AndroidStoreClient store = AndroidStoreClient(operations: operations);
    final AndroidImportClient port = AndroidImportClient(
      operations: operations,
    );
    addTearDown(operations.dispose);
    final _Attempt attempt = await runImport(
      source: source,
      displayName: 'sf-not-a-pdf.pdf',
      forceUnknownPreflight: false,
      port: port,
      store: store,
    );
    try {
      await expectCatalogRejection(
        attempt.outcome,
        code: 'IMP-004',
        message: _imp004,
        recovery: _imp004Recovery,
        passwordProtectionConfirmed: false,
        isUnrecognized: false,
        attempt: attempt,
      );
      expect(de.imp004, _imp004);
      expect(de.imp004Recovery, _imp004Recovery);
      await expectSourceUnchanged(
        source,
        bytes,
        modified,
        _fixtureSha256['sf-not-a-pdf']!,
      );
    } finally {
      await clearHook();
    }
  });

  testWidgets(
    'unknown preflight cause is rejected with the exact IMP-005 text',
    (WidgetTester tester) async {
      // A deterministically crafted PDF cannot reach PDFBox's generic
      // exception branch on every supported version. The declared debug-only
      // seam therefore makes the real loader throw a generic exception for this
      // one armed import; the production PdfPreflight catch classifies it as
      // IMP-005, and the production mapper renders the catalog text. The
      // fixture itself is valid.
      final Map<String, Uint8List> fixtures = loadFixtures();
      final Uint8List bytes = fixtures['sf-004']!;
      final File source = File(
        '${fixtureDirectory.path}${Platform.pathSeparator}sf-004.pdf',
      );
      final DateTime modified = (await source.stat()).modified;
      final AndroidOperationClient operations = AndroidOperationClient();
      final AndroidStoreClient store = AndroidStoreClient(
        operations: operations,
      );
      final AndroidImportClient port = AndroidImportClient(
        operations: operations,
      );
      addTearDown(operations.dispose);
      final _Attempt attempt = await runImport(
        source: source,
        displayName: 'sf-004.pdf',
        forceUnknownPreflight: true,
        port: port,
        store: store,
      );
      try {
        await expectCatalogRejection(
          attempt.outcome,
          code: 'IMP-005',
          message: _imp005,
          recovery: _imp005Recovery,
          passwordProtectionConfirmed: false,
          // The native layer reports a mapped IMP-005 code, so the mapper's
          // explicit "unmapped code" fallback flag stays false. The presented
          // text is still the cause-unknown IMP-005 sentence.
          isUnrecognized: false,
          attempt: attempt,
        );
        expect(de.imp005, _imp005);
        expect(de.imp005Recovery, _imp005Recovery);
        await expectSourceUnchanged(
          source,
          bytes,
          modified,
          _fixtureSha256['sf-004']!,
        );
      } finally {
        await clearHook();
      }
    },
  );

  testWidgets(
    'partially damaged fixture imports with IMP-006 and usable page',
    (WidgetTester tester) async {
      final Map<String, Uint8List> fixtures = loadFixtures();
      final Uint8List valid = fixtures['sf-001']!;
      // Produced deterministically from the committed synthetic sf-001: the
      // second page's `/MediaBox` array is replaced by same-length spaces, so
      // all xref offsets stay valid, page 0 keeps its real geometry, and page 1
      // has no inheritable MediaBox. PdfPreflight reports page 1 as unreadable
      // and the import succeeds with IMP-006 (FR-010).
      final Uint8List damaged = _damageSecondPageMediaBox(valid);
      expect(damaged.length, valid.length);
      expect(damaged, isNot(orderedEquals(valid)));
      final File source = await writeScratchSource('partial-damage', damaged);
      final Uint8List before = await source.readAsBytes();
      final DateTime modified = (await source.stat()).modified;
      final AndroidOperationClient operations = AndroidOperationClient();
      final AndroidStoreClient store = AndroidStoreClient(
        operations: operations,
      );
      final AndroidImportClient port = AndroidImportClient(
        operations: operations,
      );
      addTearDown(operations.dispose);
      addTearDown(() async {
        if (await source.exists()) {
          await source.delete();
        }
      });
      final _Attempt attempt = await runImport(
        source: source,
        displayName: 't046-partial.pdf',
        forceUnknownPreflight: false,
        port: port,
        store: store,
      );
      try {
        expect(attempt.outcome, isA<ImportAccepted>());
        final ImportAccepted accepted = attempt.outcome as ImportAccepted;
        final ImportPartialWarning? warning = accepted.warning;
        expect(warning, isNotNull);
        expect(warning!.pageNumbers, <int>[2]);
        expect(warning.message, _imp006);
        expect(warning.recovery, _imp006Recovery);
        expect(de.imp006('2'), _imp006);
        final ImportedSource imported = accepted.document.source;
        expect(attempt.createDocumentCalls, 1);
        expect(imported.pageCount, 2);
        expect(imported.pageFailures, hasLength(1));
        expect(imported.pageFailures.single.pageIndex, 1);
        expect(imported.pageFailures.single.messageKey, 'IMP-006');
        expect(
          imported.pageFailures.single.category,
          PageFailureCategory.unsupportedStructure,
        );
        // The unreadable page keeps the documented 1x1 placeholder, never a
        // fabricated original geometry.
        expect(imported.pages[1].mediaBox.width, 1);
        expect(imported.pages[1].mediaBox.height, 1);
        expect(imported.pages[0].displaySize.width, closeTo(595.28, 0.01));
        expect(imported.pages[0].displaySize.height, closeTo(841.89, 0.01));
        await expectSourceUnchanged(source, before, modified, _sha256(damaged));

        await source.delete();
        final LoadedDocument loaded = await store.loadDocument(
          imported.documentId,
        );
        expect(loaded.content.pages.length, 2);
        expect(loaded.content.pages[0].unreadable, isFalse);
        expect(loaded.content.pages[1].unreadable, isTrue);
        expect(loaded.meta.readable, isTrue);
        expect(_sha256(loaded.sourceBytes), _sha256(damaged));
        // The readable page remains renderable from the protected copy and is
        // pixel-identical to the source's page 1.
        final PdfDocument original = await PdfDocument.openData(
          damaged,
          sourceName:
              't046-partial-original-${DateTime.now().microsecondsSinceEpoch}',
        );
        final PdfDocument stored = await PdfDocument.openData(
          loaded.sourceBytes,
          sourceName:
              't046-partial-stored-${DateTime.now().microsecondsSinceEpoch}',
        );
        try {
          final String originalDigest = await _renderDigest(
            original,
            0,
            imported.pages[0].displaySize.width,
            imported.pages[0].displaySize.height,
          );
          final String storedDigest = await _renderDigest(
            stored,
            0,
            imported.pages[0].displaySize.width,
            imported.pages[0].displaySize.height,
          );
          expect(storedDigest, originalDigest);
        } finally {
          await original.dispose();
          await stored.dispose();
        }
      } finally {
        if (attempt.outcome is ImportAccepted) {
          await disposeDocument(
            store,
            (attempt.outcome as ImportAccepted).document.source.documentId,
          );
        }
        await clearHook();
      }
    },
  );
}

final class _Attempt {
  const _Attempt({
    required this.outcome,
    required this.createDocumentCalls,
    required this.documentsBefore,
    required this.documentsAfter,
  });

  final ImportOutcome outcome;
  final int createDocumentCalls;
  final Set<String> documentsBefore;
  final Set<String> documentsAfter;
}

void _expectGeometry(
  List<PageGeometry> actual,
  List<_PageExpectation> expected,
) {
  expect(actual, hasLength(expected.length));
  for (int index = 0; index < expected.length; index++) {
    final _PageExpectation page = expected[index];
    final PageGeometry geometry = actual[index];
    expect(geometry.rotation, page.rotation, reason: 'page ${index + 1}');
    expect(
      geometry.mediaBox.width,
      closeTo(page.mediaWidthPt, 0.01),
      reason: 'page ${index + 1} media width',
    );
    expect(
      geometry.mediaBox.height,
      closeTo(page.mediaHeightPt, 0.01),
      reason: 'page ${index + 1} media height',
    );
    expect(
      geometry.displaySize.width,
      closeTo(page.displayWidthPt, 0.01),
      reason: 'page ${index + 1} display width',
    );
    expect(
      geometry.displaySize.height,
      closeTo(page.displayHeightPt, 0.01),
      reason: 'page ${index + 1} display height',
    );
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

/// Replaces the second `/MediaBox [0 0 595.28 841.89]` occurrence in sf-001
/// with spaces of exactly the same length.
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
