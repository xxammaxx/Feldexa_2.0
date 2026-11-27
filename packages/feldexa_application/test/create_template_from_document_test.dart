// T115 "Als Vorlage speichern" use-case tests (FR-054–FR-057, FR-061).
//
// Host-VM tests (evidence class NONE) over the deterministic SIMULATED store:
// the FR-055 readiness classifier, the value/signature-free template save
// (FR-056/FR-057), verified-success reporting on the FR-106 pattern, typed
// failure mapping, and the FR-061 shape of the seam (one explicit call; no
// automatic template creation anywhere in this use case).

import 'dart:convert';
import 'dart:typed_data';

import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_application/src/templates/create_template_from_document.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';

String _uuid(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

SimulatedFixture _fixture() {
  final Uint8List bytes = Uint8List.fromList(List<int>.filled(512, 37));
  return SimulatedFixture(
    id: 'sf-t115',
    role: SimulatedFixtureRole.editor,
    status: SimulatedFixtureStatus.valid,
    title: 'sf-t115',
    displayName: 't115.pdf',
    bytes: bytes,
    sha256: crypto.sha256.convert(bytes).toString(),
    sizeBytes: bytes.length,
    pages: <SimulatedFixturePage>[
      SimulatedFixturePage(index: 0, widthPt: 595, heightPt: 842, rotation: 0),
    ],
    expectedOcr: const <SimulatedOcrPage>[],
    expectedErrorCode: null,
  );
}

Page _page() => Page(
  index: 0,
  geometry: PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842)),
);

ConfirmedField _field({
  required int order,
  Provenance provenance = Provenance.user,
  FieldType type = FieldType.text,
  String? suggestionId,
}) => ConfirmedField(
  id: _uuid(20 + order),
  pageIndex: 0,
  rect: Rect.fromLTWH(60, 100 + 40.0 * order, 200, 24),
  type: type,
  provenance: provenance,
  sourceSuggestionId: suggestionId,
  suggestionConfidence: provenance == Provenance.machine ? 0.82 : null,
  label: 'Feld $order',
  order: order,
  createdAt: DateTime.utc(2026, 11, 27, 9),
  updatedAt: DateTime.utc(2026, 11, 27, 9),
);

FieldSuggestion _suggestion(SuggestionResolution resolution, {String? id}) =>
    FieldSuggestion(
      id: id ?? 's_p0_0001',
      pageIndex: 0,
      rect: Rect.fromLTWH(60, 100, 200, 24),
      proposedType: FieldType.text,
      confidence: 0.82,
      labelText: null,
      evidence: SuggestionEvidence(
        cues: const <SuggestionCue>[SuggestionCue.underline],
        ocrUsed: false,
      ),
      resolution: resolution,
    );

RevisionContent _filledContent() {
  final FieldSuggestion confirmed = _suggestion(SuggestionResolution.confirmed);
  final ConfirmedField machine = _field(
    order: 0,
    provenance: Provenance.machine,
    suggestionId: confirmed.id,
  );
  final ConfirmedField userText = _field(order: 1);
  final ConfirmedField signature = _field(order: 2, type: FieldType.signature);
  return RevisionContent(
    pages: <Page>[_page()],
    suggestions: <FieldSuggestion>[
      confirmed,
      _suggestion(SuggestionResolution.rejected, id: 's_p0_0002'),
    ],
    fields: <ConfirmedField>[machine, userText, signature],
    fieldOrder: <String>[machine.id, userText.id, signature.id],
    values: <String, FieldValue>{
      machine.id: TextValue(
        text: 'Musterfrau',
        lastEditedAt: DateTime.utc(2026, 11, 27, 10),
      ),
      userText.id: TextValue(
        text: 'geheim',
        lastEditedAt: DateTime.utc(2026, 11, 27, 10),
      ),
    },
    signatures: const <String, SignatureMark>{},
    verification: <String, FieldVerification>{
      userText.id: FieldVerification(
        state: FieldVerificationState.confirmed,
        reviewedAt: DateTime.utc(2026, 11, 27, 9, 30),
      ),
      signature.id: FieldVerification(
        state: FieldVerificationState.confirmed,
        reviewedAt: DateTime.utc(2026, 11, 27, 9, 30),
      ),
    },
  );
}

