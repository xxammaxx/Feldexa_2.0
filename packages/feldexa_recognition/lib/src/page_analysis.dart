// T057 per-page analysis envelope, classification, and failure isolation.
//
// Normative sources:
//  * specs/001-scanned-form-workflow/contracts/recognition-output.md
//    section 1 (envelope), section 2 (suggestion wire shape), section 4
//    (failure contract), section 5 (determinism), and section 5.5
//    (canonical projection);
//  * specs/001-scanned-form-workflow/spec.md FR-017, FR-018, FR-019, FR-020;
//  * specs/001-scanned-form-workflow/data-model.md section 3.3 (page analysis
//    state machine) and section 3.16 (`FieldSuggestionSet`);
//  * specs/001-scanned-form-workflow/contracts/error-catalog.de.md section 2.
//
// Scope: one immutable per-page recognition envelope, one content-free
// recognition failure object, a pure signal-to-outcome classifier, and a
// synchronous per-page isolation batch. Suggestions are already-computed,
// validated recognition-output section 2 wire maps: the core-owned
// `FieldSuggestion` (T018) is not duplicated here. Detection, typing,
// confidence scoring, conflicts, persistence, the resolution state machine,
// the core `AnalysisState`/`PageFailure` types, UI, Android, I/O, isolates,
// randomness, clock, and locale are out of scope.
//
// Validation is adopted, not re-implemented. `SuggestionSchema.validateEnvelope`
// remains the single oracle for the section 1/2/4 wire shape, suggestion
// vocabulary, conflict rules, and deterministic sort order. This model adds
// only rules the wire contract leaves to the envelope owner:
//   * `uncertaintyReason` is required when `pageUncertain` is true; a valid
//     reason may be retained when `pageUncertain` is false for wire
//     compatibility (the T050 validator documents that as a deliberate
//     non-rule), so this model does not reject it;
//   * suggestions are sorted and deep-frozen on input, so caller mutations
//     cannot change a constructed envelope;
//   * failed envelopes carry no suggestions; the discarded partial count is
//     reported through `failure.suggestionCount` (section 4).
//
// One documented reconciliation: the T050 validator accepts only `REC-<nnn>`
// failure message keys, while section 2 of the error catalog assigns the
// rasterization failure `PAGE-001` and this task's binding owner decision
// fixes that mapping. [FieldSuggestionSet] therefore suppresses exactly one
// validator finding - `envelope.failure.messageKey: format` when the failure
// is `rasterization` with `PAGE-001` - and rejects every other finding.
// Widening the shared validator is T050/T058 follow-up work; this module does
// not edit it.
//
// Cancellation is not a failure (error catalog REC-004 has no message). A
// cancelled page is left out of the terminal batch result so the caller keeps
// the core `Page.analysis` value at `pending`.
library;

import 'package:feldexa_recognition/src/suggestion_schema.dart';

/// Converts a page index into a cancellation decision.
///
/// A cancelled page produces no terminal envelope. The caller keeps it
/// `pending`; it is never reported as failed (recognition-output.md section 4
/// and error catalog REC-004).
typedef PageCancellation = bool Function(int pageIndex);

/// Integer diagnostics for one page analysis run (`recognition-output.md`
/// section 1).
///
/// Timings are diagnostics only: they are excluded from the canonical
/// projection and from golden equality. Values are non-negative integer
/// milliseconds.
final class PageAnalysisTimings {
  const PageAnalysisTimings._(this.rasterMs, this.ocrMs, this.detectMs);

  /// Creates validated timings.
  ///
  /// Throws [ArgumentError] when any value is negative. The error is
  /// content-free.
  factory PageAnalysisTimings({
    required int rasterMs,
    required int ocrMs,
    required int detectMs,
  }) {
    if (rasterMs < 0 || ocrMs < 0 || detectMs < 0) {
      throw ArgumentError('Page analysis timings must be non-negative.');
    }
    return PageAnalysisTimings._(rasterMs, ocrMs, detectMs);
  }

  /// Timings for a path that reported no stage duration.
  static const PageAnalysisTimings zero = PageAnalysisTimings._(0, 0, 0);

  /// Rasterization duration in milliseconds.
  final int rasterMs;

  /// OCR duration in milliseconds.
  final int ocrMs;

  /// Geometry detection duration in milliseconds.
  final int detectMs;

