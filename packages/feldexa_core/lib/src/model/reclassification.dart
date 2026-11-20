// Feldexa core reclassification rules (T019).
//
// Owner: `packages/feldexa_core/lib/src/model/reclassification.dart` (T019,
// issue #19).
//
// Normative sources:
//   * `spec.md` FR-029 — a type change preserves compatible entered content and
//     flags incompatible content instead of discarding it;
//   * `spec.md` FR-038 — entered information is never silently truncated,
//     dropped, reordered, or omitted;
//   * `spec.md` FR-110 — a date field reclassified as text accepts free text
//     without date validation;
//   * `data-model.md` §3.5 — the reclassification matrix for
//     text ⇄ multiline, text → number/date, number/date → text,
//     text/number/date → checkbox, and → signature;
//   * `data-model.md` §3.6 — the `FieldValue` tagged union, `IncompatibleValue`,
//     and the warning/error vocabulary;
//   * `data-model.md` §5 — a value matches its field type or is flagged
//     incompatible;
//   * `contracts/error-catalog.de.md` §2 — `FLD-002`, `NUM-001`, `DATE-001`,
//     and `DATE-002`;
//   * `contracts/editor-interactions.md` §3–§5 — the explicit user actions that
//     this pure model supports;
//   * constitution Principles V, VI, and VIII — platform-independent,
//     immutable, deterministic, and content never echoed in errors or
//     `toString`.
//
// T019 owns only this module and its tests. `FieldType`, `ConfirmedField`,
// `FieldValue`, `FieldValidation`, `WarningCode`, and `IncompatibleValue` are
// T017/T018 types and are imported unchanged; this module does not redeclare or
// reshape them. The T017/T020 aggregate flag is reconciled with §3.5 in the
// document and revision snapshot (an incompatible value is flagged by the
// incompatible-content warning *or* a blocking field error).
//
// ## Persisted error vs. persisted warning
//
// `data-model.md` §3.5 distinguishes two kinds of flagged incompatible content:
//
//   * text → number/date content that does not parse is "marked `error`",
//     keeps its content, and `number/date → text` "clears" that error. The
//     blocking catalog code (`NUM-001`, `DATE-001`, or `DATE-002`) is therefore
//     persisted in `ConfirmedField.validation` as a `FieldValidation.error`,
//     alongside the preserved `IncompatibleValue`.
//   * checkbox, signature, and unconfirmed line-break joins are "flagged" and
//     stay pending until the user resolves them. They persist the
//     `incompatible_content` warning (`FLD-002`), because the user has to make
//     an explicit choice before export.
//
// The T017 `Document` and T020 `RevisionContent` accept an `IncompatibleValue`
// when the field is flagged by either the `incompatible_content` warning or a
// blocking error; an unflagged `IncompatibleValue` and a warning without
// preserved content remain rejected. [ReclassificationResult.errorCode] mirrors
// the persisted error code for callers that render the type-specific message.
// In both cases the content stays in the model and
// [ReclassificationResult.blocksExport] is true (FR-038).
//
// Every validation replacement also carries the previous state's opaque
// same-schema JSON extensions onto the new state: `data-model.md` §6 permits
// dropping unknown fields only on migration, not on an ordinary edit. Field,
// value, and validation extensions therefore survive a reclassification and
// its persistence round-trip.
//
// ## Rule matrix
//
// | From | To | Outcome |
// | --- | --- | --- |
// | any | same | no-op; the field and value are returned unchanged |
// | text | multiline | text preserved |
// | multiline | text | line breaks joined with spaces after explicit confirmation; without it the original is preserved as incompatible |
// | text/multiline | number | German or canonical number parsed; failure preserved with `NUM-001` |
// | text/multiline | date | German or ISO date parsed; failure preserved with `DATE-001`/`DATE-002` |
// | number/date | text/multiline | display text preserved (`rawGerman`/canonical); validation cleared |
// | number | date | projection parsed; failure preserved with `DATE-001`/`DATE-002` |
// | date | number | projection parsed; failure preserved with `NUM-001` |
// | text/multiline/number/date | checkbox | non-empty content preserved as incompatible; an unchecked checkbox is proposed; export blocked until resolved |
// | text/multiline/number/date | signature | non-empty content preserved as incompatible; export blocked until resolved |
// | checkbox | signature | checkbox state cleared |
// | checkbox | text/multiline | `Ja`/`Nein` display projection preserved as incompatible with a proposed text value |
// | checkbox | number/date | `Ja`/`Nein` projection preserved as incompatible; no numeric inference is invented |
// | signature | non-signature | signature reference cleared and surfaced for asset cleanup; no text is invented |
//
// Empty text is no content: moving an empty text value to number, date,
// checkbox, or signature removes the value instead of inventing a parse error
// or a checkbox state. An empty value is still preserved when the target is
// text or multiline.
//
// ## Parsing
//
// The number grammar is owned by `lib/src/validation/number.dart` and exposed
// as [parseGermanNumber]; this module delegates to it instead of keeping a
// second copy. The date parser remains here because it also distinguishes
// `DATE-001` from `DATE-002`:
//
//   * number: the T019 German and canonical forms parsed by
//     [parseGermanNumber]. A valid German grouping is preferred over a
//     canonical dot decimal, so the German display `1.234` becomes `1234`
//     rather than `1.234`.
//   * date: `d.m.yyyy` with one or two digits for day/month and four for the
//     year, or the canonical `yyyy-mm-dd` emitted by date → text. A
//     structurally valid date that is not a real calendar date is
//     `DATE-002`; anything else is `DATE-001`.
//
// The display projections are trimmed for parsing only; `rawGerman` and
// preserved content keep the exact entered text.

