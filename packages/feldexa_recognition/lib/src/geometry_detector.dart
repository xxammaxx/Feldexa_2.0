// Deterministic geometry-first candidate detection over a 200 DPI raster.
//
// Normative sources:
//  * specs/001-scanned-form-workflow/contracts/recognition-output.md
//    sections 2, 2.1, 3.1, 3.2, and 5.2;
//  * specs/001-scanned-form-workflow/contracts/coordinates-and-geometry.md
//    sections 1 and 4;
//  * specs/001-scanned-form-workflow/research.md D-06.
//
// Scope: this library owns geometric *candidates*, not suggestions. It has no
// ids, suggestion types, confidence, uncertainty, labels, OCR, conflicts,
// persistence, or UI. The adapter contract for later tasks is:
//
//  * `GeometryCandidate.rect` becomes the suggestion `rect` (display-space
//    points, 1/8 pt rounded, inside the page);
//  * `GeometryCandidate.cues` becomes the sorted, unique `evidence.cues` list;
//  * `GeometryCandidate.inkCoverage` is the measured interior ink fraction used
//    by the FR-016 / recognition-output.md section 2.1 gate. It is a detector
//    diagnostic only, never a model field;
//  * `small_square` is a cue for T050/T053 typing to map to `checkbox`;
//  * T053 owns label proximity, keyword typing, and OCR alignment; T054 owns
//    confidence; T055 owns IoU conflicts; T057 owns the page envelope.
//
// Coordinate mapping. `RasterAnalysis` exposes a half-open pixel rectangle
// `[left, right) x [top, bottom)` whose pixel `i` covers
// `[i / rasterScale, (i + 1) / rasterScale)` and whose centre is
// `(i + 0.5) / rasterScale` (coordinates-and-geometry.md section 4). This
// detector treats the half-open rectangle as an interval and maps its four
// edges with `pixelEdgeToPoint(edge) = edge / rasterScale`. Each edge is then
// rounded exactly once to the nearest 1/8 pt (ties away from zero, Dart
// `double.round`), width/height are recomputed from the rounded edges, and
// degenerate results are dropped. The result is clamped inward to
// `[0, 0, floor(pageWidthPt * 8) / 8, floor(pageHeightPt * 8) / 8]`: each
// rounded edge is lowered to the largest 1/8 pt multiple that does not exceed
// its page extent. This keeps every emitted `x`, `y`, `width`, and `height` an
// exact 1/8 pt multiple *and* inside the page even when the page size is not
// itself a multiple of 1/8 pt. Clamping is done after rounding. Ink is always
// measured on the exact half-open raster rectangle *before* display rounding
// or clamping.
//
// Rule model. A raster row is scanned left-to-right and a raster column
// top-to-bottom. An ink run must be at least [_minRunLengthPx] (3.6 pt) long;
// collinear runs separated by at most [_maxCollinearGapPx] (0.72 pt) are
// bridged. Vertically or horizontally contiguous runs whose runs overlap
// form one ink band; adjacent runs merge only when their lengths differ by at
// most a factor of [_maxGroupSpanRatio], so a filled block attached to a thin
// rule cannot dissolve the rule into an over-thick band. A band thicker than
// [_maxRuleThicknessPx] (2.16 pt) is rejected as text-like. Parallel/collinear
// fragments within [_maxParallelGapPx] (0.72 pt) of each other are merged into
// one rule. A
// rule's position is the centre of its ink band (the median covered row or
// column). The output depends only on the raster bytes, page size, and the
// scan order above; it is independent of caller order and has no randomness.
//
// Detectors (fixed execution order: rules -> grids -> boxes -> underlines ->
// whitespace -> alignment -> gate/merge/sort):
//
//  * Grids need at least two horizontal and two vertical rules whose spans
//    agree within [_spanTolerancePx] (2.16 pt) and whose perpendicular
//    endpoints agree within [_cornerTolerancePx] (2.16 pt). A single closed
//    rectangle is a box, not a grid: at least one axis must have three rules
//    (two addressable cells). Every addressable cell receives both `grid_cell`
//    and `table_cell`; this is the only source of `table_cell`. Cells whose
//    interior exceeds the ink gate are dropped.
//
//  * Boxes need four rules whose corners agree within
//    [_cornerTolerancePx]. The candidate rect is the *interior*: the right
//    edge of the left rule, the left edge of the right rule, the bottom edge
//    of the top rule, and the top edge of the bottom rule. The printed border
//    is therefore never inside the candidate. A box whose interior contains a
//    detected grid line is a grid region, not a box. A near-square interior
//    whose *outer* bordered side is 4-20 pt, whose equal-side ratio is at most
//    [_smallSquareMaxAspect], and whose interior ink is at most 50 % gets
//    `small_square`; the returned rect stays the interior.
//
//  * Underlines are emitted only for horizontal rules at least
//    [_minUnderlineLengthPx] (20.16 pt) long that are not page-border rules
//    and were not consumed as a box or grid side. The candidate is the
//    [_underlineBandHeightPx] (18 pt) band directly above the rule (the
//    documented plausible single-line band; 8-36 pt is the supported range).
//    The band must fit inside the raster. Low ink is required by the gate.
//
//  * Whitespace uses 4-connected background components in row-major scan
//    order. Components touching a page edge are open margins and are rejected.
//    A kept component must be adjacent to ink, at least
//    [_minWhitespaceSidePx] px on each side, at least
//    [_minWhitespaceAreaPx] px in area, at most
//    [_maxWhitespaceAreaFraction] of the page, and its bounding box must pass
//    the ink gate. The bounding box is the candidate. This is a bounded-empty-
//    region heuristic, not semantic understanding: it cannot tell a field from
//    an empty printed area, and large-text counters can look like small holes.
//
//  * Alignment is layout analysis over already produced candidates. A
//    candidate gets `alignment_left` when its rounded left edge is within
//    [_alignmentTolerancePt] of at least two other candidates' left edges, or
//    of an external non-page-border vertical rule (a rule that is not one of
//    the candidate's own sides). Alignment never creates a candidate. OCR
//    label alignment is T053/T056 work.
//
// Ink gate. A candidate whose exact interior ink fraction is strictly greater
// than 12 % is rejected, except a `small_square` (which is still bounded by
// the 50 % small-square ceiling). The "detected table cell with a printed
// label outside" exception is deliberately not claimed because label
// ownership is T053/T056. A candidate covering predominantly printed text is
// therefore never returned by this library.
//
// Merging and determinism. Candidates produced by more than one detector with
// the same 1/8 pt rounded rect are returned once with the union of their cues
// (sorted, unique) and the maximum measured coverage; the first candidate in
// the fixed detector order supplies the rect. Distinct overlapping
// rectangles are all returned; conflict handling is T055. Final order is
// rounded y, then x, then height, then width, then the cue list
// lexicographically. The same bytes and page size produce byte-for-byte equal
// lists across runs.
//
// Failure behavior. The raster dimensions must equal
// `RasterSize.fromDisplaySize(widthPt, heightPt)`; that is the documented
// 200 DPI rounding tolerance (+/-0.5 px). A mismatch, or an invalid page size,
// raises a content-free [ArgumentError] and never produces out-of-page rects.
// An all-white or all-black page returns an empty list without throwing.
library;

