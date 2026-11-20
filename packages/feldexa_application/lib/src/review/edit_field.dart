// Feldexa confirmed-field edit commands (T066).
//
// Owner: `packages/feldexa_application/lib/src/review/edit_field.dart`
// (T066, issue #66).
// Normative sources:
//   * `spec.md` FR-023, FR-024, FR-029, and FR-038 — add, remove, move,
//     resize, and reclassify fields, preserve corrected geometry exactly, keep
//     compatible content on a type change, flag incompatible content, and never
//     delete entered information silently;
//   * `data-model.md` §3.4–§3.6 — suggestion resolution, the confirmed-field
//     shape and provenance rules, the reclassification matrix, and the
//     `FieldValue` variants;
//   * `data-model.md` §3.14 — the command receipt is the previous/new
//     sub-state a later T067 undo history restores;
//   * `contracts/recognition-output.md` §7 — the confirmed-suggestion ↔
//     machine-field invariants and the duplicate audit flag;
//   * `contracts/error-catalog.de.md` §6 — `NUM-001`, `DATE-001`, `DATE-002`,
//     and `FLD-002`.
//
// The commands are pure: they never read a clock, generate an id, touch I/O, or
// mutate an input. Every value they need is an explicit parameter, every result
// is a fresh, fully validated [RevisionContent], and every failure is an
// [EditFieldException] with a stable, content-free code. No message echoes an
// id, label, rectangle, or document content.
//
// ## Reclassification decisions (FR-029)
//
// The core `reclassifyField` function (T019) owns the data-model §3.5 matrix
// and is reused unchanged for the transitions it models. This command layer
// adds the revision-snapshot concerns: it removes a cleared signature mark,
// keeps the values map keyed to the field, and recomputes the derived duplicate
// audit flag when a geometry or type change invalidates it.
//
// Two command-level decisions are pinned here and covered by tests:
//
//   * a `number`/`date` field converted to `text` stores the value's canonical
//     textual form (`1234.56`, `2025-12-31`), not the German display spelling;
//   * the core `reclassifyField` conversion is the single source of truth for
//     checkbox/signature sources: checkbox content is preserved as the
//     `Ja`/`Nein` projection in an [IncompatibleValue] with the
//     `incompatible_content` warning, and a signature source is cleared exactly
//     as core `_clearedSignature` specifies (no invented text or numeric/date
//     value). This layer only removes the now-cleared signature mark/value and
//     keeps the values map consistent.
//
// A same-type reclassification has nothing to do, so it fails with
// [EditFieldErrorCode.noChange] and leaves the input unchanged.
library;

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_core/feldexa_core.dart' as core show reclassifyField;

/// The kind of a successful confirmed-field edit.
enum EditFieldChangeKind {
  /// A user field was appended.
  added('added'),

  /// A field and all content keyed by it were removed.
  removed('removed'),

  /// A field kept its size and changed its position.
  moved('moved'),

  /// A field kept its position and changed its size.
  resized('resized'),

  /// A field changed its type and its value was adapted or preserved.
  reclassified('reclassified');

  const EditFieldChangeKind(this.wireName);

  /// Stable diagnostic token; never document content.
  final String wireName;
}

/// Stable, content-free failure codes for the edit commands.
enum EditFieldErrorCode {
  /// No confirmed field with the requested id exists in the revision.
  fieldNotFound,

  /// The requested id already exists, or the field/value/suggestion linkage is
  /// not in a valid state.
  wrongState,

  /// A command argument violates its value contract.
  invalidInput,

  /// The page index is missing or the rectangle leaves the page display box.
  pageOutOfBounds,

  /// The command would leave the field unchanged (same-type reclassification).
  noChange,
}

/// A failed confirmed-field edit.
///
/// The [code] is stable and content-free; [message] is a fixed sentence per
/// code. Neither the code, the message, nor [toString] echoes an id, label,
/// rectangle, path, or any other document content.
final class EditFieldException implements Exception {
  /// Creates a failure with a stable [code].
  const EditFieldException(this.code);

