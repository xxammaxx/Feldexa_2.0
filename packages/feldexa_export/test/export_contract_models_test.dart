// T022 export-plan and export-validation contract tests.
//
// These are host-VM tests (`NONE` evidence). They pin the v1 schema and
// invariants from `contracts/export-plan.md` §2–§4, `data-model.md` §3.15, and
// `spec.md` FR-068/FR-072. They prove model behavior only; they cannot prove
// PDFBox output, Android export, or artifact validity.
import 'dart:convert';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_export/feldexa_export.dart';
import 'package:flutter_test/flutter_test.dart';

const String _sha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

String _uuid(int value) {
  return '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
}

DateTime _at([int minute = 0]) => DateTime.utc(2026, 11, 14, 12, minute);

Rect _rect({
  double left = 10,
  double top = 20,
  double width = 100,
  double height = 20,
}) {
  return Rect.fromLTWH(left, top, width, height);
}

double _quantize(double value) => (value * 1000).round() / 1000;

Rect _pdfRect(Rect displayRect, {double pageHeight = 841.89}) {
  return Rect.fromLTWH(
    _quantize(displayRect.left),
    _quantize(pageHeight - displayRect.top - displayRect.height),
    _quantize(displayRect.width),
    _quantize(displayRect.height),
  );
}

PageGeometry _geometry({int rotation = 0}) {
  return PageGeometry(
    mediaBox: Rect.fromLTWH(0, 0, 595.28, 841.89),
    rotation: rotation,
  );
}

ExportFont _font({Map<String, Object?> unknownFields = const {}}) {
  return ExportFont(
    family: 'NotoSans',
    regularAsset: 'assets/fonts/NotoSans-Regular.ttf',
    boldAsset: 'assets/fonts/NotoSans-Bold.ttf',
    metricsVersion: 'noto-sans-2.013-v1',
    unknownFields: unknownFields,
  );
}

ExportPlanInfo _info({int empty = 3, int unresolved = 2}) {
  return ExportPlanInfo(
    emptyFieldCount: empty,
    unresolvedSuggestionCount: unresolved,
  );
}

ExportTextOp _textOp({
  String fieldId = 'f1',
  Provenance provenance = Provenance.machine,
  Rect? rect,
  double fontSizePt = 8.7,
  double lineHeightPt = 10.44,
  double baselineFromTopPt = 8.46,
  String color = '#000000',
  List<String> lines = const <String>['Müller-Lüdenscheidt'],
  bool overflow = false,
  Map<String, Object?> unknownFields = const {},
}) {
  final Rect displayRect =
      rect ?? _rect(left: 148.5, top: 302, width: 210, height: 14.5);
  return ExportTextOp(
    fieldId: fieldId,
    provenance: provenance,
    rect: displayRect,
    pdfRect: _pdfRect(displayRect),
    fontSizePt: fontSizePt,
    lineHeightPt: lineHeightPt,
    baselineFromTopPt: baselineFromTopPt,
    color: color,
    lines: lines,
    overflow: overflow,
    unknownFields: unknownFields,
  );
}

ExportCheckboxOp _checkboxOp({
  String fieldId = 'f2',
  Provenance provenance = Provenance.user,
  bool checked = true,
}) {
  final Rect displayRect = _rect(left: 420, top: 210, width: 10, height: 10);
  return ExportCheckboxOp(
    fieldId: fieldId,
    provenance: provenance,
    rect: displayRect,
    pdfRect: _pdfRect(displayRect),
    checked: checked,
    insetPt: 1.5,
    strokeWidthPt: 0.8,
  );
}

ExportImageOp _imageOp({
  String fieldId = 'f3',
  Provenance provenance = Provenance.template,
  String fit = 'contain',
  String align = 'center',
}) {
  final Rect displayRect = _rect(left: 320, top: 720, width: 180, height: 50);
  return ExportImageOp(
    fieldId: fieldId,
    provenance: provenance,
    rect: displayRect,
    pdfRect: _pdfRect(displayRect),
    assetId: _uuid(200),
    fit: fit,
    align: align,
  );
}

