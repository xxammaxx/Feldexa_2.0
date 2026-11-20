// T078 zoom-to-field target-scale tests.
//
// These are host-VM tests (evidence class NONE). They pin
// `contracts/coordinates-and-geometry.md` section 3 and FR-034:
//   * target = clamp(min(0.7 * viewportH / fieldH,
//                        0.9 * viewportW / fieldW,
//                        8 * fitWidthScale),
//                    fitWidthScale, 8 * fitWidthScale);
//   * the height term, the width term, and the eight-times cap each win;
//   * both clamp bounds are inclusive and exact;
//   * shrinking a field never decreases the target before the cap, and
//     enlarging it never increases the target before the floor;
//   * a 6 pt checkbox on a phone viewport zooms above fit width;
//   * invalid inputs throw ArgumentError and valid inputs stay untouched.
//
// No golden, visual, device, or Android claim is made here.

import 'dart:math' as math;

import 'package:feldexa_core/feldexa_core.dart';
import 'package:flutter_test/flutter_test.dart';

const double _tolerance = 1e-12;

const List<double> _invalidNumbers = <double>[
  0,
  -0,
  -1,
  double.nan,
  double.infinity,
  double.negativeInfinity,
];

/// The contract formula re-derived independently of the implementation.
double _contractTarget({
  required Size viewportSize,
  required Size fieldSize,
  required double fitWidthScale,
}) {
  final double maxScale = 8 * fitWidthScale;
  final double raw = math.min(
    math.min(
      0.7 * viewportSize.height / fieldSize.height,
      0.9 * viewportSize.width / fieldSize.width,
    ),
    maxScale,
  );
  return raw < fitWidthScale ? fitWidthScale : math.min(raw, maxScale);
}

