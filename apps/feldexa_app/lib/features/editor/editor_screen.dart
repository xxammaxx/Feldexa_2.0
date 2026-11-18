// T148 integrated US1 editor route: viewer, page strip, and page state.
//
// Owner: `apps/feldexa_app/lib/features/editor/editor_screen.dart` (T148).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/spec.md` US1/AC1, US1/AC2, US1/AC6,
//     FR-003, FR-010, and FR-018;
//   * `contracts/editor-interactions.md` §1 (app bar, page strip, viewport
//     order) and §6 (all pages with analysis state and unreadable markers,
//     tapping a page scrolls to it);
//   * `contracts/platform-channel.md` §3 (page failures are a successful
//     partial import; the initial revision and metadata are already committed);
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// This screen composes the existing T042 viewer, T043 strip, and T044 page
// state. It changes none of their files and uses only their public APIs:
// `PageViewController.fromImportedSource`, `PageView`, `PageStripController`,
// `PageStrip`, `PageStripPage`, `derivePageStates`, and the `IMP-006` warning.
//
// The screen receives the already-verified `ImportedSource` and a protected
// source-bytes resolver bound to its `documentId`. It never opens a path, URI,
// or display name, never renders a reconstructed page, and never creates or
// deletes a document. The viewer owns its pdfrx renderer; this screen owns and
// disposes only the layout and strip controllers.

import 'package:feldexa_app/features/editor/page_state.dart';
import 'package:feldexa_app/features/editor/page_strip.dart';
import 'package:feldexa_app/features/editor/page_view.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart' hide PageView;

/// The editor route for one successfully imported document.
class EditorScreen extends StatefulWidget {
  /// Creates the US1 editor route.
  ///
  /// [sourceBytes] is the protected-store resolver. [rendererFactory] defaults
  /// to the production pdfrx renderer and exists so host-VM tests inject a
  /// fake without a platform view or PDFium.
  const EditorScreen({
    required this.source,
    required this.sourceBytes,
    this.rendererFactory = openPdfrxPageRenderer,
    super.key,
  });

  /// The verified imported source, including preflight page geometry.
  final ImportedSource source;

  /// Resolves the protected source bytes; never a path or URI.
  final PageViewSourceBytes sourceBytes;

  /// Opens the viewer renderer for the resolved bytes.
  final PageViewRendererFactory rendererFactory;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final PageViewController _viewerController;
  late final PageStripController _stripController;
  late final List<PageStripPage> _stripPages;
  PageStateResult? _pageStates;

  @override
  void initState() {
    super.initState();
    final Set<int> unreadablePages = widget.source.pageFailures
        .map((failure) => failure.pageIndex)
        .toSet();
    _viewerController = PageViewController.fromImportedSource(widget.source);
    _stripController = PageStripController(viewer: _viewerController);
    _stripPages = List<PageStripPage>.unmodifiable(<PageStripPage>[
      for (int index = 0; index < widget.source.pageCount; index++)
        PageStripPage(unreadable: unreadablePages.contains(index)),
    ]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // German is the only release locale, so one derivation is sufficient. The
    // screen still derives after the first localization lookup rather than in
    // initState because every catalog sentence comes from AppLocalizations.
    _pageStates ??= derivePageStates(
      pages: <PageStateInput>[
        for (int index = 0; index < widget.source.pageCount; index++)
          _pageStateInput(index),
      ],
      localizations: AppLocalizations.of(context),
    );
  }

  PageStateInput _pageStateInput(int index) {
    final page = widget.source.pages[index];
    final bool unreadable = _stripPages[index].unreadable;
    return PageStateInput(
      index: index,
      analysis: unreadable
          ? PageAnalysisStatus.failed
          : PageAnalysisStatus.pending,
      unreadable: unreadable,
      failureMessageKey: unreadable ? imp006MessageKey : null,
      reportedDisplaySize: PageDisplaySize(
        widthPt: page.displaySize.width,
        heightPt: page.displaySize.height,
      ),
    );
  }

  @override
  void dispose() {
    _stripController.dispose();
    _viewerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final PageStateResult pageStates = _pageStates!;
    // `PageStateFullyUnreadable` is unreachable through a successful import
    // (T039 rejects an all-unreadable source). If it is ever supplied anyway,
    // the strip still marks every page unreadable and no IMP-006 success
    // warning is shown, so the error state is never presented as a warning.
    final PageStateWarning? warning = pageStates is PageStateSuccess
        ? pageStates.warning
        : null;
    return Scaffold(
      key: const ValueKey<String>('editor-screen'),
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            PageStrip(controller: _stripController, pages: _stripPages),
            if (warning != null) _Imp006Warning(warning: warning),
            Expanded(
              child: PageView(
                sourceId: widget.source.sourceId,
                sourceBytes: widget.sourceBytes,
                controller: _viewerController,
                rendererFactory: widget.rendererFactory,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Persistent German `IMP-006` warning for a partially readable document.
///
/// Both sentences come from the committed ARB through [PageStateWarning]. The
/// message already names the affected pages and states that a full export is
/// affected; no second wording, code, path, URI, or title is added here.
class _Imp006Warning extends StatelessWidget {
  const _Imp006Warning({required this.warning});

  final PageStateWarning warning;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      key: const ValueKey<String>('imp006-warning'),
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: theme.colorScheme.errorContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(warning.message, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(warning.recovery, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
