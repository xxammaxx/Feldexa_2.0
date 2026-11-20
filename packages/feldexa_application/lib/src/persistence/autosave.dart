// T089 debounced autosave coordinator.
//
// Owner: `packages/feldexa_application/lib/src/persistence/autosave.dart`
// (T089).
// Normative sources:
//   * `research.md` D-08/D-09 — verified commits, a 2 s debounce, foreground
//     flush, and a single writer with coalesced follow-up revisions;
//   * `spec.md` FR-045/FR-046/FR-047 and SC-020 — bounded loss, honest
//     durability reporting, and read-back-verified success;
//   * `contracts/ports.md` §2.4/§2.7 — `SecureStorePort` and `LifecyclePort`;
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// The coordinator deliberately performs no storage read-back of its own:
// `SecureStorePort.saveRevision` returns success only after the adapter has
// verified the written revision and head. At most one save is in flight;
// changes that arrive meanwhile coalesce into one follow-up revision that uses
// the latest content snapshot and the latest durable head.
//
// Every failure is content-free: only stable catalog codes are exposed, and no
// document text, field value, signature byte, path, or raw exception detail is
// logged or embedded in a status.

// A private field cannot use an initializing formal with a public named
// parameter; the explicit initializer is intentional.
// ignore_for_file: prefer_initializing_formals
library;

import 'dart:async';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';

/// Coordinates debounced autosaves, lifecycle flushes, and explicit saves for
/// one document (T089).
///
/// The caller supplies the current content snapshot through [content]. The
/// coordinator never mutates the document and never inspects the snapshot; it
/// only passes the latest snapshot to [SecureStorePort.saveRevision] and
/// reports the durability state derived from the verified result.
final class AutosaveCoordinator {
  /// Creates a coordinator for one document.
  ///
  /// [documentId] and [initialHead], when present, must be lowercase UUIDv4
  /// values; the same values are validated again by [SaveRevisionRequest]
  /// before every write. [initialHead] is the last verified revision, or null
  /// before the first revision exists. [debounce] is the quiet period after the
  /// latest [markDirty] call; it must not be negative.
  ///
  /// The lifecycle subscription is created immediately. Call [dispose] to
  /// cancel it and the debounce timer.
  AutosaveCoordinator({
    required SecureStorePort store,
    required ClockPort clock,
    required LifecyclePort lifecycle,
    required String documentId,
    required RevisionContent Function() content,
    String? initialHead,
    Duration debounce = const Duration(seconds: 2),
  }) : _store = store,
       _clock = clock,
       _content = content,
       _documentId = _requireUuidV4(documentId, 'documentId'),
       _lastDurableRevisionId = initialHead == null
           ? null
           : _requireUuidV4(initialHead, 'initialHead'),
       _debounce = debounce,
       _status = initialHead == null
           ? DurabilityStatus.unsaved
           : DurabilityStatus.clean {
    if (debounce.isNegative) {
      throw ArgumentError('debounce must not be negative');
    }
    _lifecycleSubscription = lifecycle.signals.listen(_handleLifecycleSignal);
  }

  final SecureStorePort _store;
  final ClockPort _clock;
  final RevisionContent Function() _content;
  final String _documentId;
  final Duration _debounce;

  DurabilityStatus _status;
  String? _lastDurableRevisionId;
  DateTime? _lastDurableAt;
  bool _hasPendingChanges = false;
  bool _disposed = false;

  Timer? _debounceTimer;
  StreamSubscription<AppLifecycleSignal>? _lifecycleSubscription;

  bool _saveInFlight = false;
  RevisionKind? _queuedFollowUpKind;
  List<Completer<bool>> _queuedWaiters = <Completer<bool>>[];
  List<Completer<bool>>? _activeWaiters;

  /// The change generation captured by the save currently in flight.
  int? _activeSaveGeneration;

  /// The last change generation captured by a save.
  int _changeGeneration = 0;

  /// The current durability state.
  ///
  /// It is [DurabilityStatus.clean] or [DurabilityStatus.saved] only while every
  /// in-memory change has a verified revision.
  DurabilityStatus get status => _status;

