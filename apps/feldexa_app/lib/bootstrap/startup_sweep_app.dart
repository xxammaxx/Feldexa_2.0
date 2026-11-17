// T031 production startup-sweep composition selector.
//
// Owner: `apps/feldexa_app/lib/bootstrap/startup_sweep_app.dart` (T031).
//
// The selection mechanism mirrors `apps/feldexa_app/lib/platform/registry.dart`:
// the default branch is the platform-neutral Web composition, `dart.library.io`
// selects the Android/Dart `dart:io` composition, and
// `dart.library.js_interop` keeps the Web composition. The Web build therefore
// never resolves `dart:io`, `startup_sweep_io.dart`, the Android runtime, or
// the `feldexa_adapters_android` package.

import 'startup_sweep.dart';
import 'startup_sweep_app_web.dart'
    if (dart.library.io) 'startup_sweep_app_android.dart'
    if (dart.library.js_interop) 'startup_sweep_app_web.dart'
    as platform;

/// Creates the production startup sweep for the current compile target.
///
/// Returns `null` only if a target deliberately has no production store or
/// cache to inspect. The caller still goes through
/// `runStartupSweepBounded`, so a `null` result is a clean no-op, never a crash.
StartupSweep? createAppStartupSweep() => platform.createAppStartupSweep();
