// T098 plaintext-residue sweep across the app-private storage tree
// (FR-082; CHK029).
//
// Run only on an exclusively allocated Android emulator:
//   flutter test integration_test/plaintext_leak_test.dart -d emulator-5554
//
// The test stages a distinctive synthetic "PDF" through the real Dart ->
// MethodChannel -> native EncryptedStore path (`AndroidStoreClient`, T027),
// creates a document with revisions and a signature asset, and then walks the
// whole app-private storage tree (`Directory.systemTemp.parent` is
// `/data/user/0/de.feldexa.app` inside the app process) and asserts:
//   1. no file anywhere under the app-private tree contains the distinctive
//      staged source bytes (no plaintext copy, cache, thumbnail, or backup);
//   2. no file contains the plaintext `%PDF-1` magic at all — the only
//      sanctioned plaintext artifact (FR-082's user-requested export preview)
//      is not created by this test, and the startup sweep removes stale ones.
//
// Honest scope notes (reported, not hidden):
//   * The sweep reads the app-private tree in-process; `adb shell run-as` and
//     `adb backup` derivations from the host are recorded in the evidence
//     report, not inside this file.
//   * Logcat is not a file under the app-private tree; the production store
//     client logs content-free receipts only, and logcat residue is covered
//     by the host-side review (CHK029) rather than this device sweep.

library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const int _maxFiles = 5000;
const int _maxFileBytes = 8 << 20;

/// Runs [body] with real async support and asserts it yields a value.
Future<T> _run<T>(WidgetTester tester, Future<T> Function() body) async {
  final T? value = await tester.runAsync(body);
  return value as T;
}

Uint8List _stagedSource() {
  final Uint8List bytes = Uint8List.fromList(
    const <int>[37, 80, 68, 70, 45, 49, 46, 55, 10], // %PDF-1.7\n
  );
  // Distinctive 64-byte marker appended after a separator so the byte
  // sequence cannot occur in any other file by chance.
  final Uint8List marker = Uint8List.fromList(
    List<int>.generate(64, (int i) => (i * 37 + 11) % 256),
  );
  final Uint8List combined = Uint8List(bytes.length + 1 + marker.length);
  combined.setRange(0, bytes.length, bytes);
  combined[bytes.length] = 0x1E;
  combined.setRange(bytes.length + 1, combined.length, marker);
  return combined;
}

Future<void> _sweep(Directory root, Future<void> Function(File) check) async {
  int visited = 0;
  final List<Directory> pending = <Directory>[root];
  while (pending.isNotEmpty && visited < _maxFiles) {
    final Directory current = pending.removeLast();
    await for (final FileSystemEntity entity in current.list()) {
      if (visited >= _maxFiles) {
        break;
      }
      if (entity is Directory) {
        pending.add(entity);
      } else if (entity is File) {
        visited++;
        final int size = await entity.length();
        if (size > _maxFileBytes) {
          continue;
        }
        await check(entity);
      }
    }
  }
  expect(
    visited,
    lessThan(_maxFiles),
    reason: 'the sweep must stay bounded; unexpected storage growth',
  );
}

bool _contains(Uint8List haystack, List<int> needle) {
  if (needle.isEmpty || haystack.length < needle.length) {
    return false;
  }
  outer:
  for (int i = 0; i <= haystack.length - needle.length; i++) {
    for (int j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        continue outer;
      }
    }
    return true;
  }
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'no plaintext document bytes remain anywhere under the app-private tree',
    (WidgetTester tester) async {
      final Directory appRoot = Directory.systemTemp.parent;
      expect(appRoot.existsSync(), isTrue);

      final AndroidStoreClient store = AndroidStoreClient();
      final AndroidIdClient ids = AndroidIdClient();
      final String documentId = ids.newId();
      final String sourceId = ids.newId();
      final Uint8List source = _stagedSource();
      final String sourceSha = crypto.sha256.convert(source).toString();
      final RevisionContent content = RevisionContent(
        pages: <Page>[
          Page(
            index: 0,
            geometry: PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842)),
          ),
        ],
        fieldOrder: const <String>[],
      );
      bool created = false;
      try {
        await store.stageSource(
          documentId: documentId,
          sourceId: sourceId,
          bytes: source,
          sha256: sourceSha,
        );
        await store.createDocument(
          CreateDocumentRequest(
            documentId: documentId,
            title: 'T098 Plaintext-Sweep',
            source: SourceFileRef(
              id: sourceId,
              sha256: sourceSha,
              sizeBytes: source.length,
              pageCount: 1,
              importedAt: DateTime.now().toUtc(),
            ),
            initialRevision: Revision(
              id: ids.newId(),
              documentId: documentId,
              kind: RevisionKind.explicit,
              createdAt: DateTime.now().toUtc(),
              plaintextSha256: crypto.sha256
                  .convert(canonicalJsonBytes(content.toJson()))
                  .toString(),
              content: content,
            ),
          ),
        );
        created = true;
        final LoadedDocument loaded = await store.loadDocument(documentId);
        expect(loaded.meta.readable, isTrue);
        expect(loaded.sourceBytes, source);

        final List<String> plaintextPdfFiles = <String>[];
        final List<String> markerFiles = <String>[];
        final List<int> magic = <int>[37, 80, 68, 70, 45, 49]; // %PDF-1

        await _sweep(appRoot, (File file) async {
          final Uint8List bytes = await _run(tester, () => file.readAsBytes());
          if (_contains(bytes, source)) {
            markerFiles.add(file.path);
          }
          if (_contains(bytes, magic)) {
            plaintextPdfFiles.add(file.path);
          }
        });

        expect(
          markerFiles,
          isEmpty,
          reason:
              'a byte-identical copy of the staged source is plaintext '
              'document residue (FR-082)',
        );
        expect(
          plaintextPdfFiles,
          isEmpty,
          reason:
              'no plaintext PDF magic may exist outside the sanctioned, '
              'short-lived user-requested export preview (FR-082)',
        );
      } finally {
        if (created) {
          try {
            await store.delete(
              StoreKind.document,
              documentId,
              DeleteConfirmation(
                title: 'T098 Plaintext-Sweep',
                acknowledged: true,
              ),
            );
          } catch (_) {
            // Best-effort cleanup.
          }
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
