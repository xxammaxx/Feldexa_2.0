// Structure comparison of geometric candidates, typed suggestions, and
// declared ground truth (T264).
//
// Normative sources:
//  * `specs/001-scanned-form-workflow/spec.md` FR-011, FR-013, FR-014, SC-002;
//  * `specs/001-scanned-form-workflow/contracts/recognition-output.md`
//    sections 2 and 6 (IoU >= 0.5);
//  * `specs/001-scanned-form-workflow/research.md` D-18 (recognition
//    evaluation separates position, type, and label).
//
// Scope. This library compares three things that already exist: the T264
// geometry inventory (or the T052 candidate rects it is built from), the typed
// suggestions of the existing pipeline, and a *pre-declared* ground truth. It
// neither detects nor types nor persists. It is the missing structural check
// that is independent of an OCR label count.
//
// Central rule. One matched count is not evidence. A run with the same number
// of fields as the ground truth but with wrong positions is a FAIL. An unknown
// expected count is never completeness proof. The comparison therefore never
// adjusts, adds, or drops a field to reach a total: it matches geometrically,
// then reports missing, extra, duplicate, overlapping, ambiguous, unlabelled,
// type-mismatched, and geometry-mismatched observations separately, per page
// and per kind.
//
// Matching. Two fields on the same page are *candidate matches* when their
// `IoU >= iouThreshold` (0.5, the contract conflict threshold) or when their
// centre distance is at most `maxCenterDistancePt` (12 pt, for very small
// regions whose IoU is unstable). A deterministic maximum-cardinality bipartite
// matching (Kuhn's augmenting paths) decides the pairing; adjacency lists are
// ordered by decreasing IoU, then increasing centre distance, then observed
// index, so the result depends only on the input.
//
// A pair that is only centre-distance-eligible is matched but counted as a
// geometry mismatch, so it is neither double-reported as missing + extra nor
// silently accepted.
//
// Duplicates and overlaps. Observations on one page with `IoU >= 0.5` are
// grouped transitively. Each group's lowest-index observation is the
// representative; every further member is reported as a duplicate of it. Every
// `IoU >= 0.5` pair is additionally reported as an overlap for review. This is
// how a missing, duplicated, or overlapping checkbox becomes visible instead of
// changing a total.
//
// Ambiguity. An observation whose two best ground-truth candidates are both
// IoU-eligible and differ by less than `ambiguityScoreGap` (0.1) is ambiguous.
// It is reported as such whether or not it was matched, because the choice
// between them is not established by geometry.
//
// Types. Kind equality is strict: an observation typed `unknown` is not a
// correct type, because SC-001 asks for the identical type on a strict match.
// It is therefore counted as a type mismatch, never silently accepted.
//
// Labels. `labelText` is compared trimmed and case-insensitively, without
// umlaut folding, so `Ä` never equals `A` (see T263). A missing label on a
// matched observation whose expected field declares a label is
// `unlabelled`, not a type error. Label comparison never rewrites text.
library;

import 'dart:math' as math;

import 'field_inventory.dart';
import 'geometry_detector.dart';
import 'geometry_metrics.dart';

/// One field that the declared ground truth expects.
final class ExpectedField {
  /// Creates an expected field.
  ///
  /// [pageIndex] must be non-negative and the rectangle must be inside the
  /// declared page when a page size is supplied by the caller. This type does
  /// not validate against a page itself; `StructureComparison` only compares.
  ExpectedField({
    required this.pageIndex,
    required this.rect,
    required this.kind,
    this.labelText,
    this.sourceId,
  }) {
    if (pageIndex < 0) {
      throw ArgumentError('page index must be non-negative');
    }
    if (!rect.x.isFinite || !rect.y.isFinite) {
      throw ArgumentError('field origin must be finite');
    }
  }

  /// Zero-based page index.
  final int pageIndex;

  /// Expected display-space rectangle.
  final DisplayRect rect;

  /// Expected kind.
  final FieldInventoryKind kind;

  /// Declared label context, or `null` when the field is unlabelled.
  final String? labelText;

  /// Optional stable source identifier from the ground-truth record.
  final String? sourceId;

  @override
  String toString() => 'ExpectedField($pageIndex, ${kind.wireName}, $rect)';
}

