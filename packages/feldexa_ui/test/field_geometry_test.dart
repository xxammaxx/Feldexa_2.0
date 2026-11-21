// T071B pure touch-geometry host tests.
//
// Evidence class: NONE. These are host-VM unit and widget tests. They open no
// PDF, start no browser, emulator, or device, and make no Android runtime,
// screen-reader, or visual claim. Real Android acceptance stays T071.
//
// They prove `contracts/editor-interactions.md` §4 geometry arithmetic:
//   * the view delta is divided by the current scale exactly once, at 0.5×,
//     1×, 3×, and 8×, and the same mapping holds for every handle;
//   * a body drag moves the field and is clamped to the page without resizing;
//   * a corner/edge drag resizes from the exact opposite anchor with a free
//     aspect ratio, a 4 × 4 pt minimum, and page clamping;
//   * handle and edge hit regions are at least 24 dp in view space while the
//     stored rectangle and the 6 px visual handles stay untouched;
//   * one gesture produces at most one change, and a discarded preview commits
//     nothing;
//   * the preview surface is pointer-inert paint driven by the normative
//     `layoutFieldOverlay` mapping.

@TestOn('vm')
library;

import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ui/feldexa_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Rect _pageBox = Rect.fromLTWH(0, 0, 300, 300);
const Rect _startRect = Rect.fromLTWH(40, 60, 120, 90);
const List<double> _scales = <double>[0.5, 1, 3, 8];

FieldGeometrySession _session(
  FieldGeometryHandle handle, {
  double scale = 1,
  Rect startRect = _startRect,
  Rect pageBox = _pageBox,
}) {
  return FieldGeometrySession.start(
    fieldId: 'field-1',
    handle: handle,
    startRect: startRect,
    pageBox: pageBox,
    scale: scale,
  );
}

