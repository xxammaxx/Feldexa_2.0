// ignore_for_file: implementation_imports

/// Phase A production recognition pipeline use case (issue #217, US2
/// integration).
///
/// Scope: this file is the application composition layer only. It renders one
/// page through the existing `PageRasterPort`, optionally runs the existing
/// `OcrPort` (T056), hands the tight grayscale bytes to the bytes-level
/// geometry/typing stage (`raster_page_stage.dart`: T051/T052/T053/T054/T055),
/// and returns one validated `FieldSuggestionSet` (T057) per page. It adds no
/// port, orchestrator, storage, detector, or UI, and it never persists
/// anything.
///
/// The stage runs off the calling isolate by default (T086B-R, issue #270):
/// the synchronous detector is the work that used to block the UI isolate. The
/// bytes-level entry and the worker runner are in `raster_page_stage.dart` and
/// `raster_page_stage_runner.dart`; this file keeps rendering, OCR, the
/// per-page envelope, and the page sequence, so the stage boundary contains no
/// port and no platform code.
///
/// One page is bounded twice: the caller's page cancellation token is polled at
/// the cheap checkpoints of the page work, and a page whose off-isolate stage
/// overruns `defaultPageAnalysisDeadline` has its worker killed and joined and
/// fails closed as `internal`/REC-002.
///
/// Normative sources:
///  * `contracts/recognition-output.md` §1 (envelope), §2 (suggestion), §2.1
///    (forbidden outputs), §3 (cues, typing, confidence), §4 (failure), §5
///    (determinism), and §6 (conflicts);
///  * `contracts/ports.md` §2.2/§2.3;
///  * `contracts/coordinates-and-geometry.md` §4;
///  * `spec.md` FR-011…FR-020, FR-083, FR-085;
///  * `data-model.md` §3.3/§3.16.
///
/// Documented decisions (also recorded in the task handoff):
///  * `singleLineMedianHeightPt` is the median of the detected candidate
///    heights. For an even count it is the arithmetic mean of the two middle
///    heights. When no candidate exists the fallback
///    [defaultSingleLineMedianHeightPt] is used; it is inert because no
///    candidate is typed on such a page.
///  * `credibleKeywordMatchesInferredType` is true only when the label
///    inference added a §3.2 type-forcing keyword cue whose forced type equals
///    the inferred type. Neutral keywords add their cue family but no keyword
///    bonus; this is the conservative reading of §3.3.
///  * Confidence uses `geometryWithinTypicalBounds = false` because no
///    typical-bounds estimator exists in Phase A, `skewDegrees = 0` and
///    `contrast = normal` because Phase A does not estimate either, and
///    `twoIndependentOcrLinesAgree = false` because Phase A does not run a
///    second OCR pass. These are deliberate conservative inputs.
///  * Suggestion ids are assigned after the deterministic §5.2 sort. The
///    authoritative sort is the T050 schema order
///    `pageIndex → rounded y → rounded x → type ordinal → id`; because ids do
///    not exist yet, the pre-id order uses `y → x → type ordinal → detector
///    insertion order`. The detector insertion order is the documented stable
///    scan order. `FieldSuggestionSet.fromJson` re-validates the finished
///    order and ordinal ids. The `height → width → cues` phrase in the task
///    package cannot be the primary sort: assigning ordinals in that order
///    would violate the T050 `order` rule whenever the type ordinal differs.
///  * OCR receives a tight-row `RasterImage`. When the rendered port image is
///    already tight (`bytesPerRow == width * bytesPerPixel`), the same object
///    is passed through so an identity-keyed page-size resolver such as
///    `AndroidPdfrxRasterClient.pageSizeOf(image)` still resolves it. Only a
///    padded image is rebuilt, because the OCR adapter contract and the
///    Android channel read `width × height` grayscale bytes; the rebuild
///    preserves width, height, gray8 format, and evidence, but deliberately
///    yields a new identity and therefore fails closed if a page-size resolver
///    only knows the padded source object.
///  * Failure mapping is stage-correct: a `renderPage` exception or a
///    dimension/format mismatch is `rasterization` (`PAGE-001`); a failure
///    while stripping row padding or constructing `RasterAnalysis` after a
///    successful render is `internal` (`REC-002`); a detector that throws
///    `PageAnalysisFailure.forCategory(unsupportedStructure)` keeps `REC-003`,
///    while the T052 `ArgumentError` preconditions and any other detector
///    exception are `internal`, because they describe an internal
///    page/geometry invariant, not a diagnosed unreadable structure.
///    Assembly failures are `internal`. An OCR failure is never a page
///    failure and only sets `ocrUsed = false`.
///  * Cancellation is polled at every cheap checkpoint of a page, not once per
///    page: at the page boundary before any work, again after render and OCR
///    before the geometry/typing stage is dispatched, and every
///    `_cancellationScanlineStride` scanlines while the rendered raster is
///    converted to tight bytes. The synchronous predicate cannot stop the
///    stage itself, so a caller can additionally pass one run-level
///    cancellation future: it is observed by the off-isolate runner, which
///    kills and joins the worker as soon as it completes instead of waiting
///    for `defaultPageAnalysisDeadline`; the inline mode observes it at its
///    checkpoints. A cancelled page produces no terminal envelope and is
///    reported separately, never as failed (contract §4). Remaining pages are
///    not started once the signal has completed.
///  * No label text, OCR text, file name, or path is logged. The use case has
///    no `print`, `dart:developer`, I/O, persistence, randomness, or locale
///    dependency.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/page_analysis.dart';
import 'package:feldexa_recognition/src/raster.dart';
import 'package:feldexa_recognition/src/suggestion_schema.dart';
import 'package:feldexa_recognition/src/type_inference.dart'
    show LabelObservation;

