// T028 SIMULATED export and delivery adapter tests.
//
// The preview is explicitly SIMULATED. These tests prove the watermark, the
// deterministic bytes, the canonical blocking warnings, and the delivery
// outcomes; they make no PDFBox, print-fidelity, or Android claim.

import 'dart:convert';
import 'dart:typed_data';

import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:feldexa_testkit/feldexa_testkit.dart' show sha256Hex;
import 'package:flutter_test/flutter_test.dart';

import 'support/simulated_world.dart';

void main() {
  late SimulatedFixtureCatalog catalog;

  setUpAll(() async {
    catalog = await loadCatalog();
  });

  ExportTextOp textOp(
    PageGeometry geometry, {
    required String fieldId,
    required Rect rect,
    List<String> lines = const <String>['Müller-Lüdenscheidt'],
  }) {
    final double fontSize =
        ((0.6 * rect.height).clamp(7.0, 12.0) * 10).round() / 10;
    final double lineHeight = (1.2 * fontSize * 100).round() / 100;
    return ExportTextOp(
      fieldId: fieldId,
      provenance: Provenance.user,
      rect: rect,
      pdfRect: geometry.displayRectToPdf(rect),
      fontSizePt: fontSize,
      lineHeightPt: lineHeight,
      baselineFromTopPt: 1.5 + 0.8 * fontSize,
      lines: lines,
    );
  }

  ExportCheckboxOp checkboxOp(
    PageGeometry geometry, {
    required String fieldId,
  }) {
    final Rect rect = Rect.fromLTWH(420, 210, 10, 10);
    return ExportCheckboxOp(
      fieldId: fieldId,
      provenance: Provenance.user,
      rect: rect,
      pdfRect: geometry.displayRectToPdf(rect),
      checked: true,
      insetPt: 1.5,
      strokeWidthPt: 0.8,
    );
  }

  const String signaturePngBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
      'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

  Uint8List signaturePngBytes() => base64Decode(signaturePngBase64);

  /// Saves one revision whose signature mark and value reference [assetId].
  Future<({String revisionId, String fieldId, String assetId})>
  saveRevisionWithSignature(
    SimulatedTestWorld world,
    ImportedSource imported, {
    required Rect rect,
  }) async {
    final DateTime at = world.backend.context.nowUtc();
    final String fieldId = world.backend.context.newId();
    final String assetId = world.backend.context.newId();
    final Uint8List bytes = signaturePngBytes();
    await world.storeAdapter.writeSignature(
      WriteSignatureRequest(
        documentId: imported.documentId,
        assetId: assetId,
        bytes: bytes,
        sha256: sha256Hex(bytes),
      ),
    );
    final RevisionContent content = RevisionContent(
      pages: <Page>[
        for (int index = 0; index < imported.pageCount; index++)
          Page(index: index, geometry: imported.pages[index]),
      ],
      fields: <ConfirmedField>[
        ConfirmedField(
          id: fieldId,
          pageIndex: 0,
          rect: rect,
          type: FieldType.signature,
          provenance: Provenance.user,
          label: 'Unterschrift',
          order: 0,
          createdAt: at,
          updatedAt: at,
        ),
      ],
      fieldOrder: <String>[fieldId],
      values: <String, FieldValue>{
        fieldId: SignatureValue(signatureAssetId: assetId, lastEditedAt: at),
      },
      signatures: <String, SignatureMark>{
        fieldId: SignatureMark(
          assetId: assetId,
          fieldId: fieldId,
          pageIndex: 0,
          rect: rect,
          widthPx: 1,
          heightPx: 1,
          capturedAt: at,
          sha256: sha256Hex(bytes),
        ),
      },
    );
    final StoredMeta saved = await world.storeAdapter.saveRevision(
      SaveRevisionRequest(
        documentId: imported.documentId,
        content: content,
        kind: RevisionKind.explicit,
      ),
    );
    return (
      revisionId: saved.latestRevisionId!,
      fieldId: fieldId,
      assetId: assetId,
    );
  }

  test('export descriptor is SIMULATED PDF export', () async {
    final world = await SimulatedTestWorld.create();
    final descriptor = world.exportAdapter.descriptor;
    expect(descriptor.kind, CapabilityKind.pdfExport);
    expect(descriptor.isSimulated, isTrue);
    expect(descriptor.evidence.evidenceClass, EvidenceClass.simulated);
    expect(descriptor.adapterId, simulatedExportAdapterId);
  });

  test('validates and exports a deterministic SIMULATED preview', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final saved = await world.createSavedDocument(imported);
    final geometry = imported.pages.first;
    final plan = world.buildExportPlan(
      imported: imported,
      documentId: saved.documentId,
      revisionId: saved.revisionId,
      ops: <ExportOp>[
        textOp(
          geometry,
          fieldId: 'field-1',
          rect: Rect.fromLTWH(50, 50, 200, 15),
        ),
        checkboxOp(geometry, fieldId: 'field-2'),
      ],
    );

    final ExportValidationResult validation = await world.exportAdapter
        .validate(plan);
    expect(validation.isValid, isTrue);
    expect(validation.warnings, isEmpty);
    expect(validation.evidence.evidenceClass, EvidenceClass.simulated);

    final ExportResult result = await world.exportAdapter.export(
      ExportRequest(
        documentId: saved.documentId,
        revisionId: saved.revisionId,
        plan: plan,
      ),
    );
    expect(result.artifact.state, ExportArtifactState.succeeded);
    expect(result.artifact.pageCount, 1);
    expect(result.artifact.byteSize, greaterThan(0));
    expect(result.artifact.sha256!.length, 64);
    expect(result.artifact.verification!.pageCountMatches, isTrue);
    expect(result.artifact.verification!.mediaBoxesMatch, isTrue);
    expect(result.artifact.verification!.fontGlyphsPresent, isTrue);
    expect(result.artifact.verification!.noInteractiveFields, isTrue);
    expect(result.artifact.verification!.overlayBoundsWithinPage, isTrue);
    expect(result.evidence.evidenceClass, EvidenceClass.simulated);

    final Uint8List bytes = await world.exportAdapter.readArtifact(
      result.artifact.id,
    );
    expect(bytes.length, result.artifact.byteSize);
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    // ignore: avoid_print
    // ignore: avoid_print
    expect(latin1.decode(bytes).contains('SIMULATED'), isTrue);
    expect(latin1.decode(bytes).contains('Produktions-PDF'), isTrue);
    expect(latin1.decode(bytes).contains('kein'), isTrue);
  });

  test(
    'two exports of the same plan produce byte-identical previews',
    () async {
      final world = await SimulatedTestWorld.create();
      final imported = await world.importFixture('sf-004');
      final saved = await world.createSavedDocument(imported);
      final geometry = imported.pages.first;
      final plan = world.buildExportPlan(
        imported: imported,
        documentId: saved.documentId,
        revisionId: saved.revisionId,
        ops: <ExportOp>[
          textOp(
            geometry,
            fieldId: 'field-1',
            rect: Rect.fromLTWH(50, 50, 200, 15),
          ),
        ],
      );
      final ExportRequest request = ExportRequest(
        documentId: saved.documentId,
        revisionId: saved.revisionId,
        plan: plan,
      );
      final ExportResult first = await world.exportAdapter.export(request);
      final ExportResult second = await world.exportAdapter.export(request);
      final Uint8List firstBytes = await world.exportAdapter.readArtifact(
        first.artifact.id,
      );
      final Uint8List secondBytes = await world.exportAdapter.readArtifact(
        second.artifact.id,
      );
      expect(firstBytes, orderedEquals(secondBytes));
      expect(first.artifact.sha256, second.artifact.sha256);
    },
  );

  test('the bundled Noto Sans font can be embedded', () async {
    final fontBytes = await loadNotoSansRegular();
    final world = await SimulatedTestWorld.create();
    final exportAdapter = SimulatedPdfExportAdapter(
      backend: world.backend,
      fontBytes: fontBytes,
    );
    final imported = await world.importFixture('sf-004');
    final saved = await world.createSavedDocument(imported);
    final plan = world.buildExportPlan(
      imported: imported,
      documentId: saved.documentId,
      revisionId: saved.revisionId,
      ops: <ExportOp>[
        textOp(
          imported.pages.first,
          fieldId: 'field-1',
          rect: Rect.fromLTWH(50, 50, 200, 15),
          lines: const <String>['Grüße aus München – 12,50 €'],
        ),
      ],
    );
    final ExportValidationResult validation = await exportAdapter.validate(
      plan,
    );
    expect(validation.isValid, isTrue);
    final ExportResult result = await exportAdapter.export(
      ExportRequest(
        documentId: saved.documentId,
        revisionId: saved.revisionId,
        plan: plan,
      ),
    );
    expect(result.artifact.state, ExportArtifactState.succeeded);
  });

  test(
    'overflow-free text that Helvetica cannot encode blocks with EXP-004',
    () async {
      final world = await SimulatedTestWorld.create();
      final imported = await world.importFixture('sf-004');
      final saved = await world.createSavedDocument(imported);
      final plan = world.buildExportPlan(
        imported: imported,
        documentId: saved.documentId,
        revisionId: saved.revisionId,
        ops: <ExportOp>[
          textOp(
            imported.pages.first,
            fieldId: 'field-1',
            rect: Rect.fromLTWH(50, 50, 200, 15),
            lines: const <String>['Emoji 😀'],
          ),
        ],
      );
      final ExportValidationResult validation = await world.exportAdapter
          .validate(plan);
      expect(validation.isBlocking, isTrue);
      expect(validation.warnings.map((w) => w.code), contains('EXP-004'));
      await expectLater(
        world.exportAdapter.export(
          ExportRequest(
            documentId: saved.documentId,
            revisionId: saved.revisionId,
            plan: plan,
          ),
        ),
        throwsA(
          isA<ExportBlockedException>()
              .having((e) => e.code, 'code', 'EXP-001')
              .having((e) => e.fieldIds, 'fieldIds', contains('field-1')),
        ),
      );
    },
  );

  test('embedFonts:false falls back to the Helvetica substitute', () async {
    final fontBytes = await loadNotoSansRegular();
    final world = await SimulatedTestWorld.create();
    final exportAdapter = SimulatedPdfExportAdapter(
      backend: world.backend,
      fontBytes: fontBytes,
    );
    final imported = await world.importFixture('sf-004');
    final saved = await world.createSavedDocument(imported);
    final plan = world.buildExportPlan(
      imported: imported,
      documentId: saved.documentId,
      revisionId: saved.revisionId,
      ops: <ExportOp>[
        textOp(
          imported.pages.first,
          fieldId: 'field-1',
          rect: Rect.fromLTWH(50, 50, 200, 15),
          lines: const <String>['Grüße – 12,50 €'],
        ),
      ],
    );
    expect((await exportAdapter.validate(plan)).isValid, isTrue);
    await expectLater(
      exportAdapter.export(
        ExportRequest(
          documentId: saved.documentId,
          revisionId: saved.revisionId,
          plan: plan,
          options: ExportOptions(embedFonts: false),
        ),
      ),
      throwsA(isA<ExportBlockedException>()),
    );
  });

  test(
    'export maps a field-level EXP-003 blocker to ExportBlockedException',
    () async {
      final world = await SimulatedTestWorld.create();
      final imported = await world.importFixture('sf-004');
      final saved = await world.createSavedDocument(imported);
      final plan = world.buildExportPlan(
        imported: imported,
        documentId: saved.documentId,
        revisionId: saved.revisionId,
        ops: <ExportOp>[
          textOp(
            imported.pages.first,
            fieldId: 'field-out',
            rect: Rect.fromLTWH(600, 50, 120, 15),
          ),
        ],
      );
      await expectLater(
        world.exportAdapter.export(
          ExportRequest(
            documentId: saved.documentId,
            revisionId: saved.revisionId,
            plan: plan,
          ),
        ),
        throwsA(
          isA<ExportBlockedException>()
              .having((e) => e.code, 'code', 'EXP-001')
              .having((e) => e.fieldIds, 'fieldIds', contains('field-out')),
        ),
      );
      expect(world.backend.artifacts, isEmpty);
    },
  );

  test(
    'a corrupted staged source is EXP-005 and never reaches export',
    () async {
      final world = await SimulatedTestWorld.create();
      final imported = await world.importFixture('sf-004');
      final saved = await world.createSavedDocument(imported);
      final plan = world.buildExportPlan(
        imported: imported,
        documentId: saved.documentId,
        revisionId: saved.revisionId,
        ops: <ExportOp>[],
      );
      // Mutate the backend object without updating the persisted source hash.
      world.backend.stagedSource(imported.sourceId)!.bytes[10] ^= 0xFF;

      final ExportValidationResult validation = await world.exportAdapter
          .validate(plan);
      expect(validation.isBlocking, isTrue);
      expect(validation.warnings.map((w) => w.code), contains('EXP-005'));
      expect(validation.warnings.single.reason, 'source_corrupt');

      await expectLater(
        world.exportAdapter.export(
          ExportRequest(
            documentId: saved.documentId,
            revisionId: saved.revisionId,
            plan: plan,
          ),
        ),
        throwsA(
          isA<ExportFailedException>().having((e) => e.code, 'code', 'EXP-002'),
        ),
      );
      expect(world.backend.artifacts, isEmpty);
    },
  );

  test('a missing staged source is EXP-005 and export fails', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final DateTime now = world.backend.context.nowUtc();
    final String documentId = world.backend.context.newId();
    final String revisionId = world.backend.context.newId();
    final SourceFileRef missingSource = SourceFileRef(
      id: world.backend.context.newId(),
      sha256: 'b' * 64,
      sizeBytes: 10,
      pageCount: 1,
      importedAt: now,
    );
    world.backend.putDocument(
      SimulatedDocumentRecord(
        id: documentId,
        title: 'Fehlende Quelle',
        createdAt: now,
        updatedAt: now,
        source: missingSource,
        head: null,
        lastDurableAt: null,
      ),
    );
    final plan = world.buildExportPlan(
      imported: imported,
      documentId: documentId,
      revisionId: revisionId,
      ops: <ExportOp>[],
      sourceSha256: missingSource.sha256,
    );
    final ExportValidationResult validation = await world.exportAdapter
        .validate(plan);
    expect(
      validation.warnings.map((w) => w.reason),
      containsAll(<String>['source_missing', 'revision_unavailable']),
    );
    await expectLater(
      world.exportAdapter.export(
        ExportRequest(
          documentId: documentId,
          revisionId: revisionId,
          plan: plan,
        ),
      ),
      throwsA(
        isA<ExportFailedException>().having((e) => e.code, 'code', 'EXP-002'),
      ),
    );
  });

  test('a plan/source SHA mismatch is EXP-005 and export fails', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final saved = await world.createSavedDocument(imported);
    final basePlan = world.buildExportPlan(
      imported: imported,
      documentId: saved.documentId,
      revisionId: saved.revisionId,
      ops: <ExportOp>[],
    );
    final ExportPlan mismatched = ExportPlan(
      documentId: basePlan.documentId,
      revisionId: basePlan.revisionId,
      sourceSha256: 'a' * 64,
      pageCount: basePlan.pageCount,
      evidenceClass: basePlan.evidenceClass,
      font: basePlan.font,
      pages: basePlan.pages,
      info: basePlan.info,
    );
    final ExportValidationResult validation = await world.exportAdapter
        .validate(mismatched);
    expect(validation.warnings.single.reason, 'source_hash_mismatch');
    await expectLater(
      world.exportAdapter.export(
        ExportRequest(
          documentId: saved.documentId,
          revisionId: saved.revisionId,
          plan: mismatched,
        ),
      ),
      throwsA(
        isA<ExportFailedException>().having((e) => e.code, 'code', 'EXP-002'),
      ),
    );
  });

  test('a missing revision is EXP-005 and export fails', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final saved = await world.createSavedDocument(imported);
    final basePlan = world.buildExportPlan(
      imported: imported,
      documentId: saved.documentId,
      revisionId: saved.revisionId,
      ops: <ExportOp>[],
    );
    final ExportPlan missingRevision = ExportPlan(
      documentId: basePlan.documentId,
      revisionId: '00000000-0000-4000-8000-000000000999',
      sourceSha256: basePlan.sourceSha256,
      pageCount: basePlan.pageCount,
      evidenceClass: basePlan.evidenceClass,
      font: basePlan.font,
      pages: basePlan.pages,
      info: basePlan.info,
    );
    final ExportValidationResult validation = await world.exportAdapter
        .validate(missingRevision);
    expect(validation.warnings.single.reason, 'revision_unavailable');
    await expectLater(
      world.exportAdapter.export(
        ExportRequest(
          documentId: saved.documentId,
          revisionId: '00000000-0000-4000-8000-000000000999',
          plan: missingRevision,
        ),
      ),
      throwsA(isA<ExportFailedException>()),
    );
  });

  test('a page-count mismatch is EXP-006 and export fails', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-001');
    final saved = await world.createSavedDocument(imported);
    final plan = world.buildExportPlan(
      imported: imported,
      documentId: saved.documentId,
      revisionId: saved.revisionId,
      ops: <ExportOp>[],
    );
    // The helper builds a one-page plan; sf-001 has two source pages.
    final ExportValidationResult validation = await world.exportAdapter
        .validate(plan);
    expect(validation.warnings.map((w) => w.code), contains('EXP-006'));
    expect(
      validation.warnings.firstWhere((w) => w.code == 'EXP-006').reason,
      'page_count_mismatch',
    );
    await expectLater(
      world.exportAdapter.export(
        ExportRequest(
          documentId: saved.documentId,
          revisionId: saved.revisionId,
          plan: plan,
        ),
      ),
      throwsA(
        isA<ExportFailedException>().having((e) => e.code, 'code', 'EXP-002'),
      ),
    );
  });

  test('a source failure is not masked by a field-level blocker', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final saved = await world.createSavedDocument(imported);
    final plan = world.buildExportPlan(
      imported: imported,
      documentId: saved.documentId,
      revisionId: saved.revisionId,
      ops: <ExportOp>[
        textOp(
          imported.pages.first,
          fieldId: 'field-out',
          rect: Rect.fromLTWH(600, 50, 120, 15),
        ),
      ],
    );
    world.backend.stagedSource(imported.sourceId)!.bytes[12] ^= 0xFF;
    final ExportValidationResult validation = await world.exportAdapter
        .validate(plan);
    expect(
      validation.warnings.map((w) => w.code),
      containsAll(<String>['EXP-003', 'EXP-005']),
    );
    await expectLater(
      world.exportAdapter.export(
        ExportRequest(
          documentId: saved.documentId,
          revisionId: saved.revisionId,
          plan: plan,
        ),
      ),
      throwsA(
        isA<ExportFailedException>().having((e) => e.code, 'code', 'EXP-002'),
      ),
    );
  });

  test('successful export leaves the staged source bytes unchanged', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final saved = await world.createSavedDocument(imported);
    final Uint8List before = Uint8List.fromList(
      world.backend.stagedSource(imported.sourceId)!.bytes,
    );
    final plan = world.buildExportPlan(
      imported: imported,
      documentId: saved.documentId,
      revisionId: saved.revisionId,
      ops: <ExportOp>[],
    );
    await world.exportAdapter.export(
      ExportRequest(
        documentId: saved.documentId,
        revisionId: saved.revisionId,
        plan: plan,
      ),
    );
    expect(
      world.backend.stagedSource(imported.sourceId)!.bytes,
      orderedEquals(before),
    );
    expect(
      world.backend.stagedSource(imported.sourceId)!.sha256,
      imported.sha256,
    );
  });

  test('an op outside the page blocks with EXP-003', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final saved = await world.createSavedDocument(imported);
    final geometry = imported.pages.first;
    final plan = world.buildExportPlan(
      imported: imported,
      documentId: saved.documentId,
      revisionId: saved.revisionId,
      ops: <ExportOp>[
        textOp(
          geometry,
          fieldId: 'field-out',
          rect: Rect.fromLTWH(600, 50, 120, 15),
        ),
      ],
    );
    final ExportValidationResult validation = await world.exportAdapter
        .validate(plan);
    expect(validation.warnings.map((w) => w.code), contains('EXP-003'));
    expect(validation.warnings.single.fieldId, 'field-out');
  });

  test('a missing signature asset blocks with EXP-005', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final saved = await world.createSavedDocument(imported);
    final geometry = imported.pages.first;
    final Rect rect = Rect.fromLTWH(300, 600, 120, 40);
    final op = ExportImageOp(
      fieldId: 'field-signature',
      provenance: Provenance.user,
      rect: rect,
      pdfRect: geometry.displayRectToPdf(rect),
      assetId: '00000000-0000-4000-8000-000000000123',
    );
    final plan = world.buildExportPlan(
      imported: imported,
      documentId: saved.documentId,
      revisionId: saved.revisionId,
      ops: <ExportOp>[op],
    );
    final ExportValidationResult validation = await world.exportAdapter
        .validate(plan);
    expect(validation.warnings.map((w) => w.code), contains('EXP-005'));
    expect(validation.warnings.single.reason, 'signature_missing');
  });

  test(
    'a post-revision signature asset is unlinked and fails export',
    () async {
      final world = await SimulatedTestWorld.create();
      final imported = await world.importFixture('sf-004');
      final saved = await world.createSavedDocument(imported);
      final geometry = imported.pages.first;
      final Rect rect = Rect.fromLTWH(300, 600, 120, 40);
      final String assetId = world.backend.context.newId();
      final Uint8List bytes = signaturePngBytes();
      // The asset is written after the selected revision was saved, so the
      // revision does not reference it.
      await world.storeAdapter.writeSignature(
        WriteSignatureRequest(
          documentId: saved.documentId,
          assetId: assetId,
          bytes: bytes,
          sha256: sha256Hex(bytes),
        ),
      );
      final plan = world.buildExportPlan(
        imported: imported,
        documentId: saved.documentId,
        revisionId: saved.revisionId,
        ops: <ExportOp>[
          ExportImageOp(
            fieldId: 'field-signature',
            provenance: Provenance.user,
            rect: rect,
            pdfRect: geometry.displayRectToPdf(rect),
            assetId: assetId,
          ),
        ],
      );
      final ExportValidationResult validation = await world.exportAdapter
          .validate(plan);
      expect(validation.warnings.map((w) => w.code), contains('EXP-005'));
      expect(validation.warnings.single.reason, 'signature_unlinked');
      await expectLater(
        world.exportAdapter.export(
          ExportRequest(
            documentId: saved.documentId,
            revisionId: saved.revisionId,
            plan: plan,
          ),
        ),
        throwsA(
          isA<ExportFailedException>().having((e) => e.code, 'code', 'EXP-002'),
        ),
      );
      expect(world.backend.artifacts, isEmpty);
    },
  );

  test(
    'a revision-bound signature asset exports after hash verification',
    () async {
      final world = await SimulatedTestWorld.create();
      final imported = await world.importFixture('sf-004');
      final geometry = imported.pages.first;
      final Rect rect = Rect.fromLTWH(300, 600, 120, 40);
      final bound = await saveRevisionWithSignature(
        world,
        imported,
        rect: rect,
      );
      final plan = world.buildExportPlan(
        imported: imported,
        documentId: imported.documentId,
        revisionId: bound.revisionId,
        ops: <ExportOp>[
          ExportImageOp(
            fieldId: bound.fieldId,
            provenance: Provenance.user,
            rect: rect,
            pdfRect: geometry.displayRectToPdf(rect),
            assetId: bound.assetId,
          ),
        ],
      );
      final ExportValidationResult validation = await world.exportAdapter
          .validate(plan);
      expect(validation.isValid, isTrue);
      final ExportResult result = await world.exportAdapter.export(
        ExportRequest(
          documentId: imported.documentId,
          revisionId: bound.revisionId,
          plan: plan,
        ),
      );
      expect(result.artifact.state, ExportArtifactState.succeeded);
    },
  );

  test(
    'a mutated signature asset is EXP-005 signature_hash_mismatch',
    () async {
      final world = await SimulatedTestWorld.create();
      final imported = await world.importFixture('sf-004');
      final geometry = imported.pages.first;
      final Rect rect = Rect.fromLTWH(300, 600, 120, 40);
      final bound = await saveRevisionWithSignature(
        world,
        imported,
        rect: rect,
      );
      // Explicit fault injection: corrupt the stored asset directly. The public
      // storage operation now refuses to replace an immutable signature object,
      // so this negative export case cannot be built through writeSignature.
      final Uint8List stored = world.backend
          .document(imported.documentId)!
          .signatures[bound.assetId]!;
      stored[stored.length - 1] ^= 0xFF;
      final plan = world.buildExportPlan(
        imported: imported,
        documentId: imported.documentId,
        revisionId: bound.revisionId,
        ops: <ExportOp>[
          ExportImageOp(
            fieldId: bound.fieldId,
            provenance: Provenance.user,
            rect: rect,
            pdfRect: geometry.displayRectToPdf(rect),
            assetId: bound.assetId,
          ),
        ],
      );
      final ExportValidationResult validation = await world.exportAdapter
          .validate(plan);
      expect(validation.warnings.map((w) => w.code), contains('EXP-005'));
      expect(validation.warnings.single.reason, 'signature_hash_mismatch');
      await expectLater(
        world.exportAdapter.export(
          ExportRequest(
            documentId: imported.documentId,
            revisionId: bound.revisionId,
            plan: plan,
          ),
        ),
        throwsA(
          isA<ExportFailedException>().having((e) => e.code, 'code', 'EXP-002'),
        ),
      );
      expect(world.backend.artifacts, isEmpty);
    },
  );

  test('request document/revision ids must match the plan', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final saved = await world.createSavedDocument(imported);
    final plan = world.buildExportPlan(
      imported: imported,
      documentId: saved.documentId,
      revisionId: saved.revisionId,
      ops: <ExportOp>[],
    );
    await expectLater(
      world.exportAdapter.export(
        ExportRequest(
          documentId: world.backend.context.newId(),
          revisionId: saved.revisionId,
          plan: plan,
        ),
      ),
      throwsA(
        isA<ExportFailedException>().having((e) => e.code, 'code', 'EXP-002'),
      ),
    );
    await expectLater(
      world.exportAdapter.export(
        ExportRequest(
          documentId: saved.documentId,
          revisionId: world.backend.context.newId(),
          plan: plan,
        ),
      ),
      throwsA(
        isA<ExportFailedException>().having((e) => e.code, 'code', 'EXP-002'),
      ),
    );
    expect(world.backend.artifacts, isEmpty);
  });

  test(
    'readArtifact rejects a missing artifact; delete is idempotent',
    () async {
      final world = await SimulatedTestWorld.create();
      await expectLater(
        world.exportAdapter.readArtifact(
          '00000000-0000-4000-8000-000000000999',
        ),
        throwsA(
          isA<ExportFailedException>().having((e) => e.code, 'code', 'EXP-002'),
        ),
      );
      await world.exportAdapter.deleteArtifact(
        '00000000-0000-4000-8000-000000000999',
      );
    },
  );

  test('delivery reports a labelled SIMULATED hand-off', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final saved = await world.createSavedDocument(imported);
    final plan = world.buildExportPlan(
      imported: imported,
      documentId: saved.documentId,
      revisionId: saved.revisionId,
      ops: <ExportOp>[],
    );
    final ExportResult exported = await world.exportAdapter.export(
      ExportRequest(
        documentId: saved.documentId,
        revisionId: saved.revisionId,
        plan: plan,
      ),
    );
    for (final DeliveryAction action in DeliveryAction.values) {
      final DeliveryOutcome outcome = await world.deliveryAdapter.deliver(
        action: action,
        artifactId: exported.artifact.id,
      );
      expect(outcome.completed, isTrue);
      expect(outcome.action, action);
      expect(outcome.evidence.evidenceClass, EvidenceClass.simulated);
      expect(outcome.userVisibleLocationHint, contains('SIMULATED'));
      expect(outcome.userVisibleLocationHint, isNot(contains('/')));
      expect(outcome.userVisibleLocationHint, isNot(contains('\\')));
    }
    expect(world.backend.deliveries.length, 3);
    expect(
      world.deliveryAdapter.descriptor.evidence.evidenceClass,
      EvidenceClass.simulated,
    );
  });

  test('delivery cancellation is completed:false and not an error', () async {
    final world = await SimulatedTestWorld.create();
    final imported = await world.importFixture('sf-004');
    final saved = await world.createSavedDocument(imported);
    final plan = world.buildExportPlan(
      imported: imported,
      documentId: saved.documentId,
      revisionId: saved.revisionId,
      ops: <ExportOp>[],
    );
    final ExportResult exported = await world.exportAdapter.export(
      ExportRequest(
        documentId: saved.documentId,
        revisionId: saved.revisionId,
        plan: plan,
      ),
    );
    world.deliveryAdapter.cancelNextDelivery();
    final DeliveryOutcome outcome = await world.deliveryAdapter.deliver(
      action: DeliveryAction.save,
      artifactId: exported.artifact.id,
    );
    expect(outcome.completed, isFalse);
    expect(outcome.userVisibleLocationHint, isNull);
    expect(outcome.evidence.evidenceClass, EvidenceClass.simulated);
  });

  test('delivery of an unknown artifact fails with EXP-002', () async {
    final world = await SimulatedTestWorld.create();
    await expectLater(
      world.deliveryAdapter.deliver(
        action: DeliveryAction.share,
        artifactId: '00000000-0000-4000-8000-000000000999',
      ),
      throwsA(
        isA<ExportFailedException>().having((e) => e.code, 'code', 'EXP-002'),
      ),
    );
  });

  test(
    'fixture catalogue is untouched by the export and delivery flows',
    () async {
      final world = await SimulatedTestWorld.create();
      final imported = await world.importFixture('sf-004');
      final saved = await world.createSavedDocument(imported);
      final plan = world.buildExportPlan(
        imported: imported,
        documentId: saved.documentId,
        revisionId: saved.revisionId,
        ops: <ExportOp>[],
      );
      await world.exportAdapter.export(
        ExportRequest(
          documentId: saved.documentId,
          revisionId: saved.revisionId,
          plan: plan,
        ),
      );
      expect(
        world.backend.stagedSource(imported.sourceId)!.sha256,
        catalog.fixture('sf-004').sha256,
      );
    },
  );
}
