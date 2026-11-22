// Geometry-first field inventory over existing T052 detection output (T264).
//
// Normative sources:
//  * `specs/001-scanned-form-workflow/spec.md` FR-011, FR-013, FR-014, FR-016;
//  * `specs/001-scanned-form-workflow/contracts/recognition-output.md`
//    sections 2, 2.1, 3.1;
//  * `specs/001-scanned-form-workflow/contracts/coordinates-and-geometry.md`
//    sections 1 and 4.
//
// Scope. This library turns the T052 `GeometryCandidate` list of one page into
// one *inventory*: a deterministic, deduplicated, typed-by-geometry view of the
// page's fill regions. It does not detect (T052 owns the raster rules), does not
// type from OCR labels (T053 owns label proximity typing), does not score
// confidence (T054), and does not resolve conflicts (T055). It adds no second
// recognition pipeline, no raster pass, no port, and no I/O.
//
// What "candidate" means. An inventory entry is evidence, not a confirmed
// field. A larger empty rectangle or an underline is a *candidate* because it
// is geometrically consistent with an input region; it is never promoted to a
// field by its size alone. Callers must keep treating every entry as
// unconfirmed (FR-015).
//
// Kind classification (fixed order, first match wins):
//  1. `small_square` -> `checkbox`. An interior side below
//     `minCheckboxSidePt` (4 pt) is a glyph counter (`letterInterior`), not a
//     checkbox, and is excluded. Ink above `filledInkFraction` (12 %, the
//     contract's printed/filled ink gate) means the box is already marked: it
//     stays an entry with role `filledRegion` and is never offered as an empty
//     input. An empty box measures 0 % ink, a hand-drawn cross about 10-20 %.
//  2. `table_cell` or `grid_cell` -> `tableField`.
//  3. `signature_area` -> `signature`.
//  4. `date_context` -> `date`.
//  5. pure `underline` (no box/whitespace/grid cue) -> `text` (single-line band
//     above the rule).
//  6. `whitespace`/`box`/`alignment_left` only -> `multiline` when the height is
//     at least `multilineHeightRatio` (1.8) times the page's single-line
//     reference height, else `text`.
//  7. otherwise `unknown`, flagged `ambiguousKind` for review.
// The reference height is the median height of the underline bands on the page
// when any exist, otherwise the median height of all candidates, otherwise
// `defaultSingleLineMedianHeightPt` (18 pt). It is a diagnostic, not a field.
//
// Type hints. The existing pipeline's own typing stage (T053) may supply
// [FieldTypeHint]s for candidate rectangles. A hint only refines the kind of a
// rectangle whose geometry is already established; it never creates, moves, or
// removes a candidate. This is how an explicitly numeric input (`number`)
// becomes visible, because number-ness is not a geometric property. A hint that
// contradicts a `small_square`/`table_cell` cue is not applied: the entry keeps
// the geometric kind and is flagged `ambiguousKind` instead, so no type is
// silently corrected. A hint token outside the closed suggestion vocabulary is
// ignored.
//
// Deduplication. Exact and near-exact duplicates are collapsed before typing:
// two regions with `IoU >= nearDuplicateIou` (0.98) are the same place, which
// happens when the detector reports both a box interior and the bounded
// whitespace inside it. The representative is chosen deterministically (more
// cues, then larger area, then earlier lattice order) and receives the union of
// both cue sets and the larger measured ink coverage. Near-duplicates below
// that threshold are never collapsed; they are reported as `overlapping` or
// `nested` relations so a reviewer sees them. No field is dropped to reach a
// count. The collapse runs on unclassified slots, so there is no
// structural-region exemption in it: roles (including the decorative-frame and
// print-margin exclusions) are assigned after the collapse, by `_classify`.
//
// Explicit non-fields:
//  * a region wholly inside a `printMarginPt` band of a page edge is a print
//    margin (`printMargin`) and is excluded;
//  * a region spanning at least `decorativeSpanFraction` of both page axes, or
//    at least `decorativeAreaFraction` of the page area, is a decorative frame
//    (`decorativeFrame`) and is excluded;
//  * a glyph counter is a `letterInterior` and is excluded.
// These are recorded as [FieldInventoryExclusion] diagnostics with their
// rectangle, never silently dropped.
//
// Explicit review-only states:
//  * an empty table cell in the topmost grid row is flagged `tableHeaderRow`.
//    It is still a field candidate because the detector's ink gate has already
//    removed printed heading cells; the flag exists so a reviewer can check it;
//  * a field candidate with no credible label within `labelMaxGapPt` is flagged
//    `noLabelContext`;
//  * overlapping and nested candidates are flagged and listed as relations.
//
// Determinism. The output depends only on the candidate list, the page metrics,
// the optional label observations, and the configuration. Ordering is the
// documented lattice order (y, x, height, width, kind ordinal, cues, id). Equal
// input produces an equal inventory.
library;

import 'dart:math' as math;

import 'geometry_detector.dart';
import 'geometry_metrics.dart';
import 'type_inference.dart';

/// The geometric kind of one inventory entry.
enum FieldInventoryKind {
  /// Bounded near-square empty region in the 4-20 pt range.
  checkbox,

  /// Single-line text input candidate (underline or one-line empty region).
  text,

  /// Numeric input candidate, taken from the existing pipeline's typing hint.
  number,

  /// Multi-line input candidate (tall empty region).
  multiline,

  /// Date input candidate (German date mask in the label context).
  date,

  /// Signature area candidate.
  signature,

  /// Addressable cell of a detected table grid.
  tableField,

  /// Geometry is consistent with an input region of no known kind.
  unknown,
}

