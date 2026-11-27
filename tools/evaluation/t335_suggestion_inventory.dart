// Issue #335: per-suggestion inventory of the production typing stage on the
// committed fixture `sf-001`.
//
// This is a read-only measurement tool. It adds no production behaviour, no
// threshold, and no port: it renders nothing, persists nothing, and only reads
// the committed fixture bytes plus externally rasterized page images.
//
// What it measures
// ----------------
// The productive stage `runRasterPageStage` (`raster_page_stage.dart`) is run
// unchanged on the raster of one page of `apps/feldexa_app/assets/fixtures/
// sf-001.pdf` (200 DPI, `pdftoppm -gray -r 200`) with the labels of the
// committed `sf-001.expected-ocr.json`. Its suggestion list is then classified
// against three independent sources of truth:
//
//  1. the declared ground truth `sf-001.groundTruth.fields` of
//     `apps/feldexa_app/assets/fixtures/catalog.json` (`p0-*`, `p1-*`),
//  2. the printed OCR text lines of the same page, measured in both directions
//     (how much of the suggestion is printed text / how much of a printed line
//     lies inside the suggestion), and
//  3. `FieldInventoryBuilder`'s own role/exclusion classification of the same
//     candidate set.
//
// Classification rule (declared once here, applied mechanically)
// --------------------------------------------------------------
//  gtMatch           the declared field with the highest IoU against the
//                    suggestion rect, with its IoU.
//  real_field        the suggestion with the highest IoU (>= 0.5) for that
//                    declared field: one per field, so the count is the field
//                    recall.
//  duplicate_field   another suggestion with IoU >= 0.5 against an already
//                    claimed declared field: a second proposal for the same
//                    place.
//  partial_field     IoU < 0.5 but the suggestion centre lies inside a
//                    declared field: an overlap that is too loose to call a
//                    match (reported, never counted as an artifact).
//  printed_content   neither of the above, and the suggestion is dominated by
//                    printed content: `inside >= 0.5` (the suggestion sits
//                    inside one printed line, i.e. a glyph counter) or
//                    `contained >= 0.5` (a printed line lies inside the
//                    suggestion, i.e. a printed row/band). FR-016 forbids
//                    proposing printed text as input.
//  inventory_rule    neither of the above, but `FieldInventoryBuilder` gives
//                    the same rectangle a non-`fieldCandidate` role or an
//                    exclusion reason (`printMargin`, `decorativeFrame`,
//                    `letterInterior`, `duplicateGeometry`).
//  undeclared_empty_region
//                    the remaining suggestions: empty regions that are
//                    neither declared fields nor printed content. They are
//                    reported as *undetermined* with their measurements, not
//                    asserted to be artifacts.
//
// `optionA` in the totals reports the measurable effect of offering only
// `FieldInventory.fieldCandidates` in the production path: every suggestion
// whose inventory role or exclusion is not a field candidate.
//
// Evidence class of the output: host (`NONE`). It reproduces the productive
// stage code on a Poppler raster with fixture OCR text; it is not an EMULATOR
// or DEVICE claim, and the OCR text is committed fixture data, not a device
// OCR run.
//
// `--drop-label-text <substring>` (repeatable) removes matching OCR labels
// before the stage runs. It exists only for counterfactual measurements of one
// label's influence on the typing (for example the printed `TT.MM.JJJJ` mask);
// it is not a configuration of the production path.
//
// Usage:
//   dart run tools/evaluation/t335_suggestion_inventory.dart \
//     --catalog apps/feldexa_app/assets/fixtures/catalog.json \
//     --expected-ocr apps/feldexa_app/assets/fixtures/sf-001.expected-ocr.json \
//     --page /tmp/t335-p1.pgm --page /tmp/t335-p2.pgm \
//     --out specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t335/suggestions.json
// ignore_for_file: avoid_print, depend_on_referenced_packages, implementation_imports

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:feldexa_application/src/recognition/raster_page_stage.dart';
import 'package:feldexa_recognition/src/field_inventory.dart';
import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/raster.dart';
import 'package:feldexa_recognition/src/type_inference.dart'
    show LabelObservation;

