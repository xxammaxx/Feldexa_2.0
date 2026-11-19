// T055 overlap and conflict handling.
//
// Normative sources:
//  * specs/001-scanned-form-workflow/contracts/recognition-output.md
//    section 2 (`rect` rules and `conflictsWith`), section 5.2/5.4
//    (deterministic ordering and 1/8 pt rounding), and section 6 (overlap and
//    conflict handling);
//  * specs/001-scanned-form-workflow/spec.md FR-025;
//  * specs/001-scanned-form-workflow/research.md (IoU >= 0.5 marks both).
//
// Scope. This library owns the section 6 conflict predicate, the symmetric
// conflict graph, and the opt-in exact-duplicate collapse. It never creates or
// mutates suggestions, ids, types, confidence, uncertainty, labels, envelope
// fields, resolution state, diagnostics channels, persistence, or UI. It uses
// the existing [DisplayRect] from `geometry_detector.dart`; it does not
// duplicate that type. T053 owns typing, T054 confidence, T056 OCR, T057 the
// page envelope. Callers supply stable ids and the opaque `type` string.
//
// Rounding. Every stored rect coordinate (`x`, `y`, `width`, `height`) is
// converted with `round(value * 8)` to signed integer eighths before any
// comparison. Dart's `double.round()` sends an exact half away from zero, as
// required. Edges are then integer sums (`left + width`, `top + height`), so
// no floating-point addition participates after rounding. [DisplayRect]
// guarantees strictly positive sizes; if a sub-1/16 pt size would round to
// zero, it is raised to one 1/8 pt unit so the rounded rect remains
// non-degenerate. That is the only exception to nearest rounding, and it only
// affects rects that the 200 DPI detector cannot produce.
//
// IoU. IoU is computed on the rounded rects. The intersection area is the
// product of the positive x and y overlap widths in 1/8 pt units; the union is
// `areaA + areaB - intersection`. The returned double is
// `intersection / union`, or 0 when the rects are disjoint. Rounded rects are
// non-degenerate, so the union is always positive.
//
// Epsilon policy. `recognition-output.md` section 5.4 sets a 1e-6 comparison
// epsilon for unrounded floating-point measurements. Conflict decisions are
// not made on unrounded measurements: both thresholds are evaluated with exact
// integer arithmetic on the 1/8 pt lattice (`IoU >= 0.5` as
// `2 * intersection >= union`; centre distance `<= 4 pt` as
// `dx16^2 + dy16^2 <= 64^2`, where centres are in 1/16 pt units). The
// effective floating-point epsilon is therefore zero and cannot widen either
// inclusive boundary. [ConflictDetector.iou] is a diagnostic value (one
// correctly rounded double); callers must decide with
// [ConflictDetector.conflicts], never with `iou >= 0.5`.
//
// Conflict predicate. Two rects conflict when `IoU >= 0.5`, inclusive, or when
// one rounded rect contains the other's rounded centre, inclusive of the rect
// edges, and the Euclidean distance between the two rounded centres is
// `<= 4 pt`, inclusive. The relation is symmetric. The graph never removes,
// merges, auto-ranks, or mutates an item: both candidates remain, and every
// input id appears in the graph with a sorted, unique conflict list.
//
// Duplicate collapse. Section 6 limits duplicate suppression to exact
// duplicates (`IoU > 0.98` and same type) produced by the same detector pass.
// Collapse is a separate, explicit helper rather than a side effect of
// [ConflictDetector.detect], so the conflict path can never remove an item.
// The exact-duplicate predicate requires equal `type` strings, equal
// `detectorPass` values, and rounded `IoU > 0.98` (exact integer comparison
// `100 * intersection > 98 * union`). Different types or passes never
// collapse.
//
// Deterministic representative. Candidates are sorted by id ascending
// (`String.compareTo`, UTF-16 code units) and processed in that order. An item
// is retained unless it is a direct duplicate of an already-retained
// representative; then it collapses into that lowest-id representative. The
// duplicate relation is not transitive, so no transitive closure is taken:
// every collapsed item directly duplicates its retained representative, and
// retained representatives are pairwise non-duplicate within the same
// type/pass. [DuplicateCollapseResult.collapsedCount] is diagnostics-only;
// the helper never logs, serialises, or otherwise emits ids, types, labels, or
// other content.
//
// Validation and determinism. [ConflictItem] rejects an empty id, a negative
// detector pass, and a non-finite rect (the latter via [DisplayRect], which
// also enforces strictly positive sizes). Both entry points reject duplicate
// ids across the list. Every error message is a fixed string and never
// interpolates an id, type, rect, or other caller value. Ids are compared
// exactly and never trimmed or normalised. The `type` string is opaque to this
// module (schema validation owns the suggestion enum) and is used only for
// exact equality. There is no I/O, randomness, clock, locale collation, or
// mutable global state. Output is independent of input order: ids are sorted
// ascending, pairs by `(first, second)`, and per-item lists ascending.
library;

