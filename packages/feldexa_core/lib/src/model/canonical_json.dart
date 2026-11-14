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

/// Base for immutable JSON model objects that retain unknown same-schema
/// fields.
///
/// `data-model.md` §6 requires unknown JSON fields to survive a read/write
/// round within one schema version, and `data-model.md` line 5 requires every
/// entity to be immutable-by-convention. [unknownFields] therefore stores a
/// recursively deep, unmodifiable JSON copy: mutating the input map after
/// construction or mutating a returned JSON tree can never change this object
/// or a later canonical digest.
///
/// [unknownFields] stores exactly the entries a typed decoder did not consume;
/// [toJsonWithUnknown] merges them beneath the modeled keys so a modeled value
/// always wins. Unknown fields are opaque forward-compatibility data: they are
/// not interpreted, and the concrete types deliberately keep them out of
/// `==`/`hashCode` (compare canonical JSON when extension data matters). A
/// higher `schemaVersion` is rejected before this layer, so preservation never
/// crosses a schema boundary.
abstract class JsonObject {
  /// Creates an object with optional opaque [unknownFields].
  ///
  /// Core constructors store [unknownFields] through
  /// [freezeUnknownJsonFields]; subclasses outside this library must do the
  /// same to keep the immutability invariant.
  const JsonObject({this.unknownFields = const <String, Object?>{}});

  /// Opaque same-schema JSON entries not consumed by the typed decoder.
  ///
  /// The map and every nested map/list are unmodifiable.
  final Map<String, Object?> unknownFields;

  /// Merges [unknownFields] beneath the modeled [known] keys.
  ///
  /// The unknown tree is frozen again so the returned JSON shares no mutable
  /// nested state with this object.
  Map<String, Object?> toJsonWithUnknown(Map<String, Object?> known) {
    return mergeUnknownJsonFields(known, unknownFields);
  }
}

/// Captures the entries of [json] whose keys are not in [knownKeys].
///
/// The result is recursively deep-copied into unmodifiable maps and lists, so
/// later mutation of [json] or of any of its nested values cannot change the
/// captured object. Unknown keys are opaque, so the caller must include every
/// key its decoder consumed (including deliberately ignored derived keys such
/// as `renderCacheKey`) in [knownKeys].
///
/// Throws [ArgumentError] when an unknown value is not a finite JSON value or
/// the tree contains a cycle. The error never echoes a value.
Map<String, Object?> unknownJsonFields(
  Map<String, Object?> json,
  Set<String> knownKeys,
) {
  final Map<String, Object?> result = <String, Object?>{};
  for (final MapEntry<String, Object?> entry in json.entries) {
    if (!knownKeys.contains(entry.key)) {
      result[entry.key] = entry.value;
    }
  }
  return freezeUnknownJsonFields(result);
}

/// Returns a recursively deep, unmodifiable JSON copy of [fields].
///
/// Maps and lists are rebuilt at every depth and wrapped unmodifiable; scalar
/// JSON values are immutable and shared. Only string-keyed maps, lists,
/// strings, booleans, finite numbers, and null are accepted. Throws
/// [ArgumentError] for any other value, a non-string map key, or a cycle. The
/// error never echoes a value.
Map<String, Object?> freezeUnknownJsonFields(Map<String, Object?> fields) {
  return _freezeUnknownMap(fields, HashSet<Object>.identity());
}

Map<String, Object?> _freezeUnknownMap(
  Map<Object?, Object?> fields,
  Set<Object> ancestors,
) {
  if (!ancestors.add(fields)) {
    throw ArgumentError('unknown JSON fields must not contain cycles');
  }
  final Map<String, Object?> result = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in fields.entries) {
    final Object? key = entry.key;
    if (key is! String) {
      throw ArgumentError('unknown JSON object keys must be strings');
    }
    result[key] = _freezeUnknownValue(entry.value, ancestors);
  }
  ancestors.remove(fields);
  return Map<String, Object?>.unmodifiable(result);
}

Object? _freezeUnknownValue(Object? value, Set<Object> ancestors) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double) {
    if (!value.isFinite) {
      throw ArgumentError('unknown JSON numbers must be finite');
    }
    return value;
  }
  if (value is List<Object?>) {
    if (!ancestors.add(value)) {
      throw ArgumentError('unknown JSON fields must not contain cycles');
    }
    final List<Object?> result = <Object?>[
      for (final Object? item in value) _freezeUnknownValue(item, ancestors),
    ];
    ancestors.remove(value);
    return List<Object?>.unmodifiable(result);
  }
  if (value is Map<Object?, Object?>) {
    return _freezeUnknownMap(value, ancestors);
  }
  throw ArgumentError('unknown JSON fields must contain only JSON values');
}

/// Merges opaque [unknownFields] beneath [known] modeled fields.
///
/// Modeled keys always win; an unknown entry that happens to reuse a modeled
/// key can never override validated model state. The unknown tree is frozen
/// here as well, so the merged JSON can never alias mutable extension state.
/// The canonical encoder sorts the merged keys and the nested unknown values.
Map<String, Object?> mergeUnknownJsonFields(
  Map<String, Object?> known,
  Map<String, Object?> unknownFields,
) {
  final Map<String, Object?> frozen = freezeUnknownJsonFields(unknownFields);
  if (frozen.isEmpty) {
    return known;
  }
  return <String, Object?>{...frozen, ...known};
}
