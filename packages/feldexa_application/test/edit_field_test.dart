// T066 confirmed-field edit command tests.
//
// These are host-VM tests (evidence class NONE). They pin the T066 deliverable
// in `packages/feldexa_application/lib/src/review/edit_field.dart` against
// FR-023, FR-024, FR-029, and FR-038, `data-model.md` §3.4–§3.6, and
// `contracts/recognition-output.md` §7:
//   * add creates a user field with exact geometry and explicit timestamps;
//   * remove cleans every keyed value/signature/verification entry, renumbers
//     contiguously, and turns a removed machine field's suggestion into the
//     documented audit rejection;
//   * move/resize preserve every non-geometry part and store the exact rect;
//   * every reclassification transition preserves or flags content per the
//     data-model matrix, with line-break joining only on explicit confirmation;
//   * every result is a valid core `RevisionContent`, inputs are immutable,
//     commands are deterministic and free of I/O/clock/id randomness, every
//     error is content-free, and every receipt carries undo snapshots.

import 'dart:convert';
import 'dart:io';

import 'package:feldexa_application/src/review/edit_field.dart';
import 'package:feldexa_core/feldexa_core.dart' hide reclassifyField;
import 'package:flutter_test/flutter_test.dart';

const String _sha256 =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

String _uuid(int value) {
  return '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
}

DateTime _at([int minute = 0]) => DateTime.utc(2026, 11, 20, 12, minute);

Rect _rect({
  double left = 50,
  double top = 60,
  double width = 140,
  double height = 20,
}) {
  return Rect.fromLTWH(left, top, width, height);
}

PageGeometry _geometry({double width = 595, double height = 842}) {
  return PageGeometry(mediaBox: Rect.fromLTWH(0, 0, width, height));
}

Page _page([int index = 0]) {
  return Page(index: index, geometry: _geometry());
}

TemplateOrigin _origin() {
  return TemplateOrigin(
    templateId: _uuid(80),
    templateVersionId: _uuid(81),
    templateVersionNumber: 3,
  );
}

SuggestionEvidence _evidence() {
  return SuggestionEvidence(cues: const <SuggestionCue>[SuggestionCue.line]);
}

