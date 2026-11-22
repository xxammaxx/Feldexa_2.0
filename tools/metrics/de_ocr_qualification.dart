// T263 German OCR qualification scorer (host-only).
//
// Normative sources:
//  * `specs/001-scanned-form-workflow/research.md` D-18 (frozen corpus, frozen
//    metric definition, matching by IoU >= 0.5 and same type, separated error
//    classes, no re-scoring after seeing results),
//  * `specs/001-scanned-form-workflow/contracts/recognition-output.md` §2/§3.1/
//    §3.2 (suggestion shape, keyword lexicon, type precedence),
//  * issue #263 (raw-text and semantic metrics kept apart, NFC/NFD and
//    ae/oe/ue/ss checks, no silent normalization, unresolved is not a PASS).
//
// The scorer compares recorded OCR text and recorded production suggestions
// against the pre-annotated ground truth of the additive German reference
// suite (`tools/corpus/de-ocr/reference-de.ground-truth.json`). It never runs
// OCR, never invents text, never rewrites document content, and never upgrades
// a SIMULATED or INJECTED run into device evidence.
//
// Usage:
//   dart run tools/metrics/de_ocr_qualification.dart \
//     --run <run.json> [--run <run2.json> ...] \
//     --output <report.json> [--markdown <report.md>] \
//     [--ground-truth <path>] [--require-device-evidence] \
//     [--gt-skew-degrees <deg>]
//
// Raw-text metrics use **no** normalization: ground-truth text and OCR text are
// compared as Unicode code points. Normalization, case folding, NFC/NFD, and
// the German umlaut digraphs are used only for the separately reported
// semantic label comparison, never before a raw comparison.
//
// Exit codes:
//   0  every declared variant was scored and the overall verdict is PASS
//   1  an executed gate failed, or the overall verdict is UNRESOLVED/NOT_RUN
//   2  usage error, unreadable input, or a run that does not describe the
//      annotated fixture/suite/bytes
//
// This tool has no Flutter, Gradle, emulator, or network dependency.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const String _defaultGroundTruth =
    'tools/corpus/de-ocr/reference-de.ground-truth.json';

/// Evidence classes a run file may declare.
const Set<String> _evidenceClasses = <String>{
  'EMULATOR',
  'EMULATOR_INJECTED_RASTER',
  'SIMULATED',
  'TEXT_LAYER',
};

/// Characters the issue requires to be qualified end to end.
const List<String> _requiredCharacters = <String>[
  'Ä',
  'Ö',
  'Ü',
  'ä',
  'ö',
  'ü',
  'ß',
  'ẞ',
  '€',
  '²',
  '³',
];

/// Combining diacritical marks range (U+0300 ... U+036F).
const int _combiningMin = 0x0300;
const int _combiningMax = 0x036F;

Future<void> main(List<String> arguments) async {
  try {
    final _Options options = _parseArguments(arguments);
    if (options.help) {
      stdout.write(_usage);
      return;
    }
    final _GroundTruth groundTruth = _GroundTruth.load(options.groundTruth);
    final List<_Run> runs = <_Run>[
      for (final String path in options.runs) _Run.load(path, groundTruth),
    ];
    if (runs.isEmpty) {
      throw const _Fail('at least one --run file is required');
    }
    final _Report report = _score(
      groundTruth: groundTruth,
      runs: runs,
      requireDeviceEvidence: options.requireDeviceEvidence,
      gtSkewOverride: options.gtSkewDegrees,
    );
    final File output = File(options.output);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
      flush: true,
    );
    stdout.writeln(
      'wrote ${options.output} (overall verdict ${report.overallVerdict})',
    );
    if (options.markdown != null) {
      final File markdown = File(options.markdown!);
      markdown.parent.createSync(recursive: true);
      markdown.writeAsStringSync(report.toMarkdown(), flush: true);
      stdout.writeln('wrote ${options.markdown}');
    }
    for (final _ControlResult control in report.controls) {
      stdout.writeln(
        'control ${control.id} (${control.evidenceClass}): ${control.status}'
        '${control.cer == null ? '' : ' CER ${_pct(control.cer!)}'}',
      );
    }
    for (final _VariantResult result in report.variants) {
      stdout.writeln(
        'variant ${result.id} (${result.evidenceClass}): ${result.status}'
        '${result.cer == null ? '' : ' CER ${_pct(result.cer!)}'}'
        '${result.specialCharacterRecall == null ? '' : ' special-recall ${_pct(result.specialCharacterRecall!)}'}',
      );
    }
    if (report.overallVerdict != 'PASS') {
      exitCode = 1;
    }
  } on _Fail catch (error) {
    stderr.writeln('error: ${error.message}');
    exitCode = 2;
  } on FileSystemException catch (error) {
    stderr.writeln('error: ${error.message} (${error.path ?? ''})');
    exitCode = 2;
  } on FormatException catch (error) {
    stderr.writeln('error: ${error.message}');
    exitCode = 2;
  }
}

final class _Options {
  const _Options({
    required this.groundTruth,
    required this.runs,
    required this.output,
    required this.markdown,
    required this.requireDeviceEvidence,
    required this.gtSkewDegrees,
    required this.help,
  });

  final String groundTruth;
  final List<String> runs;
  final String output;
  final String? markdown;
  final bool requireDeviceEvidence;
  final double? gtSkewDegrees;
  final bool help;
}

_Options _parseArguments(List<String> arguments) {
  String groundTruth = _defaultGroundTruth;
  final List<String> runs = <String>[];
  String? output;
  String? markdown;
  bool requireDeviceEvidence = false;
  double? gtSkewDegrees;
  bool help = false;
  for (int index = 0; index < arguments.length; index++) {
    final String argument = arguments[index];
    String next() {
      index++;
      if (index >= arguments.length || arguments[index].isEmpty) {
        throw _Fail('$argument requires a value');
      }
      return arguments[index];
    }

    switch (argument) {
      case '--run':
        runs.add(next());
      case '--output':
        output = next();
      case '--markdown':
        markdown = next();
      case '--ground-truth':
        groundTruth = next();
      case '--gt-skew-degrees':
        final String raw = next();
        final double? parsed = double.tryParse(raw);
        if (parsed == null || !parsed.isFinite) {
          throw _Fail('--gt-skew-degrees requires a finite number');
        }
        gtSkewDegrees = parsed;
      case '--require-device-evidence':
        requireDeviceEvidence = true;
      case '--help' || '-h':
        help = true;
      default:
        throw _Fail('unknown argument "$argument"');
    }
  }
  if (!help && output == null) {
    throw const _Fail('--output is required');
  }
  return _Options(
    groundTruth: groundTruth,
    runs: runs,
    output: output ?? '',
    markdown: markdown,
    requireDeviceEvidence: requireDeviceEvidence,
    gtSkewDegrees: gtSkewDegrees,
    help: help,
  );
}

/// Content-free failure with a stable message.
final class _Fail implements Exception {
  const _Fail(this.message);
  final String message;
  @override
  String toString() => 'error: $message';
}

// ---------------------------------------------------------------------------
// Ground truth
// ---------------------------------------------------------------------------

final class _Rect {
  const _Rect(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;

  double get right => x + width;
  double get bottom => y + height;
  double get centreY => y + height / 2;

  double get area => width * height;

  double iou(_Rect other) {
    final double left = x > other.x ? x : other.x;
    final double top = y > other.y ? y : other.y;
    final double rightEdge = right < other.right ? right : other.right;
    final double bottomEdge = bottom < other.bottom ? bottom : other.bottom;
    final double widthOverlap = rightEdge - left;
    final double heightOverlap = bottomEdge - top;
    if (widthOverlap <= 0 || heightOverlap <= 0) {
      return 0;
    }
    final double intersection = widthOverlap * heightOverlap;
    return intersection / (area + other.area - intersection);
  }

  List<int> codePointsOf(String text) => text.runes.toList();
}

final class _GtLine {
  const _GtLine({
    required this.id,
    required this.pageIndex,
    required this.text,
    required this.role,
    required this.critical,
    required this.rect,
    required this.presentRequiredCharacters,
  });

  final String id;
  final int pageIndex;
  final String text;
  final String role;
  final bool critical;
  final _Rect rect;
  final List<String> presentRequiredCharacters;
}

final class _GtField {
  const _GtField({
    required this.id,
    required this.pageIndex,
    required this.type,
    required this.label,
    required this.labelLineId,
    required this.rect,
  });

  final String id;
  final int pageIndex;
  final String type;
  final String label;
  final String labelLineId;
  final _Rect rect;
}

final class _VariantSpec {
  const _VariantSpec({
    required this.id,
    required this.evidenceClass,
    required this.requiresExactCriticalLines,
    required this.maxCer,
    required this.maxSpecialCharacterRecallLoss,
    required this.reference,
    required this.description,
  });

  final String id;
  final String evidenceClass;
  final bool requiresExactCriticalLines;
  final double maxCer;
  final double maxSpecialCharacterRecallLoss;
  final bool reference;
  final String description;
}

final class _GroundTruth {
  const _GroundTruth({
    required this.suiteId,
    required this.fixtureId,
    required this.pdfSha256,
    required this.lines,
    required this.fields,
    required this.variants,
    required this.pages,
    this.pageSizes = const <int, ({double widthPt, double heightPt})>{},
    this.skewDegrees = 0,
  });

  final String suiteId;
  final String fixtureId;
  final String pdfSha256;
  final List<_GtLine> lines;
  final List<_GtField> fields;
  final List<_VariantSpec> variants;
  final int pages;

  /// Page display size in points, keyed by zero-based page index.
  final Map<int, ({double widthPt, double heightPt})> pageSizes;

  /// Non-zero when the annotation was rotated into a tilted raster frame.
  final double skewDegrees;

