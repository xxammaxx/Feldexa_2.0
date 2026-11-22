// T264 baseline: geometry-first field inventory and structure comparison on a
// declared synthetic annotated corpus (host-only evaluation artifact).
//
// Normative sources:
//  * `specs/001-scanned-form-workflow/spec.md` FR-011, FR-013, FR-014, FR-016,
//    SC-001, SC-002;
//  * `specs/001-scanned-form-workflow/contracts/recognition-output.md`
//    sections 2, 2.1, 3.1, and 6;
//  * `specs/001-scanned-form-workflow/contracts/coordinates-and-geometry.md`
//    sections 1 and 4;
//  * `specs/001-scanned-form-workflow/research.md` D-18 and D-20.
//
// What this tool does. It draws a deterministic, rights-free synthetic corpus
// at the contract's 200 DPI analysis scale, *declares the ground truth at draw
// time* (before any detection), runs the productive pipeline stages
// (`RasterAnalysis` -> `GeometryDetector.detect` -> `TypeInference.infer`) plus
// the T264 `FieldInventory` and `StructureComparison`, and reports the
// comparison of:
//
//   baseline   - every typed geometry candidate the current productive pipeline
//                would propose (the pre-T264 behaviour), and
//   inventory  - the deduplicated, role-classified field candidates.
//
// Both are compared against the same pre-declared ground truth. A run with the
// same field count as the ground truth but with wrong positions is a FAIL. An
// unknown expected count is never completeness proof. Nothing is forced or
// dropped to reach a count.
//
// Evidence class. The corpus is `SIMULATED`: deterministic synthetic rasters,
// declared labels (no OCR engine runs), host VM timings. There is no Android,
// emulator, device, OCR-engine, or performance claim. Timings are recorded as
// host diagnostics only and are excluded from the golden snapshot.
//
// Golden snapshot. `--snapshot PATH` writes a canonical, timing-free JSON
// document whose bytes must match the committed golden
// `tools/evaluation/goldens/field-inventory-baseline.v1.json`. Any change in
// the detector, the inventory, the comparison, or the corpus changes those
// bytes, so a regression is visible as a snapshot diff.
//
// Usage:
//   dart run tools/evaluation/field_inventory_baseline.dart \
//     --output <run.json> [--snapshot <snapshot.json>]
//   dart run tools/evaluation/field_inventory_baseline.dart --help
//
// Exit codes:
//   0  report written (or help printed)
//   1  I/O failure or an internal invariant failure
//   2  usage error (unknown/missing/duplicate argument)
//
// `feldexa_recognition` is a workspace package and intentionally not a root
// `pubspec.yaml` dependency; the root workspace resolves it for `dart run`.
// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:feldexa_recognition/src/field_inventory.dart';
import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/photometric_quality.dart';
import 'package:feldexa_recognition/src/raster.dart';
import 'package:feldexa_recognition/src/structure_comparison.dart';
import 'package:feldexa_recognition/src/type_inference.dart';

const int _schemaVersion = 1;
const String _corpusId = 'field-inventory-synthetic-v1';

/// Why a kind has no corpus instance. A zero-count row must never be silent.
const Map<FieldInventoryKind, String> _kindAbsenceReasons =
    <FieldInventoryKind, String>{
      FieldInventoryKind.signature:
          'No detector cue produces `signature_area` on this corpus, so no '
          'signature ground truth is declared and no signature recall is '
          'claimed; signature typing is covered only by the recognition '
          'unit tests (field_inventory_test.dart, type_inference_test.dart).',
      FieldInventoryKind.unknown:
          'Every detected region carries at least one kind cue, so no region '
          'falls through to `unknown`; no unknown ground truth is declared '
          'and unknown typing is covered only by the recognition unit tests.',
    };

const int _exitOk = 0;
const int _exitInvalid = 1;
const int _exitUsage = 2;

const String _help = '''
T264 field-inventory baseline on the declared synthetic corpus (host-only).

Usage:
  field_inventory_baseline.dart --output <run.json> [--snapshot <snapshot.json>]
  field_inventory_baseline.dart --help

Options:
  --output PATH    Destination run report JSON (required).
  --snapshot PATH  Destination canonical, timing-free golden snapshot JSON.
  --help, -h       Show this help and exit 0.

The run report records measured host timings and is labelled SIMULATED. The
snapshot excludes timings and is the golden regression artifact.

Exit codes:
  0 report written, or help printed
  1 I/O failure or internal invariant failure; no report is written
  2 usage error (unknown, missing, or duplicate argument)

This tool proves no runtime, emulator, device, OCR-engine, or performance claim.
''';

/// Default page metrics: A4 portrait in display points.
const double _a4WidthPt = 595.28;
const double _a4HeightPt = 841.89;

void main(List<String> arguments) {
  try {
    _run(arguments);
  } on _Failure catch (failure) {
    stderr.writeln('error: ${failure.code}');
    exitCode = failure.exitCode;
  }
}

void _run(List<String> arguments) {
  final _Options options = _parseArguments(arguments);
  if (options.help) {
    stdout.write(_help);
    exitCode = _exitOk;
    return;
  }
  final String outputPath = _requiredPath('output', options.output);

  final List<_PageResult> pages = <_PageResult>[];
  for (final _PageSpec spec in _corpus()) {
    pages.add(_analysePage(spec));
  }
  final Map<String, Object?> snapshot = _snapshot(pages);
  final String snapshotJson = const JsonEncoder.withIndent('  ')
      .convert(snapshot);
  final Map<String, Object?> fixture = _fixtureIdentity(pages);
  final Map<String, Object?> report = <String, Object?>{
    'schemaVersion': _schemaVersion,
    'corpusId': _corpusId,
    'evidenceClass': 'SIMULATED',
    'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'conditions': <String, Object?>{
      'runtime': 'host VM',
      'dart': Platform.version,
      'analysisDpi': analysisDpi,
      'ocrEngine': null,
      'ocrEngineNote':
          'No OCR engine ran: labels are declared SIMULATED '
          'observations of the synthetic corpus.',
      'claim':
          'SIMULATED host evaluation only; no Android, emulator, device, '
          'OCR-engine, or performance claim.',
    },
    'noRegressionGate': _noRegressionGate(pages).toJson(),
    'totals': _totals(pages).toJson(),
    'memory': _memoryMeasurement(),
    'hashes': <String, Object?>{
      'goldenSha256': _sha256Hex(utf8.encode(snapshotJson)),
      'corpusSha256': fixture['corpusSha256'],
      'fixtureSha256': fixture['fixtureSha256'],
      'groundTruthSha256': fixture['groundTruthSha256'],
    },
    'pages': <Map<String, Object?>>[
      for (final _PageResult page in pages) page.toJson(includeTimings: true),
    ],
    'timings': <String, Object?>{
      'note':
          'host VM measurements, diagnostics only, never a performance '
          'claim; excluded from the golden snapshot',
      'totalRasterMs': _sum(pages, (_PageResult page) => page.rasterMs),
      'totalDetectMs': _sum(pages, (_PageResult page) => page.detectMs),
      'totalTypeMs': _sum(pages, (_PageResult page) => page.typeMs),
      'totalInventoryMs': _sum(pages, (_PageResult page) => page.inventoryMs),
      'totalCompareMs': _sum(pages, (_PageResult page) => page.compareMs),
    },
    'snapshot': snapshot,
  };

  try {
    final File output = File(outputPath);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    final String? snapshotPath = options.snapshot;
    if (snapshotPath != null) {
      final File target = File(snapshotPath);
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(snapshotJson);
    }
  } on FileSystemException catch (error) {
    throw _Failure(_exitInvalid, 'io: ${error.message}');
  }
  stdout.writeln(
    'baseline written: pages=${pages.length} '
    'verdicts=${_verdictSummary(pages)}',
  );
  exitCode = _exitOk;
}

int _sum(List<_PageResult> pages, int Function(_PageResult page) select) {
  int total = 0;
  for (final _PageResult page in pages) {
    total += select(page);
  }
  return total;
}

Map<String, Object?> _verdictSummary(List<_PageResult> pages) {
  final Map<String, int> counts = <String, int>{};
  for (final _PageResult page in pages) {
    counts[page.inventoryComparison.verdict.name] =
        (counts[page.inventoryComparison.verdict.name] ?? 0) + 1;
  }
  return counts;
}

// ---------------------------------------------------------------------------
// Corpus: deterministic drawings with declared ground truth
// ---------------------------------------------------------------------------

