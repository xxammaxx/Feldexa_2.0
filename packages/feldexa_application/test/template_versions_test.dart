// T117 template-version and use-template use-case tests
// (FR-059, FR-103, FR-104, FR-105, FR-060, FR-106 pattern).
//
// Host-VM tests (evidence class NONE) over the deterministic SIMULATED store:
// version saves append immutable versions with a verified new head; "use a
// template" creates a new independent document with empty values, no
// signatures, and a pinned TemplateOrigin; an earlier pinned version keeps
// its layout across a template change (FR-104); the latest version is used
// when no version is named (FR-105); deleting the template leaves the
// derived document loadable (FR-060, the T119 base); failures report exact
// catalog codes.

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_application/src/templates/template_versions.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';

Page _page() => Page(
  index: 0,
  geometry: PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842)),
);

ConfirmedField _field({
  required int order,
  Provenance provenance = Provenance.user,
  FieldType type = FieldType.text,
}) => ConfirmedField(
  id: _uuid(20 + order),
  pageIndex: 0,
  rect: Rect.fromLTWH(60, 100 + 40.0 * order, 200, 24),
  type: type,
  provenance: provenance,
  label: 'Feld $order',
  order: order,
  createdAt: DateTime.utc(2026, 11, 27, 9),
  updatedAt: DateTime.utc(2026, 11, 27, 9),
);

