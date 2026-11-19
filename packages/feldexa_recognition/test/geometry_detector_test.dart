// T052 host-VM tests for the deterministic geometry detectors.
//
// The test package is `flutter_test` because the repository's unit suites
// standardise on it and `@TestOn('vm')` keeps this file on the host VM.
// `packages/feldexa_recognition/pubspec.yaml` has no dev_dependency yet: T050
// owns the single `flutter_test` addition for this parallel US2 slice, and this
// worktree must not edit the pubspec. The shared pub workspace resolves
// `flutter_test` from another member package; remove the suppression once
// T050's dev_dependency is merged.
// ignore_for_file: depend_on_referenced_packages

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/raster.dart';
import 'package:flutter_test/flutter_test.dart';

const double _pageWidthPt = 144;
const double _pageHeightPt = 144;
const int _rasterWidth = 400;
const int _rasterHeight = 400;

/// A deterministic synthetic grayscale page builder.
///
/// The default page is 144 x 144 pt, which maps to exactly 400 x 400 px at the
/// contract's 200 DPI analysis scale.
final class _Canvas {
  _Canvas({
    this.width = _rasterWidth,
    this.height = _rasterHeight,
    int background = 255,
  }) : _bytes = Uint8List(width * height) {
    _bytes.fillRange(0, _bytes.length, background);
  }

  final int width;
  final int height;
  final Uint8List _bytes;

  void fillRect(int left, int top, int right, int bottom, {int value = 0}) {
    for (int y = top; y < bottom; y++) {
      for (int x = left; x < right; x++) {
        _bytes[y * width + x] = value;
      }
    }
  }

  /// Draws four borders inside `[left, top, right, bottom)`.
  void strokeRect(
    int left,
    int top,
    int right,
    int bottom, {
    int thickness = 2,
  }) {
    fillRect(left, top, right, top + thickness);
    fillRect(left, bottom - thickness, right, bottom);
    fillRect(left, top, left + thickness, bottom);
    fillRect(right - thickness, top, right, bottom);
  }

  GrayRaster build() {
    return GrayRaster.fromGrayBytes(
      width: width,
      height: height,
      bytes: _bytes,
    );
  }
}

/// Maps a pixel edge to display points and rounds once to 1/8 pt, exactly as
/// `recognition-output.md` section 2 requires.
double _edge(int pixel) => (pixel / rasterScale * 8).round() / 8;

DisplayRect _rect(int left, int top, int right, int bottom) {
  final double x = _edge(left);
  final double y = _edge(top);
  return DisplayRect(
    x: x,
    y: y,
    width: _edge(right) - x,
    height: _edge(bottom) - y,
  );
}

List<GeometryCandidate> _detect(
  GrayRaster raster, {
  double pageWidthPt = _pageWidthPt,
  double pageHeightPt = _pageHeightPt,
}) {
  return GeometryDetector.detect(
    raster.analyze(),
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
  );
}

