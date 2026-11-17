import 'package:feldexa_app/bootstrap/session_end_sweep.dart';
import 'package:feldexa_app/bootstrap/startup_sweep.dart';
import 'package:feldexa_app/bootstrap/startup_sweep_app.dart';
import 'package:feldexa_app/bootstrap/startup_sweep_bootstrap.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  StartupSweepStartup startup;
  StartupSweep? sweep;
  try {
    sweep = createAppStartupSweep();
    startup = sweep == null
        ? const StartupSweepStartup()
        // The timeout bounds the caller's wait. `sweep.cancel` is the
        // cooperative stop that keeps a timed-out run from reading or deleting
        // anything after the shell already shows the start area.
        : await runStartupSweepBounded(run: sweep.run, onTimeout: sweep.cancel);
  } catch (_) {
    // Startup recovery must never crash the shell. A construction or platform
    // failure degrades the startup state; it is not reported as success.
    startup = const StartupSweepStartup(failed: true);
  }
  runApp(FeldexaApp(startup: startup, sweep: sweep));
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
///
/// The shell is also the documented session-end lifecycle owner: when [sweep]
/// is present, the state registers a [SessionEndSweepBinding] so
/// `contracts/storage-format.md` §4 step 4 ("any on session end") has a
/// production caller. Without that wiring the export-preview cleanup would only
/// ever run at startup.
class FeldexaApp extends StatefulWidget {
  const FeldexaApp({super.key, this.startup, this.sweep});

  /// The bounded startup result, if this app launch ran one.
  final StartupSweepStartup? startup;

  /// The production sweep that owns the session-end export-preview cleanup.
  ///
  /// `null` on targets without a production store/cache (and in the plain
  /// smoke shell); no lifecycle observer is then registered.
  final StartupSweep? sweep;

  @override
  State<FeldexaApp> createState() => _FeldexaAppState();
}

class _FeldexaAppState extends State<FeldexaApp> {
  SessionEndSweepBinding? _sessionEnd;

  @override
  void initState() {
    super.initState();
    _registerSessionEndSweep();
  }

  @override
  void didUpdateWidget(FeldexaApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sweep, widget.sweep)) {
      _unregisterSessionEndSweep();
      _registerSessionEndSweep();
    }
  }

  @override
  void dispose() {
    _unregisterSessionEndSweep();
    super.dispose();
  }

  void _registerSessionEndSweep() {
    final StartupSweep? sweep = widget.sweep;
    if (sweep == null) {
      return;
    }
    final SessionEndSweepBinding binding = SessionEndSweepBinding(sweep: sweep);
    _sessionEnd = binding;
    WidgetsBinding.instance.addObserver(binding);
  }

  void _unregisterSessionEndSweep() {
    final SessionEndSweepBinding? binding = _sessionEnd;
    if (binding == null) {
      return;
    }
    WidgetsBinding.instance.removeObserver(binding);
    _sessionEnd = null;
  }

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
          // A degraded startup always surfaces a German notice: either the
          // specific catalog notice the sweep produced, or the committed ARB
          // notice for an incomplete recovery. The shell never shows a plain
          // success state for a degraded run.
          final StartupSweepStartup? startup = widget.startup;
          final List<StartupSweepNotice> notices = startup == null
              ? const <StartupSweepNotice>[]
              : startupRecoveryNotices(startup, messages: l10n);
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
/// the committed German ARB by the sweep or by [startupRecoveryNotices]. No
/// user-facing text is authored here.
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