/// The contractual wire name of one inventory kind.
extension FieldInventoryKindWire on FieldInventoryKind {
  /// Stable, non-localised token used in reports and benchmark JSON.
  String get wireName => switch (this) {
    FieldInventoryKind.checkbox => 'checkbox',
    FieldInventoryKind.text => 'text',
    FieldInventoryKind.number => 'number',
    FieldInventoryKind.multiline => 'multiline',
    FieldInventoryKind.date => 'date',
    FieldInventoryKind.signature => 'signature',
    FieldInventoryKind.tableField => 'table_field',
    FieldInventoryKind.unknown => 'unknown',
  };

  /// The role-ordered ordinal used for deterministic sorting.
  int get ordinal => index;
}

/// What an entry may be used for.
enum InventoryRole {
  /// Empty input region that a later stage may propose (still unconfirmed).
  fieldCandidate,

  /// Bounded region that is part of the page's printed structure.
  structuralRegion,

  /// Region whose ink shows it is already filled or marked.
  filledRegion,
}

/// Why an input candidate is not an inventory entry.
enum InventoryExclusionReason {
  /// The rectangle is not representable inside the page.
  outsidePage,

  /// The region lies wholly inside a print-margin band.
  printMargin,

  /// The region spans the page like a decorative frame.
  decorativeFrame,

  /// The region is a glyph counter inside printed text.
  letterInterior,

  /// The region is a near-identical duplicate of another region.
  duplicateGeometry,
}

/// How two inventory entries relate spatially.
enum InventoryRelationKind {
  /// Closer than 2 pt on one axis without overlapping.
  adjacent,

  /// Overlapping but not near-identical: `0.5 <= IoU < 0.98`.
  overlapping,

  /// One region contains at least 60 % of the other, without near-identity.
  nested,
}

/// A review flag that never changes an entry's role.
enum InventoryReviewFlag {
  /// An empty cell in the topmost detected grid row.
  tableHeaderRow,

  /// No credible label context was found near the candidate.
  noLabelContext,

  /// The geometric cues do not determine one kind.
  ambiguousKind,

  /// The entry participates in an overlapping or nested relation.
  overlappingCandidates,
}

/// Tuning for [FieldInventoryBuilder].
///
/// Every value is a documented, pre-declared constant of this library. Callers
/// may override it for a controlled experiment, but the production path uses
/// [FieldInventoryConfig.production].
final class FieldInventoryConfig {
  /// Creates a configuration.
  const FieldInventoryConfig({
    this.printMarginPt = 18,
    this.minCheckboxSidePt = 4,
    this.maxCheckboxSidePt = 20,
    this.maxCheckboxAspect = 1.25,
    this.filledInkFraction = 0.12,
    this.decorativeSpanFraction = 0.8,
    this.decorativeAreaFraction = 0.25,
    this.minLetterInteriorSidePt = 6,
    this.multilineHeightRatio = 1.8,
    this.nearDuplicateIou = 0.98,
    this.overlapIou = 0.5,
    this.nestedContainment = 0.6,
    this.adjacentGapPt = 2,
    this.alignmentTolerancePt = 1,
    this.labelMaxGapPt = 48,
  }) : assert(printMarginPt >= 0),
       assert(minCheckboxSidePt > 0),
       assert(maxCheckboxSidePt >= minCheckboxSidePt),
       assert(maxCheckboxAspect >= 1),
       assert(filledInkFraction > 0 && filledInkFraction <= 1),
       assert(decorativeSpanFraction > 0 && decorativeSpanFraction <= 1),
       assert(decorativeAreaFraction > 0 && decorativeAreaFraction <= 1),
       assert(nearDuplicateIou > overlapIou && nearDuplicateIou <= 1),
       assert(overlapIou > 0 && overlapIou < 1),
       assert(nestedContainment > 0 && nestedContainment <= 1);

  /// Width of the page-edge band that is treated as print margin.
  final double printMarginPt;

  /// Smallest interior side that can still be an empty checkbox.
  final double minCheckboxSidePt;

  /// Largest interior side of a checkbox candidate.
  final double maxCheckboxSidePt;

  /// Largest equal-side ratio of a checkbox candidate.
  final double maxCheckboxAspect;

  /// Interior ink fraction above which a checkbox counts as already marked.
  final double filledInkFraction;

  /// Page-axis fraction above which a region is a decorative frame.
  final double decorativeSpanFraction;

  /// Page-area fraction above which a region is a decorative frame.
  final double decorativeAreaFraction;

  /// Side below which a whitespace region is a glyph counter.
  final double minLetterInteriorSidePt;

  /// Height ratio that promotes a one-line region to `multiline`.
  final double multilineHeightRatio;

  /// IoU at or above which two regions collapse as the same place.
  final double nearDuplicateIou;

  /// IoU at or above which two regions count as overlapping.
  final double overlapIou;

  /// Containment fraction at or above which two regions count as nested.
  final double nestedContainment;

  /// Axis gap below which two non-overlapping regions count as adjacent.
  final double adjacentGapPt;

  /// Left-edge alignment tolerance.
  final double alignmentTolerancePt;

  /// Largest label gap that still provides label context.
  final double labelMaxGapPt;

  /// The production configuration; the only one the pipeline uses.
  static const FieldInventoryConfig production = FieldInventoryConfig();
}

/// One type hint supplied by the existing pipeline's own typing stage (T053).
///
/// The hint never moves a rectangle and never replaces a geometric cue: it only
/// refines the *kind* of a candidate whose geometry is already established. A
/// token outside the closed suggestion vocabulary is ignored, and a hint that
/// contradicts the `small_square`/`table_cell` geometry is recorded as an
/// ambiguity flag instead of being applied.
final class FieldTypeHint {
  /// Creates a type hint for [rect] with the suggestion-type token [proposedType].
  FieldTypeHint({required this.rect, required this.proposedType});

  /// The candidate rectangle the hint refers to (normalised before matching).
  final DisplayRect rect;

  /// One of `text`, `number`, `date`, `checkbox`, `multiline`, `signature`.
  final String proposedType;
}

