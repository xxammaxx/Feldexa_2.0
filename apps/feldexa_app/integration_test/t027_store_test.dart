// T027 real Dart -> MethodChannel -> native EncryptedStore/Keystore journey.
//
// Run only on an exclusively allocated Android emulator:
//   flutter test integration_test/t027_store_test.dart -d emulator-5554
//
// The test uses synthetic PDF bytes and a random document identity. It cleans
// up its own aggregate; it never reads or deletes another document.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real store creates, saves, loads, lists, and deletes', (
    WidgetTester tester,
  ) async {
    final AndroidStoreClient store = AndroidStoreClient();
    final AndroidIdClient ids = AndroidIdClient();
    final String documentId = ids.newId();
    final String sourceId = ids.newId();
    final String revisionId = ids.newId();
    final Uint8List source = Uint8List.fromList(
      utf8.encode('%PDF-1.7\nT027 synthetic Dart/native source\n'),
    );
    final String sourceSha = crypto.sha256.convert(source).toString();
    final RevisionContent content = _content();
    final String contentSha = crypto.sha256
        .convert(canonicalJsonBytes(content.toJson()))
        .toString();
    final CreateDocumentRequest request = CreateDocumentRequest(
      documentId: documentId,
      title: 'T027 Integrationstest',
      source: SourceFileRef(
        id: sourceId,
        sha256: sourceSha,
        sizeBytes: source.length,
        pageCount: 1,
        importedAt: DateTime.now().toUtc(),
      ),
      initialRevision: Revision(
        id: revisionId,
        documentId: documentId,
        kind: RevisionKind.explicit,
        createdAt: DateTime.now().toUtc(),
        plaintextSha256: contentSha,
        content: content,
      ),
    );
    bool created = false;
    try {
      await store.stageSource(
        documentId: documentId,
        sourceId: sourceId,
        bytes: source,
        sha256: sourceSha,
      );
      final StoredMeta createdMeta = await store.createDocument(request);
      created = true;
      expect(createdMeta.id, documentId);
      expect(createdMeta.latestRevisionId, revisionId);
      expect(createdMeta.title, 'T027 Integrationstest');
      expect(createdMeta.readable, isTrue);
      expect(createdMeta.kind, StoreKind.document);

      final LoadedDocument loaded = await store.loadDocument(documentId);
      expect(loaded.meta.id, documentId);
      expect(loaded.meta.latestRevisionId, revisionId);
      expect(loaded.content.pageCount, 1);
      expect(loaded.sourceBytes, orderedEquals(source));

      final List<StoredMeta> listed = await store.list(StoreKind.document);
      final StoredMeta listedMeta = listed.singleWhere(
        (StoredMeta meta) => meta.id == documentId,
      );
      expect(listedMeta.latestRevisionId, revisionId);
      expect(listedMeta.readable, isTrue);

      final StoredMeta saved = await store.saveRevision(
        SaveRevisionRequest(
          documentId: documentId,
          expectedHead: revisionId,
          content: content,
          kind: RevisionKind.explicit,
        ),
      );
      expect(saved.id, documentId);
      expect(saved.latestRevisionId, isNot(revisionId));
      expect(saved.readable, isTrue);

      final LoadedDocument reloaded = await store.loadDocument(documentId);
      expect(reloaded.meta.latestRevisionId, saved.latestRevisionId);
      expect(reloaded.sourceBytes, orderedEquals(source));

      await expectLater(
        store.createDocument(request),
        throwsA(isA<AndroidConcurrentWriteException>()),
      );
      final LoadedDocument afterDuplicate = await store.loadDocument(
        documentId,
      );
      expect(afterDuplicate.meta.latestRevisionId, saved.latestRevisionId);

      await expectLater(
        store.saveRevision(
          SaveRevisionRequest(
            documentId: documentId,
            expectedHead: ids.newId(),
            content: content,
            kind: RevisionKind.autosave,
          ),
        ),
        throwsA(isA<AndroidConcurrentWriteException>()),
      );
      final LoadedDocument afterConflict = await store.loadDocument(documentId);
      expect(afterConflict.meta.latestRevisionId, saved.latestRevisionId);

      final RecoveryStamp stamp = await store.recoveryStamp(
        documentId,
        StoreKind.document,
      );
      expect(stamp.verifiedRevisionId, saved.latestRevisionId);
      expect(stamp.headCorrupt, isFalse);
      expect(stamp.fellBackToOlderRevision, isFalse);

      final AndroidRecoveryReport recovery = await store.runStartupRecovery();
      expect(recovery.incompleteAggregatesRemoved, greaterThanOrEqualTo(0));

      await store.delete(
        StoreKind.document,
        documentId,
        DeleteConfirmation(title: 'T027 Integrationstest', acknowledged: true),
      );
      created = false;
      final List<StoredMeta> afterDelete = await store.list(StoreKind.document);
      expect(
        afterDelete.where((StoredMeta meta) => meta.id == documentId),
        isEmpty,
      );
    } finally {
      if (created) {
        try {
          await store.delete(
            StoreKind.document,
            documentId,
            DeleteConfirmation(
              title: 'T027 Integrationstest',
              acknowledged: true,
            ),
          );
        } catch (_) {
          // Cleanup is best-effort; the assertion above already recorded the
          // test outcome.
        }
      }
    }
  });
}

RevisionContent _content() {
  return RevisionContent(
    pages: <Page>[
      Page(
        index: 0,
        geometry: PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842)),
      ),
    ],
    fieldOrder: const <String>[],
  );
}
