// 200 DPI grayscale page raster analysis primitives (T051).
//
// Normative sources:
//  * specs/001-scanned-form-workflow/contracts/coordinates-and-geometry.md
//    section 4 ("Raster space"), and
//  * specs/001-scanned-form-workflow/contracts/recognition-output.md section
//    2.1 (ink coverage), which T052/T053 consume.
//
// Scope: this library owns raster *primitives*, not detectors. It converts a
// page display size in PDF points to the 200 DPI analysis raster dimensions,
// maps between raster pixel indices and display-space points, holds an
// immutable one-byte-per-pixel grayscale buffer, builds summed-area/integral
// images, and reports rectangle luminance sums and ink coverage. Ruling-line,
// box, table-grid, whitespace, and alignment detection belong to T052; OCR
// belongs to T056.
//
// Conventions:
//  * The analysis raster is grayscale, one byte per pixel, row-major, with
//    stride equal to the width, no row padding, and no alpha channel.
//    Luminance 0 is black, 255 is white.
//  * Pixel `i` covers the display-space interval
//    [i / rasterScale, (i + 1) / rasterScale) on both axes; its centre is
//    (i + 0.5) / rasterScale. [pointToPixel] returns the pixel whose centre is
//    nearest to a display-space point. For every point strictly inside a
//    pixel, that is the containing pixel; for a point exactly on a pixel
//    boundary, the right/lower pixel wins. This half-pixel origin choice is
//    the one fixed by `coordinates-and-geometry.md` section 4.
//  * Rectangles are half-open integer pixel rectangles: they cover columns
//    [left, right) and rows [top, bottom). APIs never clamp implicitly; a
//    rectangle that extends outside the raster raises [RangeError], and a
//    rectangle with non-positive width or height is rejected at construction.
//  * All arithmetic is deterministic. There is no clock, randomness, file or
//    network I/O, locale, or platform dependency in this library.
//
// Pages arrive in display orientation because PDFium already applies
// `/Rotate`. This layer therefore never rotates, mirrors, or crop-maps a page;
// page rotation and CropBox handling stay in feldexa_core's `PageGeometry`
// (`coordinates-and-geometry.md` sections 1-2).
library;

import 'dart:typed_data';

/// Analysis raster resolution fixed by
/// `coordinates-and-geometry.md` section 4.
const int analysisDpi = 200;

/// Raster pixels per PDF point at [analysisDpi] (`200 / 72`).
const double rasterScale = analysisDpi / 72.0;

/// Default luminance threshold below which a pixel counts as ink.
///
/// With the default, luminance values 0-127 are ink and 128-255 are
/// background (contract `recognition-output.md` section 2.1 measures ink
/// density against this default).
const int defaultInkThreshold = 128;

/// The 200 DPI analysis raster dimensions for a page display size.
///
/// `widthPx = round(displayWidthPt * rasterScale)` and likewise for the
/// height, exactly as specified by `coordinates-and-geometry.md` section 4.
/// Dart's [double.round] rounds halves away from zero; for the positive
/// dimensions accepted here that is "half up".
///
/// A size must be finite and strictly positive on both axes, and each rounded
/// dimension must be at least one pixel. Sizes that are too small to produce a
/// pixel (below `0.5 / rasterScale` pt, about 0.18 pt) are rejected rather
/// than clamped, so a caller never silently analyses a zero-pixel page.
final class RasterSize {
  const RasterSize._(this.widthPx, this.heightPx);

  /// Computes the analysis raster size for a display-space page size in
  /// points.
  ///
  /// Throws [ArgumentError] for a non-finite or non-positive dimension, or
  /// for a dimension that rounds to fewer than one pixel.
  factory RasterSize.fromDisplaySize({
    required double widthPt,
    required double heightPt,
  }) {
    return RasterSize._(widthPxFor(widthPt), heightPxFor(heightPt));
  }

  /// Rounds one display-space width in points to analysis pixels.
  ///
  /// Throws [ArgumentError] for a non-finite or non-positive [widthPt], or
  /// when the rounded width is below one pixel.
  static int widthPxFor(double widthPt) {
    return _dimensionPx(widthPt, 'widthPt');
  }

