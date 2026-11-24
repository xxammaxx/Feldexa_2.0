// ignore_for_file: implementation_imports

/// Bytes-level geometry/typing stage for one analysis page (T086B-R, #270).
///
/// Scope: this library owns everything the recognition pipeline does with a
/// page raster after rendering and OCR have finished — the 200 DPI analysis
/// tables (T051), the geometry detector (T052), the type inference (T053), the
/// confidence model (T054), the conflict graph (T055), and the typed, scored,
/// ordered section 2 suggestion maps. It opens no port, renders nothing, runs
/// no OCR, persists nothing, and never touches the platform.
///
/// The input is the *bytes* of one tight grayscale raster plus the page
/// parameters, so the whole stage is a pure function of sendable values. That
/// is what makes it runnable in a worker isolate: [RasterPageStageTask] and
/// [RasterPageStageOutcome] carry only `Uint8List`, `int`, `double`, `String`,
/// `bool`, lists, and maps of those. `analyze_document.dart` composes the
/// stages with rendering, OCR, and envelope assembly and executes
/// [runRasterPageStage] off the calling isolate.
///
/// Failure mapping is unchanged from the composed pipeline: an explicit
/// detector `PageAnalysisFailure` keeps its category, a detector precondition
/// or any other detector exception is `internal`, and a typing/assembly
/// exception is `internal` with the discarded partial suggestion count
/// (`recognition-output.md` §4). The stage returns that outcome instead of
/// throwing, so a page failure stays a value that crosses an isolate boundary
/// without a `RemoteError` and without losing the discarded count.
///
/// Determinism (`recognition-output.md` §5): the stage is a pure function of
/// its task. It reads no clock, no randomness, no locale, no I/O, and no
/// global state, and it logs nothing. Suggestion ids are assigned after the
/// §5.2 sort from the task page index, exactly as before.
library;

import 'dart:typed_data';

import 'package:feldexa_recognition/src/confidence.dart';
import 'package:feldexa_recognition/src/conflicts.dart';
import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/page_analysis.dart';
import 'package:feldexa_recognition/src/raster.dart';
import 'package:feldexa_recognition/src/suggestion_schema.dart';
import 'package:feldexa_recognition/src/type_inference.dart';

/// The production geometry detection function, replaceable only for
/// deterministic fault-injection tests of page failure isolation.
///
/// The default is [GeometryDetector.detect]. This is a test seam, not a new
/// port or architecture: the production path always uses the T052 detector.
typedef GeometryDetection = List<GeometryCandidate> Function(
  RasterAnalysis analysis, {
  required double pageWidthPt,
  required double pageHeightPt,
});

/// Builds the 200 DPI analysis tables for one stripped raster.
///
/// The default is `RasterAnalysis.new`. This is a fault-injection seam used
/// only to prove that an analysis failure maps to `internal`; the production
/// path always uses the T051 analysis.
typedef RasterAnalysisBuilder = RasterAnalysis Function(GrayRaster raster);

/// Fallback single-line median height when a page has no geometry candidate.
///
/// The value is inert on such a page because no candidate is typed. It keeps
/// the median rule total instead of introducing a nullable branch.
const double defaultSingleLineMedianHeightPt = 12.0;

/// Hard per-page bound on one page's off-isolate raster stage run.
///
/// This is a fail-closed diagnostic bound, not a performance statement: it
/// says nothing about SC-004, about end-to-end latency, or about the analysis
/// budget of a documented task. It is derived from the T086B-P measurement of
/// roughly two seconds per page at the 200 DPI analysis scale with a factor of
/// five, so a page that is merely slow still finishes and a page whose
/// detector hangs cannot hold the whole run.
///
/// When the bound elapses, `AnalyzeDocument` kills the page's worker isolate,
/// joins it, and turns the page into its existing `internal`/REC-002 failure
/// (`recognition-output.md` §4). No other page is affected.
const Duration defaultPageAnalysisDeadline = Duration(seconds: 10);

/// Minimum ordinal width of a suggestion id (`recognition-output.md` §2).
const int _ordinalWidth = 4;