  /// Rotates the annotation geometry into the input-raster frame.
  ///
  /// A variant may be a deliberately tilted capture (`scan-200dpi-skew-3deg`
  /// injects a three-degree rotation about the page centre in
  /// `tools/corpus/de-ocr/make_variants.py`). The ground truth stays in the
  /// upright page frame, so scoring such a run against it compares two different
  /// frames. With a non-zero [degrees] the line and field rectangles are rotated
  /// about their page centre to where the tilted content actually is. The
  /// injector samples `source = c + R(-degrees)(dest - c)`, which means the
  /// content sits at `dest = c + R(+degrees)(source - c)`; the rotation applied
  /// here is exactly that `R(+degrees)`, i.e. the same angle and sign as the
  /// injection. Rectangles keep their upright size, so the
  /// transform is a pure translation of each rectangle's centre; that is exactly
  /// what the line-association rule (vertical centre inside the box grown by
  /// 4 pt, at least 30 % horizontal overlap) compares.
  ///
  /// A wrong angle or the wrong sign therefore does **not** reproduce the
  /// frame-correct result; the sensitivity is pinned by
  /// `tools/metrics/test_de_ocr_qualification.py`.
  _GroundTruth intoRasterFrame(double degrees) {
    if (degrees == 0) {
      return this;
    }
    final double radians = degrees * math.pi / 180.0;
    final double cosA = math.cos(radians);
    final double sinA = math.sin(radians);
    _Rect transform(int pageIndex, _Rect rect) {
      final ({double widthPt, double heightPt}) size =
          pageSizes[pageIndex] ?? (widthPt: 0.0, heightPt: 0.0);
      if (size.widthPt <= 0 || size.heightPt <= 0) {
        return rect;
      }
      final double centreX = size.widthPt / 2.0;
      final double centreY = size.heightPt / 2.0;
      final double dx = rect.x + rect.width / 2.0 - centreX;
      final double dy = rect.y + rect.height / 2.0 - centreY;
      final double x = centreX + dx * cosA - dy * sinA;
      final double y = centreY + dx * sinA + dy * cosA;
      return _Rect(
        x - rect.width / 2.0,
        y - rect.height / 2.0,
        rect.width,
        rect.height,
      );
    }

    return _GroundTruth(
      suiteId: suiteId,
      fixtureId: fixtureId,
      pdfSha256: pdfSha256,
      lines: <_GtLine>[
        for (final _GtLine line in lines)
          _GtLine(
            id: line.id,
            pageIndex: line.pageIndex,
            text: line.text,
            role: line.role,
            critical: line.critical,
            rect: transform(line.pageIndex, line.rect),
            presentRequiredCharacters: line.presentRequiredCharacters,
          ),
      ],
      fields: <_GtField>[
        for (final _GtField field in fields)
          _GtField(
            id: field.id,
            pageIndex: field.pageIndex,
            type: field.type,
            label: field.label,
            labelLineId: field.labelLineId,
            rect: transform(field.pageIndex, field.rect),
          ),
      ],
      variants: variants,
      pages: pages,
      pageSizes: pageSizes,
      skewDegrees: degrees,
    );
  }

  static _GroundTruth load(String path) {
    final File file = File(path);
    if (!file.existsSync()) {
      throw _Fail('ground truth not found: $path');
    }
    final Object? decoded = jsonDecode(file.readAsStringSync());
    final Map<String, Object?> root = _asMap(decoded, 'ground truth');
    final List<_GtLine> lines = <_GtLine>[];
    for (final Object? entry in _asList(root['lines'], 'lines')) {
      final Map<String, Object?> line = _asMap(entry, 'line');
      lines.add(
        _GtLine(
          id: _asString(line['id'], 'line id'),
          pageIndex: _asInt(line['pageIndex'], 'line pageIndex'),
          text: _asString(line['text'], 'line text'),
          role: _asString(line['role'], 'line role'),
          critical: line['critical'] == true,
          rect: _readRect(line['rect'], 'line rect'),
          presentRequiredCharacters: <String>[
            for (final Object? character in _asList(
              line['presentRequiredCharacters'],
              'characters',
            ))
              _asString(character, 'character'),
          ],
        ),
      );
    }
    final List<_GtField> fields = <_GtField>[];
    for (final Object? entry in _asList(root['fields'], 'fields')) {
      final Map<String, Object?> field = _asMap(entry, 'field');
      fields.add(
        _GtField(
          id: _asString(field['id'], 'field id'),
          pageIndex: _asInt(field['pageIndex'], 'field pageIndex'),
          type: _asString(field['type'], 'field type'),
          label: _asString(field['label'], 'field label'),
          labelLineId: _asString(field['labelLineId'], 'labelLineId'),
          rect: _readRect(field['rect'], 'field rect'),
        ),
      );
    }
    final List<_VariantSpec> variants = <_VariantSpec>[];
    for (final Object? entry in _asList(root['variants'], 'variants')) {
      final Map<String, Object?> variant = _asMap(entry, 'variant');
      variants.add(
        _VariantSpec(
          id: _asString(variant['id'], 'variant id'),
          evidenceClass: _asString(
            variant['evidenceClass'],
            'variant evidenceClass',
          ),
          requiresExactCriticalLines:
              variant['requiresExactCriticalLines'] == true,
          maxCer: _asDouble(variant['maxCer'], 'variant maxCer'),
          maxSpecialCharacterRecallLoss: _asDouble(
            variant['maxSpecialCharacterRecallLoss'],
            'variant maxSpecialCharacterRecallLoss',
          ),
          reference: variant['reference'] == true,
          description: _asString(variant['description'], 'description'),
        ),
      );
    }
    final Map<String, Object?> pdf = _asMap(root['pdf'], 'pdf');
    final Map<int, ({double widthPt, double heightPt})> pageSizes =
        <int, ({double widthPt, double heightPt})>{};
    for (final Object? entry in _asList(
      root['pages'] ?? <Object?>[],
      'pages',
    )) {
      final Map<String, Object?> page = _asMap(entry, 'page');
      pageSizes[_asInt(page['index'], 'page index')] = (
        widthPt: _asDouble(page['widthPt'], 'page widthPt'),
        heightPt: _asDouble(page['heightPt'], 'page heightPt'),
      );
    }
    return _GroundTruth(
      suiteId: _asString(root['suiteId'], 'suiteId'),
      fixtureId: _asString(root['fixtureId'], 'fixtureId'),
      pdfSha256: _asString(pdf['sha256'], 'pdf sha256'),
      lines: lines,
      fields: fields,
      variants: variants,
      pages: _asInt(pdf['pageCount'], 'pageCount'),
      pageSizes: pageSizes,
    );
  }
}

// ---------------------------------------------------------------------------
// Runs
// ---------------------------------------------------------------------------

final class _OcrLine {
  const _OcrLine({
    required this.pageIndex,
    required this.text,
    required this.rect,
    required this.confidence,
  });

  final int pageIndex;
  final String text;
  final _Rect rect;
  final double? confidence;
}

final class _RecordedSuggestion {
  const _RecordedSuggestion({
    required this.pageIndex,
    required this.rect,
    required this.proposedType,
    required this.labelText,
    required this.cues,
    required this.resolution,
    required this.hasKeywordCue,
  });

  final int pageIndex;
  final _Rect rect;
  final String proposedType;
  final String? labelText;
  final List<String> cues;
  final String resolution;
  final bool hasKeywordCue;
}

/// Raster DPI the production analysis pipeline renders for geometry and OCR.
///
/// The run record's `lines` come from the test's own OCR call, which uses the
/// variant's capture DPI. Label verbatimness can only be judged against the OCR
/// text of the *same* raster the analysis recognised, so it is evaluated only
/// for variants captured at this DPI and classified as not comparable
/// otherwise (T263 review B4).
const int analysisRasterDpi = 200;

final class _RunVariant {
  const _RunVariant({
    required this.id,
    required this.raster,
    required this.lines,
    required this.suggestions,
    required this.timings,
    this.evidence = const <String, Object?>{},
  });

  final String id;
  final Map<String, Object?> raster;
  final Map<String, Object?> evidence;
  final List<_OcrLine> lines;
  final List<_RecordedSuggestion> suggestions;
  final Map<String, Object?> timings;
}

final class _Run {
  const _Run({
    required this.path,
    required this.evidenceClass,
    required this.engine,
    required this.fixtureSha256,
    required this.runner,
    required this.generatedAtUtc,
    required this.variants,
  });

  final String path;
  final String evidenceClass;
  final String? engine;
  final String fixtureSha256;
  final Map<String, Object?> runner;
  final String? generatedAtUtc;
  final List<_RunVariant> variants;

