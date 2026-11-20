// T067 bounded undo/redo command-history tests.
//
// These are host-VM tests (evidence class NONE). They pin the T067 deliverable
// in `packages/feldexa_application/lib/src/review/command_history.dart` against
// FR-027, `data-model.md` §3.14, and `contracts/editor-interactions.md` §8:
//   * `EditCommand` metadata is validated content-free (lowercase UUIDv4 id,
//     UTC timestamp, field-id rules) and exposes the stable §3.14 wire names;
//   * `CommandHistory` records exact before/after revision snapshots, undoes and
//     redoes in stack order, and clears redo on a new record;
//   * both stacks stay bounded at 100 entries and drop the oldest undo step;
//   * only move/resize/setValue of the same field coalesce, at most 500 ms
//     apart (inclusive), with one undo step and `merged = true`;
//   * inputs are never mutated, ordering is deterministic, and every failure
//     message is content-free.

import 'package:feldexa_application/src/review/command_history.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:flutter_test/flutter_test.dart';

const String _fieldId = '00000000-0000-4000-8000-000000000900';
const String _otherFieldId = '00000000-0000-4000-8000-000000000901';

String _uuid(int value) {
  return '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
}

/// A UTC instant [milliseconds] after 2026-11-20T12:00:00Z.
DateTime _at(int milliseconds) {
  return DateTime.utc(2026, 11, 20, 12, 0, 0, milliseconds);
}

RevisionContent _content(String label) {
  final DateTime at = DateTime.utc(2026, 11, 20, 12);
  final ConfirmedField field = ConfirmedField(
    id: _fieldId,
    pageIndex: 0,
    rect: Rect.fromLTWH(50, 60, 140, 20),
    type: FieldType.text,
    provenance: Provenance.user,
    label: label,
    order: 0,
    createdAt: at,
    updatedAt: at,
  );
  return RevisionContent(
    pages: <Page>[
      Page(
        index: 0,
        geometry: PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842)),
      ),
    ],
    fields: <ConfirmedField>[field],
    fieldOrder: const <String>[_fieldId],
  );
}

EditCommand _command({
  required int id,
  required EditCommandKind kind,
  required DateTime at,
  String? fieldId = _fieldId,
}) {
  return EditCommand(id: _uuid(id), kind: kind, fieldId: fieldId, at: at);
}

CommandHistoryException _captureException(void Function() action) {
  try {
    action();
  } on CommandHistoryException catch (exception) {
    return exception;
  }
  fail('expected a CommandHistoryException');
}

Matcher _failsWith(CommandHistoryErrorCode code) {
  return throwsA(
    isA<CommandHistoryException>().having(
      (CommandHistoryException exception) => exception.code,
      'code',
      code,
    ),
  );
}

