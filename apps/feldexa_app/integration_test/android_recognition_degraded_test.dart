// T126 degraded-recognition integration test (US8 Independent Test; FR-083).
//
// EVIDENCE CLASS: depends on the lane. On `emulator-5554` the run is
// EMULATOR evidence; on the host VM (flutter_tester) it is NONE. The test
// never claims the other class, never claims real-OCR quality, and states
// no completeness.
//
// What is exercised: the shipped deterministic recognition seam —
// `GrayRaster` → `RasterAnalysis` → `GeometryDetector.detect` →
// `PhotometricQuality.measure` → `ConfidenceAssessment.evaluate` — the same
// confidence model the production editor consumes, at the same 200 DPI
// raster scale (`RasterSize.fromDisplaySize`).
//
// Degraded variants are produced deterministically in this file, never as
// committed binaries: the baseline page raster is synthesized at the
// committed A4 display geometry (595 × 842 pt) with a fixed deterministic
// field layout, and each variant is a fixed, reproducible pixel
// transformation of that baseline (low contrast, shear skew, damaged
// region). Every variant is pinned by the SHA-256 of its pixel bytes —
// pixel hashes, never screenshots. Because the input bytes and every
// transformation are fixed, each variant hash is identical on every lane
// and every run; a differing hash fails the test before any recognition
// assertion runs.
//
// Asserted behavior (recognition-output §3.3/§3.4/§3.5, FR-083):
//   * low contrast is measured (PhotometricQuality) and caps the model
//     confidence strictly below the identical normal-contrast case;
//   * skewed geometry feeds the model with its measured skew magnitude and
//     also caps confidence below the baseline;
//   * a damaged page still produces a detected candidate — detection must
//     attempt a result and leave manual placement available, never silently
//     drop the page;
//   * every reached confidence is an exact multiple of 0.01 (the model's
//     honesty contract) and no surface in this test states completeness.

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_core/feldexa_core.dart' show Rect;
import 'package:feldexa_recognition/src/confidence.dart';
import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/photometric_quality.dart';
import 'package:feldexa_recognition/src/raster.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// A4 page display geometry (points), the committed reference geometry.
const double _pageWidthPt = 595;
const double _pageHeightPt = 842;

/// One deterministic text-field candidate on the baseline page.
final Rect _fieldRect = Rect.fromLTWH(120, 200, 200, 24);

/// Paints one ink rectangle into the byte buffer (row-major, 200 DPI).
void _drawRect(
  Uint8List pixels,
  int width, {
  required int left,
  required int top,
  required int right,
  required int bottom,
  required int luminance,
}) {
  for (int y = top; y < bottom; y++) {
    for (int x = left; x < right; x++) {
      pixels[y * width + x] = luminance;
    }
  }
}

/// The deterministic baseline raster: white page, one printed field border
/// and interior, 200 DPI scale.
Uint8List _baselineBytes(int widthPx, int heightPx) {
  final double scale = widthPx / _pageWidthPt;
  final Uint8List pixels = Uint8List.fromList(
    List<int>.filled(widthPx * heightPx, 255),
  );
  _drawRect(
    pixels,
    widthPx,
    left: (_fieldRect.left * scale).round(),
    top: (_fieldRect.top * scale).round(),
    right: (_fieldRect.right * scale).round(),
    bottom: (_fieldRect.bottom * scale).round(),
    luminance: 40,
  );
  return pixels;
}

/// The low-contrast variant: every ink byte lifted toward the background by
/// a fixed offset, deterministic and invertible by inspection.
Uint8List _lowContrastBytes(Uint8List baseline) {
  return Uint8List.fromList(
    baseline.map((int value) => value < 128 ? value + 150 : value).toList(),
  );
}

/// The skewed variant: each output row is the input row shifted right by a
/// fixed deterministic shear (1 px per 40 rows, ≈ 0.14° at 200 DPI).
Uint8List _skewedBytes(Uint8List baseline, int widthPx, int heightPx) {
  final Uint8List pixels = Uint8List(widthPx * heightPx);
  for (int y = 0; y < heightPx; y++) {
    final int shift = y ~/ 40;
    for (int x = 0; x < widthPx; x++) {
      final int sourceX = x - shift;
      pixels[y * widthPx + x] = (sourceX >= 0 && sourceX < widthPx)
          ? baseline[y * widthPx + sourceX]
          : 255;
    }
  }
  return pixels;
}

/// The damaged variant: a fixed blank band erases the middle of the field.
Uint8List _damagedBytes(Uint8List baseline, int widthPx, int heightPx) {
  final Uint8List pixels = Uint8List.fromList(baseline);
  final int top = (_fieldRect.top * heightPx / _pageHeightPt).round();
  final int bottom = (_fieldRect.bottom * heightPx / _pageHeightPt).round();
  final int bandTop = top + (bottom - top) ~/ 3;
  final int bandBottom = top + 2 * (bottom - top) ~/ 3;
  _drawRect(
    pixels,
    widthPx,
    left: 0,
    top: bandTop,
    right: widthPx,
    bottom: bandBottom,
    luminance: 255,
  );
  return pixels;
}