  /// The stable failure code.
  final EditFieldErrorCode code;

  /// A fixed, content-free explanation of [code].
  String get message {
    return switch (code) {
      EditFieldErrorCode.fieldNotFound =>
        'The field is not present in the revision.',
      EditFieldErrorCode.wrongState =>
        'The field or its content is not in the required state.',
      EditFieldErrorCode.invalidInput =>
        'A command argument violates its value contract.',
      EditFieldErrorCode.pageOutOfBounds =>
        'The geometry lies outside the page display box.',
      EditFieldErrorCode.noChange => 'The command would not change the field.',
    };
  }

  @override
  String toString() {
    return 'EditFieldException(${code.name}: $message)';
  }
}

/// An immutable receipt for one successful confirmed-field edit.
///
/// [content] is the complete new revision snapshot; the input content is never
/// mutated. [fieldId] identifies the affected field. The `previous*` snapshots
/// are the exact pre-command state a later T067 undo restores; they are null
/// when the command did not change that part of the revision (for example, an
/// add has no previous field). [previousSuggestion] is the original suggestion
/// record when a machine field removal changed its resolution from `confirmed`
/// to `rejected`. [previousSuggestions] is the complete suggestion list before
/// a machine-field move, resize, reclassify, or remove that may have recomputed
/// derived duplicate flags; it is null when the command cannot change
/// suggestions.
final class EditFieldChange {
  /// Creates an edit receipt.
  const EditFieldChange({
    required this.content,
    required this.fieldId,
    required this.kind,
    this.previousField,
    this.previousValue,
    this.previousSignature,
    this.previousVerification,
    this.previousSuggestion,
    this.previousSuggestions,
  });

  /// The new, fully validated revision snapshot.
  final RevisionContent content;

  /// The id of the confirmed field the command acted on.
  final String fieldId;

  /// The edit that was performed.
  final EditFieldChangeKind kind;

  /// The field before the command, or null for [EditFieldChangeKind.added].
  final ConfirmedField? previousField;

  /// The value before the command, or null when the field had no value.
  final FieldValue? previousValue;

  /// The signature mark before the command, or null.
  final SignatureMark? previousSignature;

  /// The verification entry before the command, or null.
  final FieldVerification? previousVerification;

  /// The suggestion before a machine-field removal changed its resolution.
  final FieldSuggestion? previousSuggestion;

  /// The complete suggestion list before a machine-field command that may
  /// recompute derived duplicate flags; null when suggestions cannot change.
  final List<FieldSuggestion>? previousSuggestions;

  @override
  bool operator ==(Object other) {
    return other is EditFieldChange &&
        other.content == content &&
        other.fieldId == fieldId &&
        other.kind == kind &&
        other.previousField == previousField &&
        other.previousValue == previousValue &&
        other.previousSignature == previousSignature &&
        other.previousVerification == previousVerification &&
        other.previousSuggestion == previousSuggestion &&
        _suggestionListsEqual(other.previousSuggestions, previousSuggestions);
  }

  @override
  int get hashCode {
    return Object.hash(
      content,
      fieldId,
      kind,
      previousField,
      previousValue,
      previousSignature,
      previousVerification,
      previousSuggestion,
      previousSuggestions == null ? null : Object.hashAll(previousSuggestions!),
    );
  }

  @override
  String toString() {
    return 'EditFieldChange(kind: ${kind.wireName}, '
        'fields: ${content.fields.length})';
  }
}