import 'raster_page_stage.dart';
import 'raster_page_stage_runner.dart';

/// Production OCR language hint (`contracts/ports.md` §2.3).
const String _ocrLanguageHint = 'de';

/// Comparison epsilon for page-boundary checks.
const double _pageEpsilon = 1e-6;

/// Scanline stride of the cooperative cancellation checkpoints.
///
/// While one page converts its rendered raster to tight bytes, it consults
/// [PageCancellation] once per stride instead of once per page. A page whose
/// token flips while it is already running therefore stops at the next band
/// rather than after the whole raster.
const int _cancellationScanlineStride = 64;

/// UUID shape shared by the T050 envelope validator for `analysisRunId`.
final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Lowercase UUIDv4 shape required by the port DTOs for `sourceId`.
final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// One page of one document analysis run.
///
/// [pageSizePt] is the page display size in points after `/Rotate`
/// (`coordinates-and-geometry.md` §1). [rotation] is the page geometry
/// rotation copied into the §1 envelope.
final class DocumentAnalysisPage {
  /// Creates a page descriptor.
  ///
  /// Throws a content-free [ArgumentError] for a negative index or an
  /// unsupported rotation. The display size validates itself.
  DocumentAnalysisPage({
    required this.pageIndex,
    required this.pageSizePt,
    this.rotation = 0,
  }) {
    if (pageIndex < 0) {
      throw ArgumentError('pageIndex must be non-negative.');
    }
    if (!SuggestionSchema.rotations.contains(rotation)) {
      throw ArgumentError('rotation must be one of 0, 90, 180, 270.');
    }
  }

  /// Creates a page descriptor from existing page geometry.
  ///
  /// The display size and rotation are read from [geometry]; no geometry is
  /// recomputed or persisted here.
  factory DocumentAnalysisPage.fromGeometry({
    required int pageIndex,
    required PageGeometry geometry,
  }) {
    final Size size = geometry.displaySize;
    return DocumentAnalysisPage(
      pageIndex: pageIndex,
      pageSizePt: PageDisplaySize(size.width, size.height),
      rotation: geometry.rotation,
    );
  }

  /// Zero-based page index.
  final int pageIndex;

  /// Display-space page size in points.
  final PageDisplaySize pageSizePt;

