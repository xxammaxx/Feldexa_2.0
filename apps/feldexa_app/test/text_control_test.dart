// T079 reusable text control host widget tests.
//
// Evidence class: NONE. These are host-VM widget tests with synthetic values.
// They build no platform channel, open no document, invoke no editor, store,
// or localization code, and make no Android, device, input-method,
// screen-reader, or visual claim.
//
// They prove the pinned T079 behaviour:
//   * caller-supplied labels and values render, and German umlauts round-trip;
//   * single-line input drops typed or pasted line breaks;
//   * multiline input preserves line breaks and uses the multiline keyboard;
//   * Enter commits once and then invokes the caller's next action;
//   * focus loss commits a changed value exactly once;
//   * an external value synchronizes only while unfocused;
//   * previous/next buttons use caller tooltips and are omitted when null;
//   * 10,001 characters survive without truncation;
//   * read-only and disabled controls neither change nor commit;
//   * the control builds at 200 % text scale without throwing;
//   * only injected callbacks fire and the production source imports no ARB,
//     editor, or persistence module.

@TestOn('vm')
library;

import 'dart:io';

import 'package:feldexa_app/features/fill/text_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double width = 360, double textScale = 1.0}) {
  return MaterialApp(
    builder: (BuildContext context, Widget? widget) {
      return MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: widget!,
      );
    },
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

String _fieldText(WidgetTester tester) {
  return tester.widget<TextField>(find.byType(TextField)).controller!.text;
}

bool _hasFocus(WidgetTester tester) {
  return tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus;
}

Future<void> _unfocus(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
}