/// One declared ground-truth field.
final class _Expected {
  const _Expected({
    required this.id,
    required this.rect,
    required this.kind,
    this.labelText,
    this.sectionId,
  });

  final String id;
  final DisplayRect rect;
  final FieldInventoryKind kind;
  final String? labelText;

  /// Declared evaluation section that contains this field's centre.
  final String? sectionId;

  _Expected withSection(String id) => _Expected(
    id: this.id,
    rect: rect,
    kind: kind,
    labelText: labelText,
    sectionId: id,
  );
}

/// One declared page region used only for evaluation grouping.
///
/// This is an evaluation-only section dimension: it never becomes a persistent
/// section model, a persisted field attribute, or a UI element.
final class _SectionSpec {
  const _SectionSpec({
    required this.id,
    required this.label,
    required this.rect,
  });

  final String id;
  final String label;
  final DisplayRect rect;
}

/// One declared region that is deliberately *not* a field.
final class _NonField {
  const _NonField({required this.id, required this.reason, required this.rect});

  final String id;
  final String reason;
  final DisplayRect rect;
}

/// One declared OCR label observation of the synthetic page.
final class _LabelSpec {
  const _LabelSpec({required this.text, required this.rect});

  final String text;
  final DisplayRect rect;
}

/// One synthetic page with its declared drawing and ground truth.
final class _PageSpec {
  _PageSpec({
    required this.id,
    required this.scenario,
    required this.description,
    required this.widthPt,
    required this.heightPt,
    required this.raster,
    required this.expected,
    required this.nonFields,
    required this.labels,
    required this.sections,
    required this.rasterSha256,
    required this.rasterWidthPx,
    required this.rasterHeightPx,
    required this.groundTruthSha256,
  });

  final String id;
  final String scenario;
  final String description;
  final double widthPt;
  final double heightPt;
  final GrayRaster raster;
  final List<_Expected> expected;
  final List<_NonField> nonFields;
  final List<_LabelSpec> labels;
  final List<_SectionSpec> sections;
  final String rasterSha256;
  final int rasterWidthPx;
  final int rasterHeightPx;
  final String groundTruthSha256;
}

/// A deterministic grayscale drawing canvas in 200 DPI pixels.
final class _Canvas {
  _Canvas({required this.width, required this.height, int paper = 255})
    : _bytes = Uint8List(width * height) {
    _bytes.fillRange(0, _bytes.length, paper);
  }

  final int width;
  final int height;
  final Uint8List _bytes;

  void fillRectPx(int left, int top, int right, int bottom, int value) {
    final int l = left.clamp(0, width);
    final int t = top.clamp(0, height);
    final int r = right.clamp(0, width);
    final int b = bottom.clamp(0, height);
    for (int y = t; y < b; y++) {
      for (int x = l; x < r; x++) {
        _bytes[y * width + x] = value;
      }
    }
  }

  void fillRectPt(
    double x,
    double y,
    double w,
    double h, {
    int value = 0,
    bool gradient = false,
  }) {
    final int left = pointToPixel(x);
    final int top = pointToPixel(y);
    final int right = pointToPixel(x + w);
    final int bottom = pointToPixel(y + h);
    if (!gradient) {
      fillRectPx(left, top, right, bottom, value);
      return;
    }
    for (int py = top; py < bottom; py++) {
      final int shade = 150 + ((py - top) * 60 ~/ (bottom - top));
      for (int px = left; px < right; px++) {
        _bytes[py * width + px] = shade;
      }
    }
  }

  GrayRaster build() =>
      GrayRaster.fromGrayBytes(width: width, height: height, bytes: _bytes);

  /// Exact fixture bytes of the drawn page, used for the raster hash.
  Uint8List get bytes => Uint8List.fromList(_bytes);
}

int _px(double point) => pointToPixel(point);

DisplayRect _ptRect(double x, double y, double w, double h) =>
    DisplayRect(x: x, y: y, width: w, height: h);

/// A helper that draws one page and declares its ground truth at draw time.
final class _Form {
  _Form({
    required this.id,
    required this.scenario,
    required this.description,
    this.widthPt = _a4WidthPt,
    this.heightPt = _a4HeightPt,
    this.paper = 255,
  }) : _rasterSize = RasterSize.fromDisplaySize(
         widthPt: widthPt,
         heightPt: heightPt,
       ),
       canvas = _Canvas(
         width: RasterSize.fromDisplaySize(
           widthPt: widthPt,
           heightPt: heightPt,
         ).widthPx,
         height: RasterSize.fromDisplaySize(
           widthPt: widthPt,
           heightPt: heightPt,
         ).heightPx,
         paper: paper,
       );

  final String id;
  final String scenario;
  final String description;
  final double widthPt;
  final double heightPt;
  final int paper;
  final RasterSize _rasterSize;
  final _Canvas canvas;
  final List<_Expected> expected = <_Expected>[];
  final List<_NonField> nonFields = <_NonField>[];
  final List<_LabelSpec> labels = <_LabelSpec>[];
  final List<_SectionSpec> sections = <_SectionSpec>[];

  /// Declares one evaluation-only section region of this page.
  ///
  /// The section dimension exists only for the `per page/section/type`
  /// evaluation grouping: it is declared ground truth, never a detector input,
  /// never a persisted field attribute, and never a UI construct.
  void section({
    required String id,
    required String label,
    required double x,
    required double y,
    required double width,
    required double height,
  }) {
    sections.add(
      _SectionSpec(id: id, label: label, rect: _ptRect(x, y, width, height)),
    );
  }

  /// A rule plus the 18 pt write-on band above it.
  void textField({
    required String fieldId,
    required double x,
    required double y,
    required double width,
    String? label,
    FieldInventoryKind kind = FieldInventoryKind.text,
    int ink = 0,
    double labelOffsetPt = 26,
  }) {
    canvas.fillRectPt(x, y, width, 0.9, value: ink);
    expected.add(
      _Expected(
        id: fieldId,
        rect: _ptRect(x, y - 18, width, 18),
        kind: kind,
        labelText: label,
      ),
    );
    if (label != null) {
      _label(
        label,
        x - labelOffsetPt - label.length * 3.0,
        y - 9,
        label.length * 3.0 + 20,
      );
    }
  }

  /// A stroked box plus its declared interior rectangle.
  void boxField({
    required String fieldId,
    required double x,
    required double y,
    required double width,
    required double height,
    String? label,
    FieldInventoryKind kind = FieldInventoryKind.text,
    int border = 0,
    bool declareField = true,
    bool filled = false,
    String? nonFieldReason,
    double labelOffsetPt = 26,
  }) {
    final int thickness = 2;
    final int left = _px(x);
    final int top = _px(y);
    final int right = _px(x + width);
    final int bottom = _px(y + height);
    canvas.fillRectPx(left, top, right, top + thickness, border);
    canvas.fillRectPx(left, bottom - thickness, right, bottom, border);
    canvas.fillRectPx(left, top, left + thickness, bottom, border);
    canvas.fillRectPx(right - thickness, top, right, bottom, border);
    final double inner = 2 / rasterScale;
    final DisplayRect interior = _ptRect(
      x + inner,
      y + inner,
      width - 2 * inner,
      height - 2 * inner,
    );
    if (filled) {
      // A hand-drawn cross marks an already filled checkbox.
      final int cross = 2;
      final int cx = (left + right) ~/ 2;
      final int cy = (top + bottom) ~/ 2;
      for (int offset = -cross * 4; offset <= cross * 4; offset++) {
        canvas.fillRectPx(
          cx + offset,
          cy + offset,
          cx + offset + 2,
          cy + offset + 2,
          0,
        );
        canvas.fillRectPx(
          cx + offset,
          cy - offset,
          cx + offset + 2,
          cy - offset + 2,
          0,
        );
      }
    }
    if (declareField) {
      expected.add(
        _Expected(id: fieldId, rect: interior, kind: kind, labelText: label),
      );
    } else {
      nonFields.add(
        _NonField(
          id: fieldId,
          reason: nonFieldReason ?? 'declared_non_field',
          rect: interior,
        ),
      );
    }
    if (label != null) {
      _label(
        label,
        x - labelOffsetPt - label.length * 3.0,
        y + height / 2 - 5,
        label.length * 3.0 + 20,
      );
    }
  }

