// T031 startup wiring: bounded, failure-safe invocation of the sweep.
//
// Owner: `apps/feldexa_app/lib/bootstrap/startup_sweep_bootstrap.dart` (T031).
//
// The application shell must never crash, hang, or claim a startup success it
// did not achieve. This file owns the bounded wait, the cooperative cancellation
// request, the conversion of an unexpected failure into a degraded startup
// state, and the German notice surface for a degraded startup. It imports no
// platform adapter and no `dart:io`, so the Web build can use it unchanged.
//
// The wall clock here is a real app clock (`EvidenceClass.none`), not a
// simulated adapter: it is the production wall clock for the startup sweep,
// not a fixture.

import 'dart:async';

import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/widgets.dart' show Locale;

import 'startup_sweep.dart';

/// One application-startup attempt.
final class StartupSweepStartup {
  /// Creates a startup attempt result.
  const StartupSweepStartup({
    this.result,
    this.timedOut = false,
    this.failed = false,
  });

  /// The sweep result, or `null` when the run timed out or failed.
  final StartupSweepResult? result;

  /// Whether the bounded wait expired before the sweep finished.
  final bool timedOut;

  /// Whether the sweep threw unexpectedly before returning a result.
  final bool failed;

  /// Whether startup must not be presented as a complete success.
  ///
  /// A timed-out or thrown run is degraded even though it has no result.
  bool get isDegraded =>
      timedOut || failed || (result?.status == StartupSweepStatus.degraded);

  /// Localized notices to surface to the user, in deterministic order.
  List<StartupSweepNotice> get notices =>
      result?.notices ?? const <StartupSweepNotice>[];

  /// Whether this attempt produced no specific catalog notice of its own.
  ///
  /// A timed-out or thrown run has no result at all, and a degraded result can
  /// carry only content-free issues (for example a failed directory deletion).
  /// Both cases need the generic ARB notice from [startupRecoveryNotices].
  bool get hasNoNotices => notices.isEmpty;

  @override
  String toString() =>
      'StartupSweepStartup(timedOut: $timedOut, failed: $failed, '
      'degraded: $isDegraded)';
}

/// Notices the shell must show for [startup].
///
/// The shell may never present a degraded startup as a complete success. When
/// the run timed out, threw, or returned a degraded result without a specific
/// catalog notice, the returned list carries the generic German
/// `startupRecoveryIncomplete` notice from the committed ARB. A clean or
/// recovered run yields exactly the notices the sweep produced, so the plain
/// start area stays plain.
List<StartupSweepNotice> startupRecoveryNotices(
  StartupSweepStartup startup, {
  AppLocalizations? messages,
}) {
  final List<StartupSweepNotice> notices = startup.notices;
  if (!startup.isDegraded || notices.isNotEmpty) {
    return notices;
  }
  final AppLocalizations l10n =
      messages ?? lookupAppLocalizations(const Locale('de'));
  return List<StartupSweepNotice>.unmodifiable(<StartupSweepNotice>[
    StartupSweepNotice(
      code: 'startupRecoveryIncomplete',
      message: l10n.startupRecoveryIncomplete,
      recovery: l10n.startupRecoveryIncompleteRecovery,
    ),
  ]);
}

/// One startup sweep invocation.
typedef StartupSweepRun = Future<StartupSweepResult> Function({
  int? deadlineEpochMs,
});

/// Runs [run] with a hard upper bound and converts every failure to a state.
///
/// The caller receives a value on every path:
/// * a completed sweep result;
/// * [StartupSweepStartup.timedOut] when [timeout] expires;
/// * [StartupSweepStartup.failed] when [run] throws synchronously or
///   asynchronously.
///
/// The timeout bounds the CALLER'S wait. It is converted into one absolute
/// `deadlineEpochMs` value and passed into [run]: the production sweep forwards
/// it to the native recovery, which checks it before each step and before each
/// destructive action, so no new deletion starts after the deadline. The
/// production caller also passes `StartupSweep.cancel` as [onTimeout]; that
/// cooperative token stops the Dart staging pass, reads, and `tmp/` deletions
/// after a timeout. Work already in flight inside one native step may complete
/// before its next deadline check; this is the documented residual. The step-4
/// plaintext export-preview pass deliberately runs first and is not cancelled;
/// it is bounded, and a failure is reported rather than skipped (§4 order,
/// owner decision 2026-11-17). The eventual result or error is consumed so it
/// cannot become an unhandled asynchronous error, and the UI receives a
/// degraded startup state with a visible German notice; it must not claim
/// success.
Future<StartupSweepStartup> runStartupSweepBounded({
  required StartupSweepRun run,
  Duration timeout = const Duration(seconds: 5),
  void Function()? onTimeout,
}) async {
  final int deadlineEpochMs = DateTime.now()
      .toUtc()
      .add(timeout)
      .millisecondsSinceEpoch;
  final Future<StartupSweepResult> operation;
  try {
    operation = run(deadlineEpochMs: deadlineEpochMs);
  } catch (_) {
    return const StartupSweepStartup(failed: true);
  }
  try {
    final StartupSweepResult result = await operation.timeout(timeout);
    return StartupSweepStartup(result: result);
  } on TimeoutException {
    // The sweep is still running; request the cooperative stop before the
    // caller is told the wait expired. The native call already received the
    // same absolute deadline and stops at its next check.
    onTimeout?.call();
    unawaited(
      operation.then<void>(
        (StartupSweepResult _) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
    return const StartupSweepStartup(timedOut: true);
  } catch (_) {
    return const StartupSweepStartup(failed: true);
  }
}

/// Production wall clock for the startup path.
final class StartupSweepWallClock implements ClockPort {
  /// Creates the app wall clock.
  const StartupSweepWallClock();

  static final CapabilityDescriptor _descriptor = CapabilityDescriptor(
    kind: CapabilityKind.clock,
    adapterId: 'app.startup-clock.v1',
    version: '1',
    isSimulated: false,
    evidence: CapabilityEvidence(
      evidenceClass: EvidenceClass.none,
      adapterId: 'app.startup-clock.v1',
    ),
    supportedFeatures: const <String>['utc-wall-clock'],
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}
