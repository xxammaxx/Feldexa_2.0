// T053 label proximity and keyword-driven type inference.
//
// Normative sources:
//  * specs/001-scanned-form-workflow/contracts/recognition-output.md
//    §2 (suggestion fields), §2.1 (forbidden outputs), §3.1 (cues and keyword
//    lexicon v1), §3.2 (type-inference precedence), and §3.5 (page-level
//    uncertainty is not owned here);
//  * specs/001-scanned-form-workflow/spec.md FR-012;
//  * specs/001-scanned-form-workflow/data-model.md §3.4 (`FieldSuggestion`).
//
// Scope. This library derives, for one existing `GeometryCandidate`, a
// proposed type, the chosen label text, and the cue tokens that label evidence
// adds. It never creates a suggestion, never assigns ids, confidence,
// uncertainty, conflicts, resolution, or envelope fields, and contains no
// persistence, UI, or OCR-client code. Confidence is T054, conflicts T055, and
// the page envelope T057. The caller remains responsible for merging
// `TypeInferenceResult.addedCues` with the candidate's geometric cues; this
// library never mutates or drops the candidate's cue list. A candidate still
// carries the geometric evidence that made it a candidate.
//
// Label proximity. Only *credible* label observations participate:
//  * text must be non-empty after trimming;
//  * `ocrConfidence` must be at least 0.5; and
//  * the Euclidean gap between the label rectangle and the candidate rectangle
//    must be at most 24 pt. Rectangles that overlap or touch have gap 0.
//
// The nearest credible label is selected by a total order:
//  1. gap distance (ascending; compared as squared distance, which is
//     monotonic for non-negative gaps),
//  2. label rect y (ascending),
//  3. label rect x (ascending),
//  4. trimmed original label text (`String.compareTo`, UTF-16 code units),
//  5. label rect width (ascending),
//  6. label rect height (ascending),
//  7. OCR confidence (descending).
//
// Keys 5-7 only make the order total when two observations differ in size or
// confidence while sharing distance, position, and text. Input order is never
// a tie-breaker, so replaying the same observations in a different list order
// yields the same selection.
//
// Alignment cues emitted for the selected label:
//  * `ocr_alignment_right` when the candidate is to the right of the label
//    line: the label's right edge is at or before the candidate's left edge
//    and the two rectangles overlap vertically;
//  * `ocr_alignment_below` when the candidate is below the label line: the
//    label's bottom edge is at or before the candidate's top edge and the two
//    rectangles overlap horizontally;
//  * `label_below` when the label is directly below the candidate: the label's
//    top edge is at or below the candidate's bottom edge and the horizontal
//    overlap is at least half of the narrower rectangle (the documented
//    direct-below case). This is the signature-line orientation and is
//    independent of the two OCR-line cues above.
//
// Keyword matching. The §3.1 lexicon v1 is read from
// `SuggestionSchema.keywordLexiconV1` (single source of truth). For matching,
// label text is trimmed, lowercased without locale rules, internal whitespace
// is collapsed to one space, and `ä→ae`, `ö→oe`, `ü→ue`, `ß→ss` are folded
// (T263: `ẞ` folds with `ß` through the lowercase step, so it becomes `ss`).
// Decomposed spellings are folded too: a base letter `a`, `o`, or `u`
// immediately followed by U+0308 COMBINING DIAERESIS folds to the same digraph
// as its precomposed form, so an NFD label such as `Gescha\u0308ftszeichen`
// matches `geschäftszeichen`. Partial spellings are never repaired: a label
// with missing umlaut dots (`Geschaftszeichen`) or the plausible OCR confusion
// `StraBe` keeps its own text and simply does not match the umlaut lexeme.
// The raw label text is never rewritten; folding exists only for matching and
// the returned display text stays verbatim.
// Matching is a left-to-right longest non-overlapping lexeme match at word
// boundaries (ASCII letters/digits are word characters after folding). A
// label containing `Geburtsdatum` therefore matches only `geburtsdatum`, not
// `datum`; `Vorname` matches `vorname`, not `name`. When two lexicon spellings
// fold to the same text (`straße`/`strasse`), the spelling that appears
// literally in the label is preferred; otherwise lexicon order breaks the
// tie. The cue is `keyword_<key>` for every matched lexeme, and the original
// trimmed label text is preserved for display.
//
// Type-inference precedence, exactly §3.2:
//  1. explicit candidate cue `small_square` → `checkbox`; otherwise
//     `signature_area` → `signature`;
//  2. label keyword class:
//     * date: `geburtsdatum`, `datum`, `jahr` → `date`;
//     * numeric-formatting text: `plz`, `telefon` → `text` (leading
//       zeros/formatting); `postleitzahl` and `telefax` are neutral because
//       §3.2 names only those two keywords for this exception;
//     * date-guarded text: `monat`, `zeitraum`, `von`, `bis` → `text`
//       (the "never force a fake date" rule);
//     * signature: `unterschrift`, `datum/unterschrift` → `signature`;
//     * neutral: all remaining lexicon entries do not force a type;
//  3. geometry: height ≥ 2.2 × single-line median and width ≥ 80 pt →
//     `multiline`; aspect ratio 0.75-1.33 and height ≤ 20 pt → `checkbox`;
//     otherwise single-line (no type yet);
//  4. a credible adjacent label containing the printed date mask
//     `TT.MM.JJJJ` (case-insensitive) → `date`;
//  5. default → `text`.
//
// Label keywords are resolved in the order date (suppressed by a matched
// date-guard keyword), number, numeric-formatting text, date-guarded text,
// signature. A date guard therefore wins over a second date word while still
// emitting its `keyword_<key>` cue. Neutral keywords never override geometry.
// The printed date mask is emitted as `date_context`; number and
// numeric-formatting keywords add `numeric_context` because §3.1 defines that
// cue for an adjacent label implying digits. No other cue is invented.
//
// Invalid inputs raise content-free `ArgumentError`s: they never echo label
// text or other document content. The module has no I/O, randomness,
// wall-clock, or locale-dependent collation.
library;

