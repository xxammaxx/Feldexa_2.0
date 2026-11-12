// T011 host-only fixture sources.
//
// Import this library from host VM tests:
//   import 'package:feldexa_testkit/io.dart';
//
// The default `package:feldexa_testkit/feldexa_testkit.dart` barrel stays free
// of dart:io so browser tests can import the catalogue model and fault hooks.

import 'dart:io';
import 'dart:typed_data';

import 'src/fixtures/fixture_catalog.dart';
import 'src/fixtures/fixture_loader.dart';
import 'src/fixtures/fixture_source.dart';

/// Reads fixture files from a directory on the host filesystem.
final class FileFixtureSource implements FixtureSource {
  FileFixtureSource(String rootDirectory)
    : rootDirectory = Directory(rootDirectory).absolute.path;

  /// Absolute directory that [read] resolves relative paths against.
  final String rootDirectory;

  @override
  Future<Uint8List> read(String relativePath) async {
    final String safePath = validateFixturePath(relativePath);
    final File file = File('$rootDirectory/$safePath');
    if (!await file.exists()) {
      throw FixtureSourceException(
        path: safePath,
        message: 'file not found under $rootDirectory',
      );
    }
    try {
      return await file.readAsBytes();
    } on FileSystemException catch (error) {
      throw FixtureSourceException(
        path: safePath,
        message: error.message,
        cause: error,
      );
    }
  }

  @override
  String get description => 'filesystem:$rootDirectory';
}

/// Locates a Feldexa checkout and binds sources to its declared fixture paths.
///
/// The catalogue remains the source of truth for each delivery directory; the
/// only hard-coded bootstrap path is the canonical catalogue location.
final class FixtureCheckout {
  const FixtureCheckout(this.rootDirectory);

  /// Walks up from [fromDirectory] (default: the process working directory)
  /// until it finds the Feldexa workspace root.
  factory FixtureCheckout.locate({String? fromDirectory}) {
    Directory directory = Directory(fromDirectory ?? Directory.current.path)
        .absolute;
    while (true) {
      final File pubspec = File('${directory.path}/pubspec.yaml');
      if (pubspec.existsSync()) {
        final String source = pubspec.readAsStringSync();
        if (source.contains('name: feldexa_workspace')) {
          return FixtureCheckout(directory.path);
        }
      }
      final Directory parent = directory.parent;
      if (parent.path == directory.path) {
        throw StateError(
          'Could not locate the Feldexa workspace root from '
          '${Directory(fromDirectory ?? Directory.current.path).absolute.path}.',
        );
      }
      directory = parent;
    }
  }

  /// Absolute checkout root.
  final String rootDirectory;

  /// The canonical development fixture directory from T009.
  String get canonicalDevDirectory =>
      '$rootDirectory/apps/feldexa_app/assets/fixtures';

  /// Source for one delivery target.
  FileFixtureSource sourceFor(
    FixtureCatalog catalog,
    FixtureDeliveryTarget target,
  ) =>
      FileFixtureSource('$rootDirectory/${target.directory(catalog.delivery)}');

  /// Opens the canonical loader, which validates `catalog.json`.
  Future<FixtureLoader> openLoader({FixtureDigest? digest}) =>
      FixtureLoader.open(
        FileFixtureSource(canonicalDevDirectory),
        digest: digest,
      );

  @override
  String toString() => 'FixtureCheckout($rootDirectory)';
}
