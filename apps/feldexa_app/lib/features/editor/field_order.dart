// T073 field-order review and reordering (FR-026).
//
// Owner: `apps/feldexa_app/lib/features/editor/field_order.dart` (T073,
// issue #73).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/spec.md` FR-026 (review fields in page
//     and document order and change that order) and US3 scenario 8;
//   * `specs/001-scanned-form-workflow/contracts/editor-interactions.md` §3
//     (the review list in document order shows page, index, label, type,
//     provenance, confidence, conflict, and completion; the user can move a
//     field up or down) and §5 (next/previous focus follows field order and
//     preserves values);
//   * `specs/001-scanned-form-workflow/data-model.md` §1 invariant 7, §3.12
//     (`fieldOrder` is the user-visible field order and `ConfirmedField.order`
//     equals its position), §5 (field order is a unique, contiguous
//     permutation), and §7 (stable sorts with explicit page/y/x/id
//     tie-breakers);
//   * `core.ReviewOrderMode.documentOrder` / `pageOrder`, the canonical
//     vocabulary for the two orderings;
//   * T085 `field_completion.dart` for the per-field completion state;
//   * T067 `CommandHistory` for the `reorder` undo step;
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// What this file owns
// -------------------
// 1. The deterministic default order. `compareFieldsInDocumentOrder` is the
//    canonical page → y → x → id rule from `data-model.md` §7, and
//    `defaultDocumentFieldOrder` derives the id list from it. This is the
//    `ReviewOrderMode.pageOrder` projection; it is also the defensive fallback
//    when a snapshot's stored order is not a usable permutation.
// 2. The current user-visible order. `orderedFields` returns the confirmed
//    fields in `RevisionContent.fieldOrder`, which `data-model.md` defines as
//    the user-visible field order (`ReviewOrderMode.documentOrder`) and which
//    the editor therefore shows and traverses. Confirmed fields are appended
//    in analysis order, so a freshly reviewed document already starts in page
//    and reading order without a silent rewrite of the stored order.
// 3. The review-list read model `FieldOrderEntry` with exactly the metadata
//    the contract requires: page, position (index), label, type, provenance,
//    confidence, conflict, and completion.
// 4. Reordering. `moveFieldToIndex`, `moveFieldUp`, and `moveFieldDown` return
//    a complete, revalidated `RevisionContent` whose `fieldOrder` and each
//    field's `order` agree. `moveFieldsToPageOrder` applies the whole
//    deterministic page/reading order as one reorder so FR-026's page order is
//    reachable from the review surface. Every other part of the snapshot —
//    pages, suggestions, values, signatures, verification, template origin,
//    and unknown extensions — is preserved, so a reorder can never lose a
//    value or geometry. The operation is clock-free and changes no timestamp,
//    so undo restores the exact previous snapshot.
// 5. Navigation. `nextFieldId` and `previousFieldId` walk the current order and
//    return null at the respective boundary; they never wrap, so a control can
//    reflect the boundary honestly. The value sheet turns that into focus
//    movement: a navigation action commits the draft, then hands the direction
//    to the editor, which swaps the field inside the same open sheet and lets
//    the new control request focus.
// 6. The conflict-open rule for confirmed fields. `hasOpenSuggestionConflict`
//    backs the review row's `conflicting` flag, which becomes false once the
//    opposing candidate is resolved. The T068 panel keeps its documented badge
//    entry point for resolved candidates; the field-order row reflects whether
//    a decision is still open.
//
// What this file does not own
// ---------------------------
// No store, port, runtime, or second source of truth. It performs no I/O, no
// clock read, no id generation, and no logging. The persisting commit and its
// `EditCommandKind.reorder` history entry stay in `EditorScreen`; the German
// wording stays in the ARB.
//
// Evidence
// --------
// Covered by host-VM unit and widget tests only
// (`test/field_order_test.dart` and `test/field_order_widget_test.dart`) and
// the host-VM editor composition test. It makes no Android, device, browser,
// screen-reader, or visual claim and produces no evidence above class NONE.

library;

import 'package:feldexa_app/features/editor/field_completion.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';

/// Stable key for the whole field-order review list.
const String fieldOrderListKey = 'field-order-list';

/// Stable key for the empty state.
const String fieldOrderEmptyKey = 'field-order-empty';

