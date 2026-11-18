// T050 recognition-output §1–§2 contract test.
//
// This host-VM test (`NONE` evidence) pins the wire contract in
// `specs/001-scanned-form-workflow/contracts/recognition-output.md` §1
// (envelope), §2–§2.1 (suggestion and forbidden outputs), §4 (failure shape),
// and the deterministic ordering in §5.2. All documents are synthetic maps:
// no detector, raster, OCR, persistence, or real document content is used.
//
// The production oracle is
// `packages/feldexa_recognition/lib/src/suggestion_schema.dart`. Every positive
// and negative fixture is validated through `SuggestionSchema`; there is no
// test-local validator or second vocabulary oracle. A weakening of the
// production rules therefore breaks these tests. T057/T058 must import
// `package:feldexa_recognition/src/suggestion_schema.dart` as documented there.
//
// Fixtures only build synthetic contract-shaped maps. The test keeps the
// contract-derived vocabulary lists and paths as expectations, but calls the
// production validator for the verdict.
//
// Deliberate non-rules in this correction:
//   * §2 requires cues to be sorted and unique but names no collation, so the
//     production validator enforces membership and uniqueness only. The test
//     accepts an unsorted, unique cue list; any producer-side sorting is an
//     assumption, not a contract rule.
//   * §1 requires an `uncertaintyReason` when `pageUncertain` is true and
//     restricts it to four values; it does not require null when false. The
//     test accepts a valid reason with `pageUncertain == false`.
//   * §6 allows a conflict from IoU ≥ 0.5 or the center-containment clause.
//     The production validator pins the IoU ≥ 0.5 subset; T055 owns the second
//     clause. The >12 % printed-ink rule is detector-owned, not
//     schema-expressible.
//
// Not covered here: detection quality, ink measurement, OCR, rasterization,
// persistence, logging behavior, runtime evidence, or a production envelope
// model. See the T050 evidence report for the full limitations.
@TestOn('vm')
library;

import 'package:feldexa_recognition/src/suggestion_schema.dart';
import 'package:flutter_test/flutter_test.dart';

/// The contract example UUID, reused for every synthetic run.
const String _runId = '8f14e45f-ceea-467f-a2a0-1f2c3d4e5f60';

final PageDisplaySize _a4 = PageDisplaySize(595.28, 841.89);
final PageDisplaySize _a5 = PageDisplaySize(419.53, 595.28);

// ---------------------------------------------------------------------------
// Synthetic fixtures
// ---------------------------------------------------------------------------

Map<String, Object?> _rect(num x, num y, num width, num height) {
  return <String, Object?>{
    'x': x.toDouble(),
    'y': y.toDouble(),
    'width': width.toDouble(),
    'height': height.toDouble(),
  };
}

Map<String, Object?> _pageSizeMap(PageDisplaySize size) {
  return <String, Object?>{'width': size.width, 'height': size.height};
}

Map<String, Object?> _timings() {
  return <String, Object?>{'rasterMs': 210, 'ocrMs': 1180, 'detectMs': 430};
}

Map<String, Object?> _failure({
  String category = 'ocr',
  String messageKey = 'REC-002',
  bool recoverable = true,
  int suggestionCount = 4,
}) {
  return <String, Object?>{
    'category': category,
    'messageKey': messageKey,
    'recoverable': recoverable,
    'suggestionCount': suggestionCount,
  };
}

Map<String, Object?> _suggestion({
  required String id,
  required int pageIndex,
  required Map<String, Object?> rect,
  String proposedType = 'text',
  double confidence = 0.82,
  double? uncertainty,
  String? labelText = 'Name',
  List<String> cues = const <String>['underline'],
  int cueAgreement = 1,
  double skewDegrees = 0,
  String contrast = 'normal',
  bool ocrUsed = true,
  List<String> conflictsWith = const <String>[],
  String resolution = 'unresolved',
}) {
  return <String, Object?>{
    'id': id,
    'pageIndex': pageIndex,
    'rect': rect,
    'proposedType': proposedType,
    'confidence': confidence,
    'uncertainty': uncertainty ?? _round2(1 - confidence),
    'labelText': labelText,
    'evidence': <String, Object?>{
      'cues': cues,
      'cueAgreement': cueAgreement,
      'skewDegrees': skewDegrees,
      'contrast': contrast,
      'ocrUsed': ocrUsed,
    },
    'conflictsWith': conflictsWith,
    'resolution': resolution,
  };
}

Map<String, Object?> _envelope({
  int pageIndex = 0,
  List<Map<String, Object?>> suggestions = const <Map<String, Object?>>[],
  Map<String, Object?>? pageSize,
  int rotation = 0,
  String status = 'complete',
  bool pageUncertain = false,
  String? uncertaintyReason,
  Map<String, Object?>? failure,
  Map<String, Object?>? timings,
  String evidenceClass = 'emulator',
  String analysisRunId = _runId,
}) {
  return <String, Object?>{
    'schemaVersion': SuggestionSchema.version,
    'analysisRunId': analysisRunId,
    'pageIndex': pageIndex,
    'pageSizePt': pageSize ?? _pageSizeMap(_a4),
    'rotation': rotation,
    'status': status,
    'pageUncertain': pageUncertain,
    'uncertaintyReason': uncertaintyReason,
    'failure': failure,
    'suggestions': suggestions,
    'timings': timings ?? _timings(),
    'evidenceClass': evidenceClass,
  };
}

