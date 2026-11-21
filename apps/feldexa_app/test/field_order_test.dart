// T073 field-order model tests (FR-026).
//
// Evidence class: NONE. These are host-VM unit tests with synthetic in-memory
// revisions. They open no document, start no browser, emulator, or device, and
// make no Android runtime, screen-reader, or visual claim.
//
// They prove the field-order contract:
//   * the deterministic page → y → x → id default order and the current
//     user-visible `fieldOrder` projection;
//   * the review read model exposes page, position, label, type, provenance,
//     confidence, conflict, and T085 completion;
//   * move-to-index and move-up/move-down renumber `order` contiguously and
//     preserve pages, suggestions, values, signatures, verification, and
//     unknown extensions;
//   * a reorder step is one exact, non-coalescing T067 undo entry that restores
//     the previous order, values, and geometry;
//   * a reordered snapshot round-trips through the persisted JSON form;
//   * previous/next follow the current order, never wrap, and are safe at the
//     boundaries and on a document without confirmed fields;
//   * degenerate id lists never drop a field and never throw.

@TestOn('vm')
library;

import 'package:feldexa_app/features/editor/field_completion.dart';
import 'package:feldexa_app/features/editor/field_order.dart';
import 'package:feldexa_application/src/review/command_history.dart' as history;
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter_test/flutter_test.dart';

const String _f1 = '11111111-1111-4111-8111-111111111111';
const String _f2 = '22222222-2222-4222-8222-222222222222';
const String _f3 = '33333333-3333-4333-8333-333333333333';
const String _f4 = '44444444-4444-4444-8444-444444444444';
const String _f5 = '55555555-5555-4555-8555-555555555555';
const String _f6 = '66666666-6666-4666-8666-666666666666';
const String _signatureAsset = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
const String _suggestionA = 's_p0_0001';
const String _suggestionB = 's_p0_0002';
const String _historyId = '99999999-9999-4999-8999-999999999999';
const String _historyId2 = '99999999-9999-4999-8999-999999999998';
final String _sha256 = List<String>.filled(64, 'a').join();

final DateTime _createdAt = DateTime.utc(2026, 11, 21, 8);
final DateTime _editedAt = DateTime.utc(2026, 11, 21, 9);
final DateTime _commandAt = DateTime.utc(2026, 11, 21, 10);

core.Page _page(int index, {double height = 300}) {
  return core.Page(
    index: index,
    geometry: core.PageGeometry(
      mediaBox: core.Rect.fromLTWH(0, 0, 300, height),
    ),
    analysis: core.AnalysisState.complete,
  );
}

core.FieldSuggestion _suggestion({
  required String id,
  required core.Rect rect,
  required double confidence,
  required List<String> conflictsWith,
  required core.SuggestionResolution resolution,
  String? labelText,
}) {
  return core.FieldSuggestion(
    id: id,
    pageIndex: 0,
    rect: rect,
    proposedType: core.FieldType.number,
    confidence: confidence,
    labelText: labelText,
    evidence: core.SuggestionEvidence(
      cues: const <core.SuggestionCue>[core.SuggestionCue.underline],
      ocrUsed: false,
    ),
    conflictsWith: conflictsWith,
    resolution: resolution,
  );
}

