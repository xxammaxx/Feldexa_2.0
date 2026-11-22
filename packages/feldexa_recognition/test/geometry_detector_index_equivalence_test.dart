// T086B-P differential/property tests: the indexed box scan must accept
// exactly the candidates the pre-T086B exhaustive scan accepted.
//
// `GeometryDetector.detect` enumerates box candidates with
// `_VerticalRuleIndex`, which returns a *necessary-condition superset* of the
// vertical rules that can be one side of a box. `debugDetectExhaustiveBoxScan`
// keeps the original `O(h^2 * v^2)` enumeration for tests only. Both paths call
// the same `_considerBox` acceptance logic, so their results must be identical
// for every input.
//
// These tests target the cases where a superset index is most likely to lose or
// reorder a candidate: an empty page, a single vertical rule, duplicate
// centre-x rules that the pairing rule has to reject, a box narrower than twice
// the corner tolerance so the two centre windows overlap, rules touching the
// page edge at x0 = 0, a closed grid page, and a deterministic pseudo-random
// rule field with endpoints jittered across the tolerance boundary.
//
// The differential helper is test-only; production `detect` never calls it.
// ignore_for_file: depend_on_referenced_packages

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/raster.dart';
import 'package:flutter_test/flutter_test.dart';

const double _pageWidthPt = 144;
const double _pageHeightPt = 144;
const int _rasterWidth = 400;
const int _rasterHeight = 400;

/// Deterministic grayscale page builder, 400 x 400 px = 144 x 144 pt at 200 DPI.
final class _Canvas {
  _Canvas() : _bytes = Uint8List(_rasterWidth * _rasterHeight) {
    _bytes.fillRange(0, _bytes.length, 255);
  }

  final Uint8List _bytes;

  void fillRect(int left, int top, int right, int bottom, {int value = 0}) {
    for (int y = top; y < bottom; y++) {
      final int row = y * _rasterWidth;
      _bytes.fillRange(row + left, row + right, value);
    }
  }

  /// Draws four borders inside `[left, top, right, bottom)`.
  void strokeRect(
    int left,
    int top,
    int right,
    int bottom, {
    int thickness = 2,
  }) {
    fillRect(left, top, right, top + thickness);
    fillRect(left, bottom - thickness, right, bottom);
    fillRect(left, top, left + thickness, bottom);
    fillRect(right - thickness, top, right, bottom);
  }

  GrayRaster build() => GrayRaster.fromGrayBytes(
    width: _rasterWidth,
    height: _rasterHeight,
    bytes: _bytes,
  );
}

/// Runs both box-scan implementations on the same raster.
({List<GeometryCandidate> indexed, List<GeometryCandidate> exhaustive}) _both(
  GrayRaster raster,
) {
  final RasterAnalysis analysis = raster.analyze();
  return (
    indexed: GeometryDetector.detect(
      analysis,
      pageWidthPt: _pageWidthPt,
      pageHeightPt: _pageHeightPt,
    ),
    exhaustive: GeometryDetector.debugDetectExhaustiveBoxScan(
      analysis,
      pageWidthPt: _pageWidthPt,
      pageHeightPt: _pageHeightPt,
    ),
  );
}

int _boxCount(List<GeometryCandidate> candidates) => candidates
    .where((GeometryCandidate candidate) => candidate.cues.contains('box'))
    .length;

/// Asserts the two scans agree and returns the shared candidate list.
List<GeometryCandidate> _expectAgreement(
  GrayRaster raster, {
  required String reason,
}) {
  final ({List<GeometryCandidate> indexed, List<GeometryCandidate> exhaustive})
  scans = _both(raster);
  expect(scans.indexed, scans.exhaustive, reason: reason);
  return scans.indexed;
}