/// One observed field: a typed suggestion or an inventory candidate.
final class ObservedField {
  /// Creates an observed field.
  ObservedField({
    required this.pageIndex,
    required this.rect,
    required this.kind,
    this.labelText,
    this.provenance = 'unknown',
  }) {
    if (pageIndex < 0) {
      throw ArgumentError('page index must be non-negative');
    }
  }

  /// Zero-based page index.
  final int pageIndex;

  /// Observed display-space rectangle.
  final DisplayRect rect;

  /// Observed kind; [FieldInventoryKind.unknown] is a strict type mismatch.
  final FieldInventoryKind kind;

  /// Observed label context, or `null`.
  final String? labelText;

  /// Where the observation came from, for example `inventory`,
  /// `suggestion`, or `variant:contrast`.
  final String provenance;

  @override
  String toString() =>
      'ObservedField($pageIndex, ${kind.wireName}, $rect, $provenance)';
}

/// Tuning for [StructureComparison].
final class StructureComparisonConfig {
  /// Creates a configuration.
  const StructureComparisonConfig({
    this.iouThreshold = 0.5,
    this.maxCenterDistancePt = 12,
    this.ambiguityScoreGap = 0.1,
    this.requireLabels = false,
  }) : assert(iouThreshold > 0 && iouThreshold <= 1),
       assert(maxCenterDistancePt >= 0),
       assert(ambiguityScoreGap >= 0);

  /// Minimum IoU for a geometric match.
  final double iouThreshold;

  /// Largest centre distance that can still match a very small region.
  final double maxCenterDistancePt;

  /// Score difference below which two candidate matches are ambiguous.
  final double ambiguityScoreGap;

  /// Whether a missing label is a verdict failure.
  final bool requireLabels;

  /// The production configuration.
  static const StructureComparisonConfig production =
      StructureComparisonConfig();
}

/// One established match between an expected and an observed field.
final class StructureMatch {
  const StructureMatch._({
    required this.expectedIndex,
    required this.observedIndex,
    required this.pageIndex,
    required this.iou,
    required this.centerDistancePt,
    required this.geometryOk,
    required this.kindOk,
    required this.labelOk,
  });

  /// Index into the expected list.
  final int expectedIndex;

  /// Index into the observed list.
  final int observedIndex;

  /// Page of both fields.
  final int pageIndex;

  /// Measured IoU.
  final double iou;

  /// Measured centre distance in display points.
  final double centerDistancePt;

  /// Whether `IoU >= iouThreshold`; otherwise the match is distance-only.
  final bool geometryOk;

  /// Whether the kinds agree.
  final bool kindOk;

  /// Whether the labels agree (both absent also agrees).
  final bool labelOk;

  @override
  String toString() =>
      'StructureMatch(e$expectedIndex, o$observedIndex, iou: $iou)';
}

/// One duplicated observation.
final class StructureDuplicate {
  const StructureDuplicate._({
    required this.observedIndex,
    required this.ofObservedIndex,
    required this.iou,
  });

  /// The redundant observation.
  final int observedIndex;

  /// The representative observation it duplicates.
  final int ofObservedIndex;

  /// IoU with the representative.
  final double iou;

  @override
  String toString() =>
      'StructureDuplicate(o$observedIndex of o$ofObservedIndex)';
}

/// One overlapping observation pair.
final class StructureOverlap {
  const StructureOverlap._({
    required this.firstObservedIndex,
    required this.secondObservedIndex,
    required this.iou,
  });

  /// Lower observation index.
  final int firstObservedIndex;

  /// Higher observation index.
  final int secondObservedIndex;

  /// Measured IoU.
  final double iou;

  @override
  String toString() =>
      'StructureOverlap(o$firstObservedIndex, '
      'o$secondObservedIndex, iou: $iou)';
}

/// Counts of one page/kind bucket.
final class StructureBucket {
  const StructureBucket._({
    required this.pageIndex,
    required this.kind,
    required this.expected,
    required this.observed,
    required this.matched,
    required this.missing,
    required this.extra,
    required this.duplicate,
    required this.typeMismatch,
  });

  /// Page of the bucket.
  final int pageIndex;

  /// Kind of the bucket.
  final FieldInventoryKind kind;

