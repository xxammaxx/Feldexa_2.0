// T073 field-order review list widget tests (FR-026).
//
// Evidence class: NONE. These are host-VM widget tests with synthetic
// revisions and recorded callbacks. They open no document, start no browser,
// emulator, or device, and make no Android runtime, screen-reader, or visual
// claim.

@TestOn('vm')
library;

import 'package:feldexa_app/features/editor/field_order.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _first = '11111111-1111-4111-8111-111111111111';
const String _second = '22222222-2222-4222-8222-222222222222';
const String _third = '33333333-3333-4333-8333-333333333333';
const String _suggestionId = 's_p0_0001';
const String _conflictId = 's_p0_0002';

final DateTime _at = DateTime.utc(2026, 11, 21, 8);
final AppLocalizations _de = lookupAppLocalizations(const Locale('de'));

core.Page _page(int index) {
  return core.Page(
    index: index,
    geometry: core.PageGeometry(mediaBox: core.Rect.fromLTWH(0, 0, 300, 300)),
    analysis: core.AnalysisState.complete,
  );
}

core.RevisionContent _content() {
  final List<core.ConfirmedField> fields = <core.ConfirmedField>[
    core.ConfirmedField(
      id: _first,
      pageIndex: 0,
      rect: core.Rect.fromLTWH(40, 40, 100, 20),
      type: core.FieldType.text,
      provenance: core.Provenance.machine,
      sourceSuggestionId: _suggestionId,
      suggestionConfidence: 0.82,
      label: 'Name',
      order: 0,
      createdAt: _at,
      updatedAt: _at,
    ),
    core.ConfirmedField(
      id: _second,
      pageIndex: 0,
      rect: core.Rect.fromLTWH(40, 100, 100, 20),
      type: core.FieldType.number,
      provenance: core.Provenance.user,
      label: 'Betrag',
      order: 1,
      createdAt: _at,
      updatedAt: _at,
    ),
    core.ConfirmedField(
      id: _third,
      pageIndex: 1,
      rect: core.Rect.fromLTWH(40, 40, 100, 20),
      type: core.FieldType.checkbox,
      provenance: core.Provenance.template,
      label: 'Zustimmung',
      order: 2,
      createdAt: _at,
      updatedAt: _at,
    ),
  ];
  return core.RevisionContent(
    pages: <core.Page>[_page(0), _page(1)],
    suggestions: <core.FieldSuggestion>[
      core.FieldSuggestion(
        id: _suggestionId,
        pageIndex: 0,
        rect: core.Rect.fromLTWH(40, 40, 100, 20),
        proposedType: core.FieldType.text,
        confidence: 0.82,
        labelText: 'Name',
        evidence: core.SuggestionEvidence(
          cues: const <core.SuggestionCue>[core.SuggestionCue.underline],
          ocrUsed: false,
        ),
        conflictsWith: <String>[_conflictId],
        resolution: core.SuggestionResolution.confirmed,
      ),
      core.FieldSuggestion(
        id: _conflictId,
        pageIndex: 0,
        rect: core.Rect.fromLTWH(50, 40, 100, 20),
        proposedType: core.FieldType.text,
        confidence: 0.60,
        labelText: 'Name',
        evidence: core.SuggestionEvidence(
          cues: const <core.SuggestionCue>[core.SuggestionCue.underline],
          ocrUsed: false,
        ),
        conflictsWith: <String>[_suggestionId],
      ),
    ],
    fields: fields,
    fieldOrder: <String>[_first, _second, _third],
    values: <String, core.FieldValue>{
      _first: core.TextValue(text: 'Ada', lastEditedAt: _at),
    },
  );
}

core.RevisionContent _emptyContent() {
  return core.RevisionContent(
    pages: <core.Page>[_page(0)],
    fieldOrder: const <String>[],
  );
}

Widget _host(Widget child, {double textScale = 1}) {
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
      body: Center(child: SizedBox(width: 360, height: 600, child: child)),
    ),
  );
}

Widget _list(
  core.RevisionContent content, {
  ValueChanged<String>? onMoveUp,
  ValueChanged<String>? onMoveDown,
  ValueChanged<String>? onSelect,
  bool busy = false,
}) {
  return FieldOrderReviewList(
    content: content,
    busy: busy,
    onMoveUp: onMoveUp ?? (String _) {},
    onMoveDown: onMoveDown ?? (String _) {},
    onSelect: onSelect ?? (String _) {},
  );
}

