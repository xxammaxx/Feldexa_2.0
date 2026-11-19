// T050 recognition-output schema validation.
//
// This is the production schema surface for
// `specs/001-scanned-form-workflow/contracts/recognition-output.md` §1, §2,
// §2.1, §4, §5, and the deterministic ordering in §5.2. It validates the wire
// shape only: no envelope model, detector, raster, OCR, persistence, resolution
// state machine, UI, or platform logic lives here.
//
// Adoption contract for T057/T058:
//
// ```dart
// import 'package:feldexa_recognition/src/suggestion_schema.dart';
//
// final List<SuggestionSchemaViolation> violations =
//     SuggestionSchema.validateRun(envelopes, pages: displaySizes);
// if (violations.isNotEmpty) {
//   // Reject the input; do not persist it.
// }
// ```
//
// T057's `page_analysis.dart` serializer/deserializer and T058's persistence
// reader MUST call [SuggestionSchema.validateRun] (or
// [SuggestionSchema.validateEnvelope] for one page) and adopt this file as the
// single validation source. The package has no barrel; import
// `package:feldexa_recognition/src/suggestion_schema.dart` directly. Do not
// duplicate these rules in `FieldSuggestionSet`.
//
// Cue ordering is a rule: `evidence.cues` must be sorted ascending by UTF-16
// code unit (`String.compareTo` on every adjacent pair < 0), in addition to
// uniqueness and §3.1 vocabulary membership. For the ASCII §3.1 tokens this is
// ASCII lexicographic order.
//
// One deliberate non-rule:
//   * `uncertaintyReason` is required only when `pageUncertain` is true and
//     must then be one of the four values. §1 does not require it to be null
//     when `pageUncertain` is false, so a valid reason is accepted there.
//
// The §6 conflict predicate is decidable from the wire shape: two rects
// conflict when IoU >= 0.5 or when one rect contains the other's center and
// the Euclidean center distance is <= 4 pt (both inclusive). Each coordinate
// is rounded to 1/8 pt before comparison so float noise cannot change a
// threshold. The >12 % printed-ink rule (§2.1) and OCR quality remain
// detector-owned and cannot be decided from the wire shape.
// Violation messages contain only structural paths and stable codes, never
// labels, OCR text, file names, URIs, or document content.

library;

import 'dart:convert';

/// Stable, content-free violation categories.
abstract final class SuggestionSchemaCodes {
  /// A required key is absent.
  static const String missing = 'missing';

  /// A key outside the closed contract set is present.
  static const String unexpected = 'unexpected';

  /// A value has the wrong JSON type.
  static const String type = 'type';

  /// A value is not in the closed vocabulary or is otherwise invalid.
  static const String value = 'value';

  /// A value is not in the required canonical format.
  static const String format = 'format';

  /// A numeric value is outside its allowed range.
  static const String range = 'range';

  /// A collection has the wrong cardinality.
  static const String count = 'count';

  /// A collection contains a duplicate.
  static const String duplicate = 'duplicate';

  /// A value does not match the required canonical order.
  static const String order = 'order';

  /// A conflict references an absent suggestion.
  static const String reference = 'reference';

  /// A conflict is not recorded by both candidates.
  static const String symmetry = 'symmetry';

  /// A declared conflicting pair does not qualify under the §6 rule.
  static const String overlap = 'overlap';

  /// A persisted result carries forbidden state or fields.
  static const String forbidden = 'forbidden';

  /// Page or run identity does not match the expected context.
  static const String mismatch = 'mismatch';

  /// A run does not cover every page exactly once.
  static const String cardinality = 'cardinality';
}

/// One content-free schema finding.
///
/// [path] is a structural JSON path such as `envelope.suggestions[0].id`.
/// [code] is one of [SuggestionSchemaCodes]. Neither field ever contains a
/// label, OCR text, a file name, a URI, or other document content.
final class SuggestionSchemaViolation
    implements Comparable<SuggestionSchemaViolation> {
  /// Creates a finding.
  const SuggestionSchemaViolation(this.path, this.code);

  /// Structural JSON path of the rejected value.
  final String path;

  /// Stable finding category.
  final String code;

  @override
  int compareTo(SuggestionSchemaViolation other) {
    final int byPath = path.compareTo(other.path);
    if (byPath != 0) {
      return byPath;
    }
    return code.compareTo(other.code);
  }

  @override
  bool operator ==(Object other) {
    return other is SuggestionSchemaViolation &&
        other.path == path &&
        other.code == code;
  }

  @override
  int get hashCode => Object.hash(path, code);

  @override
  String toString() => '$path: $code';
}

/// A synthetic or production page display size in points.
///
/// The width and height must be finite and positive; invalid sizes throw
/// [ArgumentError] rather than producing meaningless bounds checks.
final class PageDisplaySize {
  /// Creates a display size in points.
  ///
  /// Throws [ArgumentError] for a non-finite or non-positive dimension.
  PageDisplaySize(this.width, this.height) {
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      throw ArgumentError(
        'PageDisplaySize requires finite positive dimensions.',
      );
    }
  }

  /// Display-space width in points.
  final double width;

  /// Display-space height in points.
  final double height;
}

/// Pure-Dart validation and canonicalization for the recognition wire contract.
///
/// The public methods never mutate their input. Findings are sorted by
/// `(path, code)` so callers can assert deterministically.
abstract final class SuggestionSchema {
  /// The only accepted `schemaVersion`.
  static const int version = 1;