  /// Ground-truth fields of this page/kind.
  final int expected;

  /// Observed fields of this page/kind.
  final int observed;

  /// Matched fields of this page/kind.
  final int matched;

  /// Missing ground-truth fields of this page/kind.
  final int missing;

  /// Extra observations of this page/kind.
  final int extra;

  /// Duplicate observations of this page/kind.
  final int duplicate;

  /// Type mismatches counted against this page/expected kind.
  final int typeMismatch;

  /// A report-ready map.
  Map<String, Object?> toJson() => <String, Object?>{
    'pageIndex': pageIndex,
    'kind': kind.wireName,
    'expected': expected,
    'observed': observed,
    'matched': matched,
    'missing': missing,
    'extra': extra,
    'duplicate': duplicate,
    'typeMismatch': typeMismatch,
  };

  @override
  String toString() => 'StructureBucket($pageIndex, ${kind.wireName})';
}

/// The overall verdict of one comparison.
enum StructureVerdict {
  /// Every expected field was matched with correct geometry, kind, and (when
  /// required) label, and there were no extras, duplicates, or ambiguity.
  pass,

  /// At least one declared requirement failed.
  fail,

  /// The ground truth cannot prove completeness for at least one page (or is
  /// empty), so no pass can be claimed.
  unverified,
}

/// The full result of one structure comparison.
final class StructureComparisonResult {
  StructureComparisonResult._({
    required List<StructureMatch> matches,
    required List<int> missingExpected,
    required List<int> extraObserved,
    required List<StructureDuplicate> duplicates,
    required List<StructureOverlap> overlaps,
    required List<int> ambiguousObserved,
    required List<int> unlabelledObserved,
    required List<int> labelMismatchedMatches,
    required List<StructureBucket> buckets,
    required this.expectedCount,
    required this.observedCount,
    required this.unknownGroundTruthPages,
    required this.unscoredObservedCount,
    required this.verdict,
    required List<String> failureCodes,
  }) : matches = List<StructureMatch>.unmodifiable(matches),
       missingExpected = List<int>.unmodifiable(missingExpected),
       extraObserved = List<int>.unmodifiable(extraObserved),
       duplicates = List<StructureDuplicate>.unmodifiable(duplicates),
       overlaps = List<StructureOverlap>.unmodifiable(overlaps),
       ambiguousObserved = List<int>.unmodifiable(ambiguousObserved),
       unlabelledObserved = List<int>.unmodifiable(unlabelledObserved),
       labelMismatchedMatches = List<int>.unmodifiable(labelMismatchedMatches),
       buckets = List<StructureBucket>.unmodifiable(buckets),
       failureCodes = List<String>.unmodifiable(failureCodes);

  /// Established matches.
  final List<StructureMatch> matches;

  /// Expected indices with no match.
  final List<int> missingExpected;

  /// Observed indices with no match and no duplicate relation.
  final List<int> extraObserved;

  /// Duplicated observations.
  final List<StructureDuplicate> duplicates;

  /// Overlapping observation pairs (`IoU >= 0.5`).
  final List<StructureOverlap> overlaps;

  /// Observations with an ambiguous best match.
  final List<int> ambiguousObserved;

  /// Matched observations whose expected field declares a label that is absent.
  final List<int> unlabelledObserved;

  /// Matched pairs whose two labels are both present and different.
  final List<int> labelMismatchedMatches;

  /// Per page/kind buckets in deterministic order.
  final List<StructureBucket> buckets;

  /// Number of ground-truth fields.
  final int expectedCount;

  /// Number of observations.
  final int observedCount;

  /// Pages with observations but no ground truth.
  final List<int> unknownGroundTruthPages;

  /// Observations on pages without ground truth; deliberately not scored.
  final int unscoredObservedCount;

  /// Overall verdict.
  final StructureVerdict verdict;

  /// Stable failure tokens; empty only for a pass.
  final List<String> failureCodes;

  /// Matched pairs whose IoU is below the threshold.
  List<StructureMatch> get geometryMismatchedMatches =>
      List<StructureMatch>.unmodifiable(
        matches.where((StructureMatch match) => !match.geometryOk),
      );

