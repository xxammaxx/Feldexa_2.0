// Shared T013 validation helpers for port-local DTOs.
//
// This file is internal to `feldexa_ports` and is deliberately not exported by
// `package:feldexa_ports/feldexa_ports.dart`. It contains no canonical model
// type and no second DTO: the helpers only validate the request/result values
// that `contracts/ports.md` §2 and §2.10 assign to T013.
//
// Every validator runs at runtime, not only inside assertions, and every error
// message is a fixed rule description. A rejected value is never echoed,
// because port DTOs can carry document content, file names, or paths, and an
// exception is a common leak channel.

/// UUIDv4 shape shared by the canonical core model and the port DTOs.
final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// Lowercase SHA-256 shape from `contracts/storage-format.md`.
final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

/// Stable German catalog key shape, for example `IMP-006` or `SAVE-002`.
final RegExp _catalogCodePattern = RegExp(r'^[A-Z]{2,6}-[0-9]{3}$');

/// Control characters are never valid in titles, hints, or feature tokens.
final RegExp _controlPattern = RegExp(r'[\x00-\x1F\x7F]');

/// A compact BCP-47-like language tag, for example `de` or `de-DE`.
final RegExp _languageTagPattern = RegExp(
  r'^[A-Za-z]{2,8}([-_][A-Za-z0-9]{2,8})*$',
);

/// Validates a non-empty lowercase UUIDv4.
String requireUuidV4(String value, String name) {
  if (!_uuidV4Pattern.hasMatch(value)) {
    throw ArgumentError('$name must be a lowercase UUIDv4');
  }
  return value;
}

/// Validates an optional lowercase UUIDv4.
String? optionalUuidV4(String? value, String name) {
  if (value == null) {
    return null;
  }
  return requireUuidV4(value, name);
}

/// Validates a 64-character lowercase SHA-256 hex digest.
String requireSha256(String value, String name) {
  if (!_sha256Pattern.hasMatch(value)) {
    throw ArgumentError('$name must be 64 lowercase hexadecimal characters');
  }
  return value;
}

/// Validates an optional 64-character lowercase SHA-256 hex digest.
String? optionalSha256(String? value, String name) {
  if (value == null) {
    return null;
  }
  return requireSha256(value, name);
}

/// Validates a stable catalog key such as `SAVE-002`.
String requireCatalogCode(String value, String name) {
  if (!_catalogCodePattern.hasMatch(value)) {
    throw ArgumentError('$name must be a stable catalog key such as SAVE-002');
  }
  return value;
}

/// Validates a UTC timestamp.
DateTime requireUtc(DateTime value, String name) {
  if (!value.isUtc) {
    throw ArgumentError('$name must be UTC');
  }
  return value;
}

/// Validates an optional UTC timestamp.
DateTime? optionalUtc(DateTime? value, String name) {
  if (value == null) {
    return null;
  }
  return requireUtc(value, name);
}

/// Trims and validates a user-visible title.
///
/// A title is 1–`maxLength` characters after trimming and contains no control
/// characters. The returned value is the trimmed title.
String requireTitle(
  String value, {
  String name = 'title',
  int maxLength = 200,
}) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty ||
      trimmed.length > maxLength ||
      _controlPattern.hasMatch(trimmed)) {
    throw ArgumentError(
      '$name must be 1-$maxLength characters without control characters',
    );
  }
  return trimmed;
}

/// Trims and validates an optional user-visible display name.
///
/// A display name is a file name, never a path: path separators and control
/// characters are rejected. The returned value is the trimmed name.
String? optionalDisplayName(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  if (trimmed.isEmpty ||
      trimmed.length > _maxDisplayNameLength ||
      _controlPattern.hasMatch(trimmed) ||
      trimmed.contains('/') ||
      trimmed.contains(r'\')) {
    throw ArgumentError('displayName must be a short file name without a path');
  }
  return trimmed;
}

/// Validates a positive integer count.
int requirePositiveInt(int value, String name) {
  if (value < 1) {
    throw ArgumentError('$name must be at least 1');
  }
  return value;
}

/// Validates a non-negative integer count.
int requireNonNegativeInt(int value, String name) {
  if (value < 0) {
    throw ArgumentError('$name must be at least 0');
  }
  return value;
}

/// Validates a finite, strictly positive double.
double requireFinitePositive(double value, String name) {
  if (!value.isFinite || value <= 0) {
    throw ArgumentError('$name must be a finite, strictly positive number');
  }
  return value;
}

/// Validates a finite double in the inclusive 0–1 interval.
double requireUnitInterval(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError('$name must be a finite number between 0 and 1');
  }
  return value;
}

/// Validates a compact language tag such as `de` or `de-DE`.
String requireLanguageTag(String value, String name) {
  if (!_languageTagPattern.hasMatch(value)) {
    throw ArgumentError('$name must be a compact language tag such as de');
  }
  return value;
}

/// Validates an optional user-visible location hint.
///
/// The hint is German display text, never an internal path, URI, or file name,
/// so path separators, control characters, and `content://`/`file://` schemes
/// are rejected. The returned value is the trimmed hint.
String? optionalLocationHint(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  final String lower = trimmed.toLowerCase();
  if (trimmed.isEmpty ||
      trimmed.length > _maxLocationHintLength ||
      _controlPattern.hasMatch(trimmed) ||
      trimmed.contains('/') ||
      trimmed.contains(r'\') ||
      lower.startsWith('content:') ||
      lower.startsWith('file:')) {
    throw ArgumentError(
      'userVisibleLocationHint must be a short display hint without a path',
    );
  }
  return trimmed;
}

/// Validates a short non-empty machine or feature token.
String requireShortToken(String value, String name, {int maxLength = 64}) {
  if (value.isEmpty ||
      value.length > maxLength ||
      _controlPattern.hasMatch(value)) {
    throw ArgumentError(
      '$name must be a short token without control characters',
    );
  }
  return value;
}

/// Returns an unmodifiable copy of a list.
List<T> freezeList<T>(Iterable<T> values) {
  return List<T>.unmodifiable(values);
}

/// Returns an unmodifiable copy of a map.
Map<String, T> freezeMap<T>(Map<String, T> values) {
  return Map<String, T>.unmodifiable(values);
}

const int _maxDisplayNameLength = 255;
const int _maxLocationHintLength = 200;