/// One bytes-level geometry/typing stage task.
///
/// [pixels] is the tight, row-major, one-byte-per-pixel grayscale raster: its
/// length must be exactly `width * height`, with no row padding (the same
/// stride rule as `GrayRaster`). [labels] are the OCR observations the typing
/// stage aligns against, [ocrUsed] is the §3.3 OCR availability signal, and
/// [pageIndex] is the id prefix of the section 2 suggestion ids.
///
/// The task *is* the worker isolate message, so it takes ownership of [pixels]
/// instead of duplicating them: the runner serializes the buffer for the worker
/// anyway, and a defensive copy here would add a second full page raster to the
/// calling isolate's peak for a buffer nobody reads again (SC-004 memory). A
/// caller therefore hands over a buffer it does not use afterwards.
///
/// The stage analyses the raster with the documented `defaultInkThreshold` of
/// the T051 analysis. A task carries no threshold override, so a caller cannot
/// pass a value that nothing consumes.
final class RasterPageStageTask {
  /// Creates a task that takes ownership of [pixels].
  ///
  /// Throws a content-free [ArgumentError] for a negative page index, a
  /// non-positive dimension, a buffer length that is not `width * height`, or a
  /// non-finite or non-positive page size.
  RasterPageStageTask({
    required this.pageIndex,
    required this.pixels,
    required this.width,
    required this.height,
    required this.pageWidthPt,
    required this.pageHeightPt,
    this.labels = const <LabelObservation>[],
    this.ocrUsed = false,
  }) {
    if (pageIndex < 0) {
      throw ArgumentError('pageIndex must be non-negative.');
    }
    if (width <= 0 || height <= 0) {
      throw ArgumentError('raster dimensions must be positive.');
    }
    if (pixels.length != width * height) {
      throw ArgumentError(
        'pixels.length must be exactly width * height for a tight raster.',
      );
    }
    if (!pageWidthPt.isFinite ||
        pageWidthPt <= 0 ||
        !pageHeightPt.isFinite ||
        pageHeightPt <= 0) {
      throw ArgumentError('page size must be finite and positive.');
    }
  }

  /// Zero-based page index used as the suggestion id prefix.
  final int pageIndex;

  /// Tight grayscale pixels, `width * height` bytes, no row padding.
  ///
  /// Owned by this task; the caller must not mutate or reuse the buffer.
  final Uint8List pixels;

  /// Raster width in pixels.
  final int width;

  /// Raster height in pixels.
  final int height;

  /// Page display width in points after rotation.
  final double pageWidthPt;

  /// Page display height in points after rotation.
  final double pageHeightPt;

  /// OCR observations, already ordered by the §5.3 comparison.
  final List<LabelObservation> labels;

  /// Whether OCR actually ran for this page.
  final bool ocrUsed;
}

/// The outcome of one bytes-level geometry/typing stage run.
///
/// Exactly one of [suggestions] and [failureCategory] is meaningful: a
/// complete outcome carries the validated-shape section 2 suggestion maps, a
/// failed outcome carries the §4 category and the number of discarded partial
/// suggestions, and carries no suggestions at all (a failed page never leaks a
/// partial list).
final class RasterPageStageOutcome {
  const RasterPageStageOutcome._({
    required this.suggestions,
    required this.failureCategory,
    required this.discardedSuggestions,
    required this.timedOut,
  });

  /// A complete outcome with the §5.2-ordered suggestion maps.
  factory RasterPageStageOutcome.complete(
    List<Map<String, Object?>> suggestions,
  ) {
    return RasterPageStageOutcome._(
      suggestions: List<Map<String, Object?>>.unmodifiable(suggestions),
      failureCategory: null,
      discardedSuggestions: 0,
      timedOut: false,
    );
  }

  /// A failed outcome with no suggestions and a content-free §4 category.
  ///
  /// [category] must be one of the `PageAnalysisFailure` categories.
  /// [discardedSuggestions] is the number of partial drafts that were dropped.
  RasterPageStageOutcome.failed({
    required String category,
    int discardedSuggestions = 0,
  }) : this._(
         suggestions: const <Map<String, Object?>>[],
         failureCategory: _checkedCategory(category),
         discardedSuggestions: discardedSuggestions,
         timedOut: false,
       );

  /// The `internal` failure of a page whose stage run outlived its deadline.
  ///
  /// The worker isolate was killed before this outcome exists, so no partial
  /// work survives. The payload is the same content-free `internal`/REC-002
  /// failure as any other stage fault; [timedOut] is what tells the caller that
  /// the deadline, not the detector, ended the page.
  RasterPageStageOutcome.timedOut()
    : this._(
        suggestions: const <Map<String, Object?>>[],
        failureCategory: PageAnalysisFailure.internal,
        discardedSuggestions: 0,
        timedOut: true,
      );

  /// Section 2 suggestion maps; empty for a failed outcome.
  final List<Map<String, Object?>> suggestions;

  /// One of the `PageAnalysisFailure` categories, or null when complete.
  final String? failureCategory;

  /// Number of partial suggestions discarded by the failure.
  final int discardedSuggestions;

  /// Whether the per-page deadline, not the stage itself, ended this run.
  final bool timedOut;

  /// Whether the stage produced no terminal suggestion set.
  bool get isFailed => failureCategory != null;

  /// The §4 failure object for a failed outcome, or null when complete.
  PageAnalysisFailure? get failure {
    final String? category = failureCategory;
    if (category == null) {
      return null;
    }
    return PageAnalysisFailure.forCategory(
      category,
      suggestionCount: discardedSuggestions,
    );
  }

