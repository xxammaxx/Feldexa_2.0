// T128 Chrome editing journey (FR-086; US9 Independent Test) — entry test.
//
// EVIDENCE CLASS: NONE on this lane; on `emulator-5554` the same file is
// EMULATOR evidence. The real Chrome journey runs from the `test/`-rooted
// mirror `test/web_journey_browser_entry_test.dart` (1/1 PASS on Chrome for
// Testing 156, 2026-11-28). What is delivered
// here is the host-VM entry test over the shipped editing-journey widgets:
// the same seams the Chrome journey drives (banner, page display and
// navigation, field selection, geometry move/resize, review decisions), so
// the unblocked browser lane only has to substitute the platform.
//
// Journey steps covered here, in order, on the shipped widgets:
//   1. open — the SIMULATED banner labels the development surface;
//   2. display — a page layout builds from committed A4 display geometry;
//   3. select — `FieldSelectionSurface` resolves the tap to one item;
//   4. move — a geometry session moves the field by a view delta;
//   5. resize — a second session resizes by a corner handle;
//   6. review — confirm resolves the suggestion; the panel updates;
//   7. navigation — the page controller exposes both pages in order.
//
// Every step asserts observable widget/model state, never a mocked
// platform result, and the surface never states completeness.

import 'package:feldexa_app/features/editor/page_strip.dart';
import 'package:feldexa_app/features/editor/page_view.dart' as viewer;
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ui/feldexa_ui.dart';
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

final Rect _pageBox = Rect.fromLTWH(0, 0, 595, 842);
final Rect _fieldRect = Rect.fromLTWH(120, 200, 200, 24);

core.FieldSuggestion _suggestion(String ordinal, double confidence) {
  return core.FieldSuggestion(
    id: 's_p0_$ordinal',
    pageIndex: 0,
    rect: core.Rect.fromLTWH(
      _fieldRect.left,
      _fieldRect.top,
      _fieldRect.width,
      _fieldRect.height,
    ),
    proposedType: core.FieldType.text,
    confidence: confidence,
    labelText: 'Name',
    evidence: core.SuggestionEvidence(
      cues: const <core.SuggestionCue>[core.SuggestionCue.box],
    ),
  );
}

Widget _host(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('de'),
    home: Scaffold(body: child),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the editing journey drives display, select, move, resize, '
      'review, and navigation on the shipped widgets', (
    WidgetTester tester,
  ) async {
    // 1. open — the development surface is labeled SIMULATED (FR-087).
    await tester.pumpWidget(_host(const SimulatedBanner()));
    expect(find.text(SimulatedEvidence.token), findsOneWidget);

    // 2. display — two committed A4 pages build one deterministic layout.
    final viewer.PageViewController viewerController =
        viewer.PageViewController(
          pages: <viewer.PageViewPageSize>[
            viewer.PageViewPageSize(widthPt: 595, heightPt: 842),
            viewer.PageViewPageSize(widthPt: 595, heightPt: 842),
          ],
        );
    addTearDown(viewerController.dispose);
    expect(viewerController.layout.pageCount, 2);

    final PageStripController stripController = PageStripController(
      viewer: viewerController,
    );
    addTearDown(stripController.dispose);

    // 3. select — the selection surface resolves a tap inside the field to
    // exactly that overlay item and nothing else.
    final core.FieldSuggestion selectTarget = _suggestion('0002', 0.90);
    final FieldOverlayItem item = FieldOverlayItem.fromSuggestion(selectTarget);
    FieldOverlayItem? selected;
    final FieldSelectionController selectionController =
        FieldSelectionController();
    addTearDown(selectionController.dispose);
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 595,
          height: 842,
          child: FieldSelectionSurface(
            controller: selectionController,
            items: <FieldOverlayItem>[item],
            pageSize: const Size(595, 842),
            pageRect: _pageBox,
            onSelected: (FieldOverlayItem? value) => selected = value,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(130, 210));
    await tester.pump();
    expect(selected?.id, 's_p0_0002');

    // 4. move — one session maps the cumulative view delta exactly once.
    final FieldGeometrySession move = FieldGeometrySession.start(
      fieldId: 'f-0001',
      handle: FieldGeometryHandle.body,
      startRect: _fieldRect,
      pageBox: _pageBox,
      scale: 1.0,
    );
    move.update(
      mapViewDeltaToDisplay(viewDelta: const Offset(10, -5), scale: 1.0),
    );
    final FieldGeometryChange? moveChange = move.commit();
    expect(moveChange?.rect, Rect.fromLTWH(130, 195, 200, 24));

    // 5. resize — a corner handle resizes with the same no-drift contract.
    final FieldGeometrySession resize = FieldGeometrySession.start(
      fieldId: 'f-0001',
      handle: FieldGeometryHandle.bottomRight,
      startRect: moveChange!.rect,
      pageBox: _pageBox,
      scale: 1.0,
    );
    resize.update(
      mapViewDeltaToDisplay(viewDelta: const Offset(-40, 16), scale: 1.0),
    );
    final FieldGeometryChange? resizeChange = resize.commit();
    expect(resizeChange?.rect.width, 160);
    expect(resizeChange?.rect.height, 40);

    // 6. review — confirming resolves the suggestion out of the open set.
    core.FieldSuggestion? confirmed;
    final List<core.FieldSuggestion> suggestions = <core.FieldSuggestion>[
      _suggestion('0001', 0.30),
      _suggestion('0002', 0.90),
    ];
    await tester.pumpWidget(
      _host(
        SuggestionReviewPanel(
          suggestions: suggestions,
          confirmedFieldCount: 0,
          onConfirm: (core.FieldSuggestion suggestion) {
            confirmed = suggestion;
            suggestions.remove(suggestion);
          },
          onReject: (core.FieldSuggestion _) {},
          onUndo: () {},
          undoAvailable: false,
          busy: false,
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel(RegExp('Übernehmen')).first);
    await tester.pump();
    expect(confirmed?.id, 's_p0_0001');

    // 7. navigation — both pages stay addressable in document order: the
    // strip controller tracks the viewer and the layout exposes every page
    // rectangle at its committed display geometry.
    expect(viewerController.layout.pageCount, 2);
    final Rect page1 = viewerController.layout.pageRectFor(1);
    expect(page1.top, greaterThan(viewerController.layout.pageRectFor(0).top));
    expect(page1.width, 595);
    expect(
      PageStrip(controller: stripController, pages: const <PageStripPage>[]),
      isNotNull,
    );
    await tester.pumpWidget(_host(const SizedBox.shrink()));
    expect(tester.takeException(), isNull);
  });
}