  /// Matched pairs whose kinds disagree.
  List<StructureMatch> get typeMismatchedMatches =>
      List<StructureMatch>.unmodifiable(
        matches.where((StructureMatch match) => !match.kindOk),
      );

  /// Whether the totals agree while the geometry does not.
  ///
  /// This is exactly the constellation that must never count as a pass.
  bool get sameCountWrongGeometry =>
      expectedCount > 0 &&
      expectedCount == observedCount &&
      geometryMismatchedMatches.isNotEmpty;

  /// Mean IoU over the geometry-ok matches; `0.0` when there are none.
  double get meanMatchedIou {
    final List<StructureMatch> geometric = matches
        .where((StructureMatch match) => match.geometryOk)
        .toList();
    if (geometric.isEmpty) {
      return 0.0;
    }
    double total = 0;
    for (final StructureMatch match in geometric) {
      total += match.iou;
    }
    return total / geometric.length;
  }

  /// The smallest IoU over the geometry-ok matches; `0.0` when there are none.
  double get minMatchedIou {
    final List<StructureMatch> geometric = matches
        .where((StructureMatch match) => match.geometryOk)
        .toList();
    if (geometric.isEmpty) {
      return 0.0;
    }
    double smallest = 1.0;
    for (final StructureMatch match in geometric) {
      smallest = math.min(smallest, match.iou);
    }
    return smallest;
  }

  /// A report-ready summary. No label text is included.
  Map<String, Object?> toJson() => <String, Object?>{
    'verdict': verdict.name,
    'failureCodes': failureCodes,
    'expectedCount': expectedCount,
    'observedCount': observedCount,
    'matchedCount': matches.length,
    'missingCount': missingExpected.length,
    'extraCount': extraObserved.length,
    'duplicateCount': duplicates.length,
    'overlapCount': overlaps.length,
    'ambiguousCount': ambiguousObserved.length,
    'unlabelledCount': unlabelledObserved.length,
    'labelMismatchCount': labelMismatchedMatches.length,
    'geometryMismatchCount': geometryMismatchedMatches.length,
    'typeMismatchCount': typeMismatchedMatches.length,
    'sameCountWrongGeometry': sameCountWrongGeometry,
    'unknownGroundTruthPages': unknownGroundTruthPages,
    'unscoredObservedCount': unscoredObservedCount,
    'meanMatchedIou': meanMatchedIou,
    'minMatchedIou': minMatchedIou,
    'buckets': <Map<String, Object?>>[
      for (final StructureBucket bucket in buckets) bucket.toJson(),
    ],
    'geometryMismatches': <Map<String, Object?>>[
      for (final StructureMatch match in geometryMismatchedMatches)
        <String, Object?>{
          'expectedIndex': match.expectedIndex,
          'observedIndex': match.observedIndex,
          'iou': match.iou,
          'centerDistancePt': match.centerDistancePt,
        },
    ],
    'typeMismatches': <Map<String, Object?>>[
      for (final StructureMatch match in typeMismatchedMatches)
        <String, Object?>{
          'expectedIndex': match.expectedIndex,
          'observedIndex': match.observedIndex,
        },
    ],
  };
}

/// Compares declared ground truth with observations, independently of counts.
final class StructureComparison {
  const StructureComparison._();