  @override
  String toString() =>
      'RasterPageStageOutcome(failureCategory: $failureCategory, '
      'suggestions: ${suggestions.length}, '
      'discardedSuggestions: $discardedSuggestions, timedOut: $timedOut)';
}

String _checkedCategory(String category) {
  if (!PageAnalysisFailure.messageKeys.containsKey(category)) {
    throw ArgumentError('Unknown page analysis failure category.');
  }
  return category;
}

/// The work one page runs on the analysing isolate.
///
/// The default is [runRasterPageStage]. A caller composes its fault-injection
/// seams into this closure (T052/T051), and a test substitutes it to observe
/// the worker isolate.
typedef RasterPageStageWork = RasterPageStageOutcome Function(
  RasterPageStageTask task,
);

/// Runs the geometry/typing stage for one page.
///
/// This is the public, isolate-safe bytes-level entry point: it is a pure
/// function of [task] (plus the two documented fault-injection seams), takes
/// and returns only sendable values, and never throws for a page-level
/// failure — failures are reported through [RasterPageStageOutcome].
///
/// [geometryDetection] and [rasterAnalysis] are the T052/T051 production
/// functions; they exist only so a test can inject a deterministic failure.
RasterPageStageOutcome runRasterPageStage(
  RasterPageStageTask task, {
  GeometryDetection geometryDetection = GeometryDetector.detect,
  RasterAnalysisBuilder rasterAnalysis = RasterAnalysis.new,
}) {
  final GrayRaster gray;
  try {
    gray = GrayRaster.fromGrayBytes(
      width: task.width,
      height: task.height,
      bytes: task.pixels,
    );
  } catch (_) {
    return RasterPageStageOutcome.failed(
      category: PageAnalysisFailure.internal,
    );
  }

  final RasterAnalysis analysis;
  try {
    analysis = rasterAnalysis(gray);
  } catch (_) {
    // A raster that reached the stage is well formed, so an analysis failure
    // is an internal pipeline fault (REC-002), exactly as in the composed
    // pipeline.
    return RasterPageStageOutcome.failed(
      category: PageAnalysisFailure.internal,
    );
  }

  final List<GeometryCandidate> candidates;
  try {
    candidates = geometryDetection(
      analysis,
      pageWidthPt: task.pageWidthPt,
      pageHeightPt: task.pageHeightPt,
    );
  } on PageAnalysisFailure catch (failure) {
    // Only an explicit detector signal may declare unsupported structure.
    return RasterPageStageOutcome.failed(category: failure.category);
  } catch (_) {
    // T052 ArgumentErrors describe page/geometry preconditions (page size not
    // representable, raster/page mismatch); they are internal here, never a
    // diagnosed unreadable structure.
    return RasterPageStageOutcome.failed(
      category: PageAnalysisFailure.internal,
    );
  }

  final List<_SuggestionDraft> drafts = <_SuggestionDraft>[];
  try {
    _buildDrafts(
      candidates: candidates,
      labels: task.labels,
      pageSizePt: PageDisplaySize(task.pageWidthPt, task.pageHeightPt),
      ocrUsed: task.ocrUsed,
      out: drafts,
    );
    return RasterPageStageOutcome.complete(
      _materializeSuggestions(drafts, task.pageIndex),
    );
  } catch (_) {
    return RasterPageStageOutcome.failed(
      category: PageAnalysisFailure.internal,
      discardedSuggestions: drafts.length,
    );
  }
}

void _buildDrafts({
  required List<GeometryCandidate> candidates,
  required List<LabelObservation> labels,
  required PageDisplaySize pageSizePt,
  required bool ocrUsed,
  required List<_SuggestionDraft> out,
}) {
  if (candidates.isEmpty) {
    return;
  }
  final double median = _singleLineMedianHeight(candidates);
  int insertion = 0;
  for (final GeometryCandidate candidate in candidates) {
    final TypeInferenceResult inference = TypeInference.infer(
      candidate: candidate,
      labels: labels,
      singleLineMedianHeightPt: median,
      pageWidthPt: pageSizePt.width,
      pageHeightPt: pageSizePt.height,
    );
    final List<String> cues = <String>{
      ...candidate.cues,
      ...inference.addedCues,
    }.toList()..sort();
    final List<CueFamilyAssignment> families =
        CueFamilyAssignment.distinctFamilies(cues);
    final ConfidenceAssessment confidence = ConfidenceModel.evaluate(
      ConfidenceInputs(
        supportingCueFamilies: families.length,
        credibleKeywordMatchesInferredType: _keywordMatchesInferredType(
          inference.addedCues,
          inference.proposedType,
        ),
        geometryWithinTypicalBounds: false,
        skewDegrees: 0,
        contrast: Contrast.normal,
        ocrUsed: ocrUsed,
        twoIndependentOcrLinesAgree: false,
      ),
    );
    out.add(
      _SuggestionDraft(
        rect: candidate.rect,
        proposedType: inference.proposedType,
        confidence: confidence.confidence,
        uncertainty: confidence.uncertainty,
        cueAgreement: families.length,
        cues: List<String>.unmodifiable(cues),
        labelText: inference.labelText,
        ocrUsed: ocrUsed,
        insertion: insertion,
      ),
    );
    insertion++;
  }
  out.sort(_compareDrafts);
}