/// Appends one user-created [ConfirmedField] to [content].
///
/// [fieldId] must be a lowercase UUIDv4 that no confirmed field uses yet,
/// [pageIndex] must name an existing page, [rect] must be finite, positive, and
/// strictly inside that page's display box, [label] must contain 1–120
/// characters after trimming, and [now] must be UTC. The rectangle is stored
/// verbatim with no rounding (FR-024).
///
/// The field carries [Provenance.user] with no suggestion linkage,
/// `order = content.fields.length`, `createdAt = updatedAt = now`, and an `ok`
/// validation state. Its id is appended to `fieldOrder`; every other page,
/// suggestion, field, value, signature, verification entry, template origin,
/// and unknown extension is preserved.
///
/// Throws [EditFieldException] with [EditFieldErrorCode.invalidInput] for an
/// invalid id, label, or timestamp, [EditFieldErrorCode.wrongState] when the
/// revision already contains [fieldId], and
/// [EditFieldErrorCode.pageOutOfBounds] for a missing page or a rectangle
/// outside it.
EditFieldChange addField(
  RevisionContent content,
  String fieldId,
  int pageIndex,
  Rect rect,
  FieldType type,
  String label,
  DateTime now,
) {
  _requireUuidV4(fieldId);
  if (content.fields.any((ConfirmedField field) => field.id == fieldId)) {
    throw const EditFieldException(EditFieldErrorCode.wrongState);
  }
  final Rect pageBox = _requirePageBox(content, pageIndex);
  _requireRectInside(rect, pageBox);
  final String checkedLabel = _requireLabel(label);
  _requireUtc(now);

  final ConfirmedField field;
  try {
    field = ConfirmedField(
      id: fieldId,
      pageIndex: pageIndex,
      rect: rect,
      type: type,
      provenance: Provenance.user,
      label: checkedLabel,
      order: content.fields.length,
      createdAt: now,
      updatedAt: now,
    );
  } on ArgumentError {
    throw const EditFieldException(EditFieldErrorCode.invalidInput);
  }

  final RevisionContent updated = _buildContent(
    pages: content.pages,
    suggestions: content.suggestions,
    fields: <ConfirmedField>[...content.fields, field],
    fieldOrder: <String>[...content.fieldOrder, field.id],
    values: content.values,
    signatures: content.signatures,
    verification: content.verification,
    templateOrigin: content.templateOrigin,
    unknownFields: content.unknownFields,
  );

  return EditFieldChange(
    content: updated,
    fieldId: field.id,
    kind: EditFieldChangeKind.added,
  );
}

/// Removes [fieldId] and every value, signature mark, and verification entry
/// keyed by it.
///
/// The remaining fields are renumbered contiguously in their existing
/// `fieldOrder` sequence. Removing a machine field does not leave a confirmed
/// suggestion without its field: the source suggestion becomes
/// [SuggestionResolution.rejected], the documented audit decision for a user
/// who discarded the confirmed field. If that removal invalidates a derived
/// [FieldSuggestion.duplicateOfConfirmed] flag, the core
/// [markDuplicatesOfConfirmed] helper recomputes the flags so the returned
/// content satisfies the aggregate invariants. No other field, value,
/// signature, verification entry, suggestion, page, template origin, or
/// unknown extension is changed.
///
/// Throws [EditFieldException] with [EditFieldErrorCode.fieldNotFound] when the
/// field is absent and [EditFieldErrorCode.wrongState] when a machine field's
/// suggestion linkage is inconsistent.
EditFieldChange removeField(RevisionContent content, String fieldId) {
  final int index = _requireFieldIndex(content, fieldId);
  final ConfirmedField removedField = content.fields[index];
  final FieldValue? previousValue = content.values[fieldId];
  final SignatureMark? previousSignature = content.signatures[fieldId];
  final FieldVerification? previousVerification = content.verification[fieldId];

  final Map<String, ConfirmedField> fieldById = <String, ConfirmedField>{
    for (final ConfirmedField field in content.fields) field.id: field,
  };
  fieldById.remove(fieldId);
  final List<String> remainingOrder = <String>[
    for (final String id in content.fieldOrder)
      if (id != fieldId) id,
  ];
  final List<ConfirmedField> remainingFields = <ConfirmedField>[
    for (int position = 0; position < remainingOrder.length; position++)
      fieldById[remainingOrder[position]]!.copyWith(order: position),
  ];

  FieldSuggestion? previousSuggestion;
  List<FieldSuggestion> suggestions = content.suggestions;
  if (removedField.provenance == Provenance.machine) {
    final String? suggestionId = removedField.sourceSuggestionId;
    if (suggestionId == null) {
      throw const EditFieldException(EditFieldErrorCode.wrongState);
    }
    final int suggestionIndex = suggestions.indexWhere(
      (FieldSuggestion suggestion) => suggestion.id == suggestionId,
    );
    if (suggestionIndex < 0 ||
        suggestions[suggestionIndex].resolution !=
            SuggestionResolution.confirmed) {
      throw const EditFieldException(EditFieldErrorCode.wrongState);
    }
    previousSuggestion = suggestions[suggestionIndex];
    suggestions = <FieldSuggestion>[
      for (int position = 0; position < suggestions.length; position++)
        position == suggestionIndex
            ? suggestions[position].copyWith(
                resolution: SuggestionResolution.rejected,
              )
            : suggestions[position],
    ];
  }
  if (removedField.provenance == Provenance.machine) {
    suggestions = _refreshDuplicateFlags(suggestions, remainingFields);
  }

  final RevisionContent updated = _buildContent(
    pages: content.pages,
    suggestions: suggestions,
    fields: remainingFields,
    fieldOrder: remainingOrder,
    values: <String, FieldValue>{
      for (final MapEntry<String, FieldValue> entry in content.values.entries)
        if (entry.key != fieldId) entry.key: entry.value,
    },
    signatures: <String, SignatureMark>{
      for (final MapEntry<String, SignatureMark> entry
          in content.signatures.entries)
        if (entry.key != fieldId) entry.key: entry.value,
    },
    verification: <String, FieldVerification>{
      for (final MapEntry<String, FieldVerification> entry
          in content.verification.entries)
        if (entry.key != fieldId) entry.key: entry.value,
    },
    templateOrigin: content.templateOrigin,
    unknownFields: content.unknownFields,
  );

  return EditFieldChange(
    content: updated,
    fieldId: fieldId,
    kind: EditFieldChangeKind.removed,
    previousField: removedField,
    previousValue: previousValue,
    previousSignature: previousSignature,
    previousVerification: previousVerification,
    previousSuggestion: previousSuggestion,
    previousSuggestions: removedField.provenance == Provenance.machine
        ? content.suggestions
        : null,
  );
}

