// T051 host-VM tests for the 200 DPI grayscale page raster primitives.
//
// The test package is `flutter_test` because the widget/unit suites in this
// repository standardise on it and `@TestOn('vm')` keeps this file on the host
// VM. `packages/feldexa_recognition/pubspec.yaml` deliberately has no
// dev_dependency yet: T050 owns the single `flutter_test` addition for this
// parallel US2 slice, and this worktree must not edit the pubspec. The shared
// pub workspace resolves `flutter_test` from the other member packages, so the
// import works; remove the suppression below once T050's dev_dependency is
// merged.
// ignore_for_file: depend_on_referenced_packages

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:feldexa_recognition/src/raster.dart';
import 'package:flutter_test/flutter_test.dart';

/// A deterministic linear congruential generator for synthetic test patterns.
///
/// Using an explicit generator instead of `dart:math`'s `Random` keeps the
/// test data identical across Dart versions.
int _nextState(int state) => (state * 1664525 + 1013904223) & 0xFFFFFFFF;

Uint8List _filledBytes(int width, int height, int value) {
  final Uint8List bytes = Uint8List(width * height);
  bytes.fillRange(0, bytes.length, value);
  return bytes;
}

GrayRaster _rasterFrom(int width, int height, List<int> values) {
  return GrayRaster.fromGrayBytes(width: width, height: height, bytes: values);
}

GrayRaster _syntheticRaster(int width, int height, {int seed = 0x5EED}) {
  final Uint8List bytes = Uint8List(width * height);
  int state = seed;
  for (int i = 0; i < bytes.length; i++) {
    state = _nextState(state);
    bytes[i] = (state >> 16) & 0xFF;
  }
  return GrayRaster.fromGrayBytes(width: width, height: height, bytes: bytes);
}

int _naiveLuminanceSum(GrayRaster raster, PixelRect rect) {
  int sum = 0;
  for (int y = rect.top; y < rect.bottom; y++) {
    for (int x = rect.left; x < rect.right; x++) {
      sum += raster.luminanceAt(x, y);
    }
  }
  return sum;
}

int _naiveInkCount(GrayRaster raster, PixelRect rect, int threshold) {
  int count = 0;
  for (int y = rect.top; y < rect.bottom; y++) {
    for (int x = rect.left; x < rect.right; x++) {
      if (raster.luminanceAt(x, y) < threshold) {
        count++;
      }
    }
  }
  return count;
}