library;

import '../validation/number.dart';
import 'field.dart';

/// Why a reclassification preserved content as
/// [IncompatibleValue.reasonCode].
///
/// The wire names are stable lowercase machine tokens. They never contain user
/// content (FR-038) and are safe for logs and diagnostics.
enum ReclassificationReason {
  /// Text did not parse as a number under the target type (`NUM-001`).
  numberParseFailed('number_parse_failed'),

  /// Text did not parse as a real date under the target type (`DATE-001` or
  /// `DATE-002`).
  dateParseFailed('date_parse_failed'),

  /// Multiline line breaks would be joined with spaces and need explicit
  /// user confirmation first.
  lineBreakJoinConfirmation('line_break_join_confirmation'),

  /// Existing content must be resolved before it can become a checkbox.
  checkboxRequiresResolution('checkbox_requires_resolution'),

  /// Existing text must be resolved before it can become a signature field.
  signatureRequiresResolution('signature_requires_resolution'),

  /// A checkbox state was projected to `Ja`/`Nein` for a text-like target.
  checkboxStateProjection('checkbox_state_projection'),

  /// Preserved content contains control characters that the target text value
  /// cannot store even after line-join.
  contentNotRepresentable('content_not_representable');

  const ReclassificationReason(this.wireName);

  /// Stable lowercase machine token.
  final String wireName;
}

/// The user-action state of a type change.
enum ReclassificationKind {
  /// The content was converted without losing information.
  compatible('compatible'),

  /// The content would change shape (line breaks joined) and needs explicit
  /// user confirmation before the converted value may be stored.
  confirmationRequired('confirmation_required'),

  /// Existing content was preserved as incompatible and must be resolved
  /// before export.
  resolutionRequired('resolution_required'),

  /// A checkbox state was cleared because the target type cannot store it.
  checkboxCleared('checkbox_cleared'),

  /// A signature reference was cleared because the target type cannot store
  /// ink.
  signatureCleared('signature_cleared');

  const ReclassificationKind(this.wireName);

  /// Stable lowercase machine token.
  final String wireName;

  /// Whether the user has to act before the change is final.
  ///
  /// A cleared checkbox or signature state is already final: the target type
  /// cannot hold the old state, so only the confirmation and resolution
  /// outcomes have an open action.
  bool get requiresUserAction =>
      this == confirmationRequired || this == resolutionRequired;

  /// Whether export must wait for the user to resolve the change.
  ///
  /// Preserved incompatible content and an unconfirmed line-break join both
  /// block export (FR-029/FR-038). A cleared checkbox or signature state does
  /// not leave contradictory content behind and therefore does not block.
  bool get blocksExport =>
      this == confirmationRequired || this == resolutionRequired;
}