const int _exitOk = 0;
const int _exitInvalid = 1;
const int _exitUsage = 2;

/// IoU at or above which a suggestion is the declared field.
const double _realFieldIou = 0.5;

/// Printed-content share at or above which a suggestion is printed content.
const double _printedContentShare = 0.5;

/// IoU at or above which the inventory entry is the same rectangle.
const double _samePlaceIou = 0.9;

void main(List<String> args) {
  final _Options? options = _Options.parse(args);
  if (options == null) {
    stderr.writeln(
      'usage: dart run tools/evaluation/t335_suggestion_inventory.dart '
      '--catalog <catalog.json> --expected-ocr <fixture.expected-ocr.json> '
      '--page <page.pgm> [--page <page.pgm> ...] --out <out.json>',
    );
    exitCode = _exitUsage;
    return;
  }

  try {
    final Map<String, Object?> report = _measure(options);
    final String encoded = const JsonEncoder.withIndent('  ').convert(report);
    File(options.outPath).writeAsStringSync('$encoded\n');
    final Map<String, Object?> totals =
        (report['totals']! as Map<Object?, Object?>).cast<String, Object?>();
    stdout.writeln(
      'pages: ${(report['pages']! as List<Object?>).length}, '
      'suggestions: ${totals['suggestions']}, '
      'byCategory: ${totals['byCategory']}, '
      'optionA: ${totals['optionA']}, '
      'out: ${options.outPath}',
    );
    exitCode = _exitOk;
  } on Object catch (error, stack) {
    stderr.writeln('measurement failed: $error\n$stack');
    exitCode = _exitInvalid;
  }
}