import 'dart:math' as math;

import 'geometry_detector.dart';

/// Number of 1/8 pt units in one point.
const int _unitsPerPoint = 8;

/// Maximum centre distance for the section 6 centre rule, in points.
const int _maxCenterDistancePt = 4;

/// Squared 4 pt distance in 1/16 pt centre units: `(4 pt * 16)^2`.
const int _maxCenterDistanceSquared =
    _maxCenterDistancePt * 16 * _maxCenterDistancePt * 16;

/// Duplicate threshold denominator and numerator: `IoU > 0.98`.
const int _duplicateScale = 100;
const int _duplicateThreshold = 98;

/// One immutable candidate participating in overlap handling.
///
/// [id] is the caller-supplied stable identity (non-empty, compared exactly);
/// [type] is the opaque type identity used only for exact-duplicate collapse;
/// [detectorPass] defaults to 0 and must be non-negative. [rect] is the
/// existing display-space [DisplayRect], which already rejects non-finite
/// values and non-positive sizes.
final class ConflictItem {
  /// Creates a validated candidate.
  ///
  /// Throws a content-free [ArgumentError] for an empty [id], a negative
  /// [detectorPass], or a rect whose rounded coordinates cannot be
  /// represented (non-finite input is rejected by [DisplayRect] itself).
  ConflictItem({
    required this.id,
    required this.rect,
    required this.type,
    this.detectorPass = 0,
  }) {
    if (id.isEmpty) {
      throw ArgumentError('conflict item id must not be empty');
    }
    if (detectorPass < 0) {
      throw ArgumentError('conflict item detector pass must be non-negative');
    }
    // DisplayRect validates the four stored values. Reject a finite-but-huge
    // rect before the rounding multiplication can overflow to infinity.
    if (!_isRoundable(rect.x) ||
        !_isRoundable(rect.y) ||
        !_isRoundable(rect.width) ||
        !_isRoundable(rect.height)) {
      throw ArgumentError('conflict item rect coordinates are out of range');
    }
  }

  /// Caller-supplied stable identity; never trimmed or rewritten.
  final String id;

  /// Display-space rectangle in points.
  final DisplayRect rect;

  /// Opaque type identity for exact-duplicate comparison.
  final String type;

  /// Zero-based detector pass that produced the item.
  final int detectorPass;
}

/// One unordered conflicting id pair, ordered by `first <= second`.
final class ConflictPair implements Comparable<ConflictPair> {
  ConflictPair._(this.first, this.second) : assert(first.compareTo(second) < 0);

  /// The lexicographically smaller id.
  final String first;

  /// The lexicographically larger id.
  final String second;

  @override
  int compareTo(ConflictPair other) {
    final int byFirst = first.compareTo(other.first);
    if (byFirst != 0) {
      return byFirst;
    }
    return second.compareTo(other.second);
  }

  @override
  bool operator ==(Object other) {
    return other is ConflictPair &&
        other.first == first &&
        other.second == second;
  }

  @override
  int get hashCode => Object.hash(first, second);

  @override
  String toString() => 'ConflictPair($first, $second)';
}

/// The complete symmetric section 6 conflict graph for one item list.
///
/// [conflictsWith] contains every input id exactly once, including ids whose
/// list is empty. Its keys and each value list are unmodifiable; keys are
/// ascending by id and values are sorted, unique ids. [pairs] is the sorted,
/// unique deduplicated edge list. Both candidates of every pair remain in the
/// caller's list; the graph is purely advisory.
final class ConflictGraph {
  ConflictGraph._(this.conflictsWith, this.pairs);

  /// Sorted, unique conflicting ids for every input id.
  final Map<String, List<String>> conflictsWith;

  /// Sorted, unique conflicting pairs.
  final List<ConflictPair> pairs;
}

/// The result of deterministic exact-duplicate collapse.
///
/// [representatives] is unmodifiable and sorted by id ascending. It contains
/// the retained item objects themselves; no item is copied, mutated, or
/// rewritten. [collapsedCount] is the number of input items that were collapsed
/// into a representative and is diagnostics-only.
final class DuplicateCollapseResult {
  DuplicateCollapseResult._(this.representatives, this.collapsedCount);

  /// Retained representatives, ascending by id.
  final List<ConflictItem> representatives;

  /// Number of removed input items; never content, ids, or types.
  final int collapsedCount;
}

