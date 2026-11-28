// T086B-R golden-consumption gate: consume the committed field-inventory
// golden and prove the productive recognition path still reproduces its
// frozen projection over the declared synthetic corpus.
//
// What this tool is not: it does not regenerate the golden and it never writes
// the artifact. `tools/evaluation/field_inventory_baseline.dart` produces and
// freezes `goldens/field-inventory-baseline.v1.json`; this checker reads those
// committed bytes, binds their SHA-256, and compares the golden's frozen
// per-page/per-field projection against the output of the productive
// bytes-level stage (`runRasterPageStage`, the same entry `AnalyzeDocument`
// executes off-isolate) over the corpus the producer itself declares
// (`buildSyntheticCorpus()`, the documented read-only T264D seam).
//
// The projection is deliberately explicit and canonical:
//   * identity - corpus id, page count, fixture/corpus/ground-truth SHA-256,
//     per-page raster identity and declared ground-truth identity;
//   * typed fields - for every detector candidate, the display rect, the
//     proposed type, the label text, and the sorted union of the geometry and
//     typing cues; ordered by the §5.2 projection order;
//   * comparison - the `baseline` verdict, failure codes, integer counters and
//     IoU aggregates that the golden freezes for the typed-candidate path;
//   * totals - the corpus-wide integer counters of that same path.
// Golden and production are each canonically serialized; byte equality of the
// two documents is the gate. Any drift in the golden bytes, the corpus, the
// detector, the typing, the cue assembly, or the comparison turns it red.
//
// Evidence class: NONE. This is a host-only regression check; it measures no
// performance, runs no OCR engine, and is not EMULATOR or DEVICE evidence.
//
// Usage:
//   dart run tools/evaluation/golden_consumption_check.dart [--golden PATH]
//     [--json PATH]
//   dart run tools/evaluation/golden_consumption_check.dart --help
//
// Exit codes:
//   0  the committed golden matches the production projection
//   1  drift, or an unreadable/invalid golden or corpus
//   2  usage error
//
// `feldexa_application` and `feldexa_recognition` are workspace packages and
// intentionally not root `pubspec.yaml` dependencies; the root workspace
// resolves them for `dart run`.
// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:feldexa_application/src/recognition/raster_page_stage.dart';
import 'package:feldexa_recognition/src/field_inventory.dart';
import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/raster.dart';
import 'package:feldexa_recognition/src/structure_comparison.dart';
import 'package:feldexa_recognition/src/type_inference.dart';

import 'field_inventory_baseline.dart'
    show
        SyntheticCorpusLabel,
        SyntheticCorpusPage,
        SyntheticGroundTruthField,
        buildSyntheticCorpus,
        syntheticCorpusId,
        syntheticCorpusIdentity;

/// The SHA-256 the brief binds to the committed golden.
///
/// The tool re-derives it from the file it actually reads; this constant is the
/// independent binding, so replacing the golden with a different artifact is a
/// drift even when the projection happens to agree.
const String boundGoldenSha256 =
    '508ed9beed5a3844aa3ce101d378f7243b47e259cbcda72a412bbe6067f205e6';

/// Declared label confidence of the synthetic corpus (no OCR engine runs).
const double _syntheticLabelConfidence = 0.9;

/// Projection schema tag, so a changed projection shape is visible.
const String _projectionSchema = 'golden-consumption-v1';

