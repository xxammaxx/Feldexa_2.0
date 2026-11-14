// T013 `ClockPort` interface.
//
// Owner: `packages/feldexa_ports/lib/src/ports/clock_port.dart` (T013).
// Normative source: `contracts/ports.md` §2.8.
//
// Production uses the system clock; tests inject a fixed clock so revision and
// recovery timestamps are deterministic.

import '../descriptor.dart';

/// Provides the current UTC wall clock (`contracts/ports.md` §2.8).
abstract interface class ClockPort implements PlatformCapability {
  /// Returns the current time in UTC.
  DateTime nowUtc();
}
