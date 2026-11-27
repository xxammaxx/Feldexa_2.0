// T072 SIMULATED browser review-interaction suite (FR-086/FR-089).
//
// Runs the real review panel and the global SIMULATED banner in a browser:
// confirm, reject and undo callbacks, German labels, the evidence-separation
// banner, and no overflow at 200 % text scale. It is a `flutter_test` browser
// test, not Android runtime evidence; without Chrome on the host it is NOT_RUN.
//
// The file lives under `integration_test/` because T072 owns that path; the
// committed helper `test/web_review_browser_entry_test.dart` is a relative
// symlink so the browser runner can compile it (same pattern as T047/T062).

@TestOn('browser')
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
  core.SuggestionResolution resolution = core.SuggestionResolution.unresolved,
}) {
  return core.FieldSuggestion(
    id: id,
    pageIndex: 0,
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
      id: 's-1',
      type: core.FieldType.text,
      rect: core.Rect.fromLTWH(72, 120, 240, 18),
      labelText: 'Familienname',
    );
    final core.FieldSuggestion second = _suggestion(
      id: 's-2',
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
      find.byKey(ValueKey<String>('${confirmSuggestionKeyPrefix}s-1')),
    );
    await tester.pump();
    expect(confirmed?.id, 's-1');

    await tester.tap(
      find.byKey(ValueKey<String>('${rejectSuggestionKeyPrefix}s-2')),
    );
    await tester.pump();
    expect(rejected?.id, 's-2');

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
              id: 's-long',
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
