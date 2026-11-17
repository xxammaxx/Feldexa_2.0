// T031 application-side startup recovery and temp/export-preview sweep.
//
// Owner: `apps/feldexa_app/lib/bootstrap/startup_sweep.dart` (T031).
// Normative sources:
//   * `contracts/storage-format.md` §4 steps 1–6 — startup recovery order;
//   * `contracts/storage-format.md` §3.1 step 8 — known-kind retention and the
//     "trim history only after the delete-directory fsync succeeds" rule;
//   * `contracts/storage-format.md` §3.4, §3.5, §3.6, §5 — signature assets,
//     export artifacts, aggregate deletion, and failure semantics;
//   * `contracts/ports.md` §2.4 — `StoreKind`, `StoredMeta`, `RecoveryStamp`;
//   * `specs/001-scanned-form-workflow/plan.md` §Constraints — "No plaintext
//     document bytes in logs, caches, thumbnails, temp files, or backups" and
//     "Export preview files live only in app-private cache for the duration of
//     the preview and are swept on startup/session end";
//   * constitution Principles VI (privacy and deterministic cleanup), VII
//     (data safety and user control), and VIII (failure-case evidence).
//
// Division of labour, as stated in `android_platform_runtime.dart`: the native
// T026 recovery owns `contracts/storage-format.md` §4 steps 1–3 and 5–6
// (stale `tmp/`, incomplete aggregates, head fallback, signature assets, orphan
// KEK aliases, and the counts-only recovery event). Dart owns step 4, the
// cache-directory export previews.
//
// Owner decision 2026-11-17 amended `contracts/storage-format.md` §4 and
// `contracts/platform-channel.md` §4: the normative order is now
// 4 → 1 → 2 → 3 → 5 → 6. Step 4 runs first because stale plaintext export
// previews must be removed even when native recovery fails or times out, and
// removing them first is the only ordering that keeps that guarantee for the
// existing single `store.startupRecovery` call. Step 4 never touches an
// aggregate, KEK alias, revision, or source byte; the native steps keep their
// 1 → 2 → 3 → 5 → 6 order among themselves and step 6 stays last. The Dart
// `tmp/` pass is a secondary safety net only; the production Dart filesystem
// cannot address `filesDir/feldexa/tmp` and reports no staging entries, so
// native T026 remains the owner there. On the Web the native seam is `null`
// and the current shell has no production store; the sweep then does only its
// Web-safe directory pass and never invents aggregate state.
//
// Safety invariants:
//   * the sweep has no API that can delete, rename, or re-encrypt a document
//     or template aggregate, a revision, a source, or a KEK alias;
//   * it only deletes entries it received from the two dedicated temporary /
//     export-preview directories, and it never follows a name with a path
//     separator;
//   * it never logs or returns file paths, titles, or document content;
//   * every user-facing German sentence is read from the committed ARB via the
//     injected [AppLocalizations]; this file hard-codes no German text;
//   * the only clock used is the injected [ClockPort], read once per run, so
//     two identical inputs produce the same outcome;
//   * a cooperative [StartupSweepCancellation] checkpoint runs before every
//     non-export read and before every `tmp/` deletion, so a bounded-timeout
//     stop cannot leave store work running after the shell already showed the
//     start area; the earlier step-4 export pass is bounded and always runs.

import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/widgets.dart' show Locale;

import 'startup_sweep_cancellation.dart';
import 'startup_sweep_platform.dart';
import 'startup_sweep_recovery.dart';

export 'startup_sweep_recovery.dart' show StartupRecoveryCounts;

/// Overall outcome of one startup sweep.
enum StartupSweepStatus {
  /// Every read succeeded, nothing was repaired, and no issue was recorded.
  clean,

  /// Every read succeeded and the sweep or the native recovery repaired or
  /// adopted something. This is not a degraded result.
  recovered,

  /// At least one read failed, an aggregate is unreadable, the native recovery
  /// reported a problem, a deletion failed, or a processing bound was reached.
  /// The caller must not present this state as a complete startup success.
  degraded,
}