  /// Rounds one display-space height in points to analysis pixels.
  ///
  /// Throws [ArgumentError] for a non-finite or non-positive [heightPt], or
  /// when the rounded height is below one pixel.
  static int heightPxFor(double heightPt) {
    return _dimensionPx(heightPt, 'heightPt');
  }

  static int _dimensionPx(double points, String name) {
    if (!points.isFinite) {
      throw ArgumentError.value(points, name, 'must be finite');
    }
    if (!(points > 0)) {
      throw ArgumentError.value(points, name, 'must be strictly positive');
    }
    final int pixels = (points * rasterScale).round();
    if (pixels < 1) {
      throw ArgumentError.value(
        points,
        name,
        'must produce at least one pixel at $analysisDpi DPI',
      );
    }
    return pixels;
  }

  /// Raster width in pixels; always at least 1.
  final int widthPx;

  /// Raster height in pixels; always at least 1.
  final int heightPx;

  /// The whole raster as a half-open pixel rectangle.
  PixelRect get bounds =>
      PixelRect(left: 0, top: 0, width: widthPx, height: heightPx);

  @override
  bool operator ==(Object other) {
    return other is RasterSize &&
        other.widthPx == widthPx &&
        other.heightPx == heightPx;
  }

  @override
  int get hashCode => Object.hash(widthPx, heightPx);

  @override
  String toString() => 'RasterSize(${widthPx}x$heightPx)';
}

/// A half-open integer rectangle in raster pixel space.
///
/// The rectangle covers columns `[left, right)` and rows `[top, bottom)`,
/// where `right = left + width` and `bottom = top + height`. Adjacent
/// rectangles that share an edge do not overlap. The rectangle is independent
/// of any particular raster; a raster operation checks that it lies inside
/// that raster and raises [RangeError] instead of clamping.
final class PixelRect {
  const PixelRect._(this.left, this.top, this.width, this.height);

  /// Creates a pixel rectangle from its top-left corner and positive size.
  ///
  /// Throws [ArgumentError] if [left] or [top] is negative, or if [width] or
  /// [height] is not strictly positive.
  factory PixelRect({
    required int left,
    required int top,
    required int width,
    required int height,
  }) {
    if (left < 0) {
      throw ArgumentError.value(left, 'left', 'must be non-negative');
    }
    if (top < 0) {
      throw ArgumentError.value(top, 'top', 'must be non-negative');
    }
    if (width <= 0) {
      throw ArgumentError.value(width, 'width', 'must be strictly positive');
    }
    if (height <= 0) {
      throw ArgumentError.value(height, 'height', 'must be strictly positive');
    }
    return PixelRect._(left, top, width, height);
  }

  /// Creates a pixel rectangle from half-open left/top/right/bottom edges.
  ///
  /// Throws [ArgumentError] if an edge is negative or if `right <= left` or
  /// `bottom <= top`.
  factory PixelRect.fromLTRB(int left, int top, int right, int bottom) {
    if (left < 0) {
      throw ArgumentError.value(left, 'left', 'must be non-negative');
    }
    if (top < 0) {
      throw ArgumentError.value(top, 'top', 'must be non-negative');
    }
    if (right <= left) {
      throw ArgumentError.value(right, 'right', 'must be greater than left');
    }
    if (bottom <= top) {
      throw ArgumentError.value(bottom, 'bottom', 'must be greater than top');
    }
    return PixelRect._(left, top, right - left, bottom - top);
  }

  /// First covered column (inclusive).
  final int left;

  /// First covered row (inclusive).
  final int top;

  /// Number of covered columns; always at least 1.
  final int width;

  /// Number of covered rows; always at least 1.
  final int height;

  /// First column after the rectangle (exclusive).
  int get right => left + width;

  /// First row after the rectangle (exclusive).
  int get bottom => top + height;

  /// Number of pixels covered: `width * height`.
  int get area => width * height;

