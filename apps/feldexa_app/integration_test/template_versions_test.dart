// T120 template independence and version suite (FR-059; SC-012/SC-021).
//
// Run only on an exclusively allocated Android emulator:
//   flutter test integration_test/template_versions_test.dart -d emulator-5554
//
// Lane honesty (same as T094/T100): exercised on the deterministic SIMULATED
// store lane inside an EMULATOR device run (SIMULATED evidence, never
// Android-acceptance evidence).
//
// Pins FR-059 and the SC-012/SC-021 independence invariants: using a
// template creates two independent documents with no shared mutation
// surface; editing one derived document never changes the template or the
// sibling; saving a template change appends a new immutable version while
// existing derived documents keep their pinned version; a new document uses
// the latest version (FR-104/FR-105).

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
      id: 'sf-t120',
      role: SimulatedFixtureRole.editor,
      status: SimulatedFixtureStatus.valid,
      title: 'sf-t120',
      displayName: 't120.pdf',
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

Future<UseTemplateResult> _use(
  SimulatedBackend backend,
  SimulatedSecureStoreAdapter store,
  String templateId,
  SourceFileRef source,
  String title,
) async {
  final UseTemplateResult used = await useTemplate(
    store: store,
    templateId: templateId,
    documentId: backend.context.newId(),
    initialRevisionId: backend.context.newId(),
    initialKind: RevisionKind.explicit,
    title: title,
    createdAt: backend.context.nowUtc(),
    source: source,
  );
  expect(used.isSuccess, isTrue);
  return used;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('two derived documents are independent; editing one never changes the '
      'template or the sibling (FR-059, FR-060)', () async {
    final SimulatedBackend backend = SimulatedBackend(
      context: SimulatedAdapterContext(),
    );
    final SimulatedSecureStoreAdapter store = SimulatedSecureStoreAdapter(
      backend: backend,
    );
    final SourceFileRef source = _stagedSource(backend);
    final CreateTemplateResult created = await createTemplateFromDocument(
      store: store,
      title: 'Unabhängigkeits-Vorlage',
      source: source,
      content: RevisionContent(
        pages: <Page>[_page()],
        fields: <ConfirmedField>[_field(order: 0)],
        fieldOrder: <String>['00000000-0000-4000-8000-000000000020'],
      ),
    );
    expect(created.isSuccess, isTrue);
    final String templateId = created.meta!.id;

    final UseTemplateResult docA = await _use(
      backend,
      store,
      templateId,
      source,
      'Dokument A',
    );
    final UseTemplateResult docB = await _use(
      backend,
      store,
      templateId,
      source,
      'Dokument B',
    );
    expect(docA.meta!.id, isNot(docB.meta!.id));

    // The user edits document A and saves one revision with a value.
    final String fieldId = '00000000-0000-4000-8000-000000000020';
    final StoredMeta savedA = await store.saveRevision(
      SaveRevisionRequest(
        documentId: docA.meta!.id,
        expectedHead: docA.meta!.latestRevisionId,
        content: RevisionContent(
          pages: <Page>[_page()],
          fields: <ConfirmedField>[_field(order: 0)],
          fieldOrder: <String>[fieldId],
          values: <String, FieldValue>{
            fieldId: TextValue(
              text: 'Nur in A',
              lastEditedAt: backend.context.nowUtc(),
            ),
          },
          templateOrigin: TemplateOrigin(
            templateId: templateId,
            templateVersionId: docA.pinnedVersionId!,
            templateVersionNumber: docA.pinnedVersionNumber,
          ),
        ),
        kind: RevisionKind.explicit,
      ),
    );
    expect(savedA.latestRevisionId, isNotNull);

    // The template is unchanged: one version, no values anywhere.
    final LoadedTemplate template = await store.loadTemplate(templateId);
    expect(template.template.meta.versions, hasLength(1));
    expect(template.template.content.fieldSnapshot, hasLength(1));

    // The sibling document B is unchanged: still one revision, no values.
    final LoadedDocument sibling = await store.loadDocument(docB.meta!.id);
    expect(sibling.meta.latestRevisionId, docB.meta!.latestRevisionId);
    expect(sibling.content.values, isEmpty);

    // Document A carries exactly its own saved value.
    final LoadedDocument edited = await store.loadDocument(docA.meta!.id);
    expect(edited.meta.latestRevisionId, savedA.latestRevisionId);
    expect(edited.content.values, hasLength(1));
  });

  test('a saved template change appends a version; existing pins stay, a new '
      'document uses the latest version (FR-103, FR-104, FR-105)', () async {
    final SimulatedBackend backend = SimulatedBackend(
      context: SimulatedAdapterContext(),
    );
    final SimulatedSecureStoreAdapter store = SimulatedSecureStoreAdapter(
      backend: backend,
    );
    final SourceFileRef source = _stagedSource(backend);
    final CreateTemplateResult created = await createTemplateFromDocument(
      store: store,
      title: 'Versions-Vorlage',
      source: source,
      content: RevisionContent(
        pages: <Page>[_page()],
        fields: <ConfirmedField>[_field(order: 0)],
        fieldOrder: <String>['00000000-0000-4000-8000-000000000020'],
      ),
    );
    expect(created.isSuccess, isTrue);
    final String templateId = created.meta!.id;

    final UseTemplateResult first = await _use(
      backend,
      store,
      templateId,
      source,
      'Erstes Dokument',
    );
    expect(first.pinnedVersionNumber, 1);

    final SaveTemplateVersionResult versionTwo = await saveTemplateVersion(
      store: store,
      templateId: templateId,
      expectedHead: created.meta!.latestRevisionId!,
      pageSnapshot: <Page>[_page()],
      fieldSnapshot: <ConfirmedField>[_field(order: 0), _field(order: 1)],
    );
    expect(versionTwo.isSuccess, isTrue);

    // The existing derived document keeps its pinned version and layout.
    final LoadedDocument kept = await store.loadDocument(first.meta!.id);
    expect(
      kept.content.templateOrigin!.templateVersionId,
      first.pinnedVersionId,
    );
    expect(kept.content.fields, hasLength(1));

    // A new document after the change uses the latest version.
    final UseTemplateResult second = await _use(
      backend,
      store,
      templateId,
      source,
      'Zweites Dokument',
    );
    expect(second.pinnedVersionId, versionTwo.meta!.latestRevisionId);
    expect(second.pinnedVersionNumber, 2);
    final LoadedDocument newest = await store.loadDocument(second.meta!.id);
    expect(newest.content.fields, hasLength(2));
    expect(newest.content.values, isEmpty);
  });
}
