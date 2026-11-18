import 'package:feldexa_app/bootstrap/session_end_sweep.dart';
import 'package:feldexa_app/bootstrap/startup_sweep.dart';
import 'package:feldexa_app/bootstrap/startup_sweep_app.dart';
import 'package:feldexa_app/bootstrap/startup_sweep_bootstrap.dart';
import 'package:feldexa_app/features/editor/page_view.dart';
import 'package:feldexa_app/features/start/import_runtime.dart';
import 'package:feldexa_app/features/start/start_screen.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart' hide PageView;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  StartupSweepStartup startup;
  StartupSweep? sweep;
  try {
    sweep = createAppStartupSweep();
    startup = sweep == null
        ? const StartupSweepStartup()
        // The timeout bounds the caller's wait. The bounded runner also passes
        // one absolute deadline into the native recovery, which stops at its
        // next destructive check; `sweep.cancel` is the cooperative stop for
        // the Dart staging pass and reads. The bounded plaintext export-preview
        // pass runs first and always completes.
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
///
/// T148 makes the shell render the German start surface and opens the US1
/// editor route from the production import composition. [importRuntimeFactory]
/// and [pageRendererFactory] are explicit injection seams: production uses the
/// real Android clients and pdfrx, while host-VM widget tests supply fakes and
/// construct no platform channel.
class FeldexaApp extends StatefulWidget {
  const FeldexaApp({
    super.key,
    this.startup,
    this.sweep,
    this.importRuntimeFactory = createImportRuntime,
    this.pageRendererFactory = openPdfrxPageRenderer,
  });

  /// The bounded startup result, if this app launch ran one.
  final StartupSweepStartup? startup;

  /// The production sweep that owns the session-end export-preview cleanup.
  ///
  /// `null` on targets without a production store/cache (and in the plain
  /// smoke shell); no lifecycle observer is then registered.
  final StartupSweep? sweep;

  /// Builds the platform import composition for the start surface.
  final ImportRuntime Function() importRuntimeFactory;

  /// Opens the pdfrx renderer in the editor; tests inject a fake.
  final PageViewRendererFactory pageRendererFactory;

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
      home: StartScreen(
        startup: widget.startup,
        importRuntimeFactory: widget.importRuntimeFactory,
        pageRendererFactory: widget.pageRendererFactory,
      ),
    );
  }
}
