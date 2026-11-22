// T086C FLD-001 text-fit measurement for the productive editor path.
//
// Owner: `apps/feldexa_app/lib/features/fill/field_text_fit.dart` (T086C,
// issue #281).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/contracts/export-plan.md` §2.2 (font
//     size `clamp(0.6 × rect.height, 7.0, 12.0)`, line height
//     `1.2 × fontSizePt`, baseline `1.5 + 0.8 × fontSizePt`) and §3.1 (1.5 pt
//     padding on every side, single-line has exactly one line, multiline has
//     explicit `\n` plus greedy word wrap at spaces, a single word longer than
//     the line is never broken, overflow when `lines × lineHeightPt` exceeds
//     the available height);
//   * `specs/001-scanned-form-workflow/research.md` D-11 (one text layout
//     engine: the bundled Noto Sans glyph metrics are the single measurement
//     source for Dart layout and PDF drawing);
//   * `contracts/editor-interactions.md` §5 (entered text that overflows shows
//     the `FLD-001` warning, and the value is kept) and
//     `contracts/error-catalog.de.md` `FLD-001` / EXP-001;
//   * `specs/001-scanned-form-workflow/spec.md` FR-037 (warn before
//     finalization when content exceeds its field) and FR-038 (never silently
//     truncate, drop, reorder, or omit entered information);
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// What this file is
// -----------------
// A pure decision function for one field value: does the entered text still
// fit the stored field display region under the export layout rules? It reads
// no document, editor, store, clock, file, or network, renders no widget, and
// never changes the text it is given. The caller keeps the complete value
// (nothing is truncated here) and sets the existing `FieldValue.overflow` flag
// from the answer.
//
// The measurement itself is a seam: [fieldTextOverflows] takes a
// [TextAdvanceMeasure] callback, so the layout arithmetic is testable without a
// font and the production caller passes [notoSansTextAdvance], which measures
// with Flutter's text layout and the bundled `NotoSans` family (the same TTF
// bytes `assets/fonts/metrics.json` was generated from, per D-11).
//
// Geometry
// --------
// [core.Rect] is the field display region in display points, which is the same
// unit as `fontSizePt` at the contract's 72 dpi display mapping, so the
// measurement needs no viewport scale and no device pixel ratio. The available
// box inside the field is `rect − 2 × 1.5 pt`.
//
// One metrics source (D-11)
// ------------------------
// [initializeFieldTextMeasure] reads the bundled `assets/fonts/metrics.json`,
// the advance table T007 generated from the pinned `NotoSans-Regular.ttf` bytes
// that PDF drawing uses too. The measurement is therefore integer font units
// and identical on a host VM and on a device, which is why the host tests can
// assert exact widths. The table is read once through `rootBundle` during
// startup and cached; [fieldTextMeasure] is the synchronous seam the commit
// path reads, so a save never waits for asset I/O and never blocks on a
// measurement failure.
//
// Fail-closed cases
// -----------------
// A box with no usable inner area, or one shorter than the contract baseline,
// cannot show the text at all and reports an overflow. Checkbox and signature
// fields carry no clipable text and never report one. Empty or whitespace-only
// text has nothing to clip and never reports an overflow.
//
// Evidence
// --------
// Host-VM unit tests (`test/field_text_fit_test.dart`) cover the arithmetic
// with a synthetic measure; widget tests cover the sheet wiring. This file
// makes no Android, device, screen-reader, or visual claim of its own; the
// T086C emulator journey is the device evidence.

library;

import 'dart:convert';

import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/services.dart';

/// Padding between the field rectangle and the text, in display points.
///
/// `contracts/export-plan.md` §3.1 uses 1.5 pt on all four sides.
const double fieldTextPaddingPt = 1.5;

/// Smallest font size the export layout uses, in points (`§2.2`).
const double fieldTextMinFontSizePt = 7.0;

/// Largest font size the export layout uses, in points (`§2.2`).
const double fieldTextMaxFontSizePt = 12.0;

/// Family name of the single bundled text font (`pubspec.yaml`, D-11).
const String fieldTextFontFamily = 'NotoSans';

/// Bundle path of the generated Noto Sans advance table (T007, D-11).
const String fieldTextMetricsAssetPath = 'assets/fonts/metrics.json';

/// Weight key of the regular face inside `metrics.json`.
const String _regularWeightKey = '400';

/// Tolerance for decimal comparisons of measured advances, in points.
///
/// The published rules are decimal (`1.2 × fontSizePt`, `rect − 3.0`), so an
/// exact fit must not turn into an overflow from binary floating-point noise.
const double _measureEpsilonPt = 1e-9;

