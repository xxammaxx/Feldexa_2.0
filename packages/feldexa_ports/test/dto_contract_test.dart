// T013 port-local DTO contract tests (host VM, evidence class NONE).
//
// These tests pin `contracts/ports.md` §2.1–§2.10:
//   * the documented defaults (`ImportRequest.maxBytes`, `RasterRequest`,
//     `ExportOptions`);
//   * the required enum values and canonical core/export field types;
//   * runtime validation of hashes, ids, counts, confidence, and timestamps;
//   * unmodifiable collection fields;
//   * a content-free `toString()` for values that can carry document content.
//
// No test here produces SIMULATED, EMULATOR, or DEVICE runtime evidence, and no
// test writes a file or touches a platform channel.

import 'dart:typed_data';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

RasterImage _rasterImage({
  int width = 2,
  int height = 2,
  int bytesPerRow = 8,
  RasterFormat format = RasterFormat.rgba8888,
  int byteLength = 16,
}) {
  return RasterImage(
    bytes: fixtureBytes(byteLength),
    width: width,
    height: height,
    bytesPerRow: bytesPerRow,
    format: format,
    evidence: fixtureAndroidEvidence(adapterId: 'android.pdfium.v1'),
  );
}

PageFailure _failure({int pageIndex = 0}) {
  return PageFailure(
    pageIndex: pageIndex,
    category: PageFailureCategory.unreadable,
    messageKey: 'IMP-002',
  );
}

