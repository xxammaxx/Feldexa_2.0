// T148 German start surface and production import composition.
//
// The T117 template-versions use case has no public barrel file; this
// consumer imports its stable source library deliberately, matching the
// editor composition.
// ignore_for_file: implementation_imports
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

import 'dart:async';

import 'package:feldexa_app/bootstrap/startup_sweep.dart';
import 'package:feldexa_app/bootstrap/startup_sweep_bootstrap.dart';
import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/page_view.dart';
import 'package:feldexa_app/features/start/import_error_mapper.dart';
import 'package:feldexa_app/features/start/import_runtime.dart';
import 'package:feldexa_app/features/start/stored_items.dart';
import 'package:feldexa_app/features/templates/use_template.dart';
import 'package:feldexa_application/src/templates/template_versions.dart'
    as versions;
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
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
  bool _openingStored = false;
  bool _storeAvailable = false;
  int _listGeneration = 0;
  List<DocumentSummary>? _documents;
  List<DocumentSummary>? _templates;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeStoredItems());
  }

  /// Creates the one runtime seam once and loads the start list when a store
  /// is already part of the composition.
  ///
  /// A construction failure keeps the existing import-only surface; it is not
  /// presented as an import failure because no import was attempted.
  Future<void> _initializeStoredItems() async {
    final ImportRuntime runtime;
    try {
      runtime = _runtime ??= widget.importRuntimeFactory();
    } on Object {
      return;
    }
    if (runtime.store == null) {
      return;
    }
    _storeAvailable = true;
    await _reloadStoredItems();
  }

  /// Re-reads both stored groups through the existing store.
  ///
  /// A read failure leaves the last successfully loaded list (or the
  /// import-only surface before the first success) unchanged. No second store
  /// or persisted projection is introduced.
  Future<void> _reloadStoredItems() async {
    final SecureStorePort? store = _runtime?.store;
    if (store == null) {
      return;
    }
    final int generation = ++_listGeneration;
    try {
      final List<StoredMeta> documents = await store.list(StoreKind.document);
      final List<StoredMeta> templates = await store.list(StoreKind.template);
      if (!mounted || generation != _listGeneration) {
        return;
      }
      setState(() {
        _documents = <DocumentSummary>[
          for (final StoredMeta meta in documents)
            DocumentSummary.fromStoredMeta(meta),
        ];
        _templates = <DocumentSummary>[
          for (final StoredMeta meta in templates)
            DocumentSummary.fromStoredMeta(meta),
        ];
        _storeAvailable = true;
      });
    } on Object {
      if (!mounted || generation != _listGeneration) {
        return;
      }
      setState(() {
        _documents ??= const <DocumentSummary>[];
        _templates ??= const <DocumentSummary>[];
      });
    }
  }

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
    if (mounted && runtime.store != null) {
      await _reloadStoredItems();
    }
  }

  /// Opens one readable stored document from the start list.
  ///
  /// The verified [LoadedDocument] is loaded through the same runtime store.
  /// Its metadata and persisted geometry become the [ImportedSource] contract,
  /// and the already decrypted bytes are handed to the editor viewer without a
  /// path. An unreadable entry is refused before any load.
  Future<void> _openStoredDocument(String documentId) async {
    if (_openingStored) {
      return;
    }
    final DocumentSummary? summary = _findSummary(documentId);
    if (summary == null || summary.status == StoredItemStatus.unreadable) {
      return;
    }
    final ImportRuntime? runtime = _runtime;
    final SecureStorePort? store = runtime?.store;
    if (runtime == null || store == null) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _openingStored = true;
      _failure = null;
    });
    ImportedSource source;
    LoadedDocument loaded;
    try {
      loaded = await store.loadDocument(documentId);
      source = _importedSourceFromLoaded(loaded);
      if (!mounted) {
        return;
      }
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _openingStored = false;
        _failure = ImportErrorMapper(l10n).unclassified();
      });
      return;
    }
    final EditorRuntime editorRuntime = runtime.createEditorRuntime();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => EditorScreen(
          source: source,
          sourceBytes: (String _) async => loaded.sourceBytes,
          runtime: editorRuntime,
          rendererFactory: widget.pageRendererFactory,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _openingStored = false;
    });
    await _reloadStoredItems();
  }

  /// T117 FR-059: creates a new independent document from the tapped
  /// template's latest version and opens it in the editor. The template
  /// aggregate is never mutated (FR-060); the derived document pins the
  /// loaded version (FR-104) with empty values and copied source pages
  /// (FR-059). Success is verified by the T117 use case before the editor
  /// opens; the list is refreshed BEFORE the editor route so
  /// `_openStoredDocument` finds the new entry, and the runtime created for
  /// ids/clock is disposed when nothing is navigated.
  Future<void> _useStoredTemplate(String templateId) async {
    final ImportRuntime? runtime = _runtime;
    final SecureStorePort? store = runtime?.store;
    if (runtime == null || store == null || _openingStored) {
      return;
    }
    if (templateId.trim().isEmpty) {
      // Programmer-error guard before any store call; no content is echoed.
      return;
    }
    setState(() {
      _openingStored = true;
      _failure = null;
    });
    EditorRuntime? created;
    Future<void> reset() async {
      await created?.dispose();
      created = null;
      if (mounted) {
        setState(() {
          _openingStored = false;
        });
      }
    }

    final LoadedTemplate loaded;
    try {
      loaded = await store.loadTemplate(templateId);
    } catch (_) {
      // Content-free: an unreadable template keeps its list entry and opens
      // nothing; the failure carries no template content.
      await reset();
      return;
    }
    if (!mounted) {
      await reset();
      return;
    }
    final versions.UseTemplateResult? result = await showUseTemplateSheet(
      context,
      templateTitle: loaded.template.meta.title,
      versionNumber: loaded.template.meta.latestVersion.versionNumber,
      onCreate: () async {
        // One runtime per creation attempt; a superseded one is disposed
        // before the next attempt and never leaked on the failure path.
        await created?.dispose();
        created = runtime.createEditorRuntime();
        return versions.useTemplate(
          store: store,
          templateId: templateId,
          documentId: created!.ids.newId(),
          initialRevisionId: created!.ids.newId(),
          initialKind: core.RevisionKind.explicit,
          title: loaded.template.meta.title,
          createdAt: created!.clock.nowUtc().toUtc(),
          source: loaded.template.meta.source,
        );
      },
    );
    await created?.dispose();
    created = null;
    if (result == null || !result.isSuccess) {
      await reset();
      return;
    }
    if (!mounted) {
      await reset();
      return;
    }
    await _reloadStoredItems();
    if (!mounted) {
      setState(() {
        _openingStored = false;
      });
      return;
    }
    setState(() {
      _openingStored = false;
    });
    await _openStoredDocument(result.meta!.id);
  }

  DocumentSummary? _findSummary(String id) {
    for (final DocumentSummary summary
        in _documents ?? const <DocumentSummary>[]) {
      if (summary.id == id) {
        return summary;
      }
    }
    return null;
  }

  /// Rebuilds the import contract from verified stored metadata and geometry.
  ImportedSource _importedSourceFromLoaded(LoadedDocument loaded) {
    final core.SourceFileRef ref = loaded.meta.source;
    if (loaded.content.pageCount != ref.pageCount) {
      throw StateError('stored page count does not match source metadata');
    }
    final List<core.PageFailure> failures = <core.PageFailure>[];
    for (final core.Page page in loaded.content.pages) {
      if (!page.unreadable && page.failure == null) {
        continue;
      }
      failures.add(
        page.failure ??
            core.PageFailure(
              pageIndex: page.index,
              category: core.PageFailureCategory.unreadable,
              messageKey: 'IMP-006',
            ),
      );
    }
    return ImportedSource(
      documentId: loaded.meta.id,
      sourceId: ref.id,
      sha256: ref.sha256,
      sizeBytes: ref.sizeBytes,
      pageCount: ref.pageCount,
      pages: <core.PageGeometry>[
        for (final core.Page page in loaded.content.pages) page.geometry,
      ],
      pageFailures: failures,
      displayName: ref.originalName,
      evidence: loaded.evidence,
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
      body: _storeAvailable
          ? _buildStoredBody(l10n, theme, notices)
          : _buildImportOnlyBody(l10n, theme, notices),
    );
  }

  /// Import-only start surface used when the composition has no store.
  Widget _buildImportOnlyBody(
    AppLocalizations l10n,
    ThemeData theme,
    List<StartupSweepNotice> notices,
  ) {
    return Center(
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
              _importButton(l10n),
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
    );
  }

  /// Start surface with the T095 stored document/template groups.
  ///
  /// The import action stays available above the list. Unreadable entries come
  /// from the same T095 projection and are refused by `_openStoredDocument`; no
  /// second status model is introduced. After the editor returns, the list is
  /// re-read through the same store.
  Widget _buildStoredBody(
    AppLocalizations l10n,
    ThemeData theme,
    List<StartupSweepNotice> notices,
  ) {
    final List<DocumentSummary>? documents = _documents;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                _importButton(l10n),
                if (_importing || _openingStored) ...<Widget>[
                  const SizedBox(height: 8),
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
                for (final StartupSweepNotice notice in notices)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _StartupRecoveryNotice(notice: notice),
                  ),
                if (_failure != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _ImportFailureNotice(failure: _failure!),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: documents == null
              ? const Center(child: CircularProgressIndicator())
              : StoredItemsView(
                  documents: documents,
                  templates: _templates ?? const <DocumentSummary>[],
                  onOpenDocument: (String id) {
                    unawaited(_openStoredDocument(id));
                  },
                  onOpenTemplate: (String id) {
                    // T117 FR-059: the one explicit "Vorlage verwenden"
                    // flow; opening the layout editor stays T116.
                    unawaited(_useStoredTemplate(id));
                  },
                ),
        ),
      ],
    );
  }

  Widget _importButton(AppLocalizations l10n) {
    return FilledButton.icon(
      key: const ValueKey<String>('import-action'),
      onPressed: _importing || _openingStored ? null : _startImport,
      icon: const Icon(Icons.picture_as_pdf_outlined),
      label: Text(l10n.importAction),
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
