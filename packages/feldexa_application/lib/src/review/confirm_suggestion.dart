// Feldexa suggestion-review lifecycle commands (T065).
//
// Owner: `packages/feldexa_application/lib/src/review/confirm_suggestion.dart`
// (T065, issue #65).
// Normative sources:
//   * `data-model.md` §3.4–§3.5 — the suggestion resolution state machine and
//     the confirmed-field shape;
//   * `contracts/recognition-output.md` §7 — confirmation creates machine
//     provenance, rejection is reversible, confirmed fields are preserved, and
//     duplicates are never auto-confirmed;
//   * `spec.md` FR-021, FR-022, FR-027, and FR-028.
//
// The commands are pure: they never read a clock, generate an id, touch I/O, or
// mutate an input. Every value they need is an explicit parameter, every result
// is a fresh, fully validated [RevisionContent], and every failure is a
// [SuggestionReviewException] with a stable, content-free code. No message
// echoes an id, label, or document content.
library;

import 'package:feldexa_core/feldexa_core.dart';

/// The suggestion-resolution transition performed by a review command.
enum SuggestionReviewChangeKind {
  /// `unresolved -> confirmed` plus one machine [ConfirmedField].
  confirmed('confirmed'),

  /// `unresolved -> rejected` without a field change.
  rejected('rejected'),

  /// `rejected -> unresolved` without a field change.
  rejectionUndone('rejectionUndone'),

  /// `confirmed -> unresolved` after removing the untouched machine field.
  confirmationUndone('confirmationUndone');

  const SuggestionReviewChangeKind(this.wireName);

  /// Stable diagnostic token; never document content.
  final String wireName;
}

/// Stable, content-free failure codes for the suggestion-review commands.
enum SuggestionReviewErrorCode {
  /// No suggestion with the requested id exists in the revision.
  suggestionNotFound,

  /// The suggestion is not in the state the command requires.
  wrongState,

  /// A `duplicateOfConfirmed` suggestion may never be confirmed.
  duplicateNotConfirmable,

  /// The confirmed field to undo does not exist in the revision.
  fieldNotFound,

  /// The generated field was modified or used and must not be removed.
  fieldTouched,

  /// A command argument violates its value contract.
  invalidInput,
}

/// A failed suggestion-review command.
///
/// The [code] is stable and content-free; [message] is a fixed sentence per
/// code. Neither the code, the message, nor [toString] echoes an id, label,
/// path, or any other document content.
final class SuggestionReviewException implements Exception {
  /// Creates a failure with a stable [code].
  const SuggestionReviewException(this.code);

  /// The stable failure code.
  final SuggestionReviewErrorCode code;

  /// A fixed, content-free explanation of [code].
  String get message {
    return switch (code) {
      SuggestionReviewErrorCode.suggestionNotFound =>
        'The suggestion is not present in the revision.',
      SuggestionReviewErrorCode.wrongState =>
        'The suggestion is not in the required resolution state.',
      SuggestionReviewErrorCode.duplicateNotConfirmable =>
        'A duplicate-of-confirmed suggestion must not be confirmed.',
      SuggestionReviewErrorCode.fieldNotFound =>
        'The generated field is not present in the revision.',
      SuggestionReviewErrorCode.fieldTouched =>
        'The generated field was modified or used and must not be removed.',
      SuggestionReviewErrorCode.invalidInput =>
        'A command argument violates its value contract.',
    };
  }

  @override
  String toString() {
    return 'SuggestionReviewException(${code.name}: $message)';
  }
}

/// An immutable receipt for one successful suggestion-review command.
///
/// [content] is the complete new revision snapshot; the input content is never
/// mutated. [confirmedField] is the exact field snapshot created by
/// [confirmSuggestion] and is the value a later [undoConfirmation] must pass as
/// `expectedField`. The other kinds leave it null because they create or
/// restore no confirmed field.
final class SuggestionReviewChange {
  /// Creates a change receipt.
  const SuggestionReviewChange({
    required this.content,
    required this.suggestionId,
    required this.kind,
    this.fieldId,
    this.confirmedField,
  });

  /// The new, fully validated revision snapshot.
  final RevisionContent content;

  /// The id of the suggestion the command acted on.
  final String suggestionId;

  /// The resolution transition that was performed.
  final SuggestionReviewChangeKind kind;

  /// The created field id for [SuggestionReviewChangeKind.confirmed], or the
  /// removed field id for [SuggestionReviewChangeKind.confirmationUndone].
  /// Null when the command does not change fields.
  final String? fieldId;

  /// The created machine field for [SuggestionReviewChangeKind.confirmed].
  ///
  /// This is the exact receipt snapshot needed to undo the confirmation.
  final ConfirmedField? confirmedField;