  /// Compares [observed] with [expected].
  ///
  /// Both lists may be in any order; the result is order-independent apart from
  /// the ordinal indices, which refer to the supplied list positions.
  ///
  /// [groundTruthPages] names the pages for which a ground truth was actually
  /// declared. It matters for a page whose declared field count is zero: such a
  /// page is a *known* zero only when it is named here, otherwise the expected
  /// count is unknown and the comparison can never pass. When omitted, only the
  /// pages that carry at least one expected field count as known.
  static StructureComparisonResult compare({
    required List<ExpectedField> expected,
    required List<ObservedField> observed,
    Set<int>? groundTruthPages,
    StructureComparisonConfig config = StructureComparisonConfig.production,
  }) {
    final Set<int> knownPages = groundTruthPages == null
        ? <int>{for (final ExpectedField field in expected) field.pageIndex}
        : Set<int>.of(groundTruthPages);
    final List<int> unknownPages = <int>{
      for (final ObservedField field in observed)
        if (!knownPages.contains(field.pageIndex)) field.pageIndex,
    }.toList()..sort();

    final List<_Pair> pairs = <_Pair>[];
    final List<StructureDuplicate> duplicates = <StructureDuplicate>[];
    final List<StructureOverlap> overlaps = <StructureOverlap>[];
    final List<int> ambiguousObserved = <int>[];

    // Pages without declared ground truth are never scored: an unknown expected
    // count cannot prove completeness, and it must not turn a real observation
    // into a claimed false positive either.
    final List<int> pages = List<int>.of(knownPages)..sort();
    for (final int page in pages) {
      final List<int> expectedOnPage = <int>[
        for (int index = 0; index < expected.length; index++)
          if (expected[index].pageIndex == page) index,
      ];
      final List<int> observedOnPage = <int>[
        for (int index = 0; index < observed.length; index++)
          if (observed[index].pageIndex == page) index,
      ];
      if (observedOnPage.isEmpty) {
        continue;
      }
      _collectObservationRelations(
        observed,
        observedOnPage,
        config,
        duplicates,
        overlaps,
      );
      _collectAmbiguity(
        expected,
        observed,
        expectedOnPage,
        observedOnPage,
        config,
        ambiguousObserved,
      );
      _matchPage(
        expected,
        observed,
        expectedOnPage,
        observedOnPage,
        config,
        pairs,
      );
    }

    pairs.sort(
      (_Pair a, _Pair b) => a.expectedIndex.compareTo(b.expectedIndex),
    );
    final Set<int> matchedExpected = <int>{
      for (final _Pair pair in pairs) pair.expectedIndex,
    };
    final Set<int> matchedObserved = <int>{
      for (final _Pair pair in pairs) pair.observedIndex,
    };
    final Set<int> duplicateObserved = <int>{
      for (final StructureDuplicate duplicate in duplicates)
        duplicate.observedIndex,
    };

    final List<int> missingExpected = <int>[
      for (int index = 0; index < expected.length; index++)
        if (!matchedExpected.contains(index)) index,
    ];
    final List<int> extraObserved = <int>[
      for (int index = 0; index < observed.length; index++)
        if (knownPages.contains(observed[index].pageIndex) &&
            !matchedObserved.contains(index) &&
            !duplicateObserved.contains(index))
          index,
    ];
    final int unscoredObservedCount =
        observed.length -
        matchedObserved.length -
        extraObserved.length -
        duplicateObserved.length;
    assert(unscoredObservedCount >= 0);
    final List<int> unlabelledObserved = <int>[
      for (final _Pair pair in pairs)
        if (pair.label == _LabelStatus.missing) pair.observedIndex,
    ];
    final List<int> labelMismatched = <int>[
      for (final _Pair pair in pairs)
        if (pair.label == _LabelStatus.mismatch) pair.observedIndex,
    ];
    ambiguousObserved.sort();

    final List<String> failureCodes = <String>[];
    if (missingExpected.isNotEmpty) {
      failureCodes.add('missing_fields');
    }
    if (extraObserved.isNotEmpty) {
      failureCodes.add('extra_fields');
    }
    if (duplicates.isNotEmpty) {
      failureCodes.add('duplicate_fields');
    }
    if (pairs.any((_Pair pair) => !pair.geometryOk)) {
      failureCodes.add('geometry_mismatch');
    }
    if (pairs.any((_Pair pair) => !pair.kindOk)) {
      failureCodes.add('type_mismatch');
    }
    if (unlabelledObserved.isNotEmpty && config.requireLabels) {
      failureCodes.add('unlabelled_fields');
    }
    if (labelMismatched.isNotEmpty && config.requireLabels) {
      failureCodes.add('label_mismatch');
    }
    if (ambiguousObserved.isNotEmpty) {
      failureCodes.add('ambiguous_fields');
    }
    if (unknownPages.isNotEmpty) {
      failureCodes.add('unknown_expected_count');
    }
    failureCodes.sort();

    final bool failed =
        missingExpected.isNotEmpty ||
        extraObserved.isNotEmpty ||
        duplicates.isNotEmpty ||
        pairs.any((_Pair pair) => !pair.geometryOk) ||
        pairs.any((_Pair pair) => !pair.kindOk) ||
        (config.requireLabels &&
            (unlabelledObserved.isNotEmpty || labelMismatched.isNotEmpty));
    final StructureVerdict verdict;
    if (failed) {
      verdict = StructureVerdict.fail;
    } else if (knownPages.isEmpty || unknownPages.isNotEmpty) {
      verdict = StructureVerdict.unverified;
    } else {
      verdict = StructureVerdict.pass;
    }

    return StructureComparisonResult._(
      matches: <StructureMatch>[for (final _Pair pair in pairs) pair.match],
      missingExpected: missingExpected,
      extraObserved: extraObserved,
      duplicates: duplicates,
      overlaps: overlaps,
      ambiguousObserved: ambiguousObserved,
      unlabelledObserved: unlabelledObserved,
      labelMismatchedMatches: labelMismatched,
      buckets: _buckets(
        expected,
        observed,
        pairs,
        missingExpected,
        extraObserved,
        duplicates,
      ),
      expectedCount: expected.length,
      observedCount: observed.length,
      unknownGroundTruthPages: unknownPages,
      unscoredObservedCount: unscoredObservedCount,
      verdict: verdict,
      failureCodes: failureCodes,
    );
  }

