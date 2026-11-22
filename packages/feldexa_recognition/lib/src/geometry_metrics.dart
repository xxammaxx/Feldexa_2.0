// Exact display-space rectangle metrics on the 1/8 pt lattice (T264).
//
// Normative sources:
//  * `specs/001-scanned-form-workflow/contracts/coordinates-and-geometry.md`
//    sections 1 and 4;
//  * `specs/001-scanned-form-workflow/contracts/recognition-output.md`
//    section 2 (`rect` is 1/8 pt rounded and inside the page) and section 6
//    (`IoU >= 0.5` conflicts);
//  * `specs/001-scanned-form-workflow/spec.md` FR-014, SC-002.
//
// This library is a pure measurement primitive. It owns no candidate, no
// suggestion, no type, no confidence, and no I/O. It exists so the T264 field
// inventory, the structure comparison, and the adaptive verification share one
// exact definition of "same place" instead of three approximate ones.
//
// Rounding. Every edge is rounded once, ties away from zero, to the nearest
// 1/8 pt. Width and height are then recomputed from the rounded edges, so a
// normalised rectangle is exactly representable on the lattice. A rectangle
// whose rounded width or height is not strictly positive is degenerate and is
// reported as `null` by [normalizeRect] instead of throwing, because callers
// legitimately iterate over near-degenerate candidates.
//
// Clamping. When a page extent is supplied, each rounded edge is lowered to the
// largest 1/8 pt multiple not exceeding the page extent. This is the same
// inward clamp the T052 detector applies, so a normalised rectangle never
// leaves the page even when the page size is not itself a 1/8 pt multiple.
//
// Comparison. [iou] delegates to the T055 `ConflictDetector.iou` so the
// structure comparison and the conflict graph cannot disagree about the
// overlap of the same two rectangles.
library;

import 'dart:math' as math;

import 'conflicts.dart';
import 'geometry_detector.dart';

/// Lattice units per display-space point.
const int latticeUnitsPerPoint = 8;

/// Rounds [value] to the nearest 1/8 pt, ties away from zero.
///
/// The result is always an exact multiple of `1/8` for finite input.
double roundToEighth(double value) {
  if (!value.isFinite) {
    throw ArgumentError('value must be finite');
  }
  return (value * latticeUnitsPerPoint).round() / latticeUnitsPerPoint;
}

/// Returns [value] rounded down to a 1/8 pt multiple.
double floorToEighth(double value) {
  if (!value.isFinite) {
    throw ArgumentError('value must be finite');
  }
  return (value * latticeUnitsPerPoint).floor() / latticeUnitsPerPoint;
}

/// Normalises [rect] onto the 1/8 pt lattice, optionally clamped to the page.
///
/// Returns `null` when the normalised width or height is not strictly positive,
/// which is the only way a finite rectangle can be unrepresentable.
/// `pageWidthPt` and `pageHeightPt` must be supplied together or not at all.
DisplayRect? normalizeRect(
  DisplayRect rect, {
  double? pageWidthPt,
  double? pageHeightPt,
}) {
  if ((pageWidthPt == null) != (pageHeightPt == null)) {
    throw ArgumentError('page extents must be supplied together');
  }
  int left = _units(rect.x);
  int top = _units(rect.y);
  int right = _units(rect.x + rect.width);
  int bottom = _units(rect.y + rect.height);
  if (pageWidthPt != null && pageHeightPt != null) {
    if (!pageWidthPt.isFinite || !pageHeightPt.isFinite) {
      throw ArgumentError('page extents must be finite');
    }
    right = math.min(right, floorUnits(pageWidthPt));
    bottom = math.min(bottom, floorUnits(pageHeightPt));
  }
  if (right <= left || bottom <= top) {
    return null;
  }
  return DisplayRect(
    x: left / latticeUnitsPerPoint,
    y: top / latticeUnitsPerPoint,
    width: (right - left) / latticeUnitsPerPoint,
    height: (bottom - top) / latticeUnitsPerPoint,
  );
}

/// Converts a point to lattice units, rounding ties away from zero.
int unitsOfPoint(double points) {
  if (!points.isFinite) {
    throw ArgumentError('points must be finite');
  }
  return _units(points);
}

/// Converts a point to lattice units, rounded down.
int floorUnits(double points) {
  if (!points.isFinite) {
    throw ArgumentError('points must be finite');
  }
  return (points * latticeUnitsPerPoint).floor();
}

/// Converts lattice units back to display-space points.
double pointOfUnits(int units) => units / latticeUnitsPerPoint;

int _units(double value) => (value * latticeUnitsPerPoint).round();

/// The integer lattice rectangle `[left, right) x [top, bottom)` in 1/8 pt.
final class LatticeRect {
  /// Creates a lattice rectangle from a validated display rectangle.
  factory LatticeRect.fromDisplayRect(DisplayRect rect) {
    final int left = _units(rect.x);
    final int top = _units(rect.y);
    return LatticeRect._(
      left,
      top,
      _units(rect.x + rect.width),
      _units(rect.y + rect.height),
    );
  }

