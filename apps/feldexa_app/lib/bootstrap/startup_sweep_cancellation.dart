// T031 cooperative cancellation for the startup sweep.
//
// Owner: `apps/feldexa_app/lib/bootstrap/startup_sweep_cancellation.dart`
// (T031).
//
// Why this exists: `runStartupSweepBounded` bounds the CALLER'S wait. Dart has
// no cancellation for an arbitrary future, so a plain `Future.timeout` would
// leave a timed-out sweep performing native recovery, store reads, and
// directory deletions after the shell already showed the start area. That is
// post-timeout destructive work, and a comment saying "not stopped" is not a
// fix.
//
// This token is the cooperative stop signal. `StartupSweep.run()` checks it
// before every read and before every deletion, so once the bounded runner
// reports a timeout the sweep stops at the next check and performs no further
// store read or deletion. The checkpoints are documented on `run()`.
//
// It is deliberately tiny and dependency-free so both the Web and the Android
// compositions can import it.

/// One cooperative stop signal shared by a bounded runner and a sweep.
final class StartupSweepCancellation {
  /// Creates a token that is not cancelled yet.
  StartupSweepCancellation();

  bool _cancelled = false;

  /// Whether [cancel] has been requested.
  bool get isCancelled => _cancelled;

  /// Requests the sweep to stop at its next checkpoint.
  ///
  /// Idempotent: cancelling twice keeps the same state.
  void cancel() {
    _cancelled = true;
  }

  @override
  String toString() => 'StartupSweepCancellation(cancelled: $_cancelled)';
}