/// The §2 example shape plus two conflicting candidates on page 0.
List<Map<String, Object?>> _conflictPair() {
  return <Map<String, Object?>>[
    _suggestion(
      id: 's_p0_0001',
      pageIndex: 0,
      rect: _rect(100, 100, 100, 20),
      confidence: 0.82,
      labelText: 'Name',
      cues: <String>['underline', 'ocr_alignment_right', 'keyword_name'],
      cueAgreement: 3,
      skewDegrees: 0.4,
      conflictsWith: <String>['s_p0_0002'],
    ),
    _suggestion(
      id: 's_p0_0002',
      pageIndex: 0,
      rect: _rect(101, 101, 100, 20),
      confidence: 0.64,
      labelText: null,
      cues: <String>['box', 'whitespace'],
      cueAgreement: 2,
      skewDegrees: 0.4,
      conflictsWith: <String>['s_p0_0001'],
    ),
  ];
}

Map<String, Object?> _pageZeroEnvelope() {
  return _envelope(
    pageIndex: 0,
    suggestions: <Map<String, Object?>>[
      ..._conflictPair(),
      _suggestion(
        id: 's_p0_0003',
        pageIndex: 0,
        rect: _rect(300, 400, 200, 60),
        proposedType: 'multiline',
        confidence: 0.5,
        labelText: 'Bemerkung',
        cues: <String>['whitespace', 'alignment_left'],
        cueAgreement: 2,
        skewDegrees: 0.4,
      ),
    ],
  );
}

Map<String, Object?> _pageOneEnvelope() {
  return _envelope(
    pageIndex: 1,
    suggestions: <Map<String, Object?>>[
      _suggestion(
        id: 's_p1_0001',
        pageIndex: 1,
        rect: _rect(50, 50, 120, 14.5),
        proposedType: 'date',
        confidence: 0.9,
        labelText: null,
        cues: <String>['underline', 'date_context'],
        cueAgreement: 2,
        skewDegrees: 0.4,
      ),
    ],
  );
}

List<Map<String, Object?>> _completeRun() {
  return <Map<String, Object?>>[_pageZeroEnvelope(), _pageOneEnvelope()];
}

Map<String, Object?> _failedEnvelope({
  String category = 'ocr',
  String messageKey = 'REC-002',
  int pageIndex = 0,
}) {
  return _envelope(
    pageIndex: pageIndex,
    status: 'failed',
    failure: _failure(
      category: category,
      messageKey: messageKey,
      suggestionCount: 4,
    ),
  );
}

List<Map<String, Object?>> _failureIsolationRun() {
  return <Map<String, Object?>>[
    _pageZeroEnvelope(),
    _failedEnvelope(pageIndex: 1),
  ];
}

Map<String, Object?> _withSingle(Map<String, Object?> suggestion) {
  return _envelope(
    pageIndex: 0,
    suggestions: <Map<String, Object?>>[suggestion],
  );
}

Map<String, Object?> _uncertain(String? reason) {
  final Map<String, Object?> envelope = _pageZeroEnvelope();
  envelope['pageUncertain'] = true;
  envelope['uncertaintyReason'] = reason;
  return envelope;
}

// ---------------------------------------------------------------------------
// Production-surface wrappers and fixture utilities
// ---------------------------------------------------------------------------

List<SuggestionSchemaViolation> _validateEnvelope(
  Map<String, Object?> envelope, {
  PageDisplaySize? display,
  bool persisted = true,
}) {
  return SuggestionSchema.validateEnvelope(
    envelope,
    displaySize: display ?? _a4,
    persisted: persisted,
  );
}

List<SuggestionSchemaViolation> _validateRun(
  Object? run, {
  required List<PageDisplaySize> pages,
  bool persisted = true,
}) {
  return SuggestionSchema.validateRun(run, pages: pages, persisted: persisted);
}

void _expectValid(
  Map<String, Object?> envelope, {
  PageDisplaySize? display,
  bool persisted = true,
}) {
  expect(
    _validateEnvelope(envelope, display: display, persisted: persisted),
    isEmpty,
  );
}

/// Asserts the exact findings of one invalid envelope.
///
/// The descriptive text after the path's `': '` is a test expectation only and
/// is never compared with production text. [count] is the exact number of
/// findings at that path. [code] pins the intended stable category; [codes]
/// pins every category when one path intentionally carries more than one.
/// [additional] names every other expected finding, so an unintended
/// double-violation cannot mask a broken rule.
void _expectViolation(
  Map<String, Object?> envelope,
  String expected, {
  String? code,
  Set<String>? codes,
  int count = 1,
  List<SuggestionSchemaViolation> additional =
      const <SuggestionSchemaViolation>[],
  PageDisplaySize? display,
  bool persisted = true,
}) {
  final String path = expected.contains(': ')
      ? expected.substring(0, expected.indexOf(': '))
      : expected;
  final List<SuggestionSchemaViolation> findings = _validateEnvelope(
    envelope,
    display: display,
    persisted: persisted,
  );
  final List<SuggestionSchemaViolation> atPath = findings
      .where((SuggestionSchemaViolation finding) => finding.path == path)
      .toList();
  expect(atPath, hasLength(count), reason: 'unexpected finding count at $path');
  final Iterable<String> codesAtPath = atPath.map(
    (SuggestionSchemaViolation finding) => finding.code,
  );
  if (code != null) {
    expect(codesAtPath, contains(code));
  }
  if (codes != null) {
    expect(codesAtPath, containsAll(codes));
  }
  final List<SuggestionSchemaViolation> otherPaths = findings
      .where((SuggestionSchemaViolation finding) => finding.path != path)
      .toList();
  final List<SuggestionSchemaViolation> expectedOthers =
      List<SuggestionSchemaViolation>.of(additional)..sort();
  otherPaths.sort();
  expect(
    otherPaths,
    expectedOthers,
    reason: 'unexpected additional violations for $path',
  );
}