Map<String, Object?> _measure(_Options options) {
  final Map<String, Object?> catalog = jsonDecode(
    File(options.catalogPath).readAsStringSync(),
  ) as Map<String, Object?>;
  final Map<String, Object?> groundTruth = _groundTruth(catalog);
  final List<Map<String, Object?>> declaredPages = <Map<String, Object?>>[
    for (final Object? page in groundTruth['pages']! as List<Object?>)
      (page! as Map<Object?, Object?>).cast<String, Object?>(),
  ];
  final List<Map<String, Object?>> declaredFields = <Map<String, Object?>>[
    for (final Object? field in groundTruth['fields']! as List<Object?>)
      (field! as Map<Object?, Object?>).cast<String, Object?>(),
  ];
  final Map<String, Object?> ocr = jsonDecode(
    File(options.expectedOcrPath).readAsStringSync(),
  ) as Map<String, Object?>;

  if (options.pagePaths.length != declaredPages.length) {
    throw StateError(
      'expected ${declaredPages.length} page rasters, '
      'got ${options.pagePaths.length}',
    );
  }

  final List<Map<String, Object?>> pageReports = <Map<String, Object?>>[];
  final Map<String, int> categoryCounts = <String, int>{};
  final Map<String, int> typeCounts = <String, int>{};
  final List<Map<String, Object?>> typeMismatches = <Map<String, Object?>>[];
  final List<String> optionAIds = <String>[];
  int totalSuggestions = 0;

  for (int pageIndex = 0; pageIndex < declaredPages.length; pageIndex++) {
    final Map<String, Object?> declaredPage = declaredPages[pageIndex];
    final double pageWidthPt = (declaredPage['widthPt']! as num).toDouble();
    final double pageHeightPt = (declaredPage['heightPt']! as num).toDouble();
    final _Pgm raster = _Pgm.read(options.pagePaths[pageIndex]);
    final List<LabelObservation> labels = <LabelObservation>[
      for (final LabelObservation label in _labelsForPage(ocr, pageIndex))
        if (!options.droppedLabelText.any(
          (String needle) => label.text.toLowerCase().contains(needle),
        ))
          label,
    ];
    final List<_PrintedText> printedText = _printedTextForPage(ocr, pageIndex);

    final RasterPageStageOutcome outcome = runRasterPageStage(
      RasterPageStageTask(
        pageIndex: pageIndex,
        pixels: raster.pixels,
        width: raster.width,
        height: raster.height,
        pageWidthPt: pageWidthPt,
        pageHeightPt: pageHeightPt,
        labels: labels,
        ocrUsed: true,
      ),
    );
    if (outcome.isFailed) {
      throw StateError(
        'page $pageIndex failed the productive stage: '
        '${outcome.failureCategory}',
      );
    }

    final List<GeometryCandidate> candidates = GeometryDetector.detect(
      RasterAnalysis(
        GrayRaster.fromGrayBytes(
          width: raster.width,
          height: raster.height,
          bytes: raster.pixels,
        ),
      ),
      pageWidthPt: pageWidthPt,
      pageHeightPt: pageHeightPt,
    );
    final FieldInventory inventory = FieldInventoryBuilder.build(
      pageIndex: pageIndex,
      pageWidthPt: pageWidthPt,
      pageHeightPt: pageHeightPt,
      candidates: candidates,
      labels: labels,
    );
    final List<Map<String, Object?>> pageFields = <Map<String, Object?>>[
      for (final Map<String, Object?> field in declaredFields)
        if (field['pageIndex'] == pageIndex) field,
    ];

    final List<_Row> rows = <_Row>[];
    int index = 0;
    for (final Map<String, Object?> suggestion in outcome.suggestions) {
      index += 1;
      final _Rect rect = _Rect.fromJson(
        (suggestion['rect']! as Map<Object?, Object?>).cast<String, Object?>(),
      );
      final Map<String, Object?> evidence =
          (suggestion['evidence']! as Map<Object?, Object?>)
              .cast<String, Object?>();
      final _GroundTruthMatch match = _bestMatch(rect, pageFields);

      double inside = 0;
      double contained = 0;
      String? containedText;
      for (final _PrintedText text in printedText) {
        final double intersection = _intersection(rect, text.rect);
        if (intersection <= 0) {
          continue;
        }
        inside = math.max(inside, intersection / rect.area);
        final double share = intersection / text.rect.area;
        if (share > contained) {
          contained = share;
          containedText = text.text;
        }
      }

      rows.add(
        _Row(
          id: suggestion['id']! as String,
          order: index,
          rect: rect,
          proposedType: suggestion['proposedType']! as String,
          labelText: suggestion['labelText'] as String?,
          cues: <String>[
            for (final Object? cue in evidence['cues']! as List<Object?>)
              cue! as String,
          ],
          confidence: (suggestion['confidence']! as num).toDouble(),
          inkCoverage: _candidateInk(candidates, rect),
          match: match,
          insideShare: inside,
          containedShare: contained,
          containedText: containedText,
          inventory: _inventoryVerdict(inventory, rect),
        ),
      );
    }

    _classify(rows, pageFields);
    for (final _Row row in rows) {
      categoryCounts[row.category] = (categoryCounts[row.category] ?? 0) + 1;
      typeCounts[row.proposedType] = (typeCounts[row.proposedType] ?? 0) + 1;
      totalSuggestions += 1;
      if (row.category == 'real_field' &&
          row.match.fieldType != row.proposedType) {
        typeMismatches.add(<String, Object?>{
          'suggestionId': row.id,
          'fieldId': row.match.fieldId,
          'label': row.match.label,
          'declared': row.match.fieldType,
          'proposed': row.proposedType,
          'labelText': row.labelText,
        });
      }
      if (row.inventory.role != 'fieldCandidate' ||
          row.inventory.exclusionReason != null) {
        optionAIds.add(row.id);
      }
    }

    final Map<String, int> claimed = <String, int>{};
    for (final _Row row in rows) {
      if (row.category == 'real_field') {
        claimed[row.match.fieldId] = (claimed[row.match.fieldId] ?? 0) + 1;
      }
    }

    pageReports.add(<String, Object?>{
      'pageIndex': pageIndex,
      'pageSizePt': <String, double>{
        'width': pageWidthPt,
        'height': pageHeightPt,
      },
      'rasterSize': <String, int>{
        'width': raster.width,
        'height': raster.height,
      },
      'declaredFieldCount': pageFields.length,
      'candidateCount': candidates.length,
      'inventoryEntryCount': inventory.entries.length,
      'inventoryFieldCandidateCount': inventory.fieldCandidates.length,
      'inventoryExclusionCount': inventory.exclusions.length,
      'suggestionCount': rows.length,
      'declaredFieldsWithoutSuggestion': <String>[
        for (final Map<String, Object?> field in pageFields)
          if (!claimed.containsKey(field['id'] as String))
            field['id']! as String,
      ],
      'suggestions': <Map<String, Object?>>[
        for (final _Row row in rows) row.toJson(),
      ],
    });
  }

  return <String, Object?>{
    'tool': 'tools/evaluation/t335_suggestion_inventory.dart',
    'issue': 335,
    'fixtureId': groundTruth['fixtureId'],
    'evidenceClass':
        'NONE (host: productive stage on a Poppler raster with '
        'committed fixture OCR)',
    'droppedLabelText': options.droppedLabelText,
    'classificationRule': <String, Object?>{
      'realFieldIou': _realFieldIou,
      'printedContentShare': _printedContentShare,
      'samePlaceIou': _samePlaceIou,
      'categories': <String>[
        'real_field',
        'duplicate_field',
        'partial_field',
        'printed_content',
        'inventory_rule',
        'undeclared_empty_region',
      ],
    },
    'declaredFieldCount': declaredFields.length,
    'totals': <String, Object?>{
      'suggestions': totalSuggestions,
      'byCategory': categoryCounts,
      'byProposedType': typeCounts,
      'typeMismatches': typeMismatches,
      'optionA': <String, Object?>{
        'description':
            'suggestions whose FieldInventory role or exclusion is '
            'not a field candidate (would disappear if the production path '
            'offered only inventory.fieldCandidates)',
        'count': optionAIds.length,
        'ids': optionAIds,
      },
    },
    'pages': pageReports,
  };
}