  @override
  bool operator ==(Object other) {
    return other is SuggestionReviewChange &&
        other.content == content &&
        other.suggestionId == suggestionId &&
        other.kind == kind &&
        other.fieldId == fieldId &&
        other.confirmedField == confirmedField;
  }

  @override
  int get hashCode {
    return Object.hash(content, suggestionId, kind, fieldId, confirmedField);
  }

  @override
  String toString() {
    return 'SuggestionReviewChange(kind: ${kind.wireName}, '
        'fields: ${content.fields.length})';
  }
}

/// Confirms [suggestionId] and creates one machine [ConfirmedField].
///
/// The suggestion must exist, be [SuggestionResolution.unresolved], not be
/// [FieldSuggestion.duplicateOfConfirmed], and have no machine field that
/// already references it. [fieldId] must be a lowercase UUIDv4 that no
/// confirmed field uses yet, [label] must contain 1–120 characters after
/// trimming, and [now] must be UTC.
///
/// The created field copies the suggestion's page, canonical rect, and proposed
/// type without rounding the confirmed geometry, carries
/// [Provenance.machine], [FieldSuggestion.id], [FieldSuggestion.confidence],
/// and `order = content.fields.length`, and uses [now] for both timestamps.
/// The suggestion becomes [SuggestionResolution.confirmed]; pages, values,
/// signatures, verification, the template origin, unrelated fields, and
/// unknown fields are preserved.
///
/// Throws [SuggestionReviewException] with [SuggestionReviewErrorCode.invalidInput]
/// for an invalid [fieldId], [label], [now], or a reused field id.
SuggestionReviewChange confirmSuggestion(
  RevisionContent content,
  String suggestionId,
  String fieldId,
  String label,
  DateTime now,
) {
  final FieldSuggestion? suggestion = _findSuggestion(content, suggestionId);
  if (suggestion == null) {
    throw const SuggestionReviewException(
      SuggestionReviewErrorCode.suggestionNotFound,
    );
  }
  if (suggestion.resolution != SuggestionResolution.unresolved) {
    throw const SuggestionReviewException(SuggestionReviewErrorCode.wrongState);
  }
  if (suggestion.duplicateOfConfirmed) {
    throw const SuggestionReviewException(
      SuggestionReviewErrorCode.duplicateNotConfirmable,
    );
  }
  // Defense in depth: a valid RevisionContent cannot carry a machine field for
  // an unresolved suggestion, so this guard is unreachable through the public
  // aggregate constructor. It still fails closed instead of adding a second
  // field for the same suggestion.
  if (content.fields.any(
    (ConfirmedField field) => field.sourceSuggestionId == suggestionId,
  )) {
    throw const SuggestionReviewException(SuggestionReviewErrorCode.wrongState);
  }
  _requireUuidV4(fieldId);
  if (content.fields.any((ConfirmedField field) => field.id == fieldId)) {
    throw const SuggestionReviewException(
      SuggestionReviewErrorCode.invalidInput,
    );
  }
  final String checkedLabel = _requireLabel(label);
  _requireUtc(now);

  final ConfirmedField confirmedField = ConfirmedField(
    id: fieldId,
    pageIndex: suggestion.pageIndex,
    // The suggestion rect is already canonical; the confirmed field stores it
    // verbatim (FR-024 forbids rounding confirmed geometry).
    rect: suggestion.rect,
    type: suggestion.proposedType,
    provenance: Provenance.machine,
    sourceSuggestionId: suggestion.id,
    suggestionConfidence: suggestion.confidence,
    label: checkedLabel,
    order: content.fields.length,
    createdAt: now,
    updatedAt: now,
  );

  final RevisionContent updated = RevisionContent(
    pages: content.pages,
    suggestions: <FieldSuggestion>[
      for (final FieldSuggestion current in content.suggestions)
        current.id == suggestionId
            ? current.copyWith(resolution: SuggestionResolution.confirmed)
            : current,
    ],
    fields: <ConfirmedField>[...content.fields, confirmedField],
    fieldOrder: <String>[...content.fieldOrder, confirmedField.id],
    values: content.values,
    signatures: content.signatures,
    verification: content.verification,
    templateOrigin: content.templateOrigin,
    unknownFields: content.unknownFields,
  );

  return SuggestionReviewChange(
    content: updated,
    suggestionId: suggestionId,
    kind: SuggestionReviewChangeKind.confirmed,
    fieldId: confirmedField.id,
    confirmedField: confirmedField,
  );
}