/// The outcome of reclassifying one confirmed field and its value.
///
/// The result is immutable and never stores or echoes a label or text in
/// `toString`. Callers persist [field] and, when non-null, [value] under
/// [ConfirmedField.id]; [proposedValue] is the value the user may accept by
/// calling [resolve]. See the library documentation for the persisted
/// warning/error reconciliation.
final class ReclassificationResult {
  const ReclassificationResult._({
    required this.field,
    required this.value,
    required this.proposedValue,
    required this.kind,
    required this.reason,
    required this.errorCode,
    required this.clearedSignatureAssetId,
  });

  /// The confirmed field with the target [FieldType], the reclassification
  /// validation state, and the caller-supplied `updatedAt`.
  ///
  /// A same-type call returns the input field unchanged.
  final ConfirmedField field;

  /// The value to store for [field], or null when the field has no value.
  ///
  /// Incompatible content is an [IncompatibleValue] flagged by either a
  /// [WarningCode.incompatibleContent] warning (pending explicit user
  /// resolution) or a blocking [FieldValidation.error] (a failed type parse),
  /// which keeps the T017/T020 aggregate valid.
  final FieldValue? value;

  /// The value the user may accept by calling [resolve], or null.
  ///
  /// It is a joined [TextValue] for [ReclassificationKind.confirmationRequired]
  /// and an unchecked [CheckboxValue] or a projected [TextValue] for
  /// [ReclassificationKind.resolutionRequired]. It is null when resolution
  /// means leaving the field without a value (a signature field or an
  /// unparseable number/date).
  final FieldValue? proposedValue;

  /// What the user has to do, if anything.
  final ReclassificationKind kind;

  /// The reason content was preserved, or null for a lossless conversion.
  final ReclassificationReason? reason;

  /// The catalog code of a parse failure (`NUM-001`, `DATE-001`, `DATE-002`),
  /// or null.
  ///
  /// This is the "marked error" from `data-model.md` §3.5. It is persisted as
  /// the code of [field]'s blocking [FieldValidation.error] and repeated here
  /// for callers that render the type-specific message.
  final String? errorCode;

  /// The cleared signature asset id when a signature field became another
  /// type, or null.
  ///
  /// `data-model.md` §3.7 deletes the asset after the next verified commit;
  /// this module never deletes data itself.
  final String? clearedSignatureAssetId;

  /// The target type (the type of [field]).
  FieldType get type => field.type;

  /// Whether the conversion was lossless.
  bool get isCompatible => kind == ReclassificationKind.compatible;

  /// Whether the user has to act before the change is final.
  bool get requiresUserAction => kind.requiresUserAction;

  /// Whether export must wait for the user to resolve the change.
  bool get blocksExport => kind.blocksExport;

  /// The exact content preserved in [value], or null.
  ///
  /// The getter is document content and must not be logged.
  String? get preservedContent {
    final FieldValue? current = value;
    return current is IncompatibleValue ? current.preservedText : null;
  }

  /// The machine reason token stored with preserved content, or null.
  String? get incompatibleReasonCode {
    final FieldValue? current = value;
    return current is IncompatibleValue ? current.reasonCode : null;
  }