/// Measures [text] with the bundled `NotoSans` advance table.
///
/// Implementations must be pure and deterministic for the same inputs. The
/// production implementation is [FieldTextMetrics.measure].
///
/// [text] is measured as one line: wrapping is done by [fieldTextOverflows], so
/// a single advance call never hides a line break.
typedef TextAdvanceMeasure = double Function(String text, double fontSizePt);

/// Rounds [value] to one decimal place (the `§2.2` font-size precision).
double _roundToTenth(double value) => (value * 10).round() / 10;

/// Rounds [value] to two decimal places (the `§2.2` line-height precision).
double _roundToHundredth(double value) => (value * 100).round() / 100;

/// Available text width inside [rect], in display points.
double fieldAvailableWidthPt(core.Rect rect) {
  return rect.width - 2 * fieldTextPaddingPt;
}

/// Available text height inside [rect], in display points.
double fieldAvailableHeightPt(core.Rect rect) {
  return rect.height - 2 * fieldTextPaddingPt;
}

/// The `§2.2` font size for a field of [fieldHeightPt] points.
double fieldFontSizePt(double fieldHeightPt) {
  return _roundToTenth(
    (0.6 * fieldHeightPt).clamp(fieldTextMinFontSizePt, fieldTextMaxFontSizePt),
  );
}

/// The `§2.2` line height for [fontSizePt], in points.
double fieldLineHeightPt(double fontSizePt) {
  return _roundToHundredth(1.2 * fontSizePt);
}

/// The `§2.2` distance from the field top to the first baseline, in points.
double fieldBaselineFromTopPt(double fontSizePt) {
  return 1.5 + 0.8 * fontSizePt;
}

/// Whether [text] still fits inside [rect] for a field of [type].
///
/// Returns true exactly when the export layout could not draw the complete
/// text inside the field: a single-line advance wider than the available
/// width, a line break in a single-line field, an unbreakable word wider than
/// the available width, more wrapped lines than the available height holds, or
/// a box too small for the contract baseline. The text itself is never
/// measured destructively and never truncated.
bool fieldTextOverflows({
  required core.FieldType type,
  required core.Rect rect,
  required String text,
  required TextAdvanceMeasure measure,
}) {
  if (type == core.FieldType.checkbox || type == core.FieldType.signature) {
    return false;
  }
  // Nothing to clip: an empty or whitespace-only value is not an overflow.
  if (text.trim().isEmpty) {
    return false;
  }

  final double availableWidth = fieldAvailableWidthPt(rect);
  final double availableHeight = fieldAvailableHeightPt(rect);
  if (availableWidth <= 0 || availableHeight <= 0) {
    return true;
  }

  final double fontSize = fieldFontSizePt(rect.height);
  if (fieldBaselineFromTopPt(fontSize) > rect.height + _measureEpsilonPt) {
    return true;
  }

  final bool singleLine =
      type == core.FieldType.text ||
      type == core.FieldType.number ||
      type == core.FieldType.date;
  if (singleLine) {
    // A single-line field has exactly one line; an entered line break cannot be
    // rendered and is never silently dropped.
    if (text.contains('\n')) {
      return true;
    }
    return measure(text, fontSize) > availableWidth + _measureEpsilonPt;
  }

  final double lineHeight = fieldLineHeightPt(fontSize);
  final List<String>? lines = _wrapMultiline(
    text: text,
    availableWidth: availableWidth,
    fontSize: fontSize,
    measure: measure,
  );
  if (lines == null) {
    // A single word is wider than the line and may not be broken.
    return true;
  }
  return lines.length * lineHeight > availableHeight + _measureEpsilonPt;
}

/// Greedy `§3.1` word wrap, or null when one word alone is too wide.
///
/// Explicit `\n` always starts a new line (an empty paragraph is one rendered
/// line). Words are joined with single spaces; a word that does not fit is
/// moved to the next line, and a word wider than the line reports the
/// unbreakable-word overflow through the null result.
List<String>? _wrapMultiline({
  required String text,
  required double availableWidth,
  required double fontSize,
  required TextAdvanceMeasure measure,
}) {
  final List<String> lines = <String>[];
  for (final String paragraph in text.split('\n')) {
    if (paragraph.isEmpty) {
      lines.add('');
      continue;
    }
    String line = '';
    for (final String word in paragraph.split(' ')) {
      if (word.isEmpty) {
        continue;
      }
      if (line.isEmpty) {
        line = word;
        if (measure(line, fontSize) > availableWidth + _measureEpsilonPt) {
          return null;
        }
        continue;
      }
      final String candidate = '$line $word';
      if (measure(candidate, fontSize) <= availableWidth + _measureEpsilonPt) {
        line = candidate;
        continue;
      }
      lines.add(line);
      line = word;
      if (measure(line, fontSize) > availableWidth + _measureEpsilonPt) {
        return null;
      }
    }
    lines.add(line);
  }
  return lines;
}

