// T050 recognition-output §1–§2 contract test.
//
// This host-VM test (`NONE` evidence) pins the wire contract in
// `specs/001-scanned-form-workflow/contracts/recognition-output.md` §1
// (envelope), §2–§2.1 (suggestion and forbidden outputs), §4 (failure shape),
// and the deterministic ordering in §5.2. All documents are synthetic maps:
// no detector, raster, OCR, persistence, or real document content is used.
//
// The test is intentionally self-contained. `feldexa_recognition` has no
// recognition types yet; T057 owns the production `FieldSuggestionSet` and the
// shared barrel. Importing `feldexa_core`'s `FieldSuggestion` would require a
// dependency change that is outside T050's file scope, so the contract
// vocabulary below is mirrored test-locally from the contract and from
// `packages/feldexa_core/lib/src/model/field.dart` for shape reference only.
// When T057 lands, its types must satisfy these same assertions.
//
// Ordering notes:
//   * §5.2 states the deterministic order page → rounded y → rounded x → type
//     ordinal → ID, so within one page envelope this test pins
//     y → x → type ordinal → ID.
//   * §2 requires cues to be "sorted, unique" but names no collation. The
//     contract's own example (`underline`, `ocr_alignment_right`,
//     `keyword_name`) and §3.1's table order agree, so this test uses the §3.1
//     declaration order (keyword variants ordered by key) as the canonical
//     order.
//   * §6 allows a conflict from IoU ≥ 0.5 or the center-containment clause.
//     The task pins the IoU ≥ 0.5 subset; T055 owns the second clause.
//
// Not covered here: detection quality, ink measurement (the >12 % printed-text
// rule is detector-enforced by T051/T052 and is not schema-expressible), OCR,
// rasterization, persistence, logging behavior, runtime evidence, or any
// production class. See the T050 evidence report for the full limitations.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

const int _schemaVersion = 1;
const double _epsilon = 1e-6;

/// The contract example UUID, reused for every synthetic run.
const String _runId = '8f14e45f-ceea-467f-a2a0-1f2c3d4e5f60';

const Set<String> _envelopeKeys = <String>{
  'schemaVersion',
  'analysisRunId',
  'pageIndex',
  'pageSizePt',
  'rotation',
  'status',
  'pageUncertain',
  'uncertaintyReason',
  'failure',
  'suggestions',
  'timings',
  'evidenceClass',
};

const Set<String> _suggestionKeys = <String>{
  'id',
  'pageIndex',
  'rect',
  'proposedType',
  'confidence',
  'uncertainty',
  'labelText',
  'evidence',
  'conflictsWith',
  'resolution',
};

const Set<String> _evidenceKeys = <String>{
  'cues',
  'cueAgreement',
  'skewDegrees',
  'contrast',
  'ocrUsed',
};

const Set<String> _failureKeys = <String>{
  'category',
  'messageKey',
  'recoverable',
  'suggestionCount',
};

const Set<String> _timingKeys = <String>{'rasterMs', 'ocrMs', 'detectMs'};
const Set<int> _rotations = <int>{0, 90, 180, 270};
const Set<String> _statuses = <String>{'complete', 'failed'};

const Set<String> _uncertaintyReasons = <String>{
  'skew',
  'orientation',
  'low_contrast',
  'structure',
};

const Set<String> _proposedTypes = <String>{
  'text',
  'number',
  'date',
  'checkbox',
  'multiline',
  'signature',
};

/// FieldType declaration order used by the §5.2 "type ordinal" tie-breaker.
const List<String> _typeOrder = <String>[
  'text',
  'number',
  'date',
  'checkbox',
  'multiline',
  'signature',
];

const Set<String> _resolutions = <String>{
  'unresolved',
  'confirmed',
  'rejected',
};

const Set<String> _contrasts = <String>{'normal', 'low'};
const Set<String> _evidenceClasses = <String>{
  'simulated',
  'emulator',
  'device',
};

const Set<String> _failureCategories = <String>{
  'rasterization',
  'ocr',
  'unsupported_structure',
  'internal',
};

/// Fixed §3.1 cue tokens in declaration order. `keyword_<key>` occupies the
/// slot between `ocr_alignment_below` and `small_square`.
const Map<String, int> _cueFamilyOrder = <String, int>{
  'underline': 0,
  'box': 1,
  'grid_cell': 2,
  'whitespace': 3,
  'alignment_left': 4,
  'label_below': 5,
  'ocr_alignment_right': 6,
  'ocr_alignment_below': 7,
  'small_square': 9,
  'table_cell': 10,
  'signature_area': 11,
  'numeric_context': 12,
  'date_context': 13,
};

const int _keywordCueOrder = 8;

/// §2.1's geometric families: line, box, grid, whitespace, alignment, plus the
/// geometric square/table/signature regions from §3.1.
const Set<String> _geometricCues = <String>{
  'underline',
  'box',
  'grid_cell',
  'whitespace',
  'alignment_left',
  'small_square',
  'table_cell',
  'signature_area',
};

/// Cues that cannot appear when `ocrUsed == false` (geometry-only detection).
const Set<String> _ocrDependentCues = <String>{
  'label_below',
  'ocr_alignment_right',
  'ocr_alignment_below',
  'signature_area',
  'numeric_context',
  'date_context',
};