  /// Page rotation in degrees (`0 | 90 | 180 | 270`).
  final int rotation;
}

/// One document analysis run: explicit identity, pages, evidence class, and
/// the injected platform ports.
///
/// The request is immutable. The page list is copied; callers may keep and
/// mutate their own list without changing a run.
final class DocumentAnalysisRequest {
  /// Creates an analysis request.
  ///
  /// Throws a content-free [ArgumentError] for an invalid source id, analysis
  /// run id, evidence class, or duplicate page index.
  factory DocumentAnalysisRequest({
    required String sourceId,
    required String analysisRunId,
    required Iterable<DocumentAnalysisPage> pages,
    required String evidenceClass,
    required PageRasterPort rasterPort,
    OcrPort? ocrPort,
  }) {
    if (!_uuidV4Pattern.hasMatch(sourceId)) {
      throw ArgumentError('sourceId must be a lowercase UUIDv4.');
    }
    if (!_uuidPattern.hasMatch(analysisRunId)) {
      throw ArgumentError('analysisRunId must be a UUID.');
    }
    if (!SuggestionSchema.evidenceClasses.contains(evidenceClass)) {
      throw ArgumentError(
        'evidenceClass must be simulated, emulator, or device.',
      );
    }
    final List<DocumentAnalysisPage> pageList = List<DocumentAnalysisPage>.of(
      pages,
    );
    final Set<int> seen = <int>{};
    for (final DocumentAnalysisPage page in pageList) {
      if (!seen.add(page.pageIndex)) {
        throw ArgumentError(
          'Duplicate pageIndex in document analysis request.',
        );
      }
    }
    return DocumentAnalysisRequest._(
      sourceId: sourceId,
      analysisRunId: analysisRunId,
      pages: List<DocumentAnalysisPage>.unmodifiable(pageList),
      evidenceClass: evidenceClass,
      rasterPort: rasterPort,
      ocrPort: ocrPort,
    );
  }

  const DocumentAnalysisRequest._({
    required this.sourceId,
    required this.analysisRunId,
    required this.pages,
    required this.evidenceClass,
    required this.rasterPort,
    required this.ocrPort,
  });

  /// UUIDv4 of the immutable encrypted source (`contracts/ports.md` §2.2).
  final String sourceId;

  /// UUID shared by every page envelope of this run.
  final String analysisRunId;

  /// Immutable page list in caller order; results are sorted by page index.
  final List<DocumentAnalysisPage> pages;

  /// `simulated | emulator | device`.
  final String evidenceClass;

  /// Existing page raster capability.
  final PageRasterPort rasterPort;

  /// Existing OCR capability, or null when OCR is unavailable.
  final OcrPort? ocrPort;
}

/// The terminal outcome of one document analysis run.
///
/// [pages] contains exactly one terminal `FieldSuggestionSet` per
/// non-cancelled page, sorted by page index. Cancelled pages are absent and
/// listed in [cancelledPageIndexes]; the caller keeps them pending. Pages whose
/// stage run outlived the per-page deadline keep their existing
/// `internal`/REC-002 failure envelope in [pages] and are additionally listed
/// in [timedOutPageIndexes].
///
/// The type carries no value equality. [timedOutPageIndexes] is therefore
/// outside any `==`/`hashCode` by construction, exactly like the diagnostic
/// timings inside an envelope: it reports how a page ended, it is not part of
/// the page's canonical recognition output. Envelope comparison stays
/// `FieldSuggestionSet.canonicalJson`.
final class DocumentAnalysisResult {
  DocumentAnalysisResult._({
    required this.analysisRunId,
    required List<FieldSuggestionSet> pages,
    required List<int> cancelledPageIndexes,
    required List<int> timedOutPageIndexes,
  }) : pages = List<FieldSuggestionSet>.unmodifiable(pages),
       cancelledPageIndexes = List<int>.unmodifiable(cancelledPageIndexes),
       timedOutPageIndexes = List<int>.unmodifiable(timedOutPageIndexes);

  /// The run id shared by every envelope.
  final String analysisRunId;

