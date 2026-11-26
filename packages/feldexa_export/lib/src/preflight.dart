// Feldexa export preflight (T113).
//
// Owner: `packages/feldexa_export/lib/src/preflight.dart` (T113).
// Normative sources:
//   * `contracts/export-plan.md` §1 step [1] — unresolved suggestions excluded,
//     empty fields allowed and reported as info, type/value compatibility,
//     date/number canonical form, geometry inside the page bounds;
//   * `contracts/export-plan.md` §3.4 — the empty-field statement and the
//     **ratified** unresolved-suggestion behavior (OD-1/Q1=A, 2026-11-26);
//   * `contracts/export-plan.md` §4 — blocking codes `EXP-001` and `EXP-003`
//     with the warning payload (`fieldId`, `pageIndex`, `fieldLabel`,
//     `reason`);
//   * `contracts/error-catalog.de.md` §4 — the German texts stay in the
//     catalog/ARB; this file returns only codes and machine reasons;
//   * FR-025, FR-062, FR-068.
//
// Provisional behavior (OD-1). Unresolved suggestions never enter the plan and
// are counted in `info.unresolvedSuggestionCount`; they do not block under the
// ratified policy. FR-025 remains binding for review: the UI still has to
// surface overlapping or conflicting suggestions and require a decision. No
// caller may treat the count as a settled export policy.
//
// Rejected suggestions and rejected fields never appear: the plan is built
// from `Document.fields`, which is the confirmed field set only.
library;

import 'package:feldexa_core/feldexa_core.dart';

import 'model/export_plan.dart';

/// One confirmed field with the snapshot content that will be exported.
///
/// [value] is the committed value (null when the field is still empty) and
/// [signatureMark] is the capture reference of a signature field.
final class ExportPreflightField {
  const ExportPreflightField({
    required this.field,
    this.value,
    this.signatureMark,
  });

  /// The confirmed field.
  final ConfirmedField field;

  /// The committed value, or null when the field is empty.
  final FieldValue? value;

  /// The signature capture of a signature field, or null.
  final SignatureMark? signatureMark;

  @override
  String toString() => 'ExportPreflightField(fieldId: ${field.id})';
}

/// The preflight outcome: blocking warnings plus the pre-export information.
///
/// [validation] carries every blocking warning in document field order. When
/// [isBlocking] is true no plan may be built; [fields] is still the complete
/// confirmed field list so a caller can report every affected field.
final class ExportPreflightResult {
  const ExportPreflightResult({
    required this.validation,
    required this.emptyFieldCount,
    required this.unresolvedSuggestionCount,
    required this.fields,
  });

  /// Blocking warnings; empty means the snapshot may be laid out.
  final ExportValidation validation;

  /// Confirmed fields without renderable content (never blocking).
  final int emptyFieldCount;

  /// Unresolved suggestions excluded and warned (OD-1/Q1=A; never blocking).
  final int unresolvedSuggestionCount;

  /// Every confirmed field in document order.
  final List<ExportPreflightField> fields;

  /// Whether at least one blocking warning exists.
  bool get isBlocking => validation.isBlocking;

  @override
  String toString() =>
      'ExportPreflightResult(warnings: ${validation.warnings.length}, '
      'empty: $emptyFieldCount, unresolved: $unresolvedSuggestionCount)';
}

/// Runs the shared export preflight of `contracts/export-plan.md` §1 step [1].
///
/// The engine is pure Dart and reads only the supplied snapshot; it has no
/// Flutter, platform, file-system, or font dependency. Layout, glyph coverage,
/// and overflow detection happen afterwards in the layout stage.
final class ExportPreflight {
  /// Creates a preflight engine.
  const ExportPreflight();