  /// Whether `(x, y)` is inside this half-open rectangle.
  bool contains(int x, int y) {
    return x >= left && x < right && y >= top && y < bottom;
  }

  @override
  bool operator ==(Object other) {
    return other is PixelRect &&
        other.left == left &&
        other.top == top &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'PixelRect($left, $top, $width, $height)';
}

/// Ink counts for one half-open pixel rectangle.
///
/// [fraction] is the only floating-point value; all counting is exact integer
/// arithmetic. For threshold comparisons, prefer [exceedsPercent], which
/// compares `inkPixels * 100` against `area * percent` exactly instead of
/// comparing floating-point fractions.
final class InkCoverage {
  const InkCoverage._(this.inkPixels, this.totalPixels);

  /// Creates a coverage result.
  ///
  /// Throws [ArgumentError] if [totalPixels] is not positive or
  /// [inkPixels] is outside `0 ... totalPixels`.
  factory InkCoverage({required int inkPixels, required int totalPixels}) {
    if (totalPixels <= 0) {
      throw ArgumentError.value(
        totalPixels,
        'totalPixels',
        'must be strictly positive',
      );
    }
    if (inkPixels < 0 || inkPixels > totalPixels) {
      throw ArgumentError.value(
        inkPixels,
        'inkPixels',
        'must be between 0 and totalPixels',
      );
    }
    return InkCoverage._(inkPixels, totalPixels);
  }

  /// Number of pixels whose luminance is below the analysis threshold.
  final int inkPixels;

  /// Total number of pixels in the measured rectangle; always positive.
  final int totalPixels;

  /// Ink pixels divided by total pixels, in `0.0 ... 1.0`.
  double get fraction => inkPixels / totalPixels;

  /// Whether the ink fraction is strictly greater than [percent] percent.
  ///
  /// Uses exact integer arithmetic:
  /// `inkPixels * 100 > totalPixels * percent`. Throws [ArgumentError] if
  /// [percent] is outside `0 ... 100`.
  bool exceedsPercent(int percent) {
    if (percent < 0 || percent > 100) {
      throw ArgumentError.value(
        percent,
        'percent',
        'must be between 0 and 100',
      );
    }
    return inkPixels * 100 > totalPixels * percent;
  }

  @override
  bool operator ==(Object other) {
    return other is InkCoverage &&
        other.inkPixels == inkPixels &&
        other.totalPixels == totalPixels;
  }

  @override
  int get hashCode => Object.hash(inkPixels, totalPixels);

  @override
  String toString() => 'InkCoverage($inkPixels/$totalPixels)';
}

/// An immutable one-byte-per-pixel grayscale page raster.
///
/// The buffer is row-major with stride equal to [width], no row padding, and
/// no alpha channel. The constructor copies the supplied bytes: later changes
/// to the source list never affect this raster. [pixels] returns an
/// unmodifiable view of the internal copy, and all pixel access is
/// bounds-checked.
///
/// Two optional factories convert 8-bit color buffers deterministically:
/// [GrayRaster.fromRgba8888] (R, G, B, A byte order) and
/// [GrayRaster.fromBgra8888] (B, G, R, A byte order). Both require fully
/// opaque pixels (alpha 255), because the analysis raster is opaque paper; a
/// caller with translucent pixels must composite them onto white before
/// conversion. The luminance formula is the integer Rec. 601 approximation
/// documented on those factories.
final class GrayRaster {
  GrayRaster._(this.width, this.height, this._pixels);