void main() {
  group('contract formula', () {
    test('tall field is limited by 0.7 * viewportHeight / fieldHeight', () {
      final Size viewport = Size(900, 900);
      final Size field = Size(300, 900);
      const double fit = 0.1;

      final double target = zoomToFieldScale(
        viewportSize: viewport,
        fieldSize: field,
        fitWidthScale: fit,
      );

      final double heightTerm = 0.7 * viewport.height / field.height;
      final double widthTerm = 0.9 * viewport.width / field.width;
      expect(target, closeTo(heightTerm, _tolerance));
      expect(target, lessThan(widthTerm));
      expect(target, lessThan(8 * fit));
    });

    test('wide field is limited by 0.9 * viewportWidth / fieldWidth', () {
      final Size viewport = Size(900, 900);
      final Size field = Size(800, 600);
      const double fit = 0.2;

      final double target = zoomToFieldScale(
        viewportSize: viewport,
        fieldSize: field,
        fitWidthScale: fit,
      );

      final double heightTerm = 0.7 * viewport.height / field.height;
      final double widthTerm = 0.9 * viewport.width / field.width;
      expect(target, closeTo(widthTerm, _tolerance));
      expect(target, lessThan(heightTerm));
      expect(target, lessThan(8 * fit));
    });

    test('tiny field caps at eight times the fit-width scale', () {
      final Size viewport = Size(360, 640);
      final Size field = Size(6, 6);
      const double fit = 0.5;

      final double target = zoomToFieldScale(
        viewportSize: viewport,
        fieldSize: field,
        fitWidthScale: fit,
      );

      expect(target, 8 * fit);
      expect(target, lessThan(0.7 * viewport.height / field.height));
      expect(target, lessThan(0.9 * viewport.width / field.width));
    });

    test('oversized field floors at the fit-width scale', () {
      final Size viewport = Size(360, 640);
      final Size field = Size(4000, 4000);
      const double fit = 0.5;

      final double target = zoomToFieldScale(
        viewportSize: viewport,
        fieldSize: field,
        fitWidthScale: fit,
      );

      expect(target, fit);
      expect(target, greaterThan(0.7 * viewport.height / field.height));
      expect(target, greaterThan(0.9 * viewport.width / field.width));
    });
  });

  group('terms and clamp', () {
    test('each of the three terms wins at least once', () {
      final List<({Size viewport, Size field, double fit, double expected})>
      cases = <({Size viewport, Size field, double fit, double expected})>[
        (
          viewport: Size(900, 900),
          field: Size(300, 900),
          fit: 0.1,
          expected: 0.7 * 900 / 900,
        ),
        (
          viewport: Size(900, 900),
          field: Size(800, 600),
          fit: 0.2,
          expected: 0.9 * 900 / 800,
        ),
        (viewport: Size(360, 640), field: Size(6, 6), fit: 0.5, expected: 4),
      ];

      for (final ({Size viewport, Size field, double fit, double expected}) item
          in cases) {
        final double target = zoomToFieldScale(
          viewportSize: item.viewport,
          fieldSize: item.field,
          fitWidthScale: item.fit,
        );
        expect(target, closeTo(item.expected, _tolerance));
      }
    });

    test('both clamp ends are reached exactly', () {
      final Size viewport = Size(360, 640);
      const double fit = 0.25;
      final double capped = zoomToFieldScale(
        viewportSize: viewport,
        fieldSize: Size(2, 2),
        fitWidthScale: fit,
      );
      final double floored = zoomToFieldScale(
        viewportSize: viewport,
        fieldSize: Size(10000, 10000),
        fitWidthScale: fit,
      );

      expect(capped, 8 * fit);
      expect(floored, fit);
    });
  });

  group('bounds and equality', () {
    test('coincident height and width terms stay within both bounds', () {
      final Size viewport = Size(900, 900);
      final Size field = Size(900, 700);

      final double heightTerm = 0.7 * viewport.height / field.height;
      final double widthTerm = 0.9 * viewport.width / field.width;
      expect(heightTerm, closeTo(widthTerm, _tolerance));

      // fit == the coincident term: the inclusive floor is hit exactly.
      const double floorFit = 0.9;
      final double atFloor = zoomToFieldScale(
        viewportSize: viewport,
        fieldSize: field,
        fitWidthScale: floorFit,
      );
      expect(atFloor, floorFit);
      expect(atFloor, greaterThanOrEqualTo(floorFit));
      expect(atFloor, lessThanOrEqualTo(8 * floorFit));

      // 8 * fit == the coincident term: the inclusive cap is hit exactly.
      const double capFit = 0.1125;
      final double atCap = zoomToFieldScale(
        viewportSize: viewport,
        fieldSize: field,
        fitWidthScale: capFit,
      );
      expect(atCap, 8 * capFit);
      expect(atCap, greaterThanOrEqualTo(capFit));
      expect(atCap, lessThanOrEqualTo(8 * capFit));
    });

    test('deterministic sample grid always stays inside the clamp', () {
      final List<Size> viewports = <Size>[
        Size(360, 640),
        Size(900, 900),
        Size(1440, 800),
      ];
      final List<Size> fields = <Size>[
        Size(6, 6),
        Size(100, 50),
        Size(300, 900),
        Size(800, 600),
        Size(4000, 4000),
        Size(0.1, 0.1),
      ];
      const List<double> fits = <double>[0.05, 0.2, 1, 3];

      for (final Size viewport in viewports) {
        for (final Size field in fields) {
          for (final double fit in fits) {
            final double target = zoomToFieldScale(
              viewportSize: viewport,
              fieldSize: field,
              fitWidthScale: fit,
            );
            final String reason = 'viewport $viewport, field $field, fit $fit';
            expect(target, greaterThanOrEqualTo(fit), reason: reason);
            expect(target, lessThanOrEqualTo(8 * fit), reason: reason);
            expect(
              target,
              closeTo(
                _contractTarget(
                  viewportSize: viewport,
                  fieldSize: field,
                  fitWidthScale: fit,
                ),
                _tolerance,
              ),
              reason: reason,
            );
          }
        }
      }
    });
  });

  group('monotonicity', () {
    final Size viewport = Size(360, 640);
    final Size baseField = Size(600, 400);
    const double fit = 0.2;
    const List<double> shrinkingFactors = <double>[
      4,
      2,
      1.5,
      1,
      0.75,
      0.5,
      0.25,
      0.1,
      0.05,
    ];

    List<double> targetsForShrinkingFields() {
      return <double>[
        for (final double factor in shrinkingFactors)
          zoomToFieldScale(
            viewportSize: viewport,
            fieldSize: Size(
              baseField.width * factor,
              baseField.height * factor,
            ),
            fitWidthScale: fit,
          ),
      ];
    }

    test('shrinking a field never decreases the target before the cap', () {
      final List<double> targets = targetsForShrinkingFields();
      for (int i = 1; i < targets.length; i++) {
        expect(
          targets[i],
          greaterThanOrEqualTo(targets[i - 1]),
          reason: 'factor ${shrinkingFactors[i]} must not zoom out',
        );
      }
      expect(targets.first, fit);
      expect(targets.last, 8 * fit);
    });

    test('enlarging a field never increases the target below the floor', () {
      final List<double> targets = targetsForShrinkingFields().reversed
          .toList();
      for (int i = 1; i < targets.length; i++) {
        expect(
          targets[i],
          lessThanOrEqualTo(targets[i - 1]),
          reason: 'enlarging a field must not zoom in',
        );
      }
      expect(targets.first, 8 * fit);
      expect(targets.last, fit);
    });
  });

  group('checkbox', () {
    test('a 6 pt checkbox on a 360x640 viewport zooms above fit width', () {
      final Size viewport = Size(360, 640);
      final Size checkbox = Size(6, 6);
      const double fit = 360 / 595;

      final double target = zoomToFieldScale(
        viewportSize: viewport,
        fieldSize: checkbox,
        fitWidthScale: fit,
      );

      expect(target, greaterThan(fit));
      expect(target, greaterThanOrEqualTo(fit));
      expect(target, lessThanOrEqualTo(8 * fit));
      expect(target, closeTo(8 * fit, _tolerance));
    });
  });

  group('validation', () {
    test('invalid viewport dimensions throw ArgumentError', () {
      for (final double invalid in _invalidNumbers) {
        expect(
          () => Size(invalid, 640),
          throwsArgumentError,
          reason: 'viewport width $invalid',
        );
        expect(
          () => Size(360, invalid),
          throwsArgumentError,
          reason: 'viewport height $invalid',
        );
      }
    });

    test('invalid field dimensions throw ArgumentError', () {
      for (final double invalid in _invalidNumbers) {
        expect(
          () => Size(invalid, 6),
          throwsArgumentError,
          reason: 'field width $invalid',
        );
        expect(
          () => Size(6, invalid),
          throwsArgumentError,
          reason: 'field height $invalid',
        );
      }
    });

    test('invalid fit-width scale throws a content-free ArgumentError', () {
      for (final double invalid in _invalidNumbers) {
        expect(
          () => zoomToFieldScale(
            viewportSize: Size(360, 640),
            fieldSize: Size(6, 6),
            fitWidthScale: invalid,
          ),
          throwsA(
            isA<ArgumentError>()
                .having(
                  (ArgumentError error) => error.message,
                  'message',
                  isNull,
                )
                .having((ArgumentError error) => error.name, 'name', isNull),
          ),
          reason: 'fitWidthScale $invalid',
        );
      }
    });

    test('valid inputs and stored geometry are left unchanged', () {
      final Size viewport = Size(360, 640);
      final Rect stored = Rect.fromLTWH(100, 50, 6, 6);
      final Size fieldSize = stored.size;
      const double fit = 360 / 595;

      final double target = zoomToFieldScale(
        viewportSize: viewport,
        fieldSize: fieldSize,
        fitWidthScale: fit,
      );

      expect(target, greaterThan(fit));
      expect(viewport.width, 360);
      expect(viewport.height, 640);
      expect(fieldSize.width, 6);
      expect(fieldSize.height, 6);
      expect(fit, 360 / 595);
      expect(stored, Rect.fromLTWH(100, 50, 6, 6));
    });
  });
}