  static _Run load(String path, _GroundTruth groundTruth) {
    final File file = File(path);
    if (!file.existsSync()) {
      throw _Fail('run file not found: $path');
    }
    final Map<String, Object?> root = _asMap(
      jsonDecode(file.readAsStringSync()),
      'run',
    );
    final String suiteId = _asString(root['suiteId'], 'run suiteId');
    if (suiteId != groundTruth.suiteId) {
      throw _Fail(
        'run suite $suiteId does not match ground-truth suite '
        '${groundTruth.suiteId}',
      );
    }
    final String fixtureId = _asString(root['fixtureId'], 'run fixtureId');
    if (fixtureId != groundTruth.fixtureId) {
      throw _Fail(
        'run fixture $fixtureId does not match ground-truth fixture '
        '${groundTruth.fixtureId}',
      );
    }
    final String fixtureSha256 = _asString(
      root['fixtureSha256'],
      'run fixtureSha256',
    );
    if (fixtureSha256 != groundTruth.pdfSha256) {
      throw _Fail(
        'run fixture sha256 $fixtureSha256 does not match the annotated '
        'reference pdf sha256 ${groundTruth.pdfSha256}',
      );
    }
    final String evidenceClass = _asString(
      root['evidenceClass'],
      'run evidenceClass',
    );
    if (!_evidenceClasses.contains(evidenceClass)) {
      throw _Fail('unknown evidence class $evidenceClass');
    }
    final List<_RunVariant> variants = <_RunVariant>[];
    for (final Object? entry in _asList(root['variants'], 'variants')) {
      final Map<String, Object?> variant = _asMap(entry, 'variant');
      final String variantId = _asString(variant['id'], 'variant id');
      final List<_OcrLine> lines = <_OcrLine>[];
      final List<_RecordedSuggestion> suggestions = <_RecordedSuggestion>[];
      for (final Object? pageEntry in _asList(variant['pages'], 'pages')) {
        final Map<String, Object?> page = _asMap(pageEntry, 'page');
        final int pageIndex = _asInt(page['index'], 'page index');
        for (final Object? lineEntry in _asList(
          page['lines'] ?? <Object?>[],
          'page lines',
        )) {
          final Map<String, Object?> line = _asMap(lineEntry, 'line');
          lines.add(
            _OcrLine(
              pageIndex: pageIndex,
              text: _asString(line['text'], 'ocr line text'),
              rect: _readRect(line['rect'], 'ocr line rect'),
              confidence: line['confidence'] == null
                  ? null
                  : _asDouble(line['confidence'], 'ocr line confidence'),
            ),
          );
        }
        for (final Object? suggestionEntry in _asList(
          page['suggestions'] ?? <Object?>[],
          'page suggestions',
        )) {
          final Map<String, Object?> suggestion = _asMap(
            suggestionEntry,
            'suggestion',
          );
          final List<String> cues = <String>[
            for (final Object? cue in _asList(
              suggestion['cues'] ?? <Object?>[],
              'cues',
            ))
              _asString(cue, 'cue'),
          ];
          suggestions.add(
            _RecordedSuggestion(
              pageIndex: pageIndex,
              rect: _readRect(suggestion['rect'], 'suggestion rect'),
              proposedType: _asString(
                suggestion['proposedType'],
                'suggestion proposedType',
              ),
              labelText: suggestion['labelText'] == null
                  ? null
                  : _asString(suggestion['labelText'], 'labelText'),
              cues: cues,
              resolution: suggestion['resolution'] == null
                  ? 'unresolved'
                  : _asString(suggestion['resolution'], 'resolution'),
              hasKeywordCue: cues.any(
                (String cue) => cue.startsWith('keyword_'),
              ),
            ),
          );
        }
      }
      variants.add(
        _RunVariant(
          id: variantId,
          raster: _asMap(variant['raster'] ?? <String, Object?>{}, 'raster'),
          lines: lines,
          suggestions: suggestions,
          timings: _asMap(variant['timings'] ?? <String, Object?>{}, 'timings'),
          evidence: _asMap(
            variant['evidence'] ?? <String, Object?>{},
            'variant evidence',
          ),
        ),
      );
    }
    return _Run(
      path: path,
      evidenceClass: evidenceClass,
      engine: root['engine'] == null
          ? null
          : _asString(root['engine'], 'engine'),
      fixtureSha256: fixtureSha256,
      runner: _asMap(root['runner'] ?? <String, Object?>{}, 'runner'),
      generatedAtUtc: root['generatedAtUtc'] == null
          ? null
          : _asString(root['generatedAtUtc'], 'generatedAtUtc'),
      variants: variants,
    );
  }
}

// ---------------------------------------------------------------------------
// Scoring
// ---------------------------------------------------------------------------

enum _OpKind { match, substitution, deletion, insertion }

final class _Op {
  const _Op(this.kind, this.expected, this.observed);

  final _OpKind kind;
  final int? expected;
  final int? observed;
}

/// Levenshtein alignment over code points with a deterministic backtrace.
List<_Op> _align(List<int> expected, List<int> observed) {
  final int n = expected.length;
  final int m = observed.length;
  final List<List<int>> cost = List<List<int>>.generate(
    n + 1,
    (int row) => List<int>.filled(m + 1, 0),
    growable: false,
  );
  for (int row = 0; row <= n; row++) {
    cost[row][0] = row;
  }
  for (int column = 0; column <= m; column++) {
    cost[0][column] = column;
  }
  for (int row = 1; row <= n; row++) {
    for (int column = 1; column <= m; column++) {
      final int substitution =
          cost[row - 1][column - 1] +
          (expected[row - 1] == observed[column - 1] ? 0 : 1);
      final int deletion = cost[row - 1][column] + 1;
      final int insertion = cost[row][column - 1] + 1;
      int best = substitution;
      if (deletion < best) {
        best = deletion;
      }
      if (insertion < best) {
        best = insertion;
      }
      cost[row][column] = best;
    }
  }
  final List<_Op> reversed = <_Op>[];
  int row = n;
  int column = m;
  while (row > 0 || column > 0) {
    if (row > 0 &&
        column > 0 &&
        cost[row][column] ==
            cost[row - 1][column - 1] +
                (expected[row - 1] == observed[column - 1] ? 0 : 1)) {
      final bool same = expected[row - 1] == observed[column - 1];
      reversed.add(
        _Op(
          same ? _OpKind.match : _OpKind.substitution,
          expected[row - 1],
          observed[column - 1],
        ),
      );
      row--;
      column--;
      continue;
    }
    if (row > 0 && cost[row][column] == cost[row - 1][column] + 1) {
      reversed.add(_Op(_OpKind.deletion, expected[row - 1], null));
      row--;
      continue;
    }
    reversed.add(_Op(_OpKind.insertion, null, observed[column - 1]));
    column--;
  }
  return reversed.reversed.toList(growable: false);
}

final class _Alignment {
  const _Alignment({
    required this.associated,
    required this.gtCharCount,
    required this.ocrCharCount,
    required this.substitutions,
    required this.deletions,
    required this.insertions,
    required this.confusions,
    required this.exactLines,
    required this.nfdLines,
    required this.combiningMarkLines,
    required this.missingUmlautDots,
    required this.sharpSAsCapitalB,
    required this.asciiFoldedLines,
    required this.caseChangedLines,
    required this.requiredMatches,
    required this.criticalResults,
  });

  final int associated;
  final int gtCharCount;
  final int ocrCharCount;
  final int substitutions;
  final int deletions;
  final int insertions;
  final List<_Confusion> confusions;
  final int exactLines;
  final int nfdLines;
  final int combiningMarkLines;
  final int missingUmlautDots;
  final int sharpSAsCapitalB;
  final int asciiFoldedLines;
  final int caseChangedLines;
  final Map<String, int> requiredMatches;
  final List<_CriticalResult> criticalResults;
}

final class _Confusion {
  const _Confusion({
    required this.expected,
    required this.observed,
    required this.kind,
    required this.count,
  });

  final String? expected;
  final String? observed;
  final String kind;
  final int count;

  Map<String, Object?> toJson() => <String, Object?>{
    'expected': expected,
    'observed': observed,
    'kind': kind,
    'count': count,
  };
}

final class _CriticalResult {
  const _CriticalResult({
    required this.lineId,
    required this.expected,
    required this.observed,
    required this.exact,
  });

  final String lineId;
  final String expected;
  final String? observed;
  final bool exact;

