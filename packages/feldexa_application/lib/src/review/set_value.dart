// T071A confirmed-field value command.
//
// Owner: `packages/feldexa_application/lib/src/review/set_value.dart` (T071A,
// issue #244).
//
// Normative sources:
//   * `spec.md` FR-033/FR-035/FR-038/FR-039/FR-040/FR-045 and FR-046 — a
//     corrected value is validated, saved, and never truncated;
//   * `contracts/editor-interactions.md` §5 — the type-appropriate filling
//     control commits one value and invalid input is never stored;
//   * `data-model.md` §3.5–§3.6 and §3.12 — `FieldValue` variants and the
//     `RevisionContent` snapshot;
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// The command is pure: it reads no clock, generates no id, performs no I/O,
// and mutates neither the revision nor the supplied value. The caller supplies
// the UTC edit instant explicitly. Every failure is an `ArgumentError` with a
// fixed, content-free message: no id, label, or field value is echoed.
//
// Only `values[fieldId]` changes. Pages, suggestions, confirmed fields,
// field order, signature marks, verification records, template origin, and
// unknown same-schema JSON fields are copied to a fresh, validated
// `RevisionContent` unchanged.

import 'package:feldexa_core/feldexa_core.dart';

/// An immutable receipt for one successful value update.
///
/// [content] is the complete new revision snapshot; [previousContent] is the
/// exact input snapshot a later undo can restore. [value] is the stored value
/// carrying [lastEditedAt]; [previousValue] is the value that was replaced, or
/// null when the field had no value before. Nothing here is persisted by the
/// command itself.
final class SetValueChange {
  /// Creates a value-change receipt.
  const SetValueChange({
    required this.content,
    required this.previousContent,
    required this.fieldId,
    required this.value,
    required this.previousValue,
  });

  /// The new, fully validated revision snapshot.
  final RevisionContent content;

  /// The unchanged input snapshot.
  final RevisionContent previousContent;

  /// The id of the confirmed field that was updated.
  final String fieldId;

  /// The stored value with [lastEditedAt] stamped.
  final FieldValue value;

  /// The value that was replaced, or null when the field had no value.
  final FieldValue? previousValue;
}

/// Replaces the committed value of one confirmed field.
///
/// [fieldId] must name an existing confirmed field. [value] must be the
/// matching concrete `FieldValue` for that field's type:
/// `text` → `TextValue`, `multiline` → `MultilineValue`, `number` →
/// `NumberValue`, `date` → `DateValue`, `checkbox` → `CheckboxValue`, and
/// `signature` → `SignatureValue`. An `IncompatibleValue` is preserved content,
/// not a new edit, and is rejected here.
///
/// [lastEditedAt] must be UTC and is stamped onto the stored value. The
/// command replaces only `values[fieldId]`; every other revision member is
/// copied unchanged. The text is never truncated.
///
/// Throws [ArgumentError] for a missing field, a type mismatch, a non-UTC
/// instant, or any invalid value. The message never contains document content.
SetValueChange setFieldValue(
  RevisionContent content,
  String fieldId, {
  required FieldValue value,
  required DateTime lastEditedAt,
}) {
  if (!lastEditedAt.isUtc) {
    throw ArgumentError('lastEditedAt must be UTC');
  }
  ConfirmedField? field;
  for (final ConfirmedField candidate in content.fields) {
    if (candidate.id == fieldId) {
      field = candidate;
      break;
    }
  }
  if (field == null) {
    throw ArgumentError('the field is not present in the revision');
  }
  if (value.type != field.type) {
    throw ArgumentError('the value type does not match the field type');
  }
  final FieldValue stored = value.copyWithMetadata(lastEditedAt: lastEditedAt);
  final Map<String, FieldValue> values = <String, FieldValue>{
    for (final MapEntry<String, FieldValue> entry in content.values.entries)
      entry.key: entry.value,
    fieldId: stored,
  };
  final RevisionContent updated = RevisionContent(
    pages: content.pages,
    suggestions: content.suggestions,
    fields: content.fields,
    fieldOrder: content.fieldOrder,
    values: values,
    signatures: content.signatures,
    verification: content.verification,
    templateOrigin: content.templateOrigin,
    unknownFields: content.unknownFields,
  );
  return SetValueChange(
    content: updated,
    previousContent: content,
    fieldId: fieldId,
    value: stored,
    previousValue: content.values[fieldId],
  );
}
