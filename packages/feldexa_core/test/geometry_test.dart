// T016 PageGeometry tests.
//
// These are host-VM tests (evidence class NONE). They pin
// `contracts/coordinates-and-geometry.md` sections 1–2 and 6.1:
//   * the display box is the CropBox intersected with the MediaBox, and the
//     CropBox defaults to the MediaBox;
//   * rotations 0/90/180/270 choose the display size and the mapping formulas;
//   * CropBox offsets are applied on every side and clipped against a smaller
//     MediaBox;
//   * display → PDF → display round-trips for points and rectangles;
//   * the normative full-page table and the `(100, 50, 120, 20)` field case;
//   * validation rejects overshoots above 0.5 pt and reports clamped noise;
//   * persisted JSON round-trips and rejects malformed input.

import 'dart:convert';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:flutter_test/flutter_test.dart';

const double _closeTolerance = 1e-6;

void main() {
  group('display box', () {
    test('CropBox defaults to the MediaBox', () {
      final PageGeometry geometry = PageGeometry(mediaBox: _a4());
      expect(geometry.cropBox, _a4());
      expect(geometry.mediaBox, _a4());
      expect(geometry.rotation, 0);
    });

    test('rotation 0 and 180 keep the crop dimensions', () {
      for (final int rotation in <int>[0, 180]) {
        final PageGeometry geometry = _a4Geometry(rotation);
        expect(
          geometry.displaySize,
          Size(595, 842),
          reason: 'rotation $rotation',
        );
        expect(
          geometry.displayBox,
          Rect.fromLTWH(0, 0, 595, 842),
          reason: 'rotation $rotation',
        );
      }
    });

    test('rotation 90 and 270 swap the crop dimensions', () {
      for (final int rotation in <int>[90, 270]) {
        final PageGeometry geometry = _a4Geometry(rotation);
        expect(
          geometry.displaySize,
          Size(842, 595),
          reason: 'rotation $rotation',
        );
        expect(
          geometry.displayBox,
          Rect.fromLTWH(0, 0, 842, 595),
          reason: 'rotation $rotation',
        );
      }
    });

    test('a CropBox inside the MediaBox sets the display size', () {
      final PageGeometry geometry = _a4Geometry(
        0,
        cropBox: Rect.fromLTWH(10, 20, 500, 800),
      );
      expect(geometry.cropBox, Rect.fromLTWH(10, 20, 500, 800));
      expect(geometry.displaySize, Size(500, 800));
      final PageGeometry quarterTurn = _a4Geometry(
        90,
        cropBox: Rect.fromLTWH(10, 20, 500, 800),
      );
      expect(quarterTurn.displaySize, Size(800, 500));
    });

    test('a CropBox larger than the MediaBox is clipped to the MediaBox', () {
      final PageGeometry geometry = PageGeometry(
        mediaBox: Rect.fromLTWH(0, 0, 600, 800),
        cropBox: Rect.fromLTWH(-10, -20, 700, 900),
      );
      expect(geometry.cropBox, Rect.fromLTWH(0, 0, 600, 800));
      expect(geometry.displaySize, Size(600, 800));
    });

    test('a partly overlapping CropBox is intersected, not trusted', () {
      final PageGeometry geometry = PageGeometry(
        mediaBox: Rect.fromLTWH(0, 0, 600, 800),
        cropBox: Rect.fromLTWH(10, 20, 700, 900),
      );
      expect(geometry.cropBox, Rect.fromLTWH(10, 20, 590, 780));
      expect(geometry.displaySize, Size(590, 780));
    });

    test('a non-overlapping or degenerate CropBox is rejected', () {
      expect(
        () => PageGeometry(
          mediaBox: _a4(),
          cropBox: Rect.fromLTWH(1000, 1000, 10, 10),
        ),
        throwsArgumentError,
      );
      // Touching the MediaBox edge has zero overlap area.
      expect(
        () => PageGeometry(
          mediaBox: _a4(),
          cropBox: Rect.fromLTWH(595, 0, 10, 10),
        ),
        throwsArgumentError,
      );
    });

    test('unsupported rotations are rejected', () {
      for (final int rotation in <int>[-90, -1, 1, 45, 89, 271, 360, 720]) {
        expect(
          () => _a4Geometry(rotation),
          throwsArgumentError,
          reason: 'rotation $rotation must be rejected',
        );
      }
    });
  });

  group('rotation mapping', () {
    test('normative full-page table maps every rotation to the PDF box', () {
      for (final int rotation in <int>[0, 90, 180, 270]) {
        final PageGeometry geometry = _a4Geometry(rotation);
        final Size display = geometry.displaySize;
        final Rect pdfRect = geometry.displayRectToPdf(
          Rect.fromLTWH(0, 0, display.width, display.height),
        );
        expect(
          pdfRect,
          Rect.fromLTWH(0, 0, 595, 842),
          reason: 'rotation $rotation',
        );
      }
    });

    test('the normative (100, 50, 120, 20) field maps per rotation', () {
      final Rect field = Rect.fromLTWH(100, 50, 120, 20);
      // Rotation 0 and 90 are stated normatively in the contract; 180 and 270
      // follow from the same section 2 formulas.
      final Map<int, Rect> expected = <int, Rect>{
        0: Rect.fromLTWH(100, 772, 120, 20),
        90: Rect.fromLTWH(50, 100, 20, 120),
        180: Rect.fromLTWH(375, 50, 120, 20),
        270: Rect.fromLTWH(525, 622, 20, 120),
      };
      for (final MapEntry<int, Rect> entry in expected.entries) {
        final PageGeometry geometry = _a4Geometry(entry.key);
        expect(
          geometry.displayRectToPdf(field),
          entry.value,
          reason: 'rotation ${entry.key}',
        );
        expect(
          geometry.pdfRectToDisplay(entry.value),
          field,
          reason: 'rotation ${entry.key} inverse',
        );
      }
    });

    test('the normative (100, 50) point maps per rotation', () {
      final Point point = Point(100, 50);
      final Map<int, Point> expected = <int, Point>{
        0: Point(100, 792),
        90: Point(50, 100),
        180: Point(495, 50),
        270: Point(545, 742),
      };
      for (final MapEntry<int, Point> entry in expected.entries) {
        final PageGeometry geometry = _a4Geometry(entry.key);
        _expectPointClose(
          geometry.displayToPdf(point),
          entry.value,
          reason: 'rotation ${entry.key}',
        );
        _expectPointClose(
          geometry.pdfToDisplay(entry.value),
          point,
          reason: 'rotation ${entry.key} inverse',
        );
      }
    });

    test('CropBox offsets are applied on every side', () {
      final PageGeometry geometry = PageGeometry(
        mediaBox: Rect.fromLTWH(10, 20, 595, 842),
        rotation: 0,
      );
      expect(geometry.cropBox, Rect.fromLTWH(10, 20, 595, 842));
      expect(geometry.displaySize, Size(595, 842));
      final Rect field = Rect.fromLTWH(100, 50, 120, 20);
      final Map<int, Rect> expected = <int, Rect>{
        0: Rect.fromLTWH(110, 792, 120, 20),
        90: Rect.fromLTWH(60, 120, 20, 120),
        180: Rect.fromLTWH(385, 70, 120, 20),
        270: Rect.fromLTWH(535, 642, 20, 120),
      };
      for (final MapEntry<int, Rect> entry in expected.entries) {
        final PageGeometry rotated = PageGeometry(
          mediaBox: Rect.fromLTWH(10, 20, 595, 842),
          rotation: entry.key,
        );
        expect(
          rotated.displayRectToPdf(field),
          entry.value,
          reason: 'rotation ${entry.key}',
        );
      }
    });

    test('a clipped CropBox keeps the clipped offsets', () {
      final PageGeometry geometry = PageGeometry(
        mediaBox: Rect.fromLTWH(0, 0, 600, 800),
        cropBox: Rect.fromLTWH(10, 20, 700, 900),
        rotation: 90,
      );
      expect(geometry.cropBox, Rect.fromLTWH(10, 20, 590, 780));
      final Rect fullDisplay = geometry.displayBox;
      expect(fullDisplay, Rect.fromLTWH(0, 0, 780, 590));
      expect(
        geometry.displayRectToPdf(fullDisplay),
        Rect.fromLTWH(10, 20, 590, 780),
      );
    });

    test('all display corners map onto the four PDF crop corners', () {
      for (final int rotation in <int>[0, 90, 180, 270]) {
        final PageGeometry geometry = _a4Geometry(rotation);
        final Size size = geometry.displaySize;
        final List<Point> displayCorners = <Point>[
          Point(0, 0),
          Point(size.width, 0),
          Point(0, size.height),
          Point(size.width, size.height),
        ];
        final Set<Point> mapped = displayCorners
            .map(geometry.displayToPdf)
            .toSet();
        expect(mapped, <Point>{
          Point(0, 0),
          Point(595, 0),
          Point(0, 842),
          Point(595, 842),
        }, reason: 'rotation $rotation');
      }
    });
  });

  group('round-trip', () {
    final List<Rect> rects = <Rect>[
      Rect.fromLTWH(0, 0, 595, 842),
      Rect.fromLTWH(100, 50, 120, 20),
      Rect.fromLTWH(0.125, 0.375, 6, 6),
      Rect.fromLTWH(594.5, 841.5, 0.5, 0.5),
      Rect.fromLTWH(10.25, 20.5, 300.75, 400.125),
    ];

    test('display → PDF → display for points at all rotations', () {
      final List<Point> points = <Point>[
        Point.zero,
        Point(0.001, 0.002),
        Point(297.5, 421),
        Point(595, 842),
        Point(594.999, 841.999),
        Point(-10, -20),
        Point(600, 850),
      ];
      for (final int rotation in <int>[0, 90, 180, 270]) {
        final PageGeometry geometry = _a4Geometry(rotation);
        for (final Point point in points) {
          final Point restored = geometry.pdfToDisplay(
            geometry.displayToPdf(point),
          );
          _expectPointClose(
            restored,
            point,
            reason: 'rotation $rotation, point $point',
          );
          final Point pdfRestored = geometry.displayToPdf(
            geometry.pdfToDisplay(geometry.displayToPdf(point)),
          );
          _expectPointClose(
            pdfRestored,
            geometry.displayToPdf(point),
            reason: 'rotation $rotation, PDF point round-trip',
          );
        }
      }
    });

    test('display → PDF → display for rectangles at all rotations', () {
      for (final int rotation in <int>[0, 90, 180, 270]) {
        final PageGeometry geometry = _a4Geometry(rotation);
        for (final Rect rect in rects) {
          final Rect restored = geometry.pdfRectToDisplay(
            geometry.displayRectToPdf(rect),
          );
          _expectRectClose(
            restored,
            rect,
            reason: 'rotation $rotation, rect $rect',
          );
        }
      }
    });

    test('round-trips with offset and clipped CropBoxes', () {
      final List<PageGeometry> geometries = <PageGeometry>[
        PageGeometry(mediaBox: Rect.fromLTWH(10, 20, 595, 842), rotation: 0),
        PageGeometry(
          mediaBox: Rect.fromLTWH(-30, -40, 700, 900),
          cropBox: Rect.fromLTWH(-20, -25, 650, 850),
        ),
        PageGeometry(
          mediaBox: Rect.fromLTWH(0, 0, 600, 800),
          cropBox: Rect.fromLTWH(10, 20, 700, 900),
        ),
      ];
      for (final PageGeometry geometry in geometries) {
        for (final int rotation in <int>[0, 90, 180, 270]) {
          final PageGeometry rotated = PageGeometry(
            mediaBox: geometry.mediaBox,
            cropBox: geometry.cropBox,
            rotation: rotation,
          );
          final Size size = rotated.displaySize;
          final List<Rect> localRects = <Rect>[
            Rect.fromLTWH(0, 0, size.width, size.height),
            Rect.fromLTWH(size.width / 4, size.height / 3, 6, 6),
            Rect.fromLTWH(size.width - 10.5, size.height - 20.25, 10.5, 20.25),
          ];
          for (final Rect rect in localRects) {
            final Rect restored = rotated.pdfRectToDisplay(
              rotated.displayRectToPdf(rect),
            );
            _expectRectClose(restored, rect, reason: 'rotation $rotation');
          }
        }
      }
    });

    test('quarter turns swap the PDF rectangle width and height', () {
      final Rect displayRect = Rect.fromLTWH(100, 50, 120, 20);
      for (final int rotation in <int>[0, 180]) {
        final Rect pdf = _a4Geometry(rotation).displayRectToPdf(displayRect);
        expect(pdf.width, 120, reason: 'rotation $rotation');
        expect(pdf.height, 20, reason: 'rotation $rotation');
      }
      for (final int rotation in <int>[90, 270]) {
        final Rect pdf = _a4Geometry(rotation).displayRectToPdf(displayRect);
        expect(pdf.width, 20, reason: 'rotation $rotation');
        expect(pdf.height, 120, reason: 'rotation $rotation');
      }
    });
  });

  group('validation', () {
    test('an in-bounds rectangle is returned unchanged', () {
      final PageGeometry geometry = _a4Geometry(0);
      final GeometryValidation result = geometry.validate(
        Rect.fromLTWH(10, 20, 100, 50),
      );
      expect(result.rect, Rect.fromLTWH(10, 20, 100, 50));
      expect(result.wasClamped, isFalse);
      expect(geometry.validate(geometry.displayBox).wasClamped, isFalse);
    });

    test('sub-half-point overshoot is clamped with a warning flag', () {
      final PageGeometry geometry = _a4Geometry(0);
      final GeometryValidation left = geometry.validate(
        Rect.fromLTWH(-0.4, 20, 100, 50),
      );
      expect(left.wasClamped, isTrue);
      expect(left.rect, Rect.fromLTWH(0, 20, 99.6, 50));

      final GeometryValidation top = geometry.validate(
        Rect.fromLTWH(0, -0.4, 10, 10),
      );
      expect(top.wasClamped, isTrue);
      expect(top.rect, Rect.fromLTWH(0, 0, 10, 9.6));

      final GeometryValidation right = geometry.validate(
        Rect.fromLTWH(500, 0, 95.4, 10),
      );
      expect(right.wasClamped, isTrue);
      expect(right.rect, Rect.fromLTWH(500, 0, 95, 10));

      final GeometryValidation bottom = geometry.validate(
        Rect.fromLTWH(10, 800, 100, 42.4),
      );
      expect(bottom.wasClamped, isTrue);
      expect(bottom.rect, Rect.fromLTWH(10, 800, 100, 42));
    });

    test('exactly 0.5 pt is accepted, above it is rejected', () {
      final PageGeometry geometry = _a4Geometry(0);
      final GeometryValidation accepted = geometry.validate(
        Rect.fromLTWH(-0.5, 0, 10, 10),
      );
      expect(accepted.wasClamped, isTrue);
      expect(accepted.rect, Rect.fromLTWH(0, 0, 9.5, 10));

      expect(
        () => geometry.validate(Rect.fromLTWH(-0.5000001, 0, 10, 10)),
        throwsArgumentError,
      );
      expect(
        () => geometry.validate(Rect.fromLTWH(0, 0, 596, 10)),
        throwsArgumentError,
      );
      expect(
        () => geometry.validate(Rect.fromLTWH(0, 0, 10, 843)),
        throwsArgumentError,
      );
    });

    test('a rectangle entirely outside within tolerance is translated', () {
      final PageGeometry geometry = _a4Geometry(0);
      final GeometryValidation right = geometry.validate(
        Rect.fromLTWH(595.1, 10, 0.2, 6),
      );
      expect(right.wasClamped, isTrue);
      _expectRectClose(
        right.rect,
        Rect.fromLTWH(594.8, 10, 0.2, 6),
        reason: 'horizontal translation',
      );

      final GeometryValidation above = geometry.validate(
        Rect.fromLTWH(10, 842.1, 6, 0.2),
      );
      expect(above.wasClamped, isTrue);
      _expectRectClose(
        above.rect,
        Rect.fromLTWH(10, 841.8, 6, 0.2),
        reason: 'vertical translation',
      );
    });

    test('every clamped rectangle lies exactly inside the display box', () {
      final PageGeometry geometry = _a4Geometry(0);
      final List<Rect> inputs = <Rect>[
        Rect.fromLTWH(-0.4, 20, 100, 50),
        Rect.fromLTWH(500, 0, 95.4, 10),
        Rect.fromLTWH(10, 800, 100, 42.4),
        Rect.fromLTWH(595.1, 10, 0.2, 6),
        Rect.fromLTWH(10, 842.1, 6, 0.2),
        Rect.fromLTWH(-0.3, -0.3, 0.2, 0.2),
      ];
      for (final Rect input in inputs) {
        final Rect rect = geometry.validate(input).rect;
        expect(rect.left >= 0, isTrue, reason: '$input left');
        expect(rect.top >= 0, isTrue, reason: '$input top');
        expect(
          rect.right <= geometry.displaySize.width,
          isTrue,
          reason: '$input right',
        );
        expect(
          rect.bottom <= geometry.displaySize.height,
          isTrue,
          reason: '$input bottom',
        );
      }
    });

    test('validation uses the rotated display box', () {
      final PageGeometry geometry = _a4Geometry(90);
      expect(geometry.displaySize, Size(842, 595));
      final GeometryValidation landscape = geometry.validate(
        Rect.fromLTWH(0, 0, 842, 595),
      );
      expect(landscape.wasClamped, isFalse);
      expect(
        () => geometry.validate(Rect.fromLTWH(0, 0, 595, 842)),
        throwsArgumentError,
      );
    });

    test('the documented tolerance is 0.5 pt', () {
      expect(maxClampTolerancePt, 0.5);
    });
  });

  group('JSON', () {
    test('serializes both boxes and the rotation, not the derived size', () {
      final PageGeometry geometry = PageGeometry(
        mediaBox: Rect.fromLTWH(10, 20, 595, 842),
        cropBox: Rect.fromLTWH(20, 30, 500, 700),
        rotation: 90,
      );
      final Map<String, Object?> json = geometry.toJson();
      expect(
        json.keys,
        containsAll(<String>['mediaBox', 'cropBox', 'rotation']),
      );
      expect(json.containsKey('displaySize'), isFalse);
      expect(json['rotation'], 90);
    });

    test('round-trips through JSON and recomputes the display size', () {
      final PageGeometry geometry = PageGeometry(
        mediaBox: Rect.fromLTWH(10, 20, 595, 842),
        cropBox: Rect.fromLTWH(20, 30, 500, 700),
        rotation: 270,
      );
      final Map<String, Object?> decoded =
          jsonDecode(jsonEncode(geometry.toJson())) as Map<String, Object?>;
      final PageGeometry restored = PageGeometry.fromJson(decoded);
      expect(restored, geometry);
      expect(restored.displaySize, Size(700, 500));
    });

    test('defaults a missing or null CropBox to the MediaBox', () {
      final Map<String, Object?> withoutCropBox = <String, Object?>{
        'mediaBox': <String, Object?>{
          'x': 0,
          'y': 0,
          'width': 595,
          'height': 842,
        },
        'rotation': 0,
      };
      final PageGeometry fromMissing = PageGeometry.fromJson(withoutCropBox);
      expect(fromMissing.cropBox, _a4());

      final Map<String, Object?> withNullCropBox = <String, Object?>{
        'mediaBox': <String, Object?>{
          'x': 0,
          'y': 0,
          'width': 595,
          'height': 842,
        },
        'cropBox': null,
        'rotation': 180,
      };
      expect(PageGeometry.fromJson(withNullCropBox).cropBox, _a4());
    });

    test('clips an out-of-bounds serialized CropBox like the constructor', () {
      final Map<String, Object?> json = <String, Object?>{
        'mediaBox': <String, Object?>{
          'x': 0,
          'y': 0,
          'width': 600,
          'height': 800,
        },
        'cropBox': <String, Object?>{
          'x': -10,
          'y': -20,
          'width': 700,
          'height': 900,
        },
        'rotation': 0,
      };
      final PageGeometry geometry = PageGeometry.fromJson(json);
      expect(geometry.cropBox, Rect.fromLTWH(0, 0, 600, 800));
    });

    test('rejects malformed or unsupported JSON', () {
      final Map<String, Object?> validMediaBox = <String, Object?>{
        'x': 0,
        'y': 0,
        'width': 595,
        'height': 842,
      };
      expect(
        () => PageGeometry.fromJson(<String, Object?>{'rotation': 0}),
        throwsFormatException,
      );
      expect(
        () => PageGeometry.fromJson(<String, Object?>{
          'mediaBox': 'nope',
          'rotation': 0,
        }),
        throwsFormatException,
      );
      expect(
        () => PageGeometry.fromJson(<String, Object?>{
          'mediaBox': validMediaBox,
          'cropBox': 'nope',
          'rotation': 0,
        }),
        throwsFormatException,
      );
      expect(
        () =>
            PageGeometry.fromJson(<String, Object?>{'mediaBox': validMediaBox}),
        throwsFormatException,
      );
      expect(
        () => PageGeometry.fromJson(<String, Object?>{
          'mediaBox': validMediaBox,
          'rotation': 45,
        }),
        throwsFormatException,
      );
      expect(
        () => PageGeometry.fromJson(<String, Object?>{
          'mediaBox': validMediaBox,
          'rotation': '0',
        }),
        throwsFormatException,
      );
      expect(
        () => PageGeometry.fromJson(<String, Object?>{
          'mediaBox': validMediaBox,
          'rotation': 0.0,
        }),
        throwsFormatException,
      );
      expect(
        () => PageGeometry.fromJson(<String, Object?>{
          'mediaBox': <String, Object?>{
            'x': 0,
            'y': 0,
            'width': 0,
            'height': 1,
          },
          'rotation': 0,
        }),
        throwsFormatException,
      );
      expect(
        () => PageGeometry.fromJson(<String, Object?>{
          'mediaBox': validMediaBox,
          'cropBox': <String, Object?>{
            'x': 1000,
            'y': 1000,
            'width': 10,
            'height': 10,
          },
          'rotation': 0,
        }),
        throwsFormatException,
      );
    });
  });

  group('value semantics', () {
    test('equality and hashCode use boxes and rotation', () {
      final PageGeometry a = _a4Geometry(90);
      final PageGeometry b = _a4Geometry(90);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(_a4Geometry(0)));
      expect(a, isNot(_a4Geometry(90, cropBox: Rect.fromLTWH(0, 0, 100, 100))));
    });

    test('toString names the boxes and rotation', () {
      final String text = _a4Geometry(180).toString();
      expect(text, contains('mediaBox'));
      expect(text, contains('cropBox'));
      expect(text, contains('rotation: 180'));
    });
  });
}

Rect _a4() => Rect.fromLTWH(0, 0, 595, 842);

PageGeometry _a4Geometry(int rotation, {Rect? cropBox}) {
  return PageGeometry(mediaBox: _a4(), cropBox: cropBox, rotation: rotation);
}

void _expectPointClose(
  Point actual,
  Point expected, {
  String? reason,
  double tolerance = _closeTolerance,
}) {
  expect(actual.x, closeTo(expected.x, tolerance), reason: '${reason ?? ''} x');
  expect(actual.y, closeTo(expected.y, tolerance), reason: '${reason ?? ''} y');
}

void _expectRectClose(
  Rect actual,
  Rect expected, {
  String? reason,
  double tolerance = _closeTolerance,
}) {
  expect(
    actual.left,
    closeTo(expected.left, tolerance),
    reason: '${reason ?? ''} left',
  );
  expect(
    actual.top,
    closeTo(expected.top, tolerance),
    reason: '${reason ?? ''} top',
  );
  expect(
    actual.width,
    closeTo(expected.width, tolerance),
    reason: '${reason ?? ''} width',
  );
  expect(
    actual.height,
    closeTo(expected.height, tolerance),
    reason: '${reason ?? ''} height',
  );
}
