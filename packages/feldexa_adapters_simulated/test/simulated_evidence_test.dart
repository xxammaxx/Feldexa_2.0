// T028 evidence and determinism tests.
//
// A simulated adapter is useful only if it is impossible to mistake for
// Android evidence. These tests assert the SIMULATED label on every adapter and
// that the deterministic input context never leaks wall-clock time or
// randomness.

import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/simulated_world.dart';

void main() {
  test(
    'all six adapters carry SIMULATED evidence and the right capability',
    () async {
      final world = await SimulatedTestWorld.create();
      final Map<CapabilityKind, PlatformCapability> adapters =
          <CapabilityKind, PlatformCapability>{
            CapabilityKind.documentImport: world.importAdapter,
            CapabilityKind.pageRaster: world.rasterAdapter,
            CapabilityKind.ocr: world.ocrAdapter,
            CapabilityKind.secureStore: world.storeAdapter,
            CapabilityKind.pdfExport: world.exportAdapter,
            CapabilityKind.delivery: world.deliveryAdapter,
          };
      final Set<String> expectedIds = <String>{
        simulatedImportAdapterId,
        simulatedRasterAdapterId,
        simulatedOcrAdapterId,
        simulatedStoreAdapterId,
        simulatedExportAdapterId,
        simulatedDeliveryAdapterId,
      };
      for (final MapEntry<CapabilityKind, PlatformCapability> entry
          in adapters.entries) {
        final CapabilityDescriptor descriptor = entry.value.descriptor;
        expect(descriptor.kind, entry.key);
        expect(descriptor.version, simulatedAdapterVersion);
        expect(descriptor.isSimulated, isTrue, reason: entry.key.name);
        expect(descriptor.evidence.simulated, isTrue, reason: entry.key.name);
        expect(
          descriptor.evidence.evidenceClass,
          EvidenceClass.simulated,
          reason: entry.key.name,
        );
        expect(descriptor.evidence.simulatedReason, simulatedReasonToken);
        expect(descriptor.supportedFeatures, isNotEmpty);
        expect(expectedIds, contains(descriptor.adapterId));
      }
    },
  );

  test('no adapter claims EMULATOR, DEVICE, or unlabelled evidence', () async {
    final world = await SimulatedTestWorld.create();
    final List<CapabilityDescriptor> descriptors = <CapabilityDescriptor>[
      world.importAdapter.descriptor,
      world.rasterAdapter.descriptor,
      world.ocrAdapter.descriptor,
      world.storeAdapter.descriptor,
      world.exportAdapter.descriptor,
      world.deliveryAdapter.descriptor,
    ];
    for (final CapabilityDescriptor descriptor in descriptors) {
      expect(descriptor.evidence.evidenceClass, isNot(EvidenceClass.emulator));
      expect(descriptor.evidence.evidenceClass, isNot(EvidenceClass.device));
      expect(descriptor.evidence.evidenceClass, isNot(EvidenceClass.none));
    }
  });

  test('the deterministic context has a fixed UTC instant and stable ids', () {
    final SimulatedAdapterContext first = SimulatedAdapterContext();
    final SimulatedAdapterContext second = SimulatedAdapterContext();
    expect(first.nowUtc(), DateTime.utc(2026, 1, 1, 12));
    expect(first.nowUtc().isUtc, isTrue);
    expect(first.nowUtc(), second.nowUtc());
    final String firstUuid = first.newId();
    expect(firstUuid, second.newId());
    final String secondUuid = first.newId();
    expect(secondUuid, isNot(firstUuid));
    final String uuid = first.newId();
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(uuid),
      isTrue,
    );
    expect(first.newIdempotencyKey(), isNot(uuid));
  });

  test('a custom fixed instant is normalised to UTC', () {
    final SimulatedAdapterContext context = SimulatedAdapterContext(
      fixedUtc: DateTime(2030, 5, 4, 3, 2, 1),
    );
    expect(context.nowUtc().isUtc, isTrue);
    expect(context.nowUtc(), DateTime(2030, 5, 4, 3, 2, 1).toUtc());
  });

  test('descriptor evidence cannot be upgraded by a caller', () async {
    final world = await SimulatedTestWorld.create();
    expect(
      () => CapabilityEvidence(
        evidenceClass: EvidenceClass.none,
        adapterId: simulatedStoreAdapterId,
        simulatedReason: simulatedReasonToken,
      ),
      throwsArgumentError,
    );
    expect(
      world.storeAdapter.descriptor.evidence.evidenceClass,
      EvidenceClass.simulated,
    );
  });
}
