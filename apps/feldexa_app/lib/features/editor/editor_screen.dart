// The Phase A use case and the T057 envelope do not yet have public barrel
// files; this consumer imports their stable source libraries deliberately,
// matching the Phase A composition and its tests.
// ignore_for_file: implementation_imports
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

import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/editor/page_state.dart';
import 'package:feldexa_app/features/editor/page_strip.dart';
import 'package:feldexa_app/features/editor/page_view.dart';
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_application/src/recognition/analyze_document.dart'
    as analysis;
import 'package:feldexa_application/src/review/confirm_suggestion.dart'
    as review;
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:feldexa_recognition/src/page_analysis.dart' as recognition;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart' hide PageView;

/// Stable key for a completed first analysis run whose revision was saved.
const String editorAnalysisReadyKey = 'analysis-ready';

/// Stable key for a revision that already had suggestions; no write occurred.
const String editorAnalysisSkippedKey = 'analysis-skipped';

/// Stable key for a content-free load/analysis/validation/save failure.
const String editorAnalysisFailedKey = 'analysis-failed';

/// Maximum per-edge difference in PDF points when comparing page geometry.
///
/// Persisted revisions may quantize geometry to three decimal places. An
/// inclusive 0.001 pt tolerance therefore absorbs storage round-tripping while
/// still rejecting a genuinely different media box, crop box, or orientation.
const double pageGeometryTolerancePt = 0.001;

