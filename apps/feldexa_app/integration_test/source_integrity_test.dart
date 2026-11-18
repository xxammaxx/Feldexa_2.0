// T048 source-integrity integration test (US1; FR-004/FR-095/FR-096; SC-019).
//
// Run only on the exclusively allocated Android emulator:
//   flutter test integration_test/source_integrity_test.dart -d emulator-5554
//
// Device-side fixture delivery (reuses the T046 staging; the fixtures are
// deliberately not Flutter assets, see `assets/fixtures/catalog.json`):
//   adb -s emulator-5554 shell mkdir -p /data/local/tmp/t046-fixtures
//   adb -s emulator-5554 push apps/feldexa_app/assets/fixtures/sf-001.pdf \
//       /data/local/tmp/t046-fixtures/sf-001.pdf
//   adb -s emulator-5554 push apps/feldexa_app/assets/fixtures/sf-003.pdf \
//       /data/local/tmp/t046-fixtures/sf-003.pdf
//   adb -s emulator-5554 shell chmod 755 /data/local/tmp/t046-fixtures
//   adb -s emulator-5554 shell chmod 644 /data/local/tmp/t046-fixtures/*.pdf
//
// This test covers the production path, not a substitute:
//   * the T046 debug-only `de.feldexa/test.import` channel arms one source file
//     (MainActivity/ImportTestHooks; no handler exists in release builds);
//   * `AndroidImportClient` invokes the real `import.pickAndImport`;
//   * the native `ImportService` streams the source through the real encrypted
//     staging, preflight, and verified commit;
//   * `ImportFlow` applies the production German mapper and FR-009 gate;
//   * `AndroidStoreClient`/`store.readSource` read the committed document back
//     from the protected store after the picked source is moved and deleted;
//   * `pdfrx` (real PDFium) renders the pages from the decrypted protected
//     bytes.
//
// Distinct from T046: T046 proves byte identity and unchanged modification
// time at import plus a protected-store read-back immediately after deleting
// the picked source. This test drives the SC-019 lifecycle: the picked file is
// moved to a different directory, the document is reopened and rendered from
// the protected copy, the moved file is then deleted, the document is reopened
// and rendered again, and the export surface is exercised.
//
// Export is a recorded dependency blocker, not a pass. The Kotlin `export/`
// implementation directory contains only `.gitkeep`, `MainActivity` registers
// no `export` service, and T104
// (`android/app/src/main/kotlin/de/feldexa/app/export/PdfExportService.kt`) is
// unimplemented. The test therefore asserts that the production facade fails
// closed for `export.validate`/`export.render` with
// `PLT-001`/`platform.unsupported` and records that observation; no export
// artifact is fabricated and no export success is claimed.
//
// The test writes only synthetic fixture copies, moves and deletes only those
// copies, and deletes every document it creates. It never reads or deletes
// another document.

import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:feldexa_app/features/start/import_error_mapper.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// App-readable staging directory prepared with `adb push` (see file header).
const String _fixtureRoot = '/data/local/tmp/t046-fixtures';

/// T046 debug-only fixture gate; not registered in release builds.
const MethodChannel _testHooks = MethodChannel('de.feldexa/test.import');

/// Production platform channel. Used only for the contract-level read-back
/// (`store.readSource`) and for the recorded export-blocker probe.
const MethodChannel _platform = MethodChannel('de.feldexa/platform');

const String _sf001Sha256 =
    '22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038';
const String _sf003Sha256 =
    'c19afcf6f86ed21a422426c5f01613bb9643b097d0facad3b3349f9873e4ea4f';

const Map<String, int> _fixtureSizeBytes = <String, int>{
  'sf-001': 5956,
  'sf-003': 6610,
};

const Map<String, String> _fixtureSha256 = <String, String>{
  'sf-001': _sf001Sha256,
  'sf-003': _sf003Sha256,
};

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

/// One SC-019 trial: a fixture imported, moved, deleted, reopened, rendered.
final class _Trial {
  const _Trial({
    required this.slug,
    required this.fixtureId,
    required this.displayName,
    required this.pages,
  });

  final String slug;
  final String fixtureId;
  final String displayName;
  final List<_PageExpectation> pages;
}

const List<_PageExpectation> _sf001Pages = <_PageExpectation>[
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
];

const List<_PageExpectation> _sf003Pages = <_PageExpectation>[
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
];

