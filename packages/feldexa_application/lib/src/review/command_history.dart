// Feldexa bounded undo/redo command history (T067).
//
// Owner: `packages/feldexa_application/lib/src/review/command_history.dart`
// (T067, issue #67).
// Normative sources:
//   * `data-model.md` §3.14 — `EditCommand` and `CommandHistory`: the command
//     metadata, the bounded 100-command undo/redo stacks, and the 500 ms
//     coalescing rule for drag/resize/typing;
//   * `spec.md` FR-027 — users can revise or restore previous corrections;
//   * `contracts/editor-interactions.md` §8 — global undo/redo actions and
//     command merging within 500 ms;
//   * T065 `confirm_suggestion.dart` and T066 `edit_field.dart`, whose receipts
//     already carry the exact before/after revision states.
//
// ## Snapshot representation (binding for T067)
//
// [HistoryEntry] stores the [EditCommand] metadata plus the complete, already
// validated [RevisionContent] **before** and **after** snapshots. §3.14
// describes the persisted/affected sub-state as canonical JSON; this transient,
// in-memory history instead holds whole validated revision snapshots so undo and
// redo are exact without duplicating every command's inverse logic from
// T065/T066. The stacks are bounded to 100 entries and the stored snapshots are
// never mutated: the caller applies `before` after [CommandHistory.undo] and
// `after` after [CommandHistory.redo].
//
// ## Field-scoped commands
//
// §3.14 makes `fieldId` required for field-scoped commands. The field-scoped
// kinds are add/remove/move/resize/reclassify/setValue/addSignature/
// removeSignature/reorder. The suggestion-resolution kinds
// (confirmSuggestion/rejectSuggestion) target a suggestion record rather than
// one existing field, so they must not carry a `fieldId`; the field they create
// or remove is part of the stored `before`/`after` snapshots. This layer does
// not re-validate the field-id syntax because template-derived field ids are
// valid confirmed-field ids but need not be UUIDv4.
//
// ## Scope
//
// The history is pure: no I/O, clock, id generation, persistence, UI, or
// platform code. Every value, including ids and timestamps, is an explicit
// parameter, and every failure is a [CommandHistoryException] with a stable,
// content-free code. Durable revision history and restore (the FR-027 storage
// concern) are out of scope; this is the bounded in-memory undo/redo stack only.
library;

import 'package:feldexa_core/feldexa_core.dart';

/// The kind of one reversible editing command (§3.14).
enum EditCommandKind {
  /// A confirmed field was appended.
  addField('addField'),

  /// A confirmed field and its keyed content were removed.
  removeField('removeField'),

  /// A field changed its position.
  move('move'),

  /// A field changed its size.
  resize('resize'),

  /// A field changed its type.
  reclassify('reclassify'),

  /// A field's value was typed or edited.
  setValue('setValue'),

  /// A suggestion was confirmed into a machine field.
  confirmSuggestion('confirmSuggestion'),

  /// A suggestion was rejected.
  rejectSuggestion('rejectSuggestion'),

  /// A field was reordered within the document.
  reorder('reorder'),

  /// A signature mark was added to a signature field.
  addSignature('addSignature'),

  /// A signature mark was removed from a signature field.
  removeSignature('removeSignature');

  const EditCommandKind(this.wireName);

  /// Stable diagnostic token; never document content.
  final String wireName;

  /// Whether this kind targets one confirmed field and therefore requires a
  /// `fieldId` (§3.14).
  bool get isFieldScoped => switch (this) {
    EditCommandKind.addField ||
    EditCommandKind.removeField ||
    EditCommandKind.move ||
    EditCommandKind.resize ||
    EditCommandKind.reclassify ||
    EditCommandKind.setValue ||
    EditCommandKind.addSignature ||
    EditCommandKind.removeSignature ||
    EditCommandKind.reorder => true,
    EditCommandKind.confirmSuggestion ||
    EditCommandKind.rejectSuggestion => false,
  };

  /// Whether consecutive commands of this kind may coalesce within the 500 ms
  /// window.
  ///
  /// Only drag (`move`), resize (`resize`), and typing (`setValue`) merge; every
  /// other kind remains one undo step per command.
  bool get coalesces => switch (this) {
    EditCommandKind.move ||
    EditCommandKind.resize ||
    EditCommandKind.setValue => true,
    _ => false,
  };
}

/// Stable, content-free failure codes for the command history.
enum CommandHistoryErrorCode {
  /// The command id is not a lowercase UUIDv4.
  invalidId,

  /// The command timestamp is not UTC.
  invalidTimestamp,

  /// A field-scoped kind was constructed without a `fieldId`.
  fieldIdRequired,

  /// A suggestion-resolution kind was constructed with a `fieldId`.
  fieldIdForbidden,

  /// A recorded command is older than the newest undo entry.
  nonMonotonicTimestamp,
}

/// A failed command-history operation.
///
/// The [code] is stable and content-free; [message] is a fixed sentence per
/// code. Neither the code, the message, nor [toString] echoes an id, field,
/// timestamp, snapshot, or any other document content.
final class CommandHistoryException implements Exception {
  /// Creates a failure with a stable [code].
  const CommandHistoryException(this.code);

