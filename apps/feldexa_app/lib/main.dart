import 'package:feldexa_app/bootstrap/startup_sweep.dart';
import 'package:feldexa_app/bootstrap/startup_sweep_app.dart';
import 'package:feldexa_app/bootstrap/startup_sweep_bootstrap.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  StartupSweepStartup startup;
  try {
    final StartupSweep? sweep = createAppStartupSweep();
    startup = sweep == null
        ? const StartupSweepStartup()
        : await runStartupSweepBounded(run: sweep.run);
  } catch (_) {
    // Startup recovery must never crash the shell. A construction or platform
    // failure degrades the startup state; it is not reported as success.
    startup = const StartupSweepStartup(failed: true);
  }
  runApp(FeldexaApp(startup: startup));
}

/// Root widget of the Feldexa application.
///
/// T002 initializes the Flutter application and its Android/Web hosts; T005
/// makes German the only release locale and renders the shell from the
/// generated `AppLocalizations` instead of hard-coded text (FR-090).
///
/// T031 runs the startup sweep before this shell is shown. [startup] carries
/// any localized recovery notices; a `null` value keeps the plain shell used
/// by the existing smoke test and by callers that do not own startup.
class FeldexaApp extends StatelessWidget {
  const FeldexaApp({super.key, this.startup});

  /// The bounded startup result, if this app launch ran one.
  final StartupSweepStartup? startup;

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
          final List<StartupSweepNotice> notices =
              startup?.notices ?? const <StartupSweepNotice>[];
          return Scaffold(
            appBar: AppBar(title: Text(l10n.appTitle)),
            body: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(l10n.startTitle),
                    for (final StartupSweepNotice notice in notices)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: _StartupRecoveryNotice(notice: notice),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Localized startup-recovery notice.
///
/// Every string comes from [StartupSweepNotice], whose text is resolved from
/// the committed German ARB by the sweep. No user-facing text is authored
/// here.
class _StartupRecoveryNotice extends StatelessWidget {
  const _StartupRecoveryNotice({required this.notice});

  final StartupSweepNotice notice;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? statusLabel = notice.statusLabel;
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (statusLabel != null) ...<Widget>[
            Text(statusLabel, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
          ],
          Text(notice.message, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(notice.recovery, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
