// T013 `LifecyclePort` interface.
//
// Owner: `packages/feldexa_ports/lib/src/ports/lifecycle_port.dart` (T013).
// Normative source: `contracts/ports.md` §2.7.
//
// `paused` and `inactive` trigger the autosave flush attempt before the app may
// be killed. Delivery is best-effort at OS level; the last verified commit is
// the only durability claim.

import '../descriptor.dart';
import '../dto/lifecycle_dto.dart';

/// Delivers application lifecycle signals (`contracts/ports.md` §2.7).
abstract interface class LifecyclePort implements PlatformCapability {
  /// The current and future lifecycle signals, in platform order.
  Stream<AppLifecycleSignal> get signals;
}
