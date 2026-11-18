// T044 partially unreadable pages and the IMP-006 warning.
//
// Owner: `apps/feldexa_app/lib/features/editor/page_state.dart` (T044,
// issue #44).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/spec.md` FR-010 (a partially readable
//     document stays usable, affected pages are marked, and the user is told
//     that a full export is affected) and FR-094 (status is readable text, not
//     color-only);
//   * `specs/001-scanned-form-workflow/contracts/error-catalog.de.md` §1
//     (`IMP-006` is a warning attached to a *successful* import) and §8
//     (status vocabulary `Nicht lesbar`);
//   * `specs/001-scanned-form-workflow/contracts/editor-interactions.md` §1
//     and §6 (the page strip shows every page with its analysis state and
//     unreadable/uncertain markers);
//   * `specs/001-scanned-form-workflow/contracts/platform-channel.md` §3
//     (`IMP-006` succeeds with `pages[].unreadable` and `pageFailures`);
//   * `specs/001-scanned-form-workflow/data-model.md` §3.3 (the canonical
//     `Page`, `PageFailure`, and analysis states);
//   * `specs/001-scanned-form-workflow/reports/2026-11-18-t040-evidence.md`
//     (the persisted 1x1 placeholder for structurally unreadable pages);
//   * constitution Principles V, VI, VIII, and X.
//
// This file is a pure projection. It creates no document, revision, draft,
// template, or stored record; it opens no storage; it performs no network
// call; it logs no path, URI, title, page content, or failure text; and it
// re-renders no page. The only output text is resolved from the committed
// German `AppLocalizations`; no German sentence, catalog code, or second
// warning message is written here.
//
// Why a local input projection
// ----------------------------
// `apps/feldexa_app` declares `feldexa_core` as a dev dependency only, so
// `lib/` must not import the canonical `Page`/`AnalysisState`/`PageFailure`
// types. [PageStateInput] is the app-facing, content-free projection of one
// persisted page: index, analysis state, `unreadable`, the catalog
// `messageKey`, and the reported display size. A caller maps a canonical
// `Page` to it without this file duplicating the persisted model. The phase
// names follow the task vocabulary (`pending`, `analyzing`, `ready`, `failed`)
// and map one-to-one to the canonical `AnalysisState` wire values
// (`pending`, `running`, `complete`, `failed`).
//
// Unreadable pages and the 1x1 placeholder
// ----------------------------------------
// T039 reports null geometry for a page whose structure could not be read,
// while the persisted `Page` and the channel page shape require a positive
// box. T040 therefore persists such a page with a deterministic 1x1 pt
// placeholder box, `unreadable = true`, `analysis: failed`, and an `IMP-006`
// `PageFailure`. That placeholder is never the original page geometry.
//
// A page is unreadable when either `unreadable == true`, or its analysis is
// `failed` and its failure `messageKey` is `IMP-006`. Every unreadable page is
// non-renderable: [PageState.displaySize] is `null`, so no caller can present
// the 1x1 placeholder (or any other reported box of an unreadable page) as a
// real page size. The placeholder is only tolerated on input; it is never
// copied into the derived state. A readable page that reports 1x1 is treated
// as reporting 1x1, because this projection never infers unreadability from a
// size alone.
//
// A fully readable document yields a success with no warning. A partially
// unreadable document also yields a success, with one [PageStateWarning]
// resolved from `AppLocalizations.imp006(pages)` and `imp006Recovery`; it is
// not an error state and nothing is deleted. A fully unreadable document is
// out of scope for a successful import (T039 rejects it), so this API returns
// the explicit [PageStateFullyUnreadable] error state instead of inventing a
// document or a warning for it.

import 'package:feldexa_app/l10n/app_localizations.dart';

/// The only catalog key that marks an import-unreadable page.
///
/// This is a machine identifier used for classification and diagnostics. It
/// is never rendered; user text comes from [AppLocalizations].
const String imp006MessageKey = 'IMP-006';