  /// Terminal envelopes, sorted by page index.
  final List<FieldSuggestionSet> pages;

  /// Cancelled page indexes, sorted by page index.
  final List<int> cancelledPageIndexes;

  /// Page indexes whose stage run hit the deadline, sorted by page index.
  ///
  /// Content-free by construction: it names pages, never pixels, labels, or
  /// suggestion text. The matching envelope in [pages] carries the ordinary
  /// `internal`/REC-002 failure, so a timed-out page looks like any other
  /// internal page fault to a consumer that ignores this list.
  final List<int> timedOutPageIndexes;

  /// Whether every page reached a terminal outcome.
  bool get isComplete => cancelledPageIndexes.isEmpty;
}

/// The Phase A production recognition pipeline use case.
abstract final class AnalyzeDocument {
  /// Analyzes every requested page independently and returns one validated
  /// terminal envelope per non-cancelled page.
  ///
  /// Pages run sequentially in ascending page index order. One page's failure
  /// or cancellation never changes another page's outcome (FR-017/FR-018).
  ///
  /// [isCancelled] is the page cancellation token. It is consulted at the page
  /// boundary before any work, again after render and OCR before the expensive
  /// geometry/typing stage is dispatched, and every
  /// `_cancellationScanlineStride` scanlines while a page's raster is converted
  /// to tight bytes. Matching pages are omitted from
  /// [DocumentAnalysisResult.pages] and reported in
  /// [DocumentAnalysisResult.cancelledPageIndexes], never as failed and never
  /// with partial suggestions (`recognition-output.md` §4). A page already
  /// holding an envelope when its token flips keeps that envelope: cancellation
  /// removes work, it never rewrites a completed result.
  ///
  /// The token is a caller-side decision. It is not a message channel: a worker
  /// isolate cannot observe it, so the page-level checkpoints only bound the
  /// calling-isolate work.
  ///
  /// [cancellation] is the run-level cancellation signal. When it completes,
  /// the in-flight page's worker is killed and joined immediately - without
  /// waiting for [pageDeadline] - and the page is reported cancelled: no
  /// envelope, no partial suggestion, no failure (REC-004). Pages that have not
  /// started are not started and are reported cancelled as well. An already
  /// finished page keeps its envelope. In [RecognitionExecution.inline] the
  /// signal is observed at the page checkpoints only, because a single isolate
  /// cannot preempt running work.
  ///
  /// [geometryDetection] defaults to the production [GeometryDetector.detect]
  /// and [rasterAnalysis] defaults to `RasterAnalysis.new`; both exist only to
  /// inject a deterministic failure in isolation tests.
  ///
  /// [execution] selects how the bytes-level geometry/typing stage runs.
  /// [RecognitionExecution.offIsolate] is the production mode and the default:
  /// the synchronous T051/T052 work never runs on the calling isolate.
  /// [RecognitionExecution.inline] runs the identical entry on the calling
  /// isolate and is only for harnesses that cannot await a worker isolate.
  ///
  /// [pageDeadline] bounds one page's off-isolate stage run. When it elapses,
  /// the page's worker isolate is killed and joined, and the page receives its
  /// existing `internal`/REC-002 envelope while
  /// [DocumentAnalysisResult.timedOutPageIndexes] names it. Every page gets its
  /// own full deadline, so one page cannot spend another page's budget. The
  /// value is a fail-closed diagnostic bound and states nothing about SC-004,
  /// about end-to-end performance, or about any documented analysis budget.
  static Future<DocumentAnalysisResult> run(
    DocumentAnalysisRequest request, {
    PageCancellation? isCancelled,
    Future<void>? cancellation,
    GeometryDetection geometryDetection = GeometryDetector.detect,
    RasterAnalysisBuilder rasterAnalysis = RasterAnalysis.new,
    RecognitionExecution execution = RecognitionExecution.offIsolate,
    Duration pageDeadline = defaultPageAnalysisDeadline,
  }) async {
    final _CancellationWatch watch = _CancellationWatch(cancellation);
    if (watch.signal != null) {
      // An already-completed signal must win the first page boundary, before
      // any render work.
      await watch.settle();
    }
    final List<DocumentAnalysisPage> ordered =
        List<DocumentAnalysisPage>.of(request.pages)..sort(
          (DocumentAnalysisPage a, DocumentAnalysisPage b) =>
              a.pageIndex.compareTo(b.pageIndex),
        );
    final List<FieldSuggestionSet> pages = <FieldSuggestionSet>[];
    final List<int> cancelled = <int>[];
    final List<int> timedOut = <int>[];
    final Stopwatch clock = Stopwatch()..start();
    for (final DocumentAnalysisPage page in ordered) {
      if (watch.requested ||
          (isCancelled != null && isCancelled(page.pageIndex))) {
        cancelled.add(page.pageIndex);
        continue;
      }
      try {
        final ({FieldSuggestionSet envelope, bool timedOut}) analyzed =
            await _analyzePage(
              request,
              page,
              isCancelled,
              watch,
              geometryDetection,
              rasterAnalysis,
              execution,
              pageDeadline,
              clock,
            );
        pages.add(analyzed.envelope);
        if (analyzed.timedOut) {
          timedOut.add(page.pageIndex);
        }
      } on _PageCancelled {
        // The token flipped while this page was already running: the page
        // produced no envelope and no partial suggestion, and stays pending.
        cancelled.add(page.pageIndex);
      }
    }
    return DocumentAnalysisResult._(
      analysisRunId: request.analysisRunId,
      pages: pages,
      cancelledPageIndexes: cancelled,
      timedOutPageIndexes: timedOut,
    );
  }

