// T264 host-VM tests for the exact display-space metrics.
// ignore_for_file: depend_on_referenced_packages

@TestOn('vm')
library;

import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/geometry_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

DisplayRect _rect(double x, double y, double width, double height) =>
    DisplayRect(x: x, y: y, width: width, height: height);

void main() {
  group('rounding', () {
    test('rounds once to the nearest 1/8 pt', () {
      expect(roundToEighth(1.0 / 16), 0.125);
      expect(roundToEighth(1.0 / 24), 0.0);
      expect(roundToEighth(-1.0 / 16), -0.125);
      expect(roundToEighth(10.0 / 3), 3.375);
    });

    test('floors to a 1/8 pt multiple', () {
      expect(floorToEighth(10.0 / 3), 3.25);
      expect(floorToEighth(0), 0);
    });

    test('normalises a rectangle and reports degenerate input as null', () {
      final DisplayRect? normalised = normalizeRect(
        _rect(1.0 / 24, 1.0 / 16, 10.0 / 3, 10.0 / 3),
      );
      expect(normalised, isNotNull);
      expect(normalised!.x, 0);
      expect(normalised.y, 0.125);
      expect(normalised.width, 3.375);
      expect(normalised.height, 3.25);
      expect(normalizeRect(_rect(10, 10, 0.01, 0.01)), isNull);
    });

    test('clamps inward to a page extent that is not a 1/8 pt multiple', () {
      final DisplayRect? normalised = normalizeRect(
        _rect(0, 0, 595.28, 600),
        pageWidthPt: 595.28,
        pageHeightPt: 600,
      );
      expect(normalised, isNotNull);
      expect(normalised!.x + normalised.width, lessThanOrEqualTo(595.28));
      expect((normalised.width * 8) % 1, 0);
    });

    test('rejects a half-supplied page extent', () {
      expect(
        () => normalizeRect(_rect(0, 0, 10, 10), pageWidthPt: 100),
        throwsArgumentError,
      );
    });
  });

  group('lattice metrics', () {
    test('IoU is exact for identical and disjoint rectangles', () {
      final DisplayRect rect = _rect(10, 20, 30, 40);
      expect(iou(rect, rect), 1.0);
      expect(iou(rect, _rect(100, 100, 30, 40)), 0.0);
    });

    test('IoU matches the hand-computed half-overlap', () {
      final DisplayRect a = _rect(0, 0, 10, 10);
      final DisplayRect b = _rect(5, 0, 10, 10);
      expect(iou(a, b), closeTo(50 / 150, 1e-12));
      expect(intersectionAreaPt2(a, b), closeTo(50, 1e-12));
      expect(unionAreaPt2(a, b), closeTo(150, 1e-12));
      expect(areaPt2(a), closeTo(100, 1e-12));
    });

    test('centre distance and gap are measured in display points', () {
      final DisplayRect a = _rect(0, 0, 10, 10);
      final DisplayRect b = _rect(10, 0, 10, 10);
      expect(centerDistancePt(a, b), closeTo(10, 1e-12));
      expect(rectGapPt(a, b), closeTo(0, 1e-12));
      expect(rectGapPt(a, _rect(14, 3, 10, 10)), closeTo(4, 1e-12));
      expect(rectGapPt(a, _rect(14, 6, 10, 10)), closeTo(4, 1e-12));
      expect(
        rectGapPt(a, _rect(14, 16, 10, 10)),
        closeTo(7.211102550927978, 1e-12),
      );
    });

    test('containment fraction is relative to the inner rectangle', () {
      final DisplayRect outer = _rect(0, 0, 100, 100);
      final DisplayRect inner = _rect(25, 25, 50, 50);
      expect(containmentFraction(outer, inner), 1.0);
      expect(containmentFraction(inner, outer), 0.25);
    });

    test('isInsidePage honours the documented tolerance', () {
      expect(
        isInsidePage(
          _rect(0, 0, 595.28, 841.89),
          pageWidthPt: 595.28,
          pageHeightPt: 841.89,
        ),
        isTrue,
      );
      expect(
        isInsidePage(
          _rect(0, 0, 600, 841.89),
          pageWidthPt: 595.28,
          pageHeightPt: 841.89,
        ),
        isFalse,
      );
    });
  });
}