  Map<String, Object?> toJson() => <String, Object?>{
    'lineId': lineId,
    'expected': expected,
    'observed': observed,
    'exact': exact,
  };
}

const Map<String, String> _umlautBases = <String, String>{
  'ä': 'a',
  'ö': 'o',
  'ü': 'u',
  'Ä': 'A',
  'Ö': 'O',
  'Ü': 'U',
};

/// Associates ground-truth lines with OCR lines by geometry only.
///
/// A pair is a candidate when the OCR line's vertical centre lies inside the
/// ground-truth line box grown by 4 pt and the horizontal overlap covers at
/// least 30 % of the narrower box. Pairs are assigned greedily by ascending
/// vertical distance, then descending horizontal overlap, then ground-truth
/// order, then OCR order. Never text similarity.
List<({_GtLine gt, _OcrLine ocr})> _associate(
  List<_GtLine> lines,
  List<_OcrLine> ocrLines,
) {
  const double verticalSlack = 4;
  const double minHorizontalShare = 0.3;
  final List<({_GtLine gt, _OcrLine ocr, double dy, double overlap})>
  candidates = <({_GtLine gt, _OcrLine ocr, double dy, double overlap})>[];
  for (final _GtLine gt in lines) {
    for (final _OcrLine ocr in ocrLines) {
      if (ocr.pageIndex != gt.pageIndex) {
        continue;
      }
      final double centre = ocr.rect.centreY;
      if (centre < gt.rect.y - verticalSlack ||
          centre > gt.rect.bottom + verticalSlack) {
        continue;
      }
      final double left = gt.rect.x > ocr.rect.x ? gt.rect.x : ocr.rect.x;
      final double right = gt.rect.right < ocr.rect.right
          ? gt.rect.right
          : ocr.rect.right;
      final double overlap = right - left;
      final double narrower = gt.rect.width < ocr.rect.width
          ? gt.rect.width
          : ocr.rect.width;
      if (narrower <= 0 || overlap < minHorizontalShare * narrower) {
        continue;
      }
      final double dy = (gt.rect.centreY - centre).abs();
      candidates.add((gt: gt, ocr: ocr, dy: dy, overlap: overlap));
    }
  }
  candidates.sort((
    ({_GtLine gt, _OcrLine ocr, double dy, double overlap}) a,
    ({_GtLine gt, _OcrLine ocr, double dy, double overlap}) b,
  ) {
    int result = a.dy.compareTo(b.dy);
    if (result != 0) {
      return result;
    }
    result = b.overlap.compareTo(a.overlap);
    if (result != 0) {
      return result;
    }
    result = a.gt.id.compareTo(b.gt.id);
    if (result != 0) {
      return result;
    }
    return a.ocr.text.compareTo(b.ocr.text);
  });
  final Set<String> usedLines = <String>{};
  final Set<_OcrLine> usedOcr = <_OcrLine>{};
  final List<({_GtLine gt, _OcrLine ocr})> result =
      <({_GtLine gt, _OcrLine ocr})>[];
  for (final ({_GtLine gt, _OcrLine ocr, double dy, double overlap}) candidate
      in candidates) {
    if (usedLines.contains(candidate.gt.id) ||
        usedOcr.contains(candidate.ocr)) {
      continue;
    }
    usedLines.add(candidate.gt.id);
    usedOcr.add(candidate.ocr);
    result.add((gt: candidate.gt, ocr: candidate.ocr));
  }
  return result;
}

_Alignment _scoreRaw(_GroundTruth groundTruth, _RunVariant variant) {
  final List<({_GtLine gt, _OcrLine ocr})> pairs = _associate(
    groundTruth.lines,
    variant.lines,
  );
  final Map<String, int> confusionCounts = <String, int>{};
  int gtChars = 0;
  int ocrChars = 0;
  int substitutions = 0;
  int deletions = 0;
  int insertions = 0;
  int exactLines = 0;
  int nfdLines = 0;
  int combiningMarkLines = 0;
  int missingUmlautDots = 0;
  int sharpSAsCapitalB = 0;
  int asciiFoldedLines = 0;
  int caseChangedLines = 0;
  final Map<String, int> requiredMatches = <String, int>{
    for (final String character in _requiredCharacters) character: 0,
  };
  final Map<String, String?> observedByLine = <String, String?>{};

  void countConfusion(String? expected, String? observed, String kind) {
    final String key = '${expected ?? ''}\u0000${observed ?? ''}\u0000$kind';
    confusionCounts[key] = (confusionCounts[key] ?? 0) + 1;
  }

  for (final ({_GtLine gt, _OcrLine ocr}) pair in pairs) {
    final List<int> expected = pair.gt.text.runes.toList();
    final List<int> observed = pair.ocr.text.runes.toList();
    gtChars += expected.length;
    ocrChars += observed.length;
    observedByLine[pair.gt.id] = pair.ocr.text;
    if (pair.gt.text == pair.ocr.text) {
      exactLines++;
    }
    final String nfd = _toNfd(pair.gt.text);
    if (nfd != pair.gt.text && pair.ocr.text == nfd) {
      nfdLines++;
    }
    if (observed.any(
      (int rune) => rune >= _combiningMin && rune <= _combiningMax,
    )) {
      combiningMarkLines++;
    }
    if (pair.ocr.text != pair.gt.text &&
        pair.ocr.text == pair.gt.text.toLowerCase()) {
      caseChangedLines++;
    }
    if (pair.ocr.text != pair.gt.text &&
        pair.ocr.text == _asciiFoldText(pair.gt.text)) {
      asciiFoldedLines++;
    }
    for (final _Op op in _align(expected, observed)) {
      switch (op.kind) {
        case _OpKind.match:
          final String matched = String.fromCharCode(op.expected!);
          if (requiredMatches.containsKey(matched)) {
            requiredMatches[matched] = requiredMatches[matched]! + 1;
          }
        case _OpKind.substitution:
          substitutions++;
          final String? expectedChar = op.expected == null
              ? null
              : String.fromCharCode(op.expected!);
          final String? observedChar = op.observed == null
              ? null
              : String.fromCharCode(op.observed!);
          countConfusion(expectedChar, observedChar, 'substitution');
          if (expectedChar != null && observedChar != null) {
            if (_requiredCharacters.contains(expectedChar) ||
                _requiredCharacters.contains(observedChar)) {
              // Already counted above; the confusion matrix is character-wide.
            }
            final String? base = _umlautBases[expectedChar];
            if (base != null && observedChar == base) {
              missingUmlautDots++;
            }
            if (expectedChar == 'ß' && observedChar == 'B') {
              sharpSAsCapitalB++;
            }
          }
        case _OpKind.deletion:
          deletions++;
          final String? expectedChar = op.expected == null
              ? null
              : String.fromCharCode(op.expected!);
          countConfusion(expectedChar, null, 'deletion');
        case _OpKind.insertion:
          insertions++;
          final String? observedChar = op.observed == null
              ? null
              : String.fromCharCode(op.observed!);
          countConfusion(null, observedChar, 'insertion');
      }
    }
  }

  // Unmatched ground-truth lines are deletions and unmatched OCR lines are
  // insertions; nothing is silently dropped from the CER denominator.
  final Set<String> matchedLineIds = <String>{
    for (final ({_GtLine gt, _OcrLine ocr}) pair in pairs) pair.gt.id,
  };
  final Set<_OcrLine> matchedOcr = <_OcrLine>{
    for (final ({_GtLine gt, _OcrLine ocr}) pair in pairs) pair.ocr,
  };
  for (final _GtLine line in groundTruth.lines) {
    if (matchedLineIds.contains(line.id)) {
      continue;
    }
    gtChars += line.text.runes.length;
    deletions += line.text.runes.length;
    for (final int rune in line.text.runes) {
      countConfusion(String.fromCharCode(rune), null, 'deletion');
    }
    observedByLine[line.id] = null;
  }
  for (final _OcrLine line in variant.lines) {
    if (matchedOcr.contains(line)) {
      continue;
    }
    ocrChars += line.text.runes.length;
    insertions += line.text.runes.length;
    for (final int rune in line.text.runes) {
      countConfusion(null, String.fromCharCode(rune), 'insertion');
    }
  }

  final List<_CriticalResult> critical = <_CriticalResult>[
    for (final _GtLine line in groundTruth.lines)
      if (line.critical)
        _CriticalResult(
          lineId: line.id,
          expected: line.text,
          observed: observedByLine[line.id],
          exact: observedByLine[line.id] == line.text,
        ),
  ];

  final List<_Confusion> confusions =
      <_Confusion>[
        for (final MapEntry<String, int> entry in confusionCounts.entries)
          _Confusion(
            expected: entry.key.split('\u0000')[0].isEmpty
                ? null
                : entry.key.split('\u0000')[0],
            observed: entry.key.split('\u0000')[1].isEmpty
                ? null
                : entry.key.split('\u0000')[1],
            kind: entry.key.split('\u0000')[2],
            count: entry.value,
          ),
      ]..sort((_Confusion a, _Confusion b) {
        int result = (b.count).compareTo(a.count);
        if (result != 0) {
          return result;
        }
        result = _sortKey(a).compareTo(_sortKey(b));
        return result;
      });

  return _Alignment(
    associated: pairs.length,
    gtCharCount: gtChars,
    ocrCharCount: ocrChars,
    substitutions: substitutions,
    deletions: deletions,
    insertions: insertions,
    confusions: confusions,
    exactLines: exactLines,
    nfdLines: nfdLines,
    combiningMarkLines: combiningMarkLines,
    missingUmlautDots: missingUmlautDots,
    sharpSAsCapitalB: sharpSAsCapitalB,
    asciiFoldedLines: asciiFoldedLines,
    caseChangedLines: caseChangedLines,
    requiredMatches: requiredMatches,
    criticalResults: critical,
  );
}

String _sortKey(_Confusion confusion) {
  return '${confusion.expected ?? ''}|${confusion.observed ?? ''}|'
      '${confusion.kind}';
}

String _asciiFoldText(String text) {
  return text
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss');
}

String _toNfd(String text) {
  const Map<String, String> decomposition = <String, String>{
    'Ä': 'A\u0308',
    'Ö': 'O\u0308',
    'Ü': 'U\u0308',
    'ä': 'a\u0308',
    'ö': 'o\u0308',
    'ü': 'u\u0308',
  };
  final StringBuffer buffer = StringBuffer();
  for (final int rune in text.runes) {
    final String character = String.fromCharCode(rune);
    buffer.write(decomposition[character] ?? character);
  }
  return buffer.toString();
}

final class _SpecialCharacterScore {
  const _SpecialCharacterScore({
    required this.character,
    required this.truePositives,
    required this.falsePositives,
    required this.falseNegatives,
  });

  final String character;
  final int truePositives;
  final int falsePositives;
  final int falseNegatives;

  double get precision {
    final int denominator = truePositives + falsePositives;
    return denominator == 0 ? 0 : truePositives / denominator;
  }

  double get recall {
    final int denominator = truePositives + falseNegatives;
    return denominator == 0 ? 0 : truePositives / denominator;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'character': character,
    'codePoint':
        'U+${character.runes.first.toRadixString(16).toUpperCase().padLeft(4, '0')}',
    'truePositives': truePositives,
    'falsePositives': falsePositives,
    'falseNegatives': falseNegatives,
    'precision': _round(precision),
    'recall': _round(recall),
  };
}

// ---------------------------------------------------------------------------
// Semantic scoring
// ---------------------------------------------------------------------------

final class _FieldResult {
  const _FieldResult({
    required this.id,
    required this.expectedType,
    required this.expectedLabel,
    required this.observedType,
    required this.observedLabel,
    required this.fieldIoU,
    required this.labelIoU,
    required this.status,
    required this.reason,
  });

  final String id;
  final String expectedType;
  final String expectedLabel;
  final String? observedType;
  final String? observedLabel;
  final double fieldIoU;
  final double labelIoU;

  /// `matched`, `wrong_label`, `wrong_type`, `missing`, or `unresolved`.
  final String status;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'expectedType': expectedType,
    'expectedLabel': expectedLabel,
    'observedType': observedType,
    'observedLabel': observedLabel,
    'fieldIoU': _round(fieldIoU),
    'labelIoU': _round(labelIoU),
    'status': status,
    'reason': reason,
  };
}

final class _SemanticScore {
  const _SemanticScore({
    required this.results,
    required this.truePositives,
    required this.falsePositives,
    required this.falseNegatives,
    required this.typeCorrect,
    required this.labelCorrect,
    required this.unresolvedLabels,
    required this.forcedTypeViolations,
    required this.nonVerbatimLabels,
    required this.nonVerbatimNotComparable,
    required this.autoResolvedSuggestions,
    required this.meanFieldIoU,
    required this.meanLabelIoU,
    required this.suggestions,
  });

  final List<_FieldResult> results;
  final int truePositives;
  final int falsePositives;
  final int falseNegatives;
  final int typeCorrect;
  final int labelCorrect;
  final int unresolvedLabels;
  final int forcedTypeViolations;
  final int nonVerbatimLabels;
  final int nonVerbatimNotComparable;
  final int autoResolvedSuggestions;
  final double meanFieldIoU;
  final double meanLabelIoU;
  final int suggestions;
}

