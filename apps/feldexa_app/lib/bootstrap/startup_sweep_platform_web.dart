// T031 Web platform startup-recovery stub.
//
// Owner: `apps/feldexa_app/lib/bootstrap/startup_sweep_platform_web.dart`
// (T031).
//
// This file is selected by `startup_sweep_platform.dart` for the Web build and
// for unknown compile targets. It deliberately imports no adapter package and
// no Android runtime: the Web store is the deterministic SIMULATED surface, so
// there is no native T026 store to recover. The Dart sweep then performs the
// contract-visible `list` / `recoveryStamp` reads and the cache-directory
// export-preview sweep only.

import 'startup_sweep_recovery.dart';

/// Returns `null`: this target has no native encrypted-store recovery.
NativeStartupRecovery? platformStartupRecovery(Object? runtime) => null;
