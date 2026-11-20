// T070 seeded PageGeometry round-trip property tests.
//
// Host-VM tests (evidence class NONE). They pin the property invariants in
// `specs/001-scanned-form-workflow/contracts/coordinates-and-geometry.md`
// sections 6.2 (round-trip), 6.3 (zoom invariance), 6.4 (mixed pages),
// 6.7 (export formula), 6.8 (device independence), and a small 6.1
// (validation) sanity sample:
//   * a deterministic 32-bit LCG generates 1,000 display rects per
//     geometry/rotation, including full-page, 6x6, 1x1, thin, tall,
//     fractional-edge, and negative-coordinate rectangles;
//   * A4 portrait, A4 landscape via /Rotate 90, A5, CropBox offsets on every
//     side, a CropBox clipped by the MediaBox, and all four rotations are
//     covered;
//   * display <-> PDF mapping round-trips within 1e-6 pt and is independent
//     of view scale, pan, and device viewport width.
//
// These tests complement, and do not duplicate, the normative tables and the
// exhaustive section 6.1 cases in `geometry_test.dart`.

import 'dart:math' as math;

import 'package:feldexa_core/feldexa_core.dart';
import 'package:flutter_test/flutter_test.dart';

const double _tolerancePt = 1e-6;
const int _generatedRectsPerCombo = 1000;
const int _zoomSampleCount = 110;
const int _cropSampleCount = 250;

