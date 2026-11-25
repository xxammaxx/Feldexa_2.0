// Issue #334 export controller tests.
//
// Evidence class: NONE. Host-VM unit tests with injected fake ports and the
// committed `assets/fonts/metrics.json`; they construct no platform channel,
// open no PDF, and make no Android runtime claim.
//
// They prove the controller composition of `contracts/export-plan.md` §1 and
// `contracts/ports.md` §2.5: the plan is built from the verified snapshot, a
// blocking plan or a blocking validation result never reaches `export`, a
// verified artifact is reported as succeeded, a failure carries the catalog
// code, and every displayed sentence comes from the German ARB.

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:feldexa_app/features/export/export_controller.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

const String _documentId = '5f0c3a52-3a6a-4f0b-9c2d-1b7e4d8a6c01';
const String _sourceId = '7b2d4c1e-5f3a-4b8c-8a9d-2e6f0c1b3d42';
const String _revisionId = '9a1b2c3d-4e5f-4a6b-8c7d-8e9f0a1b2c3d';
const String _artifactValue = '0a1b2c3d-4e5f-4a6b-8c7d-8e9f0a1b2c3d';
const String _fieldId = '00000000-0000-4000-8000-000000000001';
const String _noteFieldId = '00000000-0000-4000-8000-000000000002';
final String _sha256 = List<String>.filled(64, 'a').join();
final String _artifactSha256 = List<String>.filled(64, 'b').join();
final Uint8List _sourceBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
final DateTime _at = DateTime.utc(2026, 11, 25, 9);

final CapabilityEvidence _noneEvidence = CapabilityEvidence(
  evidenceClass: EvidenceClass.none,
  adapterId: 'test.export-controller.v1',
);

final CapabilityDescriptor _exportDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.pdfExport,
  adapterId: 'test.export.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final CapabilityDescriptor _clockDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.clock,
  adapterId: 'test.clock.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

core.PageGeometry _geometry() {
  return core.PageGeometry(mediaBox: core.Rect.fromLTWH(0, 0, 595.28, 841.89));
}

core.ConfirmedField _field({String id = _fieldId, String label = 'Name'}) {
  return core.ConfirmedField(
    id: id,
    pageIndex: 0,
    rect: core.Rect.fromLTWH(40, 40, 200, 14),
    type: core.FieldType.text,
    provenance: core.Provenance.user,
    label: label,
    order: 0,
    createdAt: _at,
    updatedAt: _at,
  );
}

core.RevisionContent _content({
  List<core.ConfirmedField>? fields,
  Map<String, core.FieldValue>? values,
  List<core.FieldSuggestion> suggestions = const <core.FieldSuggestion>[],
}) {
  final List<core.ConfirmedField> confirmed =
      fields ?? <core.ConfirmedField>[_field()];
  return core.RevisionContent(
    pages: <core.Page>[
      core.Page(
        index: 0,
        geometry: _geometry(),
        analysis: core.AnalysisState.complete,
      ),
    ],
    suggestions: suggestions,
    fields: confirmed,
    fieldOrder: <String>[for (final core.ConfirmedField f in confirmed) f.id],
    values:
        values ??
        <String, core.FieldValue>{
          _fieldId: core.TextValue(text: 'Erika Mustermann', lastEditedAt: _at),
        },
  );
}

LoadedDocument _loaded({
  core.RevisionContent? content,
  String? revisionId = _revisionId,
}) {
  final core.RevisionContent revision = content ?? _content();
  return LoadedDocument(
    meta: core.DocumentMeta(
      id: _documentId,
      title: 'Antrag',
      createdAt: _at,
      updatedAt: _at,
      source: core.SourceFileRef(
        id: _sourceId,
        sha256: _sha256,
        sizeBytes: _sourceBytes.length,
        pageCount: 1,
        importedAt: _at,
      ),
      latestRevisionId: revisionId,
      lastDurableAt: _at,
    ),
    content: revision,
    sourceBytes: _sourceBytes,
    evidence: _noneEvidence,
  );
}