/// One deduplicated inventory entry.
final class FieldInventoryEntry {
  FieldInventoryEntry._({
    required this.id,
    required this.pageIndex,
    required this.rect,
    required this.kind,
    required this.role,
    required List<String> cues,
    required this.inkCoverage,
    required List<String> evidence,
    required this.labelText,
    required List<InventoryReviewFlag> reviewFlags,
    required this.collapsedDuplicateCount,
  }) : cues = List<String>.unmodifiable(cues.toSet().toList()..sort()),
       evidence = List<String>.unmodifiable(evidence.toSet().toList()..sort()),
       reviewFlags = List<InventoryReviewFlag>.unmodifiable(
         reviewFlags.toSet().toList()..sort(
           (InventoryReviewFlag a, InventoryReviewFlag b) =>
               a.index.compareTo(b.index),
         ),
       );

  /// Stable id `g_p<page>_<ordinal>`; assigned after the deterministic sort.
  final String id;

  /// Zero-based page index.
  final int pageIndex;

  /// Normalised display-space rectangle inside the page.
  final DisplayRect rect;

  /// Geometric kind.
  final FieldInventoryKind kind;

  /// Role of the entry in the page structure.
  final InventoryRole role;

  /// Sorted, unique cue tokens inherited from the detector.
  final List<String> cues;

  /// Measured interior ink fraction of the underlying candidate.
  final double inkCoverage;

  /// Sorted, unique diagnostic tokens that explain the classification.
  final List<String> evidence;

  /// Nearest credible label context, trimmed; `null` when there is none.
  final String? labelText;

  /// Sorted, unique review flags.
  final List<InventoryReviewFlag> reviewFlags;

  /// Number of near-identical candidates collapsed into this entry.
  final int collapsedDuplicateCount;

  /// Whether this entry may be proposed as an input region.
  bool get isFieldCandidate => role == InventoryRole.fieldCandidate;

  /// Whether this entry is already filled or marked.
  bool get isFilledRegion => role == InventoryRole.filledRegion;

  /// Whether this entry is part of the printed page structure.
  bool get isStructuralRegion => role == InventoryRole.structuralRegion;

  /// Whether a reviewer must look at this entry.
  bool get needsReview => reviewFlags.isNotEmpty;

  @override
  String toString() =>
      'FieldInventoryEntry($id, ${kind.wireName}, $rect, role: $role.name)';
}

/// One region that the inventory deliberately did not turn into an entry.
final class FieldInventoryExclusion {
  FieldInventoryExclusion._({
    required this.rect,
    required this.reason,
    required List<String> cues,
    required this.inkCoverage,
  }) : cues = List<String>.unmodifiable(cues.toSet().toList()..sort());

  /// Normalised display-space rectangle of the excluded region.
  final DisplayRect rect;

  /// Why the region is not a field.
  final InventoryExclusionReason reason;

  /// Sorted, unique cue tokens of the excluded candidate.
  final List<String> cues;

  /// Measured interior ink fraction of the excluded candidate.
  final double inkCoverage;

  @override
  String toString() => 'FieldInventoryExclusion(${reason.name}, $rect)';
}

/// One spatial relation between two entries.
final class FieldInventoryRelation {
  const FieldInventoryRelation._({
    required this.kind,
    required this.firstId,
    required this.secondId,
    required this.iou,
    required this.gapPt,
  });

  /// Relation kind.
  final InventoryRelationKind kind;

  /// Lexicographically smaller entry id.
  final String firstId;

  /// Lexicographically larger entry id.
  final String secondId;

  /// IoU of the two entries.
  final double iou;

  /// Smallest axis gap in display points; `0.0` when overlapping.
  final double gapPt;

  @override
  String toString() =>
      'FieldInventoryRelation(${kind.name}, $firstId, $secondId)';
}

/// Structural coverage counters that prove which categories were examined.
final class FieldInventoryCoverage {
  const FieldInventoryCoverage._({
    required this.candidatesIn,
    required this.entriesOut,
    required this.deduplicatedCount,
    required this.printMarginRejections,
    required this.decorativeFrameRejections,
    required this.letterInteriorRejections,
    required this.outsidePageRejections,
    required this.filledRegions,
    required this.structuralRegions,
    required this.tableHeaderRowCells,
    required this.adjacentPairs,
    required this.overlappingPairs,
    required this.nestedPairs,
    required this.unlabelledFieldCandidates,
    required this.ambiguousKindCandidates,
  });

  /// Number of detector candidates supplied.
  final int candidatesIn;

  /// Number of deduplicated entries produced.
  final int entriesOut;

  /// Number of near-identical candidates collapsed.
  final int deduplicatedCount;

  /// Regions excluded as print margin.
  final int printMarginRejections;

  /// Regions excluded as decorative frames.
  final int decorativeFrameRejections;

  /// Regions excluded as glyph counters.
  final int letterInteriorRejections;

  /// Regions rejected as not representable inside the page.
  final int outsidePageRejections;

  /// Entries that are already filled or marked.
  final int filledRegions;

  /// Entries that are part of the printed structure.
  final int structuralRegions;

  /// Empty cells in the topmost grid row that were flagged.
  final int tableHeaderRowCells;

  /// Adjacent entry pairs.
  final int adjacentPairs;

  /// Overlapping entry pairs.
  final int overlappingPairs;

  /// Nested entry pairs.
  final int nestedPairs;

  /// Field candidates without credible label context.
  final int unlabelledFieldCandidates;

  /// Field candidates whose geometric kind is undetermined.
  final int ambiguousKindCandidates;