/// Matches one ground-truth field to at most one recorded suggestion:
/// IoU >= 0.5 and same type count as detected (research.md D-18); the label
/// comparison additionally uses the declared matching aliases.
_SemanticScore _scoreSemantic(
  _GroundTruth groundTruth,
  _RunVariant variant,
  _Alignment alignment,
) {
  final List<_RecordedSuggestion> unused = List<_RecordedSuggestion>.of(
    variant.suggestions,
  );
  final List<_FieldResult> results = <_FieldResult>[];
  int truePositives = 0;
  int typeCorrect = 0;
  int labelCorrect = 0;
  int unresolvedLabels = 0;
  double fieldIoUSum = 0;
  double labelIoUSum = 0;
  int labelIoUCount = 0;
  final Set<String> ocrLineTexts = <String>{
    for (final _OcrLine line in variant.lines) line.text.trim(),
  };
  int nonVerbatimLabels = 0;
  int nonVerbatimNotComparable = 0;

  for (final _GtField field in groundTruth.fields) {
    _RecordedSuggestion? best;
    double bestIoU = 0;
    for (final _RecordedSuggestion suggestion in unused) {
      if (suggestion.pageIndex != field.pageIndex) {
        continue;
      }
      final double iou = suggestion.rect.iou(field.rect);
      if (iou > bestIoU) {
        bestIoU = iou;
        best = suggestion;
      }
    }
    if (best == null || bestIoU < 0.5) {
      results.add(
        _FieldResult(
          id: field.id,
          expectedType: field.type,
          expectedLabel: field.label,
          observedType: null,
          observedLabel: null,
          fieldIoU: bestIoU,
          labelIoU: 0,
          status: 'missing',
          reason: 'no recorded suggestion reaches IoU 0.5',
        ),
      );
      continue;
    }
    unused.remove(best);
    fieldIoUSum += bestIoU;
    final _GtLine? labelLine = groundTruth.lines
        .where((_GtLine line) => line.id == field.labelLineId)
        .firstOrNull;
    double labelIoU = 0;
    if (labelLine != null) {
      for (final _OcrLine line in variant.lines) {
        if (line.pageIndex != labelLine.pageIndex) {
          continue;
        }
        final double iou = line.rect.iou(labelLine.rect);
        if (iou > labelIoU) {
          labelIoU = iou;
        }
      }
      if (labelIoU > 0) {
        labelIoUSum += labelIoU;
        labelIoUCount++;
      }
    }
    final String? observedLabel = best.labelText;
    final bool labelMatches =
        observedLabel != null &&
        _matchingFold(observedLabel) == _matchingFold(field.label);
    truePositives++;
    final bool typeMatches = best.proposedType == field.type;
    if (typeMatches) {
      typeCorrect++;
    }
    if (labelMatches) {
      labelCorrect++;
    }
    if (observedLabel == null || observedLabel.trim().isEmpty) {
      unresolvedLabels++;
    }
    if (observedLabel != null &&
        !ocrLineTexts.contains(observedLabel.trim()) &&
        !_isPrefixOfAnyLine(observedLabel.trim(), ocrLineTexts)) {
      // Whitespace-only differences are already excluded above (both sides are
      // trimmed), so a remaining difference is either a different OCR call or a
      // real content rewrite. It can only be judged against the recorded OCR
      // text of the raster the analysis itself recognised; for a variant whose
      // capture DPI differs from the 200 DPI analysis raster the two
      // recognitions see different pixels (the run record's lines come from the
      // test's own OCR call on the delivered capture grid, not from the
      // analysis raster), so the comparison is not comparable.
      final Object? rasterDpi = variant.raster['dpi'];
      final bool comparable =
          rasterDpi is num && rasterDpi.round() == analysisRasterDpi;
      if (comparable) {
        nonVerbatimLabels++;
      } else {
        nonVerbatimNotComparable++;
      }
    }
    results.add(
      _FieldResult(
        id: field.id,
        expectedType: field.type,
        expectedLabel: field.label,
        observedType: best.proposedType,
        observedLabel: observedLabel,
        fieldIoU: bestIoU,
        labelIoU: labelIoU,
        status: labelMatches
            ? (typeMatches ? 'matched' : 'wrong_type')
            : (observedLabel == null ? 'unresolved' : 'wrong_label'),
        reason: labelMatches
            ? (typeMatches
                  ? 'label and type match'
                  : 'label matches, type differs')
            : (observedLabel == null
                  ? 'no credible label assigned; uncertainty kept'
                  : 'label text differs from the ground truth'),
      ),
    );
  }

  int forcedTypeViolations = 0;
  int autoResolved = 0;
  for (final _RecordedSuggestion suggestion in variant.suggestions) {
    if (suggestion.labelText == null && suggestion.hasKeywordCue) {
      forcedTypeViolations++;
    }
    if (suggestion.resolution != 'unresolved') {
      autoResolved++;
    }
  }

  return _SemanticScore(
    results: results,
    truePositives: truePositives,
    falsePositives: unused.length,
    falseNegatives: groundTruth.fields.length - truePositives,
    typeCorrect: typeCorrect,
    labelCorrect: labelCorrect,
    unresolvedLabels: unresolvedLabels,
    forcedTypeViolations: forcedTypeViolations,
    nonVerbatimLabels: nonVerbatimLabels,
    nonVerbatimNotComparable: nonVerbatimNotComparable,
    autoResolvedSuggestions: autoResolved,
    meanFieldIoU: groundTruth.fields.isEmpty
        ? 0
        : fieldIoUSum / groundTruth.fields.length,
    meanLabelIoU: labelIoUCount == 0 ? 0 : labelIoUSum / labelIoUCount,
    suggestions: variant.suggestions.length,
  );
}

bool _isPrefixOfAnyLine(String text, Set<String> lines) {
  for (final String line in lines) {
    if (line.startsWith(text)) {
      return true;
    }
  }
  return false;
}