/// Moves [fieldId] to the exact [rect].
///
/// The rectangle must be finite, positive, and strictly inside the field's page
/// display box; it is stored verbatim with no rounding (FR-024). The field's
/// type, label, value, signature mark, verification entry, order, provenance,
/// suggestion linkage, `createdAt`, and unknown extensions are preserved;
/// `updatedAt` becomes [now].
///
/// Moving and resizing share the same geometry rules and differ only in the
/// receipt [EditFieldChangeKind].
///
/// Throws [EditFieldException] with [EditFieldErrorCode.fieldNotFound] when the
/// field is absent, [EditFieldErrorCode.invalidInput] for a non-UTC timestamp,
/// and [EditFieldErrorCode.pageOutOfBounds] for a rectangle outside the page.
EditFieldChange moveField(
  RevisionContent content,
  String fieldId,
  Rect rect,
  DateTime now,
) {
  return _translateField(
    content,
    fieldId,
    rect,
    now,
    EditFieldChangeKind.moved,
  );
}

/// Resizes [fieldId] to the exact [rect].
///
/// This has exactly the move rules; only the receipt kind differs.
EditFieldChange resizeField(
  RevisionContent content,
  String fieldId,
  Rect rect,
  DateTime now,
) {
  return _translateField(
    content,
    fieldId,
    rect,
    now,
    EditFieldChangeKind.resized,
  );
}