  /// The same counters as a report-ready map.
  Map<String, int> toJson() => <String, int>{
    'candidatesIn': candidatesIn,
    'entriesOut': entriesOut,
    'deduplicatedCount': deduplicatedCount,
    'printMarginRejections': printMarginRejections,
    'decorativeFrameRejections': decorativeFrameRejections,
    'letterInteriorRejections': letterInteriorRejections,
    'outsidePageRejections': outsidePageRejections,
    'filledRegions': filledRegions,
    'structuralRegions': structuralRegions,
    'tableHeaderRowCells': tableHeaderRowCells,
    'adjacentPairs': adjacentPairs,
    'overlappingPairs': overlappingPairs,
    'nestedPairs': nestedPairs,
    'unlabelledFieldCandidates': unlabelledFieldCandidates,
    'ambiguousKindCandidates': ambiguousKindCandidates,
  };
}

/// The deduplicated, typed-by-geometry inventory of one page.
final class FieldInventory {
  FieldInventory._({
    required this.pageIndex,
    required this.pageWidthPt,
    required this.pageHeightPt,
    required List<FieldInventoryEntry> entries,
    required List<FieldInventoryExclusion> exclusions,
    required List<FieldInventoryRelation> relations,
    required this.coverage,
  }) : entries = List<FieldInventoryEntry>.unmodifiable(entries),
       exclusions = List<FieldInventoryExclusion>.unmodifiable(exclusions),
       relations = List<FieldInventoryRelation>.unmodifiable(relations);

  /// Zero-based page index.
  final int pageIndex;

  /// Page width in display points.
  final double pageWidthPt;

  /// Page height in display points.
  final double pageHeightPt;

  /// All entries in deterministic lattice order.
  final List<FieldInventoryEntry> entries;

  /// Excluded regions in deterministic lattice order.
  final List<FieldInventoryExclusion> exclusions;

  /// Spatial relations in deterministic order.
  final List<FieldInventoryRelation> relations;

  /// Structural coverage counters.
  final FieldInventoryCoverage coverage;

  /// Entries that may be proposed as input regions.
  List<FieldInventoryEntry> get fieldCandidates =>
      List<FieldInventoryEntry>.unmodifiable(
        entries.where((FieldInventoryEntry entry) => entry.isFieldCandidate),
      );

  /// Entries that are already filled or marked.
  List<FieldInventoryEntry> get filledRegions =>
      List<FieldInventoryEntry>.unmodifiable(
        entries.where((FieldInventoryEntry entry) => entry.isFilledRegion),
      );

  /// Entries that are part of the printed page structure.
  List<FieldInventoryEntry> get structuralRegions =>
      List<FieldInventoryEntry>.unmodifiable(
        entries.where((FieldInventoryEntry entry) => entry.isStructuralRegion),
      );

  /// Field-candidate counts per kind, including zero counts.
  Map<FieldInventoryKind, int> get fieldCandidateCountsByKind {
    final Map<FieldInventoryKind, int> counts = <FieldInventoryKind, int>{
      for (final FieldInventoryKind kind in FieldInventoryKind.values) kind: 0,
    };
    for (final FieldInventoryEntry entry in fieldCandidates) {
      counts[entry.kind] = counts[entry.kind]! + 1;
    }
    return Map<FieldInventoryKind, int>.unmodifiable(counts);
  }

  /// A report-ready summary of this inventory.
  Map<String, Object?> toJson() => <String, Object?>{
    'pageIndex': pageIndex,
    'pageSizePt': <String, double>{
      'width': pageWidthPt,
      'height': pageHeightPt,
    },
    'coverage': coverage.toJson(),
    'entries': <Map<String, Object?>>[
      for (final FieldInventoryEntry entry in entries)
        <String, Object?>{
          'id': entry.id,
          'kind': entry.kind.wireName,
          'role': entry.role.name,
          'rect': <String, double>{
            'x': entry.rect.x,
            'y': entry.rect.y,
            'width': entry.rect.width,
            'height': entry.rect.height,
          },
          'cues': entry.cues,
          'inkCoverage': entry.inkCoverage,
          'evidence': entry.evidence,
          'labelText': entry.labelText,
          'reviewFlags': <String>[
            for (final InventoryReviewFlag flag in entry.reviewFlags) flag.name,
          ],
          'collapsedDuplicateCount': entry.collapsedDuplicateCount,
        },
    ],
    'exclusions': <Map<String, Object?>>[
      for (final FieldInventoryExclusion exclusion in exclusions)
        <String, Object?>{
          'reason': exclusion.reason.name,
          'rect': <String, double>{
            'x': exclusion.rect.x,
            'y': exclusion.rect.y,
            'width': exclusion.rect.width,
            'height': exclusion.rect.height,
          },
          'cues': exclusion.cues,
          'inkCoverage': exclusion.inkCoverage,
        },
    ],
    'relations': <Map<String, Object?>>[
      for (final FieldInventoryRelation relation in relations)
        <String, Object?>{
          'kind': relation.kind.name,
          'firstId': relation.firstId,
          'secondId': relation.secondId,
          'iou': relation.iou,
          'gapPt': relation.gapPt,
        },
    ],
  };
}

/// Builds a [FieldInventory] from existing detector output.
final class FieldInventoryBuilder {
  const FieldInventoryBuilder._();