/// One bounded, deterministic directory entry supplied by
/// [StartupSweepFileSystem].
///
/// The name is one path segment only. A filesystem implementation must reject
/// or skip anything else before constructing this value; the factory validates
/// again so a misbehaving adapter cannot make the sweep delete outside the
/// dedicated directory.
final class StartupSweepEntry {
  /// Creates one validated directory entry.
  factory StartupSweepEntry({
    required String name,
    required DateTime lastModifiedUtc,
    bool isDirectory = false,
  }) {
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\')) {
      throw ArgumentError('name must be one non-empty path segment');
    }
    if (!lastModifiedUtc.isUtc) {
      throw ArgumentError('lastModifiedUtc must be UTC');
    }
    return StartupSweepEntry._(
      name: name,
      lastModifiedUtc: lastModifiedUtc,
      isDirectory: isDirectory,
    );
  }

  const StartupSweepEntry._({
    required this.name,
    required this.lastModifiedUtc,
    required this.isDirectory,
  });

  /// Single path segment inside the dedicated directory.
  final String name;

  /// Last modification time in UTC.
  final DateTime lastModifiedUtc;

  /// Whether the entry is a directory.
  final bool isDirectory;

  @override
  String toString() =>
      'StartupSweepEntry(isDirectory: $isDirectory, hasName: ${name.isNotEmpty})';
}

/// The only filesystem surface the startup sweep is allowed to use.
///
/// Implementations enumerate exactly two app-private locations — the store's
/// `tmp/` staging directory and the cache's `feldexa_exports/` directory — and
/// accept deletes only for an entry they previously returned. No method takes
/// an arbitrary path, which is what makes "never delete a visible document or
/// template" a structural property rather than a review promise.
abstract interface class StartupSweepFileSystem {
  /// Lists the staging entries in the store's `tmp/` directory.
  Future<List<StartupSweepEntry>> listTemporaryEntries();

  /// Removes one entry returned by [listTemporaryEntries].
  Future<void> deleteTemporaryEntry(StartupSweepEntry entry);

  /// Lists the preview artifacts in `cacheDir/feldexa_exports/`.
  Future<List<StartupSweepEntry>> listExportArtifacts();

  /// Removes one entry returned by [listExportArtifacts].
  Future<void> deleteExportArtifact(StartupSweepEntry entry);
}

/// Optional reporting seam for entries a filesystem could not inspect.
///
/// A [StartupSweepFileSystem] implementation that rejects an unsafe entry name
/// (for example a name with a path separator) or cannot stat an entry must not
/// silently drop it: the count is carried into [StartupSweepRemoval.failed] and
/// degrades the result. The count is redacted; no path, name, or content is
/// exposed.
abstract interface class StartupSweepInspectionReporter {
  /// Returns and resets the number of rejected/uninspectable entries.
  int takeInspectionFailures();
}

/// Directory stage of a [StartupSweepIssue].
enum StartupSweepStage {
  /// The native T026 recovery invocation.
  nativeRecovery,

  /// The stale/unknown `tmp/` sweep.
  temporarySweep,

  /// The document `list` read.
  documentList,

  /// The template `list` read.
  templateList,

  /// One aggregate's `recoveryStamp` read.
  recoveryStamp,

  /// The export-preview sweep.
  exportSweep,
}

/// One content-free sweep failure.
///
/// It carries only a stage, the typed catalog code when the adapter supplied
/// one, and the retry flag. It never carries an exception message, path, id,
/// title, or document content, so it is safe to include in a diagnostics event.
final class StartupSweepIssue {
  /// Creates a content-free issue.
  const StartupSweepIssue({
    required this.stage,
    this.catalogCode,
    this.retryable = false,
  });

  /// Stage that failed.
  final StartupSweepStage stage;

  /// Stable catalog code such as `SAVE-001`, or `null` for a failure with no
  /// catalog mapping (for example a deletion error raised by the filesystem
  /// seam).
  final String? catalogCode;

  /// Whether the documented recovery action allows an immediate retry.
  final bool retryable;

  @override
  String toString() =>
      'StartupSweepIssue(stage: ${stage.name}, code: ${catalogCode ?? '-'})';
}

/// One localized recovery notice for the UI.
///
/// [message] and [recovery] are the committed German ARB values, never
/// hard-coded here. [statusLabel] is the status-vocabulary label when the
/// catalog defines one (for example the unreadable or fallback status label).
final class StartupSweepNotice {
  /// Creates one localized notice.
  const StartupSweepNotice({
    required this.code,
    required this.message,
    required this.recovery,
    this.statusLabel,
    this.aggregateId,
    this.kind,
  });

  /// Stable catalog code, for example `SAVE-004`.
  final String code;

  /// Localized catalog message.
  final String message;

  /// Localized catalog recovery guidance.
  final String recovery;

  /// Localized status-vocabulary label, or `null` when the catalog has none.
  final String? statusLabel;

  /// Aggregate this notice belongs to, or `null` for a store-wide failure.
  final String? aggregateId;

  /// Aggregate kind when [aggregateId] is present.
  final StoreKind? kind;

  @override
  String toString() => 'StartupSweepNotice(code: $code)';
}

/// One aggregate's list projection and recovery stamp.
final class AggregateRecovery {
  /// Creates an aggregate recovery result.
  const AggregateRecovery({
    required this.meta,
    required this.stamp,
    this.stampFailed = false,
  });