void main() {
  group('indexed and exhaustive box scans agree', () {
    test('empty page', () {
      final List<GeometryCandidate> candidates = _expectAgreement(
        _Canvas().build(),
        reason: 'an all-white page has no rules and no candidates',
      );
      expect(candidates, isEmpty);
    });

    test('single vertical rule', () {
      final _Canvas canvas = _Canvas()..fillRect(200, 100, 202, 300);
      final List<GeometryCandidate> candidates = _expectAgreement(
        canvas.build(),
        reason: 'one vertical rule cannot form a box',
      );
      expect(_boxCount(candidates), 0);
    });

    test('duplicate centre-x rules at different y extents', () {
      // Both vertical rules have centre x = 103 but different extents and
      // thicknesses, so they do not merge. The pairing rule
      // (`right.centerX <= left.centerX`) has to reject them as a pair.
      final _Canvas canvas = _Canvas()
        ..fillRect(100, 50, 106, 150)
        ..fillRect(101, 250, 105, 350)
        ..fillRect(100, 50, 150, 52)
        ..fillRect(100, 148, 150, 150)
        ..fillRect(148, 50, 150, 150);

      final List<GeometryCandidate> candidates = _expectAgreement(
        canvas.build(),
        reason: 'duplicate centre-x must be rejected identically by both scans',
      );
      expect(_boxCount(candidates), 1);
    });

    test('box narrower than twice the corner tolerance', () {
      // Interior width 162 - 152 = 10 px < 2 x 6 px, so the two centre-x
      // windows of the horizontal pair overlap.
      final _Canvas canvas = _Canvas()..strokeRect(150, 100, 162, 200);

      final List<GeometryCandidate> candidates = _expectAgreement(
        canvas.build(),
        reason: 'overlapping centre windows must not change the result',
      );
      expect(_boxCount(candidates), 1);
    });

    test('box whose left rule starts at page edge x0 = 0', () {
      final _Canvas canvas = _Canvas()..strokeRect(0, 100, 120, 200);

      final List<GeometryCandidate> candidates = _expectAgreement(
        canvas.build(),
        reason: 'a negative lower window bound must not drop the left rule',
      );
      expect(_boxCount(candidates), 1);
      // The candidate rect is the box interior, so it starts one 2 px rule
      // inside the page edge: 2 px / (200 / 72) = 0.72 pt, rounded to 0.75 pt.
      expect(
        candidates
            .firstWhere(
              (GeometryCandidate candidate) => candidate.cues.contains('box'),
            )
            .rect
            .x,
        0.75,
      );
    });

    test('closed grid page', () {
      // Two by two addressable cells: the outer vertical rules sit exactly on
      // the horizontal endpoints so the corner test accepts the grid.
      final _Canvas canvas = _Canvas();
      for (final int top in <int>[100, 190, 278]) {
        canvas.fillRect(100, top, 300, top + 2);
      }
      for (final int left in <int>[100, 199, 298]) {
        canvas.fillRect(left, 100, left + 2, 280);
      }

      final List<GeometryCandidate> candidates = _expectAgreement(
        canvas.build(),
        reason: 'grid and box cues share the scan and must stay identical',
      );
      expect(
        candidates.where(
          (GeometryCandidate candidate) => candidate.cues.contains('grid_cell'),
        ),
        isNotEmpty,
      );
    });

    test('pseudo-random rule field with endpoints jittered near tolerance', () {
      // Deterministic LCG: no randomness, identical raster on every run.
      int state = 20261122;
      int next(int bound) {
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
        return state % bound;
      }

      final _Canvas canvas = _Canvas();
      // 26 horizontal rules in the upper half with spans jittered by 0-8 px
      // around a base span, i.e. straddling the 6 px corner and span
      // tolerances.
      for (int index = 0; index < 26; index++) {
        final int top = 20 + index * 7;
        final int left = 20 + next(9);
        final int right = 380 - next(9);
        canvas.fillRect(left, top, right, top + 2);
      }
      // 22 vertical rules in the same band, jittered the same way, so some
      // endpoints coincide with horizontal endpoints and some miss by one to
      // eight pixels.
      for (int index = 0; index < 22; index++) {
        final int left = 20 + index * 17;
        final int top = 20 + next(9);
        final int bottom = 190 - next(9);
        canvas.fillRect(left, top, left + 2, bottom);
      }
      // Two exact rectangles in the clean lower half: both scans must find
      // them, so the property assertion is not vacuous.
      canvas.strokeRect(40, 280, 160, 380);
      canvas.strokeRect(200, 280, 320, 380);

      final List<GeometryCandidate> candidates = _expectAgreement(
        canvas.build(),
        reason: 'jittered rule fields must not diverge between the scans',
      );
      expect(_boxCount(candidates), greaterThanOrEqualTo(2));
      expect(
        candidates.where(
          (GeometryCandidate candidate) => candidate.cues.contains('box'),
        ),
        isNotEmpty,
      );
    });

    test('repeated runs are stable in both scans', () {
      final GrayRaster raster = (_Canvas()..strokeRect(0, 100, 120, 200))
          .build();
      final ({
        List<GeometryCandidate> indexed,
        List<GeometryCandidate> exhaustive,
      })
      first = _both(raster);
      final ({
        List<GeometryCandidate> indexed,
        List<GeometryCandidate> exhaustive,
      })
      second = _both(raster);
      expect(second.indexed, first.indexed);
      expect(second.exhaustive, first.exhaustive);
    });
  });
}
