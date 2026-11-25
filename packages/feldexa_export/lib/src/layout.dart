// Feldexa export layout (T103).
//
// Owner: `packages/feldexa_export/lib/src/layout.dart` (T103).
// Normative sources:
//   * `contracts/export-plan.md` §2.2 — the per-op formulas the produced ops
//     must satisfy (`fontSizePt`, `lineHeightPt`, `baselineFromTopPt`, the
//     checkbox mark, the signature `contain`/`center` contract);
//   * `contracts/export-plan.md` §3 — padding, single-line and multiline
//     layout, trailing-space trimming, glyph coverage, checkbox, signature;
//   * `contracts/export-plan.md` §4 — the blocking codes `EXP-001` (content
//     does not fit) and `EXP-004` (glyph missing);
//   * `contracts/coordinates-and-geometry.md` §5 — every op carries the
//     display-space `rect` and its PDF user-space `pdfRect`;
//   * FR-064, FR-065, FR-066, FR-067, FR-068, FR-037, FR-038.
//
// The layout is pure Dart with no Flutter, `dart:ui`, `dart:io`, or platform
// imports, so the identical code runs on Android, Web, and the host VM. The
// Noto Sans advance table enters as an [ExportFontMetrics] value supplied by
// the caller; nothing here hard-codes a file path.
//
// Two deliberate rules keep this file aligned with the T022 contract models:
//   * a field never shrinks, truncates, hyphenates, ellipsizes, or breaks a
//     word (§3.1); an unfitting value becomes a blocking warning instead;
//   * German user text stays in the catalog, so a warning carries only the
//     catalog code and a machine `reason`.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:feldexa_core/feldexa_core.dart';

import 'model/export_plan.dart';

/// Field padding on every side in points (`contracts/export-plan.md` §3.1).
const double exportFieldPaddingPt = 1.5;

/// Lower bound of the `fontSizePt` clamp (`contracts/export-plan.md` §2.2).
const double exportMinFontSizePt = 7.0;

/// Upper bound of the `fontSizePt` clamp (`contracts/export-plan.md` §2.2).
const double exportMaxFontSizePt = 12.0;

/// Padding around a signature image inside its field rect (§3.3).
const double exportSignaturePaddingPt = 1.0;

/// The largest signature scale: 2× the source pixel size at 72 dpi (§2.2).
const double exportSignatureMaxScale = 2.0;

/// Width/height comparison tolerance in points for layout decisions.
///
/// This is a floating-point comparison guard, not a placement tolerance: a
/// value that fits within this bound is treated as fitting exactly.
const double _comparisonTolerancePt = 1e-9;

const double _fontSizeHeightFactor = 0.6;
const double _lineHeightFactor = 1.2;
const double _baselineAscenderFactor = 0.8;
const double _checkboxInsetFactor = 0.15;
const double _checkboxStrokeFactor = 0.08;
const int _metricsSchemaVersion = 1;

/// Mirrors the stored canonical date form of `DateValue.canonical`.
final RegExp _canonicalDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// The bundled Noto Sans advance table required by the layout (§3.1).
///
/// The table comes from `apps/feldexa_app/assets/fonts/metrics.json`: the
/// `400` (regular) entry supplies the advances used by the v1 plan, and both
/// entries supply the bundled asset paths of the [ExportFont] contract.
/// Glyph coverage is exactly the set of codepoints in the advance table, so a
/// character missing from Noto Sans is reported as a blocking `EXP-004`
/// instead of being replaced.
final class ExportFontMetrics {
  ExportFontMetrics._(
    this._advances, {
    required this.family,
    required this.metricsVersion,
    required this.regularAsset,
    required this.boldAsset,
    required this.unitsPerEm,
  });