  const LatticeRect._(this.left, this.top, this.right, this.bottom);

  /// Left edge in lattice units.
  final int left;

  /// Top edge in lattice units.
  final int top;

  /// Right (exclusive) edge in lattice units.
  final int right;

  /// Bottom (exclusive) edge in lattice units.
  final int bottom;

  /// Width in lattice units; never negative.
  int get widthUnits => right - left;

  /// Height in lattice units; never negative.
  int get heightUnits => bottom - top;

  /// Area in squared lattice units; never negative.
  int get areaUnits => widthUnits * heightUnits;

  /// The same rectangle as a display rectangle, without clamping.
  DisplayRect toDisplayRect() => DisplayRect(
    x: pointOfUnits(left),
    y: pointOfUnits(top),
    width: pointOfUnits(widthUnits),
    height: pointOfUnits(heightUnits),
  );

  @override
  bool operator ==(Object other) {
    return other is LatticeRect &&
        other.left == left &&
        other.top == top &&
        other.right == right &&
        other.bottom == bottom;
  }

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'LatticeRect($left, $top, $right, $bottom)';
}

/// Squared lattice units per squared display point.
const int _unitsSquaredPerPointSquared =
    latticeUnitsPerPoint * latticeUnitsPerPoint;

/// Intersection area of [a] and [b] in squared display points.
double intersectionAreaPt2(DisplayRect a, DisplayRect b) {
  final LatticeRect first = LatticeRect.fromDisplayRect(a);
  final LatticeRect second = LatticeRect.fromDisplayRect(b);
  return _intersectionUnits(first, second) / _unitsSquaredPerPointSquared;
}

int _intersectionUnits(LatticeRect a, LatticeRect b) {
  final int width = math.min(a.right, b.right) - math.max(a.left, b.left);
  final int height = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  if (width <= 0 || height <= 0) {
    return 0;
  }
  return width * height;
}

/// Union area of [a] and [b] in squared display points.
double unionAreaPt2(DisplayRect a, DisplayRect b) {
  final LatticeRect first = LatticeRect.fromDisplayRect(a);
  final LatticeRect second = LatticeRect.fromDisplayRect(b);
  final int union =
      first.areaUnits + second.areaUnits - _intersectionUnits(first, second);
  if (union <= 0) {
    return 0;
  }
  return union / _unitsSquaredPerPointSquared;
}

/// The exact intersection-over-union of [a] and [b], delegating to T055.
///
/// The result is in `0.0 ... 1.0`; disjoint rectangles yield `0.0`.
double iou(DisplayRect a, DisplayRect b) => ConflictDetector.iou(a, b);

/// Euclidean distance between the centres of [a] and [b] in display points.
double centerDistancePt(DisplayRect a, DisplayRect b) {
  final double dx = (a.x + a.width / 2) - (b.x + b.width / 2);
  final double dy = (a.y + a.height / 2) - (b.y + b.height / 2);
  return math.sqrt(dx * dx + dy * dy);
}

/// The fraction of [inner] covered by [outer], in `0.0 ... 1.0`.
double containmentFraction(DisplayRect outer, DisplayRect inner) {
  final LatticeRect innerRect = LatticeRect.fromDisplayRect(inner);
  if (innerRect.areaUnits <= 0) {
    return 0;
  }
  final int covered = _intersectionUnits(
    LatticeRect.fromDisplayRect(outer),
    innerRect,
  );
  return covered / innerRect.areaUnits;
}

/// The smallest axis-aligned gap between [a] and [b] in display points.
///
/// Overlapping or touching rectangles have gap `0.0`; the value is the
/// Euclidean length of the shortest edge-to-edge connector, so diagonally
/// separated rectangles report the diagonal gap.
double rectGapPt(DisplayRect a, DisplayRect b) {
  final LatticeRect first = LatticeRect.fromDisplayRect(a);
  final LatticeRect second = LatticeRect.fromDisplayRect(b);
  final int dx = math.max(
    0,
    math.max(first.left - second.right, second.left - first.right),
  );
  final int dy = math.max(
    0,
    math.max(first.top - second.bottom, second.top - first.bottom),
  );
  final double dxPt = pointOfUnits(dx);
  final double dyPt = pointOfUnits(dy);
  return math.sqrt(dxPt * dxPt + dyPt * dyPt);
}

/// The area of [rect] in squared display points, measured on the lattice.
double areaPt2(DisplayRect rect) =>
    LatticeRect.fromDisplayRect(rect).areaUnits / _unitsSquaredPerPointSquared;

/// Whether [rect] lies inside `[0, 0, pageWidthPt, pageHeightPt]` within
/// [tolerancePt].
bool isInsidePage(
  DisplayRect rect, {
  required double pageWidthPt,
  required double pageHeightPt,
  double tolerancePt = 1e-6,
}) {
  return rect.x >= -tolerancePt &&
      rect.y >= -tolerancePt &&
      rect.x + rect.width <= pageWidthPt + tolerancePt &&
      rect.y + rect.height <= pageHeightPt + tolerancePt;
}