String _uuid(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

SourceFileRef _source(SimulatedBackend backend) {
  final Uint8List bytes = Uint8List.fromList(List<int>.filled(512, 37));
  final String hash = crypto.sha256.convert(bytes).toString();
  backend.stageSource(
    sourceId: _uuid(1),
    fixture: SimulatedFixture(
      id: 'sf-t117',
      role: SimulatedFixtureRole.editor,
      status: SimulatedFixtureStatus.valid,
      title: 'sf-t117',
      displayName: 't117.pdf',
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
    id: _uuid(1),
    sha256: hash,
    sizeBytes: bytes.length,
    pageCount: 1,
    importedAt: DateTime.utc(2026, 11, 27, 9),
  );
}

void main() {
  late SimulatedBackend backend;
  late SimulatedSecureStoreAdapter store;
  late SourceFileRef source;
  late StoredMeta template;

  setUp(() async {
    backend = SimulatedBackend(context: SimulatedAdapterContext());
    store = SimulatedSecureStoreAdapter(backend: backend);
    source = _source(backend);
    final StoredMeta created = await store.createTemplate(
      CreateTemplateRequest(
        title: 'Antragsvorlage',
        source: source,
        pages: <Page>[_page()],
        fields: <ConfirmedField>[_field(order: 0)],
        fieldOrder: <String>[_uuid(20)],
      ),
    );
    template = created;
  });

  test('saving a template change appends a new immutable version', () async {
    final SaveTemplateVersionResult saved = await saveTemplateVersion(
      store: store,
      templateId: template.id,
      expectedHead: template.latestRevisionId!,
      pageSnapshot: <Page>[_page()],
      fieldSnapshot: <ConfirmedField>[
        _field(order: 0),
        _field(order: 1, type: FieldType.checkbox),
      ],
    );
    expect(saved.isSuccess, isTrue);
    expect(saved.errorCode, isNull);
    expect(saved.meta!.latestRevisionId, isNot(template.latestRevisionId));
    final LoadedTemplate loaded = await store.loadTemplate(template.id);
    expect(loaded.template.meta.versions, hasLength(2));
    expect(
      loaded.template.meta.latestVersion.versionId,
      saved.meta!.latestRevisionId,
    );
  });

  test('using a template creates an independent document with empty values and '
      'the pinned version (FR-059, FR-104)', () async {
    final UseTemplateResult used = await useTemplate(
      store: store,
      templateId: template.id,
      documentId: backend.context.newId(),
      initialRevisionId: backend.context.newId(),
      initialKind: RevisionKind.explicit,
      title: 'Antrag aus Vorlage',
      createdAt: backend.context.nowUtc(),
      source: source,
    );
    expect(used.isSuccess, isTrue);
    expect(used.errorCode, isNull);
    expect(used.pinnedVersionId, template.latestRevisionId);
    expect(used.pinnedVersionNumber, 1);
    expect(used.meta!.kind, StoreKind.document);

    final LoadedDocument document = await store.loadDocument(used.meta!.id);
    expect(document.content.values, isEmpty);
    expect(document.content.signatures, isEmpty);
    expect(document.content.suggestions, isEmpty);
    expect(document.content.verification, isEmpty);
    expect(document.content.pages, hasLength(1));
    expect(document.content.fields, hasLength(1));
    expect(document.content.templateOrigin!.templateId, template.id);
    expect(
      document.content.templateOrigin!.templateVersionId,
      used.pinnedVersionId,
    );
    // Machine-provenance layout fields are re-provenanced to the template.
    expect(document.content.fields.single.provenance, Provenance.template);
  });

  test('a document created from version 1 keeps its pinned layout across a '
      'template change (FR-104), while a new document uses the latest version '
      '(FR-105)', () async {
    final UseTemplateResult first = await useTemplate(
      store: store,
      templateId: template.id,
      documentId: backend.context.newId(),
      initialRevisionId: backend.context.newId(),
      initialKind: RevisionKind.explicit,
      title: 'Erstes Dokument',
      createdAt: backend.context.nowUtc(),
      source: source,
    );
    expect(first.pinnedVersionNumber, 1);

    final SaveTemplateVersionResult saved = await saveTemplateVersion(
      store: store,
      templateId: template.id,
      expectedHead: template.latestRevisionId!,
      pageSnapshot: <Page>[_page()],
      fieldSnapshot: <ConfirmedField>[
        _field(order: 0),
        _field(order: 1, type: FieldType.checkbox),
      ],
    );
    expect(saved.isSuccess, isTrue);

    final LoadedDocument derived = await store.loadDocument(first.meta!.id);
    expect(
      derived.content.templateOrigin!.templateVersionId,
      first.pinnedVersionId,
    );
    expect(derived.content.fields, hasLength(1));

    final UseTemplateResult second = await useTemplate(
      store: store,
      templateId: template.id,
      documentId: backend.context.newId(),
      initialRevisionId: backend.context.newId(),
      initialKind: RevisionKind.explicit,
      title: 'Zweites Dokument',
      createdAt: backend.context.nowUtc(),
      source: source,
    );
    expect(second.pinnedVersionId, saved.meta!.latestRevisionId);
    final LoadedDocument secondDoc = await store.loadDocument(second.meta!.id);
    expect(secondDoc.content.fields, hasLength(2));
  });

  test('deleting the template leaves the derived document loadable and intact '
      '(FR-060, FR-099)', () async {
    final UseTemplateResult used = await useTemplate(
      store: store,
      templateId: template.id,
      documentId: backend.context.newId(),
      initialRevisionId: backend.context.newId(),
      initialKind: RevisionKind.explicit,
      title: 'Drittes Dokument',
      createdAt: backend.context.nowUtc(),
      source: source,
    );
    expect(used.isSuccess, isTrue);

    await store.delete(
      StoreKind.template,
      template.id,
      DeleteConfirmation(acknowledged: true, title: template.title),
    );
    expect(backend.template(template.id), isNull);

    final LoadedDocument derived = await store.loadDocument(used.meta!.id);
    expect(derived.content.pages, hasLength(1));
    expect(
      derived.content.templateOrigin!.templateVersionId,
      used.pinnedVersionId,
    );
  });

  test('a version save with a stale expected head fails and reports no success '
      '(FR-106 pattern)', () async {
    final SaveTemplateVersionResult saved = await saveTemplateVersion(
      store: store,
      templateId: template.id,
      expectedHead: _uuid(99),
      pageSnapshot: <Page>[_page()],
      fieldSnapshot: <ConfirmedField>[_field(order: 0)],
    );
    expect(saved.isSuccess, isFalse);
    expect(saved.errorCode, 'SAVE-003');
    expect(saved.meta, isNull);
    final LoadedTemplate loaded = await store.loadTemplate(template.id);
    expect(loaded.template.meta.versions, hasLength(1));
  });

  test('a use of a missing template reports the load failure code without '
      'creating a document', () async {
    final UseTemplateResult used = await useTemplate(
      store: store,
      templateId: _uuid(77),
      documentId: backend.context.newId(),
      initialRevisionId: backend.context.newId(),
      initialKind: RevisionKind.explicit,
      title: 'Nicht erstellt',
      createdAt: backend.context.nowUtc(),
      source: source,
    );
    expect(used.isSuccess, isFalse);
    expect(used.errorCode, 'SAVE-003');
    expect(used.meta, isNull);
    expect(backend.documents, isEmpty);
  });

  test('a non-UTC timestamp is a programmer error before any port call', () {
    expect(
      () => useTemplate(
        store: store,
        templateId: template.id,
        documentId: backend.context.newId(),
        initialRevisionId: backend.context.newId(),
        initialKind: RevisionKind.explicit,
        title: 'Titel',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0)
            .add(const Duration(hours: 1)),
        source: source,
      ),
      throwsArgumentError,
    );
    expect(backend.documents, isEmpty);
  });
}