  /// Parses the closed `timings` object of `recognition-output.md` section 1.
  ///
  /// Throws [FormatException] for a missing, extra, non-integer, or negative
  /// value. The error never echoes input keys or values.
  factory PageAnalysisTimings.fromJson(Map<String, Object?> json) {
    if (json.length != 3 ||
        !json.containsKey('rasterMs') ||
        !json.containsKey('ocrMs') ||
        !json.containsKey('detectMs')) {
      throw const FormatException('Invalid page analysis timings: shape.');
    }
    final Object? rasterMs = json['rasterMs'];
    final Object? ocrMs = json['ocrMs'];
    final Object? detectMs = json['detectMs'];
    if (rasterMs is! int || rasterMs < 0) {
      throw const FormatException('Invalid page analysis timings: rasterMs.');
    }
    if (ocrMs is! int || ocrMs < 0) {
      throw const FormatException('Invalid page analysis timings: ocrMs.');
    }
    if (detectMs is! int || detectMs < 0) {
      throw const FormatException('Invalid page analysis timings: detectMs.');
    }
    return PageAnalysisTimings._(rasterMs, ocrMs, detectMs);
  }

  /// Returns a fresh mutable `timings` object.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'rasterMs': rasterMs,
      'ocrMs': ocrMs,
      'detectMs': detectMs,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is PageAnalysisTimings &&
        other.rasterMs == rasterMs &&
        other.ocrMs == ocrMs &&
        other.detectMs == detectMs;
  }

  @override
  int get hashCode => Object.hash(rasterMs, ocrMs, detectMs);

  @override
  String toString() {
    return 'PageAnalysisTimings(rasterMs: $rasterMs, ocrMs: $ocrMs, '
        'detectMs: $detectMs)';
  }
}

/// One terminal recognition failure (`recognition-output.md` section 4).
///
/// The category vocabulary is the four recognition categories:
/// `rasterization | ocr | unsupported_structure | internal`. The message key is
/// not caller-selectable: it is fixed by [messageKeys] from the error catalog
/// (rasterization `PAGE-001`, ocr `REC-001`, unsupported_structure `REC-003`,
/// internal `REC-002`). Cancellation is intentionally absent: REC-004 has no
/// failure object and leaves the page pending.
///
/// The object is content-free by construction. It carries no file name, path,
/// URI, label, OCR text, or document content, and [toString] never echoes
/// input beyond the four validated fields. It implements [Exception] so an
/// analyzer can abort one page by throwing it; the isolation batch converts it
/// into that page's failed envelope without touching other pages.
final class PageAnalysisFailure implements Exception {
  const PageAnalysisFailure._(
    this.category,
    this.messageKey,
    this.recoverable,
    this.suggestionCount,
  );

  /// Page could not be rendered for analysis (`PAGE-001`).
  static const String rasterization = 'rasterization';

  /// OCR engine unavailable or failed (`REC-001`).
  static const String ocr = 'ocr';

  /// Page structure unsupported or unreadable (`REC-003`).
  static const String unsupportedStructure = 'unsupported_structure';

  /// Unexpected failure (`REC-002`).
  static const String internal = 'internal';

  /// The fixed category-to-message-key mapping of error catalog section 2.
  static const Map<String, String> messageKeys = <String, String>{
    rasterization: 'PAGE-001',
    ocr: 'REC-001',
    unsupportedStructure: 'REC-003',
    internal: 'REC-002',
  };

  static final RegExp _messageKeyPattern = RegExp(r'^[A-Z]{2,6}-\d{3}$');

  /// Creates a failure with the catalog-fixed key for [category].
  ///
  /// [recoverable] is a caller signal preserved on the wire. It defaults to
  /// true because every catalogued section 4 category offers a recovery path
  /// (retry or manual fields); the data model does not derive recoverability
  /// from the category.
  ///
  /// [suggestionCount] is the number of partial suggestions discarded for
  /// this page. It must be non-negative.
  factory PageAnalysisFailure.forCategory(
    String category, {
    bool recoverable = true,
    int suggestionCount = 0,
  }) {
    final String? messageKey = messageKeys[category];
    if (messageKey == null) {
      throw ArgumentError('Unknown page analysis failure category.');
    }
    if (suggestionCount < 0) {
      throw ArgumentError('suggestionCount must be non-negative.');
    }
    return PageAnalysisFailure._(
      category,
      messageKey,
      recoverable,
      suggestionCount,
    );
  }