  static Future<({FieldSuggestionSet envelope, bool timedOut})> _analyzePage(
    DocumentAnalysisRequest request,
    DocumentAnalysisPage page,
    PageCancellation? isCancelled,
    _CancellationWatch watch,
    GeometryDetection geometryDetection,
    RasterAnalysisBuilder rasterAnalysis,
    RecognitionExecution execution,
    Duration pageDeadline,
    Stopwatch clock,
  ) async {
    int rasterMs = 0;
    int ocrMs = 0;
    int detectMs = 0;
    int partialSuggestionCount = 0;
    bool timedOut = false;
    try {
      final int rasterStart = clock.elapsedMilliseconds;
      final RasterImage rendered;
      try {
        rendered = await _renderPage(request, page);
      } catch (_) {
        rasterMs = _elapsed(clock, rasterStart);
        throw PageAnalysisFailure.forCategory(
          PageAnalysisFailure.rasterization,
        );
      }
      final _TightRaster tight;
      try {
        tight = _tightRaster(rendered, isCancelled, page.pageIndex);
      } on _PageCancelled {
        rethrow;
      } catch (_) {
        // A successful render followed by a strip failure is an internal
        // pipeline fault, not a rasterization or page-structure one.
        rasterMs = _elapsed(clock, rasterStart);
        throw PageAnalysisFailure.forCategory(PageAnalysisFailure.internal);
      }
      rasterMs = _elapsed(clock, rasterStart);

      final int ocrStart = clock.elapsedMilliseconds;
      final _OcrStage ocr = await _runOcr(
        port: request.ocrPort,
        image: tight.ocrImage,
        page: page,
      );
      ocrMs = _elapsed(clock, ocrStart);

      if (watch.requested ||
          (isCancelled != null && isCancelled(page.pageIndex))) {
        // The page was cancelled during render or OCR; skipping the
        // geometry/typing stage keeps the synchronous detector off this page.
        throw const _PageCancelled();
      }

      final int detectStart = clock.elapsedMilliseconds;
      final RasterPageStageTask task = RasterPageStageTask(
        pageIndex: page.pageIndex,
        pixels: tight.pixels,
        width: rendered.width,
        height: rendered.height,
        pageWidthPt: page.pageSizePt.width,
        pageHeightPt: page.pageSizePt.height,
        labels: ocr.labels,
        ocrUsed: ocr.ocrUsed,
      );
      RasterPageStageOutcome work(RasterPageStageTask stageTask) {
        return runRasterPageStage(
          stageTask,
          geometryDetection: geometryDetection,
          rasterAnalysis: rasterAnalysis,
        );
      }

      final RasterPageStageOutcome outcome;
      if (execution == RecognitionExecution.inline) {
        outcome = work(task);
      } else {
        outcome = await runRasterPageStageOffIsolate(
          task,
          work: work,
          deadline: pageDeadline,
          cancellation: watch.signal,
        );
      }
      if (outcome.isCancelled) {
        // The runner ended the worker as soon as the caller cancelled; the
        // page stays pending and produces no partial suggestion.
        throw const _PageCancelled();
      }
      timedOut = outcome.timedOut;
      if (outcome.isFailed) {
        detectMs = _elapsed(clock, detectStart);
        throw outcome.failure!;
      }
      final List<Map<String, Object?>> suggestions = outcome.suggestions;
      partialSuggestionCount = suggestions.length;
      final FieldSuggestionSet envelope;
      try {
        envelope = FieldSuggestionSet.fromJson(<String, Object?>{
          'schemaVersion': SuggestionSchema.version,
          'analysisRunId': request.analysisRunId,
          'pageIndex': page.pageIndex,
          'pageSizePt': <String, Object?>{
            'width': page.pageSizePt.width,
            'height': page.pageSizePt.height,
          },
          'rotation': page.rotation,
          'status': FieldSuggestionSet.statusComplete,
          'pageUncertain': false,
          'uncertaintyReason': null,
          'failure': null,
          'suggestions': suggestions,
          'timings': <String, Object?>{
            'rasterMs': rasterMs,
            'ocrMs': ocrMs,
            'detectMs': _elapsed(clock, detectStart),
          },
          'evidenceClass': request.evidenceClass,
        });
      } catch (_) {
        detectMs = _elapsed(clock, detectStart);
        throw PageAnalysisFailure.forCategory(
          PageAnalysisFailure.internal,
          suggestionCount: partialSuggestionCount,
        );
      }
      detectMs = _elapsed(clock, detectStart);
      return (envelope: envelope, timedOut: false);
    } on _PageCancelled {
      rethrow;
    } on PageAnalysisFailure catch (failure) {
      return (
        envelope: _failedEnvelope(
          request,
          page,
          failure,
          _timings(rasterMs: rasterMs, ocrMs: ocrMs, detectMs: detectMs),
        ),
        timedOut: timedOut,
      );
    } catch (_) {
      return (
        envelope: _failedEnvelope(
          request,
          page,
          PageAnalysisFailure.forCategory(
            PageAnalysisFailure.internal,
            suggestionCount: partialSuggestionCount,
          ),
          _timings(rasterMs: rasterMs, ocrMs: ocrMs, detectMs: detectMs),
        ),
        timedOut: timedOut,
      );
    }
  }

