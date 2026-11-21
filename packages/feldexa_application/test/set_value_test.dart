// T071A `setFieldValue` command unit tests.
//
// Evidence class: NONE. These are host-VM unit tests over the pure application
// command. They construct no platform channel, open no document, touch no
// store, and make no Android, device, or visual claim.
//
// They prove:
//   * every one of the six field types accepts its matching value and stamps
//     the supplied UTC edit instant;
//   * a mismatched concrete value and a missing field are content-free
//     `ArgumentError`s;
//   * only `values[fieldId]` changes while pages, suggestions, fields, order,
//     signatures, verification, template origin, and unknown JSON fields are
//     preserved;
//   * a compatible concrete replacement of preserved incompatible content
//     clears the `incompatible_content` warning or blocking parse error while
//     every other revision member stays preserved, and an incompatible
//     replacement still throws content-free without mutating the input;
//   * the receipt carries the previous value and the exact previous snapshot;
//   * text is never truncated by the command.

@TestOn('vm')
library;

import 'package:feldexa_application/src/review/set_value.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:flutter_test/flutter_test.dart';

const String _fieldText = '11111111-1111-4111-8111-111111111111';
const String _fieldMultiline = '22222222-2222-4222-8222-222222222222';
const String _fieldNumber = '33333333-3333-4333-8333-333333333333';
const String _fieldDate = '44444444-4444-4444-8444-444444444444';
const String _fieldCheckbox = '55555555-5555-4555-8555-555555555555';
const String _fieldSignature = '66666666-6666-4666-8666-666666666666';
const String _signatureAsset = '77777777-7777-4777-8777-777777777777';
const String _templateId = '88888888-8888-4888-8888-888888888888';
const String _templateVersionId = '99999999-9999-4999-8999-999999999999';
final String _sha256 = List<String>.filled(64, 'a').join();
final DateTime _editTime = DateTime.utc(2026, 11, 21, 9, 30);
final DateTime _initialTime = DateTime.utc(2026, 11, 20, 8);

Rect _rect(double top) => Rect.fromLTWH(20, top, 80, 16);

ConfirmedField _field(String id, FieldType type, int order, double top) {
  return ConfirmedField(
    id: id,
    pageIndex: 0,
    rect: _rect(top),
    type: type,
    provenance: Provenance.user,
    label: 'Feld $order',
    order: order,
    createdAt: _initialTime,
    updatedAt: _initialTime,
  );
}

RevisionContent _baseContent() {
  final List<ConfirmedField> fields = <ConfirmedField>[
    _field(_fieldText, FieldType.text, 0, 20),
    _field(_fieldMultiline, FieldType.multiline, 1, 40),
    _field(_fieldNumber, FieldType.number, 2, 60),
    _field(_fieldDate, FieldType.date, 3, 80),
    _field(_fieldCheckbox, FieldType.checkbox, 4, 100),
    _field(_fieldSignature, FieldType.signature, 5, 120),
  ];
  final Map<String, FieldValue> values = <String, FieldValue>{
    _fieldText: TextValue(text: 'Alt', lastEditedAt: _initialTime),
    _fieldMultiline: MultilineValue(
      text: 'Zeile 1\nZeile 2',
      lastEditedAt: _initialTime,
    ),
    _fieldNumber: NumberValue(
      canonical: '12.5',
      rawGerman: '12,5',
      lastEditedAt: _initialTime,
    ),
    _fieldDate: DateValue(canonical: '2026-01-02', lastEditedAt: _initialTime),
    _fieldCheckbox: CheckboxValue(checked: false, lastEditedAt: _initialTime),
    _fieldSignature: SignatureValue(
      signatureAssetId: _signatureAsset,
      lastEditedAt: _initialTime,
    ),
  };
  return RevisionContent(
    pages: <Page>[
      Page(
        index: 0,
        geometry: PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 200, 200)),
      ),
    ],
    suggestions: <FieldSuggestion>[
      FieldSuggestion(
        id: 's_p0_0001',
        pageIndex: 0,
        rect: _rect(140),
        proposedType: FieldType.text,
        confidence: 0.8,
        labelText: 'Hinweis',
        evidence: SuggestionEvidence(
          cues: const <SuggestionCue>[SuggestionCue.underline],
          ocrUsed: false,
        ),
      ),
    ],
    fields: fields,
    fieldOrder: <String>[for (final ConfirmedField field in fields) field.id],
    values: values,
    signatures: <String, SignatureMark>{
      _fieldSignature: SignatureMark(
        assetId: _signatureAsset,
        fieldId: _fieldSignature,
        pageIndex: 0,
        rect: _rect(120),
        widthPx: 100,
        heightPx: 40,
        capturedAt: _initialTime,
        sha256: _sha256,
      ),
    },
    verification: <String, FieldVerification>{
      _fieldText: FieldVerification(
        state: FieldVerificationState.corrected,
        reviewedAt: _initialTime,
        warnings: const <WarningCode>[WarningCode.overflow],
      ),
    },
    templateOrigin: TemplateOrigin(
      templateId: _templateId,
      templateVersionId: _templateVersionId,
      templateVersionNumber: 3,
    ),
    unknownFields: <String, Object?>{
      'laterField': <String, Object?>{'enabled': true},
    },
  );
}

