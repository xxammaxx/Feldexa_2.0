// The Phase A use case and the T057 envelope do not yet have public barrel
// files; this consumer imports their stable source libraries deliberately,
// matching the Phase A composition and its tests.
// ignore_for_file: implementation_imports, depend_on_referenced_packages
//
// T148 integrated US1 editor route: viewer, page strip, and page state.
// Issue #217 Phase B1 adds the first analysis run and revision persistence.
//
// Owner: `apps/feldexa_app/lib/features/editor/editor_screen.dart` (T148,
// Phase B1).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/spec.md` US1/AC1, US1/AC2, US1/AC6,
//     FR-003, FR-010, FR-014, FR-017, FR-018, FR-019, FR-020, FR-021, and
//     FR-024;
//   * `contracts/editor-interactions.md` §1 (app bar, page strip, viewport
//     order) and §6 (all pages with analysis state and unreadable markers,
//     tapping a page scrolls to it);
//   * `contracts/recognition-output.md` §1 (envelope), §4 (failure contract),
//     §6 (symmetric conflicts), and §7 (persisted suggestions/provenance);
//   * `contracts/platform-channel.md` §3 (page failures are a successful
//     partial import; the initial revision and metadata are already committed);
//   * `data-model.md` §3.3 (page analysis state), §3.4 (`FieldSuggestion`),
//     §3.12 (`RevisionContent`), and §3.16 (`FieldSuggestionSet`);
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// This screen composes the existing T042 viewer, T043 strip, T044 page state,
// the Phase A `AnalyzeDocument` use case, the T057 envelope, and the T058
// `RevisionContent` invariants. It changes none of their files and creates no
// second runtime, store, orchestrator, contract, or UI surface.
//
// Phase B1 behavior and documented decisions
// ------------------------------------------
// * The viewer and strip are built synchronously from the imported source.
//   Loading and analysis run asynchronously and never block rendering or page
//   navigation (FR-018).
// * On first open the screen loads the current revision through
//   `EditorRuntime.loadDocument(documentId)`.
// * If that revision already has suggestions, analysis does not run and no
//   revision is written. The deterministic `analysis-skipped` state is exposed
//   for B2/tests; reanalysis is a later task.
// * A persisted analysis run is equally durable. The gate treats any
//   `complete` or `running` page, or any `failed` page that is not an
//   import-unreadable `IMP-006` page, as evidence that the first run already
//   happened. This keeps a partially unreadable first import analyzable (its
//   import-marked pages are failed while the readable pages are still
//   pending) while preventing a completed zero-suggestion run from
//   re-analyzing and autosaving on every reopen. The resulting
//   `analysis-skipped` state is deterministic.
// * Before any analysis, every loaded revision page must have the same
//   `PageGeometry` as the imported source page, and the page counts must
//   match. Rotation is compared exactly; the media and crop box edges may
//   differ by at most [pageGeometryTolerancePt] (0.001 pt) to absorb persisted
//   three-decimal quantization. Display size alone is insufficient because a
//   square page rotated 90° and one rotated 270° have the same size. A
//   mismatch is a content-free `analysis-failed` state: no analysis and no
//   save.
// * Otherwise the first analysis run covers every page the import did not mark
//   unreadable. The analysis-run id is `IdPort.newId()` (the port's UUIDv4
//   method; there is no `newUuid` member). Stage timings come from the use
//   case's monotonic `Stopwatch`; this screen keeps its own monotonic
//   `Stopwatch` only for a content-free overall duration.
// * The envelope's evidence class is `emulator` in debug builds and `device`
//   in release builds. That is a coarse build-mode label, not proof of the
//   hardware: a debug build on a device is still labelled `emulator`, and a
//   release build on an emulator is still labelled `device`. B1 makes no
//   `DEVICE` or `EMULATOR` evidence claim; the host tests use injected fakes.
// * A complete envelope becomes canonical `FieldSuggestion` values and the
//   whole snapshot is validated by the T058 `RevisionContent` constructor.
//   Suggestions are persisted `unresolved`; the analyzer already supplies
//   symmetric conflicts and neither candidate is removed.
// * A failed envelope updates only that page:
//   `rasterization` → `PageFailureCategory.rasterization` / `PAGE-001`;
//   `unsupported_structure` → `unsupportedStructure` / `REC-003`;
//   `internal` and `ocr` → `unsupportedStructure` / `REC-002`, because the core
//   page-failure vocabulary has no `internal`/`ocr` member and the task fixes
//   this lossy but content-free mapping. Cancelled pages stay unchanged
//   (`pending`), never failed.
// * A first run with no existing suggestions replaces the suggestion list,
//   writes one `RevisionKind.autosave` revision with
//   `expectedHead = loaded.meta.latestRevisionId`, and exposes
//   `analysis-ready` only after the store confirms the save.
// * A page failure, analysis exception, validation failure, or save failure
//   keeps the viewer, every other page, and manual editing available. Only a
//   content-free internal state key is surfaced; no new German string, code,
//   path, URI, label, or OCR text is rendered by B1.
// * `analysis-ready`, `analysis-skipped`, and `analysis-failed` are stable
//   value keys for B2 and tests. The loaded/analyzed `RevisionContent` is
//   exposed by [EditorScreenState.content].

import 'dart:async';
import 'dart:typed_data';

import 'package:feldexa_app/features/editor/document_overview.dart';
import 'package:feldexa_app/features/editor/durability_status.dart';
import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/editor/field_order.dart';
import 'package:feldexa_app/features/editor/field_value_sheet.dart';
import 'package:feldexa_app/features/editor/page_state.dart';
import 'package:feldexa_app/features/editor/page_strip.dart';
import 'package:feldexa_app/features/editor/page_view.dart';
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/features/fill/signature_png.dart';
import 'package:feldexa_app/features/fill/signature_sheet.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_application/src/recognition/analyze_document.dart'
    as analysis;
import 'package:feldexa_application/src/review/apply_signature.dart'
    as signature;
import 'package:feldexa_application/src/review/command_history.dart' as history;
import 'package:feldexa_application/src/review/confirm_suggestion.dart'
    as review;
import 'package:feldexa_application/src/review/edit_field.dart' as edit;
import 'package:feldexa_application/src/review/set_value.dart' as set_value;
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:feldexa_recognition/src/page_analysis.dart' as recognition;
import 'package:feldexa_ui/feldexa_ui.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart' hide PageView;

/// Stable key for a completed first analysis run whose revision was saved.
const String editorAnalysisReadyKey = 'analysis-ready';

/// Stable key for a revision that already had suggestions; no write occurred.
const String editorAnalysisSkippedKey = 'analysis-skipped';

/// Stable key for a content-free load/analysis/validation/save failure.
const String editorAnalysisFailedKey = 'analysis-failed';

/// Stable key for the T086D document overview action in the editor app bar.
const ValueKey<String> editorOverviewActionKey = ValueKey<String>(
  'editor-overview-action',
);

/// Maximum per-edge difference in PDF points when comparing page geometry.
///
/// Persisted revisions may quantize geometry to three decimal places. An
/// inclusive 0.001 pt tolerance therefore absorbs storage round-tripping while
/// still rejecting a genuinely different media box, crop box, or orientation.
const double pageGeometryTolerancePt = 0.001;

/// Minimum usable height reserved for the editor page viewport.
///
/// The warning and review panel above the viewer may shrink and scroll when
/// the IME or a 200 % text scale reduces the body height, but the page must
/// keep at least this many logical pixels. Only on bodies smaller than this
/// value does the header collapse completely and the viewer take what remains.
const double _minPageViewportHeight = 160;

/// Bound on the single editor `loadDocument` call.
///
/// A shared platform-channel result path that never answers must become the
/// deterministic `analysis-failed` state instead of an infinite pending editor.
/// The normal Android load is far below this bound; the timeout is a diagnostic
/// fail-closed guard, not a performance claim or a retry policy.
const Duration editorLoadTimeout = Duration(seconds: 30);

/// Bound on the single editor `AnalyzeDocument.run` call.
///
/// The use case already isolates per-page failures. This overall bound exists
/// only because a platform port can stop answering after the protected load
/// succeeded; it turns that unsatisfiable wait into the visible, content-free
/// `analysis-failed` state. It is a diagnostic fail-closed guard, not a
/// performance or retry policy.
///
/// The bound covers asynchronous port waits only. It cannot preempt
/// synchronous CPU-bound work on the UI isolate, such as a recognition
/// detector that blocks while scanning page geometry; recognition performance
/// is outside T071A scope.
const Duration editorAnalysisTimeout = Duration(minutes: 5);

/// Content-free integration diagnostic marker for the T071A editor path.
///
/// Only marker names, page indexes, counts, byte presence, booleans, and
/// stable failure categories/keys are printed. No source id, path, URI, title,
/// label, OCR text, entered value, or other document content can pass through
/// this helper.
void _analysisDiagnostic(String message) {
  if (kDebugMode) {
    debugPrint('T071A_DIAG_$message');
  }
}

/// Evidence class written into a Phase A envelope for the current build mode.
///
/// This is deliberately a build-mode label, not hardware detection. It follows
/// the Phase B1 task decision (`emulator` in debug, `device` in release) and
/// must never be read as an acceptance claim for either evidence class.
String editorEvidenceClass({bool debugMode = kDebugMode}) {
  return debugMode ? 'emulator' : 'device';
}

