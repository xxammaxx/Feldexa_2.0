// T031 startup wiring: bounded, failure-safe invocation of the sweep.
//
// Owner: `apps/feldexa_app/lib/bootstrap/startup_sweep_bootstrap.dart` (T031).
//
// The application shell must never crash, hang, or claim a startup success it
// did not achieve. This file owns the bounded wait and the conversion of an
// unexpected failure into a degraded startup state. It imports no platform
// adapter and no `dart:io`, so the Web build can use it unchanged.
//
// The wall clock here is a real app clock (`EvidenceClass.none`), not a
// simulated adapter: it is the production wall clock for the startup sweep,
// not a fixture.

import 'dart:async';

import 'package:feldexa_ports/feldexa_ports.dart';

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

  @override
  String toString() =>
      'StartupSweepStartup(timedOut: $timedOut, failed: $failed, '
      'degraded: $isDegraded)';
}

/// One startup sweep invocation.
typedef StartupSweepRun = Future<StartupSweepResult> Function();

/// Runs [run] with a hard upper bound and converts every failure to a state.
///
/// The caller receives a value on every path:
/// * a completed sweep result;
/// * [StartupSweepStartup.timedOut] when [timeout] expires;
/// * [StartupSweepStartup.failed] when [run] throws synchronously or
///   asynchronously.
///
/// A timed-out operation is not cancelled (Dart has no cancellation for an
/// arbitrary future), but its eventual error is consumed so it cannot become
/// an unhandled asynchronous error later. It can only continue to touch the
/// dedicated cache directory, which is safe by the sweep's contract.
Future<StartupSweepStartup> runStartupSweepBounded({
  required StartupSweepRun run,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final Future<StartupSweepResult> operation;
  try {
    operation = run();
  } catch (_) {
    return const StartupSweepStartup(failed: true);
  }
  try {
    final StartupSweepResult result = await operation.timeout(timeout);
    return StartupSweepStartup(result: result);
  } on TimeoutException {
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