void _expectRunViolation(
  Object? run,
  List<PageDisplaySize> pages,
  String path, {
  String? code,
  Set<String>? codes,
  int count = 1,
  List<SuggestionSchemaViolation> additional =
      const <SuggestionSchemaViolation>[],
  bool persisted = true,
}) {
  final List<SuggestionSchemaViolation> findings = _validateRun(
    run,
    pages: pages,
    persisted: persisted,
  );
  final List<SuggestionSchemaViolation> atPath = findings
      .where((SuggestionSchemaViolation finding) => finding.path == path)
      .toList();
  expect(
    atPath,
    hasLength(count),
    reason: 'unexpected run finding count at $path',
  );
  final Iterable<String> codesAtPath = atPath.map(
    (SuggestionSchemaViolation finding) => finding.code,
  );
  if (code != null) {
    expect(codesAtPath, contains(code));
  }
  if (codes != null) {
    expect(codesAtPath, containsAll(codes));
  }
  final List<SuggestionSchemaViolation> otherPaths = findings
      .where((SuggestionSchemaViolation finding) => finding.path != path)
      .toList();
  final List<SuggestionSchemaViolation> expectedOthers =
      List<SuggestionSchemaViolation>.of(additional)..sort();
  otherPaths.sort();
  expect(
    otherPaths,
    expectedOthers,
    reason: 'unexpected additional run violations for $path',
  );
}

double _round2(double value) => (value * 100).roundToDouble() / 100;

Object? _deepCopy(Object? value) {
  if (value is Map<String, Object?>) {
    return <String, Object?>{
      for (final MapEntry<String, Object?> entry in value.entries)
        entry.key: _deepCopy(entry.value),
    };
  }
  if (value is List<Object?>) {
    return <Object?>[for (final Object? item in value) _deepCopy(item)];
  }
  return value;
}

Map<String, Object?> _copy(Map<String, Object?> source) {
  return _deepCopy(source) as Map<String, Object?>;
}

Map<String, Object?> _suggestionAt(Map<String, Object?> envelope, int index) {
  final List<Object?> suggestions = envelope['suggestions']! as List<Object?>;
  return suggestions[index] as Map<String, Object?>;
}

List<String> _suggestionIds(Map<String, Object?> envelope) {
  final List<Object?> suggestions = envelope['suggestions']! as List<Object?>;
  return <String>[
    for (final Object? suggestion in suggestions)
      if (suggestion is Map<String, Object?>)
        if (suggestion['id'] case final String id) id,
  ];
}

