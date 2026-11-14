// T013 `PageRasterPort` request and result DTOs.
//
// Owner: `packages/feldexa_ports/lib/src/dto/raster_dto.dart` (T013).
// Normative source: `contracts/ports.md` §2.2 and §2.10.
//
// The canonical `PageGeometry` used by `PageRasterPort.pageDimensions` comes
// from `feldexa_core`; this file must not redeclare it. Binary payloads are
// always [Uint8List], never a path, `File`, or `content://` URI.

import 'dart:typed_data';

import 'package:feldexa_ports/evidence.dart';

import 'validation.dart';

/// Pixel layout of a rendered page (`contracts/ports.md` §2.2).
enum RasterFormat {
  /// Four bytes per pixel: red, green, blue, alpha.
  rgba8888(4),

  /// One byte per pixel: grayscale intensity.
  gray8(1);

  const RasterFormat(this.bytesPerPixel);

  /// Bytes required for one pixel in this format.
  final int bytesPerPixel;
}

/// One page-render request (`contracts/ports.md` §2.2).
///
/// [scale] is relative to 72 dpi PDF points, so analysis uses
/// `200 / 72` and [maxDimensionPx] is a safety cap rather than a target.
final class RasterRequest {
  /// Creates a page-render request.
  ///
  /// [pageIndex] must be non-negative, [scale] finite and positive, and
  /// [maxDimensionPx] at least 1. Invalid values throw a safe [ArgumentError].
  factory RasterRequest({
    required String sourceId,
    required int pageIndex,
    required double scale,
    required RasterFormat format,
    int maxDimensionPx = defaultMaxDimensionPx,
  }) {
    final String checkedSourceId = requireUuidV4(sourceId, 'sourceId');
    final int checkedPageIndex = requireNonNegativeInt(pageIndex, 'pageIndex');
    final double checkedScale = requireFinitePositive(scale, 'scale');
    final int checkedDimension = requirePositiveInt(
      maxDimensionPx,
      'maxDimensionPx',
    );
    return RasterRequest._(
      sourceId: checkedSourceId,
      pageIndex: checkedPageIndex,
      scale: checkedScale,
      format: format,
      maxDimensionPx: checkedDimension,
    );
  }

  const RasterRequest._({
    required this.sourceId,
    required this.pageIndex,
    required this.scale,
    required this.format,
    required this.maxDimensionPx,
  });

  /// Default safety cap for either rendered dimension.
  static const int defaultMaxDimensionPx = 4096;

  /// UUIDv4 of the immutable encrypted source.
  final String sourceId;

  /// Zero-based page index.
  final int pageIndex;

  /// Render scale; `1.0` equals 72 dpi PDF points.
  final double scale;

  /// Requested pixel layout.
  final RasterFormat format;

  /// Safety cap for either rendered dimension, in pixels.
  final int maxDimensionPx;

  @override
  String toString() {
    return 'RasterRequest(pageIndex: $pageIndex, scale: $scale, '
        'format: ${format.name}, maxDimensionPx: $maxDimensionPx)';
  }
}

/// The rendered pixels of one page (`contracts/ports.md` §2.2).
///
/// [bytes] is the raw pixel buffer; [bytesPerRow] may include row padding but
/// must cover at least one full row of [width] pixels in [format].
final class RasterImage {
  /// Creates a rendered page image.
  ///
  /// [bytes] must be non-empty and hold at least `bytesPerRow * height` bytes.
  /// [width], [height], and [bytesPerRow] must be positive, and [bytesPerRow]
  /// must cover one row of [width] pixels in [format]. Invalid values throw a
  /// safe [ArgumentError].
  factory RasterImage({
    required Uint8List bytes,
    required int width,
    required int height,
    required int bytesPerRow,
    required RasterFormat format,
    required CapabilityEvidence evidence,
  }) {
    if (bytes.isEmpty) {
      throw ArgumentError('bytes must contain the rendered pixels');
    }
    final int checkedWidth = requirePositiveInt(width, 'width');
    final int checkedHeight = requirePositiveInt(height, 'height');
    final int checkedBytesPerRow = requirePositiveInt(
      bytesPerRow,
      'bytesPerRow',
    );
    if (checkedBytesPerRow < checkedWidth * format.bytesPerPixel) {
      throw ArgumentError(
        'bytesPerRow must cover one row of the raster format',
      );
    }
    if (bytes.length < checkedBytesPerRow * checkedHeight) {
      throw ArgumentError('bytes must contain every row of the raster image');
    }
    return RasterImage._(
      bytes: bytes,
      width: checkedWidth,
      height: checkedHeight,
      bytesPerRow: checkedBytesPerRow,
      format: format,
      evidence: evidence,
    );
  }

  const RasterImage._({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.format,
    required this.evidence,
  });

  /// The raw pixel buffer.
  final Uint8List bytes;

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Number of bytes per row, including any padding.
  final int bytesPerRow;

  /// Pixel layout of [bytes].
  final RasterFormat format;

  /// Evidence class of the adapter that produced this image.
  final CapabilityEvidence evidence;

  @override
  String toString() {
    return 'RasterImage(width: $width, height: $height, '
        'format: ${format.name})';
  }
}
