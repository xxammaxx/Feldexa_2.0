@TestOn('vm')
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:feldexa_app/features/editor/page_view.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart' hide PageView;
import 'package:flutter_test/flutter_test.dart';

/// T042 pdfrx page viewer and source-point geometry mapping.
///
/// These are host-VM and widget tests with a fake renderer seam. They prove
/// the page order, original display sizes, the view ↔ page-display mapping at
/// zoom levels 0.5–8, rotation/CropBox-derived display sizes, DPR
/// independence, lazy page building, source reuse, and content-free failures.
/// They produce no `SIMULATED`, `EMULATOR`, or `DEVICE` evidence.
const String _documentId = '5f0c3a52-3a6a-4f0b-9c2d-1b7e4d8a6c01';
const String _sourceId = '7b2d4c1e-5f3a-4b8c-8a9d-2e6f0c1b3d42';
const String _secondSourceId = '9c4e6a82-1d3b-4f7a-8e2c-5a0b7d9f1e63';
final String _sha256 = List<String>.filled(64, 'a').join();

core.PageGeometry _geometry({
  double width = 595,
  double height = 842,
  int rotation = 0,
  core.Rect? cropBox,
}) {
  return core.PageGeometry(
    mediaBox: core.Rect.fromLTWH(0, 0, width, height),
    cropBox: cropBox,
    rotation: rotation,
  );
}

core.PageGeometry _croppedGeometry(int rotation) {
  return core.PageGeometry(
    mediaBox: core.Rect.fromLTWH(0, 0, 595, 842),
    cropBox: core.Rect.fromLTWH(10, 20, 550, 770),
    rotation: rotation,
  );
}

ImportedSource _source(
  List<core.PageGeometry> pages, {
  String sourceId = _sourceId,
}) {
  return ImportedSource(
    documentId: _documentId,
    sourceId: sourceId,
    sha256: _sha256,
    sizeBytes: 4096,
    pageCount: pages.length,
    pages: pages,
    evidence: CapabilityEvidence.android(adapterId: 'test.fake.viewer.v1'),
  );
}

PageViewPageSize _pageSize(core.PageGeometry geometry) {
  return PageViewPageSize(
    widthPt: geometry.displaySize.width,
    heightPt: geometry.displaySize.height,
  );
}

void _expectClose(double actual, double expected, {double tolerance = 1e-9}) {
  expect(actual, closeTo(expected, tolerance));
}

void _expectOffsetClose(Offset actual, Offset expected) {
  _expectClose(actual.dx, expected.dx);
  _expectClose(actual.dy, expected.dy);
}

