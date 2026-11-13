// Feldexa core geometry value objects (T015).
//
// The coordinate contract is
// specs/001-scanned-form-workflow/contracts/coordinates-and-geometry.md:
// values are PDF points in page display space (origin top-left, y down, after
// `/Rotate`). [Rect], [Size], and [Point] are immutable value objects that
// reject non-finite numbers and, for [Size] and [Rect], non-positive
// dimensions.
//
// There is deliberately no minimum interactive size here. A 6 pt checkbox is a
// valid model rectangle; hit-area inflation and the 4 pt resize floor are UI
// concerns that never change stored geometry.
//
// In memory the values keep full double precision. Only [Rect.toJson],
// [Size.toJson], and [Point.toJson] quantize to three decimals, as required by
// `data-model.md` section 2.2. A positive dimension that would quantize to zero
// is written as 0.001 pt so a valid value object always survives a JSON
// round-trip.
library;

/// A point in page display space, measured in PDF points.
///
/// Both coordinates must be finite. Negative coordinates are allowed: they
/// occur for crop offsets and for points that are validated against the page
/// display box later.
final class Point {
  const Point._(this.x, this.y);

  /// Creates a point.
  ///
  /// Throws [ArgumentError] if [x] or [y] is NaN or infinite.
  factory Point(double x, double y) {
    _checkFinite(x, 'x');
    _checkFinite(y, 'y');
    return Point._(x, y);
  }

  /// Reads `{"x": <number>, "y": <number>}`.
  ///
  /// Throws [FormatException] when a field is missing, is not numeric, or is
  /// not finite.
  factory Point.fromJson(Map<String, Object?> json) {
    return Point(_readFinite(json, 'x'), _readFinite(json, 'y'));
  }

  /// The display-space origin.
  static const Point zero = Point._(0, 0);

  /// Horizontal coordinate in points.
  final double x;

  /// Vertical coordinate in points.
  final double y;

  /// Returns the coordinates quantized to three decimals for serialization.
  ///
  /// This does not round the stored value; [x] and [y] keep full precision.
  Map<String, double> toJson() {
    return <String, double>{'x': _serializeFinite(x), 'y': _serializeFinite(y)};
  }

  @override
  bool operator ==(Object other) {
    return other is Point && other.x == x && other.y == y;
  }

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Point($x, $y)';
}

/// A size in page display space, measured in PDF points.
///
/// [width] and [height] must be finite and strictly positive. Small sizes are
/// accepted because the model has no minimum interactive size.
final class Size {
  const Size._(this.width, this.height);

  /// Creates a size.
  ///
  /// Throws [ArgumentError] if a dimension is not finite or is not strictly
  /// positive (zero, negative zero, and negative values are rejected).
  factory Size(double width, double height) {
    _checkPositive(width, 'width');
    _checkPositive(height, 'height');
    return Size._(width, height);
  }

  /// Reads `{"width": <number>, "height": <number>}`.
  ///
  /// Throws [FormatException] when a field is missing, is not numeric, is not
  /// finite, or is not strictly positive.
  factory Size.fromJson(Map<String, Object?> json) {
    return Size(_readPositive(json, 'width'), _readPositive(json, 'height'));
  }

  /// Horizontal extent in points; always greater than zero.
  final double width;

  /// Vertical extent in points; always greater than zero.
  final double height;

  /// Width divided by height.
  double get aspectRatio => width / height;

  /// Returns `width` and `height` quantized to three decimals.
  ///
  /// A positive dimension that would quantize to zero is written as 0.001 pt
  /// so the positive-size invariant survives a round-trip.
  Map<String, double> toJson() {
    return <String, double>{
      'width': _serializePositive(width),
      'height': _serializePositive(height),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is Size && other.width == width && other.height == height;
  }

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'Size($width, $height)';
}

/// An axis-aligned rectangle in page display space, measured in PDF points.
///
/// [left] and [top] are finite; [width] and [height] are finite and strictly
/// positive. The right and bottom edges must also remain finite, so a rectangle
/// cannot be constructed from finite operands whose sum overflows to infinity.
///
/// JSON uses the field names from `contracts/export-plan.md`:
/// `{"x", "y", "width", "height"}`. [x] and [y] are aliases for [left] and
/// [top].
final class Rect {
  const Rect._(this.left, this.top, this.width, this.height);

