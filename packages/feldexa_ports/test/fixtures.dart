// Shared host-VM fixtures for the T013 port-contract tests.
//
// These values instantiate the canonical core and export types so the tests can
// prove that port DTOs consume the existing declarations instead of declaring
// second copies. Nothing here produces SIMULATED, EMULATOR, or DEVICE runtime
// evidence; every helper is deterministic.

import 'dart:typed_data';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';

/// A valid 64-character lowercase SHA-256 digest.
const String fixtureSha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// Another valid digest, used where two hashes must differ.
const String fixtureOtherSha256 =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// Builds a lowercase UUIDv4 from a test-sequence number.
String fixtureUuid(int value) {
  return '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
}

/// A fixed UTC timestamp on 2026-11-14.
DateTime fixtureAt([int minute = 0]) {
  return DateTime.utc(2026, 11, 14, 12, minute);
}

/// A deterministic rectangular field area.
Rect fixtureRect({
  double left = 50,
  double top = 60,
  double width = 140,
  double height = 20,
}) {
  return Rect.fromLTWH(left, top, width, height);
}

/// A4 page geometry in PDF user-space points.
PageGeometry fixtureGeometry() {
  return PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842));
}

/// One pending page.
Page fixturePage({int index = 0}) {
  return Page(index: index, geometry: fixtureGeometry());
}

/// A verified, encrypted source reference.
SourceFileRef fixtureSource({int pageCount = 1}) {
  return SourceFileRef(
    id: fixtureUuid(1),
    sha256: fixtureSha256,
    sizeBytes: 1234,
    pageCount: pageCount,
    originalName: 'formular.pdf',
    importedAt: fixtureAt(),
  );
}

/// Persisted document metadata.
DocumentMeta fixtureDocumentMeta() {
  return DocumentMeta(
    id: fixtureUuid(2),
    title: 'Antrag',
    createdAt: fixtureAt(),
    updatedAt: fixtureAt(1),
    source: fixtureSource(),
    latestRevisionId: fixtureUuid(3),
    lastDurableAt: fixtureAt(1),
  );
}

/// A full revision snapshot with one pending page and no fields.
RevisionContent fixtureRevisionContent() {
  return RevisionContent(pages: <Page>[fixturePage()], fieldOrder: <String>[]);
}

/// The newest template-version pointer.
TemplateVersionPointer fixtureVersionPointer() {
  return TemplateVersionPointer(
    versionId: fixtureUuid(30),
    versionNumber: 1,
    createdAt: fixtureAt(),
  );
}

/// Persisted template metadata listing one version.
TemplateMeta fixtureTemplateMeta() {
  final TemplateVersionPointer pointer = fixtureVersionPointer();
  return TemplateMeta(
    id: fixtureUuid(31),
    title: 'Vorlage',
    createdAt: fixtureAt(),
    updatedAt: fixtureAt(1),
    source: fixtureSource(),
    latestVersion: pointer,
    versions: <TemplateVersionPointer>[pointer],
  );
}

/// The immutable version record matching [fixtureTemplateMeta].
TemplateVersion fixtureTemplateVersion() {
  final TemplateVersionPointer pointer = fixtureVersionPointer();
  return TemplateVersion(
    id: pointer.versionId,
    templateId: fixtureUuid(31),
    versionNumber: pointer.versionNumber,
    createdAt: pointer.createdAt,
    pageSnapshot: <Page>[fixturePage()],
    sha256: fixtureSha256,
  );
}

/// The version content matching [fixtureTemplateVersion].
TemplateVersionContent fixtureTemplateVersionContent() {
  return TemplateVersionContent(
    pageSnapshot: <Page>[fixturePage()],
    fieldOrder: <String>[],
  );
}

/// A verified loaded-template join.
StoredTemplate fixtureStoredTemplate() {
  return StoredTemplate(
    meta: fixtureTemplateMeta(),
    version: fixtureTemplateVersion(),
    content: fixtureTemplateVersionContent(),
  );
}

/// The bundled export font contract.
ExportFont fixtureExportFont() {
  return ExportFont(
    family: 'NotoSans',
    regularAsset: 'assets/fonts/NotoSans-Regular.ttf',
    boldAsset: 'assets/fonts/NotoSans-Bold.ttf',
    metricsVersion: 'noto-sans-2.013-v1',
  );
}

/// One empty export page.
ExportPage fixtureExportPage({int index = 0}) {
  return ExportPage(index: index, geometry: fixtureGeometry());
}

/// A deterministic one-page export plan.
ExportPlan fixtureExportPlan() {
  return ExportPlan(
    documentId: fixtureUuid(2),
    revisionId: fixtureUuid(3),
    sourceSha256: fixtureSha256,
    pageCount: 1,
    evidenceClass: 'none',
    font: fixtureExportFont(),
    pages: <ExportPage>[fixtureExportPage()],
    info: ExportPlanInfo(emptyFieldCount: 0, unresolvedSuggestionCount: 0),
  );
}

/// A non-blocking export validation result.
ExportValidation fixtureExportValidation() {
  return ExportValidation(
    warnings: const <ExportValidationWarning>[],
    validatedAt: fixtureAt(),
  );
}

/// A newly started (validating) export artifact.
ExportArtifact fixtureExportArtifact() {
  return ExportArtifact.start(
    id: fixtureUuid(50),
    documentId: fixtureUuid(2),
    revisionId: fixtureUuid(3),
    pageCount: 1,
    createdAt: fixtureAt(),
  );
}

/// Evidence for a deterministic simulated Web adapter.
CapabilityEvidence fixtureSimulatedEvidence({
  String adapterId = 'web.sim.import.v1',
}) {
  return CapabilityEvidence.simulated(
    adapterId: adapterId,
    simulatedReason: 'web.simulated-adapter',
  );
}

/// Evidence for a real Android adapter.
CapabilityEvidence fixtureAndroidEvidence({
  String adapterId = 'android.pdfbox.v1',
}) {
  return CapabilityEvidence.android(adapterId: adapterId);
}

/// A descriptor matching [fixtureAndroidEvidence].
CapabilityDescriptor fixtureDescriptor({
  CapabilityKind kind = CapabilityKind.documentImport,
  String adapterId = 'android.pdfbox.v1',
  String version = '1',
  Iterable<String> supportedFeatures = const <String>['verify'],
}) {
  final CapabilityEvidence evidence = fixtureAndroidEvidence(
    adapterId: adapterId,
  );
  return CapabilityDescriptor(
    kind: kind,
    adapterId: adapterId,
    version: version,
    isSimulated: false,
    evidence: evidence,
    supportedFeatures: supportedFeatures,
  );
}

/// Deterministic non-empty bytes.
Uint8List fixtureBytes([int length = 8]) {
  return Uint8List.fromList(<int>[
    for (int index = 0; index < length; index++) index % 256,
  ]);
}