  /// The contract-visible list entry.
  final StoredMeta meta;

  /// The recovery stamp, or `null` when the stamp was skipped or failed.
  final RecoveryStamp? stamp;

  /// Whether the `recoveryStamp` read itself failed.
  final bool stampFailed;

  /// The verified revision id, filled only from the adapter's stamp.
  String? get verifiedRevisionId => stamp?.verifiedRevisionId;

  /// The verified commit time, filled only from the adapter's stamp.
  DateTime? get committedAt => stamp?.committedAt;

  /// Whether recovery adopted an older verified revision.
  bool get fellBackToOlderRevision => stamp?.fellBackToOlderRevision ?? false;

  /// Whether the aggregate must be shown as unreadable.
  ///
  /// A corrupt head with no adopted revision, a failed stamp read, and a
  /// missing verified revision all mean the same thing for the list: there is
  /// no verified state to present. The sweep never synthesizes one.
  bool get unreadable {
    if (!meta.readable) {
      return true;
    }
    final RecoveryStamp? value = stamp;
    if (value == null) {
      return true;
    }
    if (value.headCorrupt && !value.fellBackToOlderRevision) {
      return true;
    }
    return value.verifiedRevisionId == null;
  }

  @override
  String toString() =>
      'AggregateRecovery(kind: ${meta.kind.name}, '
      'unreadable: $unreadable, fallback: $fellBackToOlderRevision)';
}

/// Counts from one bounded directory removal pass.
final class StartupSweepRemoval {
  /// Creates a removal result.
  const StartupSweepRemoval({
    required this.scanned,
    required this.removed,
    required this.kept,
    required this.failed,
    required this.boundReached,
    this.listingFailed = false,
  });

  /// No directory was scanned.
  static const StartupSweepRemoval empty = StartupSweepRemoval(
    scanned: 0,
    removed: 0,
    kept: 0,
    failed: 0,
    boundReached: false,
  );

  /// Entries processed after the deterministic bound was applied.
  final int scanned;

  /// Entries deleted successfully.
  final int removed;

  /// Entries deliberately kept.
  final int kept;

  /// Entries whose deletion failed or that could not be classified safely.
  final int failed;

  /// Whether the listing contained more entries than the configured bound.
  final bool boundReached;

  /// Whether the directory listing itself failed.
  ///
  /// `run()` also records a typed issue, so this flag matters most for
  /// [StartupSweep.sweepSessionEnd], which returns only removal counts.
  final bool listingFailed;

  @override
  String toString() =>
      'StartupSweepRemoval(scanned: $scanned, removed: $removed, '
      'kept: $kept, failed: $failed, listingFailed: $listingFailed)';
}

/// Complete result of one [StartupSweep.run].
final class StartupSweepResult {
  /// Creates a sweep result.
  const StartupSweepResult({
    required this.status,
    required this.nativeRecovery,
    required this.temporary,
    required this.exportPreviews,
    required this.aggregates,
    required this.notices,
    required this.issues,
    required this.boundReached,
  });

  /// Overall startup outcome.
  final StartupSweepStatus status;

  /// Counts reported by the native recovery, all zero when there is none.
  final StartupRecoveryCounts nativeRecovery;

  /// Stale/unknown `tmp/` removal counts.
  final StartupSweepRemoval temporary;

  /// Export-preview removal counts.
  final StartupSweepRemoval exportPreviews;

  /// Contract-visible aggregates in deterministic `(kind, id)` order.
  final List<AggregateRecovery> aggregates;

  /// Localized recovery notices for the UI.
  final List<StartupSweepNotice> notices;

  /// Content-free failures.
  final List<StartupSweepIssue> issues;

  /// Whether any category exceeded the configured processing bound.
  final bool boundReached;

  /// Number of aggregates that must be shown as unreadable.
  int get unreadableCount =>
      aggregates.where((AggregateRecovery value) => value.unreadable).length;

  /// Number of aggregates whose recovery stamp adopted an older revision.
  ///
  /// A native adoption is committed before the later `recoveryStamp` reads, so
  /// a native fallback is not necessarily visible in this stamp-only count.
  /// [nativeFallbackCount] preserves that separate native count.
  int get fallbackCount => aggregates
      .where((AggregateRecovery value) => value.fellBackToOlderRevision)
      .length;

  /// Number of fallback adoptions reported by the native T026 recovery.
  ///
  /// The native recovery commits the repaired head, so a later
  /// `recoveryStamp` can report `fellBackToOlderRevision: false`; this count
  /// is how the sweep preserves the warning across that transition.
  int get nativeFallbackCount => nativeRecovery.fallbackAdoptions;

