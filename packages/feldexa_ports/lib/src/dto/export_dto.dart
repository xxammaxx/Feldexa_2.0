// T013 `PdfExportPort` request and result DTOs.
//
// Owner: `packages/feldexa_ports/lib/src/dto/export_dto.dart` (T013).
// Normative source: `contracts/ports.md` §2.5 and §2.10.
//
// `ExportPlan`, `ExportValidation`, `ExportArtifact`, and `ArtifactVerification`
// are canonical `feldexa_export` contract models owned by T022. This file only
// consumes them; it must not redeclare or wrap them in a second model.

import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/evidence.dart';

import 'validation.dart';

/// Flattening and font options for one export (`contracts/ports.md` §2.10).
///
/// Both flags default to true: the release artifact is flattened and
/// self-contained, and bundled font glyphs are embedded.
final class ExportOptions {
  /// Creates export options.
  const ExportOptions({this.flatten = true, this.embedFonts = true});

  /// Whether interactive form structure is flattened into page content.
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
    ExportOptions options = const ExportOptions(),
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