final class _FakeClock implements ClockPort {
  @override
  CapabilityDescriptor get descriptor => _clockDescriptor;

  @override
  DateTime nowUtc() => _at;
}

/// Records the port calls and answers with the configured results.
final class _FakeExportPort implements PdfExportPort {
  _FakeExportPort({this.validation, this.exportError, this.validateError});

  final ExportValidation? validation;
  final Object? exportError;
  final Object? validateError;
  final List<ExportPlan> validated = <ExportPlan>[];
  final List<ExportRequest> exported = <ExportRequest>[];

  @override
  CapabilityDescriptor get descriptor => _exportDescriptor;

  @override
  Future<ExportValidationResult> validate(ExportPlan plan) async {
    validated.add(plan);
    final Object? failure = validateError;
    if (failure != null) {
      throw failure;
    }
    return ExportValidationResult(
      validation:
          validation ??
          ExportValidation(
            warnings: const <ExportValidationWarning>[],
            validatedAt: _at,
          ),
      evidence: _noneEvidence,
    );
  }

  @override
  Future<ExportResult> export(ExportRequest request) async {
    exported.add(request);
    final Object? failure = exportError;
    if (failure != null) {
      throw failure;
    }
    return ExportResult(
      artifact: _verifiedArtifact(request),
      evidence: _noneEvidence,
    );
  }

  @override
  Future<Uint8List> readArtifact(String artifactId) async {
    throw UnsupportedOperationException();
  }

  @override
  Future<void> deleteArtifact(String artifactId) async {}
}

ExportArtifact _verifiedArtifact(ExportRequest request) {
  return ExportArtifact.start(
    id: _artifactValue,
    documentId: request.documentId,
    revisionId: request.revisionId,
    pageCount: request.plan.pageCount,
    createdAt: _at,
  ).startRendering().startVerification().succeed(
    byteSize: 4096,
    sha256: _artifactSha256,
    verification: ArtifactVerification(
      pageCountMatches: true,
      mediaBoxesMatch: true,
      fontGlyphsPresent: true,
      noInteractiveFields: true,
      overlayBoundsWithinPage: true,
      checkedAt: _at,
    ),
  );
}