  /// Builds the inventory of one page.
  ///
  /// [candidates] are the T052 geometry candidates of exactly one page.
  /// [labels] are optional OCR label observations (T053 output) used only as
  /// label context; they never change a rectangle, a kind, or a count.
  ///
  /// Throws a content-free [ArgumentError] for a negative page index, a
  /// non-finite page metric, or a candidate/label rectangle outside the page.
  static FieldInventory build({
    required int pageIndex,
    required double pageWidthPt,
    required double pageHeightPt,
    required List<GeometryCandidate> candidates,
    List<LabelObservation> labels = const <LabelObservation>[],
    List<FieldTypeHint> typeHints = const <FieldTypeHint>[],
    FieldInventoryConfig config = FieldInventoryConfig.production,
  }) {
    if (pageIndex < 0) {
      throw ArgumentError('page index must be non-negative');
    }
    if (!pageWidthPt.isFinite || !pageHeightPt.isFinite) {
      throw ArgumentError('page size must be finite');
    }
    if (pageWidthPt <= 0 || pageHeightPt <= 0) {
      throw ArgumentError('page size must be strictly positive');
    }
    for (final GeometryCandidate candidate in candidates) {
      if (!isInsidePage(
        candidate.rect,
        pageWidthPt: pageWidthPt,
        pageHeightPt: pageHeightPt,
      )) {
        throw ArgumentError('candidate rectangle is outside the page');
      }
    }
    for (final LabelObservation label in labels) {
      if (!isInsidePage(
        label.rect,
        pageWidthPt: pageWidthPt,
        pageHeightPt: pageHeightPt,
      )) {
        throw ArgumentError('label rectangle is outside the page');
      }
    }

    final List<FieldInventoryExclusion> exclusions =
        <FieldInventoryExclusion>[];
    int deduplicatedCount = 0;
    final List<_Slot> slots = _normalise(
      candidates,
      pageWidthPt: pageWidthPt,
      pageHeightPt: pageHeightPt,
      exclusions: exclusions,
      onExactDuplicate: () => deduplicatedCount++,
    );
    final List<_Slot> deduplicated = _collapseNearDuplicates(
      slots,
      config,
      onCollapse: (int count) => deduplicatedCount += count,
      exclusions: exclusions,
    );
    deduplicated.sort(_compareSlots);

    final double referenceHeight = _referenceLineHeight(deduplicated);
    final List<_Slot> classified = deduplicated;
    for (final _Slot slot in classified) {
      _classify(
        slot,
        pageWidthPt: pageWidthPt,
        pageHeightPt: pageHeightPt,
        referenceHeight: referenceHeight,
        config: config,
      );
    }
    _applyTypeHints(classified, typeHints);
    final List<_Slot> retained = <_Slot>[];
    for (final _Slot slot in classified) {
      if (slot.exclusion != null) {
        exclusions.add(
          FieldInventoryExclusion._(
            rect: slot.rect,
            reason: slot.exclusion!,
            cues: slot.cues.toList(),
            inkCoverage: slot.inkCoverage,
          ),
        );
      } else {
        retained.add(slot);
      }
    }

    _attachLabels(retained, labels, config);
    _flagTableHeaders(retained);

    // Final ids depend only on the deterministic order, so they are assigned
    // once here and shared by the relation list and the entries.
    retained.sort(_compareSlots);
    for (int index = 0; index < retained.length; index++) {
      retained[index].id =
          'g_p${pageIndex}_'
          '${index.toString().padLeft(4, '0')}';
    }
    final List<FieldInventoryRelation> relations = _relations(retained, config);

    final List<FieldInventoryEntry> entries = <FieldInventoryEntry>[
      for (final _Slot slot in retained)
        FieldInventoryEntry._(
          id: slot.id!,
          pageIndex: pageIndex,
          rect: slot.rect,
          kind: slot.kind,
          role: slot.role,
          cues: slot.cues.toList(),
          inkCoverage: slot.inkCoverage,
          evidence: slot.evidence.toList(),
          labelText: slot.labelText,
          reviewFlags: slot.reviewFlags.toList(),
          collapsedDuplicateCount: slot.collapsedDuplicateCount,
        ),
    ];
    exclusions.sort(_compareExclusions);
    relations.sort(_compareRelations);

    return FieldInventory._(
      pageIndex: pageIndex,
      pageWidthPt: pageWidthPt,
      pageHeightPt: pageHeightPt,
      entries: entries,
      exclusions: exclusions,
      relations: relations,
      coverage: _coverage(
        candidates: candidates.length,
        entries: entries,
        exclusions: exclusions,
        relations: relations,
        deduplicatedCount: deduplicatedCount,
      ),
    );
  }

  static void _applyTypeHints(List<_Slot> slots, List<FieldTypeHint> hints) {
    if (hints.isEmpty) {
      return;
    }
    final Map<String, String> byRect = <String, String>{};
    for (final FieldTypeHint hint in hints) {
      final DisplayRect? normalised = normalizeRect(hint.rect);
      if (normalised == null) {
        continue;
      }
      byRect.putIfAbsent(_rectKey(normalised), () => hint.proposedType);
    }
    for (final _Slot slot in slots) {
      final String? token = byRect[_rectKey(slot.rect)];
      if (token == null) {
        continue;
      }
      final FieldInventoryKind? hinted = fieldInventoryKindForSuggestionType(
        token,
      );
      if (hinted == null) {
        continue;
      }
      final bool geometryDecided =
          slot.cues.contains('small_square') ||
          slot.cues.contains('table_cell') ||
          slot.cues.contains('grid_cell');
      if (geometryDecided && hinted != slot.kind) {
        slot.reviewFlags.add(InventoryReviewFlag.ambiguousKind);
        slot.evidence.add('type_hint_conflict_$token');
        continue;
      }
      slot.kind = hinted;
      slot.evidence.add('type_hint_$token');
    }
  }

  static String _rectKey(DisplayRect rect) =>
      '${rect.x}:${rect.y}:${rect.width}:${rect.height}';