void main() {
  testWidgets('renders the current order with all required metadata', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(_list(_content())));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>(fieldOrderListKey)), findsOne);
    expect(
      find.byKey(const ValueKey<String>('$fieldOrderRowKeyPrefix$_first')),
      findsOne,
    );
    expect(tester.takeException(), isNull);

    expect(find.text('Name'), findsOne);
    expect(find.text('Betrag'), findsOne);
    expect(find.text('Zustimmung'), findsOne);
    expect(find.text(_de.fieldOrderPosition(1, 3)), findsOne);
    expect(find.text(_de.fieldOrderPosition(3, 3)), findsOne);
    expect(find.text(_de.suggestionPage(2)), findsOne);
    expect(find.text(_de.suggestionTypeNumber), findsOne);
    expect(find.text(_de.suggestionTypeCheckbox), findsOne);
    expect(find.text(_de.a11yFieldStatusConfirmed), findsOne);
    expect(find.text(_de.a11yFieldStatusSelfCreated), findsOne);
    expect(find.text(_de.templateLabel), findsOne);
    expect(find.text(_de.suggestionConfidence(82)), findsOne);
    expect(find.text(_de.suggestionConflict), findsOne);
    expect(find.text(_de.fieldCompletionComplete), findsWidgets);
    expect(find.text(_de.fieldCompletionOptionalEmpty), findsWidgets);

    final List<String> labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text text) => text.data ?? '')
        .toList();
    expect(
      labels.indexOf('Name'),
      lessThan(labels.indexOf('Betrag')),
      reason: 'rows must render in the current field order',
    );
    expect(
      labels.indexOf('Betrag'),
      lessThan(labels.indexOf('Zustimmung')),
      reason: 'rows must render in the current field order',
    );
  });

  testWidgets('move actions report the exact field and respect boundaries', (
    WidgetTester tester,
  ) async {
    final List<String> up = <String>[];
    final List<String> down = <String>[];
    await tester.pumpWidget(
      _host(_list(_content(), onMoveUp: up.add, onMoveDown: down.add)),
    );
    await tester.pumpAndSettle();

    IconButton button(String key) =>
        tester.widget<IconButton>(find.byKey(ValueKey<String>(key)));

    expect(button('$fieldOrderMoveUpKeyPrefix$_first').onPressed, isNull);
    expect(button('$fieldOrderMoveDownKeyPrefix$_third').onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('$fieldOrderMoveDownKeyPrefix$_first')),
    );
    await tester.pump();
    expect(down, <String>[_first]);

    await tester.tap(
      find.byKey(const ValueKey<String>('$fieldOrderMoveUpKeyPrefix$_third')),
    );
    await tester.pump();
    expect(up, <String>[_third]);
  });

  testWidgets('busy disables every move action', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        _list(
          _content(),
          busy: true,
          onMoveUp: (String _) {},
          onMoveDown: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final String id in <String>[_first, _second, _third]) {
      final IconButton up = tester.widget<IconButton>(
        find.byKey(ValueKey<String>('$fieldOrderMoveUpKeyPrefix$id')),
      );
      final IconButton down = tester.widget<IconButton>(
        find.byKey(ValueKey<String>('$fieldOrderMoveDownKeyPrefix$id')),
      );
      expect(up.onPressed, isNull);
      expect(down.onPressed, isNull);
    }
  });

  testWidgets('a row tap selects that field', (WidgetTester tester) async {
    final List<String> selected = <String>[];
    await tester.pumpWidget(_host(_list(_content(), onSelect: selected.add)));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('$fieldOrderSelectKeyPrefix$_second')),
    );
    await tester.pump();
    expect(selected, <String>[_second]);
  });

  testWidgets('shows the German empty state', (WidgetTester tester) async {
    await tester.pumpWidget(_host(_list(_emptyContent())));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>(fieldOrderEmptyKey)), findsOne);
    expect(find.text(_de.fieldOrderEmpty), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('composes at 200 % text scale without an overflow', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(_list(_content()), textScale: 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey<String>(fieldOrderListKey)), findsOne);
  });
}
