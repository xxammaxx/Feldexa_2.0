// Page geometry and the display-space ↔ PDF user-space mapping (T016).
//
// The single source of truth is
// specs/001-scanned-form-workflow/contracts/coordinates-and-geometry.md
// sections 1–2: field rectangles are stored in PDF points in the page display
// space (origin at the top-left of the visible page box, x right, y down, after
// `/Rotate`). PDF user space is points with the origin at the bottom-left and y
// up. [PageGeometry] owns the display box, the crop-box intersection, the
// rotation, and every conversion between the two spaces.
//
// Conventions used by this file:
//  * A PDF-space [Rect] stores the lower-left corner in `left`/`top` and the
//    upper-right corner in `right`/`bottom`. `top` is therefore the smaller y
//    value, not the display-space top edge.
//  * A display-space [Rect] stores the top-left corner in `left`/`top` and the
//    bottom-right corner in `right`/`bottom`, exactly like the rest of the
//    model.
//  * The effective crop box is the intersection of the supplied CropBox with
//    the MediaBox; when no CropBox is supplied it equals the MediaBox. The
//    mapping formulas use the effective crop box, so crop offsets are always
//    applied and `cx0 == cy0 == 0` is never assumed.
library;

import 'dart:math' as math;

import 'rect.dart';

/// A page's visible box, rotation, and display-space ↔ PDF-space mapping.
///
/// [mediaBox] and [cropBox] are PDF user-space rectangles. [cropBox] is always
/// the intersection of the requested CropBox with [mediaBox]; passing `null`
/// means the PDF default, where the CropBox equals the MediaBox. [displaySize]
/// is derived from the effective crop box and the rotation, and it is
/// deliberately not persisted: it cannot disagree with the stored boxes.
///
/// The mapping methods implement the exact formulas in
/// `contracts/coordinates-and-geometry.md` section 2 for rotations 0, 90, 180,
/// and 270. Both point and rectangle conversions exist, because a rectangle's
/// width and height swap for the quarter-turn rotations.
final class PageGeometry {
  const PageGeometry._(this.mediaBox, this.cropBox, this.rotation);

  /// Creates page geometry from PDF user-space boxes and a page rotation.
  ///
  /// [mediaBox] is required and must have a positive size. [cropBox] is
  /// intersected with [mediaBox]; it defaults to [mediaBox]. [rotation] must be
  /// exactly 0, 90, 180, or 270 (the PDF `/Rotate` values already normalized by
  /// the preflight parser).
  ///
  /// Throws [ArgumentError] if [rotation] is not one of the four supported
  /// values, or if the CropBox does not overlap the MediaBox in a positive-area
  /// rectangle.
  factory PageGeometry({
    required Rect mediaBox,
    Rect? cropBox,
    int rotation = 0,
  }) {
    _checkRotation(rotation);
    final Rect requested = cropBox ?? mediaBox;
    final double left = math.max(mediaBox.left, requested.left);
    final double top = math.max(mediaBox.top, requested.top);
    final double right = math.min(mediaBox.right, requested.right);
    final double bottom = math.min(mediaBox.bottom, requested.bottom);
    if (!(right > left) || !(bottom > top)) {
      throw ArgumentError.value(
        cropBox,
        'cropBox',
        'must overlap mediaBox in a rectangle with positive width and height',
      );
    }
    return PageGeometry._(
      mediaBox,
      Rect.fromLTWH(left, top, right - left, bottom - top),
      rotation,
    );
  }

