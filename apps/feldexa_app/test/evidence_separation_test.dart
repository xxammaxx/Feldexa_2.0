// T130 evidence-separation assertion (FR-088; constitution Principle VIII).
//
// Evidence class: NONE. Host-VM tests over the T129 evidence fields in
// `packages/feldexa_ports` and the T026/T047 `SimulatedEvidence` surface in
// `feldexa_ui`. They open no platform channel, browser, emulator, or device
// and prove only the labeling invariant, not runtime behavior.
//
// What is asserted, and only that:
//   * `SIMULATED` evidence is never reported as `EMULATOR` or `DEVICE`
//     (report fields, log lines, report tokens, parse round trip);
//   * the simulated UI surface is never Android verification and never a
//     production artifact;
//   * there is no construction path that upgrades a simulated result into
//     a runtime class: `CapabilityEvidence` derives `simulated` from the
//     class, and the Android constructor yields `NONE` until the harness
//     attaches `EMULATOR`/`DEVICE`.

// ignore_for_file: depend_on_referenced_packages

import 'package:feldexa_ports/evidence.dart';
import 'package:feldexa_ui/feldexa_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('report fields keep SIMULATED separate (FR-088)', () {
    test('simulated evidence reports only its own class token', () {
      final Map<String, Object?> fields = CapabilityEvidence.simulated(
        adapterId: 'web.sim.storage.v1',
        simulatedReason: 'web.simulated-adapter',
      ).toReportFields();
      expect(fields['evidenceClass'], 'SIMULATED');
      expect(fields.containsValue('EMULATOR'), isFalse);
      expect(fields.containsValue('DEVICE'), isFalse);
    });

    test('every class token is distinct and parse-stable', () {
      final Set<String> tokens = EvidenceClass.values
          .map((EvidenceClass value) => value.label)
          .toSet();
      expect(tokens, <String>{'SIMULATED', 'EMULATOR', 'DEVICE', 'NONE'});
      for (final EvidenceClass value in EvidenceClass.values) {
        expect(EvidenceClass.parse(value.label), value);
      }
    });

    test('the simulated report field line is never a runtime class', () {
      final String line = EvidenceClass.simulated.reportFieldLine;
      expect(line, 'evidenceClass: SIMULATED');
      expect(line.contains('EMULATOR'), isFalse);
      expect(line.contains('DEVICE'), isFalse);
    });

    test('structured log lines stay prefixed with their own class', () {
      final CapabilityEvidence simulated = CapabilityEvidence.simulated(
        adapterId: 'web.sim.ocr.v1',
      );
      expect(simulated.toLogLine('analyze'), startsWith('[SIMULATED]'));
      expect(
        simulated.toLogLine('analyze'),
        isNot(anyOf(contains('EMULATOR'), contains('DEVICE'))),
      );
    });
  });

  group('the simulated UI surface is never Android evidence', () {
    for (final SimulatedSurface surface in SimulatedSurface.values) {
      test('$surface stays SIMULATED and denies Android verification', () {
        final SimulatedEvidence evidence = SimulatedEvidence.of(surface);
        expect(evidence.marker, contains('SIMULATED'));
        expect(evidence.isAndroidVerification, isFalse);
        expect(evidence.isProductionArtifact, isFalse);
        expect(evidence.toReportFields()['evidenceClass'], 'SIMULATED');
      });
    }

    test('the report descriptor renders the exact catalog field', () {
      expect(SimulatedEvidence.report.marker, 'evidenceClass: SIMULATED');
      expect(SimulatedEvidence.log.marker, '[SIMULATED]');
    });
  });

  group('no construction path upgrades simulated evidence', () {
    test('simulated is derived, never accepted from a caller', () {
      final CapabilityEvidence evidence = CapabilityEvidence.simulated(
        adapterId: 'web.sim.export.v1',
      );
      expect(evidence.simulated, isTrue);
      expect(evidence.evidenceClass, EvidenceClass.simulated);
    });

    test('the Android adapter constructor yields NONE, not EMULATOR', () {
      final CapabilityEvidence evidence = CapabilityEvidence.android(
        adapterId: 'android.pdfbox.v1',
      );
      expect(evidence.evidenceClass, EvidenceClass.none);
      expect(evidence.simulated, isFalse);
    });

    test('a simulated reason on a runtime class is rejected', () {
      expect(
        () => CapabilityEvidence(
          evidenceClass: EvidenceClass.emulator,
          adapterId: 'android.mlkit.v1',
          simulatedReason: 'web.simulated-adapter',
        ),
        throwsArgumentError,
      );
      expect(
        () => CapabilityEvidence(
          evidenceClass: EvidenceClass.device,
          adapterId: 'android.mlkit.v1',
          simulatedReason: 'web.simulated-adapter',
        ),
        throwsArgumentError,
      );
    });

    test('parsing cannot promote SIMULATED into a runtime class', () {
      expect(EvidenceClass.parse('SIMULATED'), EvidenceClass.simulated);
      expect(EvidenceClass.tryParse('emulator'), EvidenceClass.emulator);
      expect(EvidenceClass.tryParse('device'), EvidenceClass.device);
      // An unknown token never silently becomes host-only evidence.
      expect(EvidenceClass.tryParse('SIMULATED_EMULATOR'), isNull);
    });
  });
}