  /// Parses the closed section 4 failure object.
  ///
  /// Enforces the exact four keys, the category vocabulary, the fixed
  /// category-to-key mapping, the `CODE-nnn` catalog key format, a boolean
  /// `recoverable`, and a non-negative integer `suggestionCount`. Throws
  /// [FormatException] without echoing any input key or value.
  factory PageAnalysisFailure.fromJson(Map<String, Object?> json) {
    if (json.length != 4 ||
        !json.containsKey('category') ||
        !json.containsKey('messageKey') ||
        !json.containsKey('recoverable') ||
        !json.containsKey('suggestionCount')) {
      throw const FormatException('Invalid page analysis failure: shape.');
    }
    final Object? category = json['category'];
    final Object? messageKey = json['messageKey'];
    final Object? recoverable = json['recoverable'];
    final Object? suggestionCount = json['suggestionCount'];
    if (category is! String || messageKeys[category] == null) {
      throw const FormatException('Invalid page analysis failure: category.');
    }
    if (messageKey is! String || !_messageKeyPattern.hasMatch(messageKey)) {
      throw const FormatException('Invalid page analysis failure: messageKey.');
    }
    if (messageKeys[category] != messageKey) {
      throw const FormatException('Invalid page analysis failure: mapping.');
    }
    if (recoverable is! bool) {
      throw const FormatException(
        'Invalid page analysis failure: recoverable.',
      );
    }
    if (suggestionCount is! int || suggestionCount < 0) {
      throw const FormatException(
        'Invalid page analysis failure: suggestionCount.',
      );
    }
    return PageAnalysisFailure._(
      category,
      messageKey,
      recoverable,
      suggestionCount,
    );
  }

  /// One of the four recognition failure categories.
  final String category;

  /// The catalog-fixed key for [category].
  final String messageKey;

  /// Whether a recovery path is available for this failure.
  final bool recoverable;

  /// Number of discarded partial suggestions for this page.
  final int suggestionCount;

  /// Returns a fresh mutable section 4 failure object.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'category': category,
      'messageKey': messageKey,
      'recoverable': recoverable,
      'suggestionCount': suggestionCount,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is PageAnalysisFailure &&
        other.category == category &&
        other.messageKey == messageKey &&
        other.recoverable == recoverable &&
        other.suggestionCount == suggestionCount;
  }

  @override
  int get hashCode {
    return Object.hash(category, messageKey, recoverable, suggestionCount);
  }

  @override
  String toString() {
    return 'PageAnalysisFailure(category: $category, '
        'messageKey: $messageKey, recoverable: $recoverable, '
        'suggestionCount: $suggestionCount)';
  }
}

/// Explicit analysis signals used by [classifyPageAnalysis].
///
/// The signals describe what a caller already knows after attempting a stage.
/// They are not inferred here: this module does not rasterize, run OCR, or
/// detect geometry.
final class PageAnalysisSignals {
  /// Creates a signal set. All flags default to false, meaning every stage
  /// succeeded.
  const PageAnalysisSignals({
    this.rasterFailed = false,
    this.geometryFailed = false,
    this.ocrFailed = false,
    this.structureUnsupported = false,
    this.cancelled = false,
  });

  /// Page rasterization did not produce an analyzable page.
  final bool rasterFailed;

  /// Geometry detection failed.
  final bool geometryFailed;

  /// OCR was unavailable or failed.
  final bool ocrFailed;

  /// The input declares the page structure unsupported or unreadable.
  final bool structureUnsupported;

  /// The caller cancelled the page.
  final bool cancelled;
}

/// Terminal classification of one page attempt.
enum PageAnalysisDecisionKind {
  /// The page produced a terminal complete envelope (possibly empty).
  complete,

  /// The page produced a terminal failure.
  failed,

  /// The page was cancelled and stays pending; it is not a failure.
  cancelled,
}

/// The pure outcome of applying the section 4 rules to
/// [PageAnalysisSignals].
final class PageAnalysisDecision {
  /// A complete page. [ocrUsed] is false when geometry-only detection ran.
  const PageAnalysisDecision.complete({required this.ocrUsed})
    : kind = PageAnalysisDecisionKind.complete,
      failure = null;

