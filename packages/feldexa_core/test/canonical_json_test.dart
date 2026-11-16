// T017 canonical JSON tests.
//
// These are host-VM tests (evidence class NONE). They pin
// `data-model.md` §6 and `contracts/storage-format.md` §2.4:
//   * sorted object keys, no insignificant whitespace, UTF-8;
//   * ISO-8601 UTC timestamps with millisecond precision;
//   * numbers without trailing zeros and normalized negative zero;
//   * fail-closed rejection of unsupported and non-finite values.

import 'dart:convert';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canonical JSON encoding', () {
    test('sorts keys recursively, omits whitespace, and keeps Unicode', () {
      final Map<String, Object?> value = <String, Object?>{
        'z': 1,
        'a': <String, Object?>{'d': 'Grüße', 'c': true},
        'list': <Object?>[
          <String, Object?>{'b': 2.0, 'a': 1},
        ],
      };

      const String expected =
          '{"a":{"c":true,"d":"Grüße"},"list":[{"a":1,"b":2}],"z":1}';

      expect(canonicalJsonEncode(value), expected);
      expect(canonicalJsonBytes(value), utf8.encode(expected));
    });

    test('does not mutate the input map order or the input lists', () {
      final Map<String, Object?> value = <String, Object?>{'b': 1, 'a': 2};
      final List<Object?> list = <Object?>[3, 1, 2];
      value['list'] = list;

      canonicalJsonEncode(value);

      expect(value.keys.toList(), <String>['b', 'a', 'list']);
      expect(list, <Object?>[3, 1, 2]);
    });

    test('normalizes integral doubles, trailing zeros, and negative zero', () {
      expect(
        canonicalJsonEncode(<String, Object?>{
          'a': 1.0,
          'b': 1.50,
          'c': -0.0,
          'd': 0.1,
          'e': 1e300,
        }),
        '{"a":1,"b":1.5,"c":0,"d":0.1,"e":1e+300}',
      );
      final Map<String, Object?> normalized =
          canonicalJsonValue(<String, Object?>{'a': 1.0})!
              as Map<String, Object?>;
      expect(normalized['a'], isA<int>());
    });

    test('uses Dart shortest form at exponent and 2^53 thresholds', () {
      expect(
        canonicalJsonEncode(<String, Object?>{
          'a': 1e-7,
          'b': -1e-7,
          'c': 1e-6,
          'd': 1e20,
          'e': 1e21,
          'f': 9007199254740992.0,
          'g': 9007199254740994.0,
          'h': 5e-324,
        }),
        '{"a":1e-7,"b":-1e-7,"c":0.000001,'
        '"d":100000000000000000000.0,"e":1e+21,'
        '"f":9007199254740992,"g":9007199254740994.0,"h":5e-324}',
      );
    });

    test('escapes quotes, backslashes, and control characters', () {
      expect(canonicalJsonEncode('a"b\\c\n'), '"a\\"b\\\\c\\n"');
      expect(canonicalJsonEncode('äöüß'), '"äöüß"');
    });

    test('rejects non-finite numbers', () {
      expect(
        () => canonicalJsonEncode(<String, Object?>{'a': double.nan}),
        throwsArgumentError,
      );
      expect(
        () => canonicalJsonEncode(<String, Object?>{'a': double.infinity}),
        throwsArgumentError,
      );
      expect(
        () => canonicalJsonEncode(<String, Object?>{
          'a': double.negativeInfinity,
        }),
        throwsArgumentError,
      );
    });

    test('rejects unsupported types and non-string map keys', () {
      expect(
        () => canonicalJsonEncode(<String, Object?>{
          'when': DateTime.utc(2026, 11, 14),
        }),
        throwsArgumentError,
      );
      expect(
        () => canonicalJsonEncode(<Object?, Object?>{1: 'one'}),
        throwsArgumentError,
      );
      expect(
        () => canonicalJsonEncode(<String, Object?>{
          'set': <int>{1},
        }),
        throwsArgumentError,
      );
    });

    test('rejects cyclic object graphs instead of overflowing', () {
      final Map<String, Object?> cycle = <String, Object?>{};
      cycle['self'] = cycle;
      expect(() => canonicalJsonEncode(cycle), throwsArgumentError);

      final List<Object?> list = <Object?>[];
      list.add(list);
      expect(() => canonicalJsonEncode(list), throwsArgumentError);
    });

    test('is deterministic for the same logical tree', () {
      final Map<String, Object?> first = <String, Object?>{
        'b': <String, Object?>{'y': 2, 'x': 1},
        'a': true,
      };
      final Map<String, Object?> second = <String, Object?>{
        'a': true,
        'b': <String, Object?>{'x': 1, 'y': 2},
      };
      expect(canonicalJsonEncode(first), canonicalJsonEncode(second));
    });
  });

  group('canonical UTC timestamps', () {
    test('serializes UTC with millisecond precision and truncates micros', () {
      final DateTime value = DateTime.utc(2026, 11, 14, 17, 3, 4, 123, 456);
      expect(canonicalUtcTimestamp(value), '2026-11-14T17:03:04.123Z');
    });

    test('rejects local timestamps', () {
      expect(
        () => canonicalUtcTimestamp(DateTime(2026, 11, 14, 17)),
        throwsArgumentError,
      );
    });

    test('parses UTC ISO-8601 and rejects local or malformed values', () {
      expect(
        parseCanonicalUtcTimestamp('2026-11-14T17:03:04.123Z'),
        DateTime.utc(2026, 11, 14, 17, 3, 4, 123),
      );
      expect(
        () => parseCanonicalUtcTimestamp('2026-11-14T17:03:04'),
        throwsFormatException,
      );
      expect(() => parseCanonicalUtcTimestamp(42), throwsFormatException);
      expect(
        () => parseCanonicalUtcTimestamp(DateTime.utc(2026)),
        throwsFormatException,
      );
    });
  });
}