String _matchingFold(String text) {
  return text
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss');
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------

final class _VariantResult {
  _VariantResult({
    required this.id,
    required this.evidenceClass,
    required this.description,
    required this.raster,
    required this.timings,
    required this.alignment,
    required this.specialCharacters,
    required this.semantic,
    required this.status,
    required this.statusReasons,
    required this.groundTruthLines,
    required this.groundTruthFields,
    required this.ocrLines,
    required this.criticalUnresolved,
    this.skewDegrees = 0,
  });

  final String id;
  final String evidenceClass;
  final String description;
  final Map<String, Object?> raster;
  final Map<String, Object?> timings;
  final _Alignment? alignment;
  final List<_SpecialCharacterScore> specialCharacters;
  final _SemanticScore? semantic;
  final String status;
  final List<String> statusReasons;
  final int groundTruthLines;
  final int groundTruthFields;
  final int ocrLines;
  final int criticalUnresolved;

  /// Annotation rotation applied to this variant's ground truth, in degrees.
  final double skewDegrees;

  double? get cer {
    final _Alignment? raw = alignment;
    if (raw == null || raw.gtCharCount == 0) {
      return null;
    }
    return (raw.substitutions + raw.deletions + raw.insertions) /
        raw.gtCharCount;
  }

  double? get specialCharacterRecall {
    final List<_SpecialCharacterScore> scores = specialCharacters;
    int tp = 0;
    int fn = 0;
    for (final _SpecialCharacterScore score in scores) {
      tp += score.truePositives;
      fn += score.falseNegatives;
    }
    final int denominator = tp + fn;
    return denominator == 0 ? null : tp / denominator;
  }

  double? get specialCharacterPrecision {
    int tp = 0;
    int fp = 0;
    for (final _SpecialCharacterScore score in specialCharacters) {
      tp += score.truePositives;
      fp += score.falsePositives;
    }
    final int denominator = tp + fp;
    return denominator == 0 ? null : tp / denominator;
  }

  /// Share of matched ground-truth fields whose label matches after the
  /// declared matching aliases (NFC/NFD, case, ae/oe/ue/ss).
  double? get labelAccuracy {
    final _SemanticScore? score = semantic;
    if (score == null || score.truePositives == 0) {
      return null;
    }
    return score.labelCorrect / score.truePositives;
  }

  /// Share of matched ground-truth fields whose proposed type is correct.
  double? get typeAccuracy {
    final _SemanticScore? score = semantic;
    if (score == null || score.truePositives == 0) {
      return null;
    }
    return score.typeCorrect / score.truePositives;
  }

  /// Field-detection precision: geometry matches / all recorded suggestions
  /// on the annotated page (metric-definition.v1 classes, kept separate).
  double? get fieldPrecision {
    final _SemanticScore? score = semantic;
    if (score == null) {
      return null;
    }
    final int denominator = score.truePositives + score.falsePositives;
    return denominator == 0 ? 0 : score.truePositives / denominator;
  }

  /// Field-detection recall: geometry matches / ground-truth fields.
  double? get fieldRecall {
    final _SemanticScore? score = semantic;
    if (score == null) {
      return null;
    }
    final int denominator = score.truePositives + score.falseNegatives;
    return denominator == 0 ? 0 : score.truePositives / denominator;
  }

  Map<String, Object?> toJson() {
    final _Alignment? raw = alignment;
    final _SemanticScore? semantics = semantic;
    return <String, Object?>{
      'id': id,
      'evidenceClass': evidenceClass,
      'description': description,
      'status': status,
      'statusReasons': statusReasons,
      'raster': raster,
      'groundTruthTransform': <String, Object?>{
        'skewDegrees': skewDegrees,
        'annotationTransformed': skewDegrees != 0,
      },
      'timings': timings,
      'raw': raw == null
          ? null
          : <String, Object?>{
              'groundTruthLines': groundTruthLines,
              'ocrLines': ocrLines,
              'associatedLines': raw.associated,
              'exactLines': raw.exactLines,
              'groundTruthCodePoints': raw.gtCharCount,
              'ocrCodePoints': raw.ocrCharCount,
              'substitutions': raw.substitutions,
              'deletions': raw.deletions,
              'insertions': raw.insertions,
              'cer': cer == null ? null : _round(cer!),
              'criticalLines': raw.criticalResults.length,
              'criticalExact': raw.criticalResults
                  .where((_CriticalResult result) => result.exact)
                  .length,
              'criticalUnresolved': <Object>[
                for (final _CriticalResult result in raw.criticalResults)
                  if (!result.exact) result.toJson(),
              ],
              'specialCharacters': <Object>[
                for (final _SpecialCharacterScore score in specialCharacters)
                  score.toJson(),
              ],
              'specialCharacterPrecision': specialCharacterPrecision == null
                  ? null
                  : _round(specialCharacterPrecision!),
              'specialCharacterRecall': specialCharacterRecall == null
                  ? null
                  : _round(specialCharacterRecall!),
              'confusionMatrix': <Object>[
                for (final _Confusion confusion in raw.confusions)
                  confusion.toJson(),
              ],
              'unicode': <String, Object?>{
                'nfcExactLines': raw.exactLines,
                'nfdFormLines': raw.nfdLines,
                'combiningMarkLines': raw.combiningMarkLines,
                'missingUmlautDots': raw.missingUmlautDots,
                'sharpSAsCapitalB': raw.sharpSAsCapitalB,
                'asciiFoldedLines': raw.asciiFoldedLines,
                'caseChangedLines': raw.caseChangedLines,
              },
            },
      'semantic': semantics == null
          ? null
          : <String, Object?>{
              'groundTruthFields': groundTruthFields,
              'recordedSuggestions': semantics.suggestions,
              'truePositives': semantics.truePositives,
              'falsePositives': semantics.falsePositives,
              'falseNegatives': semantics.falseNegatives,
              'precision': fieldPrecision == null
                  ? null
                  : _round(fieldPrecision!),
              'recall': fieldRecall == null ? null : _round(fieldRecall!),
              'typeAccuracy': typeAccuracy == null
                  ? null
                  : _round(typeAccuracy!),
              'labelAccuracy': labelAccuracy == null
                  ? null
                  : _round(labelAccuracy!),
              'unresolvedLabels': semantics.unresolvedLabels,
              'meanFieldIoU': _round(semantics.meanFieldIoU),
              'meanLabelIoU': _round(semantics.meanLabelIoU),
              'forcedTypeViolations': semantics.forcedTypeViolations,
              'nonVerbatimLabels': semantics.nonVerbatimLabels,
              'nonVerbatimNotComparable': semantics.nonVerbatimNotComparable,
              'autoResolvedSuggestions': semantics.autoResolvedSuggestions,
              'fields': <Object>[
                for (final _FieldResult result in semantics.results)
                  result.toJson(),
              ],
            },
    };
  }
}

final class _Report {
  const _Report({
    required this.groundTruth,
    required this.runs,
    required this.variants,
    required this.controls,
    required this.overallVerdict,
    required this.overallReasons,
    required this.requireDeviceEvidence,
    this.gtSkewOverride,
  });

  final _GroundTruth groundTruth;
  final List<_Run> runs;
  final List<_VariantResult> variants;
  final List<_ControlResult> controls;
  final String overallVerdict;
  final List<String> overallReasons;
  final bool requireDeviceEvidence;
  final double? gtSkewOverride;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': 1,
      'suiteId': groundTruth.suiteId,
      'fixtureId': groundTruth.fixtureId,
      'fixtureSha256': groundTruth.pdfSha256,
      'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'metricDefinitionVersion': 'metric-definition.v1',
      'rawComparisonNormalization': 'none',
      'groundTruthTransform': <String, Object?>{
        'kind': gtSkewOverride == null
            ? 'per-variant-from-recorded-injection'
            : 'fixed-override',
        'overrideDegrees': gtSkewOverride,
        'note':
            'a variant whose raster records a known skew injection '
            '(for example "skew-3deg") is scored with its annotation rotated '
            'into the input-raster frame; only line/field geometry moves, never '
            'text; upright variants keep the upright annotation',
      },
      'requireDeviceEvidence': requireDeviceEvidence,
      'overallVerdict': overallVerdict,
      'overallReasons': overallReasons,
      'runs': <Object>[
        for (final _Run run in runs)
          <String, Object?>{
            'path': run.path,
            'evidenceClass': run.evidenceClass,
            'engine': run.engine,
            'fixtureSha256': run.fixtureSha256,
            'runner': run.runner,
            'generatedAtUtc': run.generatedAtUtc,
            'deviceEvidence': _isDeviceEvidence(run.evidenceClass),
          },
      ],
      'variants': <Object>[
        for (final _VariantResult variant in variants) variant.toJson(),
      ],
      'controls': <Object>[
        for (final _ControlResult control in controls) control.toJson(),
      ],
    };
  }

  String toMarkdown() {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('# T263 German OCR qualification');
    buffer.writeln();
    buffer.writeln(
      '- Suite: `${groundTruth.suiteId}` (`${groundTruth.fixtureId}`), '
      'reference PDF sha256 `${groundTruth.pdfSha256}`',
    );
    buffer.writeln('- Metric definition: `metric-definition.v1`');
    buffer.writeln('- Raw-text normalization: none');
    buffer.writeln('- Overall verdict: **$overallVerdict**');
    for (final String reason in overallReasons) {
      buffer.writeln('  - $reason');
    }
    buffer.writeln();
    buffer.writeln(
      '| Variant | Evidence | Status | CER | Special P | Special R | '
      'Field P | Field R | Type acc. | Unresolved labels |',
    );
    buffer.writeln(
      '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |',
    );
    for (final _VariantResult variant in variants) {
      buffer.writeln(
        '| ${variant.id} | ${variant.evidenceClass} | ${variant.status} | '
        '${_fmt(variant.cer)} | ${_fmt(variant.specialCharacterPrecision)} | '
        '${_fmt(variant.specialCharacterRecall)} | '
        '${_fmt(variant.fieldPrecision)} | ${_fmt(variant.fieldRecall)} | '
        '${_fmt(variant.typeAccuracy)} | '
        '${variant.semantic?.unresolvedLabels ?? 'n/a'} |',
      );
    }
    for (final _VariantResult variant in variants) {
      final _Alignment? raw = variant.alignment;
      if (raw == null) {
        continue;
      }
      buffer.writeln();
      buffer.writeln('## ${variant.id}');
      buffer.writeln();
      buffer.writeln(variant.description);
      buffer.writeln();
      buffer.writeln(
        'Raw: ${raw.associated}/${variant.groundTruthLines} lines associated, '
        '${raw.exactLines} exact, '
        '${raw.substitutions} substitutions, ${raw.deletions} deletions, '
        '${raw.insertions} insertions, CER ${_fmt(variant.cer)}.',
      );
      if (raw.criticalResults.any((_CriticalResult result) => !result.exact)) {
        buffer.writeln();
        buffer.writeln('Critical lines that are not exact (UNRESOLVED):');
        buffer.writeln();
        for (final _CriticalResult result in raw.criticalResults) {
          if (result.exact) {
            continue;
          }
          buffer.writeln(
            '- `${result.lineId}`: expected `${result.expected}`, '
            'observed `${result.observed ?? '<no line associated>'}',
          );
        }
      }
      final List<_Confusion> notable = raw.confusions
          .where(
            (_Confusion confusion) =>
                (confusion.expected != null &&
                    _requiredCharacters.contains(confusion.expected)) ||
                (confusion.observed != null &&
                    _requiredCharacters.contains(confusion.observed)),
          )
          .take(20)
          .toList();
      if (notable.isNotEmpty) {
        buffer.writeln();
        buffer.writeln('Special-character confusion matrix:');
        buffer.writeln();
        buffer.writeln('| Expected | Observed | Kind | Count |');
        buffer.writeln('| --- | --- | --- | --- |');
        for (final _Confusion confusion in notable) {
          buffer.writeln(
            '| ${confusion.expected ?? '∅'} | ${confusion.observed ?? '∅'} | '
            '${confusion.kind} | ${confusion.count} |',
          );
        }
      }
      final _SemanticScore? semantics = variant.semantic;
      if (semantics != null) {
        buffer.writeln();
        buffer.writeln(
          'Semantic: ${semantics.truePositives}/'
          '${groundTruth.fields.length} fields with a matching label, '
          '${semantics.unresolvedLabels} unresolved label(s), '
          '${semantics.forcedTypeViolations} forced-type violation(s), '
          '${semantics.nonVerbatimLabels} non-verbatim label(s) '
          '(${semantics.nonVerbatimNotComparable} not comparable: recorded OCR '
          'raster differs from the analysis raster), '
          '${semantics.autoResolvedSuggestions} auto-resolved suggestion(s).',
        );
      }
    }
    if (controls.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('## Control paths (never OCR or device evidence)');
      buffer.writeln();
      buffer.writeln('| Control | Evidence | Status | CER | Exact lines |');
      buffer.writeln('| --- | --- | --- | --- | --- |');
      for (final _ControlResult control in controls) {
        buffer.writeln(
          '| ${control.id} | ${control.evidenceClass} | ${control.status} | '
          '${_fmt(control.cer)} | ${control.exactPages}/'
          '${control.pageCount} pages |',
        );
      }
    }
    buffer.writeln();
    buffer.writeln(
      'An UNRESOLVED case is reported as unresolved and never counted as an '
      'accuracy PASS.',
    );
    return buffer.toString();
  }
}

String _fmt(double? value) {
  if (value == null) {
    return 'n/a';
  }
  return (value * 100).toStringAsFixed(2);
}

String _pct(double value) => '${(value * 100).toStringAsFixed(2)}%';

double _round(double value) => (value * 10000).roundToDouble() / 10000;

/// `true` only for a clean production-path emulator run.
bool _isDeviceEvidence(String evidenceClass) => evidenceClass == 'EMULATOR';

/// `true` for any run that executed on the emulator, including the injected
/// scan variants. The two are still reported apart: `deviceEvidence` stays
/// clean-path-only, and every variant keeps its own evidence class.
bool _isOnDevice(String evidenceClass) =>
    evidenceClass == 'EMULATOR' || evidenceClass == 'EMULATOR_INJECTED_RASTER';

