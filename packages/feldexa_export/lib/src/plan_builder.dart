// Feldexa export plan builder (T102).
//
// Owner: `packages/feldexa_export/lib/src/plan_builder.dart` (T102).
// Normative sources:
//   * `contracts/export-plan.md` §1 pipeline — confirmed fields and values are
//     preflighted, laid out, and only then turned into the canonical plan;
//   * `contracts/export-plan.md` §2.1 — deterministic op order (by field
//     order, one op per field), page fields, and the canonical JSON shape;
//   * `contracts/export-plan.md` §2.3 — forbidden plan content: no values for
//     unconfirmed fields, no suggestion/OCR text, no labels beyond warnings,
//     no paths/URIs/device names, no interactive form definitions;
//   * `contracts/export-plan.md` §3.4 — `info` counts for empty fields and
//     ratified exclusion of unresolved suggestions (OD-1/Q1=A);
//   * `contracts/coordinates-and-geometry.md` §5 — the display→PDF CTM and the
//     per-op `pdfRect` derived from the page geometry;
//   * FR-062, FR-068, FR-069.
//
// A blocking warning never produces a plan: [ExportPlanBuilder.build] returns
// the blocking [ExportValidation] instead. The builder writes no PDF
// operators, no files, and no platform calls, so Android, Web, and the host VM
// produce the same plan for the same snapshot.
library;

import 'package:feldexa_core/feldexa_core.dart';

import 'layout.dart';
import 'model/export_plan.dart';
import 'preflight.dart';

/// The result of one plan build.
sealed class ExportPlanBuildResult {
  const ExportPlanBuildResult();
}

/// A canonical plan was produced.
final class ExportPlanBuildSuccess extends ExportPlanBuildResult {
  const ExportPlanBuildSuccess({
    required this.plan,
    required this.trimmedTrailingSpaceCount,
  });

  /// The canonical, deterministic export plan.
  final ExportPlan plan;

  /// Trailing whitespace characters removed from planned line ends.
  ///
  /// The same value is recorded in `plan.info.trimmedTrailingSpaceCount`
  /// (`contracts/export-plan.md` §3.1); it is repeated here so a caller can
  /// report the pre-export information without re-reading the plan.
  final int trimmedTrailingSpaceCount;

  @override
  String toString() => 'ExportPlanBuildSuccess(plan: $plan)';
}

/// The snapshot cannot be exported; no plan exists.
final class ExportPlanBuildBlocked extends ExportPlanBuildResult {
  const ExportPlanBuildBlocked(this.validation);

  /// The blocking warnings, each naming its field and machine reason.
  final ExportValidation validation;

  @override
  String toString() =>
      'ExportPlanBuildBlocked(warnings: ${validation.warnings.length})';
}

/// Builds the canonical export plan from a confirmed document snapshot.
///
/// Preflight and layout are the shared stages of `contracts/export-plan.md`
/// §1; this class only assembles their results into the T022 plan models and
/// maps every op rect to PDF user space.
final class ExportPlanBuilder {
  /// Creates a builder over the bundled font metrics.
  const ExportPlanBuilder({required this.metrics});

  /// The advance table and font contract of the produced plan.
  final ExportFontMetrics metrics;

