// T028 SIMULATED import adapter tests.
//
// Every assertion here is host-VM evidence; the result labels are `SIMULATED`.

import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/simulated_world.dart';

void main() {
  late SimulatedFixtureCatalog catalog;

  setUpAll(() async {
    catalog = await loadCatalog();
  });

  test(
    'descriptor is SIMULATED and identifies the import capability',
    () async {
      final world = await SimulatedTestWorld.create();
      final descriptor = world.importAdapter.descriptor;
      expect(descriptor.kind, CapabilityKind.documentImport);
      expect(descriptor.isSimulated, isTrue);
      expect(descriptor.evidence.simulated, isTrue);
      expect(descriptor.evidence.evidenceClass, EvidenceClass.simulated);
      expect(descriptor.adapterId, simulatedImportAdapterId);
      expect(descriptor.evidence.simulatedReason, simulatedReasonToken);
    },
  );

  test('imports a valid fixture, stages it, and verifies the hash', () async {
    final world = await SimulatedTestWorld.create();
    final ImportedSource imported = await world.importFixture('sf-001');
    final SimulatedFixture fixture = catalog.fixture('sf-001');

    expect(imported.sha256, fixture.sha256);
    expect(imported.sizeBytes, fixture.sizeBytes);
    expect(imported.pageCount, 2);
    expect(imported.pageFailures, isEmpty);
    expect(imported.displayName, 'sf-001.pdf');
    expect(imported.evidence.evidenceClass, EvidenceClass.simulated);
    expect(imported.evidence.simulated, isTrue);

    final staged = world.backend.stagedSource(imported.sourceId);
    expect(staged, isNotNull);
    expect(staged!.sha256, fixture.sha256);
    expect(staged.bytes.length, fixture.sizeBytes);
    final SimulatedDocumentRecord aggregate =
        world.backend.documents[imported.documentId]!;
    expect(aggregate.source.id, imported.sourceId);
    expect(aggregate.head, isNull);
    expect(aggregate.title, isNotEmpty);

    final SourceIntegrity verified = await world.importAdapter.verifySource(
      imported.sourceId,
    );
    expect(verified.readable, isTrue);
    expect(verified.actualSha256, fixture.sha256);
    expect(verified.pageCount, 2);
    expect(verified.evidence.evidenceClass, EvidenceClass.simulated);
  });

  test('imports every valid fixture with its catalogue page count', () async {
    final world = await SimulatedTestWorld.create();
    for (final String id in <String>['sf-001', 'sf-002', 'sf-003', 'sf-004']) {
      final ImportedSource imported = await world.importFixture(id);
      expect(imported.pageCount, catalog.fixture(id).pageCount, reason: id);
      expect(imported.pages.length, imported.pageCount, reason: id);
    }
  });

  test('password-protected fixture maps to IMP-001', () async {
    final world = await SimulatedTestWorld.create();
    world.importAdapter.picker.enqueueFixture('sf-protected');
    await expectLater(
      world.importAdapter.pickAndImport(ImportRequest()),
      throwsA(
        isA<ImportRejectedException>()
            .having(
              (e) => e.kind,
              'kind',
              ImportRejectionKind.passwordProtected,
            )
            .having((e) => e.code, 'code', 'IMP-001'),
      ),
    );
    expect(world.backend.stagedSources, isEmpty);
  });

  test('truncated fixture maps to IMP-002', () async {
    final world = await SimulatedTestWorld.create();
    world.importAdapter.picker.enqueueFixture('sf-truncated');
    await expectLater(
      world.importAdapter.pickAndImport(ImportRequest()),
      throwsA(
        isA<ImportRejectedException>()
            .having((e) => e.kind, 'kind', ImportRejectionKind.truncated)
            .having((e) => e.code, 'code', 'IMP-002'),
      ),
    );
    expect(world.backend.stagedSources, isEmpty);
  });

  test('non-PDF fixture maps to IMP-004', () async {
    final world = await SimulatedTestWorld.create();
    world.importAdapter.picker.enqueueFixture('sf-not-a-pdf');
    await expectLater(
      world.importAdapter.pickAndImport(ImportRequest()),
      throwsA(
        isA<ImportRejectedException>()
            .having((e) => e.kind, 'kind', ImportRejectionKind.notPdf)
            .having((e) => e.code, 'code', 'IMP-004'),
      ),
    );
    expect(world.backend.stagedSources, isEmpty);
  });

  test('cancellation throws IMP-000 and stages nothing', () async {
    final world = await SimulatedTestWorld.create();
    world.importAdapter.picker.enqueueCancel();
    await expectLater(
      world.importAdapter.pickAndImport(ImportRequest()),
      throwsA(
        isA<ImportCancelledException>()
            .having((e) => e.code, 'code', 'IMP-000')
            .having((e) => e.retryable, 'retryable', isTrue),
      ),
    );
    expect(world.backend.stagedSources, isEmpty);
    expect(world.backend.documents, isEmpty);
  });

  test('an empty picker is a cancellation, never an invented import', () async {
    final world = await SimulatedTestWorld.create();
    await expectLater(
      world.importAdapter.pickAndImport(ImportRequest()),
      throwsA(isA<ImportCancelledException>()),
    );
    expect(world.backend.stagedSources, isEmpty);
  });

  test('a size cap below the fixture maps to IMP-007', () async {
    final world = await SimulatedTestWorld.create();
    world.importAdapter.picker.enqueueFixture('sf-002');
    await expectLater(
      world.importAdapter.pickAndImport(ImportRequest(maxBytes: 1)),
      throwsA(
        isA<ImportRejectedException>()
            .having((e) => e.kind, 'kind', ImportRejectionKind.tooLarge)
            .having((e) => e.code, 'code', 'IMP-007'),
      ),
    );
    expect(world.backend.stagedSources, isEmpty);
  });

  test('unknown fixture ids map to the unknown-reason category', () async {
    final world = await SimulatedTestWorld.create();
    world.importAdapter.picker.enqueueFixture('not-in-catalogue');
    await expectLater(
      world.importAdapter.pickAndImport(ImportRequest()),
      throwsA(
        isA<ImportRejectedException>().having(
          (e) => e.kind,
          'kind',
          ImportRejectionKind.unknownReason,
        ),
      ),
    );
  });

  test('picker selections and cancellations keep caller order', () async {
    final world = await SimulatedTestWorld.create();
    world.importAdapter.picker
      ..enqueueFixture('sf-004')
      ..enqueueCancel()
      ..enqueueFixture('sf-001');
    expect(world.importAdapter.picker.pendingCount, 3);
    final ImportedSource first = await world.importAdapter.pickAndImport(
      ImportRequest(),
    );
    expect(first.pageCount, 1);
    await expectLater(
      world.importAdapter.pickAndImport(ImportRequest()),
      throwsA(isA<ImportCancelledException>()),
    );
    final ImportedSource third = await world.importAdapter.pickAndImport(
      ImportRequest(),
    );
    expect(third.pageCount, 2);
    expect(world.importAdapter.picker.isEmpty, isTrue);
  });

  test('verifySource reports an unknown source as unreadable', () async {
    final world = await SimulatedTestWorld.create();
    final SourceIntegrity integrity = await world.importAdapter.verifySource(
      '00000000-0000-4000-8000-000000000999',
    );
    expect(integrity.readable, isFalse);
    expect(integrity.evidence.evidenceClass, EvidenceClass.simulated);
  });

  test('same inputs produce identical ids and hashes across runs', () async {
    final first = await SimulatedTestWorld.create();
    final second = await SimulatedTestWorld.create();
    final ImportedSource a = await first.importFixture('sf-004');
    final ImportedSource b = await second.importFixture('sf-004');
    expect(a.documentId, b.documentId);
    expect(a.sourceId, b.sourceId);
    expect(a.sha256, b.sha256);
    expect(a.sizeBytes, b.sizeBytes);
    expect(a.pages.length, b.pages.length);
  });

  test('import refuses to create an aggregate under global SAVE-008', () async {
    final world = await SimulatedTestWorld.create();
    world.storeAdapter.simulateGlobalKeyUnavailable();
    world.importAdapter.picker.enqueueFixture('sf-004');
    await expectLater(
      world.importAdapter.pickAndImport(ImportRequest()),
      throwsA(
        isA<KeystoreUnavailableException>().having(
          (e) => e.code,
          'code',
          'SAVE-008',
        ),
      ),
    );
    expect(world.backend.stagedSources, isEmpty);
    expect(world.backend.documents, isEmpty);
  });

  test('page geometry of a rotated fixture is preserved', () async {
    final world = await SimulatedTestWorld.create();
    final ImportedSource imported = await world.importFixture('sf-003');
    expect(imported.pages.length, 5);
    for (int index = 0; index < imported.pages.length; index++) {
      final SimulatedFixturePage expected = catalog
          .fixture('sf-003')
          .pages[index];
      expect(imported.pages[index].rotation, expected.rotation);
      expect(
        imported.pages[index].displaySize.width,
        closeTo(expected.widthPt, 0.01),
      );
      expect(
        imported.pages[index].displaySize.height,
        closeTo(expected.heightPt, 0.01),
      );
    }
    expect(imported.pageFailures, isEmpty);
  });

  test('a staged source reference mismatch is refused as PLT-002', () async {
    final world = await SimulatedTestWorld.create();
    final ImportedSource imported = await world.importFixture('sf-001');
    final SourceFileRef source = SourceFileRef(
      id: imported.sourceId,
      sha256: '0' * 64,
      sizeBytes: imported.sizeBytes,
      pageCount: imported.pageCount,
      importedAt: world.backend.context.nowUtc(),
    );
    await expectLater(
      world.storeAdapter.createDocument(
        world.documentRequest(
          title: 'Test',
          source: source,
          content: world.simpleRevisionContent(imported),
          documentId: imported.documentId,
        ),
      ),
      throwsA(
        isA<SecurityException>().having((e) => e.code, 'code', 'PLT-002'),
      ),
    );
  });

  test('a full store refuses the import before source or aggregate', () async {
    final world = await SimulatedTestWorld.create(maxTotalBytes: 100);
    world.importAdapter.picker.enqueueFixture('sf-004');
    await expectLater(
      world.importAdapter.pickAndImport(ImportRequest()),
      throwsA(
        isA<StorageFullException>()
            .having((e) => e.code, 'code', 'SAVE-001')
            .having((e) => e.retryable, 'retryable', isTrue),
      ),
    );
    expect(world.backend.stagedSources, isEmpty);
    expect(world.backend.documents, isEmpty);
    expect(world.backend.totalBytes, 0);
  });

  test(
    'a refused import preserves the existing source and aggregate',
    () async {
      final world = await SimulatedTestWorld.create();
      final ImportedSource first = await world.importFixture('sf-001');
      final int beforeBytes = world.backend.totalBytes;
      // No further object fits, so the second import must be refused before it
      // stages anything or creates an aggregate.
      world.backend.maxTotalBytes = beforeBytes;
      world.importAdapter.picker.enqueueFixture('sf-004');
      await expectLater(
        world.importAdapter.pickAndImport(ImportRequest()),
        throwsA(
          isA<StorageFullException>().having((e) => e.code, 'code', 'SAVE-001'),
        ),
      );
      expect(world.backend.stagedSources.length, 1);
      expect(world.backend.documents.length, 1);
      expect(world.backend.stagedSource(first.sourceId), isNotNull);
      expect(world.backend.document(first.documentId), isNotNull);
      expect(world.backend.totalBytes, beforeBytes);
    },
  );
}
