// T028 SIMULATED secure-store adapter tests.
//
// Host-VM evidence only. The adapter is explicitly not encryption and makes no
// Android Keystore claim; these tests cover the observable port semantics.

import 'dart:typed_data';

import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:feldexa_testkit/feldexa_testkit.dart' show sha256Hex;
import 'package:flutter_test/flutter_test.dart';

import 'support/simulated_world.dart';

void main() {
  late SimulatedFixtureCatalog catalog;

  setUpAll(() async {
    catalog = await loadCatalog();
  });

  test('descriptor is SIMULATED secure storage', () async {
    final world = await SimulatedTestWorld.create();
    final descriptor = world.storeAdapter.descriptor;
    expect(descriptor.kind, CapabilityKind.secureStore);
    expect(descriptor.isSimulated, isTrue);
    expect(descriptor.evidence.evidenceClass, EvidenceClass.simulated);
    expect(descriptor.adapterId, simulatedStoreAdapterId);
  });

  test('creates, saves, and loads a verified document revision', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-001');
    final saved = await world.createSavedDocument(imported);
    expect(saved.documentId, imported.documentId);
    final LoadedDocument loaded = await world.storeAdapter.loadDocument(
      saved.documentId,
    );
    expect(loaded.meta.title, 'Simulierte Meldebescheinigung');
    expect(loaded.content.pageCount, 2);
    expect(loaded.content.pages.length, 2);
    expect(loaded.sourceBytes, orderedEquals(catalog.fixture('sf-001').bytes));
    expect(loaded.evidence.evidenceClass, EvidenceClass.simulated);
    expect(loaded.meta.latestRevisionId, saved.revisionId);

    final RecoveryStamp stamp = await world.storeAdapter.recoveryStamp(
      saved.documentId,
      StoreKind.document,
    );
    expect(stamp.verifiedRevisionId, saved.revisionId);
    expect(stamp.headCorrupt, isFalse);
    expect(stamp.fellBackToOlderRevision, isFalse);
  });

  test('a wrong expectedHead is refused and the head is unchanged', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final saved = await world.createSavedDocument(imported);
    await expectLater(
      world.storeAdapter.saveRevision(
        SaveRevisionRequest(
          documentId: saved.documentId,
          expectedHead: '00000000-0000-4000-8000-000000000999',
          content: world.simpleRevisionContent(imported),
          kind: RevisionKind.autosave,
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    final record = world.backend.document(saved.documentId)!;
    expect(record.head, saved.revisionId);
  });

  test(
    'retention keeps head + newest explicit/recovery + last 3 autosaves',
    () async {
      final world = await SimulatedTestWorld.create();
      final imported = await world.importFixture('sf-004');
      final source = world.sourceRefFor(imported);
      final created = await world.storeAdapter.createDocument(
        CreateDocumentRequest(title: 'Retention', source: source),
      );
      final content = world.simpleRevisionContent(imported);

      Future<String> save(RevisionKind kind) async {
        final String? head = world.backend.document(created.id)!.head;
        final StoredMeta meta = await world.storeAdapter.saveRevision(
          SaveRevisionRequest(
            documentId: created.id,
            expectedHead: head,
            content: content,
            kind: kind,
          ),
        );
        return meta.latestRevisionId!;
      }

      for (int index = 0; index < 5; index++) {
        await save(RevisionKind.autosave);
      }
      await save(RevisionKind.explicit);
      await save(RevisionKind.explicit);
      await save(RevisionKind.recovery);
      for (int index = 0; index < 4; index++) {
        await save(RevisionKind.autosave);
      }

      final record = world.backend.document(created.id)!;
      final revisions = record.revisions.values.toList(growable: false);
      final autosaves = revisions
          .where((r) => r.kind == RevisionKind.autosave)
          .toList(growable: false);
      final explicit = revisions
          .where((r) => r.kind == RevisionKind.explicit)
          .toList(growable: false);
      final recovery = revisions
          .where((r) => r.kind == RevisionKind.recovery)
          .toList(growable: false);
      expect(autosaves.length, 3);
      expect(explicit.length, 1);
      expect(recovery.length, 1);
      expect(record.revisions.containsKey(record.head), isTrue);
      expect(revisions.length, 5);
    },
  );

  test(
    'a failed staged write throws SAVE-003 and preserves the head',
    () async {
      final world = await SimulatedTestWorld.create();
      final imported = await world.importFixture('sf-004');
      final saved = await world.createSavedDocument(imported);
      final record = world.backend.document(saved.documentId)!;
      final int before = record.revisions.length;
      world.storeAdapter.failNextWrite();
      await expectLater(
        world.storeAdapter.saveRevision(
          SaveRevisionRequest(
            documentId: saved.documentId,
            expectedHead: record.head,
            content: world.simpleRevisionContent(imported),
            kind: RevisionKind.autosave,
          ),
        ),
        throwsA(
          isA<StorageWriteException>()
              .having((e) => e.code, 'code', 'SAVE-003')
              .having((e) => e.retryable, 'retryable', isTrue),
        ),
      );
      expect(record.head, saved.revisionId);
      expect(record.revisions.length, before);
    },
  );

  test('a failed read-back throws SAVE-003 without moving the head', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final saved = await world.createSavedDocument(imported);
    final record = world.backend.document(saved.documentId)!;
    final int before = record.revisions.length;
    world.storeAdapter.corruptNextCommit();
    await expectLater(
      world.storeAdapter.saveRevision(
        SaveRevisionRequest(
          documentId: saved.documentId,
          expectedHead: record.head,
          content: world.simpleRevisionContent(imported),
          kind: RevisionKind.autosave,
        ),
      ),
      throwsA(
        isA<CorruptDataException>().having((e) => e.code, 'code', 'SAVE-003'),
      ),
    );
    expect(record.head, saved.revisionId);
    expect(record.revisions.length, before);
  });

  test('capacity exhaustion throws SAVE-001 before the head moves', () async {
    final world = await SimulatedTestWorld.create(maxTotalBytes: 100);
    final imported = await world.importFixture('sf-004');
    final source = world.sourceRefFor(imported);
    final created = await world.storeAdapter.createDocument(
      CreateDocumentRequest(title: 'Cap', source: source),
    );
    await expectLater(
      world.storeAdapter.saveRevision(
        SaveRevisionRequest(
          documentId: created.id,
          content: world.simpleRevisionContent(imported),
          kind: RevisionKind.explicit,
        ),
      ),
      throwsA(
        isA<StorageFullException>()
            .having((e) => e.code, 'code', 'SAVE-001')
            .having((e) => e.retryable, 'retryable', isTrue),
      ),
    );
    expect(world.backend.document(created.id)!.head, isNull);
  });

  test('global SAVE-008 blocks new document and template aggregates', () async {
    final world = await SimulatedTestWorld.create();
    final fixture = catalog.fixture('sf-004');
    final staged = world.backend.stageSource(
      sourceId: world.backend.context.newId(),
      fixture: fixture,
    );
    final SourceFileRef source = SourceFileRef(
      id: staged.sourceId,
      sha256: staged.sha256,
      sizeBytes: staged.bytes.length,
      pageCount: staged.pageCount,
      importedAt: world.backend.context.nowUtc(),
    );
    world.storeAdapter.simulateGlobalKeyUnavailable();
    await expectLater(
      world.storeAdapter.createDocument(
        CreateDocumentRequest(title: 'Nicht sichtbar', source: source),
      ),
      throwsA(
        isA<KeystoreUnavailableException>().having(
          (e) => e.code,
          'code',
          'SAVE-008',
        ),
      ),
    );
    await expectLater(
      world.storeAdapter.createTemplate(
        CreateTemplateRequest(
          title: 'Nicht sichtbar',
          source: source,
          pages: <Page>[Page(index: 0, geometry: fixture.geometries.first)],
          fieldOrder: const <String>[],
        ),
      ),
      throwsA(
        isA<KeystoreUnavailableException>().having(
          (e) => e.code,
          'code',
          'SAVE-008',
        ),
      ),
    );
    expect(world.backend.documents, isEmpty);
    expect(world.backend.templates, isEmpty);
    final StoreStatus status = await world.storeAdapter.status();
    expect(status.keyAvailable, isFalse);
  });

  test(
    'aggregate key loss is SAVE-002 and leaves other documents usable',
    () async {
      final world = await SimulatedTestWorld.create();
      final first = await world.importFixture('sf-001');
      final second = await world.importFixture('sf-004');
      final savedFirst = await world.createSavedDocument(first);
      final savedSecond = await world.createSavedDocument(second);

      world.storeAdapter.simulateAggregateKeyLoss(savedFirst.documentId);
      await expectLater(
        world.storeAdapter.loadDocument(savedFirst.documentId),
        throwsA(
          isA<KeyUnavailableException>()
              .having((e) => e.code, 'code', 'SAVE-002')
              .having((e) => e.retryable, 'retryable', isFalse),
        ),
      );
      final LoadedDocument stillReadable = await world.storeAdapter
          .loadDocument(savedSecond.documentId);
      expect(stillReadable.content.pageCount, 1);

      final List<StoredMeta> listed = await world.storeAdapter.list(
        StoreKind.document,
      );
      final StoredMeta unreadable = listed.firstWhere(
        (StoredMeta meta) => meta.id == savedFirst.documentId,
      );
      expect(unreadable.readable, isFalse);
      expect(unreadable.title, simulatedUnreadableTitle);
      expect(unreadable.unreadableReasonCode, 'SAVE-002');
      final StoreStatus status = await world.storeAdapter.status();
      expect(status.keyAvailable, isFalse);
      expect(status.evidence.evidenceClass, EvidenceClass.simulated);
    },
  );

  test('global key loss is SAVE-008 for every aggregate', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-001');
    final saved = await world.createSavedDocument(imported);
    world.storeAdapter.simulateGlobalKeyUnavailable();
    await expectLater(
      world.storeAdapter.loadDocument(saved.documentId),
      throwsA(
        isA<KeystoreUnavailableException>().having(
          (e) => e.code,
          'code',
          'SAVE-008',
        ),
      ),
    );
    final List<StoredMeta> listed = await world.storeAdapter.list(
      StoreKind.document,
    );
    expect(listed.single.unreadableReasonCode, 'SAVE-008');
    expect(listed.single.title, simulatedUnreadableTitle);
    world.storeAdapter.restoreGlobalKey();
    final LoadedDocument recovered = await world.storeAdapter.loadDocument(
      saved.documentId,
    );
    expect(recovered.content.pageCount, 2);
  });

  test('signature assets are hash-checked and readable', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final saved = await world.createSavedDocument(imported);
    final assetId = world.backend.context.newId();
    final bytes = Uint8List.fromList(<int>[9, 8, 7, 6]);
    final String hash = sha256Hex(bytes);
    await world.storeAdapter.writeSignature(
      WriteSignatureRequest(
        documentId: saved.documentId,
        assetId: assetId,
        bytes: bytes,
        sha256: hash,
      ),
    );
    final Uint8List read = await world.storeAdapter.readSignature(
      saved.documentId,
      assetId,
    );
    expect(read, orderedEquals(bytes));

    await expectLater(
      world.storeAdapter.writeSignature(
        WriteSignatureRequest(
          documentId: saved.documentId,
          assetId: world.backend.context.newId(),
          bytes: bytes,
          sha256: '0' * 64,
        ),
      ),
      throwsA(isA<SecurityException>()),
    );
    await expectLater(
      world.storeAdapter.readSignature(
        saved.documentId,
        '00000000-0000-4000-8000-000000000999',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('delete requires an acknowledged matching title', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final saved = await world.createSavedDocument(imported, title: 'Löschbar');

    await expectLater(
      world.storeAdapter.delete(
        StoreKind.document,
        saved.documentId,
        DeleteConfirmation(title: 'Löschbar', acknowledged: false),
      ),
      throwsA(isA<SecurityException>()),
    );
    await expectLater(
      world.storeAdapter.delete(
        StoreKind.document,
        saved.documentId,
        DeleteConfirmation(title: 'Falsch', acknowledged: true),
      ),
      throwsA(isA<SecurityException>()),
    );
    await world.storeAdapter.delete(
      StoreKind.document,
      saved.documentId,
      DeleteConfirmation(title: 'Löschbar', acknowledged: true),
    );
    expect(await world.storeAdapter.list(StoreKind.document), isEmpty);
  });

  test(
    'an unreadable aggregate is deleted with the placeholder title',
    () async {
      final world = await SimulatedTestWorld.create();
      final imported = await world.importFixture('sf-004');
      final saved = await world.createSavedDocument(imported);
      world.storeAdapter.simulateAggregateKeyLoss(saved.documentId);
      await world.storeAdapter.delete(
        StoreKind.document,
        saved.documentId,
        DeleteConfirmation(title: simulatedUnreadableTitle, acknowledged: true),
      );
      expect(world.backend.document(saved.documentId), isNull);
    },
  );

  test('template versions are immutable, loadable, and never pruned', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final source = world.sourceRefFor(imported);
    final created = await world.storeAdapter.createTemplate(
      CreateTemplateRequest(
        title: 'Vorlage',
        source: source,
        pages: <Page>[Page(index: 0, geometry: imported.pages.first)],
        fieldOrder: const <String>[],
      ),
    );
    expect(created.latestRevisionId, isNotNull);
    final String firstVersion = created.latestRevisionId!;

    final LoadedTemplate first = await world.storeAdapter.loadTemplate(
      created.id,
    );
    expect(first.template.version.versionNumber, 1);
    expect(first.template.meta.id, created.id);
    expect(first.sourceBytes, orderedEquals(catalog.fixture('sf-004').bytes));
    expect(first.evidence.evidenceClass, EvidenceClass.simulated);

    String head = firstVersion;
    for (int index = 0; index < 4; index++) {
      final StoredMeta meta = await world.storeAdapter.saveTemplateVersion(
        SaveTemplateVersionRequest(
          templateId: created.id,
          expectedHead: head,
          pageSnapshot: <Page>[Page(index: 0, geometry: imported.pages.first)],
        ),
      );
      head = meta.latestRevisionId!;
    }
    final LoadedTemplate latest = await world.storeAdapter.loadTemplate(
      created.id,
    );
    expect(latest.template.version.versionNumber, 5);
    final LoadedTemplate pinned = await world.storeAdapter.loadTemplate(
      created.id,
      versionId: firstVersion,
    );
    expect(pinned.template.version.versionNumber, 1);
    expect(world.backend.template(created.id)!.versions.length, 5);
  });

  test(
    'a failed template read-back leaves the previous version head intact',
    () async {
      final world = await SimulatedTestWorld.create();
      final imported = await world.importFixture('sf-004');
      final source = world.sourceRefFor(imported);
      final created = await world.storeAdapter.createTemplate(
        CreateTemplateRequest(
          title: 'Vorlage',
          source: source,
          pages: <Page>[Page(index: 0, geometry: imported.pages.first)],
          fieldOrder: const <String>[],
        ),
      );
      final String firstVersion = created.latestRevisionId!;
      world.storeAdapter.corruptNextCommit();
      await expectLater(
        world.storeAdapter.saveTemplateVersion(
          SaveTemplateVersionRequest(
            templateId: created.id,
            expectedHead: firstVersion,
            pageSnapshot: <Page>[
              Page(index: 0, geometry: imported.pages.first),
            ],
          ),
        ),
        throwsA(isA<CorruptDataException>()),
      );
      final record = world.backend.template(created.id)!;
      expect(record.head, firstVersion);
      expect(record.versions.length, 1);
    },
  );

  test('status reports deterministic object counts and bytes', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-001');
    await world.createSavedDocument(imported);
    final StoreStatus first = await world.storeAdapter.status();
    final StoreStatus second = await world.storeAdapter.status();
    expect(first.objectCount, second.objectCount);
    expect(first.totalBytes, second.totalBytes);
    expect(first.objectCount, greaterThan(0));
    expect(first.totalBytes, greaterThan(catalog.fixture('sf-001').sizeBytes));
    expect(first.keyAvailable, isTrue);
  });
}
