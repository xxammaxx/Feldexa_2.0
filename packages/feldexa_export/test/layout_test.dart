// T103 export layout tests.
//
// These are host-VM tests (`NONE` evidence). They pin `contracts/export-plan.md`
// §2.2 and §3: the font-size clamp, line height and baseline formulas, the
// 1.5 pt padding boundary, single-line and multiline line breaking, German
// decimal/date display, trailing-space trimming, glyph coverage, the checkbox
// mark, and the signature `contain` fit. Widths are measured with the bundled
// Noto Sans advance table, so the assertions fail if the metrics, the padding,
// or the clamp regress. They cannot prove PDF rendering (T108/T109).
@TestOn('vm')
library;

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_export/feldexa_export.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/export_fixtures.dart';

late final ExportFontMetrics _metrics;
late final ExportLayout _layout;

void main() {
  setUpAll(() {
    _metrics = loadBundledMetrics();
    _layout = ExportLayout(metrics: _metrics);
  });

  group('bundled font metrics', () {
    test('exposes the Noto Sans contract of the export plan', () {
      expect(_metrics.family, 'NotoSans');
      expect(_metrics.metricsVersion, 'noto-sans-2.013-v1');
      expect(_metrics.regularAsset, 'assets/fonts/NotoSans-Regular.ttf');
      expect(_metrics.boldAsset, 'assets/fonts/NotoSans-Bold.ttf');
      expect(_metrics.unitsPerEm, 1000);

      final ExportFont font = _metrics.toExportFont();
      expect(font.family, 'NotoSans');
      expect(font.regularAsset, _metrics.regularAsset);
      expect(font.boldAsset, _metrics.boldAsset);
      expect(font.metricsVersion, _metrics.metricsVersion);
    });

    test('covers every German and typographic codepoint of the contract', () {
      const String german = 'äöüßÄÖÜ€„“”’–—…';
      for (final int rune in german.runes) {
        expect(
          _metrics.coversRune(rune),
          isTrue,
          reason: 'U+${rune.toRadixString(16)} must be covered',
        );
      }
      expect(_metrics.missingRunes('Müller-Lüdenscheidt'), isEmpty);
      expect(_metrics.advanceWidthPt('Straße', 10), greaterThan(0));
    });

    test('measures the pinned advance sum at the planned font size', () {
      // `font_metrics_test` pins 'Müller-Lüdenscheidt' at 96.54 pt/10 pt.
      expect(
        _metrics.advanceWidthPt('Müller-Lüdenscheidt', 10),
        closeTo(96.54, 1e-9),
      );
      expect(
        _metrics.advanceWidthPt('Müller-Lüdenscheidt', 12),
        closeTo(96.54 * 1.2, 1e-9),
      );
    });

    test('reports an uncovered rune instead of substituting a glyph', () {
      const int emoji = 0x1F600;
      expect(_metrics.coversRune(emoji), isFalse);
      expect(_metrics.missingRunes('a\u{1F600}b'), <int>[emoji]);
      expect(
        () => _metrics.advanceWidthPt('a\u{1F600}', 10),
        throwsArgumentError,
      );
    });

    test('rejects a malformed metrics document', () {
      expect(() => ExportFontMetrics.decode('[]'), throwsFormatException);
      expect(
        () => ExportFontMetrics.decode('{"schemaVersion": 2}'),
        throwsFormatException,
      );
      expect(
        () => ExportFontMetrics.decode(
          '{"schemaVersion": 1, "family": "NotoSans",'
          ' "metricsVersion": "v", "fonts": {"400": {"unitsPerEm": 1000,'
          ' "asset": "a.ttf", "advances": {}}, "700": {"asset": "b.ttf"}}}',
        ),
        throwsFormatException,
      );
    });
  });

  group('single-line text layout', () {
    test('clamps the font size and derives line height and baseline', () {
      // 0.6 × height, clamped to 7.0 … 12.0 and rounded to 0.1.
      final Map<double, double> expected = <double, double>{
        10: 7.0,
        12.5: 7.5,
        13: 7.8,
        20: 12.0,
        30: 12.0,
      };
      for (final MapEntry<double, double> sample in expected.entries) {
        final ConfirmedField field = confirmedField(
          id: uuid(10),
          type: FieldType.text,
          rect: Rect.fromLTWH(100, 100, 300, sample.key),
        );
        final ExportFieldLayout result = _layout.layoutField(
          field: field,
          geometry: a4(),
          value: textValue('Hallo'),
        );
        final ExportTextOp op = result.op! as ExportTextOp;
        expect(op.fontSizePt, sample.value);
        expect(
          op.lineHeightPt,
          closeTo((1.2 * sample.value * 100).roundToDouble() / 100, 1e-12),
        );
        expect(op.baselineFromTopPt, closeTo(1.5 + 0.8 * sample.value, 1e-12));
        expect(op.baselineFromTopPt, lessThanOrEqualTo(field.rect.height));
      }
    });

    test('places one top-left line and maps the pdfRect from the geometry', () {
      final PageGeometry geometry = a4();
      final Rect rect = Rect.fromLTWH(148.5, 302, 210, 14.5);
      final ExportFieldLayout result = _layout.layoutField(
        field: confirmedField(
          id: uuid(11),
          type: FieldType.text,
          rect: rect,
          provenance: Provenance.template,
        ),
        geometry: geometry,
        value: textValue('Müller-Lüdenscheidt'),
      );
      final ExportTextOp op = result.op! as ExportTextOp;
      expect(op.lines, <String>['Müller-Lüdenscheidt']);
      expect(op.rect, rect);
      expect(op.pdfRect, geometry.displayRectToPdf(rect));
      expect(op.provenance, Provenance.template);
      expect(op.color, '#000000');
      expect(op.overflow, isFalse);
      expect(result.trimmedTrailingSpaceCount, 0);
    });

    test('keeps German characters and typographic punctuation intact', () {
      const String value = 'Größenänderung – „Prüfung“ 1.234,56 €';
      final ExportFieldLayout result = _layout.layoutField(
        field: confirmedField(
          id: uuid(12),
          type: FieldType.text,
          rect: Rect.fromLTWH(20, 20, 400, 20),
        ),
        geometry: a4(),
        value: textValue(value),
      );
      expect((result.op! as ExportTextOp).lines, <String>[value]);
      expect(result.warnings, isEmpty);
    });

    test('blocks only when the advance width exceeds width − 3.0 pt', () {
      const String value = 'Müller-Lüdenscheidt';
      const double fontHeight = 20;
      final double advanceWidth = _metrics.advanceWidthPt(value, 12);
      final ConfirmedField exact = confirmedField(
        id: uuid(13),
        type: FieldType.text,
        rect: Rect.fromLTWH(50, 50, advanceWidth + 3.0, fontHeight),
      );
      final ExportFieldLayout fitting = _layout.layoutField(
        field: exact,
        geometry: a4(),
        value: textValue(value),
      );
      expect(fitting.op, isNotNull);
      expect(fitting.warnings, isEmpty);

      final ExportFieldLayout overflowing = _layout.layoutField(
        field: exact.copyWith(
          rect: Rect.fromLTWH(50, 50, advanceWidth + 3.0 - 0.05, fontHeight),
        ),
        geometry: a4(),
        value: textValue(value),
      );
      expect(overflowing.op, isNull);
      expect(overflowing.warnings.single.code, 'EXP-001');
      expect(overflowing.warnings.single.reason, 'too_wide');
      expect(overflowing.warnings.single.fieldId, exact.id);
      expect(overflowing.warnings.single.pageIndex, 0);
      expect(overflowing.warnings.single.fieldLabel, exact.label);
    });

    test('formats numbers with a German decimal comma and no grouping', () {
      final ExportFieldLayout result = _layout.layoutField(
        field: confirmedField(
          id: uuid(14),
          type: FieldType.number,
          rect: Rect.fromLTWH(20, 20, 300, 20),
        ),
        geometry: a4(),
        value: numberValue('1234.56', rawGerman: '1.234,56'),
      );
      expect((result.op! as ExportTextOp).lines, <String>['1234,56']);

      final ExportFieldLayout integer = _layout.layoutField(
        field: confirmedField(
          id: uuid(15),
          type: FieldType.number,
          rect: Rect.fromLTWH(20, 20, 300, 20),
        ),
        geometry: a4(),
        value: numberValue('-42'),
      );
      expect((integer.op! as ExportTextOp).lines, <String>['-42']);
    });

    test('formats dates as dd.MM.yyyy', () {
      final ExportFieldLayout result = _layout.layoutField(
        field: confirmedField(
          id: uuid(16),
          type: FieldType.date,
          rect: Rect.fromLTWH(20, 20, 300, 20),
        ),
        geometry: a4(),
        value: dateValue('2026-01-05'),
      );
      expect((result.op! as ExportTextOp).lines, <String>['05.01.2026']);
    });

    test('trims trailing spaces and counts them', () {
      final ExportFieldLayout result = _layout.layoutField(
        field: confirmedField(
          id: uuid(17),
          type: FieldType.text,
          rect: Rect.fromLTWH(20, 20, 300, 20),
        ),
        geometry: a4(),
        value: textValue('Hallo   '),
      );
      expect((result.op! as ExportTextOp).lines, <String>['Hallo']);
      expect(result.trimmedTrailingSpaceCount, 3);
    });

    test('blocks a missing glyph with EXP-004 and draws no replacement', () {
      final ConfirmedField field = confirmedField(
        id: uuid(18),
        type: FieldType.text,
        rect: Rect.fromLTWH(20, 20, 300, 20),
        label: 'Name',
      );
      final ExportFieldLayout result = _layout.layoutField(
        field: field,
        geometry: a4(),
        value: textValue('Prüfung \u{1F600}'),
      );
      expect(result.op, isNull);
      final ExportValidationWarning warning = result.warnings.single;
      expect(warning.code, 'EXP-004');
      expect(warning.reason, 'glyph_missing');
      expect(warning.fieldId, field.id);
      expect(warning.pageIndex, 0);
      expect(warning.fieldLabel, 'Name');
    });

    test('blocks a baseline that cannot fit the field height', () {
      // 0.6 × 6 = 3.6 clamps to 7.0 pt, so the 7.1 pt baseline exceeds the
      // 6 pt field even though the value is short.
      final ExportFieldLayout result = _layout.layoutField(
        field: confirmedField(
          id: uuid(19),
          type: FieldType.text,
          rect: Rect.fromLTWH(20, 20, 400, 6),
        ),
        geometry: a4(),
        value: textValue('a'),
      );
      expect(result.op, isNull);
      expect(result.warnings.single.code, 'EXP-001');
      expect(result.warnings.single.reason, 'baseline_exceeds_rect');
    });

    test('draws nothing for an empty or whitespace-only value', () {
      for (final FieldValue value in <FieldValue>[
        textValue(''),
        textValue('   '),
      ]) {
        final ExportFieldLayout result = _layout.layoutField(
          field: confirmedField(
            id: uuid(20),
            type: FieldType.text,
            rect: Rect.fromLTWH(20, 20, 300, 20),
          ),
          geometry: a4(),
          value: value,
        );
        expect(result.op, isNull);
        expect(result.isEmpty, isTrue);
        expect(result.warnings, isEmpty);
      }
      final ExportFieldLayout unset = _layout.layoutField(
        field: confirmedField(
          id: uuid(21),
          type: FieldType.text,
          rect: Rect.fromLTWH(20, 20, 300, 20),
        ),
        geometry: a4(),
      );
      expect(unset.op, isNull);
      expect(unset.isEmpty, isTrue);
    });

    test('maps the op under the rotation-90 display CTM', () {
      final PageGeometry geometry = a4(rotation: 90);
      final Rect rect = Rect.fromLTWH(100, 50, 120, 20);
      final ExportFieldLayout result = _layout.layoutField(
        field: confirmedField(id: uuid(22), type: FieldType.text, rect: rect),
        geometry: geometry,
        value: textValue('A'),
      );
      final ExportTextOp op = result.op! as ExportTextOp;
      expect(op.pdfRect, geometry.displayRectToPdf(rect));
      // `coordinates-and-geometry.md` §2: display (100, 50, 120, 20) maps to
      // PDF lower-left (50, 100) with swapped extents on a 90° page.
      expect(op.pdfRect.left, closeTo(50, 1e-9));
      expect(op.pdfRect.top, closeTo(100, 1e-9));
      expect(op.pdfRect.width, closeTo(20, 1e-9));
      expect(op.pdfRect.height, closeTo(120, 1e-9));
    });
  });

  group('multiline layout', () {
    test('materializes explicit line breaks in order', () {
      final ExportFieldLayout result = _layout.layoutField(
        field: confirmedField(
          id: uuid(30),
          type: FieldType.multiline,
          rect: Rect.fromLTWH(20, 20, 400, 100),
        ),
        geometry: a4(),
        value: multilineValue('Zeile eins\nZeile zwei\nZeile drei'),
      );
      expect((result.op! as ExportTextOp).lines, <String>[
        'Zeile eins',
        'Zeile zwei',
        'Zeile drei',
      ]);
    });

    test('keeps an interior double space instead of collapsing it', () {
      const String value = 'ab  cd';
      final double width = _metrics.advanceWidthPt(value, 12);
      final ExportFieldLayout result = _layout.layoutField(
        field: confirmedField(
          id: uuid(31),
          type: FieldType.multiline,
          rect: Rect.fromLTWH(20, 20, width + 4.0, 20),
        ),
        geometry: a4(),
        value: multilineValue(value),
      );
      expect((result.op! as ExportTextOp).lines, <String>[value]);
      expect(result.trimmedTrailingSpaceCount, 0);
    });

    test('wraps greedily at spaces and consumes the break spaces', () {
      const String value = 'ab  cd';
      // Only 'ab' fits: 14.1 pt at 12 pt within 15.1 pt of available width.
      final ExportFieldLayout result = _layout.layoutField(
        field: confirmedField(
          id: uuid(32),
          type: FieldType.multiline,
          rect: Rect.fromLTWH(20, 20, 18.1, 60),
        ),
        geometry: a4(),
        value: multilineValue(value),
      );
      expect((result.op! as ExportTextOp).lines, <String>['ab', 'cd']);
      expect(result.trimmedTrailingSpaceCount, 2);
      expect(result.warnings, isEmpty);
    });

    test('trims trailing spaces of explicit lines and counts them', () {
      final ExportFieldLayout result = _layout.layoutField(
        field: confirmedField(
          id: uuid(33),
          type: FieldType.multiline,
          rect: Rect.fromLTWH(20, 20, 400, 100),
        ),
        geometry: a4(),
        value: multilineValue('Hallo   \nWelt  '),
      );
      expect((result.op! as ExportTextOp).lines, <String>['Hallo', 'Welt']);
      expect(result.trimmedTrailingSpaceCount, 5);
    });

    test(
      'does not break, hyphenate, or shrink a word longer than the line',
      () {
        const String word = 'Donaudampfschifffahrtsgesellschaft';
        final ExportFieldLayout result = _layout.layoutField(
          field: confirmedField(
            id: uuid(34),
            type: FieldType.multiline,
            rect: Rect.fromLTWH(20, 20, 40, 200),
          ),
          geometry: a4(),
          value: multilineValue(word),
        );
        expect(result.op, isNull);
        expect(
          result.warnings.map((ExportValidationWarning w) => w.reason),
          contains('too_wide'),
        );
        expect(
          result.warnings.map((ExportValidationWarning w) => w.reason),
          isNot(contains('too_many_lines')),
        );
      },
    );

    test('blocks when the wrapped lines exceed the available height', () {
      final ExportFieldLayout result = _layout.layoutField(
        field: confirmedField(
          id: uuid(35),
          type: FieldType.multiline,
          rect: Rect.fromLTWH(20, 20, 18.1, 20),
        ),
        geometry: a4(),
        value: multilineValue('ab cd ef'),
      );
      expect(result.op, isNull);
      expect(
        result.warnings.map((ExportValidationWarning w) => w.reason),
        <String>['too_many_lines'],
      );
    });

    test('accepts exactly the number of lines that fits', () {
      // Height 20 pt: available 17 pt, line height 14.4 pt, so one line fits
      // and two lines block.
      final ExportFieldLayout oneLine = _layout.layoutField(
        field: confirmedField(
          id: uuid(36),
          type: FieldType.multiline,
          rect: Rect.fromLTWH(20, 20, 400, 20),
        ),
        geometry: a4(),
        value: multilineValue('Hallo'),
      );
      expect(oneLine.op, isNotNull);
      final ExportFieldLayout twoLines = _layout.layoutField(
        field: confirmedField(
          id: uuid(37),
          type: FieldType.multiline,
          rect: Rect.fromLTWH(20, 20, 18.1, 20),
        ),
        geometry: a4(),
        value: multilineValue('ab cd'),
      );
      expect(twoLines.op, isNull);
      expect(twoLines.warnings.single.reason, 'too_many_lines');
    });

    test('blocks a multiline value with a missing glyph', () {
      final ExportFieldLayout result = _layout.layoutField(
        field: confirmedField(
          id: uuid(38),
          type: FieldType.multiline,
          rect: Rect.fromLTWH(20, 20, 400, 100),
        ),
        geometry: a4(),
        value: multilineValue('Zeile\n\u{1F600}'),
      );
      expect(result.warnings.single.code, 'EXP-004');
      expect(result.warnings.single.reason, 'glyph_missing');
    });
  });

  group('checkbox layout', () {
    test('draws nothing for an unchecked or unset box', () {
      for (final FieldValue? value in <FieldValue?>[
        null,
        checkboxValue(checked: false),
      ]) {
        final ExportFieldLayout result = _layout.layoutField(
          field: confirmedField(
            id: uuid(40),
            type: FieldType.checkbox,
            rect: Rect.fromLTWH(420, 210, 10, 10),
          ),
          geometry: a4(),
          value: value,
        );
        expect(result.op, isNull);
        expect(result.isEmpty, isFalse);
        expect(result.warnings, isEmpty);
      }
    });

    test('derives the inset and stroke width from the box size', () {
      final Map<double, List<double>> expected = <double, List<double>>{
        10: <double>[1.5, 0.8],
        3: <double>[0.5, 0.6],
        40: <double>[3.0, 1.4],
      };
      for (final MapEntry<double, List<double>> sample in expected.entries) {
        final Rect rect = Rect.fromLTWH(420, 210, sample.key, sample.key);
        final ExportFieldLayout result = _layout.layoutField(
          field: confirmedField(
            id: uuid(41),
            type: FieldType.checkbox,
            rect: rect,
            provenance: Provenance.user,
          ),
          geometry: a4(),
          value: checkboxValue(),
        );
        final ExportCheckboxOp op = result.op! as ExportCheckboxOp;
        expect(op.checked, isTrue);
        expect(op.insetPt, sample.value[0]);
        expect(op.strokeWidthPt, sample.value[1]);
        expect(op.rect, rect);
        expect(op.pdfRect, a4().displayRectToPdf(rect));
      }
    });
  });

  group('signature layout', () {
    test('fits a 2:1 capture with contain and centers it', () {
      final Rect rect = Rect.fromLTWH(100, 100, 100, 40);
      final ExportFieldLayout result = _layout.layoutField(
        field: confirmedField(
          id: uuid(50),
          type: FieldType.signature,
          rect: rect,
          provenance: Provenance.user,
        ),
        geometry: a4(),
        value: signatureValue(uuid(51)),
        signatureMark: signatureMark(
          assetId: uuid(51),
          fieldId: uuid(50),
          fieldRect: rect,
        ),
      );
      final ExportImageOp op = result.op! as ExportImageOp;
      expect(op.assetId, uuid(51));
      expect(op.fit, 'contain');
      expect(op.align, 'center');
      // Available box 98 × 38 pt; 200 × 100 px capture → scale 0.38.
      expect(op.rect.width, closeTo(76, 1e-9));
      expect(op.rect.height, closeTo(38, 1e-9));
      expect(op.rect.left, closeTo(112, 1e-9));
      expect(op.rect.top, closeTo(101, 1e-9));
      expect(op.pdfRect, a4().displayRectToPdf(op.rect));
    });

    test('never upscales a capture beyond 2× its source pixels', () {
      final Rect rect = Rect.fromLTWH(10, 10, 500, 500);
      final ExportFieldLayout result = _layout.layoutField(
        field: confirmedField(
          id: uuid(52),
          type: FieldType.signature,
          rect: rect,
        ),
        geometry: a4(),
        value: signatureValue(uuid(53)),
        signatureMark: signatureMark(
          assetId: uuid(53),
          fieldId: uuid(52),
          fieldRect: rect,
          widthPx: 50,
          heightPx: 50,
        ),
      );
      final ExportImageOp op = result.op! as ExportImageOp;
      expect(op.rect.width, closeTo(100, 1e-9));
      expect(op.rect.height, closeTo(100, 1e-9));
      expect(op.rect.left, closeTo(210, 1e-9));
      expect(op.rect.top, closeTo(210, 1e-9));
    });

    test('blocks a signature whose capture is missing', () {
      final Rect rect = Rect.fromLTWH(10, 10, 200, 60);
      final ExportFieldLayout result = _layout.layoutField(
        field: confirmedField(
          id: uuid(54),
          type: FieldType.signature,
          rect: rect,
        ),
        geometry: a4(),
        value: signatureValue(uuid(55)),
      );
      expect(result.op, isNull);
      expect(result.warnings.single.code, 'EXP-001');
      expect(result.warnings.single.reason, 'signature_asset_missing');
    });

    test('blocks a signature field too small to hold the 1 pt padding', () {
      final ExportFieldLayout result = _layout.layoutField(
        field: confirmedField(
          id: uuid(56),
          type: FieldType.signature,
          rect: Rect.fromLTWH(10, 10, 1.5, 60),
        ),
        geometry: a4(),
        value: signatureValue(uuid(57)),
        signatureMark: signatureMark(
          assetId: uuid(57),
          fieldId: uuid(56),
          fieldRect: Rect.fromLTWH(10, 10, 1.5, 60),
        ),
      );
      expect(result.op, isNull);
      expect(result.warnings.single.reason, 'signature_too_small');
    });

    test('draws nothing for an unsigned signature field', () {
      final ExportFieldLayout result = _layout.layoutField(
        field: confirmedField(
          id: uuid(58),
          type: FieldType.signature,
          rect: Rect.fromLTWH(10, 10, 200, 60),
        ),
        geometry: a4(),
      );
      expect(result.op, isNull);
      expect(result.isEmpty, isTrue);
      expect(result.warnings, isEmpty);
    });
  });
}