/// Stable key prefix for one review row.
const String fieldOrderRowKeyPrefix = 'field-order-row-';

/// Stable key prefix for one row's select action.
const String fieldOrderSelectKeyPrefix = 'field-order-select-';

/// Stable key prefix for one row's move-up action.
const String fieldOrderMoveUpKeyPrefix = 'field-order-up-';

/// Stable key prefix for one row's move-down action.
const String fieldOrderMoveDownKeyPrefix = 'field-order-down-';

/// Deterministic page → y → x → id order for confirmed fields.
///
/// This is the stable tie-breaker chain from `data-model.md` §7 and the
/// `core.ReviewOrderMode.pageOrder` projection. Both coordinates are compared
/// exactly as stored; a reorder never rounds, quantizes, or otherwise rewrites
/// field geometry. The field id is the final tie-breaker, so the order is total
/// and independent of the caller's list order.
int compareFieldsInDocumentOrder(core.ConfirmedField a, core.ConfirmedField b) {
  int result = a.pageIndex.compareTo(b.pageIndex);
  if (result != 0) {
    return result;
  }
  result = a.rect.top.compareTo(b.rect.top);
  if (result != 0) {
    return result;
  }
  result = a.rect.left.compareTo(b.rect.left);
  if (result != 0) {
    return result;
  }
  return a.id.compareTo(b.id);
}

/// The default deterministic document order for [content].
///
/// Returns every confirmed field id ordered by
/// [compareFieldsInDocumentOrder]. The list is a new unmodifiable list and has
/// no duplicates because confirmed field ids are unique in a validated
/// revision. It is empty for a document without confirmed fields.
List<String> defaultDocumentFieldOrder(core.RevisionContent content) {
  final List<core.ConfirmedField> sorted = content.fields.toList()
    ..sort(compareFieldsInDocumentOrder);
  return List<String>.unmodifiable(
    sorted.map((core.ConfirmedField field) => field.id),
  );
}

/// The confirmed fields in [fieldOrder] order with a deterministic completion.
///
/// `RevisionContent.fieldOrder` is authoritative (`data-model.md` §3.12), and a
/// validated revision always supplies a complete permutation. This resolver
/// still fails open instead of hiding fields: an id that is unknown or repeated
/// is skipped, and any field the id list does not mention is appended in
/// [compareFieldsInDocumentOrder] order. A degenerate id list therefore can
/// never drop a field from the review list. The result is unmodifiable and
/// empty for an empty input.
List<core.ConfirmedField> resolveFieldOrder({
  required Iterable<core.ConfirmedField> fields,
  required Iterable<String> fieldOrder,
}) {
  final Map<String, core.ConfirmedField> byId = <String, core.ConfirmedField>{
    for (final core.ConfirmedField field in fields) field.id: field,
  };
  final List<core.ConfirmedField> ordered = <core.ConfirmedField>[];
  final Set<String> placed = <String>{};
  for (final String id in fieldOrder) {
    final core.ConfirmedField? field = byId[id];
    if (field == null || !placed.add(id)) {
      continue;
    }
    ordered.add(field);
  }
  if (ordered.length != byId.length) {
    final List<core.ConfirmedField> complete = byId.values.toList()
      ..sort(compareFieldsInDocumentOrder);
    for (final core.ConfirmedField field in complete) {
      if (placed.add(field.id)) {
        ordered.add(field);
      }
    }
  }
  return List<core.ConfirmedField>.unmodifiable(ordered);
}

/// The confirmed fields in the current user-visible order.
///
/// Returns [resolveFieldOrder] for the snapshot's own fields and id list, so it
/// matches `content.fields` and each field's `order` for a validated revision
/// and stays complete for a degenerate one.
List<core.ConfirmedField> orderedFields(core.RevisionContent content) {
  return resolveFieldOrder(
    fields: content.fields,
    fieldOrder: content.fieldOrder,
  );
}

/// The confirmed field ids in the current user-visible order.
List<String> fieldOrderIds(core.RevisionContent content) {
  return List<String>.unmodifiable(
    orderedFields(content).map((core.ConfirmedField field) => field.id),
  );
}