/// One typed-field projection row.
final class _TypedField {
  _TypedField({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.proposedType,
    required this.labelText,
    required this.cues,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final String proposedType;
  final String? labelText;
  final List<String> cues;

  Map<String, Object?> toJson() => <String, Object?>{
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'proposedType': proposedType,
    'labelText': labelText,
    'cues': cues,
  };

  /// Total order for the §5.2 projection comparison.
  static int compare(_TypedField a, _TypedField b) {
    int result = a.y.compareTo(b.y);
    if (result != 0) {
      return result;
    }
    result = a.x.compareTo(b.x);
    if (result != 0) {
      return result;
    }
    result = a.width.compareTo(b.width);
    if (result != 0) {
      return result;
    }
    result = a.height.compareTo(b.height);
    if (result != 0) {
      return result;
    }
    result = a.proposedType.compareTo(b.proposedType);
    if (result != 0) {
      return result;
    }
    result = (a.labelText ?? '').compareTo(b.labelText ?? '');
    if (result != 0) {
      return result;
    }
    return a.cues.join('\u0000').compareTo(b.cues.join('\u0000'));
  }
}

/// One page's frozen projection.
final class _PageProjection {
  _PageProjection({
    required this.json,
    required this.typed,
    required this.baseline,
  });

  final Map<String, Object?> json;
  final List<_TypedField> typed;
  final Map<String, Object?> baseline;

  Map<String, Object?> toJson() => <String, Object?>{
    ...json,
    'typedFields': <Map<String, Object?>>[
      for (final _TypedField field in typed) field.toJson(),
    ],
    'baseline': baseline,
  };
}

/// The complete projected document.
final class _Projection {
  _Projection({
    required this.goldenSha256,
    required this.corpus,
    required this.pages,
    required this.totals,
  });

  final String goldenSha256;
  final Map<String, Object?> corpus;
  final List<_PageProjection> pages;
  final Map<String, Object?> totals;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': _projectionSchema,
    'goldenSha256': goldenSha256,
    'corpus': corpus,
    'pages': <Map<String, Object?>>[
      for (final _PageProjection page in pages) page.toJson(),
    ],
    'totals': totals,
  };
}

final class _Failure implements Exception {
  const _Failure(this.exitCode, this.message);

  final int exitCode;
  final String message;
}

void main(List<String> arguments) {
  try {
    final ({String goldenPath, String goldenSha, String? jsonPath, bool help})
    options = _parseArguments(arguments);
    if (options.help) {
      stdout.writeln(_usage);
      return;
    }
    final Uint8List goldenBytes = File(options.goldenPath).readAsBytesSync();
    final String goldenSha256 = sha256.convert(goldenBytes).toString();
    if (goldenSha256 != options.goldenSha) {
      throw _Failure(
        1,
        'golden-consumption: DRIFT goldenSha256=$goldenSha256 expected '
        '${options.goldenSha} path=${options.goldenPath}',
      );
    }
    final Object? decoded = jsonDecode(utf8.decode(goldenBytes));
    if (decoded is! Map<String, Object?>) {
      throw const _Failure(1, 'golden-consumption: golden is not an object');
    }
    final Map<String, Object?> golden = decoded;

    final List<SyntheticCorpusPage> corpus = buildSyntheticCorpus();
    final _Projection committed = _projectGolden(golden, goldenSha256);
    final _Projection produced = _projectProduction(
      corpus,
      goldenSha256,
      golden,
    );

    final List<String> differences = _differences(committed, produced);
    final String committedJson = _canonicalJson(committed.toJson());
    final String producedJson = _canonicalJson(produced.toJson());
    if (committedJson != producedJson && differences.isEmpty) {
      differences.add('canonical projection bytes differ');
    }

    if (options.jsonPath != null) {
      File(options.jsonPath!).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'equal': differences.isEmpty,
          'goldenSha256': goldenSha256,
          'goldenPath': options.goldenPath,
          'pages': produced.pages.length,
          'typedFields': produced.pages.fold<int>(
            0,
            (int sum, _PageProjection page) => sum + page.typed.length,
          ),
          'differences': differences,
        }),
        flush: true,
      );
    }

    stdout.writeln(
      'golden-consumption: consumed $goldenSha256 '
      '(${options.goldenPath})',
    );
    stdout.writeln(
      'golden-consumption: ${produced.pages.length} pages, '
      '${produced.pages.fold<int>(0, (int sum, _PageProjection page) => sum + page.typed.length)} '
      'typed fields',
    );
    if (differences.isEmpty) {
      stdout.writeln('golden-consumption: projection EQUAL');
      return;
    }
    stdout.writeln('golden-consumption: projection DRIFT');
    for (final String difference in differences) {
      stdout.writeln('  - $difference');
    }
    throw const _Failure(1, 'golden-consumption: projection DRIFT');
  } on _Failure catch (failure) {
    stderr.writeln(failure.message);
    exitCode = failure.exitCode;
  } on FileSystemException catch (_) {
    stderr.writeln('golden-consumption: cannot read the golden artifact');
    exitCode = 1;
  } on FormatException catch (_) {
    stderr.writeln('golden-consumption: golden is not valid JSON');
    exitCode = 1;
  }
}

