import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the Feldexa shell in German', (tester) async {
    await tester.pumpWidget(const FeldexaApp());

    expect(find.byType(FeldexaApp), findsOneWidget);
    expect(find.text('Feldexa'), findsOneWidget);
    expect(find.text('Meine Dokumente'), findsOneWidget);

    final context = tester.element(find.byType(Scaffold));
    expect(Localizations.localeOf(context), const Locale('de'));
    expect(AppLocalizations.of(context).appTitle, 'Feldexa');
  });
}
