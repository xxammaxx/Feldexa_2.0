// Feldexa core date parsing (T081).
//
// Owner: `packages/feldexa_core/lib/src/validation/date.dart`.
//
// This is the single source for the German and canonical date grammar that
// T019 reclassification already pinned. Reclassification delegates here, and
// later editors can validate input against the same rules.
//
// Sources:
//   * `spec.md` FR-107–FR-110 — dates are entered as German `d.m.yyyy` and
//     stored canonically;
//   * `spec.md` SC-022 — a real calendar date is required;
//   * `contracts/error-catalog.de.md` DATE-001 (malformed) and DATE-002
//     (impossible calendar date);
//   * `data-model.md` §3.6 — the canonical `YYYY-MM-DD` date value;
//   * constitution Principles II, III, V, VI, and X — pure, platform-
//     independent, deterministic, content-safe validation.
//
// Accepted forms, after trimming outer whitespace:
//   * German `d.m.yyyy` or `dd.mm.yyyy`: day and month are one or two digits,
//     the year is exactly four digits (`^(\d{1,2})\.(\d{1,2})\.(\d{4})$`);
//   * canonical `yyyy-mm-dd`: exactly four, two, and two digits
//     (`^(\d{4})-(\d{2})-(\d{2})$`), the form emitted by date → text.
//
// Anything else, including empty and whitespace-only input, is malformed and
// returns `DATE-001`. A structurally valid shape whose day, month, and year do
// not survive a `DateTime.utc` round-trip (29 February in a non-leap year,
// 31 April, month 0 or 13, day 0 or 32) returns `DATE-002`. Success returns the
// zero-padded canonical `yyyy-mm-dd`. The function never throws.
//
// German user messages stay in the catalog and ARB; this module returns only
// the machine code. The caller keeps the entered text verbatim as display
// content.

library;

final RegExp _germanDatePattern = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$');
final RegExp _canonicalDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// The outcome of parsing one date string.
///
/// A success carries the canonical `yyyy-mm-dd` in [canonical] and a null
/// [errorCode]; a failure carries null [canonical] and `DATE-001` or `DATE-002`
/// in [errorCode]. The result never contains user content beyond the canonical
/// date and is safe for diagnostics.
final class DateParseResult {
  /// A successful parse; [canonical] is the zero-padded `yyyy-mm-dd`.
  const DateParseResult.success(String this.canonical) : errorCode = null;

  /// A failed parse; [errorCode] is `DATE-001` or `DATE-002`.
  const DateParseResult.failure(String this.errorCode) : canonical = null;

  /// The canonical `yyyy-mm-dd`, or null on failure.
  final String? canonical;

  /// The catalog code `DATE-001`/`DATE-002`, or null on success.
  final String? errorCode;

  /// Whether parsing produced a canonical date.
  bool get isSuccess => errorCode == null;
}

/// Parses a German `d.m.yyyy` or canonical `yyyy-mm-dd` date.
///
/// Outer whitespace is trimmed first. The German form accepts one or two digits
/// for day and month and exactly four for the year; the canonical form accepts
/// exactly four, two, and two digits. On success the result is the zero-padded
/// canonical `yyyy-mm-dd`, so `1.1.2025` becomes `2025-01-01`.
///
/// Returns `DATE-001` for every malformed or empty input and `DATE-002` when
/// the shape is valid but the values are not a real calendar date (29 February
/// in a non-leap year, 31 April, month 0 or 13, day 0 or 32). The function is a
/// pure string rewrite plus validation and never throws.
DateParseResult parseGermanDate(String raw) {
  final String text = raw.trim();
  final RegExpMatch? german = _germanDatePattern.firstMatch(text);
  final RegExpMatch? canonical = _canonicalDatePattern.firstMatch(text);
  final int year;
  final int month;
  final int day;
  if (german != null) {
    day = int.parse(german.group(1)!);
    month = int.parse(german.group(2)!);
    year = int.parse(german.group(3)!);
  } else if (canonical != null) {
    year = int.parse(canonical.group(1)!);
    month = int.parse(canonical.group(2)!);
    day = int.parse(canonical.group(3)!);
  } else {
    return const DateParseResult.failure('DATE-001');
  }
  final DateTime date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return const DateParseResult.failure('DATE-002');
  }
  return DateParseResult.success(
    '${_padDatePart(year, 4)}-${_padDatePart(month, 2)}-'
    '${_padDatePart(day, 2)}',
  );
}

String _padDatePart(int value, int width) {
  return value.toString().padLeft(width, '0');
}
