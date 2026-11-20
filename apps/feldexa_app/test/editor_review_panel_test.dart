// Issue #217 Phase B2 suggestion review panel tests.
//
// Evidence class: NONE. These are host-VM widget tests with synthetic
// suggestion values. They construct no platform channel, open no document, and
// make no Android runtime claim.
//
// They prove the B2 panel contract:
//   * deterministic grouping/order by page and display position;
//   * label fallback, German type names, one-based page, 1/8 pt position,
//     integer confidence percent, uncertainty below 0.50, and conflict markers;
//   * the stable keys for the panel, rows, actions, undo, and empty state;
//   * confirm/reject/undo callbacks receive the exact suggestion;
//   * resolved suggestions leave the actionable queue and the header counts
//     keep the resolution visible;
//   * the German empty state distinguishes "no suggestions" from "all
//     reviewed";
//   * no overflow at 200 % text scale.

@TestOn('vm')
library;

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

core.FieldSuggestion _signatureSuggestion({
  required String id,
  required core.Rect rect,
  required double confidence,
  String? labelText,
}) {
  return core.FieldSuggestion(
    id: id,
    pageIndex: 0,
    rect: rect,
    proposedType: core.FieldType.signature,
    confidence: confidence,
    labelText: labelText,
    evidence: core.SuggestionEvidence(
      cues: const <core.SuggestionCue>[
        core.SuggestionCue.signatureArea,
        core.SuggestionCue.underline,
      ],
      ocrUsed: true,
    ),
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
  int confirmedFieldCount = 0,
  ValueChanged<core.FieldSuggestion>? onConfirm,
  ValueChanged<core.FieldSuggestion>? onReject,
  VoidCallback? onUndo,
  bool undoAvailable = false,
  bool busy = false,
}) {
  return SuggestionReviewPanel(
    suggestions: suggestions,
    confirmedFieldCount: confirmedFieldCount,
    onConfirm: onConfirm ?? (_) {},
    onReject: onReject ?? (_) {},
    onUndo: onUndo ?? () {},
    undoAvailable: undoAvailable,
    busy: busy,
  );
}

