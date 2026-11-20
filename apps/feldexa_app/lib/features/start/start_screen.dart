// T148 German start surface and production import composition.
//
// Owner: `apps/feldexa_app/lib/features/start/start_screen.dart` (T148).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/spec.md` US1/AC1, US1/AC2, US1/AC6,
//     FR-001, FR-003, FR-009, FR-010, and FR-090;
//   * `contracts/editor-interactions.md` §1 (the start surface is outside the
//     editor regions; the import action is the US1 entry point);
//   * `contracts/platform-channel.md` §2.2/§3 (`pickAndImport` commits the
//     initial revision and metadata before its success reply);
//   * constitution Principles II, III, VI, VIII, and X.
//
// The screen owns no platform API. The injected [ImportRuntime] supplies the
// real `AndroidImportClient` on Android, and `ImportFlow` is the only code that
// turns a platform failure into German text. On `ImportAccepted` the screen
// opens the editor with the runtime store read-back closure for the imported
// `documentId`; the viewer resolves no path and no URI.
//
// The screen is testable with an injected runtime and an injected page-renderer
// factory. The widget test in `test/app_import_composition_test.dart` uses fake
// implementations and therefore builds no platform channel.

import 'package:feldexa_app/bootstrap/startup_sweep.dart';
import 'package:feldexa_app/bootstrap/startup_sweep_bootstrap.dart';
import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/page_view.dart';
import 'package:feldexa_app/features/start/import_error_mapper.dart';
import 'package:feldexa_app/features/start/import_runtime.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart' hide PageView;

/// The German start surface and US1 import entry point.
class StartScreen extends StatefulWidget {
  /// Creates the start surface.
  ///
  /// [startup] carries any localized startup-recovery notices. The factories
  /// are explicit seams: production defaults are supplied by `FeldexaApp`, and
  /// host-VM widget tests inject fakes so no platform channel is constructed.
  const StartScreen({
    required this.importRuntimeFactory,
    required this.pageRendererFactory,
    this.startup,
    super.key,
  });

  /// The bounded startup result, if this app launch ran one.
  final StartupSweepStartup? startup;

  /// Builds the platform import composition for this target.
  final ImportRuntime Function() importRuntimeFactory;

  /// Opens the pdfrx renderer in the editor; tests inject a fake.
  final PageViewRendererFactory pageRendererFactory;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  ImportRuntime? _runtime;
  ImportFailurePresentation? _failure;
  bool _importing = false;

  Future<void> _startImport() async {
    if (_importing) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ImportRuntime runtime;
    try {
      runtime = _runtime ??= widget.importRuntimeFactory();
    } on Exception {
      // A composition failure is not an import success and must not crash the
      // shell. The existing mapper supplies the truthful unknown-cause text.
      setState(() {
        _failure = ImportErrorMapper(l10n).unclassified();
      });
      return;
    }

    setState(() {
      _importing = true;
      _failure = null;
    });

    final ImportFlow flow = ImportFlow(
      localizations: l10n,
      createDocument: _documentAccepted,
    );
    ImportOutcome outcome;
    try {
      outcome = await flow.run(
        port: runtime.importPort,
        request: ImportRequest(),
      );
    } on Exception {
      // `ImportFlow` maps typed port failures; this guard covers an escaped
      // adapter or creation exception without inventing a success state.
      outcome = ImportRejected(flow.mapper.unclassified());
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _importing = false;
    });

    if (outcome is ImportRejected) {
      final ImportFailurePresentation failure = outcome.failure;
      setState(() {
        _failure = failure;
      });
      return;
    }
    if (outcome is ImportAccepted) {
      await _openEditor(outcome.document.source, runtime);
    }
    // `ImportCancelled` returns to the unchanged start surface with no message
    // (FR-009); no document was created.
  }

  /// The FR-009 document-creation gate.
  ///
  /// `import.pickAndImport` already committed the initial revision and the
  /// document metadata before it returned the verified source
  /// (`contracts/platform-channel.md` §3). This callback is therefore called
  /// exactly once for an accepted candidate and performs no additional write.
  /// The protected source itself is read back through the runtime store when
  /// the editor's `PageView` resolves it.
  Future<void> _documentAccepted(ImportedDocumentCandidate document) async {}

  Future<void> _openEditor(ImportedSource source, ImportRuntime runtime) async {
    // One editor composition per session. The editor disposes it on close; a
    // shared import operation client is not disposed by the editor runtime.
    final EditorRuntime editorRuntime = runtime.createEditorRuntime();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => EditorScreen(
          source: source,
          // The viewer is given the imported document identity, never a path.
          // `PageView` passes its opaque source id to this closure; the
          // protected bytes are resolved by the runtime store for documentId.
          sourceBytes: (String _) => runtime.readSourceBytes(source.documentId),
          runtime: editorRuntime,
          rendererFactory: widget.pageRendererFactory,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final StartupSweepStartup? startup = widget.startup;
    final List<StartupSweepNotice> notices = startup == null
        ? const <StartupSweepNotice>[]
        : startupRecoveryNotices(startup, messages: l10n);
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey<String>('start-screen'),
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  l10n.startTitle,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(l10n.emptyDocuments, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const ValueKey<String>('import-action'),
                  onPressed: _importing ? null : _startImport,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(l10n.importAction),
                ),
                if (_importing) ...<Widget>[
                  const SizedBox(height: 16),
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
                for (final StartupSweepNotice notice in notices)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _StartupRecoveryNotice(notice: notice),
                  ),
                if (_failure != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _ImportFailureNotice(failure: _failure!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Localized import failure: catalog message and recovery, never a code.
class _ImportFailureNotice extends StatelessWidget {
  const _ImportFailureNotice({required this.failure});

  final ImportFailurePresentation failure;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? message = failure.message;
    final String? recovery = failure.recovery;
    if (message == null && recovery == null) {
      return const SizedBox.shrink();
    }
    return Semantics(
      key: const ValueKey<String>('import-failure'),
      container: true,
      liveRegion: true,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (message != null)
              Text(message, style: theme.textTheme.bodyMedium),
            if (recovery != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(recovery, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
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