void main() {
  group('recognition-output §1 envelope', () {
    test('accepts one envelope per page in a complete run', () {
      final List<Map<String, Object?>> run = _completeRun();
      expect(_validateRun(run, pages: <PageDisplaySize>[_a4, _a4]), isEmpty);
      expect(run, hasLength(2));
      expect(run[0]['analysisRunId'], run[1]['analysisRunId']);
      expect(run[0]['pageIndex'], 0);
      expect(run[1]['pageIndex'], 1);
    });

    test('rejects unknown envelope keys, including auto-export flags', () {
      final Map<String, Object?> envelope = _pageZeroEnvelope()
        ..['exported'] = true;
      _expectViolation(
        envelope,
        'envelope.exported: unexpected',
        code: SuggestionSchemaCodes.unexpected,
      );
    });

    test('requires every §1 key, including nullable failure and reason', () {
      final Map<String, Object?> missingFailure = _copy(_pageZeroEnvelope())
        ..remove('failure');
      _expectViolation(
        missingFailure,
        'envelope.failure: missing',
        code: SuggestionSchemaCodes.missing,
      );

      final Map<String, Object?> missingReason = _copy(_pageZeroEnvelope())
        ..remove('uncertaintyReason');
      _expectViolation(
        missingReason,
        'envelope.uncertaintyReason: missing',
        code: SuggestionSchemaCodes.missing,
      );
    });

    test('violations are content-free path/code pairs', () {
      _expectViolation(
        _pageZeroEnvelope()..['schemaVersion'] = 2,
        'envelope.schemaVersion: must equal 1',
        code: SuggestionSchemaCodes.value,
      );
      _expectViolation(
        _copy(_pageZeroEnvelope())..remove('failure'),
        'envelope.failure: missing',
        code: SuggestionSchemaCodes.missing,
      );
      _expectViolation(
        _pageZeroEnvelope()..['exported'] = true,
        'envelope.exported: unexpected',
        code: SuggestionSchemaCodes.unexpected,
      );
      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            cues: <String>['underline', 'underline'],
          ),
        ),
        'envelope.suggestions[0].evidence.cues: must be unique',
        code: SuggestionSchemaCodes.duplicate,
      );

      final List<Map<String, Object?>> oneSided = _conflictPair();
      oneSided[1]['conflictsWith'] = <String>[];
      _expectViolation(
        _envelope(pageIndex: 0, suggestions: oneSided),
        'envelope.suggestions[0].conflictsWith: must be symmetric',
        code: SuggestionSchemaCodes.symmetry,
      );
    });

    test('requires schemaVersion 1', () {
      final Map<String, Object?> envelope = _pageZeroEnvelope()
        ..['schemaVersion'] = 2;
      _expectViolation(
        envelope,
        'envelope.schemaVersion: must equal 1',
        code: SuggestionSchemaCodes.value,
      );
    });

    test('requires a canonical UUID analysisRunId shared by every page', () {
      final Map<String, Object?> invalid = _pageZeroEnvelope()
        ..['analysisRunId'] = 'not-a-uuid';
      _expectViolation(
        invalid,
        'envelope.analysisRunId: must be a canonical lowercase UUID',
        code: SuggestionSchemaCodes.format,
      );

      final List<Map<String, Object?>> run = _completeRun();
      run[1]['analysisRunId'] = '00000000-0000-4000-8000-000000000000';
      _expectRunViolation(
        run,
        <PageDisplaySize>[_a4, _a4],
        'run.analysisRunId',
        code: SuggestionSchemaCodes.mismatch,
      );
    });

    test('requires a valid 0-based pageIndex and matching pageSizePt', () {
      final Map<String, Object?> wrongIndex = _envelope(pageIndex: 1);
      _expectViolation(
        wrongIndex,
        'envelope.pageIndex: must be a 0-based index within the page set',
        code: SuggestionSchemaCodes.range,
      );

      final Map<String, Object?> wrongSize = _pageZeroEnvelope()
        ..['pageSizePt'] = _pageSizeMap(PageDisplaySize(595.27, 841.89));
      _expectViolation(
        wrongSize,
        'envelope.pageSizePt.width: must match the page display size',
        code: SuggestionSchemaCodes.value,
      );

      _expectValid(_envelope(pageSize: _pageSizeMap(_a5)), display: _a5);
    });

    test('accepts only 0/90/180/270 rotation', () {
      for (final int rotation in <int>[0, 90, 180, 270]) {
        _expectValid(_pageZeroEnvelope()..['rotation'] = rotation);
      }
      final Map<String, Object?> invalid = _pageZeroEnvelope()
        ..['rotation'] = 45;
      _expectViolation(
        invalid,
        'envelope.rotation: must be 0, 90, 180, or 270',
        code: SuggestionSchemaCodes.value,
      );
    });

    test('pairs status and failure exactly and rejects pending', () {
      _expectValid(_pageZeroEnvelope());
      _expectValid(_failedEnvelope());

      final Map<String, Object?> missingFailure = _failedEnvelope()
        ..['failure'] = null;
      _expectViolation(
        missingFailure,
        'envelope.failure: required when status is failed',
        code: SuggestionSchemaCodes.missing,
      );

      final Map<String, Object?> extraFailure = _pageZeroEnvelope()
        ..['failure'] = _failure();
      _expectViolation(
        extraFailure,
        'envelope.failure: must be null unless status is failed',
        code: SuggestionSchemaCodes.value,
      );

      final Map<String, Object?> pending = _pageZeroEnvelope()
        ..['status'] = 'pending';
      _expectViolation(
        pending,
        'envelope.status: must be complete or failed',
        code: SuggestionSchemaCodes.value,
      );
    });

    test('keeps pageUncertain and uncertaintyReason consistent', () {
      for (final String reason in SuggestionSchema.uncertaintyReasons) {
        _expectValid(_uncertain(reason));
      }
      _expectValid(_pageZeroEnvelope());

      _expectViolation(
        _uncertain(null),
        'envelope.uncertaintyReason: required when pageUncertain is true',
        code: SuggestionSchemaCodes.missing,
      );

      // §1 does not require a null reason when pageUncertain is false.
      final Map<String, Object?> reasonWithoutFlag = _pageZeroEnvelope()
        ..['uncertaintyReason'] = 'skew';
      _expectValid(reasonWithoutFlag);

      _expectViolation(
        _uncertain('blur'),
        'envelope.uncertaintyReason: must be skew, orientation, low_contrast, '
        'structure, or null',
        code: SuggestionSchemaCodes.value,
      );
    });

    test('timings are non-negative integers with known stages only', () {
      final Map<String, Object?> negative = _pageZeroEnvelope()
        ..['timings'] = <String, Object?>{
          'rasterMs': -1,
          'ocrMs': 0,
          'detectMs': 0,
        };
      _expectViolation(
        negative,
        'envelope.timings.rasterMs: must be a non-negative integer',
        code: SuggestionSchemaCodes.range,
      );

      final Map<String, Object?> fractional = _pageZeroEnvelope()
        ..['timings'] = <String, Object?>{
          'rasterMs': 1.5,
          'ocrMs': 0,
          'detectMs': 0,
        };
      _expectViolation(
        fractional,
        'envelope.timings.rasterMs: must be a non-negative integer',
        code: SuggestionSchemaCodes.range,
      );

      final Map<String, Object?> missingStage = _pageZeroEnvelope()
        ..['timings'] = <String, Object?>{'rasterMs': 1, 'ocrMs': 2};
      _expectViolation(
        missingStage,
        'envelope.timings.detectMs: missing',
        code: SuggestionSchemaCodes.missing,
      );

      final Map<String, Object?> extraStage = _pageZeroEnvelope()
        ..['timings'] = <String, Object?>{
          'rasterMs': 1,
          'ocrMs': 2,
          'detectMs': 3,
          'totalMs': 6,
        };
      _expectViolation(
        extraStage,
        'envelope.timings.totalMs: unexpected',
        code: SuggestionSchemaCodes.unexpected,
      );
    });

    test('evidenceClass is simulated, emulator, or device', () {
      for (final String evidenceClass in SuggestionSchema.evidenceClasses) {
        _expectValid(_pageZeroEnvelope()..['evidenceClass'] = evidenceClass);
      }
      final Map<String, Object?> web = _pageZeroEnvelope()
        ..['evidenceClass'] = 'web';
      _expectViolation(
        web,
        'envelope.evidenceClass: must be simulated, emulator, or device',
        code: SuggestionSchemaCodes.value,
      );
    });

    test('canonical projection excludes timings and evidenceClass', () {
      final Map<String, Object?> baseline = _pageZeroEnvelope();
      final Map<String, Object?> diagnosticsOnly = _pageZeroEnvelope()
        ..['timings'] = <String, Object?>{
          'rasterMs': 1,
          'ocrMs': 2,
          'detectMs': 3,
        }
        ..['evidenceClass'] = 'device';

      final Map<String, Object?> projection =
          SuggestionSchema.canonicalProjection(baseline);
      expect(projection, isNot(contains('timings')));
      expect(projection, isNot(contains('evidenceClass')));
      expect(
        SuggestionSchema.canonicalJson(projection),
        SuggestionSchema.canonicalJson(
          SuggestionSchema.canonicalProjection(diagnosticsOnly),
        ),
      );

      diagnosticsOnly['rotation'] = 90;
      expect(
        SuggestionSchema.canonicalJson(projection),
        isNot(
          SuggestionSchema.canonicalJson(
            SuggestionSchema.canonicalProjection(diagnosticsOnly),
          ),
        ),
      );
    });
  });

  group('recognition-output §2 suggestion', () {
    test('accepts the documented suggestion shape', () {
      final Map<String, Object?> envelope = _pageZeroEnvelope();
      _expectValid(envelope);
      final Map<String, Object?> suggestion = _suggestionAt(envelope, 0);
      expect(suggestion['confidence'], 0.82);
      expect(suggestion['uncertainty'], 0.18);
      expect(suggestion['labelText'], 'Name');
      expect(suggestion['resolution'], 'unresolved');
    });

    test('requires every §2 key, including nullable labelText', () {
      final Map<String, Object?> envelope = _withSingle(
        _suggestion(
          id: 's_p0_0001',
          pageIndex: 0,
          rect: _rect(100, 100, 100, 20),
        ),
      );
      _suggestionAt(envelope, 0).remove('uncertainty');
      _expectViolation(
        envelope,
        'envelope.suggestions[0].uncertainty: missing',
        code: SuggestionSchemaCodes.missing,
      );
    });

    test('id encodes pageIndex and the post-sort ordinal', () {
      _expectValid(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
          ),
        ),
      );

      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p1_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
          ),
        ),
        'envelope.suggestions[0].id: page token must equal pageIndex',
        code: SuggestionSchemaCodes.mismatch,
      );

      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p00_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
          ),
        ),
        'envelope.suggestions[0].id: page token must be plain decimal '
        'without padding',
        code: SuggestionSchemaCodes.format,
      );

      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_00001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
          ),
        ),
        'envelope.suggestions[0].id: ordinal must use the canonical '
        'four-digit padding',
        code: SuggestionSchemaCodes.format,
      );

      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0002',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
          ),
        ),
        'envelope.suggestions[0].id: ordinal must equal the post-sort position',
        code: SuggestionSchemaCodes.order,
      );

      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
          ),
        ),
        'envelope.suggestions[0].id: must match '
        's_p<pageIndex>_<zero-padded ordinal>',
        code: SuggestionSchemaCodes.format,
      );

      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001x',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
          ),
        ),
        'envelope.suggestions[0].id: must match '
        's_p<pageIndex>_<zero-padded ordinal>',
        code: SuggestionSchemaCodes.format,
      );
    });

    test('suggestions follow y → x → type ordinal → id order', () {
      final List<Map<String, Object?>> sorted = <Map<String, Object?>>[
        _suggestion(
          id: 's_p0_0001',
          pageIndex: 0,
          rect: _rect(100, 100, 100, 20),
        ),
        _suggestion(
          id: 's_p0_0002',
          pageIndex: 0,
          rect: _rect(200, 100, 100, 20),
        ),
        _suggestion(
          id: 's_p0_0003',
          pageIndex: 0,
          rect: _rect(200, 100, 100, 20),
          proposedType: 'number',
          confidence: 0.7,
          labelText: null,
          cues: <String>['box'],
        ),
      ];
      expect(
        SuggestionSchema.sortedSuggestions(sorted)
            .map((Map<String, Object?> suggestion) => suggestion['id'])
            .toList(),
        <String>['s_p0_0001', 's_p0_0002', 's_p0_0003'],
      );
      expect(
        SuggestionSchema.sortedSuggestions(<Map<String, Object?>>[
          sorted[2],
          sorted[0],
          sorted[1],
        ]).map((Map<String, Object?> suggestion) => suggestion['id']).toList(),
        <String>['s_p0_0001', 's_p0_0002', 's_p0_0003'],
      );
      expect(
        SuggestionSchema.compareSuggestions(
          _suggestion(
            id: 's_p1_0001',
            pageIndex: 1,
            rect: _rect(100, 100, 100, 20),
          ),
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
          ),
        ),
        greaterThan(0),
      );

      final Map<String, Object?> valid = _envelope(
        pageIndex: 0,
        suggestions: sorted,
      );
      _expectValid(valid);

      final Map<String, Object?> reordered = _copy(valid);
      final List<Object?> list = reordered['suggestions']! as List<Object?>;
      final Object? first = list.removeAt(0);
      list.insert(1, first);
      _expectViolation(
        reordered,
        'envelope.suggestions[0]: must follow the §5.2 deterministic order',
        code: SuggestionSchemaCodes.order,
        additional: <SuggestionSchemaViolation>[
          const SuggestionSchemaViolation(
            'envelope.suggestions[1]',
            SuggestionSchemaCodes.order,
          ),
        ],
      );
    });

    test('rect lies inside page bounds and on the 1/8 pt grid', () {
      _expectValid(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(148.5, 302.0, 210.0, 14.5),
          ),
        ),
      );

      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(-0.125, 0, 10, 10),
          ),
        ),
        'envelope.suggestions[0].rect: must lie inside the page display bounds',
        code: SuggestionSchemaCodes.range,
      );

      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(0, 0, 595.375, 10),
          ),
        ),
        'envelope.suggestions[0].rect: must lie inside the page display bounds',
        code: SuggestionSchemaCodes.range,
      );

      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(0, 0, 100.1, 10),
          ),
        ),
        'envelope.suggestions[0].rect.width: must be quantized to 1/8 pt',
        code: SuggestionSchemaCodes.format,
      );

      _expectViolation(
        _withSingle(
          _suggestion(id: 's_p0_0001', pageIndex: 0, rect: _rect(0, 0, 0, 10)),
        ),
        'envelope.suggestions[0].rect.width: must be positive',
        code: SuggestionSchemaCodes.range,
      );
    });

    test('proposedType uses the closed field-type vocabulary', () {
      for (final String type in SuggestionSchema.proposedTypes) {
        _expectValid(
          _withSingle(
            _suggestion(
              id: 's_p0_0001',
              pageIndex: 0,
              rect: _rect(100, 100, 100, 20),
              proposedType: type,
              cues: type == 'signature'
                  ? <String>['signature_area']
                  : <String>['underline'],
            ),
          ),
        );
      }
      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            proposedType: 'radio',
          ),
        ),
        'envelope.suggestions[0].proposedType: must be text, number, date, '
        'checkbox, multiline, or signature',
        code: SuggestionSchemaCodes.value,
      );
    });

    test('confidence is 0…1 with two decimals', () {
      _expectValid(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            confidence: 0,
          ),
        ),
      );
      _expectValid(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            confidence: 1,
          ),
        ),
      );
      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            confidence: 0.825,
          ),
        ),
        'envelope.suggestions[0].confidence: must be 0.0 … 1.0 with '
        'two decimals',
        code: SuggestionSchemaCodes.format,
      );
      for (final double invalid in <double>[-0.01, 1.01]) {
        _expectViolation(
          _withSingle(
            _suggestion(
              id: 's_p0_0001',
              pageIndex: 0,
              rect: _rect(100, 100, 100, 20),
              confidence: invalid,
            ),
          ),
          'envelope.suggestions[0].confidence: must be 0.0 … 1.0 with '
          'two decimals',
          code: SuggestionSchemaCodes.range,
          additional: <SuggestionSchemaViolation>[
            const SuggestionSchemaViolation(
              'envelope.suggestions[0].uncertainty',
              SuggestionSchemaCodes.range,
            ),
          ],
        );
      }
    });

    test('uncertainty is 1 − confidence with two decimals', () {
      final Map<String, Object?> mismatched = _withSingle(
        _suggestion(
          id: 's_p0_0001',
          pageIndex: 0,
          rect: _rect(100, 100, 100, 20),
        ),
      );
      _suggestionAt(mismatched, 0)['uncertainty'] = 0.17;
      _expectViolation(
        mismatched,
        'envelope.suggestions[0].uncertainty: must equal 1 - confidence',
        code: SuggestionSchemaCodes.value,
      );

      final Map<String, Object?> threeDecimals = _withSingle(
        _suggestion(
          id: 's_p0_0001',
          pageIndex: 0,
          rect: _rect(100, 100, 100, 20),
        ),
      );
      _suggestionAt(threeDecimals, 0)['uncertainty'] = 0.185;
      _expectViolation(
        threeDecimals,
        'envelope.suggestions[0].uncertainty: must be 0.0 … 1.0 with '
        'two decimals',
        count: 2,
        codes: <String>{
          SuggestionSchemaCodes.format,
          SuggestionSchemaCodes.value,
        },
      );
    });

    test('labelText is trimmed, at most 200 chars, or null', () {
      final String maxLabel = List<String>.filled(200, 'N').join();
      final String tooLong = List<String>.filled(201, 'N').join();

      _expectValid(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            labelText: maxLabel,
          ),
        ),
      );
      _expectValid(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            labelText: null,
          ),
        ),
      );
      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            labelText: ' Name',
          ),
        ),
        'envelope.suggestions[0].labelText: must be trimmed',
        code: SuggestionSchemaCodes.format,
      );
      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            labelText: '',
          ),
        ),
        'envelope.suggestions[0].labelText: must be null or a non-empty string',
        code: SuggestionSchemaCodes.type,
      );
      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            labelText: tooLong,
          ),
        ),
        'envelope.suggestions[0].labelText: must be at most 200 characters',
        code: SuggestionSchemaCodes.range,
      );
    });

    test('cues use the closed §3.1 vocabulary with uniqueness', () {
      _expectValid(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            cues: <String>[
              'underline',
              'box',
              'grid_cell',
              'whitespace',
              'alignment_left',
              'label_below',
              'ocr_alignment_right',
              'ocr_alignment_below',
              'keyword_name',
              'small_square',
              'table_cell',
              'signature_area',
              'numeric_context',
              'date_context',
            ],
            cueAgreement: 14,
          ),
        ),
      );

      // The contract requires membership and uniqueness, not a collation.
      _expectValid(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            cues: <String>['box', 'underline'],
          ),
        ),
      );
      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            cues: <String>['underline', 'underline'],
          ),
        ),
        'envelope.suggestions[0].evidence.cues: must be unique',
        code: SuggestionSchemaCodes.duplicate,
      );
      for (final String invalidCue in <String>[
        'line',
        'grid',
        'ocr_alignment',
        'keyword',
        'keyword_unknown',
        'keyword_Name',
      ]) {
        _expectViolation(
          _withSingle(
            _suggestion(
              id: 's_p0_0001',
              pageIndex: 0,
              rect: _rect(100, 100, 100, 20),
              cues: <String>['underline', invalidCue],
            ),
          ),
          'envelope.suggestions[0].evidence.cues: must use only the §3.1 '
          'closed vocabulary',
          code: SuggestionSchemaCodes.value,
        );
      }
      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            cues: <String>[],
          ),
        ),
        'envelope.suggestions[0].evidence.cues: must be a non-empty array',
        count: 2,
        codes: <String>{
          SuggestionSchemaCodes.count,
          SuggestionSchemaCodes.forbidden,
        },
      );
    });

    test('cueAgreement, skewDegrees, contrast, and ocrUsed have bounds', () {
      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            cueAgreement: 0,
          ),
        ),
        'envelope.suggestions[0].evidence.cueAgreement: must be an integer '
        '>= 1',
        code: SuggestionSchemaCodes.range,
      );
      for (final double skew in <double>[-10, 10]) {
        _expectValid(
          _withSingle(
            _suggestion(
              id: 's_p0_0001',
              pageIndex: 0,
              rect: _rect(100, 100, 100, 20),
              skewDegrees: skew,
            ),
          ),
        );
      }
      for (final double skew in <double>[-10.01, 10.01]) {
        _expectViolation(
          _withSingle(
            _suggestion(
              id: 's_p0_0001',
              pageIndex: 0,
              rect: _rect(100, 100, 100, 20),
              skewDegrees: skew,
            ),
          ),
          'envelope.suggestions[0].evidence.skewDegrees: must be between '
          '-10 and +10',
          code: SuggestionSchemaCodes.range,
        );
      }
      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            contrast: 'medium',
          ),
        ),
        'envelope.suggestions[0].evidence.contrast: must be normal or low',
        code: SuggestionSchemaCodes.value,
      );
      final Map<String, Object?> badOcrFlag = _withSingle(
        _suggestion(
          id: 's_p0_0001',
          pageIndex: 0,
          rect: _rect(100, 100, 100, 20),
        ),
      );
      (_suggestionAt(badOcrFlag, 0)['evidence']!
              as Map<String, Object?>)['ocrUsed'] =
          1;
      _expectViolation(
        badOcrFlag,
        'envelope.suggestions[0].evidence.ocrUsed: must be a bool',
        code: SuggestionSchemaCodes.type,
      );
    });

    test('ocrUsed false requires geometry-only evidence', () {
      _expectValid(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            ocrUsed: false,
          ),
        ),
      );
      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            cues: <String>['underline', 'keyword_name'],
            cueAgreement: 2,
            ocrUsed: false,
          ),
        ),
        'envelope.suggestions[0].evidence.cues: must not include OCR cues '
        'when ocrUsed is false',
        code: SuggestionSchemaCodes.forbidden,
      );
      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            cues: <String>['signature_area'],
            ocrUsed: false,
          ),
        ),
        'envelope.suggestions[0].evidence.cues: must not include OCR cues '
        'when ocrUsed is false',
        code: SuggestionSchemaCodes.forbidden,
      );
    });

    test('conflicts are symmetric, real, IoU ≥ 0.5, and both remain', () {
      final Map<String, Object?> envelope = _envelope(
        pageIndex: 0,
        suggestions: _conflictPair(),
      );
      _expectValid(envelope);
      expect(
        _suggestionIds(envelope),
        containsAll(<String>['s_p0_0001', 's_p0_0002']),
      );

      final List<Map<String, Object?>> oneSided = _conflictPair();
      oneSided[1]['conflictsWith'] = <String>[];
      _expectViolation(
        _envelope(pageIndex: 0, suggestions: oneSided),
        'envelope.suggestions[0].conflictsWith: must be symmetric',
        code: SuggestionSchemaCodes.symmetry,
      );

      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            conflictsWith: <String>['s_p0_0099'],
          ),
        ),
        'envelope.suggestions[0].conflictsWith: must reference a suggestion '
        'in the same page envelope',
        code: SuggestionSchemaCodes.reference,
      );

      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            conflictsWith: <String>['s_p0_0001'],
          ),
        ),
        'envelope.suggestions[0].conflictsWith: must not reference itself',
        code: SuggestionSchemaCodes.forbidden,
      );

      final List<Map<String, Object?>> duplicate = _conflictPair();
      duplicate[0]['conflictsWith'] = <String>['s_p0_0002', 's_p0_0002'];
      _expectViolation(
        _envelope(pageIndex: 0, suggestions: duplicate),
        'envelope.suggestions[0].conflictsWith: must not contain duplicates',
        code: SuggestionSchemaCodes.duplicate,
      );

      final List<Map<String, Object?>> lowIou = _conflictPair();
      lowIou[1]['rect'] = _rect(400, 400, 100, 20);
      _expectViolation(
        _envelope(pageIndex: 0, suggestions: lowIou),
        'envelope.suggestions[0].conflictsWith: conflicting ids require '
        'IoU >= 0.5',
        code: SuggestionSchemaCodes.overlap,
        additional: <SuggestionSchemaViolation>[
          const SuggestionSchemaViolation(
            'envelope.suggestions[1].conflictsWith',
            SuggestionSchemaCodes.overlap,
          ),
        ],
      );
    });

    test('resolution vocabulary; persisted output stays unresolved', () {
      for (final String resolution in SuggestionSchema.resolutions) {
        _expectValid(
          _withSingle(
            _suggestion(
              id: 's_p0_0001',
              pageIndex: 0,
              rect: _rect(100, 100, 100, 20),
              resolution: resolution,
            ),
          ),
          persisted: resolution == 'unresolved',
        );
      }
      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            resolution: 'confirmed',
          ),
        ),
        'envelope.suggestions[0].resolution: persisted analysis output must '
        'be unresolved',
        code: SuggestionSchemaCodes.forbidden,
      );
      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            resolution: 'maybe',
          ),
        ),
        'envelope.suggestions[0].resolution: must be unresolved, confirmed, '
        'or rejected',
        code: SuggestionSchemaCodes.value,
      );
    });

    test('§2.1 forbids auto-confirm/export fields and OCR-only evidence', () {
      final Map<String, Object?> autoConfirmed = _withSingle(
        _suggestion(
          id: 's_p0_0001',
          pageIndex: 0,
          rect: _rect(100, 100, 100, 20),
        ),
      );
      _suggestionAt(autoConfirmed, 0)['autoConfirmed'] = true;
      _expectViolation(
        autoConfirmed,
        'envelope.suggestions[0].autoConfirmed: unexpected',
        code: SuggestionSchemaCodes.unexpected,
      );

      final Map<String, Object?> exported = _withSingle(
        _suggestion(
          id: 's_p0_0001',
          pageIndex: 0,
          rect: _rect(100, 100, 100, 20),
        ),
      );
      _suggestionAt(exported, 0)['exported'] = true;
      _expectViolation(
        exported,
        'envelope.suggestions[0].exported: unexpected',
        code: SuggestionSchemaCodes.unexpected,
      );

      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            cues: <String>['keyword_name', 'numeric_context'],
            cueAgreement: 2,
          ),
        ),
        'envelope.suggestions[0].evidence.cues: must include at least one '
        'geometric cue',
        code: SuggestionSchemaCodes.forbidden,
      );
    });

    test('§2.1 ink-density rule is not schema-expressible', () {
      // FR-016 rejects candidates above 12 % ink. The wire schema has no ink
      // field, so this test cannot measure or enforce that rule. It documents
      // the boundary and fails an attempted ink flag as an unknown evidence key;
      // T051/T052 own the measurement and detector rejection.
      final Map<String, Object?> envelope = _withSingle(
        _suggestion(
          id: 's_p0_0001',
          pageIndex: 0,
          rect: _rect(100, 100, 200, 14.5),
        ),
      );
      _expectValid(envelope);
      final Map<String, Object?> evidence =
          _suggestionAt(envelope, 0)['evidence']! as Map<String, Object?>;
      evidence['inkDensity'] = 0.99;
      _expectViolation(
        envelope,
        'envelope.suggestions[0].evidence.inkDensity: unexpected',
        code: SuggestionSchemaCodes.unexpected,
      );
    });
  });

  group('recognition-output §4 failure', () {
    test('accepts every documented failure category', () {
      for (final String category in SuggestionSchema.failureCategories) {
        _expectValid(_failedEnvelope(category: category));
      }
    });

    test('failure requires category, messageKey, recoverable, count', () {
      final Map<String, Object?> missingField = _failedEnvelope();
      (missingField['failure']! as Map<String, Object?>).remove('messageKey');
      _expectViolation(
        missingField,
        'envelope.failure.messageKey: missing',
        code: SuggestionSchemaCodes.missing,
      );

      final Map<String, Object?> badRecoverable = _failedEnvelope();
      (badRecoverable['failure']! as Map<String, Object?>)['recoverable'] =
          'yes';
      _expectViolation(
        badRecoverable,
        'envelope.failure.recoverable: must be a bool',
        code: SuggestionSchemaCodes.type,
      );

      final Map<String, Object?> badCount = _failedEnvelope();
      (badCount['failure']! as Map<String, Object?>)['suggestionCount'] = -1;
      _expectViolation(
        badCount,
        'envelope.failure.suggestionCount: must be a non-negative integer',
        code: SuggestionSchemaCodes.range,
      );

      final Map<String, Object?> extraField = _failedEnvelope();
      (extraField['failure']! as Map<String, Object?>)['detail'] = 'x';
      _expectViolation(
        extraField,
        'envelope.failure.detail: unexpected',
        code: SuggestionSchemaCodes.unexpected,
      );
    });

    test('failure stays code-only and uses the category vocabulary', () {
      _expectViolation(
        _failedEnvelope(category: 'timeout'),
        'envelope.failure.category: must be rasterization, ocr, '
        'unsupported_structure, or internal',
        code: SuggestionSchemaCodes.value,
      );
      _expectViolation(
        _failedEnvelope(messageKey: 'content://secret'),
        'envelope.failure.messageKey: must be a REC-<nnn> code',
        code: SuggestionSchemaCodes.format,
      );
    });

    test('a failed page discards its suggestions but not other pages', () {
      final List<Map<String, Object?>> run = _failureIsolationRun();
      expect(_validateRun(run, pages: <PageDisplaySize>[_a4, _a4]), isEmpty);
      expect(_suggestionIds(run[0]), <String>[
        's_p0_0001',
        's_p0_0002',
        's_p0_0003',
      ]);
      expect(run[1]['suggestions'], isEmpty);
      final Map<String, Object?> failure =
          run[1]['failure']! as Map<String, Object?>;
      expect(failure['suggestionCount'], 4);
    });

    test('a failed page may not keep its own suggestions', () {
      final Map<String, Object?> envelope = _failedEnvelope();
      envelope['suggestions'] = <Map<String, Object?>>[
        _suggestion(
          id: 's_p0_0001',
          pageIndex: 0,
          rect: _rect(100, 100, 100, 20),
        ),
      ];
      _expectViolation(
        envelope,
        'envelope.suggestions: must be empty when status is failed '
        '(partial results are discarded)',
        code: SuggestionSchemaCodes.forbidden,
      );
    });
  });

  group('run-level page isolation', () {
    test('requires unique page indexes and one envelope per page', () {
      final List<Map<String, Object?>> duplicate = <Map<String, Object?>>[
        _pageZeroEnvelope(),
        _pageZeroEnvelope(),
      ];
      _expectRunViolation(
        duplicate,
        <PageDisplaySize>[_a4, _a4],
        'run.pageIndex',
        count: 2,
        codes: <String>{
          SuggestionSchemaCodes.duplicate,
          SuggestionSchemaCodes.cardinality,
        },
      );

      _expectRunViolation(
        <Map<String, Object?>>[_pageZeroEnvelope()],
        <PageDisplaySize>[_a4, _a4],
        'run.pageIndex',
        code: SuggestionSchemaCodes.cardinality,
      );
    });
  });
}
