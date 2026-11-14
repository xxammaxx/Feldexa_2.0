// T013 `DeliveryPort` interface.
//
// Owner: `packages/feldexa_ports/lib/src/ports/delivery_port.dart` (T013).
// Normative source: `contracts/ports.md` §2.6.
//
// `save` uses the platform document creator, `share` the platform share sheet,
// and `print` the system print flow. The app never requests broad storage
// permission, and a user cancellation is reported as `completed: false`, not as
// an error.

import '../descriptor.dart';
import '../dto/delivery_dto.dart';

/// Hands an exported artifact to the platform (`contracts/ports.md` §2.6).
abstract interface class DeliveryPort implements PlatformCapability {
  /// Delivers the artifact named by [artifactId] via [action].
  Future<DeliveryOutcome> deliver({
    required DeliveryAction action,
    required String artifactId,
  });
}
