// T081 public date parser tests.
//
// These are host-VM tests (evidence class NONE). They pin the extracted T019
// German and canonical date grammar exposed as `parseGermanDate`:
//   * German `d.m.yyyy` accepts one or two day/month digits and four year
//     digits, with or without leading zeros, and returns zero-padded
//     `yyyy-mm-dd`;
//   * canonical `yyyy-mm-dd` from date → text parses unchanged when it is a
//     real calendar date;
//   * Gregorian leap rules are enforced (`2000` is a leap year, `1900` is not);
//   * impossible calendar values are `DATE-002`, not malformed;
//   * malformed, empty, and partially matching input is `DATE-001`;
//   * outer whitespace is trimmed, failures carry no canonical value, and no
//     input throws;
//   * reclassification delegates to the same parser with no behavior change.

import 'package:feldexa_core/feldexa_core.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _at([int minute = 0]) => DateTime.utc(2026, 11, 14, 12, minute);

Rect _rect() => Rect.fromLTWH(10, 20, 120, 18);

ConfirmedField _field({
  FieldType type = FieldType.text,
  FieldValidation validation = FieldValidation.ok,
}) {
  return ConfirmedField(
    id: '1b4e28ba-2fa1-4d3b-a1f8-6f2a3c4d5e6f',
    pageIndex: 0,
    rect: _rect(),
    type: type,
    provenance: Provenance.user,
    label: 'Feld 1',
    order: 0,
    createdAt: _at(),
    updatedAt: _at(),
    validation: validation,
  );
}

TextValue _text(String text) => TextValue(text: text, lastEditedAt: _at());

ReclassificationResult _change(
  ConfirmedField field,
  FieldValue? value,
  FieldType newType,
) {
  return reclassifyField(
    field: field,
    value: value,
    newType: newType,
    updatedAt: _at(5),
  );
}

void _expectSuccess(String raw, String canonical) {
  final DateParseResult result = parseGermanDate(raw);
  expect(result.isSuccess, isTrue, reason: raw);
  expect(result.errorCode, isNull, reason: raw);
  expect(result.canonical, canonical, reason: raw);
}

void _expectFailure(String raw, String errorCode) {
  final DateParseResult result = parseGermanDate(raw);
  expect(result.isSuccess, isFalse, reason: raw);
  expect(result.canonical, isNull, reason: raw);
  expect(result.errorCode, errorCode, reason: raw);
}

