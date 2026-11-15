// T028 SIMULATED PDF-export adapter.
//
// The Web surface cannot run PDFBox. `contracts/export-plan.md` §7 therefore
// defines a development applier: the same canonical `ExportPlan` is rendered
// into a preview PDF with overlay ops at display coordinates and every page
// carrying a visible `SIMULATED` watermark plus a German `SIMULATED` footer.
// The artifact is reported with `SIMULATED` evidence and must never be used for
// an Android acceptance or print-fidelity claim.
//
// Determinism: the `pdf` package stamps a random document ID into the trailer.
// The bytes are normalized after rendering by replacing that one ID with a
// deterministic digest of the canonical plan. If the expected trailer shape is
// absent, export fails loudly (`EXP-002`) rather than returning bytes that
// differ between runs.
//
// The optional page-image provider lets the Web bootstrap embed PDFium-rendered
// fixture pages without making this platform-free package depend on `pdfrx`.
// Without it, a clearly labelled placeholder page is used.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'simulated_backend.dart';
import 'simulated_contract.dart';
import 'simulated_digest.dart';

/// Resolves the raster preview for one source page, if the caller has one.
typedef SimulatedPageImageProvider = Uint8List? Function(int pageIndex);

/// Deterministic `PdfExportPort` substitute.
final class SimulatedPdfExportAdapter implements PdfExportPort {
  /// Creates the export adapter.
  ///
  /// [fontBytes] should be the bundled Noto Sans Regular TTF when available;
  /// without it the preview uses the PDF standard Helvetica substitute and the
  /// adapter never claims production font fidelity. [pageImageProvider] may
  /// supply pre-rasterized fixture pages for a more faithful preview.
  SimulatedPdfExportAdapter({
    required this.backend,
    Uint8List? fontBytes,
    this.pageImageProvider,
  }) : fontBytes = fontBytes == null ? null : copyBytes(fontBytes);

  /// Shared simulated backend.
  final SimulatedBackend backend;

  /// Optional Noto Sans Regular bytes for the preview.
  final Uint8List? fontBytes;

  /// Optional pre-rasterized page backgrounds.
  final SimulatedPageImageProvider? pageImageProvider;