/// Builds the base snapshot with one preserved [IncompatibleValue] and the
/// validation flag the revision schema requires for it.
RevisionContent _contentWithIncompatible({
  required String fieldId,
  required FieldValidation validation,
}) {
  final RevisionContent base = _baseContent();
  final IncompatibleValue incompatible = IncompatibleValue(
    preservedText: 'Alt',
    reasonCode: 'reclassified',
    lastEditedAt: _initialTime,
  );
  final List<ConfirmedField> fields = <ConfirmedField>[
    for (final ConfirmedField candidate in base.fields)
      if (candidate.id == fieldId)
        candidate.copyWith(validation: validation)
      else
        candidate,
  ];
  return RevisionContent(
    pages: base.pages,
    suggestions: base.suggestions,
    fields: fields,
    fieldOrder: base.fieldOrder,
    values: <String, FieldValue>{...base.values, fieldId: incompatible},
    signatures: base.signatures,
    verification: base.verification,
    templateOrigin: base.templateOrigin,
    unknownFields: base.unknownFields,
  );
}

FieldValue _valueFor(FieldType type, {String text = 'Neu'}) {
  return switch (type) {
    FieldType.text => TextValue(text: text, lastEditedAt: _initialTime),
    FieldType.multiline => MultilineValue(
      text: 'Neu\nMehr',
      lastEditedAt: _initialTime,
    ),
    FieldType.number => NumberValue(
      canonical: '1234.56',
      rawGerman: '1.234,56',
      lastEditedAt: _initialTime,
    ),
    FieldType.date => DateValue(
      canonical: '2026-12-31',
      lastEditedAt: _initialTime,
    ),
    FieldType.checkbox => CheckboxValue(
      checked: true,
      lastEditedAt: _initialTime,
    ),
    FieldType.signature => SignatureValue(
      signatureAssetId: _signatureAsset,
      lastEditedAt: _initialTime,
    ),
  };
}

String _fieldIdFor(FieldType type) {
  return switch (type) {
    FieldType.text => _fieldText,
    FieldType.multiline => _fieldMultiline,
    FieldType.number => _fieldNumber,
    FieldType.date => _fieldDate,
    FieldType.checkbox => _fieldCheckbox,
    FieldType.signature => _fieldSignature,
  };
}