/// Reclassifies [fieldId] to [newType] and adapts or preserves its value.
///
/// The core data-model §3.5 rules apply. In particular:
///
///   * `text ⇄ multiline` preserves text; `multiline → text` joins line breaks
///     with spaces only when [joinMultilineToText] is true. Without that
///     explicit confirmation, text containing a line break stays in an
///     [IncompatibleValue] with the `line_break_join_confirmation` reason and
///     the `incompatible_content` warning.
///   * `text → number/date` parses German/canonical input. Success stores a
///     [NumberValue]/[DateValue]; failure preserves the exact text in an
///     [IncompatibleValue] with a stable reason and a blocking
///     [FieldValidation.error] (`NUM-001`, `DATE-001`, or `DATE-002`).
///   * `number/date → text` stores the canonical textual form and clears an
///     incompatibility error.
///   * `text/number/date/multiline → checkbox` preserves the prior textual
///     content in an [IncompatibleValue] with the `incompatible_content`
///     warning; it never invents a checkbox state.
///   * `text/number/date/multiline → signature` preserves prior content in an
///     [IncompatibleValue] with the warning and creates no signature mark.
///   * `checkbox → text/multiline/number/date` preserves the checked/unchecked
///     state as the core `Ja`/`Nein` textual projection in an
///     [IncompatibleValue] with the `incompatible_content` warning; no
///     numeric/date value is invented.
///   * `signature → text/number/date` follows the core `_clearedSignature`
///     result: the signature value is removed (no empty `TextValue` or
///     `IncompatibleValue` is invented), and its signature mark is cleaned up.
///
/// `createdAt`, `order`, label, provenance, suggestion linkage, and unknown
/// field extensions are preserved, while `updatedAt` becomes [now]. A removed
/// signature mark and its value are cleaned up. If any derived duplicate flag
/// exists, the flags are recomputed against the new field shape so the returned
/// content remains valid.
///
/// A same-type reclassification fails with [EditFieldErrorCode.noChange] and
/// leaves [content] unchanged. A missing field is
/// [EditFieldErrorCode.fieldNotFound], a non-UTC [now] or a misplaced
/// [joinMultilineToText] flag is [EditFieldErrorCode.invalidInput], and an
/// inconsistent field/value pair is [EditFieldErrorCode.wrongState].
EditFieldChange reclassifyField(
  RevisionContent content,
  String fieldId,
  FieldType newType,
  DateTime now, {
  bool joinMultilineToText = false,
}) {
  final int index = _requireFieldIndex(content, fieldId);
  final ConfirmedField field = content.fields[index];
  _requireUtc(now);
  if (field.type == newType) {
    throw const EditFieldException(EditFieldErrorCode.noChange);
  }
  if (joinMultilineToText && newType != FieldType.text) {
    throw const EditFieldException(EditFieldErrorCode.invalidInput);
  }

  final FieldValue? previousValue = content.values[fieldId];
  if (previousValue != null &&
      previousValue is! IncompatibleValue &&
      previousValue.type != field.type) {
    throw const EditFieldException(EditFieldErrorCode.wrongState);
  }

  final ConfirmedField updatedField;
  final FieldValue? updatedValue;
  final ReclassificationResult result;
  try {
    result = core.reclassifyField(
      field: field,
      value: previousValue,
      newType: newType,
      updatedAt: now,
      confirmLineBreakJoin: joinMultilineToText,
    );
  } on ArgumentError {
    throw const EditFieldException(EditFieldErrorCode.invalidInput);
  }
  updatedField = result.field;
  updatedValue = _canonicalTextTarget(
    result: result,
    source: previousValue,
    newType: newType,
    now: now,
  );
  if (updatedField.type != newType) {
    // Defense in depth: the core conversion must produce the requested type.
    throw const EditFieldException(EditFieldErrorCode.wrongState);
  }

  final List<ConfirmedField> fields = <ConfirmedField>[...content.fields];
  fields[index] = updatedField;
  final Map<String, FieldValue> values = Map<String, FieldValue>.from(
    content.values,
  );
  if (updatedValue == null) {
    values.remove(fieldId);
  } else {
    values[fieldId] = updatedValue;
  }
  final Map<String, SignatureMark> signatures = Map<String, SignatureMark>.from(
    content.signatures,
  );
  if (field.type == FieldType.signature && newType != FieldType.signature) {
    signatures.remove(fieldId);
  }
  final List<FieldSuggestion> suggestions =
      field.provenance == Provenance.machine
      ? _refreshDuplicateFlags(content.suggestions, fields)
      : content.suggestions;

  final RevisionContent updated = _buildContent(
    pages: content.pages,
    suggestions: suggestions,
    fields: fields,
    fieldOrder: content.fieldOrder,
    values: values,
    signatures: signatures,
    verification: content.verification,
    templateOrigin: content.templateOrigin,
    unknownFields: content.unknownFields,
  );

  return EditFieldChange(
    content: updated,
    fieldId: fieldId,
    kind: EditFieldChangeKind.reclassified,
    previousField: field,
    previousValue: previousValue,
    previousSignature: content.signatures[fieldId],
    previousVerification: content.verification[fieldId],
    previousSuggestions: field.provenance == Provenance.machine
        ? content.suggestions
        : null,
  );
}