void main() {
  group('EditCommandKind', () {
    test('exposes the exact §3.14 wire names in order', () {
      expect(
        <String>[
          for (final EditCommandKind kind in EditCommandKind.values)
            kind.wireName,
        ],
        <String>[
          'addField',
          'removeField',
          'move',
          'resize',
          'reclassify',
          'setValue',
          'confirmSuggestion',
          'rejectSuggestion',
          'reorder',
          'addSignature',
          'removeSignature',
        ],
      );
    });

    test('classifies field-scoped and coalescable kinds', () {
      const Set<EditCommandKind> fieldScoped = <EditCommandKind>{
        EditCommandKind.addField,
        EditCommandKind.removeField,
        EditCommandKind.move,
        EditCommandKind.resize,
        EditCommandKind.reclassify,
        EditCommandKind.setValue,
        EditCommandKind.addSignature,
        EditCommandKind.removeSignature,
        EditCommandKind.reorder,
      };
      const Set<EditCommandKind> coalescable = <EditCommandKind>{
        EditCommandKind.move,
        EditCommandKind.resize,
        EditCommandKind.setValue,
      };
      for (final EditCommandKind kind in EditCommandKind.values) {
        expect(
          kind.isFieldScoped,
          fieldScoped.contains(kind),
          reason: kind.wireName,
        );
        expect(
          kind.coalesces,
          coalescable.contains(kind),
          reason: kind.wireName,
        );
      }
    });
  });

  group('EditCommand', () {
    test('accepts valid metadata and defaults merged to false', () {
      final EditCommand command = EditCommand(
        id: _uuid(1),
        kind: EditCommandKind.move,
        fieldId: _fieldId,
        at: _at(10),
      );
      expect(command.id, _uuid(1));
      expect(command.kind, EditCommandKind.move);
      expect(command.fieldId, _fieldId);
      expect(command.at, _at(10));
      expect(command.at.isUtc, isTrue);
      expect(command.merged, isFalse);
      expect(command.toString(), 'EditCommand(kind: move, merged: false)');
    });

    test('accepts suggestion-resolution commands without a field id', () {
      for (final EditCommandKind kind in <EditCommandKind>[
        EditCommandKind.confirmSuggestion,
        EditCommandKind.rejectSuggestion,
      ]) {
        final EditCommand command = EditCommand(
          id: _uuid(2),
          kind: kind,
          at: _at(1),
        );
        expect(command.fieldId, isNull);
        expect(command.kind.isFieldScoped, isFalse);
      }
    });

    test('requires a field id for every field-scoped kind', () {
      for (final EditCommandKind kind in EditCommandKind.values) {
        if (!kind.isFieldScoped) {
          continue;
        }
        expect(
          () => EditCommand(id: _uuid(3), kind: kind, at: _at(1)),
          _failsWith(CommandHistoryErrorCode.fieldIdRequired),
          reason: kind.wireName,
        );
      }
    });

    test('forbids a field id on suggestion-resolution kinds', () {
      for (final EditCommandKind kind in <EditCommandKind>[
        EditCommandKind.confirmSuggestion,
        EditCommandKind.rejectSuggestion,
      ]) {
        expect(
          () => EditCommand(
            id: _uuid(4),
            kind: kind,
            fieldId: _fieldId,
            at: _at(1),
          ),
          _failsWith(CommandHistoryErrorCode.fieldIdForbidden),
          reason: kind.wireName,
        );
      }
    });

    test('rejects non-UUIDv4 ids content-free', () {
      const List<String> invalidIds = <String>[
        'not-a-uuid',
        '00000000-0000-4000-8000-00000000000A',
        '00000000-0000-3000-8000-000000000001',
        '00000000-0000-4000-c000-000000000001',
        '00000000-0000-4000-8000-00000000001',
        ' 00000000-0000-4000-8000-000000000001',
      ];
      for (final String id in invalidIds) {
        final CommandHistoryException exception = _captureException(() {
          EditCommand(
            id: id,
            kind: EditCommandKind.move,
            fieldId: _fieldId,
            at: _at(1),
          );
        });
        expect(exception.code, CommandHistoryErrorCode.invalidId);
        expect(exception.message, 'The command id is not a lowercase UUIDv4.');
        expect(exception.toString(), isNot(contains(id)));
      }
    });

    test('rejects a non-UTC timestamp content-free', () {
      final DateTime local = DateTime(2026, 11, 20, 12);
      final CommandHistoryException exception = _captureException(() {
        EditCommand(
          id: _uuid(5),
          kind: EditCommandKind.move,
          fieldId: _fieldId,
          at: local,
        );
      });
      expect(exception.code, CommandHistoryErrorCode.invalidTimestamp);
      expect(exception.message, 'The command timestamp must be UTC.');
      expect(exception.toString(), isNot(contains('2026')));
      expect(exception.toString(), isNot(contains(local.toString())));
    });
  });

  group('CommandHistory bounds', () {
    test('pins the §3.14 constants', () {
      expect(CommandHistory.maxEntries, 100);
      expect(
        CommandHistory.coalescingWindow,
        const Duration(milliseconds: 500),
      );
    });

    test('an empty history cannot undo or redo', () {
      final CommandHistory history = CommandHistory();
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
      expect(history.undoDepth, 0);
      expect(history.redoDepth, 0);
      expect(history.undo(), isNull);
      expect(history.redo(), isNull);
    });

    test('the 101st command drops the oldest entry', () {
      final CommandHistory history = CommandHistory();
      for (int index = 1; index <= 101; index++) {
        history.record(
          command: _command(
            id: index,
            kind: EditCommandKind.addField,
            at: _at(index),
          ),
          before: _content('before-$index'),
          after: _content('after-$index'),
        );
      }
      expect(history.undoDepth, 100);

      final List<String> undoneIds = <String>[];
      while (history.canUndo) {
        undoneIds.add(history.undo()!.command.id);
      }
      expect(undoneIds.length, 100);
      expect(undoneIds.first, _uuid(101));
      expect(undoneIds.last, _uuid(2));
      expect(undoneIds, isNot(contains(_uuid(1))));
      expect(history.undoDepth, 0);
      expect(history.redoDepth, 100);

      final List<String> redoneIds = <String>[];
      while (history.canRedo) {
        redoneIds.add(history.redo()!.command.id);
      }
      expect(redoneIds.length, 100);
      expect(redoneIds.first, _uuid(2));
      expect(redoneIds.last, _uuid(101));
      expect(history.undoDepth, 100);
      expect(history.redoDepth, 0);
    });
  });

  group('CommandHistory ordering', () {
    test('record, undo, and redo preserve exact order and snapshots', () {
      final CommandHistory history = CommandHistory();
      final RevisionContent c0 = _content('state-0');
      final RevisionContent c1 = _content('state-1');
      final RevisionContent c2 = _content('state-2');
      final HistoryEntry first = history.record(
        command: _command(id: 1, kind: EditCommandKind.addField, at: _at(10)),
        before: c0,
        after: c1,
      );
      final HistoryEntry second = history.record(
        command: _command(id: 2, kind: EditCommandKind.addField, at: _at(20)),
        before: c1,
        after: c2,
      );
      expect(history.undoDepth, 2);
      expect(history.redoDepth, 0);
      expect(history.canUndo, isTrue);
      expect(history.canRedo, isFalse);

      final HistoryEntry? undoneSecond = history.undo();
      expect(undoneSecond, same(second));
      expect(undoneSecond!.before, same(c1));
      expect(undoneSecond.after, same(c2));
      expect(history.undoDepth, 1);
      expect(history.redoDepth, 1);

      final HistoryEntry? undoneFirst = history.undo();
      expect(undoneFirst, same(first));
      expect(undoneFirst!.before, same(c0));
      expect(undoneFirst.after, same(c1));
      expect(history.undoDepth, 0);
      expect(history.redoDepth, 2);
      expect(history.canUndo, isFalse);
      expect(history.undo(), isNull);

      final HistoryEntry? redoneFirst = history.redo();
      expect(redoneFirst, same(first));
      expect(history.undoDepth, 1);
      expect(history.redoDepth, 1);
      final HistoryEntry? redoneSecond = history.redo();
      expect(redoneSecond, same(second));
      expect(history.undoDepth, 2);
      expect(history.redoDepth, 0);
      expect(history.redo(), isNull);
    });

    test('a new record clears the redo branch', () {
      final CommandHistory history = CommandHistory();
      history.record(
        command: _command(id: 1, kind: EditCommandKind.addField, at: _at(10)),
        before: _content('state-0'),
        after: _content('state-1'),
      );
      history.record(
        command: _command(id: 2, kind: EditCommandKind.addField, at: _at(20)),
        before: _content('state-1'),
        after: _content('state-2'),
      );
      expect(history.undo()!.command.id, _uuid(2));
      expect(history.redoDepth, 1);
      expect(history.canRedo, isTrue);

      final HistoryEntry third = history.record(
        command: _command(id: 3, kind: EditCommandKind.addField, at: _at(30)),
        before: _content('state-1'),
        after: _content('state-3'),
      );
      expect(history.redoDepth, 0);
      expect(history.canRedo, isFalse);
      expect(history.undo()!.command.id, third.command.id);
      expect(history.undo()!.command.id, _uuid(1));
      expect(history.redo()!.command.id, _uuid(1));
      expect(history.redo()!.command.id, _uuid(3));
      expect(history.redo(), isNull);
    });

    test('undo and redo interleave without losing order', () {
      final CommandHistory history = CommandHistory();
      for (int index = 1; index <= 3; index++) {
        history.record(
          command: _command(
            id: index,
            kind: EditCommandKind.addField,
            at: _at(index * 10),
          ),
          before: _content('state-${index - 1}'),
          after: _content('state-$index'),
        );
      }

      expect(history.undo()!.command.id, _uuid(3));
      expect(history.undo()!.command.id, _uuid(2));
      expect(history.undoDepth, 1);
      expect(history.redoDepth, 2);

      expect(history.redo()!.command.id, _uuid(2));
      expect(history.undo()!.command.id, _uuid(2));
      expect(history.undo()!.command.id, _uuid(1));
      expect(history.undoDepth, 0);
      expect(history.redoDepth, 3);

      expect(history.redo()!.command.id, _uuid(1));
      expect(history.redo()!.command.id, _uuid(2));
      expect(history.redo()!.command.id, _uuid(3));
      expect(history.redo(), isNull);
      expect(history.undoDepth, 3);
      expect(history.redoDepth, 0);
    });
  });

  group('CommandHistory coalescing', () {
    test('coalesces the same kind and field at 499 ms', () {
      final CommandHistory history = CommandHistory();
      final RevisionContent c0 = _content('state-0');
      final RevisionContent c1 = _content('state-1');
      final RevisionContent c2 = _content('state-2');
      final HistoryEntry first = history.record(
        command: _command(id: 1, kind: EditCommandKind.move, at: _at(0)),
        before: c0,
        after: c1,
      );
      final HistoryEntry merged = history.record(
        command: _command(id: 2, kind: EditCommandKind.move, at: _at(499)),
        before: c1,
        after: c2,
      );

      expect(history.undoDepth, 1);
      expect(merged.command.merged, isTrue);
      expect(merged.command.id, first.command.id);
      expect(merged.command.kind, EditCommandKind.move);
      expect(merged.command.fieldId, _fieldId);
      expect(merged.command.at, _at(499));
      expect(merged.before, same(c0));
      expect(merged.after, same(c2));
      expect(first.command.merged, isFalse);

      final HistoryEntry undone = history.undo()!;
      expect(undone.before, same(c0));
      expect(undone.after, same(c2));
      expect(history.canUndo, isFalse);
      expect(history.redoDepth, 1);
    });

    test('coalesces at the inclusive 500 ms boundary', () {
      final CommandHistory history = CommandHistory();
      final RevisionContent c0 = _content('state-0');
      final RevisionContent c1 = _content('state-1');
      final RevisionContent c2 = _content('state-2');
      history.record(
        command: _command(id: 1, kind: EditCommandKind.resize, at: _at(100)),
        before: c0,
        after: c1,
      );
      final HistoryEntry merged = history.record(
        command: _command(id: 2, kind: EditCommandKind.resize, at: _at(600)),
        before: c1,
        after: c2,
      );

      expect(history.undoDepth, 1);
      expect(merged.command.merged, isTrue);
      expect(merged.command.at, _at(600));
      expect(merged.before, same(c0));
      expect(merged.after, same(c2));
    });

    test('coalesces equal timestamps at the lower bound', () {
      final CommandHistory history = CommandHistory();
      history.record(
        command: _command(id: 1, kind: EditCommandKind.setValue, at: _at(250)),
        before: _content('state-0'),
        after: _content('state-1'),
      );
      final HistoryEntry merged = history.record(
        command: _command(id: 2, kind: EditCommandKind.setValue, at: _at(250)),
        before: _content('state-1'),
        after: _content('state-2'),
      );

      expect(history.undoDepth, 1);
      expect(merged.command.merged, isTrue);
      expect(merged.command.at, _at(250));
    });

    test('does not coalesce at 501 ms', () {
      final CommandHistory history = CommandHistory();
      final RevisionContent c0 = _content('state-0');
      final RevisionContent c1 = _content('state-1');
      final RevisionContent c2 = _content('state-2');
      history.record(
        command: _command(id: 1, kind: EditCommandKind.move, at: _at(0)),
        before: c0,
        after: c1,
      );
      final HistoryEntry second = history.record(
        command: _command(id: 2, kind: EditCommandKind.move, at: _at(501)),
        before: c1,
        after: c2,
      );

      expect(history.undoDepth, 2);
      expect(second.command.merged, isFalse);
      expect(second.before, same(c1));
      expect(second.after, same(c2));
      expect(history.undo()!.command.id, _uuid(2));
      expect(history.undo()!.command.id, _uuid(1));
    });

    test('setValue coalesces as typing for the same field', () {
      final CommandHistory history = CommandHistory();
      history.record(
        command: _command(id: 1, kind: EditCommandKind.setValue, at: _at(10)),
        before: _content('state-0'),
        after: _content('state-1'),
      );
      final HistoryEntry merged = history.record(
        command: _command(id: 2, kind: EditCommandKind.setValue, at: _at(510)),
        before: _content('state-1'),
        after: _content('state-2'),
      );

      expect(history.undoDepth, 1);
      expect(merged.command.merged, isTrue);
    });

    test('does not coalesce different fields or different kinds', () {
      final CommandHistory history = CommandHistory();
      history.record(
        command: _command(id: 1, kind: EditCommandKind.move, at: _at(0)),
        before: _content('state-0'),
        after: _content('state-1'),
      );
      final HistoryEntry otherField = history.record(
        command: _command(
          id: 2,
          kind: EditCommandKind.move,
          fieldId: _otherFieldId,
          at: _at(10),
        ),
        before: _content('state-1'),
        after: _content('state-2'),
      );
      final HistoryEntry sameFieldOtherKind = history.record(
        command: _command(id: 3, kind: EditCommandKind.resize, at: _at(20)),
        before: _content('state-2'),
        after: _content('state-3'),
      );

      expect(history.undoDepth, 3);
      expect(otherField.command.merged, isFalse);
      expect(sameFieldOtherKind.command.merged, isFalse);
    });

    test('non-coalescable kinds never merge', () {
      for (final EditCommandKind kind in EditCommandKind.values) {
        if (kind.coalesces) {
          continue;
        }
        final CommandHistory history = CommandHistory();
        history.record(
          command: _command(
            id: 1,
            kind: kind,
            at: _at(0),
            fieldId: kind.isFieldScoped ? _fieldId : null,
          ),
          before: _content('state-0'),
          after: _content('state-1'),
        );
        final HistoryEntry second = history.record(
          command: _command(
            id: 2,
            kind: kind,
            at: _at(1),
            fieldId: kind.isFieldScoped ? _fieldId : null,
          ),
          before: _content('state-1'),
          after: _content('state-2'),
        );

        expect(history.undoDepth, 2, reason: kind.wireName);
        expect(second.command.merged, isFalse, reason: kind.wireName);
      }
    });

    test('merged is true only on the coalesced entry', () {
      final CommandHistory history = CommandHistory();
      final HistoryEntry add = history.record(
        command: _command(id: 1, kind: EditCommandKind.addField, at: _at(0)),
        before: _content('state-0'),
        after: _content('state-1'),
      );
      final HistoryEntry firstMove = history.record(
        command: _command(id: 2, kind: EditCommandKind.move, at: _at(10)),
        before: _content('state-1'),
        after: _content('state-2'),
      );
      final HistoryEntry mergedMove = history.record(
        command: _command(id: 3, kind: EditCommandKind.move, at: _at(510)),
        before: _content('state-2'),
        after: _content('state-3'),
      );

      expect(add.command.merged, isFalse);
      expect(firstMove.command.merged, isFalse);
      expect(mergedMove.command.merged, isTrue);
      expect(history.undoDepth, 2);
      expect(history.undo()!.command.merged, isTrue);
      expect(history.undo()!.command.merged, isFalse);
    });
  });

  group('CommandHistory validation and immutability', () {
    test('rejects an older timestamp content-free', () {
      final CommandHistory history = CommandHistory();
      history.record(
        command: _command(id: 1, kind: EditCommandKind.addField, at: _at(1000)),
        before: _content('state-0'),
        after: _content('state-1'),
      );
      history.record(
        command: _command(id: 2, kind: EditCommandKind.addField, at: _at(2000)),
        before: _content('state-1'),
        after: _content('state-2'),
      );
      history.undo();

      final CommandHistoryException exception = _captureException(() {
        history.record(
          command: _command(
            id: 3,
            kind: EditCommandKind.addField,
            at: _at(999),
          ),
          before: _content('state-1'),
          after: _content('state-3'),
        );
      });
      expect(exception.code, CommandHistoryErrorCode.nonMonotonicTimestamp);
      expect(
        exception.message,
        'The command timestamp precedes the newest undo entry.',
      );
      expect(exception.toString(), isNot(contains('999')));
      expect(history.undoDepth, 1);
      expect(history.redoDepth, 1);
      expect(history.canRedo, isTrue);
      expect(history.undo()!.command.id, _uuid(1));
    });

    test('accepts an equal timestamp on a non-coalescable kind', () {
      final CommandHistory history = CommandHistory();
      history.record(
        command: _command(id: 1, kind: EditCommandKind.reorder, at: _at(50)),
        before: _content('state-0'),
        after: _content('state-1'),
      );
      final HistoryEntry second = history.record(
        command: _command(id: 2, kind: EditCommandKind.reorder, at: _at(50)),
        before: _content('state-1'),
        after: _content('state-2'),
      );

      expect(history.undoDepth, 2);
      expect(second.command.merged, isFalse);
    });

    test('stored snapshots are never mutated', () {
      final CommandHistory history = CommandHistory();
      final RevisionContent before = _content('before');
      final RevisionContent middle = _content('middle');
      final RevisionContent after = _content('after');
      final String beforeJson = canonicalJsonEncode(before.toJson());
      final String middleJson = canonicalJsonEncode(middle.toJson());
      final String afterJson = canonicalJsonEncode(after.toJson());

      history.record(
        command: _command(id: 1, kind: EditCommandKind.move, at: _at(0)),
        before: before,
        after: middle,
      );
      final HistoryEntry merged = history.record(
        command: _command(id: 2, kind: EditCommandKind.move, at: _at(100)),
        before: middle,
        after: after,
      );

      expect(merged.before, same(before));
      expect(merged.after, same(after));
      expect(canonicalJsonEncode(merged.before.toJson()), beforeJson);
      expect(canonicalJsonEncode(merged.after.toJson()), afterJson);

      final HistoryEntry undone = history.undo()!;
      history.redo();
      history.undo();
      expect(undone.before, same(before));
      expect(undone.after, same(after));
      expect(canonicalJsonEncode(before.toJson()), beforeJson);
      expect(canonicalJsonEncode(middle.toJson()), middleJson);
      expect(canonicalJsonEncode(after.toJson()), afterJson);
    });

    test('identical command sequences produce identical histories', () {
      const List<EditCommandKind> kinds = <EditCommandKind>[
        EditCommandKind.move,
        EditCommandKind.move,
        EditCommandKind.addField,
        EditCommandKind.setValue,
        EditCommandKind.setValue,
        EditCommandKind.reorder,
        EditCommandKind.resize,
        EditCommandKind.resize,
      ];
      const List<int> times = <int>[0, 100, 200, 300, 700, 800, 900, 1000];
      final List<RevisionContent> states = <RevisionContent>[
        for (int index = 0; index <= kinds.length; index++)
          _content('state-$index'),
      ];

      CommandHistory build() {
        final CommandHistory history = CommandHistory();
        for (int index = 0; index < kinds.length; index++) {
          history.record(
            command: _command(
              id: index + 1,
              kind: kinds[index],
              at: _at(times[index]),
            ),
            before: states[index],
            after: states[index + 1],
          );
        }
        return history;
      }

      final CommandHistory first = build();
      final CommandHistory second = build();
      expect(first.undoDepth, second.undoDepth);
      expect(first.redoDepth, second.redoDepth);

      final List<HistoryEntry> firstEntries = <HistoryEntry>[];
      while (first.canUndo) {
        firstEntries.add(first.undo()!);
      }
      final List<HistoryEntry> secondEntries = <HistoryEntry>[];
      while (second.canUndo) {
        secondEntries.add(second.undo()!);
      }
      expect(firstEntries, secondEntries);
      expect(first.undoDepth, second.undoDepth);
      expect(first.redoDepth, second.redoDepth);
    });
  });
}