/// Maps one T057 recognition failure to the canonical core page failure.
///
/// `rasterization` keeps `PAGE-001`, `unsupported_structure` keeps `REC-003`,
/// and `internal`/`ocr` use the core `unsupported_structure` category with
/// `REC-002`. The core vocabulary has no `internal`/`ocr` member; the mapping
/// is lossy by design and never carries document content.
core.PageFailure pageFailureForAnalysis(
  recognition.PageAnalysisFailure failure, {
  required int pageIndex,
}) {
  switch (failure.category) {
    case recognition.PageAnalysisFailure.rasterization:
      return core.PageFailure(
        pageIndex: pageIndex,
        category: core.PageFailureCategory.rasterization,
        messageKey: 'PAGE-001',
      );
    case recognition.PageAnalysisFailure.unsupportedStructure:
      return core.PageFailure(
        pageIndex: pageIndex,
        category: core.PageFailureCategory.unsupportedStructure,
        messageKey: 'REC-003',
      );
    case recognition.PageAnalysisFailure.internal:
    case recognition.PageAnalysisFailure.ocr:
      return core.PageFailure(
        pageIndex: pageIndex,
        category: core.PageFailureCategory.unsupportedStructure,
        messageKey: 'REC-002',
      );
    default:
      return core.PageFailure(
        pageIndex: pageIndex,
        category: core.PageFailureCategory.unsupportedStructure,
        messageKey: 'REC-002',
      );
  }
}

/// Applies one Phase A analysis result to [base] and validates the snapshot.
///
/// Complete envelopes become canonical `FieldSuggestion` values with
/// `resolution = unresolved`, symmetric conflicts, and the envelope's
/// cues/contrast/ocrUsed evidence. Failed envelopes update only their own page
/// through [pageFailureForAnalysis] and contribute no suggestions. Pages absent
/// from [result] (cancelled by the use case) are returned unchanged, so a
/// pending page stays pending.
///
/// The returned value is constructed through the T058 `RevisionContent`
/// constructor. Every existing field, value, signature, verification,
/// template-origin, and unknown-field entry is preserved. The function does no
/// I/O and never mutates [base].
///
/// Precondition: [base] must have no suggestions. Reanalysis is a later task,
/// so an existing suggestion set is never dropped or replaced by this helper.
/// A non-empty [base.suggestions] throws [StateError] before any conversion.
///
/// Throws [FormatException], [ArgumentError], or [StateError] for a malformed
/// or inconsistent envelope or a violated precondition; the caller must
/// present only a content-free failure state.
core.RevisionContent applyDocumentAnalysis({
  required core.RevisionContent base,
  required analysis.DocumentAnalysisResult result,
}) {
  if (base.suggestions.isNotEmpty) {
    throw StateError(
      'analysis requires a revision without existing suggestions',
    );
  }
  final Map<int, recognition.FieldSuggestionSet> byPage =
      <int, recognition.FieldSuggestionSet>{
        for (final recognition.FieldSuggestionSet set in result.pages)
          set.pageIndex: set,
      };
  final List<core.Page> pages = <core.Page>[];
  for (final core.Page page in base.pages) {
    final recognition.FieldSuggestionSet? set = byPage[page.index];
    if (set == null) {
      // Cancelled pages stay pending (recognition-output §4).
      pages.add(page);
      continue;
    }
    if (set.isComplete) {
      pages.add(
        page.copyWith(analysis: core.AnalysisState.complete, failure: null),
      );
      continue;
    }
    final recognition.PageAnalysisFailure? failure = set.failure;
    if (!set.isFailed || failure == null) {
      throw StateError('analysis envelope has no terminal state');
    }
    pages.add(
      page.copyWith(
        analysis: core.AnalysisState.failed,
        failure: pageFailureForAnalysis(failure, pageIndex: page.index),
      ),
    );
  }
  final List<core.FieldSuggestion> suggestions = <core.FieldSuggestion>[
    for (final recognition.FieldSuggestionSet set in result.pages)
      if (set.isComplete)
        for (final Map<String, Object?> wire in set.suggestions)
          _fieldSuggestionFromWire(wire),
  ];
  return core.RevisionContent(
    pages: pages,
    suggestions: suggestions,
    fields: base.fields,
    fieldOrder: base.fieldOrder,
    values: base.values,
    signatures: base.signatures,
    verification: base.verification,
    templateOrigin: base.templateOrigin,
    unknownFields: base.unknownFields,
  );
}

core.FieldSuggestion _fieldSuggestionFromWire(Map<String, Object?> wire) {
  final Object? id = wire['id'];
  final Object? pageIndex = wire['pageIndex'];
  final Object? rect = wire['rect'];
  final Object? proposedType = wire['proposedType'];
  final Object? confidence = wire['confidence'];
  final Object? labelText = wire['labelText'];
  final Object? evidence = wire['evidence'];
  final Object? conflicts = wire['conflictsWith'];
  if (id is! String ||
      pageIndex is! int ||
      rect is! Map<String, Object?> ||
      proposedType is! String ||
      confidence is! num ||
      (labelText != null && labelText is! String) ||
      evidence is! Map<String, Object?> ||
      conflicts is! List<Object?>) {
    throw const FormatException('Invalid analysis suggestion');
  }
  final Object? x = rect['x'];
  final Object? y = rect['y'];
  final Object? width = rect['width'];
  final Object? height = rect['height'];
  final Object? cues = evidence['cues'];
  final Object? cueAgreement = evidence['cueAgreement'];
  final Object? skewDegrees = evidence['skewDegrees'];
  final Object? contrast = evidence['contrast'];
  final Object? ocrUsed = evidence['ocrUsed'];
  if (x is! num ||
      y is! num ||
      width is! num ||
      height is! num ||
      cues is! List<Object?> ||
      cueAgreement is! int ||
      skewDegrees is! num ||
      contrast is! String ||
      ocrUsed is! bool) {
    throw const FormatException('Invalid analysis suggestion fields');
  }
  final List<core.SuggestionCue> parsedCues = <core.SuggestionCue>[
    for (final Object? cue in cues) core.SuggestionCue.fromWire(cue),
  ];
  final core.EvidenceContrast parsedContrast;
  if (contrast == 'normal') {
    parsedContrast = core.EvidenceContrast.normal;
  } else if (contrast == 'low') {
    parsedContrast = core.EvidenceContrast.low;
  } else {
    throw const FormatException('Invalid analysis contrast');
  }
  final List<String> conflictsWith = <String>[];
  for (final Object? conflict in conflicts) {
    if (conflict is! String) {
      throw const FormatException('Invalid analysis conflict');
    }
    conflictsWith.add(conflict);
  }
  return core.FieldSuggestion(
    id: id,
    pageIndex: pageIndex,
    rect: core.Rect.fromLTWH(
      x.toDouble(),
      y.toDouble(),
      width.toDouble(),
      height.toDouble(),
    ),
    proposedType: core.FieldType.fromWire(proposedType),
    confidence: confidence.toDouble(),
    labelText: labelText as String?,
    evidence: core.SuggestionEvidence(
      cues: parsedCues,
      cueAgreement: cueAgreement,
      skewDegrees: skewDegrees.toDouble(),
      contrast: parsedContrast,
      ocrUsed: ocrUsed,
    ),
    conflictsWith: conflictsWith,
    resolution: core.SuggestionResolution.unresolved,
  );
}

/// The editor route for one successfully imported document.
class EditorScreen extends StatefulWidget {
  /// Creates the US1 editor route.
  ///
  /// [sourceBytes] is the protected-store resolver for the viewer.
  /// [runtime] is the Phase B1 analysis/persistence composition.
  /// [rendererFactory] defaults to the production pdfrx renderer and exists so
  /// host-VM tests inject a fake without a platform view or PDFium.
  const EditorScreen({
    required this.source,
    required this.sourceBytes,
    required this.runtime,
    this.rendererFactory = openPdfrxPageRenderer,
    this.loadTimeout = editorLoadTimeout,
    this.analysisTimeout = editorAnalysisTimeout,
    super.key,
  });

  /// The verified imported source, including preflight page geometry.
  final ImportedSource source;

  /// Resolves the protected source bytes; never a path or URI.
  final PageViewSourceBytes sourceBytes;

  /// The editor analysis/persistence runtime for this session.
  final EditorRuntime runtime;

  /// Opens the viewer renderer for the resolved bytes.
  final PageViewRendererFactory rendererFactory;

  /// Bound on the single revision/source load; tests may shorten it.
  final Duration loadTimeout;

  /// Bound on the single analysis run; tests may shorten it.
  final Duration analysisTimeout;

  @override
  State<EditorScreen> createState() => EditorScreenState();
}

/// State exposed to B2 and tests: the loaded/analyzed snapshot plus stable keys.
class EditorScreenState extends State<EditorScreen> {
  late final PageViewController _viewerController;
  late final PageStripController _stripController;
  late List<PageStripPage> _stripPages;
  PageStateResult? _pageStates;
  LoadedDocument? _loadedDocument;
  core.RevisionContent? _content;
  String? _analysisStateKey;
  String? _analysisRunId;
  int? _analysisElapsedMs;
  bool _analysisStarted = false;
  String? _headRevisionId;
  final history.CommandHistory _editHistory = history.CommandHistory();
  FieldGeometrySession? _geometrySession;
  int? _geometryPageIndex;