/// Bound on the single editor `loadDocument` call.
///
/// A shared platform-channel result path that never answers must become the
/// deterministic `analysis-failed` state instead of an infinite pending editor.
/// The normal Android load is far below this bound; the timeout is a diagnostic
/// fail-closed guard, not a performance claim or a retry policy.
const Duration editorLoadTimeout = Duration(seconds: 30);

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
  final List<_ReviewUndo> _reviewUndoStack = <_ReviewUndo>[];
  bool _reviewBusy = false;
  final Completer<Uint8List?> _sourceBytesReady = Completer<Uint8List?>();

  /// The loaded or analyzed revision snapshot, or null when loading failed.
  core.RevisionContent? get content => _content;

  /// The verified loaded document, or null before/after a failed load.
  LoadedDocument? get loadedDocument => _loadedDocument;

  /// The latest committed revision id used as the next `expectedHead`.
  String? get headRevisionId => _headRevisionId;

  /// Whether an undoable review action is available.
  bool get canUndoReview => _reviewUndoStack.isNotEmpty;

  /// Whether a review command is currently being saved.
  bool get reviewBusy => _reviewBusy;

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
    final LoadedDocument loaded;
    try {
      loaded = await widget.runtime
          .loadDocument(widget.source.documentId)
          .timeout(widget.loadTimeout);
    } on UnsupportedOperationException {
      // Non-Android/failed editor compositions have no revision load, but the
      // T148 US1 viewer still has the protected read-back closure. Preserve
      // that viewer path without inventing analysis or a persisted revision.
      await _completeViewerSourceBytesFromFallback();
      _markFailed();
      return;
    } catch (_) {
      _completeSourceBytes(null);
      _markFailed();
      return;
    }
    // The viewer and the analysis path share this one protected load. No
    // second `store.loadDocument` is issued for the same document.
    _completeSourceBytes(loaded.sourceBytes);
    if (!mounted) {
      return;
    }
    if (loaded.meta.id != widget.source.documentId ||
        loaded.meta.source.id != widget.source.sourceId ||
        loaded.content.pageCount != widget.source.pageCount ||
        !_geometryMatchesSource(loaded)) {
      _markFailed();
      return;
    }
    setState(() {
      _loadedDocument = loaded;
      _content = loaded.content;
      _headRevisionId = loaded.meta.latestRevisionId;
      _stripPages = _buildStripPagesFromContent(loaded.content);
    });
    if (loaded.content.suggestions.isNotEmpty ||
        _hasPersistedAnalysisRun(loaded.content)) {
      // Reanalysis is a later task. Never duplicate or overwrite an existing
      // suggestion set, and never re-run a persisted first analysis (including
      // a completed zero-suggestion run) on reopen.
      setState(() {
        _analysisStateKey = editorAnalysisSkippedKey;
      });
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
      return;
    }
    final String analysisRunId = widget.runtime.ids.newId();
    _analysisRunId = analysisRunId;
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
      );
    } catch (_) {
      stopwatch.stop();
      _markFailed(elapsedMs: stopwatch.elapsedMilliseconds);
      return;
    }
    stopwatch.stop();
    if (!mounted) {
      return;
    }
    final core.RevisionContent analyzed;
    try {
      analyzed = applyDocumentAnalysis(base: loaded.content, result: result);
    } catch (_) {
      _markFailed(elapsedMs: stopwatch.elapsedMilliseconds);
      return;
    }
    final Set<int> uncertain = <int>{
      for (final recognition.FieldSuggestionSet set in result.pages)
        if (set.isComplete && set.pageUncertain) set.pageIndex,
    };
    setState(() {
      _content = analyzed;
      _stripPages = _buildStripPagesFromContent(
        analyzed,
        uncertainPages: uncertain,
      );
      _analysisElapsedMs = stopwatch.elapsedMilliseconds;
    });
    final StoredMeta saved;
    try {
      saved = await widget.runtime.saveRevision(
        SaveRevisionRequest(
          documentId: widget.source.documentId,
          expectedHead: loaded.meta.latestRevisionId,
          content: analyzed,
          kind: core.RevisionKind.autosave,
        ),
      );
    } catch (_) {
      // The viewer and the in-memory analysis result remain available; the
      // durable document is unchanged because the store rejected the save.
      _markFailed();
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _headRevisionId = saved.latestRevisionId ?? _headRevisionId;
      _analysisStateKey = editorAnalysisReadyKey;
    });
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
    await _commitReviewChange(
      change,
      undo: _ReviewUndo.confirmation(
        suggestionId: change.suggestionId,
        confirmedField: confirmedField,
      ),
      popUndo: false,
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
    await _commitReviewChange(
      change,
      undo: _ReviewUndo.rejection(suggestionId: change.suggestionId),
      popUndo: false,
    );
  }

  Future<void> _undoLastReview() async {
    final core.RevisionContent? content = _content;
    if (content == null || _reviewBusy || _reviewUndoStack.isEmpty) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final _ReviewUndo undo = _reviewUndoStack.last;
    final review.SuggestionReviewChange change;
    try {
      change = switch (undo.kind) {
        _ReviewUndoKind.rejection => review.undoRejection(
          content,
          undo.suggestionId,
        ),
        _ReviewUndoKind.confirmation => review.undoConfirmation(
          content,
          undo.suggestionId,
          undo.confirmedField!,
        ),
      };
    } catch (_) {
      _showReviewMessage(l10n.save007);
      return;
    }
    await _commitReviewChange(change, undo: null, popUndo: true);
  }

  /// Persists one review snapshot, then updates the visible revision.
  ///
  /// The store is written with the current [headRevisionId] as `expectedHead`.
  /// The visible content is only replaced after the store confirms the commit,
  /// so a failed review save leaves the viewer, page strip, prior suggestions,
  /// and confirmed fields exactly as they were. [undo] is pushed only after a
  /// successful commit; [popUndo] removes the consumed entry only on success.
  Future<void> _commitReviewChange(
    review.SuggestionReviewChange change, {
    required _ReviewUndo? undo,
    required bool popUndo,
  }) async {
    if (_reviewBusy) {
      return;
    }
    setState(() {
      _reviewBusy = true;
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
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _reviewBusy = false;
      });
      _showReviewMessage(AppLocalizations.of(context).save003);
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _content = change.content;
      _headRevisionId = saved.latestRevisionId ?? _headRevisionId;
      if (popUndo && _reviewUndoStack.isNotEmpty) {
        _reviewUndoStack.removeLast();
      }
      if (undo != null) {
        _reviewUndoStack.add(undo);
      }
      _reviewBusy = false;
    });
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

  void _markFailed({int? elapsedMs}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _analysisStateKey = editorAnalysisFailedKey;
      if (elapsedMs != null) {
        _analysisElapsedMs = elapsedMs;
      }
    });
  }

  @override
  void dispose() {
    _completeSourceBytes(null);
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
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (_analysisStateKey != null)
              SizedBox.shrink(key: ValueKey<String>(_analysisStateKey!)),
            PageStrip(controller: _stripController, pages: _stripPages),
            if (warning != null) _Imp006Warning(warning: warning),
            if (_reviewPanelVisible)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: SuggestionReviewPanel(
                  suggestions: _content!.suggestions,
                  confirmedFieldCount: _content!.fields.length,
                  onConfirm: (core.FieldSuggestion suggestion) {
                    unawaited(_confirmSuggestion(suggestion));
                  },
                  onReject: (core.FieldSuggestion suggestion) {
                    unawaited(_rejectSuggestion(suggestion));
                  },
                  onUndo: () {
                    unawaited(_undoLastReview());
                  },
                  undoAvailable: _reviewUndoStack.isNotEmpty,
                  busy: _reviewBusy,
                ),
              ),
            Expanded(
              child: PageView(
                sourceId: widget.source.sourceId,
                sourceBytes: _viewerSourceBytes,
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

enum _ReviewUndoKind { rejection, confirmation }

/// One reversible review action kept on the B2 undo stack.
final class _ReviewUndo {
  const _ReviewUndo.rejection({required this.suggestionId})
    : kind = _ReviewUndoKind.rejection,
      confirmedField = null;

  const _ReviewUndo.confirmation({
    required this.suggestionId,
    required this.confirmedField,
  }) : kind = _ReviewUndoKind.confirmation;

  final _ReviewUndoKind kind;
  final String suggestionId;
  final core.ConfirmedField? confirmedField;
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
