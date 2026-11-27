// T087 SIMULATED browser fill test (FR-086/FR-087).
//
// Fills the real text and checkbox controls in a browser: single-line rejects
// line breaks, multiline keeps them, Enter commits, checkbox toggles and
// disabled/read-only controls never call back. SIMULATED surface only; without
// Chrome on the host it is NOT_RUN.
//
// The committed helper `test/web_fill_browser_entry_test.dart` is a relative
// symlink so the browser runner can compile this file.

@TestOn('browser')
library;

import 'package:feldexa_app/features/fill/checkbox_control.dart';
import 'package:feldexa_app/features/fill/text_control.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

void main() {
  testWidgets('single-line input rejects line breaks and Enter commits', (
    WidgetTester tester,
  ) async {
    final List<String> changes = <String>[];
    final List<String> commits = <String>[];
    await tester.pumpWidget(
      _host(
        FieldTextControl(
          label: 'Familienname',
          value: '',
          onChanged: changes.add,
          onCommitted: commits.add,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(fieldTextControlInputKey),
      'Müller\nMeier',
    );
    await tester.pump();
    expect(changes.last, 'MüllerMeier');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(commits.last, 'MüllerMeier');
  });

  testWidgets('multiline input keeps line breaks', (WidgetTester tester) async {
    final List<String> changes = <String>[];
    await tester.pumpWidget(
      _host(
        FieldTextControl(
          label: 'Begründung',
          value: '',
          multiline: true,
          onChanged: changes.add,
          onCommitted: (_) {},
        ),
      ),
    );
    await tester.enterText(
      find.byKey(fieldTextControlInputKey),
      'Zeile 1\nZeile 2',
    );
    await tester.pump();
    expect(changes.last, 'Zeile 1\nZeile 2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('checkbox toggles once and never fires when read-only', (
    WidgetTester tester,
  ) async {
    final List<bool> toggles = <bool>[];
    await tester.pumpWidget(
      _host(
        FieldCheckboxControl(
          label: 'Antrag',
          value: false,
          onChanged: toggles.add,
        ),
      ),
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(toggles, <bool>[true]);

    await tester.pumpWidget(
      _host(
        FieldCheckboxControl(
          label: 'Antrag',
          value: false,
          readOnly: true,
          onChanged: toggles.add,
        ),
      ),
    );
    await tester.tap(find.byType(Checkbox), warnIfMissed: false);
    await tester.pump();
    expect(toggles, <bool>[true]);
    expect(tester.takeException(), isNull);
  });
}