  /// Preview kept on screen while the gesture's commit is still in flight.
  ///
  /// The visible content only changes after the store verifies the save, so
  /// dropping the preview at gesture end would make the field snap back to its
  /// stored rectangle until the save resolves. The preview is therefore painted
  /// from this snapshot until [_commitGeometry] settles, successfully or not.
  Rect? _geometryCommittedPreview;
  int? _geometryCommittedPageIndex;
  bool _reviewBusy = false;
  final Completer<Uint8List?> _sourceBytesReady = Completer<Uint8List?>();
  late final FieldSelectionController _selectionController;
  core.DurabilityStatus _durabilityStatus = core.DurabilityStatus.unsaved;
  DateTime? _lastDurableAt;
  Set<int> _uncertainPages = const <int>{};
  bool _valueSheetOpen = false;

  /// The loaded or analyzed revision snapshot, or null when loading failed.
  core.RevisionContent? get content => _content;

  /// The verified loaded document, or null before/after a failed load.
  LoadedDocument? get loadedDocument => _loadedDocument;

  /// The latest committed revision id used as the next `expectedHead`.
  String? get headRevisionId => _headRevisionId;

  /// Whether the T067 history holds an undoable edit.
  ///
  /// Covers confirmed-field commands (confirm/reject, T071A) and geometry
  /// commands (move/resize, T071B), so the single undo affordance always
  /// reverses the newest committed edit.
  bool get canUndoReview => _editHistory.canUndo;

  /// Whether a move/resize preview is currently being dragged.
  bool get geometryGestureActive => _geometrySession != null;

  /// Whether a review command is currently being saved.
  bool get reviewBusy => _reviewBusy;

  /// The transient field selection source of truth (T077).
  FieldSelectionController get selection => _selectionController;

  /// The shared page view transform (T078/viewer).
  PageViewController get viewController => _viewerController;

  /// The honest durability state shown in the app bar (T091).
  core.DurabilityStatus get durabilityStatus => _durabilityStatus;

  /// When the last verified commit completed, or null before one.
  DateTime? get lastDurableAt => _lastDurableAt;

  /// `analysis-ready`, `analysis-skipped`, `analysis-failed`, or null while
  /// the first load/analysis is still running.
  String? get analysisStateKey => _analysisStateKey;

  /// The UUIDv4 of the first analysis run, when one started.
  String? get analysisRunId => _analysisRunId;

  /// Content-free overall analysis duration in milliseconds, when one ran.
  int? get analysisElapsedMs => _analysisElapsedMs;

