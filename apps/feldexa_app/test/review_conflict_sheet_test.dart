// T068 conflict badge and per-candidate resolution sheet tests.
//
// Evidence class: NONE. These are host-VM widget tests with synthetic
// suggestion values. They construct no platform channel, open no document, and
// make no Android runtime claim.
//
// They prove the T068 contract:
//   * symmetric conflicting candidates carry the panel conflict badge and
//     non-conflicting candidates do not;
//   * tapping a badge opens the symmetric group only, with both candidates
//     unresolved and independently actionable;
//   * confirming or rejecting one candidate invokes exactly that callback and
//     closes the sheet without mutating the other candidate;
//   * resolved candidates stay visible with their state and no action buttons;
//   * busy disables the badge and the resolution actions;
//   * a stale or empty conflict reference still shows the tapped candidate and
//     the German explanation without crashing;
//   * the sheet scrolls and does not overflow at 200 % text scale.

@TestOn('vm')
library;

import 'package:feldexa_app/features/editor/review_conflict_sheet.dart';
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const double _width = 400;
const double _height = 700;

core.FieldSuggestion _suggestion({
  required String id,
  required int pageIndex,
  required core.FieldType type,
  required core.Rect rect,
  required double confidence,
  String? labelText,
  List<String> conflictsWith = const <String>[],
  core.SuggestionResolution resolution = core.SuggestionResolution.unresolved,
}) {
  return core.FieldSuggestion(
    id: id,
    pageIndex: pageIndex,
    rect: rect,
    proposedType: type,
    confidence: confidence,
    labelText: labelText,
    evidence: core.SuggestionEvidence(
      cues: const <core.SuggestionCue>[core.SuggestionCue.underline],
      ocrUsed: false,
    ),
    conflictsWith: conflictsWith,
    resolution: resolution,
  );
}

Widget _host(Widget child, {double textScale = 1.0}) {
  return MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const <Locale>[Locale('de')],
    builder: (BuildContext context, Widget? widget) {
      return MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: widget!,
      );
    },
    home: Scaffold(
      body: SizedBox(width: _width, height: _height, child: child),
    ),
  );
}

SuggestionReviewPanel _panel({
  required List<core.FieldSuggestion> suggestions,
  ValueChanged<core.FieldSuggestion>? onConfirm,
  ValueChanged<core.FieldSuggestion>? onReject,
  bool busy = false,
}) {
  return SuggestionReviewPanel(
    suggestions: suggestions,
    confirmedFieldCount: 1,
    onConfirm: onConfirm ?? (_) {},
    onReject: onReject ?? (_) {},
    onUndo: () {},
    busy: busy,
  );
}

core.FieldSuggestion _conflictA({
  core.SuggestionResolution resolution = core.SuggestionResolution.unresolved,
  List<String> conflictsWith = const <String>['s_p0_0002'],
}) {
  return _suggestion(
    id: 's_p0_0001',
    pageIndex: 0,
    type: core.FieldType.text,
    rect: core.Rect.fromLTWH(190, 148, 300, 18),
    confidence: 0.87,
    labelText: 'Familienname',
    conflictsWith: conflictsWith,
    resolution: resolution,
  );
}

core.FieldSuggestion _conflictB({
  core.SuggestionResolution resolution = core.SuggestionResolution.unresolved,
  List<String> conflictsWith = const <String>['s_p0_0001'],
}) {
  return _suggestion(
    id: 's_p0_0002',
    pageIndex: 0,
    type: core.FieldType.date,
    rect: core.Rect.fromLTWH(190.125, 216.25, 300, 18),
    confidence: 0.74,
    labelText: 'Geburtsdatum',
    conflictsWith: conflictsWith,
    resolution: resolution,
  );
}

core.FieldSuggestion _unrelatedC() {
  return _suggestion(
    id: 's_p0_0003',
    pageIndex: 0,
    type: core.FieldType.number,
    rect: core.Rect.fromLTWH(427, 316, 104, 18),
    confidence: 0.9,
    labelText: 'Betrag',
  );
}

