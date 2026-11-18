// T043 page-strip navigation before analysis finishes.
//
// Owner: `apps/feldexa_app/lib/features/editor/page_strip.dart` (T043,
// issue #43).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/spec.md` FR-018 (pages remain navigable
//     while analysis of other pages is pending, running, or failed), FR-003
//     (all pages in original order), FR-090 (German user text), FR-091
//     (accessibility semantics), FR-093 (touch targets), and FR-094 (state is
//     not colour-only);
//   * `specs/001-scanned-form-workflow/contracts/editor-interactions.md`
//     section 1 (layout regions and the < 600 dp compact strip) and section 6
//     (all pages with analysis state and unreadable/uncertain markers; tapping
//     a page scrolls to it);
//   * `specs/001-scanned-form-workflow/data-model.md` §3.3 (`pending`,
//     `running`, `complete`, `failed`, `unreadable`);
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// What this file is
// -----------------
// A presentational horizontal page strip. It receives page metadata from the
// caller and never reads a document, analysis result, file, path, URI, title,
// page content, or renderer. It builds and stays interactive with every page
// in `pending` state, so navigation never waits for analysis to finish
// (FR-018). It does not rerender, reconstruct, or cache any source page.
//
// Navigation is delegated to the T042 viewer: tapping a page calls
// `PageViewController.scrollToPage`. This file does not implement scrolling,
// page layout, geometry, or rasterisation.
//
// `page_state.dart` (T044) owns the canonical partially-unreadable-page model
// and the `IMP-006` warning surface. This file deliberately defines only the
// minimal local input value [PageStripPage] (an analysis state plus unreadable
// and uncertain flags) so a later T044 adapter can map the canonical page state
// without either task editing the other's file.
//
// User-visible text
// -----------------
// Every string that exists in the committed German catalog is read from
// `AppLocalizations` or the German `MaterialLocalizations`; this file adds no
// ARB key and no catalog row. The four analysis-state words and their short
// visible forms are local presentation vocabulary because
// `contracts/error-catalog.de.md` §8 has no per-page analysis-state text yet;
// they are not codes, paths, URIs, titles, or document content, and they are
// German.
//
// Privacy
// -------
// The widget performs no I/O, opens no file, creates no temporary object, uses
// no network, and writes no log. Its only inputs are the supplied page count
// and per-page flags. Labels contain only the one-based page number and German
// state words.
//
// Test keys (stable, content-free)
// --------------------------------
// * `page-strip-page-<one-based page number>` — one page control.
// * `page-strip-indicator` — the compact current-page indicator.
// * `page-strip-previous` / `page-strip-next` — compact navigation buttons.

import 'package:feldexa_app/features/editor/page_view.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Widths strictly below this value use the compact page indicator.
///
/// The contract fixes the boundary at 600 dp; exactly 600 dp keeps the full
/// horizontal strip.
const double pageStripCompactBreakpoint = 600;

/// Horizontal width of one full-strip page control, in logical pixels.
///
/// The value is a fixed extent so the strip can jump to a far page without
/// building the pages in between. One unit is one Flutter logical pixel; no
/// document geometry or device pixel participates.
const double pageStripItemExtent = 112;

/// Height of the full horizontal strip at the default text scale, in logical
/// pixels. Larger system text scales increase the actual height so labels do
/// not overflow.
const double pageStripHeight = 92;

/// Height of the compact indicator row at the default text scale, in logical
/// pixels. Larger system text scales increase the actual height.
const double pageStripCompactHeight = 80;

/// The analysis state of one page, in the data model's vocabulary.
///
/// `pending` means analysis has not started or was cancelled (cancellation
/// leaves the page pending, not failed). `analyzing` is the model's `running`.
/// `ready` is the model's `complete`. `failed` means this page's analysis
/// failed; other pages remain unaffected. Every value is renderable and
/// tappable.
enum PageStripAnalysisState {
  /// Analysis has not started yet, or was cancelled.
  pending,

  /// Analysis is currently running for this page.
  analyzing,

  /// Analysis completed for this page.
  ready,

  /// Analysis failed for this page; the page stays usable.
  failed,
}