void main() {
  testWidgets('renders the caller label and initial value', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        FieldTextControl(
          label: 'Familienname',
          value: 'Müller',
          onChanged: (_) {},
          onCommitted: (_) {},
        ),
      ),
    );

    expect(find.text('Familienname'), findsWidgets);
    expect(find.text('Müller'), findsOneWidget);
    expect(_fieldText(tester), 'Müller');
  });

  testWidgets('round-trips German umlauts through onChanged', (
    WidgetTester tester,
  ) async {
    final List<String> changes = <String>[];
    await tester.pumpWidget(
      _host(
        FieldTextControl(
          label: 'Notiz',
          value: 'Grüße',
          onChanged: changes.add,
          onCommitted: (_) {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Müller äöüß');
    await tester.pump();

    expect(changes, <String>['Müller äöüß']);
    expect(_fieldText(tester), 'Müller äöüß');
  });

  testWidgets('single-line mode filters a pasted line break', (
    WidgetTester tester,
  ) async {
    final List<String> changes = <String>[];
    await tester.pumpWidget(
      _host(
        FieldTextControl(
          label: 'Straße',
          value: '',
          onChanged: changes.add,
          onCommitted: (_) {},
        ),
      ),
    );

    final TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.maxLines, 1);
    expect(field.textInputAction, TextInputAction.done);

    await tester.enterText(find.byType(TextField), 'Zeile1\nZeile2');
    await tester.pump();

    expect(_fieldText(tester), 'Zeile1Zeile2');
    expect(changes, <String>['Zeile1Zeile2']);
    expect(changes.join(), isNot(contains('\n')));
  });

  testWidgets('multiline mode preserves line breaks', (
    WidgetTester tester,
  ) async {
    final List<String> changes = <String>[];
    final List<String> commits = <String>[];
    await tester.pumpWidget(
      _host(
        FieldTextControl(
          label: 'Bemerkung',
          value: '',
          multiline: true,
          onChanged: changes.add,
          onCommitted: commits.add,
        ),
      ),
    );

    final TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.maxLines, isNull);
    expect(field.keyboardType, TextInputType.multiline);
    expect(field.textInputAction, TextInputAction.newline);

    await tester.enterText(find.byType(TextField), 'a\nb');
    await tester.pump();

    expect(_fieldText(tester), 'a\nb');
    expect(changes, <String>['a\nb']);

    await _unfocus(tester);
    expect(commits, <String>['a\nb']);
  });

  testWidgets('Enter commits once and then calls onNext', (
    WidgetTester tester,
  ) async {
    final List<String> commits = <String>[];
    int nextCalls = 0;
    await tester.pumpWidget(
      _host(
        FieldTextControl(
          label: 'Vorname',
          value: '',
          onChanged: (_) {},
          onCommitted: commits.add,
          onNext: () => nextCalls++,
          nextLabel: 'Nächstes Feld',
        ),
      ),
    );

    final TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.textInputAction, TextInputAction.next);

    await tester.enterText(find.byType(TextField), 'Termin');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    expect(commits, <String>['Termin']);
    expect(nextCalls, 1);

    await _unfocus(tester);
    expect(commits, <String>['Termin']);
  });

  testWidgets('focus loss after an edit commits exactly once', (
    WidgetTester tester,
  ) async {
    final List<String> commits = <String>[];
    await tester.pumpWidget(
      _host(
        FieldTextControl(
          label: 'Ort',
          value: '',
          onChanged: (_) {},
          onCommitted: commits.add,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Hamburg');
    await tester.pump();
    await _unfocus(tester);

    expect(commits, <String>['Hamburg']);

    await tester.showKeyboard(find.byType(TextField));
    await tester.pump();
    expect(_hasFocus(tester), isTrue);
    await _unfocus(tester);

    expect(commits, <String>['Hamburg']);
  });

  testWidgets('multiline done action commits once and unfocuses', (
    WidgetTester tester,
  ) async {
    final List<String> commits = <String>[];
    await tester.pumpWidget(
      _host(
        FieldTextControl(
          label: 'Bemerkung',
          value: '',
          multiline: true,
          doneLabel: 'Eingabe übernehmen',
          onChanged: (_) {},
          onCommitted: commits.add,
        ),
      ),
    );

    expect(find.byTooltip('Eingabe übernehmen'), findsOneWidget);
    expect(find.byKey(fieldTextControlDoneKey), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'a\nb');
    await tester.pump();
    await tester.tap(find.byKey(fieldTextControlDoneKey));
    await tester.pump();

    expect(commits, <String>['a\nb']);
    expect(_fieldText(tester), 'a\nb');
    expect(_hasFocus(tester), isFalse);

    await tester.showKeyboard(find.byType(TextField));
    await tester.pump();
    await _unfocus(tester);
    expect(commits, <String>['a\nb']);
  });

  testWidgets('multiline done action is absent without a caller label', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        FieldTextControl(
          label: 'Bemerkung',
          value: '',
          multiline: true,
          onChanged: (_) {},
          onCommitted: (_) {},
        ),
      ),
    );

    expect(find.byKey(fieldTextControlDoneKey), findsNothing);

    await tester.pumpWidget(
      _host(
        FieldTextControl(
          label: 'Bemerkung',
          value: '',
          multiline: true,
          doneLabel: 'Eingabe abschließen',
          onChanged: (_) {},
          onCommitted: (_) {},
        ),
      ),
    );

    expect(find.byKey(fieldTextControlDoneKey), findsOneWidget);
  });

  testWidgets('external value synchronizes only while unfocused', (
    WidgetTester tester,
  ) async {
    late StateSetter setHostState;
    String externalValue = 'erste Fassung';
    final List<String> changes = <String>[];
    final List<String> commits = <String>[];

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            setHostState = setState;
            return FieldTextControl(
              label: 'Notiz',
              value: externalValue,
              onChanged: changes.add,
              onCommitted: commits.add,
            );
          },
        ),
      ),
    );

    expect(_fieldText(tester), 'erste Fassung');

    setHostState(() {
      externalValue = 'zweite Fassung';
    });
    await tester.pump();

    expect(_fieldText(tester), 'zweite Fassung');
    expect(changes, isEmpty);
    expect(commits, isEmpty);

    await tester.showKeyboard(find.byType(TextField));
    await tester.pump();
    await _unfocus(tester);
    expect(commits, isEmpty);

    await tester.showKeyboard(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'getippter Text');
    await tester.pump();

    setHostState(() {
      externalValue = 'zweite Fassung';
    });
    await tester.pump();

    expect(_fieldText(tester), 'getippter Text');
    expect(changes, <String>['getippter Text']);

    await _unfocus(tester);
    expect(commits, <String>['getippter Text']);
  });

  testWidgets('previous and next callbacks fire with caller tooltips', (
    WidgetTester tester,
  ) async {
    int previousCalls = 0;
    int nextCalls = 0;
    await tester.pumpWidget(
      _host(
        FieldTextControl(
          label: 'Straße',
          value: '',
          onChanged: (_) {},
          onCommitted: (_) {},
          onPrevious: () => previousCalls++,
          onNext: () => nextCalls++,
          previousLabel: 'Vorheriges Feld',
          nextLabel: 'Nächstes Feld',
        ),
      ),
    );

    expect(find.byTooltip('Vorheriges Feld'), findsOneWidget);
    expect(find.byTooltip('Nächstes Feld'), findsOneWidget);

    await tester.tap(find.byKey(fieldTextControlPreviousKey));
    await tester.pump();
    expect(previousCalls, 1);

    await tester.tap(find.byKey(fieldTextControlNextKey));
    await tester.pump();
    expect(nextCalls, 1);
  });

  testWidgets('previous and next buttons are omitted when callbacks are null', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        FieldTextControl(
          label: 'Straße',
          value: '',
          onChanged: (_) {},
          onCommitted: (_) {},
          onNext: () {},
          nextLabel: 'Nächstes Feld',
        ),
      ),
    );

    expect(find.byKey(fieldTextControlPreviousKey), findsNothing);
    expect(find.byKey(fieldTextControlNextKey), findsOneWidget);

    await tester.pumpWidget(
      _host(
        FieldTextControl(
          label: 'Straße',
          value: '',
          onChanged: (_) {},
          onCommitted: (_) {},
        ),
      ),
    );

    expect(find.byKey(fieldTextControlPreviousKey), findsNothing);
    expect(find.byKey(fieldTextControlNextKey), findsNothing);
  });

  testWidgets('preserves 10,001 characters without truncation', (
    WidgetTester tester,
  ) async {
    final String longText = 'a' * 10001;
    final List<String> changes = <String>[];
    final List<String> commits = <String>[];

    await tester.pumpWidget(
      _host(
        FieldTextControl(
          label: 'Langtext',
          value: '',
          onChanged: changes.add,
          onCommitted: commits.add,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), longText);
    await tester.pump();

    expect(_fieldText(tester).length, 10001);
    expect(_fieldText(tester), longText);
    expect(changes.single.length, 10001);
    expect(changes.single, longText);

    await _unfocus(tester);
    expect(commits.single.length, 10001);
    expect(commits.single, longText);
  });

  testWidgets('read-only mode changes nothing and commits nothing', (
    WidgetTester tester,
  ) async {
    final List<String> changes = <String>[];
    final List<String> commits = <String>[];

    await tester.pumpWidget(
      _host(
        FieldTextControl(
          label: 'Status',
          value: 'fest',
          readOnly: true,
          onChanged: changes.add,
          onCommitted: commits.add,
        ),
      ),
    );

    final TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.readOnly, isTrue);

    await tester.showKeyboard(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'geändert');
    await tester.pump();
    await _unfocus(tester);

    expect(_fieldText(tester), 'fest');
    expect(changes, isEmpty);
    expect(commits, isEmpty);
  });

  testWidgets('disabled mode changes nothing and commits nothing', (
    WidgetTester tester,
  ) async {
    final List<String> changes = <String>[];
    final List<String> commits = <String>[];

    await tester.pumpWidget(
      _host(
        FieldTextControl(
          label: 'Status',
          value: 'fest',
          enabled: false,
          onChanged: changes.add,
          onCommitted: commits.add,
        ),
      ),
    );

    final TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);

    await tester.tap(find.byType(TextField), warnIfMissed: false);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'geändert');
    await tester.pump();
    await _unfocus(tester);

    expect(_fieldText(tester), 'fest');
    expect(changes, isEmpty);
    expect(commits, isEmpty);
  });

  testWidgets('builds at 200 percent text scale without throwing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        FieldTextControl(
          label: 'Anschrift',
          value: 'Müllerstraße 1, 10115 Berlin',
          multiline: true,
          doneLabel: 'Eingabe übernehmen',
          onChanged: (_) {},
          onCommitted: (_) {},
          onPrevious: () {},
          onNext: () {},
          previousLabel: 'Vorheriges Feld',
          nextLabel: 'Nächstes Feld',
        ),
        width: 320,
        textScale: 2,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('fires only injected callbacks for edits and submission', (
    WidgetTester tester,
  ) async {
    final List<String> changes = <String>[];
    final List<String> commits = <String>[];
    int nextCalls = 0;

    await tester.pumpWidget(
      _host(
        FieldTextControl(
          label: 'Ort',
          value: '',
          onChanged: changes.add,
          onCommitted: commits.add,
          onNext: () => nextCalls++,
          nextLabel: 'Nächstes Feld',
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'nur lokal');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    await _unfocus(tester);

    expect(changes, <String>['nur lokal']);
    expect(commits, <String>['nur lokal']);
    expect(nextCalls, 1);
  });

  test('production source imports no ARB, editor, or persistence module', () {
    final File file = File('lib/features/fill/text_control.dart');
    expect(file.existsSync(), isTrue);

    final String source = file.readAsStringSync();
    final List<String> imports = RegExp(
      r"^import '([^']+)';",
      multiLine: true,
    ).allMatches(source).map((Match match) => match.group(1)!).toList();

    expect(imports, <String>[
      'package:flutter/material.dart',
      'package:flutter/services.dart',
    ]);
    expect(source, isNot(contains('AppLocalizations')));
    expect(source, isNot(contains('features/editor')));
    expect(source, isNot(contains('feldexa_ports')));
    expect(source, isNot(contains('feldexa_application')));
    expect(source, isNot(contains('shared_preferences')));
    expect(source, isNot(contains('dart:io')));
    expect(RegExp('[äöüÄÖÜß]').hasMatch(source), isFalse);
  });
}