/// Projects the committed golden's frozen fields into the comparison shape.
_Projection _projectGolden(Map<String, Object?> golden, String goldenSha256) {
  final Object? pagesValue = golden['pages'];
  if (pagesValue is! List<Object?>) {
    throw const _Failure(1, 'golden-consumption: golden pages are missing');
  }
  final List<_PageProjection> pages = <_PageProjection>[];
  for (final Object? pageValue in pagesValue) {
    if (pageValue is! Map<String, Object?>) {
      throw const _Failure(1, 'golden-consumption: page is not an object');
    }
    final Map<String, Object?> page = pageValue;
    final Map<String, Object?> fields = _object(page['fields'], 'fields');
    final List<Object?> candidates = _list(
      fields['candidates'],
      'fields.candidates',
    );
    final List<Object?> observations = _list(
      fields['typeObservations'],
      'fields.typeObservations',
    );
    if (candidates.length != observations.length) {
      throw _Failure(
        1,
        'golden-consumption: ${page['id']} candidates and type observations '
        'differ in length',
      );
    }
    final List<_TypedField> typed = <_TypedField>[];
    for (int index = 0; index < candidates.length; index++) {
      final Map<String, Object?> candidate = _object(
        candidates[index],
        'candidates[$index]',
      );
      final Map<String, Object?> observation = _object(
        observations[index],
        'typeObservations[$index]',
      );
      final Map<String, Object?> rect = _object(
        candidate['rect'],
        'candidates[$index].rect',
      );
      typed.add(
        _TypedField(
          x: _number(rect['x'], 'candidate.x'),
          y: _number(rect['y'], 'candidate.y'),
          width: _number(rect['width'], 'candidate.width'),
          height: _number(rect['height'], 'candidate.height'),
          proposedType: _string(observation['proposedType'], 'proposedType'),
          labelText: observation['labelText'] as String?,
          cues: _unionCues(candidate, observation),
        ),
      );
    }
    typed.sort(_TypedField.compare);
    pages.add(
      _PageProjection(
        json: _pageIdentity(page),
        typed: typed,
        baseline: _goldenBaseline(page),
      ),
    );
  }
  final Map<String, Object?> totalsValue = _object(golden['totals'], 'totals');
  final Map<String, Object?> totals = _object(
    totalsValue['baseline'],
    'totals.baseline',
  );
  final Map<String, Object?> corpusValue = _object(
    golden['fixture'],
    'fixture',
  );
  return _Projection(
    goldenSha256: goldenSha256,
    corpus: <String, Object?>{
      'corpusId': golden['corpusId'],
      'pageCount': pages.length,
      'fixtureSha256': corpusValue['fixtureSha256'],
      'corpusSha256': corpusValue['corpusSha256'],
      'groundTruthSha256': corpusValue['groundTruthSha256'],
    },
    pages: pages,
    totals: <String, Object?>{
      'expectedFields': totalsValue['expectedFields'],
      'matched': totals['matched'],
      'extra': totals['extra'],
      'duplicate': totals['duplicate'],
    },
  );
}