  /// UUIDv4 of the last verified revision, or null before the first one.
  String? get lastDurableRevisionId => _lastDurableRevisionId;

  /// When the last verified save completed, in UTC, or null before the first
  /// verified save of this coordinator.
  DateTime? get lastDurableAt => _lastDurableAt;

  /// Whether an in-memory change has no verified revision yet.
  bool get hasPendingChanges => _hasPendingChanges;

  /// Marks the in-memory document as changed and restarts the debounce timer.
  ///
  /// No save starts before [debounce] has elapsed after the latest mark. A
  /// call during an in-flight save keeps the [DurabilityStatus.saving] state;
  /// the change is captured by the coalesced follow-up revision.
  void markDirty() {
    if (_disposed) {
      return;
    }
    _hasPendingChanges = true;
    _changeGeneration++;
    _status = _saveInFlight
        ? DurabilityStatus.saving
        : DurabilityStatus.unsaved;
    _restartDebounceTimer();
  }

  /// Saves the latest content snapshot now.
  ///
  /// A non-explicit flush with no pending change is a no-op that returns false
  /// and leaves the status untouched. An explicit flush saves even when
  /// [hasPendingChanges] is false and uses [RevisionKind.explicit].
  ///
  /// Returns true only after [SecureStorePort.saveRevision] verified the save
  /// requested by this call. It returns false for a no-op, a disposed
  /// coordinator, or a failed save. A non-explicit call during an in-flight
  /// save joins that save when no newer change exists, and otherwise queues a
  /// coalesced follow-up revision; an explicit call always queues an explicit
  /// follow-up and resolves after it.
  Future<bool> flush({bool explicit = false}) {
    if (_disposed) {
      return Future<bool>.value(false);
    }
    _cancelDebounceTimer();
    if (!explicit && !_hasPendingChanges) {
      return Future<bool>.value(false);
    }
    return _startOrQueueSave(
      explicit ? RevisionKind.explicit : RevisionKind.autosave,
    );
  }

  /// Stops timers and lifecycle handling and completes outstanding flush calls
  /// with false.
  ///
  /// Later [markDirty] and [flush] calls are no-ops. A write that was already in
  /// flight is allowed to finish, but no follow-up revision is started.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _cancelDebounceTimer();
    final StreamSubscription<AppLifecycleSignal>? subscription =
        _lifecycleSubscription;
    _lifecycleSubscription = null;
    _queuedFollowUpKind = null;

    final List<Completer<bool>> outstanding = <Completer<bool>>[
      ...?_activeWaiters,
      ..._queuedWaiters,
    ];
    _activeWaiters = null;
    _queuedWaiters = <Completer<bool>>[];
    _completeWaiters(outstanding, false);

