// T031 platform startup-recovery conditional-import selector.
//
// Owner: `apps/feldexa_app/lib/bootstrap/startup_sweep_platform.dart` (T031).
// Normative sources:
//   * `apps/feldexa_app/lib/bootstrap/android_platform_runtime.dart` header —
//     the native T026 recovery is the prerequisite of `StartupSweep.run()`;
//   * plan §Constraints — no Android code may be resolved by the Web build;
//   * `contracts/storage-format.md` §4 — startup recovery order.
//
// The selection mechanism mirrors `apps/feldexa_app/lib/platform/registry.dart`:
// the default branch is the platform-neutral Web stub, `dart.library.io`
// selects the Android runtime binding, and `dart.library.js_interop` keeps the
// Web stub. The Web build therefore never resolves
// `android_platform_runtime.dart` or the `feldexa_adapters_android` package.

import 'startup_sweep_platform_web.dart'
    if (dart.library.io) 'startup_sweep_platform_android.dart'
    if (dart.library.js_interop) 'startup_sweep_platform_web.dart'
    as platform;

import 'startup_sweep_recovery.dart';

/// Binds the native startup recovery of [runtime] to a sweep callback.
///
/// Returns `null` when the current target has no native store recovery, or
/// when [runtime] is not the platform runtime this build can drive. The caller
/// still runs `StartupSweep.run()`; a `null` result means only that the
/// contract-visible Dart reads are performed, which is the documented Web
/// behavior.
NativeStartupRecovery? platformStartupRecovery(Object? runtime) =>
    platform.platformStartupRecovery(runtime);
