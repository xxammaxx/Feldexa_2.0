// T013 `IdPort` interface.
//
// Owner: `packages/feldexa_ports/lib/src/ports/id_port.dart` (T013).
// Normative source: `contracts/ports.md` §2.8.
//
// Production uses UUIDv4 and `Random.secure()`; tests inject a deterministic ID
// sequence so revisions and navigation are reproducible.

import '../descriptor.dart';

/// Generates object identities and idempotency keys
/// (`contracts/ports.md` §2.8).
abstract interface class IdPort implements PlatformCapability {
  /// Returns a new UUIDv4 in lowercase canonical form.
  String newId();

  /// Returns a new idempotency key for a retryable write.
  String newIdempotencyKey();
}