/// The deterministic, pure section 6 conflict detector.
final class ConflictDetector {
  const ConflictDetector._();

  /// Returns the diagnostic IoU of two display rects on the rounded lattice.
  ///
  /// The result is `intersection / union` in `0.0 ... 1.0`, or 0.0 when the
  /// rounded rects are disjoint. It is one correctly rounded double; use
  /// [conflicts] for the inclusive `IoU >= 0.5` decision.
  ///
  /// Throws a content-free [ArgumentError] if a rect cannot be placed on the
  /// 1/8 pt lattice.
  static double iou(DisplayRect a, DisplayRect b) {
    final _GridRect roundedA = _GridRect.fromDisplayRect(a);
    final _GridRect roundedB = _GridRect.fromDisplayRect(b);
    return _iou(roundedA, roundedB);
  }

  /// Whether two display rects conflict under the inclusive section 6 rules.
  ///
  /// Both the `IoU >= 0.5` comparison and the centre-containment plus
  /// `distance <= 4 pt` comparison use exact integer arithmetic on rounded
  /// geometry. The relation is symmetric.
  static bool conflicts(DisplayRect a, DisplayRect b) {
    return _conflicts(
      _GridRect.fromDisplayRect(a),
      _GridRect.fromDisplayRect(b),
    );
  }

  /// Builds the symmetric conflict graph for [items].
  ///
  /// Throws a content-free [ArgumentError] if the list contains duplicate ids.
  /// The input list, its order, and every item are left untouched.
  static ConflictGraph detect(List<ConflictItem> items) {
    _checkUniqueIds(items);
    final List<ConflictItem> sorted = List<ConflictItem>.of(items)
      ..sort((ConflictItem a, ConflictItem b) => a.id.compareTo(b.id));
    final List<_GridRect> rounded = sorted
        .map((ConflictItem item) => _GridRect.fromDisplayRect(item.rect))
        .toList(growable: false);
    final Map<String, List<String>> conflictsWith = <String, List<String>>{
      for (final ConflictItem item in sorted) item.id: <String>[],
    };
    final List<ConflictPair> pairs = <ConflictPair>[];

    for (int first = 0; first < sorted.length; first++) {
      for (int second = first + 1; second < sorted.length; second++) {
        if (!_conflicts(rounded[first], rounded[second])) {
          continue;
        }
        final String firstId = sorted[first].id;
        final String secondId = sorted[second].id;
        conflictsWith[firstId]!.add(secondId);
        conflictsWith[secondId]!.add(firstId);
        pairs.add(ConflictPair._(firstId, secondId));
      }
    }
    pairs.sort();

    final Map<String, List<String>> frozen = <String, List<String>>{
      for (final MapEntry<String, List<String>> entry in conflictsWith.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    };
    return ConflictGraph._(
      Map<String, List<String>>.unmodifiable(frozen),
      List<ConflictPair>.unmodifiable(pairs),
    );
  }
}

/// Deterministic exact-duplicate collapse for same-type, same-pass items.
final class ExactDuplicateCollapser {
  const ExactDuplicateCollapser._();

  /// Whether [a] and [b] are exact duplicates under section 6.
  ///
  /// Requires the same `type`, the same `detectorPass`, and rounded
  /// `IoU > 0.98`. Nothing else participates.
  static bool areExactDuplicates(ConflictItem a, ConflictItem b) {
    if (a.type != b.type || a.detectorPass != b.detectorPass) {
      return false;
    }
    return _iouAboveDuplicateThreshold(
      _GridRect.fromDisplayRect(a.rect),
      _GridRect.fromDisplayRect(b.rect),
    );
  }

  /// Collapses exact duplicates into their lowest-id representative.
  ///
  /// Items are processed in ascending id order. An item is collapsed when it
  /// directly duplicates an already-retained representative of the same type
  /// and detector pass; otherwise it is retained. The input list and items are
  /// not mutated. Throws a content-free [ArgumentError] for duplicate ids.
  static DuplicateCollapseResult collapse(List<ConflictItem> items) {
    _checkUniqueIds(items);
    final List<ConflictItem> sorted = List<ConflictItem>.of(items)
      ..sort((ConflictItem a, ConflictItem b) => a.id.compareTo(b.id));
    final List<ConflictItem> representatives = <ConflictItem>[];
    final List<_GridRect> representativeRects = <_GridRect>[];

    for (final ConflictItem item in sorted) {
      final _GridRect rounded = _GridRect.fromDisplayRect(item.rect);
      bool collapsed = false;
      for (int index = 0; index < representatives.length; index++) {
        final ConflictItem representative = representatives[index];
        if (representative.type != item.type ||
            representative.detectorPass != item.detectorPass) {
          continue;
        }
        if (_iouAboveDuplicateThreshold(representativeRects[index], rounded)) {
          collapsed = true;
          break;
        }
      }
      if (!collapsed) {
        representatives.add(item);
        representativeRects.add(rounded);
      }
    }

    return DuplicateCollapseResult._(
      List<ConflictItem>.unmodifiable(representatives),
      items.length - representatives.length,
    );
  }
}

/// One rect on the exact 1/8 pt integer lattice.
///
/// [left] and [top] are signed 1/8 pt units; [width] and [height] are positive
/// 1/8 pt units. Edges and areas are integer arithmetic only.
final class _GridRect {
  const _GridRect._(this.left, this.top, this.width, this.height);

