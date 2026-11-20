// T077 field-selection tests.
//
// Host-VM tests (evidence class NONE) pin the selection rules from
// `contracts/editor-interactions.md` §2/§4/§11, FR-031/FR-034/FR-094, and
// SC-017:
//   * hit testing maps stored rects through `layoutFieldOverlay`, tests only
//     visible clipped rects, returns the later paint-order item on overlap,
//     and is pure;
//   * the controller notifies only on real selection changes and reconciles
//     deleted ids;
//   * the highlight paints only the selected clipped rect with a 2 dp accent
//     outline and four clamped 6 × 6 handles, and exposes one selected
//     semantics node with the caller label;
//   * the surface selects on a field tap, clears on an empty-page tap, and
//     does not swallow child pointer regions outside the page;
//   * 200% text scale does not change selection geometry.
//
// No Android, TalkBack, visual, golden, or app-composition claim is made.

import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ui/feldexa_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

const Size _pageSize = Size(100, 100);
const Rect _pageRect = Rect.fromLTWH(0, 0, 100, 100);
const Key _childKey = ValueKey<String>('selection-surface-child');

core.Rect _storedRect({
  double left = 10,
  double top = 20,
  double width = 30,
  double height = 40,
}) {
  return core.Rect.fromLTWH(left, top, width, height);
}

FieldOverlayItem _item({
  String id = 'a',
  core.Rect? rect,
  String? semanticLabel = 'Name',
}) {
  return FieldOverlayItem(
    id: id,
    pageIndex: 0,
    rect: rect ?? _storedRect(),
    provenance: FieldOverlayProvenance.machineSuggestion,
    confidence: 0.82,
    semanticLabel: semanticLabel,
  );
}

FieldSelectionPainter _painter({
  List<FieldOverlayItem>? items,
  String? selectedId = 'a',
  Size pageSize = _pageSize,
  Rect pageRect = _pageRect,
  Color accentColor = Colors.pink,
}) {
  return FieldSelectionPainter(
    items: items ?? <FieldOverlayItem>[_item()],
    selectedId: selectedId,
    pageSize: pageSize,
    pageRect: pageRect,
    accentColor: accentColor,
  );
}

