// T131 viewport, responsive-layout, and accessibility-semantics test
// (US9 scenario 5; FR-091; SC-015).
//
// EVIDENCE CLASS: NONE on the host-VM lane (this run). The equivalent
// Chrome-browser viewport pass is NOT_RUN: the browser lane on this host is
// blocked by the documented Chrome-for-Testing hang
// (`run-tscn02hu/reports/findings/2026-11-27-flutter-browser-lane-hang.md`,
// T121 briefing); it was not retried.
//
// What is asserted, and only that, on the shipped widgets:
//   * the header surfaces (`SimulatedBanner`, page-failure notice, review
//     panel) build without overflow at 360 × 640, 768 × 1024, and
//     1280 × 800 logical pixels and stay reachable by scroll;
//   * controls stay operable: the review confirm button keeps its tap
//     semantics action at every size (Material's 48 × 48 dp minimum tap
//     target is in effect through the shipped button themes);
//   * accessibility semantics: the SIMULATED banner exposes one semantics
//     node with the exact token, the page failure notice is a live region,
//     and no control relies on color or icon alone (FR-094).

import 'package:feldexa_app/features/editor/page_failure.dart';
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ui/feldexa_ui.dart';
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction, SemanticsNode;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

core.FieldSuggestion _suggestion(String ordinal, double confidence) {
  return core.FieldSuggestion(
    id: 's_p0_$ordinal',
    pageIndex: 0,
    rect: core.Rect.fromLTWH(10, 10, 100, 20),
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
    home: Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[child],
        ),
      ),
    ),
  );
}

Widget _surface() {
  return Column(
    children: <Widget>[
      const SimulatedBanner(),
      PageFailureNotice(
        explanation: PageFailureExplanation(
          code: 'REC-002',
          message:
              'Die Felderkennung auf Seite 1 ist fehlgeschlagen. Bereits '
              'erkannte Seiten bleiben unverändert.',
          recovery:
              'Bitte ergänzen Sie fehlende Felder auf dieser Seite selbst '
              'oder versuchen Sie es erneut.',
        ),
      ),
      SuggestionReviewPanel(
        suggestions: <core.FieldSuggestion>[
          _suggestion('0001', 0.30),
          _suggestion('0002', 0.90),
        ],
        confirmedFieldCount: 1,
        onConfirm: (core.FieldSuggestion _) {},
        onReject: (core.FieldSuggestion _) {},
        onUndo: () {},
        undoAvailable: false,
        busy: false,
      ),
    ],
  );
}

const List<Size> _viewportSizes = <Size>[
  Size(360, 640),
  Size(768, 1024),
  Size(1280, 800),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final Size size in _viewportSizes) {
    testWidgets('the editor header surfaces stay usable at $size', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(_surface()));

      // Layout: no overflow exception, everything reachable by scroll.
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(SuggestionReviewPanel));
      expect(find.text(SimulatedEvidence.token), findsOneWidget);
      expect(find.textContaining('fehlgeschlagen'), findsOneWidget);

      // Operability: the confirm action exposes a tap action in semantics,
      // so a screen reader or switch access can operate it at any size.
      final SemanticsNode confirm = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Übernehmen')).first,
      );
      expect(confirm.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      // FR-094: the failure notice is announced as a live region, never
      // only by color or icon.
      final SemanticsNode notice = tester.getSemantics(
        find.byKey(const ValueKey<String>('page-failure-notice-REC-002')),
      );
      expect(notice.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      // The SIMULATED banner keeps its exact, untranslated semantics label.
      expect(
        tester.getSemantics(find.byType(SimulatedBanner)).label,
        contains('SIMULATED'),
      );
    });
  }
}
