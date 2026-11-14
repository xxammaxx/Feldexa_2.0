// T023 browser registry selection test.
//
// Evidence class: SIMULATED browser runtime. This proves that the conditional
// import in `registry.dart` selects `registry_web.dart` when the Web platform
// library is available, and that the release guard rejects that simulated
// registry. It proves nothing about Android runtime behavior.

@TestOn('browser')
library;

import 'package:feldexa_app/platform/registry.dart';
import 'package:feldexa_app/platform/registry_web.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/registry_fakes.dart';

void main() {
  test('browser conditional import selects the Web registry', () {
    final AdapterRegistry registry = createRegistry(
      testAdapterSet(simulated: true),
    );

    expect(registry, isA<WebAdapterRegistry>());
    expect(registry.isDevelopmentEnvironment, isTrue);
    expect(registry.hasSimulatedCapabilities, isTrue);
    expect(registry.descriptors, hasLength(CapabilityKind.values.length));
    for (final CapabilityDescriptor descriptor in registry.descriptors) {
      expect(descriptor.evidence.evidenceClass, EvidenceClass.simulated);
      expect(descriptor.evidence.simulated, isTrue);
    }
  });

  test('browser registry rejects Android-labelled adapter evidence', () {
    expect(
      () => createRegistry(testAdapterSet()),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError error) => error.message,
          'message',
          contains('EvidenceClass.simulated'),
        ),
      ),
    );
  });

  test('release guard rejects the simulated Web registry with SIM-001', () {
    expect(
      () => resolveRegistry(
        testAdapterSet(simulated: true),
        isReleaseBuild: true,
      ),
      throwsA(
        isA<SimulatedInProductionException>().having(
          (SimulatedInProductionException error) => error.code,
          'code',
          'SIM-001',
        ),
      ),
    );
    expect(
      () => resolveRegistry(
        testAdapterSet(simulated: true),
        isReleaseBuild: false,
      ),
      returnsNormally,
    );
  });
}
