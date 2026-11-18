@TestOn('vm')
library;

import 'dart:ui' as ui;

import 'package:feldexa_app/features/editor/page_strip.dart';
import 'package:feldexa_app/features/editor/page_view.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart' hide PageView;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// T043 page-strip navigation before analysis finishes.
///
/// Host-VM widget tests with synthetic page metadata only: no PDF, no source
/// bytes, no file, no network, no emulator, and no device. They prove that all
/// pages render and navigate while analysis is pending or running, that a tap
/// delegates to `PageViewController.scrollToPage`, that selection is exposed
/// and kept visible, that the compact mode is used below 600 dp and the full
/// strip at 600 dp and above, and that every control is a German semantic
/// button with an analysis-state hint.

const ValueKey<String> _previousKey = ValueKey<String>('page-strip-previous');
const ValueKey<String> _nextKey = ValueKey<String>('page-strip-next');
const ValueKey<String> _indicatorKey = ValueKey<String>('page-strip-indicator');

ValueKey<String> _pageKey(int pageNumber) {
  return ValueKey<String>('page-strip-page-$pageNumber');
}

PageViewController _viewer(int pageCount) {
  return PageViewController(
    pages: <PageViewPageSize>[
      for (int index = 0; index < pageCount; index++)
        PageViewPageSize(widthPt: 595, heightPt: 842),
    ],
  );
}

List<PageStripPage> _pendingPages(int pageCount) {
  return <PageStripPage>[
    for (int index = 0; index < pageCount; index++) const PageStripPage(),
  ];
}

List<PageStripPage> _mixedPages() {
  return const <PageStripPage>[
    PageStripPage(),
    PageStripPage(analysisState: PageStripAnalysisState.analyzing),
    PageStripPage(analysisState: PageStripAnalysisState.ready),
    PageStripPage(analysisState: PageStripAnalysisState.failed),
    PageStripPage(
      analysisState: PageStripAnalysisState.ready,
      unreadable: true,
    ),
    PageStripPage(analysisState: PageStripAnalysisState.ready, uncertain: true),
  ];
}

Widget _harness({
  required PageStripController controller,
  required List<PageStripPage> pages,
  double width = 800,
  double height = 240,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const <Locale>[Locale('de')],
    builder: (BuildContext context, Widget? child) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      );
    },
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: height,
          child: PageStrip(controller: controller, pages: pages),
        ),
      ),
    ),
  );
}

Future<void> _pumpStrip(
  WidgetTester tester, {
  required PageStripController controller,
  required List<PageStripPage> pages,
  double width = 800,
  double height = 240,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    _harness(
      controller: controller,
      pages: pages,
      width: width,
      height: height,
      textScaler: textScaler,
    ),
  );
}

int _builtPageCount(WidgetTester tester, int pageCount) {
  int built = 0;
  for (int pageNumber = 1; pageNumber <= pageCount; pageNumber++) {
    if (find.byKey(_pageKey(pageNumber)).evaluate().isNotEmpty) {
      built++;
    }
  }
  return built;
}

