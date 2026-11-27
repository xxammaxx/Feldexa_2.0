// T094 storage-exhaustion suite: no success report on a blocked save
// (FR-074/FR-075/FR-076; SC-010).
//
// Run only on an exclusively allocated Android emulator:
//   flutter test integration_test/storage_full_test.dart -d emulator-5554
//
// Lane honesty: the Android EncryptedStore offers no injectable
// storage-exhaustion seam, and a real disk-full cannot be induced safely on a
// shared emulator. The exhaustion behavior is therefore exercised on the
// deterministic SIMULATED store lane (`SimulatedBackend.maxTotalBytes` ->
// `StorageFullException` SAVE-001), which is the committed, reviewed seam for
// exactly this contract (simulated_backend.dart: "Storage exhaustion is the
// canonical StorageFullException (SAVE-001)"). Per FR-088 this is not
// Android-acceptance evidence; the finding is reported with the SIMULATED
// evidence class inside an EMULATOR device run.
//
// The suite drives the production `saveDocument` use case (T090) so the
// assertion covers the user-visible contract: a failure carries only the
// stable catalog code and never success metadata.
//
// German catalog reference (contracts/error-catalog.de.md §3, SAVE-001):
// „Der Speicherplatz reicht nicht aus. Der letzte gespeicherte Stand ist
// erhalten; die neuesten Änderungen sind noch nicht dauerhaft gespeichert.“

library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_application/src/persistence/save_document.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const int _mebi = 1024 * 1024;

SimulatedFixture _fixture(String id, int sizeBytes) {
  final Uint8List bytes = Uint8List.fromList(List<int>.filled(sizeBytes, 37));
  return SimulatedFixture(
    id: id,
    role: SimulatedFixtureRole.editor,
    status: SimulatedFixtureStatus.valid,
    title: id,
    displayName: '$id.pdf',
    bytes: bytes,
    sha256: crypto.sha256.convert(bytes).toString(),
    sizeBytes: bytes.length,
    pages: <SimulatedFixturePage>[
      const SimulatedFixturePage(
        index: 0,
        widthPt: 595,
        heightPt: 842,
        rotation: 0,
      ),
    ],
    expectedOcr: const <SimulatedOcrPage>[],
    expectedErrorCode: null,
  );
}

RevisionContent _content() => RevisionContent(
  pages: <Page>[
    Page(
      index: 0,
      geometry: PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842)),
    ),
  ],
  fieldOrder: const <String>[],
);

Revision _initialRevision(SimulatedBackend backend, String documentId) {
  final RevisionContent content = _content();
  return Revision(
    id: backend.context.newId(),
    documentId: documentId,
    kind: RevisionKind.explicit,
    createdAt: backend.context.nowUtc(),
    plaintextSha256: crypto.sha256
        .convert(canonicalJsonBytes(content.toJson()))
        .toString(),
    content: content,
  );
}

Future<StoredMeta> _seed(
  SimulatedSecureStoreAdapter store,
  SimulatedBackend backend,
  String title,
) async {
  backend.stageSource(
    sourceId: backend.context.newId(),
    fixture: _fixture('sf-t094', 512),
  );
  final SimulatedStagedSource staged = backend.stagedSources.values.last;
  final String documentId = backend.context.newId();
  return store.createDocument(
    CreateDocumentRequest(
      documentId: documentId,
      title: title,
      source: SourceFileRef(
        id: staged.sourceId,
        sha256: staged.sha256,
        sizeBytes: staged.bytes.length,
        pageCount: staged.pageCount,
        importedAt: backend.context.nowUtc(),
      ),
      initialRevision: _initialRevision(backend, documentId),
    ),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a blocked save reports SAVE-001 and never success (FR-074/FR-075; SC-010)',
    () async {
      // One 1 MiB logical capacity: the seeded aggregate fits, the next
      // revision body does not.
      final SimulatedBackend backend = SimulatedBackend(
        context: SimulatedAdapterContext(),
        maxTotalBytes: _mebi,
      );
      final SimulatedSecureStoreAdapter store = SimulatedSecureStoreAdapter(
        backend: backend,
      );
      final StoredMeta meta = await _seed(store, backend, 'T094 Voll');

      backend.maxTotalBytes = backend.totalBytes + 1;

      // The canonical adapter path blocks the write and preserves the head.
      await expectLater(
        store.saveRevision(
          SaveRevisionRequest(
            documentId: meta.id,
            expectedHead: meta.latestRevisionId,
            content: _content(),
            kind: RevisionKind.autosave,
          ),
        ),
        throwsA(
          isA<StorageFullException>().having(
            (StorageFullException e) => e.code,
            'code',
            'SAVE-001',
          ),
        ),
      );

      // The production use case reports failure without any success metadata.
      final SaveDocumentResult result = await saveDocument(
        store: store,
        documentId: meta.id,
        expectedHead: meta.latestRevisionId,
        content: _content(),
        kind: RevisionKind.autosave,
      );
      expect(result.isSuccess, isFalse);
      expect(result.errorCode, 'SAVE-001');
      expect(result.meta, isNull);

      // FR-075: the last successfully saved state remains intact.
      final LoadedDocument loaded = await store.loadDocument(meta.id);
      expect(loaded.meta.latestRevisionId, meta.latestRevisionId);
      expect(loaded.meta.readable, isTrue);

      // FR-076: no document is deleted to free space.
      final List<StoredMeta> listed = await store.list(StoreKind.document);
      expect(listed.map((StoredMeta item) => item.id), contains(meta.id));
    },
  );

  test('exhaustion leaves the staged source and aggregate objects untouched (FR-075)', () async {
    final SimulatedBackend backend = SimulatedBackend(
      context: SimulatedAdapterContext(),
      maxTotalBytes: _mebi,
    );
    final SimulatedSecureStoreAdapter store = SimulatedSecureStoreAdapter(
      backend: backend,
    );
    final StoredMeta meta = await _seed(store, backend, 'T094 unberührt');
    final Uint8List stagedBefore = Uint8List.fromList(
      backend.readStagedSource(backend.stagedSources.values.last.sourceId)!,
    );

    backend.maxTotalBytes = backend.totalBytes;

    await expectLater(
      store.saveRevision(
        SaveRevisionRequest(
          documentId: meta.id,
          expectedHead: meta.latestRevisionId,
          content: _content(),
          kind: RevisionKind.autosave,
        ),
      ),
      throwsA(isA<StorageFullException>()),
    );

    // Objects are byte-identical after the blocked write.
    final Uint8List stagedAfter = backend.readStagedSource(
      backend.stagedSources.values.last.sourceId,
    )!;
    expect(stagedAfter, stagedBefore);
    final SimulatedDocumentRecord? record = backend.document(meta.id);
    expect(record, isNotNull);
    expect(record!.head, meta.latestRevisionId);
    expect(record.revisions.length, 1);
  });
}
