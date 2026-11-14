// T019 reclassification-rule tests.
//
// These are host-VM tests (evidence class NONE). They pin `spec.md`
// FR-029/FR-038/FR-110, `data-model.md` §3.5–§3.6 and §5,
// `contracts/error-catalog.de.md` §2, and the aggregate compatibility of the
// preserved content:
//   * every documented transition in the §3.5 matrix;
//   * text ⇄ multiline with explicit line-break confirmation;
//   * text → number/date parse success and the preserved `NUM-001`,
//     `DATE-001`, and `DATE-002` failures;
//   * number/date → text clearing the error;
//   * text/number/date → checkbox and → signature preservation;
//   * checkbox → signature clearing and signature → other clearing;
//   * empty content, the 10,000-character boundary, overflow, and unknown
//     same-schema fields;
//   * result semantics, `resolve`, aggregate pairing, the full 6 × 6 matrix,
//     and privacy: errors and `toString` never echo content.

import 'package:feldexa_core/feldexa_core.dart';
import 'package:flutter_test/flutter_test.dart';

const String _uuid = '1b4e28ba-2fa1-4d3b-a1f8-6f2a3c4d5e6f';
const String _assetId = 'd2a1b3c4-1234-4abc-8def-0123456789ab';
const String _sha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _canary = 'Müllerstraße 4711';

DateTime _at([int minute = 0]) => DateTime.utc(2026, 11, 14, 12, minute);

Rect _rect() => Rect.fromLTWH(10, 20, 120, 18);

