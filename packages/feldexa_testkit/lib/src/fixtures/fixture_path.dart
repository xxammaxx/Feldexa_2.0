// T011 portable path validation.
//
// The fixture catalogue is committed JSON, but it is still parsed as data: a
// malformed value must never be joined into a filesystem path. Windows treats
// both `/` and `\` as separators, so validating only `/` segments (the original
// T011 bug) let `..\..\outside` escape a checkout root on Windows.
//
// Rule: catalogue paths are portable, relative POSIX-style paths. Reject
// backslashes, drive/scheme colons, control characters, absolute paths, empty
// segments, `.`, `..`, and trailing slashes. Callers may then join the value
// below a trusted root without a platform-dependent re-interpretation.

/// Validates a portable, relative, `/`-separated path.
///
/// Throws [FormatException] with [label] in the message. The value is returned
/// unchanged; there is nothing to normalise because non-`/` separators are
/// rejected rather than translated.
String validatePortableRelativePath(String path, {required String label}) {
  if (path.isEmpty) {
    throw FormatException('$label must not be empty.');
  }
  if (path.contains(r'\')) {
    throw FormatException(
      '$label must use "/" separators; backslashes are not portable.',
    );
  }
  if (path.contains(':')) {
    throw FormatException(
      '$label must not contain ":" (drive letter, URL scheme, or alternate '
      'data stream).',
    );
  }
  for (final int codeUnit in path.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw FormatException('$label must not contain control characters.');
    }
  }
  if (path.startsWith('/')) {
    throw FormatException('$label must be relative, not absolute.');
  }

  final List<String> segments = path.split('/');
  for (final String segment in segments) {
    if (segment == '.' || segment == '..') {
      throw FormatException('$label must not contain "." or ".." segments.');
    }
    if (segment.isEmpty) {
      throw FormatException(
        '$label must not contain empty segments or a trailing slash.',
      );
    }
    if (segment != segment.trim()) {
      throw FormatException(
        '$label must not contain segments with leading or trailing '
        'whitespace.',
      );
    }
    if (segment.endsWith('.')) {
      throw FormatException(
        '$label must not contain segments ending with "."; Windows strips '
        'trailing dots and could reinterpret the segment.',
      );
    }
  }
  return path;
}

/// Validates a site-absolute Web base path such as `/fixtures`.
///
/// Rejects protocol-relative `//host` values, queries, fragments, and every
/// unsafe construct rejected by [validatePortableRelativePath].
String validateWebBasePath(String value, {required String label}) {
  if (!value.startsWith('/')) {
    throw FormatException('$label must start with "/".');
  }
  if (value.startsWith('//')) {
    throw FormatException('$label must not be a protocol-relative URL.');
  }
  if (value.contains('?') || value.contains('#')) {
    throw FormatException('$label must not contain a query or fragment.');
  }
  validatePortableRelativePath(value.substring(1), label: label);
  return value;
}