void main() {
  for (final FieldType type in FieldType.values) {
    test(
      '${type.wireName} stores its matching value and preserves the rest',
      () {
        final RevisionContent base = _baseContent();
        final String fieldId = _fieldIdFor(type);
        final FieldValue value = _valueFor(type);
        final SetValueChange change = setFieldValue(
          base,
          fieldId,
          value: value,
          lastEditedAt: _editTime,
        );

        expect(change.fieldId, fieldId);
        expect(change.previousContent, same(base));
        expect(change.previousValue, base.values[fieldId]);
        expect(change.content.values[fieldId], change.value);
        expect(change.value.lastEditedAt, _editTime);
        expect(change.value.type, type);

        expect(change.content.pages, base.pages);
        expect(change.content.suggestions, base.suggestions);
        expect(change.content.fields, base.fields);
        expect(change.content.fieldOrder, base.fieldOrder);
        expect(change.content.signatures, base.signatures);
        expect(change.content.verification, base.verification);
        expect(change.content.templateOrigin, base.templateOrigin);
        expect(change.content.unknownFields, base.unknownFields);

        for (final MapEntry<String, FieldValue> entry in base.values.entries) {
          if (entry.key == fieldId) {
            continue;
          }
          expect(change.content.values[entry.key], same(entry.value));
        }
        expect(base.values[fieldId], isNot(change.value));
      },
    );
  }

  test('rejects a value whose concrete type does not match the field', () {
    final RevisionContent base = _baseContent();
    expect(
      () => setFieldValue(
        base,
        _fieldText,
        value: NumberValue(
          canonical: '1',
          rawGerman: '1',
          lastEditedAt: _initialTime,
        ),
        lastEditedAt: _editTime,
      ),
      throwsArgumentError,
    );
    expect(
      () => setFieldValue(
        base,
        _fieldSignature,
        value: IncompatibleValue(
          preservedText: 'x',
          reasonCode: 'test',
          lastEditedAt: _initialTime,
        ),
        lastEditedAt: _editTime,
      ),
      throwsArgumentError,
    );
  });

  test(
    'a compatible text replacement clears the incompatible-content warning',
    () {
      final RevisionContent base = _contentWithIncompatible(
        fieldId: _fieldText,
        validation: FieldValidation.warning(
          WarningCode.incompatibleContent,
          'FLD-002',
          unknownFields: <String, Object?>{'laterValidation': true},
        ),
      );
      expect(base.values[_fieldText], isA<IncompatibleValue>());

      final SetValueChange change = setFieldValue(
        base,
        _fieldText,
        value: TextValue(text: 'Neu', lastEditedAt: _initialTime),
        lastEditedAt: _editTime,
      );
      final RevisionContent updated = change.content;
      final ConfirmedField field = updated.fields.firstWhere(
        (ConfirmedField candidate) => candidate.id == _fieldText,
      );
      expect(field.validation.isOk, isTrue);
      expect(field.validation.toJson()['status'], 'ok');
      expect(field.validation.unknownFields, <String, Object?>{
        'laterValidation': true,
      });
      final FieldValue stored = updated.values[_fieldText]!;
      expect(stored, isA<TextValue>());
      expect((stored as TextValue).text, 'Neu');
      expect(stored.lastEditedAt, _editTime);

      expect(change.previousContent, same(base));
      expect(change.previousValue, isA<IncompatibleValue>());
      expect(updated.pages, base.pages);
      expect(updated.suggestions, base.suggestions);
      expect(updated.fieldOrder, base.fieldOrder);
      expect(updated.signatures, base.signatures);
      expect(updated.verification, base.verification);
      expect(updated.templateOrigin, base.templateOrigin);
      expect(updated.unknownFields, base.unknownFields);
      for (final ConfirmedField candidate in base.fields) {
        if (candidate.id == _fieldText) {
          continue;
        }
        expect(updated.fields, contains(candidate));
      }
      for (final MapEntry<String, FieldValue> entry in base.values.entries) {
        if (entry.key == _fieldText) {
          continue;
        }
        expect(updated.values[entry.key], same(entry.value));
      }
    },
  );

  test('a compatible number replacement clears a blocking parse error', () {
    final RevisionContent base = _contentWithIncompatible(
      fieldId: _fieldNumber,
      validation: FieldValidation.error('NUM-001'),
    );
    expect(base.values[_fieldNumber], isA<IncompatibleValue>());

    final SetValueChange change = setFieldValue(
      base,
      _fieldNumber,
      value: NumberValue(
        canonical: '1234.56',
        rawGerman: '1.234,56',
        lastEditedAt: _initialTime,
      ),
      lastEditedAt: _editTime,
    );
    final ConfirmedField field = change.content.fields.firstWhere(
      (ConfirmedField candidate) => candidate.id == _fieldNumber,
    );
    expect(field.validation.isOk, isTrue);
    final FieldValue stored = change.content.values[_fieldNumber]!;
    expect(stored, isA<NumberValue>());
    expect((stored as NumberValue).canonical, '1234.56');
    expect(stored.lastEditedAt, _editTime);
  });

  test('an incompatible replacement keeps the warning and mutates nothing', () {
    final RevisionContent base = _contentWithIncompatible(
      fieldId: _fieldText,
      validation: FieldValidation.warning(
        WarningCode.incompatibleContent,
        'FLD-002',
      ),
    );
    expect(
      () => setFieldValue(
        base,
        _fieldText,
        value: NumberValue(
          canonical: '1',
          rawGerman: '1',
          lastEditedAt: _initialTime,
        ),
        lastEditedAt: _editTime,
      ),
      throwsArgumentError,
    );
    expect(
      () => setFieldValue(
        base,
        _fieldNumber,
        value: IncompatibleValue(
          preservedText: 'x',
          reasonCode: 'test',
          lastEditedAt: _initialTime,
        ),
        lastEditedAt: _editTime,
      ),
      throwsArgumentError,
    );

    final FieldValue preserved = base.values[_fieldText]!;
    expect(preserved, isA<IncompatibleValue>());
    expect((preserved as IncompatibleValue).preservedText, 'Alt');
    final ConfirmedField field = base.fields.firstWhere(
      (ConfirmedField candidate) => candidate.id == _fieldText,
    );
    expect(field.validation.isWarning, isTrue);
    expect(field.validation.warningCode, WarningCode.incompatibleContent);
  });

  test('rejects a missing field without echoing the id', () {
    final RevisionContent base = _baseContent();
    try {
      setFieldValue(
        base,
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        value: TextValue(text: 'x', lastEditedAt: _initialTime),
        lastEditedAt: _editTime,
      );
      fail('expected ArgumentError');
    } on ArgumentError catch (error) {
      expect(error.toString(), isNot(contains('aaaaaaaa')));
    }
  });

  test('rejects a non-UTC edit instant', () {
    final RevisionContent base = _baseContent();
    expect(
      () => setFieldValue(
        base,
        _fieldText,
        value: TextValue(text: 'x', lastEditedAt: _initialTime),
        lastEditedAt: DateTime(2026, 11, 21, 9, 30),
      ),
      throwsArgumentError,
    );
  });

  test('keeps a long text untruncated', () {
    final RevisionContent base = _baseContent();
    final String longText = 'ä' * 9000;
    final SetValueChange change = setFieldValue(
      base,
      _fieldText,
      value: TextValue(text: longText, lastEditedAt: _initialTime),
      lastEditedAt: _editTime,
    );
    final FieldValue stored = change.content.values[_fieldText]!;
    expect(stored, isA<TextValue>());
    expect((stored as TextValue).text.length, 9000);
  });
}
