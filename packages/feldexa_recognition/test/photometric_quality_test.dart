// T264 host-VM tests for the photometric quality measurement.
// ignore_for_file: depend_on_referenced_packages

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:feldexa_recognition/src/photometric_quality.dart';
import 'package:feldexa_recognition/src/raster.dart';
import 'package:flutter_test/flutter_test.dart';

GrayRaster _raster(int width, int height, int value) {
  final Uint8List bytes = Uint8List(width * height)
    ..fillRange(0, width * height, value);
  return GrayRaster.fromGrayBytes(width: width, height: height, bytes: bytes);
}

void main() {
  test('a blank page measures a degenerate dynamic range', () {
    final PhotometricQuality quality = PhotometricQuality.measure(
      _raster(20, 10, 255),
    );

    expect(quality.pixelCount, 200);
    expect(quality.meanLuminance, 255);
    expect(quality.standardDeviation, 0);
    expect(quality.inkDensity, 0);
    expect(quality.dynamicRange, 0);
    expect(quality.isBelowDynamicRange(96), isTrue);
  });

  test('a half-dark page measures ink density and percentiles exactly', () {
    final Uint8List bytes = Uint8List(100)
      ..fillRange(0, 50, 0)
      ..fillRange(50, 100, 255);
    final PhotometricQuality quality = PhotometricQuality.measure(
      GrayRaster.fromGrayBytes(width: 10, height: 10, bytes: bytes),
    );

    expect(quality.meanLuminance, closeTo(127.5, 1e-9));
    expect(quality.standardDeviation, closeTo(127.5, 1e-9));
    expect(quality.inkDensity, closeTo(0.5, 1e-12));
    expect(quality.p05Luminance, 0);
    expect(quality.p95Luminance, 255);
    expect(quality.dynamicRange, 255);
    expect(quality.isBelowDynamicRange(96), isFalse);
  });

  test('the report map is stable and contains no geometry', () {
    final PhotometricQuality quality = PhotometricQuality.measure(
      _raster(4, 4, 128),
    );
    final Map<String, Object?> json = quality.toJson();
    expect(json.keys, <String>[
      'pixelCount',
      'meanLuminance',
      'standardDeviation',
      'inkDensity',
      'p05Luminance',
      'p95Luminance',
      'dynamicRange',
    ]);
    expect(json['pixelCount'], 16);
  });
}
