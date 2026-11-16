// T031 Web production startup-sweep composition.
//
// Owner: `apps/feldexa_app/lib/bootstrap/startup_sweep_app_web.dart` (T031).
// Selected by `startup_sweep_app.dart` for the Web build and for unknown
// compile targets. It imports no `dart:io`, no adapter package, and no Android
// runtime.
//
// This app shell has no production encrypted-store composition on the Web (the
// app package deliberately does not depend on the simulated adapter package),
// so the sweep runs with `store: null`. It still performs the Web-safe
// directory pass, which has no persistent app-private directory to enumerate,
// and it never invents aggregate state.

import 'package:feldexa_ports/feldexa_ports.dart';

import 'startup_sweep.dart';
import 'startup_sweep_bootstrap.dart';

/// Creates the Web startup sweep.
StartupSweep? createAppStartupSweep() {
  return StartupSweep(
    store: null,
    clock: const StartupSweepWallClock(),
    files: const _NoopStartupSweepFileSystem(),
  );
}

/// A fail-closed Web filesystem: there is no persistent app-private sweep
/// directory in this shell, and a delete call is a programming error.
final class _NoopStartupSweepFileSystem implements StartupSweepFileSystem {
  const _NoopStartupSweepFileSystem();

  @override
  Future<List<StartupSweepEntry>> listTemporaryEntries() async {
    return const <StartupSweepEntry>[];
  }

  @override
  Future<void> deleteTemporaryEntry(StartupSweepEntry entry) async {
    throw UnsupportedOperationException();
  }

  @override
  Future<List<StartupSweepEntry>> listExportArtifacts() async {
    return const <StartupSweepEntry>[];
  }

  @override
  Future<void> deleteExportArtifact(StartupSweepEntry entry) async {
    throw UnsupportedOperationException();
  }
}
