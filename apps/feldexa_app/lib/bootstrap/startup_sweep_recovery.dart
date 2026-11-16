// T031 native startup-recovery value types.
//
// Owner: `apps/feldexa_app/lib/bootstrap/startup_sweep_recovery.dart` (T031).
//
// This file exists only so the conditional-import selector
// `startup_sweep_platform.dart` and `startup_sweep.dart` can share one neutral
// result type without either file importing the other (which would create an
// import cycle). It carries counts only, matching the native T026
// `RecoveryReport` and the T027 `AndroidRecoveryReport`: no id, title, path,
// or content ever crosses this boundary.

/// Counts-only result of the platform startup recovery.
///
/// The field set is exactly the native T026 `RecoveryReport` /
/// T027 `AndroidRecoveryReport` projection. The Dart sweep never derives a
/// field it was not given: a zero here means "the native recovery reported
/// zero", not "the Dart layer verified zero".
final class StartupRecoveryCounts {
  /// Creates a counts-only recovery result.
  const StartupRecoveryCounts({
    required this.tempEntriesRemoved,
    required this.incompleteAggregatesRemoved,
    required this.unreadableAggregates,
    required this.fallbackAdoptions,
    required this.orphanAliasesRemoved,
    required this.orphanAliasesRetained,
    required this.orphanAliasesFailed,
    required this.aliasSweepSkipped,
    required this.ambiguousRevisionOrder,
    required this.prunedRevisions,
  });

  /// The all-zero result used when the target has no native recovery.
  const StartupRecoveryCounts.none()
    : tempEntriesRemoved = 0,
      incompleteAggregatesRemoved = 0,
      unreadableAggregates = 0,
      fallbackAdoptions = 0,
      orphanAliasesRemoved = 0,
      orphanAliasesRetained = 0,
      orphanAliasesFailed = 0,
      aliasSweepSkipped = false,
      ambiguousRevisionOrder = 0,
      prunedRevisions = 0;

  /// Stale or unknown `tmp/` entries removed by the native recovery.
  final int tempEntriesRemoved;

  /// Incomplete aggregate directories removed by the native recovery.
  final int incompleteAggregatesRemoved;

  /// Aggregates the native recovery marked unreadable.
  final int unreadableAggregates;

  /// Older verified revisions adopted by the native head fallback.
  final int fallbackAdoptions;

  /// Orphan KEK aliases removed by the native recovery.
  final int orphanAliasesRemoved;

  /// Orphan KEK aliases deliberately retained by the native recovery.
  final int orphanAliasesRetained;

  /// Orphan KEK aliases whose removal failed.
  final int orphanAliasesFailed;

  /// Whether the native alias sweep was skipped.
  final bool aliasSweepSkipped;

  /// Aggregates whose revision order the native recovery could not decide.
  final int ambiguousRevisionOrder;

  /// Revision files pruned by the native retention step.
  final int prunedRevisions;

  /// Whether the native recovery reported any removal or adoption.
  bool get repairedAnything =>
      tempEntriesRemoved > 0 ||
      incompleteAggregatesRemoved > 0 ||
      fallbackAdoptions > 0 ||
      orphanAliasesRemoved > 0 ||
      prunedRevisions > 0;

  /// Whether the native recovery reported a condition that is not clean.
  ///
  /// `aliasSweepSkipped` and `ambiguousRevisionOrder` are included because the
  /// Dart layer must not present a skipped or ambiguous reconciliation as a
  /// complete success. `orphanAliasesRetained` is not a failure: the contract
  /// deliberately retains aliases whose aggregate directory still exists.
  bool get hasProblem =>
      unreadableAggregates > 0 ||
      orphanAliasesFailed > 0 ||
      aliasSweepSkipped ||
      ambiguousRevisionOrder > 0;

  @override
  String toString() =>
      'StartupRecoveryCounts(temp: $tempEntriesRemoved, '
      'incomplete: $incompleteAggregatesRemoved, '
      'unreadable: $unreadableAggregates, fallbacks: $fallbackAdoptions)';
}

/// One platform native startup-recovery invocation.
///
/// On Android the composition root binds this to
/// `AndroidPlatformRuntime.runStartupRecovery`; on the Web it stays `null`
/// because there is no native store to recover.
typedef NativeStartupRecovery = Future<StartupRecoveryCounts> Function();
