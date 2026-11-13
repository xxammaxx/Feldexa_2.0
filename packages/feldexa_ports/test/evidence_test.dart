// T014 capability-evidence tests (host VM, evidence class NONE).
//
// These tests pin `contracts/ports.md` §1 and constitution Principle VIII:
//   * exactly four evidence classes with the uppercase report tokens;
//   * `SIMULATED` is never Android and `NONE` is never runtime evidence;
//   * `CapabilityEvidence.simulated` is true iff the class is simulated;
//   * adapter ids and simulated reasons are validated at runtime as bounded
//     machine tokens, not by debug assertions alone;
//   * rejected input is never echoed in an error or in `toString()`.
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

    test('parses enum names and report tokens case-insensitively', () {
      expect(EvidenceClass.parse('simulated'), EvidenceClass.simulated);
      expect(EvidenceClass.parse('SIMULATED'), EvidenceClass.simulated);
      expect(EvidenceClass.parse(' Emulator '), EvidenceClass.emulator);
      expect(EvidenceClass.parse('DEVICE'), EvidenceClass.device);
      expect(EvidenceClass.parse('none'), EvidenceClass.none);
    });

    test('rejects unknown and empty tokens without echoing the input', () {
      for (final String input in <String>[
        'android',
        'secret-form.pdf',
        '/tmp/private/form.pdf',
        'PRIVATE OCR TEXT',
      ]) {
        try {
          EvidenceClass.parse(input);
          fail('parse must reject $input');
        } on FormatException catch (error) {
          expect(error.message, isNot(contains(input)));
          expect(error.toString(), isNot(contains(input)));
        }
      }
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
      final CapabilityEvidence simulated = CapabilityEvidence(
        evidenceClass: EvidenceClass.simulated,
        adapterId: 'web.sim.storage.v1',
        simulatedReason: 'fixture.deterministic',
      );
      final CapabilityEvidence emulator = CapabilityEvidence(
        evidenceClass: EvidenceClass.emulator,
        adapterId: 'android.pdfbox.v1',
      );
      final CapabilityEvidence device = CapabilityEvidence(
        evidenceClass: EvidenceClass.device,
        adapterId: 'android.pdfbox.v1',
      );
      final CapabilityEvidence none = CapabilityEvidence(
        evidenceClass: EvidenceClass.none,
        adapterId: 'android.pdfbox.v1',
      );

      expect(simulated.simulated, isTrue);
      expect(emulator.simulated, isFalse);
      expect(device.simulated, isFalse);
      expect(none.simulated, isFalse);
    });

    test('simulated named constructor keeps its reason', () {
      final CapabilityEvidence evidence = CapabilityEvidence.simulated(
        adapterId: 'web.sim.ocr.v1',
        simulatedReason: 'web.development-fixture',
      );
      expect(evidence.evidenceClass, EvidenceClass.simulated);
      expect(evidence.simulated, isTrue);
      expect(evidence.simulatedReason, 'web.development-fixture');
    });

    test('android named constructor declares no simulated evidence', () {
      final CapabilityEvidence evidence = CapabilityEvidence.android(
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
          simulatedReason: 'not-simulated',
        ),
        throwsArgumentError,
      );
    });

    test('accepts the documented machine-token boundaries', () {
      final String adapter64 = 'a.${'b' * 59}.v1';
      final String reason96 = 'r.${'s' * 91}.v1';
      expect(adapter64, hasLength(64));
      expect(reason96, hasLength(96));
      final CapabilityEvidence evidence = CapabilityEvidence.simulated(
        adapterId: adapter64,
        simulatedReason: reason96,
      );
      expect(evidence.adapterId, adapter64);
      expect(evidence.simulatedReason, reason96);
    });

    test('rejects content-like or unsafe adapter ids without echoing them', () {
      final List<String> invalid = <String>[
        '',
        'Android.PDFBox.V1',
        'android pdfbox',
        'android/pdfbox',
        r'android\pdfbox',
        '../private/form',
        '.leading.dot',
        'trailing.dot.',
        'double..dot',
        'form.pdf',
        'a${'b' * 64}',
        'sicher',
      ];
      for (final String value in invalid) {
        _expectSafeArgumentError(
          () => CapabilityEvidence(
            evidenceClass: EvidenceClass.none,
            adapterId: value,
          ),
          value,
        );
      }
    });

    test('rejects content-like or unsafe reasons without echoing them', () {
      final List<String> invalid = <String>[
        '',
        'deterministic fixture adapter',
        'C:\\Users\\person\\form.pdf',
        '/home/person/form.pdf',
        'Formular.pdf',
        '../secret',
        'double..dot',
        'form.pdf',
        'a${'b' * 96}',
        'sicher',
      ];
      for (final String value in invalid) {
        _expectSafeArgumentError(
          () => CapabilityEvidence.simulated(
            adapterId: 'web.sim.storage.v1',
            simulatedReason: value,
          ),
          value,
        );
      }
    });

    test('every construction path applies runtime validation', () {
      _expectSafeArgumentError(
        () => CapabilityEvidence.android(adapterId: 'android/pdfbox'),
        'android/pdfbox',
      );
      _expectSafeArgumentError(
        () => CapabilityEvidence.simulated(
          adapterId: 'web.sim.storage.v1',
          simulatedReason: 'not a token',
        ),
        'not a token',
      );
    });

    test('redacts adapter id and reason from toString', () {
      final CapabilityEvidence evidence = CapabilityEvidence.simulated(
        adapterId: 'web.sim.storage.v1',
        simulatedReason: 'fixture.deterministic',
      );
      expect(evidence.toString(), 'CapabilityEvidence(SIMULATED)');
      expect(evidence.toString(), isNot(contains(evidence.adapterId)));
      expect(evidence.toString(), isNot(contains(evidence.simulatedReason!)));
    });

    test('value equality covers class, adapter, and reason', () {
      final CapabilityEvidence first = CapabilityEvidence.simulated(
        adapterId: 'web.sim.storage.v1',
        simulatedReason: 'fixture.deterministic',
      );
      final CapabilityEvidence second = CapabilityEvidence.simulated(
        adapterId: 'web.sim.storage.v1',
        simulatedReason: 'fixture.deterministic',
      );
      final CapabilityEvidence differentReason = CapabilityEvidence.simulated(
        adapterId: 'web.sim.storage.v1',
        simulatedReason: 'fixture.other',
      );
      final CapabilityEvidence differentAdapter = CapabilityEvidence.simulated(
        adapterId: 'web.sim.ocr.v1',
        simulatedReason: 'fixture.deterministic',
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(differentReason));
      expect(first, isNot(differentAdapter));
      expect(
        first,
        isNot(CapabilityEvidence.android(adapterId: 'web.sim.storage.v1')),
      );
    });
  });
}

void _expectSafeArgumentError(void Function() action, String forbidden) {
  try {
    action();
    fail('expected ArgumentError');
  } on ArgumentError catch (error) {
    if (forbidden.isNotEmpty) {
      expect(error.message, isNot(contains(forbidden)));
      expect(error.toString(), isNot(contains(forbidden)));
    }
  }
}
