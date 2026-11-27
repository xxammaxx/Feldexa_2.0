// T072 SIMULATED browser review-interaction suite (FR-086/FR-089).
//
// Runs the real review panel: confirm, reject and undo callbacks, German
// labels, and no overflow at 200 % text scale. The suite is platform-agnostic,
// so it runs on the host VM (NONE evidence) and, when Chrome is available, in
// the browser lane; without Chrome the browser run is NOT_RUN.
//
// The suite lives under `test/` because Flutter 3.47.7 roots Chrome browser
// tests at `<project>/test`; `.specify/init-options.json` sets
// `allow_symlinks: false`, so T072's original `integration_test/` path is
// superseded rather than linked (same measured constraint as T062).

library;

import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

core.FieldSuggestion _suggestion({
  required String id,
  required core.FieldType type,
  required core.Rect rect,
  String? labelText,
  int pageIndex = 1,
  core.SuggestionResolution resolution = core.SuggestionResolution.unresolved,
}) {
  return core.FieldSuggestion(
    id: id,
    pageIndex: pageIndex,
    rect: rect,
    proposedType: type,
    confidence: 0.82,
    labelText: labelText,
    evidence: core.SuggestionEvidence(
      cues: const <core.SuggestionCue>[core.SuggestionCue.underline],
      ocrUsed: false,
    ),
    resolution: resolution,
  );
}

Widget _host(Widget child, {double textScale = 1.0}) {
  return MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (BuildContext context, Widget? inner) {
      return MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: inner!,
      );
    },
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('confirm, reject and undo report the exact suggestion', (
    WidgetTester tester,
  ) async {
    final core.FieldSuggestion first = _suggestion(
      id: 's_p1_0001',
      type: core.FieldType.text,
      rect: core.Rect.fromLTWH(72, 120, 240, 18),
      labelText: 'Familienname',
    );
    final core.FieldSuggestion second = _suggestion(
      id: 's_p1_0002',
      type: core.FieldType.checkbox,
      rect: core.Rect.fromLTWH(72, 160, 10, 10),
    );
    core.FieldSuggestion? confirmed;
    core.FieldSuggestion? rejected;
    var undo = 0;

    await tester.pumpWidget(
      _host(
        SuggestionReviewPanel(
          suggestions: <core.FieldSuggestion>[first, second],
          confirmedFieldCount: 0,
          onConfirm: (core.FieldSuggestion value) => confirmed = value,
          onReject: (core.FieldSuggestion value) => rejected = value,
          onUndo: () => undo++,
          undoAvailable: true,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>(suggestionPanelKey)),
      findsOneWidget,
    );
    expect(find.text('Familienname'), findsOneWidget);

    await tester.tap(
      find.byKey(ValueKey<String>('${confirmSuggestionKeyPrefix}s_p1_0001')),
    );
    await tester.pump();
    expect(confirmed?.id, 's_p1_0001');

    await tester.tap(
      find.byKey(ValueKey<String>('${rejectSuggestionKeyPrefix}s_p1_0002')),
    );
    await tester.pump();
    expect(rejected?.id, 's_p1_0002');

    await tester.tap(find.byKey(const ValueKey<String>(undoReviewKey)));
    await tester.pump();
    expect(undo, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review panel does not overflow at 200 percent text scale', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(
        SuggestionReviewPanel(
          suggestions: <core.FieldSuggestion>[
            _suggestion(
              id: 's_p1_0003',
              type: core.FieldType.text,
              rect: core.Rect.fromLTWH(40, 90, 260, 18),
              labelText:
                  'Sehr langer Bezeichner für ein gescanntes Feld im Antrag',
            ),
          ],
          confirmedFieldCount: 0,
          onConfirm: (_) {},
          onReject: (_) {},
          onUndo: () {},
        ),
        textScale: 2.0,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