const List<_Trial> _trials = <_Trial>[
  _Trial(
    slug: 'mixed-geometry',
    fixtureId: 'sf-003',
    displayName: 't048-sf-003.pdf',
    pages: _sf003Pages,
  ),
  _Trial(
    slug: 'two-page',
    fixtureId: 'sf-001',
    displayName: 't048-sf-001.pdf',
    pages: _sf001Pages,
  ),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final AppLocalizations de = lookupAppLocalizations(const Locale('de'));
  final Directory fixtureDirectory = Directory(_fixtureRoot);

  setUpAll(() async {
    await pdfrxFlutterInitialize();
  });

  for (final _Trial trial in _trials) {
    testWidgets(
      '${trial.slug}: moved then deleted source still reopens and renders',
      (WidgetTester tester) async {
        final Uint8List fixtureBytes = _loadFixture(
          fixtureDirectory,
          trial.fixtureId,
        );
        final Directory originDirectory = Directory(
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          't048-${trial.slug}-origin',
        );
        final Directory movedDirectory = Directory(
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          't048-${trial.slug}-moved',
        );
        // A previously aborted run must not leave bytes behind that would
        // weaken the "no filesystem copy remains" assertion below.
        if (await originDirectory.exists()) {
          await originDirectory.delete(recursive: true);
        }
        if (await movedDirectory.exists()) {
          await movedDirectory.delete(recursive: true);
        }
        await originDirectory.create(recursive: true);
        await movedDirectory.create(recursive: true);
        final String fileName =
            '${trial.fixtureId}-${DateTime.now().microsecondsSinceEpoch}.pdf';
        final File picked = File(
          '${originDirectory.path}${Platform.pathSeparator}$fileName',
        );
        await picked.writeAsBytes(fixtureBytes, flush: true);
        final FileStat beforeMove = await picked.stat();
        expect(beforeMove.size, _fixtureSizeBytes[trial.fixtureId]);

        final AndroidOperationClient operations = AndroidOperationClient();
        final AndroidStoreClient store = AndroidStoreClient(
          operations: operations,
        );
        final AndroidImportClient importPort = AndroidImportClient(
          operations: operations,
        );
        addTearDown(operations.dispose);
        addTearDown(() async {
          if (await picked.exists()) {
            await picked.delete();
          }
          if (await originDirectory.exists()) {
            await originDirectory.delete(recursive: true);
          }
          if (await movedDirectory.exists()) {
            await movedDirectory.delete(recursive: true);
          }
        });

        await _armFile(picked, displayName: trial.displayName);
        final Set<String> documentsBefore = (await store.list(
          StoreKind.document,
        )).map((StoredMeta meta) => meta.id).toSet();
        int createDocumentCalls = 0;
        final ImportFlow flow = ImportFlow(
          localizations: de,
          createDocument: (ImportedDocumentCandidate document) async {
            createDocumentCalls++;
          },
        );
        final ImportOutcome outcome = await flow.run(
          port: importPort,
          request: ImportRequest(),
        );
        expect(
          outcome,
          isA<ImportAccepted>(),
          reason: 'the source-integrity scenario needs a successful import',
        );
        final ImportAccepted accepted = outcome as ImportAccepted;
        final ImportedSource imported = accepted.document.source;
        try {
          // 1. Import succeeded through the production pipeline and the picked
          //    source was not modified in place (FR-004).
          expect(accepted.warning, isNull);
          expect(createDocumentCalls, 1);
          expect(imported.sha256, _fixtureSha256[trial.fixtureId]);
          expect(imported.sizeBytes, _fixtureSizeBytes[trial.fixtureId]);
          expect(imported.pageCount, trial.pages.length);
          expect(imported.pageFailures, isEmpty);
          expect(imported.displayName, trial.displayName);
          _expectGeometry(imported.pages, trial.pages);
          final Set<String> documentsAfter = (await store.list(
            StoreKind.document,
          )).map((StoredMeta meta) => meta.id).toSet();
          expect(documentsAfter, hasLength(documentsBefore.length + 1));
          expect(documentsAfter.contains(imported.documentId), isTrue);
          await _expectFileIdentity(picked, fixtureBytes, beforeMove);

          // 2. Move the picked file to a different directory. The original
          //    path must be gone, the moved bytes and modification time must be
          //    unchanged, and the file itself must never be rewritten.
          final File movedFile = File(
            '${movedDirectory.path}${Platform.pathSeparator}$fileName',
          );
          await picked.rename(movedFile.path);
          expect(await picked.exists(), isFalse);
          expect(await movedFile.exists(), isTrue);
          await _expectFileIdentity(movedFile, fixtureBytes, beforeMove);

          // 3. Reopen from storage while the picked path is gone, read the
          //    protected source explicitly through `store.readSource`, and
          //    render every page with PDFium from those decrypted bytes.
          final LoadedDocument whileMoved = await store.loadDocument(
            imported.documentId,
          );
          _expectLoadedDocument(
            whileMoved,
            imported.documentId,
            trial,
            expectedSha256: _fixtureSha256[trial.fixtureId]!,
          );
          final List<PageGeometry> storedPages = whileMoved.content.pages
              .map((Page page) => page.geometry)
              .toList();
          final List<String> referenceDigests = await _renderDigests(
            fixtureBytes,
            storedPages,
            'fixture-${trial.slug}',
          );
          final List<String> movedDigests = await _renderDigests(
            whileMoved.sourceBytes,
            storedPages,
            'stored-moved-${trial.slug}',
          );
          expect(
            movedDigests,
            orderedEquals(referenceDigests),
            reason:
                'the protected copy must render pixel-identically to the '
                'original fixture bytes',
          );
          final Uint8List contractRead = await _readProtectedSource(
            imported.documentId,
          );
          expect(_sha256(contractRead), imported.sha256);
          expect(contractRead, orderedEquals(fixtureBytes));

          // 4. Delete the moved file. Neither filesystem copy exists now, so
          //    every byte rendered below can only come from the protected
          //    internal copy (FR-095/FR-096).
          await movedFile.delete();
          expect(await movedFile.exists(), isFalse);
          expect(await picked.exists(), isFalse);
          expect(originDirectory.listSync(), isEmpty);
          expect(movedDirectory.listSync(), isEmpty);

          final List<StoredMeta> listed = await store.list(StoreKind.document);
          expect(
            listed.map((StoredMeta meta) => meta.id),
            contains(imported.documentId),
          );
          final LoadedDocument afterDelete = await store.loadDocument(
            imported.documentId,
          );
          _expectLoadedDocument(
            afterDelete,
            imported.documentId,
            trial,
            expectedSha256: _fixtureSha256[trial.fixtureId]!,
          );
          final List<String> afterDeleteDigests = await _renderDigests(
            afterDelete.sourceBytes,
            afterDelete.content.pages
                .map((Page page) => page.geometry)
                .toList(),
            'stored-deleted-${trial.slug}',
          );
          expect(afterDeleteDigests, orderedEquals(referenceDigests));

          debugPrint(
            'T048 ${trial.slug}: fixture=${_sha256(fixtureBytes)} '
            'stored=${_sha256(afterDelete.sourceBytes)} '
            'pages=${afterDelete.content.pages.length} '
            'digests=${referenceDigests.join(',')}',
          );

          // 5. Export from the protected copy. No production export service
          //    exists; the facade must fail closed with PLT-001 and the test
          //    records that blocker instead of asserting an export success.
          final String? latestRevisionId = afterDelete.meta.latestRevisionId;
          if (latestRevisionId == null || latestRevisionId.isEmpty) {
            fail('the reopened document must have a latest revision id');
          }
          await _expectExportUnavailable(
            documentId: imported.documentId,
            revisionId: latestRevisionId,
            sourceSha256: _fixtureSha256[trial.fixtureId]!,
            pages: afterDelete.content.pages
                .map((Page page) => page.geometry)
                .toList(),
            label: trial.slug,
          );
          debugPrint(
            'T048 ${trial.slug}: move+delete+reopen+render PASS; '
            'SC-019 export NOT VERIFIED (T104 production export missing)',
          );
        } finally {
          await _disposeDocument(store, imported.documentId);
          await _clearHook();
        }
      },
    );
  }
}

