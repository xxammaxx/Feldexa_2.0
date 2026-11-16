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
final class IoStartupSweepFileSystem implements StartupSweepFileSystem {
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
  /// Directories and symbolic links are reported as entries so the sweep can
  /// classify them; deletion of a directory or link is refused below. A
  /// missing directory yields an empty list.
  @override
  Future<List<StartupSweepEntry>> listExportArtifacts() async {
    final Directory root = exportDirectory;
    if (!await root.exists()) {
      return const <StartupSweepEntry>[];
    }
    final List<StartupSweepEntry> entries = <StartupSweepEntry>[];
    await for (final FileSystemEntity entity in root.list(
      recursive: false,
      followLinks: false,
    )) {
      final FileSystemEntityType type = await FileSystemEntity.type(
        entity.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.notFound) {
        continue;
      }
      final String name = entity.path.split(Platform.pathSeparator).last;
      if (name.isEmpty || name == '.' || name == '..') {
        continue;
      }
      final FileStat stat;
      try {
        stat = await entity.stat();
      } on FileSystemException {
        // A disappearing or broken entry is not a stable sweep candidate.
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
        // The sweep entry rejects a name that is not one safe path segment.
        // Skipping it is safer than inventing a path.
        continue;
      }
    }
    return List<StartupSweepEntry>.unmodifiable(entries);
  }

  /// Deletes one previously enumerated file inside [exportDirectory].
  ///
  /// A directory, symbolic link, or any non-regular entry is refused with the
  /// canonical `PLT-002` path/operation guard. A file that is already gone is
  /// treated as a successful no-op.
  @override
  Future<void> deleteExportArtifact(StartupSweepEntry entry) async {
    final Directory root = exportDirectory.absolute;
    final String path = '${root.path}${Platform.pathSeparator}${entry.name}';
    final String parent = File(path).parent.absolute.path;
    if (parent != root.path) {
      throw SecurityException();
    }
    final FileSystemEntityType type = await FileSystemEntity.type(
      path,
      followLinks: false,
    );
    switch (type) {
      case FileSystemEntityType.file:
        await File(path).delete();
      case FileSystemEntityType.notFound:
        return;
      case FileSystemEntityType.directory:
      case FileSystemEntityType.link:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        throw SecurityException();
    }
  }
}