void main() {
  final List<_Combo> combos = _buildCombos();

  group('§6.2 round-trip', () {
    test('display → PDF → display for every generated rect', () {
      for (final _Combo combo in combos) {
        int outsideDisplayBox = 0;
        for (final Rect rect in combo.samples) {
          if (!_rectInside(combo.geometry.displayBox, rect, _tolerancePt)) {
            outsideDisplayBox++;
          }
          final Rect pdf = combo.geometry.displayRectToPdf(rect);
          _expectRectClose(
            combo.geometry.pdfRectToDisplay(pdf),
            rect,
            '${combo.label}: display → PDF $pdf → display',
          );
        }
        expect(
          outsideDisplayBox,
          greaterThan(0),
          reason: '${combo.label} must include rects outside the display box',
        );
      }
    });

    test('PDF → display → PDF for rects inside the effective crop box', () {
      for (final _Combo combo in combos) {
        int checkedDisplayRects = 0;
        for (final Rect rect in combo.samples) {
          if (!_rectInside(combo.geometry.displayBox, rect, _tolerancePt)) {
            continue;
          }
          final Rect pdf = combo.geometry.displayRectToPdf(rect);
          _expectRectInside(
            combo.geometry.cropBox,
            pdf,
            '${combo.label}: display rect $rect must map inside the CropBox',
          );
          _expectRectClose(
            combo.geometry.displayRectToPdf(
              combo.geometry.pdfRectToDisplay(pdf),
            ),
            pdf,
            '${combo.label}: display → PDF → display → PDF for $rect',
          );
          checkedDisplayRects++;
        }
        expect(
          checkedDisplayRects,
          greaterThan(400),
          reason:
              '${combo.label} must exercise enough display rects inside the box',
        );

        for (final Rect pdf in combo.cropSamples) {
          _expectRectInside(
            combo.geometry.cropBox,
            pdf,
            '${combo.label}: analytic crop sample $pdf',
          );
          final Rect display = combo.geometry.pdfRectToDisplay(pdf);
          _expectRectInside(
            combo.geometry.displayBox,
            display,
            '${combo.label}: crop sample $pdf must map inside the display box',
          );
          _expectRectClose(
            combo.geometry.displayRectToPdf(display),
            pdf,
            '${combo.label}: PDF → display → PDF for $pdf',
          );
        }
      }
    });
  });

  group('§6.3 zoom invariance', () {
    test('the PDF mapping is identical at scales 0.5, 1, 1.75, 3, 8', () {
      const List<double> scales = <double>[0.5, 1, 1.75, 3, 8];
      const List<_Pan> pans = <_Pan>[
        _Pan(13.5, -7.25),
        _Pan(-42.125, 89.5),
        _Pan(0.75, 0.5),
      ];
      for (final _Combo combo in combos) {
        for (final Rect model in combo.samples.take(_zoomSampleCount)) {
          final Rect expected = combo.geometry.displayRectToPdf(model);
          for (final double scale in scales) {
            for (final _Pan pan in pans) {
              final Rect view = Rect.fromLTWH(
                pan.dx + scale * model.left,
                pan.dy + scale * model.top,
                scale * model.width,
                scale * model.height,
              );
              final Rect recovered = Rect.fromLTWH(
                (view.left - pan.dx) / scale,
                (view.top - pan.dy) / scale,
                view.width / scale,
                view.height / scale,
              );
              final String label =
                  '${combo.label}, scale $scale, pan (${pan.dx}, ${pan.dy})';
              _expectRectClose(recovered, model, '$label: view → model');
              _expectRectClose(
                combo.geometry.displayRectToPdf(recovered),
                expected,
                '$label: PDF mapping must not depend on view scale',
              );
            }
          }
        }
      }
    });
  });

  group('§6.7 export formula', () {
    test('displayRectToPdf matches the explicit per-rotation formula', () {
      int fullyOffsetCombos = 0;
      for (final _Combo combo in combos) {
        final PageGeometry geometry = combo.geometry;
        final Rect crop = geometry.cropBox;
        final Rect media = geometry.mediaBox;
        if (crop.left != media.left &&
            crop.top != media.top &&
            crop.right != media.right &&
            crop.bottom != media.bottom) {
          fullyOffsetCombos++;
        }
        for (final Rect rect in combo.samples) {
          _expectRectClose(
            geometry.displayRectToPdf(rect),
            _contractExportRect(geometry, rect),
            '${combo.label}: §6.7 formula for $rect',
          );
        }
      }
      expect(
        fullyOffsetCombos,
        greaterThanOrEqualTo(4),
        reason:
            'the formula must be covered with non-zero CropBox offsets on '
            'every side',
      );
    });
  });

  group('§6.4 mixed pages', () {
    test(
      'one display rect maps distinctly per page without cross-page state',
      () {
        final Rect field = Rect.fromLTWH(100, 50, 120, 20);
        final PageGeometry a4Portrait = PageGeometry(
          mediaBox: Rect.fromLTWH(0, 0, 595, 842),
        );
        // A4 landscape is the same MediaBox shown through /Rotate 90.
        final PageGeometry a4Landscape = PageGeometry(
          mediaBox: Rect.fromLTWH(0, 0, 595, 842),
          rotation: 90,
        );
        final PageGeometry a5 = PageGeometry(
          mediaBox: Rect.fromLTWH(0, 0, 420, 595),
        );

        expect(a4Portrait.displaySize, Size(595, 842));
        expect(a4Landscape.displaySize, Size(842, 595));
        expect(a5.displaySize, Size(420, 595));

        final Rect portraitPdf = a4Portrait.displayRectToPdf(field);
        final Rect landscapePdf = a4Landscape.displayRectToPdf(field);
        final Rect a5Pdf = a5.displayRectToPdf(field);
        expect(portraitPdf, Rect.fromLTWH(100, 772, 120, 20));
        expect(landscapePdf, Rect.fromLTWH(50, 100, 20, 120));
        expect(a5Pdf, Rect.fromLTWH(100, 525, 120, 20));
        expect(
          <Rect>{portraitPdf, landscapePdf, a5Pdf}.length,
          3,
          reason: 'the three pages must produce distinct PDF rects',
        );

        // Map on another page in between, then return to the first page: the
        // result must be unchanged because each page owns its geometry.
        a5.displayRectToPdf(Rect.fromLTWH(5.25, 7.5, 6, 6));
        a4Landscape.displayRectToPdf(field);
        _expectRectClose(
          a4Portrait.displayRectToPdf(field),
          portraitPdf,
          'A4 portrait must not retain state from A5 or A4 landscape',
        );
        expect(a4Portrait.displaySize, Size(595, 842));
        expect(a4Landscape.displaySize, Size(842, 595));
        expect(a5.displaySize, Size(420, 595));
      },
    );
  });

  group('§6.8 device independence', () {
    test('360, 800, and 1440 dp viewports reproduce the same model rects', () {
      final PageGeometry page = PageGeometry(
        mediaBox: Rect.fromLTWH(0, 0, 595, 842),
        cropBox: Rect.fromLTWH(10, 20, 500, 700),
        rotation: 270,
      );
      final Size originalSize = page.displaySize;
      final Rect originalCropBox = page.cropBox;
      final Rect originalMediaBox = page.mediaBox;
      final List<Rect> models = _displaySamples(
        page,
        0x0D5E1CE,
      ).skip(10).take(50).toList();
      final List<Rect> modelPdf = <Rect>[
        for (final Rect model in models) page.displayRectToPdf(model),
      ];

      for (final double viewportWidth in <double>[360, 800, 1440]) {
        final double fitWidthScale = viewportWidth / page.displaySize.width;
        final double viewportHeight =
            viewportWidth * page.displaySize.height / page.displaySize.width;
        final _Pan pan = _Pan(-viewportWidth * 0.13, viewportHeight * 0.07);
        for (int i = 0; i < models.length; i++) {
          final Rect model = models[i];
          final double scale = fitWidthScale * (i.isEven ? 1.0 : 2.25);
          final Rect view = Rect.fromLTWH(
            pan.dx + scale * model.left,
            pan.dy + scale * model.top,
            scale * model.width,
            scale * model.height,
          );
          final Rect recovered = Rect.fromLTWH(
            (view.left - pan.dx) / scale,
            (view.top - pan.dy) / scale,
            view.width / scale,
            view.height / scale,
          );
          final String label = 'viewport ${viewportWidth}dp, model $model';
          _expectRectClose(recovered, model, '$label: view → display');
          _expectRectClose(
            page.displayRectToPdf(recovered),
            modelPdf[i],
            '$label: PDF mapping must not depend on viewport width',
          );
        }
      }

      // The view transform never writes back into the page model.
      expect(page.displaySize, originalSize);
      expect(page.cropBox, originalCropBox);
      expect(page.mediaBox, originalMediaBox);
      expect(page.rotation, 270);
    });
  });

  group('§6.1 validate sanity', () {
    test('a tolerated overshoot is clamped inside the display box', () {
      final PageGeometry page = PageGeometry(
        mediaBox: Rect.fromLTWH(0, 0, 595, 842),
        cropBox: Rect.fromLTWH(10, 20, 500, 700),
        rotation: 270,
      );
      final Rect generated = _displaySamples(page, 0x5A11).firstWhere(
        (Rect rect) =>
            rect.left < 0.4 &&
            rect.top < 0.4 &&
            rect.right < page.displaySize.width - 1 &&
            rect.bottom < page.displaySize.height - 1,
      );
      final Rect noisy = Rect.fromLTWH(
        generated.left - 0.4,
        generated.top - 0.4,
        generated.width,
        generated.height,
      );
      final GeometryValidation validation = page.validate(noisy);
      expect(
        validation.wasClamped,
        isTrue,
        reason: '0.4 pt noise on a generated rect must be recorded',
      );
      _expectRectInside(
        page.displayBox,
        validation.rect,
        '§6.1 clamped rect for $noisy',
      );
    });

    test('an overshoot above 0.5 pt is rejected', () {
      final PageGeometry page = PageGeometry(
        mediaBox: Rect.fromLTWH(0, 0, 595, 842),
      );
      expect(
        () => page.validate(Rect.fromLTWH(-0.6, 10, 100, 50)),
        throwsArgumentError,
      );
      expect(
        () => page.validate(Rect.fromLTWH(0, 0, 595, 842.6)),
        throwsArgumentError,
      );
    });
  });
}