  /// Copies a grayscale buffer of exactly `width * height` bytes.
  ///
  /// Each byte is a luminance value from 0 (black) to 255 (white). The buffer
  /// must have no row padding: its length must equal `width * height`, which is
  /// the documented stride of [width]. Throws [ArgumentError] for a
  /// non-positive or overflowing dimension, a wrong buffer length, or a byte
  /// outside `0 ... 255`.
  factory GrayRaster.fromGrayBytes({
    required int width,
    required int height,
    required List<int> bytes,
  }) {
    _checkDimensions(width, height);
    final int expected = width * height;
    if (bytes.length != expected) {
      throw ArgumentError.value(
        bytes.length,
        'bytes.length',
        'expected exactly $expected for a ${width}x$height grayscale raster '
            '(stride $width, one byte per pixel, no padding)',
      );
    }
    final Uint8List copy = Uint8List(expected);
    if (bytes is Uint8List) {
      copy.setRange(0, expected, bytes);
    } else {
      for (int i = 0; i < expected; i++) {
        final int value = bytes[i];
        if (value < 0 || value > 255) {
          throw ArgumentError.value(
            value,
            'bytes[$i]',
            'must be between 0 and 255',
          );
        }
        copy[i] = value;
      }
    }
    return GrayRaster._(width, height, copy);
  }

  /// Converts a non-premultiplied, fully opaque 8-bit RGBA buffer.
  ///
  /// The buffer is four bytes per pixel in R, G, B, A order, row-major, with
  /// stride `4 * width` and no padding. Every alpha byte must be 255; the
  /// alpha channel is otherwise not used. Each output pixel is
  ///
  /// ```text
  /// luminance = (299 * R + 587 * G + 114 * B + 500) ~/ 1000
  /// ```
  ///
  /// the Rec. 601 luma approximation with integer weights scaled by 1000 and
  /// half-up rounding. It is fully deterministic and yields 0-255.
  ///
  /// Throws [ArgumentError] for invalid dimensions, a wrong buffer length, a
  /// channel outside `0 ... 255`, or a non-opaque alpha byte.
  factory GrayRaster.fromRgba8888({
    required int width,
    required int height,
    required List<int> bytes,
  }) {
    return _fromColorBytes(
      width: width,
      height: height,
      bytes: bytes,
      redOffset: 0,
      blueOffset: 2,
      channelOrder: 'RGBA',
    );
  }

  /// Converts a non-premultiplied, fully opaque 8-bit BGRA buffer.
  ///
  /// Identical to [GrayRaster.fromRgba8888] except that each pixel is stored
  /// in B, G, R, A order. The same Rec. 601 integer luminance formula is
  /// applied after reordering:
  ///
  /// ```text
  /// luminance = (299 * R + 587 * G + 114 * B + 500) ~/ 1000
  /// ```
  ///
  /// Throws [ArgumentError] for invalid dimensions, a wrong buffer length, a
  /// channel outside `0 ... 255`, or a non-opaque alpha byte.
  factory GrayRaster.fromBgra8888({
    required int width,
    required int height,
    required List<int> bytes,
  }) {
    return _fromColorBytes(
      width: width,
      height: height,
      bytes: bytes,
      redOffset: 2,
      blueOffset: 0,
      channelOrder: 'BGRA',
    );
  }

  static GrayRaster _fromColorBytes({
    required int width,
    required int height,
    required List<int> bytes,
    required int redOffset,
    required int blueOffset,
    required String channelOrder,
  }) {
    _checkDimensions(width, height);
    final int pixelCount = width * height;
    final int expected = pixelCount * 4;
    if (bytes.length != expected) {
      throw ArgumentError.value(
        bytes.length,
        'bytes.length',
        'expected exactly $expected for a ${width}x$height $channelOrder '
            'raster (four bytes per pixel, no padding)',
      );
    }
    final Uint8List luminances = Uint8List(pixelCount);
    final bool typed = bytes is Uint8List;
    for (int i = 0; i < pixelCount; i++) {
      final int offset = i * 4;
      final int red = bytes[offset + redOffset];
      final int green = bytes[offset + 1];
      final int blue = bytes[offset + blueOffset];
      final int alpha = bytes[offset + 3];
      if (!typed) {
        _checkChannel(red, 'bytes[${offset + redOffset}]');
        _checkChannel(green, 'bytes[${offset + 1}]');
        _checkChannel(blue, 'bytes[${offset + blueOffset}]');
        _checkChannel(alpha, 'bytes[${offset + 3}]');
      }
      if (alpha != 255) {
        throw ArgumentError.value(
          alpha,
          'bytes[${offset + 3}]',
          'alpha must be 255 (opaque); composite translucent page renders '
              'onto white before analysis',
        );
      }
      luminances[i] = _luminance601(red, green, blue);
    }
    return GrayRaster._(width, height, luminances);
  }