/// Keyword lexicon v1 from §3.1, used for the closed `keyword_<key>` vocabulary.
const List<String> _keywordLexiconV1 = <String>[
  'name',
  'vorname',
  'nachname',
  'familienname',
  'geburtsdatum',
  'geburtsort',
  'datum',
  'straße',
  'strasse',
  'hausnummer',
  'plz',
  'postleitzahl',
  'ort',
  'wohnort',
  'telefon',
  'telefax',
  'e-mail',
  'email',
  'iban',
  'bic',
  'bank',
  'konto',
  'steuernummer',
  'steuer-id',
  'aktenzeichen',
  'geschäftszeichen',
  'antrag',
  'betrag',
  'summe',
  'unterschrift',
  'datum/unterschrift',
  'monat',
  'jahr',
  'zeitraum',
  'von',
  'bis',
];

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final RegExp _suggestionIdPattern = RegExp(r'^s_p(\d+)_(\d{4,})$');
final RegExp _failureMessageKeyPattern = RegExp(r'^REC-\d{3}$');

final class _PageSize {
  const _PageSize(this.width, this.height);

  final double width;
  final double height;
}

const _PageSize _a4 = _PageSize(595.28, 841.89);
const _PageSize _a5 = _PageSize(419.53, 595.28);

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

Map<String, Object?> _pageSizeMap(_PageSize size) {
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
    'schemaVersion': _schemaVersion,
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
// Test-local contract validators
// ---------------------------------------------------------------------------

/// Validates one persisted page envelope against §1.
///
/// Findings are field paths only; no label, document text, or other content is
/// echoed.
List<String> _validateEnvelope(
  Object? raw, {
  required _PageSize display,
  int pageCount = 1,
  bool requireUnresolved = true,
}) {
  final List<String> out = <String>[];
  if (raw is! Map<String, Object?>) {
    return <String>['envelope: must be a JSON object'];
  }
  final Map<String, Object?> envelope = raw;
  _checkExactKeys(envelope, _envelopeKeys, 'envelope', out);

  if (envelope['schemaVersion'] != _schemaVersion) {
    out.add('envelope.schemaVersion: must equal 1');
  }

  final Object? analysisRunId = envelope['analysisRunId'];
  if (analysisRunId is! String || !_uuidPattern.hasMatch(analysisRunId)) {
    out.add('envelope.analysisRunId: must be a canonical lowercase UUID');
  }

  final Object? rawPageIndex = envelope['pageIndex'];
  final int? pageIndex = rawPageIndex is int ? rawPageIndex : null;
  if (pageIndex == null || pageIndex < 0 || pageIndex >= pageCount) {
    out.add('envelope.pageIndex: must be a 0-based index within the page set');
  }

  final Object? rawPageSize = envelope['pageSizePt'];
  if (rawPageSize is! Map<String, Object?>) {
    out.add('envelope.pageSizePt: must be an object');
  } else {
    _checkExactKeys(
      rawPageSize,
      const <String>{'width', 'height'},
      'envelope.pageSizePt',
      out,
    );
    final double? width = _finite(rawPageSize['width']);
    final double? height = _finite(rawPageSize['height']);
    if (width == null || (width - display.width).abs() > _epsilon) {
      out.add('envelope.pageSizePt.width: must match the page display size');
    }
    if (height == null || (height - display.height).abs() > _epsilon) {
      out.add('envelope.pageSizePt.height: must match the page display size');
    }
  }

  final Object? rotation = envelope['rotation'];
  if (rotation is! int || !_rotations.contains(rotation)) {
    out.add('envelope.rotation: must be 0, 90, 180, or 270');
  }

  final Object? status = envelope['status'];
  if (status is! String || !_statuses.contains(status)) {
    out.add('envelope.status: must be complete or failed');
  }

  final Object? pageUncertain = envelope['pageUncertain'];
  final Object? uncertaintyReason = envelope['uncertaintyReason'];
  final bool validReason =
      uncertaintyReason == null ||
      (uncertaintyReason is String &&
          _uncertaintyReasons.contains(uncertaintyReason));
  if (pageUncertain is! bool) {
    out.add('envelope.pageUncertain: must be a bool');
  }
  if (!validReason) {
    out.add(
      'envelope.uncertaintyReason: must be skew, orientation, low_contrast, '
      'structure, or null',
    );
  } else if (pageUncertain == true && uncertaintyReason == null) {
    out.add('envelope.uncertaintyReason: required when pageUncertain is true');
  } else if (pageUncertain == false && uncertaintyReason != null) {
    out.add(
      'envelope.uncertaintyReason: must be null when pageUncertain is false',
    );
  }

  final Object? failure = envelope['failure'];
  if (status == 'failed') {
    if (failure == null) {
      out.add('envelope.failure: required when status is failed');
    } else {
      _validateFailure(failure, 'envelope.failure', out);
    }
  } else if (failure != null) {
    out.add('envelope.failure: must be null unless status is failed');
  }

  final Object? rawSuggestions = envelope['suggestions'];
  if (rawSuggestions is! List<Object?>) {
    out.add('envelope.suggestions: must be an array');
  } else {
    if (status == 'failed' && rawSuggestions.isNotEmpty) {
      out.add(
        'envelope.suggestions: must be empty when status is failed '
        '(partial results are discarded)',
      );
    }
    final List<Map<String, Object?>> suggestions = <Map<String, Object?>>[];
    for (int i = 0; i < rawSuggestions.length; i++) {
      final Object? item = rawSuggestions[i];
      if (item is Map<String, Object?>) {
        suggestions.add(item);
      } else {
        out.add('envelope.suggestions[$i]: must be an object');
      }
    }
    final List<Map<String, Object?>> sorted = _sortedSuggestions(suggestions);
    for (int i = 0; i < suggestions.length; i++) {
      final Map<String, Object?> suggestion = suggestions[i];
      final int sortedIndex = sorted.indexOf(suggestion);
      final int expectedOrdinal = sortedIndex < 0 ? i + 1 : sortedIndex + 1;
      if (sortedIndex != i) {
        out.add(
          'envelope.suggestions[$i]: must follow the §5.2 deterministic order',
        );
      }
      _validateSuggestion(
        suggestion,
        path: 'envelope.suggestions[$i]',
        envelopePageIndex: pageIndex,
        display: display,
        siblings: suggestions,
        expectedOrdinal: expectedOrdinal,
        requireUnresolved: requireUnresolved,
        out: out,
      );
    }
  }

  final Object? rawTimings = envelope['timings'];
  if (rawTimings is! Map<String, Object?>) {
    out.add('envelope.timings: must be an object');
  } else {
    _checkExactKeys(rawTimings, _timingKeys, 'envelope.timings', out);
    for (final String key in _timingKeys) {
      final Object? value = rawTimings[key];
      if (value is! int || value < 0) {
        out.add('envelope.timings.$key: must be a non-negative integer');
      }
    }
  }

  final Object? evidenceClass = envelope['evidenceClass'];
  if (evidenceClass is! String || !_evidenceClasses.contains(evidenceClass)) {
    out.add('envelope.evidenceClass: must be simulated, emulator, or device');
  }

  return out;
}

/// Validates the whole run: one envelope per page, one shared run id.
List<String> _validateRun(Object? raw, {required List<_PageSize> pages}) {
  final List<String> out = <String>[];
  if (raw is! List<Object?> || raw.isEmpty || pages.isEmpty) {
    return <String>['run: must be a non-empty array of page envelopes'];
  }
  final List<Map<String, Object?>> envelopes = <Map<String, Object?>>[];
  for (int i = 0; i < raw.length; i++) {
    final Object? item = raw[i];
    if (item is Map<String, Object?>) {
      envelopes.add(item);
    } else {
      out.add('run[$i]: must be an object');
    }
  }
  final Set<Object?> runIds = envelopes
      .map((Map<String, Object?> envelope) => envelope['analysisRunId'])
      .toSet();
  if (runIds.length > 1) {
    out.add(
      'run.analysisRunId: every page envelope of a run must share one id',
    );
  }
  final Set<int> seenPages = <int>{};
  for (final Map<String, Object?> envelope in envelopes) {
    final Object? rawPageIndex = envelope['pageIndex'];
    final int? pageIndex = rawPageIndex is int ? rawPageIndex : null;
    if (pageIndex != null && !seenPages.add(pageIndex)) {
      out.add('run.pageIndex: must not repeat a page');
    }
    final _PageSize display =
        pageIndex != null && pageIndex >= 0 && pageIndex < pages.length
        ? pages[pageIndex]
        : pages.first;
    out.addAll(
      _validateEnvelope(envelope, display: display, pageCount: pages.length),
    );
  }
  bool coversEveryPage = envelopes.length == pages.length;
  for (int i = 0; i < pages.length; i++) {
    if (!seenPages.contains(i)) {
      coversEveryPage = false;
    }
  }
  if (!coversEveryPage) {
    out.add('run.pageIndex: one envelope per page is required');
  }
  return out;
}

void _validateSuggestion(
  Map<String, Object?> suggestion, {
  required String path,
  required int? envelopePageIndex,
  required _PageSize display,
  required List<Map<String, Object?>> siblings,
  required int expectedOrdinal,
  required bool requireUnresolved,
  required List<String> out,
}) {
  _checkExactKeys(suggestion, _suggestionKeys, path, out);

  final Object? rawId = suggestion['id'];
  if (rawId is! String) {
    out.add('$path.id: must match s_p<pageIndex>_<zero-padded ordinal>');
  } else {
    final RegExpMatch? match = _suggestionIdPattern.firstMatch(rawId);
    if (match == null) {
      out.add('$path.id: must match s_p<pageIndex>_<zero-padded ordinal>');
    } else {
      final String pageToken = match.group(1)!;
      final String ordinalToken = match.group(2)!;
      if (envelopePageIndex == null ||
          int.tryParse(pageToken) != envelopePageIndex) {
        out.add('$path.id: page token must equal pageIndex');
      }
      if (pageToken != '$envelopePageIndex') {
        out.add('$path.id: page token must be plain decimal without padding');
      }
      final int? ordinal = int.tryParse(ordinalToken);
      if (ordinal == null || ordinal < 1) {
        out.add('$path.id: ordinal must be at least 1');
      } else {
        if (ordinalToken != ordinal.toString().padLeft(4, '0')) {
          out.add(
            '$path.id: ordinal must use the canonical four-digit padding',
          );
        }
        if (ordinal != expectedOrdinal) {
          out.add('$path.id: ordinal must equal the post-sort position');
        }
      }
    }
  }

  if (envelopePageIndex == null ||
      suggestion['pageIndex'] != envelopePageIndex) {
    out.add('$path.pageIndex: must equal the envelope pageIndex');
  }

  final Object? rawRect = suggestion['rect'];
  final ({double x, double y, double width, double height})? rect = _rectValues(
    rawRect,
  );
  if (rawRect is! Map<String, Object?>) {
    out.add('$path.rect: must be an object');
  } else {
    _checkExactKeys(
      rawRect,
      const <String>{'x', 'y', 'width', 'height'},
      '$path.rect',
      out,
    );
    if (rect == null) {
      out.add('$path.rect: must contain finite x, y, width, and height');
    } else {
      if (rect.width <= 0) {
        out.add('$path.rect.width: must be positive');
      }
      if (rect.height <= 0) {
        out.add('$path.rect.height: must be positive');
      }
      if (rect.x < -_epsilon ||
          rect.y < -_epsilon ||
          rect.x + rect.width > display.width + _epsilon ||
          rect.y + rect.height > display.height + _epsilon) {
        out.add('$path.rect: must lie inside the page display bounds');
      }
      for (final String key in const <String>['x', 'y', 'width', 'height']) {
        final double? value = _finite(rawRect[key]);
        if (value != null && !_isEighth(value)) {
          out.add('$path.rect.$key: must be quantized to 1/8 pt');
        }
      }
    }
  }

  final Object? proposedType = suggestion['proposedType'];
  if (proposedType is! String || !_proposedTypes.contains(proposedType)) {
    out.add(
      '$path.proposedType: must be text, number, date, checkbox, multiline, '
      'or signature',
    );
  }

  final double? confidence = _finite(suggestion['confidence']);
  if (confidence == null ||
      confidence < 0 ||
      confidence > 1 ||
      !_hasTwoDecimals(confidence)) {
    out.add('$path.confidence: must be 0.0 … 1.0 with two decimals');
  }

  final double? uncertainty = _finite(suggestion['uncertainty']);
  if (uncertainty == null ||
      uncertainty < 0 ||
      uncertainty > 1 ||
      !_hasTwoDecimals(uncertainty)) {
    out.add('$path.uncertainty: must be 0.0 … 1.0 with two decimals');
  } else if (confidence != null &&
      (uncertainty - _round2(1 - confidence)).abs() > _epsilon) {
    out.add('$path.uncertainty: must equal 1 - confidence');
  }

  final Object? labelText = suggestion['labelText'];
  if (labelText != null) {
    if (labelText is! String || labelText.isEmpty) {
      out.add('$path.labelText: must be null or a non-empty string');
    } else {
      if (labelText != labelText.trim()) {
        out.add('$path.labelText: must be trimmed');
      }
      if (labelText.runes.length > 200) {
        out.add('$path.labelText: must be at most 200 characters');
      }
    }
  }

  final Object? rawEvidence = suggestion['evidence'];
  if (rawEvidence is! Map<String, Object?>) {
    out.add('$path.evidence: must be an object');
  } else {
    _validateEvidence(rawEvidence, path: '$path.evidence', out: out);
  }

  _validateConflicts(suggestion, path: path, siblings: siblings, out: out);

  final Object? resolution = suggestion['resolution'];
  if (resolution is! String || !_resolutions.contains(resolution)) {
    out.add('$path.resolution: must be unresolved, confirmed, or rejected');
  } else if (requireUnresolved && resolution != 'unresolved') {
    out.add('$path.resolution: persisted analysis output must be unresolved');
  }
}

void _validateEvidence(
  Map<String, Object?> evidence, {
  required String path,
  required List<String> out,
}) {
  _checkExactKeys(evidence, _evidenceKeys, path, out);

  final Object? rawCues = evidence['cues'];
  if (rawCues is! List<Object?>) {
    out.add('$path.cues: must be a non-empty array');
  } else {
    final List<String> cues = <String>[];
    for (int i = 0; i < rawCues.length; i++) {
      final Object? cue = rawCues[i];
      if (cue is String) {
        cues.add(cue);
      } else {
        out.add('$path.cues: must use only the §3.1 closed vocabulary');
      }
    }
    if (cues.isEmpty) {
      out.add('$path.cues: must be a non-empty array');
    }
    if (cues.toSet().length != cues.length) {
      out.add('$path.cues: must be unique');
    }
    for (final String cue in cues) {
      if (!_isKnownCue(cue)) {
        out.add('$path.cues: must use only the §3.1 closed vocabulary');
        break;
      }
    }
    for (int i = 1; i < cues.length; i++) {
      if (_compareCues(cues[i - 1], cues[i]) >= 0) {
        out.add('$path.cues: must follow the §3.1 vocabulary order');
        break;
      }
    }
    if (!cues.any(_isGeometric)) {
      out.add('$path.cues: must include at least one geometric cue');
    }
    final Object? ocrUsed = evidence['ocrUsed'];
    if (ocrUsed == false && cues.any((String cue) => _requiresOcr(cue))) {
      out.add('$path.cues: must not include OCR cues when ocrUsed is false');
    }
  }

  final Object? cueAgreement = evidence['cueAgreement'];
  if (cueAgreement is! int || cueAgreement < 1) {
    out.add('$path.cueAgreement: must be an integer >= 1');
  }

  final double? skewDegrees = _finite(evidence['skewDegrees']);
  if (skewDegrees == null || skewDegrees < -10 || skewDegrees > 10) {
    out.add('$path.skewDegrees: must be between -10 and +10');
  }

  final Object? contrast = evidence['contrast'];
  if (contrast is! String || !_contrasts.contains(contrast)) {
    out.add('$path.contrast: must be normal or low');
  }

  if (evidence['ocrUsed'] is! bool) {
    out.add('$path.ocrUsed: must be a bool');
  }
}

void _validateConflicts(
  Map<String, Object?> suggestion, {
  required String path,
  required List<Map<String, Object?>> siblings,
  required List<String> out,
}) {
  final Object? rawConflicts = suggestion['conflictsWith'];
  if (rawConflicts is! List<Object?>) {
    out.add('$path.conflictsWith: must be an array of suggestion ids');
    return;
  }
  final List<String> conflicts = <String>[];
  for (final Object? item in rawConflicts) {
    if (item is String) {
      conflicts.add(item);
    } else {
      out.add('$path.conflictsWith: must be an array of suggestion ids');
    }
  }
  if (conflicts.toSet().length != conflicts.length) {
    out.add('$path.conflictsWith: must not contain duplicates');
  }
  final Object? ownId = suggestion['id'];
  if (ownId is String && conflicts.contains(ownId)) {
    out.add('$path.conflictsWith: must not reference itself');
  }
  final Map<String, Map<String, Object?>> byId = <String, Map<String, Object?>>{
    for (final Map<String, Object?> sibling in siblings)
      if (sibling['id'] case final String id) id: sibling,
  };
  for (final String otherId in conflicts) {
    final Map<String, Object?>? other = byId[otherId];
    if (other == null) {
      out.add(
        '$path.conflictsWith: must reference a suggestion in the same page '
        'envelope',
      );
      continue;
    }
    final Object? otherConflicts = other['conflictsWith'];
    if (otherConflicts is! List<Object?> || !otherConflicts.contains(ownId)) {
      out.add('$path.conflictsWith: must be symmetric');
    }
    final double? iou = _iou(suggestion['rect'], other['rect']);
    if (iou == null || iou < 0.5 - _epsilon) {
      out.add('$path.conflictsWith: conflicting ids require IoU >= 0.5');
    }
  }
}

void _validateFailure(Object? raw, String path, List<String> out) {
  if (raw is! Map<String, Object?>) {
    out.add('$path: must be an object');
    return;
  }
  _checkExactKeys(raw, _failureKeys, path, out);

  final Object? category = raw['category'];
  if (category is! String || !_failureCategories.contains(category)) {
    out.add(
      '$path.category: must be rasterization, ocr, unsupported_structure, '
      'or internal',
    );
  }
  final Object? messageKey = raw['messageKey'];
  if (messageKey is! String ||
      !_failureMessageKeyPattern.hasMatch(messageKey)) {
    out.add('$path.messageKey: must be a REC-<nnn> code');
  }
  if (raw['recoverable'] is! bool) {
    out.add('$path.recoverable: must be a bool');
  }
  final Object? suggestionCount = raw['suggestionCount'];
  if (suggestionCount is! int || suggestionCount < 0) {
    out.add('$path.suggestionCount: must be a non-negative integer');
  }
}

// ---------------------------------------------------------------------------
// Contract helpers
// ---------------------------------------------------------------------------

void _checkExactKeys(
  Map<String, Object?> map,
  Set<String> keys,
  String path,
  List<String> out,
) {
  for (final String key in keys) {
    if (!map.containsKey(key)) {
      out.add('$path.$key: missing');
    }
  }
  for (final String key in map.keys) {
    if (!keys.contains(key)) {
      out.add('$path.$key: unexpected');
    }
  }
}

double? _finite(Object? value) {
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  return null;
}

bool _isEighth(double value) {
  final double scaled = value * 8;
  return (scaled - scaled.roundToDouble()).abs() <= _epsilon;
}

bool _hasTwoDecimals(double value) {
  final double scaled = value * 100;
  return (scaled - scaled.roundToDouble()).abs() <= _epsilon;
}

double _round2(double value) => (value * 100).roundToDouble() / 100;

double _roundToEighth(double value) => (value * 8).roundToDouble() / 8;

bool _isKnownCue(String cue) {
  if (cue.startsWith('keyword_')) {
    return _keywordLexiconV1.contains(cue.substring('keyword_'.length));
  }
  return _cueFamilyOrder.containsKey(cue);
}

bool _isGeometric(String cue) => _geometricCues.contains(cue);

bool _requiresOcr(String cue) {
  if (cue.startsWith('keyword_')) {
    return true;
  }
  return _ocrDependentCues.contains(cue);
}

int _cueOrder(String cue) {
  if (cue.startsWith('keyword_')) {
    return _keywordCueOrder;
  }
  return _cueFamilyOrder[cue] ?? 999;
}

String _cueSortKey(String cue) {
  return cue.startsWith('keyword_') ? cue.substring('keyword_'.length) : '';
}

int _compareCues(String a, String b) {
  final int byOrder = _cueOrder(a).compareTo(_cueOrder(b));
  if (byOrder != 0) {
    return byOrder;
  }
  return _cueSortKey(a).compareTo(_cueSortKey(b));
}

int _typeOrdinal(Object? type) {
  final int index = type is String ? _typeOrder.indexOf(type) : -1;
  return index < 0 ? _typeOrder.length : index;
}

String _idOf(Map<String, Object?> suggestion) {
  final Object? id = suggestion['id'];
  return id is String ? id : '';
}

int _compareSuggestions(Map<String, Object?> a, Map<String, Object?> b) {
  final ({double x, double y, double width, double height})? rectA =
      _rectValues(a['rect']);
  final ({double x, double y, double width, double height})? rectB =
      _rectValues(b['rect']);
  final double ay = rectA == null ? double.infinity : _roundToEighth(rectA.y);
  final double by = rectB == null ? double.infinity : _roundToEighth(rectB.y);
  if (ay != by) {
    return ay.compareTo(by);
  }
  final double ax = rectA == null ? double.infinity : _roundToEighth(rectA.x);
  final double bx = rectB == null ? double.infinity : _roundToEighth(rectB.x);
  if (ax != bx) {
    return ax.compareTo(bx);
  }
  final int byType = _typeOrdinal(a['proposedType'])
      .compareTo(_typeOrdinal(b['proposedType']));
  if (byType != 0) {
    return byType;
  }
  return _idOf(a).compareTo(_idOf(b));
}

List<Map<String, Object?>> _sortedSuggestions(
  List<Map<String, Object?>> input,
) {
  final List<Map<String, Object?>> sorted = List<Map<String, Object?>>.of(
    input,
  );
  sorted.sort(_compareSuggestions);
  return sorted;
}

({double x, double y, double width, double height})? _rectValues(Object? raw) {
  if (raw is! Map<String, Object?>) {
    return null;
  }
  final double? x = _finite(raw['x']);
  final double? y = _finite(raw['y']);
  final double? width = _finite(raw['width']);
  final double? height = _finite(raw['height']);
  if (x == null || y == null || width == null || height == null) {
    return null;
  }
  return (x: x, y: y, width: width, height: height);
}

double? _iou(Object? rawA, Object? rawB) {
  final ({double x, double y, double width, double height})? a = _rectValues(
    rawA,
  );
  final ({double x, double y, double width, double height})? b = _rectValues(
    rawB,
  );
  if (a == null || b == null) {
    return null;
  }
  final double left = math.max(a.x, b.x);
  final double top = math.max(a.y, b.y);
  final double right = math.min(a.x + a.width, b.x + b.width);
  final double bottom = math.min(a.y + a.height, b.y + b.height);
  final double intersectionWidth = right - left;
  final double intersectionHeight = bottom - top;
  if (intersectionWidth <= 0 || intersectionHeight <= 0) {
    return 0;
  }
  final double intersection = intersectionWidth * intersectionHeight;
  final double union = a.width * a.height + b.width * b.height - intersection;
  return union <= 0 ? 0 : intersection / union;
}

/// Canonical-hash input for §1: `timings` and `evidenceClass` are diagnostics
/// and are excluded from revision hashing and golden equality.
Map<String, Object?> _canonicalProjection(Map<String, Object?> envelope) {
  final Map<String, Object?> projection = _copy(envelope);
  projection.remove('timings');
  projection.remove('evidenceClass');
  return projection;
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map<String, Object?>) {
    final List<String> keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final String key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List<Object?>) {
    return value.map<Object?>(_canonicalize).toList();
  }
  return value;
}