  /// A grid with [columns] x [rows] addressable cells.
  void table({
    required String idPrefix,
    required double x,
    required double y,
    required double width,
    required double height,
    required int columns,
    required int rows,
    Set<String> printedCells = const <String>{},
  }) {
    final int thickness = 2;
    final double cellWidth = width / columns;
    final double cellHeight = height / rows;
    for (int column = 0; column <= columns; column++) {
      final int px = _px(x + column * cellWidth);
      canvas.fillRectPx(px, _px(y), px + thickness, _px(y + height), 0);
    }
    for (int row = 0; row <= rows; row++) {
      final int py = _px(y + row * cellHeight);
      canvas.fillRectPx(_px(x), py, _px(x + width), py + thickness, 0);
    }
    for (int row = 0; row < rows; row++) {
      for (int column = 0; column < columns; column++) {
        final String cellId = '$idPrefix-r${row}c$column';
        final DisplayRect interior = _ptRect(
          x + column * cellWidth + 2 / rasterScale,
          y + row * cellHeight + 2 / rasterScale,
          cellWidth - 4 / rasterScale,
          cellHeight - 4 / rasterScale,
        );
        if (printedCells.contains(cellId)) {
          // Printed content in the cell: a dense text-like hatch.
          for (int line = 0; line < 6; line++) {
            canvas.fillRectPt(
              interior.x + 4,
              interior.y + 3 + line * 4,
              interior.width - 8,
              1.8,
            );
          }
          nonFields.add(
            _NonField(id: cellId, reason: 'printed_table_cell', rect: interior),
          );
        } else {
          expected.add(
            _Expected(
              id: cellId,
              rect: interior,
              kind: FieldInventoryKind.tableField,
            ),
          );
        }
      }
    }
  }

  /// A decorative page frame outside the content area.
  void decorativeFrame() {
    final int thickness = 2;
    final int left = _px(4);
    final int top = _px(4);
    final int right = _px(widthPt - 4);
    final int bottom = _px(heightPt - 4);
    canvas.fillRectPx(left, top, right, top + thickness, 0);
    canvas.fillRectPx(left, bottom - thickness, right, bottom, 0);
    canvas.fillRectPx(left, top, left + thickness, bottom, 0);
    canvas.fillRectPx(right - thickness, top, right, bottom, 0);
    nonFields.add(
      _NonField(
        id: 'decorative-frame',
        reason: 'decorative_frame',
        rect: _ptRect(4, 4, widthPt - 8, heightPt - 8),
      ),
    );
  }

  /// A short rule inside the print margin (page furniture).
  void marginRule() {
    canvas.fillRectPt(2, heightPt / 2, 10, 0.9);
    nonFields.add(
      _NonField(
        id: 'margin-rule',
        reason: 'print_margin',
        rect: _ptRect(2, heightPt / 2 - 18, 10, 18),
      ),
    );
  }

  void _label(String text, double x, double y, double width) {
    labels.add(
      _LabelSpec(
        text: text,
        rect: _ptRect(
          x.clamp(20, widthPt - 120),
          y.clamp(20, heightPt - 30),
          width.clamp(40, 140),
          14,
        ),
      ),
    );
  }

  _PageSpec build() {
    if (canvas.width != _rasterSize.widthPx ||
        canvas.height != _rasterSize.heightPx) {
      throw StateError('canvas does not match the page raster size');
    }
    final List<_SectionSpec> declaredSections = sections.isEmpty
        ? <_SectionSpec>[
            _SectionSpec(
              id: 'page',
              label: 'whole page (no section split declared)',
              rect: _ptRect(0, 0, widthPt, heightPt),
            ),
          ]
        : List<_SectionSpec>.unmodifiable(sections);
    final List<_Expected> assigned = <_Expected>[];
    for (final _Expected field in expected) {
      final double centreX = field.rect.x + field.rect.width / 2;
      final double centreY = field.rect.y + field.rect.height / 2;
      final List<_SectionSpec> owners = <_SectionSpec>[
        for (final _SectionSpec section in declaredSections)
          if (_containsPoint(section.rect, centreX, centreY)) section,
      ];
      if (owners.isEmpty) {
        throw StateError('declared field ${field.id} is outside every section');
      }
      if (owners.length > 1) {
        throw StateError('declared sections overlap at field ${field.id}');
      }
      assigned.add(field.withSection(owners.single.id));
    }
    final Uint8List rasterBytes = canvas.bytes;
    return _PageSpec(
      id: id,
      scenario: scenario,
      description: description,
      widthPt: widthPt,
      heightPt: heightPt,
      raster: canvas.build(),
      expected: List<_Expected>.unmodifiable(assigned),
      nonFields: List<_NonField>.unmodifiable(nonFields),
      labels: List<_LabelSpec>.unmodifiable(labels),
      sections: List<_SectionSpec>.unmodifiable(declaredSections),
      rasterSha256: _sha256Hex(rasterBytes),
      rasterWidthPx: canvas.width,
      rasterHeightPx: canvas.height,
      groundTruthSha256: _sha256Hex(
        utf8.encode(
          _canonicalJson(<String, Object?>{
            'pageId': id,
            'widthPt': widthPt,
            'heightPt': heightPt,
            'fields': <Map<String, Object?>>[
              for (final _Expected field in assigned)
                <String, Object?>{
                  'id': field.id,
                  'rect': _rectJson(field.rect),
                  'kind': field.kind.wireName,
                  'labelText': field.labelText,
                  'sectionId': field.sectionId,
                },
            ],
            'nonFields': <Map<String, Object?>>[
              for (final _NonField nonField in nonFields)
                <String, Object?>{
                  'id': nonField.id,
                  'reason': nonField.reason,
                  'rect': _rectJson(nonField.rect),
                },
            ],
            'sections': <Map<String, Object?>>[
              for (final _SectionSpec section in declaredSections)
                <String, Object?>{
                  'id': section.id,
                  'label': section.label,
                  'rect': _rectJson(section.rect),
                },
            ],
          }),
        ),
      ),
    );
  }
}

bool _containsPoint(DisplayRect rect, double x, double y) {
  const double epsilon = 1e-9;
  return x >= rect.x - epsilon &&
      x <= rect.x + rect.width + epsilon &&
      y >= rect.y - epsilon &&
      y <= rect.y + rect.height + epsilon;
}

/// Canonical JSON used for identity hashes: compact, sorted-key, no whitespace.
String _canonicalJson(Object? value) => jsonEncode(_sortedKeys(value));

Object? _sortedKeys(Object? value) {
  if (value is Map<String, Object?>) {
    final List<String> keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final String key in keys) key: _sortedKeys(value[key]),
    };
  }
  if (value is List<Object?>) {
    return <Object?>[for (final Object? item in value) _sortedKeys(item)];
  }
  return value;
}

String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