  static void _checkChannel(int value, String name) {
    if (value < 0 || value > 255) {
      throw ArgumentError.value(value, name, 'must be between 0 and 255');
    }
  }

  static int _luminance601(int red, int green, int blue) {
    return (299 * red + 587 * green + 114 * blue + 500) ~/ 1000;
  }

  static void _checkDimensions(int width, int height) {
    if (width <= 0) {
      throw ArgumentError.value(width, 'width', 'must be strictly positive');
    }
    if (height <= 0) {
      throw ArgumentError.value(height, 'height', 'must be strictly positive');
    }
    // Guard the `width * height` byte count against 32-bit overflow on
    // platforms whose `int` is smaller than the host VM's. The analysis
    // raster is allowed to exceed 2^31 pixels only where the platform can
    // address it; rejecting keeps the stride and index arithmetic exact.
    if (width * height > 0x7FFFFFFF) {
      throw ArgumentError.value(
        '$width x $height',
        'width x height',
        'exceeds the supported 2^31 - 1 pixels',
      );
    }
  }

  /// Raster width in pixels; always at least 1.
  final int width;

  /// Raster height in pixels; always at least 1.
  final int height;

  final Uint8List _pixels;

  /// Bytes per row; always equal to [width] because there is no row padding.
  int get stride => width;

  /// Total number of pixels (`width * height`).
  int get pixelCount => width * height;

  /// The whole raster as a half-open pixel rectangle.
  PixelRect get bounds =>
      PixelRect(left: 0, top: 0, width: width, height: height);

  /// An unmodifiable view of the internal grayscale bytes, row-major.
  ///
  /// Each value is 0 (black) to 255 (white). Writing through the view throws
  /// [UnsupportedError]; use a copied buffer if mutation is required.
  Uint8List get pixels => _pixels.asUnmodifiableView();

  /// Returns the luminance at column [x], row [y].
  ///
  /// Throws [RangeError] when [x] is outside `0 ... width - 1` or [y] is
  /// outside `0 ... height - 1`.
  int luminanceAt(int x, int y) {
    _checkPixel(x, y);
    return _pixels[y * width + x];
  }

  /// Whether the pixel at ([x], [y]) is ink under [threshold].
  ///
  /// A pixel is ink exactly when its luminance is below [threshold]. The
  /// default threshold is [defaultInkThreshold] (128), so 127 is ink and 128
  /// is background. Throws [RangeError] for an out-of-raster coordinate and
  /// [ArgumentError] when [threshold] is outside `0 ... 256`.
  bool isInkAt(int x, int y, {int threshold = defaultInkThreshold}) {
    _checkInkThreshold(threshold);
    return luminanceAt(x, y) < threshold;
  }

  /// Builds the analysis primitives for this raster in one pass each.
  RasterAnalysis analyze({int inkThreshold = defaultInkThreshold}) {
    return RasterAnalysis(this, inkThreshold: inkThreshold);
  }

  void _checkPixel(int x, int y) {
    if (x < 0 || x >= width) {
      throw RangeError.range(x, 0, width - 1, 'x');
    }
    if (y < 0 || y >= height) {
      throw RangeError.range(y, 0, height - 1, 'y');
    }
  }

