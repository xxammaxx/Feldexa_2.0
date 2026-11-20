// Pure zoom-to-field target scale (T078).
//
// The formula is fixed by
// specs/001-scanned-form-workflow/contracts/coordinates-and-geometry.md
// section 3 ("Zoom-to-field") and FR-034: selecting a field computes a target
// view scale and then pans to center the field, without reading or mutating
// stored geometry. The caller supplies the current viewport in logical pixels,
// the field's display-space size in PDF points after rotation/CropBox, and the
// current fit-width scale.
//
// The scale is a plain `double`: there is no integer zoom-step rounding and no
// persisted state. This file deliberately stays platform-independent.
library;

import 'dart:math' as math;

import 'rect.dart';

/// Returns the target view scale for zooming to a field.
///
/// Implements `contracts/coordinates-and-geometry.md` section 3:
///
/// ```text
/// target = clamp(
///   min(0.7 * viewportHeight / fieldHeight,
///       0.9 * viewportWidth / fieldWidth,
///       8 * fitWidthScale),
///   fitWidthScale,
///   8 * fitWidthScale,
/// )
/// ```
///
/// The 70 % height and 90 % width margins leave some context around the field.
/// Tiny fields stop at `8 * fitWidthScale`; oversized fields stay at
/// [fitWidthScale]. Both bounds are inclusive. The result is not rounded to
/// integer zoom steps.
///
/// The function is pure: it reads no document or stored geometry, mutates no
/// argument, and persists nothing (FR-034).
///
/// Throws a content-free [ArgumentError] if a viewport or field dimension is
/// not finite or not strictly positive, or if [fitWidthScale] is not finite or
/// not strictly positive. [Size] already enforces its own invariant; the
/// checks here keep the function independently total.
double zoomToFieldScale({
  required Size viewportSize,
  required Size fieldSize,
  required double fitWidthScale,
}) {
  _checkPositive(viewportSize.width);
  _checkPositive(viewportSize.height);
  _checkPositive(fieldSize.width);
  _checkPositive(fieldSize.height);
  _checkPositive(fitWidthScale);
  final double maxScale = 8 * fitWidthScale;
  final double target = math.min(
    math.min(
      0.7 * viewportSize.height / fieldSize.height,
      0.9 * viewportSize.width / fieldSize.width,
    ),
    maxScale,
  );
  return _clamp(target, fitWidthScale, maxScale);
}

void _checkPositive(double value) {
  if (!value.isFinite || value <= 0) {
    throw ArgumentError();
  }
}

double _clamp(double value, double minimum, double maximum) {
  if (value < minimum) {
    return minimum;
  }
  if (value > maximum) {
    return maximum;
  }
  return value;
}