  /// A failed page with a catalog-fixed failure object.
  const PageAnalysisDecision.failed(PageAnalysisFailure this.failure)
    : kind = PageAnalysisDecisionKind.failed,
      ocrUsed = false;

  /// A cancelled page that stays pending and is not a failure.
  const PageAnalysisDecision.cancelled()
    : kind = PageAnalysisDecisionKind.cancelled,
      ocrUsed = false,
      failure = null;

  /// The terminal disposition.
  final PageAnalysisDecisionKind kind;

  /// Whether OCR evidence is available for the complete envelope.
  final bool ocrUsed;

  /// The failure object; non-null exactly when [kind] is failed.
  final PageAnalysisFailure? failure;

  /// Whether the page has a terminal outcome (complete or failed).
  bool get isTerminal => kind != PageAnalysisDecisionKind.cancelled;

  /// Whether the page completed.
  bool get isComplete => kind == PageAnalysisDecisionKind.complete;

  /// Whether the page failed.
  bool get isFailed => kind == PageAnalysisDecisionKind.failed;

  /// Whether the page was cancelled and stays pending.
  bool get isCancelled => kind == PageAnalysisDecisionKind.cancelled;
}

/// Applies the `recognition-output.md` section 4 failure rules.
///
/// Precedence and behavior:
///   1. cancellation wins and is not a failure (REC-004, no message);
///   2. a rasterization failure returns `rasterization` (`PAGE-001`);
///   3. a geometry failure returns `unsupported_structure` (`REC-003`) when
///      [PageAnalysisSignals.structureUnsupported] is set, otherwise
///      `internal` (`REC-002`);
///   4. an OCR failure alone never fails the page: geometry-only detection is
///      reported as complete with [PageAnalysisDecision.ocrUsed] false, so the
///      caller records `evidence.ocrUsed: false` and the lower confidence;
///   5. otherwise the page is complete with OCR used.
///
/// [suggestionCount] is copied into a returned failure. It is the number of
/// partial suggestions discarded for that page and must be non-negative.
PageAnalysisDecision classifyPageAnalysis(
  PageAnalysisSignals signals, {
  int suggestionCount = 0,
}) {
  if (suggestionCount < 0) {
    throw ArgumentError('suggestionCount must be non-negative.');
  }
  if (signals.cancelled) {
    return const PageAnalysisDecision.cancelled();
  }
  if (signals.rasterFailed) {
    return PageAnalysisDecision.failed(
      PageAnalysisFailure.forCategory(
        PageAnalysisFailure.rasterization,
        suggestionCount: suggestionCount,
      ),
    );
  }
  if (signals.geometryFailed) {
    return PageAnalysisDecision.failed(
      PageAnalysisFailure.forCategory(
        signals.structureUnsupported
            ? PageAnalysisFailure.unsupportedStructure
            : PageAnalysisFailure.internal,
        suggestionCount: suggestionCount,
      ),
    );
  }
  return PageAnalysisDecision.complete(ocrUsed: !signals.ocrFailed);
}

/// Identity and display geometry of one page analysis job.
///
/// The isolation batch validates the identity fields and rejects duplicates or
/// invalid values before invoking any analyzer. The job carries no document
/// content.
final class PageAnalysisJob {
  /// Creates a job description.
  const PageAnalysisJob({
    required this.pageIndex,
    required this.analysisRunId,
    required this.pageSizePt,
    required this.evidenceClass,
    this.rotation = 0,
  });

  /// Zero-based page index.
  final int pageIndex;

  /// Analysis run UUID shared by every envelope of one invocation.
  final String analysisRunId;

  /// Display size in points.
  final PageDisplaySize pageSizePt;

  /// Page rotation in degrees (`0 | 90 | 180 | 270`).
  final int rotation;

  /// `simulated | emulator | device`.
  final String evidenceClass;
}