    await subscription?.cancel();
  }

  void _restartDebounceTimer() {
    _cancelDebounceTimer();
    _debounceTimer = Timer(_debounce, _handleDebounceElapsed);
  }

  void _cancelDebounceTimer() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  void _handleDebounceElapsed() {
    _debounceTimer = null;
    if (_disposed || !_hasPendingChanges) {
      return;
    }
    // The timer has no caller; the returned future is drained by the save loop
    // and every failure is converted into a status inside `_saveOnce`.
    unawaited(_startOrQueueSave(RevisionKind.autosave));
  }

  void _handleLifecycleSignal(AppLifecycleSignal signal) {
    if (_disposed) {
      return;
    }
    switch (signal) {
      case AppLifecycleSignal.paused:
      case AppLifecycleSignal.inactive:
      case AppLifecycleSignal.detached:
        if (_hasPendingChanges) {
          unawaited(flush());
        }
      case AppLifecycleSignal.resumed:
        break;
    }
  }

  Future<bool> _startOrQueueSave(RevisionKind kind) {
    if (_disposed) {
      return Future<bool>.value(false);
    }
    if (_saveInFlight) {
      final bool noNewChanges = _changeGeneration == _activeSaveGeneration;
      final List<Completer<bool>>? active = _activeWaiters;
      if (kind != RevisionKind.explicit && noNewChanges && active != null) {
        // The active save already captures every change this caller needs to
        // persist. Join its verified completion instead of queueing an
        // identical follow-up revision (for example lifecycle inactive then
        // paused with one pending change).
        final Completer<bool> waiter = Completer<bool>();
        active.add(waiter);
        return waiter.future;
      }
      _queuedFollowUpKind = _upgradeKind(_queuedFollowUpKind, kind);
      final Completer<bool> queued = Completer<bool>();
      _queuedWaiters.add(queued);
      return queued.future;
    }

    final Completer<bool> completer = Completer<bool>();
    _saveInFlight = true;
    _status = DurabilityStatus.saving;
    unawaited(_drainSaves(kind, completer));
    return completer.future;
  }

  Future<void> _drainSaves(
    RevisionKind firstKind,
    Completer<bool> first,
  ) async {
    RevisionKind? kind = firstKind;
    List<Completer<bool>> waiters = <Completer<bool>>[first];

    while (kind != null) {
      if (_disposed) {
        _completeWaiters(waiters, false);
        break;
      }
      _activeWaiters = waiters;
      _status = DurabilityStatus.saving;
      final bool success = await _saveOnce(kind);
      _activeWaiters = null;

      if (_disposed) {
        _completeWaiters(waiters, false);
      } else {
        _completeWaiters(waiters, success);
      }

      if (!success || _disposed) {
        // A failure stops automatic retries until a later mark or flush.
        _cancelDebounceTimer();
        _queuedFollowUpKind = null;
        final List<Completer<bool>> queued = _queuedWaiters;
        _queuedWaiters = <Completer<bool>>[];
        _completeWaiters(queued, false);
        break;
      }

      kind = _queuedFollowUpKind;
      _queuedFollowUpKind = null;
      waiters = _queuedWaiters;
      _queuedWaiters = <Completer<bool>>[];
    }

    _activeSaveGeneration = null;
    _saveInFlight = false;
  }

  Future<bool> _saveOnce(RevisionKind kind) async {
    final String? expectedHead = _lastDurableRevisionId;
    try {
      final RevisionContent snapshot = _content();
      final int snapshotGeneration = _changeGeneration;
      _activeSaveGeneration = snapshotGeneration;
      final StoredMeta stored = await _store.saveRevision(
        SaveRevisionRequest(
          documentId: _documentId,
          expectedHead: expectedHead,
          content: snapshot,
          kind: kind,
        ),
      );
      final DateTime durableAt = _clock.nowUtc();
      _lastDurableRevisionId =
          stored.latestRevisionId ?? _lastDurableRevisionId;
      _lastDurableAt = durableAt;
      if (_changeGeneration == snapshotGeneration) {
        _hasPendingChanges = false;
        _status = DurabilityStatus.saved(lastDurableAt: durableAt);
      } else {
        // A newer change arrived while this revision was in flight. It needs
        // its own verified revision before the document is durable again.
        _hasPendingChanges = true;
        _status = DurabilityStatus.unsaved;
      }
      return true;
    } on FeldexaException catch (error) {
      // The previous durable head/time and the pending flag are preserved; a
      // failed revision never clears unsaved changes.
      _status = DurabilityStatus.saveFailed(error.code);
      return false;
    } catch (_) {
      // Unexpected failures must not escape a timer callback. The write-side
      // catalog code is the closest honest claim; no detail is exposed.
      _status = DurabilityStatus.saveFailed('SAVE-003');
      return false;
    }
  }

  static void _completeWaiters(Iterable<Completer<bool>> waiters, bool value) {
    for (final Completer<bool> waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.complete(value);
      }
    }
  }

  static RevisionKind _upgradeKind(
    RevisionKind? current,
    RevisionKind requested,
  ) {
    if (current == RevisionKind.explicit ||
        requested == RevisionKind.explicit) {
      return RevisionKind.explicit;
    }
    return requested;
  }
}

String _requireUuidV4(String value, String name) {
  if (!_uuidV4Pattern.hasMatch(value)) {
    // Never echo the rejected value.
    throw ArgumentError('$name must be a lowercase UUIDv4');
  }
  return value;
}

final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
