// T031 production `dart:io` filesystem adapter.
//
// Owner: `apps/feldexa_app/lib/bootstrap/startup_sweep_io.dart` (T031).
// Selected only through `startup_sweep_app.dart` / its Android branch; the Web
// build never resolves this file.
//
// What this adapter can and cannot reach (T031-B1 finding):
//   * It CAN reach the app-private cache directory. On Android,
//     `Directory.systemTemp` is the app's `cacheDir`, and
//     `contracts/storage-format.md` §3.6 places export artifacts at
//     `cacheDir/feldexa_exports/<artifactId>.pdf[.tmp]`.
//   * It CANNOT safely address `filesDir/feldexa/tmp`. That staging directory
//     is owned by the merged native T026 recovery, which has the aggregate
//     lock, the durable directory handles, and the native fsync semantics.
//     This adapter therefore reports no staging entries and refuses a
//     `deleteTemporaryEntry` call. It does not re-implement, duplicate, or
//     guess native recovery.
//
// The adapter only enumerates its dedicated export directory and only deletes
// one previously enumerated single-segment name inside that directory. It
// never follows a symbolic link, never recurses into a directory, and never
// accepts a caller-supplied path.

import 'dart:io';

import 'package:feldexa_ports/feldexa_ports.dart';

import 'startup_sweep.dart';