/// Assigns [category] to every row of one page: declared fields first by best
/// IoU, then the documented fallbacks in order.
void _classify(List<_Row> rows, List<Map<String, Object?>> pageFields) {
  final Map<String, _Row> bestPerField = <String, _Row>{};
  for (final Map<String, Object?> field in pageFields) {
    final String fieldId = field['id']! as String;
    for (final _Row row in rows) {
      if (row.match.fieldId != fieldId || row.match.iou < _realFieldIou) {
        continue;
      }
      final _Row? current = bestPerField[fieldId];
      if (current == null || row.match.iou > current.match.iou) {
        bestPerField[fieldId] = row;
      }
    }
  }
  final Set<String> realIds = <String>{
    for (final _Row row in bestPerField.values) row.id,
  };
  for (final _Row row in rows) {
    if (realIds.contains(row.id)) {
      row.category = 'real_field';
      continue;
    }
    if (row.match.iou >= _realFieldIou && row.match.fieldId.isNotEmpty) {
      row.category = 'duplicate_field';
      continue;
    }
    if (row.match.centerInside && row.match.fieldId.isNotEmpty) {
      row.category = 'partial_field';
      continue;
    }
    if (row.insideShare >= _printedContentShare ||
        row.containedShare >= _printedContentShare) {
      row.category = 'printed_content';
      continue;
    }
    if (row.inventory.role != null && row.inventory.role != 'fieldCandidate' ||
        row.inventory.exclusionReason != null) {
      row.category = 'inventory_rule';
      continue;
    }
    row.category = 'undeclared_empty_region';
  }
}

Map<String, Object?> _groundTruth(Map<String, Object?> catalog) {
  final List<Object?> fixtures = catalog['fixtures']! as List<Object?>;
  for (final Object? entry in fixtures) {
    final Map<String, Object?> fixture = (entry! as Map<Object?, Object?>)
        .cast<String, Object?>();
    if (fixture['id'] != 'sf-001') {
      continue;
    }
    final Map<String, Object?> truth =
        (fixture['groundTruth']! as Map<Object?, Object?>)
            .cast<String, Object?>();
    return <String, Object?>{
      'fixtureId': 'sf-001',
      'pages': fixture['pages'],
      'fields': truth['fields'],
    };
  }
  throw StateError('sf-001 is not in the catalogue');
}