/// One page's strip metadata.
///
/// The list position is the zero-based document page index; this value carries
/// no index of its own. The flags are independent of the analysis state:
/// an unreadable page may also be failed, and an uncertain page may be ready.
/// The type is immutable and contains no content, title, path, or identifier.
final class PageStripPage {
  /// Creates strip metadata for one page.
  ///
  /// [unreadable] marks a page whose content could not be decoded at import
  /// (FR-010). [uncertain] marks a page whose analysis is uncertain, for
  /// example an unreliable orientation estimate.
  const PageStripPage({
    this.analysisState = PageStripAnalysisState.pending,
    this.unreadable = false,
    this.uncertain = false,
  });

  /// The page's current analysis state.
  final PageStripAnalysisState analysisState;

  /// Whether the page content is unreadable.
  final bool unreadable;

  /// Whether the page analysis is uncertain.
  final bool uncertain;
}

/// Selection state for [PageStrip], exposed to the editor.
///
/// Tapping a page in the strip calls [selectPage], which updates
/// [selectedPageIndex] and asks the supplied T042 [viewer] to scroll to that
/// page. The controller notifies listeners only when the selected page
/// changes; the viewer is not disposed by this object.
final class PageStripController extends ChangeNotifier {
  /// Creates a controller for [viewer] with an optional initial selection.
  ///
  /// [initialPageIndex] is zero-based and must be inside the viewer's page
  /// range. The page count is fixed by the viewer for the controller's
  /// lifetime; a new document needs a new controller and viewer.
  PageStripController({required this.viewer, int initialPageIndex = 0})
    : _selectedPageIndex = _validatedIndex(initialPageIndex, viewer.pageCount);

  /// The T042 viewer whose pages this strip navigates.
  final PageViewController viewer;

  int _selectedPageIndex;

  /// Number of pages in original document order.
  int get pageCount => viewer.pageCount;

  /// Zero-based index of the currently selected page.
  int get selectedPageIndex => _selectedPageIndex;

  /// Whether a previous page exists.
  bool get canSelectPrevious => _selectedPageIndex > 0;

  /// Whether a next page exists.
  bool get canSelectNext => _selectedPageIndex < pageCount - 1;

  /// Selects [pageIndex] and scrolls the viewer to its top.
  ///
  /// The viewer call is delegated to `PageViewController.scrollToPage`; this
  /// class never computes a scroll offset. Selecting the already selected page
  /// still scrolls the viewer to it but does not notify listeners.
  ///
  /// Throws [RangeError] when [pageIndex] is outside the document.
  void selectPage(int pageIndex) {
    _validatedIndex(pageIndex, pageCount);
    viewer.scrollToPage(pageIndex);
    if (pageIndex == _selectedPageIndex) {
      return;
    }
    _selectedPageIndex = pageIndex;
    notifyListeners();
  }

  /// Selects the previous page when one exists; otherwise does nothing.
  void selectPrevious() {
    if (canSelectPrevious) {
      selectPage(_selectedPageIndex - 1);
    }
  }

  /// Selects the next page when one exists; otherwise does nothing.
  void selectNext() {
    if (canSelectNext) {
      selectPage(_selectedPageIndex + 1);
    }
  }

  static int _validatedIndex(int pageIndex, int pageCount) {
    if (pageIndex < 0 || pageIndex >= pageCount) {
      throw RangeError.range(pageIndex, 0, pageCount - 1, 'pageIndex');
    }
    return pageIndex;
  }
}

/// A page strip that stays usable while page analysis is unfinished.
///
/// [pages] must contain exactly one entry per viewer page, in original
/// document order. The strip renders every page immediately; it has no
/// analysis-completion dependency and no placeholder blank state.
///
/// At widths of at least [pageStripCompactBreakpoint] it shows the horizontal
/// strip. Below that width it collapses to a current-page indicator with
/// previous/next buttons. Both presentations use one semantic button per
/// control and keep the selected page visible.
class PageStrip extends StatefulWidget {
  /// Creates a page strip for [controller]'s viewer.
  ///
  /// [pages] is the caller's read-only snapshot of per-page metadata. A later
  /// rebuild may supply updated states; the selection lives in [controller].
  const PageStrip({required this.controller, required this.pages, super.key});

  /// Selection state and viewer navigation.
  final PageStripController controller;

  /// Per-page metadata in original document order.
  final List<PageStripPage> pages;

  @override
  State<PageStrip> createState() => _PageStripState();
}