/// Production filesystem adapter for the app-private export-preview cache.
final class IoStartupSweepFileSystem
    implements StartupSweepFileSystem, StartupSweepInspectionReporter {
  /// Creates the adapter for [exportDirectory].
  ///
  /// When omitted, the dedicated directory is
  /// `<Directory.systemTemp>/feldexa_exports`, which is the app cache directory
  /// on Android. The directory is not created here: the export writer creates
  /// it, and a missing directory simply means there is nothing to sweep.
  IoStartupSweepFileSystem({Directory? exportDirectory})
    : exportDirectory = exportDirectory ?? _defaultExportDirectory();

  /// The single directory this adapter enumerates and deletes inside.
  final Directory exportDirectory;

  int _inspectionFailures = 0;

  static Directory _defaultExportDirectory() {
    return Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}feldexa_exports',
    );
  }

  /// Returns no entries.
  ///
  /// `filesDir/feldexa/tmp` is owned by native T026; the Dart layer must not
  /// pretend to see or sweep it. This is deliberately empty, not an error.
  @override
  Future<List<StartupSweepEntry>> listTemporaryEntries() async {
    return const <StartupSweepEntry>[];
  }

  /// Refuses a staging deletion.
  ///
  /// Native T026 owns staging. A caller reaching this method is a programming
  /// error, so it fails closed with the canonical `PLT-001` capability error
  /// rather than deleting an object the Dart layer cannot safely identify.
  @override
  Future<void> deleteTemporaryEntry(StartupSweepEntry entry) async {
    throw UnsupportedOperationException();
  }

  /// Lists one level of the dedicated export directory.
  ///
  /// A symlinked root is refused before enumeration. Directories and symbolic
  /// links are reported as entries so the sweep can classify them; deletion of
  /// a directory or link is refused below. A missing directory yields an empty
  /// list. Rejected names and uninspectable entries are counted as redacted
  /// inspection failures and never expose their name.
  @override
  Future<List<StartupSweepEntry>> listExportArtifacts() async {
    _inspectionFailures = 0;
    final Directory root = exportDirectory;
    final FileSystemEntityType rootType;
    try {
      rootType = await FileSystemEntity.type(root.path, followLinks: false);
    } on FileSystemException {
      _inspectionFailures++;
      return const <StartupSweepEntry>[];
    }
    if (rootType == FileSystemEntityType.link) {
      // T031 A-2: a symlinked export root is an escape boundary; refuse it.
      throw SecurityException();
    }
    if (rootType == FileSystemEntityType.notFound) {
      return const <StartupSweepEntry>[];
    }
    if (rootType != FileSystemEntityType.directory) {
      // A file at the dedicated root is not a sweepable export directory.
      _inspectionFailures++;
      return const <StartupSweepEntry>[];
    }
    final List<StartupSweepEntry> entries = <StartupSweepEntry>[];
    try {
      await for (final FileSystemEntity entity in root.list(
        recursive: false,
        followLinks: false,
      )) {
        final FileSystemEntityType type;
        try {
          type = await FileSystemEntity.type(entity.path, followLinks: false);
        } on FileSystemException {
          _inspectionFailures++;
          continue;
        }
        if (type == FileSystemEntityType.notFound) {
          _inspectionFailures++;
          continue;
        }
        if (type == FileSystemEntityType.link) {
          // A symlink is never a safe export artifact. Count it as a redacted
          // inspection failure; never follow it and never return it for
          // deletion.
          _inspectionFailures++;
          continue;
        }
        final String name = entity.path.split(Platform.pathSeparator).last;
        if (name.isEmpty || name == '.' || name == '..') {
          _inspectionFailures++;
          continue;
        }
        final FileStat stat;
        try {
          stat = await entity.stat();
        } on FileSystemException {
          // Uninspectable (for example a broken symlink): keep it untouched
          // and report a redacted cleanup failure.
          _inspectionFailures++;
          continue;
        }
        try {
          entries.add(
            StartupSweepEntry(
              name: name,
              lastModifiedUtc: stat.modified.toUtc(),
              isDirectory: type == FileSystemEntityType.directory,
            ),
          );
        } on ArgumentError {
          // The entry rejects a name that is not one safe path segment; the
          // name is never surfaced, only counted.
          _inspectionFailures++;
          continue;
        }
      }
    } on FileSystemException {
      _inspectionFailures++;
    }
    return List<StartupSweepEntry>.unmodifiable(entries);
  }

  /// Returns and resets the redacted rejected/uninspectable entry count.
  @override
  int takeInspectionFailures() {
    final int value = _inspectionFailures;
    _inspectionFailures = 0;
    return value;
  }

  /// Deletes one previously enumerated regular file inside [exportDirectory].
  ///
  /// The root itself and every entry are resolved before deletion. A symlinked
  /// root, a directory, a symbolic link, or any real path outside the resolved
  /// real root is refused with canonical `PLT-002`. A file that is already
  /// gone is treated as a successful no-op.
  @override
  Future<void> deleteExportArtifact(StartupSweepEntry entry) async {
    final Directory root = exportDirectory.absolute;
    final FileSystemEntityType rootType;
    try {
      rootType = await FileSystemEntity.type(root.path, followLinks: false);
    } on FileSystemException {
      throw SecurityException();
    }
    if (rootType == FileSystemEntityType.link) {
      throw SecurityException();
    }
    if (rootType == FileSystemEntityType.notFound) {
      return;
    }
    if (rootType != FileSystemEntityType.directory) {
      throw SecurityException();
    }
    final String rootReal;
    try {
      rootReal = await root.resolveSymbolicLinks();
    } on FileSystemException {
      throw SecurityException();
    }
    final String path = '${root.path}${Platform.pathSeparator}${entry.name}';
    final FileSystemEntityType type;
    try {
      type = await FileSystemEntity.type(path, followLinks: false);
    } on FileSystemException {
      throw SecurityException();
    }
    switch (type) {
      case FileSystemEntityType.notFound:
        return;
      case FileSystemEntityType.file:
        break;
      case FileSystemEntityType.directory:
      case FileSystemEntityType.link:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        throw SecurityException();
    }
    final String entryReal;
    try {
      entryReal = await File(path).resolveSymbolicLinks();
    } on FileSystemException {
      throw SecurityException();
    }
    final String expected = '$rootReal${Platform.pathSeparator}${entry.name}';
    if (entryReal != expected) {
      throw SecurityException();
    }
    await File(path).delete();
  }
}