  /// Validates one confirmed document snapshot.
  ///
  /// [pageGeometries] is the authoritative page geometry of the export (as
  /// parsed from the source), indexed by page; it must cover every document
  /// page. [values] and [signatures] are the snapshot content, and
  /// [validatedAt] must be UTC.
  ///
  /// Throws [ArgumentError] for a page-geometry count that does not match the
  /// document, or for content that references an unknown confirmed field.
  /// Both would silently drop entered content (FR-038), so they fail closed.
  ExportPreflightResult run({
    required Document document,
    required Iterable<PageGeometry> pageGeometries,
    required Map<String, FieldValue> values,
    required Map<String, SignatureMark> signatures,
    required DateTime validatedAt,
  }) {
    final List<PageGeometry> pages = pageGeometries.toList(growable: false);
    if (pages.length != document.pages.length) {
      throw ArgumentError('pageGeometries must cover every document page');
    }
    final Set<String> fieldIds = <String>{
      for (final ConfirmedField field in document.fields) field.id,
    };
    for (final String fieldId in values.keys) {
      if (!fieldIds.contains(fieldId)) {
        throw ArgumentError('values reference an unknown confirmed field');
      }
    }
    for (final String fieldId in signatures.keys) {
      if (!fieldIds.contains(fieldId)) {
        throw ArgumentError('signatures reference an unknown confirmed field');
      }
    }

    final List<ExportValidationWarning> warnings = <ExportValidationWarning>[];
    final List<ExportPreflightField> fields = <ExportPreflightField>[];
    int emptyFieldCount = 0;
    for (final ConfirmedField field in document.fields) {
      final FieldValue? value = values[field.id];
      final SignatureMark? signatureMark = signatures[field.id];
      fields.add(
        ExportPreflightField(
          field: field,
          value: value,
          signatureMark: signatureMark,
        ),
      );
      if (_isEmpty(field, value)) {
        emptyFieldCount++;
      }
      warnings.addAll(
        _checkField(
          field: field,
          value: value,
          signatureMark: signatureMark,
          pages: pages,
        ),
      );
    }
    final int unresolvedSuggestionCount = document.suggestions
        .where(
          (FieldSuggestion suggestion) =>
              suggestion.resolution == SuggestionResolution.unresolved,
        )
        .length;
    return ExportPreflightResult(
      validation: ExportValidation(
        warnings: warnings,
        validatedAt: validatedAt,
      ),
      emptyFieldCount: emptyFieldCount,
      unresolvedSuggestionCount: unresolvedSuggestionCount,
      fields: List<ExportPreflightField>.unmodifiable(fields),
    );
  }

  List<ExportValidationWarning> _checkField({
    required ConfirmedField field,
    required FieldValue? value,
    required SignatureMark? signatureMark,
    required List<PageGeometry> pages,
  }) {
    ExportValidationWarning warning(String code, String reason) {
      return ExportValidationWarning(
        code: code,
        reason: reason,
        fieldId: field.id,
        pageIndex: field.pageIndex,
        fieldLabel: field.label,
      );
    }

    if (field.pageIndex >= pages.length) {
      // A field without a page has no display box to verify against; the
      // document aggregate refuses this state, so it can only come from a
      // stale snapshot.
      return <ExportValidationWarning>[warning('EXP-003', 'outside_page')];
    }
    final List<ExportValidationWarning> warnings = <ExportValidationWarning>[];
    final Size displaySize = pages[field.pageIndex].displaySize;
    if (_overshootPt(field.rect, displaySize) > pageBoundsTolerance) {
      warnings.add(warning('EXP-003', 'outside_page'));
    }
    if (field.validation.isError) {
      warnings.add(warning('EXP-001', 'field_validation_error'));
    }
    switch (value) {
      case null:
        break;
      case IncompatibleValue():
        // Preserved content after a type change is only exportable once the
        // user resolved it (`data-model.md` §3.5, FLD-002).
        warnings.add(warning('EXP-001', 'incompatible_value'));
      case final FieldValue committed:
        // §1 step [1] type/value compatibility. The canonical number and date
        // forms are already enforced when the value is constructed (T080,
        // T081), so compatibility is the complete preflight condition here.
        if (committed.type != field.type) {
          warnings.add(warning('EXP-001', 'value_type_mismatch'));
        }
    }
    if (field.type == FieldType.signature && value is SignatureValue) {
      if (signatureMark == null ||
          signatureMark.assetId != value.signatureAssetId) {
        warnings.add(warning('EXP-001', 'signature_asset_missing'));
      }
    }
    return warnings;
  }
}

/// Whether a confirmed field carries no renderable content (§3.4).
///
/// An empty field never blocks export; the count is shown before export. A
/// checkbox is never empty: unchecked is a decided state, not missing content,
/// and an unset checkbox value renders no mark (§3.2). A signature field only
/// has content once a mark exists.
bool _isEmpty(ConfirmedField field, FieldValue? value) {
  if (field.type == FieldType.checkbox) {
    return false;
  }
  return switch (value) {
    null => true,
    TextValue() => value.text.trim().isEmpty,
    MultilineValue() => value.text.trim().isEmpty,
    _ => false,
  };
}

/// The largest display-box overshoot tolerated without blocking (§4, EXP-003).
double _overshootPt(Rect rect, Size displaySize) {
  return <double>[
    -rect.left,
    -rect.top,
    rect.right - displaySize.width,
    rect.bottom - displaySize.height,
  ].reduce((double left, double right) => left > right ? left : right);
}