void main() {
  group('analysis constants and scale', () {
    test('analysis DPI is the contract 200', () {
      expect(analysisDpi, 200);
    });

    test('raster scale is exactly 200 / 72', () {
      expect(rasterScale, 200 / 72.0);
      expect(rasterScale, closeTo(2.7777777777777777, 1e-15));
      expect(rasterScale * 72.0, closeTo(200.0, 1e-12));
    });

    test('default ink threshold is 128', () {
      expect(defaultInkThreshold, 128);
    });
  });

  group('RasterSize', () {
    test('A4 portrait at 200 DPI rounds to 1654 x 2339', () {
      final RasterSize size = RasterSize.fromDisplaySize(
        widthPt: 595.28,
        heightPt: 841.89,
      );
      expect(size.widthPx, 1654);
      expect(size.heightPx, 2339);
      expect(
        size,
        RasterSize.fromDisplaySize(widthPt: 595.28, heightPt: 841.89),
      );
      expect(size.bounds, PixelRect.fromLTRB(0, 0, 1654, 2339));
    });

    test('A4 landscape swaps the rounded dimensions', () {
      final RasterSize size = RasterSize.fromDisplaySize(
        widthPt: 841.89,
        heightPt: 595.28,
      );
      expect(size.widthPx, 2339);
      expect(size.heightPx, 1654);
    });

    test('rounding is half up at the pixel boundary', () {
      expect(RasterSize.widthPxFor(1.49 / rasterScale), 1);
      expect(RasterSize.widthPxFor(1.51 / rasterScale), 2);
      expect(RasterSize.heightPxFor(1.49 / rasterScale), 1);
      expect(RasterSize.heightPxFor(1.51 / rasterScale), 2);
    });

    test('a whole number of pixels is exact', () {
      expect(RasterSize.widthPxFor(72.0), 200);
      expect(RasterSize.heightPxFor(72.0), 200);
      expect(RasterSize.widthPxFor(0.36), 1);
    });

    test('the minimum accepted size produces one pixel', () {
      expect(RasterSize.widthPxFor(1.0 / rasterScale), 1);
      expect(RasterSize.heightPxFor(1.0 / rasterScale), 1);
    });

    test('a size that would round to zero pixels is rejected', () {
      expect(
        () => RasterSize.widthPxFor(0.4 / rasterScale),
        throwsArgumentError,
      );
      expect(
        () => RasterSize.heightPxFor(0.4 / rasterScale),
        throwsArgumentError,
      );
    });

    test('zero, negative, NaN, and infinite dimensions are rejected', () {
      for (final double invalid in <double>[
        0.0,
        -0.0,
        -1.0,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => RasterSize.widthPxFor(invalid),
          throwsArgumentError,
          reason: 'width $invalid',
        );
        expect(
          () => RasterSize.heightPxFor(invalid),
          throwsArgumentError,
          reason: 'height $invalid',
        );
      }
    });

    test('invalid height rejects the combined size', () {
      expect(
        () => RasterSize.fromDisplaySize(widthPt: 595.28, heightPt: 0),
        throwsArgumentError,
      );
    });

    test('the documented extent cap is accepted at the boundary', () {
      final double inside = (maxRasterExtentPx + 0.4) / rasterScale;
      final double outside = (maxRasterExtentPx + 0.6) / rasterScale;
      expect(RasterSize.widthPxFor(inside), maxRasterExtentPx);
      expect(RasterSize.heightPxFor(inside), maxRasterExtentPx);
      expect(() => RasterSize.widthPxFor(outside), throwsArgumentError);
      expect(() => RasterSize.heightPxFor(outside), throwsArgumentError);
      // 14,400 pt is the PDF maximum page dimension and maps to 40,000 px.
      expect(RasterSize.widthPxFor(14400.0), maxRasterExtentPx);
      expect(() => RasterSize.widthPxFor(14401.0), throwsArgumentError);
    });

    test('huge finite page sizes fail closed instead of saturating', () {
      for (final double huge in <double>[1e20, 1e100, 1e308]) {
        expect(
          () => RasterSize.widthPxFor(huge),
          throwsArgumentError,
          reason: 'width $huge',
        );
        expect(
          () => RasterSize.heightPxFor(huge),
          throwsArgumentError,
          reason: 'height $huge',
        );
        expect(
          () => RasterSize.fromDisplaySize(widthPt: huge, heightPt: huge),
          throwsArgumentError,
          reason: 'size $huge',
        );
      }
    });

    test('value equality and hashCode', () {
      final RasterSize a = RasterSize.fromDisplaySize(
        widthPt: 10,
        heightPt: 20,
      );
      final RasterSize b = RasterSize.fromDisplaySize(
        widthPt: 10,
        heightPt: 20,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), 'RasterSize(28x56)');
    });
  });

  group('point and pixel mapping', () {
    test('pixel centres are at (i + 0.5) / scale', () {
      expect(pixelCenterToPoint(0), closeTo(0.5 / rasterScale, 1e-15));
      expect(pixelCenterToPoint(1), closeTo(1.5 / rasterScale, 1e-15));
      expect(pixelCenterToPoint(1653), closeTo(1653.5 / rasterScale, 1e-12));
    });

    test('pixel edges are at i / scale', () {
      expect(pixelEdgeToPoint(0), 0.0);
      expect(pixelEdgeToPoint(200), closeTo(72.0, 1e-12));
      expect(pixelEdgeToPoint(1654), closeTo(595.44, 1e-12));
    });

    test('every sampled pixel centre maps back to its own pixel', () {
      for (final int index in <int>[0, 1, 2, 7, 99, 200, 1653, 2338, 4095]) {
        final double point = pixelCenterToPoint(index);
        expect(pointToPixel(point), index, reason: 'pixel $index');
      }
    });

    test('A4 pixel centres round-trip within 0.01 pt', () {
      for (int i = 0; i < 1654; i++) {
        final double point = pixelCenterToPoint(i);
        final double roundTripped = pixelCenterToPoint(pointToPixel(point));
        expect(
          (roundTripped - point).abs(),
          lessThanOrEqualTo(0.01),
          reason: 'column $i',
        );
      }
      for (int i = 0; i < 2339; i++) {
        final double point = pixelCenterToPoint(i);
        final double roundTripped = pixelCenterToPoint(pointToPixel(point));
        expect(
          (roundTripped - point).abs(),
          lessThanOrEqualTo(0.01),
          reason: 'row $i',
        );
      }
    });

    test('pointToPixel uses the containing pixel and boundary goes right', () {
      expect(pointToPixel(0.0), 0);
      expect(pointToPixel(0.1 / rasterScale), 0);
      expect(pointToPixel(0.99 / rasterScale), 0);
      expect(pointToPixel((1.0 / rasterScale) + 0.0001), 1);
      expect(pointToPixel(1.4 / rasterScale), 1);
      expect(pointToPixel(1.6 / rasterScale), 1);
      expect(pointToPixel(2.1 / rasterScale), 2);
      expect(pointToPixel(pixelCenterToPoint(3)), 3);
    });

    test('negative and non-finite inputs are rejected', () {
      expect(() => pixelCenterToPoint(-1), throwsArgumentError);
      expect(() => pixelEdgeToPoint(-1), throwsArgumentError);
      expect(() => pointToPixel(-0.01), throwsArgumentError);
      expect(() => pointToPixel(double.nan), throwsArgumentError);
      expect(() => pointToPixel(double.infinity), throwsArgumentError);
    });

    test('huge finite points fail closed at the documented extent', () {
      final double inside = (maxRasterExtentPx - 0.5) / rasterScale;
      final double outside = (maxRasterExtentPx + 0.5) / rasterScale;
      expect(pointToPixel(inside), maxRasterExtentPx - 1);
      expect(() => pointToPixel(outside), throwsArgumentError);
      for (final double huge in <double>[1e20, 1e100, 1e308]) {
        expect(
          () => pointToPixel(huge),
          throwsArgumentError,
          reason: 'point $huge',
        );
      }
    });
  });

  group('PixelRect half-open semantics', () {
    test('edges, area, and contains are half-open', () {
      final PixelRect rect = PixelRect(left: 2, top: 3, width: 4, height: 5);
      expect(rect.left, 2);
      expect(rect.top, 3);
      expect(rect.right, 6);
      expect(rect.bottom, 8);
      expect(rect.area, 20);
      expect(rect.contains(2, 3), isTrue);
      expect(rect.contains(5, 7), isTrue);
      expect(rect.contains(6, 7), isFalse);
      expect(rect.contains(5, 8), isFalse);
      expect(rect.contains(1, 3), isFalse);
    });

    test('fromLTRB keeps the same half-open rectangle', () {
      expect(
        PixelRect.fromLTRB(2, 3, 6, 8),
        PixelRect(left: 2, top: 3, width: 4, height: 5),
      );
    });

    test('adjacent rectangles share an edge without overlapping', () {
      final PixelRect left = PixelRect(left: 0, top: 0, width: 2, height: 1);
      final PixelRect right = PixelRect(left: 2, top: 0, width: 2, height: 1);
      expect(left.right, right.left);
      expect(left.contains(2, 0), isFalse);
      expect(right.contains(2, 0), isTrue);
    });

    test('invalid rectangles are rejected', () {
      expect(
        () => PixelRect(left: -1, top: 0, width: 1, height: 1),
        throwsArgumentError,
      );
      expect(
        () => PixelRect(left: 0, top: -1, width: 1, height: 1),
        throwsArgumentError,
      );
      expect(
        () => PixelRect(left: 0, top: 0, width: 0, height: 1),
        throwsArgumentError,
      );
      expect(
        () => PixelRect(left: 0, top: 0, width: 1, height: 0),
        throwsArgumentError,
      );
      expect(() => PixelRect.fromLTRB(1, 0, 1, 1), throwsArgumentError);
      expect(() => PixelRect.fromLTRB(0, 1, 1, 1), throwsArgumentError);
      expect(() => PixelRect.fromLTRB(-1, 0, 1, 1), throwsArgumentError);
      expect(() => PixelRect.fromLTRB(0, -1, 1, 1), throwsArgumentError);
    });

    test('the documented field cap is accepted at the boundary', () {
      final PixelRect rect = PixelRect(
        left: maxRasterExtentPx,
        top: maxRasterExtentPx,
        width: maxRasterExtentPx,
        height: maxRasterExtentPx,
      );
      expect(rect.right, 2 * maxRasterExtentPx);
      expect(rect.bottom, 2 * maxRasterExtentPx);
      expect(rect.area, maxRasterPixels);
      expect(rect.right - rect.left, rect.width);
      expect(
        PixelRect.fromLTRB(
          maxRasterExtentPx,
          maxRasterExtentPx,
          2 * maxRasterExtentPx,
          2 * maxRasterExtentPx,
        ),
        rect,
      );
    });

    test('extreme fields are rejected without wrap', () {
      const int maxInt = 0x7FFFFFFFFFFFFFFF;
      expect(
        () =>
            PixelRect(left: maxRasterExtentPx + 1, top: 0, width: 1, height: 1),
        throwsArgumentError,
      );
      expect(
        () =>
            PixelRect(left: 0, top: maxRasterExtentPx + 1, width: 1, height: 1),
        throwsArgumentError,
      );
      expect(
        () =>
            PixelRect(left: 0, top: 0, width: maxRasterExtentPx + 1, height: 1),
        throwsArgumentError,
      );
      expect(
        () =>
            PixelRect(left: 0, top: 0, width: 1, height: maxRasterExtentPx + 1),
        throwsArgumentError,
      );
      expect(
        () => PixelRect(left: maxInt, top: 0, width: 1, height: 1),
        throwsArgumentError,
      );
      expect(
        () => PixelRect(left: 0, top: 0, width: maxInt, height: 1),
        throwsArgumentError,
      );
      expect(
        () => PixelRect(left: 0, top: 0, width: 1, height: maxInt),
        throwsArgumentError,
      );
      expect(
        () => PixelRect.fromLTRB(0, 0, maxRasterExtentPx + 1, 1),
        throwsArgumentError,
      );
      expect(
        () => PixelRect.fromLTRB(
          maxRasterExtentPx,
          0,
          (2 * maxRasterExtentPx) + 1,
          1,
        ),
        throwsArgumentError,
      );
      expect(
        () => PixelRect.fromLTRB(maxInt - 1, 0, maxInt, 1),
        throwsArgumentError,
      );
      expect(() => PixelRect.fromLTRB(0, 0, maxInt, 1), throwsArgumentError);
    });
  });

  group('GrayRaster construction and access', () {
    test('grayscale bytes are stored row-major with stride equal to width', () {
      final GrayRaster raster = _rasterFrom(3, 2, <int>[0, 1, 2, 3, 4, 5]);
      expect(raster.width, 3);
      expect(raster.height, 2);
      expect(raster.stride, 3);
      expect(raster.pixelCount, 6);
      expect(raster.luminanceAt(0, 0), 0);
      expect(raster.luminanceAt(2, 0), 2);
      expect(raster.luminanceAt(0, 1), 3);
      expect(raster.luminanceAt(2, 1), 5);
      expect(raster.toString(), 'GrayRaster(3x2)');
    });

    test('a Uint8List source of the exact length is accepted', () {
      final GrayRaster raster = GrayRaster.fromGrayBytes(
        width: 2,
        height: 2,
        bytes: Uint8List.fromList(<int>[10, 20, 30, 40]),
      );
      expect(raster.luminanceAt(1, 1), 40);
    });

    test('wrong buffer lengths are rejected', () {
      expect(
        () => GrayRaster.fromGrayBytes(
          width: 2,
          height: 2,
          bytes: <int>[0, 1, 2],
        ),
        throwsArgumentError,
      );
      expect(
        () => GrayRaster.fromGrayBytes(
          width: 2,
          height: 2,
          bytes: <int>[0, 1, 2, 3, 4],
        ),
        throwsArgumentError,
      );
    });

    test('non-positive dimensions are rejected', () {
      expect(
        () => GrayRaster.fromGrayBytes(width: 0, height: 1, bytes: <int>[]),
        throwsArgumentError,
      );
      expect(
        () => GrayRaster.fromGrayBytes(width: 1, height: 0, bytes: <int>[]),
        throwsArgumentError,
      );
    });

    test('dimensions above the documented raster extent are rejected', () {
      expect(
        () => GrayRaster.fromGrayBytes(
          width: maxRasterExtentPx + 1,
          height: 1,
          bytes: <int>[],
        ),
        throwsArgumentError,
      );
      expect(
        () => GrayRaster.fromGrayBytes(
          width: 1,
          height: maxRasterExtentPx + 1,
          bytes: <int>[],
        ),
        throwsArgumentError,
      );
    });

    test('bytes outside 0 .. 255 are rejected', () {
      expect(
        () =>
            GrayRaster.fromGrayBytes(width: 2, height: 1, bytes: <int>[0, 256]),
        throwsArgumentError,
      );
      expect(
        () =>
            GrayRaster.fromGrayBytes(width: 2, height: 1, bytes: <int>[-1, 0]),
        throwsArgumentError,
      );
    });

    test('the constructor copies the source bytes (no aliasing)', () {
      final Uint8List source = Uint8List.fromList(<int>[10, 20, 30, 40]);
      final GrayRaster raster = GrayRaster.fromGrayBytes(
        width: 2,
        height: 2,
        bytes: source,
      );
      source[0] = 200;
      source[3] = 250;
      expect(raster.luminanceAt(0, 0), 10);
      expect(raster.luminanceAt(1, 1), 40);
    });

    test('the exposed pixel view is unmodifiable', () {
      final GrayRaster raster = _rasterFrom(2, 1, <int>[1, 2]);
      final Uint8List view = raster.pixels;
      expect(view, <int>[1, 2]);
      expect(() => view[0] = 99, throwsUnsupportedError);
      expect(raster.luminanceAt(0, 0), 1);
    });

    test('pixel access is bounds-checked', () {
      final GrayRaster raster = _rasterFrom(2, 3, <int>[0, 1, 2, 3, 4, 5]);
      expect(() => raster.luminanceAt(-1, 0), throwsRangeError);
      expect(() => raster.luminanceAt(2, 0), throwsRangeError);
      expect(() => raster.luminanceAt(0, -1), throwsRangeError);
      expect(() => raster.luminanceAt(0, 3), throwsRangeError);
    });

    test('isInkAt uses a strict below-threshold comparison', () {
      final GrayRaster raster = _rasterFrom(4, 1, <int>[0, 127, 128, 255]);
      expect(raster.isInkAt(0, 0), isTrue);
      expect(raster.isInkAt(1, 0), isTrue);
      expect(raster.isInkAt(2, 0), isFalse);
      expect(raster.isInkAt(3, 0), isFalse);
      expect(raster.isInkAt(2, 0, threshold: 129), isTrue);
      expect(raster.isInkAt(0, 0, threshold: 0), isFalse);
      expect(raster.isInkAt(3, 0, threshold: 256), isTrue);
    });

    test('invalid ink thresholds and coordinates are rejected', () {
      final GrayRaster raster = _rasterFrom(1, 1, <int>[100]);
      expect(() => raster.isInkAt(0, 0, threshold: -1), throwsArgumentError);
      expect(() => raster.isInkAt(0, 0, threshold: 257), throwsArgumentError);
      expect(() => raster.isInkAt(1, 0), throwsRangeError);
    });
  });

  group('RGBA and BGRA conversion', () {
    test('primary colours use the documented Rec. 601 integer formula', () {
      final GrayRaster red = GrayRaster.fromRgba8888(
        width: 1,
        height: 1,
        bytes: <int>[255, 0, 0, 255],
      );
      final GrayRaster green = GrayRaster.fromRgba8888(
        width: 1,
        height: 1,
        bytes: <int>[0, 255, 0, 255],
      );
      final GrayRaster blue = GrayRaster.fromRgba8888(
        width: 1,
        height: 1,
        bytes: <int>[0, 0, 255, 255],
      );
      expect(red.luminanceAt(0, 0), 76);
      expect(green.luminanceAt(0, 0), 150);
      expect(blue.luminanceAt(0, 0), 29);
    });

    test('black and white round to 0 and 255', () {
      final GrayRaster black = GrayRaster.fromRgba8888(
        width: 1,
        height: 1,
        bytes: <int>[0, 0, 0, 255],
      );
      final GrayRaster white = GrayRaster.fromRgba8888(
        width: 2,
        height: 1,
        bytes: <int>[255, 255, 255, 255, 250, 250, 250, 255],
      );
      expect(black.luminanceAt(0, 0), 0);
      expect(white.luminanceAt(0, 0), 255);
      expect(white.luminanceAt(1, 0), 250);
    });

    test('BGRA conversion swaps red and blue without changing green', () {
      final GrayRaster bgra = GrayRaster.fromBgra8888(
        width: 2,
        height: 1,
        bytes: <int>[0, 0, 255, 255, 255, 0, 0, 255],
      );
      expect(bgra.luminanceAt(0, 0), 76);
      expect(bgra.luminanceAt(1, 0), 29);
    });

    test('translucent alpha is rejected instead of silently ignored', () {
      expect(
        () => GrayRaster.fromRgba8888(
          width: 1,
          height: 1,
          bytes: <int>[10, 20, 30, 254],
        ),
        throwsArgumentError,
      );
      expect(
        () => GrayRaster.fromBgra8888(
          width: 1,
          height: 1,
          bytes: <int>[30, 20, 10, 0],
        ),
        throwsArgumentError,
      );
    });

    test('wrong colour buffer lengths are rejected', () {
      expect(
        () =>
            GrayRaster.fromRgba8888(width: 1, height: 1, bytes: <int>[0, 0, 0]),
        throwsArgumentError,
      );
      expect(
        () => GrayRaster.fromBgra8888(
          width: 1,
          height: 1,
          bytes: <int>[0, 0, 0, 255, 0],
        ),
        throwsArgumentError,
      );
    });

    test('out-of-range channels in a plain list are rejected', () {
      expect(
        () => GrayRaster.fromRgba8888(
          width: 1,
          height: 1,
          bytes: <int>[300, 0, 0, 255],
        ),
        throwsArgumentError,
      );
      expect(
        () => GrayRaster.fromBgra8888(
          width: 1,
          height: 1,
          bytes: <int>[0, -1, 0, 255],
        ),
        throwsArgumentError,
      );
    });

    test('colour conversion does not alias the source buffer', () {
      final Uint8List source = Uint8List.fromList(<int>[255, 0, 0, 255]);
      final GrayRaster raster = GrayRaster.fromRgba8888(
        width: 1,
        height: 1,
        bytes: source,
      );
      source[0] = 0;
      expect(raster.luminanceAt(0, 0), 76);
    });
  });

  group('IntegralImage', () {
    test('known 3 x 3 sums match hand calculation', () {
      final GrayRaster raster = _rasterFrom(3, 3, <int>[
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
      ]);
      final IntegralImage integral = IntegralImage.fromGrayRaster(raster);
      expect(integral.width, 3);
      expect(integral.height, 3);
      expect(integral.total, 45);
      expect(integral.sum(PixelRect.fromLTRB(0, 0, 3, 3)), 45);
      expect(integral.sum(PixelRect.fromLTRB(1, 1, 2, 2)), 5);
      expect(integral.sum(PixelRect.fromLTRB(0, 0, 2, 2)), 12);
      expect(integral.sum(PixelRect.fromLTRB(1, 0, 3, 1)), 5);
      expect(integral.sum(PixelRect.fromLTRB(0, 0, 1, 3)), 12);
      expect(integral.sum(PixelRect.fromLTRB(2, 2, 3, 3)), 9);
    });

    test('rectangle sums equal naive sums for every rectangle', () {
      final GrayRaster raster = _syntheticRaster(17, 13);
      final IntegralImage integral = IntegralImage.fromGrayRaster(raster);
      for (int top = 0; top < raster.height; top++) {
        for (int left = 0; left < raster.width; left++) {
          for (int height = 1; top + height <= raster.height; height++) {
            for (int width = 1; left + width <= raster.width; width++) {
              final PixelRect rect = PixelRect(
                left: left,
                top: top,
                width: width,
                height: height,
              );
              expect(
                integral.sum(rect),
                _naiveLuminanceSum(raster, rect),
                reason: 'rect $rect',
              );
            }
          }
        }
      }
    });

    test('ink-mask integral counts pixels below the threshold', () {
      final GrayRaster raster = _rasterFrom(4, 1, <int>[0, 127, 128, 255]);
      final IntegralImage integral = IntegralImage.fromInkMask(raster);
      expect(integral.total, 2);
      expect(integral.sum(PixelRect.fromLTRB(0, 0, 1, 1)), 1);
      expect(integral.sum(PixelRect.fromLTRB(1, 0, 3, 1)), 1);
      expect(integral.sum(PixelRect.fromLTRB(2, 0, 4, 1)), 0);
      expect(IntegralImage.fromInkMask(raster, threshold: 129).total, 3);
      expect(IntegralImage.fromInkMask(raster, threshold: 0).total, 0);
      expect(IntegralImage.fromInkMask(raster, threshold: 256).total, 4);
    });

    test('ink-mask rectangle counts equal naive counts', () {
      final GrayRaster raster = _syntheticRaster(9, 7, seed: 0xBAD5EED);
      const int threshold = 96;
      final IntegralImage integral = IntegralImage.fromInkMask(
        raster,
        threshold: threshold,
      );
      for (int top = 0; top < raster.height; top += 2) {
        for (int left = 0; left < raster.width; left += 2) {
          final PixelRect rect = PixelRect(
            left: left,
            top: top,
            width: raster.width - left,
            height: raster.height - top,
          );
          expect(
            integral.sum(rect),
            _naiveInkCount(raster, rect, threshold),
            reason: 'rect $rect',
          );
        }
      }
    });

    test('rectangles are bounds-checked, not clamped', () {
      final GrayRaster raster = _syntheticRaster(5, 4);
      final IntegralImage integral = IntegralImage.fromGrayRaster(raster);
      expect(
        () => integral.sum(PixelRect.fromLTRB(0, 0, 6, 1)),
        throwsRangeError,
      );
      expect(
        () => integral.sum(PixelRect.fromLTRB(0, 0, 1, 5)),
        throwsRangeError,
      );
      expect(
        () => integral.sum(PixelRect(left: 5, top: 0, width: 1, height: 1)),
        throwsRangeError,
      );
      expect(
        () => integral.sum(PixelRect(left: 0, top: 4, width: 1, height: 1)),
        throwsRangeError,
      );
    });

    test('invalid ink thresholds are rejected', () {
      final GrayRaster raster = _syntheticRaster(2, 2);
      expect(
        () => IntegralImage.fromInkMask(raster, threshold: -1),
        throwsArgumentError,
      );
      expect(
        () => IntegralImage.fromInkMask(raster, threshold: 257),
        throwsArgumentError,
      );
    });
  });

  group('InkCoverage', () {
    test('validates its counts', () {
      expect(
        () => InkCoverage(inkPixels: 0, totalPixels: 0),
        throwsArgumentError,
      );
      expect(
        () => InkCoverage(inkPixels: -1, totalPixels: 4),
        throwsArgumentError,
      );
      expect(
        () => InkCoverage(inkPixels: 5, totalPixels: 4),
        throwsArgumentError,
      );
      expect(InkCoverage(inkPixels: 2, totalPixels: 4).fraction, 0.5);
    });

    test('all-white, all-black, and half-covered rasters', () {
      final RasterAnalysis white = _rasterFrom(
        4,
        4,
        _filledBytes(4, 4, 255),
      ).analyze();
      final RasterAnalysis black = _rasterFrom(
        4,
        4,
        _filledBytes(4, 4, 0),
      ).analyze();
      final RasterAnalysis half = _rasterFrom(4, 4, <int>[
        0, 0, 255, 255, //
        0, 0, 255, 255, //
        0, 0, 255, 255, //
        0, 0, 255, 255, //
      ]).analyze();

      expect(white.inkCoverage(white.raster.bounds).inkPixels, 0);
      expect(white.inkCoverage(white.raster.bounds).fraction, 0.0);
      expect(black.inkCoverage(black.raster.bounds).inkPixels, 16);
      expect(black.inkCoverage(black.raster.bounds).fraction, 1.0);
      final InkCoverage halfCoverage = half.inkCoverage(half.raster.bounds);
      expect(halfCoverage.inkPixels, 8);
      expect(halfCoverage.totalPixels, 16);
      expect(halfCoverage.fraction, 0.5);
    });

    test('the threshold is strict at the default boundary', () {
      final GrayRaster raster = _rasterFrom(3, 1, <int>[0, 127, 128]);
      final RasterAnalysis analysis = raster.analyze();
      expect(analysis.inkThreshold, 128);
      expect(analysis.inkCoverage(raster.bounds).inkPixels, 2);
      expect(analysis.inkCoverage(PixelRect.fromLTRB(1, 0, 3, 1)).inkPixels, 1);
      expect(
        raster.analyze(inkThreshold: 127).inkCoverage(raster.bounds).inkPixels,
        1,
      );
      expect(
        raster.analyze(inkThreshold: 129).inkCoverage(raster.bounds).inkPixels,
        3,
      );
    });

    test('exceedsPercent uses exact integer comparison', () {
      expect(
        InkCoverage(inkPixels: 12, totalPixels: 100).exceedsPercent(11),
        isTrue,
      );
      expect(
        InkCoverage(inkPixels: 12, totalPixels: 100).exceedsPercent(12),
        isFalse,
      );
      expect(
        InkCoverage(inkPixels: 12, totalPixels: 100).exceedsPercent(13),
        isFalse,
      );
      expect(
        () => InkCoverage(inkPixels: 0, totalPixels: 1).exceedsPercent(-1),
        throwsArgumentError,
      );
      expect(
        () => InkCoverage(inkPixels: 0, totalPixels: 1).exceedsPercent(101),
        throwsArgumentError,
      );
    });

    test('huge counts are compared without signed 64-bit overflow', () {
      const int total = 1 << 60;
      final int tenth = total ~/ 10;
      // 10 % ink must not exceed 25 %; the old int expression overflowed
      // signed 64-bit on both products and returned true.
      expect(
        InkCoverage(inkPixels: tenth, totalPixels: total).exceedsPercent(25),
        isFalse,
      );
      expect(
        InkCoverage(inkPixels: tenth, totalPixels: total).exceedsPercent(9),
        isTrue,
      );
    });

    test('huge zero, full, and exact-equality boundaries are exact', () {
      const int total = 1 << 60;
      const int quarter = 1 << 58;
      expect(
        InkCoverage(inkPixels: 0, totalPixels: total).exceedsPercent(0),
        isFalse,
      );
      expect(
        InkCoverage(inkPixels: 0, totalPixels: total).exceedsPercent(100),
        isFalse,
      );
      expect(
        InkCoverage(inkPixels: 1, totalPixels: total).exceedsPercent(0),
        isTrue,
      );
      expect(
        InkCoverage(inkPixels: 1, totalPixels: total).exceedsPercent(1),
        isFalse,
      );
      expect(
        InkCoverage(inkPixels: total, totalPixels: total).exceedsPercent(0),
        isTrue,
      );
      expect(
        InkCoverage(inkPixels: total, totalPixels: total).exceedsPercent(100),
        isFalse,
      );
      expect(
        InkCoverage(inkPixels: quarter, totalPixels: total).exceedsPercent(25),
        isFalse,
      );
      expect(
        InkCoverage(
          inkPixels: quarter + 1,
          totalPixels: total,
        ).exceedsPercent(25),
        isTrue,
      );
      expect(
        InkCoverage(
          inkPixels: quarter - 1,
          totalPixels: total,
        ).exceedsPercent(25),
        isFalse,
      );
    });

    test('comparisons stay exact above 2^63 on both sides', () {
      const int total = 1 << 62;
      const int ink = (1 << 61) + 12345;
      // ink * 100 and total * 37 are both far above signed 64-bit.
      expect(
        InkCoverage(inkPixels: ink, totalPixels: total).exceedsPercent(37),
        isTrue,
      );
      expect(
        InkCoverage(inkPixels: ink, totalPixels: total).exceedsPercent(51),
        isFalse,
      );
    });

    test('luminance sums and coverage agree with naive results', () {
      final GrayRaster raster = _syntheticRaster(11, 8, seed: 0x1234);
      final RasterAnalysis analysis = raster.analyze();
      for (int top = 0; top < raster.height; top += 3) {
        for (int left = 0; left < raster.width; left += 4) {
          final PixelRect rect = PixelRect(
            left: left,
            top: top,
            width: raster.width - left,
            height: raster.height - top,
          );
          expect(
            analysis.luminanceSum(rect),
            _naiveLuminanceSum(raster, rect),
            reason: 'luminance $rect',
          );
          expect(
            analysis.inkCoverage(rect).inkPixels,
            _naiveInkCount(raster, rect, defaultInkThreshold),
            reason: 'ink $rect',
          );
        }
      }
    });

    test('analysis is deterministic and does not mutate the raster', () {
      final GrayRaster raster = _syntheticRaster(6, 5);
      final List<int> before = raster.pixels.toList();
      final RasterAnalysis first = raster.analyze();
      final RasterAnalysis second = raster.analyze();
      final PixelRect rect = PixelRect.fromLTRB(1, 1, 5, 4);
      expect(first.luminanceSum(rect), second.luminanceSum(rect));
      expect(first.inkCoverage(rect), second.inkCoverage(rect));
      expect(raster.pixels.toList(), before);
    });

    test('analysis rejects an invalid threshold', () {
      final GrayRaster raster = _syntheticRaster(2, 2);
      expect(() => raster.analyze(inkThreshold: 257), throwsArgumentError);
    });
  });
}
