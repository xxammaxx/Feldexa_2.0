// T018 field-model tests.
//
// These are host-VM tests (evidence class NONE). They pin the constraints in
// `data-model.md` §2.3–§2.4 and §3.4–§3.8 and the suggestion shape in
// `contracts/recognition-output.md` §2–§3:
//   * deterministic suggestion ids, confidence, cue, skew, conflict, and
//     signature-cue rules;
//   * confirmed-field label (1–120), order, UTC timestamps, and the
//     machine-only suggestion provenance fields;
//   * value length limits (10,000), control-character rules, canonical number
//     and real-calendar-date shapes;
//   * signature long-edge and hash limits;
//   * verification timestamps and warning ordering;
//   * page-bounds tolerance, JSON round-trips, equality, and privacy: errors
//     and `toString` never echo labels or values.

import 'dart:convert';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:flutter_test/flutter_test.dart';

const Object _keep = Object();

const String _uuid = '1b4e28ba-2fa1-4d3b-a1f8-6f2a3c4d5e6f';
const String _assetId = 'd2a1b3c4-1234-4abc-8def-0123456789ab';
const String _sha256 =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

DateTime _at([int minute = 0]) => DateTime.utc(2026, 11, 13, 12, minute);

Rect _rect([double left = 10, double top = 20, double width = 120]) {
  return Rect.fromLTWH(left, top, width, 18);
}

Size _a4() => Size(595, 842);

String _repeat(String unit, int count) =>
    List<String>.filled(count, unit).join();

Map<String, Object?> _jsonRoundTrip(Map<String, Object?> json) {
  return jsonDecode(jsonEncode(json)) as Map<String, Object?>;
}

SuggestionEvidence _evidence({
  Iterable<SuggestionCue> cues = const <SuggestionCue>[SuggestionCue.line],
  int cueAgreement = 1,
  double skewDegrees = 0,
  EvidenceContrast contrast = EvidenceContrast.normal,
  bool ocrUsed = true,
}) {
  return SuggestionEvidence(
    cues: cues,
    cueAgreement: cueAgreement,
    skewDegrees: skewDegrees,
    contrast: contrast,
    ocrUsed: ocrUsed,
  );
}

FieldSuggestion _suggestion({
  String id = 's_p0_0001',
  int pageIndex = 0,
  Rect? rect,
  FieldType proposedType = FieldType.text,
  double confidence = 0.82,
  String? labelText = 'Name',
  SuggestionEvidence? evidence,
  Iterable<String> conflictsWith = const <String>[],
  SuggestionResolution resolution = SuggestionResolution.unresolved,
}) {
  return FieldSuggestion(
    id: id,
    pageIndex: pageIndex,
    rect: rect ?? _rect(),
    proposedType: proposedType,
    confidence: confidence,
    labelText: labelText,
    evidence: evidence ?? _evidence(),
    conflictsWith: conflictsWith,
    resolution: resolution,
  );
}

ConfirmedField _field({
  String id = _uuid,
  int pageIndex = 0,
  Rect? rect,
  FieldType type = FieldType.text,
  Provenance provenance = Provenance.user,
  Object? sourceSuggestionId = _keep,
  Object? suggestionConfidence = _keep,
  String label = 'Name',
  int order = 0,
  DateTime? createdAt,
  DateTime? updatedAt,
  FieldValidation validation = FieldValidation.ok,
}) {
  return ConfirmedField(
    id: id,
    pageIndex: pageIndex,
    rect: rect ?? _rect(),
    type: type,
    provenance: provenance,
    sourceSuggestionId: identical(sourceSuggestionId, _keep)
        ? null
        : sourceSuggestionId as String?,
    suggestionConfidence: identical(suggestionConfidence, _keep)
        ? null
        : suggestionConfidence as double?,
    label: label,
    order: order,
    createdAt: createdAt ?? _at(),
    updatedAt: updatedAt ?? _at(1),
    validation: validation,
  );
}

SignatureMark _mark({
  String assetId = _assetId,
  String fieldId = _uuid,
  int pageIndex = 0,
  Rect? rect,
  int widthPx = 400,
  int heightPx = 200,
  DateTime? capturedAt,
  String sha256 = _sha256,
}) {
  return SignatureMark(
    assetId: assetId,
    fieldId: fieldId,
    pageIndex: pageIndex,
    rect: rect ?? _rect(320, 720, 180),
    widthPx: widthPx,
    heightPx: heightPx,
    capturedAt: capturedAt ?? _at(),
    sha256: sha256,
  );
}