  /// Renders and validates the page raster. Every failure here is a
  /// rasterization failure (`PAGE-001`).
  static Future<RasterImage> _renderPage(
    DocumentAnalysisRequest request,
    DocumentAnalysisPage page,
  ) async {
    final RasterImage image = await request.rasterPort.renderPage(
      RasterRequest(
        sourceId: request.sourceId,
        pageIndex: page.pageIndex,
        scale: rasterScale,
        format: RasterFormat.gray8,
      ),
    );
    final RasterSize expected = RasterSize.fromDisplaySize(
      widthPt: page.pageSizePt.width,
      heightPt: page.pageSizePt.height,
    );
    if (image.format != RasterFormat.gray8 ||
        image.width != expected.widthPx ||
        image.height != expected.heightPx) {
      throw PageAnalysisFailure.forCategory(PageAnalysisFailure.rasterization);
    }
    return image;
  }

  /// Strips row padding and supplies the tight OCR image.
  ///
  /// A port image that is already tight is passed to OCR unchanged. Passing
  /// the same object preserves identity-keyed page-size lookups in the Android
  /// raster adapter. A padded image must be rebuilt because OCR consumes one
  /// tight grayscale byte per pixel; the new object intentionally has no
  /// page-size entry, so the composed resolver fails closed instead of
  /// guessing a page size.
  ///
  /// The returned pixels are the bytes-level input of the geometry/typing
  /// stage, which takes ownership of them; the OCR image keeps its own buffer.
  ///
  /// The scanline loop consults [isCancelled] once per
  /// [_cancellationScanlineStride] rows and throws [_PageCancelled] between
  /// bands, so a token that flips while this page is already running stops the
  /// conversion instead of after the whole raster.
  static _TightRaster _tightRaster(
    RasterImage source,
    PageCancellation? isCancelled,
    int pageIndex,
  ) {
    final int width = source.width;
    final int height = source.height;
    final Uint8List pixels = Uint8List(width * height);
    final Uint8List sourceBytes = source.bytes;
    final int sourceStride = source.bytesPerRow;
    if (isCancelled == null && sourceStride == width) {
      // No token to observe and nothing to strip: one range copy.
      pixels.setRange(0, pixels.length, sourceBytes);
    } else {
      for (int row = 0; row < height; row++) {
        if (row % _cancellationScanlineStride == 0 &&
            isCancelled != null &&
            isCancelled(pageIndex)) {
          throw const _PageCancelled();
        }
        final int target = row * width;
        // The source row offset is the padded stride; it equals the tight
        // width for an already-tight raster.
        pixels.setRange(
          target,
          target + width,
          sourceBytes,
          row * sourceStride,
        );
      }
    }
    final int tightBytesPerRow = width * source.format.bytesPerPixel;
    final RasterImage ocrImage = source.bytesPerRow == tightBytesPerRow
        ? source
        : RasterImage(
            bytes: Uint8List.fromList(pixels),
            width: width,
            height: height,
            bytesPerRow: width,
            format: RasterFormat.gray8,
            evidence: source.evidence,
          );
    return _TightRaster(pixels, ocrImage);
  }