  /// Reads the bundled metrics document.
  ///
  /// Throws [FormatException] for a missing or malformed table. The caller
  /// supplies the decoded JSON, so no file-system or asset lookup happens
  /// here.
  factory ExportFontMetrics.fromJson(Map<String, Object?> json) {
    final int schemaVersion = _readInt(json, 'schemaVersion');
    if (schemaVersion != _metricsSchemaVersion) {
      throw FormatException(
        'Unsupported font metrics schema version $schemaVersion',
      );
    }
    final Map<String, Object?> fonts = _readObject(json, 'fonts');
    final Map<String, Object?> regular = _readObject(fonts, '400');
    final Map<String, Object?> bold = _readObject(fonts, '700');
    final int unitsPerEm = _readInt(regular, 'unitsPerEm');
    if (unitsPerEm <= 0) {
      throw const FormatException('Font metrics unitsPerEm must be positive');
    }
    final Map<String, Object?> rawAdvances = _readObject(regular, 'advances');
    final Map<int, int> advances = <int, int>{};
    for (final MapEntry<String, Object?> entry in rawAdvances.entries) {
      final int? rune = int.tryParse(entry.key);
      final Object? units = entry.value;
      if (rune == null ||
          rune < 0 ||
          rune > 0x10FFFF ||
          units is! int ||
          units < 0) {
        throw const FormatException(
          'Font metrics advances must map codepoints to non-negative integers',
        );
      }
      advances[rune] = units;
    }
    if (advances.isEmpty) {
      throw const FormatException('Font metrics advances must not be empty');
    }
    return ExportFontMetrics._(
      Map<int, int>.unmodifiable(advances),
      family: _readString(json, 'family'),
      metricsVersion: _readString(json, 'metricsVersion'),
      regularAsset: _readString(regular, 'asset'),
      boldAsset: _readString(bold, 'asset'),
      unitsPerEm: unitsPerEm,
    );
  }

  /// Reads the bundled metrics document from its JSON text.
  ///
  /// Throws [FormatException] for malformed JSON or an invalid table.
  factory ExportFontMetrics.decode(String source) {
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Font metrics JSON must be an object');
    }
    return ExportFontMetrics.fromJson(decoded);
  }

  /// Bundled font family (`NotoSans`).
  final String family;

  /// Identifier of the generated metrics table.
  final String metricsVersion;

  /// Relative bundled regular font asset path.
  final String regularAsset;

  /// Relative bundled bold font asset path; v1 layout never uses bold.
  final String boldAsset;

  /// Font design units per em (`1000` for Noto Sans).
  final int unitsPerEm;

  final Map<int, int> _advances;

  /// Whether [rune] has a glyph in the bundled regular font.
  bool coversRune(int rune) => _advances.containsKey(rune);

  /// The advance width of [rune] in font design units.
  ///
  /// Throws [ArgumentError] when the bundled font has no glyph for [rune].
  int advanceWidthUnits(int rune) {
    final int? units = _advances[rune];
    if (units == null) {
      throw ArgumentError(
        'The bundled metrics do not cover U+'
        '${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}',
      );
    }
    return units;
  }

  /// The runes of [text] without a glyph, in order of first appearance.
  List<int> missingRunes(String text) {
    final List<int> missing = <int>[];
    for (final int rune in text.runes) {
      if (!_advances.containsKey(rune) && !missing.contains(rune)) {
        missing.add(rune);
      }
    }
    return missing;
  }

  /// The advance width of [text] at [fontSizePt] in points.
  ///
  /// The sum of the per-glyph advances is the complete width contract for v1:
  /// the schema contains no kerning and no ligatures (`font_metrics_test`).
  ///
  /// Throws [ArgumentError] when [text] contains a rune without a glyph.
  double advanceWidthPt(String text, double fontSizePt) {
    int units = 0;
    for (final int rune in text.runes) {
      units += advanceWidthUnits(rune);
    }
    return units * fontSizePt / unitsPerEm;
  }

  /// The bundled font contract carried by the export plan (§2).
  ExportFont toExportFont() {
    return ExportFont(
      family: family,
      regularAsset: regularAsset,
      boldAsset: boldAsset,
      metricsVersion: metricsVersion,
    );
  }
}

/// The layout result of one confirmed field.
///
/// Exactly one of [op] and a blocking [warnings] entry applies:
///   * [op] is the single planned operation for the field;
///   * [op] is null when nothing is drawn (an empty value or an unchecked
///     checkbox) or when the field is blocked;
///   * [isEmpty] marks a confirmed field without renderable content, which is
///     allowed and only reported as `info.emptyFieldCount`;
///   * [trimmedTrailingSpaceCount] counts the trailing whitespace characters
///     removed from materialized line ends (§3.1).
final class ExportFieldLayout {
  const ExportFieldLayout({
    required this.fieldId,
    required this.pageIndex,
    this.op,
    this.warnings = const <ExportValidationWarning>[],
    this.trimmedTrailingSpaceCount = 0,
    this.isEmpty = false,
  });

  /// Confirmed field id.
  final String fieldId;

  /// 0-based page index of the field.
  final int pageIndex;

  /// The planned operation, or null when nothing is drawn.
  final ExportOp? op;

