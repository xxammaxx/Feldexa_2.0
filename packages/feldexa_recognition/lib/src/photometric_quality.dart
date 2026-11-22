// Photometric quality measurement of the unmodified page raster (T264).
//
// Normative sources:
//  * `specs/001-scanned-form-workflow/spec.md` FR-011, FR-013, SC-002;
//  * `specs/001-scanned-form-workflow/contracts/recognition-output.md`
//    sections 1 (`timings`, diagnostics) and 2.1 (ink measurement).
//
// Scope. This library measures the *photometric original* of one page raster in
// a single deterministic pass over its luminance histogram. It deliberately
// does so before any threshold, binarisation, or variant transform, so a
// low-contrast page is characterised from the evidence that a binarised copy
// would already have destroyed. It detects no field, substitutes no detector,
// estimates no skew or blur, and has no I/O.
//
// It is a measurement primitive for the evaluation baseline and for the
// (not yet implemented) adaptive policy, whose frozen thresholds live in
// `tools/evaluation/adaptive-policy.v1.json`. It carries no decision: the
// caller compares against a pre-declared threshold.
//
// Statistics. All values are exact for the measured raster:
//  * `meanLuminance` and `standardDeviation` are the population moments over the
//    full `width * height` histogram;
//  * `inkDensity` is the fraction of pixels below the documented 128 ink
//    threshold (`defaultInkThreshold`);
//  * `p05Luminance` and `p95Luminance` are nearest-rank percentiles: the
//    smallest luminance whose cumulative pixel count reaches `ceil(0.05 * n)`
//    and `ceil(0.95 * n)` respectively.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'raster.dart';

/// Photometric measurements of one unmodified page raster.
final class PhotometricQuality {
  PhotometricQuality._({
    required this.pixelCount,
    required this.meanLuminance,
    required this.standardDeviation,
    required this.inkDensity,
    required this.p05Luminance,
    required this.p95Luminance,
  });

  /// Measures [raster] in one deterministic pass over its luminance bytes.
  factory PhotometricQuality.measure(GrayRaster raster) {
    final Uint8List pixels = raster.pixels;
    final List<int> histogram = List<int>.filled(256, 0);
    int total = 0;
    for (int index = 0; index < pixels.length; index++) {
      final int value = pixels[index];
      histogram[value]++;
      total += value;
    }
    final int count = pixels.length;
    final double mean = total / count;
    double squares = 0;
    for (int value = 0; value < 256; value++) {
      final int bin = histogram[value];
      if (bin == 0) {
        continue;
      }
      final double delta = value - mean;
      squares += bin * delta * delta;
    }
    final double deviation = math.sqrt(squares / count);
    int ink = 0;
    for (int value = 0; value < defaultInkThreshold; value++) {
      ink += histogram[value];
    }
    return PhotometricQuality._(
      pixelCount: count,
      meanLuminance: mean,
      standardDeviation: deviation,
      inkDensity: ink / count,
      p05Luminance: _nearestRank(histogram, count, 0.05),
      p95Luminance: _nearestRank(histogram, count, 0.95),
    );
  }

  static int _nearestRank(List<int> histogram, int count, double quantile) {
    final int target = math.max(1, (count * quantile).ceil());
    int cumulative = 0;
    for (int value = 0; value < histogram.length; value++) {
      cumulative += histogram[value];
      if (cumulative >= target) {
        return value;
      }
    }
    return 255;
  }

  /// Number of measured pixels.
  final int pixelCount;

  /// Arithmetic mean luminance in `0 ... 255`.
  final double meanLuminance;

  /// Population standard deviation of luminance.
  final double standardDeviation;

  /// Fraction of pixels below the ink threshold.
  final double inkDensity;

  /// 5th percentile luminance (nearest rank).
  final int p05Luminance;

  /// 95th percentile luminance (nearest rank).
  final int p95Luminance;

  /// The luminance span between the 5th and 95th percentile.
  int get dynamicRange => p95Luminance - p05Luminance;

  /// Whether the photometric original is below [minDynamicRange].
  ///
  /// This is a comparison, not a decision: the frozen adaptive policy owns the
  /// threshold and the hysteresis.
  bool isBelowDynamicRange(int minDynamicRange) =>
      dynamicRange < minDynamicRange;

  /// A report-ready map.
  Map<String, Object?> toJson() => <String, Object?>{
    'pixelCount': pixelCount,
    'meanLuminance': meanLuminance,
    'standardDeviation': standardDeviation,
    'inkDensity': inkDensity,
    'p05Luminance': p05Luminance,
    'p95Luminance': p95Luminance,
    'dynamicRange': dynamicRange,
  };

  @override
  String toString() =>
      'PhotometricQuality(dynamicRange: $dynamicRange, '
      'inkDensity: $inkDensity)';
}