EditFieldChange _translateField(
  RevisionContent content,
  String fieldId,
  Rect rect,
  DateTime now,
  EditFieldChangeKind kind,
) {
  final int index = _requireFieldIndex(content, fieldId);
  final ConfirmedField field = content.fields[index];
  _requireUtc(now);
  final Rect pageBox = _requirePageBox(content, field.pageIndex);
  _requireRectInside(rect, pageBox);

  final ConfirmedField updatedField = field.copyWith(
    rect: rect,
    updatedAt: now,
  );
  final List<ConfirmedField> fields = <ConfirmedField>[...content.fields];
  fields[index] = updatedField;
  final List<FieldSuggestion> suggestions =
      field.provenance == Provenance.machine
      ? _refreshDuplicateFlags(content.suggestions, fields)
      : content.suggestions;

  final RevisionContent updated = _buildContent(
    pages: content.pages,
    suggestions: suggestions,
    fields: fields,
    fieldOrder: content.fieldOrder,
    values: content.values,
    signatures: content.signatures,
    verification: content.verification,
    templateOrigin: content.templateOrigin,
    unknownFields: content.unknownFields,
  );

  return EditFieldChange(
    content: updated,
    fieldId: fieldId,
    kind: kind,
    previousField: field,
    previousValue: content.values[fieldId],
    previousSignature: content.signatures[fieldId],
    previousVerification: content.verification[fieldId],
    previousSuggestions: field.provenance == Provenance.machine
        ? content.suggestions
        : null,
  );
}

/// Replaces the core text result with the canonical textual form for a number
/// or date source; every other core result is returned unchanged.
FieldValue? _canonicalTextTarget({
  required ReclassificationResult result,
  required FieldValue? source,
  required FieldType newType,
  required DateTime now,
}) {
  if (newType == FieldType.text && source is NumberValue) {
    return _canonicalText(source.canonical, source, now);
  }
  if (newType == FieldType.text && source is DateValue) {
    return _canonicalText(source.canonical, source, now);
  }
  return result.value;
}

TextValue _canonicalText(String text, FieldValue source, DateTime now) {
  if (text.runes.length > _maxValueTextLength) {
    throw const EditFieldException(EditFieldErrorCode.invalidInput);
  }
  return TextValue(
    text: text,
    lastEditedAt: now,
    overflow: source.overflow,
    unknownFields: source.unknownFields,
  );
}

/// Recomputes [FieldSuggestion.duplicateOfConfirmed] when at least one flag is
/// present, so a stale flag cannot make the returned content invalid. The
/// helper is the single derivation authority and never confirms a suggestion.
List<FieldSuggestion> _refreshDuplicateFlags(
  Iterable<FieldSuggestion> suggestions,
  Iterable<ConfirmedField> fields,
) {
  final List<FieldSuggestion> list = suggestions.toList(growable: false);
  if (!list.any(
    (FieldSuggestion suggestion) => suggestion.duplicateOfConfirmed,
  )) {
    return list;
  }
  try {
    return markDuplicatesOfConfirmed(
      suggestions: list,
      confirmedFields: fields,
    );
  } on ArgumentError {
    throw const EditFieldException(EditFieldErrorCode.wrongState);
  }
}

int _requireFieldIndex(RevisionContent content, String fieldId) {
  for (int index = 0; index < content.fields.length; index++) {
    if (content.fields[index].id == fieldId) {
      return index;
    }
  }
  throw const EditFieldException(EditFieldErrorCode.fieldNotFound);
}