/// The seeded geometry set: five page boxes, each at all four rotations.
List<_Combo> _buildCombos() {
  final List<_PageCase> pages = <_PageCase>[
    _PageCase('A4 portrait', Rect.fromLTWH(0, 0, 595, 842)),
    _PageCase(
      'A4 with CropBox offsets on all sides',
      Rect.fromLTWH(0, 0, 595, 842),
      Rect.fromLTWH(10, 20, 500, 700),
    ),
    _PageCase('A5 portrait', Rect.fromLTWH(0, 0, 420, 595)),
    _PageCase(
      'offset MediaBox and CropBox with negative origin',
      Rect.fromLTWH(-30, -40, 700, 900),
      Rect.fromLTWH(-20, -25, 650, 850),
    ),
    _PageCase(
      'CropBox clipped by a smaller MediaBox',
      Rect.fromLTWH(0, 0, 600, 800),
      Rect.fromLTWH(10, 20, 700, 900),
    ),
  ];
  const List<int> rotations = <int>[0, 90, 180, 270];
  final List<_Combo> combos = <_Combo>[];
  for (int pageIndex = 0; pageIndex < pages.length; pageIndex++) {
    final _PageCase page = pages[pageIndex];
    for (final int rotation in rotations) {
      final PageGeometry geometry = PageGeometry(
        mediaBox: page.mediaBox,
        cropBox: page.cropBox,
        rotation: rotation,
      );
      final int seed =
          (0x5EED0000 + pageIndex * 7919 + rotation * 104729) & 0xFFFFFFFF;
      combos.add(
        _Combo(
          label: '${page.name}, rotation $rotation',
          geometry: geometry,
          samples: _displaySamples(geometry, seed),
          cropSamples: _cropSamples(geometry, seed ^ 0x00C0FFEE),
        ),
      );
    }
  }
  return combos;
}

