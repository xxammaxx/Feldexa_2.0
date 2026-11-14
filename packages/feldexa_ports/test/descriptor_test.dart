// T013 capability-descriptor tests (host VM, evidence class NONE).
//
// These tests pin `contracts/ports.md` §1 and §4:
//   * the ten `CapabilityKind` values in contract order;
//   * `PlatformCapability` exposes one descriptor;
//   * a descriptor's adapter id and simulated flag must agree with its
//     `CapabilityEvidence`, so a simulated capability cannot claim to be real;
//   * supported features are an unmodifiable copy;
//   * rejected metadata never appears in an exception or `toString()`.
//
// No test here produces SIMULATED, EMULATOR, or DEVICE runtime evidence.

import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

final class _ProbeCapability implements PlatformCapability {
  _ProbeCapability(this.descriptor);

  @override
  final CapabilityDescriptor descriptor;
}

void main() {
  group('CapabilityKind', () {
    test('matches the contract declaration order', () {
      expect(
        CapabilityKind.values.map((CapabilityKind kind) => kind.name).toList(),
        <String>[
          'documentImport',
          'pageRaster',
          'ocr',
          'secureStore',
          'pdfExport',
          'delivery',
          'lifecycle',
          'clock',
          'ids',
          'diagnostics',
        ],
      );
    });
  });

  group('CapabilityDescriptor', () {
    test('describes a real Android capability', () {
      final CapabilityDescriptor descriptor = fixtureDescriptor(
        kind: CapabilityKind.pageRaster,
        supportedFeatures: <String>['gray8', 'rgba8888', 'evict'],
      );

      expect(descriptor.kind, CapabilityKind.pageRaster);
      expect(descriptor.adapterId, 'android.pdfbox.v1');
      expect(descriptor.version, '1');
      expect(descriptor.isSimulated, isFalse);
      expect(descriptor.evidence.evidenceClass, EvidenceClass.none);
      expect(descriptor.supportedFeatures, <String>{
        'gray8',
        'rgba8888',
        'evict',
      });
    });

    test('describes a simulated Web capability and keeps the label', () {
      final CapabilityEvidence evidence = fixtureSimulatedEvidence();
      final CapabilityDescriptor descriptor = CapabilityDescriptor(
        kind: CapabilityKind.documentImport,
        adapterId: evidence.adapterId,
        version: '1',
        isSimulated: true,
        evidence: evidence,
        supportedFeatures: <String>['pick', 'verify'],
      );

      expect(descriptor.isSimulated, isTrue);
      expect(descriptor.evidence.evidenceClass, EvidenceClass.simulated);
      expect(descriptor.evidence.simulated, isTrue);
    });

    test('accepts a dotted adapter contract version', () {
      final CapabilityDescriptor descriptor = fixtureDescriptor(version: '1.2');

      expect(descriptor.version, '1.2');
    });

    test('rejects a simulated flag that disagrees with the evidence', () {
      final CapabilityEvidence evidence = fixtureAndroidEvidence();

      expect(
        () => CapabilityDescriptor(
          kind: CapabilityKind.secureStore,
          adapterId: evidence.adapterId,
          version: '1',
          isSimulated: true,
          evidence: evidence,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            contains('isSimulated must match the evidence class'),
          ),
        ),
      );
      expect(
        () => CapabilityDescriptor(
          kind: CapabilityKind.secureStore,
          adapterId: evidence.adapterId,
          version: '1',
          isSimulated: false,
          evidence: fixtureSimulatedEvidence(),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            contains('adapterId must equal'),
          ),
        ),
      );
    });

    test('rejects an adapter id that disagrees with the evidence', () {
      expect(
        () => CapabilityDescriptor(
          kind: CapabilityKind.ocr,
          adapterId: 'android.other.v1',
          version: '1',
          isSimulated: false,
          evidence: fixtureAndroidEvidence(),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            contains('adapterId must equal evidence.adapterId'),
          ),
        ),
      );
    });

    test('rejects every invalid contract version without echoing it', () {
      for (final String invalid in <String>['', '0', '01', 'v1', '1.', '.1']) {
        final Object? caught = _capture(
          () => fixtureDescriptor(version: invalid),
        );
        expect(caught, isA<ArgumentError>(), reason: 'accepted "$invalid"');
        final String text = caught.toString();
        if (invalid.isNotEmpty) {
          expect(text, isNot(contains(invalid)));
        }
        expect(text, contains('version must be a positive adapter contract'));
      }
    });

    test('rejects unsafe supported-feature tokens without echoing them', () {
      for (final String invalid in <String>[
        '',
        'two words',
        'bad\nfeature',
        'x' * 65,
      ]) {
        final Object? caught = _capture(
          () => fixtureDescriptor(supportedFeatures: <String>[invalid]),
        );
        expect(caught, isA<ArgumentError>(), reason: 'accepted "$invalid"');
        expect(
          caught.toString(),
          contains('supportedFeatures must contain short non-empty tokens'),
        );
        if (invalid.isNotEmpty) {
          expect(caught.toString(), isNot(contains(invalid)));
        }
      }
    });

    test('stores an unmodifiable copy of supported features', () {
      final List<String> source = <String>['first'];
      final CapabilityDescriptor descriptor = fixtureDescriptor(
        supportedFeatures: source,
      );

      source.add('second');

      expect(descriptor.supportedFeatures, <String>{'first'});
      expect(
        () => descriptor.supportedFeatures.add('third'),
        throwsUnsupportedError,
      );
    });

    test('implements value equality over every contract field', () {
      final CapabilityDescriptor first = fixtureDescriptor(
        supportedFeatures: <String>['a', 'b'],
      );
      final CapabilityDescriptor second = fixtureDescriptor(
        supportedFeatures: <String>['b', 'a'],
      );
      final CapabilityDescriptor otherKind = fixtureDescriptor(
        kind: CapabilityKind.clock,
        supportedFeatures: <String>['a', 'b'],
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(otherKind));
    });

    test('redacts the adapter id and features from toString', () {
      final CapabilityDescriptor descriptor = fixtureDescriptor(
        adapterId: 'android.share.v1',
        supportedFeatures: <String>['secret-feature'],
      );

      expect(descriptor.toString(), contains('kind: documentImport'));
      expect(descriptor.toString(), isNot(contains('android.share.v1')));
      expect(descriptor.toString(), isNot(contains('secret-feature')));
    });

    test('exposes the descriptor through PlatformCapability', () {
      final CapabilityDescriptor descriptor = fixtureDescriptor();
      final PlatformCapability capability = _ProbeCapability(descriptor);

      expect(capability.descriptor, same(descriptor));
      expect(capability.descriptor.kind, CapabilityKind.documentImport);
    });
  });
}

Object? _capture(void Function() action) {
  try {
    action();
  } catch (error) {
    return error;
  }
  return null;
}