void main() {
  group('ruling lines and underlines', () {
    test('a horizontal rule yields one exact underline candidate', () {
      final _Canvas canvas = _Canvas()..fillRect(100, 200, 200, 202);

      final List<GeometryCandidate> candidates = _detect(canvas.build());

      expect(candidates, hasLength(1));
      expect(
        candidates.single.rect,
        DisplayRect(x: 36, y: 54, width: 36, height: 18),
      );
      expect(candidates.single.cues, <String>['underline']);
      expect(candidates.single.inkCoverage, 0);
    });

    test('a lone vertical rule does not create an underline candidate', () {
      final _Canvas canvas = _Canvas()..fillRect(200, 100, 202, 300);

      expect(_detect(canvas.build()), isEmpty);
    });

    test('rule edges round once to the nearest 1/8 pt', () {
      // Rows 202-203 and columns 101-200 map to non-multiples of 1/8 pt.
      final _Canvas canvas = _Canvas()..fillRect(101, 202, 201, 204);

      final List<GeometryCandidate> candidates = _detect(canvas.build());

      expect(candidates, hasLength(1));
      expect(
        candidates.single.rect,
        DisplayRect(x: 36.375, y: 54.75, width: 36, height: 18),
      );
    });

    test('a page-border rule does not create an underline candidate', () {
      final _Canvas canvas = _Canvas()..fillRect(10, 390, 390, 392);

      expect(_detect(canvas.build()), isEmpty);
    });
  });

  group('boxes and small squares', () {
    test('a closed rectangle yields its interior as a box candidate', () {
      final _Canvas canvas = _Canvas()..strokeRect(100, 75, 204, 177);

      final List<GeometryCandidate> candidates = _detect(canvas.build());

      expect(candidates, hasLength(1));
      expect(candidates.single.rect, _rect(102, 77, 202, 175));
      expect(candidates.single.cues, <String>['box', 'whitespace']);
    });

    test('a 12 pt square also carries the small_square cue', () {
      final _Canvas canvas = _Canvas()..strokeRect(100, 75, 134, 109);

      final List<GeometryCandidate> candidates = _detect(canvas.build());

      expect(candidates, hasLength(1));
      expect(candidates.single.rect, _rect(102, 77, 132, 107));
      expect(candidates.single.cues, <String>[
        'box',
        'small_square',
        'whitespace',
      ]);
    });

    test('distinct overlapping boxes are all returned', () {
      final _Canvas canvas = _Canvas()
        ..strokeRect(100, 100, 300, 200)
        ..strokeRect(150, 130, 250, 170);

      final List<GeometryCandidate> candidates = _detect(canvas.build());

      expect(candidates, hasLength(2));
      final GeometryCandidate outer = candidates.singleWhere(
        (GeometryCandidate candidate) =>
            candidate.rect == _rect(102, 102, 298, 198),
      );
      final GeometryCandidate inner = candidates.singleWhere(
        (GeometryCandidate candidate) =>
            candidate.rect == _rect(152, 132, 248, 168),
      );
      expect(outer.cues, contains('box'));
      expect(inner.cues, contains('box'));
      expect(outer.rect.x, lessThanOrEqualTo(inner.rect.x));
      expect(
        outer.rect.x + outer.rect.width,
        greaterThanOrEqualTo(inner.rect.x + inner.rect.width),
      );
      expect(outer.rect.y, lessThanOrEqualTo(inner.rect.y));
      expect(
        outer.rect.y + outer.rect.height,
        greaterThanOrEqualTo(inner.rect.y + inner.rect.height),
      );
    });

    test('a three-sided shape is not a closed box', () {
      final _Canvas canvas = _Canvas()
        ..fillRect(100, 75, 204, 77)
        ..fillRect(100, 175, 204, 177)
        ..fillRect(100, 75, 102, 177);

      final List<GeometryCandidate> candidates = _detect(canvas.build());

      expect(candidates, isNotEmpty);
      expect(
        candidates.where(
          (GeometryCandidate candidate) => candidate.cues.contains('box'),
        ),
        isEmpty,
      );
      expect(
        candidates.where(
          (GeometryCandidate candidate) =>
              candidate.cues.contains('small_square'),
        ),
        isEmpty,
      );
    });
  });

  group('table grids', () {
    _Canvas gridCanvas({
      required int columns,
      required int rows,
      int left = 100,
      int top = 100,
      int cell = 100,
      int thickness = 2,
    }) {
      final _Canvas canvas = _Canvas(
        width: columns == 3 ? 500 : _rasterWidth,
        height: _rasterHeight,
      );
      final int right = left + columns * cell + thickness;
      final int bottom = top + rows * cell + thickness;
      for (int column = 0; column <= columns; column++) {
        final int x = left + column * cell;
        canvas.fillRect(x, top, x + thickness, bottom);
      }
      for (int row = 0; row <= rows; row++) {
        final int y = top + row * cell;
        canvas.fillRect(left, y, right, y + thickness);
      }
      return canvas;
    }

    List<DisplayRect> expectedCells({
      required int columns,
      required int rows,
      int left = 100,
      int top = 100,
      int cell = 100,
      int thickness = 2,
    }) {
      final List<DisplayRect> rects = <DisplayRect>[];
      for (int row = 0; row < rows; row++) {
        for (int column = 0; column < columns; column++) {
          rects.add(
            _rect(
              left + column * cell + thickness,
              top + row * cell + thickness,
              left + (column + 1) * cell,
              top + (row + 1) * cell,
            ),
          );
        }
      }
      return rects;
    }

    test('a 2 x 2 grid yields four exact cell candidates', () {
      final _Canvas canvas = gridCanvas(columns: 2, rows: 2);

      final List<GeometryCandidate> candidates = _detect(canvas.build());

      expect(candidates, hasLength(4));
      expect(
        candidates.map((GeometryCandidate candidate) => candidate.rect),
        expectedCells(columns: 2, rows: 2),
      );
      for (final GeometryCandidate candidate in candidates) {
        expect(candidate.cues, <String>[
          'grid_cell',
          'table_cell',
          'whitespace',
        ]);
      }
    });

    test('a 3 x 2 grid yields six exact cell candidates', () {
      final _Canvas canvas = gridCanvas(columns: 3, rows: 2);

      final List<GeometryCandidate> candidates = _detect(
        canvas.build(),
        pageWidthPt: 180,
      );

      expect(candidates, hasLength(6));
      expect(
        candidates.map((GeometryCandidate candidate) => candidate.rect),
        expectedCells(columns: 3, rows: 2),
      );
      for (final GeometryCandidate candidate in candidates) {
        expect(candidate.cues, <String>[
          'grid_cell',
          'table_cell',
          'whitespace',
        ]);
      }
    });
  });

  group('whitespace', () {
    test('a bounded empty region yields one whitespace candidate', () {
      final _Canvas canvas = _Canvas()..strokeRect(100, 75, 204, 177);

      final List<GeometryCandidate> candidates = _detect(canvas.build());

      expect(candidates, hasLength(1));
      expect(candidates.single.cues, contains('whitespace'));
      expect(candidates.single.rect, _rect(102, 77, 202, 175));
    });

    test('a blank page yields no whitespace candidate', () {
      final _Canvas canvas = _Canvas();

      expect(_detect(canvas.build()), isEmpty);
    });

    test('background touching a page margin is not a whitespace candidate', () {
      final _Canvas canvas = _Canvas()..fillRect(100, 25, 300, 27);

      expect(_detect(canvas.build()), isEmpty);
    });
  });

  group('alignment', () {
    test('three left-aligned candidates carry alignment_left', () {
      final _Canvas canvas = _Canvas()
        ..fillRect(100, 200, 200, 202)
        ..fillRect(100, 260, 200, 262)
        ..fillRect(100, 320, 200, 322);

      final List<GeometryCandidate> candidates = _detect(canvas.build());

      expect(candidates, hasLength(3));
      for (final GeometryCandidate candidate in candidates) {
        expect(candidate.cues, <String>['alignment_left', 'underline']);
        expect(candidate.rect.x, _edge(100));
      }
    });

    test('one unaligned candidate does not carry alignment_left', () {
      final _Canvas canvas = _Canvas()..fillRect(100, 200, 200, 202);

      final List<GeometryCandidate> candidates = _detect(canvas.build());

      expect(candidates, hasLength(1));
      expect(candidates.single.cues, <String>['underline']);
    });

    test('an external vertical rule can establish alignment_left', () {
      final _Canvas canvas = _Canvas()
        ..fillRect(100, 200, 200, 202)
        ..fillRect(100, 260, 102, 360);

      final List<GeometryCandidate> candidates = _detect(canvas.build());

      expect(candidates, hasLength(1));
      expect(candidates.single.cues, <String>['alignment_left', 'underline']);
    });
  });

  group('ink gate', () {
    test('a box whose interior exceeds 12 % ink is rejected', () {
      final _Canvas canvas = _Canvas()
        ..strokeRect(100, 100, 302, 202)
        ..fillRect(102, 140, 300, 160);

      final List<GeometryCandidate> candidates = _detect(canvas.build());

      expect(
        candidates.where(
          (GeometryCandidate candidate) => candidate.cues.contains('box'),
        ),
        isEmpty,
      );
      expect(
        candidates.where(
          (GeometryCandidate candidate) =>
              candidate.rect == _rect(102, 102, 300, 200),
        ),
        isEmpty,
      );
    });

    test('a small_square above 12 % ink is retained', () {
      final _Canvas canvas = _Canvas()
        ..strokeRect(100, 75, 134, 109)
        ..fillRect(102, 90, 132, 94);

      final List<GeometryCandidate> candidates = _detect(canvas.build());
      final GeometryCandidate square = candidates.singleWhere(
        (GeometryCandidate candidate) =>
            candidate.cues.contains('small_square'),
      );

      expect(square.rect, _rect(102, 77, 132, 107));
      expect(square.cues, contains('box'));
      expect(square.inkCoverage, greaterThan(0.12));
    });
  });

  group('page bounds and failure behavior', () {
    test(
      'a candidate touching the raster right edge is clamped to the page',
      () {
        final _Canvas canvas = _Canvas(width: 278, height: 278)
          ..fillRect(100, 200, 278, 202);

        final List<GeometryCandidate> candidates = _detect(
          canvas.build(),
          pageWidthPt: 100,
          pageHeightPt: 100,
        );

        expect(candidates, hasLength(1));
        expect(
          candidates.single.rect,
          DisplayRect(x: 36, y: 54, width: 64, height: 18),
        );
        final DisplayRect rect = candidates.single.rect;
        expect(rect.x, greaterThanOrEqualTo(0));
        expect(rect.y, greaterThanOrEqualTo(0));
        expect(rect.x + rect.width, lessThanOrEqualTo(100));
        expect(rect.y + rect.height, lessThanOrEqualTo(100));
      },
    );

    test('an all-white page returns an empty list', () {
      expect(_detect(_Canvas().build()), isEmpty);
    });

    test('an all-ink page returns an empty list', () {
      expect(_detect(_Canvas(background: 0).build()), isEmpty);
    });

    test('a raster/page-size mismatch is rejected without content', () {
      final _Canvas canvas = _Canvas();

      expect(
        () => _detect(canvas.build(), pageWidthPt: 100, pageHeightPt: 100),
        throwsArgumentError,
      );
    });
  });

  group('determinism and value types', () {
    test('two calls on the same input are deeply equal', () {
      final GrayRaster raster =
          (_Canvas()
                ..strokeRect(100, 100, 202, 202)
                ..strokeRect(250, 100, 352, 202))
              .build();

      final List<GeometryCandidate> first = _detect(raster);
      final List<GeometryCandidate> second = _detect(raster);

      expect(first, isNotEmpty);
      expect(second, equals(first));
      expect(() => first.add(first.first), throwsUnsupportedError);
      expect(() => first.first.cues.add('box'), throwsUnsupportedError);
    });

    test('the same bytes in different list types are equivalent input', () {
      final _Canvas canvas = _Canvas()..strokeRect(100, 75, 204, 177);
      final Uint8List bytes = Uint8List.fromList(canvas.build().pixels);

      final GrayRaster first = GrayRaster.fromGrayBytes(
        width: _rasterWidth,
        height: _rasterHeight,
        bytes: bytes,
      );
      final GrayRaster second = GrayRaster.fromGrayBytes(
        width: _rasterWidth,
        height: _rasterHeight,
        bytes: List<int>.of(bytes),
      );

      expect(_detect(second), equals(_detect(first)));
    });

    test('display rect and candidate have value equality', () {
      const String cuesA = 'box';
      final DisplayRect rect = DisplayRect(x: 1, y: 2, width: 3, height: 4);
      final GeometryCandidate first = GeometryCandidate(
        rect: rect,
        cues: <String>[cuesA, 'whitespace', cuesA],
        inkCoverage: 0.05,
      );
      final GeometryCandidate second = GeometryCandidate(
        rect: DisplayRect(x: 1, y: 2, width: 3, height: 4),
        cues: <String>['whitespace', cuesA],
        inkCoverage: 0.05,
      );

      expect(first.rect, second.rect);
      expect(first.cues, <String>['box', 'whitespace']);
      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });
}