void main() {
  testWidgets('only symmetric conflicting candidates render conflict badges', (
    WidgetTester tester,
  ) async {
    final AppLocalizations de = lookupAppLocalizations(const Locale('de'));
    await tester.pumpWidget(
      _host(
        _panel(
          suggestions: <core.FieldSuggestion>[
            _conflictA(),
            _conflictB(),
            _unrelatedC(),
          ],
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('conflict-badge-s_p0_0001')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conflict-badge-s_p0_0002')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conflict-badge-s_p0_0003')),
      findsNothing,
    );
    expect(find.text(de.suggestionConflict), findsNWidgets(2));
  });

  testWidgets('tapping a badge opens exactly the symmetric group', (
    WidgetTester tester,
  ) async {
    final AppLocalizations de = lookupAppLocalizations(const Locale('de'));
    await tester.pumpWidget(
      _host(
        _panel(
          suggestions: <core.FieldSuggestion>[
            _conflictA(),
            _conflictB(),
            _unrelatedC(),
          ],
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('conflict-badge-s_p0_0001')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>(reviewConflictSheetKey)),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conflict-candidate-s_p0_0001')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conflict-candidate-s_p0_0002')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conflict-candidate-s_p0_0003')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('conflict-confirm-s_p0_0001')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conflict-reject-s_p0_0001')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conflict-confirm-s_p0_0002')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conflict-reject-s_p0_0002')),
      findsOneWidget,
    );
    expect(find.text(de.reviewConflictSheetTitle), findsOneWidget);
    expect(find.text(de.reviewConflictSheetBody), findsOneWidget);
    expect(find.text(de.reviewConflictStateUnresolved), findsNWidgets(2));
    final double firstTop = tester
        .getTopLeft(
          find.byKey(const ValueKey<String>('conflict-candidate-s_p0_0001')),
        )
        .dy;
    final double secondTop = tester
        .getTopLeft(
          find.byKey(const ValueKey<String>('conflict-candidate-s_p0_0002')),
        )
        .dy;
    expect(firstTop, lessThan(secondTop));
  });

  testWidgets('confirming one candidate sends only that candidate and closes', (
    WidgetTester tester,
  ) async {
    final core.FieldSuggestion a = _conflictA();
    final core.FieldSuggestion b = _conflictB();
    final List<core.FieldSuggestion> confirmed = <core.FieldSuggestion>[];
    final List<core.FieldSuggestion> rejected = <core.FieldSuggestion>[];

    await tester.pumpWidget(
      _host(
        _panel(
          suggestions: <core.FieldSuggestion>[a, b],
          onConfirm: confirmed.add,
          onReject: rejected.add,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('conflict-badge-s_p0_0001')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('conflict-confirm-s_p0_0001')),
    );
    await tester.pumpAndSettle();

    expect(confirmed, hasLength(1));
    expect(identical(confirmed.single, a), isTrue);
    expect(rejected, isEmpty);
    expect(
      find.byKey(const ValueKey<String>(reviewConflictSheetKey)),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('suggestion-row-s_p0_0002')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conflict-badge-s_p0_0002')),
      findsOneWidget,
    );
  });

  testWidgets('reopening from the second candidate rejects only that one', (
    WidgetTester tester,
  ) async {
    final core.FieldSuggestion a = _conflictA();
    final core.FieldSuggestion b = _conflictB();
    final List<core.FieldSuggestion> confirmed = <core.FieldSuggestion>[];
    final List<core.FieldSuggestion> rejected = <core.FieldSuggestion>[];

    await tester.pumpWidget(
      _host(
        _panel(
          suggestions: <core.FieldSuggestion>[a, b],
          onConfirm: confirmed.add,
          onReject: rejected.add,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('conflict-badge-s_p0_0002')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('conflict-reject-s_p0_0002')),
    );
    await tester.pumpAndSettle();

    expect(rejected, hasLength(1));
    expect(identical(rejected.single, b), isTrue);
    expect(confirmed, isEmpty);
    expect(
      find.byKey(const ValueKey<String>(reviewConflictSheetKey)),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('suggestion-row-s_p0_0001')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conflict-badge-s_p0_0001')),
      findsOneWidget,
    );
  });

  testWidgets('resolved candidates show state without resolution actions', (
    WidgetTester tester,
  ) async {
    final AppLocalizations de = lookupAppLocalizations(const Locale('de'));
    final core.FieldSuggestion a = _conflictA(
      conflictsWith: const <String>['s_p0_0002', 's_p0_0003'],
    );
    final core.FieldSuggestion confirmed = _conflictB(
      resolution: core.SuggestionResolution.confirmed,
    );
    final core.FieldSuggestion rejected = _suggestion(
      id: 's_p0_0003',
      pageIndex: 0,
      type: core.FieldType.number,
      rect: core.Rect.fromLTWH(427, 316, 104, 18),
      confidence: 0.9,
      labelText: 'Betrag',
      conflictsWith: const <String>['s_p0_0001'],
      resolution: core.SuggestionResolution.rejected,
    );

    await tester.pumpWidget(
      _host(
        _panel(suggestions: <core.FieldSuggestion>[a, confirmed, rejected]),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('conflict-badge-s_p0_0001')),
    );
    await tester.pumpAndSettle();

    expect(find.text(de.reviewConflictStateConfirmed), findsOneWidget);
    expect(find.text(de.reviewConflictStateRejected), findsOneWidget);
    expect(find.text(de.reviewConflictStateUnresolved), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('conflict-confirm-s_p0_0002')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('conflict-reject-s_p0_0002')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('conflict-confirm-s_p0_0003')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('conflict-reject-s_p0_0003')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('conflict-confirm-s_p0_0001')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conflict-reject-s_p0_0001')),
      findsOneWidget,
    );
  });

  testWidgets('busy disables the badge and the sheet resolution actions', (
    WidgetTester tester,
  ) async {
    final core.FieldSuggestion a = _conflictA();
    final core.FieldSuggestion b = _conflictB();
    int confirmCalls = 0;
    int rejectCalls = 0;
    void onConfirm(core.FieldSuggestion _) => confirmCalls++;
    void onReject(core.FieldSuggestion _) => rejectCalls++;

    await tester.pumpWidget(
      _host(
        _panel(
          suggestions: <core.FieldSuggestion>[a, b],
          onConfirm: onConfirm,
          onReject: onReject,
          busy: true,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('conflict-badge-s_p0_0001')),
    );
    // The busy panel shows an indeterminate progress indicator, so settle would
    // never complete; one frame is enough to prove no sheet was pushed.
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>(reviewConflictSheetKey)),
      findsNothing,
    );

    await tester.pumpWidget(
      _host(
        ReviewConflictSheet(
          tapped: a,
          suggestions: <core.FieldSuggestion>[a, b],
          onConfirm: onConfirm,
          onReject: onReject,
          busy: true,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>(reviewConflictSheetKey)),
      findsOneWidget,
    );
    final TextButton confirmButton = tester.widget<TextButton>(
      find.byKey(const ValueKey<String>('conflict-confirm-s_p0_0001')),
    );
    final TextButton rejectButton = tester.widget<TextButton>(
      find.byKey(const ValueKey<String>('conflict-reject-s_p0_0001')),
    );
    expect(confirmButton.onPressed, isNull);
    expect(rejectButton.onPressed, isNull);
    await tester.tap(
      find.byKey(const ValueKey<String>('conflict-confirm-s_p0_0001')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('conflict-reject-s_p0_0001')),
    );
    await tester.pump();
    expect(confirmCalls, 0);
    expect(rejectCalls, 0);
  });

  testWidgets('a stale conflict reference shows the candidate and a note', (
    WidgetTester tester,
  ) async {
    final AppLocalizations de = lookupAppLocalizations(const Locale('de'));
    final core.FieldSuggestion stale = _conflictA(
      conflictsWith: const <String>['s_p0_9999'],
    );

    await tester.pumpWidget(
      _host(_panel(suggestions: <core.FieldSuggestion>[stale])),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('conflict-badge-s_p0_0001')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>(reviewConflictSheetKey)),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conflict-candidate-s_p0_0001')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conflict-candidate-s_p0_9999')),
      findsNothing,
    );
    expect(find.text(de.reviewConflictSingleCandidateNote), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey<String>(conflictCloseKey)));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>(reviewConflictSheetKey)),
      findsNothing,
    );

    final core.FieldSuggestion noReference = _suggestion(
      id: 's_p0_0004',
      pageIndex: 0,
      type: core.FieldType.multiline,
      rect: core.Rect.fromLTWH(20, 420, 200, 40),
      confidence: 0.65,
      labelText: 'Bemerkung',
    );
    await tester.pumpWidget(
      _host(
        ReviewConflictSheet(
          tapped: noReference,
          suggestions: <core.FieldSuggestion>[noReference],
          onConfirm: (_) {},
          onReject: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(de.reviewConflictSingleCandidateNote), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sheet scrolls without overflow at 200 % text scale', (
    WidgetTester tester,
  ) async {
    final List<core.FieldSuggestion> suggestions = <core.FieldSuggestion>[
      for (int index = 0; index < 5; index++)
        _suggestion(
          id: 's_p0_${(index + 1).toString().padLeft(4, '0')}',
          pageIndex: 0,
          type: core.FieldType.multiline,
          rect: core.Rect.fromLTWH(
            10 + index.toDouble(),
            20 + index * 20.0,
            120,
            18,
          ),
          confidence: 0.42,
          labelText:
              'Sehr langer Bezeichnungstext für ein Feld mit Umbruch $index',
          conflictsWith: index == 0
              ? <String>['s_p0_0002']
              : index == 1
              ? <String>['s_p0_0001']
              : const <String>[],
        ),
    ];

    await tester.pumpWidget(
      _host(
        ReviewConflictSheet(
          tapped: suggestions.first,
          suggestions: suggestions,
          onConfirm: (_) {},
          onReject: (_) {},
        ),
        textScale: 2.0,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>(reviewConflictSheetKey)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>(reviewConflictSheetKey)),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
  });
}