  /// Whether startup may be presented as a complete, non-degraded success.
  ///
  /// `recovered` is still complete: the contract-visible state is verified and
  /// the user only needs the `SAVE-004` guidance. `degraded` is never success.
  bool get isComplete => status != StartupSweepStatus.degraded;

  @override
  String toString() =>
      'StartupSweepResult(status: ${status.name}, '
      'temporaryRemoved: ${temporary.removed}, '
      'exportPreviewsRemoved: ${exportPreviews.removed}, '
      'unreadable: $unreadableCount, issues: ${issues.length})';
}

/// Application-side startup recovery and temporary/export-preview sweep.
final class StartupSweep {
  /// Creates a sweep over [store], [clock], and [files].
  ///
  /// [store] is `null` on a target without a production encrypted store (the
  /// current Web shell). In that case the sweep performs only the
  /// Dart-reachable directory cleanup and never invents aggregate state.
  ///
  /// [nativeRecovery] overrides the platform binding; it is the seam tests use
  /// and the direct composition-root hook. When it is `null`,
  /// [platformRuntime] is bound through the conditional platform selector:
  /// `AndroidPlatformRuntime` selects the native T026 recovery, while a Web or
  /// `null` runtime leaves the callback `null`. [messages] defaults to the
  /// committed German `de` ARB, so no production caller needs to pass
  /// user-facing text.
  StartupSweep({
    required this.store,
    required this.clock,
    required this.files,
    NativeStartupRecovery? nativeRecovery,
    Object? platformRuntime,
    AppLocalizations? messages,
    StartupSweepCancellation? cancellation,
    this.maxEntriesPerCategory = defaultMaxEntriesPerCategory,
  }) : nativeRecovery =
           nativeRecovery ?? platformStartupRecovery(platformRuntime),
       messages = messages ?? lookupAppLocalizations(const Locale('de')),
       cancellation = cancellation ?? StartupSweepCancellation() {
    if (maxEntriesPerCategory < 1) {
      throw ArgumentError.value(
        maxEntriesPerCategory,
        'maxEntriesPerCategory',
        'must be at least 1',
      );
    }
  }

  /// Contract-visible encrypted store, or `null` on a target without one.
  ///
  /// A `null` store means the target has no production encrypted store to
  /// read; the sweep still performs the cache-directory cleanup but performs
  /// no `list` or `recoveryStamp` call and reports no aggregate state.
  final SecureStorePort? store;

  /// Injected clock; the only time source the sweep reads.
  final ClockPort clock;

  /// The dedicated `tmp/` and export-preview directory seam.
  final StartupSweepFileSystem files;

  /// Native T026 recovery callback, or `null` on a target without one.
  final NativeStartupRecovery? nativeRecovery;

  /// German resources for every notice the sweep surfaces.
  final AppLocalizations messages;

  /// Cooperative stop signal shared with the bounded startup runner.
  ///
  /// The sweep checks it before every store read and before every deletion, so
  /// [cancel] stops further destructive work at the next checkpoint instead of
  /// letting a timed-out run continue in the background. A cancelled run
  /// returns a degraded result; it never reports success.
  final StartupSweepCancellation cancellation;

  /// Requests a cooperative stop at the next checkpoint.
  ///
  /// `runStartupSweepBounded` calls this when its bounded wait expires, which is
  /// what turns a caller-side timeout into a visible, bounded recovery attempt
  /// rather than unbounded post-timeout work. Idempotent.
  void cancel() {
    cancellation.cancel();
  }

  /// Whether [cancel] has been requested.
  bool get isCancelled => cancellation.isCancelled;

  /// Hard cap on entries processed per category in one run.
  ///
  /// The contract requires a bounded sweep; this is the documented, testable
  /// bound. It applies independently to `tmp/`, export previews, documents,
  /// and templates. Reaching it is reported through
  /// [StartupSweepResult.boundReached] and degrades the run instead of being
  /// silently ignored.
  final int maxEntriesPerCategory;

  /// Default processing bound per category.
  static const int defaultMaxEntriesPerCategory = 512;

  /// Age after which an unreferenced temporary or export entry is stale.
  static const Duration staleAge = Duration(hours: 24);