void main() {
  group('FieldType and enum tokens', () {
    test('wire tokens are stable and unknown tokens fail closed', () {
      expect(FieldType.fromWire('text'), FieldType.text);
      expect(FieldType.fromWire('multiline'), FieldType.multiline);
      expect(Provenance.fromWire('machine'), Provenance.machine);
      expect(
        SuggestionResolution.fromWire('rejected'),
        SuggestionResolution.rejected,
      );
      expect(
        SuggestionCue.fromWire('ocr_alignment_right'),
        SuggestionCue.ocrAlignmentRight,
      );
      expect(
        SuggestionCue.fromWire('signature_area'),
        SuggestionCue.signatureArea,
      );
      expect(
        WarningCode.fromWire('incompatible_content'),
        WarningCode.incompatibleContent,
      );
      expect(
        FieldVerificationState.fromWire('corrected'),
        FieldVerificationState.corrected,
      );
      expect(() => FieldType.fromWire('unknown'), throwsFormatException);
      expect(() => FieldType.fromWire(3), throwsFormatException);
    });

    test('represents every recognition-output §3.1 wire cue', () {
      const List<String> fixedTokens = <String>[
        'underline',
        'box',
        'grid_cell',
        'whitespace',
        'alignment_left',
        'label_below',
        'ocr_alignment_right',
        'ocr_alignment_below',
        'small_square',
        'table_cell',
        'signature_area',
        'numeric_context',
        'date_context',
      ];
      for (final String token in fixedTokens) {
        expect(SuggestionCue.fromWire(token).wireName, token, reason: token);
      }
      final SuggestionCue keyword = SuggestionCue.fromWire('keyword_vorname');
      expect(keyword.wireName, 'keyword_vorname');
      expect(keyword, SuggestionCue.fromWire('keyword_vorname'));
      expect(keyword, isNot(SuggestionCue.fromWire('keyword_name')));
      final SuggestionEvidence evidence = _evidence(
        cues: <SuggestionCue>[
          SuggestionCue.fromWire('underline'),
          SuggestionCue.fromWire('grid_cell'),
          SuggestionCue.fromWire('keyword_vorname'),
        ],
      );
      expect(evidence.toJson()['cues'], <String>[
        'underline',
        'grid_cell',
        'keyword_vorname',
      ]);
      final SuggestionEvidence parsed = SuggestionEvidence.fromJson(
        _jsonRoundTrip(evidence.toJson()),
      );
      expect(parsed, evidence);
    });
  });

  group('SuggestionEvidence', () {
    test('requires a non-empty, duplicate-free cue set', () {
      expect(
        () => _evidence(cues: const <SuggestionCue>[]),
        throwsArgumentError,
      );
      expect(
        () => _evidence(
          cues: const <SuggestionCue>[SuggestionCue.line, SuggestionCue.line],
        ),
        throwsArgumentError,
      );
    });

    test('sorts cues and stores them as an immutable set', () {
      final SuggestionEvidence evidence = _evidence(
        cues: <SuggestionCue>[
          SuggestionCue.keyword('vorname'),
          SuggestionCue.line,
          SuggestionCue.box,
        ],
      );
      expect(evidence.cues.toList(), <SuggestionCue>[
        SuggestionCue.line,
        SuggestionCue.box,
        SuggestionCue.keyword('vorname'),
      ]);
      expect(
        () => evidence.cues.add(SuggestionCue.grid),
        throwsUnsupportedError,
      );
      expect(evidence.toJson()['cues'], <String>[
        'underline',
        'box',
        'keyword_vorname',
      ]);
    });

    test('keyword cues are lossless, canonical, and validated', () {
      expect(SuggestionCue.keyword(' Name ').wireName, 'keyword_name');
      expect(
        SuggestionCue.keyword('Datum/Unterschrift').wireName,
        'keyword_datum/unterschrift',
      );
      expect(SuggestionCue.keyword('E-Mail').wireName, 'keyword_e-mail');
      expect(SuggestionCue.keyword('straße').wireName, 'keyword_straße');
      expect(SuggestionCue.keyword('name'), SuggestionCue.keyword('NAME'));
      expect(
        SuggestionCue.keyword('name').hashCode,
        SuggestionCue.keyword('NAME').hashCode,
      );
      expect(
        () => _evidence(
          cues: <SuggestionCue>[
            SuggestionCue.keyword('name'),
            SuggestionCue.keyword('NAME'),
          ],
        ),
        throwsArgumentError,
      );
      for (final String invalid in <String>[
        '',
        '   ',
        'bad key',
        'bad\u200Bkey',
        'bad\u034Fkey',
      ]) {
        expect(
          () => SuggestionCue.keyword(invalid),
          throwsArgumentError,
          reason: 'keyword key length ${invalid.runes.length}',
        );
      }
      expect(() => SuggestionCue.fromWire('keyword_'), throwsFormatException);
      expect(
        () => SuggestionCue.fromWire('keyword_bad key'),
        throwsFormatException,
      );
      expect(() => SuggestionCue.fromWire('keyword'), throwsFormatException);
      expect(
        () => SuggestionCue.fromWire('ocr_alignment'),
        throwsFormatException,
      );
      expect(() => SuggestionCue.fromWire('line'), throwsFormatException);
      expect(() => SuggestionCue.fromWire('grid'), throwsFormatException);
      expect(SuggestionCue.fromLegacyWire('line'), SuggestionCue.underline);
      expect(SuggestionCue.fromLegacyWire('grid'), SuggestionCue.gridCell);
      for (final String unknown in <String>[
        'nickname',
        'unknown',
        'vorname2',
      ]) {
        expect(
          () => SuggestionCue.keyword(unknown),
          throwsArgumentError,
          reason: unknown,
        );
        expect(
          () => SuggestionCue.fromWire('keyword_$unknown'),
          throwsFormatException,
          reason: unknown,
        );
      }
      final SuggestionEvidence sorted = _evidence(
        cues: <SuggestionCue>[
          SuggestionCue.underline,
          SuggestionCue.keyword('vorname'),
          SuggestionCue.keyword('name'),
        ],
      );
      expect(sorted.cues.toList(), <SuggestionCue>[
        SuggestionCue.underline,
        SuggestionCue.keyword('name'),
        SuggestionCue.keyword('vorname'),
      ]);
    });

    test('keyword cue keys are the closed recognition-output v1 lexicon', () {
      expect(SuggestionCue.keywordLexiconV1, hasLength(36));
      for (final String key in SuggestionCue.keywordLexiconV1) {
        final SuggestionCue cue = SuggestionCue.keyword(key);
        expect(cue.wireName, 'keyword_$key', reason: key);
        expect(SuggestionCue.fromWire('keyword_$key'), cue, reason: key);
      }
      expect(
        SuggestionCue.keyword('VORNAME'),
        SuggestionCue.keyword('vorname'),
      );
    });

    test('requires at least one geometric cue (§2.1)', () {
      for (final SuggestionCue ocrOnly in <SuggestionCue>[
        SuggestionCue.keyword('name'),
        SuggestionCue.ocrAlignmentRight,
        SuggestionCue.ocrAlignmentBelow,
        SuggestionCue.labelBelow,
        SuggestionCue.numericContext,
        SuggestionCue.dateContext,
      ]) {
        expect(
          () => _evidence(cues: <SuggestionCue>[ocrOnly]),
          throwsArgumentError,
          reason: ocrOnly.wireName,
        );
      }
      for (final SuggestionCue geometric in <SuggestionCue>[
        SuggestionCue.underline,
        SuggestionCue.box,
        SuggestionCue.gridCell,
        SuggestionCue.whitespace,
        SuggestionCue.alignmentLeft,
        SuggestionCue.smallSquare,
        SuggestionCue.tableCell,
        SuggestionCue.signatureArea,
      ]) {
        expect(
          _evidence(cues: <SuggestionCue>[geometric]).cues,
          contains(geometric),
          reason: geometric.wireName,
        );
      }
      expect(
        _evidence(
          cues: <SuggestionCue>[
            SuggestionCue.keyword('name'),
            SuggestionCue.box,
          ],
        ).cues,
        hasLength(2),
      );
      expect(
        () => SuggestionEvidence.fromJson(<String, Object?>{
          'cues': <String>['keyword_name'],
          'cueAgreement': 1,
          'skewDegrees': 0,
          'contrast': 'normal',
          'ocrUsed': true,
        }),
        throwsFormatException,
      );
    });

    test(
      'strict cue parsing rejects legacy aliases; migration canonicalizes',
      () {
        final Map<String, Object?> strictLine = <String, Object?>{
          'cues': <String>['line'],
          'cueAgreement': 1,
          'skewDegrees': 0,
          'contrast': 'normal',
          'ocrUsed': true,
        };
        expect(
          () => SuggestionEvidence.fromJson(strictLine),
          throwsFormatException,
        );
        final SuggestionEvidence migrated = SuggestionEvidence.fromLegacyJson(
          strictLine,
        );
        expect(migrated.cues, <SuggestionCue>{SuggestionCue.underline});
        expect(migrated.toJson()['cues'], <String>['underline']);

        final SuggestionEvidence grid = SuggestionEvidence.fromLegacyJson(
          <String, Object?>{
            'cues': <String>['grid'],
            'cueAgreement': 1,
            'skewDegrees': 0,
            'contrast': 'normal',
            'ocrUsed': true,
          },
        );
        expect(grid.cues, <SuggestionCue>{SuggestionCue.gridCell});
        expect(grid.toJson()['cues'], <String>['grid_cell']);

        expect(
          SuggestionEvidence.fromJson(<String, Object?>{
            'cues': <String>['underline', 'grid_cell'],
            'cueAgreement': 2,
            'skewDegrees': 0,
            'contrast': 'normal',
            'ocrUsed': true,
          }).cues,
          <SuggestionCue>{SuggestionCue.underline, SuggestionCue.gridCell},
        );
      },
    );

    test('rejects OCR-dependent cues when ocrUsed is false', () {
      for (final SuggestionCue ocrCue in <SuggestionCue>[
        SuggestionCue.keyword('name'),
        SuggestionCue.ocrAlignmentRight,
        SuggestionCue.ocrAlignmentBelow,
        SuggestionCue.labelBelow,
        SuggestionCue.signatureArea,
        SuggestionCue.numericContext,
        SuggestionCue.dateContext,
      ]) {
        expect(
          () => _evidence(
            cues: <SuggestionCue>[SuggestionCue.underline, ocrCue],
            ocrUsed: false,
          ),
          throwsArgumentError,
          reason: ocrCue.wireName,
        );
      }
      final SuggestionEvidence geometryOnly = _evidence(
        cues: <SuggestionCue>[
          SuggestionCue.underline,
          SuggestionCue.box,
          SuggestionCue.gridCell,
          SuggestionCue.whitespace,
          SuggestionCue.alignmentLeft,
          SuggestionCue.smallSquare,
          SuggestionCue.tableCell,
        ],
        ocrUsed: false,
      );
      expect(geometryOnly.ocrUsed, isFalse);
      final SuggestionEvidence withOcr = _evidence(
        cues: <SuggestionCue>[
          SuggestionCue.underline,
          SuggestionCue.keyword('name'),
          SuggestionCue.signatureArea,
        ],
        ocrUsed: true,
      );
      expect(withOcr.ocrUsed, isTrue);
      expect(
        () => SuggestionEvidence.fromJson(<String, Object?>{
          'cues': <String>['underline', 'keyword_name'],
          'cueAgreement': 1,
          'skewDegrees': 0,
          'contrast': 'normal',
          'ocrUsed': false,
        }),
        throwsFormatException,
      );
      final SuggestionEvidence jsonGeometryOnly = SuggestionEvidence.fromJson(
        <String, Object?>{
          'cues': <String>['underline', 'box'],
          'cueAgreement': 2,
          'skewDegrees': 0,
          'contrast': 'normal',
          'ocrUsed': false,
        },
      );
      expect(jsonGeometryOnly.ocrUsed, isFalse);
    });

    test('enforces cueAgreement and skew bounds', () {
      expect(_evidence(cueAgreement: 1).cueAgreement, 1);
      expect(() => _evidence(cueAgreement: 0), throwsArgumentError);
      expect(() => _evidence(cueAgreement: -1), throwsArgumentError);
      // One cue can support at most one independent cue family.
      expect(() => _evidence(cueAgreement: 2), throwsArgumentError);
      expect(() => _evidence(cueAgreement: 99), throwsArgumentError);
      final List<SuggestionCue> threeCues = <SuggestionCue>[
        SuggestionCue.underline,
        SuggestionCue.box,
        SuggestionCue.whitespace,
      ];
      // Families may be fewer than cues, but never more.
      expect(_evidence(cues: threeCues, cueAgreement: 1).cueAgreement, 1);
      expect(_evidence(cues: threeCues, cueAgreement: 3).cueAgreement, 3);
      expect(
        () => _evidence(cues: threeCues, cueAgreement: 4),
        throwsArgumentError,
      );
      expect(
        () => SuggestionEvidence.fromJson(<String, Object?>{
          'cues': <String>['underline'],
          'cueAgreement': 99,
          'skewDegrees': 0,
          'contrast': 'normal',
          'ocrUsed': true,
        }),
        throwsFormatException,
      );
      expect(_evidence(skewDegrees: -10).skewDegrees, -10);
      expect(_evidence(skewDegrees: 10).skewDegrees, 10);
      expect(() => _evidence(skewDegrees: -10.01), throwsArgumentError);
      expect(() => _evidence(skewDegrees: 10.01), throwsArgumentError);
      expect(() => _evidence(skewDegrees: double.nan), throwsArgumentError);
      expect(
        () => _evidence(skewDegrees: double.infinity),
        throwsArgumentError,
      );
    });

    test('tracks the signature cue and JSON round-trips', () {
      final SuggestionEvidence signed = _evidence(
        cues: const <SuggestionCue>[
          SuggestionCue.signatureArea,
          SuggestionCue.whitespace,
        ],
        cueAgreement: 2,
        skewDegrees: 0.4,
        contrast: EvidenceContrast.low,
        ocrUsed: true,
      );
      expect(signed.hasSignatureCue, isTrue);
      final SuggestionEvidence parsed = SuggestionEvidence.fromJson(
        _jsonRoundTrip(signed.toJson()),
      );
      expect(parsed, signed);
      expect(parsed.hashCode, signed.hashCode);
      expect(parsed.hasSignatureCue, isTrue);
    });

    test('serializes contrast normal|low and migrates the legacy boolean', () {
      final SuggestionEvidence normal = _evidence();
      expect(normal.contrast, EvidenceContrast.normal);
      expect(normal.lowContrast, isFalse);
      expect(normal.toJson()['contrast'], 'normal');
      expect(normal.toJson().containsKey('lowContrast'), isFalse);

      final SuggestionEvidence low = _evidence(contrast: EvidenceContrast.low);
      expect(low.contrast, EvidenceContrast.low);
      expect(low.lowContrast, isTrue);
      expect(low.toJson()['contrast'], 'low');

      final SuggestionEvidence migrated = SuggestionEvidence.fromLegacyJson(
        <String, Object?>{
          'cues': <String>['underline'],
          'cueAgreement': 1,
          'skewDegrees': 0,
          'lowContrast': true,
          'ocrUsed': true,
        },
      );
      expect(migrated.contrast, EvidenceContrast.low);
      expect(migrated.toJson()['contrast'], 'low');
      expect(migrated.toJson().containsKey('lowContrast'), isFalse);
      expect(
        () => SuggestionEvidence.fromJson(<String, Object?>{
          'cues': <String>['underline'],
          'cueAgreement': 1,
          'skewDegrees': 0,
          'lowContrast': true,
          'ocrUsed': true,
        }),
        throwsFormatException,
      );

      expect(
        () => SuggestionEvidence.fromJson(<String, Object?>{
          'cues': <String>['underline'],
          'cueAgreement': 1,
          'skewDegrees': 0,
          'ocrUsed': true,
        }),
        throwsFormatException,
      );
      expect(
        () => SuggestionEvidence.fromJson(<String, Object?>{
          'cues': <String>['underline'],
          'cueAgreement': 1,
          'skewDegrees': 0,
          'contrast': 'high',
          'ocrUsed': true,
        }),
        throwsFormatException,
      );
      expect(
        () => SuggestionEvidence.fromJson(<String, Object?>{
          'cues': <String>['underline'],
          'cueAgreement': 1,
          'skewDegrees': 0,
          'contrast': null,
          'ocrUsed': true,
        }),
        throwsFormatException,
      );
    });
  });

  group('FieldSuggestion', () {
    test('builds deterministic idFor ids', () {
      expect(FieldSuggestion.idFor(pageIndex: 0, ordinal: 7), 's_p0_0007');
      expect(FieldSuggestion.idFor(pageIndex: 12, ordinal: 7), 's_p12_0007');
      expect(FieldSuggestion.idFor(pageIndex: 0, ordinal: 12345), 's_p0_12345');
      expect(
        () => FieldSuggestion.idFor(pageIndex: -1, ordinal: 1),
        throwsArgumentError,
      );
      expect(
        () => FieldSuggestion.idFor(pageIndex: 0, ordinal: 0),
        throwsArgumentError,
      );
    });

    test('rejects malformed or page-mismatched ids', () {
      expect(() => _suggestion(id: 's_0_0007'), throwsArgumentError);
      expect(() => _suggestion(id: 's_p0_7'), throwsArgumentError);
      expect(() => _suggestion(id: 's_p1_0007'), throwsArgumentError);
      expect(() => _suggestion(id: 's_p0_0000'), throwsArgumentError);
      expect(() => _suggestion(id: 's_p0_0007', pageIndex: 0), returnsNormally);
    });

    test('rejects noncanonical page and ordinal aliases', () {
      // Recognition-output §2 fixes the only spelling: s_p<pageIndex>_<padded
      // ordinal>. A leading-zero page alias or a wider zero-padded ordinal is
      // the same logical id and must be rejected, not silently accepted.
      for (final String alias in <String>[
        's_p00_0001',
        's_p000_0001',
        's_p0_00001',
        's_p0_000001',
        's_p00_00000',
      ]) {
        expect(
          () => _suggestion(id: alias),
          throwsArgumentError,
          reason: alias,
        );
      }
      expect(
        () => _suggestion(id: 's_p012_0001', pageIndex: 12),
        throwsArgumentError,
      );
      expect(() => _suggestion(id: 's_p0_0001_extra'), throwsArgumentError);
      // The canonical spellings remain valid, including ordinals wider than
      // the four-digit minimum.
      expect(_suggestion(id: 's_p0_0001').id, 's_p0_0001');
      expect(_suggestion(id: 's_p12_0001', pageIndex: 12).id, 's_p12_0001');
      expect(_suggestion(id: 's_p0_9999').id, 's_p0_9999');
      expect(_suggestion(id: 's_p0_10000').id, 's_p0_10000');
      // Four-digit zero-padding of a smaller ordinal is canonical.
      expect(_suggestion(id: 's_p0_0999').id, 's_p0_0999');
      // Out-of-range digit runs fail closed without throwing a number-format
      // error from the constructor.
      expect(
        () => _suggestion(id: 's_p${_repeat('9', 30)}_0001'),
        throwsArgumentError,
      );
      expect(
        () => _suggestion(id: 's_p0_${_repeat('9', 30)}'),
        throwsArgumentError,
      );
      expect(FieldSuggestion.idFor(pageIndex: 0, ordinal: 1), 's_p0_0001');
      expect(FieldSuggestion.idFor(pageIndex: 0, ordinal: 9999), 's_p0_9999');
      expect(FieldSuggestion.idFor(pageIndex: 0, ordinal: 10000), 's_p0_10000');
    });

    test('enforces the confidence interval', () {
      expect(_suggestion(confidence: 0).confidence, 0);
      expect(_suggestion(confidence: 1).confidence, 1);
      expect(_suggestion(confidence: 0.82).uncertainty, closeTo(0.18, 1e-9));
      for (final double invalid in <double>[
        -0.01,
        1.01,
        double.nan,
        double.infinity,
      ]) {
        expect(
          () => _suggestion(confidence: invalid),
          throwsArgumentError,
          reason: 'confidence $invalid',
        );
      }
    });

    test('enforces the two-decimal confidence from recognition-output §2', () {
      for (final double valid in <double>[0, 0.01, 0.5, 0.82, 0.99, 1]) {
        expect(_suggestion(confidence: valid).confidence, valid);
      }
      for (final double invalid in <double>[0.825, 0.1234, 0.005, 0.999]) {
        expect(
          () => _suggestion(confidence: invalid),
          throwsArgumentError,
          reason: 'confidence $invalid',
        );
      }
      // A floating-point two-decimal result is stored in canonical form, not
      // with a long binary fraction.
      expect(_suggestion(confidence: 0.1 + 0.2).confidence, 0.3);
      expect(_suggestion(confidence: 0.82).uncertainty, 0.18);
    });

    test('trims labelText, treats blank as null, and enforces 200 chars', () {
      expect(_suggestion(labelText: '  Name  ').labelText, 'Name');
      expect(_suggestion(labelText: '   ').labelText, isNull);
      expect(_suggestion(labelText: null).labelText, isNull);
      expect(
        _suggestion(labelText: _repeat('A', 200)).labelText,
        hasLength(200),
      );
      expect(_suggestion(labelText: 'Straße').labelText, 'Straße');
      expect(
        () => _suggestion(labelText: _repeat('A', 201)),
        throwsArgumentError,
      );
      expect(() => _suggestion(labelText: 'Na\nme'), throwsArgumentError);
      expect(() => _suggestion(labelText: 'Na\tme'), throwsArgumentError);
    });

    test('requires the signature cue for a signature suggestion', () {
      expect(
        () => _suggestion(proposedType: FieldType.signature),
        throwsArgumentError,
      );
      final FieldSuggestion signature = _suggestion(
        proposedType: FieldType.signature,
        evidence: _evidence(
          cues: const <SuggestionCue>[SuggestionCue.signatureArea],
        ),
      );
      expect(signature.proposedType, FieldType.signature);
    });

    test('normalizes conflict ids and rejects self or malformed ids', () {
      final FieldSuggestion conflict = _suggestion(
        conflictsWith: <String>['s_p0_0003', 's_p0_0002'],
      );
      expect(conflict.conflictsWith, <String>['s_p0_0002', 's_p0_0003']);
      expect(
        () => _suggestion(conflictsWith: <String>['s_p0_0001']),
        throwsArgumentError,
      );
      expect(
        () => _suggestion(conflictsWith: <String>['s_p0_0002', 's_p0_0002']),
        throwsArgumentError,
      );
      expect(
        () => _suggestion(conflictsWith: <String>['other']),
        throwsArgumentError,
      );
      // Conflicts must be canonical suggestion ids with a positive ordinal;
      // aliases and zero ordinals are rejected.
      for (final String alias in <String>[
        's_p0_0000',
        's_p00_0001',
        's_p0_00001',
        's_p012_0001',
      ]) {
        expect(
          () => _suggestion(conflictsWith: <String>[alias]),
          throwsArgumentError,
          reason: alias,
        );
      }
      // IoU is defined within one page, so a canonical reference to another
      // page cannot be a conflict, in either direction.
      expect(
        () => _suggestion(conflictsWith: <String>['s_p1_0001']),
        throwsArgumentError,
      );
      expect(
        () => _suggestion(
          id: 's_p1_0001',
          pageIndex: 1,
          conflictsWith: <String>['s_p0_0001'],
        ),
        throwsArgumentError,
      );
      expect(
        _suggestion(conflictsWith: <String>['s_p0_0002']).conflictsWith,
        <String>['s_p0_0002'],
      );
    });

    test('checks page-bounds tolerance without clamping', () {
      final Size page = _a4();
      expect(_suggestion(rect: _rect(0, 0)).fitsWithinPage(page), isTrue);
      expect(
        _suggestion(rect: Rect.fromLTWH(-0.5, 0, 595, 842))
            .fitsWithinPage(page),
        isTrue,
      );
      expect(
        _suggestion(rect: Rect.fromLTWH(0, 0, 595.5, 842)).fitsWithinPage(page),
        isTrue,
      );
      expect(
        _suggestion(rect: Rect.fromLTWH(0, 0, 595.6, 842)).fitsWithinPage(page),
        isFalse,
      );
      expect(
        _suggestion(rect: Rect.fromLTWH(-0.6, 0, 595, 842))
            .fitsWithinPage(page),
        isFalse,
      );
      expect(
        _suggestion(rect: Rect.fromLTWH(0, 0, 595, 842.6)).fitsWithinPage(page),
        isFalse,
      );
    });

    test('rounds the stored rect to the 1/8 pt grid', () {
      final FieldSuggestion suggestion = _suggestion(
        rect: Rect.fromLTWH(10.07, 20.03, 99.99, 14.94),
      );
      expect(suggestion.rect, Rect.fromLTWH(10.125, 20, 100, 15));
    });

    test('canonicalRect rounds components and half-step ties', () {
      expect(
        FieldSuggestion.canonicalRect(
          Rect.fromLTWH(10.07, 20.03, 99.99, 14.94),
        ),
        Rect.fromLTWH(10.125, 20, 100, 15),
      );
      // Exact half-step ties round away from zero on the 1/8 pt grid.
      expect(
        FieldSuggestion.canonicalRect(
          Rect.fromLTWH(0.0625, 0.1875, 0.4375, 0.3125),
        ),
        Rect.fromLTWH(0.125, 0.25, 0.5, 0.375),
      );
      expect(
        FieldSuggestion.canonicalRect(Rect.fromLTWH(-0.0625, -0.1875, 1, 1)),
        Rect.fromLTWH(-0.125, -0.25, 1, 1),
      );
    });

    test('canonicalRect is idempotent and leaves aligned rects unchanged', () {
      final Rect aligned = Rect.fromLTWH(10.125, 20, 100, 15);
      expect(FieldSuggestion.canonicalRect(aligned), aligned);
      final Rect raw = Rect.fromLTWH(10.07, 20.03, 99.99, 14.94);
      final Rect once = FieldSuggestion.canonicalRect(raw);
      expect(FieldSuggestion.canonicalRect(once), once);
    });

    test('canonicalRect rejects zero-size and overflowing results', () {
      expect(
        () => FieldSuggestion.canonicalRect(Rect.fromLTWH(1, 1, 0.01, 1)),
        throwsArgumentError,
      );
      expect(
        () => FieldSuggestion.canonicalRect(Rect.fromLTWH(1, 1, 1, 0.01)),
        throwsArgumentError,
      );
      expect(
        () => FieldSuggestion.canonicalRect(Rect.fromLTWH(1, 1, 0.0624, 1)),
        throwsArgumentError,
      );
      // Half of one grid step still rounds up to 1/8.
      expect(
        FieldSuggestion.canonicalRect(Rect.fromLTWH(1, 1, 0.0625, 0.0625)),
        Rect.fromLTWH(1, 1, 0.125, 0.125),
      );
      expect(
        () => FieldSuggestion.canonicalRect(
          Rect.fromLTWH(double.maxFinite, 0, 1, 1),
        ),
        throwsArgumentError,
      );
    });

    test('constructor and JSON round-trip the canonical rect', () {
      final Rect raw = Rect.fromLTWH(10.07, 20.03, 99.99, 14.94);
      final Rect expected = FieldSuggestion.canonicalRect(raw);
      final FieldSuggestion suggestion = _suggestion(rect: raw);
      expect(suggestion.rect, expected);
      expect(suggestion.toJson()['rect'], expected.toJson());
      final FieldSuggestion parsed = FieldSuggestion.fromJson(
        _jsonRoundTrip(suggestion.toJson()),
      );
      expect(parsed.rect, expected);
      expect(parsed, suggestion);
      final FieldSuggestion copied = suggestion.copyWith(
        rect: Rect.fromLTWH(1.01, 2.02, 3.03, 4.04),
      );
      expect(
        copied.rect,
        FieldSuggestion.canonicalRect(Rect.fromLTWH(1.01, 2.02, 3.03, 4.04)),
      );
    });

    test('raw rects that round to the same grid point are equal', () {
      final FieldSuggestion a = _suggestion(
        rect: Rect.fromLTWH(10.07, 20.03, 99.99, 14.94),
      );
      final FieldSuggestion b = _suggestion(
        rect: Rect.fromLTWH(10.1, 20, 100, 15),
      );
      expect(b.rect, a.rect);
      expect(b, a);
    });

    test('copyWith keeps the id and can clear the optional label', () {
      final FieldSuggestion original = _suggestion(
        confidence: 0.9,
        labelText: 'Name',
      );
      final FieldSuggestion revised = original.copyWith(
        confidence: 0.4,
        labelText: null,
        resolution: SuggestionResolution.rejected,
      );
      expect(revised.id, original.id);
      expect(revised.confidence, 0.4);
      expect(revised.labelText, isNull);
      expect(revised.resolution, SuggestionResolution.rejected);
      expect(original.labelText, 'Name');
    });

    test('equality, JSON round-trip, and privacy-safe toString', () {
      final FieldSuggestion suggestion = _suggestion(
        labelText: 'Geheim',
        resolution: SuggestionResolution.confirmed,
      );
      final FieldSuggestion parsed = FieldSuggestion.fromJson(
        _jsonRoundTrip(suggestion.toJson()),
      );
      expect(parsed, suggestion);
      expect(parsed.hashCode, suggestion.hashCode);
      expect(parsed.labelText, 'Geheim');
      expect(parsed.toString(), isNot(contains('Geheim')));
      expect(_suggestion(labelText: 'Other'), isNot(equals(suggestion)));
    });

    test('matches the recognition-output §2 suggestion wire fields', () {
      final FieldSuggestion suggestion = _suggestion(confidence: 0.82);
      final Map<String, Object?> json = suggestion.toJson();
      expect(json['confidence'], 0.82);
      expect(json['uncertainty'], 0.18);
      final Map<String, Object?> evidence =
          json['evidence']! as Map<String, Object?>;
      expect(evidence['contrast'], 'normal');
      expect(evidence.containsKey('lowContrast'), isFalse);
      final FieldSuggestion parsed = FieldSuggestion.fromJson(
        _jsonRoundTrip(json),
      );
      expect(parsed, suggestion);

      final Map<String, Object?> legacy = Map<String, Object?>.from(json)
        ..remove('uncertainty');
      expect(() => FieldSuggestion.fromJson(legacy), throwsFormatException);
      expect(FieldSuggestion.fromLegacyJson(legacy), suggestion);
      final Map<String, Object?> mismatched = Map<String, Object?>.from(json)
        ..['uncertainty'] = 0.17;
      expect(() => FieldSuggestion.fromJson(mismatched), throwsFormatException);
      final Map<String, Object?> explicitNull = Map<String, Object?>.from(json)
        ..['uncertainty'] = null;
      expect(
        () => FieldSuggestion.fromJson(explicitNull),
        throwsFormatException,
      );
      expect(
        () => FieldSuggestion.fromLegacyJson(explicitNull),
        throwsFormatException,
      );
      final Map<String, Object?> nonNumeric = Map<String, Object?>.from(json)
        ..['uncertainty'] = '0.18';
      expect(() => FieldSuggestion.fromJson(nonNumeric), throwsFormatException);
      expect(
        () => FieldSuggestion.fromLegacyJson(nonNumeric),
        throwsFormatException,
      );
    });

    test(
      'strict decoding requires contrast while legacy decoding migrates it',
      () {
        final FieldSuggestion suggestion = _suggestion(
          evidence: _evidence(contrast: EvidenceContrast.low),
        );
        final Map<String, Object?> json = suggestion.toJson();
        final Map<String, Object?> evidence = Map<String, Object?>.from(
          json['evidence']! as Map<String, Object?>,
        );
        evidence.remove('contrast');
        evidence['lowContrast'] = true;
        final Map<String, Object?> legacyJson = Map<String, Object?>.from(json)
          ..['evidence'] = evidence;
        expect(
          () => FieldSuggestion.fromJson(legacyJson),
          throwsFormatException,
        );
        final FieldSuggestion legacy = FieldSuggestion.fromLegacyJson(
          legacyJson,
        );
        expect(legacy.evidence.contrast, EvidenceContrast.low);
        expect(
          (legacy.toJson()['evidence']! as Map<String, Object?>)['contrast'],
          'low',
        );
      },
    );

    test('strict suggestion decoding rejects legacy cue aliases', () {
      final FieldSuggestion suggestion = _suggestion();
      final Map<String, Object?> json = suggestion.toJson();
      final Map<String, Object?> evidence = Map<String, Object?>.from(
        json['evidence']! as Map<String, Object?>,
      );
      evidence['cues'] = <String>['line'];
      final Map<String, Object?> aliasJson = Map<String, Object?>.from(json)
        ..['evidence'] = evidence;
      expect(() => FieldSuggestion.fromJson(aliasJson), throwsFormatException);
      final FieldSuggestion migrated = FieldSuggestion.fromLegacyJson(
        aliasJson,
      );
      expect(migrated.evidence.cues, <SuggestionCue>{SuggestionCue.underline});
      expect(
        (migrated.toJson()['evidence']! as Map<String, Object?>)['cues'],
        <String>['underline'],
      );
    });

    test('round-trips the recognition-output §2 suggestion fixture', () {
      final FieldSuggestion fixture = _suggestion(
        id: 's_p0_0007',
        confidence: 0.82,
        labelText: 'Name',
        evidence: _evidence(
          cues: <SuggestionCue>[
            SuggestionCue.underline,
            SuggestionCue.ocrAlignmentRight,
            SuggestionCue.keyword('name'),
          ],
          cueAgreement: 3,
          skewDegrees: 0.4,
        ),
      );
      final Map<String, Object?> json = _jsonRoundTrip(fixture.toJson());
      expect(json['confidence'], 0.82);
      expect(json['uncertainty'], 0.18);
      final Map<String, Object?> evidence =
          json['evidence']! as Map<String, Object?>;
      expect(evidence['cues'], <String>[
        'underline',
        'ocr_alignment_right',
        'keyword_name',
      ]);
      expect(evidence['cueAgreement'], 3);
      expect(evidence['skewDegrees'], 0.4);
      expect(evidence['contrast'], 'normal');
      expect(evidence['ocrUsed'], true);
      expect(FieldSuggestion.fromJson(json), fixture);
    });
  });

  group('ConfirmedField', () {
    test('builds a user field and round-trips JSON', () {
      final ConfirmedField field = _field(validation: FieldValidation.ok);
      expect(field.provenance, Provenance.user);
      expect(field.sourceSuggestionId, isNull);
      expect(field.suggestionConfidence, isNull);
      expect(field.validation.isOk, isTrue);
      final ConfirmedField parsed = ConfirmedField.fromJson(
        _jsonRoundTrip(field.toJson()),
      );
      expect(parsed, field);
      expect(parsed.hashCode, field.hashCode);
    });

    test('requires machine provenance fields exactly for machine fields', () {
      expect(() => _field(provenance: Provenance.machine), throwsArgumentError);
      expect(
        () => _field(
          provenance: Provenance.machine,
          sourceSuggestionId: 's_p0_0001',
        ),
        throwsArgumentError,
      );
      expect(
        () => _field(provenance: Provenance.machine, suggestionConfidence: 0.8),
        throwsArgumentError,
      );
      final ConfirmedField machine = _field(
        provenance: Provenance.machine,
        sourceSuggestionId: 's_p0_0001',
        suggestionConfidence: 0.8,
      );
      expect(machine.sourceSuggestionId, 's_p0_0001');
      expect(machine.suggestionConfidence, 0.8);
      expect(
        () => _field(
          provenance: Provenance.template,
          sourceSuggestionId: 's_p0_0001',
        ),
        throwsArgumentError,
      );
      expect(
        () =>
            _field(provenance: Provenance.template, suggestionConfidence: 0.8),
        throwsArgumentError,
      );
    });

    test('requires the source suggestion on the same page', () {
      expect(
        () => _field(
          provenance: Provenance.machine,
          sourceSuggestionId: 's_p1_0001',
          suggestionConfidence: 0.8,
        ),
        throwsArgumentError,
      );
      expect(
        () => _field(
          provenance: Provenance.machine,
          sourceSuggestionId: 's_p0_0001',
          suggestionConfidence: 1.2,
        ),
        throwsArgumentError,
      );
      for (final String alias in <String>['s_p00_0001', 's_p0_00001']) {
        expect(
          () => _field(
            provenance: Provenance.machine,
            sourceSuggestionId: alias,
            suggestionConfidence: 0.8,
          ),
          throwsArgumentError,
          reason: alias,
        );
      }
      // The copied machine confidence follows the recognition-output §2
      // two-decimal rule as well.
      expect(
        () => _field(
          provenance: Provenance.machine,
          sourceSuggestionId: 's_p0_0001',
          suggestionConfidence: 0.825,
        ),
        throwsArgumentError,
      );
    });

    test('enforces the 1–120 label rule and preserves German characters', () {
      expect(_field(label: '  Straße  ').label, 'Straße');
      expect(_field(label: _repeat('A', 120)).label, hasLength(120));
      expect(() => _field(label: _repeat('A', 121)), throwsArgumentError);
      expect(() => _field(label: '   '), throwsArgumentError);
      expect(() => _field(label: 'Na\nme'), throwsArgumentError);
    });

    test('enforces order and UTC timestamps', () {
      expect(_field(order: 0).order, 0);
      expect(() => _field(order: -1), throwsArgumentError);
      final DateTime local = DateTime(2026, 11, 13, 12);
      expect(() => _field(createdAt: local), throwsArgumentError);
      expect(() => _field(updatedAt: local), throwsArgumentError);
    });

    test('enforces field-id shape and limits', () {
      expect(() => _field(id: ''), throwsArgumentError);
      expect(() => _field(id: ' padded'), throwsArgumentError);
      expect(() => _field(id: 'has space'), throwsArgumentError);
      expect(() => _field(id: _repeat('a', 129)), throwsArgumentError);
    });

    test('rejects Unicode whitespace and C1 controls in field ids', () {
      // Machine identifiers must not hide separators that `trim()` and an
      // ASCII-only check would miss: no-break space, Ogham space, the
      // U+2000–U+200A quad family, line/paragraph separators, narrow and
      // medium spaces, ideographic space, and the C1 range.
      for (final String id in <String>[
        'field\u00A0id',
        'field\u1680id',
        'field\u2000id',
        'field\u200Aid',
        'field\u2028id',
        'field\u2029id',
        'field\u202Fid',
        'field\u205Fid',
        'field\u3000id',
        'field\u0085id',
        'field\u009Fid',
      ]) {
        expect(() => _field(id: id), throwsArgumentError);
        expect(() => _mark(fieldId: id), throwsArgumentError);
      }
      expect(_field(id: 'feld-1').id, 'feld-1');
      expect(
        _field(id: 'Straße').id,
        'Straße',
        reason: 'non-ASCII visible identifiers remain valid',
      );
    });

    test('rejects invisible Unicode format controls in field ids', () {
      // Zero-width and bidirectional format characters are not visible and
      // must never be hidden inside a machine identifier.
      for (final String id in <String>[
        'field\u00ADid',
        'field\u061Cid',
        'field\u180Eid',
        'field\u200Bid',
        'field\u200Eid',
        'field\u202Eid',
        'field\u2066id',
        'field\uFEFFid',
        'field\u{E0001}id',
      ]) {
        expect(() => _field(id: id), throwsArgumentError);
        expect(() => _mark(fieldId: id), throwsArgumentError);
      }
      expect(_field(id: 'Straße').id, 'Straße');
      expect(_field(id: '中文').id, '中文');
      expect(_field(id: 'العربية').id, 'العربية');
    });

    test('rejects default-ignorable non-Cf code points in field ids', () {
      // U+034F and the other default-ignorable marks/fillers are invisible
      // even though they are not Cf format controls.
      for (final String id in <String>[
        'field\u034Fid',
        'field\u115Fid',
        'field\u17B4id',
        'field\u180Bid',
        'field\u3164id',
        'field\uFE00id',
        'field\uFFA0id',
      ]) {
        expect(() => _field(id: id), throwsArgumentError);
        expect(() => _mark(fieldId: id), throwsArgumentError);
      }
      // A visible decomposed accent (U+0301) is not default-ignorable and
      // remains a valid identifier.
      expect(_field(id: 'Cafe\u0301').id, 'Cafe\u0301');
    });

    test('accepts only matching values or preserved incompatible content', () {
      final ConfirmedField field = _field(type: FieldType.text);
      expect(
        field.acceptsValue(TextValue(text: 'x', lastEditedAt: _at())),
        isTrue,
      );
      expect(
        field.acceptsValue(
          NumberValue(canonical: '1', rawGerman: '1', lastEditedAt: _at()),
        ),
        isFalse,
      );
      expect(
        field.acceptsValue(
          IncompatibleValue(
            preservedText: 'x',
            reasonCode: 'text_to_checkbox',
            lastEditedAt: _at(),
          ),
        ),
        isTrue,
      );
    });

    test('checks page bounds and clears machine fields with copyWith', () {
      final ConfirmedField field = _field(
        rect: Rect.fromLTWH(0, 0, 595.5, 842),
      );
      expect(field.fitsWithinPage(_a4()), isTrue);
      expect(
        _field(rect: Rect.fromLTWH(0, 0, 596, 842)).fitsWithinPage(_a4()),
        isFalse,
      );

      final ConfirmedField machine = _field(
        provenance: Provenance.machine,
        sourceSuggestionId: 's_p0_0001',
        suggestionConfidence: 0.8,
      );
      final ConfirmedField user = machine.copyWith(
        provenance: Provenance.user,
        sourceSuggestionId: null,
        suggestionConfidence: null,
      );
      expect(user.provenance, Provenance.user);
      expect(user.sourceSuggestionId, isNull);
      expect(user.suggestionConfidence, isNull);
      expect(
        () => machine.copyWith(provenance: Provenance.user),
        throwsArgumentError,
      );
    });

    test('keeps confirmed-field geometry exact', () {
      // The 1/8 pt suggestion grid is deliberately not applied to corrected
      // field geometry (FR-024).
      final Rect raw = Rect.fromLTWH(10.07, 20.03, 99.99, 14.94);
      final ConfirmedField field = _field(rect: raw);
      expect(field.rect, raw);
      expect(field.toJson()['rect'], raw.toJson());
    });

    test('toString never echoes the label', () {
      expect(_field(label: 'Geheim').toString(), isNot(contains('Geheim')));
    });
  });

  group('SignatureMark', () {
    test('builds a mark and matches only its signature field', () {
      final SignatureMark mark = _mark();
      final ConfirmedField matching = _field(
        id: mark.fieldId,
        type: FieldType.signature,
        pageIndex: mark.pageIndex,
      );
      expect(mark.describesField(matching), isTrue);
      expect(
        mark.describesField(
          _field(id: mark.fieldId, pageIndex: mark.pageIndex),
        ),
        isFalse,
      );
      expect(
        mark.describesField(
          _field(
            id: mark.fieldId,
            type: FieldType.signature,
            pageIndex: mark.pageIndex + 1,
          ),
        ),
        isFalse,
      );
      expect(
        mark.describesField(
          _field(
            id: '9c858901-8a57-4791-81fe-4c455b099bc9',
            type: FieldType.signature,
          ),
        ),
        isFalse,
      );
    });

    test('enforces the positive 1024-pixel long edge', () {
      expect(_mark(widthPx: 1024, heightPx: 10).widthPx, 1024);
      expect(_mark(widthPx: 10, heightPx: 1024).heightPx, 1024);
      expect(() => _mark(widthPx: 0), throwsArgumentError);
      expect(() => _mark(heightPx: 0), throwsArgumentError);
      expect(() => _mark(widthPx: -1), throwsArgumentError);
      expect(() => _mark(widthPx: 1025), throwsArgumentError);
      expect(() => _mark(heightPx: 1025), throwsArgumentError);
    });

    test('enforces UUIDv4, SHA-256, and UTC', () {
      expect(() => _mark(assetId: 'not-a-uuid'), throwsArgumentError);
      expect(() => _mark(assetId: _assetId.toUpperCase()), throwsArgumentError);
      expect(() => _mark(sha256: _repeat('A', 64)), throwsArgumentError);
      expect(() => _mark(sha256: _repeat('a', 63)), throwsArgumentError);
      expect(() => _mark(sha256: _repeat('a', 65)), throwsArgumentError);
      expect(
        () => _mark(capturedAt: DateTime(2026, 11, 13, 12)),
        throwsArgumentError,
      );
    });

    test('round-trips JSON and keeps equality', () {
      final SignatureMark mark = _mark();
      final SignatureMark parsed = SignatureMark.fromJson(
        _jsonRoundTrip(mark.toJson()),
      );
      expect(parsed, mark);
      expect(parsed.hashCode, mark.hashCode);
      expect(parsed.copyWith(widthPx: 1024), isNot(equals(mark)));
    });
  });

  group('FieldVerification', () {
    test('requires reviewedAt exactly for confirmed and corrected', () {
      expect(
        FieldVerification(state: FieldVerificationState.unreviewed).reviewedAt,
        isNull,
      );
      expect(
        () => FieldVerification(
          state: FieldVerificationState.unreviewed,
          reviewedAt: _at(),
        ),
        throwsArgumentError,
      );
      expect(
        () => FieldVerification(state: FieldVerificationState.confirmed),
        throwsArgumentError,
      );
      expect(
        () => FieldVerification(state: FieldVerificationState.corrected),
        throwsArgumentError,
      );
      expect(
        FieldVerification(
          state: FieldVerificationState.confirmed,
          reviewedAt: _at(),
        ).state,
        FieldVerificationState.confirmed,
      );
      expect(
        FieldVerification(
          state: FieldVerificationState.corrected,
          reviewedAt: _at(),
        ).reviewedAt,
        _at(),
      );
      expect(
        FieldVerification(state: FieldVerificationState.rejected).reviewedAt,
        isNull,
      );
      expect(
        FieldVerification(
          state: FieldVerificationState.rejected,
          reviewedAt: _at(),
        ).reviewedAt,
        _at(),
      );
    });

    test('rejects duplicate warnings and sorts the stored list', () {
      final FieldVerification verification = FieldVerification(
        state: FieldVerificationState.confirmed,
        reviewedAt: _at(),
        warnings: const <WarningCode>[
          WarningCode.conflict,
          WarningCode.overflow,
        ],
      );
      expect(verification.warnings, <WarningCode>[
        WarningCode.overflow,
        WarningCode.conflict,
      ]);
      expect(
        () => FieldVerification(
          state: FieldVerificationState.confirmed,
          reviewedAt: _at(),
          warnings: const <WarningCode>[
            WarningCode.conflict,
            WarningCode.conflict,
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => FieldVerification(
          state: FieldVerificationState.confirmed,
          reviewedAt: DateTime(2026, 11, 13, 12),
        ),
        throwsArgumentError,
      );
    });

    test('round-trips JSON and equality', () {
      final FieldVerification verification = FieldVerification(
        state: FieldVerificationState.corrected,
        reviewedAt: _at(),
        warnings: const <WarningCode>[
          WarningCode.lowConfidence,
          WarningCode.incompatibleContent,
        ],
      );
      final FieldVerification parsed = FieldVerification.fromJson(
        _jsonRoundTrip(verification.toJson()),
      );
      expect(parsed, verification);
      expect(parsed.hashCode, verification.hashCode);
      expect(parsed.warnings, verification.warnings);

      final FieldVerification unreviewed = verification.copyWith(
        state: FieldVerificationState.unreviewed,
        reviewedAt: null,
      );
      expect(unreviewed.state, FieldVerificationState.unreviewed);
      expect(unreviewed.reviewedAt, isNull);
    });
  });

  group('FieldValidation', () {
    test('ok, warning, and error states are distinct', () {
      final FieldValidation warning = FieldValidation.warning(
        WarningCode.overflow,
        'FLD-001',
      );
      final FieldValidation error = FieldValidation.error('NUM-001');
      expect(FieldValidation.ok.isOk, isTrue);
      expect(FieldValidation.ok.isWarning, isFalse);
      expect(FieldValidation.ok.isError, isFalse);
      expect(warning.isWarning, isTrue);
      expect(warning.warningCode, WarningCode.overflow);
      expect(warning.messageKey, 'FLD-001');
      expect(warning.errorCode, isNull);
      expect(error.isError, isTrue);
      expect(error.errorCode, 'NUM-001');
      expect(error.warningCode, isNull);
      expect(FieldValidation.ok, FieldValidation.ok);
    });

    test('rejects invalid message keys and catalog codes', () {
      expect(
        () => FieldValidation.warning(WarningCode.overflow, 'not a key'),
        throwsArgumentError,
      );
      expect(
        () => FieldValidation.warning(WarningCode.overflow, ''),
        throwsArgumentError,
      );
      expect(() => FieldValidation.error('num-1'), throwsArgumentError);
      expect(() => FieldValidation.error('NUM-1'), throwsArgumentError);
      expect(() => FieldValidation.error('TOOLONG-001'), throwsArgumentError);
    });

    test('round-trips all three states and rejects unknown statuses', () {
      final List<FieldValidation> validations = <FieldValidation>[
        FieldValidation.ok,
        FieldValidation.warning(WarningCode.conflict, 'FLD-002'),
        FieldValidation.error('DAT-001'),
      ];
      for (final FieldValidation validation in validations) {
        final FieldValidation parsed = FieldValidation.fromJson(
          _jsonRoundTrip(validation.toJson()),
        );
        expect(parsed, validation, reason: '$validation');
        expect(parsed.hashCode, validation.hashCode);
      }
      expect(
        () => FieldValidation.fromJson(<String, Object?>{'status': 'other'}),
        throwsFormatException,
      );
    });
  });

  group('FieldValue lengths and control characters', () {
    test('text accepts 10,000 characters and rejects 10,001', () {
      expect(
        TextValue(text: _repeat('a', 10000), lastEditedAt: _at()).text,
        hasLength(10000),
      );
      expect(
        () => TextValue(text: _repeat('a', 10001), lastEditedAt: _at()),
        throwsArgumentError,
      );
    });

    test('text removes line breaks and rejects control characters', () {
      expect(
        () => TextValue(text: 'line 1\nline 2', lastEditedAt: _at()),
        throwsArgumentError,
      );
      expect(
        () => TextValue(text: 'tab\there', lastEditedAt: _at()),
        throwsArgumentError,
      );
      expect(
        () => TextValue(text: 'bell\u0007', lastEditedAt: _at()),
        throwsArgumentError,
      );
      expect(
        () => TextValue(text: 'del\u007f', lastEditedAt: _at()),
        throwsArgumentError,
      );
      expect(
        TextValue(text: 'Straße Müller-Lüdenscheidt', lastEditedAt: _at()).text,
        'Straße Müller-Lüdenscheidt',
      );
    });

    test('multiline preserves newlines and applies the same length cap', () {
      expect(
        MultilineValue(text: 'line 1\nline 2', lastEditedAt: _at()).text,
        'line 1\nline 2',
      );
      expect(
        MultilineValue(text: _repeat('a', 10000), lastEditedAt: _at()).text,
        hasLength(10000),
      );
      expect(
        () => MultilineValue(text: _repeat('a', 10001), lastEditedAt: _at()),
        throwsArgumentError,
      );
      expect(
        () => MultilineValue(text: 'windows\r\n', lastEditedAt: _at()),
        throwsArgumentError,
      );
      expect(
        () => MultilineValue(text: 'tab\there', lastEditedAt: _at()),
        throwsArgumentError,
      );
    });

    test('preserved incompatible content is kept verbatim', () {
      const String preserved = 'a\nb\tc\u0001';
      final IncompatibleValue value = IncompatibleValue(
        preservedText: preserved,
        reasonCode: 'text_to_checkbox',
        lastEditedAt: _at(),
      );
      expect(value.preservedText, preserved);
      expect(value.type, isNull);
      expect(value.kind, 'incompatible');
      expect(
        IncompatibleValue(
          preservedText: _repeat('a', 10000),
          reasonCode: 'text_to_checkbox',
          lastEditedAt: _at(),
        ).preservedText,
        hasLength(10000),
      );
      expect(
        () => IncompatibleValue(
          preservedText: _repeat('a', 10001),
          reasonCode: 'text_to_checkbox',
          lastEditedAt: _at(),
        ),
        throwsArgumentError,
      );
      expect(
        () => IncompatibleValue(
          preservedText: 'x',
          reasonCode: 'Bad Code',
          lastEditedAt: _at(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('FieldValue canonical shapes', () {
    test('number accepts normalized decimals only', () {
      for (final String canonical in <String>[
        '0',
        '1',
        '-1',
        '3.14',
        '-0.5',
        '0007',
      ]) {
        expect(
          NumberValue(
            canonical: canonical,
            rawGerman: '1.234,56',
            lastEditedAt: _at(),
          ).canonical,
          canonical,
          reason: canonical,
        );
      }
      for (final String canonical in <String>[
        '',
        '+1',
        '1e3',
        '.5',
        '1,5',
        '1.',
        '--1',
        ' ',
      ]) {
        expect(
          () => NumberValue(
            canonical: canonical,
            rawGerman: '1',
            lastEditedAt: _at(),
          ),
          throwsArgumentError,
          reason: 'canonical "$canonical"',
        );
      }
      expect(
        () => NumberValue(canonical: '1', rawGerman: '', lastEditedAt: _at()),
        throwsArgumentError,
      );
      expect(
        () =>
            NumberValue(canonical: '1', rawGerman: '1\n', lastEditedAt: _at()),
        throwsArgumentError,
      );
    });

    test('date accepts real calendar dates only', () {
      for (final String canonical in <String>[
        '2026-11-13',
        '2024-02-29',
        '2000-02-29',
        '0000-01-01',
        '9999-12-31',
      ]) {
        expect(
          DateValue(canonical: canonical, lastEditedAt: _at()).canonical,
          canonical,
          reason: canonical,
        );
      }
      for (final String canonical in <String>[
        '2026-02-29',
        '1900-02-29',
        '2026-13-01',
        '2026-00-10',
        '2026-1-1',
        '13.11.2026',
        '2026-11-32',
      ]) {
        expect(
          () => DateValue(canonical: canonical, lastEditedAt: _at()),
          throwsArgumentError,
          reason: 'canonical "$canonical"',
        );
      }
    });

    test('checkbox defaults to unchecked', () {
      expect(CheckboxValue(lastEditedAt: _at()).checked, isFalse);
      expect(CheckboxValue(checked: true, lastEditedAt: _at()).checked, isTrue);
    });

    test('signature values require a lowercase UUIDv4', () {
      expect(
        SignatureValue(
          signatureAssetId: _assetId,
          lastEditedAt: _at(),
        ).signatureAssetId,
        _assetId,
      );
      expect(
        () =>
            SignatureValue(signatureAssetId: 'not-a-uuid', lastEditedAt: _at()),
        throwsArgumentError,
      );
      expect(
        () => SignatureValue(
          signatureAssetId: _assetId.toUpperCase(),
          lastEditedAt: _at(),
        ),
        throwsArgumentError,
      );
    });

    test('every variant rejects a non-UTC lastEditedAt', () {
      final DateTime local = DateTime(2026, 11, 13, 12);
      final List<void Function(DateTime)> factories = <void Function(DateTime)>[
        (DateTime at) => TextValue(text: 'x', lastEditedAt: at),
        (DateTime at) => MultilineValue(text: 'x', lastEditedAt: at),
        (DateTime at) =>
            NumberValue(canonical: '1', rawGerman: '1', lastEditedAt: at),
        (DateTime at) => DateValue(canonical: '2026-11-13', lastEditedAt: at),
        (DateTime at) => CheckboxValue(lastEditedAt: at),
        (DateTime at) =>
            SignatureValue(signatureAssetId: _assetId, lastEditedAt: at),
        (DateTime at) => IncompatibleValue(
          preservedText: 'x',
          reasonCode: 'text_to_checkbox',
          lastEditedAt: at,
        ),
      ];
      for (final void Function(DateTime) factory in factories) {
        expect(() => factory(local), throwsArgumentError);
      }
    });

    test('metadata defaults and copyWithMetadata preserve content', () {
      final TextValue value = TextValue(text: 'x', lastEditedAt: _at());
      expect(value.overflow, isFalse);
      final TextValue overflowed = value.copyWithMetadata(overflow: true);
      expect(overflowed.overflow, isTrue);
      expect(overflowed.text, 'x');
      expect(overflowed.lastEditedAt, value.lastEditedAt);
    });

    test('JSON round-trips every variant with its type discriminator', () {
      final List<FieldValue> values = <FieldValue>[
        TextValue(text: 'text', lastEditedAt: _at()),
        MultilineValue(text: 'a\nb', lastEditedAt: _at()),
        NumberValue(
          canonical: '-12.5',
          rawGerman: '-12,5',
          lastEditedAt: _at(),
        ),
        DateValue(canonical: '2026-11-13', lastEditedAt: _at()),
        CheckboxValue(checked: true, lastEditedAt: _at()),
        SignatureValue(signatureAssetId: _assetId, lastEditedAt: _at()),
        IncompatibleValue(
          preservedText: 'a\nb',
          reasonCode: 'text_to_checkbox',
          lastEditedAt: _at(),
        ),
      ];
      for (final FieldValue value in values) {
        final FieldValue parsed = FieldValue.fromJson(
          _jsonRoundTrip(value.toJson()),
        );
        expect(parsed, value, reason: value.kind);
        expect(parsed.hashCode, value.hashCode);
        expect(parsed.kind, value.kind);
        expect(parsed.type, value.type);
      }
    });

    test('JSON timestamps are truncated to milliseconds', () {
      final DateTime precise = DateTime.utc(2026, 1, 2, 3, 4, 5, 6, 7);
      final TextValue value = TextValue(text: 'x', lastEditedAt: precise);
      expect(value.lastEditedAt.microsecond, 7);
      expect(value.toJson()['lastEditedAt'], '2026-01-02T03:04:05.006Z');
    });

    test('JSON parsing fails closed for unknown or malformed values', () {
      expect(
        () => FieldValue.fromJson(<String, Object?>{
          'type': 'unknown',
          'lastEditedAt': '2026-11-13T12:00:00.000Z',
          'overflow': false,
        }),
        throwsFormatException,
      );
      expect(
        () => FieldValue.fromJson(<String, Object?>{
          'type': 'text',
          'text': 'x',
          'lastEditedAt': '2026-11-13T12:00:00.000Z',
        }),
        throwsFormatException,
      );
      expect(
        () => FieldValue.fromJson(<String, Object?>{
          'type': 'text',
          'text': 'x',
          'lastEditedAt': '2026-11-13T12:00:00',
          'overflow': false,
        }),
        throwsFormatException,
      );
    });

    test('value equality is variant-aware', () {
      expect(
        TextValue(text: 'x', lastEditedAt: _at()),
        TextValue(text: 'x', lastEditedAt: _at()),
      );
      expect(
        TextValue(text: 'x', lastEditedAt: _at()),
        isNot(equals(MultilineValue(text: 'x', lastEditedAt: _at()))),
      );
      expect(
        TextValue(text: 'x', lastEditedAt: _at()),
        isNot(equals(TextValue(text: 'y', lastEditedAt: _at()))),
      );
    });
  });

  group('privacy', () {
    test('validation errors do not echo labels or values', () {
      final String privateLabel = _repeat('PRIVATE', 30);
      expect(
        () => _suggestion(labelText: privateLabel),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.toString(),
            'toString',
            isNot(contains('PRIVATE')),
          ),
        ),
      );
      expect(
        () => TextValue(text: 'secret\u0001', lastEditedAt: _at()),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.toString(),
            'toString',
            isNot(contains('secret')),
          ),
        ),
      );
      expect(
        () => _field(label: _repeat('PRIVATE', 20)),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.toString(),
            'toString',
            isNot(contains('PRIVATE')),
          ),
        ),
      );
    });

    test('value toString does not reveal content', () {
      expect(
        TextValue(text: 'secret', lastEditedAt: _at()).toString(),
        isNot(contains('secret')),
      );
      expect(
        MultilineValue(text: 'secret', lastEditedAt: _at()).toString(),
        isNot(contains('secret')),
      );
      expect(
        NumberValue(
          canonical: '4711',
          rawGerman: '4711',
          lastEditedAt: _at(),
        ).toString(),
        isNot(contains('4711')),
      );
      expect(
        DateValue(canonical: '1990-01-01', lastEditedAt: _at()).toString(),
        isNot(contains('1990')),
      );
      expect(
        IncompatibleValue(
          preservedText: 'secret',
          reasonCode: 'text_to_checkbox',
          lastEditedAt: _at(),
        ).toString(),
        isNot(contains('secret')),
      );
    });

    test('closed keyword diagnostics do not echo rejected input', () {
      const String arbitrary = 'privateKeyword';
      expect(
        () => SuggestionCue.keyword(arbitrary),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.toString(),
            'toString',
            isNot(contains(arbitrary)),
          ),
        ),
      );
      expect(
        () => SuggestionCue.fromWire('keyword_$arbitrary'),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.toString(),
            'toString',
            isNot(contains(arbitrary)),
          ),
        ),
      );
    });
  });
}