Uint8List _loadFixture(Directory fixtureDirectory, String fixtureId) {
  if (!fixtureDirectory.existsSync()) {
    fail(
      'Fixture staging directory $_fixtureRoot is missing. Push the '
      'committed fixtures with the adb command in this test file header.',
    );
  }
  final File file = File(
    '${fixtureDirectory.path}${Platform.pathSeparator}$fixtureId.pdf',
  );
  if (!file.existsSync()) {
    fail('Missing fixture $fixtureId.pdf in $_fixtureRoot.');
  }
  final Uint8List bytes = file.readAsBytesSync();
  expect(
    _sha256(bytes),
    _fixtureSha256[fixtureId],
    reason: 'fixture $fixtureId.pdf must match the committed catalogue',
  );
  expect(bytes.length, _fixtureSizeBytes[fixtureId]);
  return bytes;
}

Future<void> _armFile(File source, {required String displayName}) async {
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

Future<void> _expectFileIdentity(
  File file,
  Uint8List expectedBytes,
  FileStat beforeMove,
) async {
  final Uint8List actualBytes = await file.readAsBytes();
  final FileStat actual = await file.stat();
  expect(_sha256(actualBytes), _sha256(expectedBytes));
  expect(actualBytes, orderedEquals(expectedBytes));
  expect(actual.size, expectedBytes.length);
  expect(
    actual.modified,
    beforeMove.modified,
    reason: 'moving or importing must not modify the picked source mtime',
  );
}

void _expectLoadedDocument(
  LoadedDocument loaded,
  String documentId,
  _Trial trial, {
  required String expectedSha256,
}) {
  expect(loaded.meta.id, documentId);
  expect(
    loaded.meta.title,
    trial.displayName.substring(0, trial.displayName.length - '.pdf'.length),
  );
  expect(loaded.content.pages.length, trial.pages.length);
  expect(_sha256(loaded.sourceBytes), expectedSha256);
  _expectGeometry(
    loaded.content.pages.map((Page page) => page.geometry).toList(),
    trial.pages,
  );
}

Future<Uint8List> _readProtectedSource(String documentId) async {
  final Object? raw = await _platform.invokeMethod<Object?>(
    'store.readSource',
    <String, Object?>{'schemaVersion': 1, 'documentId': documentId},
  );
  final Object? value = androidEnvelopeValue(raw, method: 'store.readSource');
  final Uint8List? bytes = androidBytes(value);
  if (bytes == null || bytes.isEmpty) {
    fail('store.readSource returned no decrypted protected bytes');
  }
  return bytes;
}

Future<void> _expectExportUnavailable({
  required String documentId,
  required String revisionId,
  required String sourceSha256,
  required List<PageGeometry> pages,
  required String label,
}) async {
  final Map<String, Object?> plan = <String, Object?>{
    'schemaVersion': 1,
    'documentId': documentId,
    'revisionId': revisionId,
    'sourceSha256': sourceSha256,
    'pageCount': pages.length,
    'evidenceClass': 'emulator',
    'font': <String, Object?>{
      'family': 'NotoSans',
      'regularAsset': 'assets/fonts/NotoSans-Regular.ttf',
      'boldAsset': 'assets/fonts/NotoSans-Bold.ttf',
      'metricsVersion': 'noto-sans-2.013-v1',
    },
    'pages': <Object?>[
      for (final (int index, PageGeometry page) in pages.indexed)
        <String, Object?>{
          'index': index,
          'rotation': page.rotation,
          'mediaBox': _rectJson(page.mediaBox),
          'cropBox': _rectJson(page.cropBox),
          'displaySize': <String, Object?>{
            'width': page.displaySize.width,
            'height': page.displaySize.height,
          },
          'ctm': <String, Object?>{
            'a': 1.0,
            'b': 0.0,
            'c': 0.0,
            'd': -1.0,
            'e': 0.0,
            'f': page.displaySize.height,
          },
          'ops': <Object?>[],
        },
    ],
    'warnings': <Object?>[],
    'info': <String, Object?>{
      'emptyFieldCount': 0,
      'unresolvedSuggestionCount': 0,
    },
  };
  await _expectExportFailure('export.validate', label, plan);
  await _expectExportFailure('export.render', label, plan);
}

Future<void> _expectExportFailure(
  String method,
  String label,
  Map<String, Object?> plan,
) async {
  try {
    final Object? result = await _platform.invokeMethod<Object?>(
      method,
      <String, Object?>{'schemaVersion': 1, 'plan': plan},
    );
    fail('$method returned $result although no export service is registered');
  } on PlatformException catch (error) {
    expect(error.code, 'PLT-001', reason: '$method must fail closed');
    expect(error.message, 'platform.unsupported');
    final Object? details = error.details;
    if (details is! Map) {
      fail('$method failure carries no details map');
    }
    expect(details['category'], 'unsupported');
    expect(details['retryable'], isFalse);
    debugPrint(
      'T048 $label: $method -> ${error.code}/${error.message} '
      '(export blocker: production export service missing, owner T104)',
    );
  }
}

Map<String, Object?> _rectJson(Rect rect) => <String, Object?>{
  'x': rect.left,
  'y': rect.top,
  'width': rect.width,
  'height': rect.height,
};

Future<void> _disposeDocument(
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

Future<List<String>> _renderDigests(
  Uint8List bytes,
  List<PageGeometry> pages,
  String label,
) async {
  final PdfDocument document = await PdfDocument.openData(
    bytes,
    sourceName: 't048-$label-${DateTime.now().microsecondsSinceEpoch}',
  );
  try {
    expect(document.pages.length, pages.length, reason: '$label page count');
    final List<String> digests = <String>[];
    for (int index = 0; index < pages.length; index++) {
      final double width = pages[index].displaySize.width;
      final double height = pages[index].displaySize.height;
      expect(
        document.pages[index].width,
        closeTo(width, 0.05),
        reason: '$label page ${index + 1} width',
      );
      expect(
        document.pages[index].height,
        closeTo(height, 0.05),
        reason: '$label page ${index + 1} height',
      );
      final PdfImage? image = await document.pages[index].render(
        fullWidth: width,
        fullHeight: height,
      );
      if (image == null) {
        fail('$label PDFium could not render page ${index + 1}');
      }
      try {
        expect(image.width, closeTo(width, 1));
        expect(image.height, closeTo(height, 1));
        digests.add(_sha256(image.pixels));
      } finally {
        image.dispose();
      }
    }
    return digests;
  } finally {
    await document.dispose();
  }
}

String _sha256(List<int> bytes) => crypto.sha256.convert(bytes).toString();