  @override
  String toString() => 'GrayRaster(${width}x$height)';
}

/// Validates a luminance threshold for ink classification.
///
/// Allowed values are `0 ... 256`. With 0 no pixel is ink; with 256 every
/// pixel (including 255) is ink. Throws [ArgumentError] otherwise.
void _checkInkThreshold(int threshold) {
  if (threshold < 0 || threshold > 256) {
    throw ArgumentError.value(
      threshold,
      'threshold',
      'must be between 0 and 256',
    );
  }
}

/// A summed-area table (integral image) over one non-negative raster channel.
///
/// The table has `(width + 1) * (height + 1)` entries and stores sums in a
/// [Uint32List]. It therefore supports at most `2^32 - 1` total sum; for a
/// 0-255 luminance channel that is a raster of up to 16,843,009 pixels (a
/// 4096 x 4096 page still fits, at 4,278,190,080). Larger rasters are
/// rejected rather than silently truncated.
///
/// [sum] takes a half-open [PixelRect] and returns the exact sum of the
/// selected pixels in O(1). Rectangles are bounds-checked against this table's
/// dimensions; they are never clamped.
final class IntegralImage {
  IntegralImage._(this.width, this.height, this._table);

  /// Builds a summed-area table over the luminance values of [raster].
  ///
  /// Throws [ArgumentError] if the raster is too large for a 32-bit sum.
  factory IntegralImage.fromGrayRaster(GrayRaster raster) {
    return _build(
      width: raster.width,
      height: raster.height,
      maxValue: 255,
      valueAt: (int x, int y) => raster.luminanceAt(x, y),
    );
  }

  /// Builds a summed-area table over a binary ink mask of [raster].
  ///
  /// A pixel contributes 1 exactly when its luminance is below [threshold]
  /// (default [defaultInkThreshold]); otherwise it contributes 0. Throws
  /// [ArgumentError] for a threshold outside `0 ... 256`.
  factory IntegralImage.fromInkMask(
    GrayRaster raster, {
    int threshold = defaultInkThreshold,
  }) {
    _checkInkThreshold(threshold);
    return _build(
      width: raster.width,
      height: raster.height,
      maxValue: 1,
      valueAt: (int x, int y) => raster.luminanceAt(x, y) < threshold ? 1 : 0,
    );
  }

  static IntegralImage _build({
    required int width,
    required int height,
    required int maxValue,
    required int Function(int x, int y) valueAt,
  }) {
    final int pixelCount = width * height;
    if (pixelCount * maxValue > 0xFFFFFFFF) {
      throw ArgumentError.value(
        '${width}x$height (max value $maxValue)',
        'raster',
        'total sum exceeds the 32-bit integral-image capacity',
      );
    }
    final int tableWidth = width + 1;
    final Uint32List table = Uint32List(tableWidth * (height + 1));
    for (int y = 0; y < height; y++) {
      int rowSum = 0;
      final int previousRow = y * tableWidth;
      final int currentRow = (y + 1) * tableWidth;
      for (int x = 0; x < width; x++) {
        rowSum += valueAt(x, y);
        table[currentRow + x + 1] = table[previousRow + x + 1] + rowSum;
      }
    }
    return IntegralImage._(width, height, table);
  }

  /// Width of the source raster in pixels.
  final int width;

  /// Height of the source raster in pixels.
  final int height;

  final Uint32List _table;

  /// The sum over the whole raster.
  int get total => _table[width + (height * (width + 1))];

  /// The exact sum of the pixels in [rect].
  ///
  /// [rect] is half-open: columns `[left, right)` and rows `[top, bottom)`.
  /// Throws [RangeError] when the rectangle extends beyond this raster.
  int sum(PixelRect rect) {
    final int tableWidth = width + 1;
    if (rect.right > width) {
      throw RangeError.range(rect.right, 0, width, 'rect.right');
    }
    if (rect.bottom > height) {
      throw RangeError.range(rect.bottom, 0, height, 'rect.bottom');
    }
    return _table[rect.bottom * tableWidth + rect.right] -
        _table[rect.top * tableWidth + rect.right] -
        _table[rect.bottom * tableWidth + rect.left] +
        _table[rect.top * tableWidth + rect.left];
  }

  @override
  String toString() => 'IntegralImage(${width}x$height)';
}

/// Integral-image analysis primitives over one grayscale page raster.
///
/// The factory builds two summed-area tables in one pass each: one over the
/// luminance values and one over the binary ink mask for [inkThreshold].
/// [luminanceSum] and [inkCoverage] then answer rectangle queries in O(1)
/// without touching the pixel buffer again.
///
/// This type deliberately decides no field candidates and detects no lines,
/// boxes, grids, whitespace, or alignment. It is a measurement primitive for
/// T052/T053.
final class RasterAnalysis {
  RasterAnalysis._(
    this.raster,
    this.inkThreshold,
    this.luminanceIntegral,
    this.inkIntegral,
  );

