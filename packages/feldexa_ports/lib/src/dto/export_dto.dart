// T013 `PdfExportPort` request and result DTOs.
//
// Owner: `packages/feldexa_ports/lib/src/dto/export_dto.dart` (T013).
// Normative source: `contracts/ports.md` §2.5 and §2.10.
//
// `ExportPlan`, `ExportValidation`, `ExportArtifact`, and `ArtifactVerification`
// are canonical `feldexa_export` contract models owned by T022. This file only
// consumes them; the T013-owned `ExportValidationResult` wraps the canonical
// `ExportValidation` to attach `CapabilityEvidence` and must not redeclare,
// reshape, or duplicate that canonical type.

import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/evidence.dart';

import 'validation.dart';

/// Flattening and font options for one export (`contracts/ports.md` §2.10).
///
/// [flatten] is always true: `contracts/ports.md` §2.5 and FR-069 require the
/// exported PDF to be flattened with no AcroForm widgets, so the option cannot
/// disable flattening. [embedFonts] defaults to true so the artifact is
/// self-contained.
final class ExportOptions {
  /// Creates export options.
  ///
  /// [flatten] must be true; a false value throws a safe [ArgumentError]
  /// because it would request an unflattened artifact. [embedFonts] defaults to
  /// true.
  factory ExportOptions({bool flatten = true, bool embedFonts = true}) {
    if (!flatten) {
      throw ArgumentError(
        'flatten must be true; the exported PDF is always flattened',
      );
    }
    return ExportOptions._(flatten: flatten, embedFonts: embedFonts);
  }

  const ExportOptions._({required this.flatten, required this.embedFonts});

  static const ExportOptions _defaults = ExportOptions._(
    flatten: true,
    embedFonts: true,
  );

  /// Whether interactive form structure is flattened into page content.
  ///
  /// Always true; the constructor rejects false.
  final bool flatten;

  /// Whether bundled font glyphs are embedded in the artifact.
  final bool embedFonts;

  @override
  String toString() {
    return 'ExportOptions(flatten: $flatten, embedFonts: $embedFonts)';
  }
}

/// One export attempt request (`contracts/ports.md` §2.5).
final class ExportRequest {
  /// Creates an export request.
  ///
  /// [documentId] and [revisionId] are lowercase UUIDv4 values. Invalid values
  /// throw a safe [ArgumentError].
  factory ExportRequest({
    required String documentId,
    required String revisionId,
    required ExportPlan plan,
    ExportOptions options = ExportOptions._defaults,
  }) {
    return ExportRequest._(
      documentId: requireUuidV4(documentId, 'documentId'),
      revisionId: requireUuidV4(revisionId, 'revisionId'),
      plan: plan,
      options: options,
    );
  }

  const ExportRequest._({
    required this.documentId,
    required this.revisionId,
    required this.plan,
    required this.options,
  });

  /// UUIDv4 of the document being exported.
  final String documentId;

  /// UUIDv4 of the revision the plan was built from.
  final String revisionId;

  /// The deterministic export plan from `contracts/export-plan.md`.
  final ExportPlan plan;

  /// Flattening and font options; defaults are `flatten` and `embedFonts`.
  final ExportOptions options;

  @override
  String toString() {
    return 'ExportRequest(pageCount: ${plan.pageCount}, '
        'flatten: ${options.flatten})';
  }
}

/// The result of a completed export (`contracts/ports.md` §2.5).
///
/// The artifact is canonical `feldexa_export` data; [evidence] classifies the
/// adapter run that produced it.
final class ExportResult {
  /// Creates an export result.
  const ExportResult({required this.artifact, required this.evidence});

  /// The verified or failed artifact record.
  final ExportArtifact artifact;

  /// Evidence class of the adapter that produced this result.
  final CapabilityEvidence evidence;

  @override
  String toString() {
    return 'ExportResult(state: ${artifact.state.wireName})';
  }
}

/// The result of `PdfExportPort.validate` (`contracts/ports.md` §2.5).
///
/// [validation] remains the canonical T022 `feldexa_export` model with its
/// blocking warnings and UTC validation time. This T013-owned wrapper only
/// attaches the [evidence] required by §1 for an acceptance-relevant result; it
/// does not duplicate or reshape the canonical validation type.
final class ExportValidationResult {
  /// Creates a validation result.
  const ExportValidationResult({
    required this.validation,
    required this.evidence,
  });

  /// The canonical T022 validation, including its blocking warnings.
  final ExportValidation validation;

  /// Evidence class of the adapter that produced this validation.
  final CapabilityEvidence evidence;

  /// Whether the canonical validation has no blocking warning.
  bool get isValid => validation.isValid;

  /// Whether the canonical validation blocks export.
  bool get isBlocking => validation.isBlocking;

  /// Blocking warnings in the canonical validation order.
  ///
  /// The list is the canonical, unmodifiable warning list; [fieldLabel] values
  /// are user content and are never logged by this wrapper.
  List<ExportValidationWarning> get warnings => validation.warnings;

  @override
  String toString() {
    return 'ExportValidationResult(isValid: $isValid, '
        'warnings: ${warnings.length})';
  }
}