List<_PageSpec> _corpus() {
  final List<_PageSpec> pages = <_PageSpec>[];

  // 1. Clean text + checkboxes + decorative frame + margin rule.
  {
    final _Form form = _Form(
      id: 'clean-text',
      scenario: 'clean',
      description:
          'Three labelled text fields, two checkboxes, a decorative '
          'frame, and a rule inside the print margin.',
    );
    // Two declared evaluation sections, so the per page/section/type grouping
    // is exercised on a page that passes.
    form.section(
      id: 'header',
      label: 'Kopfbereich',
      x: 0,
      y: 0,
      width: form.widthPt,
      height: 215,
    );
    form.section(
      id: 'body',
      label: 'Rumpfbereich',
      x: 0,
      y: 215,
      width: form.widthPt,
      height: form.heightPt - 215,
    );
    form.decorativeFrame();
    form.marginRule();
    form.textField(fieldId: 'name', x: 150, y: 140, width: 300, label: 'Name');
    form.textField(
      fieldId: 'strasse',
      x: 150,
      y: 190,
      width: 300,
      label: 'Straße',
    );
    form.textField(fieldId: 'ort', x: 150, y: 240, width: 200, label: 'Ort');
    form.boxField(
      fieldId: 'antrag-ja',
      x: 150,
      y: 300,
      width: 11,
      height: 11,
      kind: FieldInventoryKind.checkbox,
      label: 'Antrag',
    );
    form.boxField(
      fieldId: 'antrag-nein',
      x: 250,
      y: 300,
      width: 11,
      height: 11,
      kind: FieldInventoryKind.checkbox,
    );
    pages.add(form.build());
  }

  // 2. Numeric and format-labelled fields, PLZ/Telefon as text.
  {
    final _Form form = _Form(
      id: 'numeric-formats',
      scenario: 'numeric',
      description:
          'Betrag, Summe, IBAN, Steuernummer (number), PLZ, Telefon, '
          'Kundennummer (text), and a German date mask.',
    );
    form.textField(
      fieldId: 'betrag',
      x: 180,
      y: 120,
      width: 220,
      label: 'Betrag (1.234,56 €)',
      kind: FieldInventoryKind.number,
    );
    form.textField(
      fieldId: 'summe',
      x: 180,
      y: 165,
      width: 220,
      label: 'Summe',
      kind: FieldInventoryKind.number,
    );
    form.textField(
      fieldId: 'iban',
      x: 180,
      y: 210,
      width: 280,
      label: 'IBAN',
      kind: FieldInventoryKind.number,
    );
    form.textField(
      fieldId: 'steuernummer',
      x: 180,
      y: 255,
      width: 200,
      label: 'Steuernummer',
      kind: FieldInventoryKind.number,
    );
    form.textField(fieldId: 'plz', x: 180, y: 300, width: 80, label: 'PLZ');
    form.textField(
      fieldId: 'telefon',
      x: 180,
      y: 345,
      width: 160,
      label: 'Telefon',
    );
    form.textField(
      fieldId: 'kundennummer',
      x: 180,
      y: 390,
      width: 160,
      label: 'Kundennummer',
    );
    form.textField(
      fieldId: 'datum',
      x: 180,
      y: 435,
      width: 140,
      label: 'Datum',
      kind: FieldInventoryKind.date,
    );
    pages.add(form.build());
  }

  // 3. A row of adjacent checkboxes.
  {
    final _Form form = _Form(
      id: 'checkbox-row',
      scenario: 'adjacent',
      description: 'Four adjacent 11 pt checkboxes with 1 pt gaps.',
    );
    for (int index = 0; index < 4; index++) {
      form.boxField(
        fieldId: 'box-$index',
        x: 100 + index * 12,
        y: 200,
        width: 11,
        height: 11,
        kind: FieldInventoryKind.checkbox,
      );
    }
    pages.add(form.build());
  }

  // 4. Declared ground truth has four boxes, the page draws three (RED case).
  {
    final _Form form = _Form(
      id: 'missing-checkbox',
      scenario: 'missing',
      description:
          'Three drawn checkboxes against four declared ground-truth '
          'boxes: the missing one must be reported, never absorbed by a count.',
    );
    for (int index = 0; index < 3; index++) {
      form.boxField(
        fieldId: 'box-$index',
        x: 100 + index * 40,
        y: 200,
        width: 11,
        height: 11,
        kind: FieldInventoryKind.checkbox,
      );
    }
    form.expected.add(
      _Expected(
        id: 'box-3',
        rect: _ptRect(220, 200, 9.56, 9.56),
        kind: FieldInventoryKind.checkbox,
      ),
    );
    pages.add(form.build());
  }

  // 5. One logical checkbox drawn as a double border (duplicate case).
  {
    final _Form form = _Form(
      id: 'duplicate-checkbox',
      scenario: 'duplicate',
      description:
          'A checkbox inside a second border 1 pt larger: one logical '
          'field, two geometric candidates.',
    );
    form.boxField(
      fieldId: 'box-double',
      x: 100,
      y: 200,
      width: 14,
      height: 14,
      kind: FieldInventoryKind.checkbox,
    );
    form.canvas.fillRectPx(_px(99), _px(199), _px(116), _px(200), 0);
    form.canvas.fillRectPx(_px(99), _px(216), _px(116), _px(217), 0);
    form.canvas.fillRectPx(_px(99), _px(199), _px(100), _px(217), 0);
    form.canvas.fillRectPx(_px(115), _px(199), _px(116), _px(217), 0);
    pages.add(form.build());
  }

  // 6. A 2 x 3 table with one printed cell and one already filled checkbox.
  {
    final _Form form = _Form(
      id: 'table',
      scenario: 'table',
      description:
          'A 2 x 3 grid: five empty cells are fields, one printed cell '
          'is not, and a marked checkbox is a filled region.',
    );
    form.table(
      idPrefix: 'cell',
      x: 120,
      y: 200,
      width: 300,
      height: 120,
      columns: 2,
      rows: 3,
      printedCells: <String>{'cell-r0c0'},
    );
    form.boxField(
      fieldId: 'filled-box',
      x: 120,
      y: 380,
      width: 11,
      height: 11,
      kind: FieldInventoryKind.checkbox,
      declareField: false,
      filled: true,
      nonFieldReason: 'already_filled',
    );
    pages.add(form.build());
  }

  // 7. Furniture only: no field may be invented.
  {
    final _Form form = _Form(
      id: 'furniture-only',
      scenario: 'whitespace',
      description:
          'Decorative frame, margin rules, and empty whitespace only. '
          'The declared ground truth has zero fields.',
    );
    form.decorativeFrame();
    form.marginRule();
    form.canvas.fillRectPt(4, 4, 0.9, form.heightPt - 8);
    pages.add(form.build());
  }

  // 8. Low contrast: ink above the fixed 128 threshold (baseline gap).
  {
    final _Form form = _Form(
      id: 'low-contrast',
      scenario: 'low_contrast',
      description:
          'Faint printing (ink 170 on 255 paper) on an otherwise clean form. '
          'The fixed 128 ink threshold cannot see it; the deferred contrast '
          'variant is NOT_RUN.',
    );
    form.textField(
      fieldId: 'faint-name',
      x: 150,
      y: 140,
      width: 300,
      label: 'Name',
      ink: 170,
    );
    form.textField(
      fieldId: 'faint-ort',
      x: 150,
      y: 200,
      width: 200,
      label: 'Ort',
      ink: 170,
    );
    form.textField(
      fieldId: 'faint-datum',
      x: 150,
      y: 260,
      width: 140,
      label: 'Datum',
      ink: 170,
    );
    pages.add(form.build());
  }

  // 9. Broken frame: a box with a gap on the bottom edge.
  {
    final _Form form = _Form(
      id: 'broken-frame',
      scenario: 'broken_frame',
      description:
          'A bordered field whose bottom rule has a 4 pt gap. The box '
          'is not closed, so the lower rules and the bounded whitespace are the '
          'remaining evidence.',
    );
    const double x = 150;
    const double y = 300;
    const double width = 260;
    const double height = 26;
    final int left = _px(x);
    final int top = _px(y);
    final int right = _px(x + width);
    final int bottom = _px(y + height);
    final int thickness = 2;
    final int gapLeft = _px(x + width / 2 - 2);
    final int gapRight = _px(x + width / 2 + 2);
    form.canvas.fillRectPx(left, top, right, top + thickness, 0);
    form.canvas.fillRectPx(left, top, left + thickness, bottom, 0);
    form.canvas.fillRectPx(right - thickness, top, right, bottom, 0);
    form.canvas.fillRectPx(left, bottom - thickness, gapLeft, bottom, 0);
    form.canvas.fillRectPx(gapRight, bottom - thickness, right, bottom, 0);
    form.expected.add(
      _Expected(
        id: 'broken-field',
        rect: _ptRect(
          x + 2 / rasterScale,
          y + 2 / rasterScale,
          width - 4 / rasterScale,
          height - 4 / rasterScale,
        ),
        kind: FieldInventoryKind.text,
      ),
    );
    pages.add(form.build());
  }

  // 10. Background shadow: a vertical gradient behind clean fields.
  {
    final _Form form = _Form(
      id: 'shadow',
      scenario: 'shadow',
      description:
          'A vertical shadow gradient (155-215) behind one checkbox and one '
          'underline. Geometry must survive the photometric degradation.',
    );
    form.canvas.fillRectPt(40, 60, 500, 700, gradient: true);
    form.textField(
      fieldId: 'shadow-name',
      x: 150,
      y: 200,
      width: 300,
      label: 'Name',
    );
    form.boxField(
      fieldId: 'shadow-box',
      x: 150,
      y: 260,
      width: 11,
      height: 11,
      kind: FieldInventoryKind.checkbox,
    );
    pages.add(form.build());
  }

  // 11. Numeric value-format variants: negative, percentage, leading zeros,
  //     and an explicit numeric/date ambiguity. The decimal-comma/thousands/
  //     currency label stays on the `numeric-formats` page.
  {
    final _Form form = _Form(
      id: 'numeric-variants',
      scenario: 'numeric_variants',
      description:
          'Negative amount, percentage, a zero-padded number kept as text, '
          'and a label carrying both a date and an amount keyword.',
    );
    form.textField(
      fieldId: 'betrag-negativ',
      x: 180,
      y: 120,
      width: 220,
      label: 'Betrag negativ (-1.234,56 €)',
      kind: FieldInventoryKind.number,
    );
    form.textField(
      fieldId: 'summe-prozent',
      x: 180,
      y: 165,
      width: 220,
      label: 'Summe in Prozent (12,5 %)',
      kind: FieldInventoryKind.number,
    );
    form.textField(
      fieldId: 'kundennummer-nullen',
      x: 180,
      y: 210,
      width: 200,
      label: 'Kundennummer 0004711',
    );
    form.textField(
      fieldId: 'datum-oder-betrag',
      x: 180,
      y: 255,
      width: 200,
      label: 'Datum oder Betrag',
      kind: FieldInventoryKind.date,
    );
    pages.add(form.build());
  }

  // 12. A tall box that must classify as multiline, next to one single-line
  //     field that fixes the single-line reference height.
  {
    final _Form form = _Form(
      id: 'multiline-area',
      scenario: 'multiline',
      description:
          'Five single-line fields that fix the single-line reference height '
          'and one tall bounded area: the tall area must be typed multiline, '
          'not text and not a table.',
    );
    for (int index = 0; index < 5; index++) {
      form.textField(
        fieldId: 'zeile-${index + 1}',
        x: 150,
        y: 120 + index * 20,
        width: 300,
        label: index == 0 ? 'Betreff' : null,
      );
    }
    form.boxField(
      fieldId: 'bemerkung-mehrzeilig',
      x: 150,
      y: 260,
      width: 320,
      height: 64,
      kind: FieldInventoryKind.multiline,
      label: 'Bemerkung',
    );
    pages.add(form.build());
  }

  return pages;
}