ExportValidationWarning _warning(
  String code, {
  String? fieldId = _fieldId,
  int? pageIndex = 0,
  String? fieldLabel = 'Name',
}) {
  return ExportValidationWarning(
    code: code,
    reason: 'test_reason',
    fieldId: fieldId,
    pageIndex: pageIndex,
    fieldLabel: fieldLabel,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ExportFontMetrics metrics;
  late AppLocalizations l10n;

  setUpAll(() async {
    metrics = await loadExportFontMetrics();
    l10n = await AppLocalizations.delegate.load(const Locale('de'));
  });

  ExportController controllerFor(_FakeExportPort port) {
    return ExportController(
      exportPort: port,
      clock: _FakeClock(),
      metrics: metrics,
      evidenceClass: 'emulator',
    );
  }

  test('prepare builds the canonical plan from the verified snapshot', () {
    final ExportController controller = controllerFor(_FakeExportPort());

    final ExportPreparation preparation = controller.prepare(_loaded());

    expect(preparation, isA<ExportPreparationReady>());
    final ExportPlan plan = (preparation as ExportPreparationReady).plan;
    expect(plan.documentId, _documentId);
    expect(plan.revisionId, _revisionId);
    expect(plan.sourceSha256, _sha256);
    expect(plan.pageCount, 1);
    expect(plan.evidenceClass, 'emulator');
    expect(plan.pages.single.ops.single.fieldId, _fieldId);
    expect(plan.info.emptyFieldCount, 0);
    expect(plan.info.unresolvedSuggestionCount, 0);
  });

  test('prepare reports the pre-export information of empty and unreviewed '
      'content without blocking it', () {
    final ExportController controller = controllerFor(_FakeExportPort());
    final core.RevisionContent content = _content(
      fields: <core.ConfirmedField>[
        _field(),
        core.ConfirmedField(
          id: _noteFieldId,
          pageIndex: 0,
          rect: core.Rect.fromLTWH(40, 80, 200, 14),
          type: core.FieldType.text,
          provenance: core.Provenance.user,
          label: 'Hinweis',
          order: 1,
          createdAt: _at,
          updatedAt: _at,
        ),
      ],
      values: <String, core.FieldValue>{
        _fieldId: core.TextValue(text: 'Erika Mustermann', lastEditedAt: _at),
      },
      suggestions: <core.FieldSuggestion>[
        core.FieldSuggestion(
          id: 's_p0_0001',
          pageIndex: 0,
          rect: core.Rect.fromLTWH(40, 120, 120, 14),
          proposedType: core.FieldType.text,
          confidence: 0.5,
          labelText: null,
          evidence: core.SuggestionEvidence(
            cues: const <core.SuggestionCue>[core.SuggestionCue.underline],
            ocrUsed: false,
          ),
        ),
      ],
    );

    final ExportPreparation preparation = controller.prepare(
      _loaded(content: content),
    );

    // Provisional OD-1: an unreviewed suggestion and an empty field inform the
    // user but never block the export.
    expect(preparation, isA<ExportPreparationReady>());
    final ExportPlanInfo info = (preparation as ExportPreparationReady).info;
    expect(info.emptyFieldCount, 1);
    expect(info.unresolvedSuggestionCount, 1);
  });

  test('prepare blocks content that would overflow its field (EXP-001)', () {
    final ExportController controller = controllerFor(_FakeExportPort());
    final core.RevisionContent content = _content(
      values: <String, core.FieldValue>{
        // A value far too long for the 200 x 14 pt field: the layout refuses
        // to shrink or truncate it, so the plan is blocked instead (FR-038).
        _fieldId: core.TextValue(text: 'a' * 400, lastEditedAt: _at),
      },
    );

    final ExportPreparation preparation = controller.prepare(
      _loaded(content: content),
    );

    expect(preparation, isA<ExportPreparationBlocked>());
    final ExportValidation validation =
        (preparation as ExportPreparationBlocked).validation;
    expect(validation.isBlocking, isTrue);
    expect(validation.warnings.single.code, 'EXP-001');
    expect(validation.warnings.single.fieldLabel, 'Name');
  });

  test('prepare refuses a snapshot without a durable revision', () {
    final ExportController controller = controllerFor(_FakeExportPort());

    expect(
      () => controller.prepare(_loaded(revisionId: null)),
      throwsA(isA<StateError>()),
    );
  });

  test('run validates, exports, and reports the verified artifact', () async {
    final _FakeExportPort port = _FakeExportPort();
    final ExportController controller = controllerFor(port);
    final ExportPreparationReady ready =
        controller.prepare(_loaded()) as ExportPreparationReady;

    final ExportAttempt attempt = await controller.run(ready);

    expect(attempt, isA<ExportAttemptSucceeded>());
    final ExportAttemptSucceeded succeeded = attempt as ExportAttemptSucceeded;
    expect(succeeded.artifact.id, _artifactValue);
    expect(succeeded.artifact.pageCount, 1);
    expect(succeeded.artifact.byteSize, 4096);
    expect(port.validated, hasLength(1));
    expect(port.exported, hasLength(1));
    expect(port.exported.single.documentId, _documentId);
    expect(port.exported.single.revisionId, _revisionId);
  });

  test('a blocking validation result never starts the export', () async {
    final _FakeExportPort port = _FakeExportPort(
      validation: ExportValidation(
        warnings: <ExportValidationWarning>[_warning('EXP-004')],
        validatedAt: _at,
      ),
    );
    final ExportController controller = controllerFor(port);
    final ExportPreparationReady ready =
        controller.prepare(_loaded()) as ExportPreparationReady;

    final ExportAttempt attempt = await controller.run(ready);

    expect(attempt, isA<ExportAttemptBlocked>());
    expect(
      (attempt as ExportAttemptBlocked).validation.warnings.single.code,
      'EXP-004',
    );
    expect(port.exported, isEmpty);
  });

  test('an export failure carries the catalog code', () async {
    final _FakeExportPort port = _FakeExportPort(
      exportError: ExportFailedException(),
    );
    final ExportController controller = controllerFor(port);
    final ExportPreparationReady ready =
        controller.prepare(_loaded()) as ExportPreparationReady;

    final ExportAttempt attempt = await controller.run(ready);

    expect(attempt, isA<ExportAttemptFailed>());
    expect((attempt as ExportAttemptFailed).code, 'EXP-002');
  });

  test('an unclassified export failure is reported as EXP-002', () async {
    final _FakeExportPort port = _FakeExportPort(
      validateError: const FormatException('broken channel answer'),
    );
    final ExportController controller = controllerFor(port);
    final ExportPreparationReady ready =
        controller.prepare(_loaded()) as ExportPreparationReady;

    final ExportAttempt attempt = await controller.run(ready);

    expect((attempt as ExportAttemptFailed).code, 'EXP-002');
    expect(port.exported, isEmpty);
  });

  test('blocking texts use the catalog sentences and their placeholders', () {
    final ExportValidation validation = ExportValidation(
      warnings: <ExportValidationWarning>[
        _warning('EXP-001', fieldLabel: 'Name'),
        _warning('EXP-001', fieldId: _noteFieldId, fieldLabel: 'Hinweis'),
      ],
      validatedAt: _at,
    );

    final List<ExportFailureText> texts = exportBlockedTexts(l10n, validation);

    expect(texts, hasLength(1));
    expect(texts.single.message, l10n.exp001(2, 'Name, Hinweis'));
    expect(texts.single.recovery, l10n.exp001Recovery);
  });

  test('a page code carries its page number and a save code its own row', () {
    expect(
      exportBlockedTexts(
        l10n,
        ExportValidation(
          warnings: <ExportValidationWarning>[
            _warning('EXP-006', fieldId: null, fieldLabel: null, pageIndex: 2),
          ],
          validatedAt: _at,
        ),
      ).single.message,
      l10n.exp006(3),
    );
    expect(
      exportBlockedTexts(
        l10n,
        ExportValidation(
          warnings: <ExportValidationWarning>[_warning('SAVE-001')],
          validatedAt: _at,
        ),
      ).single.message,
      l10n.save001Export,
    );
  });

  test('a warning set without field labels falls back to the generic row', () {
    final List<ExportFailureText> texts = exportBlockedTexts(
      l10n,
      ExportValidation(
        warnings: <ExportValidationWarning>[
          _warning('EXP-001', fieldLabel: null),
        ],
        validatedAt: _at,
      ),
    );

    // No catalog field label can be derived from a field id, so the generic
    // EXP-002 sentence is shown instead of a dangling placeholder.
    expect(texts.single.message, l10n.exp002);
    expect(texts.single.recovery, l10n.exp002Recovery);
  });

  test('failure codes map to their catalog sentence', () {
    expect(exportFailureCodeText(l10n, 'EXP-002')!.message, l10n.exp002);
    expect(exportFailureCodeText(l10n, 'EXP-005')!.message, l10n.exp005);
    expect(
      exportFailureCodeText(l10n, 'SAVE-001')!.message,
      l10n.save001Export,
    );
    // Developer-only codes have no German row: a rejected payload still means
    // no valid PDF exists, a cancellation shows nothing at all.
    expect(exportFailureCodeText(l10n, 'PLT-003')!.message, l10n.exp002);
    expect(exportFailureCodeText(l10n, 'PLT-002')!.message, l10n.exp002);
    expect(exportFailureCodeText(l10n, 'PLT-004'), isNull);
  });
}
