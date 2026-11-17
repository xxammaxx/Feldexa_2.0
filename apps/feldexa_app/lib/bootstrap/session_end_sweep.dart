// T031 production session-end caller for the export-preview cleanup.
//
// Owner: `apps/feldexa_app/lib/bootstrap/session_end_sweep.dart` (T031).
//
// `contracts/storage-format.md` §4 step 4 ends with "Delete export artifacts
// older than 24 h and any on session end", and `plan.md` §Constraints requires
// preview sweeping "on startup/session end". `StartupSweep.sweepSessionEnd()`
// implemented the age-independent removal, but before this file nothing in
// production called it: only tests did. This binding is the production caller.
//
// The documented lifecycle point available to the app shell is Flutter's own
// application lifecycle: the app process no longer owns a foreground editing
// session when the framework reports `paused` (backgrounded) or `detached`
// (view/engine going away). Both are session-end conditions for the current
// shell; `resumed`, `inactive`, and `hidden` are not, and `inactive` in
// particular happens on transient focus loss, which must not sweep.
//
// Scope safety: the callback only invokes `sweepSessionEnd()`, which touches the
// dedicated cache-directory export artifacts. It cannot reach a document,
// template, revision, source, or KEK alias. The session-end path is independent
// of the startup bounds and of the startup cancellation token: it is a bounded
// single-directory removal, and a failure is reported to the sweep's own
// removal counts rather than thrown into the framework.

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'startup_sweep.dart';

/// Production caller of [StartupSweep.sweepSessionEnd] on session end.
///
/// Register it with `WidgetsBinding.instance.addObserver` and remove it again in
/// the owner's `dispose`. The app shell (`FeldexaApp`) is that owner.
final class SessionEndSweepBinding extends WidgetsBindingObserver {
  /// Creates the binding for [sweep].
  ///
  /// [onError] receives an unexpected failure so the owner can record it; the
  /// framework callback itself never throws.
  SessionEndSweepBinding({required this.sweep, this.onError});

  /// The sweep whose export-preview directory is cleaned at session end.
  final StartupSweep sweep;

  /// Optional redacted failure hook; receives no path, name, or content.
  final void Function(Object error)? onError;

  /// Lifecycle states that end the current editing session for this shell.
  static const Set<AppLifecycleState> sessionEndStates = <AppLifecycleState>{
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  };

  Future<StartupSweepRemoval?>? _inFlight;
  Future<StartupSweepRemoval?>? _lastRun;

  /// The last session-end run, or `null` when none has started.
  ///
  /// Production never awaits this; it exists so tests can settle the run
  /// deterministically.
  Future<StartupSweepRemoval?>? get pending => _lastRun;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!sessionEndStates.contains(state)) {
      return;
    }
    // The framework callback is synchronous; the removal is not. Starting it
    // here and keeping the handle means a second lifecycle event does not start
    // a competing pass over the same directory. A later session may sweep
    // again, because the guard is released when the pass finishes.
    if (_inFlight != null) {
      return;
    }
    final Future<StartupSweepRemoval?> running = _run();
    _inFlight = running;
    _lastRun = running;
    unawaited(
      running.whenComplete(() {
        if (identical(_inFlight, running)) {
          _inFlight = null;
        }
      }),
    );
  }

  Future<StartupSweepRemoval?> _run() async {
    try {
      return await sweep.sweepSessionEnd();
    } catch (error) {
      onError?.call(error);
      return null;
    }
  }

  @override
  String toString() =>
      'SessionEndSweepBinding(states: '
      '${sessionEndStates.map((AppLifecycleState s) => s.name).join(',')})';
}