/// The six-field fixture in the stored order `f1 … f6`.
///
/// The stored order is deliberately not the page order: field `f2` sits above
/// `f1` on page 0, so [defaultDocumentFieldOrder] must produce
/// `f2, f1, f5, f3, f4, f6`.
core.RevisionContent _content({List<String>? fieldOrder}) {
  final List<core.ConfirmedField> fields = <core.ConfirmedField>[
    core.ConfirmedField(
      id: _f1,
      pageIndex: 0,
      rect: core.Rect.fromLTWH(40, 120, 100, 20),
      type: core.FieldType.text,
      provenance: core.Provenance.user,
      label: 'Name',
      order: 0,
      createdAt: _createdAt,
      updatedAt: _createdAt,
      validation: core.FieldValidation.warning(
        core.WarningCode.overflow,
        'FLD-001',
      ),
    ),
    core.ConfirmedField(
      id: _f2,
      pageIndex: 0,
      rect: core.Rect.fromLTWH(40, 60, 100, 20),
      type: core.FieldType.number,
      provenance: core.Provenance.machine,
      sourceSuggestionId: _suggestionA,
      suggestionConfidence: 0.82,
      label: 'Betrag',
      order: 1,
      createdAt: _createdAt,
      updatedAt: _createdAt,
    ),
    core.ConfirmedField(
      id: _f3,
      pageIndex: 1,
      rect: core.Rect.fromLTWH(40, 40, 120, 20),
      type: core.FieldType.checkbox,
      provenance: core.Provenance.user,
      label: 'Zustimmung',
      order: 2,
      createdAt: _createdAt,
      updatedAt: _createdAt,
    ),
    core.ConfirmedField(
      id: _f4,
      pageIndex: 1,
      rect: core.Rect.fromLTWH(40, 200, 160, 60),
      type: core.FieldType.signature,
      provenance: core.Provenance.user,
      label: 'Unterschrift',
      order: 3,
      createdAt: _createdAt,
      updatedAt: _createdAt,
    ),
    core.ConfirmedField(
      id: _f5,
      pageIndex: 0,
      rect: core.Rect.fromLTWH(40, 200, 100, 20),
      type: core.FieldType.text,
      provenance: core.Provenance.user,
      label: 'Hinweis',
      order: 4,
      createdAt: _createdAt,
      updatedAt: _createdAt,
      validation: core.FieldValidation.warning(
        core.WarningCode.incompatibleContent,
        'FLD-002',
      ),
    ),
    core.ConfirmedField(
      id: _f6,
      pageIndex: 1,
      rect: core.Rect.fromLTWH(40, 300, 100, 20),
      type: core.FieldType.multiline,
      provenance: core.Provenance.user,
      label: 'Bemerkung',
      order: 5,
      createdAt: _createdAt,
      updatedAt: _createdAt,
    ),
  ];
  final List<String> order =
      fieldOrder ??
      <String>[for (final core.ConfirmedField field in fields) field.id];
  final Map<String, core.ConfirmedField> byId = <String, core.ConfirmedField>{
    for (final core.ConfirmedField field in fields) field.id: field,
  };
  return core.RevisionContent(
    pages: <core.Page>[_page(0), _page(1, height: 400)],
    suggestions: <core.FieldSuggestion>[
      _suggestion(
        id: _suggestionA,
        rect: core.Rect.fromLTWH(40, 60, 100, 20),
        confidence: 0.82,
        conflictsWith: <String>[_suggestionB],
        resolution: core.SuggestionResolution.confirmed,
        labelText: 'Betrag',
      ),
      _suggestion(
        id: _suggestionB,
        rect: core.Rect.fromLTWH(50, 60, 100, 20),
        confidence: 0.70,
        conflictsWith: <String>[_suggestionA],
        resolution: core.SuggestionResolution.unresolved,
      ),
    ],
    fields: <core.ConfirmedField>[
      for (final String id in order)
        byId[id]!.copyWith(order: order.indexOf(id)),
    ],
    fieldOrder: order,
    values: <String, core.FieldValue>{
      _f1: core.TextValue(text: 'Ada', lastEditedAt: _editedAt),
      _f2: core.NumberValue(
        canonical: '1234.56',
        rawGerman: '1234,56',
        lastEditedAt: _editedAt,
      ),
      _f3: core.CheckboxValue(checked: true, lastEditedAt: _editedAt),
      _f4: core.SignatureValue(
        signatureAssetId: _signatureAsset,
        lastEditedAt: _editedAt,
      ),
      _f5: core.IncompatibleValue(
        preservedText: '31.02.2025',
        reasonCode: 'reclassified_to_text',
        lastEditedAt: _editedAt,
      ),
    },
    signatures: <String, core.SignatureMark>{
      _f4: core.SignatureMark(
        assetId: _signatureAsset,
        fieldId: _f4,
        pageIndex: 1,
        rect: core.Rect.fromLTWH(40, 200, 160, 60),
        widthPx: 160,
        heightPx: 60,
        capturedAt: _editedAt,
        sha256: _sha256,
      ),
    },
    verification: <String, core.FieldVerification>{
      _f2: core.FieldVerification(
        state: core.FieldVerificationState.confirmed,
        reviewedAt: _editedAt,
      ),
    },
    unknownFields: const <String, Object?>{
      'x-test-extension': <String, Object?>{'kept': true},
    },
  );
}