List<LabelObservation> _labelsForPage(Map<String, Object?> ocr, int pageIndex) {
  final List<LabelObservation> labels = <LabelObservation>[];
  for (final Map<String, Object?> block in _blocks(ocr, pageIndex)) {
    final List<Object?> lines = block['lines']! as List<Object?>;
    if (lines.isEmpty) {
      labels.add(_label(block['text']! as String, block['rect']!, block));
      continue;
    }
    for (final Object? line in lines) {
      final Map<String, Object?> lineMap = (line! as Map<Object?, Object?>)
          .cast<String, Object?>();
      labels.add(_label(lineMap['text']! as String, lineMap['rect']!, lineMap));
    }
  }
  return labels;
}

List<_PrintedText> _printedTextForPage(
  Map<String, Object?> ocr,
  int pageIndex,
) {
  final List<_PrintedText> printed = <_PrintedText>[];
  for (final Map<String, Object?> block in _blocks(ocr, pageIndex)) {
    printed.add(
      _PrintedText(
        text: block['text']! as String,
        rect: _Rect.fromJson(
          (block['rect']! as Map<Object?, Object?>).cast<String, Object?>(),
        ),
      ),
    );
    for (final Object? line in block['lines']! as List<Object?>) {
      final Map<String, Object?> lineMap = (line! as Map<Object?, Object?>)
          .cast<String, Object?>();
      printed.add(
        _PrintedText(
          text: lineMap['text']! as String,
          rect: _Rect.fromJson(
            (lineMap['rect']! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        ),
      );
    }
  }
  return printed;
}

List<Map<String, Object?>> _blocks(Map<String, Object?> ocr, int pageIndex) {
  final List<Map<String, Object?>> blocks = <Map<String, Object?>>[];
  for (final Object? page in ocr['pages']! as List<Object?>) {
    final Map<String, Object?> pageMap = (page! as Map<Object?, Object?>)
        .cast<String, Object?>();
    if (pageMap['pageIndex'] != pageIndex) {
      continue;
    }
    for (final Object? block in pageMap['blocks']! as List<Object?>) {
      blocks.add((block! as Map<Object?, Object?>).cast<String, Object?>());
    }
  }
  return blocks;
}

LabelObservation _label(
  String text,
  Object? rectValue,
  Map<String, Object?> source,
) {
  final _Rect rect = _Rect.fromJson(
    (rectValue! as Map<Object?, Object?>).cast<String, Object?>(),
  );
  final double confidence = (source['confidence'] as num?)?.toDouble() ?? 0.97;
  return LabelObservation(
    text: text,
    rect: DisplayRect(
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
    ),
    ocrConfidence: confidence,
  );
}

double? _candidateInk(List<GeometryCandidate> candidates, _Rect rect) {
  for (final GeometryCandidate candidate in candidates) {
    if ((candidate.rect.x - rect.x).abs() < 1e-9 &&
        (candidate.rect.y - rect.y).abs() < 1e-9 &&
        (candidate.rect.width - rect.width).abs() < 1e-9 &&
        (candidate.rect.height - rect.height).abs() < 1e-9) {
      return candidate.inkCoverage;
    }
  }
  return null;
}

_GroundTruthMatch _bestMatch(_Rect rect, List<Map<String, Object?>> fields) {
  _GroundTruthMatch best = const _GroundTruthMatch.none();
  double bestIou = 0;
  for (final Map<String, Object?> field in fields) {
    final Map<String, Object?> raw = (field['rect']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final _Rect target = _Rect(
      (raw['xPt']! as num).toDouble(),
      (raw['yPt']! as num).toDouble(),
      (raw['widthPt']! as num).toDouble(),
      (raw['heightPt']! as num).toDouble(),
    );
    final double iou = _iou(rect, target);
    if (iou <= bestIou) {
      continue;
    }
    bestIou = iou;
    final double cx = rect.x + rect.width / 2;
    final double cy = rect.y + rect.height / 2;
    best = _GroundTruthMatch(
      fieldId: field['id']! as String,
      fieldType: field['type']! as String,
      label: field['label']! as String,
      iou: iou,
      centerInside:
          cx >= target.x &&
          cx <= target.x + target.width &&
          cy >= target.y &&
          cy <= target.y + target.height,
      rect: target,
    );
  }
  return best;
}

_InventoryVerdict _inventoryVerdict(FieldInventory inventory, _Rect rect) {
  for (final FieldInventoryEntry entry in inventory.entries) {
    if (_iou(rect, _fromDisplay(entry.rect)) >= _samePlaceIou) {
      return _InventoryVerdict(
        role: entry.role.name,
        kind: entry.kind.wireName,
        exclusionReason: null,
        reviewFlags: <String>[
          for (final InventoryReviewFlag flag in entry.reviewFlags) flag.name,
        ],
      );
    }
  }
  for (final FieldInventoryExclusion exclusion in inventory.exclusions) {
    if (_iou(rect, _fromDisplay(exclusion.rect)) >= _samePlaceIou) {
      return _InventoryVerdict(
        role: null,
        kind: null,
        exclusionReason: exclusion.reason.name,
        reviewFlags: const <String>[],
      );
    }
  }
  return const _InventoryVerdict(
    role: null,
    kind: null,
    exclusionReason: null,
    reviewFlags: <String>[],
  );
}

_Rect _fromDisplay(DisplayRect rect) =>
    _Rect(rect.x, rect.y, rect.width, rect.height);

double _intersection(_Rect a, _Rect b) {
  final double overlapX =
      math.min(a.x + a.width, b.x + b.width) - math.max(a.x, b.x);
  final double overlapY =
      math.min(a.y + a.height, b.y + b.height) - math.max(a.y, b.y);
  if (overlapX <= 0 || overlapY <= 0) {
    return 0;
  }
  return overlapX * overlapY;
}

double _iou(_Rect a, _Rect b) {
  final double intersection = _intersection(a, b);
  if (intersection <= 0) {
    return 0;
  }
  final double union = a.area + b.area - intersection;
  if (union <= 0) {
    return 0;
  }
  return intersection / union;
}

double _round(double value) => double.parse(value.toStringAsFixed(3));

final class _Options {
  const _Options({
    required this.catalogPath,
    required this.expectedOcrPath,
    required this.pagePaths,
    required this.outPath,
    required this.droppedLabelText,
  });

  final String catalogPath;
  final String expectedOcrPath;
  final List<String> pagePaths;
  final String outPath;

  /// Lowercased label substrings removed from the stage input.
  final List<String> droppedLabelText;

  static _Options? parse(List<String> args) {
    String? catalog;
    String? expectedOcr;
    String? out;
    final List<String> pages = <String>[];
    final List<String> dropped = <String>[];
    for (int index = 0; index < args.length; index++) {
      final String arg = args[index];
      String? next() => index + 1 < args.length ? args[++index] : null;
      switch (arg) {
        case '--catalog':
          catalog = next();
        case '--expected-ocr':
          expectedOcr = next();
        case '--page':
          final String? page = next();
          if (page != null) {
            pages.add(page);
          }
        case '--out':
          out = next();
        case '--drop-label-text':
          final String? needle = next();
          if (needle != null) {
            dropped.add(needle.toLowerCase());
          }
        default:
          return null;
      }
    }
    if (catalog == null ||
        expectedOcr == null ||
        out == null ||
        pages.isEmpty) {
      return null;
    }
    return _Options(
      catalogPath: catalog,
      expectedOcrPath: expectedOcr,
      pagePaths: List<String>.unmodifiable(pages),
      outPath: out,
      droppedLabelText: List<String>.unmodifiable(dropped),
    );
  }
}

final class _Row {
  _Row({
    required this.id,
    required this.order,
    required this.rect,
    required this.proposedType,
    required this.labelText,
    required this.cues,
    required this.confidence,
    required this.inkCoverage,
    required this.match,
    required this.insideShare,
    required this.containedShare,
    required this.containedText,
    required this.inventory,
  });

  final String id;
  final int order;
  final _Rect rect;
  final String proposedType;
  final String? labelText;
  final List<String> cues;
  final double confidence;
  final double? inkCoverage;
  final _GroundTruthMatch match;
  final double insideShare;
  final double containedShare;
  final String? containedText;
  final _InventoryVerdict inventory;

  String category = '';

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'order': order,
    'rect': rect.toJson(),
    'proposedType': proposedType,
    'labelText': labelText,
    'cues': cues,
    'confidence': _round(confidence),
    'inkCoverage': inkCoverage == null ? null : _round(inkCoverage!),
    'category': category,
    'groundTruth': match.toJson(),
    'printedContent': <String, Object?>{
      'insideShare': _round(insideShare),
      'containedShare': _round(containedShare),
      'containedText': containedText,
    },
    'inventory': inventory.toJson(),
    'minSidePt': _round(math.min(rect.width, rect.height)),
    'typeMismatch': category == 'real_field' && match.fieldType != proposedType
        ? 'declared ${match.fieldType} != proposed $proposedType'
        : null,
  };
}

final class _Rect {
  const _Rect(this.x, this.y, this.width, this.height);

  factory _Rect.fromJson(Map<String, Object?> json) => _Rect(
    (json['x']! as num).toDouble(),
    (json['y']! as num).toDouble(),
    (json['width']! as num).toDouble(),
    (json['height']! as num).toDouble(),
  );

  final double x;
  final double y;
  final double width;
  final double height;

  double get area => width * height;

  Map<String, Object?> toJson() => <String, Object?>{
    'x': _round(x),
    'y': _round(y),
    'width': _round(width),
    'height': _round(height),
  };
}

final class _PrintedText {
  const _PrintedText({required this.text, required this.rect});

  final String text;
  final _Rect rect;
}

final class _GroundTruthMatch {
  const _GroundTruthMatch({
    required this.fieldId,
    required this.fieldType,
    required this.label,
    required this.iou,
    required this.centerInside,
    required this.rect,
  });

  const _GroundTruthMatch.none()
    : fieldId = '',
      fieldType = '',
      label = '',
      iou = 0,
      centerInside = false,
      rect = const _Rect(0, 0, 0, 0);

  final String fieldId;
  final String fieldType;
  final String label;
  final double iou;
  final bool centerInside;
  final _Rect rect;

  Map<String, Object?> toJson() => <String, Object?>{
    'fieldId': fieldId,
    'fieldType': fieldType,
    'label': label,
    'iou': _round(iou),
    'centerInside': centerInside,
    'rect': rect.toJson(),
  };
}

final class _InventoryVerdict {
  const _InventoryVerdict({
    required this.role,
    required this.kind,
    required this.exclusionReason,
    required this.reviewFlags,
  });

  final String? role;
  final String? kind;
  final String? exclusionReason;
  final List<String> reviewFlags;

  Map<String, Object?> toJson() => <String, Object?>{
    'role': role,
    'kind': kind,
    'exclusionReason': exclusionReason,
    'reviewFlags': reviewFlags,
  };
}

/// One binary PGM (`P5`, maxval 255) page raster.
final class _Pgm {
  const _Pgm({required this.width, required this.height, required this.pixels});

  final int width;
  final int height;
  final Uint8List pixels;

  static _Pgm read(String path) {
    final Uint8List bytes = File(path).readAsBytesSync();
    int offset = 0;
    String token() {
      while (offset < bytes.length) {
        final int byte = bytes[offset];
        if (byte == 0x23) {
          while (offset < bytes.length && bytes[offset] != 0x0A) {
            offset += 1;
          }
          continue;
        }
        if (byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D) {
          offset += 1;
          continue;
        }
        break;
      }
      final int start = offset;
      while (offset < bytes.length &&
          bytes[offset] != 0x20 &&
          bytes[offset] != 0x09 &&
          bytes[offset] != 0x0A &&
          bytes[offset] != 0x0D) {
        offset += 1;
      }
      return String.fromCharCodes(bytes.sublist(start, offset));
    }

    final String magic = token();
    if (magic != 'P5') {
      throw FormatException('$path is not a binary PGM');
    }
    final int width = int.parse(token());
    final int height = int.parse(token());
    final int maxval = int.parse(token());
    if (maxval != 255) {
      throw FormatException('$path has maxval $maxval, expected 255');
    }
    offset += 1;
    final Uint8List pixels = Uint8List.sublistView(bytes, offset);
    if (pixels.length != width * height) {
      throw FormatException(
        '$path holds ${pixels.length} pixels, expected ${width * height}',
      );
    }
    return _Pgm(width: width, height: height, pixels: pixels);
  }
}
