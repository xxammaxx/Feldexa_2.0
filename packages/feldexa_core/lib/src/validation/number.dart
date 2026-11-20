// Feldexa core number parsing (T080).
//
// Owner: `packages/feldexa_core/lib/src/validation/number.dart`.
//
// This is the single source for the German and canonical number grammar that
// T019 reclassification already pinned. Reclassification delegates here, and
// later editors can validate input against the same rules.
//
// The parser is deliberately small, pure, and string-only: it validates and
// rewrites separators, never converts to `num`. The sign, leading zeros, and
// fraction digits are preserved verbatim.
//
// Accepted forms, matched in this order:
//   * German grouping `-?\d{1,3}(?:\.\d{3})+(?:,\d+)?`: the grouping dots are
//     removed and a comma fraction becomes a dot fraction. A valid grouping is
//     preferred over a canonical dot decimal, so `1.234` becomes `1234`;
//   * German decimal `-?\d+(?:,\d+)?`: the comma becomes a dot decimal;
//   * canonical `-?\d+(?:\.\d+)?`: returned unchanged, including `1.23`,
//     `1.2345`, and `12.34`, which are dot decimals and not groupings.
//
// Exponent notation, a leading `+`, spaces inside the number, repeated signs
// or separators, and empty fractions are rejected. The function never throws.

library;

final RegExp _canonicalNumberPattern = RegExp(r'^-?\d+(?:\.\d+)?$');
final RegExp _germanGroupedNumberPattern = RegExp(
  r'^(-?)(\d{1,3}(?:\.\d{3})+)(?:,(\d+))?$',
);
final RegExp _germanDecimalNumberPattern = RegExp(r'^(-?)(\d+)(?:,(\d+))?$');

/// Parses a German or canonical number into the stored canonical form.
///
/// Outer whitespace is trimmed first. German grouped input such as `1.234,56`
/// becomes `1234.56`, a German comma decimal such as `12,5` becomes `12.5`, and
/// canonical input such as `-0.75` is returned unchanged. A valid German
/// grouping is preferred over a canonical dot decimal, so `1.234` becomes
/// `1234`.
///
/// Returns null for empty or whitespace-only input and for every unsupported
/// form: exponent notation, a leading `+`, internal spaces, repeated signs or
/// separators, and an empty integer or fraction. The result is a string
/// rewrite only; no numeric conversion happens, so leading zeros and the
/// exact fraction digits are kept. The caller keeps [raw] verbatim as display
/// text.
String? parseGermanNumber(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  final RegExpMatch? grouped = _germanGroupedNumberPattern.firstMatch(text);
  if (grouped != null) {
    final String sign = grouped.group(1)!;
    final String integer = grouped.group(2)!.replaceAll('.', '');
    final String? fraction = grouped.group(3);
    return '$sign$integer${fraction == null ? '' : '.$fraction'}';
  }
  final RegExpMatch? german = _germanDecimalNumberPattern.firstMatch(text);
  if (german != null) {
    final String sign = german.group(1)!;
    final String integer = german.group(2)!;
    final String? fraction = german.group(3);
    return '$sign$integer${fraction == null ? '' : '.$fraction'}';
  }
  if (_canonicalNumberPattern.hasMatch(text)) {
    return text;
  }
  return null;
}