  @override
  void initState() {
    super.initState();
    _viewerController = PageViewController.fromImportedSource(widget.source);
    _stripController = PageStripController(viewer: _viewerController);
    _stripPages = _buildStripPagesFromSource();
    _selectionController = FieldSelectionController();
    unawaited(_loadAndAnalyze());
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
    final core.PageGeometry page = widget.source.pages[index];
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

  List<PageStripPage> _buildStripPagesFromSource() {
    final Set<int> unreadable = widget.source.pageFailures
        .map((core.PageFailure failure) => failure.pageIndex)
        .toSet();
    return List<PageStripPage>.unmodifiable(<PageStripPage>[
      for (int index = 0; index < widget.source.pageCount; index++)
        PageStripPage(unreadable: unreadable.contains(index)),
    ]);
  }

  List<PageStripPage> _buildStripPagesFromContent(
    core.RevisionContent content, {
    Set<int> uncertainPages = const <int>{},
  }) {
    final Set<int> unreadable = <int>{
      for (final core.Page page in content.pages)
        if (page.unreadable) page.index,
      for (final core.PageFailure failure in widget.source.pageFailures)
        failure.pageIndex,
    };
    return List<PageStripPage>.unmodifiable(<PageStripPage>[
      for (final core.Page page in content.pages)
        PageStripPage(
          analysisState: _stripAnalysisState(page.analysis),
          unreadable: unreadable.contains(page.index),
          uncertain: uncertainPages.contains(page.index),
        ),
    ]);
  }

  PageStripAnalysisState _stripAnalysisState(core.AnalysisState state) {
    switch (state) {
      case core.AnalysisState.pending:
        return PageStripAnalysisState.pending;
      case core.AnalysisState.running:
        return PageStripAnalysisState.analyzing;
      case core.AnalysisState.complete:
        return PageStripAnalysisState.ready;
      case core.AnalysisState.failed:
        return PageStripAnalysisState.failed;
    }
  }

  /// Whether the B2 review panel has a committed/loaded revision to show.
  bool get _reviewPanelVisible {
    return _content != null &&
        (_analysisStateKey == editorAnalysisReadyKey ||
            _analysisStateKey == editorAnalysisSkippedKey);
  }

  /// Whether the loaded revision already records a first analysis run.
  ///
  /// `complete` and `running` pages are direct evidence. An import-unreadable
  /// page is persisted as `failed` with `IMP-006` before analysis starts, so
  /// that specific failure is not run evidence; every other failure is. This
  /// keeps a partially unreadable first import analyzable while making a
  /// completed zero-suggestion run durable across reopen.
  bool _hasPersistedAnalysisRun(core.RevisionContent content) {
    for (final core.Page page in content.pages) {
      switch (page.analysis) {
        case core.AnalysisState.pending:
          break;
        case core.AnalysisState.complete:
        case core.AnalysisState.running:
          return true;
        case core.AnalysisState.failed:
          final core.PageFailure? failure = page.failure;
          final bool importUnreadable =
              page.unreadable || failure?.messageKey == imp006MessageKey;
          if (!importUnreadable) {
            return true;
          }
      }
    }
    return false;
  }

  /// Whether every loaded page geometry matches the imported source page.
  ///
  /// The page count is checked by the caller. Rotation must match exactly. The
  /// media and crop box edges are compared per coordinate with the documented
  /// [pageGeometryTolerancePt] tolerance, which absorbs persisted three-decimal
  /// quantization. A same-size 90°/270° page therefore fails, and so does a
  /// genuinely different media or crop box.
  bool _geometryMatchesSource(LoadedDocument loaded) {
    for (int index = 0; index < widget.source.pageCount; index++) {
      if (!_pageGeometryMatches(
        loaded.content.pages[index].geometry,
        widget.source.pages[index],
      )) {
        return false;
      }
    }
    return true;
  }

  bool _pageGeometryMatches(
    core.PageGeometry loaded,
    core.PageGeometry source,
  ) {
    return loaded.rotation == source.rotation &&
        _rectMatchesWithinTolerance(loaded.mediaBox, source.mediaBox) &&
        _rectMatchesWithinTolerance(loaded.cropBox, source.cropBox);
  }

  bool _rectMatchesWithinTolerance(core.Rect loaded, core.Rect source) {
    return (loaded.left - source.left).abs() <= pageGeometryTolerancePt &&
        (loaded.top - source.top).abs() <= pageGeometryTolerancePt &&
        (loaded.right - source.right).abs() <= pageGeometryTolerancePt &&
        (loaded.bottom - source.bottom).abs() <= pageGeometryTolerancePt;
  }

  Future<void> _loadAndAnalyze() async {
    if (_analysisStarted) {
      return;
    }
    _analysisStarted = true;
    _analysisDiagnostic('LOAD_START');
    final LoadedDocument loaded;
    try {
      loaded = await widget.runtime
          .loadDocument(widget.source.documentId)
          .timeout(widget.loadTimeout);
    } on UnsupportedOperationException {
      // Non-Android/failed editor compositions have no revision load, but the
      // T148 US1 viewer still has the protected read-back closure. Preserve
      // that viewer path without inventing analysis or a persisted revision.
      _analysisDiagnostic('LOAD_UNSUPPORTED');
      await _completeViewerSourceBytesFromFallback();
      _markFailed(reason: 'load-unsupported');
      return;
    } on TimeoutException {
      _analysisDiagnostic('LOAD_FAIL:TYPE=timeout');
      _completeSourceBytes(null);
      _markFailed(reason: 'load-timeout');
      return;
    } catch (error) {
      _analysisDiagnostic('LOAD_FAIL:TYPE=${error.runtimeType}');
      _completeSourceBytes(null);
      _markFailed(reason: 'load-error');
      return;
    }
    _analysisDiagnostic(
      'LOAD_OK:PAGES=${loaded.content.pageCount}:BYTES=${loaded.sourceBytes.isEmpty ? 0 : 1}:SUGGESTIONS=${loaded.content.suggestions.length}',
    );
    // The viewer and the analysis path share this one protected load. No
    // second `store.loadDocument` is issued for the same document.
    _completeSourceBytes(loaded.sourceBytes);
    if (!mounted) {
      _analysisDiagnostic('LOAD_ABANDONED:UNMOUNTED=1');
      return;
    }
    final bool identityMatches =
        loaded.meta.id == widget.source.documentId &&
        loaded.meta.source.id == widget.source.sourceId;
    final bool pageCountMatches =
        loaded.content.pageCount == widget.source.pageCount;
    final bool geometryMatches =
        pageCountMatches && _geometryMatchesSource(loaded);
    if (!identityMatches || !pageCountMatches || !geometryMatches) {
      _analysisDiagnostic(
        'LOAD_REJECT:IDENTITY=${identityMatches ? 1 : 0}:PAGES=${pageCountMatches ? 1 : 0}:GEOMETRY=${geometryMatches ? 1 : 0}',
      );
      _markFailed(reason: 'load-reject');
      return;
    }
    setState(() {
      _loadedDocument = loaded;
      _content = loaded.content;
      _headRevisionId = loaded.meta.latestRevisionId;
      _lastDurableAt = loaded.meta.lastDurableAt;
      _durabilityStatus = loaded.meta.latestRevisionId == null
          ? core.DurabilityStatus.unsaved
          : loaded.meta.lastDurableAt == null
          ? core.DurabilityStatus.clean
          : core.DurabilityStatus.saved(
              lastDurableAt: loaded.meta.lastDurableAt!,
            );
      _stripPages = _buildStripPagesFromContent(loaded.content);
    });
    _analysisDiagnostic(
      'CONTENT_SET:PAGES=${loaded.content.pageCount}:SUGGESTIONS=${loaded.content.suggestions.length}:STRIP=${_stripPages.length}',
    );
    if (loaded.content.suggestions.isNotEmpty ||
        _hasPersistedAnalysisRun(loaded.content)) {
      // Reanalysis is a later task. Never duplicate or overwrite an existing
      // suggestion set, and never re-run a persisted first analysis (including
      // a completed zero-suggestion run) on reopen.
      setState(() {
        _analysisStateKey = editorAnalysisSkippedKey;
      });
      _analysisDiagnostic('ANALYSIS_STATE:skipped:PERSISTED=1');
      return;
    }
    final Set<int> unreadable = <int>{
      for (final core.Page page in loaded.content.pages)
        if (page.unreadable) page.index,
      for (final core.PageFailure failure in widget.source.pageFailures)
        failure.pageIndex,
    };
    final List<analysis.DocumentAnalysisPage> pages =
        <analysis.DocumentAnalysisPage>[
          for (final core.Page page in loaded.content.pages)
            if (!unreadable.contains(page.index))
              analysis.DocumentAnalysisPage.fromGeometry(
                pageIndex: page.index,
                geometry: page.geometry,
              ),
        ];
    if (pages.isEmpty) {
      // A successful import never reaches this state (all-unreadable sources
      // are rejected); leave the document unchanged and expose the
      // deterministic no-analysis state rather than inventing one.
      setState(() {
        _analysisStateKey = editorAnalysisSkippedKey;
      });
      _analysisDiagnostic('ANALYSIS_STATE:skipped:NO_PAGES=1');
      return;
    }
    final String analysisRunId = widget.runtime.ids.newId();
    _analysisRunId = analysisRunId;
    _analysisDiagnostic(
      'ANALYSIS_START:PAGES=${pages.length}:UNREADABLE=${unreadable.length}:SOURCE_BYTES=${loaded.sourceBytes.isEmpty ? 0 : 1}:OCR=${widget.runtime.ocr == null ? 0 : 1}',
    );
    final Stopwatch stopwatch = Stopwatch()..start();
    final analysis.DocumentAnalysisResult result;
    try {
      result = await analysis.AnalyzeDocument.run(
        analysis.DocumentAnalysisRequest(
          sourceId: widget.source.sourceId,
          analysisRunId: analysisRunId,
          pages: pages,
          evidenceClass: editorEvidenceClass(),
          rasterPort: widget.runtime.raster,
          ocrPort: widget.runtime.ocr,
        ),
      ).timeout(widget.analysisTimeout);
    } on TimeoutException {
      stopwatch.stop();
      _analysisDiagnostic('ANALYSIS_FAIL:CODE=timeout');
      _markFailed(
        elapsedMs: stopwatch.elapsedMilliseconds,
        reason: 'analysis-timeout',
      );
      return;
    } catch (error) {
      stopwatch.stop();
      _analysisDiagnostic('ANALYSIS_FAIL:TYPE=${error.runtimeType}');
      _markFailed(
        elapsedMs: stopwatch.elapsedMilliseconds,
        reason: 'analysis-error',
      );
      return;
    }
    stopwatch.stop();
    if (!mounted) {
      return;
    }
    _analysisDiagnostic(
      'ANALYSIS_RESULT:PAGES=${result.pages.length}:CANCELLED=${result.cancelledPageIndexes.length}',
    );
    for (final recognition.FieldSuggestionSet set in result.pages) {
      if (set.isComplete) {
        _analysisDiagnostic(
          'ANALYSIS_PAGE:P=${set.pageIndex}:STATUS=complete:SUGGESTIONS=${set.suggestions.length}:UNCERTAIN=${set.pageUncertain ? 1 : 0}',
        );
      } else {
        final recognition.PageAnalysisFailure? failure = set.failure;
        _analysisDiagnostic(
          'ANALYSIS_PAGE:P=${set.pageIndex}:STATUS=failed:CATEGORY=${failure?.category ?? 'none'}:KEY=${failure?.messageKey ?? 'none'}',
        );
      }
    }
    final core.RevisionContent analyzed;
    try {
      analyzed = applyDocumentAnalysis(base: loaded.content, result: result);
    } catch (error) {
      _analysisDiagnostic('ANALYSIS_APPLY_FAIL:TYPE=${error.runtimeType}');
      _markFailed(
        elapsedMs: stopwatch.elapsedMilliseconds,
        reason: 'analysis-apply',
      );
      return;
    }
    final Set<int> uncertain = <int>{
      for (final recognition.FieldSuggestionSet set in result.pages)
        if (set.isComplete && set.pageUncertain) set.pageIndex,
    };
    setState(() {
      _content = analyzed;
      _uncertainPages = uncertain;
      _stripPages = _buildStripPagesFromContent(
        analyzed,
        uncertainPages: uncertain,
      );
      _analysisElapsedMs = stopwatch.elapsedMilliseconds;
      _durabilityStatus = core.DurabilityStatus.saving;
    });
    _analysisDiagnostic(
      'ANALYSIS_APPLIED:PAGES=${analyzed.pageCount}:SUGGESTIONS=${analyzed.suggestions.length}:UNCERTAIN=${uncertain.length}',
    );
    final StoredMeta saved;
    final DateTime savedAt = widget.runtime.clock.nowUtc().toUtc();
    _analysisDiagnostic('ANALYSIS_SAVE_START');
    try {
      saved = await widget.runtime.saveRevision(
        SaveRevisionRequest(
          documentId: widget.source.documentId,
          expectedHead: loaded.meta.latestRevisionId,
          content: analyzed,
          kind: core.RevisionKind.autosave,
        ),
      );
    } catch (error) {
      // The viewer and the in-memory analysis result remain available; the
      // durable document is unchanged because the store rejected the save.
      _analysisDiagnostic('ANALYSIS_SAVE_FAIL:CODE=${_saveFailureCode(error)}');
      if (mounted) {
        setState(() {
          _durabilityStatus = core.DurabilityStatus.saveFailed('SAVE-003');
        });
      }
      _markFailed(reason: 'save-error');
      return;
    }
    if (!mounted) {
      return;
    }
    final DateTime durableAt = saved.lastDurableAt ?? savedAt;
    setState(() {
      _headRevisionId = saved.latestRevisionId ?? _headRevisionId;
      _lastDurableAt = durableAt;
      _durabilityStatus = core.DurabilityStatus.saved(lastDurableAt: durableAt);
      _analysisStateKey = editorAnalysisReadyKey;
    });
    _analysisDiagnostic('ANALYSIS_SAVE_OK');
    _analysisDiagnostic('ANALYSIS_STATE:ready');
  }

  Future<void> _confirmSuggestion(core.FieldSuggestion suggestion) async {
    final core.RevisionContent? content = _content;
    if (content == null || _reviewBusy) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final review.SuggestionReviewChange change;
    try {
      change = review.confirmSuggestion(
        content,
        suggestion.id,
        widget.runtime.ids.newId(),
        suggestion.labelText ??
            l10n.suggestionFieldLabel(content.fields.length + 1),
        widget.runtime.clock.nowUtc().toUtc(),
      );
    } catch (_) {
      _showReviewMessage(l10n.save007);
      return;
    }
    final core.ConfirmedField? confirmedField = change.confirmedField;
    if (confirmedField == null) {
      // Defensive: a confirmed receipt always carries the generated field.
      _showReviewMessage(l10n.save007);
      return;
    }
    await _commitSnapshot(
      change.content,
      kind: history.EditCommandKind.confirmSuggestion,
    );
  }

  Future<void> _rejectSuggestion(core.FieldSuggestion suggestion) async {
    final core.RevisionContent? content = _content;
    if (content == null || _reviewBusy) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final review.SuggestionReviewChange change;
    try {
      change = review.rejectSuggestion(content, suggestion.id);
    } catch (_) {
      _showReviewMessage(l10n.save007);
      return;
    }
    await _commitSnapshot(
      change.content,
      kind: history.EditCommandKind.rejectSuggestion,
    );
  }

  /// Reverses the newest committed edit through the T067 history.
  ///
  /// The newest [history.CommandHistory] entry is popped and its exact `before`
  /// snapshot is written through the same verified save path as a forward
  /// command. Restoring the stored snapshot, rather than re-deriving the old
  /// state, is what makes undo drift-free: a move or resize returns bit for bit,
  /// a value edit returns to the previous value, and a confirmation or rejection
  /// is reversed with its suggestion resolution intact even when the field was
  /// moved after it was confirmed (the T065 `fieldTouched` guard cannot apply
  /// here).
  ///
  /// This is only sound because every committed mutation of this screen records
  /// its own entry: confirm/reject, move/resize, and value edits. The newest
  /// `before` snapshot therefore never predates a change that has no entry of
  /// its own, so undo can never drop a field or a value that the user created
  /// after the command being reversed.
  ///
  /// A failed save re-arms the entry and claims nothing, so the visible
  /// revision stays the one the store still holds.
  ///
  /// The history is only authoritative for changes it recorded. If the current
  /// content is not exactly the `after` snapshot of the newest entry, something
  /// changed the revision without its own undo step (a rejected history record,
  /// or a content mutation such as the analysis apply that is not a user
  /// command). Reversing `before` would then drop that newer content, so the
  /// undo is refused instead: the document is left untouched, the entry is put
  /// back on the undo stack, and the existing conflict message is shown. Undo
  /// therefore never writes a revision that loses newer content.
  Future<void> _undoLastEdit() async {
    final core.RevisionContent? current = _content;
    if (current == null || _reviewBusy) {
      return;
    }
    final history.HistoryEntry? entry = _editHistory.undo();
    if (entry == null) {
      return;
    }
    if (!_isSameRevisionContent(current, entry.after)) {
      // The revision moved on without an entry of its own. Applying the stale
      // `before` snapshot would silently drop that newer content.
      _editHistory.redo();
      _showReviewMessage(AppLocalizations.of(context).save006);
      return;
    }
    final bool committed = await _commitSnapshot(entry.before);
    if (!committed) {
      _editHistory.redo();
    }
  }

  /// Whether two revision snapshots describe exactly the same document state.
  ///
  /// Compared through the canonical JSON form, so the guard is exact rather
  /// than dependent on object identity: two independently constructed but
  /// equal snapshots are the same state.
  bool _isSameRevisionContent(
    core.RevisionContent left,
    core.RevisionContent right,
  ) {
    return identical(left, right) ||
        core.canonicalJsonEncode(left.toJson()) ==
            core.canonicalJsonEncode(right.toJson());
  }

  /// Persists one edited geometry revision at gesture end (T071B).
  ///
  /// The T066 command is applied to the current revision and its receipt is
  /// committed through [_commitSnapshot], so exactly one store write happens
  /// per gesture. A rectangle the command rejects (non-finite, non-positive, or
  /// outside the page) is discarded with the existing content-free save
  /// message; the stored geometry is never replaced by a guess.
  Future<void> _commitGeometry(FieldGeometryChange change) async {
    final core.RevisionContent? content = _content;
    if (content == null) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final core.Rect rect = core.Rect.fromLTWH(
      change.rect.left,
      change.rect.top,
      change.rect.width,
      change.rect.height,
    );
    final edit.EditFieldChange receipt;
    try {
      final DateTime editedAt = widget.runtime.clock.nowUtc().toUtc();
      receipt = change.kind == FieldGeometryEditKind.move
          ? edit.moveField(content, change.fieldId, rect, editedAt)
          : edit.resizeField(content, change.fieldId, rect, editedAt);
    } catch (_) {
      _showReviewMessage(l10n.save007);
      return;
    }
    await _commitSnapshot(
      receipt.content,
      kind: change.kind == FieldGeometryEditKind.move
          ? history.EditCommandKind.move
          : history.EditCommandKind.resize,
      fieldId: change.fieldId,
    );
  }

  /// Claims a one-finger drag that starts on the selected field (T071B).
  ///
  /// Returns false unless a confirmed field on [pageIndex] is selected and
  /// [viewportPoint] falls on its body or on one of its eight handle hit
  /// regions. The gesture start is mapped once through [PageViewMapping] and
  /// the current scale is captured; the session then divides only the
  /// cumulative delta by that scale.
  bool _beginGeometryDrag(
    int pageIndex,
    PageViewMapping mapping,
    Offset viewportPoint,
  ) {
    final core.RevisionContent? content = _content;
    final String? selectedId = _selectionController.selectedId;
    if (content == null || selectedId == null || _reviewBusy) {
      return false;
    }
    core.ConfirmedField? field;
    for (final core.ConfirmedField candidate in content.fields) {
      if (candidate.id == selectedId && candidate.pageIndex == pageIndex) {
        field = candidate;
        break;
      }
    }
    if (field == null || pageIndex >= content.pages.length) {
      return false;
    }
    final Rect viewRect = layoutFieldOverlay(
      items: <FieldOverlayItem>[FieldOverlayItem.fromConfirmedField(field)],
      pageSize: mapping.pageSize.contentSize,
      pageRect: mapping.pageRectInViewport,
    ).single.viewRect;
    final FieldGeometryHandle? handle = hitTestFieldGeometry(
      viewRect: viewRect,
      viewPoint: viewportPoint,
    );
    if (handle == null) {
      return false;
    }
    final FieldGeometrySession session = FieldGeometrySession.start(
      fieldId: field.id,
      handle: handle,
      startRect: Rect.fromLTWH(
        field.rect.left,
        field.rect.top,
        field.rect.width,
        field.rect.height,
      ),
      pageBox: Rect.fromLTWH(
        content.pages[pageIndex].geometry.displayBox.left,
        content.pages[pageIndex].geometry.displayBox.top,
        content.pages[pageIndex].geometry.displayBox.width,
        content.pages[pageIndex].geometry.displayBox.height,
      ),
      scale: mapping.scale,
    );
    setState(() {
      _geometrySession = session;
      _geometryPageIndex = pageIndex;
      // A new gesture replaces any preview still waiting for an older commit.
      _geometryCommittedPreview = null;
      _geometryCommittedPageIndex = null;
    });
    return true;
  }

  /// Recomputes the transient preview for the active gesture; no store write.
  ///
  /// This rebuilds the whole screen once per pointer move because the preview
  /// is drawn inside the page overlay. Narrowing it to an `AnimatedBuilder` and
  /// a repaint-only preview layer is a follow-up (F3); it is a frame-cost
  /// concern only and changes no behaviour.
  void _updateGeometryDrag(Offset viewportDelta) {
    final FieldGeometrySession? session = _geometrySession;
    if (session == null) {
      return;
    }
    setState(() {
      session.update(viewportDelta);
    });
  }

  /// Ends the active gesture: exactly one commit, or none when nothing changed.
  ///
  /// The preview stays painted until the asynchronous commit settles, so the
  /// field does not visibly snap back to its stored rectangle while the save is
  /// in flight. A failed save clears it, which honestly shows the stored state.
  void _endGeometryDrag({required bool cancelled}) {
    final FieldGeometrySession? session = _geometrySession;
    if (session == null) {
      return;
    }
    final int? pageIndex = _geometryPageIndex;
    if (cancelled) {
      setState(() {
        _geometrySession = null;
        _geometryPageIndex = null;
        _geometryCommittedPreview = null;
        _geometryCommittedPageIndex = null;
      });
      session.cancel();
      return;
    }
    final FieldGeometryChange? change = session.commit();
    setState(() {
      _geometrySession = null;
      _geometryPageIndex = null;
      _geometryCommittedPreview = change == null ? null : session.previewRect;
      _geometryCommittedPageIndex = change == null ? null : pageIndex;
    });
    if (change == null) {
      return;
    }
    unawaited(
      _commitGeometry(change).whenComplete(() {
        if (!mounted) {
          return;
        }
        setState(() {
          _geometryCommittedPreview = null;
          _geometryCommittedPageIndex = null;
        });
      }),
    );
  }

  /// Discards an active preview without committing (pointer cancel).
  void _cancelGeometryGesture() {
    final FieldGeometrySession? session = _geometrySession;
    if (session == null) {
      return;
    }
    setState(() {
      _geometrySession = null;
      _geometryPageIndex = null;
    });
    session.cancel();
  }

  /// Persists one edited revision, then updates the visible revision.
  ///
  /// The store is written with the current [headRevisionId] as `expectedHead`.
  /// The visible content is only replaced after the store confirms the commit,
  /// so a failed save leaves the viewer, page strip, selection, prior
  /// suggestions, and confirmed fields exactly as they were. With [kind] (and
  /// [fieldId] for field-scoped kinds) the committed snapshots are also
  /// recorded as one T067 undo step; an undo itself passes no [kind], so a
  /// reversal is not recorded as a new command.
  Future<bool> _commitSnapshot(
    core.RevisionContent next, {
    history.EditCommandKind? kind,
    String? fieldId,
  }) async {
    if (_reviewBusy) {
      return false;
    }
    final core.RevisionContent? before = _content;
    setState(() {
      _reviewBusy = true;
      _durabilityStatus = core.DurabilityStatus.saving;
    });
    final StoredMeta saved;
    try {
      saved = await widget.runtime.saveRevision(
        SaveRevisionRequest(
          documentId: widget.source.documentId,
          expectedHead: _headRevisionId,
          content: next,
          kind: core.RevisionKind.autosave,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return false;
      }
      setState(() {
        _reviewBusy = false;
        _durabilityStatus = core.DurabilityStatus.saveFailed(
          _saveFailureCode(error),
        );
      });
      _showReviewMessage(AppLocalizations.of(context).save003);
      return false;
    }
    if (!mounted) {
      return false;
    }
    final DateTime durableAt =
        saved.lastDurableAt ?? widget.runtime.clock.nowUtc().toUtc();
    setState(() {
      _content = next;
      _headRevisionId = saved.latestRevisionId ?? _headRevisionId;
      _lastDurableAt = durableAt;
      _durabilityStatus = core.DurabilityStatus.saved(lastDurableAt: durableAt);
      _stripPages = _buildStripPagesFromContent(
        next,
        uncertainPages: _uncertainPages,
      );
      _reviewBusy = false;
    });
    _selectionController.reconcile(
      next.fields.map((core.ConfirmedField field) => field.id),
    );
    _recordHistory(kind: kind, fieldId: fieldId, before: before, after: next);
    return true;
  }

  /// Records one committed command as an undo step.
  ///
  /// The revision is already durable when this runs, so a rejected history
  /// entry (for example a clock that did not advance) loses only the transient
  /// undo step and never turns a committed edit into a failure.
  void _recordHistory({
    required history.EditCommandKind? kind,
    required String? fieldId,
    required core.RevisionContent? before,
    required core.RevisionContent after,
  }) {
    if (kind == null || before == null) {
      return;
    }
    try {
      _editHistory.record(
        command: history.EditCommand(
          id: widget.runtime.ids.newId(),
          kind: kind,
          fieldId: fieldId,
          at: widget.runtime.clock.nowUtc().toUtc(),
        ),
        before: before,
        after: after,
      );
    } on history.CommandHistoryException {
      // Undo is unavailable for this step; the committed revision stands.
    }
  }

  /// Persists one captured signature for [field] (T086A, issue #269).
  ///
  /// The path is one bounded, verified round with no reuse library and no
  /// shared ink:
  ///   1. [encodeSignaturePng] rasterizes exactly the captured draft, with the
  ///      long edge bounded by the model's 1024 px limit;
  ///   2. `SignatureAsset.fromPng` copies the bytes and derives the SHA-256 the
  ///      encrypted store verifies on write and again after its read-back;
  ///   3. `SecureStorePort.writeSignature` stores those bytes once in this
  ///      document's aggregate;
  ///   4. `applySignature` produces the snapshot that carries both the
  ///      `SignatureValue` and the `SignatureMark` for this field and page;
  ///   5. `_commitSnapshot` persists that snapshot as one verified autosave
  ///      revision with one `addSignature` undo step.
  ///
  /// A failed asset write performs no revision write. A failed revision save can
  /// leave the written asset unreferenced: no stored mark, no export plan, and
  /// no read-back can reach an asset id that no revision names, so the visible
  /// document never claims a signature that is not durable.
  Future<FieldValueCommitResult> _saveSignature(
    core.ConfirmedField field,
    SignatureDraft draft,
  ) async {
    final core.RevisionContent? content = _content;
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (content == null || _reviewBusy) {
      return FieldValueCommitResult.failed(l10n.save003);
    }
    final SignaturePng? png = await encodeSignaturePng(draft);
    if (!mounted) {
      return FieldValueCommitResult.failed(l10n.save003);
    }
    if (png == null) {
      return FieldValueCommitResult.failed(l10n.save007);
    }
    final signature.SignatureAsset asset;
    final signature.SignatureChange change;
    final String assetId = widget.runtime.ids.newId();
    final DateTime capturedAt = widget.runtime.clock.nowUtc().toUtc();
    try {
      asset = signature.SignatureAsset.fromPng(
        bytes: png.bytes,
        widthPx: png.widthPx,
        heightPx: png.heightPx,
      );
      change = signature.applySignature(
        content,
        field.id,
        assetId: assetId,
        asset: asset,
        capturedAt: capturedAt,
      );
    } catch (_) {
      return FieldValueCommitResult.failed(l10n.save007);
    }
    setState(() {
      _durabilityStatus = core.DurabilityStatus.saving;
    });
    try {
      await widget.runtime.store.writeSignature(
        WriteSignatureRequest(
          documentId: widget.source.documentId,
          assetId: assetId,
          bytes: asset.bytes,
          sha256: asset.sha256,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return FieldValueCommitResult.failed(l10n.save003);
      }
      final String code = _saveFailureCode(error);
      setState(() {
        _durabilityStatus = core.DurabilityStatus.saveFailed(code);
      });
      return FieldValueCommitResult.failed(_saveMessageForCode(l10n, code));
    }
    if (!mounted) {
      return FieldValueCommitResult.failed(l10n.save003);
    }
    final bool committed = await _commitSnapshot(
      change.content,
      kind: history.EditCommandKind.addSignature,
      fieldId: field.id,
    );
    if (!committed) {
      return FieldValueCommitResult.failed(l10n.save003);
    }
    return const FieldValueCommitResult.saved();
  }

  /// Persists one corrected field value through the same verified save path.
  ///
  /// The command snapshot is written with the current head as `expectedHead`.
  /// Visible content changes only after the store verifies the commit, so a
  /// failed save leaves the sheet draft and the prior document state intact and
  /// surfaces a content-free `saveFailed(code)` state instead of a saved claim.
  ///
  /// The durable change is also recorded as one T067 `setValue` undo step with
  /// its exact before/after snapshots. Every committed mutation of this screen
  /// therefore owns a history entry, which is what keeps undo from reversing an
  /// older entry over newer content (for example dropping a confirmed field
  /// after its value was edited).
  Future<FieldValueCommitResult> _saveFieldValue(
    core.ConfirmedField field,
    core.FieldValue value,
  ) async {
    final core.RevisionContent? content = _content;
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (content == null) {
      return FieldValueCommitResult.failed(l10n.save007);
    }
    final DateTime editedAt = widget.runtime.clock.nowUtc().toUtc();
    final set_value.SetValueChange change;
    try {
      change = set_value.setFieldValue(
        content,
        field.id,
        value: value,
        lastEditedAt: editedAt,
      );
    } catch (_) {
      return FieldValueCommitResult.failed(l10n.save007);
    }
    setState(() {
      _durabilityStatus = core.DurabilityStatus.saving;
    });
    final StoredMeta saved;
    try {
      saved = await widget.runtime.saveRevision(
        SaveRevisionRequest(
          documentId: widget.source.documentId,
          expectedHead: _headRevisionId,
          content: change.content,
          kind: core.RevisionKind.autosave,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return const FieldValueCommitResult.saved();
      }
      final String code = _saveFailureCode(error);
      setState(() {
        _durabilityStatus = core.DurabilityStatus.saveFailed(code);
      });
      return FieldValueCommitResult.failed(_saveMessageForCode(l10n, code));
    }
    if (!mounted) {
      return const FieldValueCommitResult.saved();
    }
    final DateTime durableAt = saved.lastDurableAt ?? editedAt;
    setState(() {
      _content = change.content;
      _headRevisionId = saved.latestRevisionId ?? _headRevisionId;
      _lastDurableAt = durableAt;
      _durabilityStatus = core.DurabilityStatus.saved(lastDurableAt: durableAt);
      _stripPages = _buildStripPagesFromContent(
        change.content,
        uncertainPages: _uncertainPages,
      );
    });
    _selectionController.reconcile(
      change.content.fields.map((core.ConfirmedField field) => field.id),
    );
    _recordHistory(
      kind: history.EditCommandKind.setValue,
      fieldId: field.id,
      before: content,
      after: change.content,
    );
    return const FieldValueCommitResult.saved();
  }

  String _saveFailureCode(Object error) {
    if (error is FeldexaException && error.code.startsWith('SAVE-')) {
      return error.code;
    }
    return 'SAVE-003';
  }

  String _saveMessageForCode(AppLocalizations l10n, String code) {
    return switch (code) {
      'SAVE-001' => l10n.save001,
      'SAVE-002' => l10n.save002,
      'SAVE-004' => l10n.save004,
      'SAVE-005' => l10n.save005,
      'SAVE-006' => l10n.save006,
      'SAVE-007' => l10n.save007,
      'SAVE-008' => l10n.save008,
      _ => l10n.save003,
    };
  }

  /// Returns the confirmed field with [id] in [content], or null.
  core.ConfirmedField? _fieldById(core.RevisionContent content, String id) {
    for (final core.ConfirmedField field in content.fields) {
      if (field.id == id) {
        return field;
      }
    }
    return null;
  }

  /// Opens the type-appropriate sheet for one tapped confirmed field.
  ///
  /// The sheet stays open across a next/previous field move (contract §5,
  /// US4-4): the traversal action commits the open draft first, then this
  /// wrapper swaps in the target field, which is taken from the latest
  /// `_content` and requests focus through its own `autofocus`. Values are
  /// therefore never lost and the move follows the current field order.
  ///
  /// The per-field „In Reihenfolge verschieben“ action closes the sheet with
  /// [FieldValueSheetOutcome.reorder] after the same verified commit, and the
  /// order review is opened only then. If the revision no longer contains the
  /// shown field (for example a concurrent analysis apply replaced it), the
  /// sheet closes instead of editing a stale snapshot.
  Future<void> _openFieldValueSheet(core.ConfirmedField field) async {
    final core.RevisionContent? content = _content;
    if (_valueSheetOpen || content == null) {
      return;
    }
    _valueSheetOpen = true;
    core.ConfirmedField currentField = field;
    try {
      final FieldValueSheetOutcome? outcome =
          await showModalBottomSheet<FieldValueSheetOutcome>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (BuildContext sheetContext) {
              return StatefulBuilder(
                builder: (BuildContext context, StateSetter setSheetState) {
                  final core.RevisionContent? live = _content;
                  final core.ConfirmedField? shown = live == null
                      ? null
                      : _fieldById(live, currentField.id);
                  if (live == null || shown == null) {
                    // The visible revision is the only source of truth; a
                    // field that disappeared is never edited from a stale
                    // snapshot.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (sheetContext.mounted) {
                        unawaited(Navigator.of(sheetContext).maybePop());
                      }
                    });
                    return const SizedBox.shrink();
                  }
                  currentField = shown;
                  final String? previousId = previousFieldId(live, shown.id);
                  final String? nextId = nextFieldId(live, shown.id);
                  return FieldValueSheet(
                    key: ValueKey<String>('field-value-sheet-${shown.id}'),
                    field: shown,
                    currentValue: live.values[shown.id],
                    canGoPrevious: previousId != null,
                    canGoNext: nextId != null,
                    onCommit: (core.FieldValue value) =>
                        _saveFieldValue(shown, value),
                    onSignatureCommit: (SignatureDraft draft) =>
                        _saveSignature(shown, draft),
                    onNavigate: (FieldValueNavigation direction) {
                      final String? targetId =
                          direction == FieldValueNavigation.next
                          ? nextId
                          : previousId;
                      if (targetId == null) {
                        return false;
                      }
                      // Read the revision after the commit so the target field
                      // and its snapshot are the latest durable ones.
                      final core.RevisionContent? latest = _content;
                      final core.ConfirmedField? target = latest == null
                          ? null
                          : _fieldById(latest, targetId);
                      if (target == null) {
                        // The target vanished. Report that no swap happened so
                        // the sheet re-enables its actions instead of staying
                        // busy and closing.
                        return false;
                      }
                      _selectFieldInOrder(target.id);
                      setSheetState(() {
                        currentField = target;
                      });
                      return true;
                    },
                  );
                },
              );
            },
          );
      if (!mounted) {
        return;
      }
      if (outcome == FieldValueSheetOutcome.reorder) {
        await _showFieldOrderSheet();
      }
    } finally {
      _valueSheetOpen = false;
    }
  }