void main() {
  group('German dates', () {
    test('accepts one or two day and month digits', () {
      _expectSuccess('1.1.2025', '2025-01-01');
      _expectSuccess('01.01.2025', '2025-01-01');
      _expectSuccess('31.12.2025', '2025-12-31');
      _expectSuccess('9.2.2025', '2025-02-09');
    });

    test('pads every canonical part to 4-2-2', () {
      _expectSuccess('1.2.2025', '2025-02-01');
      _expectSuccess('01.2.2025', '2025-02-01');
      _expectSuccess('1.02.2025', '2025-02-01');
      _expectSuccess('01.02.2025', '2025-02-01');
    });
  });

  group('canonical dates', () {
    test('accepts the form emitted by date to text', () {
      _expectSuccess('2025-02-28', '2025-02-28');
      _expectSuccess('2025-12-31', '2025-12-31');
      _expectSuccess('2024-02-29', '2024-02-29');
    });

    test('rejects an impossible canonical date as DATE-002', () {
      _expectFailure('2025-02-29', 'DATE-002');
      _expectFailure('2025-04-31', 'DATE-002');
      _expectFailure('2025-00-01', 'DATE-002');
      _expectFailure('2025-13-01', 'DATE-002');
    });
  });

  group('leap years', () {
    test('accepts a real leap day', () {
      _expectSuccess('29.02.2024', '2024-02-29');
      _expectSuccess('29.02.2000', '2000-02-29');
    });

    test('rejects 29 February outside a leap year as DATE-002', () {
      _expectFailure('29.02.2023', 'DATE-002');
      _expectFailure('29.02.1900', 'DATE-002');
    });
  });

  group('impossible calendar dates', () {
    test('rejects impossible days and months as DATE-002', () {
      for (final String raw in <String>[
        '31.04.2025',
        '31.06.2025',
        '00.01.2025',
        '01.00.2025',
        '32.01.2025',
        '31.13.2025',
      ]) {
        _expectFailure(raw, 'DATE-002');
      }
    });

    test('DATE-002 failures carry no canonical value', () {
      final DateParseResult result = parseGermanDate('31.04.2025');
      expect(result.canonical, isNull);
      expect(result.errorCode, 'DATE-002');
      expect(result.isSuccess, isFalse);
    });
  });

  group('malformed input', () {
    test('rejects malformed and partially matching dates as DATE-001', () {
      for (final String raw in <String>[
        '',
        '   ',
        '\t\n',
        '31.12.25',
        '2025-2-9',
        '31/12/2025',
        '31.12.2025 extra',
        '2025-02-29x',
        '1.1.20250',
      ]) {
        _expectFailure(raw, 'DATE-001');
      }
    });

    test('DATE-001 failures carry no canonical value', () {
      final DateParseResult result = parseGermanDate('31/12/2025');
      expect(result.canonical, isNull);
      expect(result.errorCode, 'DATE-001');
      expect(result.isSuccess, isFalse);
    });
  });

  group('whitespace and invariants', () {
    test('trims outer whitespace around German and canonical input', () {
      _expectSuccess(' 1.2.2025 ', '2025-02-01');
      _expectSuccess('\t31.12.2025\n', '2025-12-31');
      _expectSuccess(' 2025-02-28 ', '2025-02-28');
    });

    test('successful canonical output is always 4-2-2', () {
      const List<String> inputs = <String>[
        '1.1.2025',
        '9.2.2025',
        '29.02.2024',
        '31.12.2025',
        '2025-02-28',
      ];
      final RegExp canonicalPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
      for (final String input in inputs) {
        final DateParseResult result = parseGermanDate(input);
        expect(result.isSuccess, isTrue, reason: input);
        expect(
          canonicalPattern.hasMatch(result.canonical!),
          isTrue,
          reason: input,
        );
      }
    });

    test('failure and success states are mutually exclusive', () {
      final DateParseResult success = parseGermanDate('1.1.2025');
      expect(success.isSuccess, isTrue);
      expect(success.errorCode, isNull);
      expect(success.canonical, isNotNull);

      final DateParseResult malformed = parseGermanDate('Datum fehlt');
      expect(malformed.isSuccess, isFalse);
      expect(malformed.canonical, isNull);
      expect(malformed.errorCode, 'DATE-001');
    });

    test('never throws for any String input', () {
      const List<String> samples = <String>[
        '',
        '   ',
        '\t\n',
        '1.1.2025',
        '01.01.2025',
        '31.12.2025',
        '29.02.2024',
        '29.02.2023',
        '29.02.2000',
        '29.02.1900',
        '31.04.2025',
        '00.01.2025',
        '32.01.2025',
        '31.13.2025',
        '2025-02-28',
        '2025-02-29',
        '2025-2-9',
        '31.12.25',
        '31/12/2025',
        '31.12.2025 extra',
        '2025-02-29x',
        '1.1.20250',
        '0000-01-01',
        '9999-12-31',
        'Datum fehlt',
        'Müllerstraße 4711',
        '🔥',
      ];
      for (final String sample in samples) {
        expect(() => parseGermanDate(sample), returnsNormally, reason: sample);
      }
    });
  });

  group('reclassification delegation', () {
    test('text to date parses 1.2.2025 into the canonical date', () {
      final ReclassificationResult result = _change(
        _field(),
        _text('1.2.2025'),
        FieldType.date,
      );
      expect(result.kind, ReclassificationKind.compatible);
      expect(result.errorCode, isNull);
      expect((result.value! as DateValue).canonical, '2025-02-01');
    });

    test('a canonical projection still parses', () {
      final ReclassificationResult toText = _change(
        _field(type: FieldType.date),
        DateValue(canonical: '2025-02-28', lastEditedAt: _at()),
        FieldType.text,
      );
      expect((toText.value! as TextValue).text, '2025-02-28');

      final ReclassificationResult backToDate = _change(
        _field(),
        toText.value,
        FieldType.date,
      );
      expect((backToDate.value! as DateValue).canonical, '2025-02-28');
    });

    test('malformed input keeps dateParseFailed and DATE-001', () {
      final ReclassificationResult result = _change(
        _field(),
        _text('31/12/2025'),
        FieldType.date,
      );
      expect(result.kind, ReclassificationKind.resolutionRequired);
      expect(result.reason, ReclassificationReason.dateParseFailed);
      expect(result.errorCode, 'DATE-001');
      expect(result.preservedContent, '31/12/2025');
      expect(result.field.validation.isError, isTrue);
      expect(result.field.validation.errorCode, 'DATE-001');
      expect(result.value, isA<IncompatibleValue>());
    });

    test('impossible input keeps dateParseFailed and DATE-002', () {
      final ReclassificationResult result = _change(
        _field(),
        _text('31.04.2025'),
        FieldType.date,
      );
      expect(result.kind, ReclassificationKind.resolutionRequired);
      expect(result.reason, ReclassificationReason.dateParseFailed);
      expect(result.errorCode, 'DATE-002');
      expect(result.preservedContent, '31.04.2025');
      expect(result.field.validation.isError, isTrue);
      expect(result.field.validation.errorCode, 'DATE-002');
      expect(result.value, isA<IncompatibleValue>());
    });

    test('date to text clears the error and keeps canonical content', () {
      final ConfirmedField field = _field(
        type: FieldType.date,
        validation: FieldValidation.error('DATE-001'),
      );
      final ReclassificationResult result = _change(
        field,
        DateValue(canonical: '2025-12-31', lastEditedAt: _at()),
        FieldType.text,
      );
      expect((result.value! as TextValue).text, '2025-12-31');
      expect(result.field.validation, FieldValidation.ok);
      expect(result.errorCode, isNull);
      expect(result.kind, ReclassificationKind.compatible);
    });
  });
}