  static FieldInventoryCoverage _coverage({
    required int candidates,
    required List<FieldInventoryEntry> entries,
    required List<FieldInventoryExclusion> exclusions,
    required List<FieldInventoryRelation> relations,
    required int deduplicatedCount,
  }) {
    int count(InventoryExclusionReason reason) => exclusions
        .where(
          (FieldInventoryExclusion exclusion) => exclusion.reason == reason,
        )
        .length;
    int relation(InventoryRelationKind kind) => relations
        .where((FieldInventoryRelation relation) => relation.kind == kind)
        .length;
    return FieldInventoryCoverage._(
      candidatesIn: candidates,
      entriesOut: entries.length,
      deduplicatedCount: deduplicatedCount,
      printMarginRejections: count(InventoryExclusionReason.printMargin),
      decorativeFrameRejections: count(
        InventoryExclusionReason.decorativeFrame,
      ),
      letterInteriorRejections: count(InventoryExclusionReason.letterInterior),
      outsidePageRejections: count(InventoryExclusionReason.outsidePage),
      filledRegions: entries
          .where((FieldInventoryEntry entry) => entry.isFilledRegion)
          .length,
      structuralRegions: entries
          .where((FieldInventoryEntry entry) => entry.isStructuralRegion)
          .length,
      tableHeaderRowCells: entries
          .where(
            (FieldInventoryEntry entry) =>
                entry.reviewFlags.contains(InventoryReviewFlag.tableHeaderRow),
          )
          .length,
      adjacentPairs: relation(InventoryRelationKind.adjacent),
      overlappingPairs: relation(InventoryRelationKind.overlapping),
      nestedPairs: relation(InventoryRelationKind.nested),
      unlabelledFieldCandidates: entries
          .where(
            (FieldInventoryEntry entry) =>
                entry.isFieldCandidate && entry.labelText == null,
          )
          .length,
      ambiguousKindCandidates: entries
          .where(
            (FieldInventoryEntry entry) =>
                entry.reviewFlags.contains(InventoryReviewFlag.ambiguousKind),
          )
          .length,
    );
  }

  static List<_Slot> _normalise(
    List<GeometryCandidate> candidates, {
    required double pageWidthPt,
    required double pageHeightPt,
    required List<FieldInventoryExclusion> exclusions,
    required void Function() onExactDuplicate,
  }) {
    final Map<String, _Slot> byRect = <String, _Slot>{};
    for (final GeometryCandidate candidate in candidates) {
      final DisplayRect? normalised = normalizeRect(
        candidate.rect,
        pageWidthPt: pageWidthPt,
        pageHeightPt: pageHeightPt,
      );
      if (normalised == null) {
        exclusions.add(
          FieldInventoryExclusion._(
            rect: candidate.rect,
            reason: InventoryExclusionReason.outsidePage,
            cues: candidate.cues,
            inkCoverage: candidate.inkCoverage,
          ),
        );
        continue;
      }
      final String key =
          '${normalised.x}:${normalised.y}:'
          '${normalised.width}:${normalised.height}';
      final _Slot? existing = byRect[key];
      if (existing == null) {
        byRect[key] = _Slot(
          rect: normalised,
          cues: <String>{...candidate.cues},
          inkCoverage: candidate.inkCoverage,
        );
      } else {
        existing.cues.addAll(candidate.cues);
        existing.inkCoverage = math.max(
          existing.inkCoverage,
          candidate.inkCoverage,
        );
        existing.collapsedDuplicateCount++;
        onExactDuplicate();
      }
    }
    return byRect.values.toList();
  }

  static List<_Slot> _collapseNearDuplicates(
    List<_Slot> slots,
    FieldInventoryConfig config, {
    required void Function(int count) onCollapse,
    required List<FieldInventoryExclusion> exclusions,
  }) {
    slots.sort(_compareSlots);
    final List<_Slot> kept = <_Slot>[];
    for (final _Slot slot in slots) {
      _Slot? representative;
      for (final _Slot candidate in kept) {
        if (iou(candidate.rect, slot.rect) >= config.nearDuplicateIou) {
          representative = candidate;
          break;
        }
      }
      if (representative == null) {
        kept.add(slot);
        continue;
      }
      representative.cues.addAll(slot.cues);
      representative.inkCoverage = math.max(
        representative.inkCoverage,
        slot.inkCoverage,
      );
      representative.collapsedDuplicateCount +=
          1 + slot.collapsedDuplicateCount;
      onCollapse(1);
      exclusions.add(
        FieldInventoryExclusion._(
          rect: slot.rect,
          reason: InventoryExclusionReason.duplicateGeometry,
          cues: slot.cues.toList(),
          inkCoverage: slot.inkCoverage,
        ),
      );
    }
    return kept;
  }

  static double _referenceLineHeight(List<_Slot> slots) {
    final List<double> underline = <double>[
      for (final _Slot slot in slots)
        if (slot.cues.contains('underline')) slot.rect.height,
    ]..sort();
    if (underline.isNotEmpty) {
      return _median(underline);
    }
    final List<double> all = <double>[
      for (final _Slot slot in slots) slot.rect.height,
    ]..sort();
    if (all.isEmpty) {
      return 18.0;
    }
    return _median(all);
  }

  static double _median(List<double> sorted) {
    final int count = sorted.length;
    if (count == 0) {
      return 0;
    }
    if (count.isOdd) {
      return sorted[count ~/ 2];
    }
    return (sorted[count ~/ 2 - 1] + sorted[count ~/ 2]) / 2;
  }