/// Explicit edge cases followed by 1,000 deterministic generated rects.
///
/// Even generated rects lie inside the display box; odd ones may lie outside
/// it, because the mapping itself must round-trip everywhere.
List<Rect> _displaySamples(PageGeometry geometry, int seed) {
  final Size display = geometry.displaySize;
  final _Lcg lcg = _Lcg(seed);
  final List<Rect> samples = <Rect>[
    geometry.displayBox,
    Rect.fromLTWH(0.125, 0.375, 6, 6),
    Rect.fromLTWH(10.5, 20.25, 1, 1),
    Rect.fromLTWH(display.width * 0.1, display.height * 0.1, 4, 300),
    Rect.fromLTWH(display.width * 0.2, display.height * 0.2, 300, 4),
    Rect.fromLTWH(0.125, 0.375, 6.25, 6.125),
    Rect.fromLTWH(display.width - 10.375, display.height - 20.625, 10.25, 20.5),
    Rect.fromLTWH(display.width - 20.5, display.height - 15.25, 40.75, 30.5),
    Rect.fromLTWH(-20.5, -33.25, 10.25, 6.5),
    Rect.fromLTWH(-150.125, -200.5, 6, 6),
  ];
  for (int i = 0; i < _generatedRectsPerCombo; i++) {
    final double width = lcg.range(4, 300);
    final double height = lcg.range(4, 300);
    final bool inside = i.isEven;
    final double left = inside
        ? lcg.range(0, display.width - width)
        : lcg.range(-display.width * 0.15, display.width * 1.15);
    final double top = inside
        ? lcg.range(0, display.height - height)
        : lcg.range(-display.height * 0.15, display.height * 1.15);
    samples.add(Rect.fromLTWH(left, top, width, height));
  }
  return samples;
}