  /// Blocking warnings for this field; empty when the field can be exported.
  final List<ExportValidationWarning> warnings;

  /// Trailing whitespace characters removed from line ends.
  final int trimmedTrailingSpaceCount;

  /// Whether the field carries no renderable content.
  final bool isEmpty;

  /// Whether at least one blocking warning exists.
  bool get isBlocking => warnings.isNotEmpty;

  @override
  String toString() =>
      'ExportFieldLayout(fieldId: $fieldId, op: ${op?.kind}, '
      'warnings: ${warnings.length})';
}

/// Lays confirmed field values out into export operations
/// (`contracts/export-plan.md` §3).
///
/// The engine decides size, lines, baselines, the checkbox mark, and the
/// signature fit. It produces the display `rect` and the mapped `pdfRect` for
/// every op; it never writes PDF operators and never decides page geometry.
final class ExportLayout {
  /// Creates a layout engine over the bundled metrics.
  const ExportLayout({required this.metrics});

  /// The advance table every measurement uses.
  final ExportFontMetrics metrics;

  /// Lays out one confirmed field on [geometry].
  ///
  /// [value] is the committed value of the field (null when the field was
  /// never filled); [signatureMark] carries the capture asset and pixel size
  /// of a signature field. The result contains either the single op for the
  /// field or its blocking warnings, never both.
  ExportFieldLayout layoutField({
    required ConfirmedField field,
    required PageGeometry geometry,
    FieldValue? value,
    SignatureMark? signatureMark,
  }) {
    return switch (field.type) {
      FieldType.text || FieldType.number || FieldType.date => _layoutText(
        field: field,
        geometry: geometry,
        value: value,
      ),
      FieldType.multiline => _layoutMultiline(
        field: field,
        geometry: geometry,
        value: value,
      ),
      FieldType.checkbox => _layoutCheckbox(
        field: field,
        geometry: geometry,
        value: value,
      ),
      FieldType.signature => _layoutSignature(
        field: field,
        geometry: geometry,
        value: value,
        signatureMark: signatureMark,
      ),
    };
  }

  ExportFieldLayout _layoutText({
    required ConfirmedField field,
    required PageGeometry geometry,
    required FieldValue? value,
  }) {
    if (value == null) {
      return _empty(field);
    }
    final String? displayText = _singleLineText(value);
    if (displayText == null) {
      return _blocked(field, 'value_type_mismatch');
    }
    final Rect rect = field.rect;
    final double fontSizePt = _fontSizePt(rect);
    final double lineHeightPt = _roundTo(_lineHeightFactor * fontSizePt, 2);
    final double baselineFromTopPt =
        exportFieldPaddingPt + _baselineAscenderFactor * fontSizePt;
    final _TrimmedText trimmed = _trimTrailingWhitespace(displayText);
    if (trimmed.text.isEmpty) {
      return _empty(field, trimmedTrailingSpaceCount: trimmed.removedCount);
    }
    final ExportFieldLayout? glyphBlocked = _checkGlyphCoverage(
      field,
      trimmed.text,
    );
    if (glyphBlocked != null) {
      return glyphBlocked;
    }
    final List<ExportValidationWarning> warnings = <ExportValidationWarning>[];
    final double availableWidth = _availableWidth(rect);
    if (metrics.advanceWidthPt(trimmed.text, fontSizePt) >
        availableWidth + _comparisonTolerancePt) {
      warnings.add(_warning(field, 'EXP-001', 'too_wide'));
    }
    if (baselineFromTopPt > rect.height + _comparisonTolerancePt) {
      warnings.add(_warning(field, 'EXP-001', 'baseline_exceeds_rect'));
    }
    if (warnings.isNotEmpty) {
      return ExportFieldLayout(
        fieldId: field.id,
        pageIndex: field.pageIndex,
        warnings: List<ExportValidationWarning>.unmodifiable(warnings),
        trimmedTrailingSpaceCount: trimmed.removedCount,
      );
    }
    return ExportFieldLayout(
      fieldId: field.id,
      pageIndex: field.pageIndex,
      op: ExportTextOp(
        fieldId: field.id,
        provenance: field.provenance,
        rect: rect,
        pdfRect: geometry.displayRectToPdf(rect),
        fontSizePt: fontSizePt,
        lineHeightPt: lineHeightPt,
        baselineFromTopPt: baselineFromTopPt,
        lines: <String>[trimmed.text],
      ),
      trimmedTrailingSpaceCount: trimmed.removedCount,
    );
  }

