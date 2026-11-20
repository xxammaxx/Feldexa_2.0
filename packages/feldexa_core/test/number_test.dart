// T080 public number parser tests.
//
// These are host-VM tests (evidence class NONE). They pin the extracted T019
// German and canonical number grammar exposed as `parseGermanNumber`:
//   * canonical dot decimals are returned unchanged, including `1.23`,
//     `1.2345`, and `12.34`, which are not valid German groupings;
//   * a German comma decimal becomes a dot decimal and a valid German grouping
//     wins over the canonical reading of the same dots;
//   * exponent notation, a leading plus, internal spaces, repeated signs or
//     separators, and empty fractions are rejected;
//   * outer whitespace is trimmed, the sign and fraction digits stay verbatim,
//     leading zeros are not rewritten, and nothing is converted to `num`;
//   * no input throws.

import 'package:feldexa_core/feldexa_core.dart';
import 'package:flutter_test/flutter_test.dart';

const String _longDigits = '123456789012345678901234567890';

void main() {
  group('canonical numbers', () {
    test('accepts canonical forms unchanged', () {
      expect(parseGermanNumber('0'), '0');
      expect(parseGermanNumber('-12'), '-12');
      expect(parseGermanNumber('12.5'), '12.5');
      expect(parseGermanNumber('-0.75'), '-0.75');
      expect(parseGermanNumber('007'), '007');
      expect(parseGermanNumber(_longDigits), _longDigits);
    });

    test('accepts dot decimals that are not valid German groupings', () {
      expect(parseGermanNumber('1.23'), '1.23');
      expect(parseGermanNumber('1.2345'), '1.2345');
      expect(parseGermanNumber('12.34'), '12.34');
    });

    test('keeps the sign and leading zeros verbatim', () {
      expect(parseGermanNumber('-007'), '-007');
      expect(parseGermanNumber('-0.7500'), '-0.7500');
    });
  });

  group('German decimal numbers', () {
    test('converts a comma decimal to the canonical dot form', () {
      expect(parseGermanNumber('12,5'), '12.5');
      expect(parseGermanNumber('-0,75'), '-0.75');
      expect(parseGermanNumber('0,50'), '0.50');
    });

    test('rejects a missing integer or fraction part', () {
      expect(parseGermanNumber('1,'), isNull);
      expect(parseGermanNumber(',5'), isNull);
      expect(parseGermanNumber('1,,2'), isNull);
    });
  });

  group('German grouped numbers', () {
    test('removes grouping dots', () {
      expect(parseGermanNumber('1.234'), '1234');
      expect(parseGermanNumber('1.234,56'), '1234.56');
      expect(parseGermanNumber('-1.234.567,89'), '-1234567.89');
    });

    test('a valid grouping wins over a canonical dot decimal', () {
      expect(parseGermanNumber('1.234'), '1234');
      expect(parseGermanNumber('-999.999'), '-999999');
      expect(parseGermanNumber('-0.750'), '-0750');
    });

    test('rejects a malformed grouping', () {
      expect(parseGermanNumber('1.234.56'), isNull);
      expect(parseGermanNumber('1.2345.678'), isNull);
      expect(parseGermanNumber('1.234.5678'), isNull);
    });
  });

  group('invalid input', () {
    test('rejects exponent, plus, internal space, and repeated signs', () {
      expect(parseGermanNumber('1e3'), isNull);
      expect(parseGermanNumber('+1'), isNull);
      expect(parseGermanNumber('1 234'), isNull);
      expect(parseGermanNumber('--1'), isNull);
      expect(parseGermanNumber('1.2.3'), isNull);
    });

    test('rejects empty and whitespace-only input', () {
      expect(parseGermanNumber(''), isNull);
      expect(parseGermanNumber('   '), isNull);
      expect(parseGermanNumber('\t\n'), isNull);
    });
  });

  group('whitespace and canonical output', () {
    test('trims outer whitespace before parsing', () {
      expect(parseGermanNumber(' 42 '), '42');
      expect(parseGermanNumber('\t1.234,56\n'), '1234.56');
    });

    test('returns no comma, exponent, or grouping-dot ambiguity', () {
      const List<String> inputs = <String>[
        '12,5',
        '1.234',
        '1.234,56',
        '-1.234.567,89',
      ];
      for (final String input in inputs) {
        final String? canonical = parseGermanNumber(input);
        expect(canonical, isNotNull, reason: input);
        expect(canonical, isNot(contains(',')), reason: input);
        expect(canonical, isNot(contains('e')), reason: input);
        expect(canonical, isNot(contains('E')), reason: input);
        expect(
          RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(canonical!),
          isTrue,
          reason: input,
        );
      }
    });

    test('never converts to num and preserves sign and fraction digits', () {
      expect(parseGermanNumber('007'), '007');
      expect(parseGermanNumber('-0.75'), '-0.75');
      expect(parseGermanNumber('-0,750'), '-0.750');
      expect(parseGermanNumber('0,50'), '0.50');
      expect(parseGermanNumber(_longDigits), _longDigits);
    });

    test('never throws for any String input', () {
      const List<String> samples = <String>[
        '',
        '   ',
        '0',
        '-12',
        '12.5',
        '-0.75',
        '007',
        '1.23',
        '1.2345',
        '12.34',
        '12,5',
        '-0,75',
        '0,50',
        '1.234',
        '1.234,56',
        '-1.234.567,89',
        '1e3',
        '+1',
        '1 234',
        '--1',
        '1.2.3',
        '1.234.56',
        '1,',
        ',5',
        '1,,2',
        '0x10',
        'NaN',
        'Infinity',
        '  42  ',
      ];
      for (final String sample in samples) {
        expect(
          () => parseGermanNumber(sample),
          returnsNormally,
          reason: sample,
        );
      }
    });
  });
}