  /// The stable failure code.
  final CommandHistoryErrorCode code;

  /// A fixed, content-free explanation of [code].
  String get message {
    return switch (code) {
      CommandHistoryErrorCode.invalidId =>
        'The command id is not a lowercase UUIDv4.',
      CommandHistoryErrorCode.invalidTimestamp =>
        'The command timestamp must be UTC.',
      CommandHistoryErrorCode.fieldIdRequired =>
        'The command kind requires a field id.',
      CommandHistoryErrorCode.fieldIdForbidden =>
        'The command kind must not carry a field id.',
      CommandHistoryErrorCode.nonMonotonicTimestamp =>
        'The command timestamp precedes the newest undo entry.',
    };
  }

  @override
  String toString() {
    return 'CommandHistoryException(${code.name}: $message)';
  }
}

/// The metadata of one reversible editing command (§3.14).
///
/// [id] must be a lowercase UUIDv4 and [at] must be UTC. [fieldId] is required
/// for [EditCommandKind.isFieldScoped] kinds and forbidden for
/// [EditCommandKind.confirmSuggestion] and [EditCommandKind.rejectSuggestion];
/// the id itself is not interpreted further. [merged] is false for a newly
/// recorded command and true only for an entry coalesced by
/// [CommandHistory.record].
final class EditCommand {
  /// Creates validated command metadata.
  ///
  /// Throws [CommandHistoryException] with a content-free code for an invalid
  /// [id], a non-UTC [at], a missing field-scoped `fieldId`, or a
  /// suggestion-resolution command carrying a `fieldId`.
  factory EditCommand({
    required String id,
    required EditCommandKind kind,
    String? fieldId,
    required DateTime at,
    bool merged = false,
  }) {
    _requireLowercaseUuidV4(id);
    if (!at.isUtc) {
      throw const CommandHistoryException(
        CommandHistoryErrorCode.invalidTimestamp,
      );
    }
    if (kind.isFieldScoped) {
      if (fieldId == null) {
        throw const CommandHistoryException(
          CommandHistoryErrorCode.fieldIdRequired,
        );
      }
    } else if (fieldId != null) {
      throw const CommandHistoryException(
        CommandHistoryErrorCode.fieldIdForbidden,
      );
    }
    return EditCommand._(
      id: id,
      kind: kind,
      fieldId: fieldId,
      at: at,
      merged: merged,
    );
  }

  const EditCommand._({
    required this.id,
    required this.kind,
    required this.fieldId,
    required this.at,
    required this.merged,
  });

  /// Lowercase UUIDv4 assigned by the caller.
  final String id;

  /// The reversible editing operation.
  final EditCommandKind kind;

  /// The confirmed field this command is scoped to, or null for the
  /// suggestion-resolution kinds.
  final String? fieldId;

  /// UTC time assigned by the caller's clock port.
  final DateTime at;

  /// True when this metadata represents a coalesced entry.
  final bool merged;

  @override
  bool operator ==(Object other) {
    return other is EditCommand &&
        other.id == id &&
        other.kind == kind &&
        other.fieldId == fieldId &&
        other.at == at &&
        other.merged == merged;
  }

  @override
  int get hashCode => Object.hash(id, kind, fieldId, at, merged);

  @override
  String toString() {
    return 'EditCommand(kind: ${kind.wireName}, merged: $merged)';
  }
}

/// One immutable undo/redo step: metadata plus the exact revision snapshots.
///
/// [before] and [after] are complete, already validated [RevisionContent]
/// instances produced by the T065/T066 commands (or by the caller's equivalent
/// mutation). The history never mutates them.
final class HistoryEntry {
  /// Creates one immutable history step.
  const HistoryEntry({
    required this.command,
    required this.before,
    required this.after,
  });

  /// The command metadata, including the coalesced [EditCommand.merged] flag.
  final EditCommand command;

  /// The exact revision state before the command; undo applies this snapshot.
  final RevisionContent before;

  /// The exact revision state after the command; redo applies this snapshot.
  final RevisionContent after;

  @override
  bool operator ==(Object other) {
    return other is HistoryEntry &&
        other.command == command &&
        other.before == before &&
        other.after == after;
  }

  @override
  int get hashCode => Object.hash(command, before, after);

  @override
  String toString() {
    return 'HistoryEntry(kind: ${command.kind.wireName}, '
        'merged: ${command.merged})';
  }
}

/// A bounded, in-memory undo/redo history for one open document (§3.14).
///
/// New commands are recorded with [record], which clears the redo stack and
/// trims the undo stack to the newest [maxEntries] entries. Move, resize, and
/// set-value commands of the same field coalesce into the newest undo entry
/// when their timestamps are at most [coalescingWindow] apart (inclusive):
/// merging keeps the original `before` snapshot, takes the newest `after`
/// snapshot, updates the entry timestamp, and sets [EditCommand.merged] so only
/// one undo step remains.
///
/// [undo] moves the newest undo entry to the redo stack and returns it; [redo]
/// moves the newest redo entry back and returns it. The caller applies
/// [HistoryEntry.before] or [HistoryEntry.after] respectively. The history
/// never mutates stored snapshots and performs no I/O, clock read, or id
/// generation.
final class CommandHistory {
  /// Creates an empty history.
  CommandHistory();

