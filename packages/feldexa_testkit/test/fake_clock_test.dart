// T011 fake-clock tests.
//
// These are host-VM tests. They produce no SIMULATED, EMULATOR, or DEVICE
// runtime evidence; they prove the test seam is deterministic.

import 'package:feldexa_testkit/feldexa_testkit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  group('FakeClock', () {
    test('starts at the Unix epoch in UTC', () {
      final FakeClock clock = FakeClock();
      expect(clock.nowUtc(), epoch);
      expect(clock.nowUtc().isUtc, isTrue);
      expect(clock.startedAt, epoch);
    });

    test('normalises an explicit local time to UTC', () {
      final DateTime local = DateTime(2026, 11, 13, 9, 30);
      final FakeClock clock = FakeClock(initialUtc: local);
      expect(clock.nowUtc().isUtc, isTrue);
      expect(clock.nowUtc(), local.toUtc());
    });

    test('does not advance on reads and counts them', () {
      final FakeClock clock = FakeClock();
      expect(clock.readCount, 0);
      final DateTime first = clock.nowUtc();
      final DateTime second = clock.nowUtc();
      expect(second, first);
      expect(clock.readCount, 2);
    });

    test('advances by exact durations', () {
      final FakeClock clock = FakeClock();
      clock
        ..advance(const Duration(days: 2))
        ..advance(const Duration(hours: 3))
        ..advance(const Duration(minutes: 4))
        ..advance(const Duration(seconds: 5))
        ..advance(const Duration(milliseconds: 6))
        ..advance(const Duration(microseconds: 7));
      expect(
        clock.nowUtc(),
        epoch.add(
          const Duration(
            days: 2,
            hours: 3,
            minutes: 4,
            seconds: 5,
            milliseconds: 6,
            microseconds: 7,
          ),
        ),
      );
      expect(clock.elapsed, clock.nowUtc().difference(epoch));
    });

    test('rejects a negative advance', () {
      final FakeClock clock = FakeClock();
      expect(
        () => clock.advance(const Duration(microseconds: -1)),
        throwsArgumentError,
      );
    });

    test('advanceTo moves forward and accepts the current instant', () {
      final FakeClock clock = FakeClock();
      final DateTime target = epoch.add(const Duration(hours: 1));
      clock.advanceTo(target);
      expect(clock.nowUtc(), target);
      clock.advanceTo(target);
      expect(clock.nowUtc(), target);
    });

    test('advanceTo rejects moving backwards', () {
      final FakeClock clock = FakeClock(
        initialUtc: epoch.add(const Duration(hours: 1)),
      );
      expect(() => clock.advanceTo(epoch), throwsArgumentError);
    });

    test('setUtc allows an explicit rewind and normalises to UTC', () {
      final FakeClock clock = FakeClock();
      final DateTime local = DateTime(2026, 11, 13, 12);
      clock.setUtc(local);
      expect(clock.nowUtc(), local.toUtc());
      expect(clock.nowUtc().isUtc, isTrue);
      clock.setUtc(epoch);
      expect(clock.nowUtc(), epoch);
    });

    test('reset returns to the creation instant and clears the read count', () {
      final FakeClock clock = FakeClock(initialUtc: epoch);
      clock
        ..advance(const Duration(minutes: 5))
        ..nowUtc()
        ..reset();
      expect(clock.nowUtc(), epoch);
      expect(clock.readCount, 1, reason: 'reset clears, then this read counts');
    });

    test('instances are independent', () {
      final FakeClock first = FakeClock();
      final FakeClock second = FakeClock();
      first.advance(const Duration(seconds: 1));
      expect(first.nowUtc(), isNot(second.nowUtc()));
    });

    test('is host-only metadata, never runtime or Android evidence', () {
      final EvidenceLabel label = FakeClock().evidence;
      expect(label.evidenceClass, EvidenceClass.none);
      expect(label.isRuntime, isFalse);
      expect(label.isAndroid, isFalse);
      expect(label.tag, 'NONE');
    });
  });
}