void main() {
  testWidgets('renders grouped deterministic rows with German metadata', (
    WidgetTester tester,
  ) async {
    final AppLocalizations de = lookupAppLocalizations(const Locale('de'));
    final core.FieldSuggestion pageOneFirst = _suggestion(
      id: 's_p0_0001',
      pageIndex: 0,
      type: core.FieldType.text,
      rect: core.Rect.fromLTWH(190, 148, 300, 18),
      confidence: 0.87,
      labelText: 'Familienname',
    );
    final core.FieldSuggestion pageOneSecond = _suggestion(
      id: 's_p0_0002',
      pageIndex: 0,
      type: core.FieldType.date,
      rect: core.Rect.fromLTWH(190.125, 216.25, 300, 18),
      confidence: 0.74,
      labelText: 'Geburtsdatum',
    );
    final core.FieldSuggestion pageTwo = _suggestion(
      id: 's_p1_0001',
      pageIndex: 1,
      type: core.FieldType.number,
      rect: core.Rect.fromLTWH(427, 316, 104, 18),
      confidence: 0.9,
      labelText: 'Betrag 1',
    );

    // Deliberately out of document order; the panel sorts by page/position.
    await tester.pumpWidget(
      _host(
        _panel(
          suggestions: <core.FieldSuggestion>[
            pageTwo,
            pageOneSecond,
            pageOneFirst,
          ],
          confirmedFieldCount: 0,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>(suggestionPanelKey)),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('suggestion-row-s_p0_0001')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('suggestion-row-s_p0_0002')),
      findsOneWidget,
    );

    final double firstTop = tester
        .getTopLeft(
          find.byKey(const ValueKey<String>('suggestion-row-s_p0_0001')),
        )
        .dy;
    final double secondTop = tester
        .getTopLeft(
          find.byKey(const ValueKey<String>('suggestion-row-s_p0_0002')),
        )
        .dy;
    expect(firstTop, lessThan(secondTop));

    expect(find.text('Familienname'), findsOneWidget);
    expect(find.text(de.suggestionTypeText), findsOneWidget);
    expect(find.text(de.suggestionPage(1)), findsNWidgets(2));
    expect(find.text(de.suggestionPosition('190', '148')), findsOneWidget);
    expect(find.text(de.suggestionConfidence(87)), findsOneWidget);
    expect(find.text(de.suggestionTypeDate), findsOneWidget);
    expect(
      find.text(de.suggestionPosition('190,125', '216,25')),
      findsOneWidget,
    );
    expect(find.text(de.suggestionConfidence(74)), findsOneWidget);
    expect(find.text(de.suggestionOpenCount(3)), findsOneWidget);
    expect(find.text(de.suggestionFieldCount(0)), findsOneWidget);
    expect(find.text(de.suggestionConfirmAction), findsNWidgets(3));
    expect(find.text(de.suggestionRejectAction), findsNWidgets(3));
  });

  testWidgets('shows fallback, uncertain, conflict, and progress markers', (
    WidgetTester tester,
  ) async {
    final AppLocalizations de = lookupAppLocalizations(const Locale('de'));
    final core.FieldSuggestion conflicting = _suggestion(
      id: 's_p0_0001',
      pageIndex: 0,
      type: core.FieldType.checkbox,
      rect: core.Rect.fromLTWH(190, 502, 10, 10),
      confidence: 0.49,
      labelText: null,
      conflictsWith: <String>['s_p0_0002'],
    );
    final core.FieldSuggestion confirmed = _suggestion(
      id: 's_p0_0002',
      pageIndex: 0,
      type: core.FieldType.text,
      rect: core.Rect.fromLTWH(200, 502, 20, 10),
      confidence: 0.8,
      labelText: 'Bereits geprüft',
      resolution: core.SuggestionResolution.confirmed,
    );
    final core.FieldSuggestion rejected = _suggestion(
      id: 's_p0_0003',
      pageIndex: 0,
      type: core.FieldType.text,
      rect: core.Rect.fromLTWH(220, 502, 20, 10),
      confidence: 0.8,
      labelText: 'Abgelehnt',
      resolution: core.SuggestionResolution.rejected,
    );
    final core.FieldSuggestion signature = _signatureSuggestion(
      id: 's_p0_0004',
      rect: core.Rect.fromLTWH(190, 612, 300, 30),
      confidence: 0.8,
      labelText: 'Unterschrift Antragsteller',
    );

    await tester.pumpWidget(
      _host(
        _panel(
          suggestions: <core.FieldSuggestion>[
            conflicting,
            confirmed,
            rejected,
            signature,
          ],
          confirmedFieldCount: 1,
        ),
      ),
    );

    expect(find.text(de.suggestionRowFallback), findsOneWidget);
    expect(find.text(de.suggestionTypeCheckbox), findsOneWidget);
    expect(find.text(de.suggestionTypeSignature), findsOneWidget);
    expect(find.text(de.suggestionUncertain), findsOneWidget);
    expect(find.text(de.suggestionConflict), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('conflict-badge-s_p0_0001')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conflict-badge-s_p0_0004')),
      findsNothing,
    );
    expect(find.text(de.suggestionConfidence(49)), findsOneWidget);
    expect(find.text(de.suggestionOpenCount(2)), findsOneWidget);
    expect(find.text(de.suggestionFieldCount(1)), findsOneWidget);
    expect(find.text(de.suggestionReviewProgress(1, 1)), findsOneWidget);
    expect(find.text('Bereits geprüft'), findsNothing);
    expect(find.text('Abgelehnt'), findsNothing);
  });

  testWidgets('confirm, reject, and undo callbacks receive the exact value', (
    WidgetTester tester,
  ) async {
    final core.FieldSuggestion suggestion = _suggestion(
      id: 's_p0_0001',
      pageIndex: 0,
      type: core.FieldType.text,
      rect: core.Rect.fromLTWH(190, 148, 300, 18),
      confidence: 0.9,
      labelText: 'Familienname',
    );
    core.FieldSuggestion? confirmed;
    core.FieldSuggestion? rejected;
    int undoCalls = 0;

    await tester.pumpWidget(
      _host(
        _panel(
          suggestions: <core.FieldSuggestion>[suggestion],
          onConfirm: (core.FieldSuggestion value) => confirmed = value,
          onReject: (core.FieldSuggestion value) => rejected = value,
          onUndo: () => undoCalls++,
          undoAvailable: true,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('confirm-suggestion-s_p0_0001')),
    );
    await tester.pump();
    expect(confirmed, same(suggestion));
    expect(rejected, isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('reject-suggestion-s_p0_0001')),
    );
    await tester.pump();
    expect(rejected, same(suggestion));

    await tester.tap(find.byKey(const ValueKey<String>(undoReviewKey)));
    await tester.pump();
    expect(undoCalls, 1);
  });

  testWidgets('busy disables actions while a save is in flight', (
    WidgetTester tester,
  ) async {
    final core.FieldSuggestion suggestion = _suggestion(
      id: 's_p0_0001',
      pageIndex: 0,
      type: core.FieldType.text,
      rect: core.Rect.fromLTWH(190, 148, 300, 18),
      confidence: 0.9,
      labelText: 'Familienname',
    );
    int confirmCalls = 0;

    await tester.pumpWidget(
      _host(
        _panel(
          suggestions: <core.FieldSuggestion>[suggestion],
          onConfirm: (_) => confirmCalls++,
          undoAvailable: true,
          busy: true,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('confirm-suggestion-s_p0_0001')),
    );
    await tester.tap(find.byKey(const ValueKey<String>(undoReviewKey)));
    await tester.pump();
    expect(confirmCalls, 0);
    expect(
      find.byKey(const ValueKey<String>('suggestion-review-busy')),
      findsOneWidget,
    );
  });

  testWidgets('empty states distinguish no suggestions from all reviewed', (
    WidgetTester tester,
  ) async {
    final AppLocalizations de = lookupAppLocalizations(const Locale('de'));
    await tester.pumpWidget(_host(_panel(suggestions: const [])));
    expect(
      find.byKey(const ValueKey<String>(suggestionEmptyKey)),
      findsOneWidget,
    );
    expect(find.text(de.suggestionEmpty), findsOneWidget);

    final core.FieldSuggestion rejected = _suggestion(
      id: 's_p0_0001',
      pageIndex: 0,
      type: core.FieldType.text,
      rect: core.Rect.fromLTWH(190, 148, 300, 18),
      confidence: 0.9,
      labelText: 'Familienname',
      resolution: core.SuggestionResolution.rejected,
    );
    await tester.pumpWidget(
      _host(_panel(suggestions: <core.FieldSuggestion>[rejected])),
    );
    expect(find.text(de.suggestionAllReviewed), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>(suggestionEmptyKey)),
      findsOneWidget,
    );
  });

  testWidgets('no overflow at 200 % text scale', (WidgetTester tester) async {
    final List<core.FieldSuggestion> suggestions = <core.FieldSuggestion>[
      for (int index = 0; index < 6; index++)
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
        _panel(
          suggestions: suggestions,
          confirmedFieldCount: 3,
          undoAvailable: true,
        ),
        textScale: 2.0,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>(suggestionPanelKey)),
      findsOneWidget,
    );
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