ExportPage _page({
  int index = 0,
  PageGeometry? geometry,
  List<ExportOp> ops = const <ExportOp>[],
  ExportCtm? ctm,
  Map<String, Object?> unknownFields = const {},
}) {
  return ExportPage(
    index: index,
    geometry: geometry ?? _geometry(),
    ops: ops,
    ctm: ctm,
    unknownFields: unknownFields,
  );
}

ExportPlan _plan({
  int pageCount = 2,
  List<ExportPage>? pages,
  String evidenceClass = 'emulator',
  ExportFont? font,
  List<String> warnings = const <String>[],
  ExportPlanInfo? info,
  Map<String, Object?> unknownFields = const {},
}) {
  return ExportPlan(
    documentId: _uuid(1),
    revisionId: _uuid(2),
    sourceSha256: _sha256,
    pageCount: pageCount,
    evidenceClass: evidenceClass,
    font: font ?? _font(),
    pages:
        pages ??
        <ExportPage>[
          _page(ops: <ExportOp>[_textOp(), _checkboxOp(), _imageOp()]),
          _page(index: 1),
        ],
    warnings: warnings,
    info: info ?? _info(),
    unknownFields: unknownFields,
  );
}

Map<String, Object?> _contractExampleJson() {
  return <String, Object?>{
    'schemaVersion': 1,
    'documentId': _uuid(1),
    'revisionId': _uuid(2),
    'sourceSha256': _sha256,
    'pageCount': 2,
    'evidenceClass': 'emulator',
    'font': <String, Object?>{
      'family': 'NotoSans',
      'regularAsset': 'assets/fonts/NotoSans-Regular.ttf',
      'boldAsset': 'assets/fonts/NotoSans-Bold.ttf',
      'metricsVersion': 'noto-sans-2.013-v1',
    },
    'pages': <Object?>[
      <String, Object?>{
        'index': 0,
        'rotation': 0,
        'mediaBox': <String, Object?>{
          'x': 0,
          'y': 0,
          'width': 595.28,
          'height': 841.89,
        },
        'cropBox': <String, Object?>{
          'x': 0,
          'y': 0,
          'width': 595.28,
          'height': 841.89,
        },
        'displaySize': <String, Object?>{'width': 595.28, 'height': 841.89},
        'ctm': <String, Object?>{
          'a': 1,
          'b': 0,
          'c': 0,
          'd': -1,
          'e': 0,
          'f': 841.89,
        },
        'ops': <Object?>[
          <String, Object?>{
            'op': 'text',
            'fieldId': 'f1',
            'provenance': 'machine',
            'rect': <String, Object?>{
              'x': 148.5,
              'y': 302.0,
              'width': 210.0,
              'height': 14.5,
            },
            'pdfRect': <String, Object?>{
              'x': 148.5,
              'y': 525.39,
              'width': 210.0,
              'height': 14.5,
            },
            'fontSizePt': 8.7,
            'lineHeightPt': 10.44,
            'baselineFromTopPt': 8.46,
            'color': '#000000',
            'lines': <Object?>['Müller-Lüdenscheidt'],
            'overflow': false,
          },
          <String, Object?>{
            'op': 'checkbox',
            'fieldId': 'f2',
            'provenance': 'user',
            'rect': <String, Object?>{
              'x': 420.0,
              'y': 210.0,
              'width': 10.0,
              'height': 10.0,
            },
            'pdfRect': <String, Object?>{
              'x': 420.0,
              'y': 621.89,
              'width': 10.0,
              'height': 10.0,
            },
            'checked': true,
            'insetPt': 1.5,
            'strokeWidthPt': 0.8,
          },
          <String, Object?>{
            'op': 'image',
            'fieldId': 'f3',
            'provenance': 'template',
            'rect': <String, Object?>{
              'x': 320.0,
              'y': 720.0,
              'width': 180.0,
              'height': 50.0,
            },
            'pdfRect': <String, Object?>{
              'x': 320.0,
              'y': 71.89,
              'width': 180.0,
              'height': 50.0,
            },
            'assetId': _uuid(200),
            'fit': 'contain',
            'align': 'center',
          },
        ],
      },
      <String, Object?>{
        'index': 1,
        'rotation': 0,
        'mediaBox': <String, Object?>{
          'x': 0,
          'y': 0,
          'width': 595.28,
          'height': 841.89,
        },
        'cropBox': <String, Object?>{
          'x': 0,
          'y': 0,
          'width': 595.28,
          'height': 841.89,
        },
        'displaySize': <String, Object?>{'width': 595.28, 'height': 841.89},
        'ctm': <String, Object?>{
          'a': 1,
          'b': 0,
          'c': 0,
          'd': -1,
          'e': 0,
          'f': 841.89,
        },
        'ops': <Object?>[],
      },
    ],
    'warnings': <Object?>[],
    'info': <String, Object?>{
      'emptyFieldCount': 3,
      'unresolvedSuggestionCount': 2,
    },
  };
}