/// The zero-based position of [fieldId] in the current order, or -1.
int fieldOrderIndexOf(core.RevisionContent content, String fieldId) {
  return orderedFields(content)
      .indexWhere((core.ConfirmedField field) => field.id == fieldId);
}

/// One row of the field-order review list (`contracts/editor-interactions.md`
/// §3).
///
/// Every value is copied from the validated revision; the entry never mutates
/// the model and never invents a value. [position] is zero-based and [number]
/// is its one-based display form. [confidence] is non-null only for a machine
/// field, [conflicting] is true only while the source suggestion still carries
/// symmetric conflict references, and [completion] is the T085 state for the
/// field's validation and committed value.
final class FieldOrderEntry {
  /// Creates one immutable review row.
  const FieldOrderEntry({
    required this.fieldId,
    required this.position,
    required this.pageIndex,
    required this.label,
    required this.type,
    required this.provenance,
    required this.confidence,
    required this.conflicting,
    required this.completion,
  });

  /// The stable confirmed field id.
  final String fieldId;

  /// Zero-based position in the current field order.
  final int position;

  /// Zero-based page index of the field.
  final int pageIndex;

  /// The stored field label, verbatim.
  final String label;

  /// The stored field type.
  final core.FieldType type;

  /// How the field came into existence.
  final core.Provenance provenance;

  /// Machine suggestion confidence, or null for a non-machine field.
  final double? confidence;

  /// Whether the source suggestion is still in an open conflict.
  ///
  /// True exactly when [hasOpenSuggestionConflict] reports an open conflict for
  /// the field's source suggestion: a referenced candidate is still unresolved,
  /// or the reference is stale. It becomes false once every referenced
  /// candidate is resolved, so a decided conflict no longer shows a badge even
  /// though the T068 conflict sheet can still display the decided candidates.
  final bool conflicting;

  /// The T085 completion state for this field.
  final FieldCompletionState completion;

  /// The one-based position shown as the list index.
  int get number => position + 1;
}

/// Whether [suggestion] is still in an open conflict among [suggestions].
///
/// A conflict is open while at least one referenced candidate exists and is
/// unresolved. Once every referenced candidate is resolved (confirmed or
/// rejected), the conflict is decided and this returns false; that is what the
/// field-order row reports for a confirmed field's source suggestion. A stale
/// reference to a candidate that is not in the revision stays open: it still
/// needs an explicit decision and the T068 conflict sheet documents that case.
/// A suggestion without references is never conflicting.
///
/// The T068 review panel keeps its own per-row badge rule
/// (`conflictsWith.isNotEmpty`) because its rows are the unresolved queue and
/// the badge is the entry point that shows the resolved candidates' state; the
/// two surfaces therefore agree on the visible badge while a row is unresolved
/// and the field-order row clears it once the conflict is decided.
bool hasOpenSuggestionConflict(
  core.FieldSuggestion suggestion,
  Iterable<core.FieldSuggestion> suggestions,
) {
  if (suggestion.conflictsWith.isEmpty) {
    return false;
  }
  final Map<String, core.FieldSuggestion> byId = <String, core.FieldSuggestion>{
    for (final core.FieldSuggestion candidate in suggestions)
      candidate.id: candidate,
  };
  bool sawPresentCandidate = false;
  for (final String conflictId in suggestion.conflictsWith) {
    final core.FieldSuggestion? candidate = byId[conflictId];
    if (candidate == null) {
      continue;
    }
    sawPresentCandidate = true;
    if (candidate.resolution == core.SuggestionResolution.unresolved) {
      return true;
    }
  }
  // A stale reference (no referenced candidate in the revision) remains a
  // visible conflict rather than disappearing without a decision.
  return !sawPresentCandidate;
}

/// Builds the field-order review rows for [content] in the current order.
///
/// The returned list is unmodifiable and complete: no confirmed field is
/// dropped, so the review list can never silently hide a field. A document
/// without confirmed fields yields an empty list.
List<FieldOrderEntry> fieldOrderEntries(core.RevisionContent content) {
  final List<core.ConfirmedField> ordered = orderedFields(content);
  final Map<String, core.FieldSuggestion> suggestions =
      <String, core.FieldSuggestion>{
        for (final core.FieldSuggestion suggestion in content.suggestions)
          suggestion.id: suggestion,
      };
  return List<FieldOrderEntry>.unmodifiable(<FieldOrderEntry>[
    for (int position = 0; position < ordered.length; position++)
      _entryFor(content, ordered[position], position, suggestions),
  ]);
}

