// T011 deterministic clock.
//
// The production ClockPort contract (contracts/ports.md §2.8) is
// `DateTime nowUtc()`. This fake matches that method shape so later tasks can
// add the port interface without rewriting the tests that use it.
//
// The clock is manual: no timer runs and no wall-clock value is read. Tests
// advance it explicitly, which makes debounce and timeout assertions
// deterministic on every machine.

import '../evidence/evidence.dart';

/// A deterministic, manually advanced UTC clock.
final class FakeClock {
  /// Creates a clock at [initialUtc], or at the Unix epoch when omitted.
  ///
  /// A local [DateTime] is normalised to UTC so [nowUtc] never leaks the test
  /// machine's time zone.
  FakeClock({DateTime? initialUtc})
    : _now = (initialUtc ?? _epoch).toUtc(),
      _startedAt = (initialUtc ?? _epoch).toUtc();

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );

  DateTime _now;
  final DateTime _startedAt;
  int _readCount = 0;

  /// The ClockPort-shaped read method. Each call counts as one read.
  DateTime nowUtc() {
    _readCount++;
    return _now;
  }

  /// The current instant without counting a read.
  DateTime get currentUtc => _now;

  /// The instant this clock was created at.
  DateTime get startedAt => _startedAt;

  /// Elapsed fake time since creation.
  Duration get elapsed => _now.difference(_startedAt);

  /// Number of [nowUtc] calls, useful for asserting polling behaviour.
  int get readCount => _readCount;

  /// The clock is host-side scaffolding and never runtime evidence.
  EvidenceLabel get evidence => const EvidenceLabel.hostVm(
    'host-vm',
    'FakeClock: deterministic test time source, not runtime evidence',
  );

  /// Advances by [by]. A negative duration is rejected: rewinding time would
  /// hide debounce and ordering bugs. Use [setUtc] for an explicit rewind.
  void advance(Duration by) {
    if (by.isNegative) {
      throw ArgumentError.value(
        by,
        'by',
        'FakeClock only advances forward; use setUtc for an explicit rewind',
      );
    }
    _now = _now.add(by);
  }

  /// Advances to [instant], which must not be before the current instant.
  void advanceTo(DateTime instant) {
    final DateTime target = instant.toUtc();
    if (target.isBefore(_now)) {
      throw ArgumentError.value(
        instant,
        'instant',
        'FakeClock.advanceTo cannot move backwards; use setUtc',
      );
    }
    _now = target;
  }

  /// Sets the clock explicitly, including backwards.
  void setUtc(DateTime instant) {
    _now = instant.toUtc();
  }

  /// Returns the clock to its creation instant and resets the read count.
  void reset() {
    _now = _startedAt;
    _readCount = 0;
  }
}
