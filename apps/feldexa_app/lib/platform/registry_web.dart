// T023 Web development adapter registry.
//
// Owner: `apps/feldexa_app/lib/platform/registry_web.dart` (T023).
// Normative sources: constitution Principle II; plan §Architecture Decisions 8
// and 9; `contracts/ports.md` §1 and §4.
//
// This file is selected by the conditional import in `registry.dart` when the
// Web platform library is available. Every adapter registered through it must
// carry `EvidenceClass.simulated`, including the PDFium page-raster adapter:
// Web rendering is visually real but cannot produce Android runtime evidence.
// A descriptor with any other evidence class is rejected, so browser work can
// never be labelled as Android evidence.
//
// T028 supplies the deterministic SIMULATED adapters; T023 supplies the
// registry and its evidence-separation check. `hasSimulatedCapabilities` is
// always `true` here, which makes the release guard fail fast with `SIM-001`.

import 'package:feldexa_ports/feldexa_ports.dart';

import 'registry.dart';

/// The simulated-only adapter registry used by the Web development surface.
final class WebAdapterRegistry extends CapabilityRegistryBase {
  /// Composes [adapters] as the Web development registry.
  ///
  /// Throws [ArgumentError] if any descriptor is not simulated.
  WebAdapterRegistry(PlatformAdapterSet adapters)
    : super(adapters: adapters, policy: RegistryEvidencePolicy.webSimulated);
}

/// Conditional-import entrypoint selected by `registry.dart` on the Web.
AdapterRegistry createPlatformRegistry(PlatformAdapterSet adapters) {
  return WebAdapterRegistry(adapters);
}
