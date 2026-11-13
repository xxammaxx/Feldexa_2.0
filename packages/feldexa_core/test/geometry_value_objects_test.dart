// T015 geometry value-object tests.
//
// These are host-VM tests (evidence class NONE). They pin the invariants from
// `data-model.md` section 2.2 and the coordinate contract:
//   * all coordinates and dimensions are finite;
//   * Size and Rect dimensions are strictly positive;
//   * small rectangles (6 pt checkboxes) are valid model values;
//   * full precision is kept in memory and only JSON quantizes to 3 decimals;
//   * a positive dimension never quantizes to zero and break a round-trip.

import 'dart:convert';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Point', () {
    test('keeps finite coordinates without rounding', () {
      final Point point = Point(1.234567890123, -98.7654321);
      expect(point.x, 1.234567890123);
      expect(point.y, -98.7654321);
    });

    test('accepts zero, negative, subnormal, and extreme finite values', () {
      expect(Point.zero, Point(0, 0));
      expect(Point(-0.0, -0.0), Point(0, 0));
      expect(Point(double.minPositive, 0).x, double.minPositive);
      expect(Point(-double.maxFinite, double.maxFinite).x, -double.maxFinite);
    });

    test('rejects NaN, positive infinity, and negative infinity', () {
      final List<double> invalid = <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ];
      for (final double value in invalid) {
        expect(
          () => Point(value, 0),
          throwsArgumentError,
          reason: 'x must reject $value',
        );
        expect(
          () => Point(0, value),
          throwsArgumentError,
          reason: 'y must reject $value',
        );
      }
    });

    test('is an immutable value object with stable equality', () {
      expect(Point(1, 2), Point(1, 2));
      expect(Point(1, 2).hashCode, Point(1, 2).hashCode);
      expect(Point(1, 2), isNot(Point(1, 3)));
      expect(Point.zero.toString(), 'Point(0.0, 0.0)');
    });

    test('quantizes to three decimals only when serialized', () {
      final Point point = Point(1.23456, -7.89012);
      final Map<String, double> json = point.toJson();
      expect(json.keys, <String>['x', 'y']);
      expect(json['x'], closeTo(1.235, 1e-12));
      expect(json['y'], closeTo(-7.89, 1e-12));
      // The object itself was not rounded.
      expect(point.x, 1.23456);
      expect(point.y, -7.89012);
    });

    test('JSON round-trip reads the quantized coordinates', () {
      final Point point = Point(0.0014, 12.9996);
      final Map<String, Object?> decoded =
          jsonDecode(jsonEncode(point.toJson())) as Map<String, Object?>;
      expect(Point.fromJson(decoded), Point(0.001, 13.0));
    });

    test('fromJson rejects missing, non-numeric, and non-finite fields', () {
      expect(
        () => Point.fromJson(<String, Object?>{'y': 1}),
        throwsFormatException,
      );
      expect(
        () => Point.fromJson(<String, Object?>{'x': '1', 'y': 1}),
        throwsFormatException,
      );
      expect(
        () => Point.fromJson(<String, Object?>{'x': double.nan, 'y': 1}),
        throwsFormatException,
      );
      expect(
        () => Point.fromJson(<String, Object?>{'x': 1, 'y': double.infinity}),
        throwsFormatException,
      );
    });
  });

  group('Size', () {
    test('accepts small and large positive dimensions', () {
      expect(Size(6, 6).width, 6);
      expect(
        Size(double.minPositive, double.minPositive).height,
        double.minPositive,
      );
      expect(Size(595.28, 841.89).aspectRatio, closeTo(0.7071, 0.0001));
    });

    test('rejects zero, negative zero, negative, NaN, and infinity', () {
      final List<double> invalid = <double>[
        0.0,
        -0.0,
        -0.001,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ];
      for (final double value in invalid) {
        expect(
          () => Size(value, 1),
          throwsArgumentError,
          reason: 'width must reject $value',
        );
        expect(
          () => Size(1, value),
          throwsArgumentError,
          reason: 'height must reject $value',
        );
      }
    });

    test('is an immutable value object with stable equality', () {
      expect(Size(210, 14.5), Size(210, 14.5));
      expect(Size(210, 14.5).hashCode, Size(210, 14.5).hashCode);
      expect(Size(210, 14.5), isNot(Size(210, 15)));
      expect(Size(6, 6).toString(), 'Size(6.0, 6.0)');
    });

    test('keeps full precision until serialization', () {
      final Size size = Size(210.123456, 14.987654);
      expect(size.width, 210.123456);
      expect(size.height, 14.987654);
      final Map<String, double> json = size.toJson();
      expect(json['width'], closeTo(210.123, 1e-12));
      expect(json['height'], closeTo(14.988, 1e-12));
    });

    test('preserves positivity for dimensions below the quantization step', () {
      final Size tiny = Size(0.0004, 0.0001);
      final Map<String, double> json = tiny.toJson();
      expect(json['width'], 0.001);
      expect(json['height'], 0.001);
      expect(Size.fromJson(json), Size(0.001, 0.001));
    });

    test('fromJson rejects non-positive and malformed dimensions', () {
      expect(
        () => Size.fromJson(<String, Object?>{'width': 0, 'height': 1}),
        throwsFormatException,
      );
      expect(
        () => Size.fromJson(<String, Object?>{'width': 1, 'height': -2}),
        throwsFormatException,
      );
      expect(
        () => Size.fromJson(<String, Object?>{'width': '1', 'height': 2}),
        throwsFormatException,
      );
      expect(
        () =>
            Size.fromJson(<String, Object?>{'width': 1, 'height': double.nan}),
        throwsFormatException,
      );
      expect(
        () => Size.fromJson(<String, Object?>{'width': 1}),
        throwsFormatException,
      );
    });
  });

  group('Rect', () {
    test('accepts a 6 pt checkbox and other small rectangles', () {
      final Rect checkbox = Rect.fromLTWH(100, 50, 6, 6);
      expect(checkbox.width, 6);
      expect(checkbox.height, 6);
      expect(Rect.fromLTWH(0, 0, 0.001, 0.001).width, 0.001);
    });

    test('accepts finite negative origins', () {
      final Rect rect = Rect.fromLTWH(-10, -20, 30, 40);
      expect(rect.right, 20);
      expect(rect.bottom, 20);
      expect(rect.origin, Point(-10, -20));
      expect(rect.size, Size(30, 40));
    });

    test('derives x/y aliases and the right/bottom edges', () {
      final Rect rect = Rect.fromLTWH(100, 50, 120, 20);
      expect(rect.x, 100);
      expect(rect.y, 50);
      expect(rect.right, 220);
      expect(rect.bottom, 70);
    });

    test('rejects non-positive width and height', () {
      final List<double> invalid = <double>[
        0.0,
        -0.0,
        -1.5,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ];
      for (final double value in invalid) {
        expect(
          () => Rect.fromLTWH(0, 0, value, 1),
          throwsArgumentError,
          reason: 'width must reject $value',
        );
        expect(
          () => Rect.fromLTWH(0, 0, 1, value),
          throwsArgumentError,
          reason: 'height must reject $value',
        );
      }
    });

    test('rejects non-finite origins', () {
      expect(() => Rect.fromLTWH(double.nan, 0, 1, 1), throwsArgumentError);
      expect(
        () => Rect.fromLTWH(0, double.infinity, 1, 1),
        throwsArgumentError,
      );
      expect(
        () => Rect.fromLTWH(double.negativeInfinity, 0, 1, 1),
        throwsArgumentError,
      );
    });

    test('rejects a finite edge that overflows to infinity', () {
      expect(
        () => Rect.fromLTWH(double.maxFinite, 0, double.maxFinite, 1),
        throwsArgumentError,
      );
      expect(
        () => Rect.fromLTWH(0, double.maxFinite, 1, double.maxFinite),
        throwsArgumentError,
      );
    });

    test('is an immutable value object with stable equality', () {
      expect(Rect.fromLTWH(1, 2, 3, 4), Rect.fromLTWH(1, 2, 3, 4));
      expect(
        Rect.fromLTWH(1, 2, 3, 4).hashCode,
        Rect.fromLTWH(1, 2, 3, 4).hashCode,
      );
      expect(Rect.fromLTWH(1, 2, 3, 4), isNot(Rect.fromLTWH(1, 2, 3, 5)));
      expect(
        Rect.fromLTWH(1, 2, 3, 4).toString(),
        'Rect(left: 1.0, top: 2.0, width: 3.0, height: 4.0)',
      );
    });

    test('keeps full precision until serialization', () {
      final Rect rect = Rect.fromLTWH(
        1.23456789,
        2.34567891,
        3.45678912,
        4.56789123,
      );
      expect(rect.left, 1.23456789);
      expect(rect.top, 2.34567891);
      expect(rect.width, 3.45678912);
      expect(rect.height, 4.56789123);
      final Map<String, double> json = rect.toJson();
      expect(json.keys, <String>['x', 'y', 'width', 'height']);
      expect(json['x'], closeTo(1.235, 1e-12));
      expect(json['y'], closeTo(2.346, 1e-12));
      expect(json['width'], closeTo(3.457, 1e-12));
      expect(json['height'], closeTo(4.568, 1e-12));
    });

    test('JSON round-trip preserves the normalised contract example', () {
      final Rect rect = Rect.fromLTWH(148.5, 302.0, 210.0, 14.5);
      final Map<String, Object?> decoded =
          jsonDecode(jsonEncode(rect.toJson())) as Map<String, Object?>;
      final Rect restored = Rect.fromJson(decoded);
      expect(restored, rect);
      expect(restored.x, 148.5);
      expect(restored.height, 14.5);
    });

    test('JSON preserves positivity below the quantization step', () {
      final Rect rect = Rect.fromLTWH(0.0004, 0.0004, 0.0004, 0.0004);
      final Rect restored = Rect.fromJson(rect.toJson());
      expect(restored.x, 0.0);
      expect(restored.y, 0.0);
      expect(restored.width, 0.001);
      expect(restored.height, 0.001);
    });

    test('fromJson rejects missing, malformed, and invalid fields', () {
      expect(
        () => Rect.fromJson(<String, Object?>{'y': 0, 'width': 1, 'height': 1}),
        throwsFormatException,
      );
      expect(
        () => Rect.fromJson(<String, Object?>{
          'x': 0,
          'y': 0,
          'width': '1',
          'height': 1,
        }),
        throwsFormatException,
      );
      expect(
        () => Rect.fromJson(<String, Object?>{
          'x': 0,
          'y': 0,
          'width': 0,
          'height': 1,
        }),
        throwsFormatException,
      );
      expect(
        () => Rect.fromJson(<String, Object?>{
          'x': 0,
          'y': 0,
          'width': 1,
          'height': -1,
        }),
        throwsFormatException,
      );
      expect(
        () => Rect.fromJson(<String, Object?>{
          'x': 0,
          'y': 0,
          'width': double.nan,
          'height': 1,
        }),
        throwsFormatException,
      );
      expect(
        () => Rect.fromJson(<String, Object?>{
          'x': double.maxFinite,
          'y': 0,
          'width': double.maxFinite,
          'height': 1,
        }),
        throwsFormatException,
      );
    });
  });
}