  /// Reads the persisted form `{"mediaBox", "cropBox", "rotation"}`.
  ///
  /// `cropBox` may be absent (or `null`), in which case the CropBox defaults to
  /// the MediaBox. [displaySize] is derived and is not read from JSON. The
  /// effective crop box is recomputed, so a serialized CropBox that extends
  /// outside the MediaBox is clipped exactly as at construction time.
  ///
  /// Throws [FormatException] when a field is missing, has the wrong type, or
  /// describes an invalid page box or rotation.
  factory PageGeometry.fromJson(Map<String, Object?> json) {
    final Object? media = json['mediaBox'];
    if (media is! Map<String, Object?>) {
      throw const FormatException(
        'PageGeometry JSON field "mediaBox" must be an object.',
      );
    }
    final Object? crop = json['cropBox'];
    Map<String, Object?>? cropJson;
    if (crop != null) {
      if (crop is! Map<String, Object?>) {
        throw const FormatException(
          'PageGeometry JSON field "cropBox" must be an object or null.',
        );
      }
      cropJson = crop;
    }
    final Object? rotation = json['rotation'];
    if (rotation is! int) {
      throw const FormatException(
        'PageGeometry JSON field "rotation" must be an integer.',
      );
    }
    try {
      return PageGeometry(
        mediaBox: Rect.fromJson(media),
        cropBox: cropJson == null ? null : Rect.fromJson(cropJson),
        rotation: rotation,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid PageGeometry JSON: ${error.message}');
    }
  }

  /// The full PDF page box, in PDF user space (points, y up).
  final Rect mediaBox;

  /// The effective crop box: the requested CropBox intersected with [mediaBox].
  ///
  /// When the PDF has no CropBox this equals [mediaBox].
  final Rect cropBox;

  /// The normalized PDF `/Rotate` value: exactly 0, 90, 180, or 270.
  final int rotation;

  /// The visible page size in display-space PDF points.
  ///
  /// Rotation 0 and 180 keep `(cropWidth, cropHeight)`; rotation 90 and 270
  /// swap them to `(cropHeight, cropWidth)`.
  Size get displaySize {
    return switch (rotation) {
      0 || 180 => Size(cropBox.width, cropBox.height),
      90 || 270 => Size(cropBox.height, cropBox.width),
      _ => throw StateError('unreachable rotation $rotation'),
    };
  }

  /// The display-space bounds `[0, 0, displayWidth, displayHeight]`.
  Rect get displayBox {
    final Size size = displaySize;
    return Rect.fromLTWH(0, 0, size.width, size.height);
  }

  /// Maps a display-space point to PDF user space.
  ///
  /// The formulas are the normative section 2 formulas; display coordinates may
  /// lie outside the display box and PDF coordinates may lie outside the crop
  /// box, because validation is a separate, explicit step ([validate]).
  Point displayToPdf(Point point) {
    final double cx0 = cropBox.left;
    final double cy0 = cropBox.top;
    final double cx1 = cropBox.right;
    final double cy1 = cropBox.bottom;
    return switch (rotation) {
      0 => Point(cx0 + point.x, cy1 - point.y),
      90 => Point(cx0 + point.y, cy0 + point.x),
      180 => Point(cx1 - point.x, cy0 + point.y),
      270 => Point(cx1 - point.y, cy1 - point.x),
      _ => throw StateError('unreachable rotation $rotation'),
    };
  }

  /// Maps a PDF user-space point to display space.
  ///
  /// This is the exact inverse of [displayToPdf] for all four rotations.
  Point pdfToDisplay(Point point) {
    final double cx0 = cropBox.left;
    final double cy0 = cropBox.top;
    final double cx1 = cropBox.right;
    final double cy1 = cropBox.bottom;
    return switch (rotation) {
      0 => Point(point.x - cx0, cy1 - point.y),
      90 => Point(point.y - cy0, point.x - cx0),
      180 => Point(cx1 - point.x, point.y - cy0),
      270 => Point(cy1 - point.y, cx1 - point.x),
      _ => throw StateError('unreachable rotation $rotation'),
    };
  }

  /// Maps a display-space rectangle to the PDF user-space rectangle.
  ///
  /// The result is `(u0, v0, width, height)` with `(u0, v0)` the PDF
  /// lower-left corner; width and height swap for rotations 90 and 270. The
  /// returned rectangle is the exact bounding box of the mapped opposite
  /// corners, so `pdfRectToDisplay(displayRectToPdf(r))` round-trips without
  /// assuming an axis orientation.
  Rect displayRectToPdf(Rect rect) {
    return _rectBetween(
      displayToPdf(Point(rect.left, rect.top)),
      displayToPdf(Point(rect.right, rect.bottom)),
    );
  }

  /// Maps a PDF user-space rectangle to the display-space rectangle.
  ///
  /// The result is `(x, y, width, height)` with `(x, y)` the display top-left
  /// corner. Width and height swap for rotations 90 and 270.
  Rect pdfRectToDisplay(Rect rect) {
    return _rectBetween(
      pdfToDisplay(Point(rect.left, rect.top)),
      pdfToDisplay(Point(rect.right, rect.bottom)),
    );
  }

  /// Validates a stored display-space rectangle against the display box.
  ///
  /// Contract section 6.1: an overshoot of at most 0.5 pt on every side is
  /// treated as numerical noise and clamped once to the display box, while an
  /// overshoot beyond 0.5 pt is rejected with [ArgumentError]. Each edge is
  /// clamped into `[0, 0, displayW, displayH]`; a rectangle that lies entirely
  /// outside within the tolerance is translated to the nearest edge so it keeps
  /// its positive size instead of collapsing.
  ///
  /// A sub-half-point page can be narrower or shorter than the rectangle being
  /// translated: because the overshoot bound limits an entirely outside
  /// rectangle to at most 0.5 pt in size, a display dimension below 0.5 pt can
  /// still be smaller than that rectangle. Translation therefore caps the kept
  /// size at the display dimension; otherwise the translated far edge would
  /// land outside the display box (for example, a 0.2 pt wide rectangle on a
  /// 0.1 pt wide page). The cap can only reduce an edge movement that is
  /// already inside the 0.5 pt tolerance, and normal PDF page sizes are
  /// unaffected because their dimensions exceed the tolerance by far.
  ///
  /// The returned [GeometryValidation.rect] is always inside the display box,
  /// and [GeometryValidation.wasClamped] is the recorded warning the caller
  /// must surface when it persists a clamped rectangle. Clamping is never
  /// silent.
  GeometryValidation validate(Rect rect) {
    final double width = displaySize.width;
    final double height = displaySize.height;
    final double overshoot = <double>[
      -rect.left,
      -rect.top,
      rect.right - width,
      rect.bottom - height,
    ].reduce(math.max);
    if (overshoot > maxClampTolerancePt) {
      throw ArgumentError.value(
        rect,
        'rect',
        'must lie within [0, 0, $width, $height]; overshoot '
            '${overshoot.toStringAsFixed(6)} pt exceeds '
            '${maxClampTolerancePt.toStringAsFixed(1)} pt',
      );
    }
    if (overshoot <= 0) {
      return GeometryValidation._(rect: rect, wasClamped: false);
    }
    double left = _clamp(rect.left, 0, width);
    double right = _clamp(rect.right, 0, width);
    double top = _clamp(rect.top, 0, height);
    double bottom = _clamp(rect.bottom, 0, height);
    if (!(right > left)) {
      // Entirely to the left of, or the right of, the display box within the
      // tolerance: translate it to the nearest edge and keep its width. The
      // kept width is capped at the display width: a page narrower than 0.5 pt
      // can be narrower than the translated rectangle, and an uncapped width
      // would put the far edge outside the display box.
      final double rectWidth = math.min(rect.width, width);
      if (rect.left <= 0) {
        left = 0;
        right = rectWidth;
      } else {
        right = width;
        left = width - rectWidth;
      }
    }
    if (!(bottom > top)) {
      final double rectHeight = math.min(rect.height, height);
      if (rect.top <= 0) {
        top = 0;
        bottom = rectHeight;
      } else {
        bottom = height;
        top = height - rectHeight;
      }
    }
    if (!(right > left) || !(bottom > top)) {
      throw ArgumentError.value(
        rect,
        'rect',
        'cannot be clamped into the display box without changing its size',
      );
    }
    return GeometryValidation._(
      rect: Rect.fromLTWH(left, top, right - left, bottom - top),
      wasClamped: true,
    );
  }

  /// Returns the persisted form: both PDF boxes and the rotation.
  ///
  /// [displaySize] is derived and is not written; reading this JSON recomputes
  /// it. The boxes use [Rect.toJson], which quantizes only at serialization.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'mediaBox': mediaBox.toJson(),
      'cropBox': cropBox.toJson(),
      'rotation': rotation,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is PageGeometry &&
        other.mediaBox == mediaBox &&
        other.cropBox == cropBox &&
        other.rotation == rotation;
  }

