// T023 explicit adapter registry and release assertion.
//
// Owner: `apps/feldexa_app/lib/platform/registry.dart` (T023).
// Normative sources:
//   * constitution Principle II — platform capabilities are reached only
//     through explicit, injectable interfaces; Web simulations never stand in
//     for Android runtime evidence;
//   * plan §Architecture Decisions 8 — Android and Web registries are selected
//     at compile time via conditional imports, and a production build rejects
//     simulated adapters;
//   * `contracts/ports.md` §4 — one registry per build, exactly one adapter per
//     `CapabilityKind`, and `assertNoSimulatedAdapters`.
//
// The concrete adapter construction is deliberately not part of this task:
// T027 provides the Android thin clients and T028 provides the SIMULATED Web
// adapters. T023 owns the composition seam, the compile-time selection, the
// evidence-separation checks, and the release assertion those adapters will be
// wired through. No adapter package is imported here, so a Web build cannot
// pull Android plugin code and an Android build cannot pull the simulated
// package through this file.

import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;

// Conditional imports are the only selection mechanism allowed by
// `contracts/ports.md` §4 and research.md D-22. The default branch is the
// unsupported target so an unknown compile target fails closed per capability.
import 'registry_unsupported.dart'
    if (dart.library.io) 'registry_android.dart'
    if (dart.library.js_interop) 'registry_web.dart'
    as platform;

/// The complete set of platform adapters supplied to one registry.
///
/// This is the composition input, not a registry. It exists so the bootstrap
/// can build every adapter once and hand the exact set to the compiled-in
/// platform registry. A registry never constructs adapters lazily, because a
/// release build must reject a simulated capability before the first use.
final class PlatformAdapterSet {
  /// Creates a complete adapter set.
  ///
  /// Every port is required; a partial registry is not a valid build state.
  const PlatformAdapterSet({
    required this.import,
    required this.raster,
    required this.ocr,
    required this.store,
    required this.export,
    required this.delivery,
    required this.lifecycle,
    required this.clock,
    required this.ids,
    required this.diagnostics,
  });

  /// Picker, staging, and source verification.
  final DocumentImportPort import;

  /// Page geometry and raster rendering.
  final PageRasterPort raster;

  /// On-device text recognition.
  final OcrPort ocr;

  /// Encrypted document and template store.
  final SecureStorePort store;

  /// Plan validation and flattened PDF export.
  final PdfExportPort export;

  /// Save, share, and print hand-off.
  final DeliveryPort delivery;

  /// Application lifecycle signals.
  final LifecyclePort lifecycle;

  /// UTC wall clock.
  final ClockPort clock;

  /// UUIDv4 and idempotency-key generation.
  final IdPort ids;

  /// Content-free on-device diagnostics.
  final DiagnosticsPort diagnostics;

  /// The ten capabilities in [CapabilityKind] declaration order.
  List<PlatformCapability> get _capabilities => <PlatformCapability>[
    import,
    raster,
    ocr,
    store,
    export,
    delivery,
    lifecycle,
    clock,
    ids,
    diagnostics,
  ];
}

/// The evidence policy a registry enforces at construction time.
///
/// The two values are not interchangeable: an Android registry is real-only,
/// and a Web registry is simulated-only. This is what keeps the Android and
/// browser evidence classes structurally separate instead of relying on a
/// review promise (constitution Principle II; plan §Architecture Decisions 8).
enum RegistryEvidencePolicy {
  /// Production adapters only; every descriptor is `EvidenceClass.none`.
  androidReal,

  /// Web development adapters only; every descriptor is
  /// `EvidenceClass.simulated`, including the PDFium raster adapter.
  webSimulated,
}

/// Shared implementation of the ten-capability registry.
///
/// Platform files (`registry_android.dart` and `registry_web.dart`) are thin
/// subclasses that fix the [RegistryEvidencePolicy]. The constructor validates
/// in release builds too, because a mislabelled adapter must never survive
/// `--release` where assertions are disabled.
abstract class CapabilityRegistryBase implements AdapterRegistry {
  /// Validates [adapters] against [policy] and exposes them read-only.
  ///
  /// Throws [SimulatedInProductionException] if an Android registry receives
  /// any simulated descriptor (the `SIM-001` failure). Throws [ArgumentError]
  /// for a missing, duplicated, misordered, or wrong-evidence descriptor.
  CapabilityRegistryBase({
    required PlatformAdapterSet adapters,
    required RegistryEvidencePolicy policy,
  }) : isDevelopmentEnvironment = policy == RegistryEvidencePolicy.webSimulated,
       _import = adapters.import,
       _raster = adapters.raster,
       _ocr = adapters.ocr,
       _store = adapters.store,
       _export = adapters.export,
       _delivery = adapters.delivery,
       _lifecycle = adapters.lifecycle,
       _clock = adapters.clock,
       _ids = adapters.ids,
       _diagnostics = adapters.diagnostics,
       _descriptors = _validatedDescriptors(adapters, policy) {
    _hasSimulatedCapabilities = _descriptors.any(
      (CapabilityDescriptor value) => value.isSimulated,
    );
  }

  final DocumentImportPort _import;
  final PageRasterPort _raster;
  final OcrPort _ocr;
  final SecureStorePort _store;
  final PdfExportPort _export;
  final DeliveryPort _delivery;
  final LifecyclePort _lifecycle;
  final ClockPort _clock;
  final IdPort _ids;
  final DiagnosticsPort _diagnostics;
  final List<CapabilityDescriptor> _descriptors;

  late final bool _hasSimulatedCapabilities;

  @override
  final bool isDevelopmentEnvironment;