void main() {
  group('hitTestFieldSelection', () {
    test('returns the field containing the view point', () {
      final FieldOverlayItem item = _item(
        id: 'inside',
        rect: _storedRect(left: 10, top: 20, width: 30, height: 40),
      );

      expect(
        hitTestFieldSelection(
          items: <FieldOverlayItem>[item],
          pageSize: _pageSize,
          pageRect: _pageRect,
          viewPoint: const Offset(15, 25),
        ),
        same(item),
      );
      expect(
        hitTestFieldSelection(
          items: <FieldOverlayItem>[item],
          pageSize: _pageSize,
          pageRect: _pageRect,
          viewPoint: const Offset(39, 59),
        ),
        same(item),
      );
      expect(
        hitTestFieldSelection(
          items: <FieldOverlayItem>[item],
          pageSize: _pageSize,
          pageRect: _pageRect,
          viewPoint: const Offset(5, 5),
        ),
        isNull,
      );
    });

    test('returns the later item when fields overlap', () {
      final FieldOverlayItem lower = _item(
        id: 'lower',
        rect: _storedRect(left: 10, top: 10, width: 40, height: 40),
      );
      final FieldOverlayItem upper = _item(
        id: 'upper',
        rect: _storedRect(left: 20, top: 20, width: 40, height: 40),
      );

      expect(
        hitTestFieldSelection(
          items: <FieldOverlayItem>[lower, upper],
          pageSize: _pageSize,
          pageRect: _pageRect,
          viewPoint: const Offset(25, 25),
        ),
        same(upper),
      );
      expect(
        hitTestFieldSelection(
          items: <FieldOverlayItem>[lower, upper],
          pageSize: _pageSize,
          pageRect: _pageRect,
          viewPoint: const Offset(12, 12),
        ),
        same(lower),
      );
    });

    test(
      'returns null for empty items, unusable pages, and outside points',
      () {
        final FieldOverlayItem item = _item();

        expect(
          hitTestFieldSelection(
            items: const <FieldOverlayItem>[],
            pageSize: _pageSize,
            pageRect: _pageRect,
            viewPoint: const Offset(15, 25),
          ),
          isNull,
        );

        for (final Size pageSize in <Size>[
          Size.zero,
          const Size(-1, 10),
          const Size(10, -1),
          const Size(double.nan, 10),
          const Size(10, double.infinity),
        ]) {
          expect(
            hitTestFieldSelection(
              items: <FieldOverlayItem>[item],
              pageSize: pageSize,
              pageRect: _pageRect,
              viewPoint: const Offset(15, 25),
            ),
            isNull,
            reason: '$pageSize must be a miss',
          );
        }

        for (final Rect pageRect in <Rect>[
          const Rect.fromLTWH(0, 0, 0, 100),
          const Rect.fromLTWH(0, 0, 100, 0),
          const Rect.fromLTWH(10, 10, -5, 50),
        ]) {
          expect(
            hitTestFieldSelection(
              items: <FieldOverlayItem>[item],
              pageSize: _pageSize,
              pageRect: pageRect,
              viewPoint: const Offset(15, 25),
            ),
            isNull,
            reason: '$pageRect must be a miss',
          );
        }

        expect(
          hitTestFieldSelection(
            items: <FieldOverlayItem>[item],
            pageSize: _pageSize,
            pageRect: const Rect.fromLTWH(50, 50, 100, 100),
            viewPoint: const Offset(10, 10),
          ),
          isNull,
        );
        expect(
          hitTestFieldSelection(
            items: <FieldOverlayItem>[
              _item(
                id: 'outside',
                rect: _storedRect(left: 150, top: 150, width: 10, height: 10),
              ),
            ],
            pageSize: _pageSize,
            pageRect: _pageRect,
            viewPoint: const Offset(50, 50),
          ),
          isNull,
        );
      },
    );

    test('tests only the clipped rect of a partly clipped field', () {
      // View rect (50, 10, 100, 50) clips to (50, 10, 50, 50).
      final FieldOverlayItem partial = _item(
        id: 'partial',
        rect: _storedRect(left: 50, top: 10, width: 100, height: 50),
      );

      expect(
        hitTestFieldSelection(
          items: <FieldOverlayItem>[partial],
          pageSize: _pageSize,
          pageRect: _pageRect,
          viewPoint: const Offset(75, 20),
        ),
        same(partial),
      );
      expect(
        hitTestFieldSelection(
          items: <FieldOverlayItem>[partial],
          pageSize: _pageSize,
          pageRect: _pageRect,
          viewPoint: const Offset(40, 20),
        ),
        isNull,
      );
      expect(
        hitTestFieldSelection(
          items: <FieldOverlayItem>[partial],
          pageSize: _pageSize,
          pageRect: _pageRect,
          viewPoint: const Offset(75, 70),
        ),
        isNull,
      );
      expect(
        hitTestFieldSelection(
          items: <FieldOverlayItem>[partial],
          pageSize: _pageSize,
          pageRect: _pageRect,
          viewPoint: const Offset(110, 20),
        ),
        isNull,
      );
      // Half-open containment: the clipped bottom edge is outside.
      expect(
        hitTestFieldSelection(
          items: <FieldOverlayItem>[partial],
          pageSize: _pageSize,
          pageRect: _pageRect,
          viewPoint: const Offset(75, 60),
        ),
        isNull,
      );
    });

    test('does not mutate items, lists, or stored rects', () {
      final FieldOverlayItem item = _item(
        id: 'pure',
        rect: _storedRect(left: 12, top: 34, width: 56, height: 78),
      );
      final core.Rect stored = item.rect;
      final List<FieldOverlayItem> items = <FieldOverlayItem>[item];

      final FieldOverlayItem? hit = hitTestFieldSelection(
        items: items,
        pageSize: _pageSize,
        pageRect: _pageRect,
        viewPoint: const Offset(20, 40),
      );

      expect(hit, same(item));
      expect(items, hasLength(1));
      expect(items.single, same(item));
      expect(identical(item.rect, stored), isTrue);
      expect(item.rect, stored);
      expect(item.selected, isFalse);
      expect(item.semanticLabel, 'Name');
    });
  });

  group('FieldSelectionController', () {
    test(
      'selects, reports membership, and clears with minimal notifications',
      () {
        final FieldSelectionController controller = FieldSelectionController();
        addTearDown(controller.dispose);
        int notifications = 0;
        controller.addListener(() {
          notifications += 1;
        });

        expect(controller.selectedId, isNull);
        expect(controller.isSelected('a'), isFalse);

        controller.select('a');
        expect(controller.selectedId, 'a');
        expect(controller.isSelected('a'), isTrue);
        expect(controller.isSelected('b'), isFalse);
        expect(notifications, 1);

        controller.select('a');
        expect(notifications, 1);

        controller.select('b');
        expect(controller.selectedId, 'b');
        expect(notifications, 2);

        controller.clear();
        expect(controller.selectedId, isNull);
        expect(notifications, 3);

        controller.clear();
        expect(notifications, 3);
      },
    );

    test('reconcile keeps present ids and clears missing ids', () {
      final FieldSelectionController controller = FieldSelectionController();
      addTearDown(controller.dispose);
      int notifications = 0;
      controller.addListener(() {
        notifications += 1;
      });

      controller.reconcile(const <String>[]);
      expect(controller.selectedId, isNull);
      expect(notifications, 0);

      controller.select('a');
      expect(notifications, 1);

      controller.reconcile(<String>['a', 'b']);
      expect(controller.selectedId, 'a');
      expect(notifications, 1);

      controller.reconcile(<String>['b']);
      expect(controller.selectedId, isNull);
      expect(notifications, 2);

      controller.select('c');
      expect(notifications, 3);
      controller.reconcile(<String>['c', 'c']);
      expect(controller.selectedId, 'c');
      expect(notifications, 3);

      controller.reconcile(const <String>[]);
      expect(controller.selectedId, isNull);
      expect(notifications, 4);
    });
  });

  group('FieldSelectionPainter', () {
    test('paints only the selected clipped rect and four 6x6 handles', () {
      final FieldOverlayItem other = _item(
        id: 'other',
        rect: _storedRect(left: 5, top: 5, width: 20, height: 20),
      );
      final FieldOverlayItem selected = _item(
        id: 'selected',
        rect: _storedRect(left: 10, top: 20, width: 30, height: 40),
      );
      final FieldSelectionPainter painter = _painter(
        items: <FieldOverlayItem>[other, selected],
        selectedId: 'selected',
      );
      final _RecordingCanvas canvas = _RecordingCanvas();

      painter.paint(canvas, _pageSize);

      final List<_RecordedInvocation> clips = canvas.calls
          .where((_RecordedInvocation call) => call.memberName == #clipRect)
          .toList();
      expect(clips, hasLength(1));
      expect(clips.single.positionalArguments[0], _pageRect);

      final List<_RecordedInvocation> drawRects = canvas.calls
          .where((_RecordedInvocation call) => call.memberName == #drawRect)
          .toList();
      expect(drawRects, hasLength(5));

      expect(
        drawRects[0].positionalArguments[0],
        const Rect.fromLTWH(10, 20, 30, 40),
      );
      final Paint outline = drawRects[0].positionalArguments[1] as Paint;
      expect(outline.style, PaintingStyle.stroke);
      expect(outline.strokeWidth, 2);
      expect(outline.color.toARGB32(), Colors.pink.toARGB32());

      final List<Rect> expectedHandles = <Rect>[
        const Rect.fromLTWH(7, 17, 6, 6),
        const Rect.fromLTWH(37, 17, 6, 6),
        const Rect.fromLTWH(7, 57, 6, 6),
        const Rect.fromLTWH(37, 57, 6, 6),
      ];
      for (int i = 0; i < expectedHandles.length; i += 1) {
        final _RecordedInvocation call = drawRects[i + 1];
        expect(call.positionalArguments[0], expectedHandles[i]);
        final Paint handle = call.positionalArguments[1] as Paint;
        expect(handle.style, PaintingStyle.fill);
        expect(handle.color.toARGB32(), Colors.pink.toARGB32());
      }

      expect(
        drawRects.any(
          (_RecordedInvocation call) =>
              call.positionalArguments[0] == const Rect.fromLTWH(5, 5, 20, 20),
        ),
        isFalse,
      );
      expect(
        canvas.calls.where(
          (_RecordedInvocation call) => call.memberName == #drawLine,
        ),
        isEmpty,
      );
      expect(
        canvas.calls.where(
          (_RecordedInvocation call) => call.memberName == #drawPath,
        ),
        isEmpty,
      );
    });

    test('clips the selected item and clamps handles inside the page', () {
      final FieldOverlayItem clipped = _item(
        id: 'clipped',
        rect: _storedRect(left: 80, top: -10, width: 40, height: 40),
      );
      final FieldSelectionPainter painter = _painter(
        items: <FieldOverlayItem>[clipped],
        selectedId: 'clipped',
      );
      final _RecordingCanvas canvas = _RecordingCanvas();

      painter.paint(canvas, _pageSize);

      final List<_RecordedInvocation> drawRects = canvas.calls
          .where((_RecordedInvocation call) => call.memberName == #drawRect)
          .toList();
      expect(drawRects, hasLength(5));
      // Clipped rect = (80, 0, 20, 30), not the unclipped view rect.
      expect(
        drawRects[0].positionalArguments[0],
        const Rect.fromLTWH(80, 0, 20, 30),
      );

      final List<Rect> expectedHandles = <Rect>[
        const Rect.fromLTWH(77, 0, 6, 6),
        const Rect.fromLTWH(94, 0, 6, 6),
        const Rect.fromLTWH(77, 27, 6, 6),
        const Rect.fromLTWH(94, 27, 6, 6),
      ];
      for (int i = 0; i < expectedHandles.length; i += 1) {
        final Rect handle = drawRects[i + 1].positionalArguments[0] as Rect;
        expect(handle, expectedHandles[i]);
        expect(handle.width, 6);
        expect(handle.height, 6);
        expect(handle.left, greaterThanOrEqualTo(_pageRect.left));
        expect(handle.top, greaterThanOrEqualTo(_pageRect.top));
        expect(handle.right, lessThanOrEqualTo(_pageRect.right));
        expect(handle.bottom, lessThanOrEqualTo(_pageRect.bottom));
      }
    });

    test('no-ops without a matching visible selection or usable page', () {
      final FieldOverlayItem item = _item(id: 'a');
      final FieldOverlayItem invisible = _item(
        id: 'a',
        rect: _storedRect(left: 150, top: 150, width: 10, height: 10),
      );
      final List<FieldSelectionPainter> cases = <FieldSelectionPainter>[
        _painter(items: <FieldOverlayItem>[item], selectedId: null),
        _painter(items: <FieldOverlayItem>[item], selectedId: 'missing'),
        _painter(items: const <FieldOverlayItem>[], selectedId: 'a'),
        _painter(items: <FieldOverlayItem>[item], pageSize: Size.zero),
        _painter(
          items: <FieldOverlayItem>[item],
          pageRect: const Rect.fromLTWH(0, 0, 0, 100),
        ),
        _painter(items: <FieldOverlayItem>[invisible], selectedId: 'a'),
        _painter(
          items: <FieldOverlayItem>[item],
          pageSize: const Size(double.nan, 100),
        ),
      ];

      for (int i = 0; i < cases.length; i += 1) {
        final _RecordingCanvas canvas = _RecordingCanvas();
        cases[i].paint(canvas, _pageSize);
        expect(canvas.calls, isEmpty, reason: 'case $i must not paint');
      }
    });

    test('shouldRepaint tracks selection, rect, accent, and page geometry', () {
      final FieldOverlayItem item = _item(id: 'a');
      final FieldSelectionPainter original = _painter(
        items: <FieldOverlayItem>[item],
        selectedId: 'a',
      );

      expect(original.shouldRepaint(original), isFalse);
      expect(
        _painter(
          items: <FieldOverlayItem>[_item(id: 'a')],
          selectedId: 'a',
        ).shouldRepaint(original),
        isFalse,
      );
      expect(
        _painter(
          items: <FieldOverlayItem>[item],
          selectedId: 'b',
        ).shouldRepaint(original),
        isTrue,
      );
      expect(
        _painter(
          items: <FieldOverlayItem>[
            _item(id: 'a', rect: _storedRect(width: 31)),
          ],
          selectedId: 'a',
        ).shouldRepaint(original),
        isTrue,
      );
      expect(
        _painter(
          items: <FieldOverlayItem>[item],
          selectedId: 'a',
          accentColor: Colors.orange,
        ).shouldRepaint(original),
        isTrue,
      );
      expect(
        _painter(
          items: <FieldOverlayItem>[item],
          selectedId: 'a',
          pageSize: const Size(101, 100),
        ).shouldRepaint(original),
        isTrue,
      );
      expect(
        _painter(
          items: <FieldOverlayItem>[item],
          selectedId: 'a',
          pageRect: const Rect.fromLTWH(1, 0, 100, 100),
        ).shouldRepaint(original),
        isTrue,
      );
      expect(
        _painter(
          items: <FieldOverlayItem>[
            item,
            _item(id: 'b'),
          ],
          selectedId: 'a',
        ).shouldRepaint(original),
        isTrue,
      );
    });
  });

  group('FieldSelectionHighlight', () {
    testWidgets('exposes one selected semantics node with the caller label', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final FieldSelectionController controller = FieldSelectionController();
      addTearDown(controller.dispose);

      try {
        await _pumpHighlight(
          tester,
          controller: controller,
          items: <FieldOverlayItem>[_item(id: 'a')],
          semanticLabel: 'Name field',
        );
        expect(_selectionSemantics(), findsNothing);

        controller.select('a');
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(_selectionSemantics(), findsOneWidget);
        expect(
          tester.getSemantics(_selectionSemantics()),
          matchesSemantics(
            label: 'Name field',
            textDirection: TextDirection.ltr,
            isSelected: true,
            hasSelectedState: true,
          ),
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('is pointer-inert and paints only the selected item', (
      WidgetTester tester,
    ) async {
      final FieldSelectionController controller = FieldSelectionController()
        ..select('a');
      addTearDown(controller.dispose);

      await _pumpHighlight(
        tester,
        controller: controller,
        items: <FieldOverlayItem>[
          _item(id: 'a'),
          _item(
            id: 'b',
            rect: _storedRect(left: 50, top: 50, width: 20, height: 20),
          ),
        ],
      );
      expect(tester.takeException(), isNull);

      final Finder ignoreFinder = find.descendant(
        of: find.byType(FieldSelectionHighlight),
        matching: find.byType(IgnorePointer),
      );
      expect(ignoreFinder, findsOneWidget);
      expect(tester.widget<IgnorePointer>(ignoreFinder).ignoring, isTrue);

      final Finder paintFinder = find.descendant(
        of: find.byType(FieldSelectionHighlight),
        matching: find.byType(CustomPaint),
      );
      expect(paintFinder, findsOneWidget);
      final CustomPaint customPaint = tester.widget<CustomPaint>(paintFinder);
      final FieldSelectionPainter painter =
          customPaint.painter! as FieldSelectionPainter;
      expect(painter.selectedId, 'a');
      expect(painter.items, hasLength(1));
      expect(painter.items.single.id, 'a');
      expect(customPaint.child, isA<SizedBox>());
    });

    testWidgets('a missing or empty-page selection paints nothing', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final FieldSelectionController controller = FieldSelectionController()
        ..select('deleted');
      addTearDown(controller.dispose);

      try {
        await _pumpHighlight(
          tester,
          controller: controller,
          items: <FieldOverlayItem>[_item(id: 'a')],
        );

        expect(tester.takeException(), isNull);
        expect(_selectionSemantics(), findsNothing);
        final CustomPaint customPaint = tester.widget<CustomPaint>(
          find.descendant(
            of: find.byType(FieldSelectionHighlight),
            matching: find.byType(CustomPaint),
          ),
        );
        final FieldSelectionPainter painter =
            customPaint.painter! as FieldSelectionPainter;
        expect(painter.selectedId, isNull);
        expect(painter.items, isEmpty);

        await _pumpHighlight(
          tester,
          controller: controller,
          items: <FieldOverlayItem>[_item(id: 'a')],
          pageSize: Size.zero,
          pageRect: const Rect.fromLTWH(0, 0, 0, 0),
        );
        expect(tester.takeException(), isNull);
        expect(_selectionSemantics(), findsNothing);
      } finally {
        handle.dispose();
      }
    });
  });

  group('FieldSelectionSurface', () {
    testWidgets('a tap inside a field selects it and reports the exact item', (
      WidgetTester tester,
    ) async {
      final FieldSelectionController controller = FieldSelectionController();
      addTearDown(controller.dispose);
      final List<FieldOverlayItem> items = <FieldOverlayItem>[
        _item(
          id: 'target',
          rect: _storedRect(left: 20, top: 20, width: 40, height: 40),
        ),
      ];
      final List<FieldOverlayItem?> reported = <FieldOverlayItem?>[];
      int childTaps = 0;

      await _pumpSurface(
        tester,
        controller: controller,
        items: items,
        onSelected: reported.add,
        onChildTap: () {
          childTaps += 1;
        },
      );

      final Offset origin = tester.getTopLeft(find.byKey(_childKey));
      await tester.tapAt(origin + const Offset(80, 80));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(controller.selectedId, 'target');
      expect(reported, hasLength(1));
      expect(identical(reported.single, items.single), isTrue);
      expect(childTaps, 0);
      expect(
        tester.getSize(find.byWidget(_tapSurface(tester))),
        const Size(200, 200),
      );
    });

    testWidgets('a tap on the empty page clears and reports null', (
      WidgetTester tester,
    ) async {
      final FieldSelectionController controller = FieldSelectionController()
        ..select('target');
      addTearDown(controller.dispose);
      final List<FieldOverlayItem> items = <FieldOverlayItem>[
        _item(
          id: 'target',
          rect: _storedRect(left: 20, top: 20, width: 40, height: 40),
        ),
      ];
      final List<FieldOverlayItem?> reported = <FieldOverlayItem?>[];
      int childTaps = 0;

      await _pumpSurface(
        tester,
        controller: controller,
        items: items,
        onSelected: reported.add,
        onChildTap: () {
          childTaps += 1;
        },
      );

      final Offset origin = tester.getTopLeft(find.byKey(_childKey));
      await tester.tapAt(origin + const Offset(200, 200));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(controller.selectedId, isNull);
      expect(reported, <FieldOverlayItem?>[null]);
      expect(childTaps, 0);
    });

    testWidgets('does not swallow child taps outside the page', (
      WidgetTester tester,
    ) async {
      final FieldSelectionController controller = FieldSelectionController()
        ..select('target');
      addTearDown(controller.dispose);
      final List<FieldOverlayItem> items = <FieldOverlayItem>[
        _item(
          id: 'target',
          rect: _storedRect(left: 20, top: 20, width: 40, height: 40),
        ),
      ];
      final List<FieldOverlayItem?> reported = <FieldOverlayItem?>[];
      int childTaps = 0;

      await _pumpSurface(
        tester,
        controller: controller,
        items: items,
        onSelected: reported.add,
        onChildTap: () {
          childTaps += 1;
        },
      );

      final Offset origin = tester.getTopLeft(find.byKey(_childKey));
      // (20, 20) lies outside pageRect (50, 50, 200, 200).
      await tester.tapAt(origin + const Offset(20, 20));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(childTaps, 1);
      expect(controller.selectedId, 'target');
      expect(reported, isEmpty);
      expect(find.byKey(_childKey), findsOneWidget);
      expect(tester.getSize(find.byKey(_childKey)), const Size(400, 600));
    });

    testWidgets('tapping never mutates items or stored geometry', (
      WidgetTester tester,
    ) async {
      final FieldSelectionController controller = FieldSelectionController();
      addTearDown(controller.dispose);
      final FieldOverlayItem item = _item(
        id: 'target',
        rect: _storedRect(left: 20, top: 20, width: 40, height: 40),
      );
      final core.Rect stored = item.rect;
      final List<FieldOverlayItem> items = <FieldOverlayItem>[item];
      final List<FieldOverlayItem?> reported = <FieldOverlayItem?>[];

      await _pumpSurface(
        tester,
        controller: controller,
        items: items,
        onSelected: reported.add,
        onChildTap: () {},
      );

      final Offset origin = tester.getTopLeft(find.byKey(_childKey));
      await tester.tapAt(origin + const Offset(80, 80));
      await tester.pump();
      await tester.tapAt(origin + const Offset(200, 200));
      await tester.pump();
      await tester.tapAt(origin + const Offset(20, 20));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(items, hasLength(1));
      expect(items.single, same(item));
      expect(identical(item.rect, stored), isTrue);
      expect(item.rect, stored);
      expect(item.selected, isFalse);
      expect(item.semanticLabel, 'Name');
      expect(reported, hasLength(2));
      expect(reported.first, same(item));
      expect(reported.last, isNull);
    });

    testWidgets('200% text scale keeps the selection geometry', (
      WidgetTester tester,
    ) async {
      final FieldSelectionController controller = FieldSelectionController()
        ..select('target');
      addTearDown(controller.dispose);
      final FieldOverlayItem item = _item(
        id: 'target',
        rect: _storedRect(left: 20, top: 20, width: 40, height: 40),
      );
      final core.Rect stored = item.rect;
      final List<FieldOverlayItem> items = <FieldOverlayItem>[item];
      final List<FieldOverlayItem?> reported = <FieldOverlayItem?>[];

      await _pumpSurface(
        tester,
        controller: controller,
        items: items,
        onSelected: reported.add,
        onChildTap: () {},
        textScale: 1,
      );
      final List<Rect> normalScale = _paintedRects(tester);

      await _pumpSurface(
        tester,
        controller: controller,
        items: items,
        onSelected: reported.add,
        onChildTap: () {},
        textScale: 2,
      );
      final List<Rect> doubleScale = _paintedRects(tester);

      expect(tester.takeException(), isNull);
      expect(normalScale, isNotEmpty);
      expect(doubleScale, normalScale);
      expect(identical(item.rect, stored), isTrue);

      final Offset origin = tester.getTopLeft(find.byKey(_childKey));
      await tester.tapAt(origin + const Offset(80, 80));
      await tester.pump();
      expect(controller.selectedId, 'target');
      expect(reported, hasLength(1));
      expect(identical(reported.single, item), isTrue);
    });
  });
}

Finder _selectionSemantics() {
  return find.descendant(
    of: find.byType(FieldSelectionHighlight),
    matching: find.byType(Semantics),
  );
}

GestureDetector _tapSurface(WidgetTester tester) {
  return tester
      .widgetList<GestureDetector>(find.byType(GestureDetector))
      .singleWhere((GestureDetector detector) => detector.onTapUp != null);
}

List<Rect> _paintedRects(WidgetTester tester) {
  final Finder paintFinder = find.byWidgetPredicate(
    (Widget widget) =>
        widget is CustomPaint && widget.painter is FieldSelectionPainter,
  );
  expect(paintFinder, findsOneWidget);
  final CustomPaint customPaint = tester.widget<CustomPaint>(paintFinder);
  final _RecordingCanvas canvas = _RecordingCanvas();
  (customPaint.painter! as FieldSelectionPainter).paint(canvas, _pageSize);
  return <Rect>[
    for (final _RecordedInvocation call in canvas.calls)
      if (call.memberName == #drawRect) call.positionalArguments[0] as Rect,
  ];
}

Future<void> _pumpHighlight(
  WidgetTester tester, {
  required FieldSelectionController controller,
  required List<FieldOverlayItem> items,
  String? semanticLabel = 'Name field',
  Size pageSize = _pageSize,
  Rect pageRect = _pageRect,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(400, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 400,
              child: FieldSelectionHighlight(
                controller: controller,
                items: items,
                pageSize: pageSize,
                pageRect: pageRect,
                semanticLabel: semanticLabel,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpSurface(
  WidgetTester tester, {
  required FieldSelectionController controller,
  required List<FieldOverlayItem> items,
  required ValueChanged<FieldOverlayItem?> onSelected,
  required VoidCallback onChildTap,
  Size pageSize = const Size(200, 200),
  Rect pageRect = const Rect.fromLTWH(50, 50, 200, 200),
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(400, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SizedBox.expand(
            child: FieldSelectionSurface(
              controller: controller,
              items: items,
              pageSize: pageSize,
              pageRect: pageRect,
              onSelected: onSelected,
              child: GestureDetector(
                key: _childKey,
                behavior: HitTestBehavior.opaque,
                onTap: onChildTap,
                child: const SizedBox.expand(
                  child: ColoredBox(color: Color(0xFFFFFFFF)),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _RecordedInvocation {
  const _RecordedInvocation(this.memberName, this.positionalArguments);

  final Symbol memberName;
  final List<dynamic> positionalArguments;
}

final class _RecordingCanvas implements Canvas {
  final List<_RecordedInvocation> calls = <_RecordedInvocation>[];

  @override
  void noSuchMethod(Invocation invocation) {
    calls.add(
      _RecordedInvocation(
        invocation.memberName,
        invocation.positionalArguments,
      ),
    );
  }
}
