// T316 package-root resolution for host-VM tests.
//
// `flutter test packages/feldexa_recognition/test/foo_test.dart` runs the test
// with the repository root as working directory, while
// `flutter test test/foo_test.dart` runs it inside the package. Tests that scan
// package sources must not resolve relative paths against that working
// directory, otherwise the repository-root invocation reads unrelated files.
//
// The Flutter test runner offers no usable anchor: `Platform.script` reports
// `<working directory>/main.dart`, and `Isolate.packageConfigSync` and
// `Isolate.resolvePackageUri` throw `Unsupported operation` inside
// flutter_tester. The helper therefore walks up from the working directory and
// identifies the package by its pubspec name, which yields the same directory
// from the package itself, from `packages/`, and from the repository root.

import 'dart:io';

/// Repository-relative location of this package.
const String _repositoryPath = 'packages/feldexa_recognition';

/// Pubspec name that identifies this package.
const String _packageName = 'feldexa_recognition';

/// The `feldexa_recognition` package directory.
///
/// Resolved by name, so it is the same directory regardless of the working
/// directory the test was started from.
final Directory packageRoot = _locatePackageRoot();

Directory _locatePackageRoot() {
  Directory directory = Directory.current.absolute;
  while (true) {
    for (final Directory candidate in <Directory>[
      directory,
      Directory('${directory.path}/$_repositoryPath'),
    ]) {
      if (_isPackage(candidate)) {
        return candidate;
      }
    }
    final Directory parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Could not locate $_repositoryPath (pubspec name: $_packageName) from '
        '${Directory.current.absolute.path}.',
      );
    }
    directory = parent;
  }
}

bool _isPackage(Directory directory) {
  final File pubspec = File('${directory.path}/pubspec.yaml');
  return pubspec.existsSync() &&
      pubspec.readAsStringSync().contains('name: $_packageName');
}