  /// Returns the state after the user explicitly resolves the open action.
  ///
  /// * A compatible or already-cleared result is returned unchanged.
  /// * A [ReclassificationKind.confirmationRequired] result stores
  ///   [proposedValue] (the space-joined text) and clears the flag.
  /// * A [ReclassificationKind.resolutionRequired] result replaces the
  ///   preserved content with [proposedValue], or with no value when
  ///   [proposedValue] is null. The caller may only invoke this after the user
  ///   has consciously resolved the flagged content; it is the explicit
  ///   discard/accept action, never automatic cleanup. A persisted parse error
  ///   is cleared in the same step (`data-model.md` §3.5: number/date → text
  ///   clears the error, and explicit resolution clears it for the same
  ///   reason).
  ///
  /// The field's `updatedAt` is not changed by this method.
  ReclassificationResult resolve() {
    if (!kind.requiresUserAction) {
      return this;
    }
    final ConfirmedField updated = field.copyWith(
      validation: _validationAfter(field, FieldValidation.ok, proposedValue),
    );
    return ReclassificationResult._(
      field: updated,
      value: proposedValue,
      proposedValue: null,
      kind: ReclassificationKind.compatible,
      reason: null,
      errorCode: null,
      clearedSignatureAssetId: null,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReclassificationResult &&
        other.field == field &&
        other.value == value &&
        other.proposedValue == proposedValue &&
        other.kind == kind &&
        other.reason == reason &&
        other.errorCode == errorCode &&
        other.clearedSignatureAssetId == clearedSignatureAssetId;
  }

  @override
  int get hashCode {
    return Object.hash(
      field,
      value,
      proposedValue,
      kind,
      reason,
      errorCode,
      clearedSignatureAssetId,
    );
  }

  @override
  String toString() {
    return 'ReclassificationResult(type: ${field.type.wireName}, '
        'kind: ${kind.wireName}, value: ${value?.kind ?? 'none'}, '
        'reason: ${reason?.wireName ?? 'none'}, '
        'errorCode: ${errorCode ?? 'none'})';
  }
}

/// Reclassifies [field] to [newType] and adapts [value].
///
/// [updatedAt] must be UTC and becomes both `field.updatedAt` and the
/// `lastEditedAt` of a converted or preserved value. [value] may be null when
/// the field has no entered value. A non-null value must either belong to
/// [field] (`value.type == field.type`) or be an [IncompatibleValue] from an
/// earlier reclassification.
///
/// [confirmLineBreakJoin] must be supplied only for a change to
/// [FieldType.text] after the user explicitly confirmed joining line breaks
/// with spaces (`data-model.md` §3.5). Without it, text containing a line break
/// is preserved and flagged as
/// [ReclassificationKind.confirmationRequired]. The flag is also accepted for
/// preserved content that contains a line break after an earlier failed
/// reclassification, so the user can still confirm the join explicitly.
///
/// The function is pure: it never mutates [field] or [value], never deletes
/// content without an explicit [ReclassificationResult.resolve], and never
/// echoes content in an error. Throws [ArgumentError] for an inconsistent
/// value/field pair, a non-UTC [updatedAt], a misplaced
/// [confirmLineBreakJoin] flag, or display content that exceeds the
/// 10,000-character limit of every target value variant. The last case can only
/// arise from a [NumberValue] whose unbounded `rawGerman` display text is
/// longer than 10,000 characters; truncating it would violate FR-038, so the
/// conversion fails loudly instead.
ReclassificationResult reclassifyField({
  required ConfirmedField field,
  required FieldValue? value,
  required FieldType newType,
  required DateTime updatedAt,
  bool confirmLineBreakJoin = false,
}) {
  if (!updatedAt.isUtc) {
    throw ArgumentError('updatedAt must be UTC');
  }
  if (value != null &&
      value is! IncompatibleValue &&
      value.type != field.type) {
    throw ArgumentError('value does not belong to the field type');
  }
  if (confirmLineBreakJoin && newType != FieldType.text) {
    throw ArgumentError('confirmLineBreakJoin only applies to a text target');
  }
  if (field.type == newType) {
    return ReclassificationResult._(
      field: field,
      value: value,
      proposedValue: null,
      kind: ReclassificationKind.compatible,
      reason: null,
      errorCode: null,
      clearedSignatureAssetId: null,
    );
  }
  return switch (newType) {
    FieldType.text => _toText(
      field: field,
      source: value,
      updatedAt: updatedAt,
      confirmLineBreakJoin: confirmLineBreakJoin,
    ),
    FieldType.multiline => _toMultiline(
      field: field,
      source: value,
      updatedAt: updatedAt,
    ),
    FieldType.number => _toNumber(
      field: field,
      source: value,
      updatedAt: updatedAt,
    ),
    FieldType.date => _toDate(
      field: field,
      source: value,
      updatedAt: updatedAt,
    ),
    FieldType.checkbox => _toCheckbox(
      field: field,
      source: value,
      updatedAt: updatedAt,
    ),
    FieldType.signature => _toSignature(
      field: field,
      source: value,
      updatedAt: updatedAt,
    ),
  };
}

ReclassificationResult _toText({
  required ConfirmedField field,
  required FieldValue? source,
  required DateTime updatedAt,
  required bool confirmLineBreakJoin,
}) {
  if (source is SignatureValue) {
    return _clearedSignature(
      field: field,
      target: FieldType.text,
      source: source,
      updatedAt: updatedAt,
    );
  }
  if (source is CheckboxValue) {
    final String projection = _checkboxProjection(source.checked);
    return _preserved(
      field: field,
      target: FieldType.text,
      source: source,
      preservedText: projection,
      reason: ReclassificationReason.checkboxStateProjection,
      kind: ReclassificationKind.resolutionRequired,
      proposedValue: _textValue(projection, source, updatedAt),
      updatedAt: updatedAt,
    );
  }
  final String? text = _displayText(source);
  if (text == null) {
    return _converted(
      field: field,
      target: FieldType.text,
      newValue: null,
      updatedAt: updatedAt,
    );
  }
  _checkValueTextLength(text);
  if (text.contains('\n')) {
    final String joined = _joinLines(text);
    if (!_containsUnsupportedControlCharacters(joined, allowNewline: false)) {
      if (confirmLineBreakJoin) {
        return _converted(
          field: field,
          target: FieldType.text,
          newValue: _textValue(joined, source, updatedAt),
          updatedAt: updatedAt,
        );
      }
      return _preserved(
        field: field,
        target: FieldType.text,
        source: source!,
        preservedText: text,
        reason: ReclassificationReason.lineBreakJoinConfirmation,
        kind: ReclassificationKind.confirmationRequired,
        proposedValue: _textValue(joined, source, updatedAt),
        updatedAt: updatedAt,
      );
    }
    return _notRepresentableText(
      field: field,
      target: FieldType.text,
      source: source!,
      preservedText: text,
      updatedAt: updatedAt,
    );
  }
  if (_containsUnsupportedControlCharacters(text, allowNewline: false)) {
    return _notRepresentableText(
      field: field,
      target: FieldType.text,
      source: source!,
      preservedText: text,
      updatedAt: updatedAt,
    );
  }
  return _converted(
    field: field,
    target: FieldType.text,
    newValue: _textValue(text, source, updatedAt),
    updatedAt: updatedAt,
  );
}

ReclassificationResult _toMultiline({
  required ConfirmedField field,
  required FieldValue? source,
  required DateTime updatedAt,
}) {
  if (source is SignatureValue) {
    return _clearedSignature(
      field: field,
      target: FieldType.multiline,
      source: source,
      updatedAt: updatedAt,
    );
  }
  if (source is CheckboxValue) {
    final String projection = _checkboxProjection(source.checked);
    return _preserved(
      field: field,
      target: FieldType.multiline,
      source: source,
      preservedText: projection,
      reason: ReclassificationReason.checkboxStateProjection,
      kind: ReclassificationKind.resolutionRequired,
      proposedValue: MultilineValue(
        text: projection,
        lastEditedAt: updatedAt,
        overflow: source.overflow,
        unknownFields: source.unknownFields,
      ),
      updatedAt: updatedAt,
    );
  }
  final String? text = _displayText(source);
  if (text == null) {
    return _converted(
      field: field,
      target: FieldType.multiline,
      newValue: null,
      updatedAt: updatedAt,
    );
  }
  _checkValueTextLength(text);
  if (_containsUnsupportedControlCharacters(text, allowNewline: true)) {
    return _notRepresentableText(
      field: field,
      target: FieldType.multiline,
      source: source!,
      preservedText: text,
      updatedAt: updatedAt,
    );
  }
  return _converted(
    field: field,
    target: FieldType.multiline,
    newValue: MultilineValue(
      text: text,
      lastEditedAt: updatedAt,
      overflow: source!.overflow,
      unknownFields: source.unknownFields,
    ),
    updatedAt: updatedAt,
  );
}

ReclassificationResult _toNumber({
  required ConfirmedField field,
  required FieldValue? source,
  required DateTime updatedAt,
}) {
  if (source is SignatureValue) {
    return _clearedSignature(
      field: field,
      target: FieldType.number,
      source: source,
      updatedAt: updatedAt,
    );
  }
  if (source is CheckboxValue) {
    final String projection = _checkboxProjection(source.checked);
    return _preserved(
      field: field,
      target: FieldType.number,
      source: source,
      preservedText: projection,
      reason: ReclassificationReason.checkboxStateProjection,
      kind: ReclassificationKind.resolutionRequired,
      updatedAt: updatedAt,
    );
  }
  final String? text = _displayText(source);
  if (text == null || text.isEmpty) {
    return _converted(
      field: field,
      target: FieldType.number,
      newValue: null,
      updatedAt: updatedAt,
    );
  }
  final String? canonical = parseGermanNumber(text);
  if (canonical != null) {
    return _converted(
      field: field,
      target: FieldType.number,
      newValue: NumberValue(
        canonical: canonical,
        rawGerman: text,
        lastEditedAt: updatedAt,
        overflow: source!.overflow,
        unknownFields: source.unknownFields,
      ),
      updatedAt: updatedAt,
    );
  }
  _checkValueTextLength(text);
  return _preserved(
    field: field,
    target: FieldType.number,
    source: source!,
    preservedText: text,
    reason: ReclassificationReason.numberParseFailed,
    kind: ReclassificationKind.resolutionRequired,
    errorCode: 'NUM-001',
    updatedAt: updatedAt,
  );
}

ReclassificationResult _toDate({
  required ConfirmedField field,
  required FieldValue? source,
  required DateTime updatedAt,
}) {
  if (source is SignatureValue) {
    return _clearedSignature(
      field: field,
      target: FieldType.date,
      source: source,
      updatedAt: updatedAt,
    );
  }
  if (source is CheckboxValue) {
    final String projection = _checkboxProjection(source.checked);
    return _preserved(
      field: field,
      target: FieldType.date,
      source: source,
      preservedText: projection,
      reason: ReclassificationReason.checkboxStateProjection,
      kind: ReclassificationKind.resolutionRequired,
      updatedAt: updatedAt,
    );
  }
  final String? text = _displayText(source);
  if (text == null || text.isEmpty) {
    return _converted(
      field: field,
      target: FieldType.date,
      newValue: null,
      updatedAt: updatedAt,
    );
  }
  final _ParsedDate parsed = _parseDate(text);
  final String? canonical = parsed.canonical;
  if (canonical != null) {
    return _converted(
      field: field,
      target: FieldType.date,
      newValue: DateValue(
        canonical: canonical,
        lastEditedAt: updatedAt,
        overflow: source!.overflow,
        unknownFields: source.unknownFields,
      ),
      updatedAt: updatedAt,
    );
  }
  _checkValueTextLength(text);
  return _preserved(
    field: field,
    target: FieldType.date,
    source: source!,
    preservedText: text,
    reason: ReclassificationReason.dateParseFailed,
    kind: ReclassificationKind.resolutionRequired,
    errorCode: parsed.errorCode,
    updatedAt: updatedAt,
  );
}

ReclassificationResult _toCheckbox({
  required ConfirmedField field,
  required FieldValue? source,
  required DateTime updatedAt,
}) {
  if (source is SignatureValue) {
    return _clearedSignature(
      field: field,
      target: FieldType.checkbox,
      source: source,
      updatedAt: updatedAt,
    );
  }
  final String? text = _displayText(source);
  if (text == null || text.isEmpty) {
    return _converted(
      field: field,
      target: FieldType.checkbox,
      newValue: null,
      updatedAt: updatedAt,
    );
  }
  _checkValueTextLength(text);
  return _preserved(
    field: field,
    target: FieldType.checkbox,
    source: source!,
    preservedText: text,
    reason: ReclassificationReason.checkboxRequiresResolution,
    kind: ReclassificationKind.resolutionRequired,
    proposedValue: CheckboxValue(
      checked: false,
      lastEditedAt: updatedAt,
      unknownFields: source.unknownFields,
    ),
    updatedAt: updatedAt,
  );
}

ReclassificationResult _toSignature({
  required ConfirmedField field,
  required FieldValue? source,
  required DateTime updatedAt,
}) {
  if (source is CheckboxValue) {
    return _clearedCheckbox(field: field, source: source, updatedAt: updatedAt);
  }
  if (source is SignatureValue) {
    // A signature value can only belong to a signature field, and a same-type
    // call returned before dispatch, so this branch is defensive.
    return _converted(
      field: field,
      target: FieldType.signature,
      newValue: source,
      updatedAt: updatedAt,
    );
  }
  final String? text = _displayText(source);
  if (text == null || text.isEmpty) {
    return _converted(
      field: field,
      target: FieldType.signature,
      newValue: null,
      updatedAt: updatedAt,
    );
  }
  _checkValueTextLength(text);
  return _preserved(
    field: field,
    target: FieldType.signature,
    source: source!,
    preservedText: text,
    reason: ReclassificationReason.signatureRequiresResolution,
    kind: ReclassificationKind.resolutionRequired,
    updatedAt: updatedAt,
  );
}

ReclassificationResult _converted({
  required ConfirmedField field,
  required FieldType target,
  required FieldValue? newValue,
  required DateTime updatedAt,
}) {
  final FieldValidation validation = _validationAfter(
    field,
    FieldValidation.ok,
    newValue,
  );
  return ReclassificationResult._(
    field: field.copyWith(
      type: target,
      validation: validation,
      updatedAt: updatedAt,
    ),
    value: newValue,
    proposedValue: null,
    kind: ReclassificationKind.compatible,
    reason: null,
    errorCode: null,
    clearedSignatureAssetId: null,
  );
}

ReclassificationResult _preserved({
  required ConfirmedField field,
  required FieldType target,
  required FieldValue source,
  required String preservedText,
  required ReclassificationReason reason,
  required ReclassificationKind kind,
  required DateTime updatedAt,
  FieldValue? proposedValue,
  String? errorCode,
}) {
  final IncompatibleValue preserved = IncompatibleValue(
    preservedText: preservedText,
    reasonCode: reason.wireName,
    lastEditedAt: updatedAt,
    overflow: source.overflow,
    unknownFields: source.unknownFields,
  );
  // data-model.md §3.5 distinguishes a parse failure (`error`) from other
  // incompatible content (`warning`). A parse failure persists its catalog code
  // as the blocking field error; checkbox, signature, and line-join cases
  // persist the incompatible-content warning that the user resolves.
  final FieldValidation validation = _carryValidationExtensions(
    errorCode == null
        ? FieldValidation.warning(WarningCode.incompatibleContent, 'FLD-002')
        : FieldValidation.error(errorCode),
    field.validation,
  );
  return ReclassificationResult._(
    field: field.copyWith(
      type: target,
      validation: validation,
      updatedAt: updatedAt,
    ),
    value: preserved,
    proposedValue: proposedValue,
    kind: kind,
    reason: reason,
    errorCode: errorCode,
    clearedSignatureAssetId: null,
  );
}

ReclassificationResult _clearedSignature({
  required ConfirmedField field,
  required FieldType target,
  required SignatureValue source,
  required DateTime updatedAt,
}) {
  return ReclassificationResult._(
    field: field.copyWith(
      type: target,
      validation: _validationAfter(field, FieldValidation.ok, null),
      updatedAt: updatedAt,
    ),
    value: null,
    proposedValue: null,
    kind: ReclassificationKind.signatureCleared,
    reason: null,
    errorCode: null,
    clearedSignatureAssetId: source.signatureAssetId,
  );
}

ReclassificationResult _clearedCheckbox({
  required ConfirmedField field,
  required CheckboxValue source,
  required DateTime updatedAt,
}) {
  return ReclassificationResult._(
    field: field.copyWith(
      type: FieldType.signature,
      validation: _validationAfter(field, FieldValidation.ok, null),
      updatedAt: updatedAt,
    ),
    value: null,
    proposedValue: null,
    kind: ReclassificationKind.checkboxCleared,
    reason: null,
    errorCode: null,
    clearedSignatureAssetId: null,
  );
}

ReclassificationResult _notRepresentableText({
  required ConfirmedField field,
  required FieldType target,
  required FieldValue source,
  required String preservedText,
  required DateTime updatedAt,
}) {
  return _preserved(
    field: field,
    target: target,
    source: source,
    preservedText: preservedText,
    reason: ReclassificationReason.contentNotRepresentable,
    kind: ReclassificationKind.resolutionRequired,
    updatedAt: updatedAt,
  );
}

/// Keeps a pre-existing overflow warning when the reclassified value still
/// carries it, and otherwise applies [newValidation].
///
/// Overflow is derived at layout time and is independent of the field type;
/// keeping the status avoids hiding a known overflow until the next layout.
/// Incompatible content takes precedence because it must block export. Every
/// replacement also carries the previous state's same-schema extensions.
FieldValidation _validationAfter(
  ConfirmedField field,
  FieldValidation newValidation,
  FieldValue? newValue,
) {
  if (newValidation.isOk &&
      newValue != null &&
      field.validation.isWarning &&
      field.validation.warningCode == WarningCode.overflow) {
    return field.validation;
  }
  return _carryValidationExtensions(newValidation, field.validation);
}

/// Carries opaque same-schema JSON extensions from [previous] onto
/// [replacement].
///
/// `data-model.md` §6 only permits dropping unknown JSON fields on migration.
/// A reclassification creates a new validation state, but the mapped state
/// still wins and the opaque extension entries are retained for a later write.
/// The warning/error factories expose their extension parameter; the valid
/// state is decoded with its modeled status because `data-model.md` §3.5 has no
/// separate constructor for an extended `ok`.
FieldValidation _carryValidationExtensions(
  FieldValidation replacement,
  FieldValidation previous,
) {
  final Map<String, Object?> extensions = previous.unknownFields;
  if (extensions.isEmpty) {
    return replacement;
  }
  if (replacement.isWarning) {
    return FieldValidation.warning(
      replacement.warningCode!,
      replacement.messageKey!,
      unknownFields: extensions,
    );
  }
  if (replacement.isError) {
    return FieldValidation.error(
      replacement.errorCode!,
      unknownFields: extensions,
    );
  }
  if (previous.isOk) {
    return previous;
  }
  return FieldValidation.fromJson(<String, Object?>{
    ...extensions,
    'status': 'ok',
  });
}

TextValue _textValue(String text, FieldValue? source, DateTime updatedAt) {
  return TextValue(
    text: text,
    lastEditedAt: updatedAt,
    overflow: source?.overflow ?? false,
    unknownFields: source?.unknownFields ?? const <String, Object?>{},
  );
}

/// The lossless display projection of a value, or null when the value has no
/// text representation (a signature).
String? _displayText(FieldValue? value) {
  return switch (value) {
    null => null,
    TextValue text => text.text,
    MultilineValue text => text.text,
    NumberValue number => number.rawGerman,
    DateValue date => date.canonical,
    CheckboxValue checkbox => _checkboxProjection(checkbox.checked),
    SignatureValue _ => null,
    IncompatibleValue preserved => preserved.preservedText,
  };
}

String _checkboxProjection(bool checked) => checked ? 'Ja' : 'Nein';

String _joinLines(String text) => text.replaceAll('\n', ' ');

/// The maximum text length of every persisted value variant
/// (`data-model.md` §3.6; T018).
///
/// `NumberValue.rawGerman` is display text and is not length-limited by T018,
/// so a valid number value can carry more than 10,000 characters. Converting
/// that display text to text, multiline, or preserved content cannot be
/// lossless within the model; the conversion fails loudly instead of truncating
/// (FR-038). The error never echoes the content.
const int _maxValueTextLength = 10000;

void _checkValueTextLength(String text) {
  if (text.runes.length > _maxValueTextLength) {
    throw ArgumentError(
      'content exceeds the 10,000-character value limit for the target type',
    );
  }
}

bool _containsUnsupportedControlCharacters(
  String text, {
  required bool allowNewline,
}) {
  for (final int rune in text.runes) {
    if (allowNewline && rune == 0x0A) {
      continue;
    }
    if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
      return true;
    }
  }
  return false;
}