/// Deterministic PDF-space rects that lie inside the effective crop box.
List<Rect> _cropSamples(PageGeometry geometry, int seed) {
  final Rect crop = geometry.cropBox;
  final _Lcg lcg = _Lcg(seed);
  final double maxWidth = math.min(300.0, crop.width);
  final double maxHeight = math.min(300.0, crop.height);
  final List<Rect> samples = <Rect>[crop];
  for (int i = 0; i < _cropSampleCount; i++) {
    final double width = lcg.range(1, maxWidth);
    final double height = lcg.range(1, maxHeight);
    final double left = lcg.range(crop.left, crop.right - width);
    final double top = lcg.range(crop.top, crop.bottom - height);
    samples.add(Rect.fromLTWH(left, top, width, height));
  }
  return samples;
}

/// The literal section 6.7 export mapping, one case per rotation.
Rect _contractExportRect(PageGeometry geometry, Rect rect) {
  final Rect crop = geometry.cropBox;
  return switch (geometry.rotation) {
    0 => Rect.fromLTWH(
      crop.left + rect.left,
      crop.bottom - rect.top - rect.height,
      rect.width,
      rect.height,
    ),
    90 => Rect.fromLTWH(
      crop.left + rect.top,
      crop.top + rect.left,
      rect.height,
      rect.width,
    ),
    180 => Rect.fromLTWH(
      crop.right - rect.left - rect.width,
      crop.top + rect.top,
      rect.width,
      rect.height,
    ),
    270 => Rect.fromLTWH(
      crop.right - rect.top - rect.height,
      crop.bottom - rect.left - rect.width,
      rect.height,
      rect.width,
    ),
    _ => throw StateError('unsupported rotation ${geometry.rotation}'),
  };
}

/// A 32-bit linear congruential generator, seeded and platform independent.
final class _Lcg {
  _Lcg(int seed) : _state = seed & _mask;

  static const int _mask = 0xFFFFFFFF;
  int _state;

  int _next() {
    _state = (_state * 1664525 + 1013904223) & _mask;
    return _state;
  }

  double nextDouble() => _next() / 0x100000000;

  double range(double min, double max) => min + nextDouble() * (max - min);
}

final class _Pan {
  const _Pan(this.dx, this.dy);

  final double dx;
  final double dy;
}

final class _PageCase {
  const _PageCase(this.name, this.mediaBox, [this.cropBox]);

  final String name;
  final Rect mediaBox;
  final Rect? cropBox;
}

final class _Combo {
  const _Combo({
    required this.label,
    required this.geometry,
    required this.samples,
    required this.cropSamples,
  });

  final String label;
  final PageGeometry geometry;
  final List<Rect> samples;
  final List<Rect> cropSamples;
}

bool _rectInside(Rect outer, Rect rect, double tolerance) {
  return rect.left >= outer.left - tolerance &&
      rect.top >= outer.top - tolerance &&
      rect.right <= outer.right + tolerance &&
      rect.bottom <= outer.bottom + tolerance;
}

void _expectRectInside(
  Rect outer,
  Rect rect,
  String reason, {
  double tolerance = _tolerancePt,
}) {
  if (!_rectInside(outer, rect, tolerance)) {
    fail('$reason: $rect is not inside $outer (tolerance $tolerance pt)');
  }
}

void _expectRectClose(Rect actual, Rect expected, String reason) {
  final double error = math.max(
    math.max(
      (actual.left - expected.left).abs(),
      (actual.top - expected.top).abs(),
    ),
    math.max(
      (actual.width - expected.width).abs(),
      (actual.height - expected.height).abs(),
    ),
  );
  if (error > _tolerancePt) {
    fail(
      '$reason: expected $expected, got $actual, max error $error pt '
      'exceeds $_tolerancePt pt',
    );
  }
}