  ExportFieldLayout _layoutMultiline({
    required ConfirmedField field,
    required PageGeometry geometry,
    required FieldValue? value,
  }) {
    if (value == null) {
      return _empty(field);
    }
    if (value is! MultilineValue) {
      return _blocked(field, 'value_type_mismatch');
    }
    final Rect rect = field.rect;
    final double fontSizePt = _fontSizePt(rect);
    final double lineHeightPt = _roundTo(_lineHeightFactor * fontSizePt, 2);
    final double baselineFromTopPt =
        exportFieldPaddingPt + _baselineAscenderFactor * fontSizePt;
    // The explicit `\n` line separators are layout instructions, not
    // rendered glyphs, so coverage is checked without them.
    final ExportFieldLayout? glyphBlocked = _checkGlyphCoverage(
      field,
      value.text.replaceAll('\n', ''),
    );
    if (glyphBlocked != null) {
      return glyphBlocked;
    }
    final _WrappedLines wrapped = _wrap(
      value.text,
      availableWidth: _availableWidth(rect),
      fontSizePt: fontSizePt,
    );
    if (wrapped.lines.every((String line) => line.isEmpty)) {
      return _empty(
        field,
        trimmedTrailingSpaceCount: wrapped.trimmedTrailingSpaceCount,
      );
    }
    final List<ExportValidationWarning> warnings = <ExportValidationWarning>[];
    if (wrapped.hasTooWideLine) {
      warnings.add(_warning(field, 'EXP-001', 'too_wide'));
    }
    if (wrapped.lines.length * lineHeightPt >
        _availableHeight(rect) + _comparisonTolerancePt) {
      warnings.add(_warning(field, 'EXP-001', 'too_many_lines'));
    }
    if (baselineFromTopPt > rect.height + _comparisonTolerancePt) {
      warnings.add(_warning(field, 'EXP-001', 'baseline_exceeds_rect'));
    }
    if (warnings.isNotEmpty) {
      return ExportFieldLayout(
        fieldId: field.id,
        pageIndex: field.pageIndex,
        warnings: List<ExportValidationWarning>.unmodifiable(warnings),
        trimmedTrailingSpaceCount: wrapped.trimmedTrailingSpaceCount,
      );
    }
    return ExportFieldLayout(
      fieldId: field.id,
      pageIndex: field.pageIndex,
      op: ExportTextOp(
        fieldId: field.id,
        provenance: field.provenance,
        rect: rect,
        pdfRect: geometry.displayRectToPdf(rect),
        fontSizePt: fontSizePt,
        lineHeightPt: lineHeightPt,
        baselineFromTopPt: baselineFromTopPt,
        lines: wrapped.lines,
      ),
      trimmedTrailingSpaceCount: wrapped.trimmedTrailingSpaceCount,
    );
  }

  ExportFieldLayout _layoutCheckbox({
    required ConfirmedField field,
    required PageGeometry geometry,
    required FieldValue? value,
  }) {
    if (value != null && value is! CheckboxValue) {
      return _blocked(field, 'value_type_mismatch');
    }
    if (value is! CheckboxValue || !value.checked) {
      return _noOp(field);
    }
    final Rect rect = field.rect;
    final double minSide = math.min(rect.width, rect.height);
    final double insetPt = (_checkboxInsetFactor * minSide)
        .clamp(0.5, 3.0)
        .toDouble();
    final double strokeWidthPt = _roundTo(
      (_checkboxStrokeFactor * minSide).clamp(0.6, 1.4).toDouble(),
      1,
    );
    return ExportFieldLayout(
      fieldId: field.id,
      pageIndex: field.pageIndex,
      op: ExportCheckboxOp(
        fieldId: field.id,
        provenance: field.provenance,
        rect: rect,
        pdfRect: geometry.displayRectToPdf(rect),
        checked: true,
        insetPt: insetPt,
        strokeWidthPt: strokeWidthPt,
      ),
    );
  }