/// Runs the productive bytes-level stage over the declared corpus.
_Projection _projectProduction(
  List<SyntheticCorpusPage> corpus,
  String goldenSha256,
  Map<String, Object?> golden,
) {
  final List<_PageProjection> pages = <_PageProjection>[];
  int matched = 0;
  int extra = 0;
  int duplicate = 0;
  int expectedFields = 0;
  for (final SyntheticCorpusPage page in corpus) {
    final RasterSize expectedSize = RasterSize.fromDisplaySize(
      widthPt: page.widthPt,
      heightPt: page.heightPt,
    );
    if (page.rasterWidthPx != expectedSize.widthPx ||
        page.rasterHeightPx != expectedSize.heightPx) {
      throw _Failure(
        1,
        'golden-consumption: ${page.id} raster is not at the analysis scale',
      );
    }
    final RasterPageStageTask task = RasterPageStageTask(
      pageIndex: 0,
      pixels: Uint8List.fromList(page.raster.pixels),
      width: page.rasterWidthPx,
      height: page.rasterHeightPx,
      pageWidthPt: page.widthPt,
      pageHeightPt: page.heightPt,
      labels: <LabelObservation>[
        for (final SyntheticCorpusLabel label in page.labels)
          LabelObservation(
            text: label.text,
            rect: label.rect,
            ocrConfidence: _syntheticLabelConfidence,
          ),
      ],
      ocrUsed: true,
    );
    final RasterPageStageOutcome outcome = runRasterPageStage(task);
    if (outcome.isFailed) {
      throw _Failure(
        1,
        'golden-consumption: ${page.id} production stage failed '
        '(${outcome.failureCategory})',
      );
    }
    final List<_TypedField> typed = <_TypedField>[
      for (final Map<String, Object?> suggestion in outcome.suggestions)
        _suggestionField(suggestion),
    ]..sort(_TypedField.compare);
    final List<ExpectedField> expected = <ExpectedField>[
      for (final SyntheticGroundTruthField field in page.fields)
        ExpectedField(
          pageIndex: 0,
          rect: field.rect,
          kind: field.kind,
          labelText: field.labelText,
          sourceId: field.id,
        ),
    ];
    final List<ObservedField> observed = <ObservedField>[
      for (final _TypedField field in typed)
        ObservedField(
          pageIndex: 0,
          rect: DisplayRect(
            x: field.x,
            y: field.y,
            width: field.width,
            height: field.height,
          ),
          kind:
              fieldInventoryKindForSuggestionType(field.proposedType) ??
              FieldInventoryKind.unknown,
          labelText: field.labelText,
          provenance: 'suggestion',
        ),
    ];
    final StructureComparisonResult comparison = StructureComparison.compare(
      expected: expected,
      observed: observed,
      groundTruthPages: <int>{0},
    );
    expectedFields += expected.length;
    matched += comparison.matches.length;
    extra += comparison.extraObserved.length;
    duplicate += comparison.duplicates.length;
    pages.add(
      _PageProjection(
        json: <String, Object?>{
          'id': page.id,
          'pageSizePt': <String, double>{
            'width': page.widthPt,
            'height': page.heightPt,
          },
          'fixture': <String, Object?>{
            'rasterSha256': page.rasterSha256,
            'rasterWidthPx': page.rasterWidthPx,
            'rasterHeightPx': page.rasterHeightPx,
            'rasterBytes': page.rasterWidthPx * page.rasterHeightPx,
          },
          'groundTruth': <String, Object?>{
            'fieldCount': page.fields.length,
            'groundTruthSha256': page.groundTruthSha256,
          },
          'declaredFieldCount': page.fields.length,
        },
        typed: typed,
        baseline: <String, Object?>{
          'verdict': comparison.verdict.name,
          'failureCodes': comparison.failureCodes,
          'expectedCount': comparison.expectedCount,
          'observedCount': comparison.observedCount,
          'matchedCount': comparison.matches.length,
          'missingCount': comparison.missingExpected.length,
          'extraCount': comparison.extraObserved.length,
          'duplicateCount': comparison.duplicates.length,
          'overlapCount': comparison.overlaps.length,
          'ambiguousCount': comparison.ambiguousObserved.length,
          'unlabelledCount': comparison.unlabelledObserved.length,
          'labelMismatchCount': comparison.labelMismatchedMatches.length,
          'geometryMismatchCount': comparison.geometryMismatchedMatches.length,
          'typeMismatchCount': comparison.typeMismatchedMatches.length,
          'sameCountWrongGeometry': comparison.sameCountWrongGeometry,
          'unknownGroundTruthPages': comparison.unknownGroundTruthPages,
          'meanMatchedIou': _round6(comparison.meanMatchedIou),
          'minMatchedIou': _round6(comparison.minMatchedIou),
        },
      ),
    );
  }
  final Map<String, String> identity = syntheticCorpusIdentity(corpus);
  return _Projection(
    goldenSha256: goldenSha256,
    corpus: <String, Object?>{
      'corpusId': syntheticCorpusId,
      'pageCount': corpus.length,
      'fixtureSha256': identity['fixtureSha256'],
      'corpusSha256': identity['corpusSha256'],
      'groundTruthSha256': identity['groundTruthSha256'],
    },
    pages: pages,
    totals: <String, Object?>{
      'expectedFields': expectedFields,
      'matched': matched,
      'extra': extra,
      'duplicate': duplicate,
    },
  );
}