  static void _collectObservationRelations(
    List<ObservedField> observed,
    List<int> observedOnPage,
    StructureComparisonConfig config,
    List<StructureDuplicate> duplicates,
    List<StructureOverlap> overlaps,
  ) {
    final List<int> sorted = List<int>.of(observedOnPage)..sort();
    final List<int> parent = List<int>.generate(sorted.length, (int i) => i);
    int find(int value) {
      int root = value;
      while (parent[root] != root) {
        root = parent[root];
      }
      while (parent[value] != value) {
        final int next = parent[value];
        parent[value] = root;
        value = next;
      }
      return root;
    }

    for (int first = 0; first < sorted.length; first++) {
      for (int second = first + 1; second < sorted.length; second++) {
        final double overlap = iou(
          observed[sorted[first]].rect,
          observed[sorted[second]].rect,
        );
        if (overlap >= config.iouThreshold) {
          overlaps.add(
            StructureOverlap._(
              firstObservedIndex: sorted[first],
              secondObservedIndex: sorted[second],
              iou: overlap,
            ),
          );
          final int a = find(first);
          final int b = find(second);
          if (a != b) {
            if (a < b) {
              parent[b] = a;
            } else {
              parent[a] = b;
            }
          }
        }
      }
    }
    final Map<int, List<int>> groups = <int, List<int>>{};
    for (int index = 0; index < sorted.length; index++) {
      groups.putIfAbsent(find(index), () => <int>[]).add(sorted[index]);
    }
    for (final List<int> group in groups.values) {
      if (group.length < 2) {
        continue;
      }
      final List<int> ordered = List<int>.of(group)..sort();
      final int representative = ordered.first;
      for (int index = 1; index < ordered.length; index++) {
        duplicates.add(
          StructureDuplicate._(
            observedIndex: ordered[index],
            ofObservedIndex: representative,
            iou: iou(
              observed[ordered[index]].rect,
              observed[representative].rect,
            ),
          ),
        );
      }
    }
    overlaps.sort(
      (StructureOverlap a, StructureOverlap b) =>
          a.firstObservedIndex != b.firstObservedIndex
          ? a.firstObservedIndex.compareTo(b.firstObservedIndex)
          : a.secondObservedIndex.compareTo(b.secondObservedIndex),
    );
    duplicates.sort(
      (StructureDuplicate a, StructureDuplicate b) =>
          a.observedIndex.compareTo(b.observedIndex),
    );
  }

  static void _collectAmbiguity(
    List<ExpectedField> expected,
    List<ObservedField> observed,
    List<int> expectedOnPage,
    List<int> observedOnPage,
    StructureComparisonConfig config,
    List<int> ambiguousObserved,
  ) {
    for (final int observedIndex in observedOnPage) {
      final List<double> scores = <double>[];
      for (final int expectedIndex in expectedOnPage) {
        final double overlap = iou(
          expected[expectedIndex].rect,
          observed[observedIndex].rect,
        );
        if (overlap >= config.iouThreshold) {
          scores.add(overlap);
        }
      }
      if (scores.length < 2) {
        continue;
      }
      scores.sort((double a, double b) => b.compareTo(a));
      if (scores[0] - scores[1] < config.ambiguityScoreGap) {
        ambiguousObserved.add(observedIndex);
      }
    }
  }

