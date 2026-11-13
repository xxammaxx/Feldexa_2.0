// T014 capability-evidence tests (host VM, evidence class NONE).
//
// These tests pin `contracts/ports.md` §1 and constitution Principle VIII:
//   * exactly four evidence classes with the uppercase report tokens;
//   * `SIMULATED` is never Android and `NONE` is never runtime evidence;
//   * `CapabilityEvidence.simulated` is true iff the class is simulated;
//   * an inconsistent label cannot be constructed.
//
// No test here produces SIMULATED, EMULATOR, or DEVICE runtime evidence.

import 'package:feldexa_ports/evidence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EvidenceClass', () {
    test('declares exactly the four contract classes in contract order', () {
      expect(EvidenceClass.values, <EvidenceClass>[
        EvidenceClass.simulated,
        EvidenceClass.emulator,
        EvidenceClass.device,
        EvidenceClass.none,
      ]);
    });

    test('uses the exact uppercase report tokens', () {
      expect(
        EvidenceClass.values.map((EvidenceClass value) => value.label).toList(),
        <String>['SIMULATED', 'EMULATOR', 'DEVICE', 'NONE'],
      );
    });

    test('parses enum names and tokens case-insensitively', () {
      expect(EvidenceClass.parse('simulated'), EvidenceClass.simulated);
      expect(EvidenceClass.parse('SIMULATED'), EvidenceClass.simulated);
      expect(EvidenceClass.parse(' Emulator '), EvidenceClass.emulator);
      expect(EvidenceClass.parse('DEVICE'), EvidenceClass.device);
      expect(EvidenceClass.parse('none'), EvidenceClass.none);
    });

    test('rejects unknown and empty tokens instead of defaulting', () {
      expect(() => EvidenceClass.parse('android'), throwsFormatException);
      expect(() => EvidenceClass.parse(''), throwsFormatException);
      expect(EvidenceClass.tryParse('real'), isNull);
      expect(EvidenceClass.tryParse('SIMULATED'), EvidenceClass.simulated);
    });

    test('separates Android classes from SIMULATED and NONE', () {
      expect(EvidenceClass.none.isAndroid, isFalse);
      expect(EvidenceClass.none.isRuntime, isFalse);
      expect(EvidenceClass.simulated.isAndroid, isFalse);
      expect(EvidenceClass.simulated.isRuntime, isTrue);
      expect(EvidenceClass.emulator.isAndroid, isTrue);
      expect(EvidenceClass.device.isAndroid, isTrue);
      expect(EvidenceClass.emulator.isRuntime, isTrue);
      expect(EvidenceClass.device.isRuntime, isTrue);
    });

    test('every class has a non-empty description', () {
      for (final EvidenceClass value in EvidenceClass.values) {
        expect(value.description, isNotEmpty);
      }
    });
  });

  group('CapabilityEvidence', () {
    test('derives simulated only for the simulated class', () {
      const CapabilityEvidence simulated = CapabilityEvidence(
        evidenceClass: EvidenceClass.simulated,
        adapterId: 'web.sim.storage.v1',
        simulatedReason: 'deterministic fixture adapter',
      );
      const CapabilityEvidence emulator = CapabilityEvidence(
        evidenceClass: EvidenceClass.emulator,
        adapterId: 'android.pdfbox.v1',
      );
      const CapabilityEvidence device = CapabilityEvidence(
        evidenceClass: EvidenceClass.device,
        adapterId: 'android.pdfbox.v1',
      );
      const CapabilityEvidence none = CapabilityEvidence(
        evidenceClass: EvidenceClass.none,
        adapterId: 'android.pdfbox.v1',
      );

      expect(simulated.simulated, isTrue);
      expect(emulator.simulated, isFalse);
      expect(device.simulated, isFalse);
      expect(none.simulated, isFalse);
    });

    test('simulated named constructor keeps its reason', () {
      const CapabilityEvidence evidence = CapabilityEvidence.simulated(
        adapterId: 'web.sim.ocr.v1',
        simulatedReason: 'Web development fixture',
      );
      expect(evidence.evidenceClass, EvidenceClass.simulated);
      expect(evidence.simulated, isTrue);
      expect(evidence.simulatedReason, 'Web development fixture');
    });

    test('android named constructor declares no simulated evidence', () {
      const CapabilityEvidence evidence = CapabilityEvidence.android(
        adapterId: 'android.keystore.v1',
      );
      expect(evidence.evidenceClass, EvidenceClass.none);
      expect(evidence.simulated, isFalse);
      expect(evidence.simulatedReason, isNull);
    });

    test('non-simulated evidence may not carry a simulated reason', () {
      expect(
        () => CapabilityEvidence(
          evidenceClass: EvidenceClass.emulator,
          adapterId: 'android.pdfbox.v1',
          simulatedReason: 'not simulated',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects an empty adapter id', () {
      expect(
        () => CapabilityEvidence(
          evidenceClass: EvidenceClass.none,
          adapterId: '',
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => CapabilityEvidence.simulated(adapterId: ''),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => CapabilityEvidence.android(adapterId: ''),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects an empty simulated reason when one is supplied', () {
      expect(
        () => CapabilityEvidence.simulated(
          adapterId: 'web.sim.pdf.v1',
          simulatedReason: '',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('value equality covers class, adapter, and reason', () {
      const CapabilityEvidence first = CapabilityEvidence.simulated(
        adapterId: 'web.sim.storage.v1',
        simulatedReason: 'fixture',
      );
      const CapabilityEvidence second = CapabilityEvidence.simulated(
        adapterId: 'web.sim.storage.v1',
        simulatedReason: 'fixture',
      );
      const CapabilityEvidence differentReason = CapabilityEvidence.simulated(
        adapterId: 'web.sim.storage.v1',
        simulatedReason: 'other',
      );
      const CapabilityEvidence differentAdapter = CapabilityEvidence.simulated(
        adapterId: 'web.sim.ocr.v1',
        simulatedReason: 'fixture',
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(differentReason));
      expect(first, isNot(differentAdapter));
      expect(
        first,
        isNot(
          const CapabilityEvidence.android(adapterId: 'web.sim.storage.v1'),
        ),
      );
    });

    test('toString names the class and adapter only', () {
      const CapabilityEvidence evidence = CapabilityEvidence.simulated(
        adapterId: 'web.sim.storage.v1',
        simulatedReason: 'content-free reason',
      );
      expect(
        evidence.toString(),
        'CapabilityEvidence(SIMULATED, web.sim.storage.v1)',
      );
      expect(evidence.toString(), isNot(contains('content-free reason')));
    });

    test('supports compile-time constant evidence', () {
      const CapabilityEvidence evidence = CapabilityEvidence.simulated(
        adapterId: 'web.sim.export.v1',
        simulatedReason: 'Web development export',
      );
      expect(evidence.evidenceClass, EvidenceClass.simulated);
    });
  });
}