FieldOrderEntry _entryFor(
  core.RevisionContent content,
  core.ConfirmedField field,
  int position,
  Map<String, core.FieldSuggestion> suggestions,
) {
  final String? sourceSuggestionId = field.sourceSuggestionId;
  final core.FieldSuggestion? suggestion = sourceSuggestionId == null
      ? null
      : suggestions[sourceSuggestionId];
  return FieldOrderEntry(
    fieldId: field.id,
    position: position,
    pageIndex: field.pageIndex,
    label: field.label,
    type: field.type,
    provenance: field.provenance,
    confidence: field.suggestionConfidence,
    conflicting:
        suggestion != null &&
        hasOpenSuggestionConflict(suggestion, suggestions.values),
    completion: fieldCompletionState(
      validation: field.validation,
      value: content.values[field.id],
    ),
  );
}

/// Stable, content-free failure codes for a reorder operation.
enum FieldOrderErrorCode {
  /// The requested field id is not a confirmed field of this revision.
  fieldNotFound,

  /// The target index is outside `0 … fieldCount - 1`.
  indexOutOfBounds,
}

/// A failed reorder operation.
///
/// The [code] is stable and content-free; [message] is a fixed sentence per
/// code. Neither the code, the message, nor [toString] echoes an id, label,
/// rectangle, value, or any other document content.
final class FieldOrderException implements Exception {
  /// Creates a failure with a stable [code].
  const FieldOrderException(this.code);

  /// The stable failure code.
  final FieldOrderErrorCode code;

  /// A fixed, content-free explanation of [code].
  String get message {
    return switch (code) {
      FieldOrderErrorCode.fieldNotFound =>
        'The field is not part of this revision.',
      FieldOrderErrorCode.indexOutOfBounds =>
        'The target position is outside the field order.',
    };
  }

  @override
  String toString() {
    return 'FieldOrderException(${code.name}: $message)';
  }
}

/// One successful reorder: the new snapshot and the moved field's positions.
///
/// [content] is a complete, revalidated `RevisionContent`; the input snapshot
/// is never mutated. [previousIndex] and [newIndex] are zero-based positions in
/// the respective order, and [changed] is false for a no-op request (the same
/// snapshot is returned, so no revision is written).
final class FieldOrderChange {
  /// Creates one reorder receipt.
  const FieldOrderChange({
    required this.content,
    required this.fieldId,
    required this.previousIndex,
    required this.newIndex,
  });

  /// The complete new revision snapshot.
  final core.RevisionContent content;

  /// The reordered confirmed field id.
  final String fieldId;

  /// The zero-based position before the reorder.
  final int previousIndex;

  /// The zero-based position after the reorder.
  final int newIndex;

  /// Whether the position actually changed.
  bool get changed => previousIndex != newIndex;
}

/// Moves [fieldId] to [newIndex] in the user-visible order.
///
/// The new position is interpreted in the resulting order, so moving a field
/// down by one is `newIndex = previousIndex + 1`. The returned snapshot keeps
/// every page, suggestion, value, signature, verification entry, template
/// origin, and unknown extension; only `fieldOrder` and the affected fields'
/// `order` values change. It is therefore impossible for a reorder to lose a
/// value or geometry. No timestamp is read or written.
///
/// A request that does not change the position returns the input [content]
/// unchanged with `changed == false`; callers must not persist that no-op.
///
/// Throws [FieldOrderException] with
/// [FieldOrderErrorCode.fieldNotFound] when [fieldId] is not a confirmed field
/// and [FieldOrderErrorCode.indexOutOfBounds] when [newIndex] is outside
/// `0 … fieldCount - 1`.
FieldOrderChange moveFieldToIndex(
  core.RevisionContent content,
  String fieldId,
  int newIndex,
) {
  final List<core.ConfirmedField> ordered = orderedFields(content);
  final Map<String, core.ConfirmedField> byId = <String, core.ConfirmedField>{
    for (final core.ConfirmedField field in ordered) field.id: field,
  };
  final int previousIndex = ordered.indexWhere(
    (core.ConfirmedField field) => field.id == fieldId,
  );
  if (previousIndex < 0 || !byId.containsKey(fieldId)) {
    throw const FieldOrderException(FieldOrderErrorCode.fieldNotFound);
  }
  if (newIndex < 0 || newIndex >= ordered.length) {
    throw const FieldOrderException(FieldOrderErrorCode.indexOutOfBounds);
  }
  if (newIndex == previousIndex) {
    return FieldOrderChange(
      content: content,
      fieldId: fieldId,
      previousIndex: previousIndex,
      newIndex: newIndex,
    );
  }
  final List<String> ids = <String>[
    for (final core.ConfirmedField field in ordered) field.id,
  ];
  ids.removeAt(previousIndex);
  ids.insert(newIndex, fieldId);
  return FieldOrderChange(
    content: _contentWithFieldOrder(content, byId: byId, fieldOrder: ids),
    fieldId: fieldId,
    previousIndex: previousIndex,
    newIndex: newIndex,
  );
}