  /// Builds the plan for one confirmed snapshot.
  ///
  /// [pageGeometries] is the authoritative page geometry of the export and
  /// must cover every document page. [values] and [signatures] are the
  /// snapshot content, [evidenceClass] is one of the plan evidence tokens, and
  /// [sourceSha256] plus [revisionId] identify the immutable source and the
  /// exported revision. [validatedAt] must be UTC.
  ///
  /// Returns [ExportPlanBuildBlocked] instead of a plan for every blocking
  /// warning (FR-068): an overflowing, unplaceable, or unrenderable value is
  /// never silently shrunk, truncated, or omitted (FR-038). Throws
  /// [ArgumentError] for a snapshot that cannot be exported at all (for
  /// example a page-geometry count mismatch or an invalid evidence token).
  ExportPlanBuildResult build({
    required Document document,
    required Iterable<PageGeometry> pageGeometries,
    required Map<String, FieldValue> values,
    required Map<String, SignatureMark> signatures,
    required String evidenceClass,
    required String sourceSha256,
    required String revisionId,
    required DateTime validatedAt,
  }) {
    final List<PageGeometry> pages = pageGeometries.toList(growable: false);
    // The plan is built for the document's own confirmed content. A different
    // map here would silently drop or invent entered values in the artifact
    // (FR-038), so anything but the document's own content fails closed.
    _requireDocumentContent(
      document: document,
      values: values,
      signatures: signatures,
    );
    final ExportPreflightResult preflight = const ExportPreflight().run(
      document: document,
      pageGeometries: pages,
      values: values,
      signatures: signatures,
      validatedAt: validatedAt,
    );
    if (preflight.isBlocking) {
      return ExportPlanBuildBlocked(preflight.validation);
    }

    final ExportLayout layout = ExportLayout(metrics: metrics);
    final List<List<ExportOp>> opsByPage = <List<ExportOp>>[
      for (int index = 0; index < pages.length; index++) <ExportOp>[],
    ];
    final List<ExportValidationWarning> warnings = <ExportValidationWarning>[];
    int trimmedTrailingSpaceCount = 0;
    // `document.fields` is the confirmed set in field order, so appending one
    // op per field yields the §2.1 deterministic order across pages.
    for (final ExportPreflightField entry in preflight.fields) {
      final ConfirmedField field = entry.field;
      final ExportFieldLayout fieldLayout = layout.layoutField(
        field: field,
        geometry: pages[field.pageIndex],
        value: entry.value,
        signatureMark: entry.signatureMark,
      );
      trimmedTrailingSpaceCount += fieldLayout.trimmedTrailingSpaceCount;
      if (fieldLayout.isBlocking) {
        warnings.addAll(fieldLayout.warnings);
        continue;
      }
      final ExportOp? op = fieldLayout.op;
      if (op != null) {
        opsByPage[field.pageIndex].add(op);
      }
    }
    if (warnings.isNotEmpty) {
      return ExportPlanBuildBlocked(
        ExportValidation(warnings: warnings, validatedAt: validatedAt),
      );
    }

    final ExportPlan plan = ExportPlan(
      documentId: document.id,
      revisionId: revisionId,
      sourceSha256: sourceSha256,
      pageCount: pages.length,
      evidenceClass: evidenceClass,
      font: metrics.toExportFont(),
      pages: <ExportPage>[
        for (int index = 0; index < pages.length; index++)
          ExportPage(
            index: index,
            geometry: pages[index],
            ops: opsByPage[index],
          ),
      ],
      info: ExportPlanInfo(
        emptyFieldCount: preflight.emptyFieldCount,
        unresolvedSuggestionCount: preflight.unresolvedSuggestionCount,
        // `contracts/export-plan.md` §3.1 names this counter in `info`; the
        // T022 model models only the two blocking-neutral counts, so the
        // contract-named counter travels as a same-schema extension.
        unknownFields: trimmedTrailingSpaceCount == 0
            ? const <String, Object?>{}
            : <String, Object?>{
                'trimmedTrailingSpaceCount': trimmedTrailingSpaceCount,
              },
      ),
    );
    return ExportPlanBuildSuccess(
      plan: plan,
      trimmedTrailingSpaceCount: trimmedTrailingSpaceCount,
    );
  }
}

/// Refuses snapshot content that is not the document's own content.
void _requireDocumentContent({
  required Document document,
  required Map<String, FieldValue> values,
  required Map<String, SignatureMark> signatures,
}) {
  bool sameFieldValues =
      values.length == document.values.length &&
      values.entries.every(
        (MapEntry<String, FieldValue> entry) =>
            document.values[entry.key] == entry.value,
      );
  if (!sameFieldValues) {
    throw ArgumentError('values must be the document snapshot values');
  }
  bool sameSignatures =
      signatures.length == document.signatures.length &&
      signatures.entries.every(
        (MapEntry<String, SignatureMark> entry) =>
            document.signatures[entry.key] == entry.value,
      );
  if (!sameSignatures) {
    throw ArgumentError('signatures must be the document snapshot signatures');
  }
}