void main() {
  group('ImportRequest', () {
    test('defaults to the contract 80 MiB cap', () {
      expect(ImportRequest().maxBytes, 83886080);
      expect(maxSourceSizeBytes, 83886080);
    });

    test('accepts a lower cap and rejects zero or a larger cap', () {
      expect(ImportRequest(maxBytes: 1).maxBytes, 1);

      for (final int invalid in <int>[0, -1, 83886081]) {
        expect(
          () => ImportRequest(maxBytes: invalid),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError error) => error.message,
              'message',
              contains('between 1 and 83886080'),
            ),
          ),
        );
      }
    });
  });

  group('ImportedSource', () {
    test('carries every contract field and the canonical geometry type', () {
      final ImportedSource source = ImportedSource(
        documentId: fixtureUuid(2),
        sourceId: fixtureUuid(1),
        sha256: fixtureSha256,
        sizeBytes: 1234,
        pageCount: 1,
        pages: <PageGeometry>[fixtureGeometry()],
        displayName: '  formular.pdf  ',
        evidence: fixtureAndroidEvidence(),
      );

      final PageGeometry geometry = source.pages.single;
      expect(geometry.mediaBox.width, 595);
      expect(source.documentId, fixtureUuid(2));
      expect(source.sourceId, fixtureUuid(1));
      expect(source.sha256, fixtureSha256);
      expect(source.sizeBytes, 1234);
      expect(source.pageCount, 1);
      expect(source.displayName, 'formular.pdf');
      expect(source.pageFailures, isEmpty);
    });

    test('accepts partially readable sources with unique failed pages', () {
      final ImportedSource source = ImportedSource(
        documentId: fixtureUuid(2),
        sourceId: fixtureUuid(1),
        sha256: fixtureSha256,
        sizeBytes: 1234,
        pageCount: 2,
        pages: <PageGeometry>[fixtureGeometry(), fixtureGeometry()],
        pageFailures: <PageFailure>[_failure()],
        evidence: fixtureAndroidEvidence(),
      );

      expect(source.pageFailures.single.pageIndex, 0);
      expect(() => source.pages.add(fixtureGeometry()), throwsUnsupportedError);
      expect(() => source.pageFailures.add(_failure()), throwsUnsupportedError);
    });

    test('rejects an inconsistent page count and unsafe values', () {
      ImportedSource build({
        int pageCount = 1,
        int pages = 1,
        int sizeBytes = 1234,
        String sha256 = fixtureSha256,
        String? displayName,
        List<PageFailure> failures = const <PageFailure>[],
      }) {
        return ImportedSource(
          documentId: fixtureUuid(2),
          sourceId: fixtureUuid(1),
          sha256: sha256,
          sizeBytes: sizeBytes,
          pageCount: pageCount,
          pages: <PageGeometry>[
            for (int index = 0; index < pages; index++) fixtureGeometry(),
          ],
          pageFailures: failures,
          displayName: displayName,
          evidence: fixtureAndroidEvidence(),
        );
      }

      expect(() => build(pageCount: 0), throwsArgumentError);
      expect(() => build(pageCount: 2), throwsArgumentError);
      expect(() => build(sizeBytes: 0), throwsArgumentError);
      expect(() => build(sizeBytes: 83886081), throwsArgumentError);
      expect(() => build(sha256: 'a' * 63), throwsArgumentError);
      expect(
        () => build(failures: <PageFailure>[_failure(pageIndex: 1)]),
        throwsArgumentError,
      );
      expect(
        () => build(
          pageCount: 2,
          pages: 2,
          failures: <PageFailure>[_failure(), _failure()],
        ),
        throwsArgumentError,
      );
      expect(
        () => build(displayName: '/tmp/formular.pdf'),
        throwsArgumentError,
      );
      expect(() => build(displayName: r'C:\formular.pdf'), throwsArgumentError);
    });

    test('redacts the display name from toString', () {
      final ImportedSource source = ImportedSource(
        documentId: fixtureUuid(2),
        sourceId: fixtureUuid(1),
        sha256: fixtureSha256,
        sizeBytes: 1234,
        pageCount: 1,
        pages: <PageGeometry>[fixtureGeometry()],
        displayName: 'geheim.pdf',
        evidence: fixtureAndroidEvidence(),
      );

      expect(source.toString(), contains('pageCount: 1'));
      expect(source.toString(), isNot(contains('geheim.pdf')));
    });
  });

  group('SourceIntegrity', () {
    test('represents both readable and unreadable results', () {
      final SourceIntegrity readable = SourceIntegrity(
        readable: true,
        actualSha256: fixtureSha256,
        pageCount: 1,
        pageFailures: <PageFailure>[_failure()],
        evidence: fixtureAndroidEvidence(adapterId: 'android.keystore.v1'),
      );
      final SourceIntegrity unreadable = SourceIntegrity(
        readable: false,
        evidence: fixtureAndroidEvidence(adapterId: 'android.keystore.v1'),
      );

      expect(readable.readable, isTrue);
      expect(readable.actualSha256, fixtureSha256);
      expect(readable.pageCount, 1);
      expect(readable.pageFailures, hasLength(1));
      expect(unreadable.readable, isFalse);
      expect(unreadable.actualSha256, isNull);
      expect(unreadable.pageCount, isNull);
      expect(unreadable.pageFailures, isEmpty);
    });

    test('carries the capability evidence required by §1', () {
      final SourceIntegrity simulated = SourceIntegrity(
        readable: true,
        actualSha256: fixtureSha256,
        pageCount: 1,
        evidence: fixtureSimulatedEvidence(adapterId: 'web.sim.import.v1'),
      );
      final SourceIntegrity android = SourceIntegrity(
        readable: false,
        evidence: fixtureAndroidEvidence(adapterId: 'android.keystore.v1'),
      );

      expect(simulated.evidence.evidenceClass, EvidenceClass.simulated);
      expect(simulated.evidence.simulated, isTrue);
      expect(android.evidence.evidenceClass, EvidenceClass.none);
      expect(android.evidence.simulated, isFalse);
      expect(simulated.toString(), isNot(contains('web.sim.import.v1')));
    });

    test('rejects invalid hashes, counts, and out-of-range failures', () {
      expect(
        () => SourceIntegrity(
          readable: true,
          actualSha256: 'not-a-hash',
          evidence: fixtureAndroidEvidence(),
        ),
        throwsArgumentError,
      );
      expect(
        () => SourceIntegrity(
          readable: true,
          pageCount: 0,
          evidence: fixtureAndroidEvidence(),
        ),
        throwsArgumentError,
      );
      expect(
        () => SourceIntegrity(
          readable: true,
          pageCount: 1,
          pageFailures: <PageFailure>[_failure(pageIndex: 1)],
          evidence: fixtureAndroidEvidence(),
        ),
        throwsArgumentError,
      );
      expect(
        () => SourceIntegrity(
          readable: true,
          pageFailures: <PageFailure>[_failure(), _failure()],
          evidence: fixtureAndroidEvidence(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('RasterRequest and RasterImage', () {
    test('uses the documented raster defaults and formats', () {
      final RasterRequest request = RasterRequest(
        sourceId: fixtureUuid(1),
        pageIndex: 0,
        scale: 200 / 72,
        format: RasterFormat.gray8,
      );

      expect(request.maxDimensionPx, 4096);
      expect(RasterRequest.defaultMaxDimensionPx, 4096);
      expect(RasterFormat.rgba8888.bytesPerPixel, 4);
      expect(RasterFormat.gray8.bytesPerPixel, 1);
      expect(
        RasterFormat.values.map((RasterFormat value) => value.name).toList(),
        <String>['rgba8888', 'gray8'],
      );
    });

    test('rejects invalid raster requests', () {
      RasterRequest build({
        int pageIndex = 0,
        double scale = 1,
        int maxDimensionPx = 4096,
        String sourceId = '00000000-0000-4000-8000-000000000001',
      }) {
        return RasterRequest(
          sourceId: sourceId,
          pageIndex: pageIndex,
          scale: scale,
          format: RasterFormat.rgba8888,
          maxDimensionPx: maxDimensionPx,
        );
      }

      expect(() => build(pageIndex: -1), throwsArgumentError);
      expect(() => build(scale: 0), throwsArgumentError);
      expect(() => build(scale: -1), throwsArgumentError);
      expect(() => build(scale: double.nan), throwsArgumentError);
      expect(() => build(scale: double.infinity), throwsArgumentError);
      expect(() => build(maxDimensionPx: 0), throwsArgumentError);
      expect(() => build(sourceId: 'source-1'), throwsArgumentError);
    });

    test('accepts RGBA and gray8 buffers with correct row coverage', () {
      final RasterImage rgba = _rasterImage();
      final RasterImage gray = _rasterImage(
        width: 3,
        height: 2,
        bytesPerRow: 3,
        format: RasterFormat.gray8,
        byteLength: 6,
      );

      expect(rgba.width, 2);
      expect(rgba.height, 2);
      expect(rgba.format, RasterFormat.rgba8888);
      expect(gray.format, RasterFormat.gray8);
    });

    test('rejects malformed raster buffers', () {
      expect(() => _rasterImage(byteLength: 0), throwsArgumentError);
      expect(
        () => _rasterImage(width: 0, bytesPerRow: 1, byteLength: 1),
        throwsArgumentError,
      );
      expect(
        () => _rasterImage(width: 2, bytesPerRow: 4, byteLength: 8),
        throwsArgumentError,
      );
      expect(
        () => _rasterImage(width: 2, bytesPerRow: 8, byteLength: 15),
        throwsArgumentError,
      );
    });
  });

  group('OCR DTOs', () {
    test('carries display-point rectangles and 0-1 confidence', () {
      final OcrLine line = OcrLine(
        rect: fixtureRect(),
        text: 'Müller',
        confidence: 0.97,
      );
      final OcrBlock block = OcrBlock(
        rect: fixtureRect(),
        text: 'Müller',
        confidence: 1,
        lines: <OcrLine>[line],
      );
      final OcrRequest request = OcrRequest(
        image: _rasterImage(),
        pageIndex: 0,
        languageHint: 'de',
      );

      final Rect rect = block.rect;
      expect(rect.width, 140);
      expect(block.confidence, 1);
      expect(block.lines.single, same(line));
      expect(request.languageHint, 'de');
      expect(() => block.lines.add(line), throwsUnsupportedError);
    });

    test('rejects confidence outside 0-1 without echoing text', () {
      for (final double invalid in <double>[
        -0.01,
        1.01,
        double.nan,
        double.infinity,
      ]) {
        final Object? caught = _capture(
          () => OcrBlock(
            rect: fixtureRect(),
            text: 'streng geheim',
            confidence: invalid,
          ),
        );
        expect(caught, isA<ArgumentError>());
        expect(caught.toString(), isNot(contains('streng geheim')));
      }
    });

    test('rejects invalid page indexes and language tags', () {
      expect(
        () => OcrRequest(
          image: _rasterImage(),
          pageIndex: -1,
          languageHint: 'de',
        ),
        throwsArgumentError,
      );
      for (final String invalid in <String>['', 'd', 'de/DE', 'de DE']) {
        expect(
          () => OcrRequest(
            image: _rasterImage(),
            pageIndex: 0,
            languageHint: invalid,
          ),
          throwsArgumentError,
        );
      }
    });

    test('redacts OCR text from toString', () {
      final OcrBlock block = OcrBlock(
        rect: fixtureRect(),
        text: 'Vertragspartner',
        confidence: 0.5,
      );

      expect(block.toString(), contains('textLength: 15'));
      expect(block.toString(), isNot(contains('Vertragspartner')));
    });
  });

  group('Store DTOs', () {
    test('StoreStatus validates capacity counts', () {
      final StoreStatus status = StoreStatus(
        keyAvailable: true,
        objectCount: 2,
        totalBytes: 4096,
        evidence: fixtureAndroidEvidence(adapterId: 'android.keystore.v1'),
      );

      expect(status.keyAvailable, isTrue);
      expect(status.objectCount, 2);
      expect(status.totalBytes, 4096);
      expect(
        () => StoreStatus(
          keyAvailable: true,
          objectCount: -1,
          totalBytes: 0,
          evidence: fixtureAndroidEvidence(),
        ),
        throwsArgumentError,
      );
      expect(
        () => StoreStatus(
          keyAvailable: true,
          objectCount: 0,
          totalBytes: -1,
          evidence: fixtureAndroidEvidence(),
        ),
        throwsArgumentError,
      );
    });

    test('StoredMeta carries the single port-level list read model', () {
      final StoredMeta meta = StoredMeta(
        id: fixtureUuid(2),
        kind: StoreKind.document,
        title: '  Antrag  ',
        createdAt: fixtureAt(),
        updatedAt: fixtureAt(1),
        latestRevisionId: fixtureUuid(3),
        lastDurableAt: fixtureAt(1),
      );

      expect(meta.kind, StoreKind.document);
      expect(meta.title, 'Antrag');
      expect(meta.latestRevisionId, fixtureUuid(3));
      expect(meta.readable, isTrue);
      expect(meta.toString(), isNot(contains('Antrag')));
    });

    test('StoredMeta represents an unreadable entry honestly', () {
      final StoredMeta unreadable = StoredMeta(
        id: fixtureUuid(2),
        kind: StoreKind.template,
        title: 'Vorlage',
        createdAt: fixtureAt(),
        updatedAt: fixtureAt(1),
        readable: false,
        unreadableReasonCode: 'SAVE-002',
      );

      expect(unreadable.readable, isFalse);
      expect(unreadable.unreadableReasonCode, 'SAVE-002');
      expect(
        () => StoredMeta(
          id: fixtureUuid(2),
          kind: StoreKind.document,
          title: 'Antrag',
          createdAt: fixtureAt(),
          updatedAt: fixtureAt(1),
          unreadableReasonCode: 'SAVE-002',
        ),
        throwsArgumentError,
      );
      expect(
        () => StoredMeta(
          id: fixtureUuid(2),
          kind: StoreKind.document,
          title: 'Antrag',
          createdAt: fixtureAt(),
          updatedAt: fixtureAt(1),
          readable: false,
          unreadableReasonCode: 'not-a-code',
        ),
        throwsArgumentError,
      );
    });

    test('StoredMeta rejects invalid ids, titles, and timestamps', () {
      StoredMeta build({
        String id = '00000000-0000-4000-8000-000000000002',
        String title = 'Antrag',
        DateTime? createdAt,
        DateTime? updatedAt,
        String? latestRevisionId = '00000000-0000-4000-8000-000000000003',
      }) {
        return StoredMeta(
          id: id,
          kind: StoreKind.document,
          title: title,
          createdAt: createdAt ?? fixtureAt(),
          updatedAt: updatedAt ?? fixtureAt(1),
          latestRevisionId: latestRevisionId,
        );
      }

      expect(() => build(id: 'id'), throwsArgumentError);
      expect(() => build(title: '   '), throwsArgumentError);
      expect(() => build(title: 'x' * 201), throwsArgumentError);
      expect(
        () => build(createdAt: DateTime(2026, 11, 14, 12)),
        throwsArgumentError,
      );
      expect(
        () => build(updatedAt: DateTime(2026, 11, 14, 12)),
        throwsArgumentError,
      );
      expect(() => build(latestRevisionId: 'rev-1'), throwsArgumentError);
    });

    test('LoadedDocument and LoadedTemplate use canonical types', () {
      final LoadedDocument document = LoadedDocument(
        meta: fixtureDocumentMeta(),
        content: fixtureRevisionContent(),
        sourceBytes: fixtureBytes(16),
        evidence: fixtureAndroidEvidence(),
      );
      final LoadedTemplate template = LoadedTemplate(
        template: fixtureStoredTemplate(),
        sourceBytes: fixtureBytes(16),
        evidence: fixtureAndroidEvidence(),
      );

      final DocumentMeta meta = document.meta;
      final RevisionContent content = document.content;
      final StoredTemplate stored = template.template;
      expect(meta.title, 'Antrag');
      expect(content.pageCount, 1);
      expect(stored.version.versionNumber, 1);
      expect(document.sourceBytes, hasLength(16));
      expect(template.sourceBytes, hasLength(16));
      expect(
        () => LoadedDocument(
          meta: fixtureDocumentMeta(),
          content: fixtureRevisionContent(),
          sourceBytes: Uint8List(0),
          evidence: fixtureAndroidEvidence(),
        ),
        throwsArgumentError,
      );
      expect(
        () => LoadedTemplate(
          template: fixtureStoredTemplate(),
          sourceBytes: Uint8List(0),
          evidence: fixtureAndroidEvidence(),
        ),
        throwsArgumentError,
      );
    });

    test('CreateDocumentRequest validates and trims the title', () {
      final CreateDocumentRequest request = CreateDocumentRequest(
        title: '  Antrag  ',
        source: fixtureSource(),
      );

      expect(request.title, 'Antrag');
      expect(request.toString(), isNot(contains('Antrag')));
      expect(
        () => CreateDocumentRequest(title: ' ', source: fixtureSource()),
        throwsArgumentError,
      );
    });

    test('SaveRevisionRequest carries a canonical RevisionContent', () {
      final SaveRevisionRequest request = SaveRevisionRequest(
        documentId: fixtureUuid(2),
        content: fixtureRevisionContent(),
        kind: RevisionKind.autosave,
      );
      final SaveRevisionRequest explicit = SaveRevisionRequest(
        documentId: fixtureUuid(2),
        expectedHead: fixtureUuid(3),
        content: fixtureRevisionContent(),
        kind: RevisionKind.explicit,
      );

      final RevisionContent content = request.content;
      expect(content.pageCount, 1);
      expect(request.expectedHead, isNull);
      expect(request.kind, RevisionKind.autosave);
      expect(explicit.expectedHead, fixtureUuid(3));
      expect(
        () => SaveRevisionRequest(
          documentId: 'document-1',
          content: fixtureRevisionContent(),
          kind: RevisionKind.autosave,
        ),
        throwsArgumentError,
      );
      expect(
        () => SaveRevisionRequest(
          documentId: fixtureUuid(2),
          expectedHead: 'head-1',
          content: fixtureRevisionContent(),
          kind: RevisionKind.explicit,
        ),
        throwsArgumentError,
      );
    });

    test('CreateTemplateRequest freezes snapshots and requires pages', () {
      final List<Page> pages = <Page>[fixturePage()];
      final List<String> order = <String>[];
      final CreateTemplateRequest request = CreateTemplateRequest(
        title: 'Vorlage',
        source: fixtureSource(),
        pages: pages,
        fieldOrder: order,
      );

      pages.clear();
      order.add('field-1');

      expect(request.pages, hasLength(1));
      expect(request.fieldOrder, isEmpty);
      expect(() => request.pages.add(fixturePage()), throwsUnsupportedError);
      expect(
        () => CreateTemplateRequest(
          title: 'Vorlage',
          source: fixtureSource(),
          pages: <Page>[],
          fieldOrder: <String>[],
        ),
        throwsArgumentError,
      );
    });

    test('SaveTemplateVersionRequest freezes snapshots', () {
      final List<Page> pages = <Page>[fixturePage()];
      final SaveTemplateVersionRequest request = SaveTemplateVersionRequest(
        templateId: fixtureUuid(31),
        pageSnapshot: pages,
        fieldSnapshot: const <ConfirmedField>[],
      );

      pages.clear();

      expect(request.pageSnapshot, hasLength(1));
      expect(request.expectedHead, isNull);
      expect(
        () => SaveTemplateVersionRequest(
          templateId: fixtureUuid(31),
          pageSnapshot: <Page>[],
        ),
        throwsArgumentError,
      );
      expect(
        () => SaveTemplateVersionRequest(
          templateId: 'template-1',
          pageSnapshot: <Page>[fixturePage()],
        ),
        throwsArgumentError,
      );
    });

    test('WriteSignatureRequest validates bytes and hash', () {
      final WriteSignatureRequest request = WriteSignatureRequest(
        documentId: fixtureUuid(2),
        assetId: fixtureUuid(40),
        bytes: fixtureBytes(12),
        sha256: fixtureSha256,
      );

      expect(request.bytes, hasLength(12));
      expect(request.sha256, fixtureSha256);
      expect(request.toString(), isNot(contains('sha256')));
      expect(
        () => WriteSignatureRequest(
          documentId: fixtureUuid(2),
          assetId: fixtureUuid(40),
          bytes: Uint8List(0),
          sha256: fixtureSha256,
        ),
        throwsArgumentError,
      );
      expect(
        () => WriteSignatureRequest(
          documentId: fixtureUuid(2),
          assetId: fixtureUuid(40),
          bytes: fixtureBytes(1),
          sha256: 'bad',
        ),
        throwsArgumentError,
      );
    });

    test('DeleteConfirmation carries explicit acknowledgement', () {
      final DeleteConfirmation confirmation = DeleteConfirmation(
        title: ' Antrag ',
        acknowledged: true,
      );

      expect(confirmation.title, 'Antrag');
      expect(confirmation.acknowledged, isTrue);
      expect(confirmation.toString(), isNot(contains('Antrag')));
    });

    test('RecoveryStamp validates optional evidence fields', () {
      final RecoveryStamp stamp = RecoveryStamp(
        verifiedRevisionId: fixtureUuid(3),
        committedAt: fixtureAt(),
        headCorrupt: true,
        fellBackToOlderRevision: true,
      );

      expect(stamp.headCorrupt, isTrue);
      expect(stamp.fellBackToOlderRevision, isTrue);
      expect(
        () => RecoveryStamp(
          verifiedRevisionId: 'revision-1',
          headCorrupt: false,
          fellBackToOlderRevision: false,
        ),
        throwsArgumentError,
      );
      expect(
        () => RecoveryStamp(
          committedAt: DateTime(2026, 11, 14, 12),
          headCorrupt: false,
          fellBackToOlderRevision: false,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Export DTOs', () {
    test('ExportOptions defaults to mandated flatten and embedFonts', () {
      final ExportOptions options = ExportOptions();

      expect(options.flatten, isTrue);
      expect(options.embedFonts, isTrue);
      expect(ExportOptions(flatten: true).flatten, isTrue);
      expect(ExportOptions(flatten: true).embedFonts, isTrue);
    });

    test('rejects disabling mandatory flattening', () {
      final Object? caught = _capture(() => ExportOptions(flatten: false));

      expect(caught, isA<ArgumentError>());
      expect(caught.toString(), contains('flatten must be true'));
      expect(caught.toString(), isNot(contains('flatten: false')));
    });

    test('ExportRequest carries the canonical plan and options', () {
      final ExportRequest request = ExportRequest(
        documentId: fixtureUuid(2),
        revisionId: fixtureUuid(3),
        plan: fixtureExportPlan(),
      );

      final ExportPlan plan = request.plan;
      final ExportOptions options = request.options;
      expect(plan.pageCount, 1);
      expect(options.flatten, isTrue);
      expect(request.documentId, fixtureUuid(2));
      expect(
        () => ExportRequest(
          documentId: 'document-1',
          revisionId: fixtureUuid(3),
          plan: fixtureExportPlan(),
        ),
        throwsArgumentError,
      );
      expect(
        () => ExportRequest(
          documentId: fixtureUuid(2),
          revisionId: 'revision-1',
          plan: fixtureExportPlan(),
        ),
        throwsArgumentError,
      );
    });

    test('ExportResult carries the canonical artifact and evidence', () {
      final ExportResult result = ExportResult(
        artifact: fixtureExportArtifact(),
        evidence: fixtureAndroidEvidence(adapterId: 'android.pdfbox.v1'),
      );

      final ExportArtifact artifact = result.artifact;
      final ArtifactVerification? verification = artifact.verification;
      expect(artifact.pageCount, 1);
      expect(verification, isNull);
      expect(result.evidence.evidenceClass, EvidenceClass.none);
      expect(result.toString(), contains('validating'));
    });

    test(
      'ExportValidationResult carries canonical validation and evidence',
      () {
        final ExportValidationResult result = fixtureExportValidationResult();
        final ExportValidation canonical = result.validation;

        expect(canonical.warnings, isEmpty);
        expect(result.isValid, isTrue);
        expect(result.isBlocking, isFalse);
        expect(result.warnings, isEmpty);
        expect(result.evidence.evidenceClass, EvidenceClass.none);
        expect(result.evidence.simulated, isFalse);
      },
    );

    test('ExportValidationResult preserves blocking warnings and evidence', () {
      final ExportValidation blocking = fixtureBlockingExportValidation();
      final ExportValidationResult result = fixtureExportValidationResult(
        validation: blocking,
        evidence: fixtureSimulatedEvidence(adapterId: 'web.sim.export.v1'),
      );

      expect(result.validation, same(blocking));
      expect(result.isValid, isFalse);
      expect(result.isBlocking, isTrue);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single.code, 'EXP-001');
      expect(result.warnings.single.reason, 'too_wide');
      expect(result.warnings.single.pageIndex, 0);
      expect(result.evidence.evidenceClass, EvidenceClass.simulated);
      expect(result.evidence.simulated, isTrue);
      expect(result.toString(), contains('warnings: 1'));
      expect(result.toString(), isNot(contains('Name')));
    });
  });

  group('Delivery and lifecycle DTOs', () {
    test('DeliveryOutcome reports cancellation without an error', () {
      final DeliveryOutcome cancelled = DeliveryOutcome(
        action: DeliveryAction.share,
        completed: false,
        evidence: fixtureAndroidEvidence(),
      );
      final DeliveryOutcome saved = DeliveryOutcome(
        action: DeliveryAction.save,
        completed: true,
        userVisibleLocationHint: ' In „Downloads“ gespeichert ',
        evidence: fixtureAndroidEvidence(),
      );

      expect(cancelled.completed, isFalse);
      expect(saved.userVisibleLocationHint, 'In „Downloads“ gespeichert');
      expect(
        DeliveryAction.values.map((DeliveryAction action) => action.name),
        <String>['save', 'share', 'print'],
      );
    });

    test('DeliveryOutcome rejects internal paths and URIs in the hint', () {
      for (final String invalid in <String>[
        '',
        '/tmp/export.pdf',
        r'C:\export.pdf',
        'content://media/export.pdf',
        'file:///tmp/export.pdf',
        'Zeile\nzwei',
      ]) {
        final Object? caught = _capture(
          () => DeliveryOutcome(
            action: DeliveryAction.save,
            completed: true,
            userVisibleLocationHint: invalid,
            evidence: fixtureAndroidEvidence(),
          ),
        );
        expect(caught, isA<ArgumentError>());
        if (invalid.isNotEmpty) {
          expect(caught.toString(), isNot(contains(invalid)));
        }
      }
    });

    test('AppLifecycleSignal matches the contract order', () {
      expect(
        AppLifecycleSignal.values
            .map((AppLifecycleSignal signal) => signal.name)
            .toList(),
        <String>['resumed', 'inactive', 'paused', 'detached'],
      );
    });
  });
}

Object? _capture(void Function() action) {
  try {
    action();
  } catch (error) {
    return error;
  }
  return null;
}
