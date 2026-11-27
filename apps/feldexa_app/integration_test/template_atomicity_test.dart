// T118 template-save atomicity suite (FR-106, CHK035).
//
// Run only on an exclusively allocated Android emulator:
//   flutter test integration_test/template_atomicity_test.dart -d emulator-5554
//
// Lane honesty (same as T094/T100): the Android EncryptedStore exposes no
// injectable failure seam for template commits, so the atomicity rule is
// exercised on the deterministic SIMULATED store lane
// (`SimulatedBackend.maxTotalBytes` -> SAVE-001; `failNextWrite` ->
// `StorageWriteException`). Per FR-088 this is SIMULATED evidence inside an
// EMULATOR device run, never Android-acceptance evidence.
//
// Pins the FR-106 rule for template saves on the document-save pattern: a
// blocked or failed template save reports no success, leaves no partial
// aggregate or partial version, and preserves the previous durable head.

library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_application/src/templates/create_template_from_document.dart';
import 'package:feldexa_application/src/templates/template_versions.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Page _page() => Page(
  index: 0,
  geometry: PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842)),
);

ConfirmedField _field({required int order}) => ConfirmedField(
  id: '00000000-0000-4000-8000-${(20 + order).toString().padLeft(12, '0')}',
  pageIndex: 0,
  rect: Rect.fromLTWH(60, 100 + 40.0 * order, 200, 24),
  type: FieldType.text,
  provenance: Provenance.user,
  label: 'Feld $order',
  order: order,
  createdAt: DateTime.utc(2026, 11, 27, 9),
  updatedAt: DateTime.utc(2026, 11, 27, 9),
);

SourceFileRef _stagedSource(SimulatedBackend backend) {
  final Uint8List bytes = Uint8List.fromList(List<int>.filled(512, 37));
  final String hash = crypto.sha256.convert(bytes).toString();
  backend.stageSource(
    sourceId: '00000000-0000-4000-8000-000000000001',
    fixture: SimulatedFixture(
      id: 'sf-t118',
      role: SimulatedFixtureRole.editor,
      status: SimulatedFixtureStatus.valid,
      title: 'sf-t118',
      displayName: 't118.pdf',
      bytes: bytes,
      sha256: hash,
      sizeBytes: bytes.length,
      pages: <SimulatedFixturePage>[
        SimulatedFixturePage(
          index: 0,
          widthPt: 595,
          heightPt: 842,
          rotation: 0,
        ),
      ],
      expectedOcr: const <SimulatedOcrPage>[],
      expectedErrorCode: null,
    ),
  );
  return SourceFileRef(
    id: '00000000-0000-4000-8000-000000000001',
    sha256: hash,
    sizeBytes: bytes.length,
    pageCount: 1,
    importedAt: DateTime.utc(2026, 11, 27, 9),
  );
}

