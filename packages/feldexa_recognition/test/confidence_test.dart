// T054 host-VM tests for the confidence and uncertainty model.
//
// Normative sources:
//  * specs/001-scanned-form-workflow/contracts/recognition-output.md
//    sections 2, 3.1, 3.3, and 3.4;
//  * specs/001-scanned-form-workflow/spec.md FR-015 and FR-083.
//
// The model is pure and deterministic: these tests assert exact decimal
// doubles (never approximations), the integer-hundredths representation, the
// §3.1 cue-family mapping, invalid-input rejection, and the absence of any
// write, persistence, or caller-object mutation.
@TestOn('vm')
library;

import 'dart:io';

import 'package:feldexa_recognition/src/confidence.dart';
import 'package:flutter_test/flutter_test.dart';

ConfidenceInputs _inputs({
  int families = 0,
  bool keyword = false,
  bool geometry = false,
  double skew = 0.0,
  Contrast contrast = Contrast.normal,
  bool ocrUsed = true,
  bool agree = false,
}) {
  return ConfidenceInputs(
    supportingCueFamilies: families,
    credibleKeywordMatchesInferredType: keyword,
    geometryWithinTypicalBounds: geometry,
    skewDegrees: skew,
    contrast: contrast,
    ocrUsed: ocrUsed,
    twoIndependentOcrLinesAgree: agree,
  );
}

ConfidenceAssessment _score({
  int families = 0,
  bool keyword = false,
  bool geometry = false,
  double skew = 0.0,
  Contrast contrast = Contrast.normal,
  bool ocrUsed = true,
  bool agree = false,
}) {
  return ConfidenceModel.evaluate(
    _inputs(
      families: families,
      keyword: keyword,
      geometry: geometry,
      skew: skew,
      contrast: contrast,
      ocrUsed: ocrUsed,
      agree: agree,
    ),
  );
}

/// Asserts the exact two-decimal representation and its complement.
void _expectExact(ConfidenceAssessment assessment, int hundredths) {
  expect(assessment.confidenceHundredths, hundredths);
  expect(assessment.confidence, hundredths / 100);
  expect(assessment.uncertaintyHundredths, 100 - hundredths);
  expect(assessment.uncertainty, (100 - hundredths) / 100);
  // Both fields are exact two-decimal doubles, so the pair sums to exactly
  // one. `1.0 - confidence` can be one ulp away; the decimal representation
  // is authoritative (see confidence.dart).
  expect(assessment.confidence + assessment.uncertainty, 1.0);
  expect(
    (assessment.uncertainty - (1.0 - assessment.confidence)).abs(),
    lessThanOrEqualTo(1e-12),
  );
  expect(
    assessment.presentation,
    ConfidencePresentation.forConfidenceHundredths(hundredths),
  );
}

