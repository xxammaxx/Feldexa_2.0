import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const FeldexaApp());
}

/// Root widget of the Feldexa application.
///
/// T002 initializes the Flutter application and its Android/Web hosts; T005
/// makes German the only release locale and renders the shell from the
/// generated `AppLocalizations` instead of hard-coded text (FR-090).
class FeldexaApp extends StatelessWidget {
  const FeldexaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return Scaffold(
            appBar: AppBar(title: Text(l10n.appTitle)),
            body: Center(child: Text(l10n.startTitle)),
          );
        },
      ),
    );
  }
}