import 'dart:math' as math;

import 'geometry_detector.dart';
import 'suggestion_schema.dart';

/// Maximum Euclidean gap in points between a credible label and its candidate.
///
/// This radius is the proximity rule for the *non-structural* cases: a label
/// above or below a candidate whose rectangles are still close. It is not the
/// rule for a label printed on the candidate's own row (the common left-label
/// layout), because there the horizontal gap between the label column and the
/// field column grows with the label's own length and is bounded by the layout,
/// not by a fixed distance. See [_sharesRow].
const double _maxLabelDistancePt = 24;

/// Squared form of [_maxLabelDistancePt] for exact, monotonic comparisons.
const double _maxLabelDistanceSquared =
    _maxLabelDistancePt * _maxLabelDistancePt;

/// Minimum OCR confidence for a label observation to be credible.
const double _minLabelConfidence = 0.5;

/// Single-line height factor from `recognition-output.md` §3.2.
const double _multilineHeightFactor = 2.2;

/// Minimum width in points for the multiline geometry rule.
const double _multilineMinWidthPt = 80;

/// Inclusive aspect-ratio bounds for the checkbox geometry rule.
const double _checkboxMinAspect = 0.75;
const double _checkboxMaxAspect = 1.33;

/// Maximum height in points for the checkbox geometry rule.
const double _checkboxMaxHeightPt = 20;

/// Maximum displayed label length in Unicode code points (§2).
const int _maxLabelTextRunes = 200;

/// Comparison epsilon for inclusive contract boundaries.
const double _epsilon = 1e-6;

/// U+0308 COMBINING DIAERESIS, the NFD part of the German umlauts.
const int _combiningDiaeresis = 0x0308;

/// The same mark as a string, for composition.
const String _combiningDiaeresisChar = '\u0308';