void main() {
  group('mapViewDeltaToDisplay', () {
    for (final double scale in _scales) {
      test('divides the view delta once at ${scale}x', () {
        final Offset display = mapViewDeltaToDisplay(
          viewDelta: Offset(21 * scale, -13 * scale),
          scale: scale,
        );
        expect(display.dx, closeTo(21, 1e-9));
        expect(display.dy, closeTo(-13, 1e-9));
      });
    }

    test('rejects a non-positive or non-finite scale', () {
      expect(
        () => mapViewDeltaToDisplay(viewDelta: Offset.zero, scale: 0),
        throwsArgumentError,
      );
      expect(
        () => mapViewDeltaToDisplay(viewDelta: Offset.zero, scale: -1),
        throwsArgumentError,
      );
      expect(
        () => mapViewDeltaToDisplay(viewDelta: Offset.zero, scale: double.nan),
        throwsArgumentError,
      );
    });

    test('rejects a non-finite delta', () {
      expect(
        () => mapViewDeltaToDisplay(
          viewDelta: const Offset(double.infinity, 0),
          scale: 1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('body drag (move)', () {
    for (final double scale in _scales) {
      test('moves by the scaled delta without resizing at ${scale}x', () {
        final FieldGeometrySession session = _session(
          FieldGeometryHandle.body,
          scale: scale,
        );
        final Rect preview = session.update(Offset(24 * scale, 18 * scale));
        expect(preview.left, closeTo(_startRect.left + 24, 1e-9));
        expect(preview.top, closeTo(_startRect.top + 18, 1e-9));
        expect(preview.size, _startRect.size);
        expect(session.hasChanged, isTrue);

        final FieldGeometryChange? change = session.commit();
        expect(change, isNotNull);
        expect(change!.kind, FieldGeometryEditKind.move);
        expect(change.rect, preview);
        expect(change.previousRect, _startRect);
      });
    }

    test('clamps to the page while keeping the exact size', () {
      final FieldGeometrySession session = _session(FieldGeometryHandle.body);
      expect(
        session.update(const Offset(-1000, -1000)),
        const Rect.fromLTWH(0, 0, 120, 90),
      );
      expect(
        session.update(const Offset(1000, 1000)),
        const Rect.fromLTWH(180, 210, 120, 90),
      );
    });

    test('an unchanged drag commits nothing', () {
      final FieldGeometrySession session = _session(FieldGeometryHandle.body);
      session.update(Offset.zero);
      expect(session.hasChanged, isFalse);
      expect(session.commit(), isNull);
    });

    test('cancel restores the stored rectangle and commits nothing', () {
      final FieldGeometrySession session = _session(FieldGeometryHandle.body);
      session.update(const Offset(30, 30));
      expect(session.hasChanged, isTrue);
      session.cancel();
      expect(session.previewRect, _startRect);
      expect(session.commit(), isNull);
    });

    test('the preview always derives from the start rectangle', () {
      final FieldGeometrySession session = _session(FieldGeometryHandle.body);
      session.update(const Offset(30, 0));
      session.update(const Offset(0, 40));
      // The second update is cumulative, so no frame-by-frame drift appears.
      expect(session.previewRect, _startRect.shift(const Offset(0, 40)));
    });
  });

  group('handle drag (resize)', () {
    test('every corner keeps the opposite corner exactly fixed', () {
      const Rect start = Rect.fromLTWH(100, 100, 80, 60);
      final Map<FieldGeometryHandle, Offset> corners =
          <FieldGeometryHandle, Offset>{
            FieldGeometryHandle.topLeft: start.bottomRight,
            FieldGeometryHandle.topRight: start.bottomLeft,
            FieldGeometryHandle.bottomLeft: start.topRight,
            FieldGeometryHandle.bottomRight: start.topLeft,
          };
      for (final MapEntry<FieldGeometryHandle, Offset> entry
          in corners.entries) {
        final FieldGeometrySession session = _session(
          entry.key,
          startRect: start,
        );
        final Rect preview = session.update(const Offset(-6, -8));
        switch (entry.key) {
          case FieldGeometryHandle.topLeft:
            expect(preview.bottomRight, entry.value);
          case FieldGeometryHandle.topRight:
            expect(preview.bottomLeft, entry.value);
          case FieldGeometryHandle.bottomLeft:
            expect(preview.topRight, entry.value);
          case FieldGeometryHandle.bottomRight:
            expect(preview.topLeft, entry.value);
          case FieldGeometryHandle.body:
          case FieldGeometryHandle.topCenter:
          case FieldGeometryHandle.centerLeft:
          case FieldGeometryHandle.centerRight:
          case FieldGeometryHandle.bottomCenter:
            fail('not a corner');
        }
        expect(session.commit()!.kind, FieldGeometryEditKind.resize);
      }
    });

    test('each edge drag moves only its own edge', () {
      final FieldGeometrySession left = _session(
        FieldGeometryHandle.centerLeft,
      );
      final Rect leftPreview = left.update(const Offset(-10, 25));
      expect(leftPreview.left, _startRect.left - 10);
      expect(leftPreview.right, _startRect.right);
      expect(leftPreview.top, _startRect.top);
      expect(leftPreview.bottom, _startRect.bottom);

      final FieldGeometrySession top = _session(FieldGeometryHandle.topCenter);
      final Rect topPreview = top.update(const Offset(25, 10));
      expect(topPreview.top, _startRect.top + 10);
      expect(topPreview.bottom, _startRect.bottom);
      expect(topPreview.left, _startRect.left);
      expect(topPreview.right, _startRect.right);

      final FieldGeometrySession right = _session(
        FieldGeometryHandle.centerRight,
      );
      expect(right.update(const Offset(10, 0)).right, _startRect.right + 10);

      final FieldGeometrySession bottom = _session(
        FieldGeometryHandle.bottomCenter,
      );
      expect(bottom.update(const Offset(0, 10)).bottom, _startRect.bottom + 10);
    });

    test('the minimum size is 4 x 4 pt against the anchor', () {
      final FieldGeometrySession session = _session(
        FieldGeometryHandle.topLeft,
      );
      final Rect preview = session.update(const Offset(1000, 1000));
      expect(preview.width, fieldGeometryMinSize);
      expect(preview.height, fieldGeometryMinSize);
      expect(preview.bottomRight, _startRect.bottomRight);
      expect(preview.left, _startRect.right - fieldGeometryMinSize);
      expect(preview.top, _startRect.bottom - fieldGeometryMinSize);
    });

    test('the minimum size applies on the opposite diagonal too', () {
      final FieldGeometrySession session = _session(
        FieldGeometryHandle.bottomRight,
      );
      final Rect preview = session.update(const Offset(-1000, -1000));
      expect(preview.width, fieldGeometryMinSize);
      expect(preview.height, fieldGeometryMinSize);
      expect(preview.topLeft, _startRect.topLeft);
    });

    for (final double scale in _scales) {
      test('resize deltas use the same scale mapping at ${scale}x', () {
        final FieldGeometrySession session = _session(
          FieldGeometryHandle.bottomRight,
          scale: scale,
        );
        final Rect preview = session.update(Offset(20 * scale, 10 * scale));
        expect(preview.width, closeTo(_startRect.width + 20, 1e-9));
        expect(preview.height, closeTo(_startRect.height + 10, 1e-9));
        expect(preview.topLeft, _startRect.topLeft);
      });
    }

    test('resizing clamps to the page box', () {
      final FieldGeometrySession session = _session(
        FieldGeometryHandle.bottomRight,
      );
      final Rect preview = session.update(const Offset(1000, 1000));
      expect(preview.right, _pageBox.right);
      expect(preview.bottom, _pageBox.bottom);
      expect(preview.topLeft, _startRect.topLeft);

      final FieldGeometrySession back = _session(
        FieldGeometryHandle.bottomRight,
      );
      final Rect negative = back.update(const Offset(-1000, -1000));
      expect(negative.topLeft, _startRect.topLeft);
      expect(negative.width, fieldGeometryMinSize);
      expect(negative.height, fieldGeometryMinSize);
    });

    test('a body handle falls back to the move rule', () {
      expect(
        resizeFieldRect(
          startRect: _startRect,
          handle: FieldGeometryHandle.body,
          displayDelta: const Offset(5, 6),
          pageBox: _pageBox,
        ),
        _startRect.shift(const Offset(5, 6)),
      );
    });
  });

  group('hitTestFieldGeometry', () {
    const Rect viewRect = Rect.fromLTWH(100, 100, 120, 90);

    test('corner regions reach 12 dp out and no further', () {
      for (final (FieldGeometryHandle handle, Offset corner, Offset out)
          in <(FieldGeometryHandle, Offset, Offset)>[
            (
              FieldGeometryHandle.topLeft,
              viewRect.topLeft,
              const Offset(-1, -1),
            ),
            (
              FieldGeometryHandle.topRight,
              viewRect.topRight,
              const Offset(1, -1),
            ),
            (
              FieldGeometryHandle.bottomLeft,
              viewRect.bottomLeft,
              const Offset(-1, 1),
            ),
            (
              FieldGeometryHandle.bottomRight,
              viewRect.bottomRight,
              const Offset(1, 1),
            ),
          ]) {
        expect(
          hitTestFieldGeometry(viewRect: viewRect, viewPoint: corner),
          handle,
        );
        expect(
          hitTestFieldGeometry(
            viewRect: viewRect,
            viewPoint: corner + out * 11.5,
          ),
          handle,
        );
        expect(
          hitTestFieldGeometry(
            viewRect: viewRect,
            viewPoint: corner + out * 13,
          ),
          isNull,
        );
      }
    });

    test('edge regions are 24 dp thick at the edge midpoint', () {
      expect(
        hitTestFieldGeometry(
          viewRect: viewRect,
          viewPoint: Offset(viewRect.center.dx, viewRect.top - 11.5),
        ),
        FieldGeometryHandle.topCenter,
      );
      expect(
        hitTestFieldGeometry(
          viewRect: viewRect,
          viewPoint: Offset(viewRect.center.dx, viewRect.bottom + 11.5),
        ),
        FieldGeometryHandle.bottomCenter,
      );
      expect(
        hitTestFieldGeometry(
          viewRect: viewRect,
          viewPoint: Offset(viewRect.left - 11.5, viewRect.center.dy),
        ),
        FieldGeometryHandle.centerLeft,
      );
      expect(
        hitTestFieldGeometry(
          viewRect: viewRect,
          viewPoint: Offset(viewRect.right + 11.5, viewRect.center.dy),
        ),
        FieldGeometryHandle.centerRight,
      );
    });

    test('the body is a move target only when requested', () {
      expect(
        hitTestFieldGeometry(viewRect: viewRect, viewPoint: viewRect.center),
        FieldGeometryHandle.body,
      );
      expect(
        hitTestFieldGeometry(
          viewRect: viewRect,
          viewPoint: viewRect.center,
          includeBody: false,
        ),
        isNull,
      );
    });

    test('a miss, an unusable rectangle, or a bad hit size yields null', () {
      expect(
        hitTestFieldGeometry(
          viewRect: viewRect,
          viewPoint: viewRect.center + const Offset(200, 200),
        ),
        isNull,
      );
      expect(
        hitTestFieldGeometry(
          viewRect: Rect.fromLTWH(100, 100, 0, 90),
          viewPoint: const Offset(100, 100),
        ),
        isNull,
      );
      expect(
        hitTestFieldGeometry(
          viewRect: viewRect,
          viewPoint: const Offset(double.infinity, 0),
        ),
        isNull,
      );
      expect(
        () => hitTestFieldGeometry(
          viewRect: viewRect,
          viewPoint: viewRect.center,
          hitSize: 0,
        ),
        throwsArgumentError,
      );
    });

    test('a small field still resolves to a handle, never the body first', () {
      const Rect tiny = Rect.fromLTWH(10, 10, 5, 5);
      expect(
        hitTestFieldGeometry(viewRect: tiny, viewPoint: tiny.center),
        FieldGeometryHandle.topLeft,
      );
    });

    test('hit testing never changes the stored rectangle', () {
      final FieldOverlayItem item = FieldOverlayItem(
        id: 'field-1',
        pageIndex: 0,
        rect: _startRect.toCoreRect(),
        provenance: FieldOverlayProvenance.user,
      );
      final FieldOverlayLayout layout = layoutFieldOverlay(
        items: <FieldOverlayItem>[item],
        pageSize: const Size(300, 300),
        pageRect: const Rect.fromLTWH(0, 0, 600, 600),
      ).single;
      hitTestFieldGeometry(
        viewRect: layout.viewRect,
        viewPoint: layout.viewRect.topLeft,
      );
      expect(item.rect, _startRect.toCoreRect());
      expect(layout.viewRect, const Rect.fromLTWH(80, 120, 240, 180));
    });
  });

  group('FieldGeometryPreview', () {
    testWidgets('paints a pointer-inert preview and nothing without a rect', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              height: 600,
              child: FieldGeometryPreview(
                previewRect: const Rect.fromLTWH(40, 60, 120, 90),
                pageSize: const Size(300, 300),
                pageRect: const Rect.fromLTWH(0, 0, 600, 600),
                accentColor: const Color(0xFF1565C0),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(FieldGeometryPreview),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
      expect(find.byType(IgnorePointer), findsOneWidget);

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: FieldGeometryPreview(
            previewRect: null,
            pageSize: Size(300, 300),
            pageRect: Rect.fromLTWH(0, 0, 600, 600),
            accentColor: Color(0xFF1565C0),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(IgnorePointer), findsNothing);
    });
  });
}

extension on Rect {
  /// The stored model rectangle with the same edges.
  core.Rect toCoreRect() => core.Rect.fromLTWH(left, top, width, height);
}