SourceFileRef _source(SimulatedBackend backend, SimulatedFixture fixture) {
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

void main() {
  test('templateStructureReadiness requires resolved suggestions', () {
    final RevisionContent unresolved = RevisionContent(
      pages: <Page>[_page()],
      suggestions: <FieldSuggestion>[
        _suggestion(SuggestionResolution.unresolved),
      ],
      fieldOrder: const <String>[],
    );
    expect(
      templateStructureReadiness(unresolved),
      TemplateStructureReadiness.unreviewed,
    );
    expect(
      templateStructureReadiness(_filledContent()),
      TemplateStructureReadiness.reviewed,
    );
  });

  test('templateStructureReadiness requires reviewed user-added fields', () {
    final RevisionContent content = _filledContent();
    final RevisionContent unreviewed = RevisionContent(
      pages: content.pages,
      suggestions: content.suggestions,
      fields: content.fields,
      fieldOrder: content.fieldOrder,
      values: content.values,
      verification: const <String, FieldVerification>{},
    );
    expect(
      templateStructureReadiness(unreviewed),
      TemplateStructureReadiness.unreviewed,
    );
  });

  test('creating a template from a filled document stores pages and field '
      'definitions without values or signatures (FR-055–FR-057)', () async {
    final SimulatedBackend backend = SimulatedBackend(
      context: SimulatedAdapterContext(),
    );
    final SimulatedSecureStoreAdapter store = SimulatedSecureStoreAdapter(
      backend: backend,
    );
    final RevisionContent content = _filledContent();
    expect(
      templateStructureReadiness(content),
      TemplateStructureReadiness.reviewed,
    );

    final CreateTemplateResult result = await createTemplateFromDocument(
      store: store,
      title: 'Antragsvorlage',
      source: _source(backend, _fixture()),
      content: content,
    );

    expect(result.isSuccess, isTrue);
    expect(result.errorCode, isNull);
    expect(result.meta, isNotNull);
    final LoadedTemplate loaded = await store.loadTemplate(result.meta!.id);
    expect(loaded.template.pages, hasLength(1));
    expect(loaded.template.fields, hasLength(3));
    expect(
      loaded.template.fields.map((ConfirmedField field) => field.id),
      content.fieldOrder,
    );
    // FR-057: the stored template carries no value or signature data, even
    // though the source snapshot was filled.
    expect(backend.templates, hasLength(1));
    final SimulatedTemplateRecord record = backend.templates.values.single;
    expect(record.versions, hasLength(1));
    final String canonical = utf8.decode(
      record.versions.values.single.canonicalBytes,
    );
    expect(canonical.contains('Musterfrau'), isFalse);
    expect(canonical.contains('geheim'), isFalse);
    expect(canonical.contains('values'), isFalse);
    expect(canonical.contains('signatures'), isFalse);
  });

  test('reports verified success only with a readable version head', () async {
    final SimulatedBackend backend = SimulatedBackend(
      context: SimulatedAdapterContext(),
    );
    final SimulatedSecureStoreAdapter store = SimulatedSecureStoreAdapter(
      backend: backend,
    );
    final CreateTemplateResult result = await createTemplateFromDocument(
      store: store,
      title: 'Zweite Vorlage',
      source: _source(backend, _fixture()),
      content: _filledContent(),
    );
    expect(result.isSuccess, isTrue);
    expect(result.meta!.kind, StoreKind.template);
    expect(result.meta!.latestRevisionId, isNotNull);
    expect(result.meta!.readable, isTrue);
  });

  test('maps a storage failure to its exact catalog code', () async {
    final SimulatedBackend backend = SimulatedBackend(
      context: SimulatedAdapterContext(),
      maxTotalBytes: 0,
    );
    final SimulatedSecureStoreAdapter store = SimulatedSecureStoreAdapter(
      backend: backend,
    );
    final CreateTemplateResult result = await createTemplateFromDocument(
      store: store,
      title: 'Dritte Vorlage',
      source: _source(backend, _fixture()),
      content: _filledContent(),
    );
    expect(result.isSuccess, isFalse);
    expect(result.errorCode, 'SAVE-001');
    expect(result.meta, isNull);
    expect(backend.templates, isEmpty);
  });
}