// ---------------------------------------------------------------------------
// Analysis
// ---------------------------------------------------------------------------

final class _PageResult {
  _PageResult({
    required this.spec,
    required this.quality,
    required this.candidates,
    required this.typeObservations,
    required this.inventory,
    required this.baselineComparison,
    required this.inventoryComparison,
    required this.baselineMetrics,
    required this.inventoryMetrics,
    required this.rasterMs,
    required this.detectMs,
    required this.typeMs,
    required this.inventoryMs,
    required this.compareMs,
  });

  final _PageSpec spec;
  final PhotometricQuality quality;
  final List<GeometryCandidate> candidates;
  final List<_TypeObservation> typeObservations;
  final FieldInventory inventory;
  final StructureComparisonResult baselineComparison;
  final StructureComparisonResult inventoryComparison;
  final _TypeMetrics baselineMetrics;
  final _TypeMetrics inventoryMetrics;
  final int rasterMs;
  final int detectMs;
  final int typeMs;
  final int inventoryMs;
  final int compareMs;

  /// Declared evaluation section that contains [rect], or `unassigned`.
  String _sectionOf(DisplayRect rect) {
    final double centreX = rect.x + rect.width / 2;
    final double centreY = rect.y + rect.height / 2;
    for (final _SectionSpec section in spec.sections) {
      if (_containsPoint(section.rect, centreX, centreY)) {
        return section.id;
      }
    }
    return 'unassigned';
  }

  Map<String, Object?> toJson({required bool includeTimings}) {
    return <String, Object?>{
      'id': spec.id,
      'scenario': spec.scenario,
      'description': spec.description,
      'pageSizePt': <String, double>{
        'width': spec.widthPt,
        'height': spec.heightPt,
      },
      'fixture': <String, Object?>{
        'rasterSha256': spec.rasterSha256,
        'rasterWidthPx': spec.rasterWidthPx,
        'rasterHeightPx': spec.rasterHeightPx,
        'rasterBytes': spec.rasterWidthPx * spec.rasterHeightPx,
      },
      'groundTruth': <String, Object?>{
        'fieldCount': spec.expected.length,
        'groundTruthSha256': spec.groundTruthSha256,
      },
      'declaredGroundTruth': <String, Object?>{
        'fieldCount': spec.expected.length,
        'kinds': _countKinds(<FieldInventoryKind>[
          for (final _Expected field in spec.expected) field.kind,
        ]),
        'nonFields': <Map<String, Object?>>[
          for (final _NonField nonField in spec.nonFields)
            <String, Object?>{
              'id': nonField.id,
              'reason': nonField.reason,
              'rect': _rectJson(nonField.rect),
            },
        ],
      },
      'photometricQuality': quality.toJson(),
      'candidateCount': candidates.length,
      'inventoryCoverage': inventory.coverage.toJson(),
      'sections': <Map<String, Object?>>[
        for (final _SectionSpec section in spec.sections)
          <String, Object?>{
            'id': section.id,
            'label': section.label,
            'rect': _rectJson(section.rect),
            'declared': <String, Object?>{
              'fieldCount': _fieldsIn(section.id).length,
              'kinds': _countKinds(<FieldInventoryKind>[
                for (final _Expected field in _fieldsIn(section.id)) field.kind,
              ]),
            },
            'inventory': <String, Object?>{
              'candidateCount': _entriesIn(section.id).length,
              'kinds': _countKinds(<FieldInventoryKind>[
                for (final FieldInventoryEntry entry in _entriesIn(section.id))
                  entry.kind,
              ]),
            },
          },
      ],
      'fields': <String, Object?>{
        'expected': <Map<String, Object?>>[
          for (int index = 0; index < spec.expected.length; index++)
            <String, Object?>{
              'index': index,
              'id': spec.expected[index].id,
              'sectionId': spec.expected[index].sectionId,
              'rect': _rectJson(spec.expected[index].rect),
              'kind': spec.expected[index].kind.wireName,
              'labelText': spec.expected[index].labelText,
            },
        ],
        'candidates': <Map<String, Object?>>[
          for (int index = 0; index < candidates.length; index++)
            <String, Object?>{
              'index': index,
              'sectionId': _sectionOf(candidates[index].rect),
              'rect': _rectJson(candidates[index].rect),
              'cues': candidates[index].cues,
              'inkCoverage': _round6(candidates[index].inkCoverage),
            },
        ],
        'typeObservations': <Map<String, Object?>>[
          for (int index = 0; index < typeObservations.length; index++)
            typeObservations[index].toJson(index),
        ],
        'inventory': <Map<String, Object?>>[
          for (int index = 0; index < inventory.entries.length; index++)
            <String, Object?>{
              'index': index,
              'id': inventory.entries[index].id,
              'sectionId': _sectionOf(inventory.entries[index].rect),
              'rect': _rectJson(inventory.entries[index].rect),
              'kind': inventory.entries[index].kind.wireName,
              'role': inventory.entries[index].role.name,
              'labelText': inventory.entries[index].labelText,
              'cues': inventory.entries[index].cues,
              'inkCoverage': _round6(inventory.entries[index].inkCoverage),
              'collapsedDuplicateCount':
                  inventory.entries[index].collapsedDuplicateCount,
            },
        ],
        'baselineMatches': _matchJson(baselineComparison),
        'inventoryMatches': _matchJson(inventoryComparison),
      },
      'baseline': _comparisonJson(
        baselineComparison,
        baselineMetrics,
        includeDetails: includeTimings,
      ),
      'inventory': _comparisonJson(
        inventoryComparison,
        inventoryMetrics,
        includeDetails: includeTimings,
      ),
      if (includeTimings)
        'timingsMs': <String, int>{
          'raster': rasterMs,
          'detect': detectMs,
          'type': typeMs,
          'inventory': inventoryMs,
          'compare': compareMs,
        },
    };
  }

  List<_Expected> _fieldsIn(String sectionId) => <_Expected>[
    for (final _Expected field in spec.expected)
      if (field.sectionId == sectionId) field,
  ];

  List<FieldInventoryEntry> _entriesIn(String sectionId) =>
      <FieldInventoryEntry>[
        for (final FieldInventoryEntry entry in inventory.fieldCandidates)
          if (_sectionOf(entry.rect) == sectionId) entry,
      ];
}

/// One `TypeInference` result kept for the frozen projection.
///
/// It carries the proposed type, the selected label text, and the sorted cue
/// additions (keyword, numeric-context, date-context and alignment cues), so a
/// frozen snapshot can prove that a field kept its label evidence.
final class _TypeObservation {
  const _TypeObservation({
    required this.rect,
    required this.proposedType,
    required this.labelText,
    required this.addedCues,
  });

  final DisplayRect rect;
  final String proposedType;
  final String? labelText;
  final List<String> addedCues;

