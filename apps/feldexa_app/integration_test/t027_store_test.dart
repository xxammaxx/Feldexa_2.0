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
      expect(
        loaded.content.unknownFields['t027CanonicalProbe'],
        1.0000000000000002e-7,
      );
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

      final String signatureId = ids.newId();
      final Uint8List signatureBytes = base64Decode(_validSignature2x2);
      final String signatureSha = crypto.sha256
          .convert(signatureBytes)
          .toString();
      await store.writeSignature(
        WriteSignatureRequest(
          documentId: documentId,
          assetId: signatureId,
          bytes: signatureBytes,
          sha256: signatureSha,
        ),
      );
      expect(
        await store.readSignature(documentId, signatureId),
        orderedEquals(signatureBytes),
      );

      final Uint8List replacementSignature = base64Decode(_validSignature3x3);
      await expectLater(
        store.writeSignature(
          WriteSignatureRequest(
            documentId: documentId,
            assetId: signatureId,
            bytes: replacementSignature,
            sha256: crypto.sha256.convert(replacementSignature).toString(),
          ),
        ),
        throwsA(isA<SecurityException>()),
      );
      expect(
        await store.readSignature(documentId, signatureId),
        orderedEquals(signatureBytes),
      );
      final LoadedDocument afterSignatureConflict = await store.loadDocument(
        documentId,
      );
      expect(
        afterSignatureConflict.meta.latestRevisionId,
        saved.latestRevisionId,
      );

      final Uint8List invalidSignature = Uint8List.fromList(
        utf8.encode('%PDF-1.7 not a PNG at all'),
      );
      await expectLater(
        store.writeSignature(
          WriteSignatureRequest(
            documentId: documentId,
            assetId: ids.newId(),
            bytes: invalidSignature,
            sha256: crypto.sha256.convert(invalidSignature).toString(),
          ),
        ),
        throwsA(isA<AndroidInvalidDataException>()),
      );
      final Uint8List truncatedSignature = Uint8List.sublistView(
        signatureBytes,
        0,
        20,
      );
      await expectLater(
        store.writeSignature(
          WriteSignatureRequest(
            documentId: documentId,
            assetId: ids.newId(),
            bytes: truncatedSignature,
            sha256: crypto.sha256.convert(truncatedSignature).toString(),
          ),
        ),
        throwsA(isA<AndroidInvalidDataException>()),
      );
      expect(
        await store.readSignature(documentId, signatureId),
        orderedEquals(signatureBytes),
      );
      final LoadedDocument afterInvalidSignature = await store.loadDocument(
        documentId,
      );
      expect(
        afterInvalidSignature.meta.latestRevisionId,
        saved.latestRevisionId,
      );

      final Uint8List boundary1024 = base64Decode(_validSignature1024);
      final String boundaryAsset = ids.newId();
      await store.writeSignature(
        WriteSignatureRequest(
          documentId: documentId,
          assetId: boundaryAsset,
          bytes: boundary1024,
          sha256: crypto.sha256.convert(boundary1024).toString(),
        ),
      );
      expect(
        await store.readSignature(documentId, boundaryAsset),
        orderedEquals(boundary1024),
      );

      final Uint8List overBoundary = base64Decode(_overLimitSignature1025);
      await expectLater(
        store.writeSignature(
          WriteSignatureRequest(
            documentId: documentId,
            assetId: ids.newId(),
            bytes: overBoundary,
            sha256: crypto.sha256.convert(overBoundary).toString(),
          ),
        ),
        throwsA(isA<AndroidInvalidDataException>()),
      );

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
    unknownFields: const <String, Object?>{
      // A representative non-integral exponent value: Dart writes `1e-7`
      // where JVM Double.toString would write `1.0E-7`. The native store must
      // re-serialize the revision content to the same canonical bytes.
      't027CanonicalProbe': 1.0000000000000002e-7,
    },
  );
}

// Real valid PNGs produced by an independent zlib/CRC encoder. They are kept
// as constants so the integration test does not duplicate production parsing
// or depend on an Android encoder through a second channel.
const String _validSignature2x2 =
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR42mMwTpv5H4QZ'
    'YAwAScgIxevRCIwAAAAASUVORK5CYII=';
const String _validSignature3x3 =
    'iVBORw0KGgoAAAANSUhEUgAAAAMAAAADCAYAAABWKLW/AAAAEUlEQVR42mMwTpv5H4YZ'
    'cHIAdSYTuuPczfEAAAAASUVORK5CYII=';
const String _validSignature1024 =
    'iVBORw0KGgoAAAANSUhEUgAABAAAAAABCAYAAABADtw1AAAAIUlEQVR42u3DAQ0AAAgD'
    'IDvZyU5Pqz0cbFRPVlVVVf39AGAOxHn43lj+AAAAAElFTkSuQmCC';
const String _overLimitSignature1025 =
    'iVBORw0KGgoAAAANSUhEUgAABAEAAAABCAYAAACvzLcLAAAAIUlEQVR42u3DAQ0AAAgD'
    'IDvZyU5Pqz0cbFRPVlVVVf3/AHZOxqqdEp2aAAAAAElFTkSuQmCC';