FieldSuggestion _suggestion({
  int pageIndex = 0,
  int ordinal = 1,
  Rect? rect,
  FieldType proposedType = FieldType.text,
  double confidence = 0.82,
  String? labelText = 'Name',
  SuggestionResolution resolution = SuggestionResolution.unresolved,
  bool duplicateOfConfirmed = false,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return FieldSuggestion(
    id: FieldSuggestion.idFor(pageIndex: pageIndex, ordinal: ordinal),
    pageIndex: pageIndex,
    rect: rect ?? _rect(),
    proposedType: proposedType,
    confidence: confidence,
    labelText: labelText,
    evidence: _evidence(),
    resolution: resolution,
    duplicateOfConfirmed: duplicateOfConfirmed,
    unknownFields: unknownFields,
  );
}

ConfirmedField _field({
  required String id,
  required int order,
  int pageIndex = 0,
  Rect? rect,
  FieldType type = FieldType.text,
  Provenance provenance = Provenance.user,
  String? sourceSuggestionId,
  double? suggestionConfidence,
  String label = 'Feld',
  DateTime? createdAt,
  DateTime? updatedAt,
  FieldValidation validation = FieldValidation.ok,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return ConfirmedField(
    id: id,
    pageIndex: pageIndex,
    rect: rect ?? _rect(top: 60.0 + order * 30.0),
    type: type,
    provenance: provenance,
    sourceSuggestionId: sourceSuggestionId,
    suggestionConfidence: suggestionConfidence,
    label: label,
    order: order,
    createdAt: createdAt ?? _at(),
    updatedAt: updatedAt ?? _at(1),
    validation: validation,
    unknownFields: unknownFields,
  );
}

ConfirmedField _userField({
  required String id,
  required int order,
  String label = 'Bemerkung',
  FieldType type = FieldType.text,
  DateTime? createdAt,
  DateTime? updatedAt,
  FieldValidation validation = FieldValidation.ok,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return _field(
    id: id,
    order: order,
    type: type,
    label: label,
    createdAt: createdAt,
    updatedAt: updatedAt,
    validation: validation,
    unknownFields: unknownFields,
  );
}

ConfirmedField _machineField({
  required String id,
  required String sourceSuggestionId,
  required int order,
  int pageIndex = 0,
  Rect? rect,
  FieldType type = FieldType.text,
  double suggestionConfidence = 0.82,
  String label = 'Feld',
  DateTime? createdAt,
  DateTime? updatedAt,
  FieldValidation validation = FieldValidation.ok,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return _field(
    id: id,
    order: order,
    pageIndex: pageIndex,
    rect: rect,
    type: type,
    provenance: Provenance.machine,
    sourceSuggestionId: sourceSuggestionId,
    suggestionConfidence: suggestionConfidence,
    label: label,
    createdAt: createdAt,
    updatedAt: updatedAt,
    validation: validation,
    unknownFields: unknownFields,
  );
}

FieldVerification _verification({
  FieldVerificationState state = FieldVerificationState.unreviewed,
  DateTime? reviewedAt,
  List<WarningCode> warnings = const <WarningCode>[],
}) {
  return FieldVerification(
    state: state,
    reviewedAt: reviewedAt,
    warnings: warnings,
  );
}

SignatureMark _signatureMark({
  required String fieldId,
  String? assetId,
  int pageIndex = 0,
  Rect? rect,
  DateTime? capturedAt,
}) {
  return SignatureMark(
    assetId: assetId ?? _uuid(90),
    fieldId: fieldId,
    pageIndex: pageIndex,
    rect: rect ?? _rect(),
    widthPx: 320,
    heightPx: 100,
    capturedAt: capturedAt ?? _at(),
    sha256: _sha256,
  );
}

TextValue _text(
  String text, {
  DateTime? at,
  bool overflow = false,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return TextValue(
    text: text,
    lastEditedAt: at ?? _at(1),
    overflow: overflow,
    unknownFields: unknownFields,
  );
}

MultilineValue _multiline(
  String text, {
  DateTime? at,
  bool overflow = false,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return MultilineValue(
    text: text,
    lastEditedAt: at ?? _at(1),
    overflow: overflow,
    unknownFields: unknownFields,
  );
}

NumberValue _number(
  String canonical, {
  String? rawGerman,
  DateTime? at,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return NumberValue(
    canonical: canonical,
    rawGerman: rawGerman ?? canonical,
    lastEditedAt: at ?? _at(1),
    unknownFields: unknownFields,
  );
}

DateValue _date(
  String canonical, {
  DateTime? at,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return DateValue(
    canonical: canonical,
    lastEditedAt: at ?? _at(1),
    unknownFields: unknownFields,
  );
}

CheckboxValue _checkbox(bool checked) {
  return CheckboxValue(checked: checked, lastEditedAt: _at(1));
}

SignatureValue _signatureValue(String assetId) {
  return SignatureValue(signatureAssetId: assetId, lastEditedAt: _at(1));
}

RevisionContent _content({
  List<Page>? pages,
  List<FieldSuggestion> suggestions = const <FieldSuggestion>[],
  List<ConfirmedField> fields = const <ConfirmedField>[],
  List<String>? fieldOrder,
  Map<String, FieldValue> values = const <String, FieldValue>{},
  Map<String, SignatureMark> signatures = const <String, SignatureMark>{},
  Map<String, FieldVerification> verification =
      const <String, FieldVerification>{},
  TemplateOrigin? templateOrigin,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return RevisionContent(
    pages: pages ?? <Page>[_page()],
    suggestions: suggestions,
    fields: fields,
    fieldOrder:
        fieldOrder ??
        <String>[for (final ConfirmedField field in fields) field.id],
    values: values,
    signatures: signatures,
    verification: verification,
    templateOrigin: templateOrigin,
    unknownFields: unknownFields,
  );
}

RevisionContent _singleField(
  ConfirmedField field, {
  FieldValue? value,
  FieldVerification? verification,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return _content(
    fields: <ConfirmedField>[field],
    values: value == null
        ? const <String, FieldValue>{}
        : <String, FieldValue>{field.id: value},
    verification: verification == null
        ? const <String, FieldVerification>{}
        : <String, FieldVerification>{field.id: verification},
    unknownFields: unknownFields,
  );
}

String _bytes(RevisionContent content) {
  return canonicalJsonEncode(content.toJson());
}

RevisionContent _reload(RevisionContent content) {
  return RevisionContent.fromJson(
    jsonDecode(canonicalJsonEncode(content.toJson())) as Map<String, Object?>,
  );
}

void _expectValid(RevisionContent content) {
  final String bytes = _bytes(content);
  final RevisionContent reloaded = _reload(content);
  expect(reloaded, content);
  expect(_bytes(reloaded), bytes);
  expect(content.fieldOrder.length, content.fields.length);
  for (int index = 0; index < content.fields.length; index++) {
    expect(content.fields[index].order, index);
    expect(content.fieldOrder[index], content.fields[index].id);
  }
  for (final String fieldId in content.values.keys) {
    expect(
      content.fields.any((ConfirmedField field) => field.id == fieldId),
      isTrue,
    );
  }
  for (final String fieldId in content.signatures.keys) {
    expect(
      content.fields.any((ConfirmedField field) => field.id == fieldId),
      isTrue,
    );
  }
}

EditFieldException _errorOf(void Function() action) {
  try {
    action();
  } on EditFieldException catch (error) {
    return error;
  }
  fail('expected an EditFieldException');
}

void _expectCode(void Function() action, EditFieldErrorCode code) {
  expect(_errorOf(action).code, code);
}

void main() {
  group('addField', () {
    test('appends a user field with exact geometry, order, timestamps, and '
        'no suggestion linkage', () {
      final ConfirmedField existing = _userField(
        id: _uuid(1),
        order: 0,
        label: 'Bestehend',
      );
      final RevisionContent base = _content(
        fields: <ConfirmedField>[existing],
        values: <String, FieldValue>{existing.id: _text('Inhalt')},
        verification: <String, FieldVerification>{
          existing.id: _verification(
            state: FieldVerificationState.confirmed,
            reviewedAt: _at(),
          ),
        },
        templateOrigin: _origin(),
        unknownFields: <String, Object?>{'x_t066_doc': true},
      );
      final String newId = _uuid(40);
      final Rect rect = _rect(
        left: 10.125,
        top: 20.25,
        width: 30.5,
        height: 40.75,
      );
      final DateTime now = _at(5);

      final EditFieldChange change = addField(
        base,
        newId,
        0,
        rect,
        FieldType.text,
        '  Neue Bemerkung  ',
        now,
      );

      expect(change.kind, EditFieldChangeKind.added);
      expect(change.fieldId, newId);
      expect(change.previousField, isNull);
      expect(change.previousValue, isNull);
      expect(change.previousSignature, isNull);
      expect(change.previousVerification, isNull);
      expect(change.previousSuggestion, isNull);
      expect(change.content.fields, hasLength(2));
      expect(change.content.fieldOrder, <String>[existing.id, newId]);
      final ConfirmedField added = change.content.fields.last;
      expect(added.id, newId);
      expect(added.pageIndex, 0);
      expect(added.rect, rect);
      expect(added.type, FieldType.text);
      expect(added.provenance, Provenance.user);
      expect(added.sourceSuggestionId, isNull);
      expect(added.suggestionConfidence, isNull);
      expect(added.label, 'Neue Bemerkung');
      expect(added.order, 1);
      expect(added.createdAt, now);
      expect(added.updatedAt, now);
      expect(added.validation.isOk, isTrue);
      expect(change.content.fields.first, existing);
      expect(change.content.values[existing.id], base.values[existing.id]);
      expect(
        change.content.verification[existing.id],
        base.verification[existing.id],
      );
      expect(change.content.templateOrigin, base.templateOrigin);
      expect(change.content.unknownFields, base.unknownFields);
      _expectValid(change.content);
    });

    test(
      'accepts an exact edge-touching rect on another page without rounding',
      () {
        final RevisionContent base = _content(
          pages: <Page>[_page(0), _page(1)],
        );
        final Rect edge = _rect(left: 0, top: 0, width: 595, height: 842);

        final EditFieldChange change = addField(
          base,
          _uuid(41),
          1,
          edge,
          FieldType.multiline,
          'Randfeld',
          _at(6),
        );

        final ConfirmedField added = change.content.fields.single;
        expect(added.pageIndex, 1);
        expect(added.rect, edge);
        expect(added.rect.left, 0);
        expect(added.rect.top, 0);
        expect(added.rect.right, 595);
        expect(added.rect.bottom, 842);
        _expectValid(change.content);
      },
    );

    test('rejects invalid ids and treats an existing id as wrongState', () {
      final ConfirmedField existing = _userField(id: _uuid(2), order: 0);
      final RevisionContent base = _content(fields: <ConfirmedField>[existing]);

      for (final String id in <String>[
        'not-a-uuid',
        'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA',
        '00000000-0000-1000-8000-000000000003',
        '00000000-0000-4000-c000-000000000004',
      ]) {
        _expectCode(
          () => addField(base, id, 0, _rect(), FieldType.text, 'Feld', _at()),
          EditFieldErrorCode.invalidInput,
        );
      }
      final EditFieldException duplicate = _errorOf(
        () => addField(
          base,
          existing.id,
          0,
          _rect(),
          FieldType.text,
          'Feld',
          _at(),
        ),
      );
      expect(duplicate.code, EditFieldErrorCode.wrongState);
      expect(duplicate.message, isNotEmpty);
      expect(duplicate.message, isNot(contains(existing.id)));
      expect(duplicate.toString(), isNot(contains(existing.id)));
    });

    test('rejects empty, oversized, and control-character labels', () {
      final RevisionContent base = _content();
      for (final String label in <String>[
        '',
        '   ',
        List<String>.filled(121, 'a').join(),
        'Feld\u0000name',
      ]) {
        _expectCode(
          () => addField(
            base,
            _uuid(42),
            0,
            _rect(),
            FieldType.text,
            label,
            _at(),
          ),
          EditFieldErrorCode.invalidInput,
        );
      }
    });

    test('rejects a non-UTC timestamp', () {
      _expectCode(
        () => addField(
          _content(),
          _uuid(43),
          0,
          _rect(),
          FieldType.text,
          'Feld',
          DateTime(2026, 11, 20, 12),
        ),
        EditFieldErrorCode.invalidInput,
      );
    });

    test('rejects a missing page and every out-of-page rect', () {
      final RevisionContent base = _content();
      _expectCode(
        () => addField(
          base,
          _uuid(44),
          1,
          _rect(),
          FieldType.text,
          'Feld',
          _at(),
        ),
        EditFieldErrorCode.pageOutOfBounds,
      );
      for (final Rect rect in <Rect>[
        _rect(left: -0.001),
        _rect(top: -0.001),
        _rect(left: 500, width: 100),
        _rect(top: 830, height: 20),
      ]) {
        _expectCode(
          () =>
              addField(base, _uuid(45), 0, rect, FieldType.text, 'Feld', _at()),
          EditFieldErrorCode.pageOutOfBounds,
        );
      }
    });
  });

  group('removeField', () {
    test('removes a user field, its value and verification, and renumbers the '
        'remaining fields contiguously', () {
      final ConfirmedField first = _userField(id: _uuid(10), order: 0);
      final ConfirmedField second = _userField(id: _uuid(11), order: 1);
      final ConfirmedField third = _userField(id: _uuid(12), order: 2);
      final FieldVerification firstVerification = _verification(
        state: FieldVerificationState.corrected,
        reviewedAt: _at(2),
      );
      final FieldVerification thirdVerification = _verification();
      final RevisionContent base = _content(
        fields: <ConfirmedField>[first, second, third],
        values: <String, FieldValue>{
          first.id: _text('Erster'),
          third.id: _text('Dritter'),
        },
        verification: <String, FieldVerification>{
          first.id: firstVerification,
          third.id: thirdVerification,
        },
        templateOrigin: _origin(),
      );

      final EditFieldChange change = removeField(base, first.id);

      expect(change.kind, EditFieldChangeKind.removed);
      expect(change.fieldId, first.id);
      expect(change.previousField, first);
      expect(change.previousValue, base.values[first.id]);
      expect(change.previousVerification, firstVerification);
      expect(change.previousSignature, isNull);
      expect(change.previousSuggestion, isNull);
      expect(
        change.content.fields.map((ConfirmedField field) => field.id),
        <String>[second.id, third.id],
      );
      expect(
        change.content.fields.map((ConfirmedField field) => field.order),
        <int>[0, 1],
      );
      expect(change.content.fieldOrder, <String>[second.id, third.id]);
      expect(change.content.values.keys, <String>[third.id]);
      expect(change.content.verification.keys, <String>[third.id]);
      expect(change.content.values[third.id], base.values[third.id]);
      expect(change.content.verification[third.id], thirdVerification);
      expect(change.content.templateOrigin, base.templateOrigin);
      _expectValid(change.content);
    });

    test(
      'removes a signature field with its value, mark, and verification',
      () {
        final ConfirmedField signature = _field(
          id: _uuid(20),
          order: 0,
          type: FieldType.signature,
          label: 'Unterschrift',
        );
        final ConfirmedField other = _userField(id: _uuid(21), order: 1);
        final String assetId = _uuid(22);
        final SignatureMark mark = _signatureMark(
          fieldId: signature.id,
          assetId: assetId,
          rect: signature.rect,
        );
        final FieldVerification verification = _verification(
          state: FieldVerificationState.confirmed,
          reviewedAt: _at(3),
        );
        final RevisionContent base = _content(
          fields: <ConfirmedField>[signature, other],
          values: <String, FieldValue>{signature.id: _signatureValue(assetId)},
          signatures: <String, SignatureMark>{signature.id: mark},
          verification: <String, FieldVerification>{signature.id: verification},
        );

        final EditFieldChange change = removeField(base, signature.id);

        expect(change.previousSignature, mark);
        expect(change.previousValue, isA<SignatureValue>());
        expect(change.previousVerification, verification);
        expect(change.content.signatures, isEmpty);
        expect(change.content.values, isEmpty);
        expect(change.content.verification, isEmpty);
        expect(change.content.fields.single.id, other.id);
        expect(change.content.fields.single.order, 0);
        _expectValid(change.content);
      },
    );

    test('rejects a removed machine field suggestion and clears the now '
        'unsupported duplicate flag', () {
      final FieldSuggestion confirmed = _suggestion(
        ordinal: 1,
        resolution: SuggestionResolution.confirmed,
      );
      final ConfirmedField machine = _machineField(
        id: _uuid(30),
        sourceSuggestionId: confirmed.id,
        order: 0,
      );
      final FieldSuggestion duplicate = _suggestion(
        ordinal: 2,
        rect: machine.rect,
        proposedType: machine.type,
        duplicateOfConfirmed: true,
      );
      final FieldVerification verification = _verification(
        state: FieldVerificationState.corrected,
        reviewedAt: _at(4),
      );
      final RevisionContent base = _content(
        suggestions: <FieldSuggestion>[confirmed, duplicate],
        fields: <ConfirmedField>[machine],
        values: <String, FieldValue>{machine.id: _text('Maschineninhalt')},
        verification: <String, FieldVerification>{machine.id: verification},
      );

      final EditFieldChange change = removeField(base, machine.id);

      expect(change.previousSuggestion, confirmed);
      expect(change.previousField, machine);
      expect(change.previousValue, isA<TextValue>());
      expect(change.previousVerification, verification);
      expect(
        change.content.suggestions
            .singleWhere(
              (FieldSuggestion suggestion) => suggestion.id == confirmed.id,
            )
            .resolution,
        SuggestionResolution.rejected,
      );
      expect(
        change.content.suggestions
            .singleWhere(
              (FieldSuggestion suggestion) => suggestion.id == duplicate.id,
            )
            .duplicateOfConfirmed,
        isFalse,
      );
      expect(change.content.fields, isEmpty);
      _expectValid(change.content);

      final List<FieldSuggestion> restoredSuggestions =
          change.previousSuggestions!;
      expect(change.previousSuggestions, base.suggestions);
      final RevisionContent restored = RevisionContent(
        pages: change.content.pages,
        suggestions: restoredSuggestions,
        fields: <ConfirmedField>[change.previousField!],
        fieldOrder: <String>[change.fieldId],
        values: <String, FieldValue>{change.fieldId: change.previousValue!},
        signatures: change.previousSignature == null
            ? const <String, SignatureMark>{}
            : <String, SignatureMark>{
                change.fieldId: change.previousSignature!,
              },
        verification: change.previousVerification == null
            ? const <String, FieldVerification>{}
            : <String, FieldVerification>{
                change.fieldId: change.previousVerification!,
              },
        templateOrigin: change.content.templateOrigin,
        unknownFields: change.content.unknownFields,
      );
      expect(restored, base);
    });

    test('removing the last field empties fields and keyed data', () {
      final ConfirmedField field = _userField(id: _uuid(31), order: 0);
      final RevisionContent base = _content(
        fields: <ConfirmedField>[field],
        values: <String, FieldValue>{field.id: _text('Letzter')},
        verification: <String, FieldVerification>{field.id: _verification()},
      );

      final EditFieldChange change = removeField(base, field.id);

      expect(change.content.fields, isEmpty);
      expect(change.content.fieldOrder, isEmpty);
      expect(change.content.values, isEmpty);
      expect(change.content.verification, isEmpty);
      _expectValid(change.content);
    });

    test('a missing field fails closed without changing the input', () {
      final RevisionContent base = _content(
        fields: <ConfirmedField>[_userField(id: _uuid(32), order: 0)],
      );
      final String before = _bytes(base);

      _expectCode(
        () => removeField(base, _uuid(33)),
        EditFieldErrorCode.fieldNotFound,
      );
      expect(_bytes(base), before);
    });
  });

  group('moveField and resizeField', () {
    test('move stores the exact rect, updates updatedAt, and preserves all '
        'other field content', () {
      final ConfirmedField field = _field(
        id: _uuid(50),
        order: 0,
        type: FieldType.number,
        label: 'Betrag',
        validation: FieldValidation.warning(WarningCode.overflow, 'FLD-001'),
        unknownFields: <String, Object?>{'x_t066_field': 7},
      );
      final NumberValue value = _number(
        '1234.56',
        rawGerman: '1.234,56',
        unknownFields: <String, Object?>{'x_t066_value': true},
      );
      final FieldVerification verification = _verification(
        state: FieldVerificationState.confirmed,
        reviewedAt: _at(5),
      );
      final RevisionContent base = _content(
        fields: <ConfirmedField>[field],
        values: <String, FieldValue>{field.id: value},
        verification: <String, FieldVerification>{field.id: verification},
      );
      final Rect moved = _rect(
        left: 12.345,
        top: 67.89,
        width: 20.5,
        height: 10.25,
      );
      final DateTime now = _at(7);

      final EditFieldChange change = moveField(base, field.id, moved, now);

      expect(change.kind, EditFieldChangeKind.moved);
      expect(change.previousField, field);
      expect(change.previousValue, value);
      expect(change.previousVerification, verification);
      final ConfirmedField updated = change.content.fields.single;
      expect(updated.rect, moved);
      expect(updated.rect.left, 12.345);
      expect(updated.rect.top, 67.89);
      expect(updated.rect.width, 20.5);
      expect(updated.rect.height, 10.25);
      expect(updated.updatedAt, now);
      expect(updated.createdAt, field.createdAt);
      expect(updated.type, FieldType.number);
      expect(updated.label, 'Betrag');
      expect(updated.provenance, Provenance.user);
      expect(updated.order, 0);
      expect(updated.validation, field.validation);
      expect(updated.unknownFields, field.unknownFields);
      expect(change.content.values[field.id], value);
      expect(change.content.verification[field.id], verification);
      expect(change.content.fieldOrder, <String>[field.id]);
      _expectValid(change.content);
    });

    test('resize has the same preservation rules and the resized kind', () {
      final ConfirmedField field = _userField(id: _uuid(51), order: 0);
      final RevisionContent base = _content(
        fields: <ConfirmedField>[field],
        values: <String, FieldValue>{field.id: _text('Text')},
      );
      final Rect resized = _rect(
        left: field.rect.left,
        top: field.rect.top,
        width: 333.125,
        height: 44.875,
      );

      final EditFieldChange change = resizeField(
        base,
        field.id,
        resized,
        _at(8),
      );

      expect(change.kind, EditFieldChangeKind.resized);
      expect(change.content.fields.single.rect, resized);
      expect(change.content.fields.single.updatedAt, _at(8));
      expect(change.content.fields.single.type, field.type);
      expect(change.content.fields.single.label, field.label);
      expect(change.content.values[field.id], base.values[field.id]);
      _expectValid(change.content);
    });

    test('out-of-page rects and a missing field fail closed', () {
      final ConfirmedField field = _userField(id: _uuid(52), order: 0);
      final RevisionContent base = _content(fields: <ConfirmedField>[field]);
      for (final Rect rect in <Rect>[
        _rect(left: -1),
        _rect(top: -1),
        _rect(left: 580, width: 20),
        _rect(top: 830, height: 20),
      ]) {
        _expectCode(
          () => moveField(base, field.id, rect, _at()),
          EditFieldErrorCode.pageOutOfBounds,
        );
        _expectCode(
          () => resizeField(base, field.id, rect, _at()),
          EditFieldErrorCode.pageOutOfBounds,
        );
      }
      _expectCode(
        () => moveField(base, _uuid(53), _rect(), _at()),
        EditFieldErrorCode.fieldNotFound,
      );
      _expectCode(
        () => resizeField(base, _uuid(53), _rect(), _at()),
        EditFieldErrorCode.fieldNotFound,
      );
    });

    test('a non-UTC timestamp is invalidInput for both commands', () {
      final ConfirmedField field = _userField(id: _uuid(54), order: 0);
      final RevisionContent base = _content(fields: <ConfirmedField>[field]);
      final DateTime local = DateTime(2026, 11, 20, 12);
      _expectCode(
        () => moveField(base, field.id, _rect(), local),
        EditFieldErrorCode.invalidInput,
      );
      _expectCode(
        () => resizeField(base, field.id, _rect(), local),
        EditFieldErrorCode.invalidInput,
      );
    });

    test('moving a machine field recomputes a stale duplicate flag', () {
      final FieldSuggestion confirmed = _suggestion(
        ordinal: 1,
        resolution: SuggestionResolution.confirmed,
      );
      final ConfirmedField machine = _machineField(
        id: _uuid(55),
        sourceSuggestionId: confirmed.id,
        order: 0,
      );
      final FieldSuggestion duplicate = _suggestion(
        ordinal: 2,
        rect: machine.rect,
        proposedType: machine.type,
        duplicateOfConfirmed: true,
      );
      final RevisionContent base = _content(
        suggestions: <FieldSuggestion>[confirmed, duplicate],
        fields: <ConfirmedField>[machine],
      );

      final EditFieldChange change = moveField(
        base,
        machine.id,
        _rect(left: 300, top: 500),
        _at(9),
      );

      expect(
        change.content.suggestions
            .singleWhere(
              (FieldSuggestion suggestion) => suggestion.id == duplicate.id,
            )
            .duplicateOfConfirmed,
        isFalse,
      );
      _expectValid(change.content);
    });
  });

  group('reclassifyField', () {
    test('text to multiline preserves text, metadata, and unknown fields', () {
      final ConfirmedField field = _field(
        id: _uuid(60),
        order: 0,
        label: 'Notiz',
        validation: FieldValidation.warning(WarningCode.overflow, 'FLD-001'),
        unknownFields: <String, Object?>{
          'x_t066_field': <String, Object?>{'a': 1},
        },
      );
      final TextValue value = _text(
        'Zeile',
        overflow: true,
        unknownFields: <String, Object?>{'x_t066_value': 'keep'},
      );
      final RevisionContent base = _singleField(field, value: value);

      final EditFieldChange change = reclassifyField(
        base,
        field.id,
        FieldType.multiline,
        _at(10),
      );

      expect(change.kind, EditFieldChangeKind.reclassified);
      expect(change.previousField, field);
      expect(change.previousValue, value);
      final ConfirmedField updated = change.content.fields.single;
      expect(updated.type, FieldType.multiline);
      expect(updated.createdAt, field.createdAt);
      expect(updated.updatedAt, _at(10));
      expect(updated.order, 0);
      expect(updated.label, 'Notiz');
      expect(updated.provenance, Provenance.user);
      expect(updated.unknownFields, field.unknownFields);
      expect(updated.validation, field.validation);
      final MultilineValue updatedValue =
          change.content.values[field.id]! as MultilineValue;
      expect(updatedValue.text, 'Zeile');
      expect(updatedValue.lastEditedAt, _at(10));
      expect(updatedValue.overflow, isTrue);
      expect(updatedValue.unknownFields, value.unknownFields);
      _expectValid(change.content);
    });

    test('multiline to text without line breaks stores plain text', () {
      final ConfirmedField field = _field(
        id: _uuid(61),
        order: 0,
        type: FieldType.multiline,
      );
      final RevisionContent base = _singleField(
        field,
        value: _multiline('Einzeilig'),
      );

      final EditFieldChange change = reclassifyField(
        base,
        field.id,
        FieldType.text,
        _at(11),
      );

      final TextValue value = change.content.values[field.id]! as TextValue;
      expect(value.text, 'Einzeilig');
      expect(change.content.fields.single.type, FieldType.text);
      expect(change.content.fields.single.validation.isOk, isTrue);
      _expectValid(change.content);
    });

    test('multiline to text joins line breaks only with the explicit flag', () {
      final ConfirmedField field = _field(
        id: _uuid(62),
        order: 0,
        type: FieldType.multiline,
      );
      final RevisionContent base = _singleField(
        field,
        value: _multiline('Zeile 1\nZeile 2'),
      );

      final EditFieldChange joined = reclassifyField(
        base,
        field.id,
        FieldType.text,
        _at(12),
        joinMultilineToText: true,
      );

      final TextValue joinedValue =
          joined.content.values[field.id]! as TextValue;
      expect(joinedValue.text, 'Zeile 1 Zeile 2');
      expect(joined.content.fields.single.validation.isOk, isTrue);
      _expectValid(joined.content);
    });

    test('multiline to text without the flag preserves the line breaks as '
        'flagged incompatible content', () {
      final ConfirmedField field = _field(
        id: _uuid(63),
        order: 0,
        type: FieldType.multiline,
      );
      final RevisionContent base = _singleField(
        field,
        value: _multiline('Zeile 1\nZeile 2'),
      );

      final EditFieldChange change = reclassifyField(
        base,
        field.id,
        FieldType.text,
        _at(13),
      );

      final IncompatibleValue value =
          change.content.values[field.id]! as IncompatibleValue;
      expect(value.preservedText, 'Zeile 1\nZeile 2');
      expect(value.reasonCode, 'line_break_join_confirmation');
      final FieldValidation validation =
          change.content.fields.single.validation;
      expect(validation.isWarning, isTrue);
      expect(validation.warningCode, WarningCode.incompatibleContent);
      expect(validation.messageKey, 'FLD-002');
      _expectValid(change.content);
    });

    test('text to number parses the German decimal and keeps rawGerman', () {
      final ConfirmedField field = _field(id: _uuid(64), order: 0);
      final RevisionContent base = _singleField(
        field,
        value: _text('1.234,56'),
      );

      final EditFieldChange change = reclassifyField(
        base,
        field.id,
        FieldType.number,
        _at(14),
      );

      final NumberValue value = change.content.values[field.id]! as NumberValue;
      expect(value.canonical, '1234.56');
      expect(value.rawGerman, '1.234,56');
      expect(value.lastEditedAt, _at(14));
      expect(change.content.fields.single.type, FieldType.number);
      expect(change.content.fields.single.validation.isOk, isTrue);
      _expectValid(change.content);
    });

    test('text to number failure preserves the exact text with NUM-001', () {
      final ConfirmedField field = _field(id: _uuid(65), order: 0);
      final RevisionContent base = _singleField(
        field,
        value: _text('keine Zahl'),
      );

      final EditFieldChange change = reclassifyField(
        base,
        field.id,
        FieldType.number,
        _at(15),
      );

      final IncompatibleValue value =
          change.content.values[field.id]! as IncompatibleValue;
      expect(value.preservedText, 'keine Zahl');
      expect(value.reasonCode, 'number_parse_failed');
      final FieldValidation validation =
          change.content.fields.single.validation;
      expect(validation.isError, isTrue);
      expect(validation.errorCode, 'NUM-001');
      _expectValid(change.content);
    });

    test('text to date parses German and stores the canonical date', () {
      final ConfirmedField field = _field(id: _uuid(66), order: 0);
      final RevisionContent base = _singleField(
        field,
        value: _text('31.12.2025'),
      );

      final EditFieldChange change = reclassifyField(
        base,
        field.id,
        FieldType.date,
        _at(16),
      );

      final DateValue value = change.content.values[field.id]! as DateValue;
      expect(value.canonical, '2025-12-31');
      expect(change.content.fields.single.type, FieldType.date);
      expect(change.content.fields.single.validation.isOk, isTrue);
      _expectValid(change.content);
    });

    test('text to date distinguishes malformed DATE-001 and impossible '
        'DATE-002 while preserving the text', () {
      final ConfirmedField malformedField = _field(id: _uuid(67), order: 0);
      final EditFieldChange malformed = reclassifyField(
        _singleField(malformedField, value: _text('31/12/2025')),
        malformedField.id,
        FieldType.date,
        _at(17),
      );
      final IncompatibleValue malformedValue =
          malformed.content.values[malformedField.id]! as IncompatibleValue;
      expect(malformedValue.preservedText, '31/12/2025');
      expect(malformedValue.reasonCode, 'date_parse_failed');
      expect(malformed.content.fields.single.validation.errorCode, 'DATE-001');
      _expectValid(malformed.content);

      final ConfirmedField impossibleField = _field(id: _uuid(68), order: 0);
      final EditFieldChange impossible = reclassifyField(
        _singleField(impossibleField, value: _text('31.02.2025')),
        impossibleField.id,
        FieldType.date,
        _at(17),
      );
      final IncompatibleValue impossibleValue =
          impossible.content.values[impossibleField.id]! as IncompatibleValue;
      expect(impossibleValue.preservedText, '31.02.2025');
      expect(impossibleValue.reasonCode, 'date_parse_failed');
      expect(impossible.content.fields.single.validation.errorCode, 'DATE-002');
      _expectValid(impossible.content);
    });

    test('number to text stores the canonical textual form and clears the '
        'incompatibility error', () {
      final ConfirmedField field = _field(
        id: _uuid(69),
        order: 0,
        type: FieldType.number,
        validation: FieldValidation.error('NUM-001'),
      );
      final RevisionContent base = _singleField(
        field,
        value: _number('1234.56', rawGerman: '1.234,56'),
      );

      final EditFieldChange change = reclassifyField(
        base,
        field.id,
        FieldType.text,
        _at(18),
      );

      final TextValue value = change.content.values[field.id]! as TextValue;
      expect(value.text, '1234.56');
      expect(change.content.fields.single.type, FieldType.text);
      expect(change.content.fields.single.validation.isOk, isTrue);
      _expectValid(change.content);
    });

    test(
      'date to text stores the canonical textual form and clears the error',
      () {
        final ConfirmedField field = _field(
          id: _uuid(70),
          order: 0,
          type: FieldType.date,
          validation: FieldValidation.error('DATE-001'),
        );
        final RevisionContent base = _singleField(
          field,
          value: _date('2025-12-31'),
        );

        final EditFieldChange change = reclassifyField(
          base,
          field.id,
          FieldType.text,
          _at(19),
        );

        final TextValue value = change.content.values[field.id]! as TextValue;
        expect(value.text, '2025-12-31');
        expect(change.content.fields.single.validation.isOk, isTrue);
        _expectValid(change.content);
      },
    );

    test('text, number, date, and multiline to checkbox preserve prior textual '
        'content with the incompatible warning', () {
      final List<({ConfirmedField field, FieldValue value, String preserved})>
      fixtures = <({ConfirmedField field, FieldValue value, String preserved})>[
        (
          field: _field(id: _uuid(71), order: 0),
          value: _text('Ja'),
          preserved: 'Ja',
        ),
        (
          field: _field(id: _uuid(72), order: 0, type: FieldType.number),
          value: _number('1234.56', rawGerman: '1.234,56'),
          preserved: '1.234,56',
        ),
        (
          field: _field(id: _uuid(73), order: 0, type: FieldType.date),
          value: _date('2025-12-31'),
          preserved: '2025-12-31',
        ),
        (
          field: _field(id: _uuid(74), order: 0, type: FieldType.multiline),
          value: _multiline('Zeile 1\nZeile 2'),
          preserved: 'Zeile 1\nZeile 2',
        ),
      ];

      for (final ({ConfirmedField field, FieldValue value, String preserved})
          fixture
          in fixtures) {
        final EditFieldChange change = reclassifyField(
          _singleField(fixture.field, value: fixture.value),
          fixture.field.id,
          FieldType.checkbox,
          _at(20),
        );
        final IncompatibleValue value =
            change.content.values[fixture.field.id]! as IncompatibleValue;
        expect(value.preservedText, fixture.preserved);
        expect(value.reasonCode, 'checkbox_requires_resolution');
        expect(change.content.fields.single.type, FieldType.checkbox);
        final FieldValidation validation =
            change.content.fields.single.validation;
        expect(validation.warningCode, WarningCode.incompatibleContent);
        expect(
          change.content.values[fixture.field.id],
          isNot(isA<CheckboxValue>()),
        );
        _expectValid(change.content);
      }
    });

    test('text to signature preserves content with the warning and creates no '
        'signature mark', () {
      final ConfirmedField field = _field(id: _uuid(75), order: 0);
      final RevisionContent base = _singleField(
        field,
        value: _text('Unterschrift'),
      );

      final EditFieldChange change = reclassifyField(
        base,
        field.id,
        FieldType.signature,
        _at(21),
      );

      final IncompatibleValue value =
          change.content.values[field.id]! as IncompatibleValue;
      expect(value.preservedText, 'Unterschrift');
      expect(value.reasonCode, 'signature_requires_resolution');
      expect(change.content.fields.single.type, FieldType.signature);
      expect(
        change.content.fields.single.validation.warningCode,
        WarningCode.incompatibleContent,
      );
      expect(change.content.signatures, isEmpty);
      _expectValid(change.content);
    });

    test(
      'checkbox to text preserves checked/unchecked as the Ja/Nein projection',
      () {
        for (final bool checked in <bool>[true, false]) {
          final ConfirmedField field = _field(
            id: _uuid(76),
            order: 0,
            type: FieldType.checkbox,
          );
          final RevisionContent base = _singleField(
            field,
            value: _checkbox(checked),
          );

          final EditFieldChange change = reclassifyField(
            base,
            field.id,
            FieldType.text,
            _at(22),
          );

          final IncompatibleValue value =
              change.content.values[field.id]! as IncompatibleValue;
          expect(value.preservedText, checked ? 'Ja' : 'Nein');
          expect(value.reasonCode, 'checkbox_state_projection');
          expect(change.content.fields.single.type, FieldType.text);
          expect(
            change.content.fields.single.validation.warningCode,
            WarningCode.incompatibleContent,
          );
          expect(change.content.values[field.id], isNot(isA<TextValue>()));
          _expectValid(change.content);
        }
      },
    );

    test('checkbox to number/date preserves Ja/Nein without numeric or date '
        'inference', () {
      for (final FieldType target in <FieldType>[
        FieldType.number,
        FieldType.date,
      ]) {
        for (final bool checked in <bool>[true, false]) {
          final ConfirmedField field = _field(
            id: _uuid(77),
            order: 0,
            type: FieldType.checkbox,
          );
          final EditFieldChange change = reclassifyField(
            _singleField(field, value: _checkbox(checked)),
            field.id,
            target,
            _at(23),
          );
          final IncompatibleValue value =
              change.content.values[field.id]! as IncompatibleValue;
          expect(value.preservedText, checked ? 'Ja' : 'Nein');
          expect(value.reasonCode, 'checkbox_state_projection');
          expect(change.content.fields.single.type, target);
          expect(
            change.content.fields.single.validation.warningCode,
            WarningCode.incompatibleContent,
          );
          expect(change.content.values[field.id], isNot(isA<NumberValue>()));
          expect(change.content.values[field.id], isNot(isA<DateValue>()));
          _expectValid(change.content);
        }
      }
    });

    test('checkbox to multiline follows the same Ja/Nein projection', () {
      for (final bool checked in <bool>[true, false]) {
        final ConfirmedField field = _field(
          id: _uuid(80),
          order: 0,
          type: FieldType.checkbox,
        );
        final RevisionContent base = _singleField(
          field,
          value: _checkbox(checked),
        );

        final EditFieldChange change = reclassifyField(
          base,
          field.id,
          FieldType.multiline,
          _at(23),
        );

        final IncompatibleValue value =
            change.content.values[field.id]! as IncompatibleValue;
        expect(value.preservedText, checked ? 'Ja' : 'Nein');
        expect(value.reasonCode, 'checkbox_state_projection');
        expect(change.content.fields.single.type, FieldType.multiline);
        expect(
          change.content.fields.single.validation.warningCode,
          WarningCode.incompatibleContent,
        );
        _expectValid(change.content);
      }
    });

    test('signature to text clears the value exactly like core and removes the '
        'signature mark', () {
      final ConfirmedField field = _field(
        id: _uuid(78),
        order: 0,
        type: FieldType.signature,
      );
      final String assetId = _uuid(79);
      final SignatureMark mark = _signatureMark(
        fieldId: field.id,
        assetId: assetId,
        rect: field.rect,
      );
      final FieldVerification verification = _verification(
        state: FieldVerificationState.confirmed,
        reviewedAt: _at(6),
      );
      final RevisionContent base = _content(
        fields: <ConfirmedField>[field],
        values: <String, FieldValue>{field.id: _signatureValue(assetId)},
        signatures: <String, SignatureMark>{field.id: mark},
        verification: <String, FieldVerification>{field.id: verification},
      );

      final EditFieldChange change = reclassifyField(
        base,
        field.id,
        FieldType.text,
        _at(24),
      );

      expect(change.content.values.containsKey(field.id), isFalse);
      expect(change.content.values, isEmpty);
      expect(change.content.signatures, isEmpty);
      expect(change.content.verification[field.id], verification);
      expect(change.previousSignature, mark);
      expect(change.previousValue, isA<SignatureValue>());
      expect(change.content.fields.single.type, FieldType.text);
      _expectValid(change.content);
    });

    test(
      'signature to number/date clears the value and mark exactly like core',
      () {
        for (final FieldType target in <FieldType>[
          FieldType.number,
          FieldType.date,
        ]) {
          final ConfirmedField field = _field(
            id: _uuid(82),
            order: 0,
            type: FieldType.signature,
          );
          final String assetId = _uuid(83);
          final SignatureMark mark = _signatureMark(
            fieldId: field.id,
            assetId: assetId,
            rect: field.rect,
          );
          final FieldVerification verification = _verification(
            state: FieldVerificationState.corrected,
            reviewedAt: _at(6),
          );
          final RevisionContent base = _content(
            fields: <ConfirmedField>[field],
            values: <String, FieldValue>{field.id: _signatureValue(assetId)},
            signatures: <String, SignatureMark>{field.id: mark},
            verification: <String, FieldVerification>{field.id: verification},
          );

          final EditFieldChange change = reclassifyField(
            base,
            field.id,
            target,
            _at(25),
          );

          expect(change.content.values.containsKey(field.id), isFalse);
          expect(change.content.signatures, isEmpty);
          expect(change.content.verification[field.id], verification);
          expect(change.content.fields.single.type, target);
          expect(change.content.fields.single.validation.warningCode, isNull);
          _expectValid(change.content);
        }
      },
    );

    test('number, date, and multiline to signature preserve prior content with '
        'the warning and create no signature mark', () {
      final List<({ConfirmedField field, FieldValue value, String preserved})>
      fixtures = <({ConfirmedField field, FieldValue value, String preserved})>[
        (
          field: _field(id: _uuid(89), order: 0, type: FieldType.number),
          value: _number('1234.56', rawGerman: '1.234,56'),
          preserved: '1.234,56',
        ),
        (
          field: _field(id: _uuid(91), order: 0, type: FieldType.date),
          value: _date('2025-12-31'),
          preserved: '2025-12-31',
        ),
        (
          field: _field(id: _uuid(92), order: 0, type: FieldType.multiline),
          value: _multiline('Zeile 1\nT066-GEHEIM-SIGNATUR'),
          preserved: 'Zeile 1\nT066-GEHEIM-SIGNATUR',
        ),
      ];

      for (final ({ConfirmedField field, FieldValue value, String preserved})
          fixture
          in fixtures) {
        final FieldVerification verification = _verification(
          state: FieldVerificationState.confirmed,
          reviewedAt: _at(6),
        );
        final RevisionContent base = _content(
          fields: <ConfirmedField>[fixture.field],
          values: <String, FieldValue>{fixture.field.id: fixture.value},
          verification: <String, FieldVerification>{
            fixture.field.id: verification,
          },
        );

        final EditFieldChange change = reclassifyField(
          base,
          fixture.field.id,
          FieldType.signature,
          _at(26),
        );

        final IncompatibleValue value =
            change.content.values[fixture.field.id]! as IncompatibleValue;
        expect(value.preservedText, fixture.preserved);
        expect(value.reasonCode, 'signature_requires_resolution');
        expect(change.content.fields.single.type, FieldType.signature);
        expect(
          change.content.fields.single.validation.warningCode,
          WarningCode.incompatibleContent,
        );
        expect(change.content.signatures, isEmpty);
        expect(change.content.verification[fixture.field.id], verification);
        expect(change.previousSignature, isNull);
        expect(change.toString(), isNot(contains('T066-GEHEIM')));
        expect(value.toString(), isNot(contains('T066-GEHEIM')));
        _expectValid(change.content);
      }
    });

    test('same-type reclassification fails with noChange and leaves the input '
        'unchanged', () {
      final ConfirmedField field = _field(id: _uuid(84), order: 0);
      final RevisionContent base = _singleField(
        field,
        value: _text('Unverändert'),
      );
      final String before = _bytes(base);

      _expectCode(
        () => reclassifyField(base, field.id, FieldType.text, _at(26)),
        EditFieldErrorCode.noChange,
      );
      expect(_bytes(base), before);
    });

    test('a misplaced join flag, missing field, and non-UTC timestamp fail '
        'closed', () {
      final ConfirmedField field = _field(id: _uuid(85), order: 0);
      final RevisionContent base = _singleField(field, value: _text('1'));

      _expectCode(
        () => reclassifyField(
          base,
          field.id,
          FieldType.number,
          _at(),
          joinMultilineToText: true,
        ),
        EditFieldErrorCode.invalidInput,
      );
      _expectCode(
        () => reclassifyField(base, _uuid(86), FieldType.number, _at()),
        EditFieldErrorCode.fieldNotFound,
      );
      _expectCode(
        () => reclassifyField(
          base,
          field.id,
          FieldType.number,
          DateTime(2026, 11, 20, 12),
        ),
        EditFieldErrorCode.invalidInput,
      );
    });

    test('a machine field keeps its suggestion linkage, and a type change '
        'clears a stale duplicate flag', () {
      final FieldSuggestion confirmed = _suggestion(
        ordinal: 1,
        resolution: SuggestionResolution.confirmed,
      );
      final ConfirmedField machine = _machineField(
        id: _uuid(87),
        sourceSuggestionId: confirmed.id,
        order: 0,
      );
      final FieldSuggestion duplicate = _suggestion(
        ordinal: 2,
        rect: machine.rect,
        proposedType: machine.type,
        duplicateOfConfirmed: true,
      );
      final RevisionContent base = _content(
        suggestions: <FieldSuggestion>[confirmed, duplicate],
        fields: <ConfirmedField>[machine],
      );

      final EditFieldChange change = reclassifyField(
        base,
        machine.id,
        FieldType.number,
        _at(27),
      );

      final ConfirmedField updated = change.content.fields.single;
      expect(change.previousSuggestions, base.suggestions);
      expect(updated.type, FieldType.number);
      expect(updated.provenance, Provenance.machine);
      expect(updated.sourceSuggestionId, confirmed.id);
      expect(updated.suggestionConfidence, confirmed.confidence);
      expect(
        change.content.suggestions
            .singleWhere(
              (FieldSuggestion suggestion) => suggestion.id == confirmed.id,
            )
            .resolution,
        SuggestionResolution.confirmed,
      );
      expect(
        change.content.suggestions
            .singleWhere(
              (FieldSuggestion suggestion) => suggestion.id == duplicate.id,
            )
            .duplicateOfConfirmed,
        isFalse,
      );
      _expectValid(change.content);
    });

    test('reclassifying preserved content back to text clears the error and '
        'keeps the original text', () {
      final ConfirmedField field = _field(id: _uuid(88), order: 0);
      final EditFieldChange failed = reclassifyField(
        _singleField(field, value: _text('keine Zahl')),
        field.id,
        FieldType.number,
        _at(28),
      );

      final EditFieldChange restored = reclassifyField(
        failed.content,
        field.id,
        FieldType.text,
        _at(29),
      );

      final TextValue value = restored.content.values[field.id]! as TextValue;
      expect(value.text, 'keine Zahl');
      expect(restored.content.fields.single.type, FieldType.text);
      expect(restored.content.fields.single.validation.isOk, isTrue);
      _expectValid(restored.content);
    });
  });

  group('cross-cutting guarantees', () {
    test('every command leaves its input unchanged', () {
      final ConfirmedField field = _field(
        id: _uuid(100),
        order: 0,
        type: FieldType.text,
      );
      final RevisionContent base = _content(
        fields: <ConfirmedField>[field],
        values: <String, FieldValue>{field.id: _text('Text')},
        verification: <String, FieldVerification>{field.id: _verification()},
        templateOrigin: _origin(),
        unknownFields: <String, Object?>{'x_t066_doc': true},
      );
      final String before = _bytes(base);

      addField(base, _uuid(101), 0, _rect(), FieldType.text, 'Neu', _at());
      removeField(base, field.id);
      moveField(base, field.id, _rect(left: 70), _at());
      resizeField(base, field.id, _rect(width: 80), _at());
      reclassifyField(base, field.id, FieldType.multiline, _at());

      expect(_bytes(base), before);
    });

    test('commands are deterministic for identical inputs', () {
      final ConfirmedField field = _field(
        id: _uuid(102),
        order: 0,
        type: FieldType.multiline,
      );
      final RevisionContent base = _content(
        fields: <ConfirmedField>[field],
        values: <String, FieldValue>{field.id: _multiline('A\nB')},
      );

      final EditFieldChange first = reclassifyField(
        base,
        field.id,
        FieldType.text,
        _at(30),
        joinMultilineToText: true,
      );
      final EditFieldChange second = reclassifyField(
        base,
        field.id,
        FieldType.text,
        _at(30),
        joinMultilineToText: true,
      );

      expect(second, first);
      expect(_bytes(second.content), _bytes(first.content));
    });

    test(
      'move and reclassify receipts restore the previous revision exactly',
      () {
        final ConfirmedField field = _userField(
          id: _uuid(108),
          order: 0,
          label: 'Rückgabe',
        );
        final FieldVerification verification = _verification(
          state: FieldVerificationState.confirmed,
          reviewedAt: _at(7),
        );
        final RevisionContent base = _content(
          fields: <ConfirmedField>[field],
          values: <String, FieldValue>{field.id: _text('Text')},
          verification: <String, FieldVerification>{field.id: verification},
          templateOrigin: _origin(),
        );

        final EditFieldChange moved = moveField(
          base,
          field.id,
          _rect(left: 90),
          _at(35),
        );
        final RevisionContent restoredFromMove = RevisionContent(
          pages: moved.content.pages,
          suggestions: moved.content.suggestions,
          fields: <ConfirmedField>[moved.previousField!],
          fieldOrder: <String>[moved.fieldId],
          values: <String, FieldValue>{moved.fieldId: moved.previousValue!},
          signatures: moved.previousSignature == null
              ? const <String, SignatureMark>{}
              : <String, SignatureMark>{
                  moved.fieldId: moved.previousSignature!,
                },
          verification: moved.previousVerification == null
              ? const <String, FieldVerification>{}
              : <String, FieldVerification>{
                  moved.fieldId: moved.previousVerification!,
                },
          templateOrigin: moved.content.templateOrigin,
          unknownFields: moved.content.unknownFields,
        );
        expect(restoredFromMove, base);

        final EditFieldChange reclassified = reclassifyField(
          base,
          field.id,
          FieldType.multiline,
          _at(36),
        );
        final RevisionContent restoredFromReclassify = RevisionContent(
          pages: reclassified.content.pages,
          suggestions: reclassified.content.suggestions,
          fields: <ConfirmedField>[reclassified.previousField!],
          fieldOrder: <String>[reclassified.fieldId],
          values: <String, FieldValue>{
            reclassified.fieldId: reclassified.previousValue!,
          },
          signatures: reclassified.previousSignature == null
              ? const <String, SignatureMark>{}
              : <String, SignatureMark>{
                  reclassified.fieldId: reclassified.previousSignature!,
                },
          verification: reclassified.previousVerification == null
              ? const <String, FieldVerification>{}
              : <String, FieldVerification>{
                  reclassified.fieldId: reclassified.previousVerification!,
                },
          templateOrigin: reclassified.content.templateOrigin,
          unknownFields: reclassified.content.unknownFields,
        );
        expect(restoredFromReclassify, base);
      },
    );

    test('every representative success is accepted by the core aggregate and '
        'round-trips canonically', () {
      final ConfirmedField field = _field(id: _uuid(103), order: 0);
      final RevisionContent base = _content(
        fields: <ConfirmedField>[field],
        values: <String, FieldValue>{field.id: _text('12,5')},
      );

      final EditFieldChange added = addField(
        base,
        _uuid(104),
        0,
        _rect(),
        FieldType.text,
        'Neu',
        _at(31),
      );
      _expectValid(added.content);

      final EditFieldChange moved = moveField(
        added.content,
        field.id,
        _rect(left: 80),
        _at(32),
      );
      _expectValid(moved.content);

      final EditFieldChange resized = resizeField(
        moved.content,
        field.id,
        _rect(left: 80, width: 100),
        _at(33),
      );
      _expectValid(resized.content);

      final EditFieldChange reclassified = reclassifyField(
        resized.content,
        field.id,
        FieldType.number,
        _at(34),
      );
      _expectValid(reclassified.content);

      final EditFieldChange removed = removeField(
        reclassified.content,
        _uuid(104),
      );
      _expectValid(removed.content);
    });

    test('add, move, and resize share the geometry boundary that rejects NaN, '
        'infinity, zero, and negative components with stable content-free '
        'codes', () {
      final Rect pageBox = _geometry().displayBox;

      for (final double bad in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        for (final ({double left, double top, double width, double height})
            fixture
            in <({double left, double top, double width, double height})>[
              (left: bad, top: 0, width: 10, height: 10),
              (left: 0, top: bad, width: 10, height: 10),
              (left: 0, top: 0, width: bad, height: 10),
              (left: 0, top: 0, width: 10, height: bad),
            ]) {
          final EditFieldException error = _errorOf(
            () => validateFieldRect(
              left: fixture.left,
              top: fixture.top,
              width: fixture.width,
              height: fixture.height,
              pageBox: pageBox,
            ),
          );
          expect(error.code, EditFieldErrorCode.invalidInput);
          expect(error.message, isNotEmpty);
          expect(error.message, isNot(contains('NaN')));
          expect(error.message, isNot(contains('Infinity')));
          expect(error.toString(), contains('invalidInput'));
        }
      }

      for (final double bad in <double>[0, -1, -0.0]) {
        for (final ({double left, double top, double width, double height})
            fixture
            in <({double left, double top, double width, double height})>[
              (left: 0, top: 0, width: bad, height: 10),
              (left: 0, top: 0, width: 10, height: bad),
            ]) {
          final EditFieldException error = _errorOf(
            () => validateFieldRect(
              left: fixture.left,
              top: fixture.top,
              width: fixture.width,
              height: fixture.height,
              pageBox: pageBox,
            ),
          );
          expect(error.code, EditFieldErrorCode.invalidInput);
          expect(error.message, isNotEmpty);
          expect(error.toString(), isNot(contains('-0.0')));
        }
      }

      // The immutable core Rect rejects an invalid component at construction,
      // before any command can receive it; the command's shared validator above
      // is the reachable boundary for raw pointer/drag values.
      final ConfirmedField field = _userField(id: _uuid(110), order: 0);
      final RevisionContent base = _content(fields: <ConfirmedField>[field]);
      expect(
        () => addField(
          base,
          _uuid(111),
          0,
          Rect.fromLTWH(double.nan, 0, 10, 10),
          FieldType.text,
          'Feld',
          _at(),
        ),
        throwsArgumentError,
      );
      expect(
        () => moveField(
          base,
          field.id,
          Rect.fromLTWH(0, 0, double.infinity, 10),
          _at(),
        ),
        throwsArgumentError,
      );
      expect(
        () => resizeField(base, field.id, Rect.fromLTWH(0, 0, 0, 10), _at()),
        throwsArgumentError,
      );
    });

    test('machine-field move receipts snapshot the complete previous '
        'suggestions for exact undo', () {
      final FieldSuggestion confirmed = _suggestion(
        ordinal: 1,
        resolution: SuggestionResolution.confirmed,
      );
      final ConfirmedField machine = _machineField(
        id: _uuid(109),
        sourceSuggestionId: confirmed.id,
        order: 0,
      );
      final FieldSuggestion duplicate = _suggestion(
        ordinal: 2,
        rect: machine.rect,
        proposedType: machine.type,
        duplicateOfConfirmed: true,
      );
      final RevisionContent base = _content(
        suggestions: <FieldSuggestion>[confirmed, duplicate],
        fields: <ConfirmedField>[machine],
      );

      final EditFieldChange change = moveField(
        base,
        machine.id,
        _rect(left: 300, top: 500),
        _at(37),
      );

      expect(change.previousSuggestions, base.suggestions);
      expect(change.previousSuggestions, isNotNull);
      final RevisionContent restored = RevisionContent(
        pages: change.content.pages,
        suggestions: change.previousSuggestions!,
        fields: <ConfirmedField>[change.previousField!],
        fieldOrder: <String>[change.fieldId],
        values: change.previousValue == null
            ? const <String, FieldValue>{}
            : <String, FieldValue>{change.fieldId: change.previousValue!},
        signatures: change.previousSignature == null
            ? const <String, SignatureMark>{}
            : <String, SignatureMark>{
                change.fieldId: change.previousSignature!,
              },
        verification: change.previousVerification == null
            ? const <String, FieldVerification>{}
            : <String, FieldVerification>{
                change.fieldId: change.previousVerification!,
              },
        templateOrigin: change.content.templateOrigin,
        unknownFields: change.content.unknownFields,
      );
      expect(restored, base);
      _expectValid(change.content);
    });

    test('every error message is content-free', () {
      final ConfirmedField field = _field(
        id: _uuid(105),
        order: 0,
        label: 'T066-GEHEIM-LABEL',
      );
      final RevisionContent base = _content(fields: <ConfirmedField>[field]);
      final List<EditFieldException> errors = <EditFieldException>[
        _errorOf(
          () => addField(
            base,
            'T066-GEHEIM-ID',
            0,
            _rect(),
            FieldType.text,
            'T066-GEHEIM-LABEL',
            _at(),
          ),
        ),
        _errorOf(
          () => addField(
            base,
            _uuid(106),
            5,
            _rect(),
            FieldType.text,
            'T066-GEHEIM-LABEL',
            _at(),
          ),
        ),
        _errorOf(() => removeField(base, _uuid(107))),
        _errorOf(() => moveField(base, field.id, _rect(left: -1), _at())),
        _errorOf(() => reclassifyField(base, field.id, FieldType.text, _at())),
        _errorOf(
          () => addField(
            base,
            field.id,
            0,
            _rect(),
            FieldType.text,
            'T066-GEHEIM-LABEL',
            _at(),
          ),
        ),
      ];

      expect(
        errors.map((EditFieldException error) => error.code).toSet(),
        <EditFieldErrorCode>{
          EditFieldErrorCode.invalidInput,
          EditFieldErrorCode.pageOutOfBounds,
          EditFieldErrorCode.fieldNotFound,
          EditFieldErrorCode.noChange,
          EditFieldErrorCode.wrongState,
        },
      );
      for (final EditFieldException error in errors) {
        expect(error.message, isNotEmpty);
        expect(error.message, isNot(contains('T066-GEHEIM')));
        expect(error.toString(), isNot(contains('T066-GEHEIM')));
        expect(error.message, isNot(contains(_uuid(105))));
        expect(error.toString(), isNot(contains(_uuid(105))));
        expect(error.message, isNot(contains('/')));
      }
      for (final EditFieldErrorCode code in EditFieldErrorCode.values) {
        final EditFieldException exception = EditFieldException(code);
        expect(exception.message, isNotEmpty);
        expect(exception.toString(), contains(code.name));
        expect(exception.message, isNot(contains('T066-GEHEIM')));
      }
    });

    test('the command library has no I/O, clock, or id-randomness path', () {
      final File library = File('lib/src/review/edit_field.dart');
      expect(library.existsSync(), isTrue);
      final String source = library.readAsStringSync();

      for (final String forbidden in <String>[
        'dart:io',
        'dart:math',
        'DateTime.now',
        'Random(',
        'Stopwatch',
        'package:uuid',
        'Uuid().v4',
      ]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason: 'the pure command library must not contain $forbidden',
        );
      }
    });
  });
}