void main() {
  group('PageStripController', () {
    test('rejects an initial page outside the document', () {
      final PageViewController viewer = _viewer(3);
      addTearDown(viewer.dispose);

      expect(
        () => PageStripController(viewer: viewer, initialPageIndex: -1),
        throwsRangeError,
      );
      expect(
        () => PageStripController(viewer: viewer, initialPageIndex: 3),
        throwsRangeError,
      );
    });

    test('selects pages, delegates scrolling, and clamps at boundaries', () {
      final PageViewController viewer = _viewer(4);
      addTearDown(viewer.dispose);
      viewer.setViewportSize(const Size(400, 800));
      final PageStripController controller = PageStripController(
        viewer: viewer,
      );
      addTearDown(controller.dispose);
      int notifications = 0;
      controller.addListener(() => notifications++);

      expect(controller.selectedPageIndex, 0);
      expect(controller.canSelectPrevious, isFalse);
      expect(controller.canSelectNext, isTrue);

      controller.selectNext();
      expect(controller.selectedPageIndex, 1);
      expect(notifications, 1);
      expect(
        viewer.pan.dy,
        closeTo(-viewer.layout.pageRectFor(1).top * viewer.scale, 1e-9),
      );

      controller.selectPage(3);
      expect(controller.selectedPageIndex, 3);
      expect(notifications, 2);
      expect(controller.canSelectNext, isFalse);

      controller.selectNext();
      expect(controller.selectedPageIndex, 3);
      expect(notifications, 2);

      controller.selectPrevious();
      expect(controller.selectedPageIndex, 2);
      expect(notifications, 3);

      // Re-selecting the same page still asks the viewer to show it but does
      // not notify listeners.
      controller.selectPage(2);
      expect(controller.selectedPageIndex, 2);
      expect(notifications, 3);
      expect(() => controller.selectPage(4), throwsRangeError);
      expect(() => controller.selectPage(-1), throwsRangeError);
    });

    test('changes selection before a viewport exists', () {
      final PageViewController viewer = _viewer(3);
      addTearDown(viewer.dispose);
      final PageStripController controller = PageStripController(
        viewer: viewer,
      );
      addTearDown(controller.dispose);

      controller.selectPage(2);

      expect(controller.selectedPageIndex, 2);
      expect(viewer.pan, Offset.zero);
      expect(viewer.hasViewport, isFalse);
    });
  });

  group('PageStrip full presentation', () {
    testWidgets('lists every page in order with all analysis states', (
      WidgetTester tester,
    ) async {
      final PageViewController viewer = _viewer(6);
      addTearDown(viewer.dispose);
      final PageStripController controller = PageStripController(
        viewer: viewer,
      );
      addTearDown(controller.dispose);

      await _pumpStrip(tester, controller: controller, pages: _mixedPages());

      for (int pageNumber = 1; pageNumber <= 6; pageNumber++) {
        expect(find.byKey(_pageKey(pageNumber)), findsOneWidget);
        expect(
          tester.getTopLeft(find.byKey(_pageKey(pageNumber))).dx,
          greaterThan(
            pageNumber == 1
                ? -1
                : tester.getTopLeft(find.byKey(_pageKey(pageNumber - 1))).dx,
          ),
        );
      }
      expect(find.text('Wartet'), findsOneWidget);
      expect(find.text('Läuft'), findsOneWidget);
      expect(find.text('Fertig'), findsNWidgets(3));
      expect(find.text('Fehler'), findsOneWidget);
      expect(find.text('Nicht lesbar'), findsOneWidget);
      expect(find.text('unsicher'), findsOneWidget);

      // No catalog code, path, URI, or document title leaks into a label.
      for (final Text text in tester.widgetList<Text>(find.byType(Text))) {
        final String value = text.data ?? '';
        expect(value, isNot(contains('IMP-')));
        expect(value, isNot(contains('SAVE-')));
        expect(value, isNot(contains('PLT-')));
        expect(value, isNot(contains('/')));
      }
    });

    testWidgets('renders and navigates while every page is still pending', (
      WidgetTester tester,
    ) async {
      final PageViewController viewer = _viewer(5);
      addTearDown(viewer.dispose);
      viewer.setViewportSize(const Size(400, 800));
      final PageStripController controller = PageStripController(
        viewer: viewer,
      );
      addTearDown(controller.dispose);

      await _pumpStrip(tester, controller: controller, pages: _pendingPages(5));

      expect(tester.takeException(), isNull);
      expect(_builtPageCount(tester, 5), 5);
      expect(find.byKey(_pageKey(5)), findsOneWidget);

      await tester.tap(find.byKey(_pageKey(2)));
      await tester.pump();

      expect(controller.selectedPageIndex, 1);
      expect(
        viewer.pan.dy,
        closeTo(-viewer.layout.pageRectFor(1).top * viewer.scale, 1e-9),
      );
    });

    testWidgets('keeps the selected page visible when analysis updates', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final PageViewController viewer = _viewer(3);
      addTearDown(viewer.dispose);
      final PageStripController controller = PageStripController(
        viewer: viewer,
      );
      addTearDown(controller.dispose);

      await _pumpStrip(tester, controller: controller, pages: _pendingPages(3));
      await tester.tap(find.byKey(_pageKey(2)));
      await tester.pump();
      expect(controller.selectedPageIndex, 1);

      await _pumpStrip(
        tester,
        controller: controller,
        pages: const <PageStripPage>[
          PageStripPage(analysisState: PageStripAnalysisState.ready),
          PageStripPage(
            analysisState: PageStripAnalysisState.analyzing,
            uncertain: true,
          ),
          PageStripPage(analysisState: PageStripAnalysisState.failed),
        ],
      );

      expect(controller.selectedPageIndex, 1);
      expect(find.text('Läuft'), findsOneWidget);
      expect(find.text('unsicher'), findsOneWidget);
      final SemanticsData data = tester
          .getSemantics(find.byKey(_pageKey(2)))
          .getSemanticsData();
      expect(data.hint, 'Analyse läuft, unsicher');
      handle.dispose();
    });

    testWidgets('rejects a page list that does not match the viewer', (
      WidgetTester tester,
    ) async {
      final PageViewController viewer = _viewer(3);
      addTearDown(viewer.dispose);
      final PageStripController controller = PageStripController(
        viewer: viewer,
      );
      addTearDown(controller.dispose);

      await _pumpStrip(tester, controller: controller, pages: _pendingPages(2));

      expect(tester.takeException(), isA<ArgumentError>());
    });
  });

  group('PageStrip semantics', () {
    testWidgets('exposes one German button per page with state hints', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final PageViewController viewer = _viewer(6);
      addTearDown(viewer.dispose);
      final PageStripController controller = PageStripController(
        viewer: viewer,
      );
      addTearDown(controller.dispose);

      await _pumpStrip(tester, controller: controller, pages: _mixedPages());

      final SemanticsNode selected = tester.getSemantics(
        find.byKey(_pageKey(1)),
      );
      final SemanticsData selectedData = selected.getSemanticsData();
      expect(selected.label, 'Seite 1 von 6');
      expect(selected.hint, 'Analyse ausstehend');
      expect(selectedData.flagsCollection.isButton, isTrue);
      expect(selectedData.flagsCollection.isSelected, ui.Tristate.isTrue);
      expect(selectedData.hasAction(SemanticsAction.tap), isTrue);

      final SemanticsData second = tester
          .getSemantics(find.byKey(_pageKey(2)))
          .getSemanticsData();
      expect(second.label, 'Seite 2 von 6');
      expect(second.hint, 'Analyse läuft');
      expect(second.flagsCollection.isSelected, ui.Tristate.isFalse);

      expect(
        tester.getSemantics(find.byKey(_pageKey(3))).hint,
        'Analyse abgeschlossen',
      );
      expect(
        tester.getSemantics(find.byKey(_pageKey(4))).hint,
        'Analyse fehlgeschlagen',
      );
      expect(
        tester.getSemantics(find.byKey(_pageKey(5))).hint,
        'Analyse abgeschlossen, Nicht lesbar',
      );
      expect(
        tester.getSemantics(find.byKey(_pageKey(6))).hint,
        'Analyse abgeschlossen, unsicher',
      );

      // Primary controls are comfortably above the 48 dp touch-target floor.
      for (int pageNumber = 1; pageNumber <= 6; pageNumber++) {
        final Size size = tester.getSize(find.byKey(_pageKey(pageNumber)));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      handle.dispose();
    });

    testWidgets('updates the semantic hint when analysis progresses', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final PageViewController viewer = _viewer(2);
      addTearDown(viewer.dispose);
      final PageStripController controller = PageStripController(
        viewer: viewer,
      );
      addTearDown(controller.dispose);

      await _pumpStrip(tester, controller: controller, pages: _pendingPages(2));
      expect(
        tester.getSemantics(find.byKey(_pageKey(1))).hint,
        'Analyse ausstehend',
      );

      await _pumpStrip(
        tester,
        controller: controller,
        pages: const <PageStripPage>[
          PageStripPage(analysisState: PageStripAnalysisState.analyzing),
          PageStripPage(),
        ],
      );
      expect(
        tester.getSemantics(find.byKey(_pageKey(1))).hint,
        'Analyse läuft',
      );

      await _pumpStrip(
        tester,
        controller: controller,
        pages: const <PageStripPage>[
          PageStripPage(analysisState: PageStripAnalysisState.ready),
          PageStripPage(),
        ],
      );
      expect(
        tester.getSemantics(find.byKey(_pageKey(1))).hint,
        'Analyse abgeschlossen',
      );
      handle.dispose();
    });
  });

  group('PageStrip compact presentation', () {
    testWidgets('collapses below 600 dp and navigates with labelled buttons', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final PageViewController viewer = _viewer(5);
      addTearDown(viewer.dispose);
      viewer.setViewportSize(const Size(400, 800));
      final PageStripController controller = PageStripController(
        viewer: viewer,
      );
      addTearDown(controller.dispose);

      await _pumpStrip(
        tester,
        controller: controller,
        pages: _pendingPages(5),
        width: 599,
      );

      expect(find.byKey(_indicatorKey), findsOneWidget);
      expect(find.byKey(_previousKey), findsOneWidget);
      expect(find.byKey(_nextKey), findsOneWidget);
      expect(find.byKey(_pageKey(1)), findsNothing);
      expect(find.byKey(_pageKey(5)), findsNothing);
      expect(find.text('Seite 1 von 5'), findsOneWidget);
      expect(find.text('Analyse ausstehend'), findsOneWidget);

      final SemanticsData previous = tester
          .getSemantics(find.byKey(_previousKey))
          .getSemanticsData();
      final SemanticsData next = tester
          .getSemantics(find.byKey(_nextKey))
          .getSemanticsData();
      expect(previous.label, 'Vorherige Seite');
      expect(next.label, 'Nächste Seite');
      expect(previous.flagsCollection.isButton, isTrue);
      expect(next.flagsCollection.isButton, isTrue);
      expect(previous.hasAction(SemanticsAction.tap), isFalse);
      expect(next.hasAction(SemanticsAction.tap), isTrue);

      await tester.tap(find.byKey(_nextKey));
      await tester.pump();

      expect(controller.selectedPageIndex, 1);
      expect(find.text('Seite 2 von 5'), findsOneWidget);
      expect(
        viewer.pan.dy,
        closeTo(-viewer.layout.pageRectFor(1).top * viewer.scale, 1e-9),
      );

      controller.selectPage(4);
      await tester.pump();

      expect(find.text('Seite 5 von 5'), findsOneWidget);
      final IconButton nextButton = tester.widget<IconButton>(
        find.descendant(
          of: find.byKey(_nextKey),
          matching: find.byType(IconButton),
        ),
      );
      expect(nextButton.onPressed, isNull);
      handle.dispose();
    });

    testWidgets('shows unreadable and uncertain markers in compact mode', (
      WidgetTester tester,
    ) async {
      final PageViewController viewer = _viewer(1);
      addTearDown(viewer.dispose);
      final PageStripController controller = PageStripController(
        viewer: viewer,
      );
      addTearDown(controller.dispose);

      await _pumpStrip(
        tester,
        controller: controller,
        pages: const <PageStripPage>[
          PageStripPage(
            analysisState: PageStripAnalysisState.failed,
            unreadable: true,
            uncertain: true,
          ),
        ],
        width: 400,
      );

      expect(find.text('Seite 1 von 1'), findsOneWidget);
      expect(find.text('Analyse fehlgeschlagen'), findsOneWidget);
      expect(find.text('Nicht lesbar'), findsOneWidget);
      expect(find.text('unsicher'), findsOneWidget);
      expect(find.byKey(_previousKey), findsOneWidget);
      expect(find.byKey(_nextKey), findsOneWidget);
    });

    testWidgets('stays usable at 200% text scaling in both presentations', (
      WidgetTester tester,
    ) async {
      final PageViewController viewer = _viewer(3);
      addTearDown(viewer.dispose);
      final PageStripController controller = PageStripController(
        viewer: viewer,
      );
      addTearDown(controller.dispose);
      const List<PageStripPage> pages = <PageStripPage>[
        PageStripPage(
          analysisState: PageStripAnalysisState.failed,
          unreadable: true,
          uncertain: true,
        ),
        PageStripPage(analysisState: PageStripAnalysisState.analyzing),
        PageStripPage(analysisState: PageStripAnalysisState.ready),
      ];

      await _pumpStrip(
        tester,
        controller: controller,
        pages: pages,
        width: 400,
        textScaler: const TextScaler.linear(2),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Seite 1 von 3'), findsOneWidget);
      expect(find.text('Nicht lesbar'), findsOneWidget);
      expect(find.text('unsicher'), findsOneWidget);

      await _pumpStrip(
        tester,
        controller: controller,
        pages: pages,
        width: 800,
        height: 320,
        textScaler: const TextScaler.linear(2),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(_pageKey(1)), findsOneWidget);
      expect(find.byKey(_pageKey(3)), findsOneWidget);
      expect(find.text('Nicht lesbar'), findsOneWidget);
      expect(find.text('unsicher'), findsOneWidget);
    });

    testWidgets('uses the full strip at exactly 600 dp', (
      WidgetTester tester,
    ) async {
      final PageViewController viewer = _viewer(4);
      addTearDown(viewer.dispose);
      final PageStripController controller = PageStripController(
        viewer: viewer,
      );
      addTearDown(controller.dispose);

      await _pumpStrip(
        tester,
        controller: controller,
        pages: _pendingPages(4),
        width: 599,
      );
      expect(find.byKey(_indicatorKey), findsOneWidget);
      expect(find.byKey(_pageKey(1)), findsNothing);

      await _pumpStrip(
        tester,
        controller: controller,
        pages: _pendingPages(4),
        width: 600,
      );
      expect(find.byKey(_indicatorKey), findsNothing);
      expect(find.byKey(_previousKey), findsNothing);
      expect(find.byKey(_nextKey), findsNothing);
      expect(find.byKey(_pageKey(1)), findsOneWidget);
      expect(find.byKey(_pageKey(4)), findsOneWidget);
    });
  });

  group('PageStrip long documents', () {
    testWidgets('builds lazily and reveals a distant selection', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final PageViewController viewer = _viewer(100);
      addTearDown(viewer.dispose);
      final PageStripController controller = PageStripController(
        viewer: viewer,
      );
      addTearDown(controller.dispose);

      await _pumpStrip(
        tester,
        controller: controller,
        pages: _pendingPages(100),
      );

      final int initiallyBuilt = _builtPageCount(tester, 100);
      expect(initiallyBuilt, lessThan(100));
      expect(initiallyBuilt, lessThanOrEqualTo(20));
      expect(find.byKey(_pageKey(100)), findsNothing);

      controller.selectPage(99);
      await tester.pump();
      await tester.pump();

      expect(controller.selectedPageIndex, 99);
      expect(find.byKey(_pageKey(100)), findsOneWidget);
      expect(_builtPageCount(tester, 100), lessThan(100));
      expect(
        tester.getSemantics(find.byKey(_pageKey(100))).label,
        'Seite 100 von 100',
      );
      final double left = tester.getTopLeft(find.byKey(_pageKey(100))).dx;
      expect(left, greaterThanOrEqualTo(0));
      expect(left, lessThan(800));

      await tester.tap(find.byKey(_pageKey(100)));
      await tester.pump();
      expect(controller.selectedPageIndex, 99);
      handle.dispose();
    });

    testWidgets('compact mode stays usable at page 100', (
      WidgetTester tester,
    ) async {
      final PageViewController viewer = _viewer(100);
      addTearDown(viewer.dispose);
      final PageStripController controller = PageStripController(
        viewer: viewer,
        initialPageIndex: 99,
      );
      addTearDown(controller.dispose);

      await _pumpStrip(
        tester,
        controller: controller,
        pages: _pendingPages(100),
        width: 400,
      );

      expect(find.text('Seite 100 von 100'), findsOneWidget);
      expect(find.byKey(_nextKey), findsOneWidget);
      final IconButton nextButton = tester.widget<IconButton>(
        find.descendant(
          of: find.byKey(_nextKey),
          matching: find.byType(IconButton),
        ),
      );
      expect(nextButton.onPressed, isNull);
      expect(controller.selectedPageIndex, 99);
    });
  });
}