/// Returns [content] with [fieldOrder] and each field's `order` rewritten.
///
/// Every other part of the snapshot is passed through, including template
/// origin and unknown extensions, and the `RevisionContent` constructor
/// revalidates the result (unique ids, contiguous `order`, per-field page
/// bounds, provenance, values, and signatures). No timestamp is read or
/// written. [fieldOrder] must be a permutation of the supplied field ids; the
/// callers in this file always build one from [orderedFields].
core.RevisionContent _contentWithFieldOrder(
  core.RevisionContent content, {
  required Map<String, core.ConfirmedField> byId,
  required List<String> fieldOrder,
}) {
  final List<core.ConfirmedField> reordered = <core.ConfirmedField>[
    for (int position = 0; position < fieldOrder.length; position++)
      byId[fieldOrder[position]]!.copyWith(order: position),
  ];
  return core.RevisionContent(
    pages: content.pages,
    suggestions: content.suggestions,
    fields: reordered,
    fieldOrder: fieldOrder,
    values: content.values,
    signatures: content.signatures,
    verification: content.verification,
    templateOrigin: content.templateOrigin,
    unknownFields: content.unknownFields,
  );
}

/// Moves [fieldId] one position towards the start of the order.
///
/// Returns null when the field is already first or is not part of the
/// revision, so a boundary control can stay disabled without an exception.
FieldOrderChange? moveFieldUp(core.RevisionContent content, String fieldId) {
  final int index = fieldOrderIndexOf(content, fieldId);
  if (index <= 0) {
    return null;
  }
  return moveFieldToIndex(content, fieldId, index - 1);
}

/// Moves [fieldId] one position towards the end of the order.
///
/// Returns null when the field is already last or is not part of the revision,
/// so a boundary control can stay disabled without an exception.
FieldOrderChange? moveFieldDown(core.RevisionContent content, String fieldId) {
  final int index = fieldOrderIndexOf(content, fieldId);
  final int count = content.fields.length;
  if (index < 0 || index >= count - 1) {
    return null;
  }
  return moveFieldToIndex(content, fieldId, index + 1);
}

/// Whether [content] already holds the deterministic page/reading order.
///
/// This is the `ReviewOrderMode.pageOrder` projection of
/// [defaultDocumentFieldOrder]. An empty document is trivially in page order.
bool isInPageOrder(core.RevisionContent content) {
  final List<core.ConfirmedField> ordered = orderedFields(content);
  if (ordered.isEmpty) {
    return true;
  }
  final List<String> currentIds = <String>[
    for (final core.ConfirmedField field in ordered) field.id,
  ];
  final List<String> pageIds = defaultDocumentFieldOrder(content);
  for (int index = 0; index < currentIds.length; index++) {
    if (currentIds[index] != pageIds[index]) {
      return false;
    }
  }
  return true;
}