double _singleLineMedianHeight(List<GeometryCandidate> candidates) {
  if (candidates.isEmpty) {
    return defaultSingleLineMedianHeightPt;
  }
  final List<double> heights = <double>[
    for (final GeometryCandidate candidate in candidates) candidate.rect.height,
  ]..sort();
  final int count = heights.length;
  if (count.isOdd) {
    return heights[count ~/ 2];
  }
  return (heights[count ~/ 2 - 1] + heights[count ~/ 2]) / 2;
}

bool _keywordMatchesInferredType(List<String> addedCues, String proposedType) {
  for (final String cue in addedCues) {
    if (!cue.startsWith('keyword_')) {
      continue;
    }
    final String key = cue.substring('keyword_'.length);
    if (TypeInference.forcedTypeForKey(key) == proposedType) {
      return true;
    }
  }
  return false;
}

List<Map<String, Object?>> _materializeSuggestions(
  List<_SuggestionDraft> drafts,
  int pageIndex,
) {
  final List<Map<String, Object?>> suggestions = <Map<String, Object?>>[];
  final List<ConflictItem> conflictItems = <ConflictItem>[];
  for (int index = 0; index < drafts.length; index++) {
    final _SuggestionDraft draft = drafts[index];
    final String id =
        's_p${pageIndex}_'
        '${(index + 1).toString().padLeft(_ordinalWidth, '0')}';
    conflictItems.add(
      ConflictItem(id: id, rect: draft.rect, type: draft.proposedType),
    );
    suggestions.add(<String, Object?>{
      'id': id,
      'pageIndex': pageIndex,
      'rect': <String, Object?>{
        'x': draft.rect.x,
        'y': draft.rect.y,
        'width': draft.rect.width,
        'height': draft.rect.height,
      },
      'proposedType': draft.proposedType,
      'confidence': draft.confidence,
      'uncertainty': draft.uncertainty,
      'labelText': draft.labelText,
      'evidence': <String, Object?>{
        'cues': draft.cues,
        'cueAgreement': draft.cueAgreement,
        'skewDegrees': 0.0,
        'contrast': 'normal',
        'ocrUsed': draft.ocrUsed,
      },
      'conflictsWith': const <String>[],
      'resolution': 'unresolved',
    });
  }
  if (suggestions.isEmpty) {
    return suggestions;
  }
  final ConflictGraph graph = ConflictDetector.detect(conflictItems);
  for (final Map<String, Object?> suggestion in suggestions) {
    final String id = suggestion['id']! as String;
    suggestion['conflictsWith'] = graph.conflictsWith[id]!;
  }
  return suggestions;
}

int _compareDrafts(_SuggestionDraft a, _SuggestionDraft b) {
  int result = _roundToEighth(a.rect.y).compareTo(_roundToEighth(b.rect.y));
  if (result != 0) {
    return result;
  }
  result = _roundToEighth(a.rect.x).compareTo(_roundToEighth(b.rect.x));
  if (result != 0) {
    return result;
  }
  result = _typeOrdinal(a.proposedType).compareTo(_typeOrdinal(b.proposedType));
  if (result != 0) {
    return result;
  }
  // §5.2 resolves remaining ties by stable insertion order from the scan.
  return a.insertion.compareTo(b.insertion);
}

int _typeOrdinal(String type) {
  final int index = SuggestionSchema.proposedTypes.indexOf(type);
  return index < 0 ? SuggestionSchema.proposedTypes.length : index;
}

double _roundToEighth(double value) => (value * 8).round() / 8;

/// One typed, scored candidate before ids and conflicts are assigned.
final class _SuggestionDraft {
  _SuggestionDraft({
    required this.rect,
    required this.proposedType,
    required this.confidence,
    required this.uncertainty,
    required this.cueAgreement,
    required this.cues,
    required this.labelText,
    required this.ocrUsed,
    required this.insertion,
  });

  final DisplayRect rect;
  final String proposedType;
  final double confidence;
  final double uncertainty;
  final int cueAgreement;
  final List<String> cues;
  final String? labelText;
  final bool ocrUsed;

  /// Zero-based detector order, used only as the final stable tie-break.
  final int insertion;
}