/// Synchronous, deterministic per-page isolation batch.
///
/// One analyzer call runs for every non-cancelled job, in ascending page index
/// order. No isolate, thread, platform channel, or I/O is used. A page-local
/// exception or invalid result becomes that page's failure and cannot change
/// another page's result (FR-017/FR-018).
abstract final class PageAnalysisBatch {
  /// Analyzes [jobs] independently and returns one terminal envelope per
  /// non-cancelled page, sorted by page index.
  ///
  /// [analyze] receives the validated job and must return an envelope whose
  /// page index, run id, display size, rotation, and evidence class match the
  /// job. A mismatched result is replaced by that page's `internal` failure
  /// (`REC-002`) without affecting other pages.
  ///
  /// When [analyze] throws a [PageAnalysisFailure], its category, recoverable
  /// flag, and `suggestionCount` are preserved in the failed envelope. Any
  /// other exception becomes `internal` with `suggestionCount: 0`. Synthesized
  /// failures use [PageAnalysisTimings.zero] because no stage reported a
  /// duration; timings are diagnostics only.
  ///
  /// A page for which [isCancelled] returns true is never analyzed, produces
  /// no terminal envelope, and is never marked failed. The caller keeps it
  /// pending (REC-004).
  ///
  /// Rejects a negative page index, duplicate page indexes, or an invalid job
  /// identity with a content-free [ArgumentError] before any analyzer call.
  /// Returned failures never carry suggestions; partial suggestions are
  /// represented only by `failure.suggestionCount`.
  static List<FieldSuggestionSet> analyze({
    required Iterable<PageAnalysisJob> jobs,
    required FieldSuggestionSet Function(PageAnalysisJob job) analyze,
    PageCancellation? isCancelled,
  }) {
    final List<PageAnalysisJob> ordered = List<PageAnalysisJob>.of(jobs);
    final Set<int> seenPageIndexes = <int>{};
    for (final PageAnalysisJob job in ordered) {
      if (job.pageIndex < 0) {
        throw ArgumentError('pageIndex must be non-negative.');
      }
      if (!seenPageIndexes.add(job.pageIndex)) {
        throw ArgumentError('Duplicate pageIndex in page analysis batch.');
      }
      _validateJob(job);
    }
    ordered.sort(
      (PageAnalysisJob a, PageAnalysisJob b) =>
          a.pageIndex.compareTo(b.pageIndex),
    );
    final List<FieldSuggestionSet> results = <FieldSuggestionSet>[];
    for (final PageAnalysisJob job in ordered) {
      if (isCancelled != null && isCancelled(job.pageIndex)) {
        continue;
      }
      results.add(_analyzeOne(job, analyze));
    }
    return List<FieldSuggestionSet>.unmodifiable(results);
  }

  static FieldSuggestionSet _analyzeOne(
    PageAnalysisJob job,
    FieldSuggestionSet Function(PageAnalysisJob job) analyze,
  ) {
    try {
      final FieldSuggestionSet result = analyze(job);
      if (!_matchesJob(result, job)) {
        return _failedEnvelope(
          job,
          PageAnalysisFailure.forCategory(PageAnalysisFailure.internal),
        );
      }
      return result;
    } on PageAnalysisFailure catch (failure) {
      return _failedEnvelope(job, failure);
    } catch (_) {
      return _failedEnvelope(
        job,
        PageAnalysisFailure.forCategory(PageAnalysisFailure.internal),
      );
    }
  }

  static bool _matchesJob(FieldSuggestionSet result, PageAnalysisJob job) {
    const double epsilon = 1e-6;
    return result.pageIndex == job.pageIndex &&
        result.analysisRunId == job.analysisRunId &&
        result.rotation == job.rotation &&
        result.evidenceClass == job.evidenceClass &&
        (result.pageSizePt.width - job.pageSizePt.width).abs() <= epsilon &&
        (result.pageSizePt.height - job.pageSizePt.height).abs() <= epsilon;
  }

  static void _validateJob(PageAnalysisJob job) {
    final Map<String, Object?> probe = <String, Object?>{
      'schemaVersion': SuggestionSchema.version,
      'analysisRunId': job.analysisRunId,
      'pageIndex': job.pageIndex,
      'pageSizePt': <String, Object?>{
        'width': job.pageSizePt.width,
        'height': job.pageSizePt.height,
      },
      'rotation': job.rotation,
      'status': FieldSuggestionSet.statusComplete,
      'pageUncertain': false,
      'uncertaintyReason': null,
      'failure': null,
      'suggestions': <Object?>[],
      'timings': PageAnalysisTimings.zero.toJson(),
      'evidenceClass': job.evidenceClass,
    };
    final List<SuggestionSchemaViolation> findings = _envelopeFindings(
      probe,
      job.pageSizePt,
    );
    if (findings.isNotEmpty) {
      throw ArgumentError(
        'Invalid page analysis job: ${_describeFindings(findings)}',
      );
    }
  }