RevisionContent _content() => RevisionContent(
  pages: <Page>[_page()],
  fields: <ConfirmedField>[_field(order: 0)],
  fieldOrder: <String>['00000000-0000-4000-8000-000000000020'],
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a blocked template creation reports no success and no partial aggregate '
    '(FR-106, SAVE-001)',
    () async {
      final SimulatedBackend backend = SimulatedBackend(
        context: SimulatedAdapterContext(),
        maxTotalBytes: 0,
      );
      final SimulatedSecureStoreAdapter store = SimulatedSecureStoreAdapter(
        backend: backend,
      );
      final SourceFileRef source = _stagedSource(backend);
      int objects(SimulatedBackend b) =>
          b.stagedSources.length + b.documents.length + b.templates.length;
      final int objectsBefore = objects(backend);

      final CreateTemplateResult result = await createTemplateFromDocument(
        store: store,
        title: 'Atomare Vorlage',
        source: source,
        content: _content(),
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorCode, 'SAVE-001');
      expect(result.meta, isNull);
      expect(backend.templates, isEmpty);
      expect(objects(backend), objectsBefore);
      // The staged source is intact: the user can free space and retry.
      expect(backend.stagedSources[source.id], isNotNull);
    },
  );

  test('a failed post-write read-back preserves the previous version head '
      'byte- and hash-identical (FR-106, SAVE-003 path)', () async {
    final SimulatedBackend backend = SimulatedBackend(
      context: SimulatedAdapterContext(),
    );
    final SimulatedSecureStoreAdapter store = SimulatedSecureStoreAdapter(
      backend: backend,
    );
    final SourceFileRef source = _stagedSource(backend);
    final CreateTemplateResult created = await createTemplateFromDocument(
      store: store,
      title: 'Versionskopf',
      source: source,
      content: _content(),
    );
    expect(created.isSuccess, isTrue);
    final String head = created.meta!.latestRevisionId!;
    final SimulatedTemplateVersionRecord headRecord = backend
        .template(created.meta!.id)!
        .versions[head]!;
    final int bytesBefore = headRecord.canonicalBytes.length;
    final String hashBefore = headRecord.sha256;

    // Post-write read-back damage: the write lands, verification fails; the
    // FR-106 reporting rule runs through the T117 use case.
    store.corruptNextCommit();
    final SaveTemplateVersionResult corrupted = await saveTemplateVersion(
      store: store,
      templateId: created.meta!.id,
      expectedHead: head,
      pageSnapshot: <Page>[_page()],
      fieldSnapshot: <ConfirmedField>[_field(order: 0)],
    );
    expect(corrupted.isSuccess, isFalse);
    expect(corrupted.errorCode, 'SAVE-003');
    expect(corrupted.meta, isNull);

    // Byte- and hash-exact: the previous head is untouched, no partial
    // version exists, and the failed version was rolled back.
    final SimulatedTemplateRecord record = backend.template(created.meta!.id)!;
    expect(record.versions, hasLength(1));
    expect(record.head, head);
    expect(record.versions[head]!.canonicalBytes.length, bytesBefore);
    expect(record.versions[head]!.sha256, hashBefore);

    // A correct save afterwards appends exactly one new version.
    final SaveTemplateVersionResult saved = await saveTemplateVersion(
      store: store,
      templateId: created.meta!.id,
      expectedHead: head,
      pageSnapshot: <Page>[_page()],
      fieldSnapshot: <ConfirmedField>[_field(order: 0), _field(order: 1)],
    );
    expect(saved.isSuccess, isTrue);
    final LoadedTemplate reloaded = await store.loadTemplate(created.meta!.id);
    expect(reloaded.template.meta.versions, hasLength(2));
    expect(
      reloaded.template.meta.latestVersion.versionId,
      saved.meta!.latestRevisionId,
    );
  });

  test('a stale expected head never appends a version and reports SAVE-003 '
      '(FR-106)', () async {
    final SimulatedBackend backend = SimulatedBackend(
      context: SimulatedAdapterContext(),
    );
    final SimulatedSecureStoreAdapter store = SimulatedSecureStoreAdapter(
      backend: backend,
    );
    final CreateTemplateResult created = await createTemplateFromDocument(
      store: store,
      title: 'Vorsichts-Vorlage',
      source: _stagedSource(backend),
      content: _content(),
    );
    expect(created.isSuccess, isTrue);

    final SaveTemplateVersionResult stale = await saveTemplateVersion(
      store: store,
      templateId: created.meta!.id,
      expectedHead: '00000000-0000-4000-8000-000000000099',
      pageSnapshot: <Page>[_page()],
      fieldSnapshot: <ConfirmedField>[_field(order: 0)],
    );
    expect(stale.isSuccess, isFalse);
    expect(stale.errorCode, 'SAVE-003');
    expect(stale.meta, isNull);
    final LoadedTemplate loaded = await store.loadTemplate(created.meta!.id);
    expect(loaded.template.meta.versions, hasLength(1));
  });
}