/// Rejects [suggestionId] without changing any confirmed field.
///
/// The suggestion must exist and be [SuggestionResolution.unresolved]. Rejecting
/// a `duplicateOfConfirmed` suggestion is allowed: the audit flag only forbids
/// confirmation. Pages, fields, order, values, signatures, verification, the
/// template origin, and unknown fields are preserved.
SuggestionReviewChange rejectSuggestion(
  RevisionContent content,
  String suggestionId,
) {
  final FieldSuggestion? suggestion = _findSuggestion(content, suggestionId);
  if (suggestion == null) {
    throw const SuggestionReviewException(
      SuggestionReviewErrorCode.suggestionNotFound,
    );
  }
  if (suggestion.resolution != SuggestionResolution.unresolved) {
    throw const SuggestionReviewException(SuggestionReviewErrorCode.wrongState);
  }

  final RevisionContent updated = RevisionContent(
    pages: content.pages,
    suggestions: <FieldSuggestion>[
      for (final FieldSuggestion current in content.suggestions)
        current.id == suggestionId
            ? current.copyWith(resolution: SuggestionResolution.rejected)
            : current,
    ],
    fields: content.fields,
    fieldOrder: content.fieldOrder,
    values: content.values,
    signatures: content.signatures,
    verification: content.verification,
    templateOrigin: content.templateOrigin,
    unknownFields: content.unknownFields,
  );

  return SuggestionReviewChange(
    content: updated,
    suggestionId: suggestionId,
    kind: SuggestionReviewChangeKind.rejected,
  );
}

/// Reverses a rejection: `rejected -> unresolved`.
///
/// No confirmed field, order, value, signature, verification, template origin,
/// or unknown field changes.
SuggestionReviewChange undoRejection(
  RevisionContent content,
  String suggestionId,
) {
  final FieldSuggestion? suggestion = _findSuggestion(content, suggestionId);
  if (suggestion == null) {
    throw const SuggestionReviewException(
      SuggestionReviewErrorCode.suggestionNotFound,
    );
  }
  if (suggestion.resolution != SuggestionResolution.rejected) {
    throw const SuggestionReviewException(SuggestionReviewErrorCode.wrongState);
  }

  final RevisionContent updated = RevisionContent(
    pages: content.pages,
    suggestions: <FieldSuggestion>[
      for (final FieldSuggestion current in content.suggestions)
        current.id == suggestionId
            ? current.copyWith(resolution: SuggestionResolution.unresolved)
            : current,
    ],
    fields: content.fields,
    fieldOrder: content.fieldOrder,
    values: content.values,
    signatures: content.signatures,
    verification: content.verification,
    templateOrigin: content.templateOrigin,
    unknownFields: content.unknownFields,
  );

  return SuggestionReviewChange(
    content: updated,
    suggestionId: suggestionId,
    kind: SuggestionReviewChangeKind.rejectionUndone,
  );
}