  @override
  int get hashCode => Object.hash(mediaBox, cropBox, rotation);

  @override
  String toString() {
    return 'PageGeometry(mediaBox: $mediaBox, cropBox: $cropBox, '
        'rotation: $rotation)';
  }
}

/// The largest display-box overshoot that [PageGeometry.validate] clamps.
///
/// The value is fixed by `contracts/coordinates-and-geometry.md` section 6.1.
const double maxClampTolerancePt = 0.5;

/// The result of [PageGeometry.validate].
///
/// [rect] is the stored rectangle after normalization, and [wasClamped] is true
/// when numerical noise was removed. A caller that persists a clamped rectangle
/// must record a warning; the value object never clamps silently.
final class GeometryValidation {
  const GeometryValidation._({required this.rect, required this.wasClamped});

  /// The rectangle to store; it lies inside the page display box.
  final Rect rect;

  /// Whether [rect] differs from the validated input.
  final bool wasClamped;

  @override
  bool operator ==(Object other) {
    return other is GeometryValidation &&
        other.rect == rect &&
        other.wasClamped == wasClamped;
  }

  @override
  int get hashCode => Object.hash(rect, wasClamped);

  @override
  String toString() {
    return 'GeometryValidation(rect: $rect, wasClamped: $wasClamped)';
  }
}

void _checkRotation(int rotation) {
  if (rotation != 0 && rotation != 90 && rotation != 180 && rotation != 270) {
    throw ArgumentError.value(
      rotation,
      'rotation',
      'must be exactly 0, 90, 180, or 270',
    );
  }
}

Rect _rectBetween(Point a, Point b) {
  final double left = math.min(a.x, b.x);
  final double top = math.min(a.y, b.y);
  return Rect.fromLTWH(
    left,
    top,
    math.max(a.x, b.x) - left,
    math.max(a.y, b.y) - top,
  );
}

double _clamp(double value, double min, double max) {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}
