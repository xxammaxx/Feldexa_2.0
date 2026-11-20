// T085 per-field completion state for optional and empty fields.
//
// Owner: `apps/feldexa_app/lib/features/editor/field_completion.dart` (T085,
// issue #85).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/spec.md` FR-041 (the document overview
//     shows per-field completion state);
//   * `specs/001-scanned-form-workflow/contracts/editor-interactions.md`
//     section 3 (the review list includes completion) and section 7 (the
//     document overview shows per-field completion and durability);
//   * `specs/001-scanned-form-workflow/data-model.md` section 3.6
//     (`FieldValue` variants) and section 3.8 (`FieldVerification` warnings);
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// What this file is
// -----------------
// A pure classifier for one confirmed field. It maps the canonical
// `FieldValidation` and the optional committed `FieldValue` to exactly one
// `FieldCompletionState`. It reads no editor state, opens no document or
// store, performs no I/O, uses no clock, and logs no content. The overview and
// any later caller map the returned state to German ARB text; this file
// authors no user-facing string, ARB key, or label.
//
// Precedence
// ----------
// A blocking validation error wins over everything. Otherwise preserved
// incompatible content wins over a warning. Otherwise a warning wins over the
// value semantics, so an empty optional field with a warning is `warning`, not
// `optionalEmpty`. Only then does the value decide completion.
//
// Optional empty
// --------------
// An absent value or empty/whitespace-only text is `optionalEmpty`. That is a
// valid optional field state, not a defect: it is neither blocking nor a
// failure, and it counts as complete for progress and overview purposes. An
// unchecked checkbox is an explicit state and is `complete`, not empty.
//
// Fail closed
// -----------
// `FieldValue` is a sealed model today. The final branch still returns
// `blockingError` for any future variant instead of throwing or silently
// counting it as complete, so extending the model cannot make an unknown value
// disappear from the overview.
//
// Evidence
// --------
// Covered by host-VM tests only (`test/field_completion_test.dart`). It makes
// no Android, device, screen-reader, or visual claim and produces no evidence
// above class NONE.

library;

import 'package:feldexa_core/feldexa_core.dart' as core;

/// The completion state of one field for the document overview (FR-041).
///
/// Exactly one value describes a field. Use
/// [FieldCompletionStateSemantics.isBlocking] and
/// [FieldCompletionStateSemantics.countsAsComplete] to gate or count on the
/// state; this file deliberately adds no separate count helper.
enum FieldCompletionState {
  /// The field holds a usable, non-empty value.
  complete,

  /// An optional field has no value.
  ///
  /// This is a valid optional state, not a defect: it counts as complete and
  /// is not blocking. An unchecked checkbox is not optional-empty; it is
  /// [complete].
  optionalEmpty,

  /// A blocking validation error must be corrected before export.
  blockingError,

  /// A non-blocking validation warning is shown and the value is kept.
  warning,

  /// Content was preserved after an incompatible reclassification.
  ///
  /// The preserved content needs an explicit user decision, so this state is
  /// blocking even when the preserved text is non-empty.
  incompatible,
}

/// Semantic predicates for [FieldCompletionState].
///
/// These two getters are the only counting primitive for the overview.
extension FieldCompletionStateSemantics on FieldCompletionState {
  /// Whether this state blocks progress or export.
  ///
  /// True exactly for [FieldCompletionState.blockingError] and
  /// [FieldCompletionState.incompatible].
  bool get isBlocking =>
      this == FieldCompletionState.blockingError ||
      this == FieldCompletionState.incompatible;

  /// Whether this state counts as completed for progress and overview.
  ///
  /// True exactly for [FieldCompletionState.complete],
  /// [FieldCompletionState.optionalEmpty], and [FieldCompletionState.warning].
  /// Optional-empty is a valid optional field state and is not a defect; it
  /// counts as complete and is not blocking.
  bool get countsAsComplete =>
      this == FieldCompletionState.complete ||
      this == FieldCompletionState.optionalEmpty ||
      this == FieldCompletionState.warning;
}

/// Classifies one field from its validation and committed value (FR-041).
///
/// The precedence is fixed:
///
/// 1. [core.FieldValidation.isError] yields
///    [FieldCompletionState.blockingError], regardless of the value.
/// 2. A [core.IncompatibleValue] yields [FieldCompletionState.incompatible],
///    regardless of whether the preserved text is empty, and before a warning.
/// 3. [core.FieldValidation.isWarning] yields [FieldCompletionState.warning],
///    regardless of the value; an empty optional field with a warning is
///    [FieldCompletionState.warning], not
///    [FieldCompletionState.optionalEmpty].
/// 4. Otherwise the value decides:
///    * `null`, or a [core.TextValue] or [core.MultilineValue] whose text is
///      empty or whitespace-only, yields
///      [FieldCompletionState.optionalEmpty];
///    * non-empty text and multiline text, both checkbox states,
///      [core.NumberValue], [core.DateValue], and [core.SignatureValue] yield
///      [FieldCompletionState.complete].
///
/// A future [core.FieldValue] variant that this classifier does not know
/// yields [FieldCompletionState.blockingError] instead of throwing or counting
/// as complete, so the classification fails closed.
///
/// The function is deterministic and has no side effects: it performs no I/O,
/// reads no clock, persists nothing, calls no network, reads no editor state,
/// and logs no content.
FieldCompletionState fieldCompletionState({
  required core.FieldValidation validation,
  required core.FieldValue? value,
}) {
  if (validation.isError) {
    return FieldCompletionState.blockingError;
  }
  if (value is core.IncompatibleValue) {
    return FieldCompletionState.incompatible;
  }
  if (validation.isWarning) {
    return FieldCompletionState.warning;
  }
  if (value == null) {
    return FieldCompletionState.optionalEmpty;
  }
  if (value is core.TextValue) {
    return value.text.trim().isEmpty
        ? FieldCompletionState.optionalEmpty
        : FieldCompletionState.complete;
  }
  if (value is core.MultilineValue) {
    return value.text.trim().isEmpty
        ? FieldCompletionState.optionalEmpty
        : FieldCompletionState.complete;
  }
  if (value is core.CheckboxValue ||
      value is core.NumberValue ||
      value is core.DateValue ||
      value is core.SignatureValue) {
    return FieldCompletionState.complete;
  }
  // Fail closed for a future FieldValue variant: the sealed model has no other
  // variant today, but an extended model must neither throw nor count as
  // complete.
  return FieldCompletionState.blockingError;
}
