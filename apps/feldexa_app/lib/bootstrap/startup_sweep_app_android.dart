// T031 Android/Dart production startup-sweep composition.
//
// Owner: `apps/feldexa_app/lib/bootstrap/startup_sweep_app_android.dart`
// (T031). Selected only by `startup_sweep_app.dart` on `dart:library.io`
// targets; the Web build never resolves this file.
//
// The startup path needs the real T027 store and the native T026 recovery. It
// deliberately composes the full `AndroidPlatformRuntime` so it uses the
// established T027 seam rather than constructing a second adapter set. The
// raster and OCR resolvers are startup-only placeholders that fail closed:
// startup owns neither loaded-document bytes nor page geometry, and it never
// calls those capabilities. They are replaced by the real composition when the
// editor bootstrap owns them; they are not simulated adapters and are never
// used to claim startup evidence.

import 'dart:io';

import 'android_platform_runtime.dart';

import 'package:feldexa_ports/feldexa_ports.dart';

import 'startup_sweep.dart';
import 'startup_sweep_io.dart';
import 'startup_sweep_platform.dart';
import 'startup_sweep_recovery.dart';

/// Creates the real Android startup sweep.
StartupSweep? createAppStartupSweep() {
  final AndroidPlatformRuntime runtime = AndroidPlatformRuntime.create(
    sourceBytes: (String sourceId) async => null,
    ocrPageSize: (image) => throw UnsupportedOperationException(),
  );
  final NativeStartupRecovery? nativeRecovery = platformStartupRecovery(
    runtime,
  );
  return StartupSweep(
    store: runtime.store,
    clock: runtime.adapters.clock,
    files: IoStartupSweepFileSystem(
      exportDirectory: Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}feldexa_exports',
      ),
    ),
    nativeRecovery: nativeRecovery,
  );
}