/// The app-facing analysis phase of one page.
///
/// The four values map one-to-one to the canonical `AnalysisState` wire values
/// in `packages/feldexa_core/lib/src/model/document.dart`
/// (`pending`, `running`, `complete`, `failed`). The task and UI vocabulary
/// uses `analyzing` and `ready`; the persisted tokens are unchanged.
enum PageAnalysisStatus {
  /// No analysis run has started; the page is readable.
  pending,

  /// Analysis is running; the page is readable.
  analyzing,

  /// Analysis completed; the page is readable.
  ready,

  /// Analysis failed. The page stays readable and renderable unless it is also
  /// marked unreadable (see [PageState.isUnreadable]).
  failed,
}

/// A finite, positive page display size in PDF points.
///
/// This is the projection used by [PageStateInput], not a second geometry
/// model: it carries the width and height of `PageGeometry.displaySize` only.
/// Rotation, CropBox offsets, and source coordinates remain owned by the
/// canonical geometry. The type is deliberately independent of the
/// rendering-layer `PageViewPageSize` so this state model never imports pdfrx;
/// a viewer or page strip can pass [widthPt] and [heightPt] to it.
final class PageDisplaySize {
  /// Creates a display size.
  ///
  /// [widthPt] and [heightPt] must be finite and greater than zero. The error
  /// never echoes content.
  factory PageDisplaySize({required double widthPt, required double heightPt}) {
    if (!widthPt.isFinite || !heightPt.isFinite) {
      throw ArgumentError('page display size must be finite');
    }
    if (widthPt <= 0 || heightPt <= 0) {
      throw ArgumentError('page display size must be positive');
    }
    return PageDisplaySize._(widthPt, heightPt);
  }

  const PageDisplaySize._(this.widthPt, this.heightPt);

  /// Display width in PDF points.
  final double widthPt;

  /// Display height in PDF points.
  final double heightPt;

  @override
  String toString() => 'PageDisplaySize(${widthPt}pt, ${heightPt}pt)';
}

/// The content-free projection of one persisted page.
///
/// A caller maps the canonical `Page` as follows:
///
/// * `index` ← `Page.index` (0-based);
/// * `analysis` ← `Page.analysis` (`pending`/`running`/`complete`/`failed`);
/// * `unreadable` ← `Page.unreadable`;
/// * `failureMessageKey` ← `Page.failure?.messageKey` (required exactly when
///   the analysis failed);
/// * `reportedDisplaySize` ← `Page.geometry.displaySize`, except that an
///   unreadable page may pass `null`. The T040 1x1 placeholder may be passed
///   and is deliberately ignored by the derived state.
///
/// The input carries no document id, title, display name, path, URI, or page
/// content, so it cannot leak them into a user-visible label.
final class PageStateInput {
  /// Creates one page projection.
  ///
  /// [index] must be at least zero and page indices must be contiguous from
  /// zero across the document. [failureMessageKey] is required exactly when
  /// [analysis] is [PageAnalysisStatus.failed] and must be a catalog key such
  /// as `IMP-006`. A page that is not unreadable requires a
  /// [reportedDisplaySize]. Invalid values throw a content-free
  /// [ArgumentError].
  factory PageStateInput({
    required int index,
    required PageAnalysisStatus analysis,
    bool unreadable = false,
    String? failureMessageKey,
    PageDisplaySize? reportedDisplaySize,
  }) {
    if (index < 0) {
      throw ArgumentError('index must be at least 0');
    }
    final bool failed = analysis == PageAnalysisStatus.failed;
    if (failed != (failureMessageKey != null)) {
      throw ArgumentError(
        'failureMessageKey is required exactly when analysis is failed',
      );
    }
    if (failureMessageKey != null &&
        !_catalogKeyPattern.hasMatch(failureMessageKey)) {
      throw ArgumentError(
        'failureMessageKey must be a catalog key such as IMP-006',
      );
    }
    final bool isUnreadable =
        unreadable || (failed && failureMessageKey == imp006MessageKey);
    if (!isUnreadable && reportedDisplaySize == null) {
      throw ArgumentError('a readable page requires a reported display size');
    }
    return PageStateInput._(
      index,
      analysis,
      unreadable,
      failureMessageKey,
      reportedDisplaySize,
    );
  }