  static void _matchPage(
    List<ExpectedField> expected,
    List<ObservedField> observed,
    List<int> expectedOnPage,
    List<int> observedOnPage,
    StructureComparisonConfig config,
    List<_Pair> out,
  ) {
    final List<_Candidate> candidates = <_Candidate>[];
    for (final int expectedIndex in expectedOnPage) {
      for (final int observedIndex in observedOnPage) {
        final double overlap = iou(
          expected[expectedIndex].rect,
          observed[observedIndex].rect,
        );
        final double distance = centerDistancePt(
          expected[expectedIndex].rect,
          observed[observedIndex].rect,
        );
        final bool iouEligible = overlap >= config.iouThreshold;
        final bool distanceEligible =
            !iouEligible && distance <= config.maxCenterDistancePt;
        if (!iouEligible && !distanceEligible) {
          continue;
        }
        candidates.add(
          _Candidate(
            expectedIndex: expectedIndex,
            observedIndex: observedIndex,
            iou: overlap,
            centerDistancePt: distance,
            geometryOk: iouEligible,
          ),
        );
      }
    }
    candidates.sort(_compareCandidates);
    final Map<int, List<_Candidate>> adjacency = <int, List<_Candidate>>{};
    for (final _Candidate candidate in candidates) {
      adjacency
          .putIfAbsent(candidate.expectedIndex, () => <_Candidate>[])
          .add(candidate);
    }
    final Map<int, _Candidate> assigned = <int, _Candidate>{};
    for (final int expectedIndex in expectedOnPage) {
      final Set<int> visited = <int>{};
      _augment(expectedIndex, adjacency, assigned, visited);
    }
    final List<_Candidate> chosen = assigned.values.toList()
      ..sort(
        (_Candidate a, _Candidate b) =>
            a.expectedIndex.compareTo(b.expectedIndex),
      );
    for (final _Candidate candidate in chosen) {
      final ExpectedField expectedField = expected[candidate.expectedIndex];
      final ObservedField observedField = observed[candidate.observedIndex];
      out.add(
        _Pair(
          expectedIndex: candidate.expectedIndex,
          observedIndex: candidate.observedIndex,
          pageIndex: expectedField.pageIndex,
          iou: candidate.iou,
          centerDistancePt: candidate.centerDistancePt,
          geometryOk: candidate.geometryOk,
          kindOk: expectedField.kind == observedField.kind,
          label: _labelStatus(expectedField, observedField),
        ),
      );
    }
  }

  static bool _augment(
    int expectedIndex,
    Map<int, List<_Candidate>> adjacency,
    Map<int, _Candidate> assigned,
    Set<int> visited,
  ) {
    for (final _Candidate candidate
        in adjacency[expectedIndex] ?? const <_Candidate>[]) {
      if (!visited.add(candidate.observedIndex)) {
        continue;
      }
      final _Candidate? existing = assigned[candidate.observedIndex];
      if (existing == null ||
          _augment(existing.expectedIndex, adjacency, assigned, visited)) {
        assigned[candidate.observedIndex] = candidate;
        return true;
      }
    }
    return false;
  }

  static int _compareCandidates(_Candidate a, _Candidate b) {
    final int byIou = b.iou.compareTo(a.iou);
    if (byIou != 0) {
      return byIou;
    }
    final int byDistance = a.centerDistancePt.compareTo(b.centerDistancePt);
    if (byDistance != 0) {
      return byDistance;
    }
    final int byObserved = a.observedIndex.compareTo(b.observedIndex);
    if (byObserved != 0) {
      return byObserved;
    }
    return a.expectedIndex.compareTo(b.expectedIndex);
  }