  factory _GridRect.fromDisplayRect(DisplayRect rect) {
    final int left = _toEighths(rect.x);
    final int top = _toEighths(rect.y);
    int width = _toEighths(rect.width);
    int height = _toEighths(rect.height);
    // DisplayRect guarantees strictly positive sizes. A sub-1/16 pt extent
    // rounds to zero; raise it to one unit so the lattice rect stays valid.
    if (width <= 0) {
      width = 1;
    }
    if (height <= 0) {
      height = 1;
    }
    return _GridRect._(left, top, width, height);
  }

  final int left;
  final int top;
  final int width;
  final int height;

  int get right => left + width;

  int get bottom => top + height;

  int get area => width * height;

  /// Centre x in 1/16 pt units.
  int get centerX16 => left + right;

  /// Centre y in 1/16 pt units.
  int get centerY16 => top + bottom;
}

/// Rounds one finite coordinate to signed 1/8 pt units, ties away from zero.
int _toEighths(double value) {
  final double scaled = value * _unitsPerPoint;
  if (!scaled.isFinite) {
    throw ArgumentError('conflict rect coordinates are out of range');
  }
  return scaled.round();
}

/// Whether [value] can be multiplied by 8 without overflowing to infinity.
bool _isRoundable(double value) => (value * _unitsPerPoint).isFinite;

/// Rejects duplicate ids across one input list, content-free.
void _checkUniqueIds(List<ConflictItem> items) {
  final Set<String> seen = <String>{};
  for (final ConflictItem item in items) {
    if (!seen.add(item.id)) {
      throw ArgumentError('conflict item ids must be unique');
    }
  }
}

/// Integer intersection area in squared 1/8 pt units.
int _intersectionArea(_GridRect a, _GridRect b) {
  final int overlapWidth =
      math.min(a.right, b.right) - math.max(a.left, b.left);
  final int overlapHeight =
      math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  if (overlapWidth <= 0 || overlapHeight <= 0) {
    return 0;
  }
  return overlapWidth * overlapHeight;
}

/// Diagnostic IoU on rounded rects.
double _iou(_GridRect a, _GridRect b) {
  final int intersection = _intersectionArea(a, b);
  if (intersection == 0) {
    return 0.0;
  }
  final int union = a.area + b.area - intersection;
  return intersection / union;
}

/// Exact `IoU >= 0.5`, inclusive.
bool _iouAtLeastHalf(_GridRect a, _GridRect b) {
  final int intersection = _intersectionArea(a, b);
  if (intersection == 0) {
    return false;
  }
  final int union = a.area + b.area - intersection;
  return 2 * intersection >= union;
}

/// Exact `IoU > 0.98`.
bool _iouAboveDuplicateThreshold(_GridRect a, _GridRect b) {
  final int intersection = _intersectionArea(a, b);
  if (intersection == 0) {
    return false;
  }
  final int union = a.area + b.area - intersection;
  return _duplicateScale * intersection > _duplicateThreshold * union;
}

/// Whether [outer] contains [inner]'s centre, inclusive of the rect edges.
bool _containsCenter(_GridRect outer, _GridRect inner) {
  final int x = inner.centerX16;
  final int y = inner.centerY16;
  return x >= 2 * outer.left &&
      x <= 2 * outer.right &&
      y >= 2 * outer.top &&
      y <= 2 * outer.bottom;
}

/// Inclusive centre-containment plus `distance <= 4 pt` rule.
bool _centerRule(_GridRect a, _GridRect b) {
  if (!_containsCenter(a, b) && !_containsCenter(b, a)) {
    return false;
  }
  final int dx = a.centerX16 - b.centerX16;
  final int dy = a.centerY16 - b.centerY16;
  return dx * dx + dy * dy <= _maxCenterDistanceSquared;
}

/// The complete section 6 predicate on rounded rects.
bool _conflicts(_GridRect a, _GridRect b) {
  return _iouAtLeastHalf(a, b) || _centerRule(a, b);
}
