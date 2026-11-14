// T013 `PdfExportPort` interface.
//
// Owner: `packages/feldexa_ports/lib/src/ports/pdf_export_port.dart` (T013).
// Normative sources:
//   * `contracts/ports.md` §2.5 — the export interface;
//   * `contracts/export-plan.md` — the canonical plan and validation models;
//   * FR-068/FR-072/FR-073 — blocking validation, verified output, and an
//     unchanged source.
//
// `ExportPlan`, `ExportValidation`, `ExportArtifact`, and `ArtifactVerification`
// are owned by T022 in `feldexa_export`; this port only consumes them. The
// T013-owned `ExportValidationResult` wraps the canonical validation to attach
// the adapter evidence required by `contracts/ports.md` §1.
//
// `feldexa_export` never imports `feldexa_ports`: the wrapper lives on the ports
// side of the one-way dependency boundary.

import 'dart:typed_data';

import 'package:feldexa_export/feldexa_export.dart';

import '../descriptor.dart';
import '../dto/export_dto.dart';

/// Validates an export plan and produces a flattened, verified PDF
/// (`contracts/ports.md` §2.5).
abstract interface class PdfExportPort implements PlatformCapability {
  /// Returns the canonical blocking warnings plus the adapter evidence before
  /// any file is written (FR-068 and `contracts/ports.md` §1).
  ///
  /// The warnings remain the canonical T022 `ExportValidation` data; the
  /// wrapper only labels the result with [CapabilityEvidence] so a simulated
  /// preflight is never reported as a real one.
  Future<ExportValidationResult> validate(ExportPlan plan);

  /// Exports the planned pages and verifies the produced artifact.
  ///
  /// A failed export throws `ExportBlockedException` or
  /// `ExportFailedException`; a partial file is never reported as success
  /// (FR-072). The source document and stored working document are never
  /// modified (FR-073).
  Future<ExportResult> export(ExportRequest request);

  /// Reads the artifact bytes for preview, bounded in size.
  Future<Uint8List> readArtifact(String artifactId);

  /// Deletes one exported artifact.
  Future<void> deleteArtifact(String artifactId);
}