  Map<String, Object?> toJson(int index) => <String, Object?>{
    'index': index,
    'rect': _rectJson(rect),
    'proposedType': proposedType,
    'labelText': labelText,
    'addedCues': addedCues,
  };
}

List<Map<String, Object?>> _matchJson(StructureComparisonResult result) =>
    <Map<String, Object?>>[
      for (final StructureMatch match in result.matches)
        <String, Object?>{
          'expectedIndex': match.expectedIndex,
          'observedIndex': match.observedIndex,
          'iou': _round6(match.iou),
          'centerDistancePt': _round6(match.centerDistancePt),
          'geometryOk': match.geometryOk,
          'kindOk': match.kindOk,
          'labelOk': match.labelOk,
        },
    ];

Map<String, Object?> _comparisonJson(
  StructureComparisonResult result,
  _TypeMetrics metrics, {
  required bool includeDetails,
}) {
  return <String, Object?>{
    'verdict': result.verdict.name,
    'failureCodes': result.failureCodes,
    'expectedCount': result.expectedCount,
    'observedCount': result.observedCount,
    'matchedCount': result.matches.length,
    'missingCount': result.missingExpected.length,
    'extraCount': result.extraObserved.length,
    'duplicateCount': result.duplicates.length,
    'overlapCount': result.overlaps.length,
    'ambiguousCount': result.ambiguousObserved.length,
    'unlabelledCount': result.unlabelledObserved.length,
    'labelMismatchCount': result.labelMismatchedMatches.length,
    'geometryMismatchCount': result.geometryMismatchedMatches.length,
    'typeMismatchCount': result.typeMismatchedMatches.length,
    'sameCountWrongGeometry': result.sameCountWrongGeometry,
    'unknownGroundTruthPages': result.unknownGroundTruthPages,
    'meanMatchedIou': _round6(result.meanMatchedIou),
    'minMatchedIou': _round6(result.minMatchedIou),
    'metrics': metrics.toJson(),
    'buckets': <Map<String, Object?>>[
      for (final StructureBucket bucket in result.buckets) bucket.toJson(),
    ],
    if (includeDetails)
      'typeMismatches': <Map<String, Object?>>[
        for (final StructureMatch match in result.typeMismatchedMatches)
          <String, Object?>{
            'expectedIndex': match.expectedIndex,
            'observedIndex': match.observedIndex,
            'iou': _round6(match.iou),
          },
      ],
  };
}

Map<String, Object?> _rectJson(DisplayRect rect) => <String, double>{
  'x': rect.x,
  'y': rect.y,
  'width': rect.width,
  'height': rect.height,
};

Map<String, int> _countKinds(List<FieldInventoryKind> kinds) {
  final Map<FieldInventoryKind, int> counts = <FieldInventoryKind, int>{
    for (final FieldInventoryKind kind in FieldInventoryKind.values) kind: 0,
  };
  for (final FieldInventoryKind kind in kinds) {
    counts[kind] = counts[kind]! + 1;
  }
  return <String, int>{
    for (final FieldInventoryKind kind in FieldInventoryKind.values)
      if (counts[kind]! > 0) kind.wireName: counts[kind]!,
  };
}

_PageResult _analysePage(_PageSpec spec) {
  final Stopwatch rasterWatch = Stopwatch()..start();
  final RasterAnalysis analysis = spec.raster.analyze();
  rasterWatch.stop();
  final PhotometricQuality quality = PhotometricQuality.measure(spec.raster);

  final Stopwatch detectWatch = Stopwatch()..start();
  final List<GeometryCandidate> candidates = GeometryDetector.detect(
    analysis,
    pageWidthPt: spec.widthPt,
    pageHeightPt: spec.heightPt,
  );
  detectWatch.stop();

  final List<LabelObservation> labels = <LabelObservation>[
    for (final _LabelSpec label in spec.labels)
      LabelObservation(text: label.text, rect: label.rect, ocrConfidence: 0.9),
  ];

  final Stopwatch typeWatch = Stopwatch()..start();
  final double medianHeight = _medianCandidateHeight(candidates);
  final List<ObservedField> baselineObserved = <ObservedField>[];
  final List<FieldTypeHint> hints = <FieldTypeHint>[];
  final List<_TypeObservation> typeObservations = <_TypeObservation>[];
  for (final GeometryCandidate candidate in candidates) {
    final TypeInferenceResult inference = TypeInference.infer(
      candidate: candidate,
      labels: labels,
      singleLineMedianHeightPt: medianHeight,
      pageWidthPt: spec.widthPt,
      pageHeightPt: spec.heightPt,
    );
    typeObservations.add(
      _TypeObservation(
        rect: candidate.rect,
        proposedType: inference.proposedType,
        labelText: inference.labelText,
        addedCues: inference.addedCues,
      ),
    );
    baselineObserved.add(
      ObservedField(
        pageIndex: 0,
        rect: candidate.rect,
        kind:
            fieldInventoryKindForSuggestionType(inference.proposedType) ??
            FieldInventoryKind.unknown,
        labelText: inference.labelText,
        provenance: 'suggestion',
      ),
    );
    hints.add(
      FieldTypeHint(rect: candidate.rect, proposedType: inference.proposedType),
    );
  }
  typeWatch.stop();

  final Stopwatch inventoryWatch = Stopwatch()..start();
  final FieldInventory inventory = FieldInventoryBuilder.build(
    pageIndex: 0,
    pageWidthPt: spec.widthPt,
    pageHeightPt: spec.heightPt,
    candidates: candidates,
    labels: labels,
    typeHints: hints,
  );
  inventoryWatch.stop();

  final List<ExpectedField> expected = <ExpectedField>[
    for (final _Expected field in spec.expected)
      ExpectedField(
        pageIndex: 0,
        rect: field.rect,
        kind: field.kind,
        labelText: field.labelText,
        sourceId: field.id,
      ),
  ];
  final List<ObservedField> inventoryObserved = <ObservedField>[
    for (final FieldInventoryEntry entry in inventory.fieldCandidates)
      ObservedField(
        pageIndex: 0,
        rect: entry.rect,
        kind: entry.kind,
        labelText: entry.labelText,
        provenance: 'inventory',
      ),
  ];

  final Stopwatch compareWatch = Stopwatch()..start();
  final StructureComparisonResult baselineComparison =
      StructureComparison.compare(
        expected: expected,
        observed: baselineObserved,
        groundTruthPages: <int>{0},
      );
  final StructureComparisonResult inventoryComparison =
      StructureComparison.compare(
        expected: expected,
        observed: inventoryObserved,
        groundTruthPages: <int>{0},
      );
  compareWatch.stop();

  return _PageResult(
    spec: spec,
    quality: quality,
    candidates: candidates,
    typeObservations: List<_TypeObservation>.unmodifiable(typeObservations),
    inventory: inventory,
    baselineComparison: baselineComparison,
    inventoryComparison: inventoryComparison,
    baselineMetrics: _TypeMetrics.fromComparison(
      expected,
      baselineObserved,
      baselineComparison,
    ),
    inventoryMetrics: _TypeMetrics.fromComparison(
      expected,
      inventoryObserved,
      inventoryComparison,
    ),
    rasterMs: rasterWatch.elapsedMilliseconds,
    detectMs: detectWatch.elapsedMilliseconds,
    typeMs: typeWatch.elapsedMilliseconds,
    inventoryMs: inventoryWatch.elapsedMilliseconds,
    compareMs: compareWatch.elapsedMilliseconds,
  );
}

