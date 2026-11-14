// T023 host-VM registry tests.
//
// Evidence class: NONE. These are static/host checks for compile-time
// selection, evidence separation, and the structural release assertion. They
// are not SIMULATED browser evidence and they are not EMULATOR or DEVICE
// Android runtime evidence.
//
// The browser half of the selection test lives in
// `test/platform_registry_web_test.dart` and runs only on the browser platform.

@TestOn('vm')
library;

import 'dart:io';

import 'package:feldexa_app/platform/registry.dart';
import 'package:feldexa_app/platform/registry_android.dart';
import 'package:feldexa_app/platform/registry_unsupported.dart';
import 'package:feldexa_app/platform/registry_web.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/registry_fakes.dart';

void main() {
  group('compile-time selection', () {
    test('dart:io selects the Android registry by default', () {
      final AdapterRegistry registry = createRegistry(testAdapterSet());

      expect(registry, isA<AndroidAdapterRegistry>());
      expect(registry.isDevelopmentEnvironment, isFalse);
      expect(registry.hasSimulatedCapabilities, isFalse);
      expect(registry.descriptors, hasLength(CapabilityKind.values.length));
      expect(
        registry.descriptors.map((CapabilityDescriptor value) => value.kind),
        CapabilityKind.values,
      );
      expect(
        registryPorts(registry)
            .map((PlatformCapability value) => value.descriptor),
        registry.descriptors,
      );
      expect(
        () => registry.descriptors.add(testDescriptor(CapabilityKind.clock)),
        throwsUnsupportedError,
      );
    });

    test('the unsupported target fails closed with PLT-001', () {
      const UnsupportedAdapterRegistry registry = UnsupportedAdapterRegistry();
      final List<PlatformCapability Function()> capabilities =
          <PlatformCapability Function()>[
            () => registry.import,
            () => registry.raster,
            () => registry.ocr,
            () => registry.store,
            () => registry.export,
            () => registry.delivery,
            () => registry.lifecycle,
            () => registry.clock,
            () => registry.ids,
            () => registry.diagnostics,
          ];

      expect(registry.isDevelopmentEnvironment, isFalse);
      expect(registry.hasSimulatedCapabilities, isFalse);
      expect(registry.descriptors, isEmpty);
      for (final PlatformCapability Function() capability in capabilities) {
        expect(
          capability,
          throwsA(
            isA<UnsupportedOperationException>().having(
              (UnsupportedOperationException error) => error.code,
              'code',
              'PLT-001',
            ),
          ),
        );
      }
    });
  });

  group('Android registry evidence separation', () {
    test('accepts real Android adapters with EvidenceClass.none', () {
      final AndroidAdapterRegistry registry = AndroidAdapterRegistry(
        testAdapterSet(),
      );

      expect(registry.isDevelopmentEnvironment, isFalse);
      expect(registry.hasSimulatedCapabilities, isFalse);
      for (final CapabilityDescriptor descriptor in registry.descriptors) {
        expect(descriptor.isSimulated, isFalse);
        expect(descriptor.evidence.simulated, isFalse);
        expect(descriptor.evidence.evidenceClass, EvidenceClass.none);
      }
    });

    test('rejects one simulated adapter with SIM-001', () {
      final List<CapabilityDescriptor> descriptors = <CapabilityDescriptor>[
        for (final CapabilityKind kind in CapabilityKind.values)
          testDescriptor(kind, simulated: kind == CapabilityKind.pageRaster),
      ];

      expect(
        () => AndroidAdapterRegistry(testAdapterSet(descriptors: descriptors)),
        throwsA(
          isA<SimulatedInProductionException>().having(
            (SimulatedInProductionException error) => error.code,
            'code',
            'SIM-001',
          ),
        ),
      );
    });

    test('rejects an all-simulated adapter set with SIM-001', () {
      expect(
        () => AndroidAdapterRegistry(testAdapterSet(simulated: true)),
        throwsA(isA<SimulatedInProductionException>()),
      );
    });

    test(
      'rejects an environment-labelled adapter instead of mislabelling it',
      () {
        final List<CapabilityDescriptor> descriptors = <CapabilityDescriptor>[
          for (final CapabilityKind kind in CapabilityKind.values)
            kind == CapabilityKind.ocr
                ? testDescriptor(kind, evidenceClass: EvidenceClass.emulator)
                : testDescriptor(kind),
        ];

        expect(
          () =>
              AndroidAdapterRegistry(testAdapterSet(descriptors: descriptors)),
          throwsArgumentError,
        );
      },
    );

    test('rejects a descriptor in the wrong capability slot', () {
      final List<CapabilityDescriptor> descriptors = <CapabilityDescriptor>[
        for (final CapabilityKind kind in CapabilityKind.values)
          testDescriptor(kind),
      ];
      final CapabilityDescriptor first = descriptors[0];
      descriptors[0] = descriptors[1];
      descriptors[1] = first;

      expect(
        () => AndroidAdapterRegistry(testAdapterSet(descriptors: descriptors)),
        throwsArgumentError,
      );
    });
  });

  group('Web registry evidence separation', () {
    test('accepts simulated-only adapters and reports development mode', () {
      final WebAdapterRegistry registry = WebAdapterRegistry(
        testAdapterSet(simulated: true),
      );

      expect(registry.isDevelopmentEnvironment, isTrue);
      expect(registry.hasSimulatedCapabilities, isTrue);
      expect(registry.descriptors, hasLength(CapabilityKind.values.length));
      for (final CapabilityDescriptor descriptor in registry.descriptors) {
        expect(descriptor.isSimulated, isTrue);
        expect(descriptor.evidence.simulated, isTrue);
        expect(descriptor.evidence.evidenceClass, EvidenceClass.simulated);
      }
    });

    test(
      'rejects an Android-labelled adapter instead of claiming it as Web',
      () {
        final List<CapabilityDescriptor> descriptors = <CapabilityDescriptor>[
          for (final CapabilityKind kind in CapabilityKind.values)
            testDescriptor(kind, simulated: true),
        ];
        descriptors[3] = testDescriptor(CapabilityKind.secureStore);

        expect(
          () => WebAdapterRegistry(testAdapterSet(descriptors: descriptors)),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError error) => error.message,
              'message',
              contains('EvidenceClass.simulated'),
            ),
          ),
        );
      },
    );
  });

  group('release assertion', () {
    test('accepts the real Android registry', () {
      final AndroidAdapterRegistry registry = AndroidAdapterRegistry(
        testAdapterSet(),
      );

      expect(() => assertNoSimulatedAdapters(registry), returnsNormally);
      expect(
        () => resolveRegistry(testAdapterSet(), isReleaseBuild: true),
        returnsNormally,
      );
      expect(
        () => resolveRegistry(testAdapterSet(), isReleaseBuild: false),
        returnsNormally,
      );
    });

    test('rejects a simulated Web registry with SIM-001', () {
      final WebAdapterRegistry registry = WebAdapterRegistry(
        testAdapterSet(simulated: true),
      );

      expect(
        () => assertNoSimulatedAdapters(registry),
        throwsA(
          isA<SimulatedInProductionException>().having(
            (SimulatedInProductionException error) => error.code,
            'code',
            'SIM-001',
          ),
        ),
      );
    });

    test('inspects live descriptors when the registry metadata lies', () {
      final WebAdapterRegistry web = WebAdapterRegistry(
        testAdapterSet(simulated: true),
      );
      final MetadataLyingRegistry liar = MetadataLyingRegistry(delegate: web);

      expect(
        () => assertNoSimulatedAdapters(liar),
        throwsA(isA<SimulatedInProductionException>()),
      );
    });

    test('rejects a registry that only claims simulated capabilities', () {
      final AndroidAdapterRegistry android = AndroidAdapterRegistry(
        testAdapterSet(),
      );
      final MetadataLyingRegistry liar = MetadataLyingRegistry(
        delegate: android,
        hasSimulatedCapabilities: true,
      );

      expect(
        () => assertNoSimulatedAdapters(liar),
        throwsA(isA<SimulatedInProductionException>()),
      );
    });
  });

  group('Android dependency boundary', () {
    test('registry sources never import the simulated adapter package', () {
      final Directory appRoot = _findAppRoot();
      for (final String fileName in <String>[
        'registry.dart',
        'registry_android.dart',
        'registry_web.dart',
        'registry_unsupported.dart',
      ]) {
        final String source = File('${appRoot.path}/lib/platform/$fileName')
            .readAsStringSync();
        expect(
          source,
          isNot(
            matches(
              RegExp(
                r'''(^|\n)\s*(import|export)\s+['"][^'"]*'''
                r'''feldexa_adapters_simulated''',
              ),
            ),
          ),
          reason: '$fileName must not reach the simulated adapter package',
        );
      }
      final String androidSource = File(
        '${appRoot.path}/lib/platform/registry_android.dart',
      ).readAsStringSync();
      expect(androidSource, isNot(contains('registry_web.dart')));
    });
  });
}

Directory _findAppRoot() {
  Directory dir = Directory.current;
  while (true) {
    if (File('${dir.path}/lib/platform/registry.dart').existsSync()) {
      return dir;
    }

    final Directory nested = Directory('${dir.path}/apps/feldexa_app');
    if (File('${nested.path}/lib/platform/registry.dart').existsSync()) {
      return nested;
    }

    final Directory parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'Could not locate apps/feldexa_app from ${Directory.current.path}',
      );
    }
    dir = parent;
  }
}