/// The bundled Noto Sans advance table used for FLD-001 measurement (D-11).
///
/// [measure] turns a string into display points: the sum of the glyph advances
/// in font units, scaled by `fontSizePt / unitsPerEm`. It is deterministic
/// across host and device because it never consults a platform font.
final class FieldTextMetrics {
  const FieldTextMetrics._({
    required this.unitsPerEm,
    required this.advances,
    required this.missingGlyphAdvance,
  });

  /// Parses one `metrics.json` document (schema version 1, §`fonts.<weight>`).
  ///
  /// Throws a [FormatException] when the document does not carry the regular
  /// face, a positive `unitsPerEm`, or a non-empty `advances` table.
  factory FieldTextMetrics.fromJson(Map<String, Object?> json) {
    final Object? fonts = json['fonts'];
    if (fonts is! Map<String, Object?>) {
      throw const FormatException('metrics.json has no fonts map');
    }
    final Object? regular = fonts[_regularWeightKey];
    if (regular is! Map<String, Object?>) {
      throw const FormatException('metrics.json has no regular face');
    }
    final Object? unitsPerEm = regular['unitsPerEm'];
    if (unitsPerEm is! int || unitsPerEm <= 0) {
      throw const FormatException('metrics.json has no positive unitsPerEm');
    }
    final Object? rawAdvances = regular['advances'];
    if (rawAdvances is! Map<String, Object?> || rawAdvances.isEmpty) {
      throw const FormatException('metrics.json has no advance table');
    }
    final Map<int, int> advances = <int, int>{};
    for (final MapEntry<String, Object?> entry in rawAdvances.entries) {
      final int? rune = int.tryParse(entry.key);
      final Object? advance = entry.value;
      if (rune == null || advance is! int || advance < 0) {
        throw const FormatException('metrics.json has a malformed advance');
      }
      advances[rune] = advance;
    }
    // A glyph the table does not cover cannot be measured exactly. Fail closed
    // toward the warning with the widest advance the font declares instead of
    // pretending the text fits; the export blocks such a glyph separately.
    final Object? advanceWidthMax = regular['advanceWidthMax'];
    return FieldTextMetrics._(
      unitsPerEm: unitsPerEm,
      advances: advances,
      missingGlyphAdvance: advanceWidthMax is int && advanceWidthMax > 0
          ? advanceWidthMax
          : unitsPerEm,
    );
  }

  /// Font design units per em.
  final int unitsPerEm;

  /// Advance width per code point, in font design units.
  final Map<int, int> advances;

  /// Advance used for a code point the table does not cover, in design units.
  final int missingGlyphAdvance;

  /// Single-line advance width of [text] at [fontSizePt], in display points.
  double measure(String text, double fontSizePt) {
    int units = 0;
    for (final int rune in text.runes) {
      units += advances[rune] ?? missingGlyphAdvance;
    }
    return units * fontSizePt / unitsPerEm;
  }
}

/// Cached parse of the bundled advance table, or null before startup.
FieldTextMetrics? _cachedMetrics;
Future<bool>? _pendingInitialization;

/// Reads the bundled Noto Sans advance table once and caches it.
///
/// Called from the application startup before `runApp`, so the commit path can
/// measure synchronously through [fieldTextMeasure]. Returns true when the
/// table is available. Returns false when the asset cannot be read or parsed;
/// a missing table never blocks a save and never fabricates a warning — the
/// sheet stores the complete value without setting the `overflow` flag. A
/// failed initialization is not cached, so a later call can retry.
Future<bool> initializeFieldTextMeasure() async {
  if (_cachedMetrics != null) {
    return true;
  }
  final Future<bool> pending = _pendingInitialization ??= _readMetricsAsset();
  final bool ready = await pending;
  if (!ready) {
    _pendingInitialization = null;
  }
  return ready;
}

/// The loaded production measure, or null when the table is not available.
///
/// Synchronous by design: the value sheet measures on the commit path and must
/// never wait for asset I/O or fail a save because a table is missing.
TextAdvanceMeasure? get fieldTextMeasure {
  final FieldTextMetrics? metrics = _cachedMetrics;
  return metrics?.measure;
}

/// Whether [initializeFieldTextMeasure] already succeeded.
bool get fieldTextMeasureReady => _cachedMetrics != null;

Future<bool> _readMetricsAsset() async {
  try {
    final String source = await rootBundle.loadString(
      fieldTextMetricsAssetPath,
    );
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      return false;
    }
    _cachedMetrics = FieldTextMetrics.fromJson(decoded);
    return true;
  } on Object {
    return false;
  }
}