class _PageStripState extends State<PageStrip> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleSelectionChanged);
    _scheduleRevealSelectedPage();
  }

  @override
  void didUpdateWidget(covariant PageStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleSelectionChanged);
      widget.controller.addListener(_handleSelectionChanged);
    }
    _scheduleRevealSelectedPage();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleSelectionChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleSelectionChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _scheduleRevealSelectedPage();
  }

  void _scheduleRevealSelectedPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealSelectedPage();
    });
  }

  /// Keeps the selected control inside the horizontal viewport.
  ///
  /// The fixed [pageStripItemExtent] makes this arithmetic possible without
  /// building the intervening pages, so a 100-page document does not allocate
  /// 100 controls to reveal the last page.
  void _revealSelectedPage() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    final ScrollPosition position = _scrollController.position;
    final double itemStart =
        widget.controller.selectedPageIndex * pageStripItemExtent;
    final double itemEnd = itemStart + pageStripItemExtent;
    final double viewportWidth = position.viewportDimension;
    double target = position.pixels;
    if (itemStart < target) {
      target = itemStart;
    } else if (itemEnd > target + viewportWidth) {
      target = itemEnd - viewportWidth;
    }
    final double clamped = target
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    if ((clamped - position.pixels).abs() > 0.5) {
      _scrollController.jumpTo(clamped);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int pageCount = widget.controller.pageCount;
    if (widget.pages.length != pageCount) {
      throw ArgumentError.value(
        widget.pages.length,
        'pages',
        'must contain exactly $pageCount entries for the viewer',
      );
    }
    // The region width the editor gives the strip decides the presentation;
    // MediaQuery is only the fallback when the parent width is unbounded.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        if (availableWidth < pageStripCompactBreakpoint) {
          return _buildCompact(context);
        }
        return _buildStrip(context);
      },
    );
  }

  Widget _buildStrip(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      height: _scaledHeight(context, pageStripHeight),
      child: ColoredBox(
        color: theme.colorScheme.surface,
        child: ListView.builder(
          key: const ValueKey<String>('page-strip-list'),
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          itemExtent: pageStripItemExtent,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemCount: widget.controller.pageCount,
          itemBuilder: (BuildContext context, int pageIndex) {
            return _buildPageButton(context, pageIndex);
          },
        ),
      ),
    );
  }

  Widget _buildPageButton(BuildContext context, int pageIndex) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final PageStripPage page = widget.pages[pageIndex];
    final bool selected = widget.controller.selectedPageIndex == pageIndex;
    final int pageNumber = pageIndex + 1;
    final Color accent = theme.colorScheme.primary;

    return Semantics(
      key: ValueKey<String>('page-strip-page-$pageNumber'),
      container: true,
      button: true,
      selected: selected,
      label: _pageLabel(l10n, pageNumber),
      hint: _stateHint(l10n, page),
      onTap: () => widget.controller.selectPage(pageIndex),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: selected
              ? theme.colorScheme.secondaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              // Selection uses both a thicker outline and a top bar, so it is
              // not conveyed by colour alone (FR-094).
              color: selected ? accent : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: () => widget.controller.selectPage(pageIndex),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (selected)
                  Align(
                    alignment: Alignment.topCenter,
                    child: Container(height: 4, color: accent),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '$pageNumber',
                        maxLines: 1,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            _analysisIcon(page.analysisState),
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              _analysisShortLabel(page.analysisState),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (page.unreadable)
                        _markerRow(
                          context,
                          Icons.visibility_off_outlined,
                          l10n.statusUnreadable,
                        ),
                      if (page.uncertain)
                        _markerRow(
                          context,
                          Icons.help_outline,
                          _uncertainWord(l10n),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _markerRow(BuildContext context, IconData icon, String text) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompact(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final MaterialLocalizations material = MaterialLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final int pageIndex = widget.controller.selectedPageIndex;
    final PageStripPage page = widget.pages[pageIndex];
    final int pageNumber = pageIndex + 1;

    return SizedBox(
      height: _scaledHeight(context, pageStripCompactHeight),
      child: ColoredBox(
        color: theme.colorScheme.surface,
        child: Row(
          children: <Widget>[
            _compactButton(
              context,
              key: const ValueKey<String>('page-strip-previous'),
              label: material.previousPageTooltip,
              icon: Icons.chevron_left,
              onPressed: widget.controller.canSelectPrevious
                  ? widget.controller.selectPrevious
                  : null,
            ),
            Expanded(
              child: Semantics(
                key: const ValueKey<String>('page-strip-indicator'),
                container: true,
                liveRegion: true,
                label: _pageLabel(l10n, pageNumber),
                hint: _stateHint(l10n, page),
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        _pageLabel(l10n, pageNumber),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            _analysisIcon(page.analysisState),
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              _analysisHint(page.analysisState),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (page.unreadable || page.uncertain)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            if (page.unreadable)
                              Flexible(
                                child: _compactMarker(
                                  context,
                                  Icons.visibility_off_outlined,
                                  l10n.statusUnreadable,
                                ),
                              ),
                            if (page.unreadable && page.uncertain)
                              const SizedBox(width: 8),
                            if (page.uncertain)
                              Flexible(
                                child: _compactMarker(
                                  context,
                                  Icons.help_outline,
                                  _uncertainWord(l10n),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
            _compactButton(
              context,
              key: const ValueKey<String>('page-strip-next'),
              label: material.nextPageTooltip,
              icon: Icons.chevron_right,
              onPressed: widget.controller.canSelectNext
                  ? widget.controller.selectNext
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactMarker(BuildContext context, IconData icon, String text) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _compactButton(
    BuildContext context, {
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Semantics(
      key: key,
      container: true,
      button: true,
      enabled: onPressed != null,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: SizedBox(
        width: 56,
        height: 56,
        child: IconButton(
          onPressed: onPressed,
          tooltip: label,
          icon: Icon(icon),
        ),
      ),
    );
  }

  String _pageLabel(AppLocalizations l10n, int pageNumber) {
    return l10n.a11yPageNavigation(pageNumber, widget.controller.pageCount);
  }

  /// Grows a fixed presentation height with the system text scale.
  ///
  /// The default scale keeps [baseHeight] exactly; at 200 % the height grows
  /// by 60 % so single-line labels are not forced into a vertical overflow.
  double _scaledHeight(BuildContext context, double baseHeight) {
    final double scale = MediaQuery.textScalerOf(context)
        .scale(1)
        .clamp(1.0, 2.0)
        .toDouble();
    return baseHeight * (1 + (scale - 1) * 0.6);
  }

  String _stateHint(AppLocalizations l10n, PageStripPage page) {
    final List<String> parts = <String>[_analysisHint(page.analysisState)];
    if (page.unreadable) {
      parts.add(l10n.statusUnreadable);
    }
    if (page.uncertain) {
      parts.add(_uncertainWord(l10n));
    }
    return parts.join(', ');
  }

  /// Full German analysis-state text used by the compact indicator and hints.
  String _analysisHint(PageStripAnalysisState state) {
    switch (state) {
      case PageStripAnalysisState.pending:
        return 'Analyse ausstehend';
      case PageStripAnalysisState.analyzing:
        return 'Analyse läuft';
      case PageStripAnalysisState.ready:
        return 'Analyse abgeschlossen';
      case PageStripAnalysisState.failed:
        return 'Analyse fehlgeschlagen';
    }
  }

  /// Short visible analysis-state text for a narrow strip control.
  String _analysisShortLabel(PageStripAnalysisState state) {
    switch (state) {
      case PageStripAnalysisState.pending:
        return 'Wartet';
      case PageStripAnalysisState.analyzing:
        return 'Läuft';
      case PageStripAnalysisState.ready:
        return 'Fertig';
      case PageStripAnalysisState.failed:
        return 'Fehler';
    }
  }

  IconData _analysisIcon(PageStripAnalysisState state) {
    switch (state) {
      case PageStripAnalysisState.pending:
        return Icons.schedule;
      case PageStripAnalysisState.analyzing:
        return Icons.autorenew;
      case PageStripAnalysisState.ready:
        return Icons.check_circle_outline;
      case PageStripAnalysisState.failed:
        return Icons.error_outline;
    }
  }

  /// The catalog stores uncertainty as the optional suffix `, unsicher`.
  String _uncertainWord(AppLocalizations l10n) {
    const String prefix = ', ';
    final String catalog = l10n.a11yFieldUncertain;
    return catalog.startsWith(prefix)
        ? catalog.substring(prefix.length)
        : catalog;
  }
}