const String _keywordPrefix = 'keyword_';
const String _smallSquareCue = 'small_square';
const String _signatureAreaCue = 'signature_area';
const String _ocrAlignmentRightCue = 'ocr_alignment_right';
const String _ocrAlignmentBelowCue = 'ocr_alignment_below';
const String _labelBelowCue = 'label_below';
const String _numericContextCue = 'numeric_context';
const String _dateContextCue = 'date_context';

/// The §3.2 type class of one keyword lexicon entry.
enum _KeywordClass {
  /// Forces `date` at the label-keyword step.
  date,

  /// Forces `number` at the label-keyword step.
  number,

  /// Forces `text` because the field keeps leading zeros or formatting.
  textNumeric,

  /// Forces `text` because the label is date-guarded and must not become date.
  textDateGuard,

  /// Forces `signature` at the label-keyword step.
  signature,

  /// Supplies evidence only; geometry or the default decides the type.
  neutral,
}

/// The documented §3.2 classification of all 36 lexicon entries.
const Map<String, _KeywordClass> _keywordClasses = <String, _KeywordClass>{
  // Date keywords.
  'geburtsdatum': _KeywordClass.date,
  'datum': _KeywordClass.date,
  'jahr': _KeywordClass.date,
  // Explicit numeric keywords.
  'betrag': _KeywordClass.number,
  'summe': _KeywordClass.number,
  'iban': _KeywordClass.number,
  'steuernummer': _KeywordClass.number,
  // §3.2 names only plz and telefon as numeric-looking text fields.
  'plz': _KeywordClass.textNumeric,
  'telefon': _KeywordClass.textNumeric,
  // The §3.2 date-guarded labels must never become a fake date.
  'monat': _KeywordClass.textDateGuard,
  'zeitraum': _KeywordClass.textDateGuard,
  'von': _KeywordClass.textDateGuard,
  'bis': _KeywordClass.textDateGuard,
  // Signature keywords.
  'unterschrift': _KeywordClass.signature,
  'datum/unterschrift': _KeywordClass.signature,
  // Neutral identity/address/bank/reference/dialog words.
  'name': _KeywordClass.neutral,
  'vorname': _KeywordClass.neutral,
  'nachname': _KeywordClass.neutral,
  'familienname': _KeywordClass.neutral,
  'geburtsort': _KeywordClass.neutral,
  'straße': _KeywordClass.neutral,
  'strasse': _KeywordClass.neutral,
  'hausnummer': _KeywordClass.neutral,
  'ort': _KeywordClass.neutral,
  'wohnort': _KeywordClass.neutral,
  // §3.2 does not authorize forced text for these two synonyms.
  'postleitzahl': _KeywordClass.neutral,
  'telefax': _KeywordClass.neutral,
  'e-mail': _KeywordClass.neutral,
  'email': _KeywordClass.neutral,
  'bic': _KeywordClass.neutral,
  'bank': _KeywordClass.neutral,
  'konto': _KeywordClass.neutral,
  'steuer-id': _KeywordClass.neutral,
  'aktenzeichen': _KeywordClass.neutral,
  'geschäftszeichen': _KeywordClass.neutral,
  'antrag': _KeywordClass.neutral,
};

/// One OCR label observation with its display rectangle and confidence.
///
/// [text] is the raw OCR text; matching normalizes it, while the returned
/// `labelText` keeps the trimmed original spelling for display. [rect] is in
/// page display-space points and must be finite and strictly positive.
/// [ocrConfidence] must be finite and in `0.0 ... 1.0`; observations below
/// `0.5` are ignored as non-credible.
final class LabelObservation {
  /// Creates a label observation.
  ///
  /// Throws a content-free [ArgumentError] for a non-finite or out-of-range
  /// confidence. The error never includes [text].
  LabelObservation({
    required this.text,
    required this.rect,
    required this.ocrConfidence,
  }) {
    if (!ocrConfidence.isFinite || ocrConfidence < 0 || ocrConfidence > 1) {
      throw ArgumentError('label confidence must be finite and within 0 ... 1');
    }
  }

  /// Raw OCR label text; never logged by this library.
  final String text;