  const PageStateInput._(
    this.index,
    this.analysis,
    this.unreadable,
    this.failureMessageKey,
    this._reportedDisplaySize,
  );

  /// Zero-based page index in original document order.
  final int index;

  /// Analysis phase of the page.
  final PageAnalysisStatus analysis;

  /// Whether `Page.unreadable` was set by the import path.
  final bool unreadable;

  /// The persisted catalog key, or `null` when the analysis did not fail.
  ///
  /// This is machine metadata for classification and diagnostics only; it is
  /// never rendered.
  final String? failureMessageKey;

  /// The reported size, including a possible 1x1 placeholder.
  ///
  /// Deliberately private: only [derivePageStates] reads it, and it copies the
  /// value into [PageState.displaySize] only for readable pages.
  final PageDisplaySize? _reportedDisplaySize;

  /// Whether this input is unreadable by either documented signal.
  bool get _isUnreadable =>
      unreadable ||
      (analysis == PageAnalysisStatus.failed &&
          failureMessageKey == imp006MessageKey);

  @override
  String toString() =>
      'PageStateInput(index: $index, analysis: ${analysis.name}, '
      'unreadable: $_isUnreadable)';
}

/// The derived state of one page.
///
/// [pageIndex] is zero-based; [pageNumber] is the 1-based number shown in
/// German text and semantics. [displaySize] is non-null exactly for a
/// renderable page; an unreadable page always reports `null`, never the T040
/// 1x1 placeholder. [statusLabel] is German catalog text when the catalog
/// defines a page-level status (an unreadable page or a failed analysis), and
/// `null` otherwise; a color-only marker is never the only signal.
final class PageState {
  const PageState._({
    required this.pageIndex,
    required this.analysis,
    required this.isUnreadable,
    required this.displaySize,
    required this.statusLabel,
    required this.failureMessageKey,
  });

  /// Zero-based page index in original document order.
  final int pageIndex;

  /// The analysis phase reported for the page.
  final PageAnalysisStatus analysis;

  /// Whether the page content is unreadable and therefore non-renderable.
  final bool isUnreadable;

  /// The renderable page display size, or `null` for an unreadable page.
  ///
  /// The T040 1x1 placeholder is never exposed here.
  final PageDisplaySize? displaySize;

  /// German catalog status text suitable for a semantic hint, or `null`.
  ///
  /// An unreadable page uses the catalog status `Nicht lesbar`; a readable
  /// page whose analysis failed uses the `REC-002` sentence with its 1-based
  /// page number. The readable `pending`, `analyzing`, and `ready` phases have
  /// no page-level status-vocabulary row, so they return `null` rather than an
  /// invented label. The page strip can combine this text with
  /// `AppLocalizations.a11yPageNavigation(page, count)`. The text is resolved
  /// at derivation time from the supplied [AppLocalizations]; derive again if
  /// the locale changes.
  final String? statusLabel;

  /// The persisted catalog key, or `null` when the analysis did not fail.
  ///
  /// Machine metadata for tests and diagnostics only; never render it.
  final String? failureMessageKey;

  /// The 1-based page number used by German text and semantics.
  int get pageNumber => pageIndex + 1;

  /// Whether the page remains usable after a partial import (FR-010).
  ///
  /// A readable page is usable even when its analysis failed; an unreadable
  /// page is not renderable and exposes no [displaySize].
  bool get isUsable => !isUnreadable;

  /// Whether this is a readable page whose analysis failed.
  bool get isAnalysisFailed =>
      analysis == PageAnalysisStatus.failed && !isUnreadable;