import 'dart:typed_data';

import 'raster.dart';

/// Minimum ink-run length for a ruling-line fragment: 10 px ~= 3.6 pt.
///
/// A 4 pt checkbox side is about 11 px at 200 DPI, so the minimum must stay
/// below that to let `small_square` boxes be detected.
const int _minRunLengthPx = 10;

/// Maximum accepted thickness of one ruling-line band: 6 px ~= 2.16 pt.
const int _maxRuleThicknessPx = 6;

/// Maximum collinear gap bridged inside one scan row/column: 2 px ~= 0.72 pt.
const int _maxCollinearGapPx = 2;

/// Maximum gap between parallel/collinear fragments merged into one rule.
const int _maxParallelGapPx = 2;

/// Maximum span ratio between runs merged into one ink band.
///
/// Adjacent runs whose lengths differ by more than this factor belong to
/// different structures (for example, a filled block touching a thin rule),
/// so they must not dissolve the thin rule into an over-thick band.
const int _maxGroupSpanRatio = 2;

/// Corner/endpoint agreement tolerance: 6 px ~= 2.16 pt.
const int _cornerTolerancePx = 6;

/// Rule-span agreement tolerance for grid clustering: 6 px ~= 2.16 pt.
const int _spanTolerancePx = 6;

/// Minimum positive interior side of a box or grid cell: 6 px ~= 2.16 pt.
const int _minInteriorSidePx = 6;

/// Underline band height above a horizontal rule: 50 px = 18 pt.
///
/// 18 pt is inside the documented 8-36 pt plausible single-line range.
const int _underlineBandHeightPx = 50;

/// Minimum horizontal-rule length that can produce an underline: 56 px.
const int _minUnderlineLengthPx = 56;

/// The FR-016 / recognition-output.md section 2.1 interior ink limit.
const int _maxInkPercent = 12;

/// Small-square upper ink bound (the 12 % gate is exempted for this cue).
const int _smallSquareMaxInkPercent = 50;

/// Small-square outer-side range in display points.
const double _smallSquareMinSidePt = 4;
const double _smallSquareMaxSidePt = 20;

/// Maximum small-square equal-side ratio.
const double _smallSquareMaxAspect = 1.25;

/// Whitespace component minimum side and area.
const int _minWhitespaceSidePx = 10;
const int _minWhitespaceAreaPx = 100;

/// Whitespace components larger than this fraction of the page are rejected
/// as page-frame/background regions rather than bounded field areas.
const double _maxWhitespaceAreaFraction = 0.25;

/// Alignment tolerance in display points.
const double _alignmentTolerancePt = 1.0;

/// An immutable rectangle in page display-space points.
///
/// `x` and `y` are the top-left corner; `width` and `height` are strictly
/// positive. Coordinates are finite. Value equality is exact because every
/// edge is a 1/8 pt multiple, including the inward page-bound clamp; a page
/// whose size is not a 1/8 pt multiple therefore never leaks an unrounded
/// extent into a rectangle.
final class DisplayRect {
  /// Creates a validated display-space rectangle.
  factory DisplayRect({
    required double x,
    required double y,
    required double width,
    required double height,
  }) {
    if (!x.isFinite || !y.isFinite) {
      throw ArgumentError('display rect origin must be finite');
    }
    if (!width.isFinite || !height.isFinite) {
      throw ArgumentError('display rect size must be finite');
    }
    if (!(width > 0) || !(height > 0)) {
      throw ArgumentError('display rect size must be strictly positive');
    }
    return DisplayRect._(x, y, width, height);
  }

  const DisplayRect._(this.x, this.y, this.width, this.height);

  /// Top-left x in display-space points.
  final double x;

  /// Top-left y in display-space points.
  final double y;

  /// Width in display-space points; strictly positive.
  final double width;

  /// Height in display-space points; strictly positive.
  final double height;

  @override
  bool operator ==(Object other) {
    return other is DisplayRect &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'DisplayRect($x, $y, $width, $height)';
}

/// An immutable geometric candidate in page display-space points.
///
/// [cues] are contract cue tokens from `recognition-output.md` section 3.1,
/// sorted and unique. [inkCoverage] is the measured interior ink fraction in
/// `0.0 ... 1.0`, not a confidence. The detector never emits ids, types,
/// confidence, uncertainty, labels, or conflicts.
final class GeometryCandidate {
  /// Creates a candidate, normalising the cue list.
  factory GeometryCandidate({
    required DisplayRect rect,
    required List<String> cues,
    required double inkCoverage,
  }) {
    if (!inkCoverage.isFinite || inkCoverage < 0 || inkCoverage > 1) {
      throw ArgumentError('ink coverage must be a fraction in 0 ... 1');
    }
    final List<String> sorted = cues.toSet().toList()..sort();
    return GeometryCandidate._(
      rect,
      List<String>.unmodifiable(sorted),
      inkCoverage,
    );
  }