  static _LabelStatus _labelStatus(
    ExpectedField expected,
    ObservedField observed,
  ) {
    final String? expectedLabel = expected.labelText?.trim();
    final String? observedLabel = observed.labelText?.trim();
    final bool expectedHas = expectedLabel != null && expectedLabel.isNotEmpty;
    final bool observedHas = observedLabel != null && observedLabel.isNotEmpty;
    if (!expectedHas) {
      return _LabelStatus.notRequired;
    }
    if (!observedHas) {
      return _LabelStatus.missing;
    }
    if (expectedLabel.toLowerCase() != observedLabel.toLowerCase()) {
      return _LabelStatus.mismatch;
    }
    return _LabelStatus.ok;
  }

  static List<StructureBucket> _buckets(
    List<ExpectedField> expected,
    List<ObservedField> observed,
    List<_Pair> pairs,
    List<int> missingExpected,
    List<int> extraObserved,
    List<StructureDuplicate> duplicates,
  ) {
    final Map<String, _BucketBuilder> builders = <String, _BucketBuilder>{};
    _BucketBuilder builder(int page, FieldInventoryKind kind) {
      return builders.putIfAbsent(
        '$page|${kind.wireName}',
        () => _BucketBuilder(page, kind),
      );
    }

    for (int index = 0; index < expected.length; index++) {
      builder(expected[index].pageIndex, expected[index].kind).expected++;
    }
    for (final ObservedField field in observed) {
      builder(field.pageIndex, field.kind).observed++;
    }
    for (final _Pair pair in pairs) {
      final _BucketBuilder bucket = builder(
        pair.pageIndex,
        expected[pair.expectedIndex].kind,
      );
      bucket.matched++;
      if (!pair.kindOk) {
        bucket.typeMismatch++;
      }
    }
    for (final int index in missingExpected) {
      builder(expected[index].pageIndex, expected[index].kind).missing++;
    }
    for (final int index in extraObserved) {
      builder(observed[index].pageIndex, observed[index].kind).extra++;
    }
    for (final StructureDuplicate duplicate in duplicates) {
      final ObservedField field = observed[duplicate.observedIndex];
      builder(field.pageIndex, field.kind).duplicate++;
    }
    final List<StructureBucket> buckets = builders.values
        .map((_BucketBuilder bucket) => bucket.build())
        .toList();
    buckets.sort((StructureBucket a, StructureBucket b) {
      if (a.pageIndex != b.pageIndex) {
        return a.pageIndex.compareTo(b.pageIndex);
      }
      return a.kind.ordinal.compareTo(b.kind.ordinal);
    });
    return buckets;
  }
}

enum _LabelStatus { notRequired, ok, missing, mismatch }

final class _Candidate {
  const _Candidate({
    required this.expectedIndex,
    required this.observedIndex,
    required this.iou,
    required this.centerDistancePt,
    required this.geometryOk,
  });

  final int expectedIndex;
  final int observedIndex;
  final double iou;
  final double centerDistancePt;
  final bool geometryOk;
}

final class _Pair {
  _Pair({
    required this.expectedIndex,
    required this.observedIndex,
    required this.pageIndex,
    required this.iou,
    required this.centerDistancePt,
    required this.geometryOk,
    required this.kindOk,
    required this.label,
  }) : match = StructureMatch._(
         expectedIndex: expectedIndex,
         observedIndex: observedIndex,
         pageIndex: pageIndex,
         iou: iou,
         centerDistancePt: centerDistancePt,
         geometryOk: geometryOk,
         kindOk: kindOk,
         labelOk: label == _LabelStatus.ok || label == _LabelStatus.notRequired,
       );

  final int expectedIndex;
  final int observedIndex;
  final int pageIndex;
  final double iou;
  final double centerDistancePt;
  final bool geometryOk;
  final bool kindOk;
  final _LabelStatus label;
  final StructureMatch match;
}

final class _BucketBuilder {
  _BucketBuilder(this.pageIndex, this.kind);

  final int pageIndex;
  final FieldInventoryKind kind;
  int expected = 0;
  int observed = 0;
  int matched = 0;
  int missing = 0;
  int extra = 0;
  int duplicate = 0;
  int typeMismatch = 0;

  StructureBucket build() => StructureBucket._(
    pageIndex: pageIndex,
    kind: kind,
    expected: expected,
    observed: observed,
    matched: matched,
    missing: missing,
    extra: extra,
    duplicate: duplicate,
    typeMismatch: typeMismatch,
  );
}