/// Rewrites the whole order to the deterministic page/reading order.
///
/// FR-026 names both page and document order. The current user-visible order is
/// the document order; this operation applies the `pageOrder` projection as one
/// complete reorder, so the page order is reachable from the review surface
/// without an explicit stored preference (`DocumentPreferences` is not part of
/// `RevisionContent`). Every other snapshot part — values, geometry,
/// signatures, verification, template origin, and unknown extensions — is
/// preserved and revalidated.
///
/// Returns null when the document has no confirmed fields or already holds the
/// page order, so the caller never persists a no-op. Otherwise `fieldId` is the
/// first field whose absolute position changed, and `previousIndex`/`newIndex`
/// describe that field.
FieldOrderChange? moveFieldsToPageOrder(core.RevisionContent content) {
  final List<core.ConfirmedField> ordered = orderedFields(content);
  if (ordered.isEmpty) {
    return null;
  }
  final List<String> currentIds = <String>[
    for (final core.ConfirmedField field in ordered) field.id,
  ];
  final List<String> pageIds = defaultDocumentFieldOrder(content);
  int firstDifference = 0;
  while (firstDifference < currentIds.length &&
      currentIds[firstDifference] == pageIds[firstDifference]) {
    firstDifference++;
  }
  if (firstDifference >= currentIds.length) {
    return null;
  }
  final String movedId = currentIds[firstDifference];
  final Map<String, core.ConfirmedField> byId = <String, core.ConfirmedField>{
    for (final core.ConfirmedField field in ordered) field.id: field,
  };
  return FieldOrderChange(
    content: _contentWithFieldOrder(content, byId: byId, fieldOrder: pageIds),
    fieldId: movedId,
    previousIndex: firstDifference,
    newIndex: pageIds.indexOf(movedId),
  );
}

/// The id of the field after [currentFieldId] in the current order.
///
/// A null or unknown [currentFieldId] starts at the first field, which is the
/// documented review entry point. Returns null at the end of the order and for
/// a document without confirmed fields; the walk never wraps.
String? nextFieldId(core.RevisionContent content, String? currentFieldId) {
  final List<String> ids = fieldOrderIds(content);
  if (ids.isEmpty) {
    return null;
  }
  if (currentFieldId == null) {
    return ids.first;
  }
  final int index = ids.indexOf(currentFieldId);
  if (index < 0) {
    return ids.first;
  }
  return index + 1 < ids.length ? ids[index + 1] : null;
}

/// The id of the field before [currentFieldId] in the current order.
///
/// A null or unknown [currentFieldId] starts at the last field. Returns null at
/// the start of the order and for a document without confirmed fields; the walk
/// never wraps.
String? previousFieldId(core.RevisionContent content, String? currentFieldId) {
  final List<String> ids = fieldOrderIds(content);
  if (ids.isEmpty) {
    return null;
  }
  if (currentFieldId == null) {
    return ids.last;
  }
  final int index = ids.indexOf(currentFieldId);
  if (index < 0) {
    return ids.last;
  }
  return index > 0 ? ids[index - 1] : null;
}

/// The FR-026 review list in the current field order.
///
/// Every row shows the position, label, type, page, provenance, confidence
/// (machine fields only), conflict state, and T085 completion state, and offers
/// „Nach oben“/„Nach unten“ move actions (FR-026). A tap on a row selects that
/// field through [onSelect]. All German text comes from the ARB; this widget
/// holds no German literal.
///
/// [busy] disables every action while a reorder save is in flight, so two
/// overlapping commits cannot race. Boundary actions are disabled rather than
/// hidden, so the order and its ends stay visible.
class FieldOrderReviewList extends StatelessWidget {
  /// Creates the review list.
  const FieldOrderReviewList({
    required this.content,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onSelect,
    this.busy = false,
    super.key,
  });

  /// The current validated revision snapshot.
  final core.RevisionContent content;

  /// Moves one field one position towards the start.
  final ValueChanged<String> onMoveUp;

  /// Moves one field one position towards the end.
  final ValueChanged<String> onMoveDown;

  /// Selects one field without changing the order.
  final ValueChanged<String> onSelect;

  /// Disables every action while a save is in flight.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<FieldOrderEntry> entries = fieldOrderEntries(content);
    if (entries.isEmpty) {
      return Padding(
        key: const ValueKey<String>(fieldOrderEmptyKey),
        padding: const EdgeInsets.all(16),
        child: Text(l10n.fieldOrderEmpty),
      );
    }
    return SingleChildScrollView(
      key: const ValueKey<String>(fieldOrderListKey),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final FieldOrderEntry entry in entries)
            FieldOrderRow(
              entry: entry,
              count: entries.length,
              busy: busy,
              onMoveUp: onMoveUp,
              onMoveDown: onMoveDown,
              onSelect: onSelect,
            ),
        ],
      ),
    );
  }
}

