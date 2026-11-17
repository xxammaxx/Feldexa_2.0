// T031 Android platform startup-recovery binding.
//
// Owner: `apps/feldexa_app/lib/bootstrap/startup_sweep_platform_android.dart`
// (T031). Selected by `startup_sweep_platform.dart` on `dart:library.io`
// targets only; the Web build never resolves this file.
//
// This is the one place T031 reaches the T027 composition seam. It does not
// construct the runtime and it does not duplicate any recovery algorithm: it
// converts the native T026 `AndroidRecoveryReport` counts into the neutral
// [StartupRecoveryCounts] value that `StartupSweep.run()` records first.

import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';

import 'android_platform_runtime.dart';
import 'startup_sweep_recovery.dart';

/// Binds [AndroidPlatformRuntime.runStartupRecovery] for [runtime].
///
/// A [runtime] that is not an [AndroidPlatformRuntime] yields `null`, so a
/// caller cannot accidentally drive an unrelated object. The returned callback
/// performs the channel call when invoked, not when it is created.
NativeStartupRecovery? platformStartupRecovery(Object? runtime) {
  if (runtime is! AndroidPlatformRuntime) {
    return null;
  }
  return ({int? deadlineEpochMs}) async {
    final AndroidRecoveryReport report = await runtime.runStartupRecovery(
      deadlineEpochMs: deadlineEpochMs,
    );
    return StartupRecoveryCounts(
      tempEntriesRemoved: report.tempEntriesRemoved,
      incompleteAggregatesRemoved: report.incompleteAggregatesRemoved,
      unreadableAggregates: report.unreadableAggregates,
      fallbackAdoptions: report.fallbackAdoptions,
      orphanAliasesRemoved: report.orphanAliasesRemoved,
      orphanAliasesRetained: report.orphanAliasesRetained,
      orphanAliasesFailed: report.orphanAliasesFailed,
      aliasSweepSkipped: report.aliasSweepSkipped,
      ambiguousRevisionOrder: report.ambiguousRevisionOrder,
      prunedRevisions: report.prunedRevisions,
      deadlineReached: report.deadlineReached,
    );
  };
}