/// Injected skew of a recorded variant, in degrees, from its own raster record.
///
/// `make_variants.py` records `raster.degradations` (for example
/// `["skew-3deg"]`), and the optional `raster.skewDegrees`/`evidence.skewDegrees`
/// trace is honoured when present. Anything else is an upright capture (0).
double _injectedSkewDegrees(_RunVariant variant) {
  final Object? trace = variant.evidence['skewDegrees'];
  if (trace is num && trace.isFinite) {
    return trace.toDouble();
  }
  final Object? rasterTrace = variant.raster['skewDegrees'];
  if (rasterTrace is num && rasterTrace.isFinite) {
    return rasterTrace.toDouble();
  }
  final Object? degradations = variant.raster['degradations'];
  if (degradations is List) {
    for (final Object? entry in degradations) {
      if (entry is! String) {
        continue;
      }
      final RegExpMatch? match = RegExp(r'^skew-(-?[0-9]+(?:\.[0-9]+)?)deg$')
          .firstMatch(entry.trim());
      if (match != null) {
        return double.parse(match.group(1)!);
      }
    }
  }
  return 0;
}

_Report _score({
  required _GroundTruth groundTruth,
  required List<_Run> runs,
  required bool requireDeviceEvidence,
  double? gtSkewOverride,
}) {
  final Map<String, _RunVariant> recordedVariants = <String, _RunVariant>{};
  for (final _Run run in runs) {
    for (final _RunVariant variant in run.variants) {
      recordedVariants[variant.id] = variant;
    }
  }
  final List<_VariantResult> variants = <_VariantResult>[];
  for (final _VariantSpec spec in groundTruth.variants) {
    final _RunVariant? recorded = recordedVariants[spec.id];
    if (recorded == null) {
      variants.add(
        _VariantResult(
          id: spec.id,
          evidenceClass: spec.evidenceClass,
          description: spec.description,
          raster: <String, Object?>{},
          timings: <String, Object?>{},
          alignment: null,
          specialCharacters: const <_SpecialCharacterScore>[],
          semantic: null,
          status: 'NOT_RUN',
          statusReasons: <String>['no run file recorded this variant'],
          groundTruthLines: groundTruth.lines.length,
          groundTruthFields: groundTruth.fields.length,
          ocrLines: 0,
          criticalUnresolved: 0,
          skewDegrees: gtSkewOverride ?? 0,
        ),
      );
      continue;
    }
    // A deliberately tilted capture is annotated in the upright frame, so the
    // annotation is rotated into the raster frame for exactly that variant. The
    // override forces one angle for every variant and exists only to prove the
    // sensitivity of the measurement (wrong sign, wrong angle, no transform).
    final double variantSkew = gtSkewOverride ?? _injectedSkewDegrees(recorded);
    final _GroundTruth variantGroundTruth = groundTruth.intoRasterFrame(
      variantSkew,
    );
    final _Alignment alignment = _scoreRaw(variantGroundTruth, recorded);
    final List<_SpecialCharacterScore> specialCharacters =
        _scoreRequiredCharacters(alignment);
    final _SemanticScore semantic = _scoreSemantic(
      variantGroundTruth,
      recorded,
      alignment,
    );
    final List<String> reasons = <String>[];
    final List<String> unresolvedReasons = <String>[];
    final double cer = alignment.gtCharCount == 0
        ? 0
        : (alignment.substitutions +
                  alignment.deletions +
                  alignment.insertions) /
              alignment.gtCharCount;
    if (cer > spec.maxCer) {
      reasons.add(
        'CER ${_pct(cer)} exceeds the pre-declared ceiling ${_pct(spec.maxCer)}',
      );
    }
    int tp = 0;
    int fn = 0;
    for (final _SpecialCharacterScore score in specialCharacters) {
      tp += score.truePositives;
      fn += score.falseNegatives;
    }
    final double recall = tp + fn == 0 ? 1 : tp / (tp + fn);
    if (recall < 1 - spec.maxSpecialCharacterRecallLoss) {
      reasons.add(
        'special-character recall ${_pct(recall)} is below the pre-declared '
        'floor ${_pct(1 - spec.maxSpecialCharacterRecallLoss)}',
      );
    }
    final int criticalUnresolved = alignment.criticalResults
        .where((_CriticalResult result) => !result.exact)
        .length;
    final bool criticalExactFailure =
        spec.requiresExactCriticalLines && criticalUnresolved > 0;
    if (criticalExactFailure) {
      unresolvedReasons.add(
        '$criticalUnresolved critical line(s) are not exactly recognised',
      );
    }
    if (spec.requiresExactCriticalLines && semantic.unresolvedLabels > 0) {
      unresolvedReasons.add(
        '${semantic.unresolvedLabels} reference field(s) have no credible '
        'label; uncertainty is kept instead of forcing a type',
      );
    }
    if (spec.requiresExactCriticalLines && semantic.truePositives > 0) {
      final double accuracy = semantic.labelCorrect / semantic.truePositives;
      if (accuracy < 1) {
        unresolvedReasons.add(
          'label accuracy ${_pct(accuracy)} on the reference variant is not '
          '100 %',
        );
      }
    }
    if (semantic.forcedTypeViolations > 0) {
      reasons.add(
        '${semantic.forcedTypeViolations} suggestion(s) carry a keyword cue '
        'without a credible label (forced type)',
      );
    }
    if (semantic.nonVerbatimLabels > 0) {
      reasons.add(
        '${semantic.nonVerbatimLabels} suggestion label(s) are not verbatim '
        'OCR text (silent normalization)',
      );
    }
    if (semantic.autoResolvedSuggestions > 0) {
      reasons.add(
        '${semantic.autoResolvedSuggestions} suggestion(s) are pre-resolved '
        'without a user decision',
      );
    }
    reasons.addAll(unresolvedReasons);
    String status;
    if (reasons.isEmpty) {
      status = 'PASS';
    } else if (reasons.length == unresolvedReasons.length) {
      status = 'UNRESOLVED';
    } else {
      status = 'FAIL';
    }
    variants.add(
      _VariantResult(
        id: spec.id,
        evidenceClass: recorded.id == spec.id
            ? _evidenceClassOf(recorded, runs, spec)
            : spec.evidenceClass,
        description: spec.description,
        raster: recorded.raster,
        timings: recorded.timings,
        alignment: alignment,
        specialCharacters: specialCharacters,
        semantic: semantic,
        status: status,
        statusReasons: reasons,
        groundTruthLines: groundTruth.lines.length,
        groundTruthFields: groundTruth.fields.length,
        ocrLines: recorded.lines.length,
        criticalUnresolved: criticalUnresolved,
        skewDegrees: variantSkew,
      ),
    );
  }

  // Control paths (for example the PDF text layer) are reported separately and
  // never counted as a scored variant or as device evidence. They are compared
  // with whitespace removed, because pdftotext's spacing heuristics are a tool
  // artifact; the compared question is which code points the PDF contains.
  final Set<String> declaredIds = <String>{
    for (final _VariantSpec spec in groundTruth.variants) spec.id,
  };
  final List<_ControlResult> controls = <_ControlResult>[];
  for (final _Run run in runs) {
    for (final _RunVariant recorded in run.variants) {
      if (declaredIds.contains(recorded.id)) {
        continue;
      }
      controls.add(_scoreControl(groundTruth, run, recorded));
    }
  }

  final List<String> overallReasons = <String>[];
  final _VariantSpec? reference = groundTruth.variants
      .where((_VariantSpec spec) => spec.reference)
      .firstOrNull;
  _VariantResult? referenceResult;
  if (reference != null) {
    referenceResult = variants
        .where((_VariantResult result) => result.id == reference.id)
        .firstOrNull;
    if (referenceResult == null) {
      overallReasons.add('reference variant ${reference.id} was not declared');
    } else if (referenceResult.status == 'NOT_RUN') {
      overallReasons.add('reference variant ${reference.id} was not executed');
    } else if (referenceResult.evidenceClass != 'EMULATOR') {
      overallReasons.add(
        'reference variant ${reference.id} is ${referenceResult.evidenceClass}, '
        'not EMULATOR production-path evidence',
      );
    } else if (referenceResult.status != 'PASS') {
      overallReasons.add(
        'reference variant ${reference.id} is ${referenceResult.status}: '
        '${referenceResult.statusReasons.join('; ')}',
      );
    }
  }
  if (requireDeviceEvidence) {
    for (final _VariantResult result in variants) {
      if (result.status == 'NOT_RUN') {
        continue;
      }
      if (!_isOnDevice(result.evidenceClass)) {
        overallReasons.add(
          'variant ${result.id} is ${result.evidenceClass}, which is not an '
          'on-emulator run',
        );
      }
    }
  }
  final String overallVerdict;
  if (overallReasons.isEmpty) {
    overallVerdict = 'PASS';
  } else if (referenceResult != null &&
      referenceResult.status == 'UNRESOLVED' &&
      overallReasons.length == 1) {
    overallVerdict = 'UNRESOLVED';
  } else {
    overallVerdict = 'FAIL';
  }
  return _Report(
    groundTruth: groundTruth,
    runs: runs,
    variants: variants,
    controls: controls,
    overallVerdict: overallVerdict,
    overallReasons: overallReasons,
    requireDeviceEvidence: requireDeviceEvidence,
    gtSkewOverride: gtSkewOverride,
  );
}

final class _ControlResult {
  const _ControlResult({
    required this.id,
    required this.evidenceClass,
    required this.description,
    required this.status,
    required this.statusReasons,
    required this.pageCount,
    required this.exactPages,
    required this.groundTruthCodePoints,
    required this.missingCount,
    required this.extraCount,
    required this.missingCodePoints,
    required this.extraCodePoints,
  });

  final String id;
  final String evidenceClass;
  final String description;
  final String status;
  final List<String> statusReasons;
  final int pageCount;
  final int exactPages;
  final int groundTruthCodePoints;
  final int missingCount;
  final int extraCount;
  final List<MapEntry<String, int>> missingCodePoints;
  final List<MapEntry<String, int>> extraCodePoints;

