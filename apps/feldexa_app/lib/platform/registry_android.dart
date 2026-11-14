// T023 Android adapter registry.
//
// Owner: `apps/feldexa_app/lib/platform/registry_android.dart` (T023).
// Normative sources: constitution Principle II; plan §Architecture Decisions 8;
// `contracts/ports.md` §4.
//
// This file is selected by the conditional import in `registry.dart` on every
// `dart:io` target (Android in production, host VM for unit tests). It must
// never import `feldexa_adapters_simulated`: the Android build graph must not
// be able to reach a simulated adapter, and the dependency-graph test in
// `test/platform_registry_test.dart` asserts that this source has no such
// import.
//
// T027 supplies the Android thin clients; T023 supplies the registry that
// composes them. `AndroidAdapterRegistry` rejects any simulated descriptor at
// construction, so a mistaken wiring fails before the first capability call.

import 'package:feldexa_ports/feldexa_ports.dart';

import 'registry.dart';

/// The real-only adapter registry used by Android builds.
final class AndroidAdapterRegistry extends CapabilityRegistryBase {
  /// Composes [adapters] as the Android production registry.
  ///
  /// Throws [SimulatedInProductionException] if any descriptor is simulated or
  /// is not `EvidenceClass.none`.
  AndroidAdapterRegistry(PlatformAdapterSet adapters)
    : super(adapters: adapters, policy: RegistryEvidencePolicy.androidReal);
}

/// Conditional-import entrypoint selected by `registry.dart` on `dart:io`.
AdapterRegistry createPlatformRegistry(PlatformAdapterSet adapters) {
  return AndroidAdapterRegistry(adapters);
}
