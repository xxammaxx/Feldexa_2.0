// Feldexa canonical JSON encoding (T017).
//
// Normative sources:
//   * `data-model.md` §6 — canonical JSON is sorted object keys, UTF-8, no
//     insignificant whitespace, ISO-8601 UTC timestamps, and SHA-256 over the
//     canonical bytes;
//   * `contracts/storage-format.md` §2.4 — sorted keys, UTF-8, no whitespace,
//     UTC ISO-8601 with milliseconds, numbers without trailing zeros;
//   * `data-model.md` §7 — no map iteration order may affect serialized output.
//
// The encoder is deliberately a pure JSON encoder: it accepts only JSON values
// (`null`, `bool`, `num`, `String`, `List`, and string-keyed `Map`). Model
// timestamps are already serialized by the owning entity, so a `DateTime` is
// rejected here instead of being silently coerced.
//
// [canonicalJsonValue] returns a JSON tree whose maps are key-sorted and whose
// integral doubles are normalized to integers (`1.0` -> `1`, `-0.0` -> `0`).
// [canonicalJsonEncode] then emits that tree compactly with `dart:convert`,
// whose string escaping is the usual JSON escaping and whose output preserves
// non-ASCII characters. The result is deterministic for a given value tree and
// can be hashed byte-for-byte through [canonicalJsonBytes].
library;

import 'dart:collection';
import 'dart:convert';

/// Integral doubles up to this magnitude convert to `int` without losing
/// precision. Larger integral doubles stay doubles so canonicalization never
/// depends on platform-specific integer width.
const double _maxExactIntegerDouble = 9007199254740992.0;

/// Encodes [value] as canonical JSON.
///
/// Throws [ArgumentError] for a non-finite number, a non-string map key, an
/// unsupported value type (for example `DateTime` or `Set`), or a cyclic
/// object graph. The error never echoes a value.
String canonicalJsonEncode(Object? value) {
  return jsonEncode(canonicalJsonValue(value));
}

/// The UTF-8 bytes of [canonicalJsonEncode] for [value].
///
/// This is the byte sequence over which `data-model.md` §6 computes SHA-256.
List<int> canonicalJsonBytes(Object? value) {
  return utf8.encode(canonicalJsonEncode(value));
}

/// Returns a canonical JSON tree for [value].
///
/// Maps are rebuilt with keys in ascending [String.compareTo] order, lists keep
/// their order, and integral `double` values become `int` values. The input is
/// never mutated.
///
/// Throws [ArgumentError] under the same conditions as [canonicalJsonEncode].
Object? canonicalJsonValue(Object? value) {
  return _canonicalize(value, HashSet<Object>.identity());
}

Object? _canonicalize(Object? value, Set<Object> ancestors) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double) {
    if (!value.isFinite) {
      throw ArgumentError('canonical JSON numbers must be finite');
    }
    if (value == 0) {
      // Normalize negative zero so the same tree always hashes identically.
      return 0;
    }
    if (value == value.truncateToDouble() &&
        value.abs() <= _maxExactIntegerDouble) {
      return value.toInt();
    }
    return value;
  }
  if (value is List<Object?>) {
    if (!ancestors.add(value)) {
      throw ArgumentError('canonical JSON must not contain cycles');
    }
    final List<Object?> result = <Object?>[
      for (final Object? item in value) _canonicalize(item, ancestors),
    ];
    ancestors.remove(value);
    return result;
  }
  if (value is Map<Object?, Object?>) {
    if (!ancestors.add(value)) {
      throw ArgumentError('canonical JSON must not contain cycles');
    }
    final List<String> keys = <String>[];
    for (final Object? key in value.keys) {
      if (key is! String) {
        throw ArgumentError('canonical JSON object keys must be strings');
      }
      keys.add(key);
    }
    keys.sort();
    final Map<String, Object?> result = <String, Object?>{};
    for (final String key in keys) {
      result[key] = _canonicalize(value[key], ancestors);
    }
    ancestors.remove(value);
    return result;
  }
  throw ArgumentError('canonical JSON does not support ${value.runtimeType}');
}

/// Serializes [value] to the canonical UTC timestamp form.
///
/// The value must be UTC (`storage-format.md` §2.4); microseconds are truncated
/// to the millisecond precision the contract stores. Throws [ArgumentError] for
/// a local timestamp.
String canonicalUtcTimestamp(DateTime value) {
  if (!value.isUtc) {
    throw ArgumentError('timestamp must be UTC');
  }
  return DateTime.fromMillisecondsSinceEpoch(
    value.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}

/// Parses an ISO-8601 timestamp that must resolve to UTC.
///
/// Accepts the millisecond form this encoder writes and other valid ISO-8601
/// UTC spellings; the caller always re-serializes through
/// [canonicalUtcTimestamp]. Throws [FormatException] for a non-string,
/// unparseable, or local timestamp. [name] names the JSON field in the error
/// without echoing the rejected value.
DateTime parseCanonicalUtcTimestamp(
  Object? value, {
  String name = 'timestamp',
}) {
  if (value is! String) {
    throw FormatException(
      'JSON field "$name" must be an ISO-8601 UTC timestamp',
    );
  }
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException(
      'JSON field "$name" must be an ISO-8601 UTC timestamp',
    );
  }
  return parsed;
}