_TypedField _suggestionField(Map<String, Object?> suggestion) {
  final Map<String, Object?> rect = _object(suggestion['rect'], 'rect');
  final Map<String, Object?> evidence = _object(
    suggestion['evidence'],
    'evidence',
  );
  final List<Object?> cues = _list(evidence['cues'], 'evidence.cues');
  return _TypedField(
    x: _number(rect['x'], 'rect.x'),
    y: _number(rect['y'], 'rect.y'),
    width: _number(rect['width'], 'rect.width'),
    height: _number(rect['height'], 'rect.height'),
    proposedType: _string(suggestion['proposedType'], 'proposedType'),
    labelText: suggestion['labelText'] as String?,
    cues: <String>[for (final Object? cue in cues) _string(cue, 'cue')],
  );
}

Map<String, Object?> _pageIdentity(Map<String, Object?> page) {
  return <String, Object?>{
    'id': page['id'],
    'pageSizePt': page['pageSizePt'],
    'fixture': page['fixture'],
    'groundTruth': page['groundTruth'],
    'declaredFieldCount': _object(
      page['declaredGroundTruth'],
      'declared',
    )['fieldCount'],
  };
}

Map<String, Object?> _goldenBaseline(Map<String, Object?> page) {
  final Map<String, Object?> baseline = _object(page['baseline'], 'baseline');
  const List<String> keys = <String>[
    'verdict',
    'failureCodes',
    'expectedCount',
    'observedCount',
    'matchedCount',
    'missingCount',
    'extraCount',
    'duplicateCount',
    'overlapCount',
    'ambiguousCount',
    'unlabelledCount',
    'labelMismatchCount',
    'geometryMismatchCount',
    'typeMismatchCount',
    'sameCountWrongGeometry',
    'unknownGroundTruthPages',
    'meanMatchedIou',
    'minMatchedIou',
  ];
  return <String, Object?>{for (final String key in keys) key: baseline[key]};
}

List<String> _unionCues(
  Map<String, Object?> candidate,
  Map<String, Object?> observation,
) {
  final Set<String> cues = <String>{
    for (final Object? cue in _list(candidate['cues'], 'candidate.cues'))
      _string(cue, 'cue'),
    for (final Object? cue in _list(
      observation['addedCues'],
      'typeObservation.addedCues',
    ))
      _string(cue, 'cue'),
  };
  return cues.toList()..sort();
}

List<String> _differences(_Projection golden, _Projection produced) {
  final List<String> differences = <String>[];
  if (_canonicalJson(golden.corpus) != _canonicalJson(produced.corpus)) {
    differences.add(
      'corpus identity differs: golden=${_canonicalJson(golden.corpus)} '
      'production=${_canonicalJson(produced.corpus)}',
    );
  }
  if (golden.pages.length != produced.pages.length) {
    differences.add(
      'page count differs: golden=${golden.pages.length} '
      'production=${produced.pages.length}',
    );
    return differences;
  }
  for (int index = 0; index < golden.pages.length; index++) {
    final _PageProjection expected = golden.pages[index];
    final _PageProjection actual = produced.pages[index];
    final String id = _string(expected.json['id'], 'id');
    if (_canonicalJson(expected.json) != _canonicalJson(actual.json)) {
      differences.add(
        '$id: page identity differs golden=${_canonicalJson(expected.json)} '
        'production=${_canonicalJson(actual.json)}',
      );
    }
    if (expected.typed.length != actual.typed.length) {
      differences.add(
        '$id: typed field count differs golden=${expected.typed.length} '
        'production=${actual.typed.length}',
      );
    } else {
      for (int field = 0; field < expected.typed.length; field++) {
        if (_canonicalJson(expected.typed[field].toJson()) !=
            _canonicalJson(actual.typed[field].toJson())) {
          differences.add(
            '$id: typed field $field differs '
            'golden=${_canonicalJson(expected.typed[field].toJson())} '
            'production=${_canonicalJson(actual.typed[field].toJson())}',
          );
        }
      }
    }
    if (_canonicalJson(expected.baseline) != _canonicalJson(actual.baseline)) {
      differences.add(
        '$id: baseline comparison differs '
        'golden=${_canonicalJson(expected.baseline)} '
        'production=${_canonicalJson(actual.baseline)}',
      );
    }
  }
  if (_canonicalJson(golden.totals) != _canonicalJson(produced.totals)) {
    differences.add(
      'totals differ: golden=${_canonicalJson(golden.totals)} '
      'production=${_canonicalJson(produced.totals)}',
    );
  }
  return differences;
}

