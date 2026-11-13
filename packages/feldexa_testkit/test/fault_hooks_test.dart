// T011 fault-hook tests.
//
// Host-VM tests prove the injector itself is deterministic. They do not prove
// any storage/keystore/export recovery behaviour; those tests belong to the
// adapter tasks that call these hooks.

import 'package:feldexa_testkit/feldexa_testkit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FaultInjector', () {
    test('injects nothing without an armed rule', () {
      final FaultInjector injector = FaultInjector();
      injector.check(FaultPoints.storeWrite);
      injector.check(FaultPoints.storeWrite);
      expect(injector.totalCalls, 2);
      expect(injector.callsAt(FaultPoints.storeWrite), 2);
      expect(injector.injectedFaults, isEmpty);
    });

    test('injects a one-shot fault at the armed point', () {
      final FaultInjector injector = FaultInjector(
        FaultPlan(<FaultRule>[
          FaultRule(
            point: FaultPoints.storeWrite,
            kind: FaultKind.storageFull,
            message: 'quota test',
          ),
        ]),
      );

      expect(
        () => injector.check(FaultPoints.storeWrite),
        throwsA(
          isA<InjectedFault>()
              .having(
                (InjectedFault fault) => fault.kind,
                'kind',
                FaultKind.storageFull,
              )
              .having(
                (InjectedFault fault) => fault.catalogCode,
                'catalogCode',
                'SAVE-001',
              )
              .having((InjectedFault fault) => fault.callIndex, 'callIndex', 1)
              .having(
                (InjectedFault fault) => fault.message,
                'message',
                'quota test',
              ),
        ),
      );
      expect(injector.injectedFaults, hasLength(1));

      injector.check(FaultPoints.storeWrite);
      expect(injector.callsAt(FaultPoints.storeWrite), 2);
    });

    test('honours startsAt call numbering', () {
      final FaultInjector injector = FaultInjector(
        FaultPlan(<FaultRule>[
          FaultRule(
            point: FaultPoints.storeCommit,
            kind: FaultKind.fsyncFailure,
            startsAt: 3,
          ),
        ]),
      );

      injector
        ..check(FaultPoints.storeCommit)
        ..check(FaultPoints.storeCommit);
      expect(
        () => injector.check(FaultPoints.storeCommit),
        throwsA(
          isA<InjectedFault>().having(
            (InjectedFault fault) => fault.callIndex,
            'callIndex',
            3,
          ),
        ),
      );
    });

    test('honours times and then passes', () {
      final FaultInjector injector = FaultInjector(
        FaultPlan(<FaultRule>[
          FaultRule(
            point: FaultPoints.storeWrite,
            kind: FaultKind.shortWrite,
            times: 2,
          ),
        ]),
      );

      expect(
        () => injector.check(FaultPoints.storeWrite),
        throwsA(isA<InjectedFault>()),
      );
      expect(
        () => injector.check(FaultPoints.storeWrite),
        throwsA(isA<InjectedFault>()),
      );
      injector.check(FaultPoints.storeWrite);
      expect(injector.injectedFaults, hasLength(2));
    });

    test('times null injects on every matching call', () {
      final FaultInjector injector = FaultInjector(
        FaultPlan(<FaultRule>[
          FaultRule(
            point: FaultPoints.keystoreUnwrap,
            kind: FaultKind.keystoreUnavailable,
            times: null,
          ),
        ]),
      );

      for (int call = 1; call <= 3; call++) {
        expect(
          () => injector.check(FaultPoints.keystoreUnwrap),
          throwsA(isA<InjectedFault>()),
          reason: 'call $call',
        );
      }
      expect(injector.injectedFaults, hasLength(3));
    });

    test('different fault points are independent', () {
      final FaultInjector injector = FaultInjector(
        FaultPlan(<FaultRule>[
          FaultRule(point: FaultPoints.storeWrite, kind: FaultKind.storageFull),
          FaultRule(
            point: FaultPoints.exportWrite,
            kind: FaultKind.exportFailure,
          ),
        ]),
      );

      expect(
        () => injector.check(FaultPoints.storeWrite),
        throwsA(isA<InjectedFault>()),
      );
      expect(
        () => injector.check(FaultPoints.exportWrite),
        throwsA(isA<InjectedFault>()),
      );
      injector.check(FaultPoints.storeCommit);
      expect(injector.callsAt(FaultPoints.storeCommit), 1);
    });

    test('same point can arm later calls', () {
      final FaultInjector injector = FaultInjector(
        FaultPlan(<FaultRule>[
          FaultRule(
            point: FaultPoints.storeWrite,
            kind: FaultKind.storageFull,
            startsAt: 1,
          ),
          FaultRule(
            point: FaultPoints.storeWrite,
            kind: FaultKind.writeInterrupted,
            startsAt: 3,
          ),
        ]),
      );

      expect(
        () => injector.check(FaultPoints.storeWrite),
        throwsA(
          isA<InjectedFault>().having(
            (InjectedFault fault) => fault.kind,
            'kind',
            FaultKind.storageFull,
          ),
        ),
      );
      injector.check(FaultPoints.storeWrite);
      expect(
        () => injector.check(FaultPoints.storeWrite),
        throwsA(
          isA<InjectedFault>().having(
            (InjectedFault fault) => fault.kind,
            'kind',
            FaultKind.writeInterrupted,
          ),
        ),
      );
    });

    test('arm, disarm, and clear manage rules', () {
      final FaultInjector injector = FaultInjector();
      injector.arm(
        FaultRule(point: FaultPoints.storeWrite, kind: FaultKind.storageFull),
      );
      expect(injector.rules, hasLength(1));
      injector.disarm(FaultPoints.storeWrite);
      expect(injector.rules, isEmpty);
      injector.check(FaultPoints.storeWrite);

      injector.arm(
        FaultRule(point: FaultPoints.storeWrite, kind: FaultKind.storageFull),
      );
      injector.clear();
      expect(injector.rules, isEmpty);
      expect(injector.totalCalls, 0);
      expect(injector.injectedFaults, isEmpty);
    });

    test('rejects duplicate rules for the same point and call', () {
      final FaultInjector injector = FaultInjector(
        FaultPlan(<FaultRule>[
          FaultRule(point: FaultPoints.storeWrite, kind: FaultKind.storageFull),
        ]),
      );
      expect(
        () => injector.arm(
          FaultRule(point: FaultPoints.storeWrite, kind: FaultKind.shortWrite),
        ),
        throwsArgumentError,
      );
      expect(
        () => FaultPlan(<FaultRule>[
          FaultRule(point: FaultPoints.storeWrite, kind: FaultKind.storageFull),
          FaultRule(point: FaultPoints.storeWrite, kind: FaultKind.shortWrite),
        ]),
        throwsArgumentError,
      );
    });

    test('validates rule arguments', () {
      expect(
        () => FaultRule(point: '', kind: FaultKind.storageFull),
        throwsArgumentError,
      );
      expect(
        () => FaultRule(point: '  ', kind: FaultKind.storageFull),
        throwsArgumentError,
      );
      expect(
        () => FaultRule(
          point: FaultPoints.storeWrite,
          kind: FaultKind.storageFull,
          startsAt: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => FaultRule(
          point: FaultPoints.storeWrite,
          kind: FaultKind.storageFull,
          times: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => FaultRule(
          point: FaultPoints.storeWrite,
          kind: FaultKind.storageFull,
          message: '',
        ),
        throwsArgumentError,
      );
    });

    test('run and runAsync do not execute the action on a fault', () async {
      final FaultPlan plan = FaultPlan(<FaultRule>[
        FaultRule(point: FaultPoints.storeWrite, kind: FaultKind.storageFull),
      ]);

      bool syncRan = false;
      expect(
        () => FaultInjector(plan).run(FaultPoints.storeWrite, () {
          syncRan = true;
          return 1;
        }),
        throwsA(isA<InjectedFault>()),
      );
      expect(syncRan, isFalse);

      bool asyncRan = false;
      await expectLater(
        FaultInjector(plan).runAsync(FaultPoints.storeWrite, () async {
          asyncRan = true;
          return 2;
        }),
        throwsA(isA<InjectedFault>()),
      );
      expect(asyncRan, isFalse);
    });

    test('run and runAsync return the action result when clear', () async {
      final FaultInjector injector = FaultInjector();
      expect(injector.run(FaultPoints.storeWrite, () => 'ok'), 'ok');
      expect(
        await injector.runAsync(FaultPoints.storeWrite, () async => 42),
        42,
      );
      expect(injector.totalCalls, 2);
    });

    test(
      'action exceptions propagate and are not converted to faults',
      () async {
        final FaultInjector injector = FaultInjector();
        expect(
          () => injector.run<int>(FaultPoints.storeWrite, () {
            throw StateError('real failure');
          }),
          throwsStateError,
        );
        await expectLater(
          injector.runAsync<int>(FaultPoints.storeWrite, () async {
            throw StateError('real async failure');
          }),
          throwsStateError,
        );
        expect(injector.injectedFaults, isEmpty);
      },
    );

    test('faultsAt filters by point and kind', () {
      final FaultInjector injector = FaultInjector(
        FaultPlan(<FaultRule>[
          FaultRule(
            point: FaultPoints.storeWrite,
            kind: FaultKind.storageFull,
            times: 2,
          ),
          FaultRule(
            point: FaultPoints.exportVerify,
            kind: FaultKind.exportFailure,
          ),
        ]),
      );
      for (int call = 0; call < 2; call++) {
        expect(
          () => injector.check(FaultPoints.storeWrite),
          throwsA(isA<InjectedFault>()),
        );
      }
      expect(
        () => injector.check(FaultPoints.exportVerify),
        throwsA(isA<InjectedFault>()),
      );

      expect(injector.faultsAt(FaultPoints.storeWrite), hasLength(2));
      expect(
        injector.faultsAt(FaultPoints.storeWrite, kind: FaultKind.storageFull),
        hasLength(2),
      );
      expect(
        injector.faultsAt(FaultPoints.storeWrite, kind: FaultKind.shortWrite),
        isEmpty,
      );
      expect(injector.faultsAt(FaultPoints.exportVerify), hasLength(1));
      expect(
        injector.injectedFaults.first.toString(),
        'InjectedFault(storageFull at store.write, call 1)',
      );
    });

    test('catalog codes match the documented failure taxonomy', () {
      expect(FaultKind.storageFull.catalogCode, 'SAVE-001');
      expect(FaultKind.keystoreUnavailable.catalogCode, 'SAVE-002');
      expect(FaultKind.corruptKeyMaterial.catalogCode, 'SAVE-002');
      expect(FaultKind.shortWrite.catalogCode, 'SAVE-003');
      expect(FaultKind.fsyncFailure.catalogCode, 'SAVE-003');
      expect(FaultKind.writeInterrupted.catalogCode, 'SAVE-003');
      expect(FaultKind.exportFailure.catalogCode, 'EXP-002');
    });
  });
}