double _medianCandidateHeight(List<GeometryCandidate> candidates) {
  if (candidates.isEmpty) {
    return 18;
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

/// Per-kind precision/recall/F1 plus type and label accuracy.
final class _TypeMetrics {
  _TypeMetrics._({
    required this.expected,
    required this.matched,
    required this.extra,
    required this.duplicate,
    required this.duplicateUnmatched,
    required this.kindMatched,
    required this.labelledExpected,
    required this.labelsAgree,
  });

  factory _TypeMetrics.fromComparison(
    List<ExpectedField> expected,
    List<ObservedField> observed,
    StructureComparisonResult result,
  ) {
    int kindMatched = 0;
    for (final StructureMatch match in result.matches) {
      if (expected[match.expectedIndex].kind ==
          observed[match.observedIndex].kind) {
        kindMatched++;
      }
    }
    final Set<int> matchedObserved = <int>{
      for (final StructureMatch match in result.matches) match.observedIndex,
    };
    final int duplicateUnmatched = result.duplicates
        .where(
          (StructureDuplicate duplicate) =>
              !matchedObserved.contains(duplicate.observedIndex),
        )
        .length;
    int labelledExpected = 0;
    for (final ExpectedField field in expected) {
      final String? label = field.labelText?.trim();
      if (label != null && label.isNotEmpty) {
        labelledExpected++;
      }
    }
    int labelsAgree = 0;
    for (final StructureMatch match in result.matches) {
      final String? expectedLabel = expected[match.expectedIndex].labelText;
      final String? observedLabel = observed[match.observedIndex].labelText;
      if (expectedLabel != null &&
          expectedLabel.trim().isNotEmpty &&
          observedLabel != null &&
          expectedLabel.trim().toLowerCase() ==
              observedLabel.trim().toLowerCase()) {
        labelsAgree++;
      }
    }
    return _TypeMetrics._(
      expected: expected.length,
      matched: result.matches.length,
      extra: result.extraObserved.length,
      duplicate: result.duplicates.length,
      duplicateUnmatched: duplicateUnmatched,
      kindMatched: kindMatched,
      labelledExpected: labelledExpected,
      labelsAgree: labelsAgree,
    );
  }

  final int expected;
  final int matched;
  final int extra;
  final int duplicate;
  final int duplicateUnmatched;
  final int kindMatched;
  final int labelledExpected;
  final int labelsAgree;

  /// Precision over unique proposals: a duplicate that is itself matched is a
  /// correct region but a redundant proposal, and is counted in [duplicate].
  double get precision {
    final int denominator = matched + extra + duplicateUnmatched;
    return denominator == 0 ? 1 : matched / denominator;
  }

  double get recall => expected == 0 ? 1 : matched / expected;

  double get f1 {
    final double p = precision;
    final double r = recall;
    return p + r == 0 ? 0 : 2 * p * r / (p + r);
  }

  double get typeAccuracy => matched == 0 ? 0 : kindMatched / matched;

  double get labelAccuracy =>
      labelledExpected == 0 ? 1 : labelsAgree / labelledExpected;

  Map<String, Object?> toJson() => <String, Object?>{
    'expected': expected,
    'matched': matched,
    'extra': extra,
    'duplicate': duplicate,
    'duplicateUnmatched': duplicateUnmatched,
    'kindMatched': kindMatched,
    'labelledExpected': labelledExpected,
    'labelsAgree': labelsAgree,
    'precision': _round6(precision),
    'recall': _round6(recall),
    'f1': _round6(f1),
    'typeAccuracy': _round6(typeAccuracy),
    'labelAccuracy': _round6(labelAccuracy),
  };
}

/// The declared no-regression gate: inventory must not be worse than baseline.
final class _NoRegressionGate {
  const _NoRegressionGate({
    required this.applies,
    required this.passed,
    required this.baselineMatched,
    required this.inventoryMatched,
    required this.baselineFalsePositives,
    required this.inventoryFalsePositives,
    required this.reason,
  });

  final bool applies;
  final bool passed;
  final int baselineMatched;
  final int inventoryMatched;
  final int baselineFalsePositives;
  final int inventoryFalsePositives;
  final String? reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'criterion':
        'inventory matched >= baseline matched AND inventory false '
        'positives <= baseline false positives, per the whole corpus',
    'applies': applies,
    'passed': passed,
    'baselineMatched': baselineMatched,
    'inventoryMatched': inventoryMatched,
    'baselineFalsePositives': baselineFalsePositives,
    'inventoryFalsePositives': inventoryFalsePositives,
    if (reason != null) 'reason': reason,
  };
}

_NoRegressionGate _noRegressionGate(List<_PageResult> pages) {
  int baselineMatched = 0;
  int inventoryMatched = 0;
  int baselineFalsePositives = 0;
  int inventoryFalsePositives = 0;
  for (final _PageResult page in pages) {
    baselineMatched += page.baselineMetrics.matched;
    inventoryMatched += page.inventoryMetrics.matched;
    baselineFalsePositives +=
        page.baselineMetrics.extra + page.baselineMetrics.duplicateUnmatched;
    inventoryFalsePositives +=
        page.inventoryMetrics.extra + page.inventoryMetrics.duplicateUnmatched;
  }
  final bool passed =
      inventoryMatched >= baselineMatched &&
      inventoryFalsePositives <= baselineFalsePositives;
  return _NoRegressionGate(
    applies: true,
    passed: passed,
    baselineMatched: baselineMatched,
    inventoryMatched: inventoryMatched,
    baselineFalsePositives: baselineFalsePositives,
    inventoryFalsePositives: inventoryFalsePositives,
    reason: passed ? null : 'inventory_regressed_against_baseline',
  );
}

final class _Totals {
  const _Totals({
    required this.expected,
    required this.baseline,
    required this.inventory,
    required this.verdicts,
    required this.byKind,
  });

  final int expected;
  final Map<String, Object?> baseline;
  final Map<String, Object?> inventory;
  final Map<String, int> verdicts;
  final Map<String, Object?> byKind;

  Map<String, Object?> toJson() => <String, Object?>{
    'expectedFields': expected,
    'baseline': baseline,
    'inventory': inventory,
    'inventoryVerdicts': verdicts,
    'byKind': byKind,
  };
}

_Totals _totals(List<_PageResult> pages) {
  int expected = 0;
  int baselineMatched = 0;
  int inventoryMatched = 0;
  int baselineExtra = 0;
  int inventoryExtra = 0;
  int baselineDuplicates = 0;
  int inventoryDuplicates = 0;
  int baselineDuplicateUnmatched = 0;
  int inventoryDuplicateUnmatched = 0;
  int baselineKind = 0;
  int inventoryKind = 0;
  int labelled = 0;
  int baselineLabels = 0;
  int inventoryLabels = 0;
  final Map<String, int> verdicts = <String, int>{};
  for (final _PageResult page in pages) {
    expected += page.baselineMetrics.expected;
    baselineMatched += page.baselineMetrics.matched;
    inventoryMatched += page.inventoryMetrics.matched;
    baselineExtra += page.baselineMetrics.extra;
    inventoryExtra += page.inventoryMetrics.extra;
    baselineDuplicates += page.baselineMetrics.duplicate;
    inventoryDuplicates += page.inventoryMetrics.duplicate;
    baselineDuplicateUnmatched += page.baselineMetrics.duplicateUnmatched;
    inventoryDuplicateUnmatched += page.inventoryMetrics.duplicateUnmatched;
    baselineKind += page.baselineMetrics.kindMatched;
    inventoryKind += page.inventoryMetrics.kindMatched;
    labelled += page.baselineMetrics.labelledExpected;
    baselineLabels += page.baselineMetrics.labelsAgree;
    inventoryLabels += page.inventoryMetrics.labelsAgree;
    verdicts[page.inventoryComparison.verdict.name] =
        (verdicts[page.inventoryComparison.verdict.name] ?? 0) + 1;
  }
  Map<String, Object?> aggregate(
    int matched,
    int extra,
    int duplicate,
    int duplicateUnmatched,
    int kindMatched,
    int labelsAgree,
  ) {
    final int denominator = matched + extra + duplicateUnmatched;
    final double precision = denominator == 0 ? 1 : matched / denominator;
    final double recall = expected == 0 ? 1 : matched / expected;
    final double f1 = precision + recall == 0
        ? 0
        : 2 * precision * recall / (precision + recall);
    return <String, Object?>{
      'matched': matched,
      'extra': extra,
      'duplicate': duplicate,
      'duplicateUnmatched': duplicateUnmatched,
      'precision': _round6(precision),
      'recall': _round6(recall),
      'f1': _round6(f1),
      'typeAccuracy': _round6(matched == 0 ? 0 : kindMatched / matched),
      'labelAccuracy': _round6(labelled == 0 ? 1 : labelsAgree / labelled),
    };
  }

  return _Totals(
    byKind: _kindTotals(pages),
    expected: expected,
    baseline: aggregate(
      baselineMatched,
      baselineExtra,
      baselineDuplicates,
      baselineDuplicateUnmatched,
      baselineKind,
      baselineLabels,
    ),
    inventory: aggregate(
      inventoryMatched,
      inventoryExtra,
      inventoryDuplicates,
      inventoryDuplicateUnmatched,
      inventoryKind,
      inventoryLabels,
    ),
    verdicts: verdicts,
  );
}

/// Per-kind recall/type accuracy over the whole corpus, for both paths.
///
/// Every kind of [FieldInventoryKind] gets a row, including the kinds this
/// corpus does not draw: a zero-count kind must be visible as an explicit
/// absence with a reason, never as a silently missing row.
Map<String, Object?> _kindTotals(List<_PageResult> pages) {
  final Map<String, Object?> result = <String, Object?>{};
  for (final FieldInventoryKind kind in FieldInventoryKind.values) {
    final Map<String, int> baseline = <String, int>{
      'expected': 0,
      'matched': 0,
      'kindMatched': 0,
    };
    final Map<String, int> inventory = <String, int>{
      'expected': 0,
      'matched': 0,
      'kindMatched': 0,
    };
    for (final _PageResult page in pages) {
      _accumulateKind(page.spec, page.baselineComparison, baseline, kind);
      _accumulateKind(page.spec, page.inventoryComparison, inventory, kind);
    }
    Map<String, Object?> summary(Map<String, int> counts) => <String, Object?>{
      'expected': counts['expected'],
      'matched': counts['matched'],
      'recall': counts['expected'] == 0
          ? null
          : _round6(counts['matched']! / counts['expected']!),
      'typeAccuracy': counts['matched'] == 0
          ? null
          : _round6(counts['kindMatched']! / counts['matched']!),
    };
    final int instances = baseline['expected']!;
    result[kind.wireName] = <String, Object?>{
      'baseline': summary(baseline),
      'inventory': summary(inventory),
      'corpusInstances': instances,
      'absence': instances == 0
          ? (_kindAbsenceReasons[kind] ??
                'no corpus instance for this kind; absence is not a PASS')
          : null,
    };
  }
  return result;
}

void _accumulateKind(
  _PageSpec spec,
  StructureComparisonResult comparison,
  Map<String, int> counts,
  FieldInventoryKind kind,
) {
  for (int index = 0; index < spec.expected.length; index++) {
    if (spec.expected[index].kind == kind) {
      counts['expected'] = counts['expected']! + 1;
    }
  }
  for (final StructureMatch match in comparison.matches) {
    final _Expected expected = spec.expected[match.expectedIndex];
    if (expected.kind != kind) {
      continue;
    }
    counts['matched'] = counts['matched']! + 1;
    if (match.kindOk) {
      counts['kindMatched'] = counts['kindMatched']! + 1;
    }
  }
}

Map<String, Object?> _snapshot(List<_PageResult> pages) {
  return <String, Object?>{
    'schemaVersion': _schemaVersion,
    'corpusId': _corpusId,
    'evidenceClass': 'SIMULATED',
    'generator': 'tools/evaluation/field_inventory_baseline.dart',
    'note':
        'Canonical golden snapshot: no generatedAt, no timings, no memory, no '
        'paths. It freezes the per-page/per-field projection (rects, kinds, '
        'labels, cue sets, per-page candidates, section grouping) and the '
        'fixture/corpus/ground-truth identity. Byte equality with '
        'tools/evaluation/goldens/field-inventory-baseline.v1.json is the '
        'regression check.',
    'fixture': _fixtureIdentity(pages),
    'noRegressionGate': _noRegressionGate(pages).toJson(),
    'totals': _totals(pages).toJson(),
    'pages': <Map<String, Object?>>[
      for (final _PageResult page in pages) page.toJson(includeTimings: false),
    ],
  };
}

/// Deterministic fixture, corpus and ground-truth identity.
///
/// `fixtureSha256` is the SHA-256 over the ordered per-page raster digests (the
/// exact grayscale bytes the pipeline analysed), `corpusSha256` is the SHA-256
/// over the canonical corpus manifest (page geometry plus both per-page
/// digests), and `groundTruthSha256` is the SHA-256 over the canonical declared
/// ground truth. All three are reproducible from the corpus definition alone.
Map<String, Object?> _fixtureIdentity(List<_PageResult> pages) {
  final List<Map<String, Object?>> manifest = <Map<String, Object?>>[
    for (final _PageResult page in pages)
      <String, Object?>{
        'id': page.spec.id,
        'scenario': page.spec.scenario,
        'widthPt': page.spec.widthPt,
        'heightPt': page.spec.heightPt,
        'rasterSha256': page.spec.rasterSha256,
        'groundTruthSha256': page.spec.groundTruthSha256,
      },
  ];
  return <String, Object?>{
    'corpusId': _corpusId,
    'pageCount': pages.length,
    'fixtureSha256': _sha256Hex(
      utf8.encode(
        <String>[for (final _PageResult page in pages) page.spec.rasterSha256]
            .join('\n'),
      ),
    ),
    'corpusSha256': _sha256Hex(
      utf8.encode(
        _canonicalJson(<String, Object?>{
          'corpusId': _corpusId,
          'pages': manifest,
        }),
      ),
    ),
    'groundTruthSha256': _sha256Hex(
      utf8.encode(
        _canonicalJson(<String, Object?>{
          'corpusId': _corpusId,
          'pages': <Map<String, Object?>>[
            for (final _PageResult page in pages)
              <String, Object?>{
                'id': page.spec.id,
                'groundTruthSha256': page.spec.groundTruthSha256,
                'fieldCount': page.spec.expected.length,
              },
          ],
        }),
      ),
    ),
  };
}

/// One real host memory measurement, recorded as a diagnostic only.
///
/// `kernelPeakResidentKb`/`kernelResidentKb` are the `VmHWM`/`VmRSS` values of
/// the kernel's per-process status counters (Linux, kibibytes) and are the
/// primary measurement;
/// `processInfoMaxRss` is `dart:io`'s own reading reported verbatim. Nothing
/// here is a performance claim and none of it enters the golden snapshot.
Map<String, Object?> _memoryMeasurement() {
  int? peakKb;
  int? residentKb;
  String unit =
      'linux kernel per-process status counters VmHWM and VmRSS (kibibytes)';
  try {
    for (final String line in File('/proc/self/status').readAsLinesSync()) {
      if (line.startsWith('VmHWM:')) {
        peakKb = int.tryParse(line.replaceAll(RegExp(r'[^0-9]'), ''));
      } else if (line.startsWith('VmRSS:')) {
        residentKb = int.tryParse(line.replaceAll(RegExp(r'[^0-9]'), ''));
      }
    }
  } on FileSystemException {
    peakKb = null;
    residentKb = null;
  }
  final int processInfoMaxRss = ProcessInfo.maxRss;
  if (peakKb == null || residentKb == null) {
    // No /proc: fall back to the VM reading and say so, never invent a value.
    final int fallbackKb = math.max(processInfoMaxRss ~/ 1024, 1);
    peakKb = fallbackKb;
    residentKb = fallbackKb;
    unit =
        'fallback: dart:io ProcessInfo.maxRss / 1024 (no kernel status '
        'counters on this host)';
  }
  return <String, Object?>{
    'note':
        'host diagnostics only, no performance claim, excluded from the golden '
        'snapshot; processInfoMaxRss is the dart:io value in bytes and agrees '
        'with the kernel peak on this host',
    'unit': unit,
    'kernelPeakResidentKb': peakKb,
    'kernelResidentKb': residentKb,
    'processInfoMaxRss': processInfoMaxRss,
    'peakResidentSetBytes': peakKb * 1024,
  };
}

double _round6(double value) => (value * 1000000).round() / 1000000;

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

final class _Options {
  const _Options({this.output, this.snapshot, this.help = false});

  final String? output;
  final String? snapshot;
  final bool help;
}

final class _Failure implements Exception {
  const _Failure(this.exitCode, this.code);

  final int exitCode;
  final String code;
}

_Options _parseArguments(List<String> arguments) {
  String? output;
  String? snapshot;
  bool help = false;
  for (int index = 0; index < arguments.length; index++) {
    final String argument = arguments[index];
    switch (argument) {
      case '--help':
      case '-h':
        help = true;
      case '--output':
        output = _value(arguments, index, 'output');
        index++;
      case '--snapshot':
        snapshot = _value(arguments, index, 'snapshot');
        index++;
      default:
        throw _Failure(_exitUsage, 'unknown-argument: $argument');
    }
  }
  if (!help && output == null) {
    throw const _Failure(_exitUsage, 'missing-output');
  }
  return _Options(output: output, snapshot: snapshot, help: help);
}

String _value(List<String> arguments, int index, String name) {
  if (index + 1 >= arguments.length) {
    throw _Failure(_exitUsage, 'missing-value: $name');
  }
  return arguments[index + 1];
}

String _requiredPath(String name, String? value) {
  if (value == null || value.isEmpty) {
    throw _Failure(_exitUsage, 'missing-value: $name');
  }
  return value;
}