  static void _classify(
    _Slot slot, {
    required double pageWidthPt,
    required double pageHeightPt,
    required double referenceHeight,
    required FieldInventoryConfig config,
  }) {
    final double side = math.min(slot.rect.width, slot.rect.height);
    final double longSide = math.max(slot.rect.width, slot.rect.height);
    final double aspect = side > 0 ? longSide / side : double.infinity;
    final double pageArea = pageWidthPt * pageHeightPt;
    final double area = slot.rect.width * slot.rect.height;

    // Structural exclusions first: they are page furniture, not inputs.
    if (slot.rect.width >= config.decorativeSpanFraction * pageWidthPt &&
        slot.rect.height >= config.decorativeSpanFraction * pageHeightPt) {
      slot
        ..role = InventoryRole.structuralRegion
        ..exclusion = InventoryExclusionReason.decorativeFrame;
      slot.evidence.add('page_span_frame');
      return;
    }
    if (area >= config.decorativeAreaFraction * pageArea) {
      slot
        ..role = InventoryRole.structuralRegion
        ..exclusion = InventoryExclusionReason.decorativeFrame;
      slot.evidence.add('page_area_fraction');
      return;
    }
    if (_insidePrintMargin(
      slot.rect,
      pageWidthPt: pageWidthPt,
      pageHeightPt: pageHeightPt,
      marginPt: config.printMarginPt,
    )) {
      slot
        ..role = InventoryRole.structuralRegion
        ..exclusion = InventoryExclusionReason.printMargin;
      slot.evidence.add('print_margin_band');
      return;
    }

    if (slot.cues.contains('small_square')) {
      slot.evidence.add('small_square_cue');
      if (side < config.minCheckboxSidePt ||
          longSide > config.maxCheckboxSidePt ||
          aspect > config.maxCheckboxAspect) {
        slot
          ..kind = FieldInventoryKind.unknown
          ..role = InventoryRole.structuralRegion
          ..exclusion = InventoryExclusionReason.letterInterior;
        slot.evidence.add('below_checkbox_side_range');
        return;
      }
      slot.kind = FieldInventoryKind.checkbox;
      if (slot.inkCoverage > config.filledInkFraction) {
        slot
          ..role = InventoryRole.filledRegion
          ..evidence.add('already_filled');
        return;
      }
      slot.role = InventoryRole.fieldCandidate;
      return;
    }

    if (side < config.minLetterInteriorSidePt &&
        slot.cues.contains('whitespace') &&
        !slot.cues.contains('box') &&
        !slot.cues.contains('table_cell') &&
        !slot.cues.contains('grid_cell') &&
        !slot.cues.contains('underline')) {
      slot
        ..kind = FieldInventoryKind.unknown
        ..role = InventoryRole.structuralRegion
        ..exclusion = InventoryExclusionReason.letterInterior;
      slot.evidence.add('glyph_counter_size');
      return;
    }

    slot.role = InventoryRole.fieldCandidate;
    if (slot.cues.contains('table_cell') || slot.cues.contains('grid_cell')) {
      slot
        ..kind = FieldInventoryKind.tableField
        ..evidence.add('table_cell_cue');
      return;
    }
    if (slot.cues.contains('signature_area')) {
      slot
        ..kind = FieldInventoryKind.signature
        ..evidence.add('signature_area_cue');
      return;
    }
    if (slot.cues.contains('date_context')) {
      slot
        ..kind = FieldInventoryKind.date
        ..evidence.add('date_context_cue');
      return;
    }
    if (slot.cues.contains('underline') &&
        !slot.cues.contains('box') &&
        !slot.cues.contains('whitespace')) {
      slot
        ..kind = FieldInventoryKind.text
        ..evidence.add('underline_cue');
      return;
    }
    if (slot.cues.contains('underline')) {
      slot.evidence.add('underline_cue');
    }
    if (slot.cues.contains('box')) {
      slot.evidence.add('box_cue');
    }
    if (slot.cues.contains('whitespace')) {
      slot.evidence.add('whitespace_cue');
    }
    if (slot.cues.contains('alignment_left')) {
      slot.evidence.add('alignment_left_cue');
    }
    final bool tall =
        slot.rect.height >=
        config.multilineHeightRatio * math.max(referenceHeight, 1);
    if (tall) {
      slot
        ..kind = FieldInventoryKind.multiline
        ..evidence.add('height_over_single_line_reference');
      return;
    }
    final bool hasInputCue =
        slot.cues.contains('underline') ||
        slot.cues.contains('box') ||
        slot.cues.contains('whitespace') ||
        slot.cues.contains('alignment_left');
    if (hasInputCue) {
      slot
        ..kind = FieldInventoryKind.text
        ..evidence.add('single_line_reference');
      return;
    }
    slot
      ..kind = FieldInventoryKind.unknown
      ..reviewFlags.add(InventoryReviewFlag.ambiguousKind);
    slot.evidence.add('no_kind_cue');
  }

  static bool _insidePrintMargin(
    DisplayRect rect, {
    required double pageWidthPt,
    required double pageHeightPt,
    required double marginPt,
  }) {
    if (marginPt <= 0) {
      return false;
    }
    final bool left = rect.x + rect.width <= marginPt;
    final bool top = rect.y + rect.height <= marginPt;
    final bool right = rect.x >= pageWidthPt - marginPt;
    final bool bottom = rect.y >= pageHeightPt - marginPt;
    return left || top || right || bottom;
  }

  static void _attachLabels(
    List<_Slot> slots,
    List<LabelObservation> labels,
    FieldInventoryConfig config,
  ) {
    if (labels.isEmpty) {
      for (final _Slot slot in slots) {
        if (slot.isFieldCandidate) {
          slot.reviewFlags.add(InventoryReviewFlag.noLabelContext);
        }
      }
      return;
    }
    for (final _Slot slot in slots) {
      LabelObservation? best;
      double bestGap = double.infinity;
      for (final LabelObservation label in labels) {
        if (label.ocrConfidence < 0.5) {
          continue;
        }
        final double gap = rectGapPt(label.rect, slot.rect);
        if (gap > config.labelMaxGapPt) {
          continue;
        }
        if (best == null ||
            gap < bestGap ||
            (gap == bestGap && label.text.compareTo(best.text) < 0)) {
          best = label;
          bestGap = gap;
        }
      }
      slot.labelText = best == null ? null : _trimLabel(best.text);
      if (best == null && slot.isFieldCandidate) {
        slot.reviewFlags.add(InventoryReviewFlag.noLabelContext);
      }
    }
  }

  static String _trimLabel(String text) {
    final String trimmed = text.trim();
    final List<int> runes = trimmed.runes.toList();
    if (runes.length <= 200) {
      return trimmed;
    }
    return String.fromCharCodes(runes.sublist(0, 200));
  }