  /// Label rectangle in page display-space points.
  final DisplayRect rect;

  /// OCR confidence in `0.0 ... 1.0`.
  final double ocrConfidence;
}

/// The type, label text, and cue tokens derived for one geometry candidate.
///
/// `proposedType` is a member of [SuggestionSchema.proposedTypes].
/// `labelText` is the trimmed, at-most-200-code-point nearest credible label,
/// or `null` when no label is credible. `addedCues` contains only the cues
/// supplied by label proximity and typing, sorted and unique. The candidate's
/// geometric cues are not repeated, removed, or modified; the caller merges
/// both lists when building a suggestion.
final class TypeInferenceResult {
  TypeInferenceResult._({
    required this.proposedType,
    required this.labelText,
    required List<String> addedCues,
  }) : addedCues = List<String>.unmodifiable(addedCues);

  /// One of [SuggestionSchema.proposedTypes].
  final String proposedType;

  /// Nearest credible label, trimmed and at most 200 code points, or `null`.
  final String? labelText;

  /// Newly supported cue tokens, sorted ascending and unique.
  final List<String> addedCues;

  @override
  bool operator ==(Object other) {
    if (other is! TypeInferenceResult ||
        other.proposedType != proposedType ||
        other.labelText != labelText ||
        other.addedCues.length != addedCues.length) {
      return false;
    }
    for (int index = 0; index < addedCues.length; index++) {
      if (other.addedCues[index] != addedCues[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(proposedType, labelText, Object.hashAll(addedCues));
}

/// Deterministic label proximity and keyword-driven type inference.
///
/// The class is stateless and has no I/O. See the library documentation for
/// the proximity rule, total tie-break order, lexicon classes, and §3.2
/// precedence.
final class TypeInference {
  const TypeInference._();

  /// Derives the proposed type, label text, and added cues for [candidate].
  ///
  /// [labels] may be in any order; selection is order-independent and uses the
  /// documented total tie-break order. [singleLineMedianHeightPt] is the
  /// page's single-line text median in points. [pageWidthPt] and
  /// [pageHeightPt] are the display-space page metrics; candidate and label
  /// rectangles must lie inside them.
  ///
  /// Throws a content-free [ArgumentError] for a non-finite/non-positive
  /// median or page metric, or for any rectangle outside the page.
  static TypeInferenceResult infer({
    required GeometryCandidate candidate,
    required List<LabelObservation> labels,
    required double singleLineMedianHeightPt,
    required double pageWidthPt,
    required double pageHeightPt,
  }) {
    _validatePageMetrics(pageWidthPt, pageHeightPt);
    if (!singleLineMedianHeightPt.isFinite || singleLineMedianHeightPt <= 0) {
      throw ArgumentError(
        'single-line median height must be finite and positive',
      );
    }
    _validateInsidePage(candidate.rect, pageWidthPt, pageHeightPt, 'candidate');
    for (final LabelObservation label in labels) {
      _validateInsidePage(label.rect, pageWidthPt, pageHeightPt, 'label');
    }

    final List<_CredibleLabel> credible = _credibleLabels(
      labels,
      candidate.rect,
    );
    final _CredibleLabel? selected = _nearest(credible);
    final List<String> addedCues = <String>[];
    _KeywordMatch keywords = _KeywordMatch.none;
    if (selected != null) {
      addedCues.addAll(_alignmentCues(selected.rect, candidate.rect));
      keywords = _matchKeywords(selected.text);
      addedCues.addAll(keywords.cues);
      if (keywords.hasNumericFamily) {
        addedCues.add(_numericContextCue);
      }
    }

    final bool hasDateMask = credible.any(
      (_CredibleLabel label) => _containsDateMask(label.text),
    );
    if (hasDateMask) {
      addedCues.add(_dateContextCue);
    }

    final String proposedType = _inferType(
      candidate,
      keywords,
      hasDateMask,
      singleLineMedianHeightPt,
    );
    final List<String> sortedCues = addedCues.toSet().toList()..sort();
    return TypeInferenceResult._(
      proposedType: proposedType,
      labelText: selected == null ? null : _displayText(selected.text),
      addedCues: sortedCues,
    );
  }

  static void _validatePageMetrics(double pageWidthPt, double pageHeightPt) {
    if (!pageWidthPt.isFinite ||
        !pageHeightPt.isFinite ||
        pageWidthPt <= 0 ||
        pageHeightPt <= 0) {
      throw ArgumentError('page size must be finite and positive');
    }
  }

  static void _validateInsidePage(
    DisplayRect rect,
    double pageWidthPt,
    double pageHeightPt,
    String kind,
  ) {
    final double right = rect.x + rect.width;
    final double bottom = rect.y + rect.height;
    if (rect.x < -_epsilon ||
        rect.y < -_epsilon ||
        right > pageWidthPt + _epsilon ||
        bottom > pageHeightPt + _epsilon) {
      throw ArgumentError('$kind rect must be inside the page');
    }
  }

  static List<_CredibleLabel> _credibleLabels(
    List<LabelObservation> labels,
    DisplayRect candidate,
  ) {
    final List<_CredibleLabel> credible = <_CredibleLabel>[];
    for (final LabelObservation label in labels) {
      final String text = label.text.trim();
      if (text.isEmpty || label.ocrConfidence < _minLabelConfidence) {
        continue;
      }
      final double distanceSquared = _gapSquared(label.rect, candidate);
      final bool sharesRow = _sharesRow(label.rect, candidate);
      if (!sharesRow && distanceSquared > _maxLabelDistanceSquared + _epsilon) {
        continue;
      }
      credible.add(
        _CredibleLabel(
          text: text,
          rect: label.rect,
          confidence: label.ocrConfidence,
          distanceSquared: distanceSquared,
          sharesRow: sharesRow,
        ),
      );
    }
    return credible;
  }

  /// True when [label] is printed on the candidate's own row and outside it.
  ///
  /// `contracts/recognition-output.md` §3.1 defines the cue
  /// `ocr_alignment_right` as "the candidate is to the right of an OCR label
  /// line". A left label is therefore associated by layout: the two vertical
  /// spans overlap, and the label is not printed inside the candidate region.
  /// The horizontal gap is deliberately not distance-capped here, because a
  /// short label in a fixed label column leaves a wide empty gap that says
  /// nothing about the association; the same-row relation does.
  static bool _sharesRow(DisplayRect label, DisplayRect candidate) {
    final double labelBottom = label.y + label.height;
    final double candidateBottom = candidate.y + candidate.height;
    final double verticalOverlap = _overlap(
      label.y,
      labelBottom,
      candidate.y,
      candidateBottom,
    );
    if (verticalOverlap <= _epsilon) {
      return false;
    }
    // A line printed mostly inside the candidate is printed content of that
    // region (for example a `TT.MM.JJJJ` mask), not the region's label.
    final double labelArea = label.width * label.height;
    final double horizontalOverlap = _overlap(
      label.x,
      label.x + label.width,
      candidate.x,
      candidate.x + candidate.width,
    );
    final double insideArea = horizontalOverlap * verticalOverlap;
    return !(labelArea > 0 && insideArea > 0.5 * labelArea);
  }

  static _CredibleLabel? _nearest(List<_CredibleLabel> credible) {
    if (credible.isEmpty) {
      return null;
    }
    final List<_CredibleLabel> sorted = List<_CredibleLabel>.of(credible)
      ..sort(_compareCredibleLabels);
    return sorted.first;
  }

  static int _compareCredibleLabels(
    _CredibleLabel first,
    _CredibleLabel second,
  ) {
    // A label printed on the candidate's own row is the field's label by
    // layout, so it outranks a nearer heading or neighbouring line above or
    // below the row.
    if (first.sharesRow != second.sharesRow) {
      return first.sharesRow ? -1 : 1;
    }
    int result = first.distanceSquared.compareTo(second.distanceSquared);
    if (result != 0) {
      return result;
    }
    result = first.rect.y.compareTo(second.rect.y);
    if (result != 0) {
      return result;
    }
    result = first.rect.x.compareTo(second.rect.x);
    if (result != 0) {
      return result;
    }
    result = first.text.compareTo(second.text);
    if (result != 0) {
      return result;
    }
    result = first.rect.width.compareTo(second.rect.width);
    if (result != 0) {
      return result;
    }
    result = first.rect.height.compareTo(second.rect.height);
    if (result != 0) {
      return result;
    }
    return second.confidence.compareTo(first.confidence);
  }

  static double _gapSquared(DisplayRect label, DisplayRect candidate) {
    double dx = 0;
    final double candidateRight = candidate.x + candidate.width;
    final double labelRight = label.x + label.width;
    if (label.x > candidateRight) {
      dx = label.x - candidateRight;
    } else if (candidate.x > labelRight) {
      dx = candidate.x - labelRight;
    }

    double dy = 0;
    final double candidateBottom = candidate.y + candidate.height;
    final double labelBottom = label.y + label.height;
    if (label.y > candidateBottom) {
      dy = label.y - candidateBottom;
    } else if (candidate.y > labelBottom) {
      dy = candidate.y - labelBottom;
    }
    return dx * dx + dy * dy;
  }

  static List<String> _alignmentCues(DisplayRect label, DisplayRect candidate) {
    final List<String> cues = <String>[];
    final double candidateRight = candidate.x + candidate.width;
    final double candidateBottom = candidate.y + candidate.height;
    final double labelRight = label.x + label.width;
    final double labelBottom = label.y + label.height;
    final double horizontalOverlap = _overlap(
      label.x,
      labelRight,
      candidate.x,
      candidateRight,
    );

    // `ocr_alignment_right`: the candidate is to the right of the label line.
    final bool candidateIsRight = labelRight <= candidate.x + _epsilon;
    final bool verticalOverlap =
        _overlap(label.y, labelBottom, candidate.y, candidateBottom) > _epsilon;
    if (candidateIsRight && verticalOverlap) {
      cues.add(_ocrAlignmentRightCue);
    }

    // `ocr_alignment_below`: the candidate is below the label line.
    final bool candidateIsBelow = labelBottom <= candidate.y + _epsilon;
    if (candidateIsBelow && horizontalOverlap > _epsilon) {
      cues.add(_ocrAlignmentBelowCue);
    }

    // `label_below`: the label is directly below the candidate (signature
    // line), independent of the OCR-line orientation above.
    final bool labelIsBelow = label.y >= candidateBottom - _epsilon;
    if (labelIsBelow) {
      final double narrowerWidth = math.min(label.width, candidate.width);
      if (horizontalOverlap >= 0.5 * narrowerWidth - _epsilon) {
        cues.add(_labelBelowCue);
      }
    }
    return cues;
  }

  static double _overlap(
    double firstStart,
    double firstEnd,
    double secondStart,
    double secondEnd,
  ) {
    final double start = math.max(firstStart, secondStart);
    final double end = math.min(firstEnd, secondEnd);
    return end - start;
  }

  static bool _containsDateMask(String text) {
    return _dateMaskPattern.hasMatch(_normalizeForMatching(text));
  }

  static final RegExp _dateMaskPattern = RegExp(
    r'(?:^|[^a-z0-9])tt\.mm\.jjjj(?:$|[^a-z0-9])',
  );

  static _KeywordMatch _matchKeywords(String text) {
    final String normalized = _normalizeForMatching(text);
    if (normalized.isEmpty) {
      return _KeywordMatch.none;
    }
    final String exactSearchText = _composeGermanUmlauts(
      text.trim().toLowerCase(),
    );
    final List<String> keys = <String>[];
    int index = 0;
    while (index < normalized.length) {
      if (index > 0 && _isWordUnit(normalized.codeUnitAt(index - 1))) {
        index++;
        continue;
      }
      _LexiconEntry? best;
      for (final _LexiconEntry entry in _lexiconEntries) {
        if (best != null && entry.normalized.length < best.normalized.length) {
          break;
        }
        if (!normalized.startsWith(entry.normalized, index)) {
          continue;
        }
        final int end = index + entry.normalized.length;
        if (end < normalized.length &&
            _isWordUnit(normalized.codeUnitAt(end))) {
          continue;
        }
        if (best == null || _isPreferredLexeme(entry, best, exactSearchText)) {
          best = entry;
        }
      }
      if (best == null) {
        index++;
      } else {
        if (!keys.contains(best.key)) {
          keys.add(best.key);
        }
        index += best.normalized.length;
      }
    }
    return _KeywordMatch(keys);
  }

  static bool _isPreferredLexeme(
    _LexiconEntry candidate,
    _LexiconEntry current,
    String exactSearchText,
  ) {
    if (candidate.normalized.length != current.normalized.length) {
      return candidate.normalized.length > current.normalized.length;
    }
    final bool candidateExact = _containsExactKey(
      exactSearchText,
      candidate.key,
    );
    final bool currentExact = _containsExactKey(exactSearchText, current.key);
    if (candidateExact != currentExact) {
      return candidateExact;
    }
    return candidate.order < current.order;
  }

  static bool _containsExactKey(String lowerText, String key) {
    int start = 0;
    while (true) {
      final int index = lowerText.indexOf(key, start);
      if (index < 0) {
        return false;
      }
      final bool beforeOk =
          index == 0 || !_isGermanWordUnit(lowerText.codeUnitAt(index - 1));
      final int end = index + key.length;
      final bool afterOk =
          end == lowerText.length ||
          !_isGermanWordUnit(lowerText.codeUnitAt(end));
      if (beforeOk && afterOk) {
        return true;
      }
      start = index + 1;
    }
  }

  static bool _isWordUnit(int codeUnit) {
    return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7A);
  }

  static bool _isGermanWordUnit(int codeUnit) {
    return _isWordUnit(codeUnit) ||
        codeUnit == 0x00E4 ||
        codeUnit == 0x00F6 ||
        codeUnit == 0x00FC ||
        codeUnit == 0x00DF;
  }

  static String _normalizeForMatching(String text) {
    return _foldGermanUmlauts(text.trim().toLowerCase())
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss');
  }

  /// Folds NFD spellings (`a` + U+0308, ...) to the same digraphs as their
  /// precomposed forms. Other combining sequences are left untouched, so they
  /// break word matching instead of being silently repaired.
  static String _foldGermanUmlauts(String text) {
    final List<int> runes = text.runes.toList(growable: false);
    final StringBuffer buffer = StringBuffer();
    for (int index = 0; index < runes.length; index++) {
      final int rune = runes[index];
      if (index + 1 < runes.length && runes[index + 1] == _combiningDiaeresis) {
        switch (rune) {
          case 0x61 || 0x41:
            buffer.write('ae');
            index++;
            continue;
          case 0x6F || 0x4F:
            buffer.write('oe');
            index++;
            continue;
          case 0x75 || 0x55:
            buffer.write('ue');
            index++;
            continue;
        }
      }
      buffer.writeCharCode(rune);
    }
    return buffer.toString();
  }

  /// Composes the four German umlaut pairs (and their capitals) so that the
  /// literal-spelling preference is identical for NFC and NFD labels.
  static String _composeGermanUmlauts(String text) {
    return text
        .replaceAll('a$_combiningDiaeresisChar', 'ä')
        .replaceAll('o$_combiningDiaeresisChar', 'ö')
        .replaceAll('u$_combiningDiaeresisChar', 'ü')
        .replaceAll('A$_combiningDiaeresisChar', 'Ä')
        .replaceAll('O$_combiningDiaeresisChar', 'Ö')
        .replaceAll('U$_combiningDiaeresisChar', 'Ü');
  }

  static String _inferType(
    GeometryCandidate candidate,
    _KeywordMatch keywords,
    bool hasDateMask,
    double singleLineMedianHeightPt,
  ) {
    if (candidate.cues.contains(_smallSquareCue)) {
      return 'checkbox';
    }
    if (candidate.cues.contains(_signatureAreaCue)) {
      return 'signature';
    }
    final String? keywordType = keywords.forcedType;
    if (keywordType != null) {
      return keywordType;
    }

    final double height = candidate.rect.height;
    final double width = candidate.rect.width;
    final bool multiline =
        height >=
            _multilineHeightFactor * singleLineMedianHeightPt - _epsilon &&
        width >= _multilineMinWidthPt - _epsilon;
    if (multiline) {
      return 'multiline';
    }
    final double aspect = width / height;
    final bool checkbox =
        aspect >= _checkboxMinAspect - _epsilon &&
        aspect <= _checkboxMaxAspect + _epsilon &&
        height <= _checkboxMaxHeightPt + _epsilon;
    if (checkbox) {
      return 'checkbox';
    }
    if (hasDateMask) {
      return 'date';
    }
    return 'text';
  }

  static String _displayText(String text) {
    final String trimmed = text.trim();
    final List<int> runes = trimmed.runes.toList();
    if (runes.length <= _maxLabelTextRunes) {
      return trimmed;
    }
    return String.fromCharCodes(runes.take(_maxLabelTextRunes)).trimRight();
  }
}

/// One lexicon entry plus its matching-folded form and declaration order.
final class _LexiconEntry {
  const _LexiconEntry(this.key, this.normalized, this.order);

  final String key;
  final String normalized;
  final int order;
}

/// Lexicon entries ordered by folded length (descending), then declaration.
final List<_LexiconEntry> _lexiconEntries =
    <_LexiconEntry>[
      for (
        int index = 0;
        index < SuggestionSchema.keywordLexiconV1.length;
        index++
      )
        _LexiconEntry(
          SuggestionSchema.keywordLexiconV1[index],
          TypeInference._normalizeForMatching(
            SuggestionSchema.keywordLexiconV1[index],
          ),
          index,
        ),
    ]..sort((_LexiconEntry first, _LexiconEntry second) {
      final int byLength = second.normalized.length.compareTo(
        first.normalized.length,
      );
      if (byLength != 0) {
        return byLength;
      }
      return first.order.compareTo(second.order);
    });

/// One credible label after distance and text normalization.
final class _CredibleLabel {
  const _CredibleLabel({
    required this.text,
    required this.rect,
    required this.confidence,
    required this.distanceSquared,
    required this.sharesRow,
  });

  final String text;
  final DisplayRect rect;
  final double confidence;
  final double distanceSquared;

  /// The label is printed on the candidate's own row and outside it.
  final bool sharesRow;
}

/// The matched lexicon keys for the selected label.
final class _KeywordMatch {
  const _KeywordMatch(this.keys);

  static const _KeywordMatch none = _KeywordMatch(<String>[]);

  final List<String> keys;

  List<String> get cues => <String>[
    for (final String key in keys) '$_keywordPrefix$key',
  ];

  bool get hasNumericFamily => keys.any(
    (String key) =>
        _keywordClasses[key] == _KeywordClass.number ||
        _keywordClasses[key] == _KeywordClass.textNumeric,
  );

  String? get forcedType {
    final bool dateGuarded = _hasClass(_KeywordClass.textDateGuard);
    // §3.2: a region labelled Monat/Zeitraum/von/bis must never be forced to
    // date, even when a second date word also appears in the label.
    if (!dateGuarded && _hasClass(_KeywordClass.date)) {
      return 'date';
    }
    if (_hasClass(_KeywordClass.number)) {
      return 'number';
    }
    if (_hasClass(_KeywordClass.textNumeric) || dateGuarded) {
      return 'text';
    }
    if (_hasClass(_KeywordClass.signature)) {
      return 'signature';
    }
    return null;
  }

  bool _hasClass(_KeywordClass keywordClass) {
    return keys.any((String key) => _keywordClasses[key] == keywordClass);
  }
}
