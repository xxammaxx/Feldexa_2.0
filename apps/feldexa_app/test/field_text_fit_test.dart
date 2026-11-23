// T086C field-text fit unit tests (FLD-001 reachability, issue #281).
//
// Evidence class: NONE. Pure host-VM unit tests with a synthetic advance
// measure. They use the normative layout rules from
// `contracts/export-plan.md` §2.2/§3.1 (1.5 pt padding, font size
// `clamp(0.6 × rect.height, 7.0, 12.0)`, line height `1.2 × fontSizePt`, greedy
// word wrap at spaces, no long-word breaking) and make no font, Android,
// device, or visual claim. The synthetic measure is 0.5 em per rune, so every
// expectation below is exact arithmetic and independent of the bundled font.

@TestOn('vm')
library;

import 'package:feldexa_app/features/fill/field_text_fit.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter_test/flutter_test.dart';

/// Deterministic stand-in for real glyph advances: 0.5 em per rune.
double _syntheticMeasure(String text, double fontSizePt) {
  return text.runes.length * fontSizePt * 0.5;
}

core.Rect _rect(double width, double height) {
  return core.Rect.fromLTWH(0, 0, width, height);
}

bool _overflows(
  core.FieldType type,
  core.Rect rect,
  String text, {
  double Function(String text, double fontSizePt) measure = _syntheticMeasure,
}) {
  return fieldTextOverflows(
    type: type,
    rect: rect,
    text: text,
    measure: measure,
  );
}

void main() {
  group('font metrics follow the export-plan §2.2 clamps', () {
    test('font size is 0.6 × height clamped to 7.0 … 12.0 pt', () {
      expect(fieldFontSizePt(20), closeTo(12.0, 1e-9));
      expect(fieldFontSizePt(30), closeTo(12.0, 1e-9));
      expect(fieldFontSizePt(18), closeTo(10.8, 1e-9));
      expect(fieldFontSizePt(10), closeTo(7.0, 1e-9));
      expect(fieldFontSizePt(4), closeTo(7.0, 1e-9));
    });

    test(
      'line height is 1.2 × font size and the baseline stays in the field',
      () {
        expect(fieldLineHeightPt(12.0), closeTo(14.4, 1e-9));
        expect(fieldLineHeightPt(7.0), closeTo(8.4, 1e-9));
        expect(fieldBaselineFromTopPt(12.0), closeTo(11.1, 1e-9));
        expect(fieldBaselineFromTopPt(7.0), closeTo(7.1, 1e-9));
      },
    );

    test('the available box removes 1.5 pt on every side', () {
      final core.Rect rect = _rect(100, 20);
      expect(fieldAvailableWidthPt(rect), closeTo(97.0, 1e-9));
      expect(fieldAvailableHeightPt(rect), closeTo(17.0, 1e-9));
    });
  });

  group('single-line fields (text, number, date)', () {
    test('a text that fits the available width does not overflow', () {
      // 5 runes × 0.5 em × 12 pt = 30 pt ≤ 97 pt.
      expect(_overflows(core.FieldType.text, _rect(100, 20), 'Erika'), isFalse);
      expect(
        _overflows(core.FieldType.number, _rect(100, 20), '12,5'),
        isFalse,
      );
      expect(
        _overflows(core.FieldType.date, _rect(100, 20), '31.12.2025'),
        isFalse,
      );
    });

    test('a text wider than the available width overflows', () {
      // 17 runes × 0.5 em × 12 pt = 102 pt > 97 pt.
      expect(
        _overflows(core.FieldType.text, _rect(100, 20), 'Müller-Lüdenscheid'),
        isTrue,
      );
    });

    test('the exact available width is still accepted', () {
      // 97 pt / (0.5 em × 12 pt) = 16.16 runes; 16 runes = 96 pt fits.
      expect(
        _overflows(core.FieldType.text, _rect(100, 20), 'A' * 16),
        isFalse,
      );
    });

    test('a line break cannot be rendered by a single-line field', () {
      expect(_overflows(core.FieldType.text, _rect(1000, 20), 'a\nb'), isTrue);
    });
  });

  group('multiline fields', () {
    test('one line fits, two lines exceed a one-line-high box', () {
      // height 20 → available 17 pt, line height 14.4 pt → one line only.
      expect(
        _overflows(core.FieldType.multiline, _rect(100, 20), 'a'),
        isFalse,
      );
      expect(
        _overflows(core.FieldType.multiline, _rect(100, 20), 'a\nb'),
        isTrue,
      );
    });

    test('greedy word wrap keeps as many words per line as fit', () {
      // width 200 → available 197 pt; each word is 20 runes = 120 pt.
      final String word = 'w' * 20;
      final String twoWords = '$word $word'; // 241 pt > 197 → two lines.
      final String oneLine = '$word ${'x' * 5}'; // 120 + 30 + space = 156 pt.
      // height 60 → available 57 pt, line height 14.4 → three lines fit.
      expect(
        _overflows(core.FieldType.multiline, _rect(200, 60), oneLine),
        isFalse,
      );
      expect(
        _overflows(core.FieldType.multiline, _rect(200, 60), twoWords),
        isFalse,
      );
      expect(
        _overflows(
          core.FieldType.multiline,
          _rect(200, 60),
          List<String>.filled(5, word).join(' '),
        ),
        isTrue,
      );
    });

    test('a single word wider than the line overflows and is not broken', () {
      // 30 runes = 180 pt > 97 pt, and it cannot be wrapped.
      expect(
        _overflows(core.FieldType.multiline, _rect(100, 200), 'x' * 30),
        isTrue,
      );
    });

    test('an explicit empty line counts as a rendered line', () {
      // height 20 → one line fits, so 'a\n' is already two lines.
      expect(
        _overflows(core.FieldType.multiline, _rect(100, 20), 'a\n'),
        isTrue,
      );
    });
  });

  group('fields without clipable text and degenerate boxes', () {
    test('checkbox and signature never report a text overflow', () {
      expect(
        _overflows(core.FieldType.checkbox, _rect(4, 4), 'x' * 500),
        isFalse,
      );
      expect(
        _overflows(core.FieldType.signature, _rect(4, 4), 'x' * 500),
        isFalse,
      );
    });

    test('empty and whitespace-only text never overflows', () {
      expect(_overflows(core.FieldType.text, _rect(4, 4), ''), isFalse);
      expect(_overflows(core.FieldType.text, _rect(4, 4), '   '), isFalse);
      expect(
        _overflows(core.FieldType.multiline, _rect(4, 4), '\n\n'),
        isFalse,
      );
    });

    test('a box with no usable inner area overflows any text', () {
      expect(_overflows(core.FieldType.text, _rect(2, 20), 'a'), isTrue);
      expect(_overflows(core.FieldType.multiline, _rect(100, 2), 'a'), isTrue);
    });

    test('a box shorter than the baseline overflows any text', () {
      // height 6 → font size 7 pt, baseline 7.1 pt > 6 pt.
      expect(_overflows(core.FieldType.text, _rect(100, 6), 'a'), isTrue);
    });
  });

  group('the measure callback is the single metrics seam', () {
    test('a wider measure flips the same text from fitting to overflowing', () {
      final core.Rect rect = _rect(100, 20);
      final String text = 'ABCDEFGHIJ';
      expect(_overflows(core.FieldType.text, rect, text), isFalse);
      expect(
        _overflows(
          core.FieldType.text,
          rect,
          text,
          measure: (String value, double fontSizePt) =>
              value.runes.length * fontSizePt * 1.0,
        ),
        isTrue,
      );
    });
  });
}