ConfirmedField _field({
  String id = _uuid,
  FieldType type = FieldType.text,
  Provenance provenance = Provenance.user,
  FieldValidation validation = FieldValidation.ok,
  DateTime? createdAt,
  DateTime? updatedAt,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return ConfirmedField(
    id: id,
    pageIndex: 0,
    rect: _rect(),
    type: type,
    provenance: provenance,
    label: 'Feld 1',
    order: 0,
    createdAt: createdAt ?? _at(),
    updatedAt: updatedAt ?? _at(),
    validation: validation,
    unknownFields: unknownFields,
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
    lastEditedAt: at ?? _at(),
    overflow: overflow,
    unknownFields: unknownFields,
  );
}

NumberValue _number(
  String canonical,
  String rawGerman, {
  DateTime? at,
  bool overflow = false,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return NumberValue(
    canonical: canonical,
    rawGerman: rawGerman,
    lastEditedAt: at ?? _at(),
    overflow: overflow,
    unknownFields: unknownFields,
  );
}

DateValue _date(
  String canonical, {
  DateTime? at,
  bool overflow = false,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return DateValue(
    canonical: canonical,
    lastEditedAt: at ?? _at(),
    overflow: overflow,
    unknownFields: unknownFields,
  );
}

CheckboxValue _checkbox(
  bool checked, {
  DateTime? at,
  bool overflow = false,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return CheckboxValue(
    checked: checked,
    lastEditedAt: at ?? _at(),
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
    lastEditedAt: at ?? _at(),
    overflow: overflow,
    unknownFields: unknownFields,
  );
}

SignatureValue _signature(
  String assetId, {
  DateTime? at,
  bool overflow = false,
}) {
  return SignatureValue(
    signatureAssetId: assetId,
    lastEditedAt: at ?? _at(),
    overflow: overflow,
  );
}

IncompatibleValue _incompatible(
  String preservedText,
  String reasonCode, {
  DateTime? at,
}) {
  return IncompatibleValue(
    preservedText: preservedText,
    reasonCode: reasonCode,
    lastEditedAt: at ?? _at(),
  );
}

ReclassificationResult _change(
  ConfirmedField field,
  FieldValue? value,
  FieldType newType, {
  bool confirm = false,
  DateTime? updatedAt,
}) {
  return reclassifyField(
    field: field,
    value: value,
    newType: newType,
    updatedAt: updatedAt ?? _at(5),
    confirmLineBreakJoin: confirm,
  );
}

/// Mirrors the T017/T020 aggregate invariant: a stored value must match the
/// field type, or be an [IncompatibleValue] flagged as incompatible by the
/// `incompatible_content` warning or a blocking [FieldValidation.error]
/// (`data-model.md` §3.5).
void _expectAggregateCompatible(ReclassificationResult result) {
  final FieldValue? value = result.value;
  if (value == null) {
    expect(result.field.validation.isError, isFalse);
    return;
  }
  expect(result.field.acceptsValue(value), isTrue);
  final bool incompatible = value is IncompatibleValue;
  final bool flagsIncompatible =
      result.field.validation.isError ||
      (result.field.validation.isWarning &&
          result.field.validation.warningCode ==
              WarningCode.incompatibleContent);
  expect(
    incompatible,
    flagsIncompatible,
    reason:
        'incompatible content must be flagged by a warning or a field error',
  );
  if (result.errorCode != null) {
    expect(result.field.validation.errorCode, result.errorCode);
  }
}

/// Builds a minimal valid document with the result's field and value, proving
/// the aggregate accepts the reclassified state.
Document _documentFor(ReclassificationResult result) {
  const String sourceId = '00000000-0000-4000-8000-000000000001';
  const String documentId = '00000000-0000-4000-8000-000000000002';
  const String revisionId = '00000000-0000-4000-8000-000000000090';
  final FieldValue? value = result.value;
  final Map<String, SignatureMark> signatures = <String, SignatureMark>{};
  if (value is SignatureValue) {
    signatures[result.field.id] = SignatureMark(
      assetId: value.signatureAssetId,
      fieldId: result.field.id,
      pageIndex: 0,
      rect: _rect(),
      widthPx: 100,
      heightPx: 50,
      capturedAt: _at(),
      sha256: _sha256,
    );
  }
  return Document(
    id: documentId,
    title: 'Antrag',
    createdAt: _at(),
    updatedAt: _at(),
    source: SourceFileRef(
      id: sourceId,
      sha256: _sha256,
      sizeBytes: 1024,
      pageCount: 1,
      importedAt: _at(),
    ),
    pages: <Page>[
      Page(
        index: 0,
        geometry: PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842)),
      ),
    ],
    fields: <ConfirmedField>[result.field],
    fieldOrder: <String>[result.field.id],
    values: value == null
        ? const <String, FieldValue>{}
        : <String, FieldValue>{result.field.id: value},
    signatures: signatures,
    lastDurable: DurablePointer(
      revisionId: revisionId,
      kind: DurablePointer.autosaveKind,
      committedAt: _at(),
      sha256: _sha256,
    ),
  );
}

void main() {
  group('same-type reclassification', () {
    final Map<FieldType, FieldValue> values = <FieldType, FieldValue>{
      FieldType.text: _text('Müller'),
      FieldType.number: _number('42', '42'),
      FieldType.date: _date('2025-12-31'),
      FieldType.checkbox: _checkbox(true),
      FieldType.multiline: _multiline('a\nb'),
      FieldType.signature: _signature(_assetId),
    };

    for (final MapEntry<FieldType, FieldValue> entry in values.entries) {
      test('${entry.key.wireName} to itself is a no-op', () {
        final ConfirmedField field = _field(type: entry.key);
        final ReclassificationResult result = _change(
          field,
          entry.value,
          entry.key,
        );
        expect(result.field, same(field));
        expect(result.value, same(entry.value));
        expect(result.kind, ReclassificationKind.compatible);
        expect(result.requiresUserAction, isFalse);
        expect(result.blocksExport, isFalse);
        expect(result.reason, isNull);
        expect(result.errorCode, isNull);
        expect(result.clearedSignatureAssetId, isNull);
      });
    }
  });

  group('text and multiline', () {
    test('text to multiline preserves content and metadata', () {
      final ConfirmedField field = _field(
        type: FieldType.text,
        validation: FieldValidation.warning(WarningCode.overflow, 'FLD-001'),
        unknownFields: <String, Object?>{'fieldExtension': true},
      );
      final TextValue source = _text(
        'Müllerstraße',
        overflow: true,
        unknownFields: <String, Object?>{'valueExtension': 'kept'},
      );

      final ReclassificationResult result = _change(
        field,
        source,
        FieldType.multiline,
      );

      expect(result.kind, ReclassificationKind.compatible);
      expect(result.field.type, FieldType.multiline);
      expect(result.field.updatedAt, _at(5));
      expect(result.field.unknownFields, <String, Object?>{
        'fieldExtension': true,
      });
      expect(result.field.validation.warningCode, WarningCode.overflow);
      final MultilineValue value = result.value! as MultilineValue;
      expect(value.text, 'Müllerstraße');
      expect(value.overflow, isTrue);
      expect(value.lastEditedAt, _at(5));
      expect(value.unknownFields, <String, Object?>{'valueExtension': 'kept'});
      _expectAggregateCompatible(result);
    });

    test('multiline without a line break to text is lossless', () {
      final ReclassificationResult result = _change(
        _field(type: FieldType.multiline),
        _multiline('Einzeilig'),
        FieldType.text,
      );
      expect(result.kind, ReclassificationKind.compatible);
      expect(result.value, isA<TextValue>());
      expect((result.value! as TextValue).text, 'Einzeilig');
    });

    test('multiline with a line break needs explicit confirmation', () {
      final ReclassificationResult result = _change(
        _field(type: FieldType.multiline),
        _multiline('Zeile 1\nZeile 2'),
        FieldType.text,
      );

      expect(result.kind, ReclassificationKind.confirmationRequired);
      expect(result.requiresUserAction, isTrue);
      expect(result.blocksExport, isTrue);
      expect(result.reason, ReclassificationReason.lineBreakJoinConfirmation);
      final IncompatibleValue preserved = result.value! as IncompatibleValue;
      expect(preserved.preservedText, 'Zeile 1\nZeile 2');
      expect(preserved.reasonCode, 'line_break_join_confirmation');
      expect(
        result.field.validation.warningCode,
        WarningCode.incompatibleContent,
      );
      expect(result.field.validation.messageKey, 'FLD-002');
      expect(result.proposedValue, isA<TextValue>());
      expect((result.proposedValue! as TextValue).text, 'Zeile 1 Zeile 2');
      expect(result.proposedValue!.lastEditedAt, _at(5));
      _expectAggregateCompatible(result);
      expect(() => _documentFor(result), returnsNormally);
    });

    test('each line break becomes exactly one space after confirmation', () {
      final ReclassificationResult result = _change(
        _field(type: FieldType.multiline),
        _multiline('a\n\nb\n'),
        FieldType.text,
        confirm: true,
      );
      expect(result.kind, ReclassificationKind.compatible);
      expect((result.value! as TextValue).text, 'a  b ');
      expect(result.field.validation, FieldValidation.ok);
      _expectAggregateCompatible(result);
    });

    test('confirmed line-break join resolves the open action', () {
      final ReclassificationResult pending = _change(
        _field(type: FieldType.multiline),
        _multiline('a\nb'),
        FieldType.text,
      );
      final ReclassificationResult resolved = pending.resolve();
      expect(resolved.kind, ReclassificationKind.compatible);
      expect(resolved.value, isA<TextValue>());
      expect((resolved.value! as TextValue).text, 'a b');
      expect(resolved.field.validation, FieldValidation.ok);
      expect(resolved.preservedContent, isNull);
      expect(resolved.blocksExport, isFalse);
      _expectAggregateCompatible(resolved);
      expect(() => _documentFor(resolved), returnsNormally);
    });

    test('empty text stays an empty multiline value', () {
      final ReclassificationResult result = _change(
        _field(),
        _text(''),
        FieldType.multiline,
      );
      expect(result.kind, ReclassificationKind.compatible);
      expect((result.value! as MultilineValue).text, '');
      _expectAggregateCompatible(result);
    });
  });

  group('text to number', () {
    test('parses a German grouped decimal', () {
      final ReclassificationResult result = _change(
        _field(),
        _text('1.234,56'),
        FieldType.number,
      );
      expect(result.kind, ReclassificationKind.compatible);
      final NumberValue value = result.value! as NumberValue;
      expect(value.canonical, '1234.56');
      expect(value.rawGerman, '1.234,56');
      expect(value.lastEditedAt, _at(5));
    });

    test('parses German comma decimals and negatives', () {
      expect(
        (_change(_field(), _text('1234,56'), FieldType.number).value!
                as NumberValue)
            .canonical,
        '1234.56',
      );
      expect(
        (_change(_field(), _text('-1.234,56'), FieldType.number).value!
                as NumberValue)
            .canonical,
        '-1234.56',
      );
      expect(
        (_change(_field(), _text('0,50'), FieldType.number).value!
                as NumberValue)
            .canonical,
        '0.50',
      );
    });

    test('parses canonical dot decimals', () {
      expect(
        (_change(_field(), _text('1.23'), FieldType.number).value!
                as NumberValue)
            .canonical,
        '1.23',
      );
      expect(
        (_change(_field(), _text('1234.56'), FieldType.number).value!
                as NumberValue)
            .canonical,
        '1234.56',
      );
    });

    test('prefers a valid German grouping over a canonical dot decimal', () {
      final ReclassificationResult result = _change(
        _field(),
        _text('1.234'),
        FieldType.number,
      );
      expect((result.value! as NumberValue).canonical, '1234');
      expect((result.value! as NumberValue).rawGerman, '1.234');
    });

    test('trims for parsing but preserves the raw display text', () {
      final ReclassificationResult result = _change(
        _field(),
        _text(' 42 '),
        FieldType.number,
      );
      final NumberValue value = result.value! as NumberValue;
      expect(value.canonical, '42');
      expect(value.rawGerman, ' 42 ');
    });

    test(
      'preserves unparseable text with NUM-001 instead of discarding it',
      () {
        final ReclassificationResult result = _change(
          _field(),
          _text('keine Zahl'),
          FieldType.number,
        );
        expect(result.kind, ReclassificationKind.resolutionRequired);
        expect(result.blocksExport, isTrue);
        expect(result.errorCode, 'NUM-001');
        expect(result.reason, ReclassificationReason.numberParseFailed);
        final IncompatibleValue value = result.value! as IncompatibleValue;
        expect(value.preservedText, 'keine Zahl');
        expect(value.reasonCode, 'number_parse_failed');
        expect(result.preservedContent, 'keine Zahl');
        expect(result.proposedValue, isNull);
        expect(result.field.validation.isError, isTrue);
        expect(result.field.validation.errorCode, 'NUM-001');
        expect(result.field.validation.warningCode, isNull);
        _expectAggregateCompatible(result);
        expect(() => _documentFor(result), returnsNormally);
      },
    );

    test('preserves German characters and spaces verbatim on failure', () {
      final ReclassificationResult result = _change(
        _field(),
        _text(_canary),
        FieldType.number,
      );
      expect(result.preservedContent, _canary);
      expect(result.errorCode, 'NUM-001');
    });

    test('empty text produces no value instead of a parse error', () {
      final ReclassificationResult result = _change(
        _field(),
        _text(''),
        FieldType.number,
      );
      expect(result.kind, ReclassificationKind.compatible);
      expect(result.value, isNull);
      expect(result.errorCode, isNull);
      expect(result.field.validation, FieldValidation.ok);
      _expectAggregateCompatible(result);
      expect(() => _documentFor(result), returnsNormally);
    });

    test('whitespace-only text is preserved rather than treated as empty', () {
      final ReclassificationResult result = _change(
        _field(),
        _text('   '),
        FieldType.number,
      );
      expect(result.kind, ReclassificationKind.resolutionRequired);
      expect(result.preservedContent, '   ');
      expect(result.errorCode, 'NUM-001');
    });

    test('accepts the 10,000-character preserved-content boundary', () {
      final String longText = List<String>.filled(10000, 'x').join();
      final ReclassificationResult result = _change(
        _field(),
        _text(longText),
        FieldType.number,
      );
      expect(result.value, isA<IncompatibleValue>());
      expect(result.preservedContent, longText);
      expect(result.errorCode, 'NUM-001');
    });

    test('clears a previous field error on a lossless conversion', () {
      final ConfirmedField field = _field(
        validation: FieldValidation.error('NUM-001'),
      );
      final ReclassificationResult result = _change(
        field,
        _text('42'),
        FieldType.number,
      );
      expect(result.field.validation, FieldValidation.ok);
      expect(result.value, isA<NumberValue>());
    });

    test('keeps overflow metadata and the overflow warning', () {
      final ConfirmedField field = _field(
        validation: FieldValidation.warning(WarningCode.overflow, 'FLD-001'),
      );
      final ReclassificationResult result = _change(
        field,
        _text('42', overflow: true),
        FieldType.number,
      );
      expect((result.value! as NumberValue).overflow, isTrue);
      expect(result.field.validation.warningCode, WarningCode.overflow);
    });

    test('incompatible content takes precedence over an overflow warning', () {
      final ConfirmedField field = _field(
        validation: FieldValidation.warning(WarningCode.overflow, 'FLD-001'),
      );
      final ReclassificationResult result = _change(
        field,
        _text(_canary, overflow: true),
        FieldType.number,
      );
      expect(result.field.validation, FieldValidation.error('NUM-001'));
      expect(result.field.validation.warningCode, isNull);
      expect((result.value! as IncompatibleValue).overflow, isTrue);
    });
  });

  group('text to date', () {
    test('parses German dates with or without leading zeros', () {
      final ReclassificationResult result = _change(
        _field(),
        _text('31.12.2025'),
        FieldType.date,
      );
      final DateValue value = result.value! as DateValue;
      expect(value.canonical, '2025-12-31');
      expect(value.lastEditedAt, _at(5));
      expect(
        (_change(_field(), _text('1.2.2025'), FieldType.date).value!
                as DateValue)
            .canonical,
        '2025-02-01',
      );
    });

    test('accepts the canonical form emitted by date to text', () {
      final ReclassificationResult result = _change(
        _field(),
        _text('2025-12-31'),
        FieldType.date,
      );
      expect((result.value! as DateValue).canonical, '2025-12-31');
    });

    test('accepts a real leap day', () {
      final ReclassificationResult result = _change(
        _field(),
        _text('29.02.2024'),
        FieldType.date,
      );
      expect((result.value! as DateValue).canonical, '2024-02-29');
    });

    test('marks an impossible calendar date as DATE-002 and preserves it', () {
      final ReclassificationResult result = _change(
        _field(),
        _text('31.02.2025'),
        FieldType.date,
      );
      expect(result.kind, ReclassificationKind.resolutionRequired);
      expect(result.errorCode, 'DATE-002');
      expect(result.reason, ReclassificationReason.dateParseFailed);
      expect(result.preservedContent, '31.02.2025');
      expect(result.field.validation.isError, isTrue);
      expect(result.field.validation.errorCode, 'DATE-002');
      expect(result.field.validation.warningCode, isNull);
      _expectAggregateCompatible(result);
      expect(() => _documentFor(result), returnsNormally);
    });

    test('marks an impossible month as DATE-002', () {
      final ReclassificationResult result = _change(
        _field(),
        _text('31.13.2025'),
        FieldType.date,
      );
      expect(result.errorCode, 'DATE-002');
    });

    test('marks a malformed date as DATE-001 and preserves it', () {
      final ReclassificationResult result = _change(
        _field(),
        _text('Datum fehlt'),
        FieldType.date,
      );
      expect(result.errorCode, 'DATE-001');
      expect(result.preservedContent, 'Datum fehlt');
    });

    test('distinguishes a 29 February of a non-leap year as DATE-002', () {
      final ReclassificationResult result = _change(
        _field(),
        _text('29.02.2025'),
        FieldType.date,
      );
      expect(result.errorCode, 'DATE-002');
    });

    test('empty text produces no value instead of a date error', () {
      final ReclassificationResult result = _change(
        _field(),
        _text(''),
        FieldType.date,
      );
      expect(result.value, isNull);
      expect(result.errorCode, isNull);
      expect(result.kind, ReclassificationKind.compatible);
    });
  });

  group('number and date to text or multiline', () {
    test('number to text preserves the German display input', () {
      final ConfirmedField field = _field(
        type: FieldType.number,
        validation: FieldValidation.error('NUM-001'),
      );
      final ReclassificationResult result = _change(
        field,
        _number('1234.56', '1.234,56'),
        FieldType.text,
      );
      expect(result.kind, ReclassificationKind.compatible);
      expect((result.value! as TextValue).text, '1.234,56');
      expect(result.field.validation, FieldValidation.ok);
    });

    test(
      'date to text preserves the canonical content and clears the error',
      () {
        final ConfirmedField field = _field(
          type: FieldType.date,
          validation: FieldValidation.error('DATE-001'),
        );
        final ReclassificationResult result = _change(
          field,
          _date('2025-12-31'),
          FieldType.text,
        );
        expect((result.value! as TextValue).text, '2025-12-31');
        expect(result.field.validation, FieldValidation.ok);
      },
    );

    test('number and date to multiline preserve their display text', () {
      expect(
        (_change(
                  _field(type: FieldType.number),
                  _number('42', '42,0'),
                  FieldType.multiline,
                ).value!
                as MultilineValue)
            .text,
        '42,0',
      );
      expect(
        (_change(
                  _field(type: FieldType.date),
                  _date('2025-12-31'),
                  FieldType.multiline,
                ).value!
                as MultilineValue)
            .text,
        '2025-12-31',
      );
    });

    test('converted values keep same-schema extensions', () {
      final ReclassificationResult result = _change(
        _field(type: FieldType.number),
        _number('42', '42', unknownFields: <String, Object?>{'extension': 1}),
        FieldType.text,
      );
      expect(result.value!.unknownFields, <String, Object?>{'extension': 1});
    });
  });

  group('number and date cross-conversion', () {
    test('number to date parses a date-shaped display input', () {
      final ReclassificationResult result = _change(
        _field(type: FieldType.number),
        _number('31122025', '31.12.2025'),
        FieldType.date,
      );
      expect(result.kind, ReclassificationKind.compatible);
      expect((result.value! as DateValue).canonical, '2025-12-31');
    });

    test('number to date preserves a non-date projection with DATE-001', () {
      final ReclassificationResult result = _change(
        _field(type: FieldType.number),
        _number('1234.56', '1234,56'),
        FieldType.date,
      );
      expect(result.kind, ReclassificationKind.resolutionRequired);
      expect(result.errorCode, 'DATE-001');
      expect(result.preservedContent, '1234,56');
      _expectAggregateCompatible(result);
    });

    test('date to number preserves the canonical date with NUM-001', () {
      final ReclassificationResult result = _change(
        _field(type: FieldType.date),
        _date('2025-12-31'),
        FieldType.number,
      );
      expect(result.kind, ReclassificationKind.resolutionRequired);
      expect(result.errorCode, 'NUM-001');
      expect(result.preservedContent, '2025-12-31');
    });
  });

  group('to checkbox', () {
    test('text content is preserved and an unchecked box is proposed', () {
      final ReclassificationResult result = _change(
        _field(),
        _text('Erika Mustermann'),
        FieldType.checkbox,
      );
      expect(result.kind, ReclassificationKind.resolutionRequired);
      expect(result.blocksExport, isTrue);
      expect(result.reason, ReclassificationReason.checkboxRequiresResolution);
      expect(result.preservedContent, 'Erika Mustermann');
      expect(result.field.type, FieldType.checkbox);
      expect(
        result.field.validation.warningCode,
        WarningCode.incompatibleContent,
      );
      final CheckboxValue proposed = result.proposedValue! as CheckboxValue;
      expect(proposed.checked, isFalse);
      expect(proposed.lastEditedAt, _at(5));
      _expectAggregateCompatible(result);
      expect(() => _documentFor(result), returnsNormally);
    });

    test('number and date content are preserved verbatim', () {
      expect(
        _change(
          _field(type: FieldType.number),
          _number('1234.56', '1.234,56'),
          FieldType.checkbox,
        ).preservedContent,
        '1.234,56',
      );
      expect(
        _change(
          _field(type: FieldType.date),
          _date('2025-12-31'),
          FieldType.checkbox,
        ).preservedContent,
        '2025-12-31',
      );
    });

    test('multiline line breaks are preserved', () {
      final ReclassificationResult result = _change(
        _field(type: FieldType.multiline),
        _multiline('a\nb'),
        FieldType.checkbox,
      );
      expect(result.preservedContent, 'a\nb');
    });

    test('empty text becomes no value instead of an incompatible warning', () {
      final ReclassificationResult result = _change(
        _field(),
        _text(''),
        FieldType.checkbox,
      );
      expect(result.kind, ReclassificationKind.compatible);
      expect(result.value, isNull);
      expect(result.field.validation, FieldValidation.ok);
      _expectAggregateCompatible(result);
    });

    test('resolve accepts the proposed unchecked state', () {
      final ReclassificationResult pending = _change(
        _field(),
        _text('Erika'),
        FieldType.checkbox,
      );
      final ReclassificationResult resolved = pending.resolve();
      expect(resolved.kind, ReclassificationKind.compatible);
      expect(resolved.value, isA<CheckboxValue>());
      expect((resolved.value! as CheckboxValue).checked, isFalse);
      expect(resolved.field.validation, FieldValidation.ok);
      expect(resolved.preservedContent, isNull);
      expect(resolved.blocksExport, isFalse);
      _expectAggregateCompatible(resolved);
      expect(() => _documentFor(resolved), returnsNormally);
    });
  });

  group('to signature', () {
    test('text content is preserved and blocks export until resolved', () {
      final ReclassificationResult result = _change(
        _field(),
        _text(_canary),
        FieldType.signature,
      );
      expect(result.kind, ReclassificationKind.resolutionRequired);
      expect(result.blocksExport, isTrue);
      expect(result.reason, ReclassificationReason.signatureRequiresResolution);
      expect(result.preservedContent, _canary);
      expect(result.proposedValue, isNull);
      expect(result.field.type, FieldType.signature);
      _expectAggregateCompatible(result);
      expect(() => _documentFor(result), returnsNormally);
    });

    test('number and date content are preserved', () {
      expect(
        _change(
          _field(type: FieldType.number),
          _number('42', '42'),
          FieldType.signature,
        ).preservedContent,
        '42',
      );
      expect(
        _change(
          _field(type: FieldType.date),
          _date('2025-12-31'),
          FieldType.signature,
        ).preservedContent,
        '2025-12-31',
      );
    });

    test('empty text becomes an unsigned signature without a warning', () {
      final ReclassificationResult result = _change(
        _field(),
        _text(''),
        FieldType.signature,
      );
      expect(result.kind, ReclassificationKind.compatible);
      expect(result.value, isNull);
      expect(result.field.validation, FieldValidation.ok);
      _expectAggregateCompatible(result);
    });

    test('a checkbox state is cleared when the target is a signature', () {
      final ReclassificationResult result = _change(
        _field(type: FieldType.checkbox),
        _checkbox(true),
        FieldType.signature,
      );
      expect(result.kind, ReclassificationKind.checkboxCleared);
      expect(result.value, isNull);
      expect(result.preservedContent, isNull);
      expect(result.field.validation, FieldValidation.ok);
      expect(result.blocksExport, isFalse);
      _expectAggregateCompatible(result);
      expect(() => _documentFor(result), returnsNormally);
    });

    test('resolve discards the flagged text explicitly', () {
      final ReclassificationResult pending = _change(
        _field(),
        _text('Erika'),
        FieldType.signature,
      );
      final ReclassificationResult resolved = pending.resolve();
      expect(resolved.kind, ReclassificationKind.compatible);
      expect(resolved.value, isNull);
      expect(resolved.field.validation, FieldValidation.ok);
      _expectAggregateCompatible(resolved);
      expect(() => _documentFor(resolved), returnsNormally);
    });
  });

  group('from checkbox', () {
    test('checked and unchecked states project to Ja and Nein', () {
      final ReclassificationResult checked = _change(
        _field(type: FieldType.checkbox),
        _checkbox(true),
        FieldType.text,
      );
      expect(checked.kind, ReclassificationKind.resolutionRequired);
      expect(checked.reason, ReclassificationReason.checkboxStateProjection);
      expect(checked.preservedContent, 'Ja');
      expect((checked.proposedValue! as TextValue).text, 'Ja');

      final ReclassificationResult unchecked = _change(
        _field(type: FieldType.checkbox),
        _checkbox(false),
        FieldType.text,
      );
      expect(unchecked.preservedContent, 'Nein');
      expect((unchecked.proposedValue! as TextValue).text, 'Nein');
      _expectAggregateCompatible(checked);
      _expectAggregateCompatible(unchecked);
    });

    test('multiline projects the state and proposes multiline text', () {
      final ReclassificationResult result = _change(
        _field(type: FieldType.checkbox),
        _checkbox(true),
        FieldType.multiline,
      );
      expect(result.preservedContent, 'Ja');
      expect((result.proposedValue! as MultilineValue).text, 'Ja');
    });

    test(
      'number and date targets preserve the projection without inference',
      () {
        final ReclassificationResult number = _change(
          _field(type: FieldType.checkbox),
          _checkbox(true),
          FieldType.number,
        );
        expect(number.preservedContent, 'Ja');
        expect(number.errorCode, isNull);
        expect(number.proposedValue, isNull);

        final ReclassificationResult date = _change(
          _field(type: FieldType.checkbox),
          _checkbox(false),
          FieldType.date,
        );
        expect(date.preservedContent, 'Nein');
        expect(date.errorCode, isNull);
      },
    );

    test('resolve accepts the projected text explicitly', () {
      final ReclassificationResult pending = _change(
        _field(type: FieldType.checkbox),
        _checkbox(true),
        FieldType.text,
      );
      final ReclassificationResult resolved = pending.resolve();
      expect((resolved.value! as TextValue).text, 'Ja');
      expect(resolved.field.validation, FieldValidation.ok);
      _expectAggregateCompatible(resolved);
    });
  });

  group('from signature', () {
    test('signature to text clears the reference and surfaces the asset', () {
      final ReclassificationResult result = _change(
        _field(type: FieldType.signature),
        _signature(_assetId),
        FieldType.text,
      );
      expect(result.kind, ReclassificationKind.signatureCleared);
      expect(result.value, isNull);
      expect(result.clearedSignatureAssetId, _assetId);
      expect(result.preservedContent, isNull);
      expect(result.field.validation, FieldValidation.ok);
      expect(result.blocksExport, isFalse);
      _expectAggregateCompatible(result);
      expect(() => _documentFor(result), returnsNormally);
    });

    test('signature to the other non-signature types clears the reference', () {
      for (final FieldType target in <FieldType>[
        FieldType.multiline,
        FieldType.number,
        FieldType.date,
        FieldType.checkbox,
      ]) {
        final ReclassificationResult result = _change(
          _field(type: FieldType.signature),
          _signature(_assetId),
          target,
        );
        expect(result.kind, ReclassificationKind.signatureCleared);
        expect(result.value, isNull);
        expect(result.clearedSignatureAssetId, _assetId);
        expect(result.field.type, target);
        _expectAggregateCompatible(result);
        expect(() => _documentFor(result), returnsNormally);
      }
    });

    test('resolve is a no-op for an already cleared signature', () {
      final ReclassificationResult cleared = _change(
        _field(type: FieldType.signature),
        _signature(_assetId),
        FieldType.text,
      );
      expect(cleared.resolve(), same(cleared));
    });
  });

  group('preserved content beyond the documented matrix', () {
    test(
      'a preserved line break can be confirmed for a non-multiline source',
      () {
        final ConfirmedField field = _field(type: FieldType.number);
        final IncompatibleValue preserved = _incompatible(
          'a\nb',
          'number_parse_failed',
        );
        final ReclassificationResult pending = _change(
          field,
          preserved,
          FieldType.text,
        );
        expect(pending.kind, ReclassificationKind.confirmationRequired);
        expect(pending.preservedContent, 'a\nb');
        expect((pending.proposedValue! as TextValue).text, 'a b');

        final ReclassificationResult confirmed = _change(
          field,
          preserved,
          FieldType.text,
          confirm: true,
        );
        expect((confirmed.value! as TextValue).text, 'a b');
      },
    );

    test('control characters that text cannot store stay incompatible', () {
      final ConfirmedField field = _field(type: FieldType.number);
      final IncompatibleValue preserved = _incompatible(
        'a\u0001b',
        'number_parse_failed',
      );
      final ReclassificationResult result = _change(
        field,
        preserved,
        FieldType.text,
      );
      expect(result.kind, ReclassificationKind.resolutionRequired);
      expect(result.reason, ReclassificationReason.contentNotRepresentable);
      expect(result.preservedContent, 'a\u0001b');
      expect(
        result.field.validation.warningCode,
        WarningCode.incompatibleContent,
      );
      _expectAggregateCompatible(result);
    });

    test(
      'control characters that multiline cannot store stay incompatible',
      () {
        final ConfirmedField field = _field(type: FieldType.number);
        final IncompatibleValue preserved = _incompatible(
          'a\rb',
          'number_parse_failed',
        );
        final ReclassificationResult result = _change(
          field,
          preserved,
          FieldType.multiline,
        );
        expect(result.reason, ReclassificationReason.contentNotRepresentable);
        expect(result.preservedContent, 'a\rb');
      },
    );
  });

  group('input validation and privacy', () {
    test('rejects a value that does not belong to the field type', () {
      expect(
        () => _change(
          _field(type: FieldType.text),
          _number('42', _canary),
          FieldType.number,
        ),
        throwsArgumentError,
      );
    });

    test('a rejection never echoes content', () {
      expect(
        () => _change(
          _field(type: FieldType.text),
          _number('42', _canary),
          FieldType.number,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.toString(),
            'toString',
            isNot(contains(_canary)),
          ),
        ),
      );
    });

    test('rejects a misplaced line-break confirmation flag', () {
      expect(
        () => _change(_field(), _text('x'), FieldType.number, confirm: true),
        throwsArgumentError,
      );
      expect(
        () => _change(_field(), _text('x'), FieldType.multiline, confirm: true),
        throwsArgumentError,
      );
    });

    test('rejects a non-UTC updatedAt', () {
      expect(
        () => reclassifyField(
          field: _field(),
          value: _text('x'),
          newType: FieldType.multiline,
          updatedAt: DateTime(2026, 11, 14, 12),
        ),
        throwsArgumentError,
      );
    });

    test('rejects over-limit display content without echoing it', () {
      final String raw = List<String>.filled(10001, 'x').join();
      expect(
        () => _change(
          _field(type: FieldType.number),
          _number('1', raw),
          FieldType.text,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.toString(),
            'toString',
            isNot(contains('xxxxxxxxxxxxxxxxxxxx')),
          ),
        ),
      );
    });

    test('result toString never echoes preserved content', () {
      final ReclassificationResult result = _change(
        _field(),
        _text(_canary),
        FieldType.number,
      );
      expect(result.toString(), isNot(contains(_canary)));
      expect(result.value.toString(), isNot(contains(_canary)));
    });

    test('result equality and hashCode cover every field', () {
      final ReclassificationResult first = _change(
        _field(),
        _text('42'),
        FieldType.number,
      );
      final ReclassificationResult second = _change(
        _field(),
        _text('42'),
        FieldType.number,
      );
      final ReclassificationResult third = _change(
        _field(),
        _text('43'),
        FieldType.number,
      );
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(third));
    });
  });

  group('missing value and recovery', () {
    test('a field without a value changes type without content flags', () {
      for (final FieldType target in FieldType.values) {
        final ReclassificationResult result = _change(
          _field(type: FieldType.text),
          null,
          target,
        );
        expect(result.field.type, target);
        expect(result.value, isNull);
        expect(result.kind, ReclassificationKind.compatible);
        expect(result.field.validation, FieldValidation.ok);
        _expectAggregateCompatible(result);
        expect(() => _documentFor(result), returnsNormally);
      }
    });

    test('preserved content recovers as text', () {
      final ReclassificationResult result = _change(
        _field(type: FieldType.number),
        _incompatible('42', 'number_parse_failed'),
        FieldType.text,
      );
      expect(result.kind, ReclassificationKind.compatible);
      expect((result.value! as TextValue).text, '42');
      expect(result.field.validation, FieldValidation.ok);
      expect(result.preservedContent, isNull);
    });

    test('resolve is idempotent', () {
      final ReclassificationResult pending = _change(
        _field(type: FieldType.multiline),
        _multiline('a\nb'),
        FieldType.text,
      );
      final ReclassificationResult resolved = pending.resolve();
      expect(resolved.resolve(), same(resolved));
    });
  });

  group('same-schema validation extensions', () {
    const Map<String, Object?> extensions = <String, Object?>{
      'future.validation': 'kept',
    };

    FieldValidation okWithExtensions() {
      return FieldValidation.fromJson(<String, Object?>{
        ...extensions,
        'status': 'ok',
      });
    }

    test('a lossless conversion keeps validation extensions', () {
      final ReclassificationResult result = _change(
        _field(validation: okWithExtensions()),
        _text('x'),
        FieldType.multiline,
      );
      expect(result.field.validation.isOk, isTrue);
      expect(result.field.validation.unknownFields, extensions);
    });

    test('clearing an error keeps validation extensions', () {
      final ConfirmedField field = _field(
        type: FieldType.number,
        validation: FieldValidation.error('NUM-001', unknownFields: extensions),
      );
      final ReclassificationResult result = _change(
        field,
        _number('42', '42'),
        FieldType.text,
      );
      expect(result.field.validation.isOk, isTrue);
      expect(result.field.validation.unknownFields, extensions);
    });

    test('a parse-failure error keeps validation extensions', () {
      final ReclassificationResult result = _change(
        _field(validation: okWithExtensions()),
        _text('keine Zahl'),
        FieldType.number,
      );
      expect(result.field.validation.isError, isTrue);
      expect(result.field.validation.errorCode, 'NUM-001');
      expect(result.field.validation.unknownFields, extensions);
    });

    test('a checkbox warning keeps validation extensions', () {
      final ReclassificationResult result = _change(
        _field(validation: okWithExtensions()),
        _text('Erika'),
        FieldType.checkbox,
      );
      expect(result.field.validation.isWarning, isTrue);
      expect(result.field.validation.unknownFields, extensions);
    });

    test('resolve keeps validation extensions', () {
      final ReclassificationResult pending = _change(
        _field(validation: okWithExtensions()),
        _text('Erika'),
        FieldType.checkbox,
      );
      final ReclassificationResult resolved = pending.resolve();
      expect(resolved.field.validation.isOk, isTrue);
      expect(resolved.field.validation.unknownFields, extensions);
    });

    test('resolve keeps value extensions for a line-break join', () {
      final ReclassificationResult pending = _change(
        _field(type: FieldType.multiline),
        _multiline('a\nb', unknownFields: extensions),
        FieldType.text,
      );
      final ReclassificationResult resolved = pending.resolve();
      expect((resolved.value! as TextValue).text, 'a b');
      expect(resolved.value!.unknownFields, extensions);
    });

    test('resolve keeps value extensions for a checkbox projection', () {
      final ReclassificationResult pending = _change(
        _field(type: FieldType.checkbox),
        _checkbox(true, unknownFields: extensions),
        FieldType.text,
      );
      final ReclassificationResult resolved = pending.resolve();
      expect((resolved.value! as TextValue).text, 'Ja');
      expect(resolved.value!.unknownFields, extensions);
    });

    test('resolve keeps value extensions for a multiline projection', () {
      final ReclassificationResult pending = _change(
        _field(type: FieldType.checkbox),
        _checkbox(false, unknownFields: extensions),
        FieldType.multiline,
      );
      final ReclassificationResult resolved = pending.resolve();
      expect((resolved.value! as MultilineValue).text, 'Nein');
      expect(resolved.value!.unknownFields, extensions);
    });

    test('resolve keeps value extensions for a proposed checkbox', () {
      final ReclassificationResult pending = _change(
        _field(),
        _text('Erika', unknownFields: extensions),
        FieldType.checkbox,
      );
      final ReclassificationResult resolved = pending.resolve();
      expect((resolved.value! as CheckboxValue).checked, isFalse);
      expect(resolved.value!.unknownFields, extensions);
      final Document document = _documentFor(resolved);
      final Document reopened = Document.fromJson(document.toJson());
      expect(reopened.values.values.single.unknownFields, extensions);
    });

    test('clearing a signature keeps validation extensions', () {
      final ReclassificationResult result = _change(
        _field(
          type: FieldType.signature,
          validation: FieldValidation.warning(
            WarningCode.overflow,
            'FLD-001',
            unknownFields: extensions,
          ),
        ),
        _signature(_assetId),
        FieldType.text,
      );
      expect(result.field.validation.isOk, isTrue);
      expect(result.field.validation.unknownFields, extensions);
    });

    test('the persisted roundtrip keeps validation extensions', () {
      final ReclassificationResult result = _change(
        _field(validation: okWithExtensions()),
        _text('keine Zahl'),
        FieldType.number,
      );
      final Document document = _documentFor(result);
      final Document reopened = Document.fromJson(document.toJson());
      expect(reopened.fields.single.validation.unknownFields, extensions);
      final RevisionContent persisted = RevisionContent.fromJson(
        RevisionContent.fromDocument(reopened).toJson(),
      );
      expect(persisted.fields.single.validation.unknownFields, extensions);
    });
  });

  group('persisted blocking error and warning', () {
    test(
      'unparseable number persists a blocking NUM-001 error with content',
      () {
        final ReclassificationResult result = _change(
          _field(),
          _text('keine Zahl'),
          FieldType.number,
        );
        expect(result.value, isA<IncompatibleValue>());
        expect(result.field.validation, FieldValidation.error('NUM-001'));
        expect(result.field.validation.isError, isTrue);
        expect(result.field.validation.warningCode, isNull);
        expect(result.errorCode, 'NUM-001');
        _expectAggregateCompatible(result);
      },
    );

    test(
      'unparseable date persists a blocking DATE-002 error with content',
      () {
        final ReclassificationResult result = _change(
          _field(),
          _text('31.02.2025'),
          FieldType.date,
        );
        expect(result.value, isA<IncompatibleValue>());
        expect(result.field.validation, FieldValidation.error('DATE-002'));
        expect(result.field.validation.isError, isTrue);
        expect(result.errorCode, 'DATE-002');
        _expectAggregateCompatible(result);
      },
    );

    test(
      'NUM-001 survives the document and revision persistence roundtrip',
      () {
        final ReclassificationResult result = _change(
          _field(),
          _text('keine Zahl'),
          FieldType.number,
        );
        final Document document = _documentFor(result);
        final Document reopened = Document.fromJson(document.toJson());
        final ConfirmedField reopenedField = reopened.fields.single;
        expect(reopenedField.validation, FieldValidation.error('NUM-001'));
        final IncompatibleValue reopenedValue =
            reopened.values[reopenedField.id]! as IncompatibleValue;
        expect(reopenedValue.preservedText, 'keine Zahl');

        final RevisionContent content = RevisionContent.fromDocument(reopened);
        final RevisionContent persisted = RevisionContent.fromJson(
          content.toJson(),
        );
        final ConfirmedField persistedField = persisted.fields.single;
        expect(persistedField.validation, FieldValidation.error('NUM-001'));
        final IncompatibleValue persistedValue =
            persisted.values[persistedField.id]! as IncompatibleValue;
        expect(persistedValue.preservedText, 'keine Zahl');
      },
    );

    test(
      'DATE-002 survives the document and revision persistence roundtrip',
      () {
        final ReclassificationResult result = _change(
          _field(),
          _text('31.02.2025'),
          FieldType.date,
        );
        final Document document = _documentFor(result);
        final RevisionContent persisted = RevisionContent.fromJson(
          RevisionContent.fromDocument(Document.fromJson(document.toJson()))
              .toJson(),
        );
        final ConfirmedField field = persisted.fields.single;
        expect(field.validation, FieldValidation.error('DATE-002'));
        final IncompatibleValue value =
            persisted.values[field.id]! as IncompatibleValue;
        expect(value.preservedText, '31.02.2025');
      },
    );

    test('the incompatible-content warning survives for checkbox content', () {
      final ReclassificationResult result = _change(
        _field(),
        _text('Erika'),
        FieldType.checkbox,
      );
      expect(
        result.field.validation,
        FieldValidation.warning(WarningCode.incompatibleContent, 'FLD-002'),
      );
      final Document document = _documentFor(result);
      final RevisionContent persisted = RevisionContent.fromJson(
        RevisionContent.fromDocument(Document.fromJson(document.toJson()))
            .toJson(),
      );
      expect(
        persisted.fields.single.validation,
        FieldValidation.warning(WarningCode.incompatibleContent, 'FLD-002'),
      );
      expect(persisted.values.values.single, isA<IncompatibleValue>());
    });

    test('resolving a parse failure clears the persisted error', () {
      final ReclassificationResult resolved = _change(
        _field(),
        _text('keine Zahl'),
        FieldType.number,
      ).resolve();
      expect(resolved.field.validation, FieldValidation.ok);
      expect(resolved.value, isNull);
      final Document document = _documentFor(resolved);
      final RevisionContent persisted = RevisionContent.fromJson(
        RevisionContent.fromDocument(Document.fromJson(document.toJson()))
            .toJson(),
      );
      expect(persisted.fields.single.validation, FieldValidation.ok);
      expect(persisted.values, isEmpty);
    });
  });

  group('full type matrix', () {
    final Map<FieldType, FieldValue> sources = <FieldType, FieldValue>{
      FieldType.text: _text('Müller'),
      FieldType.number: _number('42', '42'),
      FieldType.date: _date('2025-12-31'),
      FieldType.checkbox: _checkbox(true),
      FieldType.multiline: _multiline('a\nb'),
      FieldType.signature: _signature(_assetId),
    };

    for (final FieldType from in FieldType.values) {
      for (final FieldType to in FieldType.values) {
        test('${from.wireName} to ${to.wireName} yields a valid state', () {
          final ConfirmedField field = _field(type: from);
          final FieldValue source = sources[from]!;
          final ReclassificationResult result = _change(field, source, to);

          expect(result.field.type, to);
          if (from == to) {
            expect(result.value, same(source));
          }
          _expectAggregateCompatible(result);
          expect(() => _documentFor(result), returnsNormally);

          if (result.value != null && result.value is! IncompatibleValue) {
            expect(result.value!.type, to);
          }
          if (result.blocksExport) {
            expect(result.requiresUserAction, isTrue);
          }

          final ReclassificationResult resolved = result.resolve();
          _expectAggregateCompatible(resolved);
          expect(resolved.blocksExport, isFalse);
          expect(() => _documentFor(resolved), returnsNormally);
        });
      }
    }
  });
}
