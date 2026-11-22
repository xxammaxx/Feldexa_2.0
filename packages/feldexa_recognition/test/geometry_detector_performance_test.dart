// T086B regression test: the box detector must not degrade into a
// quadratic-squared scan on a rule-dense page.
//
// Normative source: specs/001-scanned-form-workflow/contracts/
// recognition-output.md section 2 (candidates, ink gate) and section 5.2
// (diagnostics); research.md D-06 (rules -> grids -> boxes). This test does not
// change any contract value: it fixes the detection *cost* discovered while
// analysing the committed `sf-001.pdf` fixture, whose two pages produced 291 /
// 540 and 339 / 608 horizontal/vertical ruling lines at 200 DPI.
//
// The former `_detectBoxes` enumerated every horizontal pair against every
// vertical pair before applying the corner test. On `sf-001` page 1 that is
// 42,195 x 145,530 = 6.1e9 loop iterations, measured 86,842 ms for one page
// (`GeometryDetector.detect` only, host `dart run`, Dart SDK 3.13.5, Intel
// Core i5-3570K). Page 2 measured 142,269 ms. Both produced 16 / 20
// corner-compatible boxes, i.e. the cost was paid almost entirely for
// combinations that the corner test rejects.
//
// This test builds a rule-dense A4 raster of the same shape (many independent
// horizontal rules on one axis, many independent vertical rules on the other)
// and requires the whole detection to stay inside a generous wall-clock budget.
// The exhaustive scan needs roughly 23 s for this raster; the indexed scan
// needs well under a second. The budget is set an order of magnitude above the
// indexed cost and well below the exhaustive cost, so it fails on the
// pathological implementation and is not sensitive to ordinary host noise.
//
// Three explicit rectangles are drawn in an otherwise clean corner so the test
// also proves the scan still finds boxes on a page with hundreds of rules, and
// therefore cannot pass by returning an empty list.
// ignore_for_file: depend_on_referenced_packages

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/raster.dart';
import 'package:flutter_test/flutter_test.dart';

const double _pageWidthPt = 595.28;
const double _pageHeightPt = 841.89;
const int _rasterWidth = 1654;
const int _rasterHeight = 2339;

/// Wall-clock budget for one `GeometryDetector.detect` call on the dense page.
const Duration _budget = Duration(seconds: 10);

/// Independent horizontal ruling lines in `y = 100 ... 2134`.
const int _horizontalRuleCount = 340;

/// Independent vertical ruling lines in `x = 80 ... 1275`, below the
/// horizontals so the page has no closed grid.
const int _verticalRuleCount = 240;

/// Clean-corner rectangles drawn as `(left, top, right, bottom)`.
const List<(int, int, int, int)> _boxes = <(int, int, int, int)>[
  (1360, 200, 1560, 300),
  (1360, 360, 1460, 460),
  (1500, 520, 1620, 640),
];

/// Maps a pixel edge to display points and rounds once to 1/8 pt, exactly as
/// `recognition-output.md` section 2 requires.
double _edge(int pixel) => (pixel / rasterScale * 8).round() / 8;

DisplayRect _rect(int left, int top, int right, int bottom) {
  final double x = _edge(left);
  final double y = _edge(top);
  return DisplayRect(
    x: x,
    y: y,
    width: _edge(right) - x,
    height: _edge(bottom) - y,
  );
}

/// Builds the dense A4 page described in the file header.
GrayRaster _densePage() {
  final Uint8List bytes = Uint8List(_rasterWidth * _rasterHeight)
    ..fillRange(0, _rasterWidth * _rasterHeight, 255);

  void fillRect(int left, int top, int right, int bottom) {
    for (int y = top; y < bottom; y++) {
      final int row = y * _rasterWidth;
      bytes.fillRange(row + left, row + right, 0);
    }
  }

  // Horizontal rules: 2 px thick, 6 px pitch (4 px of background), five
  // distinct span variants so no two rules form a grid cluster.
  for (int index = 0; index < _horizontalRuleCount; index++) {
    final int y = 100 + index * 6;
    final int variant = index % 5;
    fillRect(60 + variant * 90, y, 1200 - variant * 90, y + 2);
  }

  // Vertical rules: 2 px thick, 5 px pitch (3 px of background), all below the
  // horizontals so the page contains no addressable grid cell.
  for (int index = 0; index < _verticalRuleCount; index++) {
    final int x = 80 + index * 5;
    fillRect(x, 2160, x + 2, 2330);
  }

  // Three closed rectangles in the clean corner.
  for (final (int left, int top, int right, int bottom) in _boxes) {
    fillRect(left, top, right, top + 2);
    fillRect(left, bottom - 2, right, bottom);
    fillRect(left, top, left + 2, bottom);
    fillRect(right - 2, top, right, bottom);
  }

  return GrayRaster.fromGrayBytes(
    width: _rasterWidth,
    height: _rasterHeight,
    bytes: bytes,
  );
}

void main() {
  group('rule-dense page', () {
    test('detection stays inside the wall-clock budget', () {
      final RasterAnalysis analysis = _densePage().analyze();

      final Stopwatch watch = Stopwatch()..start();
      final List<GeometryCandidate> candidates = GeometryDetector.detect(
        analysis,
        pageWidthPt: _pageWidthPt,
        pageHeightPt: _pageHeightPt,
      );
      watch.stop();

      // ignore: avoid_print
      print(
        'T086B dense page: ${watch.elapsedMilliseconds} ms, '
        '${candidates.length} candidates, '
        'budget ${_budget.inMilliseconds} ms',
      );
      expect(
        watch.elapsed,
        lessThan(_budget),
        reason:
            'the box scan must index candidate rule pairs instead of '
            'enumerating every horizontal pair against every vertical pair',
      );
    });

    test('the clean-corner rectangles are still detected as boxes', () {
      final List<GeometryCandidate> candidates = GeometryDetector.detect(
        _densePage().analyze(),
        pageWidthPt: _pageWidthPt,
        pageHeightPt: _pageHeightPt,
      );

      final List<DisplayRect> boxRects = candidates
          .where(
            (GeometryCandidate candidate) => candidate.cues.contains('box'),
          )
          .map((GeometryCandidate candidate) => candidate.rect)
          .toList();

      expect(
        boxRects,
        containsAll(
          _boxes.map(
            ((int, int, int, int) box) =>
                _rect(box.$1 + 2, box.$2 + 2, box.$3 - 2, box.$4 - 2),
          ),
        ),
      );
    });

    test('the same raster produces the same candidates twice', () {
      final RasterAnalysis analysis = _densePage().analyze();
      List<GeometryCandidate> detect() => GeometryDetector.detect(
        analysis,
        pageWidthPt: _pageWidthPt,
        pageHeightPt: _pageHeightPt,
      );

      final List<GeometryCandidate> first = detect();
      final List<GeometryCandidate> second = detect();

      expect(second, first);
    });
  });
}