void main() {
  group('PageViewLayout', () {
    test('keeps original order, display sizes, and centered page boxes', () {
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[
          _pageSize(_geometry(width: 595, height: 842)),
          _pageSize(_geometry(width: 595, height: 842, rotation: 90)),
          _pageSize(_geometry(width: 420, height: 595)),
        ],
        pageGap: 8,
      );
      final PageViewLayout layout = controller.layout;

      expect(layout.pageCount, 3);
      expect(layout.contentSize, const Size(842, 2048));
      expect(layout.pageRects[0], const Rect.fromLTWH(123.5, 0, 595, 842));
      expect(layout.pageRects[1], const Rect.fromLTWH(0, 850, 842, 595));
      expect(layout.pageRects[2], const Rect.fromLTWH(211, 1453, 420, 595));
      expect(layout.pageSizeFor(1).widthPt, 842);
      expect(layout.pageSizeFor(1).heightPt, 595);
    });

    test('rejects an empty page list, a negative gap, and bad indices', () {
      expect(
        () => PageViewController(pages: const <PageViewPageSize>[]),
        throwsArgumentError,
      );
      expect(
        () => PageViewController(
          pages: <PageViewPageSize>[_pageSize(_geometry())],
          pageGap: -1,
        ),
        throwsArgumentError,
      );
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[_pageSize(_geometry())],
      );
      expect(() => controller.layout.pageSizeFor(1), throwsRangeError);
      expect(() => controller.layout.pageRectFor(-1), throwsRangeError);
      expect(() => controller.mappingFor(1), throwsRangeError);
    });

    test('validates the page display size value itself', () {
      expect(
        () => PageViewPageSize(widthPt: 0, heightPt: 10),
        throwsArgumentError,
      );
      expect(
        () => PageViewPageSize(widthPt: 10, heightPt: double.infinity),
        throwsArgumentError,
      );
    });
  });

  group('PageGeometry.displaySize input', () {
    test('uses the exact display size for all four rotations', () {
      for (final int rotation in <int>[0, 90, 180, 270]) {
        final core.PageGeometry geometry = _croppedGeometry(rotation);
        final PageViewController controller =
            PageViewController.fromImportedSource(
              _source(<core.PageGeometry>[geometry]),
            );
        final PageViewPageSize size = controller.layout.pageSizeFor(0);
        expect(size.widthPt, geometry.displaySize.width);
        expect(size.heightPt, geometry.displaySize.height);
        expect(size.widthPt, rotation == 0 || rotation == 180 ? 550 : 770);
        expect(size.heightPt, rotation == 0 || rotation == 180 ? 770 : 550);
      }
    });

    test('keeps mixed pages independent in document order', () {
      final PageViewController controller =
          PageViewController.fromImportedSource(
            _source(<core.PageGeometry>[
              _geometry(width: 595.28, height: 841.89),
              _croppedGeometry(90),
              _geometry(width: 420, height: 595),
            ]),
          );
      expect(controller.pageCount, 3);
      expect(controller.layout.pageSizeFor(0).widthPt, 595.28);
      expect(controller.layout.pageSizeFor(1).widthPt, 770);
      expect(controller.layout.pageSizeFor(1).heightPt, 550);
      expect(controller.layout.pageSizeFor(2).widthPt, 420);
    });
  });

  group('view transform and hit testing', () {
    test('maps view to display and back at every contract zoom level', () {
      final core.PageGeometry geometry = _croppedGeometry(0);
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[_pageSize(geometry)],
      );
      const Offset display = Offset(100, 50);
      final core.Point expectedPdf = geometry.displayToPdf(
        core.Point(display.dx, display.dy),
      );

      for (final double scale in <double>[0.5, 1, 1.75, 3, 8]) {
        controller.setView(scale: scale, pan: const Offset(37.5, -20.25));
        final Offset view = controller.displayToView(0, display);
        final Offset back = controller.viewToDisplay(0, view);
        _expectOffsetClose(back, display);

        final Offset pdfDisplay = controller.viewToDisplay(0, view);
        final core.Point pdf = geometry.displayToPdf(
          core.Point(pdfDisplay.dx, pdfDisplay.dy),
        );
        _expectClose(pdf.x, expectedPdf.x);
        _expectClose(pdf.y, expectedPdf.y);
      }
      _expectClose(expectedPdf.x, 110);
      _expectClose(expectedPdf.y, 740);
    });

    test('maps a display rectangle without changing its PDF geometry', () {
      final core.PageGeometry geometry = _croppedGeometry(90);
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[_pageSize(geometry)],
      );
      controller.setView(scale: 1.75, pan: const Offset(-40, 25));
      const Rect displayRect = Rect.fromLTWH(100, 50, 120, 20);

      final Rect viewRect = controller.displayRectToView(0, displayRect);
      final Rect back = controller.viewRectToDisplay(0, viewRect);
      _expectClose(back.left, displayRect.left);
      _expectClose(back.top, displayRect.top);
      _expectClose(back.width, displayRect.width);
      _expectClose(back.height, displayRect.height);

      final core.Rect pdfRect = geometry.displayRectToPdf(
        core.Rect.fromLTWH(back.left, back.top, back.width, back.height),
      );
      _expectClose(pdfRect.left, 60);
      _expectClose(pdfRect.top, 120);
      _expectClose(pdfRect.width, 20);
      _expectClose(pdfRect.height, 120);
    });

    test('round-trips all rotations with non-zero CropBox offsets', () {
      const Offset display = Offset(37, 59);
      const Map<int, Offset> expectedPdfByRotation = <int, Offset>{
        0: Offset(47, 731),
        90: Offset(69, 57),
        180: Offset(523, 79),
        270: Offset(501, 753),
      };
      for (final int rotation in <int>[0, 90, 180, 270]) {
        final core.PageGeometry geometry = _croppedGeometry(rotation);
        final PageViewController controller = PageViewController(
          pages: <PageViewPageSize>[_pageSize(geometry)],
        );
        controller.setView(scale: 2.5, pan: const Offset(-123.25, 44.5));
        final Offset view = controller.displayToView(0, display);
        _expectOffsetClose(controller.viewToDisplay(0, view), display);

        final core.Point pdf = geometry.displayToPdf(
          core.Point(display.dx, display.dy),
        );
        final Offset expectedPdf = expectedPdfByRotation[rotation]!;
        _expectClose(pdf.x, expectedPdf.dx);
        _expectClose(pdf.y, expectedPdf.dy);
        final core.Point back = geometry.pdfToDisplay(pdf);
        _expectOffsetClose(
          controller.displayToView(0, Offset(back.x, back.y)),
          view,
        );
      }
    });

    test('uses the contract pan and scale formula directly', () {
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[_pageSize(_geometry())],
      );
      controller.setView(scale: 2, pan: const Offset(-10, 30));
      final PageViewMapping mapping = controller.mappingFor(0);
      _expectOffsetClose(
        mapping.contentToView(const Offset(4, 5)),
        const Offset(-2, 40),
      );
      _expectOffsetClose(
        mapping.viewToContent(const Offset(-2, 40)),
        const Offset(4, 5),
      );
      _expectOffsetClose(
        mapping.pageRectInViewport.topLeft,
        const Offset(-10, 30),
      );
    });

    test('rejects zero-area rectangles', () {
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[_pageSize(_geometry())],
      );
      expect(
        () => controller.viewRectToDisplay(0, Rect.zero),
        throwsArgumentError,
      );
      expect(
        () => controller.displayRectToView(0, Rect.fromLTWH(0, 0, 0, 10)),
        throwsArgumentError,
      );
    });
  });

  group('PageViewController', () {
    test('fit width follows the widest page and the 0.5×–8× bounds', () {
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[
          _pageSize(_geometry(width: 500, height: 1200)),
          _pageSize(_geometry(width: 400, height: 800)),
        ],
      );
      controller.setViewportSize(const Size(400, 800));
      _expectClose(controller.fitWidthScale, 0.8);
      _expectClose(controller.minScale, 0.4);
      _expectClose(controller.maxScale, 6.4);
      _expectClose(controller.scale, 0.8);
      _expectOffsets(controller.pan, const Offset(0, 0));

      controller.setView(scale: 3, pan: const Offset(-100, -200));
      controller.fitWidth();
      _expectClose(controller.scale, 0.8);
    });

    test('fit page uses the tighter dimension ratio', () {
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[
          _pageSize(_geometry(width: 500, height: 1200)),
        ],
      );
      controller.setViewportSize(const Size(400, 800));
      controller.fitPage(0);
      _expectClose(controller.scale, 800 / 1200);
      _expectClose(controller.mappingFor(0).pageRectInViewport.center.dx, 200);
      _expectClose(controller.mappingFor(0).pageRectInViewport.center.dy, 400);
    });

    test('scrollToPage places the page top at the viewport top', () {
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[
          _pageSize(_geometry(width: 100, height: 150)),
          _pageSize(_geometry(width: 100, height: 150)),
          _pageSize(_geometry(width: 100, height: 150)),
        ],
        pageGap: 10,
      );
      controller.setViewportSize(const Size(200, 200));
      controller.scrollToPage(1);
      _expectClose(controller.pan.dy, -320);
      _expectClose(controller.mappingFor(1).pageRectInViewport.top, 0);
      _expectClose(controller.mappingFor(1).pageRectInViewport.center.dx, 100);
    });

    test('hit-tests page indices and rejects the inter-page gap', () {
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[
          _pageSize(_geometry(width: 100, height: 150)),
          _pageSize(_geometry(width: 100, height: 150)),
          _pageSize(_geometry(width: 100, height: 150)),
        ],
        pageGap: 10,
      );
      controller.setViewportSize(const Size(200, 200));
      controller.setView(scale: 1, pan: Offset.zero);
      expect(controller.pageIndexAt(const Offset(50, 75)), 0);
      expect(controller.pageIndexAt(const Offset(50, 160)), 1);
      expect(controller.pageIndexAt(const Offset(50, 155)), isNull);
      expect(controller.pageIndexAt(const Offset(50, 600)), isNull);
    });

    test('does not depend on the device pixel ratio', () {
      // Geometry values are computed from scale and pan only; there is no DPR
      // input to any controller method. This unit-level assertion documents
      // the absence of a DPR parameter; the widget test exercises a DPR change.
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[_pageSize(_geometry())],
      );
      controller.setViewportSize(const Size(400, 800));
      final double scale = controller.scale;
      final Offset view = controller.displayToView(0, const Offset(100, 50));
      _expectClose(scale, 400 / 595);
      _expectClose(controller.viewToDisplay(0, view).dx, 100);
      _expectClose(controller.viewToDisplay(0, view).dy, 50);
    });

    test('rejects invalid viewport and transform values', () {
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[_pageSize(_geometry())],
      );
      expect(() => controller.setViewportSize(Size.zero), throwsArgumentError);
      expect(
        () => controller.setView(scale: 0, pan: Offset.zero),
        throwsArgumentError,
      );
      expect(
        () => controller.setView(scale: 1, pan: const Offset(double.nan, 0)),
        throwsArgumentError,
      );
    });
  });

  group('raster cap and hardening', () {
    test('caps an A3 page at 4096 px on the long edge', () {
      final PageViewPageSize a3 = PageViewPageSize(
        widthPt: 842,
        heightPt: 1191,
      );
      final PageViewRasterPlan plan = PageViewRasterPlan.forPage(
        page: a3,
        viewSize: const Size(842 * 8, 1191 * 8),
        devicePixelRatio: 3,
      );
      expect(math.max(plan.widthPx, plan.heightPx), 4096);
      expect(plan.widthPx, lessThanOrEqualTo(4096));
      expect(plan.heightPx, lessThanOrEqualTo(4096));
      expect(plan.isCapped, isTrue);
      expect(plan.effectiveScale, lessThan(plan.desiredScale));
    });

    test('does not downscale a small page below its DPR size', () {
      final PageViewPageSize small = PageViewPageSize(
        widthPt: 100,
        heightPt: 150,
      );
      final PageViewRasterPlan plan = PageViewRasterPlan.forPage(
        page: small,
        viewSize: const Size(200, 300),
        devicePixelRatio: 2,
      );
      expect(plan.widthPx, 400);
      expect(plan.heightPx, 600);
      expect(plan.isCapped, isFalse);
    });

    test('raster cap leaves view and display mapping unchanged', () {
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[
          PageViewPageSize(widthPt: 842, heightPt: 1191),
        ],
      );
      controller.setViewportSize(const Size(400, 800));
      controller.setView(scale: 4, pan: const Offset(-10, -20));
      final Offset before = controller.viewToDisplay(0, const Offset(200, 300));
      final PageViewRasterPlan plan = PageViewRasterPlan.forPage(
        page: controller.layout.pageSizeFor(0),
        viewSize: const Size(3368, 4764),
        devicePixelRatio: 3,
      );
      expect(plan.isCapped, isTrue);
      expect(controller.viewToDisplay(0, const Offset(200, 300)), before);
      expect(controller.scale, 4);
      expect(controller.pan, const Offset(-10, -20));
    });

    test('fitWidth clamps pan with the target scale after zoom-in', () {
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[
          PageViewPageSize(widthPt: 100, heightPt: 100),
        ],
      );
      controller.setViewportSize(const Size(200, 200));
      controller.setView(scale: 4, pan: const Offset(-150, -150));
      controller.fitWidth();
      _expectClose(controller.scale, 2);
      _expectOffsetClose(controller.pan, Offset.zero);
      final Rect page = controller.mappingFor(0).pageRectInViewport;
      _expectClose(page.left, 0);
      _expectClose(page.width, 200);
      _expectClose(page.top, 0);
    });

    test('rejects an overflowing accumulated page strip', () {
      expect(
        () => PageViewController(
          pages: <PageViewPageSize>[
            PageViewPageSize(widthPt: 10, heightPt: 1e308),
            PageViewPageSize(widthPt: 10, heightPt: 1e308),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects an overflowing transformed rectangle', () {
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[
          PageViewPageSize(widthPt: 100, heightPt: 100),
        ],
      );
      controller.setViewportSize(const Size(200, 200));
      controller.setView(scale: 1e308, pan: Offset.zero);
      expect(
        () =>
            controller.displayRectToView(0, Rect.fromLTWH(0, 0, 1e308, 1e308)),
        throwsArgumentError,
      );
    });
  });

  group('PageView widget', () {
    testWidgets('renders every page in order with its original display size', (
      WidgetTester tester,
    ) async {
      final List<core.PageGeometry> geometries = <core.PageGeometry>[
        _geometry(width: 100, height: 150),
        _geometry(width: 100, height: 150, rotation: 90),
        _geometry(width: 80, height: 120),
      ];
      final PageViewController controller =
          PageViewController.fromImportedSource(_source(geometries));
      final _FakeRendererFactory factory = _FakeRendererFactory(3);
      int sourceCalls = 0;

      await tester.pumpWidget(
        _harness(
          controller: controller,
          factory: factory.call,
          sourceBytes: (String id) async {
            sourceCalls++;
            return _bytes;
          },
        ),
      );
      await tester.pumpAndSettle();
      controller.setView(scale: 1, pan: Offset.zero);
      await tester.pump();

      expect(sourceCalls, 1);
      expect(factory.calls, 1);
      expect(factory.created, hasLength(1));
      expect(factory.created.single.built, <int>{0, 1, 2});
      expect(find.byKey(_pageKey(0)), findsOneWidget);
      expect(find.byKey(_pageKey(1)), findsOneWidget);
      expect(find.byKey(_pageKey(2)), findsOneWidget);

      final Size page0 = tester.getSize(find.byKey(_pageKey(0)));
      final Size page1 = tester.getSize(find.byKey(_pageKey(1)));
      final Size page2 = tester.getSize(find.byKey(_pageKey(2)));
      expect(page0, const Size(100, 150));
      expect(page1, const Size(150, 100));
      expect(page2, const Size(80, 120));

      final Offset origin = tester.getTopLeft(find.byType(PageView));
      final Offset p0 = tester.getTopLeft(find.byKey(_pageKey(0))) - origin;
      final Offset p1 = tester.getTopLeft(find.byKey(_pageKey(1))) - origin;
      final Offset p2 = tester.getTopLeft(find.byKey(_pageKey(2))) - origin;
      _expectOffsetClose(p0, const Offset(25, 0));
      _expectOffsetClose(p1, const Offset(0, 158));
      _expectOffsetClose(p2, const Offset(35, 266));

      final Offset display = controller.viewToDisplay(
        1,
        tester.getCenter(find.byKey(_pageKey(1))) - origin,
      );
      _expectOffsetClose(display, const Offset(75, 50));
      final core.Point pdf = geometries[1].displayToPdf(
        core.Point(display.dx, display.dy),
      );
      _expectClose(pdf.x, 50);
      _expectClose(pdf.y, 75);
    });

    testWidgets('reuses the opened document across rebuilds', (
      WidgetTester tester,
    ) async {
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[_pageSize(_geometry())],
      );
      final _FakeRendererFactory factory = _FakeRendererFactory(1);
      int sourceCalls = 0;

      // A new closure on every build must not reopen the document: the
      // opaque sourceId is the identity, and the document object is created
      // once per source.
      Widget build() => _harness(
        controller: controller,
        factory: factory.call,
        sourceBytes: (String id) async {
          sourceCalls++;
          return _bytes;
        },
      );

      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      await tester.pumpWidget(build());
      await tester.pumpWidget(build());
      await tester.pump();

      expect(sourceCalls, 1);
      expect(factory.calls, 1);
      expect(factory.created.single.built, <int>{0});
    });

    testWidgets('keeps the mapping when the device pixel ratio changes', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[_pageSize(_geometry())],
      );
      final _FakeRendererFactory factory = _FakeRendererFactory(1);

      await tester.pumpWidget(
        _harness(
          controller: controller,
          factory: factory.call,
          sourceBytes: _sourceBytes,
        ),
      );
      await tester.pumpAndSettle();
      final double scale = controller.scale;
      final Offset pan = controller.pan;
      final Offset display = controller.viewToDisplay(
        0,
        controller.displayToView(0, const Offset(100, 50)),
      );

      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(2400, 1800);
      await tester.pumpAndSettle();

      expect(controller.scale, scale);
      expect(controller.pan, pan);
      _expectOffsetClose(
        controller.viewToDisplay(0, controller.displayToView(0, display)),
        display,
      );
    });

    testWidgets('builds only pages intersecting the viewport', (
      WidgetTester tester,
    ) async {
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[
          _pageSize(_geometry(width: 100, height: 150)),
          _pageSize(_geometry(width: 100, height: 150)),
          _pageSize(_geometry(width: 100, height: 150)),
        ],
        pageGap: 8,
      );
      final _FakeRendererFactory factory = _FakeRendererFactory(3);

      await tester.pumpWidget(
        _harness(
          controller: controller,
          factory: factory.call,
          sourceBytes: _sourceBytes,
          sized: const Size(200, 150),
        ),
      );
      await tester.pumpAndSettle();

      expect(factory.created.single.built, <int>{0});
      expect(find.byKey(_pageKey(0)), findsOneWidget);
      expect(find.byKey(_pageKey(1)), findsNothing);

      controller.scrollToPage(2);
      await tester.pump();

      expect(find.byKey(_pageKey(0)), findsNothing);
      expect(find.byKey(_pageKey(2)), findsOneWidget);
    });

    testWidgets('disposes the renderer when the viewer is removed', (
      WidgetTester tester,
    ) async {
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[_pageSize(_geometry())],
      );
      final _FakeRendererFactory factory = _FakeRendererFactory(1);

      await tester.pumpWidget(
        _harness(
          controller: controller,
          factory: factory.call,
          sourceBytes: _sourceBytes,
        ),
      );
      await tester.pumpAndSettle();
      expect(factory.created.single.disposed, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(factory.created.single.disposed, isTrue);
    });

    testWidgets('reopens on a source change and disposes the old renderer', (
      WidgetTester tester,
    ) async {
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[_pageSize(_geometry())],
      );
      final _FakeRendererFactory factory = _FakeRendererFactory(1);
      int sourceCalls = 0;
      Future<Uint8List?> source(String id) async {
        sourceCalls++;
        return _bytes;
      }

      await tester.pumpWidget(
        _harness(
          controller: controller,
          factory: factory.call,
          sourceBytes: source,
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _harness(
          controller: controller,
          factory: factory.call,
          sourceBytes: source,
          sourceId: _secondSourceId,
        ),
      );
      await tester.pumpAndSettle();

      expect(sourceCalls, 2);
      expect(factory.created, hasLength(2));
      expect(factory.created[0].disposed, isTrue);
      expect(factory.created[1].disposed, isFalse);
    });

    testWidgets('refuses a page-count mismatch without painting pages', (
      WidgetTester tester,
    ) async {
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[
          _pageSize(_geometry()),
          _pageSize(_geometry()),
        ],
      );
      final _FakeRendererFactory factory = _FakeRendererFactory(1);
      PageViewLoadException? reported;

      await tester.pumpWidget(
        _harness(
          controller: controller,
          factory: factory.call,
          sourceBytes: _sourceBytes,
          onLoadError: (PageViewLoadException error) => reported = error,
        ),
      );
      await tester.pumpAndSettle();

      expect(reported?.failure, PageViewLoadFailure.pageCountMismatch);
      expect(factory.created.single.disposed, isTrue);
      expect(find.byKey(_pageKey(0)), findsNothing);
      expect(find.byKey(const ValueKey<String>('error')), findsOneWidget);
    });

    testWidgets('reports an unavailable source with a content-free failure', (
      WidgetTester tester,
    ) async {
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[_pageSize(_geometry())],
      );
      final _FakeRendererFactory factory = _FakeRendererFactory(1);
      PageViewLoadException? reported;

      await tester.pumpWidget(
        _harness(
          controller: controller,
          factory: factory.call,
          sourceBytes: (String id) async => null,
          onLoadError: (PageViewLoadException error) => reported = error,
        ),
      );
      await tester.pumpAndSettle();

      expect(reported?.failure, PageViewLoadFailure.sourceUnavailable);
      expect(reported?.toString(), isNot(contains(_sourceId)));
      expect(factory.calls, 0);
      expect(find.byKey(const ValueKey<String>('error')), findsOneWidget);
    });

    testWidgets('sanitizes a renderer exception', (WidgetTester tester) async {
      final PageViewController controller = PageViewController(
        pages: <PageViewPageSize>[_pageSize(_geometry())],
      );
      PageViewLoadException? reported;

      await tester.pumpWidget(
        _harness(
          controller: controller,
          factory: (Uint8List bytes) async {
            throw StateError('/private/path/document.pdf');
          },
          sourceBytes: _sourceBytes,
          onLoadError: (PageViewLoadException error) => reported = error,
        ),
      );
      await tester.pumpAndSettle();

      expect(reported?.failure, PageViewLoadFailure.unreadableSource);
      expect(reported, isNotNull);
      expect(reported!.toString(), isNot(contains('/private/path')));
      expect(find.byKey(const ValueKey<String>('error')), findsOneWidget);
    });
  });
}

