// T101 SIMULATED browser persistence and recovery suite (FR-086/FR-087).
//
// The suite is platform-agnostic (no `@TestOn('browser')`), so it runs on the
// host VM (evidence NONE) and, when Chrome is available, in the browser lane
// (evidence SIMULATED); without Chrome the browser run is NOT_RUN. It lives
// under `test/` because Flutter 3.47.7 roots Chrome browser tests at
// `<project>/test` (same measured T062 constraint as T072/T087); the T101 row
// path `integration_test/web_persistence_test.dart` hosts the identical
// suite and runs on the host VM.
//
// Persistence model of the SIMULATED lane: `SimulatedBackend` is the
// deterministic in-memory backing store a Web build keeps for the lifetime of
// the tab/session. A browser reload keeps that backing store and re-creates
// the adapters over it. The suite models exactly that recovery: save, then
// construct a fresh adapter over the same backend, and recover the saved
// document without any re-import.
//
// Normative sources: `spec.md` FR-086/FR-087/FR-088;
// `contracts/error-catalog.de.md` §6 (SIMULATED banner text);
// `simulated_store_adapter.dart` header note ("may be persisted only for
// reload tests").

library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';

SimulatedBackend _backend() => SimulatedBackend(
  context: SimulatedAdapterContext(),
  maxTotalBytes: 4 << 20,
);

SimulatedFixture _fixture() {
  const List<int> bytes = <int>[
    37, 80, 68, 70, 45, 49, 46, 55, 10, // %PDF-1.7
  ];
  final Uint8List data = Uint8List.fromList(bytes);
  return SimulatedFixture(
    id: 'sf-t101',
    role: SimulatedFixtureRole.editor,
    status: SimulatedFixtureStatus.valid,
    title: 'T101 Browser Persistence',
    displayName: 't101.pdf',
    bytes: data,
    sha256: crypto.sha256.convert(data).toString(),
    sizeBytes: data.length,
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

RevisionContent _content(int pageGeometryScale) => RevisionContent(
  pages: <Page>[
    Page(
      index: 0,
      geometry: PageGeometry(
        mediaBox: Rect.fromLTWH(0, 0, 595.0 * pageGeometryScale, 842.0),
      ),
    ),
  ],
  fieldOrder: const <String>[],
);

Revision _initialRevision(SimulatedBackend backend, String documentId) {
  final RevisionContent content = _content(1);
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

SourceFileRef _sourceRef(SimulatedBackend backend, SimulatedFixture fixture) {
  backend.stageSource(sourceId: backend.context.newId(), fixture: fixture);
  final SimulatedStagedSource staged = backend.stagedSources.values.last;
  return SourceFileRef(
    id: staged.sourceId,
    sha256: staged.sha256,
    sizeBytes: staged.bytes.length,
    pageCount: staged.pageCount,
    importedAt: backend.context.nowUtc(),
  );
}

Future<StoredMeta> _createDocument(
  SimulatedSecureStoreAdapter store,
  SimulatedBackend backend,
  SimulatedFixture fixture, {
  required String title,
}) {
  final String documentId = backend.context.newId();
  return store.createDocument(
    CreateDocumentRequest(
      documentId: documentId,
      title: title,
      source: _sourceRef(backend, fixture),
      initialRevision: _initialRevision(backend, documentId),
    ),
  );
}

void main() {
  test('a saved document survives a simulated reload and recovers without re-import', () async {
    final SimulatedBackend backend = _backend();
    final SimulatedFixture fixture = _fixture();
    final SimulatedSecureStoreAdapter first = SimulatedSecureStoreAdapter(
      backend: backend,
    );

    final StoredMeta created = await _createDocument(
      first,
      backend,
      fixture,
      title: 'T101 Wiederherstellung',
    );
    expect(created.readable, isTrue);

    // "Reload": the browser keeps the backing store and re-creates the
    // adapters. No re-import, no re-entering of data.
    final SimulatedSecureStoreAdapter reloaded = SimulatedSecureStoreAdapter(
      backend: backend,
    );

    final LoadedDocument recovered = await reloaded.loadDocument(created.id);
    expect(recovered.meta.id, created.id);
    expect(recovered.meta.title, 'T101 Wiederherstellung');
    expect(recovered.meta.latestRevisionId, created.latestRevisionId);
    expect(recovered.meta.readable, isTrue);
    expect(recovered.sourceBytes, _fixture().bytes);

    final List<StoredMeta> listed = await reloaded.list(StoreKind.document);
    expect(listed.map((StoredMeta meta) => meta.id), contains(created.id));

    final RecoveryStamp stamp = await reloaded.recoveryStamp(
      created.id,
      StoreKind.document,
    );
    expect(stamp.verifiedRevisionId, created.latestRevisionId);
    expect(stamp.headCorrupt, isFalse);
    expect(stamp.fellBackToOlderRevision, isFalse);
  });

  test(
    'an autosave revision committed before the reload is also recovered',
    () async {
      final SimulatedBackend backend = _backend();
      final SimulatedFixture fixture = _fixture();
      final SimulatedSecureStoreAdapter first = SimulatedSecureStoreAdapter(
        backend: backend,
      );
      final StoredMeta created = await _createDocument(
        first,
        backend,
        fixture,
        title: 'T101 Autosave',
      );

      final StoredMeta saved = await first.saveRevision(
        SaveRevisionRequest(
          documentId: created.id,
          expectedHead: created.latestRevisionId,
          content: _content(2),
          kind: RevisionKind.autosave,
        ),
      );
      expect(saved.latestRevisionId, isNot(created.latestRevisionId));

      final SimulatedSecureStoreAdapter reloaded = SimulatedSecureStoreAdapter(
        backend: backend,
      );
      final LoadedDocument recovered = await reloaded.loadDocument(created.id);
      expect(recovered.meta.latestRevisionId, saved.latestRevisionId);
      expect(
        recovered.content.pages.first.geometry.displaySize.width,
        595.0 * 2,
      );
    },
  );

  test(
    'a fresh session without persisted state starts empty and deterministic',
    () async {
      // A brand-new tab has no backing store: a new backend is empty, and two
      // fresh sessions with identical inputs produce identical results
      // (FR-087 determinism).
      final SimulatedBackend empty = _backend();
      final SimulatedSecureStoreAdapter fresh = SimulatedSecureStoreAdapter(
        backend: empty,
      );
      expect(await fresh.list(StoreKind.document), isEmpty);
      expect(await fresh.list(StoreKind.template), isEmpty);
      expect(
        () => fresh.loadDocument('00000000-0000-4000-8000-000000000001'),
        throwsArgumentError,
      );

      final SimulatedBackend sessionA = _backend();
      final SimulatedBackend sessionB = _backend();
      for (final SimulatedBackend backend in <SimulatedBackend>[
        sessionA,
        sessionB,
      ]) {
        final SimulatedSecureStoreAdapter store = SimulatedSecureStoreAdapter(
          backend: backend,
        );
        await _createDocument(
          store,
          backend,
          _fixture(),
          title: 'Determinismus',
        );
      }
      expect(
        sessionA.documents.keys.toList(),
        sessionB.documents.keys.toList(),
        reason: 'the deterministic context yields the same id sequence',
      );
      expect(
        sessionA.documents.values.first.head,
        sessionB.documents.values.first.head,
      );
    },
  );
}