  static void _flagTableHeaders(List<_Slot> slots) {
    final List<_Slot> cells = <_Slot>[
      for (final _Slot slot in slots)
        if (slot.kind == FieldInventoryKind.tableField) slot,
    ];
    if (cells.length < 2) {
      return;
    }
    double top = double.infinity;
    for (final _Slot cell in cells) {
      top = math.min(top, cell.rect.y);
    }
    for (final _Slot cell in cells) {
      if (cell.rect.y == top) {
        cell.reviewFlags.add(InventoryReviewFlag.tableHeaderRow);
      }
    }
  }

  static List<FieldInventoryRelation> _relations(
    List<_Slot> slots,
    FieldInventoryConfig config,
  ) {
    final List<FieldInventoryRelation> relations = <FieldInventoryRelation>[];
    final List<_Slot> ordered = List<_Slot>.of(slots)..sort(_compareSlots);
    for (int first = 0; first < ordered.length; first++) {
      for (int second = first + 1; second < ordered.length; second++) {
        final _Slot a = ordered[first];
        final _Slot b = ordered[second];
        final double overlap = iou(a.rect, b.rect);
        if (overlap >= config.overlapIou) {
          a.reviewFlags.add(InventoryReviewFlag.overlappingCandidates);
          b.reviewFlags.add(InventoryReviewFlag.overlappingCandidates);
          relations.add(
            FieldInventoryRelation._(
              kind: InventoryRelationKind.overlapping,
              firstId: a.id!,
              secondId: b.id!,
              iou: overlap,
              gapPt: 0,
            ),
          );
          continue;
        }
        final double containment = containmentFraction(a.rect, b.rect);
        final double reverse = containmentFraction(b.rect, a.rect);
        final double best = math.max(containment, reverse);
        if (best >= config.nestedContainment) {
          a.reviewFlags.add(InventoryReviewFlag.overlappingCandidates);
          b.reviewFlags.add(InventoryReviewFlag.overlappingCandidates);
          relations.add(
            FieldInventoryRelation._(
              kind: InventoryRelationKind.nested,
              firstId: a.id!,
              secondId: b.id!,
              iou: overlap,
              gapPt: 0,
            ),
          );
          continue;
        }
        final double gap = rectGapPt(a.rect, b.rect);
        if (gap <= config.adjacentGapPt &&
            a.rect.y < b.rect.y + b.rect.height &&
            b.rect.y < a.rect.y + a.rect.height) {
          relations.add(
            FieldInventoryRelation._(
              kind: InventoryRelationKind.adjacent,
              firstId: a.id!,
              secondId: b.id!,
              iou: overlap,
              gapPt: gap,
            ),
          );
          continue;
        }
      }
    }
    return relations;
  }

  static int _compareSlots(_Slot a, _Slot b) {
    int result = unitsOfPoint(a.rect.y).compareTo(unitsOfPoint(b.rect.y));
    if (result != 0) {
      return result;
    }
    result = unitsOfPoint(a.rect.x).compareTo(unitsOfPoint(b.rect.x));
    if (result != 0) {
      return result;
    }
    result = unitsOfPoint(a.rect.height).compareTo(unitsOfPoint(b.rect.height));
    if (result != 0) {
      return result;
    }
    result = unitsOfPoint(a.rect.width).compareTo(unitsOfPoint(b.rect.width));
    if (result != 0) {
      return result;
    }
    result = a.kind.ordinal.compareTo(b.kind.ordinal);
    if (result != 0) {
      return result;
    }
    return a.cuesText.compareTo(b.cuesText);
  }

  static int _compareExclusions(
    FieldInventoryExclusion a,
    FieldInventoryExclusion b,
  ) {
    int result = unitsOfPoint(a.rect.y).compareTo(unitsOfPoint(b.rect.y));
    if (result != 0) {
      return result;
    }
    result = unitsOfPoint(a.rect.x).compareTo(unitsOfPoint(b.rect.x));
    if (result != 0) {
      return result;
    }
    return a.reason.index.compareTo(b.reason.index);
  }

  static int _compareRelations(
    FieldInventoryRelation a,
    FieldInventoryRelation b,
  ) {
    int result = a.kind.index.compareTo(b.kind.index);
    if (result != 0) {
      return result;
    }
    result = a.firstId.compareTo(b.firstId);
    if (result != 0) {
      return result;
    }
    return a.secondId.compareTo(b.secondId);
  }
}

/// Maps an existing suggestion-type token to an inventory kind.
///
/// Returns `null` for a token outside the closed suggestion vocabulary, so an
/// unknown extension token is ignored instead of guessed.
FieldInventoryKind? fieldInventoryKindForSuggestionType(String token) {
  return switch (token) {
    'text' => FieldInventoryKind.text,
    'number' => FieldInventoryKind.number,
    'date' => FieldInventoryKind.date,
    'checkbox' => FieldInventoryKind.checkbox,
    'multiline' => FieldInventoryKind.multiline,
    'signature' => FieldInventoryKind.signature,
    'table_field' => FieldInventoryKind.tableField,
    _ => null,
  };
}

/// Mutable build-time slot; never escapes this library.
final class _Slot {
  _Slot({required this.rect, required this.cues, required this.inkCoverage});

  final DisplayRect rect;
  final Set<String> cues;
  double inkCoverage;
  FieldInventoryKind kind = FieldInventoryKind.unknown;
  InventoryRole role = InventoryRole.fieldCandidate;
  InventoryExclusionReason? exclusion;
  final List<String> evidence = <String>[];
  final Set<InventoryReviewFlag> reviewFlags = <InventoryReviewFlag>{};
  String? labelText;
  int collapsedDuplicateCount = 0;

  /// Final id, assigned after the deterministic sort of the retained slots.
  String? id;

  bool get isFieldCandidate => role == InventoryRole.fieldCandidate;

  bool get isStructural => role == InventoryRole.structuralRegion;

  String get cuesText {
    final List<String> sorted = cues.toList()..sort();
    return sorted.join(',');
  }
}
