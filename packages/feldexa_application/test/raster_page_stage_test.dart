// T297 follow-up tests for the bytes-level raster stage.
//
// Evidence class: NONE. These are host-VM tests of `raster_page_stage.dart`.
//
// They pin three follow-ups from the T086B-R reviews (issue #297):
//  * the stage analyses every task with the documented default ink threshold,
//    because the dead per-task `inkThreshold` override is gone (point 1);
//  * one stage message owns the caller's pixel buffer instead of duplicating a
//    full page raster per page (point 4);
//  * the caller-side keyword/type bonus reads the single keyword→type truth of
//    `TypeInference`, not a copy of it (point 8).

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:feldexa_application/src/recognition/raster_page_stage.dart';
import 'package:feldexa_recognition/src/confidence.dart';
import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/raster.dart';
import 'package:feldexa_recognition/src/suggestion_schema.dart';
import 'package:feldexa_recognition/src/type_inference.dart';
import 'package:flutter_test/flutter_test.dart';

/// 144 x 144 pt maps to exactly 400 x 400 px at the 200 DPI analysis scale.
const int _rasterWidth = 400;
const int _rasterHeight = 400;
const int _rasterBytes = _rasterWidth * _rasterHeight;
const double _pageWidthPt = 144;
const double _pageHeightPt = 144;

/// One dark bar on rows 200-201, the fixture candidate of the stage tests.
Uint8List _underlineBytes() {
  final Uint8List bytes = Uint8List(_rasterBytes)
    ..fillRange(0, _rasterBytes, 0xFF);
  for (int y = 200; y < 202; y++) {
    for (int x = 100; x < 200; x++) {
      bytes[y * _rasterWidth + x] = 0;
    }
  }
  return bytes;
}

RasterPageStageTask _task({
  Uint8List? pixels,
  List<LabelObservation> labels = const <LabelObservation>[],
}) {
  return RasterPageStageTask(
    pageIndex: 0,
    pixels: pixels ?? _underlineBytes(),
    width: _rasterWidth,
    height: _rasterHeight,
    pageWidthPt: _pageWidthPt,
    pageHeightPt: _pageHeightPt,
    labels: labels,
    ocrUsed: labels.isNotEmpty,
  );
}

/// The credible label geometry used by the accepted document analysis tests.
LabelObservation _label(String text) {
  return LabelObservation(
    text: text,
    rect: DisplayRect(x: 10, y: 56, width: 22, height: 10),
    ocrConfidence: 0.95,
  );
}

RasterPageStageOutcome _runWithLabel(String text) {
  return runRasterPageStage(_task(labels: <LabelObservation>[_label(text)]));
}

void main() {
  test('the stage analyses with the documented default ink threshold', () {
    final Uint8List pixels = _underlineBytes();
    int? analysedThreshold;
    int? analysedPixels;
    final RasterPageStageOutcome outcome = runRasterPageStage(
      _task(pixels: pixels),
      rasterAnalysis: (GrayRaster raster) {
        // The seam builds the production analysis; recording its threshold and
        // size is how this test reads which threshold the stage really used.
        final RasterAnalysis analysis = RasterAnalysis(raster);
        analysedThreshold = analysis.inkThreshold;
        analysedPixels = raster.width * raster.height;
        return analysis;
      },
    );

    expect(analysedThreshold, defaultInkThreshold);
    expect(analysedPixels, _rasterBytes);
    expect(outcome.isFailed, isFalse);
    expect(outcome.suggestions, isNotEmpty);
  });

  test('one stage message owns the caller buffer instead of copying it', () {
    final Uint8List pixels = _underlineBytes();
    final RasterPageStageTask task = _task(pixels: pixels);

    // A defensive `Uint8List.fromList` in the task constructor would duplicate
    // the whole page raster for every page, on top of the isolate message that
    // the runner already serializes.
    expect(identical(task.pixels, pixels), isTrue);
  });

  test('the keyword/type bonus follows the shared keyword→type truth', () {
    // The four fixed confidence inputs are the documented Phase A decisions
    // (`geometryWithinTypicalBounds` false, no skew estimate, `normal`
    // contrast, no second OCR pass). With the observed cue families they make
    // the section 3.3 keyword bonus the only remaining variable, so the score
    // says whether the stage treated the keyword as matching its type.
    double score(int families, {required bool keywordMatchesType}) {
      return ConfidenceModel.evaluate(
        ConfidenceInputs(
          supportingCueFamilies: families,
          credibleKeywordMatchesInferredType: keywordMatchesType,
          geometryWithinTypicalBounds: false,
          skewDegrees: 0,
          contrast: Contrast.normal,
          ocrUsed: true,
          twoIndependentOcrLinesAgree: false,
        ),
      ).confidence;
    }

    for (final String key in SuggestionSchema.keywordLexiconV1) {
      final RasterPageStageOutcome outcome = _runWithLabel(key);
      final Map<String, Object?> suggestion = outcome.suggestions.single;
      final Map<String, Object?> evidence =
          suggestion['evidence']! as Map<String, Object?>;
      final List<String> cues = (evidence['cues']! as List<Object?>)
          .cast<String>()
          .toList();
      final String proposedType = suggestion['proposedType']! as String;
      final int families = CueFamilyAssignment.distinctFamilies(cues).length;
      final bool expectedBonus = cues
          .where((String cue) => cue.startsWith('keyword_'))
          .map((String cue) => cue.substring('keyword_'.length))
          .any(
            (String matched) =>
                TypeInference.forcedTypeForKey(matched) == proposedType,
          );

      expect(
        score(families, keywordMatchesType: true),
        isNot(score(families, keywordMatchesType: false)),
        reason: 'the §3.3 keyword bonus must be observable for "$key"',
      );
      expect(
        suggestion['confidence'],
        expectedBonus
            ? score(families, keywordMatchesType: true)
            : score(families, keywordMatchesType: false),
        reason:
            'label "$key" must award the keyword bonus exactly when the shared '
            'keyword→type truth forces the inferred type',
      );
    }
  });
}