  /// Handles one T077 selection callback from a page overlay.
  ///
  /// A confirmed field opens its value sheet. An unresolved suggestion only
  /// stays selected and highlighted; no field or value is invented. A miss was
  /// already cleared by [FieldSelectionSurface].
  void _handleOverlaySelection(FieldOverlayItem? item) {
    final core.RevisionContent? content = _content;
    if (item == null || content == null) {
      _selectionController.clear();
      return;
    }
    for (final core.ConfirmedField field in content.fields) {
      if (field.id == item.id) {
        unawaited(_openFieldValueSheet(field));
        return;
      }
    }
  }

  /// Builds the T069 items for exactly one page.
  List<FieldOverlayItem> _overlayItemsForPage(
    core.RevisionContent content,
    int pageIndex,
  ) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<FieldOverlayItem> items = <FieldOverlayItem>[];
    for (final core.ConfirmedField field in content.fields) {
      if (field.pageIndex != pageIndex) {
        continue;
      }
      items.add(
        FieldOverlayItem.fromConfirmedField(
          field,
          semanticLabel: _fieldSemantics(l10n, field, content.values[field.id]),
        ),
      );
    }
    for (final core.FieldSuggestion suggestion in content.suggestions) {
      if (suggestion.pageIndex != pageIndex ||
          suggestion.resolution != core.SuggestionResolution.unresolved) {
        continue;
      }
      items.add(
        FieldOverlayItem.fromSuggestion(
          suggestion,
          semanticLabel: l10n.a11ySuggestion(
            _fieldTypeLabel(l10n, suggestion.proposedType),
            suggestion.labelText ?? l10n.suggestionRowFallback,
            (suggestion.confidence * 100).round(),
          ),
        ),
      );
    }
    return items;
  }

  String _fieldSemantics(
    AppLocalizations l10n,
    core.ConfirmedField field,
    core.FieldValue? value,
  ) {
    return l10n.a11yFieldOverlay(
      field.label,
      _fieldTypeLabel(l10n, field.type),
      field.pageIndex + 1,
      value == null ? l10n.a11yFieldValueEmpty : l10n.a11yFieldValueFilled,
      field.provenance == core.Provenance.user
          ? l10n.a11yFieldStatusSelfCreated
          : l10n.a11yFieldStatusConfirmed,
      '',
      '',
    );
  }

  String _fieldTypeLabel(AppLocalizations l10n, core.FieldType type) {
    return switch (type) {
      core.FieldType.text => l10n.suggestionTypeText,
      core.FieldType.multiline => l10n.suggestionTypeMultiline,
      core.FieldType.number => l10n.suggestionTypeNumber,
      core.FieldType.date => l10n.suggestionTypeDate,
      core.FieldType.checkbox => l10n.suggestionTypeCheckbox,
      core.FieldType.signature => l10n.suggestionTypeSignature,
    };
  }

  /// Composes the T069 overlay and T077 selection surface for one page.
  ///
  /// The hook is laid out inside the page's own box; [viewportRect] is the
  /// page rectangle in viewport coordinates, so its size and a zero origin give
  /// the local page rectangle used by both shared widgets.
  Widget _buildPageOverlay(
    int pageIndex,
    Rect viewportRect,
    PageViewMapping mapping,
  ) {
    final core.RevisionContent? content = _content;
    if (content == null) {
      return const SizedBox.shrink();
    }
    final List<FieldOverlayItem> items = _overlayItemsForPage(
      content,
      pageIndex,
    );
    final Size pageSize = mapping.pageSize.contentSize;
    final Rect pageRect = Offset.zero & viewportRect.size;
    final FieldGeometrySession? session = _geometrySession;
    final Rect? previewRect = session != null
        ? (_geometryPageIndex == pageIndex ? session.previewRect : null)
        : (_geometryCommittedPageIndex == pageIndex
              ? _geometryCommittedPreview
              : null);
    return Listener(
      // A cancelled pointer discards the preview: no command, no store write.
      onPointerCancel: (PointerCancelEvent event) => _cancelGeometryGesture(),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // An empty page still needs the selection surface: a tap on empty
          // page space must clear an existing selection (contract §2), so only
          // the painted overlay is omitted when there are no items.
          if (items.isNotEmpty)
            FieldOverlay(items: items, pageSize: pageSize, pageRect: pageRect),
          FieldSelectionSurface(
            controller: _selectionController,
            items: items,
            pageSize: pageSize,
            pageRect: pageRect,
            onSelected: _handleOverlaySelection,
            child: const SizedBox.expand(),
          ),
          // Transient only: the preview is mounted while a gesture is active
          // (and until its commit settles) and is pointer-inert, so the 6 px
          // handles stay paint.
          if (previewRect != null)
            FieldGeometryPreview(
              key: const ValueKey<String>('field-geometry-preview'),
              previewRect: previewRect,
              pageSize: pageSize,
              pageRect: pageRect,
              accentColor: Theme.of(context).colorScheme.primary,
            ),
        ],
      ),
    );
  }

  /// Opens the FR-026 field-order review list.
  ///
  /// The list shows the confirmed fields in their current user-visible order
  /// (`data-model.md` §3.12) with page, position, label, type, provenance,
  /// confidence, conflict, and completion. A row tap selects that field and
  /// scrolls its page into view; the footer walks the same order with
  /// previous/next. Moving a field up or down saves exactly one
  /// [history.EditCommandKind.reorder] revision and refreshes the visible list
  /// only after the store confirms the commit, so a failed save leaves the
  /// order, values, and geometry untouched. The reorder step is undoable
  /// through the existing T067 history entry.
  ///
  /// `In Seitenreihenfolge sortieren` applies the whole deterministic
  /// page/reading order (`defaultDocumentFieldOrder`) as one reorder, which is
  /// FR-026's page-order half; it is disabled when the order already matches.
  /// Every move reads the latest `_content` at operation time rather than the
  /// snapshot captured when the sheet opened, so a concurrent analysis apply
  /// cannot be overwritten by a stale `before` state.
  Future<void> _showFieldOrderSheet() async {
    core.RevisionContent? current = _content;
    if (current == null) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        bool sheetBusy = false;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final AppLocalizations l10n = AppLocalizations.of(context);
            final core.RevisionContent? shown = current;
            if (shown == null) {
              return const SizedBox.shrink();
            }
            final String? previousId = previousFieldId(
              shown,
              _selectionController.selectedId,
            );
            final String? nextId = nextFieldId(
              shown,
              _selectionController.selectedId,
            );

            Future<void> moveField(String fieldId, int delta) async {
              if (sheetBusy) {
                return;
              }
              // The live revision, not the snapshot taken when the sheet
              // opened: a concurrent analysis apply must never be replaced by
              // a stale `before` state.
              final core.RevisionContent? content = _content;
              if (content == null) {
                return;
              }
              final FieldOrderChange? change = delta < 0
                  ? moveFieldUp(content, fieldId)
                  : moveFieldDown(content, fieldId);
              if (change == null || !change.changed) {
                // The field is already at the boundary or the live revision no
                // longer matches the rendered one; re-render from `_content`
                // instead of leaving a stale list on screen.
                setSheetState(() {
                  current = _content;
                });
                return;
              }
              setSheetState(() {
                sheetBusy = true;
              });
              await _commitSnapshot(
                change.content,
                kind: history.EditCommandKind.reorder,
                fieldId: fieldId,
              );
              if (!sheetContext.mounted) {
                return;
              }
              setSheetState(() {
                sheetBusy = false;
                current = _content;
              });
            }

            Future<void> applyPageOrder() async {
              if (sheetBusy) {
                return;
              }
              final core.RevisionContent? content = _content;
              if (content == null) {
                return;
              }
              final FieldOrderChange? change = moveFieldsToPageOrder(content);
              if (change == null) {
                setSheetState(() {
                  current = _content;
                });
                return;
              }
              setSheetState(() {
                sheetBusy = true;
              });
              await _commitSnapshot(
                change.content,
                kind: history.EditCommandKind.reorder,
                fieldId: change.fieldId,
              );
              if (!sheetContext.mounted) {
                return;
              }
              setSheetState(() {
                sheetBusy = false;
                current = _content;
              });
            }

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.7,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              l10n.fieldOrderTitle,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            key: const ValueKey<String>('field-order-close'),
                            tooltip: MaterialLocalizations.of(context)
                                .closeButtonTooltip,
                            onPressed: () =>
                                Navigator.of(sheetContext).maybePop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      Text(
                        l10n.fieldOrderHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          key: const ValueKey<String>(
                            'field-order-apply-page-order',
                          ),
                          onPressed: sheetBusy || isInPageOrder(shown)
                              ? null
                              : () {
                                  unawaited(applyPageOrder());
                                },
                          child: Text(l10n.fieldOrderApplyPageOrder),
                        ),
                      ),
                      Flexible(
                        child: FieldOrderReviewList(
                          content: shown,
                          busy: sheetBusy,
                          onMoveUp: (String fieldId) {
                            unawaited(moveField(fieldId, -1));
                          },
                          onMoveDown: (String fieldId) {
                            unawaited(moveField(fieldId, 1));
                          },
                          onSelect: (String fieldId) {
                            _selectFieldInOrder(fieldId);
                            unawaited(Navigator.of(sheetContext).maybePop());
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: TextButton(
                              key: const ValueKey<String>(
                                'field-order-previous',
                              ),
                              onPressed: previousId == null || sheetBusy
                                  ? null
                                  : () {
                                      _selectFieldInOrder(previousId);
                                      setSheetState(() {});
                                    },
                              child: Text(l10n.fieldOrderPreviousField),
                            ),
                          ),
                          Expanded(
                            child: TextButton(
                              key: const ValueKey<String>('field-order-next'),
                              onPressed: nextId == null || sheetBusy
                                  ? null
                                  : () {
                                      _selectFieldInOrder(nextId);
                                      setSheetState(() {});
                                    },
                              child: Text(l10n.fieldOrderNextField),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Selects one field of the current order and brings its page into view.
  ///
  /// This is a view-state change only: no value, geometry, or order is written;
  /// the committed values stay exactly as they are (FR-033).
  void _selectFieldInOrder(String fieldId) {
    final core.RevisionContent? content = _content;
    if (content == null) {
      return;
    }
    for (final core.ConfirmedField field in content.fields) {
      if (field.id != fieldId) {
        continue;
      }
      _viewerController.scrollToPage(field.pageIndex);
      _selectionController.select(field.id);
      return;
    }
  }

  /// Opens the T086D document overview without leaving the editor state.
  ///
  /// The overview receives a read-only snapshot of the current field order and
  /// durability status; the editor keeps every document, value, and pending
  /// edit while the route is on top. A returned field id is resolved against
  /// the live revision, selected, and opened for filling. „Weiter ausfüllen“
  /// simply returns to the unchanged editor.
  Future<void> _showDocumentOverview() async {
    final core.RevisionContent? content = _content;
    if (content == null) {
      return;
    }
    final DocumentOverviewOutcome? outcome = await Navigator.of(context)
        .push<DocumentOverviewOutcome>(
          MaterialPageRoute<DocumentOverviewOutcome>(
            builder: (BuildContext context) => DocumentOverviewScreen(
              entries: fieldOrderEntries(content),
              durabilityStatus: _durabilityStatus,
              lastDurableAt: _lastDurableAt,
            ),
          ),
        );
    if (!mounted || outcome == null) {
      return;
    }
    final String? fieldId = outcome.fieldId;
    if (fieldId == null) {
      return;
    }
    final core.RevisionContent? live = _content;
    if (live == null) {
      return;
    }
    final core.ConfirmedField? field = _fieldById(live, fieldId);
    if (field == null) {
      return;
    }
    _selectFieldInOrder(fieldId);
    await _openFieldValueSheet(field);
  }

  Future<void> _showPrivacyDisclosure() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          content: const SingleChildScrollView(
            child: PrivacyKeyDisclosure(visible: true),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.reviewConflictCloseAction),
            ),
          ],
        );
      },
    );
  }

  void _showReviewMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _completeSourceBytes(Uint8List? bytes) {
    if (!_sourceBytesReady.isCompleted) {
      _sourceBytesReady.complete(bytes);
    }
  }

  /// Resolves the viewer's existing US1 read-back closure once when the editor
  /// runtime is unavailable. This is not a second concurrent revision load:
  /// the editor load already terminated with `UnsupportedOperationException`.
  Future<void> _completeViewerSourceBytesFromFallback() async {
    Uint8List? bytes;
    try {
      bytes = await widget
          .sourceBytes(widget.source.sourceId)
          .timeout(widget.loadTimeout);
    } catch (_) {
      bytes = null;
    }
    _completeSourceBytes(bytes);
  }

  Future<Uint8List?> _viewerSourceBytes(String sourceId) {
    if (sourceId == widget.source.sourceId) {
      // The viewer waits for the editor's single protected load; it never
      // issues its own store read for the same document.
      return _sourceBytesReady.future;
    }
    return widget.sourceBytes(sourceId);
  }

  void _markFailed({int? elapsedMs, String reason = 'unknown'}) {
    if (!mounted) {
      return;
    }
    _analysisDiagnostic('ANALYSIS_STATE:failed:REASON=$reason');
    setState(() {
      _analysisStateKey = editorAnalysisFailedKey;
      if (elapsedMs != null) {
        _analysisElapsedMs = elapsedMs;
      }
    });
  }

  /// Height reserved for the T091 status under the app-bar title.
  ///
  /// The status is wrapped in a scroll view, so a long `saveFailed` sentence at
  /// 200 % scale stays reachable without an overflow error. The value scales
  /// with the caller's text scaler and is not a fixed dp guess.
  double _statusBarHeight(BuildContext context) {
    final double line = MediaQuery.textScalerOf(context).scale(14);
    return (line * 3.2 + 12).clamp(52.0, 140.0).toDouble();
  }

  @override
  void dispose() {
    _completeSourceBytes(null);
    _selectionController.dispose();
    _stripController.dispose();
    _viewerController.dispose();
    unawaited(widget.runtime.dispose());
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
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: <Widget>[
          IconButton(
            key: editorOverviewActionKey,
            tooltip: l10n.documentOverviewTitle,
            onPressed: _content == null
                ? null
                : () {
                    unawaited(_showDocumentOverview());
                  },
            icon: const Icon(Icons.checklist_rtl),
          ),
          IconButton(
            key: const ValueKey<String>('editor-field-order-action'),
            tooltip: l10n.fieldOrderTitle,
            onPressed: _content == null
                ? null
                : () {
                    unawaited(_showFieldOrderSheet());
                  },
            icon: const Icon(Icons.reorder),
          ),
          IconButton(
            key: const ValueKey<String>('editor-privacy-action'),
            tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
            onPressed: () {
              unawaited(_showPrivacyDisclosure());
            },
            icon: const Icon(Icons.privacy_tip_outlined),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_statusBarHeight(context)),
          child: SizedBox(
            height: _statusBarHeight(context),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: DurabilityStatusLabel(
                status: _durabilityStatus,
                lastDurableAt: _lastDurableAt,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (_analysisStateKey != null)
              SizedBox.shrink(key: ValueKey<String>(_analysisStateKey!)),
            PageStrip(controller: _stripController, pages: _stripPages),
            // The page strip stays fixed under the app bar. The warning and
            // review panel are header content: with an open IME (or at 200 %
            // text scale) they scroll inside a height bound so this column
            // never overflows and the page viewport keeps its minimum.
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double maxHeaderHeight =
                      (constraints.maxHeight - _minPageViewportHeight).clamp(
                        0.0,
                        double.infinity,
                      );
                  return Column(
                    children: <Widget>[
                      if (warning != null || _reviewPanelVisible)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: maxHeaderHeight,
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                if (warning != null)
                                  _Imp006Warning(warning: warning),
                                if (_reviewPanelVisible)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      4,
                                      8,
                                      4,
                                    ),
                                    child: SuggestionReviewPanel(
                                      suggestions: _content!.suggestions,
                                      confirmedFieldCount:
                                          _content!.fields.length,
                                      onConfirm:
                                          (core.FieldSuggestion suggestion) {
                                            unawaited(
                                              _confirmSuggestion(suggestion),
                                            );
                                          },
                                      onReject:
                                          (core.FieldSuggestion suggestion) {
                                            unawaited(
                                              _rejectSuggestion(suggestion),
                                            );
                                          },
                                      onUndo: () {
                                        unawaited(_undoLastEdit());
                                      },
                                      undoAvailable: _editHistory.canUndo,
                                      busy: _reviewBusy,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        child: PageView(
                          key: const ValueKey<String>('editor-page-view'),
                          sourceId: widget.source.sourceId,
                          sourceBytes: _viewerSourceBytes,
                          controller: _viewerController,
                          rendererFactory: widget.rendererFactory,
                          overlayBuilder: _buildPageOverlay,
                          // T071B: a one-finger drag on the selected field is
                          // geometry, not a page pan; two pointers always stay
                          // with the page view.
                          overlayDragStart: _beginGeometryDrag,
                          overlayDragUpdate: _updateGeometryDrag,
                          overlayDragEnd: _endGeometryDrag,
                        ),
                      ),
                    ],
                  );
                },
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
