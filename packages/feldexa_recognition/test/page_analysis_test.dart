// T057 host-VM tests for the per-page analysis envelope and isolation.
//
// Normative sources:
//  * specs/001-scanned-form-workflow/contracts/recognition-output.md
//    sections 1, 2, 4, 5, and 5.5;
//  * specs/001-scanned-form-workflow/spec.md FR-017, FR-018, FR-019, FR-020;
//  * specs/001-scanned-form-workflow/data-model.md sections 3.3 and 3.16;
//  * specs/001-scanned-form-workflow/contracts/error-catalog.de.md section 2.
//
// All documents are synthetic contract-shaped maps and display sizes. No
// raster, OCR, detector, persistence, Android runtime, network, or real
// document content is used. The T050 `SuggestionSchema` remains the validation
// oracle; these tests pin that adoption and the T057-owned envelope rules.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:feldexa_recognition/src/page_analysis.dart';
import 'package:feldexa_recognition/src/suggestion_schema.dart';
import 'package:flutter_test/flutter_test.dart';

const String _runId = '8f14e45f-ceea-467f-a2a0-1f2c3d4e5f60';
const String _otherRunId = '11111111-2222-3333-4444-555555555555';
const String _secretLabel = 'Patient Meier';
const String _secretPath = '/home/xxammaxx/private/scan.pdf';

final PageDisplaySize _a4 = PageDisplaySize(595.28, 841.89);
final PageDisplaySize _a5 = PageDisplaySize(419.53, 595.28);

// ---------------------------------------------------------------------------
// Synthetic section 1/2 fixtures
// ---------------------------------------------------------------------------

Map<String, Object?> _rect(num x, num y, num width, num height) {
  return <String, Object?>{
    'x': x.toDouble(),
    'y': y.toDouble(),
    'width': width.toDouble(),
    'height': height.toDouble(),
  };
}

Map<String, Object?> _pageSizeJson(PageDisplaySize size) {
  return <String, Object?>{'width': size.width, 'height': size.height};
}

Map<String, Object?> _timingsJson({
  int rasterMs = 210,
  int ocrMs = 1180,
  int detectMs = 430,
}) {
  return <String, Object?>{
    'rasterMs': rasterMs,
    'ocrMs': ocrMs,
    'detectMs': detectMs,
  };
}

Map<String, Object?> _suggestionJson({
  String id = 's_p0_0001',
  int pageIndex = 0,
  Map<String, Object?>? rect,
  String proposedType = 'text',
  double confidence = 0.82,
  String? labelText = 'Name',
  List<String> cues = const <String>['underline'],
  int cueAgreement = 1,
  double skewDegrees = 0.4,
  String contrast = 'normal',
  bool ocrUsed = true,
  List<String> conflictsWith = const <String>[],
}) {
  return <String, Object?>{
    'id': id,
    'pageIndex': pageIndex,
    'rect': rect ?? _rect(100, 100, 200, 14.5),
    'proposedType': proposedType,
    'confidence': confidence,
    'uncertainty': (100 - (confidence * 100).round()) / 100,
    'labelText': labelText,
    'evidence': <String, Object?>{
      'cues': cues,
      'cueAgreement': cueAgreement,
      'skewDegrees': skewDegrees,
      'contrast': contrast,
      'ocrUsed': ocrUsed,
    },
    'conflictsWith': conflictsWith,
    'resolution': 'unresolved',
  };
}

Map<String, Object?> _failureJson(PageAnalysisFailure failure) {
  return failure.toJson();
}

Map<String, Object?> _wireJson({
  int schemaVersion = SuggestionSchema.version,
  String analysisRunId = _runId,
  int pageIndex = 0,
  PageDisplaySize? pageSize,
  int rotation = 0,
  String status = 'complete',
  bool pageUncertain = false,
  String? uncertaintyReason,
  Map<String, Object?>? failure,
  List<Map<String, Object?>> suggestions = const <Map<String, Object?>>[],
  Map<String, Object?>? timings,
  String evidenceClass = 'emulator',
}) {
  return <String, Object?>{
    'schemaVersion': schemaVersion,
    'analysisRunId': analysisRunId,
    'pageIndex': pageIndex,
    'pageSizePt': _pageSizeJson(pageSize ?? _a4),
    'rotation': rotation,
    'status': status,
    'pageUncertain': pageUncertain,
    'uncertaintyReason': uncertaintyReason,
    'failure': failure,
    'suggestions': suggestions,
    'timings': timings ?? _timingsJson(),
    'evidenceClass': evidenceClass,
  };
}

FieldSuggestionSet _set({
  int pageIndex = 0,
  String analysisRunId = _runId,
  PageDisplaySize? pageSize,
  int rotation = 0,
  String status = 'complete',
  bool pageUncertain = false,
  String? uncertaintyReason,
  PageAnalysisFailure? failure,
  List<Map<String, Object?>> suggestions = const <Map<String, Object?>>[],
  PageAnalysisTimings? timings,
  String evidenceClass = 'emulator',
}) {
  return FieldSuggestionSet(
    pageIndex: pageIndex,
    analysisRunId: analysisRunId,
    pageSizePt: pageSize ?? _a4,
    rotation: rotation,
    status: status,
    pageUncertain: pageUncertain,
    uncertaintyReason: uncertaintyReason,
    failure: failure,
    suggestions: suggestions,
    timings:
        timings ??
        PageAnalysisTimings(rasterMs: 210, ocrMs: 1180, detectMs: 430),
    evidenceClass: evidenceClass,
  );
}

PageAnalysisJob _job({
  int pageIndex = 0,
  String analysisRunId = _runId,
  PageDisplaySize? pageSize,
  int rotation = 0,
  String evidenceClass = 'emulator',
}) {
  return PageAnalysisJob(
    pageIndex: pageIndex,
    analysisRunId: analysisRunId,
    pageSizePt: pageSize ?? _a4,
    rotation: rotation,
    evidenceClass: evidenceClass,
  );
}

