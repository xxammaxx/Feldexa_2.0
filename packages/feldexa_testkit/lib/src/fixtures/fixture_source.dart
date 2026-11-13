// T011 fixture-source contract.
//
// The default testkit library stays free of dart:io so the same sources can be
// used by host tests, package tests, and browser tests. A source is rooted at a
// delivery directory and receives delivery-relative paths such as
// `catalog.json` or `sf-001.pdf`.
//
// Host tests can opt into `package:feldexa_testkit/io.dart`, which provides a
// filesystem source rooted at the canonical, Web, or corpus directory.

import 'dart:convert';
import 'dart:typed_data';

import 'fixture_path.dart';

/// Reads fixture files by delivery-relative path.
abstract interface class FixtureSource {
  /// Reads one file. Implementations must use [validateFixturePath].
  Future<Uint8List> read(String relativePath);

  /// Content-free description used in diagnostics.
  String get description;
}

/// A source read failure, including a missing file.
final class FixtureSourceException implements Exception {
  const FixtureSourceException({
    required this.path,
    required this.message,
    this.cause,
  });

  final String path;
  final String message;
  final Object? cause;

  @override
  String toString() => 'FixtureSourceException($path): $message';
}

/// Validates a delivery-relative path for a [FixtureSource].
///
/// Rejects empty paths, absolute paths, Windows separators, drive/scheme
/// colons, control characters, empty segments, `.`, `..`, and trailing
/// slashes. This is deliberately strict: fixture paths come from the committed
/// catalogue, not from user input, so a traversal-shaped value is a catalogue
/// bug. The [ArgumentError] shape matches the public source API.
String validateFixturePath(String path) {
  try {
    return validatePortableRelativePath(path, label: 'fixture path');
  } on FormatException catch (error) {
    throw ArgumentError.value(path, 'path', error.message);
  }
}

/// An in-memory source, useful for browser tests and parser unit tests.
final class InMemoryFixtureSource implements FixtureSource {
  /// Copies [files] so later mutation of the caller's maps cannot change the
  /// source.
  InMemoryFixtureSource(Map<String, List<int>> files)
    : _files = <String, Uint8List>{
        for (final MapEntry<String, List<int>> entry in files.entries)
          validateFixturePath(entry.key): Uint8List.fromList(entry.value),
      };

  /// Convenience for text fixtures such as `catalog.json`.
  factory InMemoryFixtureSource.fromText(Map<String, String> files) =>
      InMemoryFixtureSource(<String, List<int>>{
        for (final MapEntry<String, String> entry in files.entries)
          entry.key: utf8.encode(entry.value),
      });

  final Map<String, Uint8List> _files;

  /// Whether [relativePath] exists.
  bool contains(String relativePath) =>
      _files.containsKey(validateFixturePath(relativePath));

  /// Delivery-relative paths, sorted.
  List<String> get paths => _files.keys.toList()..sort();

  @override
  Future<Uint8List> read(String relativePath) async {
    final String safePath = validateFixturePath(relativePath);
    final Uint8List? bytes = _files[safePath];
    if (bytes == null) {
      throw FixtureSourceException(
        path: safePath,
        message: 'missing in-memory fixture',
      );
    }
    return Uint8List.fromList(bytes);
  }

  @override
  String get description => 'in-memory (${_files.length} files)';
}
