// T119 template-deletion independence suite (FR-060/FR-099, CHK034).
//
// Run only on an exclusively allocated Android emulator:
//   flutter test integration_test/template_delete_test.dart -d emulator-5554
//
// Lane honesty (same as T094/T100): exercised on the deterministic SIMULATED
// store lane inside an EMULATOR device run (SIMULATED evidence, never
// Android-acceptance evidence).
//
// Pins FR-060/FR-099: deleting the template aggregate leaves every derived
// document loadable with its source pages, pinned template origin, layout,
// and entered values intact; a delete without explicit confirmation never
// deletes anything.

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

ConfirmedField _field({required int order, bool signature = false}) =>
    ConfirmedField(
      id: '00000000-0000-4000-8000-${(20 + order).toString().padLeft(12, '0')}',
      pageIndex: 0,
      rect: Rect.fromLTWH(60, 100 + 40.0 * order, 200, 24),
      type: signature ? FieldType.signature : FieldType.text,
      provenance: Provenance.user,
      label: signature ? 'Unterschrift' : 'Feld $order',
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
      id: 'sf-t119',
      role: SimulatedFixtureRole.editor,
      status: SimulatedFixtureStatus.valid,
      title: 'sf-t119',
      displayName: 't119.pdf',
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
  fields: <ConfirmedField>[_field(order: 0), _field(order: 1, signature: true)],
  fieldOrder: <String>[
    '00000000-0000-4000-8000-000000000020',
    '00000000-0000-4000-8000-000000000021',
  ],
);

Future<StoredMeta> _createTemplate(
  SimulatedSecureStoreAdapter store,
  SourceFileRef source,
) async {
  final CreateTemplateResult result = await createTemplateFromDocument(
    store: store,
    title: 'Lösch-Vorlage',
    source: source,
    content: _content(),
  );
  expect(result.isSuccess, isTrue);
  return result.meta!;
}

Future<UseTemplateResult> _derive(
  SimulatedBackend backend,
  SimulatedSecureStoreAdapter store,
  StoredMeta template,
  SourceFileRef source,
) async {
  final UseTemplateResult used = await useTemplate(
    store: store,
    templateId: template.id,
    documentId: backend.context.newId(),
    initialRevisionId: backend.context.newId(),
    initialKind: RevisionKind.explicit,
    title: 'Abgeleitetes Dokument',
    createdAt: backend.context.nowUtc(),
    source: source,
  );
  expect(used.isSuccess, isTrue);
  return used;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('deleting the template leaves the derived document, its pages, pin, and '
      'values intact (FR-060, FR-099)', () async {
    final SimulatedBackend backend = SimulatedBackend(
      context: SimulatedAdapterContext(),
    );
    final SimulatedSecureStoreAdapter store = SimulatedSecureStoreAdapter(
      backend: backend,
    );
    final SourceFileRef source = _stagedSource(backend);
    final Uint8List fixtureBytes = backend.readStagedSource(source.id)!;
    final StoredMeta template = await _createTemplate(store, source);
    final UseTemplateResult derived = await _derive(
      backend,
      store,
      template,
      source,
    );

    // The user fills the derived document and saves once.
    final String textFieldId = '00000000-0000-4000-8000-000000000020';
    final RevisionContent filled = RevisionContent(
      pages: <Page>[_page()],
      fields: <ConfirmedField>[
        _field(order: 0),
        _field(order: 1, signature: true),
      ],
      fieldOrder: <String>[textFieldId, '00000000-0000-4000-8000-000000000021'],
      values: <String, FieldValue>{
        textFieldId: TextValue(
          text: 'Bleibt erhalten',
          lastEditedAt: backend.context.nowUtc(),
        ),
      },
      templateOrigin: TemplateOrigin(
        templateId: template.id,
        templateVersionId: derived.pinnedVersionId!,
        templateVersionNumber: derived.pinnedVersionNumber,
      ),
    );
    final StoredMeta saved = await store.saveRevision(
      SaveRevisionRequest(
        documentId: derived.meta!.id,
        expectedHead: derived.meta!.latestRevisionId,
        content: filled,
        kind: RevisionKind.explicit,
      ),
    );
    expect(saved.latestRevisionId, isNot(derived.meta!.latestRevisionId));

    // Explicit deletion of the template aggregate only.
    await store.delete(
      StoreKind.template,
      template.id,
      DeleteConfirmation(acknowledged: true, title: template.title),
    );
    expect(backend.template(template.id), isNull);
    expect(backend.documents, hasLength(1));

    final LoadedDocument reloaded = await store.loadDocument(derived.meta!.id);
    expect(reloaded.content.pages, hasLength(1));
    expect(reloaded.content.fields, hasLength(2));
    expect(
      reloaded.content.templateOrigin!.templateVersionId,
      derived.pinnedVersionId,
    );
    expect(reloaded.content.values[textFieldId], isA<TextValue>());
    expect(
      (reloaded.content.values[textFieldId] as TextValue).text,
      'Bleibt erhalten',
    );
    // The derived document's own source copy opens with the original bytes
    // even with every other source object removed.
    expect(reloaded.sourceBytes, fixtureBytes);
    // The document list still shows exactly the derived document.
    final List<StoredMeta> documents = await store.list(StoreKind.document);
    expect(documents, hasLength(1));
    expect(documents.single.id, derived.meta!.id);
  });

  test(
    'a delete without explicit confirmation deletes nothing (FR-099)',
    () async {
      final SimulatedBackend backend = SimulatedBackend(
        context: SimulatedAdapterContext(),
      );
      final SimulatedSecureStoreAdapter store = SimulatedSecureStoreAdapter(
        backend: backend,
      );
      final StoredMeta template = await _createTemplate(
        store,
        _stagedSource(backend),
      );

      await expectLater(
        store.delete(
          StoreKind.template,
          template.id,
          DeleteConfirmation(acknowledged: false, title: template.title),
        ),
        throwsA(isA<SecurityException>()),
      );
      expect(backend.template(template.id), isNotNull);
    },
  );
}