  double? get cer {
    if (groundTruthCodePoints == 0) {
      return null;
    }
    return (missingCount + extraCount) / groundTruthCodePoints;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'control': true,
    'evidenceClass': evidenceClass,
    'description': description,
    'status': status,
    'statusReasons': statusReasons,
    'comparison':
        'whitespace removed, per-page code-point multiset, Unicode code points '
        'unchanged',
    'pageCount': pageCount,
    'exactPages': exactPages,
    'groundTruthCodePoints': groundTruthCodePoints,
    'missingCodePointCount': missingCount,
    'extraCodePointCount': extraCount,
    'cer': cer == null ? null : _round(cer!),
    'missingCodePoints': <Object>[
      for (final MapEntry<String, int> entry in missingCodePoints)
        <String, Object?>{'character': entry.key, 'count': entry.value},
    ],
    'extraCodePoints': <Object>[
      for (final MapEntry<String, int> entry in extraCodePoints)
        <String, Object?>{'character': entry.key, 'count': entry.value},
    ],
    'deviceEvidence': false,
  };
}

/// Scores a control path by comparing the whitespace-free code-point multiset
/// of every page.
///
/// Order is deliberately not compared: a control tool's line breaking and word
/// order are its own artifact, while the control question is whether the PDF
/// contains every printed code point exactly once. Geometry association is
/// reported for information only.
_ControlResult _scoreControl(
  _GroundTruth groundTruth,
  _Run run,
  _RunVariant recorded,
) {
  final Map<int, Map<int, int>> expectedByPage = <int, Map<int, int>>{};
  for (final _GtLine line in groundTruth.lines) {
    final Map<int, int> counts = expectedByPage[line.pageIndex] ?? <int, int>{};
    for (final int rune in line.text.runes) {
      if (_isWhitespace(rune)) {
        continue;
      }
      counts[rune] = (counts[rune] ?? 0) + 1;
    }
    expectedByPage[line.pageIndex] = counts;
  }
  final Map<int, Map<int, int>> observedByPage = <int, Map<int, int>>{};
  for (final _OcrLine line in recorded.lines) {
    final Map<int, int> counts = observedByPage[line.pageIndex] ?? <int, int>{};
    for (final int rune in line.text.runes) {
      if (_isWhitespace(rune)) {
        continue;
      }
      counts[rune] = (counts[rune] ?? 0) + 1;
    }
    observedByPage[line.pageIndex] = counts;
  }
  int groundTruthCodePoints = 0;
  int missingCount = 0;
  int extraCount = 0;
  int exactPages = 0;
  final Map<int, int> missing = <int, int>{};
  final Map<int, int> extra = <int, int>{};
  final int pageCount = groundTruth.pages;
  for (int page = 0; page < pageCount; page++) {
    final Map<int, int> expected = expectedByPage[page] ?? <int, int>{};
    final Map<int, int> observed = observedByPage[page] ?? <int, int>{};
    for (final MapEntry<int, int> entry in expected.entries) {
      groundTruthCodePoints += entry.value;
      final int seen = observed[entry.key] ?? 0;
      if (seen < entry.value) {
        missing[entry.key] = (missing[entry.key] ?? 0) + (entry.value - seen);
        missingCount += entry.value - seen;
      }
    }
    for (final MapEntry<int, int> entry in observed.entries) {
      final int wanted = expected[entry.key] ?? 0;
      if (entry.value > wanted) {
        extra[entry.key] = (extra[entry.key] ?? 0) + (entry.value - wanted);
        extraCount += entry.value - wanted;
      }
    }
    if (missingCount == 0 && extraCount == 0) {
      exactPages++;
    }
  }
  final List<MapEntry<String, int>> missingCodePoints =
      <MapEntry<String, int>>[
        for (final MapEntry<int, int> entry in missing.entries)
          MapEntry<String, int>(String.fromCharCode(entry.key), entry.value),
      ]..sort((MapEntry<String, int> a, MapEntry<String, int> b) {
        final int byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
  final List<MapEntry<String, int>> extraCodePoints =
      <MapEntry<String, int>>[
        for (final MapEntry<int, int> entry in extra.entries)
          MapEntry<String, int>(String.fromCharCode(entry.key), entry.value),
      ]..sort((MapEntry<String, int> a, MapEntry<String, int> b) {
        final int byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
  final List<String> reasons = <String>[
    if (exactPages != pageCount)
      '${pageCount - exactPages} page(s) differ in whitespace-free code-point '
          'multiset',
  ];
  return _ControlResult(
    id: recorded.id,
    evidenceClass: run.evidenceClass,
    description:
        'Control path (${run.engine ?? 'unspecified tool'}); reported '
        'separately and never counted as OCR or device evidence.',
    status: reasons.isEmpty ? 'PASS' : 'UNRESOLVED',
    statusReasons: reasons,
    pageCount: pageCount,
    exactPages: exactPages,
    groundTruthCodePoints: groundTruthCodePoints,
    missingCodePoints: missingCodePoints,
    extraCodePoints: extraCodePoints,
    missingCount: missingCount,
    extraCount: extraCount,
  );
}

bool _isWhitespace(int rune) {
  return rune == 0x20 ||
      rune == 0x09 ||
      rune == 0x0A ||
      rune == 0x0D ||
      rune == 0xA0 ||
      rune == 0x202F ||
      rune == 0x2009;
}

String _evidenceClassOf(
  _RunVariant recorded,
  List<_Run> runs,
  _VariantSpec spec,
) {
  for (final _Run run in runs) {
    if (run.variants.contains(recorded)) {
      return run.evidenceClass;
    }
  }
  return spec.evidenceClass;
}

List<_SpecialCharacterScore> _scoreRequiredCharacters(_Alignment alignment) {
  final Map<String, ({int tp, int fp, int fn})> counters =
      <String, ({int tp, int fp, int fn})>{
        for (final String character in _requiredCharacters)
          character: (tp: 0, fp: 0, fn: 0),
      };
  for (final _Confusion confusion in alignment.confusions) {
    final String? expected = confusion.expected;
    final String? observed = confusion.observed;
    if (expected != null) {
      final ({int tp, int fp, int fn})? current = counters[expected];
      if (current != null && confusion.kind != 'insertion') {
        counters[expected] = (
          tp: current.tp,
          fp: current.fp,
          fn: current.fn + confusion.count,
        );
      }
    }
    if (observed != null) {
      final ({int tp, int fp, int fn})? current = counters[observed];
      if (current != null && confusion.kind != 'deletion') {
        counters[observed] = (
          tp: current.tp,
          fp: current.fp + confusion.count,
          fn: current.fn,
        );
      }
    }
  }
  return <_SpecialCharacterScore>[
    for (final String character in _requiredCharacters)
      _SpecialCharacterScore(
        character: character,
        truePositives: alignment.requiredMatches[character] ?? 0,
        falsePositives: counters[character]!.fp,
        falseNegatives: counters[character]!.fn,
      ),
  ];
}

// ---------------------------------------------------------------------------
// JSON helpers
// ---------------------------------------------------------------------------

Map<String, Object?> _asMap(Object? value, String what) {
  if (value is Map<String, Object?>) {
    return value;
  }
  throw _Fail('$what must be a JSON object');
}

List<Object?> _asList(Object? value, String what) {
  if (value is List<Object?>) {
    return value;
  }
  throw _Fail('$what must be a JSON array');
}

String _asString(Object? value, String what) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw _Fail('$what must be a non-empty string');
}

int _asInt(Object? value, String what) {
  if (value is int) {
    return value;
  }
  throw _Fail('$what must be an integer');
}

double _asDouble(Object? value, String what) {
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  throw _Fail('$what must be a finite number');
}

_Rect _readRect(Object? value, String what) {
  final Map<String, Object?> map = _asMap(value, what);
  final bool usesPt = map.containsKey('xPt');
  final double x = _asDouble(map[usesPt ? 'xPt' : 'x'], '$what x');
  final double y = _asDouble(map[usesPt ? 'yPt' : 'y'], '$what y');
  final double width = _asDouble(
    map[usesPt ? 'widthPt' : 'width'],
    '$what width',
  );
  final double height = _asDouble(
    map[usesPt ? 'heightPt' : 'height'],
    '$what height',
  );
  if (width <= 0 || height <= 0) {
    throw _Fail('$what must have positive width and height');
  }
  return _Rect(x, y, width, height);
}

const String _usage =
    '''
T263 German OCR qualification scorer

Usage:
  dart run tools/metrics/de_ocr_qualification.dart \\
    --run <run.json> [--run <run2.json> ...] \\
    --output <report.json> [--markdown <report.md>] \\
    [--ground-truth <path>] [--require-device-evidence]
  dart run tools/metrics/de_ocr_qualification.dart --help

Options:
  --run PATH                  Recorded OCR/suggestion run file. Repeatable.
  --output PATH               Metrics report JSON to write.
  --markdown PATH             Optional Markdown summary to write.
  --ground-truth PATH         Ground truth (default: $_defaultGroundTruth).
  --gt-skew-degrees DEG       Transform the ground-truth geometry (lines and
                              fields) from the upright page frame into the
                              input-raster frame by rotating it about the page
                              centre with the same mapping the variant injector
                              uses (`tools/corpus/de-ocr/make_variants.py`,
                              `skew(..., degrees=3.0)`). Use it to score a
                              deliberately tilted capture frame-correctly; the
                              upright-GT score of such a variant is not
                              comparable and is reported separately.
  --require-device-evidence   Fail unless the reference variant is EMULATOR and
                              every executed variant ran on the emulator
                              (EMULATOR or EMULATOR_INJECTED_RASTER). SIMULATED
                              and TEXT_LAYER runs never satisfy it.
  --help, -h                  Show this help.

Exit codes: 0 PASS, 1 gate failure/UNRESOLVED/NOT_RUN, 2 usage or input error.
''';