final RegExp _germanDatePattern = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$');
final RegExp _canonicalDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Parses a German `d.m.yyyy` or canonical `yyyy-mm-dd` date.
///
/// Returns a canonical `yyyy-mm-dd`, `DATE-001` for a malformed input, or
/// `DATE-002` for a structurally valid but non-existent calendar date.
_ParsedDate _parseDate(String raw) {
  final String text = raw.trim();
  final RegExpMatch? german = _germanDatePattern.firstMatch(text);
  final RegExpMatch? canonical = _canonicalDatePattern.firstMatch(text);
  final int year;
  final int month;
  final int day;
  if (german != null) {
    day = int.parse(german.group(1)!);
    month = int.parse(german.group(2)!);
    year = int.parse(german.group(3)!);
  } else if (canonical != null) {
    year = int.parse(canonical.group(1)!);
    month = int.parse(canonical.group(2)!);
    day = int.parse(canonical.group(3)!);
  } else {
    return const _ParsedDate.failure('DATE-001');
  }
  final DateTime date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return const _ParsedDate.failure('DATE-002');
  }
  return _ParsedDate.success(
    '${_padDatePart(year, 4)}-${_padDatePart(month, 2)}-'
    '${_padDatePart(day, 2)}',
  );
}

String _padDatePart(int value, int width) {
  return value.toString().padLeft(width, '0');
}

final class _ParsedDate {
  const _ParsedDate.success(String this.canonical) : errorCode = null;

  const _ParsedDate.failure(String this.errorCode) : canonical = null;

  final String? canonical;
  final String? errorCode;
}