Map<String, Object?> _deepCopyMap(Map<String, Object?> value) {
  return <String, Object?>{
    for (final MapEntry<String, Object?> entry in value.entries)
      entry.key: _deepCopyValue(entry.value),
  };
}

Object? _deepCopyValue(Object? value) {
  if (value is Map<String, Object?>) {
    return _deepCopyMap(value);
  }
  if (value is List<Object?>) {
    return value.map(_deepCopyValue).toList(growable: false);
  }
  return value;
}

Object _errorOf(void Function() action) {
  try {
    action();
  } catch (error) {
    return error;
  }
  fail('Expected an error.');
}

void _expectContentFree(Object error, Iterable<String> secrets) {
  final String text = error.toString();
  for (final String secret in secrets) {
    expect(text, isNot(contains(secret)), reason: 'error echoed $secret');
  }
}

void main() {
  group('FieldSuggestionSet section 1 round-trip', () {
    test('a complete envelope with suggestions round-trips exactly', () {
      final Map<String, Object?> first = _suggestionJson(
        id: 's_p0_0001',
        rect: _rect(100, 100, 200, 14.5),
        cues: <String>['keyword_name', 'ocr_alignment_right', 'underline'],
        cueAgreement: 3,
      );
      final Map<String, Object?> second = _suggestionJson(
        id: 's_p0_0002',
        rect: _rect(300, 200, 120, 14.5),
        proposedType: 'date',
        confidence: 0.9,
        labelText: null,
        cues: <String>['date_context', 'underline'],
        cueAgreement: 2,
      );
      final FieldSuggestionSet set = _set(
        suggestions: <Map<String, Object?>>[first, second],
      );

      expect(set.isComplete, isTrue);
      expect(set.isFailed, isFalse);
      expect(set.schemaVersion, 1);
      expect(set.suggestions, hasLength(2));
      expect(
        set.toJson(),
        _wireJson(suggestions: <Map<String, Object?>>[first, second]),
      );
      expect(FieldSuggestionSet.fromJson(set.toJson()).toJson(), set.toJson());
    });

    test('a failed envelope round-trips with its failure', () {
      final FieldSuggestionSet set = _set(
        status: FieldSuggestionSet.statusFailed,
        failure: PageAnalysisFailure.forCategory(
          PageAnalysisFailure.internal,
          suggestionCount: 4,
        ),
      );

      expect(set.isFailed, isTrue);
      expect(set.isComplete, isFalse);
      expect(set.suggestions, isEmpty);
      expect(set.failure!.suggestionCount, 4);
      final FieldSuggestionSet decoded = FieldSuggestionSet.fromJson(
        set.toJson(),
      );
      expect(decoded.toJson(), set.toJson());
      expect(decoded.failure, set.failure);
    });

    test('an uncertain envelope round-trips for every reason', () {
      for (final String reason in SuggestionSchema.uncertaintyReasons) {
        final FieldSuggestionSet set = _set(
          pageUncertain: true,
          uncertaintyReason: reason,
        );
        expect(set.pageUncertain, isTrue);
        expect(set.uncertaintyReason, reason);
        expect(
          FieldSuggestionSet.fromJson(set.toJson()).toJson(),
          set.toJson(),
        );
      }
    });

    test('every evidence class round-trips', () {
      for (final String evidenceClass in SuggestionSchema.evidenceClasses) {
        final FieldSuggestionSet set = _set(evidenceClass: evidenceClass);
        expect(set.evidenceClass, evidenceClass);
        expect(
          FieldSuggestionSet.fromJson(set.toJson()).toJson(),
          set.toJson(),
        );
      }
    });

    test('an empty complete envelope is valid', () {
      final FieldSuggestionSet set = _set();
      expect(set.suggestions, isEmpty);
      expect(set.failure, isNull);
      expect(FieldSuggestionSet.fromJson(set.toJson()).toJson(), set.toJson());
    });

    test('toJson exposes exactly the closed section 1 key set', () {
      expect(_set().toJson().keys.toSet(), SuggestionSchema.envelopeKeys);
    });

    test('fromJson normalizes suggestion order before validation', () {
      final Map<String, Object?> low = _suggestionJson(
        id: 's_p0_0001',
        rect: _rect(100, 100, 200, 14.5),
      );
      final Map<String, Object?> high = _suggestionJson(
        id: 's_p0_0002',
        rect: _rect(100, 200, 200, 14.5),
        labelText: null,
      );
      final Map<String, Object?> wire = _wireJson(
        suggestions: <Map<String, Object?>>[high, low],
      );

      final FieldSuggestionSet decoded = FieldSuggestionSet.fromJson(wire);
      expect(
        decoded.suggestions.map((Map<String, Object?> s) => s['id']).toList(),
        <String>['s_p0_0001', 's_p0_0002'],
      );
      expect(
        decoded.toJson(),
        _wireJson(suggestions: <Map<String, Object?>>[low, high]),
      );
    });

    test('canonical JSON is stable across a round-trip', () {
      final FieldSuggestionSet set = _set(
        suggestions: <Map<String, Object?>>[_suggestionJson()],
      );
      final FieldSuggestionSet decoded = FieldSuggestionSet.fromJson(
        set.toJson(),
      );
      expect(decoded.canonicalJson(), set.canonicalJson());
    });

    test('fromJson accepts a decoded JSON map for every status', () {
      final List<FieldSuggestionSet> sets = <FieldSuggestionSet>[
        _set(suggestions: <Map<String, Object?>>[_suggestionJson()]),
        _set(
          status: FieldSuggestionSet.statusFailed,
          failure: PageAnalysisFailure.forCategory(
            PageAnalysisFailure.rasterization,
            suggestionCount: 2,
          ),
        ),
      ];
      for (final FieldSuggestionSet set in sets) {
        final Object? decodedJson = jsonDecode(jsonEncode(set.toJson()));
        expect(decodedJson, isA<Map<String, Object?>>());
        final FieldSuggestionSet decoded = FieldSuggestionSet.fromJson(
          decodedJson! as Map<String, Object?>,
        );
        expect(decoded.toJson(), set.toJson());
      }
    });
  });

  group('required and forbidden pairings', () {
    test('failed requires a failure object', () {
      final Object error = _errorOf(
        () => _set(status: FieldSuggestionSet.statusFailed),
      );
      expect(error, isA<ArgumentError>());
      expect(error.toString(), contains('envelope.failure'));
    });

    test('complete forbids a failure object', () {
      final Object error = _errorOf(
        () => _set(
          failure: PageAnalysisFailure.forCategory(
            PageAnalysisFailure.internal,
          ),
        ),
      );
      expect(error, isA<ArgumentError>());
      expect(error.toString(), contains('envelope.failure'));
    });

    test('a failed envelope forbids suggestions', () {
      final Object error = _errorOf(
        () => _set(
          status: FieldSuggestionSet.statusFailed,
          failure: PageAnalysisFailure.forCategory(
            PageAnalysisFailure.internal,
          ),
          suggestions: <Map<String, Object?>>[_suggestionJson()],
        ),
      );
      expect(error, isA<ArgumentError>());
      expect(error.toString(), contains('envelope.suggestions'));
    });

    test('pageUncertain requires an uncertaintyReason', () {
      final Object constructorError = _errorOf(() => _set(pageUncertain: true));
      expect(constructorError, isA<ArgumentError>());
      expect(constructorError.toString(), contains('uncertaintyReason'));

      final Object fromJsonError = _errorOf(
        () => FieldSuggestionSet.fromJson(_wireJson(pageUncertain: true)),
      );
      expect(fromJsonError, isA<FormatException>());
      expect(fromJsonError.toString(), contains('uncertaintyReason'));
    });

    test('a valid reason is retained when pageUncertain is false', () {
      for (final String reason in SuggestionSchema.uncertaintyReasons) {
        final FieldSuggestionSet set = _set(uncertaintyReason: reason);
        expect(set.pageUncertain, isFalse);
        expect(set.uncertaintyReason, reason);
        expect(set.toJson()['uncertaintyReason'], reason);

        final FieldSuggestionSet decoded = FieldSuggestionSet.fromJson(
          set.toJson(),
        );
        expect(decoded.pageUncertain, isFalse);
        expect(decoded.uncertaintyReason, reason);
        expect(decoded.toJson(), set.toJson());

        final FieldSuggestionSet direct = FieldSuggestionSet.fromJson(
          _wireJson(uncertaintyReason: reason),
        );
        expect(direct.pageUncertain, isFalse);
        expect(direct.uncertaintyReason, reason);
      }
    });

    test('an invalid uncertainty reason is rejected in both states', () {
      for (final bool uncertain in <bool>[true, false]) {
        final Object error = _errorOf(
          () => _set(pageUncertain: uncertain, uncertaintyReason: 'blur'),
        );
        expect(error, isA<ArgumentError>());
        expect(error.toString(), contains('envelope.uncertaintyReason'));

        final Object fromJsonError = _errorOf(
          () => FieldSuggestionSet.fromJson(
            _wireJson(pageUncertain: uncertain, uncertaintyReason: 'blur'),
          ),
        );
        expect(fromJsonError, isA<FormatException>());
        expect(
          fromJsonError.toString(),
          contains('envelope.uncertaintyReason'),
        );
      }
    });

    test('an invalid status is rejected', () {
      final Object error = _errorOf(() => _set(status: 'pending'));
      expect(error, isA<ArgumentError>());
      expect(error.toString(), contains('envelope.status'));
    });

    test('an invalid rotation is rejected', () {
      final Object error = _errorOf(() => _set(rotation: 45));
      expect(error, isA<ArgumentError>());
      expect(error.toString(), contains('envelope.rotation'));
    });

    test('a non-UUID analysisRunId is rejected', () {
      final Object error = _errorOf(() => _set(analysisRunId: 'run-1'));
      expect(error, isA<ArgumentError>());
      expect(error.toString(), contains('envelope.analysisRunId'));
    });

    test('an invalid evidence class is rejected', () {
      final Object error = _errorOf(() => _set(evidenceClass: 'production'));
      expect(error, isA<ArgumentError>());
      expect(error.toString(), contains('envelope.evidenceClass'));
    });

    test('a negative page index is rejected', () {
      final Object error = _errorOf(() => _set(pageIndex: -1));
      expect(error, isA<ArgumentError>());
      expect(error.toString(), contains('pageIndex'));
    });

    test('a schemaVersion other than 1 is rejected', () {
      final Object error = _errorOf(
        () => FieldSuggestionSet.fromJson(_wireJson(schemaVersion: 2)),
      );
      expect(error, isA<FormatException>());
      expect(error.toString(), contains('envelope.schemaVersion'));
    });

    test('an unknown envelope key is rejected content-free', () {
      final Map<String, Object?> wire = _wireJson();
      wire[_secretPath] = _secretLabel;
      final Object error = _errorOf(() => FieldSuggestionSet.fromJson(wire));
      expect(error, isA<FormatException>());
      expect(error.toString(), contains('envelope.<unknown-field>'));
      _expectContentFree(error, <String>[_secretPath, _secretLabel]);
    });

    test('an unknown timings key is rejected content-free', () {
      final Map<String, Object?> wire = _wireJson(
        timings: <String, Object?>{..._timingsJson(), _secretPath: 1},
      );
      final Object error = _errorOf(() => FieldSuggestionSet.fromJson(wire));
      expect(error, isA<FormatException>());
      expect(error.toString(), contains('envelope.timings.<unknown-field>'));
      _expectContentFree(error, <String>[_secretPath]);
    });

    test('negative timings are rejected by the model and the parser', () {
      expect(
        () => PageAnalysisTimings(rasterMs: -1, ocrMs: 0, detectMs: 0),
        throwsArgumentError,
      );
      final Object error = _errorOf(
        () => FieldSuggestionSet.fromJson(
          _wireJson(timings: _timingsJson(rasterMs: -1)),
        ),
      );
      expect(error, isA<FormatException>());
      expect(error.toString(), contains('envelope.timings.rasterMs'));
    });

    test('a numerically equal double timing is rejected', () {
      final Object error = _errorOf(
        () => FieldSuggestionSet.fromJson(
          _wireJson(
            timings: <String, Object?>{
              'rasterMs': 1.0,
              'ocrMs': 0,
              'detectMs': 0,
            },
          ),
        ),
      );
      expect(error, isA<FormatException>());
      expect(error.toString(), contains('envelope.timings.rasterMs'));
    });

    test('a missing timings key is rejected', () {
      final Object error = _errorOf(
        () => FieldSuggestionSet.fromJson(
          _wireJson(timings: <String, Object?>{'rasterMs': 0, 'ocrMs': 0}),
        ),
      );
      expect(error, isA<FormatException>());
      expect(error.toString(), contains('envelope.timings.detectMs'));
    });
  });

  group('SuggestionSchema adoption', () {
    test('an invalid suggestion is rejected by the shared validator', () {
      final Map<String, Object?> suggestion = _suggestionJson();
      suggestion['confidence'] = 1.5;
      final Object error = _errorOf(
        () => _set(suggestions: <Map<String, Object?>>[suggestion]),
      );
      expect(error, isA<ArgumentError>());
      expect(error.toString(), contains('envelope.suggestions[0].confidence'));
    });

    test('an unknown suggestion key is reported at a fixed marker', () {
      final Map<String, Object?> suggestion = _suggestionJson(
        labelText: _secretLabel,
      );
      suggestion[_secretPath] = _secretLabel;
      final Object error = _errorOf(
        () => FieldSuggestionSet.fromJson(
          _wireJson(suggestions: <Map<String, Object?>>[suggestion]),
        ),
      );
      expect(error, isA<FormatException>());
      expect(
        error.toString(),
        contains('envelope.suggestions[0].<unknown-field>'),
      );
      _expectContentFree(error, <String>[_secretPath, _secretLabel]);
    });

    test('an unknown failure key is reported at a fixed marker', () {
      final Map<String, Object?> failure = _failureJson(
        PageAnalysisFailure.forCategory(PageAnalysisFailure.internal),
      );
      failure[_secretPath] = _secretLabel;
      final Object error = _errorOf(
        () => FieldSuggestionSet.fromJson(
          _wireJson(status: 'failed', failure: failure),
        ),
      );
      expect(error, isA<FormatException>());
      expect(error.toString(), contains('envelope.failure.<unknown-field>'));
      _expectContentFree(error, <String>[_secretPath, _secretLabel]);
    });

    test('an invalid label is not echoed', () {
      final Map<String, Object?> suggestion = _suggestionJson(
        labelText: ' $_secretLabel ',
      );
      final Object error = _errorOf(
        () => FieldSuggestionSet.fromJson(
          _wireJson(suggestions: <Map<String, Object?>>[suggestion]),
        ),
      );
      expect(error, isA<FormatException>());
      expect(error.toString(), contains('envelope.suggestions[0].labelText'));
      _expectContentFree(error, <String>[_secretLabel]);
    });

    test('the documented PAGE-001 reconciliation is exact', () {
      final FieldSuggestionSet set = _set(
        status: FieldSuggestionSet.statusFailed,
        failure: PageAnalysisFailure.forCategory(
          PageAnalysisFailure.rasterization,
          suggestionCount: 2,
        ),
      );
      expect(set.failure!.messageKey, 'PAGE-001');
      expect(FieldSuggestionSet.fromJson(set.toJson()).toJson(), set.toJson());

      final Object wrongKey = _errorOf(
        () => FieldSuggestionSet.fromJson(
          _wireJson(
            status: 'failed',
            failure: <String, Object?>{
              'category': 'rasterization',
              'messageKey': 'PAGE-002',
              'recoverable': true,
              'suggestionCount': 0,
            },
          ),
        ),
      );
      expect(wrongKey, isA<FormatException>());
      expect(wrongKey.toString(), contains('envelope.failure.messageKey'));

      final Object wrongCategory = _errorOf(
        () => FieldSuggestionSet.fromJson(
          _wireJson(
            status: 'failed',
            failure: <String, Object?>{
              'category': 'ocr',
              'messageKey': 'PAGE-001',
              'recoverable': true,
              'suggestionCount': 0,
            },
          ),
        ),
      );
      expect(wrongCategory, isA<FormatException>());
      expect(wrongCategory.toString(), contains('envelope.failure.messageKey'));
    });
  });

  group('PageAnalysisFailure mapping', () {
    test('all four categories map to their fixed catalog key', () {
      const Map<String, String> expected = <String, String>{
        'rasterization': 'PAGE-001',
        'ocr': 'REC-001',
        'unsupported_structure': 'REC-003',
        'internal': 'REC-002',
      };
      expect(PageAnalysisFailure.messageKeys, expected);
      for (final MapEntry<String, String> entry in expected.entries) {
        final PageAnalysisFailure failure = PageAnalysisFailure.forCategory(
          entry.key,
        );
        expect(failure.category, entry.key);
        expect(failure.messageKey, entry.value);
        expect(failure.recoverable, isTrue);
        expect(failure.suggestionCount, 0);
      }
    });

    test('every failure round-trips through fromJson', () {
      for (final String category in SuggestionSchema.failureCategories) {
        final PageAnalysisFailure failure = PageAnalysisFailure.forCategory(
          category,
          recoverable: false,
          suggestionCount: 3,
        );
        final PageAnalysisFailure decoded = PageAnalysisFailure.fromJson(
          failure.toJson(),
        );
        expect(decoded, failure);
        expect(decoded.toJson(), failure.toJson());
      }
    });

    test('a mismatched category and key are rejected', () {
      final Object error = _errorOf(
        () => PageAnalysisFailure.fromJson(<String, Object?>{
          'category': 'ocr',
          'messageKey': 'REC-002',
          'recoverable': true,
          'suggestionCount': 0,
        }),
      );
      expect(error, isA<FormatException>());
      expect(error.toString(), contains('mapping'));
    });

    test('an invalid key pattern is rejected content-free', () {
      final Object error = _errorOf(
        () => PageAnalysisFailure.fromJson(<String, Object?>{
          'category': 'internal',
          'messageKey': _secretPath,
          'recoverable': true,
          'suggestionCount': 0,
        }),
      );
      expect(error, isA<FormatException>());
      expect(error.toString(), contains('messageKey'));
      _expectContentFree(error, <String>[_secretPath]);
    });

    test('a negative suggestion count is rejected', () {
      final Object error = _errorOf(
        () => PageAnalysisFailure.fromJson(<String, Object?>{
          'category': 'internal',
          'messageKey': 'REC-002',
          'recoverable': true,
          'suggestionCount': -1,
        }),
      );
      expect(error, isA<FormatException>());
      expect(error.toString(), contains('suggestionCount'));
    });

    test('missing and extra keys are rejected content-free', () {
      final Map<String, Object?> missing = <String, Object?>{
        'category': 'internal',
        'messageKey': 'REC-002',
        'recoverable': true,
      };
      final Object missingError = _errorOf(
        () => PageAnalysisFailure.fromJson(missing),
      );
      expect(missingError, isA<FormatException>());
      expect(missingError.toString(), contains('shape'));

      final Object extraError = _errorOf(
        () => PageAnalysisFailure.fromJson(<String, Object?>{
          'category': 'internal',
          'messageKey': 'REC-002',
          'recoverable': true,
          'suggestionCount': 0,
          _secretPath: _secretLabel,
        }),
      );
      expect(extraError, isA<FormatException>());
      expect(extraError.toString(), contains('shape'));
      _expectContentFree(extraError, <String>[_secretPath, _secretLabel]);
    });

    test('toString is content-free', () {
      final PageAnalysisFailure failure = PageAnalysisFailure.forCategory(
        PageAnalysisFailure.unsupportedStructure,
        suggestionCount: 2,
      );
      final String text = failure.toString();
      expect(text, contains('unsupported_structure'));
      expect(text, contains('REC-003'));
      expect(text, isNot(contains(_secretLabel)));
      expect(text, isNot(contains(_secretPath)));
    });

    test('cancellation is not a failure category', () {
      expect(
        PageAnalysisFailure.messageKeys.values,
        isNot(contains('REC-004')),
      );
      final PageAnalysisDecision decision = classifyPageAnalysis(
        const PageAnalysisSignals(cancelled: true, rasterFailed: true),
      );
      expect(decision.isCancelled, isTrue);
      expect(decision.failure, isNull);
      expect(decision.ocrUsed, isFalse);
    });
  });

  group('classifyPageAnalysis', () {
    test('a clean page is complete with OCR evidence', () {
      final PageAnalysisDecision decision = classifyPageAnalysis(
        const PageAnalysisSignals(),
      );
      expect(decision.isComplete, isTrue);
      expect(decision.isTerminal, isTrue);
      expect(decision.ocrUsed, isTrue);
      expect(decision.failure, isNull);
    });

    test('OCR failure alone stays complete with ocrUsed false', () {
      final PageAnalysisDecision decision = classifyPageAnalysis(
        const PageAnalysisSignals(ocrFailed: true),
      );
      expect(decision.isComplete, isTrue);
      expect(decision.ocrUsed, isFalse);
      expect(decision.failure, isNull);

      final FieldSuggestionSet set = _set(
        suggestions: <Map<String, Object?>>[_suggestionJson(ocrUsed: false)],
      );
      expect(set.isComplete, isTrue);
      final Map<String, Object?> evidence =
          set.suggestions.single['evidence']! as Map<String, Object?>;
      expect(evidence['ocrUsed'], isFalse);
    });

    test('a raster failure is rasterization PAGE-001', () {
      final PageAnalysisDecision decision = classifyPageAnalysis(
        const PageAnalysisSignals(rasterFailed: true),
      );
      expect(decision.isFailed, isTrue);
      expect(decision.failure!.category, PageAnalysisFailure.rasterization);
      expect(decision.failure!.messageKey, 'PAGE-001');
    });

    test('a geometry failure is internal REC-002', () {
      final PageAnalysisDecision decision = classifyPageAnalysis(
        const PageAnalysisSignals(geometryFailed: true),
      );
      expect(decision.isFailed, isTrue);
      expect(decision.failure!.category, PageAnalysisFailure.internal);
      expect(decision.failure!.messageKey, 'REC-002');
    });

    test('an unsupported structure is unsupported_structure REC-003', () {
      final PageAnalysisDecision decision = classifyPageAnalysis(
        const PageAnalysisSignals(
          geometryFailed: true,
          structureUnsupported: true,
        ),
      );
      expect(decision.isFailed, isTrue);
      expect(
        decision.failure!.category,
        PageAnalysisFailure.unsupportedStructure,
      );
      expect(decision.failure!.messageKey, 'REC-003');
    });

    test('geometry plus OCR failure never yields the ocr category', () {
      final PageAnalysisDecision internal = classifyPageAnalysis(
        const PageAnalysisSignals(geometryFailed: true, ocrFailed: true),
      );
      expect(internal.failure!.category, PageAnalysisFailure.internal);
      expect(internal.failure!.messageKey, 'REC-002');

      final PageAnalysisDecision unsupported = classifyPageAnalysis(
        const PageAnalysisSignals(
          geometryFailed: true,
          ocrFailed: true,
          structureUnsupported: true,
        ),
      );
      expect(
        unsupported.failure!.category,
        PageAnalysisFailure.unsupportedStructure,
      );
    });

    test('raster failure wins over a geometry failure', () {
      final PageAnalysisDecision decision = classifyPageAnalysis(
        const PageAnalysisSignals(rasterFailed: true, geometryFailed: true),
      );
      expect(decision.failure!.category, PageAnalysisFailure.rasterization);
    });

    test('cancellation wins and never produces a failure', () {
      final PageAnalysisDecision decision = classifyPageAnalysis(
        const PageAnalysisSignals(
          cancelled: true,
          rasterFailed: true,
          geometryFailed: true,
          ocrFailed: true,
        ),
      );
      expect(decision.kind, PageAnalysisDecisionKind.cancelled);
      expect(decision.isTerminal, isFalse);
      expect(decision.failure, isNull);
    });

    test('the discarded suggestion count flows into the failure', () {
      final PageAnalysisDecision decision = classifyPageAnalysis(
        const PageAnalysisSignals(rasterFailed: true),
        suggestionCount: 7,
      );
      expect(decision.failure!.suggestionCount, 7);
      expect(decision.failure!.toJson()['suggestionCount'], 7);
    });

    test('a negative discarded count is rejected', () {
      expect(
        () => classifyPageAnalysis(
          const PageAnalysisSignals(),
          suggestionCount: -1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('PageAnalysisBatch isolation', () {
    test('a failing page does not change its neighbours', () {
      final Map<int, FieldSuggestionSet> baseline = <int, FieldSuggestionSet>{
        0: _set(suggestions: <Map<String, Object?>>[_suggestionJson()]),
        2: _set(
          pageIndex: 2,
          suggestions: <Map<String, Object?>>[
            _suggestionJson(
              id: 's_p2_0001',
              pageIndex: 2,
              rect: _rect(50, 50, 120, 14.5),
            ),
          ],
        ),
      };
      final List<PageAnalysisJob> jobs = <PageAnalysisJob>[
        _job(),
        _job(pageIndex: 1),
        _job(pageIndex: 2),
      ];
      final List<FieldSuggestionSet> results = PageAnalysisBatch.analyze(
        jobs: jobs,
        analyze: (PageAnalysisJob job) {
          if (job.pageIndex == 1) {
            throw StateError(_secretLabel);
          }
          return baseline[job.pageIndex]!;
        },
      );

      expect(results.map((FieldSuggestionSet s) => s.pageIndex), <int>[
        0,
        1,
        2,
      ]);
      expect(results[0].toJson(), baseline[0]!.toJson());
      expect(results[2].toJson(), baseline[2]!.toJson());
      expect(results[1].isFailed, isTrue);
      expect(results[1].failure!.category, PageAnalysisFailure.internal);
      expect(results[1].failure!.messageKey, 'REC-002');
      expect(results[1].suggestions, isEmpty);
    });

    test('an exception becomes a zero-timing internal failure', () {
      final List<FieldSuggestionSet> results = PageAnalysisBatch.analyze(
        jobs: <PageAnalysisJob>[_job()],
        analyze: (PageAnalysisJob job) {
          throw StateError(_secretPath);
        },
      );
      final FieldSuggestionSet result = results.single;
      expect(result.isFailed, isTrue);
      expect(result.failure!.suggestionCount, 0);
      expect(result.timings, PageAnalysisTimings.zero);
      expect(result.toJson()['failure'], result.failure!.toJson());
      expect(result.toString(), isNot(contains(_secretPath)));
    });

    test('a thrown PageAnalysisFailure preserves category and count', () {
      final List<FieldSuggestionSet> results = PageAnalysisBatch.analyze(
        jobs: <PageAnalysisJob>[_job()],
        analyze: (PageAnalysisJob job) {
          throw PageAnalysisFailure.forCategory(
            PageAnalysisFailure.unsupportedStructure,
            recoverable: false,
            suggestionCount: 4,
          );
        },
      );
      final FieldSuggestionSet result = results.single;
      expect(result.isFailed, isTrue);
      expect(
        result.failure!.category,
        PageAnalysisFailure.unsupportedStructure,
      );
      expect(result.failure!.messageKey, 'REC-003');
      expect(result.failure!.recoverable, isFalse);
      expect(result.failure!.suggestionCount, 4);
      expect(result.suggestions, isEmpty);
    });

    test('a returned failed envelope preserves its discarded count', () {
      final FieldSuggestionSet failed = _set(
        status: FieldSuggestionSet.statusFailed,
        failure: PageAnalysisFailure.forCategory(
          PageAnalysisFailure.internal,
          suggestionCount: 4,
        ),
      );
      final List<FieldSuggestionSet> results = PageAnalysisBatch.analyze(
        jobs: <PageAnalysisJob>[_job()],
        analyze: (PageAnalysisJob job) => failed,
      );
      expect(results.single.toJson(), failed.toJson());
      expect(results.single.failure!.suggestionCount, 4);
      expect(results.single.suggestions, isEmpty);
    });

    test('a mismatched page index becomes that page internal failure', () {
      final List<FieldSuggestionSet> results = PageAnalysisBatch.analyze(
        jobs: <PageAnalysisJob>[_job(), _job(pageIndex: 1)],
        analyze: (PageAnalysisJob job) {
          return _set(pageIndex: job.pageIndex == 0 ? 1 : 0);
        },
      );
      expect(results.map((FieldSuggestionSet s) => s.pageIndex), <int>[0, 1]);
      for (final FieldSuggestionSet result in results) {
        expect(result.isFailed, isTrue);
        expect(result.failure!.category, PageAnalysisFailure.internal);
      }
    });

    test('mismatched run, size, rotation, or evidence class is isolated', () {
      final List<PageAnalysisJob> jobs = <PageAnalysisJob>[
        _job(),
        _job(pageIndex: 1),
        _job(pageIndex: 2),
        _job(pageIndex: 3),
      ];
      final List<FieldSuggestionSet> results = PageAnalysisBatch.analyze(
        jobs: jobs,
        analyze: (PageAnalysisJob job) {
          switch (job.pageIndex) {
            case 0:
              return _set(analysisRunId: _otherRunId);
            case 1:
              return _set(pageIndex: 1, pageSize: _a5);
            case 2:
              return _set(pageIndex: 2, rotation: 90);
            default:
              return _set(pageIndex: 3, evidenceClass: 'device');
          }
        },
      );
      expect(results.map((FieldSuggestionSet s) => s.pageIndex), <int>[
        0,
        1,
        2,
        3,
      ]);
      for (final FieldSuggestionSet result in results) {
        expect(result.isFailed, isTrue);
        expect(result.failure!.messageKey, 'REC-002');
      }
    });

    test('cancelled pages are never analyzed and never failed', () {
      final List<int> analyzed = <int>[];
      final List<FieldSuggestionSet> results = PageAnalysisBatch.analyze(
        jobs: <PageAnalysisJob>[_job(), _job(pageIndex: 1), _job(pageIndex: 2)],
        isCancelled: (int pageIndex) => pageIndex == 1,
        analyze: (PageAnalysisJob job) {
          analyzed.add(job.pageIndex);
          if (job.pageIndex == 1) {
            throw StateError('cancelled pages must not run');
          }
          return _set(pageIndex: job.pageIndex);
        },
      );
      expect(analyzed, <int>[0, 2]);
      expect(results.map((FieldSuggestionSet s) => s.pageIndex), <int>[0, 2]);
      expect(results.any((FieldSuggestionSet s) => s.isFailed), isFalse);
    });

    test('cancelling every page returns no terminal outcomes', () {
      final List<FieldSuggestionSet> results = PageAnalysisBatch.analyze(
        jobs: <PageAnalysisJob>[_job(), _job(pageIndex: 1)],
        isCancelled: (int pageIndex) => true,
        analyze: (PageAnalysisJob job) => _set(pageIndex: job.pageIndex),
      );
      expect(results, isEmpty);
    });

    test('an empty job set returns an empty result', () {
      expect(
        PageAnalysisBatch.analyze(
          jobs: const <PageAnalysisJob>[],
          analyze: (PageAnalysisJob job) => _set(),
        ),
        isEmpty,
      );
    });

    test('duplicate page indexes are rejected before analysis', () {
      int calls = 0;
      final Object error = _errorOf(
        () => PageAnalysisBatch.analyze(
          jobs: <PageAnalysisJob>[_job(), _job()],
          analyze: (PageAnalysisJob job) {
            calls++;
            return _set();
          },
        ),
      );
      expect(error, isA<ArgumentError>());
      expect(error.toString(), contains('Duplicate pageIndex'));
      expect(calls, 0);
    });

    test('a negative page index is rejected before analysis', () {
      final Object error = _errorOf(
        () => PageAnalysisBatch.analyze(
          jobs: <PageAnalysisJob>[_job(pageIndex: -1)],
          analyze: (PageAnalysisJob job) => _set(),
        ),
      );
      expect(error, isA<ArgumentError>());
      expect(error.toString(), contains('pageIndex'));
    });

    test('invalid job identities are rejected before analysis', () {
      final List<PageAnalysisJob> invalid = <PageAnalysisJob>[
        _job(analysisRunId: 'not-a-uuid'),
        _job(evidenceClass: 'production'),
        _job(rotation: 45),
      ];
      for (final PageAnalysisJob job in invalid) {
        int calls = 0;
        final Object error = _errorOf(
          () => PageAnalysisBatch.analyze(
            jobs: <PageAnalysisJob>[job],
            analyze: (PageAnalysisJob job) {
              calls++;
              return _set(pageIndex: job.pageIndex);
            },
          ),
        );
        expect(error, isA<ArgumentError>());
        expect(error.toString(), contains('Invalid page analysis job'));
        expect(calls, 0);
      }
    });

    test('shuffled job order yields identical deterministic results', () {
      final List<PageAnalysisJob> ascending = <PageAnalysisJob>[
        _job(),
        _job(pageIndex: 1),
        _job(pageIndex: 2),
      ];
      final List<PageAnalysisJob> shuffled = <PageAnalysisJob>[
        ascending[2],
        ascending[0],
        ascending[1],
      ];
      FieldSuggestionSet analyzeJob(PageAnalysisJob job) {
        return _set(
          pageIndex: job.pageIndex,
          timings: PageAnalysisTimings(
            rasterMs: 10 + job.pageIndex,
            ocrMs: 20,
            detectMs: 30,
          ),
        );
      }

      final List<FieldSuggestionSet> first = PageAnalysisBatch.analyze(
        jobs: ascending,
        analyze: analyzeJob,
      );
      final List<FieldSuggestionSet> second = PageAnalysisBatch.analyze(
        jobs: shuffled,
        analyze: analyzeJob,
      );
      expect(
        second.map((FieldSuggestionSet s) => s.canonicalJson()).toList(),
        first.map((FieldSuggestionSet s) => s.canonicalJson()).toList(),
      );
      expect(second.map((FieldSuggestionSet s) => s.pageIndex).toList(), <int>[
        0,
        1,
        2,
      ]);
    });

    test('the result list is unmodifiable', () {
      final List<FieldSuggestionSet> results = PageAnalysisBatch.analyze(
        jobs: <PageAnalysisJob>[_job()],
        analyze: (PageAnalysisJob job) => _set(),
      );
      expect(() => results.add(_set()), throwsUnsupportedError);
    });

    test('the batch performs no file I/O and creates no artifacts', () {
      final Directory original = Directory.current;
      final Directory temporary = Directory.systemTemp.createTempSync(
        't057_page_analysis_',
      );
      try {
        Directory.current = temporary;
        PageAnalysisBatch.analyze(
          jobs: <PageAnalysisJob>[_job(), _job(pageIndex: 1)],
          analyze: (PageAnalysisJob job) => _set(pageIndex: job.pageIndex),
        );
        expect(temporary.listSync(), isEmpty);
      } finally {
        Directory.current = original;
        temporary.deleteSync(recursive: true);
      }
    });
  });

  group('immutability and determinism', () {
    test('caller mutations cannot change a constructed envelope', () {
      final Map<String, Object?> suggestion = _suggestionJson();
      final Map<String, Object?> rect =
          suggestion['rect']! as Map<String, Object?>;
      final List<Map<String, Object?>> input = <Map<String, Object?>>[
        suggestion,
      ];
      final FieldSuggestionSet set = _set(suggestions: input);

      input.clear();
      suggestion['labelText'] = 'changed';
      rect['x'] = 0.0;

      expect(set.suggestions, hasLength(1));
      expect(set.suggestions.single['labelText'], 'Name');
      expect(
        (set.suggestions.single['rect']! as Map<String, Object?>)['x'],
        100.0,
      );
    });

    test('stored suggestion maps and lists are frozen', () {
      final FieldSuggestionSet set = _set(
        suggestions: <Map<String, Object?>>[_suggestionJson()],
      );
      final Map<String, Object?> suggestion = set.suggestions.single;
      expect(() => suggestion['labelText'] = 'changed', throwsUnsupportedError);
      final Map<String, Object?> rect =
          suggestion['rect']! as Map<String, Object?>;
      expect(() => rect['x'] = 0.0, throwsUnsupportedError);
      final Map<String, Object?> evidence =
          suggestion['evidence']! as Map<String, Object?>;
      expect(
        () => (evidence['cues']! as List<Object?>).add('box'),
        throwsUnsupportedError,
      );
    });

    test('toJson returns a fresh mutable copy every time', () {
      final FieldSuggestionSet set = _set(
        suggestions: <Map<String, Object?>>[_suggestionJson()],
      );
      final Map<String, Object?> first = set.toJson();
      final List<Object?> suggestions = first['suggestions']! as List<Object?>;
      final Map<String, Object?> suggestion =
          suggestions.single as Map<String, Object?>;
      suggestion['labelText'] = 'changed';
      expect(set.toJson(), isNot(first));
      expect(
        ((set.toJson()['suggestions']! as List<Object?>).single
            as Map<String, Object?>)['labelText'],
        'Name',
      );
    });

    test('fromJson does not alias the input maps', () {
      final Map<String, Object?> suggestion = _suggestionJson();
      final Map<String, Object?> wire = _wireJson(
        suggestions: <Map<String, Object?>>[suggestion],
      );
      final FieldSuggestionSet set = FieldSuggestionSet.fromJson(wire);
      suggestion['labelText'] = 'changed';
      wire['status'] = 'failed';
      expect(
        ((set.toJson()['suggestions']! as List<Object?>).single
            as Map<String, Object?>)['labelText'],
        'Name',
      );
      expect(set.status, FieldSuggestionSet.statusComplete);
    });

    test('equal inputs produce equal canonical JSON under shuffled order', () {
      final Map<String, Object?> low = _suggestionJson(
        id: 's_p0_0001',
        rect: _rect(100, 100, 200, 14.5),
      );
      final Map<String, Object?> high = _suggestionJson(
        id: 's_p0_0002',
        rect: _rect(100, 200, 200, 14.5),
        labelText: null,
      );
      final FieldSuggestionSet first = _set(
        suggestions: <Map<String, Object?>>[low, high],
      );
      final FieldSuggestionSet second = _set(
        suggestions: <Map<String, Object?>>[high, low],
      );
      expect(second.canonicalJson(), first.canonicalJson());
      expect(second.toJson(), first.toJson());
    });

    test('the canonical projection excludes run, timings, and evidence', () {
      final FieldSuggestionSet first = _set(
        timings: PageAnalysisTimings(rasterMs: 1, ocrMs: 2, detectMs: 3),
        evidenceClass: 'simulated',
      );
      final FieldSuggestionSet second = _set(
        analysisRunId: _otherRunId,
        timings: PageAnalysisTimings(rasterMs: 400, ocrMs: 500, detectMs: 600),
        evidenceClass: 'device',
      );
      expect(second.canonicalJson(), first.canonicalJson());
      expect(
        first.canonicalProjection().keys,
        isNot(contains('analysisRunId')),
      );
      expect(first.canonicalProjection().keys, isNot(contains('timings')));
      expect(
        first.canonicalProjection().keys,
        isNot(contains('evidenceClass')),
      );
    });

    test('page and failure fields remain in the canonical projection', () {
      final FieldSuggestionSet complete = _set();
      final FieldSuggestionSet failed = _set(
        status: FieldSuggestionSet.statusFailed,
        failure: PageAnalysisFailure.forCategory(PageAnalysisFailure.internal),
      );
      expect(failed.canonicalJson(), isNot(complete.canonicalJson()));
      expect(complete.canonicalProjection()['pageIndex'], 0);
      expect(complete.canonicalProjection()['status'], 'complete');
    });
  });

  group('scope boundaries', () {
    test('the module imports only the shared suggestion validator', () {
      final File source = File('lib/src/page_analysis.dart');
      expect(source.existsSync(), isTrue);
      final String text = source.readAsStringSync();
      final List<String> imports = RegExp(
        r'^import .*;$',
        multiLine: true,
      ).allMatches(text).map((RegExpMatch match) => match.group(0)!).toList();
      expect(imports, <String>[
        "import 'package:feldexa_recognition/src/suggestion_schema.dart';",
      ]);
      for (final String forbidden in <String>[
        'dart:io',
        'dart:isolate',
        'dart:async',
        'package:feldexa_core',
        'package:feldexa_ports',
        'class AnalysisState',
        'class PageFailure',
        'class FieldSuggestion ',
        'class GeometryDetector',
        'class ConfidenceModel',
      ]) {
        expect(text, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('the recognition package declares no core dependency', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('feldexa_core')));
      expect(pubspec, isNot(contains('feldexa_ports')));
      expect(pubspec, isNot(contains('feldexa_application')));
    });
  });
}