  static FieldSuggestionSet _failedEnvelope(
    PageAnalysisJob job,
    PageAnalysisFailure failure,
  ) {
    return FieldSuggestionSet(
      pageIndex: job.pageIndex,
      analysisRunId: job.analysisRunId,
      pageSizePt: job.pageSizePt,
      rotation: job.rotation,
      status: FieldSuggestionSet.statusFailed,
      failure: failure,
      timings: PageAnalysisTimings.zero,
      evidenceClass: job.evidenceClass,
    );
  }
}

/// The per-page recognition envelope of `recognition-output.md` section 1.
///
/// One instance represents one page of one analysis run. The envelope stores
/// immutable, already-validated section 2 suggestion wire maps; it does not
/// redeclare the core-owned `FieldSuggestion`, `AnalysisState`, or
/// `PageFailure`. Suggestions are sorted with
/// [SuggestionSchema.sortedSuggestions] and deep-frozen on input; [toJson]
/// returns a fresh mutable copy, so no caller can mutate the stored state.
///
/// Validation delegates to [SuggestionSchema.validateEnvelope]. The model adds
/// only the `uncertaintyReason` retention rule (required when uncertain,
/// accepted when certain) and the one documented `PAGE-001` allowance
/// described in the library comment.
final class FieldSuggestionSet {
  const FieldSuggestionSet._({
    required this.pageIndex,
    required this.analysisRunId,
    required this.pageSizePt,
    required this.rotation,
    required this.status,
    required this.pageUncertain,
    required this.uncertaintyReason,
    required this.failure,
    required this.suggestions,
    required this.timings,
    required this.evidenceClass,
  });

  /// Complete-envelope status token.
  static const String statusComplete = 'complete';

  /// Failed-envelope status token.
  static const String statusFailed = 'failed';

  /// Creates a validated envelope.
  ///
  /// [suggestions] may be empty and in any input order; it is sorted
  /// deterministically before validation. The envelope is rejected with a
  /// content-free [ArgumentError] when any section 1/2/4 rule fails.
  ///
  /// [uncertaintyReason] is required when [pageUncertain] is true. A valid
  /// reason supplied while [pageUncertain] is false is accepted and retained,
  /// matching the shared validator's documented non-rule.
  ///
  /// A failed envelope must carry a [failure] and no suggestions; a complete
  /// envelope must carry no [failure]. [failure] is required exactly when
  /// [status] is [statusFailed].
  factory FieldSuggestionSet({
    required int pageIndex,
    required String analysisRunId,
    required PageDisplaySize pageSizePt,
    int rotation = 0,
    required String status,
    bool pageUncertain = false,
    String? uncertaintyReason,
    PageAnalysisFailure? failure,
    List<Map<String, Object?>> suggestions = const <Map<String, Object?>>[],
    PageAnalysisTimings timings = PageAnalysisTimings.zero,
    required String evidenceClass,
  }) {
    if (pageIndex < 0) {
      throw ArgumentError('pageIndex must be non-negative.');
    }
    final List<Map<String, Object?>> sorted =
        SuggestionSchema.sortedSuggestions(suggestions);
    final Map<String, Object?> wire = <String, Object?>{
      'schemaVersion': SuggestionSchema.version,
      'analysisRunId': analysisRunId,
      'pageIndex': pageIndex,
      'pageSizePt': <String, Object?>{
        'width': pageSizePt.width,
        'height': pageSizePt.height,
      },
      'rotation': rotation,
      'status': status,
      'pageUncertain': pageUncertain,
      'uncertaintyReason': uncertaintyReason,
      'failure': failure?.toJson(),
      'suggestions': sorted,
      'timings': timings.toJson(),
      'evidenceClass': evidenceClass,
    };
    final List<SuggestionSchemaViolation> findings = _envelopeFindings(
      wire,
      pageSizePt,
    );
    if (findings.isNotEmpty) {
      throw ArgumentError(
        'Invalid page analysis envelope: ${_describeFindings(findings)}',
      );
    }
    return FieldSuggestionSet._(
      pageIndex: pageIndex,
      analysisRunId: analysisRunId,
      pageSizePt: pageSizePt,
      rotation: rotation,
      status: status,
      pageUncertain: pageUncertain,
      uncertaintyReason: uncertaintyReason,
      failure: failure,
      suggestions: List<Map<String, Object?>>.unmodifiable(
        sorted.map(_freezeMap),
      ),
      timings: timings,
      evidenceClass: evidenceClass,
    );
  }