  /// Builds the analysis tables for [raster].
  ///
  /// Throws [ArgumentError] for a threshold outside `0 ... 256`, or when the
  /// raster is too large for 32-bit integral-image sums.
  factory RasterAnalysis(
    GrayRaster raster, {
    int inkThreshold = defaultInkThreshold,
  }) {
    _checkInkThreshold(inkThreshold);
    return RasterAnalysis._(
      raster,
      inkThreshold,
      IntegralImage.fromGrayRaster(raster),
      IntegralImage.fromInkMask(raster, threshold: inkThreshold),
    );
  }

  /// The analysed raster.
  final GrayRaster raster;

  /// Threshold used by [inkIntegral]: luminance below this value is ink.
  final int inkThreshold;

  /// Summed-area table over luminance values.
  final IntegralImage luminanceIntegral;

  /// Summed-area table over the binary ink mask; [IntegralImage.sum] counts
  /// ink pixels and [IntegralImage.total] is the page-wide ink count.
  final IntegralImage inkIntegral;

  /// Exact sum of luminance values in [rect].
  int luminanceSum(PixelRect rect) => luminanceIntegral.sum(rect);

  /// Exact ink count and fraction for [rect].
  InkCoverage inkCoverage(PixelRect rect) {
    return InkCoverage(
      inkPixels: inkIntegral.sum(rect),
      totalPixels: rect.area,
    );
  }

  @override
  String toString() =>
      'RasterAnalysis(${raster.width}x${raster.height}, '
      'inkThreshold: $inkThreshold)';
}

/// Converts a zero-based raster pixel index to the display-space point at the
/// pixel's centre: `(index + 0.5) / rasterScale`.
///
/// The mapping is one-dimensional; the same formula applies to columns and
/// rows. Throws [ArgumentError] for a negative index. The caller is
/// responsible for checking the index against the page's raster dimensions.
double pixelCenterToPoint(int index) {
  if (index < 0) {
    throw ArgumentError.value(index, 'index', 'must be non-negative');
  }
  return (index + 0.5) / rasterScale;
}

/// Converts a pixel boundary index to display-space points: `edge /
/// rasterScale`.
///
/// This is the conversion for the left/top or right/bottom edge of a
/// half-open pixel rectangle; [pixelCenterToPoint] is the conversion for a
/// pixel centre. Throws [ArgumentError] for a negative edge.
double pixelEdgeToPoint(int edge) {
  if (edge < 0) {
    throw ArgumentError.value(edge, 'edge', 'must be non-negative');
  }
  return edge / rasterScale;
}

/// Converts a non-negative display-space point to the nearest raster pixel
/// index.
///
/// The result is `floor(point * rasterScale)`: the pixel whose centre is
/// nearest to the point. Pixel `i` owns the scaled interval `[i, i + 1)`, so a
/// point exactly at a boundary is assigned to the right/lower pixel. The
/// returned index is not range-checked against a page size; for a point on the
/// right or bottom page edge it can equal the raster dimension. Mapping a
/// pixel centre back with [pixelCenterToPoint] returns the original index.
///
/// Like every double mapping, a boundary point reconstructed by dividing an
/// integer index by [rasterScale] can fall on the lower side of the boundary
/// by one floating-point ulp; use [pixelCenterToPoint] for index-exact
/// round-trips and compare edges with an explicit tolerance when a caller
/// derives points by division.
///
/// Throws [ArgumentError] for a non-finite or negative [point].
int pointToPixel(double point) {
  if (!point.isFinite) {
    throw ArgumentError.value(point, 'point', 'must be finite');
  }
  if (point < 0) {
    throw ArgumentError.value(point, 'point', 'must be non-negative');
  }
  return (point * rasterScale).floor();
}