  ExportFieldLayout _layoutSignature({
    required ConfirmedField field,
    required PageGeometry geometry,
    required FieldValue? value,
    required SignatureMark? signatureMark,
  }) {
    if (value == null) {
      return _empty(field);
    }
    if (value is! SignatureValue) {
      return _blocked(field, 'value_type_mismatch');
    }
    final SignatureMark? mark = signatureMark;
    if (mark == null || mark.assetId != value.signatureAssetId) {
      return _blocked(field, 'signature_asset_missing');
    }
    final Rect rect = field.rect;
    final double availableWidth = rect.width - 2 * exportSignaturePaddingPt;
    final double availableHeight = rect.height - 2 * exportSignaturePaddingPt;
    if (availableWidth <= 0 || availableHeight <= 0) {
      return _blocked(field, 'signature_too_small');
    }
    final double containScale = math.min(
      availableWidth / mark.widthPx,
      availableHeight / mark.heightPx,
    );
    final double scale = math.min(containScale, exportSignatureMaxScale);
    final double width = mark.widthPx * scale;
    final double height = mark.heightPx * scale;
    final Rect imageRect = Rect.fromLTWH(
      rect.left + (rect.width - width) / 2,
      rect.top + (rect.height - height) / 2,
      width,
      height,
    );
    return ExportFieldLayout(
      fieldId: field.id,
      pageIndex: field.pageIndex,
      op: ExportImageOp(
        fieldId: field.id,
        provenance: field.provenance,
        rect: imageRect,
        pdfRect: geometry.displayRectToPdf(imageRect),
        assetId: mark.assetId,
      ),
    );
  }

  /// Materializes the lines of [text] by wrapping at spaces (§3.1).
  ///
  /// Explicit `\n` starts a new line. A word longer than the available width
  /// is never broken; the line keeps it and [hasTooWideLine] records the
  /// blocking condition. Trailing whitespace is removed from every emitted
  /// line and counted, including the spaces consumed by a wrap break.
  _WrappedLines _wrap(
    String text, {
    required double availableWidth,
    required double fontSizePt,
  }) {
    final List<String> lines = <String>[];
    int trimmedTrailingSpaceCount = 0;
    bool hasTooWideLine = false;
    for (final String paragraph in text.split('\n')) {
      final List<int> runes = paragraph.runes.toList(growable: false);
      if (runes.isEmpty) {
        lines.add('');
        continue;
      }
      int start = 0;
      while (start < runes.length) {
        double width = 0;
        int end = start;
        int breakIndex = -1;
        while (end < runes.length) {
          final double advance = _runeAdvancePt(runes[end], fontSizePt);
          if (end > start && width + advance > availableWidth) {
            break;
          }
          width += advance;
          if (_isSpaceRune(runes[end])) {
            breakIndex = end;
          }
          end++;
        }
        final String piece;
        if (end >= runes.length) {
          piece = _runesToText(runes, start, end);
          start = runes.length;
        } else if (breakIndex >= start) {
          piece = _runesToText(runes, start, breakIndex);
          start = breakIndex + 1;
          trimmedTrailingSpaceCount++;
          while (start < runes.length && _isSpaceRune(runes[start])) {
            start++;
            trimmedTrailingSpaceCount++;
          }
        } else {
          // No space in the fitting prefix: keep the whole word unbroken.
          while (end < runes.length && !_isSpaceRune(runes[end])) {
            end++;
          }
          piece = _runesToText(runes, start, end);
          start = end;
          while (start < runes.length && _isSpaceRune(runes[start])) {
            start++;
            trimmedTrailingSpaceCount++;
          }
        }
        final _TrimmedText trimmed = _trimTrailingWhitespace(piece);
        trimmedTrailingSpaceCount += trimmed.removedCount;
        if (trimmed.text.isEmpty) {
          continue;
        }
        lines.add(trimmed.text);
        if (metrics.advanceWidthPt(trimmed.text, fontSizePt) >
            availableWidth + _comparisonTolerancePt) {
          hasTooWideLine = true;
        }
      }
    }
    return _WrappedLines(
      lines: lines,
      trimmedTrailingSpaceCount: trimmedTrailingSpaceCount,
      hasTooWideLine: hasTooWideLine,
    );
  }

  ExportFieldLayout? _checkGlyphCoverage(ConfirmedField field, String text) {
    if (metrics.missingRunes(text).isEmpty) {
      return null;
    }
    return _blocked(field, 'glyph_missing', code: 'EXP-004');
  }

  double _runeAdvancePt(int rune, double fontSizePt) {
    return metrics.advanceWidthUnits(rune) * fontSizePt / metrics.unitsPerEm;
  }

  String? _singleLineText(FieldValue value) {
    return switch (value) {
      TextValue() => value.text,
      NumberValue() => _germanNumber(value.canonical),
      DateValue() => _germanDate(value.canonical),
      _ => null,
    };
  }