  /// Closed §1 envelope key set.
  static const Set<String> envelopeKeys = <String>{
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

  /// Closed §2 suggestion key set.
  static const Set<String> suggestionKeys = <String>{
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

  /// Closed §2 evidence key set.
  static const Set<String> evidenceKeys = <String>{
    'cues',
    'cueAgreement',
    'skewDegrees',
    'contrast',
    'ocrUsed',
  };

  /// Closed §4 failure key set.
  static const Set<String> failureKeys = <String>{
    'category',
    'messageKey',
    'recoverable',
    'suggestionCount',
  };

  /// Closed §1 timings key set.
  static const Set<String> timingKeys = <String>{
    'rasterMs',
    'ocrMs',
    'detectMs',
  };

  /// Allowed page rotations.
  static const Set<int> rotations = <int>{0, 90, 180, 270};

  /// Allowed envelope statuses.
  static const Set<String> statuses = <String>{'complete', 'failed'};

  /// Allowed page-level uncertainty reasons.
  static const Set<String> uncertaintyReasons = <String>{
    'skew',
    'orientation',
    'low_contrast',
    'structure',
  };

  /// Allowed suggestion types in the §5.2 type-ordinal order.
  static const List<String> proposedTypes = <String>[
    'text',
    'number',
    'date',
    'checkbox',
    'multiline',
    'signature',
  ];

  /// Allowed suggestion resolutions.
  static const Set<String> resolutions = <String>{
    'unresolved',
    'confirmed',
    'rejected',
  };

  /// Allowed evidence contrast values.
  static const Set<String> contrasts = <String>{'normal', 'low'};

  /// Allowed evidence classes.
  static const Set<String> evidenceClasses = <String>{
    'simulated',
    'emulator',
    'device',
  };

  /// Allowed §4 failure categories.
  static const Set<String> failureCategories = <String>{
    'rasterization',
    'ocr',
    'unsupported_structure',
    'internal',
  };

  /// Fixed §3.1 cue tokens. `keyword_<key>` is handled by [isKnownCue].
  static const Set<String> fixedCues = <String>{
    'underline',
    'box',
    'grid_cell',
    'whitespace',
    'alignment_left',
    'label_below',
    'ocr_alignment_right',
    'ocr_alignment_below',
    'small_square',
    'table_cell',
    'signature_area',
    'numeric_context',
    'date_context',
  };

  /// Keyword lexicon v1 for `keyword_<key>` cues.
  static const List<String> keywordLexiconV1 = <String>[
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

  /// Cue families that satisfy §2.1's "at least one geometric cue" rule.
  static const Set<String> geometricCues = <String>{
    'underline',
    'box',
    'grid_cell',
    'whitespace',
    'alignment_left',
    'small_square',
    'table_cell',
    'signature_area',
  };

  /// Cues that cannot appear when `ocrUsed` is false.
  static const Set<String> ocrDependentCues = <String>{
    'label_below',
    'ocr_alignment_right',
    'ocr_alignment_below',
    'signature_area',
    'numeric_context',
    'date_context',
  };

  static const double _epsilon = 1e-6;
  static const String _keywordPrefix = 'keyword_';

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  static final RegExp _suggestionIdPattern = RegExp(r'^s_p(\d+)_(\d{4,})$');
  static final RegExp _failureMessageKeyPattern = RegExp(r'^REC-\d{3}$');

  /// Whether [cue] is a member of the §3.1 closed vocabulary.
  ///
  /// A keyword cue is accepted only when its key is in
  /// [keywordLexiconV1]. The data-model aliases `line` and `grid` and the
  /// ambiguous `ocr_alignment` form are not wire tokens.
  static bool isKnownCue(String cue) {
    if (cue.startsWith(_keywordPrefix)) {
      return keywordLexiconV1.contains(cue.substring(_keywordPrefix.length));
    }
    return fixedCues.contains(cue);
  }

  /// Whether [cue] is geometric for the §2.1 forbidden-output rule.
  static bool isGeometricCue(String cue) => geometricCues.contains(cue);

  /// Whether [cue] requires OCR and is forbidden when `ocrUsed` is false.
  static bool cueRequiresOcr(String cue) {
    return cue.startsWith(_keywordPrefix) || ocrDependentCues.contains(cue);
  }

  /// Validates every page envelope of one analysis run.
  ///
  /// [pages] supplies the expected display size per page in `pageIndex` order.
  /// The run must contain exactly one envelope per page, all sharing one
  /// `analysisRunId`. When [persisted] is true (the default), every suggestion
  /// must carry only `unresolved`; pass false only for audit/read models that
  /// intentionally expose a user's confirmed or rejected resolution.
  ///
  /// Returns content-free findings sorted by `(path, code)`.
  static List<SuggestionSchemaViolation> validateRun(
    Object? raw, {
    required List<PageDisplaySize> pages,
    bool persisted = true,
  }) {
    final List<SuggestionSchemaViolation> findings =
        <SuggestionSchemaViolation>[];
    if (raw is! List<Object?> || raw.isEmpty || pages.isEmpty) {
      return _finish(<SuggestionSchemaViolation>[
        const SuggestionSchemaViolation('run', SuggestionSchemaCodes.type),
      ]);
    }
    final List<Map<String, Object?>> envelopes = <Map<String, Object?>>[];
    for (int i = 0; i < raw.length; i++) {
      final Object? item = raw[i];
      if (item is Map<String, Object?>) {
        envelopes.add(item);
      } else {
        findings.add(
          SuggestionSchemaViolation('run[$i]', SuggestionSchemaCodes.type),
        );
      }
    }
    final Set<Object?> runIds = envelopes
        .map((Map<String, Object?> envelope) => envelope['analysisRunId'])
        .toSet();
    if (runIds.length > 1) {
      findings.add(
        const SuggestionSchemaViolation(
          'run.analysisRunId',
          SuggestionSchemaCodes.mismatch,
        ),
      );
    }
    final Set<int> seenPages = <int>{};
    for (final Map<String, Object?> envelope in envelopes) {
      final Object? rawPageIndex = envelope['pageIndex'];
      final int? pageIndex = rawPageIndex is int ? rawPageIndex : null;
      if (pageIndex != null && !seenPages.add(pageIndex)) {
        findings.add(
          const SuggestionSchemaViolation(
            'run.pageIndex',
            SuggestionSchemaCodes.duplicate,
          ),
        );
      }
      final PageDisplaySize display =
          pageIndex != null && pageIndex >= 0 && pageIndex < pages.length
          ? pages[pageIndex]
          : pages.first;
      findings.addAll(
        validateEnvelope(
          envelope,
          displaySize: display,
          pageCount: pages.length,
          persisted: persisted,
        ),
      );
    }
    bool coversEveryPage = envelopes.length == pages.length;
    for (int i = 0; i < pages.length; i++) {
      if (!seenPages.contains(i)) {
        coversEveryPage = false;
      }
    }
    if (!coversEveryPage) {
      findings.add(
        const SuggestionSchemaViolation(
          'run.pageIndex',
          SuggestionSchemaCodes.cardinality,
        ),
      );
    }
    return _finish(findings);
  }

  /// Validates one page envelope against §1.
  ///
  /// [displaySize] is the page's display size; `pageSizePt` must match it.
  /// [pageCount] bounds `pageIndex`. When [persisted] is true (the default),
  /// suggestions must be `unresolved`.
  ///
  /// Returns content-free findings sorted by `(path, code)`.
  static List<SuggestionSchemaViolation> validateEnvelope(
    Object? raw, {
    required PageDisplaySize displaySize,
    int pageCount = 1,
    bool persisted = true,
  }) {
    if (pageCount < 1) {
      throw ArgumentError.value(pageCount, 'pageCount', 'must be at least 1');
    }
    final List<SuggestionSchemaViolation> findings =
        <SuggestionSchemaViolation>[];
    if (raw is! Map<String, Object?>) {
      return _finish(<SuggestionSchemaViolation>[
        const SuggestionSchemaViolation('envelope', SuggestionSchemaCodes.type),
      ]);
    }
    _checkExactKeys(raw, envelopeKeys, 'envelope', findings);

    if (raw['schemaVersion'] != version) {
      findings.add(
        const SuggestionSchemaViolation(
          'envelope.schemaVersion',
          SuggestionSchemaCodes.value,
        ),
      );
    }

    final Object? analysisRunId = raw['analysisRunId'];
    if (analysisRunId is! String || !_uuidPattern.hasMatch(analysisRunId)) {
      findings.add(
        const SuggestionSchemaViolation(
          'envelope.analysisRunId',
          SuggestionSchemaCodes.format,
        ),
      );
    }

    final Object? rawPageIndex = raw['pageIndex'];
    final int? pageIndex = rawPageIndex is int ? rawPageIndex : null;
    if (pageIndex == null || pageIndex < 0 || pageIndex >= pageCount) {
      findings.add(
        const SuggestionSchemaViolation(
          'envelope.pageIndex',
          SuggestionSchemaCodes.range,
        ),
      );
    }

    final Object? rawPageSize = raw['pageSizePt'];
    if (rawPageSize is! Map<String, Object?>) {
      findings.add(
        const SuggestionSchemaViolation(
          'envelope.pageSizePt',
          SuggestionSchemaCodes.type,
        ),
      );
    } else {
      _checkExactKeys(
        rawPageSize,
        const <String>{'width', 'height'},
        'envelope.pageSizePt',
        findings,
      );
      final double? width = _finite(rawPageSize['width']);
      final double? height = _finite(rawPageSize['height']);
      if (width == null || (width - displaySize.width).abs() > _epsilon) {
        findings.add(
          const SuggestionSchemaViolation(
            'envelope.pageSizePt.width',
            SuggestionSchemaCodes.value,
          ),
        );
      }
      if (height == null || (height - displaySize.height).abs() > _epsilon) {
        findings.add(
          const SuggestionSchemaViolation(
            'envelope.pageSizePt.height',
            SuggestionSchemaCodes.value,
          ),
        );
      }
    }

    final Object? rotation = raw['rotation'];
    if (rotation is! int || !rotations.contains(rotation)) {
      findings.add(
        const SuggestionSchemaViolation(
          'envelope.rotation',
          SuggestionSchemaCodes.value,
        ),
      );
    }

    final Object? status = raw['status'];
    if (status is! String || !statuses.contains(status)) {
      findings.add(
        const SuggestionSchemaViolation(
          'envelope.status',
          SuggestionSchemaCodes.value,
        ),
      );
    }

    final Object? pageUncertain = raw['pageUncertain'];
    final Object? uncertaintyReason = raw['uncertaintyReason'];
    final bool validReason =
        uncertaintyReason == null ||
        (uncertaintyReason is String &&
            uncertaintyReasons.contains(uncertaintyReason));
    if (pageUncertain is! bool) {
      findings.add(
        const SuggestionSchemaViolation(
          'envelope.pageUncertain',
          SuggestionSchemaCodes.type,
        ),
      );
    }
    if (!validReason) {
      findings.add(
        const SuggestionSchemaViolation(
          'envelope.uncertaintyReason',
          SuggestionSchemaCodes.value,
        ),
      );
    } else if (pageUncertain == true && uncertaintyReason == null) {
      findings.add(
        const SuggestionSchemaViolation(
          'envelope.uncertaintyReason',
          SuggestionSchemaCodes.missing,
        ),
      );
    }
    // §1 does not require uncertaintyReason to be null when pageUncertain is
    // false; a valid reason is accepted and retained for diagnostics.

    final Object? failure = raw['failure'];
    if (status == 'failed') {
      if (failure == null) {
        findings.add(
          const SuggestionSchemaViolation(
            'envelope.failure',
            SuggestionSchemaCodes.missing,
          ),
        );
      } else {
        _validateFailure(failure, 'envelope.failure', findings);
      }
    } else if (failure != null) {
      findings.add(
        const SuggestionSchemaViolation(
          'envelope.failure',
          SuggestionSchemaCodes.value,
        ),
      );
    }

    final Object? rawSuggestions = raw['suggestions'];
    if (rawSuggestions is! List<Object?>) {
      findings.add(
        const SuggestionSchemaViolation(
          'envelope.suggestions',
          SuggestionSchemaCodes.type,
        ),
      );
    } else {
      if (status == 'failed' && rawSuggestions.isNotEmpty) {
        findings.add(
          const SuggestionSchemaViolation(
            'envelope.suggestions',
            SuggestionSchemaCodes.forbidden,
          ),
        );
      }
      final List<Map<String, Object?>> suggestions = <Map<String, Object?>>[];
      for (int i = 0; i < rawSuggestions.length; i++) {
        final Object? item = rawSuggestions[i];
        if (item is Map<String, Object?>) {
          suggestions.add(item);
        } else {
          findings.add(
            SuggestionSchemaViolation(
              'envelope.suggestions[$i]',
              SuggestionSchemaCodes.type,
            ),
          );
        }
      }
      final List<Map<String, Object?>> sorted = sortedSuggestions(suggestions);
      for (int i = 0; i < suggestions.length; i++) {
        final Map<String, Object?> suggestion = suggestions[i];
        final int sortedIndex = sorted.indexOf(suggestion);
        final int expectedOrdinal = sortedIndex < 0 ? i + 1 : sortedIndex + 1;
        if (sortedIndex != i) {
          findings.add(
            SuggestionSchemaViolation(
              'envelope.suggestions[$i]',
              SuggestionSchemaCodes.order,
            ),
          );
        }
        _validateSuggestion(
          suggestion,
          path: 'envelope.suggestions[$i]',
          envelopePageIndex: pageIndex,
          displaySize: displaySize,
          siblings: suggestions,
          expectedOrdinal: expectedOrdinal,
          persisted: persisted,
          findings: findings,
        );
      }
      _validateConflictCompleteness(suggestions, findings: findings);
    }

    final Object? rawTimings = raw['timings'];
    if (rawTimings is! Map<String, Object?>) {
      findings.add(
        const SuggestionSchemaViolation(
          'envelope.timings',
          SuggestionSchemaCodes.type,
        ),
      );
    } else {
      _checkExactKeys(rawTimings, timingKeys, 'envelope.timings', findings);
      for (final String key in timingKeys) {
        if (!rawTimings.containsKey(key)) {
          continue;
        }
        final Object? value = rawTimings[key];
        if (value is! int || value < 0) {
          findings.add(
            SuggestionSchemaViolation(
              'envelope.timings.$key',
              SuggestionSchemaCodes.range,
            ),
          );
        }
      }
    }

    final Object? evidenceClass = raw['evidenceClass'];
    if (evidenceClass is! String || !evidenceClasses.contains(evidenceClass)) {
      findings.add(
        const SuggestionSchemaViolation(
          'envelope.evidenceClass',
          SuggestionSchemaCodes.value,
        ),
      );
    }

    return _finish(findings);
  }

  /// Returns the deterministic §5.2 comparator result for two suggestions.
  ///
  /// The order is `pageIndex`, rounded `y`, rounded `x`, type ordinal (`text`,
  /// `number`, `date`, `checkbox`, `multiline`, `signature`), then `id`. Inside
  /// one page envelope the page keys are equal, so `y → x → type → id` decides.
  static int compareSuggestions(
    Map<String, Object?> a,
    Map<String, Object?> b,
  ) {
    final int byPage = _pageIndexOf(a).compareTo(_pageIndexOf(b));
    if (byPage != 0) {
      return byPage;
    }
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

  /// Returns a sorted copy of [suggestions] using [compareSuggestions].
  static List<Map<String, Object?>> sortedSuggestions(
    Iterable<Map<String, Object?>> suggestions,
  ) {
    final List<Map<String, Object?>> sorted = List<Map<String, Object?>>.of(
      suggestions,
    );
    sorted.sort(compareSuggestions);
    return List<Map<String, Object?>>.unmodifiable(sorted);
  }

  /// Deep-copies [envelope] without `timings` and `evidenceClass`.
  ///
  /// This is the input to canonical revision hashing and golden equality
  /// (§1; §5.5). Diagnostics cannot affect the projection.
  static Map<String, Object?> canonicalProjection(
    Map<String, Object?> envelope,
  ) {
    return <String, Object?>{
      for (final MapEntry<String, Object?> entry in envelope.entries)
        if (entry.key != 'timings' && entry.key != 'evidenceClass')
          entry.key: _deepCopy(entry.value),
    };
  }

  /// Encodes [value] as canonical JSON: sorted object keys, no insignificant
  /// whitespace, UTF-8-compatible scalars.
  ///
  /// Throws [ArgumentError] for a non-finite number or an unsupported value.
  /// The error never echoes document content.
  static String canonicalJson(Object? value) {
    return jsonEncode(_canonicalize(value, r'$'));
  }

  static void _validateSuggestion(
    Map<String, Object?> suggestion, {
    required String path,
    required int? envelopePageIndex,
    required PageDisplaySize displaySize,
    required List<Map<String, Object?>> siblings,
    required int expectedOrdinal,
    required bool persisted,
    required List<SuggestionSchemaViolation> findings,
  }) {
    _checkExactKeys(suggestion, suggestionKeys, path, findings);

    final Object? rawId = suggestion['id'];
    if (rawId is! String) {
      findings.add(
        SuggestionSchemaViolation('$path.id', SuggestionSchemaCodes.format),
      );
    } else {
      final RegExpMatch? match = _suggestionIdPattern.firstMatch(rawId);
      if (match == null) {
        findings.add(
          SuggestionSchemaViolation('$path.id', SuggestionSchemaCodes.format),
        );
      } else {
        final String pageToken = match.group(1)!;
        final String ordinalToken = match.group(2)!;
        if (envelopePageIndex == null ||
            int.tryParse(pageToken) != envelopePageIndex) {
          findings.add(
            SuggestionSchemaViolation(
              '$path.id',
              SuggestionSchemaCodes.mismatch,
            ),
          );
        }
        final int? pageTokenValue = int.tryParse(pageToken);
        if (pageTokenValue == null || pageToken != '$pageTokenValue') {
          findings.add(
            SuggestionSchemaViolation('$path.id', SuggestionSchemaCodes.format),
          );
        }
        final int? ordinal = int.tryParse(ordinalToken);
        if (ordinal == null || ordinal < 1) {
          findings.add(
            SuggestionSchemaViolation('$path.id', SuggestionSchemaCodes.range),
          );
        } else {
          if (ordinalToken != ordinal.toString().padLeft(4, '0')) {
            findings.add(
              SuggestionSchemaViolation(
                '$path.id',
                SuggestionSchemaCodes.format,
              ),
            );
          }
          if (ordinal != expectedOrdinal) {
            findings.add(
              SuggestionSchemaViolation(
                '$path.id',
                SuggestionSchemaCodes.order,
              ),
            );
          }
        }
      }
    }

    if (envelopePageIndex == null ||
        suggestion['pageIndex'] != envelopePageIndex) {
      findings.add(
        SuggestionSchemaViolation(
          '$path.pageIndex',
          SuggestionSchemaCodes.mismatch,
        ),
      );
    }

    final Object? rawRect = suggestion['rect'];
    final ({double x, double y, double width, double height})? rect =
        _rectValues(rawRect);
    if (rawRect is! Map<String, Object?>) {
      findings.add(
        SuggestionSchemaViolation('$path.rect', SuggestionSchemaCodes.type),
      );
    } else {
      _checkExactKeys(
        rawRect,
        const <String>{'x', 'y', 'width', 'height'},
        '$path.rect',
        findings,
      );
      if (rect == null) {
        findings.add(
          SuggestionSchemaViolation('$path.rect', SuggestionSchemaCodes.type),
        );
      } else {
        if (rect.width <= 0) {
          findings.add(
            SuggestionSchemaViolation(
              '$path.rect.width',
              SuggestionSchemaCodes.range,
            ),
          );
        }
        if (rect.height <= 0) {
          findings.add(
            SuggestionSchemaViolation(
              '$path.rect.height',
              SuggestionSchemaCodes.range,
            ),
          );
        }
        if (rect.x < -_epsilon ||
            rect.y < -_epsilon ||
            rect.x + rect.width > displaySize.width + _epsilon ||
            rect.y + rect.height > displaySize.height + _epsilon) {
          findings.add(
            SuggestionSchemaViolation(
              '$path.rect',
              SuggestionSchemaCodes.range,
            ),
          );
        }
        for (final String key in const <String>['x', 'y', 'width', 'height']) {
          final double? value = _finite(rawRect[key]);
          if (value != null && !_isEighth(value)) {
            findings.add(
              SuggestionSchemaViolation(
                '$path.rect.$key',
                SuggestionSchemaCodes.format,
              ),
            );
          }
        }
      }
    }

    final Object? proposedType = suggestion['proposedType'];
    if (proposedType is! String || !proposedTypes.contains(proposedType)) {
      findings.add(
        SuggestionSchemaViolation(
          '$path.proposedType',
          SuggestionSchemaCodes.value,
        ),
      );
    }

    final double? confidence = _finite(suggestion['confidence']);
    if (suggestion.containsKey('confidence')) {
      if (confidence == null || confidence < 0 || confidence > 1) {
        findings.add(
          SuggestionSchemaViolation(
            '$path.confidence',
            SuggestionSchemaCodes.range,
          ),
        );
      } else if (!_hasTwoDecimals(confidence)) {
        findings.add(
          SuggestionSchemaViolation(
            '$path.confidence',
            SuggestionSchemaCodes.format,
          ),
        );
      }
    }

    final double? uncertainty = _finite(suggestion['uncertainty']);
    if (suggestion.containsKey('uncertainty')) {
      if (uncertainty == null || uncertainty < 0 || uncertainty > 1) {
        findings.add(
          SuggestionSchemaViolation(
            '$path.uncertainty',
            SuggestionSchemaCodes.range,
          ),
        );
      } else {
        if (!_hasTwoDecimals(uncertainty)) {
          findings.add(
            SuggestionSchemaViolation(
              '$path.uncertainty',
              SuggestionSchemaCodes.format,
            ),
          );
        }
        if (confidence != null &&
            (uncertainty - _round2(1 - confidence)).abs() > _epsilon) {
          findings.add(
            SuggestionSchemaViolation(
              '$path.uncertainty',
              SuggestionSchemaCodes.value,
            ),
          );
        }
      }
    }

    final Object? labelText = suggestion['labelText'];
    if (labelText != null) {
      if (labelText is! String || labelText.isEmpty) {
        findings.add(
          SuggestionSchemaViolation(
            '$path.labelText',
            SuggestionSchemaCodes.type,
          ),
        );
      } else {
        if (labelText != labelText.trim()) {
          findings.add(
            SuggestionSchemaViolation(
              '$path.labelText',
              SuggestionSchemaCodes.format,
            ),
          );
        }
        if (labelText.runes.length > 200) {
          findings.add(
            SuggestionSchemaViolation(
              '$path.labelText',
              SuggestionSchemaCodes.range,
            ),
          );
        }
      }
    }

    final Object? rawEvidence = suggestion['evidence'];
    if (rawEvidence is! Map<String, Object?>) {
      findings.add(
        SuggestionSchemaViolation('$path.evidence', SuggestionSchemaCodes.type),
      );
    } else {
      _validateEvidence(
        rawEvidence,
        path: '$path.evidence',
        findings: findings,
      );
    }

    _validateConflicts(
      suggestion,
      path: path,
      siblings: siblings,
      findings: findings,
    );

    final Object? resolution = suggestion['resolution'];
    if (resolution is! String || !resolutions.contains(resolution)) {
      findings.add(
        SuggestionSchemaViolation(
          '$path.resolution',
          SuggestionSchemaCodes.value,
        ),
      );
    } else if (persisted && resolution != 'unresolved') {
      findings.add(
        SuggestionSchemaViolation(
          '$path.resolution',
          SuggestionSchemaCodes.forbidden,
        ),
      );
    }
  }

  static void _validateEvidence(
    Map<String, Object?> evidence, {
    required String path,
    required List<SuggestionSchemaViolation> findings,
  }) {
    _checkExactKeys(evidence, evidenceKeys, path, findings);

    final Object? rawCues = evidence['cues'];
    if (rawCues is! List<Object?>) {
      findings.add(
        SuggestionSchemaViolation('$path.cues', SuggestionSchemaCodes.type),
      );
    } else {
      final List<String> cues = <String>[];
      for (final Object? cue in rawCues) {
        if (cue is String) {
          cues.add(cue);
        } else {
          findings.add(
            SuggestionSchemaViolation('$path.cues', SuggestionSchemaCodes.type),
          );
        }
      }
      if (cues.isEmpty) {
        findings.add(
          SuggestionSchemaViolation('$path.cues', SuggestionSchemaCodes.count),
        );
      }
      if (cues.toSet().length != cues.length) {
        findings.add(
          SuggestionSchemaViolation(
            '$path.cues',
            SuggestionSchemaCodes.duplicate,
          ),
        );
      }
      // Ascending UTF-16 code-unit order: every adjacent pair must satisfy
      // `compareTo(next) < 0`. A duplicate pair is therefore also unsorted and
      // yields both findings. One `order` finding covers the whole list.
      for (int i = 0; i + 1 < cues.length; i++) {
        if (cues[i].compareTo(cues[i + 1]) >= 0) {
          findings.add(
            SuggestionSchemaViolation(
              '$path.cues',
              SuggestionSchemaCodes.order,
            ),
          );
          break;
        }
      }
      for (final String cue in cues) {
        if (!isKnownCue(cue)) {
          findings.add(
            SuggestionSchemaViolation(
              '$path.cues',
              SuggestionSchemaCodes.value,
            ),
          );
          break;
        }
      }
      if (!cues.any(isGeometricCue)) {
        findings.add(
          SuggestionSchemaViolation(
            '$path.cues',
            SuggestionSchemaCodes.forbidden,
          ),
        );
      }
      final Object? ocrUsed = evidence['ocrUsed'];
      if (ocrUsed == false && cues.any(cueRequiresOcr)) {
        findings.add(
          SuggestionSchemaViolation(
            '$path.cues',
            SuggestionSchemaCodes.forbidden,
          ),
        );
      }
    }

    final Object? cueAgreement = evidence['cueAgreement'];
    if (cueAgreement is! int || cueAgreement < 1) {
      findings.add(
        SuggestionSchemaViolation(
          '$path.cueAgreement',
          SuggestionSchemaCodes.range,
        ),
      );
    }

    final double? skewDegrees = _finite(evidence['skewDegrees']);
    if (skewDegrees == null || skewDegrees < -10 || skewDegrees > 10) {
      findings.add(
        SuggestionSchemaViolation(
          '$path.skewDegrees',
          SuggestionSchemaCodes.range,
        ),
      );
    }

    final Object? contrast = evidence['contrast'];
    if (contrast is! String || !contrasts.contains(contrast)) {
      findings.add(
        SuggestionSchemaViolation(
          '$path.contrast',
          SuggestionSchemaCodes.value,
        ),
      );
    }

    if (evidence['ocrUsed'] is! bool) {
      findings.add(
        SuggestionSchemaViolation('$path.ocrUsed', SuggestionSchemaCodes.type),
      );
    }
  }

  static void _validateConflicts(
    Map<String, Object?> suggestion, {
    required String path,
    required List<Map<String, Object?>> siblings,
    required List<SuggestionSchemaViolation> findings,
  }) {
    final Object? rawConflicts = suggestion['conflictsWith'];
    if (rawConflicts is! List<Object?>) {
      findings.add(
        SuggestionSchemaViolation(
          '$path.conflictsWith',
          SuggestionSchemaCodes.type,
        ),
      );
      return;
    }
    final List<String> conflicts = <String>[];
    for (final Object? item in rawConflicts) {
      if (item is String) {
        conflicts.add(item);
      } else {
        findings.add(
          SuggestionSchemaViolation(
            '$path.conflictsWith',
            SuggestionSchemaCodes.type,
          ),
        );
      }
    }
    if (conflicts.toSet().length != conflicts.length) {
      findings.add(
        SuggestionSchemaViolation(
          '$path.conflictsWith',
          SuggestionSchemaCodes.duplicate,
        ),
      );
    }
    final Object? ownId = suggestion['id'];
    if (ownId is String && conflicts.contains(ownId)) {
      findings.add(
        SuggestionSchemaViolation(
          '$path.conflictsWith',
          SuggestionSchemaCodes.forbidden,
        ),
      );
    }
    final Map<String, Map<String, Object?>> byId =
        <String, Map<String, Object?>>{};
    for (final Map<String, Object?> sibling in siblings) {
      final Object? id = sibling['id'];
      if (id is String) {
        byId[id] = sibling;
      }
    }
    for (final String otherId in conflicts) {
      final Map<String, Object?>? other = byId[otherId];
      if (other == null) {
        findings.add(
          SuggestionSchemaViolation(
            '$path.conflictsWith',
            SuggestionSchemaCodes.reference,
          ),
        );
        continue;
      }
      final Object? otherConflicts = other['conflictsWith'];
      if (otherConflicts is! List<Object?> || !otherConflicts.contains(ownId)) {
        findings.add(
          SuggestionSchemaViolation(
            '$path.conflictsWith',
            SuggestionSchemaCodes.symmetry,
          ),
        );
      }
      if (!_conflictQualifies(suggestion['rect'], other['rect'])) {
        findings.add(
          SuggestionSchemaViolation(
            '$path.conflictsWith',
            SuggestionSchemaCodes.overlap,
          ),
        );
      }
    }
  }

  /// Emits `symmetry` for every missing side of a §6-qualifying pair.
  ///
  /// Runs after individual suggestion validation, over structurally usable
  /// suggestions in envelope order: a string `id`, a parseable `rect`, and a
  /// `conflictsWith` array. For each unordered pair whose rects qualify under
  /// [_conflictQualifies], each side must list the other's id. A fully
  /// undeclared pair yields two findings, one per direction; a declared
  /// one-sided pair yields the missing reverse direction here in addition to
  /// the declared-symmetry finding from [_validateConflicts].
  static void _validateConflictCompleteness(
    List<Map<String, Object?>> suggestions, {
    required List<SuggestionSchemaViolation> findings,
  }) {
    final List<int> usable = <int>[];
    for (int index = 0; index < suggestions.length; index++) {
      final Object? id = suggestions[index]['id'];
      final ({double x, double y, double width, double height})? rect =
          _rectValues(suggestions[index]['rect']);
      final Object? conflicts = suggestions[index]['conflictsWith'];
      if (id is String &&
          rect != null &&
          rect.width > 0 &&
          rect.height > 0 &&
          conflicts is List<Object?>) {
        usable.add(index);
      }
    }
    for (int i = 0; i < usable.length; i++) {
      for (int j = i + 1; j < usable.length; j++) {
        final int aIndex = usable[i];
        final int bIndex = usable[j];
        final Map<String, Object?> a = suggestions[aIndex];
        final Map<String, Object?> b = suggestions[bIndex];
        if (!_conflictQualifies(a['rect'], b['rect'])) {
          continue;
        }
        final String aId = a['id']! as String;
        final String bId = b['id']! as String;
        final List<Object?> aConflicts = a['conflictsWith']! as List<Object?>;
        final List<Object?> bConflicts = b['conflictsWith']! as List<Object?>;
        if (!aConflicts.contains(bId)) {
          findings.add(
            SuggestionSchemaViolation(
              'envelope.suggestions[$aIndex].conflictsWith',
              SuggestionSchemaCodes.symmetry,
            ),
          );
        }
        if (!bConflicts.contains(aId)) {
          findings.add(
            SuggestionSchemaViolation(
              'envelope.suggestions[$bIndex].conflictsWith',
              SuggestionSchemaCodes.symmetry,
            ),
          );
        }
      }
    }
  }

  static void _validateFailure(
    Object? raw,
    String path,
    List<SuggestionSchemaViolation> findings,
  ) {
    if (raw is! Map<String, Object?>) {
      findings.add(SuggestionSchemaViolation(path, SuggestionSchemaCodes.type));
      return;
    }
    _checkExactKeys(raw, failureKeys, path, findings);

    final Object? category = raw['category'];
    if (category is! String || !failureCategories.contains(category)) {
      findings.add(
        SuggestionSchemaViolation(
          '$path.category',
          SuggestionSchemaCodes.value,
        ),
      );
    }
    final Object? messageKey = raw['messageKey'];
    if (raw.containsKey('messageKey') &&
        (messageKey is! String ||
            !_failureMessageKeyPattern.hasMatch(messageKey))) {
      findings.add(
        SuggestionSchemaViolation(
          '$path.messageKey',
          SuggestionSchemaCodes.format,
        ),
      );
    }
    if (raw['recoverable'] is! bool) {
      findings.add(
        SuggestionSchemaViolation(
          '$path.recoverable',
          SuggestionSchemaCodes.type,
        ),
      );
    }
    final Object? suggestionCount = raw['suggestionCount'];
    if (suggestionCount is! int || suggestionCount < 0) {
      findings.add(
        SuggestionSchemaViolation(
          '$path.suggestionCount',
          SuggestionSchemaCodes.range,
        ),
      );
    }
  }

  static void _checkExactKeys(
    Map<String, Object?> map,
    Set<String> keys,
    String path,
    List<SuggestionSchemaViolation> findings,
  ) {
    for (final String key in keys) {
      if (!map.containsKey(key)) {
        findings.add(
          SuggestionSchemaViolation(
            '$path.$key',
            SuggestionSchemaCodes.missing,
          ),
        );
      }
    }
    for (final String key in map.keys) {
      if (!keys.contains(key)) {
        findings.add(
          SuggestionSchemaViolation(
            '$path.$key',
            SuggestionSchemaCodes.unexpected,
          ),
        );
      }
    }
  }

  static List<SuggestionSchemaViolation> _finish(
    List<SuggestionSchemaViolation> findings,
  ) {
    findings.sort();
    return List<SuggestionSchemaViolation>.unmodifiable(findings);
  }

  static double? _finite(Object? value) {
    if (value is num && value.isFinite) {
      return value.toDouble();
    }
    return null;
  }

  static bool _isEighth(double value) {
    final double scaled = value * 8;
    return (scaled - scaled.roundToDouble()).abs() <= _epsilon;
  }

  static bool _hasTwoDecimals(double value) {
    final double scaled = value * 100;
    return (scaled - scaled.roundToDouble()).abs() <= _epsilon;
  }

  static double _round2(double value) => (value * 100).roundToDouble() / 100;

  static double _roundToEighth(double value) => (value * 8).roundToDouble() / 8;

  static int _pageIndexOf(Map<String, Object?> suggestion) {
    final Object? pageIndex = suggestion['pageIndex'];
    return pageIndex is int ? pageIndex : 0x7fffffff;
  }

  static int _typeOrdinal(Object? type) {
    final int index = type is String ? proposedTypes.indexOf(type) : -1;
    return index < 0 ? proposedTypes.length : index;
  }

  static String _idOf(Map<String, Object?> suggestion) {
    final Object? id = suggestion['id'];
    return id is String ? id : '';
  }

  static ({double x, double y, double width, double height})? _rectValues(
    Object? raw,
  ) {
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

  /// Whether two rects qualify as a §6 conflict.
  ///
  /// Each coordinate is rounded to 1/8 pt first. The pair qualifies when
  /// `IoU >= 0.5` (inclusive) or when one rect contains the other's center
  /// (boundary inclusive) and the Euclidean center distance is `<= 4 pt`
  /// (inclusive). Threshold comparisons use [_epsilon]; invalid rects do not
  /// qualify.
  static bool _conflictQualifies(Object? rawA, Object? rawB) {
    final ({double x, double y, double width, double height})? a = _rectValues(
      rawA,
    );
    final ({double x, double y, double width, double height})? b = _rectValues(
      rawB,
    );
    if (a == null || b == null) {
      return false;
    }
    final ({double x, double y, double width, double height}) roundedA =
        _roundedRect(a);
    final ({double x, double y, double width, double height}) roundedB =
        _roundedRect(b);
    if (_iou(roundedA, roundedB) >= 0.5 - _epsilon) {
      return true;
    }
    final double aCenterX = roundedA.x + roundedA.width / 2;
    final double aCenterY = roundedA.y + roundedA.height / 2;
    final double bCenterX = roundedB.x + roundedB.width / 2;
    final double bCenterY = roundedB.y + roundedB.height / 2;
    final double dx = aCenterX - bCenterX;
    final double dy = aCenterY - bCenterY;
    final double distanceLimit = 4 + _epsilon;
    if (dx * dx + dy * dy > distanceLimit * distanceLimit) {
      return false;
    }
    final bool aCenterInB =
        aCenterX >= roundedB.x - _epsilon &&
        aCenterX <= roundedB.x + roundedB.width + _epsilon &&
        aCenterY >= roundedB.y - _epsilon &&
        aCenterY <= roundedB.y + roundedB.height + _epsilon;
    final bool bCenterInA =
        bCenterX >= roundedA.x - _epsilon &&
        bCenterX <= roundedA.x + roundedA.width + _epsilon &&
        bCenterY >= roundedA.y - _epsilon &&
        bCenterY <= roundedA.y + roundedA.height + _epsilon;
    return aCenterInB || bCenterInA;
  }

  static ({double x, double y, double width, double height}) _roundedRect(
    ({double x, double y, double width, double height}) rect,
  ) {
    return (
      x: _roundToEighth(rect.x),
      y: _roundToEighth(rect.y),
      width: _roundToEighth(rect.width),
      height: _roundToEighth(rect.height),
    );
  }

  static double _iou(
    ({double x, double y, double width, double height}) a,
    ({double x, double y, double width, double height}) b,
  ) {
    final double left = a.x > b.x ? a.x : b.x;
    final double top = a.y > b.y ? a.y : b.y;
    final double right = a.x + a.width < b.x + b.width
        ? a.x + a.width
        : b.x + b.width;
    final double bottom = a.y + a.height < b.y + b.height
        ? a.y + a.height
        : b.y + b.height;
    final double intersectionWidth = right - left;
    final double intersectionHeight = bottom - top;
    if (intersectionWidth <= 0 || intersectionHeight <= 0) {
      return 0;
    }
    final double intersection = intersectionWidth * intersectionHeight;
    final double union = a.width * a.height + b.width * b.height - intersection;
    return union <= 0 ? 0 : intersection / union;
  }

  static Object? _canonicalize(Object? value, String path) {
    if (value == null || value is bool || value is String || value is int) {
      return value;
    }
    if (value is double) {
      if (!value.isFinite) {
        throw ArgumentError('Non-finite number at $path');
      }
      return value;
    }
    if (value is Map<String, Object?>) {
      final List<String> keys = value.keys.toList()..sort();
      return <String, Object?>{
        for (final String key in keys) key: _canonicalize(value[key], path),
      };
    }
    if (value is List<Object?>) {
      return <Object?>[
        for (int i = 0; i < value.length; i++)
          _canonicalize(value[i], '$path[$i]'),
      ];
    }
    throw ArgumentError('Unsupported canonical JSON value at $path');
  }

  static Object? _deepCopy(Object? value) {
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
}
