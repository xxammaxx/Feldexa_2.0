// Independent corner verification of the export CTM
// (`contracts/coordinates-and-geometry.md` §5).
//
// §5 requires every rotation matrix to be verified by mapping the four
// display-box corners back onto the four PDF box corners. These host-VM tests
// (`NONE` evidence) do exactly that: the expected corners are recomputed from
// the §2 point formulas, so the matrix is checked against the contract instead
// of against itself. They prove matrix arithmetic only; they cannot prove PDF
// output (T108/T109).
@TestOn('vm')
library;

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_export/feldexa_export.dart';
import 'package:flutter_test/flutter_test.dart';

/// Conversion tolerance from §5: 0.01 pt in plan generation.
const double _tolerancePt = 0.01;

/// Applies [ctm] to a display point the way a PDF `cm` operator does:
/// `u = a·x + c·y + e`, `v = b·x + d·y + f`.
Point _apply(ExportCtm ctm, double x, double y) {
  return Point(ctm.a * x + ctm.c * y + ctm.e, ctm.b * x + ctm.d * y + ctm.f);
}

/// The §2 display→PDF point formula for [geometry], written out per rotation.
///
/// This is a deliberate second transcription of the contract text, not a call
/// to `PageGeometry.displayToPdf` and not a copy of the `a…f` coefficients: the
/// corner test has to fail when either the contract formula or the generated
/// matrix drifts.
Point _section2Point(PageGeometry geometry, double x, double y) {
  final Rect crop = geometry.cropBox;
  final double cx0 = crop.left;
  final double cy0 = crop.top;
  final double cx1 = crop.right;
  final double cy1 = crop.bottom;
  return switch (geometry.rotation) {
    0 => Point(cx0 + x, cy1 - y),
    90 => Point(cx0 + y, cy0 + x),
    180 => Point(cx1 - x, cy0 + y),
    270 => Point(cx1 - y, cy1 - x),
    _ => throw StateError('unsupported rotation ${geometry.rotation}'),
  };
}

/// The four display-box corners of [geometry], top-left first, clockwise.
List<Point> _displayCorners(PageGeometry geometry) {
  final Size size = geometry.displaySize;
  return <Point>[
    Point(0, 0),
    Point(size.width, 0),
    Point(size.width, size.height),
    Point(0, size.height),
  ];
}

/// A4 portrait without a CropBox: the effective CropBox is the MediaBox.
PageGeometry _a4AtOrigin(int rotation) {
  return PageGeometry(
    mediaBox: Rect.fromLTWH(0, 0, 595.28, 841.89),
    rotation: rotation,
  );
}

/// A page whose CropBox is offset by (10, 20) and smaller than the MediaBox.
PageGeometry _offsetCrop(int rotation) {
  return PageGeometry(
    mediaBox: Rect.fromLTWH(0, 0, 620, 860),
    cropBox: Rect.fromLTWH(10, 20, 585, 790),
    rotation: rotation,
  );
}

void main() {
  const List<int> rotations = <int>[0, 90, 180, 270];

  test('maps the four display corners onto the four PDF corners (§5)', () {
    final Map<String, PageGeometry Function(int)> pages =
        <String, PageGeometry Function(int)>{
          'A4 at origin': _a4AtOrigin,
          'offset CropBox': _offsetCrop,
        };
    for (final MapEntry<String, PageGeometry Function(int)> page
        in pages.entries) {
      for (final int rotation in rotations) {
        final PageGeometry geometry = page.value(rotation);
        final ExportCtm ctm = ExportCtm.fromGeometry(geometry);
        final Rect crop = geometry.cropBox;
        final String reason = '${page.key}, rotation $rotation';
        for (final Point corner in _displayCorners(geometry)) {
          final Point mapped = _apply(ctm, corner.x, corner.y);
          final Point expected = _section2Point(geometry, corner.x, corner.y);
          expect(
            mapped.x,
            closeTo(expected.x, _tolerancePt),
            reason: '$reason: u of display (${corner.x}, ${corner.y})',
          );
          expect(
            mapped.y,
            closeTo(expected.y, _tolerancePt),
            reason: '$reason: v of display (${corner.x}, ${corner.y})',
          );
        }
        // The mapped corner set must span the crop box exactly: a wrong sign
        // keeps the width but shifts or reflects the height range.
        final Iterable<Point> mapped = _displayCorners(geometry)
            .map((Point corner) => _apply(ctm, corner.x, corner.y));
        expect(
          mapped.map((Point point) => point.x).reduce(_min),
          closeTo(crop.left, _tolerancePt),
          reason: '$reason: leftmost mapped corner',
        );
        expect(
          mapped.map((Point point) => point.x).reduce(_max),
          closeTo(crop.right, _tolerancePt),
          reason: '$reason: rightmost mapped corner',
        );
        expect(
          mapped.map((Point point) => point.y).reduce(_min),
          closeTo(crop.top, _tolerancePt),
          reason: '$reason: lowest mapped corner',
        );
        expect(
          mapped.map((Point point) => point.y).reduce(_max),
          closeTo(crop.bottom, _tolerancePt),
          reason: '$reason: highest mapped corner',
        );
      }
    }
  });

  test('pins the rotation-180 matrix to a=-1 and d=+1 (§5, §2)', () {
    for (final PageGeometry geometry in <PageGeometry>[
      _a4AtOrigin(180),
      _offsetCrop(180),
    ]) {
      final ExportCtm ctm = ExportCtm.fromGeometry(geometry);
      expect(ctm.a, -1);
      expect(ctm.b, 0);
      expect(ctm.c, 0);
      expect(ctm.d, 1);
      expect(ctm.e, geometry.cropBox.right);
      expect(ctm.f, geometry.cropBox.top);
    }
  });

  test('rotation 180 lands a known display point at the §2 PDF point', () {
    // Display top-left maps to the PDF bottom-right corner: `u = cx1 - x`,
    // `v = cy0 + y`, so display y grows with PDF y instead of against it.
    final Point a4 = _apply(ExportCtm.fromGeometry(_a4AtOrigin(180)), 100, 50);
    expect(a4.x, closeTo(495.28, _tolerancePt));
    expect(a4.y, closeTo(50, _tolerancePt));

    final Point offset = _apply(
      ExportCtm.fromGeometry(_offsetCrop(180)),
      100,
      50,
    );
    expect(offset.x, closeTo(495, _tolerancePt));
    expect(offset.y, closeTo(70, _tolerancePt));

    // The same display point must match the §2 formula for the same page.
    final PageGeometry geometry = _offsetCrop(180);
    final Point expected = _section2Point(geometry, 100, 50);
    expect(offset.x, closeTo(expected.x, _tolerancePt));
    expect(offset.y, closeTo(expected.y, _tolerancePt));
  });
}

double _min(double a, double b) => a < b ? a : b;

double _max(double a, double b) => a > b ? a : b;