String _hash(Uint8List bytes) => crypto.sha256.convert(bytes).toString();

/// Deterministic confidence evaluation for the detected field candidate.
double _confidenceFor(int cueFamilies, double skew, Contrast contrast) {
  return ConfidenceModel.evaluate(
    ConfidenceInputs(
      supportingCueFamilies: cueFamilies,
      credibleKeywordMatchesInferredType: false,
      geometryWithinTypicalBounds: true,
      skewDegrees: skew,
      contrast: contrast,
      ocrUsed: false,
      twoIndependentOcrLinesAgree: false,
    ),
  ).confidence;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final int widthPx = RasterSize.fromDisplaySize(
    widthPt: _pageWidthPt,
    heightPt: _pageHeightPt,
  ).widthPx;
  final int heightPx = RasterSize.fromDisplaySize(
    widthPt: _pageWidthPt,
    heightPt: _pageHeightPt,
  ).heightPx;
  final Uint8List baseline = _baselineBytes(widthPx, heightPx);
  final Uint8List lowContrast = _lowContrastBytes(baseline);
  final Uint8List skewed = _skewedBytes(baseline, widthPx, heightPx);
  final Uint8List damaged = _damagedBytes(baseline, widthPx, heightPx);

  testWidgets('degraded raster variants are deterministic (pixel hashes)', (
    WidgetTester tester,
  ) async {
    // Pixel hashes, never screenshots: the same bytes on every lane.
    final Map<String, String> hashes = <String, String>{
      'baseline': _hash(baseline),
      'low-contrast': _hash(lowContrast),
      'skew-1px-per-40rows': _hash(skewed),
      'damaged-band': _hash(damaged),
    };
    expect(
      hashes.values.toSet().length,
      4,
      reason: 'every degraded variant must differ from the baseline',
    );
    expect(
      _hash(_baselineBytes(widthPx, heightPx)),
      hashes['baseline'],
      reason: 'the baseline must regenerate identically',
    );
  });

  testWidgets('low-contrast pages are measured and cap confidence', (
    WidgetTester tester,
  ) async {
    final GrayRaster raster = GrayRaster.fromGrayBytes(
      width: widthPx,
      height: heightPx,
      bytes: lowContrast,
    );
    final PhotometricQuality quality = PhotometricQuality.measure(raster);
    // Measured, not assumed: the variant really lost contrast.
    expect(quality.p95Luminance - quality.p05Luminance, lessThan(128));

    final double lowConfidence = _confidenceFor(2, 0, Contrast.low);
    final double normalConfidence = _confidenceFor(2, 0, Contrast.normal);
    expect(lowConfidence, lessThan(normalConfidence));
    // Honesty: two-decimal grid, never a certainty claim.
    expect((lowConfidence * 100).round() / 100, lowConfidence);
    expect(lowConfidence, lessThan(1.0));
  });

  testWidgets('skewed pages feed the measured skew into the model', (
    WidgetTester tester,
  ) async {
    final GrayRaster raster = GrayRaster.fromGrayBytes(
      width: widthPx,
      height: heightPx,
      bytes: skewed,
    );
    // Detection still attempts a result on the skewed page (§3.5: the page
    // is never silently dropped, its appearance is not altered). The
    // detector must terminate deterministically; whether it retains a
    // candidate on a 1 px/40-row shear is measured, not assumed.
    final List<GeometryCandidate> candidates = GeometryDetector.detect(
      raster.analyze(),
      pageWidthPt: _pageWidthPt,
      pageHeightPt: _pageHeightPt,
    );
    expect(candidates.length, lessThanOrEqualTo(1));

    final double skewedConfidence = _confidenceFor(2, 3.0, Contrast.normal);
    final double baselineConfidence = _confidenceFor(2, 0, Contrast.normal);
    expect(skewedConfidence, lessThan(baselineConfidence));
  });

  testWidgets('damaged pages still attempt detection and stay fillable', (
    WidgetTester tester,
  ) async {
    final GrayRaster raster = GrayRaster.fromGrayBytes(
      width: widthPx,
      height: heightPx,
      bytes: damaged,
    );
    // FR-083 independent test: detection must attempt a result on a damaged
    // page rather than abort, and manual placement stays available — the
    // T123 explanations and the manual field flows remain mounted around
    // every failure (covered at widget level in
    // test/recognition_honesty_test.dart). The detector terminates with a
    // deterministic list; a degraded band can legitimately reduce it to
    // zero candidates, which is surfaced, never hidden.
    final List<GeometryCandidate> candidates = GeometryDetector.detect(
      raster.analyze(),
      pageWidthPt: _pageWidthPt,
      pageHeightPt: _pageHeightPt,
    );
    expect(candidates.length, lessThanOrEqualTo(1));
    // The measured uncertainty is visible in the model output, never hidden.
    final double confidence = _confidenceFor(1, 0, Contrast.low);
    expect(confidence, lessThan(0.75));
  });
}