core.RevisionContent _emptyContent() {
  return core.RevisionContent(
    pages: <core.Page>[_page(0)],
    fieldOrder: const <String>[],
  );
}

List<String> _ids(core.RevisionContent content) {
  return <String>[
    for (final core.ConfirmedField field in content.fields) field.id,
  ];
}

List<int> _orders(core.RevisionContent content) {
  return <int>[
    for (final core.ConfirmedField field in content.fields) field.order,
  ];
}

void main() {
  group('deterministic document order', () {
    test('sorts by page, y, x, then id regardless of the stored order', () {
      final core.RevisionContent forward = _content();
      final core.RevisionContent reversed = _content(
        fieldOrder: <String>[_f6, _f5, _f4, _f3, _f2, _f1],
      );

      const List<String> expected = <String>[_f2, _f1, _f5, _f3, _f4, _f6];
      expect(defaultDocumentFieldOrder(forward), expected);
      expect(defaultDocumentFieldOrder(reversed), expected);
    });

    test('breaks a full tie with the stable field id', () {
      core.ConfirmedField field(String id, int order) {
        return core.ConfirmedField(
          id: id,
          pageIndex: 0,
          rect: core.Rect.fromLTWH(10, 10, 20, 20),
          type: core.FieldType.text,
          provenance: core.Provenance.user,
          label: 'Feld',
          order: order,
          createdAt: _createdAt,
          updatedAt: _createdAt,
        );
      }

      final List<core.ConfirmedField> fields = <core.ConfirmedField>[
        field(_f2, 0),
        field(_f1, 1),
      ];
      expect(
        orderedFields(
          core.RevisionContent(
            pages: <core.Page>[_page(0)],
            fields: fields,
            fieldOrder: <String>[_f2, _f1],
          ),
        ).map((core.ConfirmedField value) => value.id).toList(),
        <String>[_f2, _f1],
      );
      expect(
        resolveFieldOrder(
          fields: fields,
          fieldOrder: const <String>[],
        ).map((core.ConfirmedField value) => value.id).toList(),
        <String>[_f1, _f2],
      );
    });

    test('the current order follows fieldOrder, not the page order', () {
      expect(
        orderedFields(_content())
            .map((core.ConfirmedField field) => field.id)
            .toList(),
        <String>[_f1, _f2, _f3, _f4, _f5, _f6],
      );
      expect(fieldOrderIds(_content()), <String>[_f1, _f2, _f3, _f4, _f5, _f6]);
    });

    test('a degenerate id list never drops or duplicates a field', () {
      final List<core.ConfirmedField> fields = _content().fields;
      final List<core.ConfirmedField> resolved = resolveFieldOrder(
        fields: fields,
        fieldOrder: <String>[_f3, 'unknown-id', _f3, _f1],
      );

      expect(
        resolved.map((core.ConfirmedField field) => field.id).toList(),
        <String>[_f3, _f1, _f2, _f5, _f4, _f6],
      );
      expect(
        resolveFieldOrder(fields: fields, fieldOrder: const <String>[]),
        hasLength(6),
      );
    });
  });

  group('review read model', () {
    test('exposes page, position, label, type, provenance and confidence', () {
      final List<FieldOrderEntry> entries = fieldOrderEntries(_content());

      expect(entries, hasLength(6));
      expect(
        entries.map((FieldOrderEntry entry) => entry.number).toList(),
        <int>[1, 2, 3, 4, 5, 6],
      );
      expect(
        entries.map((FieldOrderEntry entry) => entry.pageIndex).toList(),
        <int>[0, 0, 1, 1, 0, 1],
      );
      expect(
        entries.map((FieldOrderEntry entry) => entry.label).toList(),
        <String>[
          'Name',
          'Betrag',
          'Zustimmung',
          'Unterschrift',
          'Hinweis',
          'Bemerkung',
        ],
      );
      expect(
        entries.map((FieldOrderEntry entry) => entry.type).toList(),
        <core.FieldType>[
          core.FieldType.text,
          core.FieldType.number,
          core.FieldType.checkbox,
          core.FieldType.signature,
          core.FieldType.text,
          core.FieldType.multiline,
        ],
      );
      expect(
        entries.map((FieldOrderEntry entry) => entry.provenance).toList(),
        <core.Provenance>[
          core.Provenance.user,
          core.Provenance.machine,
          core.Provenance.user,
          core.Provenance.user,
          core.Provenance.user,
          core.Provenance.user,
        ],
      );
      expect(
        entries.map((FieldOrderEntry entry) => entry.confidence).toList(),
        <double?>[null, 0.82, null, null, null, null],
      );
    });

    test('reports the conflict while the source suggestion carries it', () {
      final List<FieldOrderEntry> entries = fieldOrderEntries(_content());
      expect(entries[1].conflicting, isTrue);
      expect(entries[0].conflicting, isFalse);
    });

    test('maps every T085 completion state', () {
      final List<FieldOrderEntry> entries = fieldOrderEntries(_content());
      expect(
        entries.map((FieldOrderEntry entry) => entry.completion).toList(),
        <FieldCompletionState>[
          FieldCompletionState.warning,
          FieldCompletionState.complete,
          FieldCompletionState.complete,
          FieldCompletionState.complete,
          FieldCompletionState.incompatible,
          FieldCompletionState.optionalEmpty,
        ],
      );
    });

    test('reports a blocking validation error as blocking completion', () {
      final core.RevisionContent content = core.RevisionContent(
        pages: <core.Page>[_page(0)],
        fields: <core.ConfirmedField>[
          core.ConfirmedField(
            id: _f1,
            pageIndex: 0,
            rect: core.Rect.fromLTWH(40, 40, 100, 20),
            type: core.FieldType.number,
            provenance: core.Provenance.user,
            label: 'Betrag',
            order: 0,
            createdAt: _createdAt,
            updatedAt: _createdAt,
            validation: core.FieldValidation.error('NUM-001'),
          ),
        ],
        fieldOrder: const <String>[_f1],
      );

      final FieldOrderEntry entry = fieldOrderEntries(content).single;
      expect(entry.completion, FieldCompletionState.blockingError);
      expect(entry.confidence, isNull);
    });

    test('a document without confirmed fields yields no rows', () {
      expect(fieldOrderEntries(_emptyContent()), isEmpty);
    });
  });

  group('reorder', () {
    test('moveFieldToIndex renumbers order contiguously', () {
      final core.RevisionContent content = _content();
      final FieldOrderChange change = moveFieldToIndex(content, _f3, 0);

      expect(change.changed, isTrue);
      expect(change.fieldId, _f3);
      expect(change.previousIndex, 2);
      expect(change.newIndex, 0);
      expect(_ids(change.content), <String>[_f3, _f1, _f2, _f4, _f5, _f6]);
      expect(change.content.fieldOrder, _ids(change.content));
      expect(_orders(change.content), <int>[0, 1, 2, 3, 4, 5]);
    });

    test('preserves pages, suggestions, values, signatures and extensions', () {
      final core.RevisionContent content = _content();
      final core.RevisionContent next = moveFieldToIndex(
        content,
        _f6,
        0,
      ).content;

      expect(next.pages, content.pages);
      expect(next.suggestions, content.suggestions);
      expect(next.values, content.values);
      expect(next.signatures, content.signatures);
      expect(next.verification, content.verification);
      expect(next.templateOrigin, content.templateOrigin);
      expect(next.unknownFields, content.unknownFields);
      final Map<String, core.ConfirmedField> before =
          <String, core.ConfirmedField>{
            for (final core.ConfirmedField field in content.fields)
              field.id: field,
          };
      for (final core.ConfirmedField field in next.fields) {
        final core.ConfirmedField original = before[field.id]!;
        expect(field.rect, original.rect);
        expect(field.pageIndex, original.pageIndex);
        expect(field.type, original.type);
        expect(field.label, original.label);
        expect(field.validation, original.validation);
        expect(field.updatedAt, original.updatedAt);
      }
    });

    test('a no-op move returns the same snapshot and changed is false', () {
      final core.RevisionContent content = _content();
      final FieldOrderChange change = moveFieldToIndex(content, _f1, 0);

      expect(change.changed, isFalse);
      expect(identical(change.content, content), isTrue);
    });

    test('moveFieldUp and moveFieldDown stop at the boundaries', () {
      final core.RevisionContent content = _content();

      expect(moveFieldUp(content, _f1), isNull);
      expect(moveFieldDown(content, _f6), isNull);
      expect(moveFieldUp(content, 'unknown-id'), isNull);
      expect(moveFieldDown(content, 'unknown-id'), isNull);

      final FieldOrderChange up = moveFieldUp(content, _f2)!;
      expect(_ids(up.content).take(2).toList(), <String>[_f2, _f1]);

      final FieldOrderChange down = moveFieldDown(content, _f2)!;
      expect(_ids(down.content).take(3).toList(), <String>[_f1, _f3, _f2]);
    });

    test('rejects an unknown field and an out-of-range index', () {
      final core.RevisionContent content = _content();

      expect(
        () => moveFieldToIndex(content, 'unknown-id', 0),
        throwsA(
          isA<FieldOrderException>().having(
            (FieldOrderException error) => error.code,
            'code',
            FieldOrderErrorCode.fieldNotFound,
          ),
        ),
      );
      expect(
        () => moveFieldToIndex(content, _f1, -1),
        throwsA(
          isA<FieldOrderException>().having(
            (FieldOrderException error) => error.code,
            'code',
            FieldOrderErrorCode.indexOutOfBounds,
          ),
        ),
      );
      expect(
        () => moveFieldToIndex(content, _f1, 6),
        throwsA(
          isA<FieldOrderException>().having(
            (FieldOrderException error) => error.code,
            'code',
            FieldOrderErrorCode.indexOutOfBounds,
          ),
        ),
      );
      expect(
        const FieldOrderException(FieldOrderErrorCode.fieldNotFound).toString(),
        isNot(contains(_f1)),
      );
    });
  });

  group('undo and persistence', () {
    test('one reorder step undoes to the exact previous order and values', () {
      final core.RevisionContent before = _content();
      final core.RevisionContent after = moveFieldToIndex(
        before,
        _f2,
        5,
      ).content;
      final history.CommandHistory commands = history.CommandHistory();
      commands.record(
        command: history.EditCommand(
          id: _historyId,
          kind: history.EditCommandKind.reorder,
          fieldId: _f2,
          at: _commandAt,
        ),
        before: before,
        after: after,
      );

      expect(commands.undoDepth, 1);
      final history.HistoryEntry undone = commands.undo()!;
      expect(undone.before, before);
      expect(_ids(undone.before), _ids(before));
      expect(_orders(undone.before), _orders(before));
      expect(undone.before.values, before.values);
      expect(undone.before.fields[1].rect, before.fields[1].rect);

      final history.HistoryEntry redone = commands.redo()!;
      expect(redone.after, after);
      expect(_ids(redone.after), _ids(after));
      expect(_ids(redone.after).last, _f2);
    });

    test('reorder commands never coalesce into one undo step', () {
      final core.RevisionContent first = _content();
      final core.RevisionContent second = moveFieldToIndex(
        first,
        _f2,
        0,
      ).content;
      final core.RevisionContent third = moveFieldToIndex(
        second,
        _f3,
        0,
      ).content;
      final history.CommandHistory commands = history.CommandHistory();

      commands.record(
        command: history.EditCommand(
          id: _historyId,
          kind: history.EditCommandKind.reorder,
          fieldId: _f2,
          at: _commandAt,
        ),
        before: first,
        after: second,
      );
      commands.record(
        command: history.EditCommand(
          id: _historyId2,
          kind: history.EditCommandKind.reorder,
          fieldId: _f2,
          at: _commandAt.add(const Duration(milliseconds: 100)),
        ),
        before: second,
        after: third,
      );

      expect(history.EditCommandKind.reorder.isFieldScoped, isTrue);
      expect(history.EditCommandKind.reorder.coalesces, isFalse);
      expect(commands.undoDepth, 2);
      expect(commands.undo()!.before, second);
      expect(commands.undo()!.before, first);
    });

    test('a reordered snapshot round-trips through persisted JSON', () {
      final core.RevisionContent moved = moveFieldToIndex(
        _content(),
        _f4,
        0,
      ).content;
      final core.RevisionContent restored = core.RevisionContent.fromJson(
        moved.toJson(),
      );

      expect(restored, moved);
      expect(restored.fieldOrder, moved.fieldOrder);
      expect(_orders(restored), <int>[0, 1, 2, 3, 4, 5]);
      expect(restored.values, moved.values);
      expect(restored.signatures, moved.signatures);
      expect(
        core.canonicalJsonEncode(restored.toJson()),
        core.canonicalJsonEncode(moved.toJson()),
      );
    });
  });

  group('next and previous in the current order', () {
    test('walk the stored order without wrapping', () {
      final core.RevisionContent content = _content();

      expect(nextFieldId(content, null), _f1);
      expect(previousFieldId(content, null), _f6);
      expect(nextFieldId(content, _f1), _f2);
      expect(previousFieldId(content, _f1), isNull);
      expect(nextFieldId(content, _f6), isNull);
      expect(previousFieldId(content, _f6), _f5);
      expect(nextFieldId(content, 'unknown-id'), _f1);
      expect(previousFieldId(content, 'unknown-id'), _f6);
    });

    test('follow a reordered snapshot', () {
      final core.RevisionContent moved = moveFieldToIndex(
        _content(),
        _f6,
        0,
      ).content;

      expect(nextFieldId(moved, null), _f6);
      expect(nextFieldId(moved, _f6), _f1);
      expect(previousFieldId(moved, _f1), _f6);
      expect(previousFieldId(moved, null), _f5);
    });

    test('are safe without confirmed fields', () {
      final core.RevisionContent empty = _emptyContent();
      expect(nextFieldId(empty, null), isNull);
      expect(previousFieldId(empty, null), isNull);
      expect(nextFieldId(empty, _f1), isNull);
      expect(previousFieldId(empty, _f1), isNull);
      expect(fieldOrderEntries(empty), isEmpty);
      expect(orderedFields(empty), isEmpty);
      expect(defaultDocumentFieldOrder(empty), isEmpty);
    });

    test('navigation never mutates the revision', () {
      final core.RevisionContent content = _content();
      nextFieldId(content, _f2);
      previousFieldId(content, _f2);
      expect(content, _content());
    });
  });
}
