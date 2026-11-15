// T028 deterministic inputs shared by the simulated adapters.
//
// `contracts/ports.md` §1 requires every simulated adapter to be deterministic:
// same input → same output, with no wall-clock, randomness, or network. The
// adapters therefore never read the system clock, `Random`, or an HTTP client.
// They receive one [SimulatedAdapterContext], which supplies a fixed UTC
// instant and a monotonic UUIDv4 sequence.
//
// The context is an input to the adapters, not a registered `ClockPort` or
// `IdPort` capability. T028 deliberately does not add a seventh/eighth
// adapter: the Web registry's clock, ids, lifecycle, and diagnostics ports
// remain the T023/T027 composition seam.
library;

/// Fixed, deterministic clock and identity source for SIMULATED adapters.
final class SimulatedAdapterContext {
  /// Creates a context at [fixedUtc] (default: 2026-01-01T12:00:00Z).
  ///
  /// A local [DateTime] is normalised to UTC. The instant never advances on
  /// its own, so two runs with the same inputs produce the same timestamps.
  /// Tests that need a later instant construct a new adapter with a different
  /// context rather than advancing a shared wall clock.
  SimulatedAdapterContext({DateTime? fixedUtc, int firstOrdinal = 1})
    : _fixedUtc = (fixedUtc ?? defaultFixedUtc).toUtc(),
      _nextOrdinal = firstOrdinal {
    if (firstOrdinal < 1) {
      throw ArgumentError('firstOrdinal must be at least 1');
    }
  }

  /// Default deterministic instant used when the caller supplies none.
  static final DateTime defaultFixedUtc = DateTime.utc(2026, 1, 1, 12);

  final DateTime _fixedUtc;
  int _nextOrdinal;

  /// The fixed UTC instant of this context.
  DateTime nowUtc() => _fixedUtc;

  /// Generates the next deterministic lowercase UUIDv4.
  ///
  /// The value is a valid version-4 UUID with the RFC 4122 variant and a
  /// monotonically increasing counter in the final 48 bits. It is unique
  /// within one context and reproducible across runs.
  String newId() {
    final int ordinal = _nextOrdinal++;
    if (ordinal > _maxOrdinal) {
      throw StateError('deterministic UUID sequence exhausted');
    }
    return '00000000-0000-4000-8000-${_hex12(ordinal)}';
  }

  /// Generates a deterministic idempotency key.
  ///
  /// The key uses the same monotonic counter as [newId] but a distinct variant
  /// nibble, so a key never collides with an object id from this context.
  String newIdempotencyKey() {
    final int ordinal = _nextOrdinal++;
    if (ordinal > _maxOrdinal) {
      throw StateError('deterministic idempotency sequence exhausted');
    }
    return '00000000-0000-4000-9000-${_hex12(ordinal)}';
  }

  /// Next sequence number for deterministic ordering that must not depend on
  /// equal fixed timestamps (for example revision retention).
  int nextSequence() => _nextOrdinal++;

  static const int _maxOrdinal = 0xFFFFFFFFFFFF;

  static String _hex12(int value) => value.toRadixString(16).padLeft(12, '0');
}