  @override
  String toString() =>
      'PageState(index: $pageIndex, analysis: ${analysis.name}, '
      'unreadable: $isUnreadable)';
}

/// The `IMP-006` warning for a successful partial import.
///
/// [message] and [recovery] are the exact catalog sentences resolved through
/// [AppLocalizations]; [message] already states that an export of the complete
/// document is affected, so [affectsFullExport] is a structural flag and adds
/// no second message. [pageNumbers] are ascending and 1-based.
///
/// T041's import flow shows its own one-shot `ImportPartialWarning` at the end
/// of the import. This editor-level warning carries the same catalog sentences
/// for as long as the opened document is presented; both resolve the text from
/// the same ARB and neither defines its own German wording.
final class PageStateWarning {
  PageStateWarning._({
    required this.message,
    required this.recovery,
    required List<int> pageNumbers,
  }) : pageNumbers = List<int>.unmodifiable(pageNumbers);

  /// Exact German warning with the affected page numbers filled in.
  final String message;

  /// Exact German recovery guidance for the warning.
  final String recovery;

  /// Affected pages as ascending 1-based page numbers.
  final List<int> pageNumbers;

  /// Whether a full export is affected; always `true` for this warning.
  ///
  /// The catalog sentence in [message] is the only user-visible statement of
  /// that fact.
  bool get affectsFullExport => true;

  @override
  String toString() =>
      'PageStateWarning(pageNumbers: ${pageNumbers.join(', ')})';
}

/// The result of deriving page states for one document.
///
/// Exactly one subclass is returned. [PageStateSuccess] is a successful
/// result even when it carries the `IMP-006` warning; a partial import is not
/// an error and deletes nothing. [PageStateFullyUnreadable] is the explicit
/// error state for input that the import path itself rejects.
sealed class PageStateResult {
  PageStateResult._({
    required List<PageState> pages,
    required List<PageState> unreadablePages,
    required List<int> unreadablePageNumbers,
  }) : pages = List<PageState>.unmodifiable(pages),
       unreadablePages = List<PageState>.unmodifiable(unreadablePages),
       unreadablePageNumbers = List<int>.unmodifiable(unreadablePageNumbers);

  /// Every page in ascending original order.
  final List<PageState> pages;

  /// The unreadable pages, in ascending original order.
  final List<PageState> unreadablePages;

  /// The affected pages as ascending 1-based page numbers.
  final List<int> unreadablePageNumbers;

  /// Whether this result may be presented as a successful import.
  bool get isSuccess;

  /// Whether this result is the explicit fully-unreadable error state.
  bool get isErrorState => !isSuccess;

  /// The number of readable, usable pages.
  int get readablePageCount => pages.length - unreadablePages.length;

  /// The number of unreadable, non-renderable pages.
  int get unreadablePageCount => unreadablePages.length;
}

/// A successful result: fully readable or partially unreadable.
final class PageStateSuccess extends PageStateResult {
  // The base constructor is private and named, so super parameters cannot
  // forward to it; the explicit super call is intentional.
  // ignore: use_super_parameters
  PageStateSuccess._({
    required List<PageState> pages,
    required List<PageState> unreadablePages,
    required List<int> unreadablePageNumbers,
    required this.warning,
  }) : super._(
         pages: pages,
         unreadablePages: unreadablePages,
         unreadablePageNumbers: unreadablePageNumbers,
       );

  /// The `IMP-006` warning, or `null` when every page is readable.
  final PageStateWarning? warning;

  @override
  bool get isSuccess => true;

  /// Whether the document is a successful partial import with a warning.
  bool get isPartiallyUnreadable => warning != null;

  /// Whether every page is readable and no warning is shown.
  bool get isFullyReadable => warning == null;

  /// Whether the catalog warning states that a full export is affected.
  bool get isFullExportAffected => warning != null;
}