double _round6(double value) => (value * 1000000).round() / 1000000;

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw _Failure(1, 'golden-consumption: $name is not an object');
  }
  return value;
}

List<Object?> _list(Object? value, String name) {
  if (value is! List<Object?>) {
    throw _Failure(1, 'golden-consumption: $name is not a list');
  }
  return value;
}

double _number(Object? value, String name) {
  if (value is! num) {
    throw _Failure(1, 'golden-consumption: $name is not a number');
  }
  return value.toDouble();
}

String _string(Object? value, String name) {
  if (value is! String) {
    throw _Failure(1, 'golden-consumption: $name is not a string');
  }
  return value;
}

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

const String _usage = '''
Golden-consumption gate (T086B-R): consume the committed field-inventory
golden and compare it with the productive recognition path over the declared
synthetic corpus. The golden is read-only and is never regenerated.

Usage:
  dart run tools/evaluation/golden_consumption_check.dart
    [--golden PATH] [--json PATH]
  dart run tools/evaluation/golden_consumption_check.dart --help

Options:
  --golden PATH      Golden artifact to consume (default:
                     tools/evaluation/goldens/field-inventory-baseline.v1.json).
  --golden-sha SHA   Expected SHA-256 of the consumed bytes (default: the
                     brief-bound golden hash). The default is the gate; an
                     explicit value exists only for drift-control tests.
  --json PATH        Write the comparison result as JSON.
  --help, -h         Show this help.

Exit codes:
  0  projection equal
  1  drift, unreadable golden, or a production-stage failure
  2  usage error

Evidence class: NONE (host-only regression check).
''';

({String goldenPath, String goldenSha, String? jsonPath, bool help})
_parseArguments(List<String> arguments) {
  String? goldenPath;
  String? goldenSha;
  String? jsonPath;
  bool help = false;
  for (int index = 0; index < arguments.length; index++) {
    final String argument = arguments[index];
    switch (argument) {
      case '--help':
      case '-h':
        help = true;
      case '--golden':
        goldenPath = _value(arguments, index, 'golden');
        index++;
      case '--golden-sha':
        goldenSha = _value(arguments, index, 'golden-sha');
        index++;
      case '--json':
        jsonPath = _value(arguments, index, 'json');
        index++;
      default:
        throw _Failure(2, 'golden-consumption: unknown argument: $argument');
    }
  }
  final String resolvedSha = (goldenSha ?? boundGoldenSha256).toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(resolvedSha)) {
    throw const _Failure(2, 'golden-consumption: --golden-sha must be SHA-256');
  }
  return (
    goldenPath: goldenPath ?? _defaultGoldenPath(),
    goldenSha: resolvedSha,
    jsonPath: jsonPath,
    help: help,
  );
}

String _defaultGoldenPath() {
  final Uri script = Platform.script;
  final Uri golden = script.resolve('goldens/field-inventory-baseline.v1.json');
  if (golden.scheme == 'file') {
    return golden.toFilePath();
  }
  return 'tools/evaluation/goldens/field-inventory-baseline.v1.json';
}

String _value(List<String> arguments, int index, String name) {
  if (index + 1 >= arguments.length) {
    throw _Failure(2, 'golden-consumption: missing value for --$name');
  }
  return arguments[index + 1];
}
