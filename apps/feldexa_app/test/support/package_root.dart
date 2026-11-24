// T316 package-root resolution for host-VM tests.
//
// `flutter test apps/feldexa_app/test/foo_test.dart` runs the test with the
// repository root as working directory, while `flutter test test/foo_test.dart`
// runs it inside the app package. Tests that scan package sources must not
// resolve relative paths against that working directory, otherwise the
// repository-root invocation reads unrelated files.
//
// The Flutter test runner offers no usable anchor: `Platform.script` reports
// `<working directory>/main.dart`, and `Isolate.packageConfigSync` and
// `Isolate.resolvePackageUri` throw `Unsupported operation` inside
// flutter_tester. The helper therefore walks up from the working directory and
// identifies the package by its pubspec name, which yields the same directory
// from the package itself, from `apps/`, and from the repository root.

import 'dart:io';

/// Repository-relative location of this package.
const String _repositoryPath = 'apps/feldexa_app';

/// Pubspec name that identifies this package.
const String _packageName = 'feldexa_app';

/// Pubspec name that identifies the workspace root.
const String _workspaceName = 'feldexa_workspace';

/// The `feldexa_app` package directory.
///
/// Resolved by name, so it is the same directory regardless of the working
/// directory the test was started from.
final Directory packageRoot = _locatePackageRoot();

/// The Feldexa workspace root that contains [packageRoot].
final Directory repositoryRoot = _locateRepositoryRoot();

Directory _locateRepositoryRoot() {
  Directory directory = packageRoot.parent;
  while (true) {
    final File pubspec = File('${directory.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: $_workspaceName')) {
      return directory;
    }
    final Directory parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Could not locate the workspace root ($_workspaceName) above '
        '${packageRoot.path}.',
      );
    }
    directory = parent;
  }
}

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