  /// The maximum number of entries in each stack (§3.14).
  static const int maxEntries = 100;

  /// The inclusive coalescing window for drag, resize, and typing commands.
  static const Duration coalescingWindow = Duration(milliseconds: 500);

  final List<HistoryEntry> _undoStack = <HistoryEntry>[];
  final List<HistoryEntry> _redoStack = <HistoryEntry>[];

  /// Whether [undo] can return an entry.
  bool get canUndo => _undoStack.isNotEmpty;

  /// Whether [redo] can return an entry.
  bool get canRedo => _redoStack.isNotEmpty;

  /// The number of undoable entries, in the range 0..[maxEntries].
  int get undoDepth => _undoStack.length;

  /// The number of redoable entries, in the range 0..[maxEntries].
  int get redoDepth => _redoStack.length;

  /// Records one command with its exact [before] and [after] snapshots.
  ///
  /// A new entry is always stored with [EditCommand.merged] false. The redo
  /// stack is cleared first, so recording after an undo discards the redo
  /// branch. If [command] is a coalescable kind and the newest undo entry has
  /// the same kind and `fieldId`, both timestamps are UTC, and
  /// `command.at - top.command.at` is between zero and [coalescingWindow]
  /// inclusive, the newest entry is replaced by one merged step: the original
  /// `before` snapshot, the incoming `after` snapshot, the incoming timestamp,
  /// the original command id, and `merged = true`. Otherwise a new entry is
  /// pushed and the undo stack is trimmed to the newest [maxEntries] entries.
  ///
  /// Throws [CommandHistoryException] with
  /// [CommandHistoryErrorCode.nonMonotonicTimestamp] when [command] is older
  /// than the newest undo entry; the history is unchanged in that case. The
  /// message is content-free. [EditCommand] construction has already validated
  /// the id, timestamp, and field-id rule.
  HistoryEntry record({
    required EditCommand command,
    required RevisionContent before,
    required RevisionContent after,
  }) {
    final HistoryEntry? top = _undoStack.isEmpty ? null : _undoStack.last;
    if (top != null && command.at.isBefore(top.command.at)) {
      throw const CommandHistoryException(
        CommandHistoryErrorCode.nonMonotonicTimestamp,
      );
    }
    _redoStack.clear();
    if (top != null && _coalescesWith(command, top.command)) {
      final HistoryEntry merged = HistoryEntry(
        command: _copyCommand(top.command, at: command.at, merged: true),
        before: top.before,
        after: after,
      );
      _undoStack[_undoStack.length - 1] = merged;
      return merged;
    }
    final HistoryEntry entry = HistoryEntry(
      command: _copyCommand(command, merged: false),
      before: before,
      after: after,
    );
    _undoStack.add(entry);
    _trim(_undoStack);
    return entry;
  }

  /// Moves the newest undo entry to the redo stack and returns it.
  ///
  /// Returns null when [canUndo] is false. The caller applies
  /// [HistoryEntry.before].
  HistoryEntry? undo() {
    if (_undoStack.isEmpty) {
      return null;
    }
    final HistoryEntry entry = _undoStack.removeLast();
    _redoStack.add(entry);
    _trim(_redoStack);
    return entry;
  }

  /// Moves the newest redo entry back to the undo stack and returns it.
  ///
  /// Returns null when [canRedo] is false. The caller applies
  /// [HistoryEntry.after].
  HistoryEntry? redo() {
    if (_redoStack.isEmpty) {
      return null;
    }
    final HistoryEntry entry = _redoStack.removeLast();
    _undoStack.add(entry);
    _trim(_undoStack);
    return entry;
  }

  bool _coalescesWith(EditCommand incoming, EditCommand previous) {
    if (!incoming.kind.coalesces) {
      return false;
    }
    if (incoming.kind != previous.kind ||
        incoming.fieldId != previous.fieldId) {
      return false;
    }
    if (!incoming.at.isUtc || !previous.at.isUtc) {
      return false;
    }
    final Duration elapsed = incoming.at.difference(previous.at);
    if (elapsed.isNegative) {
      return false;
    }
    return elapsed <= coalescingWindow;
  }

  EditCommand _copyCommand(
    EditCommand command, {
    DateTime? at,
    required bool merged,
  }) {
    return EditCommand(
      id: command.id,
      kind: command.kind,
      fieldId: command.fieldId,
      at: at ?? command.at,
      merged: merged,
    );
  }

  void _trim(List<HistoryEntry> stack) {
    final int overflow = stack.length - maxEntries;
    if (overflow > 0) {
      stack.removeRange(0, overflow);
    }
  }
}

void _requireLowercaseUuidV4(String id) {
  if (!_lowercaseUuidV4.hasMatch(id)) {
    throw const CommandHistoryException(CommandHistoryErrorCode.invalidId);
  }
}

final RegExp _lowercaseUuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