  /// Creates a rectangle at ([left], [top]) with [width] and [height].
  ///
  /// Throws [ArgumentError] if a coordinate is not finite, if [width] or
  /// [height] is not strictly positive, or if the right or bottom edge would
  /// overflow to infinity.
  factory Rect.fromLTWH(double left, double top, double width, double height) {
    _checkFinite(left, 'left');
    _checkFinite(top, 'top');
    _checkPositive(width, 'width');
    _checkPositive(height, 'height');
    if (!(left + width).isFinite) {
      throw ArgumentError.value(left, 'left', 'left + width must be finite');
    }
    if (!(top + height).isFinite) {
      throw ArgumentError.value(top, 'top', 'top + height must be finite');
    }
    return Rect._(left, top, width, height);
  }

  /// Reads a JSON object with numeric `x`, `y`, `width`, and `height`.
  ///
  /// Throws [FormatException] when a field is missing, is not numeric, is not
  /// finite, is not strictly positive, or produces a non-finite edge.
  factory Rect.fromJson(Map<String, Object?> json) {
    final double x = _readFinite(json, 'x');
    final double y = _readFinite(json, 'y');
    final double width = _readPositive(json, 'width');
    final double height = _readPositive(json, 'height');
    try {
      return Rect.fromLTWH(x, y, width, height);
    } on ArgumentError catch (error) {
      throw FormatException('Invalid rect JSON: ${error.message}');
    }
  }

  /// Horizontal coordinate of the left edge, in points.
  final double left;

  /// Vertical coordinate of the top edge, in points.
  final double top;

  /// Horizontal extent in points; always greater than zero.
  final double width;

  /// Vertical extent in points; always greater than zero.
  final double height;

  /// Alias for [left], matching the contract's `x` JSON field.
  double get x => left;

  /// Alias for [top], matching the contract's `y` JSON field.
  double get y => top;

  /// Horizontal coordinate of the right edge, in points.
  double get right => left + width;

  /// Vertical coordinate of the bottom edge, in points.
  double get bottom => top + height;

  /// The top-left corner.
  Point get origin => Point._(left, top);

  /// The width and height as a [Size].
  Size get size => Size._(width, height);

  /// Returns the rectangle quantized to three decimals for serialization.
  ///
  /// The stored fields are not rounded. Positive dimensions that would
  /// quantize to zero are written as 0.001 pt.
  Map<String, double> toJson() {
    return <String, double>{
      'x': _serializeFinite(left),
      'y': _serializeFinite(top),
      'width': _serializePositive(width),
      'height': _serializePositive(height),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is Rect &&
        other.left == left &&
        other.top == top &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() {
    return 'Rect(left: $left, top: $top, width: $width, height: $height)';
  }
}

const double _serializationScale = 1000;

void _checkFinite(double value, String name) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, name, 'must be finite');
  }
}

void _checkPositive(double value, String name) {
  _checkFinite(value, name);
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'must be greater than 0');
  }
}

double _readFinite(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! num) {
    throw FormatException(
      'JSON field "$key" must be a number, found '
      '${value == null ? 'nothing' : value.runtimeType}.',
    );
  }
  final double result = value.toDouble();
  if (!result.isFinite) {
    throw FormatException('JSON field "$key" must be finite, found $result.');
  }
  return result;
}

double _readPositive(Map<String, Object?> json, String key) {
  final double value = _readFinite(json, key);
  if (value <= 0) {
    throw FormatException(
      'JSON field "$key" must be greater than 0, found $value.',
    );
  }
  return value;
}

/// Quantizes [value] to three decimals, preserving finiteness.
///
/// Values whose scaling overflows have no fractional precision below 0.001 at
/// their magnitude, so they are returned unchanged.
double _serializeFinite(double value) {
  final double scaled = value * _serializationScale;
  if (!scaled.isFinite) {
    return value;
  }
  final double rounded = scaled.roundToDouble() / _serializationScale;
  // Normalize negative zero so canonical JSON does not contain "-0.0".
  return rounded == 0.0 ? 0.0 : rounded;
}

/// Quantizes a strictly positive dimension without rounding it down to zero.
double _serializePositive(double value) {
  final double quantized = _serializeFinite(value);
  return quantized == 0.0 ? 0.001 : quantized;
}
