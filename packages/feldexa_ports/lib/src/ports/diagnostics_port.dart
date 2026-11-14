// T013 `DiagnosticsPort` interface.
//
// Owner: `packages/feldexa_ports/lib/src/ports/diagnostics_port.dart` (T013).
// Normative source: `contracts/ports.md` §2.9.
//
// Diagnostics are on-device only and are never transmitted. Events carry no
// document content, names, text, values, signatures, or paths; scalar fields
// are limited to enums, counts, durations, and error codes. The implementation
// uses a size-capped ring buffer.

import '../descriptor.dart';

/// Records content-free diagnostic events (`contracts/ports.md` §2.9).
abstract interface class DiagnosticsPort implements PlatformCapability {
  /// Records one event identified by a stable machine [code].
  ///
  /// [scalarFields] must contain only enums, counts, durations, or error codes,
  /// never document content, names, text, values, or paths.
  void event(String code, {Map<String, Object?> scalarFields = const {}});

  /// Clears the on-device event buffer.
  Future<void> clear();
}