  /// Known staging names written by the native atomic commit protocol.
  ///
  /// `contracts/storage-format.md` §3 stages `tmp/<txnId>.part`,
  /// `tmp/<txnId>.head`, and their object siblings before promotion. Any other
  /// name is unknown and is swept regardless of age (§4 step 1).
  static final RegExp _knownTemporaryName = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
    r'[0-9a-f]{12}\.(part|head|meta|src|sig|ver|restore)$',
  );

  /// Runs the startup recovery in the normative order 4 → 1 → 2 → 3 → 5 → 6.
  ///
  /// The native T026 call owns `contracts/storage-format.md` §4 steps 1–3 and
  /// steps 5–6: stale/unknown `tmp/`, incomplete aggregates and head fallback,
  /// unreferenced signatures, orphan KEK aliases, and the redacted counts-only
  /// recovery event. Dart owns step 4, the cache-directory export previews.
  ///
  /// Owner decision 2026-11-17 made step 4 first normative: stale plaintext
  /// export previews must be removed even when the native recovery fails or
  /// times out, so the export-preview pass runs **before** the monolithic
  /// native call and is deliberately **not** subject to the cooperative
  /// cancellation token. It is bounded by [maxEntriesPerCategory], touches only
  /// the dedicated cache directory, and records an explicit issue if anything
  /// cannot be removed, so a timeout can never skip it silently. The native
  /// steps keep their 1 → 2 → 3 → 5 → 6 order among themselves and step 6
  /// remains last. The Dart `tmp/` pass remains a secondary safety net for
  /// targets whose filesystem seam can reach staging; the production Dart
  /// adapter cannot and deliberately reports no staging entries. No aggregate
  /// object, alias, revision, or source is ever a candidate for deletion here.
  ///
  /// Cancellation checkpoints for the non-priority work: before the native
  /// recovery, before the staging pass, before each kind read, before each
  /// `recoveryStamp` read, and before each individual `tmp/` deletion. The
  /// export-preview pass above is the documented exception: it always runs. A
  /// cancelled run stops at the next checkpoint, performs no further read or
  /// non-export deletion, and returns a degraded result.
  Future<StartupSweepResult> run() async {
    final DateTime nowUtc = clock.nowUtc().toUtc();
    final _SweepState state = _SweepState();

    // Dart-owned step 4: always remove stale plaintext export previews first,
    // even when native recovery fails (T031-A2) and even when the bounded wait
    // has already expired or expires during the pass (owner decision
    // 2026-11-17). A skip here would leave plaintext in the app cache with no
    // report, which is the failure this ordering exists to prevent.
    final StartupSweepRemoval exportPreviews = await _sweepExportPreviews(
      nowUtc,
      state,
      priority: true,
    );

    // Native steps 1–3 and 5–6. The callback is the T027 composition seam.
    StartupRecoveryCounts native = const StartupRecoveryCounts.none();
    if (!_stopIfCancelled(state)) {
      native = await _runNativeRecovery(state);
    }

    // Secondary staging pass. The production Dart adapter cannot address the
    // native `filesDir/feldexa/tmp` directory and returns no entries; native
    // T026 owns that directory. The fake/file-system seam can still exercise
    // this contract-identical fallback.
    StartupSweepRemoval temporary = StartupSweepRemoval.empty;
    if (!_stopIfCancelled(state)) {
      temporary = await _sweepTemporary(nowUtc, state);
    }

    final List<AggregateRecovery> aggregates = <AggregateRecovery>[];
    if (!state.nativeFailed && !state.cancelled && store != null) {
      // Contract-visible reads only after native reconciliation. A native
      // failure or a missing production store skips these reads because they
      // need the aggregate key; it does not skip the plaintext cleanup above.
      await _readKind(StoreKind.document, aggregates, state);
      await _readKind(StoreKind.template, aggregates, state);
    }

    return _result(
      native: native,
      temporary: temporary,
      exportPreviews: exportPreviews,
      aggregates: aggregates,
      state: state,
    );
  }

  /// Records and reports a requested cooperative stop.
  ///
  /// Returns `true` when the run must not continue. The cancelled flag makes
  /// the result degraded, so a stopped run is never presented as success.
  bool _stopIfCancelled(_SweepState state) {
    if (!cancellation.isCancelled) {
      return false;
    }
    state.cancelled = true;
    return true;
  }

  /// Removes every export-preview artifact at session end.
  ///
  /// `contracts/storage-format.md` §4 step 4 requires "any on session end",
  /// independent of age. Only the dedicated cache-directory artifacts are
  /// touched; no aggregate, alias, revision, or source is reachable here.
  Future<StartupSweepRemoval> sweepSessionEnd() {
    final _SweepState state = _SweepState();
    return _sweepExportPreviews(clock.nowUtc().toUtc(), state, removeAll: true);
  }

  Future<StartupRecoveryCounts> _runNativeRecovery(_SweepState state) async {
    final NativeStartupRecovery? callback = nativeRecovery;
    if (callback == null) {
      return const StartupRecoveryCounts.none();
    }
    try {
      final StartupRecoveryCounts counts = await callback();
      if (counts.hasProblem) {
        state.addIssue(
          const StartupSweepIssue(stage: StartupSweepStage.nativeRecovery),
        );
      }
      return counts;
    } on FeldexaException catch (error) {
      state.nativeFailed = true;
      state.addIssue(
        StartupSweepIssue(
          stage: StartupSweepStage.nativeRecovery,
          catalogCode: error.code,
          retryable: error.retryable,
        ),
      );
      _addCodeNotice(error.code, null, state);
      return const StartupRecoveryCounts.none();
    } catch (_) {
      state.nativeFailed = true;
      state.addIssue(
        const StartupSweepIssue(stage: StartupSweepStage.nativeRecovery),
      );
      return const StartupRecoveryCounts.none();
    }
  }

  Future<StartupSweepRemoval> _sweepTemporary(
    DateTime nowUtc,
    _SweepState state,
  ) async {
    final List<StartupSweepEntry> entries;
    try {
      entries = await files.listTemporaryEntries();
    } on FeldexaException catch (error) {
      state.addIssue(
        StartupSweepIssue(
          stage: StartupSweepStage.temporarySweep,
          catalogCode: error.code,
          retryable: error.retryable,
        ),
      );
      return const StartupSweepRemoval(
        scanned: 0,
        removed: 0,
        kept: 0,
        failed: 0,
        boundReached: false,
        listingFailed: true,
      );
    } catch (_) {
      state.addIssue(
        const StartupSweepIssue(stage: StartupSweepStage.temporarySweep),
      );
      return const StartupSweepRemoval(
        scanned: 0,
        removed: 0,
        kept: 0,
        failed: 0,
        boundReached: false,
        listingFailed: true,
      );
    }
    return _removeEntries(
      entries: entries,
      stage: StartupSweepStage.temporarySweep,
      state: state,
      shouldRemove: (StartupSweepEntry entry) =>
          !_knownTemporaryName.hasMatch(entry.name) || _isStale(entry, nowUtc),
      remove: files.deleteTemporaryEntry,
    );
  }

  Future<StartupSweepRemoval> _sweepExportPreviews(
    DateTime nowUtc,
    _SweepState state, {
    bool removeAll = false,
    bool priority = false,
  }) async {
    final List<StartupSweepEntry> entries;
    try {
      entries = await files.listExportArtifacts();
    } on FeldexaException catch (error) {
      final int rejected = _takeInspectionFailures();
      state.addIssue(
        StartupSweepIssue(
          stage: StartupSweepStage.exportSweep,
          catalogCode: error.code,
          retryable: error.retryable,
        ),
      );
      return StartupSweepRemoval(
        scanned: rejected,
        removed: 0,
        kept: 0,
        failed: rejected,
        boundReached: false,
        listingFailed: true,
      );
    } catch (_) {
      final int rejected = _takeInspectionFailures();
      state.addIssue(
        const StartupSweepIssue(stage: StartupSweepStage.exportSweep),
      );
      return StartupSweepRemoval(
        scanned: rejected,
        removed: 0,
        kept: 0,
        failed: rejected,
        boundReached: false,
        listingFailed: true,
      );
    }
    final int rejected = _takeInspectionFailures();
    final StartupSweepRemoval removal = await _removeEntries(
      entries: entries,
      stage: StartupSweepStage.exportSweep,
      state: state,
      shouldRemove: (StartupSweepEntry entry) =>
          removeAll || _isStale(entry, nowUtc),
      remove: files.deleteExportArtifact,
      // An export directory must contain files only. A directory is retained
      // and reported instead of being deleted recursively.
      rejectDirectories: true,
      // The priority pass (startup step 4) must not be skipped by a timeout;
      // the session-end pass has its own fresh, uncancelled state.
      respectCancellation: !priority,
    );
    if (rejected <= 0) {
      return removal;
    }
    // T031-A-3: rejected or uninspectable entries are redacted cleanup
    // failures. The count is carried; no path, name, or content is surfaced.
    state.addIssue(
      const StartupSweepIssue(stage: StartupSweepStage.exportSweep),
    );
    return StartupSweepRemoval(
      scanned: removal.scanned + rejected,
      removed: removal.removed,
      kept: removal.kept,
      failed: removal.failed + rejected,
      boundReached: removal.boundReached,
      listingFailed: removal.listingFailed,
    );
  }

  int _takeInspectionFailures() {
    final StartupSweepFileSystem source = files;
    if (source is StartupSweepInspectionReporter) {
      return (source as StartupSweepInspectionReporter)
          .takeInspectionFailures();
    }
    return 0;
  }

  Future<StartupSweepRemoval> _removeEntries({
    required List<StartupSweepEntry> entries,
    required StartupSweepStage stage,
    required _SweepState state,
    required bool Function(StartupSweepEntry entry) shouldRemove,
    required Future<void> Function(StartupSweepEntry entry) remove,
    bool rejectDirectories = false,
    bool respectCancellation = true,
  }) async {
    final List<StartupSweepEntry> sorted = List<StartupSweepEntry>.of(entries)
      ..sort((StartupSweepEntry a, StartupSweepEntry b) {
        return a.name.compareTo(b.name);
      });
    final bool boundReached = sorted.length > maxEntriesPerCategory;
    if (boundReached) {
      state.boundReached = true;
    }
    final Iterable<StartupSweepEntry> bounded = boundReached
        ? sorted.take(maxEntriesPerCategory)
        : sorted;
    int scanned = 0;
    int removed = 0;
    int kept = 0;
    int failed = 0;
    for (final StartupSweepEntry entry in bounded) {
      if (respectCancellation && _stopIfCancelled(state)) {
        // A cancelled run stops before this deletion. Nothing after the stop
        // checkpoint is deleted or counted as processed.
        break;
      }
      scanned++;
      if (rejectDirectories && entry.isDirectory) {
        failed++;
        state.addIssue(StartupSweepIssue(stage: stage));
        continue;
      }
      if (!shouldRemove(entry)) {
        kept++;
        continue;
      }
      try {
        await remove(entry);
        removed++;
      } on FeldexaException catch (error) {
        failed++;
        state.addIssue(
          StartupSweepIssue(
            stage: stage,
            catalogCode: error.code,
            retryable: error.retryable,
          ),
        );
      } catch (_) {
        failed++;
        state.addIssue(StartupSweepIssue(stage: stage));
      }
    }
    return StartupSweepRemoval(
      scanned: scanned,
      removed: removed,
      kept: kept,
      failed: failed,
      boundReached: boundReached,
    );
  }

  Future<void> _readKind(
    StoreKind kind,
    List<AggregateRecovery> aggregates,
    _SweepState state,
  ) async {
    final SecureStorePort? activeStore = store;
    if (activeStore == null || _stopIfCancelled(state)) {
      return;
    }
    final StartupSweepStage listStage = switch (kind) {
      StoreKind.document => StartupSweepStage.documentList,
      StoreKind.template => StartupSweepStage.templateList,
    };
    final List<StoredMeta> entries;
    try {
      entries = await activeStore.list(kind);
    } on FeldexaException catch (error) {
      state.addIssue(
        StartupSweepIssue(
          stage: listStage,
          catalogCode: error.code,
          retryable: error.retryable,
        ),
      );
      _addCodeNotice(error.code, null, state);
      return;
    } catch (_) {
      state.addIssue(StartupSweepIssue(stage: listStage));
      return;
    }

    final List<StoredMeta> sorted = List<StoredMeta>.of(entries)
      ..sort((StoredMeta a, StoredMeta b) => a.id.compareTo(b.id));
    final bool boundReached = sorted.length > maxEntriesPerCategory;
    if (boundReached) {
      state.boundReached = true;
    }
    final Iterable<StoredMeta> bounded = boundReached
        ? sorted.take(maxEntriesPerCategory)
        : sorted;
    for (final StoredMeta meta in bounded) {
      if (_stopIfCancelled(state)) {
        // No further `recoveryStamp` read after a stop request.
        return;
      }
      if (!meta.readable) {
        aggregates.add(AggregateRecovery(meta: meta, stamp: null));
        final String? code = meta.unreadableReasonCode;
        if (code != null) {
          _addCodeNotice(code, meta, state);
        }
        continue;
      }
      try {
        final RecoveryStamp stamp = await activeStore.recoveryStamp(
          meta.id,
          kind,
        );
        aggregates.add(AggregateRecovery(meta: meta, stamp: stamp));
        if (stamp.fellBackToOlderRevision) {
          if (stamp.verifiedRevisionId == null) {
            // A fallback claim without a verified revision is not a state the
            // sweep may present as a successful adoption.
            state.addIssue(
              const StartupSweepIssue(
                stage: StartupSweepStage.recoveryStamp,
                catalogCode: 'SAVE-003',
              ),
            );
          } else {
            state.addNotice(
              StartupSweepNotice(
                code: 'SAVE-004',
                statusLabel: messages.durabilityRecoveryFallback,
                message: messages.save004,
                recovery: messages.save004Recovery,
                aggregateId: meta.id,
                kind: meta.kind,
              ),
            );
          }
        } else if (stamp.headCorrupt) {
          state.addIssue(
            const StartupSweepIssue(
              stage: StartupSweepStage.recoveryStamp,
              catalogCode: 'SAVE-003',
            ),
          );
        }
      } on FeldexaException catch (error) {
        aggregates.add(
          AggregateRecovery(meta: meta, stamp: null, stampFailed: true),
        );
        state.addIssue(
          StartupSweepIssue(
            stage: StartupSweepStage.recoveryStamp,
            catalogCode: error.code,
            retryable: error.retryable,
          ),
        );
        _addCodeNotice(error.code, meta, state);
      } catch (_) {
        aggregates.add(
          AggregateRecovery(meta: meta, stamp: null, stampFailed: true),
        );
        state.addIssue(
          const StartupSweepIssue(stage: StartupSweepStage.recoveryStamp),
        );
      }
    }
  }

  void _addCodeNotice(String code, StoredMeta? meta, _SweepState state) {
    final (String?, String, String)? guidance = _guidanceFor(code);
    if (guidance == null) {
      return;
    }
    state.addNotice(
      StartupSweepNotice(
        code: code,
        statusLabel: guidance.$1,
        message: guidance.$2,
        recovery: guidance.$3,
        aggregateId: meta?.id,
        kind: meta?.kind,
      ),
    );
  }

  (String?, String, String)? _guidanceFor(String code) {
    switch (code) {
      case 'SAVE-001':
        return (null, messages.save001, messages.save001Recovery);
      case 'SAVE-002':
        return (
          messages.statusUnreadable,
          messages.save002,
          messages.save002Recovery,
        );
      case 'SAVE-003':
        return (
          messages.statusUnreadable,
          messages.save003,
          messages.save003Recovery,
        );
      case 'SAVE-005':
        // No status-vocabulary row exists for an unknown newer schema; the
        // catalog message itself carries the update guidance.
        return (null, messages.save005, messages.save005Recovery);
      case 'SAVE-008':
        return (
          messages.statusUnreadable,
          messages.save008,
          messages.save008Recovery,
        );
      default:
        return null;
    }
  }

  StartupSweepResult _result({
    required StartupRecoveryCounts native,
    required StartupSweepRemoval temporary,
    required StartupSweepRemoval exportPreviews,
    required List<AggregateRecovery> aggregates,
    required _SweepState state,
  }) {
    // T031-A1: the native recovery commits the repaired head, so the later
    // recoveryStamp reads can all report `fellBackToOlderRevision: false`.
    // Preserve the native adoption as a store-wide SAVE-004 notice when no
    // aggregate-specific fallback notice already carries the warning.
    if (native.fallbackAdoptions > 0 &&
        !state.notices.any(
          (StartupSweepNotice value) => value.code == 'SAVE-004',
        )) {
      state.addNotice(
        StartupSweepNotice(
          code: 'SAVE-004',
          statusLabel: messages.durabilityRecoveryFallback,
          message: messages.save004,
          recovery: messages.save004Recovery,
        ),
      );
    }
    final bool hasUnreadable = aggregates.any(
      (AggregateRecovery value) => value.unreadable,
    );
    final bool degraded =
        state.issues.isNotEmpty ||
        state.boundReached ||
        state.cancelled ||
        hasUnreadable ||
        native.hasProblem;
    final bool repaired =
        native.repairedAnything ||
        temporary.removed > 0 ||
        exportPreviews.removed > 0 ||
        aggregates.any(
          (AggregateRecovery value) => value.fellBackToOlderRevision,
        );
    final StartupSweepStatus status = degraded
        ? StartupSweepStatus.degraded
        : repaired
        ? StartupSweepStatus.recovered
        : StartupSweepStatus.clean;
    return StartupSweepResult(
      status: status,
      nativeRecovery: native,
      temporary: temporary,
      exportPreviews: exportPreviews,
      aggregates: List<AggregateRecovery>.unmodifiable(aggregates),
      notices: List<StartupSweepNotice>.unmodifiable(state.notices),
      issues: List<StartupSweepIssue>.unmodifiable(state.issues),
      boundReached: state.boundReached,
    );
  }

  bool _isStale(StartupSweepEntry entry, DateTime nowUtc) {
    return nowUtc.difference(entry.lastModifiedUtc) > staleAge;
  }
}

/// Mutable run-scoped issue/notice accumulator with deterministic notice
/// de-duplication.
final class _SweepState {
  final List<StartupSweepIssue> issues = <StartupSweepIssue>[];
  final List<StartupSweepNotice> notices = <StartupSweepNotice>[];
  final Set<String> _noticeKeys = <String>{};
  bool boundReached = false;
  bool nativeFailed = false;
  bool cancelled = false;

  void addIssue(StartupSweepIssue issue) {
    issues.add(issue);
  }

  void addNotice(StartupSweepNotice notice) {
    final String key =
        '${notice.code}|${notice.aggregateId ?? ''}|'
        '${notice.kind?.name ?? ''}';
    if (_noticeKeys.add(key)) {
      notices.add(notice);
    }
  }
}