  static Future<_OcrStage> _runOcr({
    required OcrPort? port,
    required RasterImage image,
    required DocumentAnalysisPage page,
  }) async {
    if (port == null) {
      return const _OcrStage(labels: <LabelObservation>[], ocrUsed: false);
    }
    try {
      final List<OcrBlock> blocks = await port.recognize(
        OcrRequest(
          image: image,
          pageIndex: page.pageIndex,
          languageHint: _ocrLanguageHint,
        ),
      );
      return _OcrStage(
        labels: _labelsFromBlocks(blocks, page.pageSizePt),
        ocrUsed: true,
      );
    } catch (_) {
      // OCR is auxiliary (constitution Principle IV): any OCR failure is
      // recoverable and continues geometry-only with the §3.3 penalty.
      return const _OcrStage(labels: <LabelObservation>[], ocrUsed: false);
    }
  }

  static List<LabelObservation> _labelsFromBlocks(
    List<OcrBlock> blocks,
    PageDisplaySize pageSizePt,
  ) {
    final List<LabelObservation> labels = <LabelObservation>[];
    for (final OcrBlock block in blocks) {
      if (block.lines.isNotEmpty) {
        for (final OcrLine line in block.lines) {
          labels.add(
            _labelObservation(
              text: line.text,
              rect: line.rect,
              confidence: line.confidence,
              pageSizePt: pageSizePt,
            ),
          );
        }
      } else {
        labels.add(
          _labelObservation(
            text: block.text,
            rect: block.rect,
            confidence: block.confidence,
            pageSizePt: pageSizePt,
          ),
        );
      }
    }
    // §5.3: OCR observations are ordered before alignment matching. The
    // inference itself is order-independent; this only makes the input
    // canonical.
    labels.sort(_compareLabels);
    return List<LabelObservation>.unmodifiable(labels);
  }