  ExportFieldLayout _empty(
    ConfirmedField field, {
    int trimmedTrailingSpaceCount = 0,
  }) {
    return ExportFieldLayout(
      fieldId: field.id,
      pageIndex: field.pageIndex,
      trimmedTrailingSpaceCount: trimmedTrailingSpaceCount,
      isEmpty: true,
    );
  }

  ExportFieldLayout _noOp(ConfirmedField field) {
    return ExportFieldLayout(fieldId: field.id, pageIndex: field.pageIndex);
  }

  ExportFieldLayout _blocked(
    ConfirmedField field,
    String reason, {
    String code = 'EXP-001',
  }) {
    return ExportFieldLayout(
      fieldId: field.id,
      pageIndex: field.pageIndex,
      warnings: List<ExportValidationWarning>.unmodifiable(
        <ExportValidationWarning>[_warning(field, code, reason)],
      ),
    );
  }

  ExportValidationWarning _warning(
    ConfirmedField field,
    String code,
    String reason,
  ) {
    return ExportValidationWarning(
      code: code,
      reason: reason,
      fieldId: field.id,
      pageIndex: field.pageIndex,
      fieldLabel: field.label,
    );
  }
}

/// Display text of a single-line number as §3.1 requires: the German decimal
/// comma and no thousands separators.
///
/// `NumberValue.canonical` is stored with a dot and never contains grouping
/// (T080), so replacing the dot is the complete rewrite.
String _germanNumber(String canonical) => canonical.replaceAll('.', ',');

/// Display text of a single-line date as §3.1 requires: `dd.MM.yyyy`.
///
/// `DateValue.canonical` is always a real calendar date in `YYYY-MM-DD` form
/// (T081); a violated invariant fails loudly instead of being reformatted
/// silently.
String _germanDate(String canonical) {
  final RegExpMatch match = _canonicalDatePattern.firstMatch(canonical)!;
  final int year = int.parse(match.group(1)!);
  final int month = int.parse(match.group(2)!);
  final int day = int.parse(match.group(3)!);
  final String dd = day.toString().padLeft(2, '0');
  final String mm = month.toString().padLeft(2, '0');
  return '$dd.$mm.${year.toString().padLeft(4, '0')}';
}

/// The `fontSizePt` clamp of `contracts/export-plan.md` §2.2.
double _fontSizePt(Rect rect) {
  return _roundTo(
    (_fontSizeHeightFactor * rect.height)
        .clamp(exportMinFontSizePt, exportMaxFontSizePt)
        .toDouble(),
    1,
  );
}

double _availableWidth(Rect rect) {
  return rect.width - 2 * exportFieldPaddingPt;
}

double _availableHeight(Rect rect) {
  return rect.height - 2 * exportFieldPaddingPt;
}

/// Matches the T022 model rounding exactly, so a produced value passes the
/// `ExportTextOp` formula checks bit for bit.
double _roundTo(double value, int decimals) {
  final double factor = math.pow(10, decimals).toDouble();
  return (value * factor).roundToDouble() / factor;
}

bool _isSpaceRune(int rune) => rune == 0x20;

String _runesToText(List<int> runes, int start, int end) {
  return String.fromCharCodes(runes, start, end);
}

_TrimmedText _trimTrailingWhitespace(String value) {
  // `String.trimRight` removes exactly the trailing characters the
  // `ExportTextOp` contract refuses at a line end.
  final String trimmed = value.trimRight();
  return _TrimmedText(trimmed, value.runes.length - trimmed.runes.length);
}

final class _TrimmedText {
  const _TrimmedText(this.text, this.removedCount);

  final String text;
  final int removedCount;
}

final class _WrappedLines {
  const _WrappedLines({
    required this.lines,
    required this.trimmedTrailingSpaceCount,
    required this.hasTooWideLine,
  });

  final List<String> lines;
  final int trimmedTrailingSpaceCount;
  final bool hasTooWideLine;
}

int _readInt(Map<String, Object?> json, String name) {
  final Object? value = json[name];
  if (value is! int) {
    throw FormatException('Font metrics field "$name" must be an integer');
  }
  return value;
}

String _readString(Map<String, Object?> json, String name) {
  final Object? value = json[name];
  if (value is! String || value.isEmpty) {
    throw FormatException(
      'Font metrics field "$name" must be a non-empty string',
    );
  }
  return value;
}

Map<String, Object?> _readObject(Map<String, Object?> json, String name) {
  final Object? value = json[name];
  if (value is! Map<String, Object?>) {
    throw FormatException('Font metrics field "$name" must be an object');
  }
  return value;
}