/// The explicit error state for a document with no readable page.
///
/// The import path rejects an all-unreadable source (T039), so this state is
/// not reachable through a successful import. It exists so the derivation is
/// total and never presents an all-unreadable source as a document. It carries
/// no `IMP-006` warning: the warning is attached to a successful import only.
/// Callers must not create, present, or continue a document from this result.
final class PageStateFullyUnreadable extends PageStateResult {
  // The base constructor is private and named, so super parameters cannot
  // forward to it; the explicit super call is intentional.
  // ignore: use_super_parameters
  PageStateFullyUnreadable._({
    required List<PageState> pages,
    required List<PageState> unreadablePages,
    required List<int> unreadablePageNumbers,
  }) : super._(
         pages: pages,
         unreadablePages: unreadablePages,
         unreadablePageNumbers: unreadablePageNumbers,
       );

  @override
  bool get isSuccess => false;
}

/// Derives the per-page state and the `IMP-006` warning for one document.
///
/// [pages] must contain exactly one entry per page, with contiguous 0-based
/// indices; order is irrelevant. [localizations] supplies every German
/// sentence. The result is a [PageStateSuccess] for a fully or partially
/// readable document, or [PageStateFullyUnreadable] when no page is readable.
///
/// Throws a content-free [ArgumentError] for an empty page collection, a
/// duplicate or non-contiguous index, or an invalid [PageStateInput].
PageStateResult derivePageStates({
  required Iterable<PageStateInput> pages,
  required AppLocalizations localizations,
}) {
  final List<PageStateInput> inputs = List<PageStateInput>.of(pages)
    ..sort((PageStateInput a, PageStateInput b) => a.index.compareTo(b.index));
  if (inputs.isEmpty) {
    throw ArgumentError('a document requires at least one page');
  }
  for (int position = 0; position < inputs.length; position++) {
    if (inputs[position].index != position) {
      throw ArgumentError('page indices must be contiguous and unique from 0');
    }
  }

  final List<PageState> states = <PageState>[];
  final List<PageState> unreadablePages = <PageState>[];
  final List<int> unreadablePageNumbers = <int>[];
  for (final PageStateInput input in inputs) {
    final bool isUnreadable = input._isUnreadable;
    final PageDisplaySize? displaySize = isUnreadable
        ? null
        : input._reportedDisplaySize;
    final String? statusLabel = isUnreadable
        ? localizations.statusUnreadable
        : input.analysis == PageAnalysisStatus.failed
        ? localizations.rec002(input.index + 1)
        : null;
    final PageState state = PageState._(
      pageIndex: input.index,
      analysis: input.analysis,
      isUnreadable: isUnreadable,
      displaySize: displaySize,
      statusLabel: statusLabel,
      failureMessageKey: input.failureMessageKey,
    );
    states.add(state);
    if (isUnreadable) {
      unreadablePages.add(state);
      unreadablePageNumbers.add(state.pageNumber);
    }
  }

  if (unreadablePages.isEmpty) {
    return PageStateSuccess._(
      pages: states,
      unreadablePages: const <PageState>[],
      unreadablePageNumbers: const <int>[],
      warning: null,
    );
  }
  if (unreadablePages.length == states.length) {
    return PageStateFullyUnreadable._(
      pages: states,
      unreadablePages: unreadablePages,
      unreadablePageNumbers: unreadablePageNumbers,
    );
  }

  final List<int> affected = List<int>.unmodifiable(unreadablePageNumbers);
  return PageStateSuccess._(
    pages: states,
    unreadablePages: unreadablePages,
    unreadablePageNumbers: affected,
    warning: PageStateWarning._(
      message: localizations.imp006(affected.join(', ')),
      recovery: localizations.imp006Recovery,
      pageNumbers: affected,
    ),
  );
}

/// German catalog keys are compact stable codes such as `IMP-006`.
final RegExp _catalogKeyPattern = RegExp(r'^[A-Z]{2,6}-[0-9]{3}$');