  @override
  bool get hasSimulatedCapabilities => _hasSimulatedCapabilities;

  @override
  List<CapabilityDescriptor> get descriptors => _descriptors;

  @override
  DocumentImportPort get import => _import;

  @override
  PageRasterPort get raster => _raster;

  @override
  OcrPort get ocr => _ocr;

  @override
  SecureStorePort get store => _store;

  @override
  PdfExportPort get export => _export;

  @override
  DeliveryPort get delivery => _delivery;

  @override
  LifecyclePort get lifecycle => _lifecycle;

  @override
  ClockPort get clock => _clock;

  @override
  IdPort get ids => _ids;

  @override
  DiagnosticsPort get diagnostics => _diagnostics;

  static List<CapabilityDescriptor> _validatedDescriptors(
    PlatformAdapterSet adapters,
    RegistryEvidencePolicy policy,
  ) {
    final List<PlatformCapability> capabilities = adapters._capabilities;
    final List<CapabilityDescriptor> descriptors = <CapabilityDescriptor>[];
    for (int index = 0; index < capabilities.length; index++) {
      final CapabilityDescriptor descriptor = capabilities[index].descriptor;
      final CapabilityKind expected = CapabilityKind.values[index];
      if (descriptor.kind != expected) {
        throw ArgumentError(
          'adapter at index $index must describe ${expected.name}, not '
          '${descriptor.kind.name}',
        );
      }
      _validateEvidence(descriptor, policy, index);
      descriptors.add(descriptor);
    }
    return List<CapabilityDescriptor>.unmodifiable(descriptors);
  }

  static void _validateEvidence(
    CapabilityDescriptor descriptor,
    RegistryEvidencePolicy policy,
    int index,
  ) {
    final EvidenceClass evidenceClass = descriptor.evidence.evidenceClass;
    switch (policy) {
      case RegistryEvidencePolicy.androidReal:
        if (descriptor.isSimulated ||
            descriptor.evidence.simulated ||
            evidenceClass == EvidenceClass.simulated) {
          // Android must never resolve a simulated or browser-labelled
          // capability, not even in a debug build. SIM-001 is the canonical
          // failure and it carries no document, path, or adapter content.
          throw SimulatedInProductionException();
        }
        if (evidenceClass != EvidenceClass.none) {
          throw ArgumentError(
            'Android adapter at index $index must declare EvidenceClass.none; '
            'the test harness attaches EMULATOR or DEVICE to the run',
          );
        }
      case RegistryEvidencePolicy.webSimulated:
        if (!descriptor.isSimulated ||
            !descriptor.evidence.simulated ||
            evidenceClass != EvidenceClass.simulated) {
          throw ArgumentError(
            'Web registry adapter at index $index must carry '
            'EvidenceClass.simulated; browser work never claims real or '
            'Android runtime evidence',
          );
        }
    }
  }
}

/// Creates the registry selected for the current compile target.
///
/// On an `dart:io` target this is [platform.createPlatformRegistry] from
/// `registry_android.dart`; on the Web it is the same entrypoint from
/// `registry_web.dart`; any other target uses `registry_unsupported.dart`.
/// The selected factory validates the adapter evidence and returns an
/// immutable registry.
AdapterRegistry createRegistry(PlatformAdapterSet adapters) {
  return platform.createPlatformRegistry(adapters);
}

/// Resolves the one registry for this build and applies the release guard.
///
/// [isReleaseBuild] defaults to Flutter's compile-time [kReleaseMode]. Tests
/// may override it explicitly to exercise both branches on the host VM; the
/// default is never overridden by application code.
///
/// In a release build a registry that exposes any simulated capability throws
/// [SimulatedInProductionException] (`SIM-001`) before it is returned. Web
/// development builds keep their registry and its `SIMULATED` labels; they are
/// never accepted as Android runtime evidence.
AdapterRegistry resolveRegistry(
  PlatformAdapterSet adapters, {
  bool isReleaseBuild = kReleaseMode,
}) {
  final AdapterRegistry registry = createRegistry(adapters);
  if (isReleaseBuild) {
    assertNoSimulatedAdapters(registry);
  }
  return registry;
}

/// Fails fast with `SIM-001` if [registry] can expose a simulated capability.
///
/// The check inspects the live port descriptors as well as
/// [AdapterRegistry.hasSimulatedCapabilities] and
/// [AdapterRegistry.descriptors], so a registry whose metadata disagrees with
/// the adapters it returns is still rejected. A production bootstrap calls
/// this behind [kReleaseMode]; tests call it directly for both classes of
/// evidence.
void assertNoSimulatedAdapters(AdapterRegistry registry) {
  for (final PlatformCapability capability in _capabilityPorts(registry)) {
    final CapabilityDescriptor descriptor = capability.descriptor;
    if (descriptor.isSimulated ||
        descriptor.evidence.simulated ||
        descriptor.evidence.evidenceClass == EvidenceClass.simulated) {
      throw SimulatedInProductionException();
    }
  }
  if (registry.hasSimulatedCapabilities) {
    throw SimulatedInProductionException();
  }
  for (final CapabilityDescriptor descriptor in registry.descriptors) {
    if (descriptor.isSimulated ||
        descriptor.evidence.simulated ||
        descriptor.evidence.evidenceClass == EvidenceClass.simulated) {
      throw SimulatedInProductionException();
    }
  }
}

List<PlatformCapability> _capabilityPorts(AdapterRegistry registry) {
  return <PlatformCapability>[
    registry.import,
    registry.raster,
    registry.ocr,
    registry.store,
    registry.export,
    registry.delivery,
    registry.lifecycle,
    registry.clock,
    registry.ids,
    registry.diagnostics,
  ];
}