Object? _deepCopy(Object? value) {
  if (value is Map<String, Object?>) {
    return <String, Object?>{
      for (final MapEntry<String, Object?> entry in value.entries)
        entry.key: _deepCopy(entry.value),
    };
  }
  if (value is List<Object?>) {
    return value.map<Object?>(_deepCopy).toList();
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

// ---------------------------------------------------------------------------
// Positive and negative assertion helpers
// ---------------------------------------------------------------------------

void _expectValid(
  Map<String, Object?> envelope, {
  _PageSize display = _a4,
  bool requireUnresolved = true,
}) {
  expect(
    _validateEnvelope(
      envelope,
      display: display,
      requireUnresolved: requireUnresolved,
    ),
    isEmpty,
  );
}

void _expectViolation(
  Map<String, Object?> envelope,
  String finding, {
  _PageSize display = _a4,
  bool requireUnresolved = true,
}) {
  expect(
    _validateEnvelope(
      envelope,
      display: display,
      requireUnresolved: requireUnresolved,
    ),
    contains(finding),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('recognition-output §1 envelope', () {
    test('accepts one envelope per page in a complete run', () {
      final List<Map<String, Object?>> run = _completeRun();
      expect(_validateRun(run, pages: <_PageSize>[_a4, _a4]), isEmpty);
      expect(run, hasLength(2));
      expect(run[0]['analysisRunId'], run[1]['analysisRunId']);
      expect(run[0]['pageIndex'], 0);
      expect(run[1]['pageIndex'], 1);
    });

    test('rejects unknown envelope keys, including auto-export flags', () {
      final Map<String, Object?> envelope = _pageZeroEnvelope()
        ..['exported'] = true;
      _expectViolation(envelope, 'envelope.exported: unexpected');
    });

    test('requires every §1 key, including nullable failure and reason', () {
      final Map<String, Object?> missingFailure = _copy(_pageZeroEnvelope())
        ..remove('failure');
      _expectViolation(missingFailure, 'envelope.failure: missing');

      final Map<String, Object?> missingReason = _copy(_pageZeroEnvelope())
        ..remove('uncertaintyReason');
      _expectViolation(missingReason, 'envelope.uncertaintyReason: missing');
    });

    test('requires schemaVersion 1', () {
      final Map<String, Object?> envelope = _pageZeroEnvelope()
        ..['schemaVersion'] = 2;
      _expectViolation(envelope, 'envelope.schemaVersion: must equal 1');
    });

    test('requires a canonical UUID analysisRunId shared by every page', () {
      final Map<String, Object?> invalid = _pageZeroEnvelope()
        ..['analysisRunId'] = 'not-a-uuid';
      _expectViolation(
        invalid,
        'envelope.analysisRunId: must be a canonical lowercase UUID',
      );

      final List<Map<String, Object?>> run = _completeRun();
      run[1]['analysisRunId'] = '00000000-0000-4000-8000-000000000000';
      expect(
        _validateRun(run, pages: <_PageSize>[_a4, _a4]),
        contains(
          'run.analysisRunId: every page envelope of a run must share one id',
        ),
      );
    });

    test('requires a valid 0-based pageIndex and matching pageSizePt', () {
      final Map<String, Object?> wrongIndex = _pageZeroEnvelope()
        ..['pageIndex'] = 1;
      _expectViolation(
        wrongIndex,
        'envelope.pageIndex: must be a 0-based index within the page set',
      );

      final Map<String, Object?> wrongSize = _pageZeroEnvelope()
        ..['pageSizePt'] = _pageSizeMap(const _PageSize(595.27, 841.89));
      _expectViolation(
        wrongSize,
        'envelope.pageSizePt.width: must match the page display size',
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
      );

      final Map<String, Object?> extraFailure = _pageZeroEnvelope()
        ..['failure'] = _failure();
      _expectViolation(
        extraFailure,
        'envelope.failure: must be null unless status is failed',
      );

      final Map<String, Object?> pending = _pageZeroEnvelope()
        ..['status'] = 'pending';
      _expectViolation(pending, 'envelope.status: must be complete or failed');
    });

    test('keeps pageUncertain and uncertaintyReason consistent', () {
      for (final String reason in _uncertaintyReasons) {
        _expectValid(_uncertain(reason));
      }
      _expectValid(_pageZeroEnvelope());

      _expectViolation(
        _uncertain(null),
        'envelope.uncertaintyReason: required when pageUncertain is true',
      );

      final Map<String, Object?> reasonWithoutFlag = _pageZeroEnvelope()
        ..['uncertaintyReason'] = 'skew';
      _expectViolation(
        reasonWithoutFlag,
        'envelope.uncertaintyReason: must be null when pageUncertain is false',
      );

      _expectViolation(
        _uncertain('blur'),
        'envelope.uncertaintyReason: must be skew, orientation, low_contrast, '
        'structure, or null',
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
      );

      final Map<String, Object?> missingStage = _pageZeroEnvelope()
        ..['timings'] = <String, Object?>{'rasterMs': 1, 'ocrMs': 2};
      _expectViolation(missingStage, 'envelope.timings.detectMs: missing');

      final Map<String, Object?> extraStage = _pageZeroEnvelope()
        ..['timings'] = <String, Object?>{
          'rasterMs': 1,
          'ocrMs': 2,
          'detectMs': 3,
          'totalMs': 6,
        };
      _expectViolation(extraStage, 'envelope.timings.totalMs: unexpected');
    });

    test('evidenceClass is simulated, emulator, or device', () {
      for (final String evidenceClass in _evidenceClasses) {
        _expectValid(_pageZeroEnvelope()..['evidenceClass'] = evidenceClass);
      }
      final Map<String, Object?> web = _pageZeroEnvelope()
        ..['evidenceClass'] = 'web';
      _expectViolation(
        web,
        'envelope.evidenceClass: must be simulated, emulator, or device',
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

      final Map<String, Object?> projection = _canonicalProjection(baseline);
      expect(projection, isNot(contains('timings')));
      expect(projection, isNot(contains('evidenceClass')));
      expect(
        _canonicalJson(projection),
        _canonicalJson(_canonicalProjection(diagnosticsOnly)),
      );

      diagnosticsOnly['rotation'] = 90;
      expect(
        _canonicalJson(projection),
        isNot(_canonicalJson(_canonicalProjection(diagnosticsOnly))),
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
      );

      _expectViolation(
        _withSingle(
          _suggestion(id: 's_p0_0001', pageIndex: 0, rect: _rect(0, 0, 0, 10)),
        ),
        'envelope.suggestions[0].rect.width: must be positive',
      );
    });

    test('proposedType uses the closed field-type vocabulary', () {
      for (final String type in _proposedTypes) {
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
      for (final double invalid in <double>[-0.01, 0.825, 1.01]) {
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
      );
    });

    test('cues use the closed §3.1 vocabulary, sorted and unique', () {
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

      _expectViolation(
        _withSingle(
          _suggestion(
            id: 's_p0_0001',
            pageIndex: 0,
            rect: _rect(100, 100, 100, 20),
            cues: <String>['box', 'underline'],
          ),
        ),
        'envelope.suggestions[0].evidence.cues: must follow the §3.1 '
        'vocabulary order',
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
              cues: <String>[invalidCue],
            ),
          ),
          'envelope.suggestions[0].evidence.cues: must use only the §3.1 '
          'closed vocabulary',
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
      );

      final List<Map<String, Object?>> unknownId = _conflictPair();
      unknownId[0]['conflictsWith'] = <String>['s_p0_0099'];
      _expectViolation(
        _envelope(pageIndex: 0, suggestions: unknownId),
        'envelope.suggestions[0].conflictsWith: must reference a suggestion '
        'in the same page envelope',
      );

      final List<Map<String, Object?>> selfReference = _conflictPair();
      selfReference[0]['conflictsWith'] = <String>['s_p0_0001'];
      _expectViolation(
        _envelope(pageIndex: 0, suggestions: selfReference),
        'envelope.suggestions[0].conflictsWith: must not reference itself',
      );

      final List<Map<String, Object?>> duplicate = _conflictPair();
      duplicate[0]['conflictsWith'] = <String>['s_p0_0002', 's_p0_0002'];
      _expectViolation(
        _envelope(pageIndex: 0, suggestions: duplicate),
        'envelope.suggestions[0].conflictsWith: must not contain duplicates',
      );

      final List<Map<String, Object?>> lowIou = _conflictPair();
      lowIou[1]['rect'] = _rect(400, 400, 100, 20);
      _expectViolation(
        _envelope(pageIndex: 0, suggestions: lowIou),
        'envelope.suggestions[0].conflictsWith: conflicting ids require '
        'IoU >= 0.5',
      );
    });

    test('resolution vocabulary; persisted output stays unresolved', () {
      for (final String resolution in _resolutions) {
        _expectValid(
          _withSingle(
            _suggestion(
              id: 's_p0_0001',
              pageIndex: 0,
              rect: _rect(100, 100, 100, 20),
              resolution: resolution,
            ),
          ),
          requireUnresolved: resolution == 'unresolved',
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
      );
    });
  });

  group('recognition-output §4 failure', () {
    test('accepts every documented failure category', () {
      for (final String category in _failureCategories) {
        _expectValid(_failedEnvelope(category: category));
      }
    });

    test('failure requires category, messageKey, recoverable, count', () {
      final Map<String, Object?> missingField = _failedEnvelope();
      (missingField['failure']! as Map<String, Object?>).remove('messageKey');
      _expectViolation(missingField, 'envelope.failure.messageKey: missing');

      final Map<String, Object?> badRecoverable = _failedEnvelope();
      (badRecoverable['failure']! as Map<String, Object?>)['recoverable'] =
          'yes';
      _expectViolation(
        badRecoverable,
        'envelope.failure.recoverable: must be a bool',
      );

      final Map<String, Object?> badCount = _failedEnvelope();
      (badCount['failure']! as Map<String, Object?>)['suggestionCount'] = -1;
      _expectViolation(
        badCount,
        'envelope.failure.suggestionCount: must be a non-negative integer',
      );

      final Map<String, Object?> extraField = _failedEnvelope();
      (extraField['failure']! as Map<String, Object?>)['detail'] = 'x';
      _expectViolation(extraField, 'envelope.failure.detail: unexpected');
    });

    test('failure stays code-only and uses the category vocabulary', () {
      _expectViolation(
        _failedEnvelope(category: 'timeout'),
        'envelope.failure.category: must be rasterization, ocr, '
        'unsupported_structure, or internal',
      );
      _expectViolation(
        _failedEnvelope(messageKey: 'content://secret'),
        'envelope.failure.messageKey: must be a REC-<nnn> code',
      );
    });

    test('a failed page discards its suggestions but not other pages', () {
      final List<Map<String, Object?>> run = _failureIsolationRun();
      expect(_validateRun(run, pages: <_PageSize>[_a4, _a4]), isEmpty);
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
      );
    });
  });

  group('run-level page isolation', () {
    test('requires unique page indexes and one envelope per page', () {
      final List<Map<String, Object?>> duplicate = _completeRun();
      duplicate[1]['pageIndex'] = 0;
      expect(
        _validateRun(duplicate, pages: <_PageSize>[_a4, _a4]),
        contains('run.pageIndex: must not repeat a page'),
      );

      expect(
        _validateRun(
          <Map<String, Object?>>[_pageZeroEnvelope()],
          pages: <_PageSize>[_a4, _a4],
        ),
        contains('run.pageIndex: one envelope per page is required'),
      );
    });
  });
}
