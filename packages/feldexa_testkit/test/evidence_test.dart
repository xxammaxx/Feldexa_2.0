// T011 evidence-label tests.
//
// These are host-VM tests of the label types. They prove the toolkit cannot
// silently turn a host check into SIMULATED or Android evidence; they do not
// produce any runtime evidence themselves.

import 'package:feldexa_ports/evidence.dart' as ports;
import 'package:feldexa_testkit/feldexa_testkit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EvidenceClass', () {
    test('consumes the canonical ports EvidenceClass declaration', () {
      // A compile-time type identity check: this assignment only compiles if
      // the toolkit re-exports the ports type instead of declaring its own.
      const ports.EvidenceClass canonical = EvidenceClass.simulated;
      expect(canonical, ports.EvidenceClass.simulated);
      expect(EvidenceClass.values, ports.EvidenceClass.values);
    });

    test('parses names and report tokens case-insensitively', () {
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
    });

    test('labels are distinct report tokens', () {
      expect(
        EvidenceClass.values.map((EvidenceClass value) => value.label).toSet(),
        <String>{'NONE', 'SIMULATED', 'EMULATOR', 'DEVICE'},
      );
    });
  });

  group('EvidenceLabel', () {
    test('host checks carry NONE and no runtime claim', () {
      const EvidenceLabel label = EvidenceLabel.hostVm();
      expect(label.tag, 'NONE');
      expect(label.isRuntime, isFalse);
      expect(label.isAndroid, isFalse);
      expect(label.surface, 'host-vm');
    });

    test('SIMULATED browser labels are not Android evidence', () {
      const EvidenceLabel label = EvidenceLabel.simulatedBrowser();
      expect(label.tag, 'SIMULATED');
      expect(label.isAndroid, isFalse);
      expect(label.toJson()['evidenceClass'], 'SIMULATED');
    });

    test('Android labels stay EMULATOR or DEVICE', () {
      expect(EvidenceLabel.androidEmulator().tag, 'EMULATOR');
      expect(EvidenceLabel.androidEmulator().isAndroid, isTrue);
      expect(EvidenceLabel.androidDevice().tag, 'DEVICE');
      expect(EvidenceLabel.androidDevice().isAndroid, isTrue);
    });

    test('value equality covers class, surface, and detail', () {
      const EvidenceLabel first = EvidenceLabel(
        EvidenceClass.simulated,
        'chrome',
        detail: 'run',
      );
      const EvidenceLabel second = EvidenceLabel(
        EvidenceClass.simulated,
        'chrome',
        detail: 'run',
      );
      const EvidenceLabel different = EvidenceLabel(
        EvidenceClass.simulated,
        'chrome',
        detail: 'other',
      );
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(different));
      expect(first.toString(), 'SIMULATED[chrome]');
      expect(first.toString(), isNot(contains('run')));
    });

    test('detail stays available explicitly but is redacted from logs', () {
      const EvidenceLabel label = EvidenceLabel(
        EvidenceClass.simulated,
        'chrome',
        detail: 'fixture.detail',
      );
      expect(label.toJson()['detail'], 'fixture.detail');
      expect(label.toString(), 'SIMULATED[chrome]');
      expect(label.toString(), isNot(contains('fixture.detail')));
    });
  });

  group('EvidenceLedger', () {
    test('separates host, SIMULATED, and Android results', () {
      final EvidenceLedger ledger = EvidenceLedger()
        ..record(const EvidenceLabel.hostVm())
        ..record(const EvidenceLabel.simulatedBrowser())
        ..record(const EvidenceLabel.androidEmulator())
        ..record(const EvidenceLabel.androidDevice());

      expect(ledger.classes, <EvidenceClass>{
        EvidenceClass.none,
        EvidenceClass.simulated,
        EvidenceClass.emulator,
        EvidenceClass.device,
      });
      expect(ledger.forClass(EvidenceClass.simulated), hasLength(1));
      expect(ledger.isMerged, isTrue);
      expect(ledger.requireSeparated, throwsStateError);
      expect(ledger.summarize(), contains('SIMULATED: 1'));
      expect(ledger.summarize(), contains('EMULATOR: 1'));
    });

    test('host checks next to one runtime class are not a merged claim', () {
      final EvidenceLedger ledger = EvidenceLedger()
        ..record(const EvidenceLabel.hostVm())
        ..record(const EvidenceLabel.simulatedBrowser());
      expect(ledger.isMerged, isFalse);
      expect(ledger.requireSeparated, returnsNormally);
    });

    test('SIMULATED plus DEVICE is still a merged claim', () {
      final EvidenceLedger ledger = EvidenceLedger()
        ..record(const EvidenceLabel.simulatedBrowser())
        ..record(const EvidenceLabel.androidDevice());
      expect(ledger.isMerged, isTrue);
      expect(ledger.requireSeparated, throwsStateError);
    });

    test('entries are a read-only view', () {
      final EvidenceLedger ledger = EvidenceLedger()
        ..record(const EvidenceLabel.hostVm());
      expect(
        () => ledger.entries.add(const EvidenceLabel.hostVm()),
        throwsUnsupportedError,
      );
    });
  });
}