final Uint8List _bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

Future<Uint8List?> _sourceBytes(String sourceId) async => _bytes;

ValueKey<String> _pageKey(int pageIndex) {
  return ValueKey<String>('fake-page-$pageIndex');
}

Widget _harness({
  required PageViewController controller,
  required PageViewRendererFactory factory,
  required PageViewSourceBytes sourceBytes,
  String sourceId = _sourceId,
  Size? sized,
  ValueChanged<PageViewLoadException>? onLoadError,
}) {
  final Widget viewer = PageView(
    sourceId: sourceId,
    sourceBytes: sourceBytes,
    controller: controller,
    rendererFactory: factory,
    loadingBuilder: (BuildContext context) =>
        const SizedBox(key: ValueKey<String>('loading')),
    errorBuilder: (BuildContext context) =>
        const SizedBox(key: ValueKey<String>('error')),
    onLoadError: onLoadError,
  );
  return MaterialApp(
    home: Scaffold(
      body: sized == null
          ? viewer
          : Center(
              child: SizedBox.fromSize(size: sized, child: viewer),
            ),
    ),
  );
}

/// A fake renderer that never touches PDFium or a platform view.
final class _FakeRendererFactory {
  _FakeRendererFactory(this.pageCount);

  final int pageCount;
  final List<_FakePageRenderer> created = <_FakePageRenderer>[];
  int calls = 0;
  Uint8List? lastBytes;

  Future<PageViewRenderer> call(Uint8List bytes) async {
    calls++;
    lastBytes = bytes;
    final _FakePageRenderer renderer = _FakePageRenderer(pageCount);
    created.add(renderer);
    return renderer;
  }
}

final class _FakePageRenderer implements PageViewRenderer {
  _FakePageRenderer(this.pageCount);

  @override
  final int pageCount;

  final Set<int> built = <int>{};
  bool disposed = false;

  @override
  Widget buildPage(
    BuildContext context,
    int pageIndex, {
    required ValueChanged<PageViewLoadException> onFailure,
  }) {
    built.add(pageIndex);
    return ColoredBox(key: _pageKey(pageIndex), color: const Color(0xFF00FF00));
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void _expectOffsets(Offset actual, Offset expected) {
  _expectOffsetClose(actual, expected);
}