Rect _requirePageBox(RevisionContent content, int pageIndex) {
  if (pageIndex < 0 || pageIndex >= content.pages.length) {
    throw const EditFieldException(EditFieldErrorCode.pageOutOfBounds);
  }
  return content.pages[pageIndex].geometry.displayBox;
}

/// Validates a proposed confirmed-field rectangle at the command boundary.
///
/// This is the geometry rule shared by [addField], [moveField], and
/// [resizeField], exposed so callers can preflight raw pointer-derived values
/// before constructing a [Rect]. Every component must be finite; [width] and
/// [height] must be strictly positive; the right and bottom edges must remain
/// finite; and the rectangle must lie strictly inside [pageBox]. No rounding is
/// performed (FR-024).
///
/// Throws [EditFieldException] with [EditFieldErrorCode.invalidInput] for a
/// non-finite or non-positive component and [EditFieldErrorCode.pageOutOfBounds]
/// for a rectangle outside [pageBox]. Both messages are content-free.
void validateFieldRect({
  required double left,
  required double top,
  required double width,
  required double height,
  required Rect pageBox,
}) {
  if (!left.isFinite ||
      !top.isFinite ||
      !width.isFinite ||
      !height.isFinite ||
      width <= 0 ||
      height <= 0) {
    throw const EditFieldException(EditFieldErrorCode.invalidInput);
  }
  final double right = left + width;
  final double bottom = top + height;
  if (!right.isFinite || !bottom.isFinite) {
    throw const EditFieldException(EditFieldErrorCode.invalidInput);
  }
  if (left < pageBox.left ||
      top < pageBox.top ||
      right > pageBox.right ||
      bottom > pageBox.bottom) {
    throw const EditFieldException(EditFieldErrorCode.pageOutOfBounds);
  }
}

void _requireRectInside(Rect rect, Rect pageBox) {
  validateFieldRect(
    left: rect.left,
    top: rect.top,
    width: rect.width,
    height: rect.height,
    pageBox: pageBox,
  );
}

String _requireLabel(String label) {
  final String trimmed = label.trim();
  if (trimmed.isEmpty || trimmed.runes.length > _maxLabelLength) {
    throw const EditFieldException(EditFieldErrorCode.invalidInput);
  }
  for (final int rune in trimmed.runes) {
    if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
      throw const EditFieldException(EditFieldErrorCode.invalidInput);
    }
  }
  return trimmed;
}

void _requireUuidV4(String fieldId) {
  if (!_lowercaseUuidV4.hasMatch(fieldId)) {
    throw const EditFieldException(EditFieldErrorCode.invalidInput);
  }
}

void _requireUtc(DateTime now) {
  if (!now.isUtc) {
    throw const EditFieldException(EditFieldErrorCode.invalidInput);
  }
}

RevisionContent _buildContent({
  required List<Page> pages,
  required List<FieldSuggestion> suggestions,
  required List<ConfirmedField> fields,
  required List<String> fieldOrder,
  required Map<String, FieldValue> values,
  required Map<String, SignatureMark> signatures,
  required Map<String, FieldVerification> verification,
  required TemplateOrigin? templateOrigin,
  required Map<String, Object?> unknownFields,
}) {
  try {
    return RevisionContent(
      pages: pages,
      suggestions: suggestions,
      fields: fields,
      fieldOrder: fieldOrder,
      values: values,
      signatures: signatures,
      verification: verification,
      templateOrigin: templateOrigin,
      unknownFields: unknownFields,
    );
  } on ArgumentError {
    throw const EditFieldException(EditFieldErrorCode.wrongState);
  }
}

const int _maxLabelLength = 120;
const int _maxValueTextLength = 10000;

bool _suggestionListsEqual(
  List<FieldSuggestion>? first,
  List<FieldSuggestion>? second,
) {
  if (identical(first, second)) {
    return true;
  }
  if (first == null || second == null || first.length != second.length) {
    return false;
  }
  for (int index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

final RegExp _lowercaseUuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
