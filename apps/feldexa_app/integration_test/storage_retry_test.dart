// T100 retry-after-storage-freed suite (FR-077).
//
// Run only on an exclusively allocated Android emulator:
//   flutter test integration_test/storage_retry_test.dart -d emulator-5554
//
// Lane honesty (same as T094): the Android EncryptedStore exposes no
// injectable storage-exhaustion seam, so the blocked-then-retryable behavior
// is exercised on the deterministic SIMULATED store lane
// (`SimulatedBackend.maxTotalBytes` -> SAVE-001, retry after the cap is
// raised). Per FR-088 this is SIMULATED evidence inside an EMULATOR device
// run, never Android-acceptance evidence.
//
// The blocked operation is retried with the same in-memory snapshot and the
// same expected head — no re-import and no re-entering of data (FR-077).

library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_application/src/persistence/save_document.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

SimulatedFixture _fixture() {
  final Uint8List bytes = Uint8List.fromList(
    List<int>.filled(512, 37), // '%'
  );
  return SimulatedFixture(
    id: 'sf-t100',
    role: SimulatedFixtureRole.editor,
    status: SimulatedFixtureStatus.valid,
    title: 'sf-t100',
    displayName: 't100.pdf',
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a blocked save is retryable after space is freed, without re-import',
    () async {
      final SimulatedBackend backend = SimulatedBackend(
        context: SimulatedAdapterContext(),
        maxTotalBytes: 4 << 20,
      );
      final SimulatedSecureStoreAdapter store = SimulatedSecureStoreAdapter(
        backend: backend,
      );

      // Import + initial save once.
      final SimulatedFixture fixture = _fixture();
      backend.stageSource(sourceId: backend.context.newId(), fixture: fixture);
      final SimulatedStagedSource staged = backend.stagedSources.values.last;
      final String documentId = backend.context.newId();
      final RevisionContent initial = _content();
      final StoredMeta created = await store.createDocument(
        CreateDocumentRequest(
          documentId: documentId,
          title: 'T100 Wiederholung',
          source: SourceFileRef(
            id: staged.sourceId,
            sha256: staged.sha256,
            sizeBytes: staged.bytes.length,
            pageCount: staged.pageCount,
            importedAt: backend.context.nowUtc(),
          ),
          initialRevision: Revision(
            id: backend.context.newId(),
            documentId: documentId,
            kind: RevisionKind.explicit,
            createdAt: backend.context.nowUtc(),
            plaintextSha256: crypto.sha256
                .convert(canonicalJsonBytes(initial.toJson()))
                .toString(),
            content: initial,
          ),
        ),
      );

      // The user keeps editing in memory; the next save hits a full store.
      final RevisionContent pending = _content();
      backend.maxTotalBytes = backend.totalBytes;

      final SaveDocumentResult blocked = await saveDocument(
        store: store,
        documentId: documentId,
        expectedHead: created.latestRevisionId,
        content: pending,
        kind: RevisionKind.autosave,
      );
      expect(blocked.isSuccess, isFalse);
      expect(blocked.errorCode, 'SAVE-001');
      expect(blocked.meta, isNull);

      // The user frees space: the logical cap is raised. Nothing was
      // re-imported — the staged source is still the original object.
      backend.maxTotalBytes = backend.totalBytes + (1 << 20);
      expect(backend.stagedSources[staged.sourceId], isNotNull);

      // The exact same operation — same snapshot, same expected head, same
      // document — now succeeds. No re-import, no re-entering of data.
      final SaveDocumentResult retried = await saveDocument(
        store: store,
        documentId: documentId,
        expectedHead: created.latestRevisionId,
        content: pending,
        kind: RevisionKind.autosave,
      );
      expect(retried.isSuccess, isTrue);
      expect(retried.errorCode, isNull);
      expect(retried.meta!.latestRevisionId, isNot(created.latestRevisionId));

      final LoadedDocument loaded = await store.loadDocument(documentId);
      expect(loaded.meta.latestRevisionId, retried.meta!.latestRevisionId);
      expect(loaded.sourceBytes, _fixture().bytes);
    },
  );

  test('a blocked first save of a fresh session retried after freeing keeps the aggregate intact', () async {
    final SimulatedBackend backend = SimulatedBackend(
      context: SimulatedAdapterContext(),
      maxTotalBytes: 4 << 20,
    );
    final SimulatedSecureStoreAdapter store = SimulatedSecureStoreAdapter(
      backend: backend,
    );

    final SimulatedFixture fixture = _fixture();
    backend.stageSource(sourceId: backend.context.newId(), fixture: fixture);
    final SimulatedStagedSource staged = backend.stagedSources.values.last;
    final String documentId = backend.context.newId();
    final StoredMeta created = await store.createDocument(
      CreateDocumentRequest(
        documentId: documentId,
        title: 'T100 zweite Runde',
        source: SourceFileRef(
          id: staged.sourceId,
          sha256: staged.sha256,
          sizeBytes: staged.bytes.length,
          pageCount: staged.pageCount,
          importedAt: backend.context.nowUtc(),
        ),
        initialRevision: Revision(
          id: backend.context.newId(),
          documentId: documentId,
          kind: RevisionKind.explicit,
          createdAt: backend.context.nowUtc(),
          plaintextSha256: crypto.sha256
              .convert(canonicalJsonBytes(_content().toJson()))
              .toString(),
          content: _content(),
        ),
      ),
    );

    // Block the write, verify the failure, free space, retry twice: each
    // retry is independent and idempotent from the caller's perspective.
    backend.maxTotalBytes = backend.totalBytes;
    await expectLater(
      store.saveRevision(
        SaveRevisionRequest(
          documentId: documentId,
          expectedHead: created.latestRevisionId,
          content: _content(),
          kind: RevisionKind.autosave,
        ),
      ),
      throwsA(isA<StorageFullException>()),
    );

    backend.maxTotalBytes = backend.totalBytes + (1 << 20);
    final StoredMeta first = await store.saveRevision(
      SaveRevisionRequest(
        documentId: documentId,
        expectedHead: created.latestRevisionId,
        content: _content(),
        kind: RevisionKind.autosave,
      ),
    );
    final StoredMeta second = await store.saveRevision(
      SaveRevisionRequest(
        documentId: documentId,
        expectedHead: first.latestRevisionId,
        content: _content(),
        kind: RevisionKind.autosave,
      ),
    );
    expect(second.latestRevisionId, isNot(first.latestRevisionId));
  });
}