/// The committed German label for one field type.
///
/// This is the single type-label mapping used by the field-order review and the
/// T086D document overview; it authors no new string.
String fieldTypeLabel(AppLocalizations l10n, core.FieldType type) {
  return switch (type) {
    core.FieldType.text => l10n.suggestionTypeText,
    core.FieldType.number => l10n.suggestionTypeNumber,
    core.FieldType.date => l10n.suggestionTypeDate,
    core.FieldType.checkbox => l10n.suggestionTypeCheckbox,
    core.FieldType.multiline => l10n.suggestionTypeMultiline,
    core.FieldType.signature => l10n.suggestionTypeSignature,
  };
}

/// One row of the [FieldOrderReviewList].
class FieldOrderRow extends StatelessWidget {
  /// Creates one review row.
  const FieldOrderRow({
    required this.entry,
    required this.count,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onSelect,
    this.busy = false,
    super.key,
  });

  /// The row's read model.
  final FieldOrderEntry entry;

  /// The number of rows in the list.
  final int count;

  /// Moves this field one position towards the start.
  final ValueChanged<String> onMoveUp;

  /// Moves this field one position towards the end.
  final ValueChanged<String> onMoveDown;

  /// Selects this field.
  final ValueChanged<String> onSelect;

  /// Disables every action while a save is in flight.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final bool canMoveUp = !busy && entry.position > 0;
    final bool canMoveDown = !busy && entry.position < count - 1;
    return Container(
      key: ValueKey<String>('$fieldOrderRowKeyPrefix${entry.fieldId}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: InkWell(
              key: ValueKey<String>(
                '$fieldOrderSelectKeyPrefix${entry.fieldId}',
              ),
              onTap: busy ? null : () => onSelect(entry.fieldId),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(entry.label, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        _MetaText(l10n.fieldOrderPosition(entry.number, count)),
                        _MetaText(l10n.suggestionPage(entry.pageIndex + 1)),
                        _MetaText(_typeLabel(l10n, entry.type)),
                        _MetaText(_provenanceLabel(l10n, entry.provenance)),
                        if (entry.confidence != null)
                          _MetaText(
                            l10n.suggestionConfidence(
                              (entry.confidence! * 100).clamp(0, 100).round(),
                            ),
                          ),
                        if (entry.conflicting)
                          _MetaText(l10n.suggestionConflict),
                        _MetaText(_completionLabel(l10n, entry.completion)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            key: ValueKey<String>('$fieldOrderMoveUpKeyPrefix${entry.fieldId}'),
            tooltip: l10n.fieldOrderMoveUp,
            onPressed: canMoveUp ? () => onMoveUp(entry.fieldId) : null,
            icon: const Icon(Icons.keyboard_arrow_up),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
          IconButton(
            key: ValueKey<String>(
              '$fieldOrderMoveDownKeyPrefix${entry.fieldId}',
            ),
            tooltip: l10n.fieldOrderMoveDown,
            onPressed: canMoveDown ? () => onMoveDown(entry.fieldId) : null,
            icon: const Icon(Icons.keyboard_arrow_down),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        ],
      ),
    );
  }

  static String _typeLabel(AppLocalizations l10n, core.FieldType type) {
    return fieldTypeLabel(l10n, type);
  }

  static String _provenanceLabel(
    AppLocalizations l10n,
    core.Provenance provenance,
  ) {
    return switch (provenance) {
      core.Provenance.machine => l10n.a11yFieldStatusConfirmed,
      core.Provenance.user => l10n.a11yFieldStatusSelfCreated,
      core.Provenance.template => l10n.templateLabel,
    };
  }

  static String _completionLabel(
    AppLocalizations l10n,
    FieldCompletionState state,
  ) {
    return switch (state) {
      FieldCompletionState.complete => l10n.fieldCompletionComplete,
      FieldCompletionState.optionalEmpty => l10n.fieldCompletionOptionalEmpty,
      FieldCompletionState.blockingError => l10n.fieldCompletionBlockingError,
      FieldCompletionState.warning => l10n.fieldCompletionWarning,
      FieldCompletionState.incompatible => l10n.fieldCompletionIncompatible,
    };
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.bodySmall);
  }
}