/// Undoes a confirmation: `confirmed -> unresolved`, removing the generated
/// field.
///
/// [expectedField] must be the exact [ConfirmedField] snapshot that
/// [confirmSuggestion] returned. The suggestion must be confirmed, the field
/// with [ConfirmedField.id] must still exist, and the current machine field
/// linked to the suggestion must equal [expectedField] as a deep canonical-JSON
/// snapshot: `canonicalJsonEncode(field.toJson())`. That comparison covers every
/// stored field plus `unknownFields` at the top level and nested inside unknown
/// map or list values, so an extension-only change is detected even though
/// [ConfirmedField.operator==] deliberately ignores unknown fields. No value,
/// signature mark, or verification entry may be keyed by that field id.
///
/// On success the field is removed, the remaining fields are renumbered
/// contiguously in their existing `fieldOrder` sequence, and the suggestion
/// becomes [SuggestionResolution.unresolved]. Pages, values, signatures,
/// verification, the template origin, unrelated fields, and unknown fields are
/// preserved. If removing the field leaves a `duplicateOfConfirmed` audit flag
/// without its supporting machine field, the derived flag is cleared so the
/// returned content remains valid; no duplicate is ever confirmed.
///
/// Throws [SuggestionReviewException] with [SuggestionReviewErrorCode.fieldNotFound]
/// when the field is absent and [SuggestionReviewErrorCode.fieldTouched] when
/// it was edited, moved, reordered, re-typed, retimed, or used.
SuggestionReviewChange undoConfirmation(
  RevisionContent content,
  String suggestionId,
  ConfirmedField expectedField,
) {
  final FieldSuggestion? suggestion = _findSuggestion(content, suggestionId);
  if (suggestion == null) {
    throw const SuggestionReviewException(
      SuggestionReviewErrorCode.suggestionNotFound,
    );
  }
  if (suggestion.resolution != SuggestionResolution.confirmed) {
    throw const SuggestionReviewException(SuggestionReviewErrorCode.wrongState);
  }

  final ConfirmedField? expected = _findField(content, expectedField.id);
  if (expected == null) {
    throw const SuggestionReviewException(
      SuggestionReviewErrorCode.fieldNotFound,
    );
  }
  final ConfirmedField? linked = _linkedMachineField(content, suggestionId);
  if (linked == null) {
    // Defense in depth: a confirmed suggestion in a valid RevisionContent
    // always has exactly one machine field.
    throw const SuggestionReviewException(
      SuggestionReviewErrorCode.fieldNotFound,
    );
  }
  final String linkedSnapshot = _fieldSnapshot(linked);
  if (_fieldSnapshot(expected) != linkedSnapshot ||
      _fieldSnapshot(expectedField) != linkedSnapshot) {
    throw const SuggestionReviewException(
      SuggestionReviewErrorCode.fieldTouched,
    );
  }
  if (content.values.containsKey(linked.id) ||
      content.signatures.containsKey(linked.id) ||
      content.verification.containsKey(linked.id)) {
    throw const SuggestionReviewException(
      SuggestionReviewErrorCode.fieldTouched,
    );
  }

  final List<String> remainingOrder = <String>[
    for (final String fieldId in content.fieldOrder)
      if (fieldId != linked.id) fieldId,
  ];
  final Map<String, ConfirmedField> fieldById = <String, ConfirmedField>{
    for (final ConfirmedField field in content.fields) field.id: field,
  };
  final List<ConfirmedField> remainingFields = <ConfirmedField>[
    for (int index = 0; index < remainingOrder.length; index++)
      fieldById[remainingOrder[index]]!.copyWith(order: index),
  ];

  final List<FieldSuggestion> updatedSuggestions = <FieldSuggestion>[
    for (final FieldSuggestion current in content.suggestions)
      current.id == suggestionId
          ? current.copyWith(resolution: SuggestionResolution.unresolved)
          : current,
  ];
  // `duplicateOfConfirmed` is a derived audit flag. Removing its supporting
  // machine field must clear the flag rather than leave invalid content; the
  // helper never confirms, rejects, or removes a suggestion.
  final List<FieldSuggestion> finalSuggestions =
      updatedSuggestions.any(
        (FieldSuggestion current) => current.duplicateOfConfirmed,
      )
      ? markDuplicatesOfConfirmed(
          suggestions: updatedSuggestions,
          confirmedFields: remainingFields,
        )
      : updatedSuggestions;

  final RevisionContent updated = RevisionContent(
    pages: content.pages,
    suggestions: finalSuggestions,
    fields: remainingFields,
    fieldOrder: remainingOrder,
    values: content.values,
    signatures: content.signatures,
    verification: content.verification,
    templateOrigin: content.templateOrigin,
    unknownFields: content.unknownFields,
  );

  return SuggestionReviewChange(
    content: updated,
    suggestionId: suggestionId,
    kind: SuggestionReviewChangeKind.confirmationUndone,
    fieldId: linked.id,
  );
}

FieldSuggestion? _findSuggestion(RevisionContent content, String suggestionId) {
  for (final FieldSuggestion suggestion in content.suggestions) {
    if (suggestion.id == suggestionId) {
      return suggestion;
    }
  }
  return null;
}

ConfirmedField? _findField(RevisionContent content, String fieldId) {
  for (final ConfirmedField field in content.fields) {
    if (field.id == fieldId) {
      return field;
    }
  }
  return null;
}

ConfirmedField? _linkedMachineField(
  RevisionContent content,
  String suggestionId,
) {
  for (final ConfirmedField field in content.fields) {
    if (field.provenance == Provenance.machine &&
        field.sourceSuggestionId == suggestionId) {
      return field;
    }
  }
  return null;
}

/// The exact persisted snapshot of [field], including unknown extensions.
///
/// [ConfirmedField.operator==] intentionally ignores `unknownFields`, so the
/// touched check cannot use it. Canonical JSON includes the modeled keys and
/// every retained unknown value, recursively.
String _fieldSnapshot(ConfirmedField field) {
  return canonicalJsonEncode(field.toJson());
}

void _requireUuidV4(String fieldId) {
  if (!_lowercaseUuidV4.hasMatch(fieldId)) {
    throw const SuggestionReviewException(
      SuggestionReviewErrorCode.invalidInput,
    );
  }
}

String _requireLabel(String label) {
  final String trimmed = label.trim();
  if (trimmed.isEmpty || trimmed.runes.length > _maxLabelLength) {
    throw const SuggestionReviewException(
      SuggestionReviewErrorCode.invalidInput,
    );
  }
  for (final int rune in trimmed.runes) {
    if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
      throw const SuggestionReviewException(
        SuggestionReviewErrorCode.invalidInput,
      );
    }
  }
  return trimmed;
}

void _requireUtc(DateTime now) {
  if (!now.isUtc) {
    throw const SuggestionReviewException(
      SuggestionReviewErrorCode.invalidInput,
    );
  }
}

const int _maxLabelLength = 120;

final RegExp _lowercaseUuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