  static LabelObservation _labelObservation({
    required String text,
    required Rect rect,
    required double confidence,
    required PageDisplaySize pageSizePt,
  }) {
    final double right = rect.left + rect.width;
    final double bottom = rect.top + rect.height;
    if (rect.left < -_pageEpsilon ||
        rect.top < -_pageEpsilon ||
        right > pageSizePt.width + _pageEpsilon ||
        bottom > pageSizePt.height + _pageEpsilon) {
      throw const FormatException(
        'OCR label rectangle is outside the page bounds.',
      );
    }
    return LabelObservation(
      text: text,
      rect: DisplayRect(
        x: rect.left,
        y: rect.top,
        width: rect.width,
        height: rect.height,
      ),
      ocrConfidence: confidence,
    );
  }

  static int _compareLabels(LabelObservation a, LabelObservation b) {
    int result = _roundToEighth(a.rect.y).compareTo(_roundToEighth(b.rect.y));
    if (result != 0) {
      return result;
    }
    result = _roundToEighth(a.rect.x).compareTo(_roundToEighth(b.rect.x));
    if (result != 0) {
      return result;
    }
    return a.text.compareTo(b.text);
  }

  static double _roundToEighth(double value) => (value * 8).round() / 8;

  static int _elapsed(Stopwatch clock, int start) {
    final int value = clock.elapsedMilliseconds - start;
    return value < 0 ? 0 : value;
  }

  static PageAnalysisTimings _timings({
    required int rasterMs,
    required int ocrMs,
    required int detectMs,
  }) {
    return PageAnalysisTimings(
      rasterMs: rasterMs < 0 ? 0 : rasterMs,
      ocrMs: ocrMs < 0 ? 0 : ocrMs,
      detectMs: detectMs < 0 ? 0 : detectMs,
    );
  }

  static FieldSuggestionSet _failedEnvelope(
    DocumentAnalysisRequest request,
    DocumentAnalysisPage page,
    PageAnalysisFailure failure,
    PageAnalysisTimings timings,
  ) {
    return FieldSuggestionSet(
      pageIndex: page.pageIndex,
      analysisRunId: request.analysisRunId,
      pageSizePt: page.pageSizePt,
      rotation: page.rotation,
      status: FieldSuggestionSet.statusFailed,
      failure: failure,
      timings: timings,
      evidenceClass: request.evidenceClass,
    );
  }
}

/// Tight grayscale pixels plus the OCR image for one rendered page.
final class _TightRaster {
  _TightRaster(this.pixels, this.ocrImage);

  /// Row-major, one byte per pixel, `width * height` bytes, no padding.
  final Uint8List pixels;

  /// The tight image handed to OCR; identical to the port image when the port
  /// already delivered a tight raster.
  final RasterImage ocrImage;
}

/// OCR labels plus whether OCR actually ran for the page.
final class _OcrStage {
  const _OcrStage({required this.labels, required this.ocrUsed});

  final List<LabelObservation> labels;
  final bool ocrUsed;
}

/// Signals that the page cancellation token flipped while the page was running.
///
/// This is not a page failure: `run` records the page in
/// [DocumentAnalysisResult.cancelledPageIndexes] and emits no envelope
/// (`recognition-output.md` §4, REC-004).
final class _PageCancelled implements Exception {
  const _PageCancelled();
}

/// Observes one run-level cancellation signal without awaiting it.
///
/// The signal is a caller-side future; the page loop must be able to ask
/// "already requested?" at a boundary without blocking on an unfinished
/// future, so the observer records the first completion (value or error) in
/// [requested]. [settle] yields one microtask so a signal that was already
/// completed before the run started is visible at the first boundary.
final class _CancellationWatch {
  _CancellationWatch(this.signal) {
    final Future<void>? source = signal;
    if (source != null) {
      unawaited(
        source.then<void>(
          (void _) => requested = true,
          onError: (Object _) => requested = true,
        ),
      );
    }
  }

  /// The raw signal handed to the off-isolate runner, or null.
  final Future<void>? signal;

  /// Whether the signal completed (value or error).
  bool requested = false;

  /// Yields one microtask so a completed signal is observed.
  Future<void> settle() => Future<void>.microtask(() {});
}