  const GeometryCandidate._(this.rect, this.cues, this.inkCoverage);

  /// Candidate rectangle in display-space points, inside the page bounds.
  final DisplayRect rect;

  /// Sorted, unique contract cue tokens.
  final List<String> cues;

  /// Measured interior ink fraction in `0.0 ... 1.0`.
  final double inkCoverage;

  @override
  bool operator ==(Object other) {
    if (other is! GeometryCandidate ||
        other.rect != rect ||
        other.inkCoverage != inkCoverage ||
        other.cues.length != cues.length) {
      return false;
    }
    for (int index = 0; index < cues.length; index++) {
      if (other.cues[index] != cues[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(rect, Object.hashAll(cues), inkCoverage);

  @override
  String toString() =>
      'GeometryCandidate($rect, cues: $cues, inkCoverage: $inkCoverage)';
}

/// Deterministic, geometry-first detectors over one 200 DPI grayscale raster.
///
/// The class is stateless. See the library documentation for thresholds,
/// coordinate mapping, the ink gate, merging, and ordering.
final class GeometryDetector {
  const GeometryDetector._();

  /// Detects geometric candidates for one analysed page.
  ///
  /// [analysis] must be a 200 DPI raster whose dimensions equal
  /// `RasterSize.fromDisplaySize(widthPt: pageWidthPt, heightPt:
  /// pageHeightPt)`. A mismatch or invalid page size raises a content-free
  /// [ArgumentError]. The returned list is unmodifiable and ordered by rounded
  /// y, then x, then height, then width, then cue list lexicographically.
  static List<GeometryCandidate> detect(
    RasterAnalysis analysis, {
    required double pageWidthPt,
    required double pageHeightPt,
  }) {
    _checkPage(analysis, pageWidthPt, pageHeightPt);

    final _InkMask mask = _InkMask.from(analysis);
    final List<_Rule> rules = _detectRules(mask);
    final _GridDetection grids = _detectGrids(rules, analysis);
    final _BoxDetection boxes = _detectBoxes(
      rules,
      mask,
      analysis,
      grids.rules,
    );
    final Set<_Rule> consumed = <_Rule>{...boxes.rules, ...grids.rules};
    final List<_RawCandidate> raw = <_RawCandidate>[
      ...boxes.candidates,
      ...grids.candidates,
      ..._detectUnderlines(rules, mask, analysis, consumed),
      ..._detectWhitespace(mask, analysis),
    ];

    final List<_Accumulator> merged = _merge(raw, pageWidthPt, pageHeightPt);
    _applyAlignment(merged, rules, mask);
    final List<GeometryCandidate> candidates =
        merged
            .map(
              (_Accumulator candidate) => GeometryCandidate(
                rect: candidate.rect,
                cues: candidate.cues.toList(),
                inkCoverage: candidate.coverage,
              ),
            )
            .toList()
          ..sort(_compareCandidates);
    return List<GeometryCandidate>.unmodifiable(candidates);
  }

  static void _checkPage(
    RasterAnalysis analysis,
    double pageWidthPt,
    double pageHeightPt,
  ) {
    final RasterSize expected;
    try {
      expected = RasterSize.fromDisplaySize(
        widthPt: pageWidthPt,
        heightPt: pageHeightPt,
      );
    } on ArgumentError {
      throw ArgumentError('page size is not representable at 200 DPI');
    }
    final GrayRaster raster = analysis.raster;
    if (raster.width != expected.widthPx ||
        raster.height != expected.heightPx) {
      throw ArgumentError(
        'raster dimensions are inconsistent with the supplied page size at '
        '200 DPI',
      );
    }
  }

  static List<_Rule> _detectRules(_InkMask mask) {
    final List<_Rule> rules = <_Rule>[
      ..._scanRules(mask, horizontal: true),
      ..._scanRules(mask, horizontal: false),
    ];
    return _mergeRules(rules);
  }

  static List<_Rule> _scanRules(_InkMask mask, {required bool horizontal}) {
    final int outer = horizontal ? mask.height : mask.width;
    final int inner = horizontal ? mask.width : mask.height;
    final List<_RunGroup> groups = <_RunGroup>[];
    List<_RunGroup> active = <_RunGroup>[];

    for (int line = 0; line < outer; line++) {
      final List<_Run> runs = _lineRuns(
        mask,
        horizontal: horizontal,
        line: line,
        inner: inner,
      );
      final List<_RunGroup> nextActive = <_RunGroup>[];
      for (final _Run run in runs) {
        _RunGroup? target;
        for (final _RunGroup group in active) {
          if (group.lastLine == line - 1 &&
              group.overlaps(run.start, run.end) &&
              _compatibleSpans(group, run)) {
            target = group;
            break;
          }
        }
        if (target == null) {
          final _RunGroup group = _RunGroup(line, line, run.start, run.end);
          groups.add(group);
          nextActive.add(group);
        } else {
          target.extend(run.start, run.end, line);
          nextActive.add(target);
        }
      }
      active = nextActive;
    }

    final List<_Rule> rules = <_Rule>[];
    for (final _RunGroup group in groups) {
      final int thickness = group.lastLine - group.firstLine + 1;
      if (thickness > _maxRuleThicknessPx) {
        continue;
      }
      rules.add(
        horizontal
            ? _Rule(
                horizontal: true,
                x0: group.start,
                y0: group.firstLine,
                x1: group.end,
                y1: group.lastLine + 1,
              )
            : _Rule(
                horizontal: false,
                x0: group.firstLine,
                y0: group.start,
                x1: group.lastLine + 1,
                y1: group.end,
              ),
      );
    }
    return rules;
  }

  static bool _compatibleSpans(_RunGroup group, _Run run) {
    final int groupSpan = group.end - group.start;
    final int runSpan = run.end - run.start;
    return runSpan * _maxGroupSpanRatio >= groupSpan &&
        groupSpan * _maxGroupSpanRatio >= runSpan;
  }

  static List<_Run> _lineRuns(
    _InkMask mask, {
    required bool horizontal,
    required int line,
    required int inner,
  }) {
    bool at(int position) {
      return horizontal
          ? mask.isInk(position, line)
          : mask.isInk(line, position);
    }

    final List<_Run> runs = <_Run>[];
    int position = 0;
    while (position < inner) {
      while (position < inner && !at(position)) {
        position++;
      }
      final int start = position;
      while (position < inner && at(position)) {
        position++;
      }
      if (position - start >= _minRunLengthPx) {
        runs.add(_Run(line, start, position));
      }
    }

    final List<_Run> bridged = <_Run>[];
    for (final _Run run in runs) {
      if (bridged.isNotEmpty &&
          run.start - bridged.last.end <= _maxCollinearGapPx) {
        final _Run previous = bridged.removeLast();
        bridged.add(_Run(line, previous.start, run.end));
      } else {
        bridged.add(run);
      }
    }
    return bridged;
  }

  static List<_Rule> _mergeRules(List<_Rule> rules) {
    final List<_Rule> current = List<_Rule>.of(rules)..sort(_compareRules);
    bool changed = true;
    while (changed) {
      changed = false;
      final List<_Rule> next = <_Rule>[];
      for (final _Rule rule in current) {
        int match = -1;
        for (int index = 0; index < next.length; index++) {
          if (_mergeable(next[index], rule)) {
            match = index;
            break;
          }
        }
        if (match < 0) {
          next.add(rule);
        } else {
          next[match] = _unionRule(next[match], rule);
          changed = true;
        }
      }
      current
        ..clear()
        ..addAll(next);
    }
    current.sort(_compareRules);
    return current;
  }

  static bool _mergeable(_Rule first, _Rule second) {
    if (first.horizontal != second.horizontal) {
      return false;
    }
    final _Rule union = _unionRule(first, second);
    if ((first.horizontal ? union.height : union.width) > _maxRuleThicknessPx) {
      return false;
    }
    if (first.horizontal) {
      if (second.x0 > first.x1 + _maxParallelGapPx ||
          first.x0 > second.x1 + _maxParallelGapPx) {
        return false;
      }
      if (second.y0 > first.y1 + _maxParallelGapPx ||
          first.y0 > second.y1 + _maxParallelGapPx) {
        return false;
      }
    } else {
      if (second.y0 > first.y1 + _maxParallelGapPx ||
          first.y0 > second.y1 + _maxParallelGapPx) {
        return false;
      }
      if (second.x0 > first.x1 + _maxParallelGapPx ||
          first.x0 > second.x1 + _maxParallelGapPx) {
        return false;
      }
    }
    return true;
  }

  static _Rule _unionRule(_Rule first, _Rule second) {
    return _Rule(
      horizontal: first.horizontal,
      x0: _minInt(first.x0, second.x0),
      y0: _minInt(first.y0, second.y0),
      x1: _maxInt(first.x1, second.x1),
      y1: _maxInt(first.y1, second.y1),
    );
  }

  static _GridDetection _detectGrids(
    List<_Rule> rules,
    RasterAnalysis analysis,
  ) {
    final List<List<_Rule>> horizontalClusters = _clusters(
      rules.where((_Rule rule) => rule.horizontal).toList(),
      horizontal: true,
    );
    final List<List<_Rule>> verticalClusters = _clusters(
      rules.where((_Rule rule) => !rule.horizontal).toList(),
      horizontal: false,
    );
    final List<_RawCandidate> candidates = <_RawCandidate>[];
    final Set<_Rule> consumed = <_Rule>{};

    for (final List<_Rule> horizontalCluster in horizontalClusters) {
      if (horizontalCluster.length < 2) {
        continue;
      }
      for (final List<_Rule> verticalCluster in verticalClusters) {
        if (verticalCluster.length < 2) {
          continue;
        }
        // A single closed rectangle (2 + 2 rules) is a box, not a grid.
        if (horizontalCluster.length < 3 && verticalCluster.length < 3) {
          continue;
        }
        final List<_Rule> horizontals = List<_Rule>.of(horizontalCluster)
          ..sort(_compareRuleCenterY);
        final List<_Rule> verticals = List<_Rule>.of(verticalCluster)
          ..sort(_compareRuleCenterX);
        final int left = _medianInt(
          horizontals.map((_Rule rule) => rule.x0).toList(),
        );
        final int right = _medianInt(
          horizontals.map((_Rule rule) => rule.x1).toList(),
        );
        final int top = _medianInt(
          verticals.map((_Rule rule) => rule.y0).toList(),
        );
        final int bottom = _medianInt(
          verticals.map((_Rule rule) => rule.y1).toList(),
        );
        if (!_gridCovers(horizontals, verticals, left, right, top, bottom)) {
          continue;
        }
        // A checkbox-sized near-square region is not a table, even when a
        // mark inside it happens to form a third horizontal rule.
        if (_hasSmallSquareGeometry(right - left, bottom - top)) {
          continue;
        }

        consumed.addAll(horizontals);
        consumed.addAll(verticals);
        for (int row = 0; row < horizontals.length - 1; row++) {
          final int cellTop = horizontals[row].y1;
          final int cellBottom = horizontals[row + 1].y0;
          if (cellBottom - cellTop < _minInteriorSidePx) {
            continue;
          }
          for (int column = 0; column < verticals.length - 1; column++) {
            final int cellLeft = verticals[column].x1;
            final int cellRight = verticals[column + 1].x0;
            if (cellRight - cellLeft < _minInteriorSidePx) {
              continue;
            }
            final PixelRect rect = PixelRect.fromLTRB(
              cellLeft,
              cellTop,
              cellRight,
              cellBottom,
            );
            final InkCoverage coverage = analysis.inkCoverage(rect);
            if (coverage.exceedsPercent(_maxInkPercent)) {
              continue;
            }
            candidates.add(
              _RawCandidate(
                pixelRect: rect,
                cues: <String>{'grid_cell', 'table_cell'},
                inkCoverage: coverage.fraction,
                sideRules: <_Rule>{
                  horizontals[row],
                  horizontals[row + 1],
                  verticals[column],
                  verticals[column + 1],
                },
              ),
            );
          }
        }
      }
    }
    return _GridDetection(candidates, consumed);
  }

  static List<List<_Rule>> _clusters(
    List<_Rule> rules, {
    required bool horizontal,
  }) {
    final List<_Rule> sorted = List<_Rule>.of(rules)..sort(_compareRules);
    final List<int> parent = List<int>.generate(
      sorted.length,
      (int index) => index,
    );
    int find(int index) {
      int root = index;
      while (parent[root] != root) {
        parent[root] = parent[parent[root]];
        root = parent[root];
      }
      return root;
    }

    for (int first = 0; first < sorted.length; first++) {
      for (int second = first + 1; second < sorted.length; second++) {
        if (_sameSpan(sorted[first], sorted[second], horizontal: horizontal)) {
          final int left = find(first);
          final int right = find(second);
          if (left != right) {
            parent[right] = left;
          }
        }
      }
    }

    final Map<int, List<_Rule>> grouped = <int, List<_Rule>>{};
    for (int index = 0; index < sorted.length; index++) {
      grouped.putIfAbsent(find(index), () => <_Rule>[]).add(sorted[index]);
    }
    final List<List<_Rule>> result = grouped.values.toList()
      ..sort(
        (List<_Rule> first, List<_Rule> second) =>
            _compareRules(first.first, second.first),
      );
    return result;
  }

  static bool _sameSpan(_Rule first, _Rule second, {required bool horizontal}) {
    if (horizontal) {
      return (first.x0 - second.x0).abs() <= _spanTolerancePx &&
          (first.x1 - second.x1).abs() <= _spanTolerancePx;
    }
    return (first.y0 - second.y0).abs() <= _spanTolerancePx &&
        (first.y1 - second.y1).abs() <= _spanTolerancePx;
  }

  static bool _gridCovers(
    List<_Rule> horizontals,
    List<_Rule> verticals,
    int left,
    int right,
    int top,
    int bottom,
  ) {
    final double tolerance = _cornerTolerancePx.toDouble();
    for (final _Rule vertical in verticals) {
      if (vertical.centerX < left - tolerance ||
          vertical.centerX > right + tolerance) {
        return false;
      }
      if (vertical.y0 > top + tolerance || vertical.y1 < bottom - tolerance) {
        return false;
      }
    }
    for (final _Rule horizontal in horizontals) {
      if (horizontal.centerY < top - tolerance ||
          horizontal.centerY > bottom + tolerance) {
        return false;
      }
      if (horizontal.x0 > left + tolerance ||
          horizontal.x1 < right - tolerance) {
        return false;
      }
    }

    bool hasTop = false;
    bool hasBottom = false;
    for (final _Rule horizontal in horizontals) {
      if ((horizontal.centerY - top).abs() <= tolerance) {
        hasTop = true;
      }
      if ((horizontal.centerY - bottom).abs() <= tolerance) {
        hasBottom = true;
      }
    }
    bool hasLeft = false;
    bool hasRight = false;
    for (final _Rule vertical in verticals) {
      if ((vertical.centerX - left).abs() <= tolerance) {
        hasLeft = true;
      }
      if ((vertical.centerX - right).abs() <= tolerance) {
        hasRight = true;
      }
    }
    return hasTop && hasBottom && hasLeft && hasRight;
  }

  static _BoxDetection _detectBoxes(
    List<_Rule> rules,
    _InkMask mask,
    RasterAnalysis analysis,
    Set<_Rule> gridRules,
  ) {
    final List<_Rule> horizontals =
        rules.where((_Rule rule) => rule.horizontal).toList()
          ..sort(_compareRuleCenterY);
    final List<_Rule> verticals =
        rules.where((_Rule rule) => !rule.horizontal).toList()
          ..sort(_compareRuleCenterX);
    final List<_RawCandidate> candidates = <_RawCandidate>[];
    final Set<_Rule> consumed = <_Rule>{};

    for (int topIndex = 0; topIndex < horizontals.length; topIndex++) {
      for (
        int bottomIndex = topIndex + 1;
        bottomIndex < horizontals.length;
        bottomIndex++
      ) {
        final _Rule top = horizontals[topIndex];
        final _Rule bottom = horizontals[bottomIndex];
        if (bottom.centerY <= top.centerY ||
            bottom.y0 - top.y1 < _minInteriorSidePx) {
          continue;
        }
        for (int leftIndex = 0; leftIndex < verticals.length; leftIndex++) {
          for (
            int rightIndex = leftIndex + 1;
            rightIndex < verticals.length;
            rightIndex++
          ) {
            final _Rule left = verticals[leftIndex];
            final _Rule right = verticals[rightIndex];
            if (right.centerX <= left.centerX ||
                right.x0 - left.x1 < _minInteriorSidePx) {
              continue;
            }
            if (!_cornersAgree(top, bottom, left, right)) {
              continue;
            }
            final PixelRect? interior = _pixelRect(
              left.x1,
              top.y1,
              right.x0,
              bottom.y0,
              mask,
            );
            if (interior == null) {
              continue;
            }

            consumed.addAll(<_Rule>{top, bottom, left, right});
            final int outerLeft = _minInt(
              _minInt(top.x0, bottom.x0),
              _minInt(left.x0, right.x0),
            );
            final int outerRight = _maxInt(
              _maxInt(top.x1, bottom.x1),
              _maxInt(left.x1, right.x1),
            );
            final int outerTop = _minInt(
              _minInt(top.y0, bottom.y0),
              _minInt(left.y0, right.y0),
            );
            final int outerBottom = _maxInt(
              _maxInt(top.y1, bottom.y1),
              _maxInt(left.y1, right.y1),
            );
            if (outerRight - outerLeft >= mask.width * 0.9 &&
                outerBottom - outerTop >= mask.height * 0.9) {
              continue;
            }
            if (_containsGridLine(interior, gridRules)) {
              continue;
            }

            final InkCoverage coverage = analysis.inkCoverage(interior);
            final bool smallSquare = _isSmallSquare(
              outerRight - outerLeft,
              outerBottom - outerTop,
              coverage,
            );
            if (coverage.exceedsPercent(_maxInkPercent) && !smallSquare) {
              continue;
            }
            candidates.add(
              _RawCandidate(
                pixelRect: interior,
                cues: <String>{'box', if (smallSquare) 'small_square'},
                inkCoverage: coverage.fraction,
                sideRules: <_Rule>{top, bottom, left, right},
              ),
            );
          }
        }
      }
    }
    return _BoxDetection(candidates, consumed);
  }

  static bool _cornersAgree(_Rule top, _Rule bottom, _Rule left, _Rule right) {
    final double tolerance = _cornerTolerancePx.toDouble();
    return (top.x0 - left.centerX).abs() <= tolerance &&
        (top.x1 - right.centerX).abs() <= tolerance &&
        (bottom.x0 - left.centerX).abs() <= tolerance &&
        (bottom.x1 - right.centerX).abs() <= tolerance &&
        (left.y0 - top.centerY).abs() <= tolerance &&
        (left.y1 - bottom.centerY).abs() <= tolerance &&
        (right.y0 - top.centerY).abs() <= tolerance &&
        (right.y1 - bottom.centerY).abs() <= tolerance;
  }

  static bool _containsGridLine(PixelRect interior, Set<_Rule> gridRules) {
    for (final _Rule rule in gridRules) {
      if (rule.centerX > interior.left &&
          rule.centerX < interior.right &&
          rule.centerY > interior.top &&
          rule.centerY < interior.bottom) {
        return true;
      }
    }
    return false;
  }

  static bool _isSmallSquare(
    int outerWidthPx,
    int outerHeightPx,
    InkCoverage coverage,
  ) {
    return _hasSmallSquareGeometry(outerWidthPx, outerHeightPx) &&
        !coverage.exceedsPercent(_smallSquareMaxInkPercent);
  }

  static bool _hasSmallSquareGeometry(int widthPx, int heightPx) {
    final double width = widthPx / rasterScale;
    final double height = heightPx / rasterScale;
    if (width < _smallSquareMinSidePt ||
        width > _smallSquareMaxSidePt ||
        height < _smallSquareMinSidePt ||
        height > _smallSquareMaxSidePt) {
      return false;
    }
    final double smaller = width < height ? width : height;
    final double larger = width > height ? width : height;
    return larger / smaller <= _smallSquareMaxAspect;
  }

  static List<_RawCandidate> _detectUnderlines(
    List<_Rule> rules,
    _InkMask mask,
    RasterAnalysis analysis,
    Set<_Rule> consumed,
  ) {
    final List<_RawCandidate> candidates = <_RawCandidate>[];
    for (final _Rule rule in rules) {
      if (!rule.horizontal ||
          consumed.contains(rule) ||
          _isPageBorderRule(rule, mask) ||
          rule.width < _minUnderlineLengthPx) {
        continue;
      }
      final int bandTop = rule.y0 - _underlineBandHeightPx;
      if (bandTop < 0) {
        continue;
      }
      final PixelRect band = PixelRect(
        left: rule.x0,
        top: bandTop,
        width: rule.width,
        height: _underlineBandHeightPx,
      );
      final InkCoverage coverage = analysis.inkCoverage(band);
      if (coverage.exceedsPercent(_maxInkPercent)) {
        continue;
      }
      candidates.add(
        _RawCandidate(
          pixelRect: band,
          cues: const <String>{'underline'},
          inkCoverage: coverage.fraction,
          sideRules: <_Rule>{rule},
        ),
      );
    }
    return candidates;
  }

  static List<_RawCandidate> _detectWhitespace(
    _InkMask mask,
    RasterAnalysis analysis,
  ) {
    final int pixelCount = mask.width * mask.height;
    final Uint8List visited = Uint8List(pixelCount);
    // Queue entries are linear pixel indices `y * width + x`. Packing y and x
    // into 16-bit lanes overflowed for rasters taller than 32767 px, which the
    // supported 40,000 px extent allows; the linear index stays below
    // `maxRasterPixels` (1.6e9) and therefore fits a signed 32-bit cell.
    final Int32List queue = Int32List(pixelCount);
    final List<_RawCandidate> candidates = <_RawCandidate>[];

    for (int y = 0; y < mask.height; y++) {
      for (int x = 0; x < mask.width; x++) {
        final int start = y * mask.width + x;
        if (mask.ink[start] != 0 || visited[start] != 0) {
          continue;
        }

        int head = 0;
        int tail = 0;
        queue[tail++] = start;
        visited[start] = 1;
        int minX = x;
        int maxX = x;
        int minY = y;
        int maxY = y;
        int area = 0;
        bool touchesBorder = false;
        bool adjacentInk = false;

        void visit(int nextX, int nextY) {
          if (nextX < 0 ||
              nextY < 0 ||
              nextX >= mask.width ||
              nextY >= mask.height) {
            return;
          }
          final int index = nextY * mask.width + nextX;
          if (mask.ink[index] != 0) {
            adjacentInk = true;
            return;
          }
          if (visited[index] != 0) {
            return;
          }
          visited[index] = 1;
          queue[tail++] = index;
        }

        while (head < tail) {
          final int current = queue[head++];
          final int currentX = current % mask.width;
          final int currentY = current ~/ mask.width;
          area++;
          if (currentX < minX) {
            minX = currentX;
          }
          if (currentX > maxX) {
            maxX = currentX;
          }
          if (currentY < minY) {
            minY = currentY;
          }
          if (currentY > maxY) {
            maxY = currentY;
          }
          if (currentX == 0 ||
              currentY == 0 ||
              currentX == mask.width - 1 ||
              currentY == mask.height - 1) {
            touchesBorder = true;
          }
          visit(currentX - 1, currentY);
          visit(currentX + 1, currentY);
          visit(currentX, currentY - 1);
          visit(currentX, currentY + 1);
        }

        if (touchesBorder || !adjacentInk) {
          continue;
        }
        final int width = maxX - minX + 1;
        final int height = maxY - minY + 1;
        if (width < _minWhitespaceSidePx ||
            height < _minWhitespaceSidePx ||
            area < _minWhitespaceAreaPx) {
          continue;
        }
        final int boxArea = width * height;
        if (boxArea > _maxWhitespaceAreaFraction * pixelCount) {
          continue;
        }
        final PixelRect rect = PixelRect.fromLTRB(
          minX,
          minY,
          maxX + 1,
          maxY + 1,
        );
        final InkCoverage coverage = analysis.inkCoverage(rect);
        if (coverage.exceedsPercent(_maxInkPercent)) {
          continue;
        }
        candidates.add(
          _RawCandidate(
            pixelRect: rect,
            cues: const <String>{'whitespace'},
            inkCoverage: coverage.fraction,
            sideRules: const <_Rule>{},
          ),
        );
      }
    }
    return candidates;
  }

  static List<_Accumulator> _merge(
    List<_RawCandidate> raw,
    double pageWidthPt,
    double pageHeightPt,
  ) {
    final Map<String, _Accumulator> byRect = <String, _Accumulator>{};
    for (final _RawCandidate candidate in raw) {
      final DisplayRect? rect = _toDisplay(
        candidate.pixelRect,
        pageWidthPt,
        pageHeightPt,
      );
      if (rect == null) {
        continue;
      }
      final int keyX = (rect.x * 8).round();
      final int keyY = (rect.y * 8).round();
      final int keyWidth = (rect.width * 8).round();
      final int keyHeight = (rect.height * 8).round();
      final String key = '$keyX,$keyY,$keyWidth,$keyHeight';
      final _Accumulator? existing = byRect[key];
      if (existing == null) {
        byRect[key] = _Accumulator(rect)..add(candidate);
      } else {
        existing.add(candidate);
      }
    }
    return byRect.values.toList();
  }

  static void _applyAlignment(
    List<_Accumulator> candidates,
    List<_Rule> rules,
    _InkMask mask,
  ) {
    final List<_Rule> verticalRules = rules
        .where(
          (_Rule rule) => !rule.horizontal && !_isPageBorderRule(rule, mask),
        )
        .toList();
    for (final _Accumulator candidate in candidates) {
      int alignedLeftEdges = 0;
      for (final _Accumulator other in candidates) {
        if (identical(candidate, other)) {
          continue;
        }
        if ((candidate.rect.x - other.rect.x).abs() <=
            _alignmentTolerancePt + 1e-9) {
          alignedLeftEdges++;
          if (alignedLeftEdges >= 2) {
            break;
          }
        }
      }
      if (alignedLeftEdges >= 2) {
        candidate.cues.add('alignment_left');
        continue;
      }
      for (final _Rule rule in verticalRules) {
        if (candidate.sideRules.contains(rule)) {
          continue;
        }
        final double ruleX = rule.centerX / rasterScale;
        if ((ruleX - candidate.rect.x).abs() <= _alignmentTolerancePt + 1e-9) {
          candidate.cues.add('alignment_left');
          break;
        }
      }
    }
  }

  static DisplayRect? _toDisplay(
    PixelRect pixel,
    double pageWidthPt,
    double pageHeightPt,
  ) {
    final double maxX = _inwardPageExtent(pageWidthPt);
    final double maxY = _inwardPageExtent(pageHeightPt);
    final double left = _clampToPage(
      _roundToEighth(pixelEdgeToPoint(pixel.left)),
      maxX,
    );
    final double top = _clampToPage(
      _roundToEighth(pixelEdgeToPoint(pixel.top)),
      maxY,
    );
    final double right = _clampToPage(
      _roundToEighth(pixelEdgeToPoint(pixel.right)),
      maxX,
    );
    final double bottom = _clampToPage(
      _roundToEighth(pixelEdgeToPoint(pixel.bottom)),
      maxY,
    );
    final double width = right - left;
    final double height = bottom - top;
    if (!(width > 0) || !(height > 0)) {
      return null;
    }
    return DisplayRect(x: left, y: top, width: width, height: height);
  }

  static double _roundToEighth(double value) => (value * 8).round() / 8;

  /// Largest 1/8 pt multiple that does not exceed [pageExtent].
  ///
  /// Clamping inward rather than to the exact extent keeps rounded edges on
  /// the 1/8 pt lattice when the page size itself is not a 1/8 pt multiple.
  static double _inwardPageExtent(double pageExtent) =>
      (pageExtent * 8).floor() / 8;

  static double _clampToPage(double value, double pageExtent) {
    if (value <= 0) {
      return 0;
    }
    if (value >= pageExtent) {
      return pageExtent;
    }
    return value;
  }

  static bool _isPageBorderRule(_Rule rule, _InkMask mask) {
    const int margin = _maxRuleThicknessPx * 2;
    if (rule.horizontal) {
      return rule.width >= mask.width * 0.9 &&
          (rule.y1 <= margin || rule.y0 >= mask.height - margin);
    }
    return rule.height >= mask.height * 0.9 &&
        (rule.x1 <= margin || rule.x0 >= mask.width - margin);
  }

  static PixelRect? _pixelRect(
    int left,
    int top,
    int right,
    int bottom,
    _InkMask mask,
  ) {
    if (right <= left ||
        bottom <= top ||
        left < 0 ||
        top < 0 ||
        right > mask.width ||
        bottom > mask.height) {
      return null;
    }
    return PixelRect.fromLTRB(left, top, right, bottom);
  }

  static int _medianInt(List<int> values) {
    final List<int> sorted = List<int>.of(values)..sort();
    return sorted[sorted.length ~/ 2];
  }

  static int _compareCandidates(
    GeometryCandidate first,
    GeometryCandidate second,
  ) {
    int result = first.rect.y.compareTo(second.rect.y);
    if (result != 0) {
      return result;
    }
    result = first.rect.x.compareTo(second.rect.x);
    if (result != 0) {
      return result;
    }
    result = first.rect.height.compareTo(second.rect.height);
    if (result != 0) {
      return result;
    }
    result = first.rect.width.compareTo(second.rect.width);
    if (result != 0) {
      return result;
    }
    return _compareCueLists(first.cues, second.cues);
  }

  static int _compareCueLists(List<String> first, List<String> second) {
    final int length = first.length < second.length
        ? first.length
        : second.length;
    for (int index = 0; index < length; index++) {
      final int result = first[index].compareTo(second[index]);
      if (result != 0) {
        return result;
      }
    }
    return first.length.compareTo(second.length);
  }

  static int _compareRules(_Rule first, _Rule second) {
    int result = (first.horizontal ? 0 : 1).compareTo(
      second.horizontal ? 0 : 1,
    );
    if (result != 0) {
      return result;
    }
    result = first.x0.compareTo(second.x0);
    if (result != 0) {
      return result;
    }
    result = first.y0.compareTo(second.y0);
    if (result != 0) {
      return result;
    }
    result = first.x1.compareTo(second.x1);
    if (result != 0) {
      return result;
    }
    return first.y1.compareTo(second.y1);
  }

  static int _compareRuleCenterX(_Rule first, _Rule second) {
    final int result = first.centerX.compareTo(second.centerX);
    if (result != 0) {
      return result;
    }
    return _compareRules(first, second);
  }

  static int _compareRuleCenterY(_Rule first, _Rule second) {
    final int result = first.centerY.compareTo(second.centerY);
    if (result != 0) {
      return result;
    }
    return _compareRules(first, second);
  }

  static int _minInt(int first, int second) => first < second ? first : second;

  static int _maxInt(int first, int second) => first > second ? first : second;
}

/// One half-open pixel rectangle plus detector evidence.
final class _RawCandidate {
  _RawCandidate({
    required this.pixelRect,
    required Set<String> cues,
    required this.inkCoverage,
    required Set<_Rule> sideRules,
  }) : cues = Set<String>.of(cues),
       sideRules = Set<_Rule>.of(sideRules);

  final PixelRect pixelRect;
  final Set<String> cues;
  final double inkCoverage;
  final Set<_Rule> sideRules;
}

/// One merged rounded rectangle.
final class _Accumulator {
  _Accumulator(this.rect);

  final DisplayRect rect;
  final Set<String> cues = <String>{};
  final Set<_Rule> sideRules = <_Rule>{};
  double coverage = 0;

  void add(_RawCandidate candidate) {
    cues.addAll(candidate.cues);
    sideRules.addAll(candidate.sideRules);
    if (candidate.inkCoverage > coverage) {
      coverage = candidate.inkCoverage;
    }
  }
}

final class _GridDetection {
  _GridDetection(this.candidates, this.rules);

  final List<_RawCandidate> candidates;
  final Set<_Rule> rules;
}

final class _BoxDetection {
  _BoxDetection(this.candidates, this.rules);

  final List<_RawCandidate> candidates;
  final Set<_Rule> rules;
}

/// One ruling-line rectangle in half-open raster pixels.
final class _Rule {
  const _Rule({
    required this.horizontal,
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
  });

  final bool horizontal;
  final int x0;
  final int y0;
  final int x1;
  final int y1;

  int get width => x1 - x0;
  int get height => y1 - y0;
  double get centerX => (x0 + x1) / 2;
  double get centerY => (y0 + y1) / 2;

  @override
  String toString() => '_Rule(${horizontal ? 'H' : 'V'} $x0,$y0..$x1,$y1)';
}

/// One consecutive ink run on a scan line.
final class _Run {
  const _Run(this.line, this.start, this.end);

  final int line;
  final int start;
  final int end;
}

/// A vertically connected group of overlapping runs.
final class _RunGroup {
  _RunGroup(this.firstLine, this.lastLine, this.start, this.end);

  final int firstLine;
  int lastLine;
  int start;
  int end;

  bool overlaps(int otherStart, int otherEnd) {
    return start < otherEnd && otherStart < end;
  }

  void extend(int otherStart, int otherEnd, int line) {
    if (otherStart < start) {
      start = otherStart;
    }
    if (otherEnd > end) {
      end = otherEnd;
    }
    lastLine = line;
  }
}

/// The binary ink mask built once per detection call.
final class _InkMask {
  _InkMask._(this.width, this.height, this.ink);

  factory _InkMask.from(RasterAnalysis analysis) {
    final GrayRaster raster = analysis.raster;
    final Uint8List pixels = raster.pixels;
    final Uint8List ink = Uint8List(raster.pixelCount);
    for (int index = 0; index < ink.length; index++) {
      if (pixels[index] < analysis.inkThreshold) {
        ink[index] = 1;
      }
    }
    return _InkMask._(raster.width, raster.height, ink);
  }

  final int width;
  final int height;
  final Uint8List ink;

  bool isInk(int x, int y) => ink[y * width + x] != 0;
}