  static final CapabilityDescriptor _descriptor = simulatedDescriptor(
    kind: CapabilityKind.pdfExport,
    adapterId: simulatedExportAdapterId,
    supportedFeatures: const <String>[
      'preview-pdf',
      'simulated-watermark',
      'overlay-geometry',
      'deterministic-bytes',
    ],
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  /// Evidence label carried by every export result.
  CapabilityEvidence get evidence => _descriptor.evidence;

  @override
  Future<ExportValidationResult> validate(ExportPlan plan) async {
    return ExportValidationResult(
      validation: ExportValidation(
        warnings: _validatePlan(plan, embeddedFont: fontBytes != null),
        validatedAt: backend.context.nowUtc(),
      ),
      evidence: evidence,
    );
  }

  @override
  Future<ExportResult> export(ExportRequest request) async {
    final ExportPlan plan = request.plan;
    if (request.documentId != plan.documentId ||
        request.revisionId != plan.revisionId) {
      // The request and the plan must identify the same aggregate/revision;
      // otherwise the preview could bind a plan to the wrong source.
      throw ExportFailedException();
    }
    final bool embeddedFont = fontBytes != null && request.options.embedFonts;
    final List<ExportValidationWarning> warnings = _validatePlan(
      plan,
      embeddedFont: embeddedFont,
    );
    if (warnings.isNotEmpty) {
      // `ExportBlockedException` is the canonical `EXP-001` content-blocker;
      // `ExportFailedException` is the canonical `EXP-002` failure. Catalog-only
      // codes such as EXP-003/EXP-004/EXP-005/EXP-006 are carried by the
      // `validate` result (`contracts/ports.md` §3), so export must not invent
      // a second exception class for them. It must, however, keep the
      // classification: a source/page failure is never disguised as a
      // field-level content block just because a field blocker is also found.
      final bool sourceOrPageFailure = warnings.any(
        (ExportValidationWarning warning) =>
            _exportFailureWarningCodes.contains(warning.code),
      );
      if (sourceOrPageFailure) {
        throw ExportFailedException();
      }
      final List<String> fieldIds = _blockingFieldIds(warnings);
      if (fieldIds.isEmpty) {
        throw ExportFailedException();
      }
      throw ExportBlockedException(fieldIds);
    }

    final DateTime createdAt = backend.context.nowUtc();
    ExportArtifact artifact = ExportArtifact.start(
      id: backend.context.newId(),
      documentId: plan.documentId,
      revisionId: plan.revisionId,
      pageCount: plan.pageCount,
      createdAt: createdAt,
    ).startRendering();

    final Uint8List bytes;
    try {
      bytes = await _renderPreview(plan, embeddedFont: embeddedFont);
    } on ExportFailedException {
      rethrow;
    } catch (_) {
      throw ExportFailedException();
    }
    artifact = artifact.startVerification();

    final ArtifactVerification verification = _verifyPreview(
      bytes,
      plan,
      embeddedFont: embeddedFont,
      checkedAt: createdAt,
    );
    if (!verification.pageCountMatches ||
        !verification.mediaBoxesMatch ||
        !verification.fontGlyphsPresent ||
        !verification.noInteractiveFields ||
        !verification.overlayBoundsWithinPage) {
      // Never present a preview whose simulated self-check failed.
      throw ExportFailedException();
    }
    artifact = artifact.succeed(
      byteSize: bytes.length,
      sha256: sha256Hex(bytes),
      verification: verification,
    );
    backend.putArtifact(
      SimulatedArtifactRecord(artifact: artifact, bytes: copyBytes(bytes)),
    );
    return ExportResult(artifact: artifact, evidence: evidence);
  }

  @override
  Future<Uint8List> readArtifact(String artifactId) async {
    final SimulatedArtifactRecord? record = backend.artifact(artifactId);
    if (record == null) {
      throw ExportFailedException();
    }
    final Uint8List copy = copyBytes(record.bytes);
    if (sha256Hex(copy) != record.artifact.sha256) {
      throw ExportFailedException();
    }
    return copy;
  }

  @override
  Future<void> deleteArtifact(String artifactId) async {
    backend.removeArtifact(artifactId);
  }

  /// Performs the simulated applier's own structural checks on the preview.
  ///
  /// The content streams are uncompressed, so the checks inspect the produced
  /// bytes: page objects, MediaBox dimensions, absence of form/widget objects,
  /// and overlay bounds. They are SIMULATED self-checks only; they do not
  /// replace independent PDFBox/Poppler/MuPDF verification (`export-plan.md`
  /// §7).
  ArtifactVerification _verifyPreview(
    Uint8List bytes,
    ExportPlan plan, {
    required bool embeddedFont,
    required DateTime checkedAt,
  }) {
    final String pdf = latin1.decode(bytes);
    final int pageCount = RegExp(r'/Type\s*/Page\b').allMatches(pdf).length;
    final List<RegExpMatch> mediaBoxMatches = RegExp(
      r'/MediaBox\s*\[\s*([0-9.+-]+)\s+([0-9.+-]+)\s+([0-9.+-]+)\s+([0-9.+-]+)\s*\]',
    ).allMatches(pdf).toList(growable: false);
    bool mediaBoxesMatch = mediaBoxMatches.length == plan.pageCount;
    if (mediaBoxesMatch) {
      for (int index = 0; index < plan.pageCount; index++) {
        final RegExpMatch match = mediaBoxMatches[index];
        final double width = double.parse(match.group(3)!);
        final double height = double.parse(match.group(4)!);
        final Size expected = plan.pages[index].geometry.displaySize;
        if ((width - expected.width).abs() > 0.01 ||
            (height - expected.height).abs() > 0.01) {
          mediaBoxesMatch = false;
          break;
        }
      }
    }
    final bool noInteractiveFields =
        !pdf.contains('/AcroForm') && !pdf.contains('/Widget');
    bool overlayBoundsWithinPage = true;
    for (final ExportPage page in plan.pages) {
      final Size display = page.geometry.displaySize;
      for (final ExportOp op in page.ops) {
        if (!_withinDisplay(op.rect, display)) {
          overlayBoundsWithinPage = false;
          break;
        }
      }
    }
    bool fontGlyphsPresent = true;
    for (final ExportPage page in plan.pages) {
      for (final ExportOp op in page.ops) {
        if (op is ExportTextOp &&
            !embeddedFont &&
            !_helveticaCanEncode(op.lines.join('\n'))) {
          fontGlyphsPresent = false;
        }
      }
    }
    return ArtifactVerification(
      pageCountMatches: pageCount == plan.pageCount,
      mediaBoxesMatch: mediaBoxesMatch,
      fontGlyphsPresent: fontGlyphsPresent,
      noInteractiveFields: noInteractiveFields,
      overlayBoundsWithinPage: overlayBoundsWithinPage,
      checkedAt: checkedAt,
    );
  }

  // --- validation ---------------------------------------------------------

  List<ExportValidationWarning> _validatePlan(
    ExportPlan plan, {
    required bool embeddedFont,
  }) {
    final List<ExportValidationWarning> warnings = <ExportValidationWarning>[];
    final SimulatedDocumentRecord? document = backend.document(plan.documentId);
    if (document == null) {
      warnings.add(
        ExportValidationWarning(code: 'EXP-005', reason: 'source_missing'),
      );
      return warnings;
    }
    // Verify the staged source content itself, not only the persisted source
    // reference. `validate` must catch a corrupt backend object before any
    // write, so export cannot silently use bytes that no longer match the
    // recorded SHA-256 (EXP-005, FR-072/FR-073).
    final SimulatedStagedSource? staged = backend.stagedSource(
      document.source.id,
    );
    if (staged == null) {
      warnings.add(
        ExportValidationWarning(code: 'EXP-005', reason: 'source_missing'),
      );
    } else {
      final String actualSourceSha256 = sha256Hex(staged.bytes);
      final bool contentMatches =
          staged.bytes.length == document.source.sizeBytes &&
          actualSourceSha256 == document.source.sha256 &&
          staged.pageCount == document.source.pageCount;
      if (!contentMatches) {
        warnings.add(
          ExportValidationWarning(code: 'EXP-005', reason: 'source_corrupt'),
        );
      } else if (document.source.sha256 != plan.sourceSha256) {
        warnings.add(
          ExportValidationWarning(
            code: 'EXP-005',
            reason: 'source_hash_mismatch',
          ),
        );
      }
    }
    if (document.source.pageCount != plan.pageCount) {
      warnings.add(
        ExportValidationWarning(code: 'EXP-006', reason: 'page_count_mismatch'),
      );
    }
    // Defensive: ExportPlan already enforces length and contiguous indexes,
    // but the applier must not trust a plan that survived a bad import.
    if (plan.pages.length != plan.pageCount) {
      warnings.add(
        ExportValidationWarning(
          code: 'EXP-006',
          reason: 'page_structure_mismatch',
        ),
      );
    }
    for (final ExportPage page in plan.pages) {
      if (page.index < 0 || page.index >= plan.pageCount) {
        warnings.add(
          ExportValidationWarning(
            code: 'EXP-006',
            reason: 'page_index_out_of_range',
            pageIndex: page.index < 0 ? 0 : page.index,
          ),
        );
      }
    }
    final SimulatedRevisionRecord? revision =
        document.revisions[plan.revisionId];
    if (revision == null) {
      warnings.add(
        ExportValidationWarning(
          code: 'EXP-005',
          reason: 'revision_unavailable',
        ),
      );
    }

    for (final ExportPage page in plan.pages) {
      final Size display = page.geometry.displaySize;
      for (final ExportOp op in page.ops) {
        if (!_withinDisplay(op.rect, display)) {
          warnings.add(
            ExportValidationWarning(
              code: 'EXP-003',
              reason: 'outside_page',
              fieldId: op.fieldId,
              pageIndex: page.index,
            ),
          );
          continue;
        }
        switch (op) {
          case ExportTextOp():
            if (op.overflow) {
              warnings.add(
                ExportValidationWarning(
                  code: 'EXP-001',
                  reason: 'text_overflow',
                  fieldId: op.fieldId,
                  pageIndex: page.index,
                ),
              );
            }
            if (op.lines.isEmpty ||
                op.lines.any((String line) => line.trim().isEmpty)) {
              warnings.add(
                ExportValidationWarning(
                  code: 'EXP-001',
                  reason: 'empty_text',
                  fieldId: op.fieldId,
                  pageIndex: page.index,
                ),
              );
            }
            if (!embeddedFont && !_helveticaCanEncode(op.lines.join('\n'))) {
              warnings.add(
                ExportValidationWarning(
                  code: 'EXP-004',
                  reason: 'glyph_missing',
                  fieldId: op.fieldId,
                  pageIndex: page.index,
                ),
              );
            }
          case ExportCheckboxOp():
            // An unchecked box draws nothing, by contract. No extra check.
            break;
          case ExportImageOp():
            if (backend.signatureBytes(plan.documentId, op.assetId) == null) {
              warnings.add(
                ExportValidationWarning(
                  code: 'EXP-005',
                  reason: 'signature_missing',
                  fieldId: op.fieldId,
                  pageIndex: page.index,
                ),
              );
            }
        }
      }
    }
    return List<ExportValidationWarning>.unmodifiable(warnings);
  }

  /// Warning codes that describe an export failure rather than a field block.
  ///
  /// The canonical taxonomy has no separate exception class for these
  /// catalog-only codes; they remain exact in `validate`'s result and export
  /// uses the nearest typed `ExportFailedException` (`EXP-002`).
  static const Set<String> _exportFailureWarningCodes = <String>{
    'EXP-002',
    'EXP-005',
    'EXP-006',
    'SAVE-001',
  };

  static bool _withinDisplay(Rect rect, Size display) {
    const double tolerance = 0.5;
    return rect.left >= -tolerance &&
        rect.top >= -tolerance &&
        rect.right <= display.width + tolerance &&
        rect.bottom <= display.height + tolerance;
  }

  static List<String> _blockingFieldIds(
    List<ExportValidationWarning> warnings,
  ) {
    final List<String> ids = <String>[];
    final Set<String> seen = <String>{};
    final RegExp pattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');
    for (final ExportValidationWarning warning in warnings) {
      final String? id = warning.fieldId;
      if (id != null && pattern.hasMatch(id) && seen.add(id)) {
        ids.add(id);
      }
    }
    return ids;
  }

  // --- preview rendering ---------------------------------------------------

  Future<Uint8List> _renderPreview(
    ExportPlan plan, {
    required bool embeddedFont,
  }) async {
    // Uncompressed content streams make the SIMULATED watermark and footer
    // inspectable in tests and reviews; determinism is unaffected.
    final pw.Document document = pw.Document(compress: false);
    final pw.Font font = embeddedFont
        ? pw.Font.ttf(ByteData.sublistView(fontBytes!))
        : pw.Font.helvetica();
    for (final ExportPage page in plan.pages) {
      final Size display = page.geometry.displaySize;
      final PdfPageFormat format = PdfPageFormat(
        display.width,
        display.height,
        marginAll: 0,
      );
      final Uint8List? pageImage = pageImageProvider?.call(page.index);
      document.addPage(
        pw.Page(
          pageFormat: format,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            return pw.Stack(
              children: <pw.Widget>[
                pw.Positioned.fill(
                  child: pageImage == null
                      ? pw.Container(
                          color: const PdfColor(0.96, 0.96, 0.96),
                          child: pw.Center(
                            child: pw.Text(
                              'Quellseite ${page.index + 1} (SIMULATED)',
                              style: pw.TextStyle(
                                font: font,
                                fontSize: 12,
                                color: const PdfColor(0.6, 0.6, 0.6),
                              ),
                            ),
                          ),
                        )
                      : pw.Image(
                          pw.MemoryImage(pageImage),
                          fit: pw.BoxFit.contain,
                        ),
                ),
                if (pageImage == null)
                  pw.Positioned.fill(
                    child: pw.Center(
                      child: pw.Text(
                        'SIMULATED',
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 42,
                          color: const PdfColor(0.78, 0.78, 0.78),
                        ),
                      ),
                    ),
                  ),
                for (final ExportOp op in page.ops)
                  _opWidget(op, font, plan.documentId),
                pw.Positioned(
                  left: 16,
                  bottom: 12,
                  child: pw.Text(
                    embeddedFont
                        ? 'SIMULATED – kein Produktions-PDF'
                        : 'SIMULATED - kein Produktions-PDF',
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 8,
                      color: const PdfColor(0.55, 0.55, 0.55),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }
    final Uint8List rendered = await document.save();
    return _normalizeDocumentId(rendered, plan);
  }

  pw.Widget _opWidget(ExportOp op, pw.Font font, String documentId) {
    switch (op) {
      case ExportTextOp():
        final double textTop =
            op.rect.top + op.baselineFromTopPt - op.fontSizePt;
        return pw.Positioned(
          left: op.rect.left + 1.5,
          top: textTop < op.rect.top ? op.rect.top : textTop,
          child: pw.SizedBox(
            width: op.rect.width - 3.0,
            child: pw.Text(
              op.lines.join('\n'),
              style: pw.TextStyle(font: font, fontSize: op.fontSizePt),
            ),
          ),
        );
      case ExportCheckboxOp():
        if (!op.checked) {
          return pw.SizedBox();
        }
        return pw.Positioned(
          left: op.rect.left,
          top: op.rect.top,
          child: pw.CustomPaint(
            size: PdfPoint(op.rect.width, op.rect.height),
            painter: (PdfGraphics canvas, PdfPoint size) {
              canvas
                ..setStrokeColor(const PdfColor(0, 0, 0))
                ..setLineWidth(op.strokeWidthPt)
                ..moveTo(op.insetPt, op.insetPt)
                ..lineTo(size.x - op.insetPt, size.y - op.insetPt)
                ..moveTo(size.x - op.insetPt, op.insetPt)
                ..lineTo(op.insetPt, size.y - op.insetPt)
                ..strokePath();
            },
          ),
        );
      case ExportImageOp():
        final Uint8List? bytes = backend.signatureBytes(documentId, op.assetId);
        if (bytes == null) {
          return pw.SizedBox();
        }
        return pw.Positioned(
          left: op.rect.left,
          top: op.rect.top,
          child: pw.SizedBox(
            width: op.rect.width,
            height: op.rect.height,
            child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
          ),
        );
    }
  }

  Uint8List _normalizeDocumentId(Uint8List bytes, ExportPlan plan) {
    final String source = latin1.decode(bytes);
    final RegExp pattern = RegExp(r'/ID\[<([0-9a-f]{64})><([0-9a-f]{64})>\]');
    final List<RegExpMatch> matches = pattern.allMatches(source).toList();
    if (matches.length != 1) {
      throw ExportFailedException();
    }
    if (source.contains('/CreationDate') || source.contains('/ModDate')) {
      throw ExportFailedException();
    }
    final String deterministic = sha256Hex(canonicalJsonBytes(plan.toJson()));
    final RegExpMatch match = matches.single;
    final String normalized = source.replaceRange(
      match.start,
      match.end,
      '/ID[<$deterministic><$deterministic>]',
    );
    return Uint8List.fromList(latin1.encode(normalized));
  }

  /// Whether the built-in Helvetica substitute can draw every code point.
  ///
  /// The PDF standard font is a Latin-1 development substitute, not the bundled
  /// Noto Sans. Typographic dashes and quotes outside Latin-1 are reported as
  /// `EXP-004` unless the caller supplies the bundled font bytes.
  static bool _helveticaCanEncode(String text) {
    for (final int rune in text.runes) {
      if (rune > 0xFF) {
        return false;
      }
    }
    return true;
  }
}