void main() {
  group('T054 confidence formula', () {
    test('the base confidence is exactly 0.35', () {
      _expectExact(_score(), 35);
    });

    test('each supporting cue family adds exactly 0.12 up to four', () {
      _expectExact(_score(families: 1), 47);
      _expectExact(_score(families: 2), 59);
      _expectExact(_score(families: 3), 71);
      _expectExact(_score(families: 4), 83);
    });

    test('the cue-family bonus is capped at 0.48', () {
      _expectExact(_score(families: 5), 83);
      _expectExact(_score(families: 40), 83);
    });

    test('a credible keyword match adds exactly 0.10', () {
      _expectExact(_score(keyword: true), 45);
    });

    test('geometry inside typical bounds adds exactly 0.05', () {
      _expectExact(_score(geometry: true), 40);
    });

    test('skew strictly greater than 2.0 subtracts exactly 0.25', () {
      // The boundary itself is inclusive and unpenalized.
      _expectExact(_score(skew: 2.0), 35);
      _expectExact(_score(skew: -2.0), 35);
      _expectExact(_score(skew: 2.0001), 10);
      _expectExact(_score(skew: -2.0001), 10);
    });

    test('low contrast subtracts exactly 0.20', () {
      _expectExact(_score(contrast: Contrast.low), 15);
    });

    test('missing OCR subtracts exactly 0.15', () {
      _expectExact(_score(ocrUsed: false), 20);
    });

    test('two agreeing OCR lines add exactly 0.10', () {
      _expectExact(_score(agree: true), 45);
    });

    test('all factors combine additively', () {
      _expectExact(
        _score(
          families: 1,
          keyword: true,
          geometry: true,
          skew: 3.0,
          contrast: Contrast.low,
          ocrUsed: false,
          agree: true,
        ),
        12,
      );
    });

    test('the all-positive score clamps to exactly 0.98', () {
      _expectExact(
        _score(families: 4, keyword: true, geometry: true, agree: true),
        98,
      );
    });

    test('the all-negative score clamps to exactly 0.05', () {
      _expectExact(
        _score(skew: 10.0, contrast: Contrast.low, ocrUsed: false),
        5,
      );
    });

    test('results are exact doubles, not floating-point approximations', () {
      expect(_score(families: 1).confidence, 0.47);
      expect(_score(families: 2).confidence, 0.59);
      expect(_score(families: 3).confidence, 0.71);
      expect(_score(families: 4).confidence, 0.83);
      expect(
        _score(
          families: 4,
          keyword: true,
          geometry: true,
          agree: true,
        ).confidence,
        0.98,
      );
      expect(
        _score(skew: 10.0, contrast: Contrast.low, ocrUsed: false).confidence,
        0.05,
      );
    });

    test('uncertainty is the exact two-decimal complement for every value', () {
      for (int families = 0; families <= 4; families++) {
        for (int mask = 0; mask < 16; mask++) {
          final ConfidenceAssessment assessment = _score(
            families: families,
            keyword: mask & 1 != 0,
            geometry: mask & 2 != 0,
            skew: mask & 4 != 0 ? 3.0 : 0.0,
            contrast: mask & 8 != 0 ? Contrast.low : Contrast.normal,
            ocrUsed: mask & 4 == 0,
          );
          final int hundredths = assessment.confidenceHundredths;
          expect(assessment.uncertaintyHundredths, 100 - hundredths);
          expect(assessment.uncertainty, (100 - hundredths) / 100);
          expect(assessment.confidence + assessment.uncertainty, 1.0);
          expect(
            (assessment.uncertainty - (1.0 - assessment.confidence)).abs(),
            lessThanOrEqualTo(1e-12),
          );
        }
      }
    });
  });

  group('T054 §3.4 presentation thresholds', () {
    test('0.75 and above is a solid outline', () {
      expect(
        ConfidencePresentation.forConfidenceHundredths(75),
        ConfidencePresentation.solidOutline,
      );
      expect(
        ConfidencePresentation.forConfidenceHundredths(76),
        ConfidencePresentation.solidOutline,
      );
      expect(
        ConfidencePresentation.forConfidenceHundredths(98),
        ConfidencePresentation.solidOutline,
      );
      expect(
        ConfidencePresentation.forConfidenceHundredths(100),
        ConfidencePresentation.solidOutline,
      );
    });

    test('0.50 through 0.74 is a dashed outline', () {
      expect(
        ConfidencePresentation.forConfidenceHundredths(50),
        ConfidencePresentation.dashedOutline,
      );
      expect(
        ConfidencePresentation.forConfidenceHundredths(74),
        ConfidencePresentation.dashedOutline,
      );
    });

    test('below 0.50 is dashed with the uncertainty badge', () {
      expect(
        ConfidencePresentation.forConfidenceHundredths(49),
        ConfidencePresentation.dashedWithUncertaintyBadge,
      );
      expect(
        ConfidencePresentation.forConfidenceHundredths(5),
        ConfidencePresentation.dashedWithUncertaintyBadge,
      );
      expect(
        ConfidencePresentation.forConfidenceHundredths(0),
        ConfidencePresentation.dashedWithUncertaintyBadge,
      );
    });

    test('the model applies the thresholds at 0.76, 0.74, 0.50, and 0.49', () {
      final ConfidenceAssessment solid = _score(families: 3, geometry: true);
      expect(solid.confidence, 0.76);
      expect(solid.presentation, ConfidencePresentation.solidOutline);

      final ConfidenceAssessment dashed = _score(
        families: 2,
        keyword: true,
        geometry: true,
      );
      expect(dashed.confidence, 0.74);
      expect(dashed.presentation, ConfidencePresentation.dashedOutline);

      final ConfidenceAssessment dashedAtBoundary = _score(
        keyword: true,
        geometry: true,
      );
      expect(dashedAtBoundary.confidence, 0.50);
      expect(
        dashedAtBoundary.presentation,
        ConfidencePresentation.dashedOutline,
      );

      final ConfidenceAssessment badged = _score(
        families: 2,
        keyword: true,
        contrast: Contrast.low,
      );
      expect(badged.confidence, 0.49);
      expect(
        badged.presentation,
        ConfidencePresentation.dashedWithUncertaintyBadge,
      );
    });

    test(
      'low-confidence suggestions keep a stable badge identifier (FR-083)',
      () {
        final ConfidenceAssessment assessment = _score(
          skew: 10.0,
          contrast: Contrast.low,
          ocrUsed: false,
        );
        expect(assessment.confidence, 0.05);
        expect(
          assessment.presentation,
          ConfidencePresentation.dashedWithUncertaintyBadge,
        );
        expect(assessment.presentation.name, 'dashedWithUncertaintyBadge');
        expect(assessment.presentation.showsUncertaintyBadge, isTrue);
        expect(assessment.showsUncertaintyBadge, isTrue);
        expect(
          ConfidencePresentation.solidOutline.showsUncertaintyBadge,
          isFalse,
        );
      },
    );

    test('out-of-range hundredths are rejected with a content-free error', () {
      for (final int hundredths in <int>[-1, 101]) {
        expect(
          () => ConfidencePresentation.forConfidenceHundredths(hundredths),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError error) => error.message,
              'message',
              isNot(contains('$hundredths')),
            ),
          ),
        );
      }
    });
  });

  group('T054 §3.1 cue-family mapping', () {
    const Map<String, CueFamily> expected = <String, CueFamily>{
      'underline': CueFamily.line,
      'box': CueFamily.box,
      'grid_cell': CueFamily.grid,
      'whitespace': CueFamily.whitespace,
      'alignment_left': CueFamily.alignment,
      'label_below': CueFamily.ocrAlignment,
      'ocr_alignment_right': CueFamily.ocrAlignment,
      'ocr_alignment_below': CueFamily.ocrAlignment,
      'small_square': CueFamily.geometry,
      'table_cell': CueFamily.geometry,
      'signature_area': CueFamily.geometry,
      'numeric_context': CueFamily.ocrContext,
      'date_context': CueFamily.ocrContext,
    };

    test('every fixed §3.1 token maps to its documented family', () {
      for (final MapEntry<String, CueFamily> entry in expected.entries) {
        final CueFamilyAssignment assignment = CueFamilyAssignment.of(
          entry.key,
        );
        expect(assignment.family, entry.value, reason: entry.key);
        expect(assignment.familyId, entry.value.name, reason: entry.key);
        expect(assignment.isExtension, isFalse, reason: entry.key);
        expect(
          CueFamilyAssignment.of(entry.key),
          assignment,
          reason: entry.key,
        );
      }
    });

    test('every keyword_* token maps to the keyword family', () {
      for (final String cue in <String>[
        'keyword_name',
        'keyword_unterschrift',
        'keyword_not_in_lexicon',
        'keyword_',
      ]) {
        final CueFamilyAssignment assignment = CueFamilyAssignment.of(cue);
        expect(assignment.family, CueFamily.keyword, reason: cue);
        expect(assignment.familyId, 'keyword', reason: cue);
        expect(assignment.isExtension, isFalse, reason: cue);
      }
    });

    test(
      'each distinct unknown token gets its own stable extension family',
      () {
        final CueFamilyAssignment first = CueFamilyAssignment.of('future_cue');
        final CueFamilyAssignment other = CueFamilyAssignment.of('other_cue');

        expect(first.family, isNull);
        expect(first.isExtension, isTrue);
        expect(first.familyId, 'extension:future_cue');
        expect(CueFamilyAssignment.of('future_cue'), first);
        expect(CueFamilyAssignment.of('future_cue').hashCode, first.hashCode);
        expect(other, isNot(first));
        expect(other.familyId, 'extension:other_cue');

        final CueFamilyAssignment empty = CueFamilyAssignment.of('');
        expect(empty.family, isNull);
        expect(empty.familyId, 'extension:');
      },
    );

    test('distinctFamilies deduplicates and sorts deterministically', () {
      final List<CueFamilyAssignment> families =
          CueFamilyAssignment.distinctFamilies(<String>[
            'underline',
            'underline',
            'box',
            'extension_a',
            'extension_b',
            'extension_a',
          ]);

      expect(
        families.map((CueFamilyAssignment family) => family.familyId).toList(),
        <String>[
          'box',
          'extension:extension_a',
          'extension:extension_b',
          'line',
        ],
      );
      expect(
        () => families.add(CueFamilyAssignment.of('box')),
        throwsUnsupportedError,
      );
      expect(
        CueFamilyAssignment.distinctFamilies(<String>['underline']).length,
        1,
      );
      expect(CueFamilyAssignment.distinctFamilies(<String>[]), isEmpty);
    });

    test('the mapped family count feeds the confidence input exactly', () {
      final List<String> cues = <String>[
        'underline',
        'ocr_alignment_right',
        'keyword_name',
      ];
      final int families = CueFamilyAssignment.distinctFamilies(cues).length;
      expect(families, 3);

      final ConfidenceAssessment assessment = _score(
        families: families,
        keyword: true,
      );
      _expectExact(assessment, 81);
      expect(assessment.confidence, 0.81);
    });
  });

  group('T054 determinism and invalid input', () {
    test('repeated evaluation of the same inputs is identical', () {
      final ConfidenceInputs inputs = _inputs(
        families: 3,
        keyword: true,
        geometry: true,
        skew: 0.4,
      );

      final ConfidenceAssessment first = ConfidenceModel.evaluate(inputs);
      final ConfidenceAssessment second = ConfidenceModel.evaluate(inputs);
      final ConfidenceAssessment third = ConfidenceModel.evaluate(inputs);

      expect(second.confidenceHundredths, first.confidenceHundredths);
      expect(second.confidence, first.confidence);
      expect(second.uncertainty, first.uncertainty);
      expect(second.presentation, first.presentation);
      expect(third.confidenceHundredths, first.confidenceHundredths);
    });

    test('negative cue families are rejected with a content-free error', () {
      expect(
        () => _inputs(families: -1),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            'supportingCueFamilies must be non-negative',
          ),
        ),
      );
      expect(
        () => _inputs(families: -999),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            isNot(contains('-999')),
          ),
        ),
      );
    });

    test('non-finite or out-of-range skew is rejected', () {
      for (final double skew in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
        10.0001,
        -10.0001,
      ]) {
        expect(
          () => _inputs(skew: skew),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError error) => error.message,
              'message',
              'skewDegrees must be finite and within -10.0..10.0',
            ),
          ),
          reason: '$skew',
        );
      }
    });

    test('skew at the inclusive input bounds is accepted', () {
      _expectExact(_score(skew: 10.0), 10);
      _expectExact(_score(skew: -10.0), 10);
    });

    test('error messages never echo the rejected input value', () {
      try {
        _inputs(families: -7);
        fail('expected ArgumentError');
      } on ArgumentError catch (error) {
        expect('${error.message}', isNot(contains('-7')));
      }

      try {
        _inputs(skew: 10.0001);
        fail('expected ArgumentError');
      } on ArgumentError catch (error) {
        expect('${error.message}', isNot(contains('10.0001')));
      }
    });
  });

  group('T054 no side effects', () {
    test('does not write, persist, or mutate caller objects', () {
      final List<String> cues = <String>[
        'underline',
        'keyword_name',
        'future_cue',
      ];
      final List<String> cueSnapshot = List<String>.of(cues);
      final ConfidenceInputs inputs = _inputs(
        families: 3,
        keyword: true,
        geometry: true,
        skew: 0.4,
      );

      final ConfidenceAssessment first = ConfidenceModel.evaluate(inputs);
      final List<CueFamilyAssignment> families =
          CueFamilyAssignment.distinctFamilies(cues);
      final ConfidenceAssessment second = ConfidenceModel.evaluate(inputs);

      expect(cues, cueSnapshot);
      expect(
        families.map((CueFamilyAssignment family) => family.familyId).toList(),
        <String>['extension:future_cue', 'keyword', 'line'],
      );
      expect(inputs.supportingCueFamilies, 3);
      expect(inputs.credibleKeywordMatchesInferredType, isTrue);
      expect(inputs.geometryWithinTypicalBounds, isTrue);
      expect(inputs.skewDegrees, 0.4);
      expect(inputs.contrast, Contrast.normal);
      expect(inputs.ocrUsed, isTrue);
      expect(inputs.twoIndependentOcrLinesAgree, isFalse);
      expect(second.confidenceHundredths, first.confidenceHundredths);
      expect(second.confidence, first.confidence);
      expect(second.uncertainty, first.uncertainty);

      final Directory original = Directory.current;
      final Directory temporary = Directory.systemTemp.createTempSync(
        't054_confidence_',
      );
      try {
        Directory.current = temporary;
        ConfidenceModel.evaluate(inputs);
        CueFamilyAssignment.distinctFamilies(cues);
        expect(temporary.listSync(), isEmpty);
      } finally {
        Directory.current = original;
        temporary.deleteSync(recursive: true);
      }
    });
  });
}