void main() {
  group('ExportPlan v1 schema', () {
    test('serializes the §2 schema canonically and round-trips', () {
      final ExportPlan plan = _plan();
      final Object? canonical = jsonDecode(canonicalJsonEncode(plan.toJson()));
      expect(canonical, equals(_contractExampleJson()));

      final ExportPlan restored = ExportPlan.fromJson(_contractExampleJson());
      expect(restored, equals(plan));
      expect(
        canonicalJsonEncode(restored.toJson()),
        canonicalJsonEncode(plan.toJson()),
      );
    });

    test('derives display size and CTM from the page geometry', () {
      final ExportPage page = _page(
        geometry: PageGeometry(
          mediaBox: Rect.fromLTWH(10, 20, 842, 595),
          cropBox: Rect.fromLTWH(10, 20, 595, 595),
          rotation: 90,
        ),
      );
      expect(page.rotation, 90);
      expect(page.displaySize.width, 595);
      expect(page.displaySize.height, 595);
      expect(page.ctm.a, 0);
      expect(page.ctm.b, 1);
      expect(page.ctm.c, 1);
      expect(page.ctm.d, 0);
      expect(page.ctm.e, 10);
      expect(page.ctm.f, 20);
    });

    test('preserves unknown same-schema fields at every modeled level', () {
      final ExportPlan plan = _plan(
        font: _font(
          unknownFields: <String, Object?>{
            'futureFont': <String, Object?>{'weight': 400},
          },
        ),
        pages: <ExportPage>[
          _page(
            ops: <ExportOp>[
              _textOp(unknownFields: <String, Object?>{'futureOp': 'text'}),
            ],
            ctm: ExportCtm(
              a: 1,
              b: 0,
              c: 0,
              d: -1,
              e: 0,
              f: 841.89,
              unknownFields: <String, Object?>{'futureCtm': true},
            ),
            unknownFields: <String, Object?>{'futurePage': true},
          ),
        ],
        pageCount: 1,
        unknownFields: <String, Object?>{
          'futureRoot': <String, Object?>{'nested': 1},
        },
      );
      final ExportPlan restored = ExportPlan.fromJson(
        jsonDecode(jsonEncode(plan.toJson())) as Map<String, Object?>,
      );
      expect(
        canonicalJsonEncode(restored.toJson()),
        canonicalJsonEncode(plan.toJson()),
      );
      expect(restored.unknownFields['futureRoot'], isNotNull);
      expect(restored.pages.single.unknownFields['futurePage'], isTrue);
      expect(restored.font.unknownFields['futureFont'], isNotNull);
      expect(restored.pages.single.ctm.unknownFields['futureCtm'], isTrue);
    });

    test('rejects forbidden plan content at any depth', () {
      expect(
        () => _plan(unknownFields: <String, Object?>{'values': <Object?>[]}),
        throwsArgumentError,
      );
      expect(
        () => _font(unknownFields: <String, Object?>{'label': 'Name'}),
        throwsArgumentError,
      );
      expect(
        () => _textOp(
          unknownFields: <String, Object?>{
            'nested': <String, Object?>{'screenshot': 'x'},
          },
        ),
        throwsArgumentError,
      );
      final Map<String, Object?> json = _contractExampleJson();
      (json['pages']! as List<Object?>).add(<String, Object?>{'label': 'x'});
      expect(() => ExportPlan.fromJson(json), throwsFormatException);
    });

    test('rejects invalid plan identity, evidence, and page metadata', () {
      expect(
        () => ExportPlan(
          documentId: 'not-a-uuid',
          revisionId: _uuid(2),
          sourceSha256: _sha256,
          pageCount: 1,
          evidenceClass: 'emulator',
          font: _font(),
          pages: <ExportPage>[_page()],
          info: _info(),
        ),
        throwsArgumentError,
      );
      expect(
        () => ExportPlan(
          documentId: _uuid(1),
          revisionId: _uuid(2),
          sourceSha256: 'ABC',
          pageCount: 1,
          evidenceClass: 'emulator',
          font: _font(),
          pages: <ExportPage>[_page()],
          info: _info(),
        ),
        throwsArgumentError,
      );
      expect(() => _plan(evidenceClass: 'android'), throwsArgumentError);
      expect(() => _plan(pageCount: 3), throwsArgumentError);
      expect(
        () => _plan(pages: <ExportPage>[_page(index: 1)]),
        throwsArgumentError,
      );
      expect(
        () => ExportPlan(
          documentId: _uuid(1),
          revisionId: _uuid(2),
          sourceSha256: _sha256,
          pageCount: 1,
          evidenceClass: 'emulator',
          font: _font(),
          pages: <ExportPage>[_page()],
          info: _info(),
          schemaVersion: 2,
        ),
        throwsArgumentError,
      );
    });

    test('rejects absolute and URI font asset paths', () {
      expect(
        () => ExportFont(
          family: 'NotoSans',
          regularAsset: '/etc/fonts/NotoSans.ttf',
          boldAsset: 'assets/fonts/NotoSans-Bold.ttf',
          metricsVersion: 'v1',
        ),
        throwsArgumentError,
      );
      expect(
        () => ExportFont(
          family: 'NotoSans',
          regularAsset: 'file:///tmp/NotoSans.ttf',
          boldAsset: 'assets/fonts/NotoSans-Bold.ttf',
          metricsVersion: 'v1',
        ),
        throwsArgumentError,
      );
      expect(
        () => ExportFont(
          family: 'NotoSans',
          regularAsset: 'assets/../NotoSans.ttf',
          boldAsset: 'assets/fonts/NotoSans-Bold.ttf',
          metricsVersion: 'v1',
        ),
        throwsArgumentError,
      );
    });

    test('rejects mismatched CTM, display size, and pdfRect', () {
      expect(
        () => _page(ctm: ExportCtm(a: 0, b: 0, c: 0, d: 0, e: 0, f: 0)),
        throwsArgumentError,
      );

      final Map<String, Object?> wrongDisplay = _contractExampleJson();
      final Map<String, Object?> firstPage =
          (wrongDisplay['pages']! as List<Object?>).first!
              as Map<String, Object?>;
      firstPage['displaySize'] = <String, Object?>{
        'width': 100.0,
        'height': 100.0,
      };
      expect(() => ExportPlan.fromJson(wrongDisplay), throwsFormatException);

      final Rect rect = _rect();
      final ExportTextOp mismatchedPdfRect = ExportTextOp(
        fieldId: 'f1',
        provenance: Provenance.user,
        rect: rect,
        pdfRect: Rect.fromLTWH(0, 0, rect.width, rect.height),
        fontSizePt: 12,
        lineHeightPt: 14.4,
        baselineFromTopPt: 11.1,
        lines: const <String>['x'],
      );
      expect(
        () => _page(ops: <ExportOp>[mismatchedPdfRect]),
        throwsArgumentError,
      );
    });

    test('rejects duplicate ops for one field', () {
      expect(
        () => _page(
          ops: <ExportOp>[
            _textOp(fieldId: 'f1'),
            _textOp(fieldId: 'f1'),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('ExportOp rules', () {
    test('rejects overflowing, clipped, and malformed text ops', () {
      expect(() => _textOp(overflow: true), throwsArgumentError);
      expect(() => _textOp(fontSizePt: 12.5), throwsArgumentError);
      expect(() => _textOp(fontSizePt: 6.9), throwsArgumentError);
      expect(() => _textOp(color: '#ffffff'), throwsArgumentError);
      expect(() => _textOp(lines: const <String>[]), throwsArgumentError);
      expect(() => _textOp(lines: const <String>['x ']), throwsArgumentError);
      expect(() => _textOp(lines: const <String>['a\nb']), throwsArgumentError);
      expect(
        () => _textOp(rect: _rect(height: 5), baselineFromTopPt: 6),
        throwsArgumentError,
      );
    });

    test('rejects text metrics that violate the §2.2 formula', () {
      expect(() => _textOp(fontSizePt: 8.6), throwsArgumentError);
      expect(() => _textOp(lineHeightPt: 10.43), throwsArgumentError);
      expect(
        _textOp(fontSizePt: 8.7, lineHeightPt: 10.44, baselineFromTopPt: 8.46),
        isA<ExportTextOp>(),
      );
    });

    test('rejects the stale §2 example baseline under the §2.2 formula', () {
      // §2.2 is normative: baseline = 1.5 + 0.8 × 8.7 = 8.46. The §2 example
      // still says 8.1. T022 follows the normative rule and refuses 8.1
      // instead of silently accepting both values.
      expect(() => _textOp(baselineFromTopPt: 8.1), throwsArgumentError);

      final Map<String, Object?> staleExample = _contractExampleJson();
      final Map<String, Object?> firstPage =
          (staleExample['pages']! as List<Object?>).first!
              as Map<String, Object?>;
      final Map<String, Object?> textOp =
          (firstPage['ops']! as List<Object?>).first! as Map<String, Object?>;
      textOp['baselineFromTopPt'] = 8.1;
      expect(() => ExportPlan.fromJson(staleExample), throwsFormatException);
    });

    test('applies the text clamps before checking the formula', () {
      expect(
        _textOp(
          rect: _rect(height: 10),
          fontSizePt: 7.0,
          lineHeightPt: 8.4,
          baselineFromTopPt: 7.1,
        ).fontSizePt,
        7.0,
      );
      expect(
        _textOp(
          rect: _rect(height: 25),
          fontSizePt: 12.0,
          lineHeightPt: 14.4,
          baselineFromTopPt: 11.1,
        ).fontSizePt,
        12.0,
      );
    });

    test('rejects checkbox metrics that violate the §2.2 formula', () {
      final Rect ten = _rect(width: 10, height: 10);
      expect(
        () => ExportCheckboxOp(
          fieldId: 'f2',
          provenance: Provenance.user,
          rect: ten,
          pdfRect: _pdfRect(ten),
          checked: true,
          insetPt: 1.4,
          strokeWidthPt: 0.8,
        ),
        throwsArgumentError,
      );
      expect(
        () => ExportCheckboxOp(
          fieldId: 'f2',
          provenance: Provenance.user,
          rect: ten,
          pdfRect: _pdfRect(ten),
          checked: true,
          insetPt: 1.5,
          strokeWidthPt: 0.9,
        ),
        throwsArgumentError,
      );
      final Rect two = _rect(width: 2, height: 2);
      expect(
        ExportCheckboxOp(
          fieldId: 'f2',
          provenance: Provenance.user,
          rect: two,
          pdfRect: _pdfRect(two),
          checked: true,
          insetPt: 0.5,
          strokeWidthPt: 0.6,
        ).insetPt,
        0.5,
      );
      final Rect hundred = _rect(width: 100, height: 100);
      expect(
        ExportCheckboxOp(
          fieldId: 'f2',
          provenance: Provenance.user,
          rect: hundred,
          pdfRect: _pdfRect(hundred),
          checked: true,
          insetPt: 3.0,
          strokeWidthPt: 1.4,
        ).strokeWidthPt,
        1.4,
      );
    });

    test('rejects mark values outside the normative clamps', () {
      final Rect rect = _rect(width: 10, height: 10);
      expect(
        () => ExportCheckboxOp(
          fieldId: 'f2',
          provenance: Provenance.user,
          rect: rect,
          pdfRect: _pdfRect(rect),
          checked: true,
          insetPt: 0.4,
          strokeWidthPt: 0.8,
        ),
        throwsArgumentError,
      );
      expect(
        () => ExportCheckboxOp(
          fieldId: 'f2',
          provenance: Provenance.user,
          rect: rect,
          pdfRect: _pdfRect(rect),
          checked: true,
          insetPt: 1.5,
          strokeWidthPt: 1.5,
        ),
        throwsArgumentError,
      );
      expect(() => _imageOp(fit: 'cover'), throwsArgumentError);
      expect(() => _imageOp(align: 'left'), throwsArgumentError);
    });

    test('rejects an unknown op discriminator and provenance token', () {
      final Map<String, Object?> pageJson = <String, Object?>{
        'index': 0,
        'rotation': 0,
        'mediaBox': <String, Object?>{
          'x': 0,
          'y': 0,
          'width': 100,
          'height': 100,
        },
        'cropBox': <String, Object?>{
          'x': 0,
          'y': 0,
          'width': 100,
          'height': 100,
        },
        'displaySize': <String, Object?>{'width': 100, 'height': 100},
        'ctm': <String, Object?>{
          'a': 1,
          'b': 0,
          'c': 0,
          'd': -1,
          'e': 0,
          'f': 100,
        },
        'ops': <Object?>[
          <String, Object?>{'op': 'stamp'},
        ],
      };
      expect(() => ExportPage.fromJson(pageJson), throwsFormatException);

      final Map<String, Object?> textJson = <String, Object?>{
        'op': 'text',
        'fieldId': 'f1',
        'provenance': 'guess',
        'rect': <String, Object?>{'x': 10, 'y': 20, 'width': 100, 'height': 20},
        'pdfRect': <String, Object?>{
          'x': 10,
          'y': 60,
          'width': 100,
          'height': 20,
        },
        'fontSizePt': 12,
        'lineHeightPt': 14.4,
        'baselineFromTopPt': 11.1,
        'color': '#000000',
        'lines': <Object?>['x'],
        'overflow': false,
      };
      expect(() => ExportTextOp.fromJson(textJson), throwsFormatException);
    });
  });

  group('ExportValidation', () {
    test('empty validation is valid and non-blocking', () {
      final ExportValidation validation = ExportValidation(
        warnings: const <ExportValidationWarning>[],
        validatedAt: _at(),
      );
      expect(validation.isValid, isTrue);
      expect(validation.isBlocking, isFalse);
      expect(validation.hasBlockingWarnings, isFalse);
      expect(validation.toJson()['warnings'], isEmpty);
    });

    test('blocking warning keeps code, reason, and field context', () {
      final ExportValidation validation = ExportValidation(
        warnings: <ExportValidationWarning>[
          ExportValidationWarning(
            code: 'EXP-001',
            reason: 'too_wide',
            fieldId: 'f1',
            pageIndex: 0,
            fieldLabel: 'Name',
          ),
        ],
        validatedAt: _at(),
      );
      expect(validation.isValid, isFalse);
      expect(validation.isBlocking, isTrue);
      expect(validation.hasBlockingWarnings, isTrue);
      expect(validation.toString(), isNot(contains('Name')));
      final ExportValidation restored = ExportValidation.fromJson(
        jsonDecode(jsonEncode(validation.toJson())) as Map<String, Object?>,
      );
      expect(restored, validation);
      expect(restored.warnings.single.fieldLabel, 'Name');
    });

    test('rejects non-blocking codes and local timestamps', () {
      expect(
        () => ExportValidationWarning(code: 'FLD-001', reason: 'x'),
        throwsArgumentError,
      );
      expect(
        () => ExportValidationWarning(
          code: 'EXP-003',
          reason: 'outside_page',
          pageIndex: -1,
        ),
        throwsArgumentError,
      );
      expect(
        () => ExportValidation(
          warnings: const <ExportValidationWarning>[],
          validatedAt: DateTime(2026, 11, 14, 12),
        ),
        throwsArgumentError,
      );
    });
  });
}