  /// Parses a section 1 envelope.
  ///
  /// Input suggestion order is normalized to the deterministic section 5
  /// order before validation. Throws [FormatException] for any missing, extra,
  /// or invalid field. Error messages contain only structural paths and stable
  /// codes - never a label, OCR text, file name, path, URI, or other document
  /// content.
  factory FieldSuggestionSet.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> normalized = Map<String, Object?>.of(json);
    final Object? rawSuggestions = normalized['suggestions'];
    if (rawSuggestions is List<Object?>) {
      final List<Map<String, Object?>> maps = <Map<String, Object?>>[];
      bool allMaps = true;
      for (final Object? item in rawSuggestions) {
        if (item is Map<String, Object?>) {
          maps.add(item);
        } else {
          allMaps = false;
          break;
        }
      }
      if (allMaps) {
        normalized['suggestions'] = SuggestionSchema.sortedSuggestions(maps);
      }
    }
    final PageDisplaySize displaySize = _displaySizeOrFallback(
      normalized['pageSizePt'],
    );
    final List<SuggestionSchemaViolation> findings = _envelopeFindings(
      normalized,
      displaySize,
    );
    if (findings.isNotEmpty) {
      throw FormatException(
        'Invalid page analysis envelope: ${_describeFindings(findings)}',
      );
    }
    final int pageIndex = normalized['pageIndex'] as int;
    final Map<String, Object?> rawSize =
        normalized['pageSizePt'] as Map<String, Object?>;
    final PageDisplaySize pageSizePt = PageDisplaySize(
      (rawSize['width'] as num).toDouble(),
      (rawSize['height'] as num).toDouble(),
    );
    final bool pageUncertain = normalized['pageUncertain'] as bool;
    final String? uncertaintyReason =
        normalized['uncertaintyReason'] as String?;
    final Object? rawFailure = normalized['failure'];
    final PageAnalysisFailure? failure = rawFailure == null
        ? null
        : PageAnalysisFailure.fromJson(rawFailure as Map<String, Object?>);
    final List<Object?> suggestionItems =
        normalized['suggestions'] as List<Object?>;
    final List<Map<String, Object?>> suggestionMaps = <Map<String, Object?>>[
      for (final Object? item in suggestionItems) item as Map<String, Object?>,
    ];
    return FieldSuggestionSet._(
      pageIndex: pageIndex,
      analysisRunId: normalized['analysisRunId'] as String,
      pageSizePt: pageSizePt,
      rotation: normalized['rotation'] as int,
      status: normalized['status'] as String,
      pageUncertain: pageUncertain,
      uncertaintyReason: uncertaintyReason,
      failure: failure,
      suggestions: List<Map<String, Object?>>.unmodifiable(
        suggestionMaps.map(_freezeMap),
      ),
      timings: PageAnalysisTimings.fromJson(
        normalized['timings'] as Map<String, Object?>,
      ),
      evidenceClass: normalized['evidenceClass'] as String,
    );
  }

  /// Zero-based page index.
  final int pageIndex;

  /// Analysis run UUID shared by every envelope of one invocation.
  final String analysisRunId;

  /// Display size in points.
  final PageDisplaySize pageSizePt;

  /// Page rotation in degrees (`0 | 90 | 180 | 270`).
  final int rotation;

  /// `complete | failed`.
  final String status;

  /// Whether page-level uncertainty prevents reliable placement.
  final bool pageUncertain;

  /// `skew | orientation | low_contrast | structure`; required when
  /// [pageUncertain] is true and accepted (retained) when it is false.
  final String? uncertaintyReason;

  /// The terminal failure; required exactly when [status] is `failed`.
  final PageAnalysisFailure? failure;

  /// Immutable, sorted, validated section 2 suggestion wire maps.
  final List<Map<String, Object?>> suggestions;

  /// Diagnostic integer stage timings.
  final PageAnalysisTimings timings;

  /// `simulated | emulator | device`.
  final String evidenceClass;

  /// The only accepted schema version.
  int get schemaVersion => SuggestionSchema.version;

  /// Whether the envelope is complete.
  bool get isComplete => status == statusComplete;

  /// Whether the envelope is failed.
  bool get isFailed => status == statusFailed;

  /// Returns a fresh mutable section 1 envelope.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'analysisRunId': analysisRunId,
      'pageIndex': pageIndex,
      'pageSizePt': <String, Object?>{
        'width': pageSizePt.width,
        'height': pageSizePt.height,
      },
      'rotation': rotation,
      'status': status,
      'pageUncertain': pageUncertain,
      'uncertaintyReason': uncertaintyReason,
      'failure': failure?.toJson(),
      'suggestions': suggestions.map(_copyMap).toList(growable: false),
      'timings': timings.toJson(),
      'evidenceClass': evidenceClass,
    };
  }

  /// The section 5.5 canonical projection: a deep copy without
  /// `analysisRunId`, `timings`, and `evidenceClass`.
  Map<String, Object?> canonicalProjection() {
    return SuggestionSchema.canonicalProjection(toJson());
  }

  /// Canonical JSON of [canonicalProjection] (`recognition-output.md`
  /// section 5 item 5).
  String canonicalJson() {
    return SuggestionSchema.canonicalJson(canonicalProjection());
  }

  @override
  String toString() {
    return 'FieldSuggestionSet(pageIndex: $pageIndex, status: $status, '
        'pageUncertain: $pageUncertain, suggestions: ${suggestions.length})';
  }
}

