// T023 registry test support.
//
// Shared fakes for the host-VM and browser registry tests. They implement the
// ten ports only far enough to expose descriptor metadata; calling a capability
// method fails with [UnimplementedError], which keeps these tests about
// registry composition and evidence separation rather than adapter behaviour.

import 'package:feldexa_app/platform/registry.dart';
import 'package:feldexa_ports/feldexa_ports.dart';

/// Builds a deterministic descriptor for [kind].
///
/// Android descriptors use `EvidenceClass.none` and Web descriptors use
/// `EvidenceClass.simulated`, matching `contracts/ports.md` §1. Pass
/// [evidenceClass] to construct a deliberately mismatched adapter for the
/// negative tests.
CapabilityDescriptor testDescriptor(
  CapabilityKind kind, {
  bool simulated = false,
  EvidenceClass? evidenceClass,
}) {
  final String kindToken = kind.name.toLowerCase();
  final String adapterId = '${simulated ? 'web.sim' : 'android'}.$kindToken.v1';
  final CapabilityEvidence evidence;
  if (simulated) {
    evidence = CapabilityEvidence.simulated(
      adapterId: adapterId,
      simulatedReason: 'web.fixture-adapter',
    );
  } else if (evidenceClass != null) {
    evidence = CapabilityEvidence(
      evidenceClass: evidenceClass,
      adapterId: adapterId,
    );
  } else {
    evidence = CapabilityEvidence.android(adapterId: adapterId);
  }
  return CapabilityDescriptor(
    kind: kind,
    adapterId: adapterId,
    version: '1',
    isSimulated: simulated,
    evidence: evidence,
    supportedFeatures: <String>['tests'],
  );
}

/// A port that carries [descriptor] and fails if a capability method is called.
final class FakeCapabilityPort
    implements
        DocumentImportPort,
        PageRasterPort,
        OcrPort,
        SecureStorePort,
        PdfExportPort,
        DeliveryPort,
        LifecyclePort,
        ClockPort,
        IdPort,
        DiagnosticsPort {
  /// Creates a fake port with [descriptor].
  FakeCapabilityPort(this.descriptor);

  @override
  final CapabilityDescriptor descriptor;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('fake registry port method was called');
  }
}

/// Builds an adapter set whose descriptors follow [descriptors], or one per
/// [CapabilityKind] when omitted.
PlatformAdapterSet testAdapterSet({
  bool simulated = false,
  List<CapabilityDescriptor>? descriptors,
}) {
  final List<CapabilityDescriptor> values =
      descriptors ??
      <CapabilityDescriptor>[
        for (final CapabilityKind kind in CapabilityKind.values)
          testDescriptor(kind, simulated: simulated),
      ];
  if (values.length != CapabilityKind.values.length) {
    throw ArgumentError('test adapter set needs ten descriptors');
  }
  final List<FakeCapabilityPort> ports = <FakeCapabilityPort>[
    for (final CapabilityDescriptor value in values) FakeCapabilityPort(value),
  ];
  return PlatformAdapterSet(
    import: ports[0],
    raster: ports[1],
    ocr: ports[2],
    store: ports[3],
    export: ports[4],
    delivery: ports[5],
    lifecycle: ports[6],
    clock: ports[7],
    ids: ports[8],
    diagnostics: ports[9],
  );
}

/// The ten live ports in registry order.
List<PlatformCapability> registryPorts(AdapterRegistry registry) {
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

/// A registry whose metadata disagrees with the ports it returns.
///
/// Used only to prove that [assertNoSimulatedAdapters] inspects the live
/// capability descriptors and cannot be defeated by a false
/// `hasSimulatedCapabilities` or an empty descriptor list.
final class MetadataLyingRegistry implements AdapterRegistry {
  /// Wraps [delegate] but reports the supplied metadata.
  MetadataLyingRegistry({
    required this.delegate,
    this.hasSimulatedCapabilities = false,
    this.descriptors = const <CapabilityDescriptor>[],
  });

  /// The registry whose live ports are being inspected.
  final AdapterRegistry delegate;

  @override
  final bool hasSimulatedCapabilities;

  @override
  final List<CapabilityDescriptor> descriptors;

  @override
  bool get isDevelopmentEnvironment => delegate.isDevelopmentEnvironment;

  @override
  DocumentImportPort get import => delegate.import;

  @override
  PageRasterPort get raster => delegate.raster;

  @override
  OcrPort get ocr => delegate.ocr;

  @override
  SecureStorePort get store => delegate.store;

  @override
  PdfExportPort get export => delegate.export;

  @override
  DeliveryPort get delivery => delegate.delivery;

  @override
  LifecyclePort get lifecycle => delegate.lifecycle;

  @override
  ClockPort get clock => delegate.clock;

  @override
  IdPort get ids => delegate.ids;

  @override
  DiagnosticsPort get diagnostics => delegate.diagnostics;
}