PageDisplaySize _displaySizeOrFallback(Object? raw) {
  if (raw is Map<String, Object?>) {
    final Object? width = raw['width'];
    final Object? height = raw['height'];
    if (width is num &&
        height is num &&
        width.isFinite &&
        height.isFinite &&
        width > 0 &&
        height > 0) {
      return PageDisplaySize(width.toDouble(), height.toDouble());
    }
  }
  return PageDisplaySize(1, 1);
}

List<SuggestionSchemaViolation> _envelopeFindings(
  Map<String, Object?> wire,
  PageDisplaySize displaySize,
) {
  final Object? rawPageIndex = wire['pageIndex'];
  final int pageIndex = rawPageIndex is int ? rawPageIndex : 0;
  const int maxInt = 0x7FFFFFFFFFFFFFFF;
  final int pageCount = pageIndex < 0 || pageIndex == maxInt
      ? 1
      : pageIndex + 1;
  return SuggestionSchema.validateEnvelope(
        wire,
        displaySize: displaySize,
        pageCount: pageCount,
      )
      .where((SuggestionSchemaViolation finding) {
        return !_isDocumentedPageRenderingKey(wire, finding);
      })
      .toList(growable: false);
}

bool _isDocumentedPageRenderingKey(
  Map<String, Object?> wire,
  SuggestionSchemaViolation finding,
) {
  if (finding.path != 'envelope.failure.messageKey' ||
      finding.code != SuggestionSchemaCodes.format) {
    return false;
  }
  final Object? failure = wire['failure'];
  return failure is Map<String, Object?> &&
      failure['category'] == PageAnalysisFailure.rasterization &&
      failure['messageKey'] == 'PAGE-001';
}

String _describeFindings(List<SuggestionSchemaViolation> findings) {
  return findings
      .map((SuggestionSchemaViolation finding) => finding.toString())
      .join(', ');
}

Map<String, Object?> _freezeMap(Map<String, Object?> map) {
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    for (final MapEntry<String, Object?> entry in map.entries)
      entry.key: _freezeValue(entry.value),
  });
}

Object? _freezeValue(Object? value) {
  if (value is Map<String, Object?>) {
    return _freezeMap(value);
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map(_freezeValue));
  }
  return value;
}

Map<String, Object?> _copyMap(Map<String, Object?> map) {
  return <String, Object?>{
    for (final MapEntry<String, Object?> entry in map.entries)
      entry.key: _copyValue(entry.value),
  };
}

Object? _copyValue(Object? value) {
  if (value is Map<String, Object?>) {
    return _copyMap(value);
  }
  if (value is List<Object?>) {
    return value.map(_copyValue).toList(growable: false);
  }
  return value;
}
