// T036 failure-injection harness and FakeRegistry tests.
//
// These are host-VM tests: they prove the harness itself is deterministic and
// maps injected faults to the typed T014 exceptions. They are NONE-class
// evidence and do not prove Android storage, Keystore, export, or recovery
// behavior; those remain with the adapter/emulator tasks.

import 'dart:async';
import 'dart:typed_data';

import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:feldexa_testkit/feldexa_testkit.dart';
import 'package:flutter_test/flutter_test.dart';

FaultInjector _injectorFor(FaultRule rule) =>
    FaultInjector(FaultPlan(<FaultRule>[rule]));

CapabilityDescriptor _descriptor(
  CapabilityKind kind, {
  bool simulated = true,
}) => fakeCapabilityDescriptor(kind, simulated: simulated);

void main() {
  group('ScriptedClock', () {
    test('is deterministic and never advances on its own', () {
      final ScriptedClock clock = ScriptedClock(
        descriptor: _descriptor(CapabilityKind.clock),
        initialUtc: DateTime.utc(2026, 11, 15, 9),
      );

      expect(clock.nowUtc(), DateTime.utc(2026, 11, 15, 9));
      expect(clock.nowUtc(), DateTime.utc(2026, 11, 15, 9));
      expect(clock.readCount, 2);

      clock.advance(const Duration(seconds: 2));
      expect(clock.nowUtc(), DateTime.utc(2026, 11, 15, 9, 0, 2));
      expect(clock.elapsed, const Duration(seconds: 2));
    });

    test('rejects a backward advance but allows an explicit rewind', () {
      final ScriptedClock clock = ScriptedClock(
        descriptor: _descriptor(CapabilityKind.clock),
        initialUtc: DateTime.utc(2026, 11, 15, 9),
      );

      expect(
        () => clock.advance(const Duration(seconds: -1)),
        throwsArgumentError,
      );
      expect(
        () => clock.advanceTo(DateTime.utc(2026, 11, 15, 8)),
        throwsArgumentError,
      );

      clock.setUtc(DateTime.utc(2026, 11, 15, 8));
      expect(clock.nowUtc(), DateTime.utc(2026, 11, 15, 8));
    });

    test('applies forward and backward jumps after the configured reads', () {
      final DateTime start = DateTime.utc(2026, 11, 15, 9);
      final ScriptedClock clock = ScriptedClock(
        descriptor: _descriptor(CapabilityKind.clock),
        initialUtc: start,
      );

      clock.scheduleJump(
        ClockJump.forward(afterReads: 1, amount: const Duration(seconds: 3)),
      );

      expect(clock.nowUtc(), start);
      expect(
        clock.nowUtc(),
        start.add(const Duration(seconds: 3)),
        reason: 'the jump applies before the second read',
      );
      expect(clock.appliedJumps, hasLength(1));

      clock.scheduleJump(
        ClockJump.backward(afterReads: 3, amount: const Duration(seconds: 5)),
      );
      expect(clock.nowUtc(), start.add(const Duration(seconds: 3)));
      expect(
        clock.nowUtc(),
        start.subtract(const Duration(seconds: 2)),
        reason: 'a wall-clock correction may move backwards',
      );
      expect(clock.appliedJumps, hasLength(2));
    });

    test('rejects a jump scheduled for a read that already happened', () {
      final ScriptedClock clock = ScriptedClock(
        descriptor: _descriptor(CapabilityKind.clock),
        initialUtc: DateTime.utc(2026, 11, 15, 9),
      );
      clock.nowUtc();
      clock.nowUtc();

      expect(
        () => clock.scheduleJump(
          ClockJump.forward(afterReads: 1, amount: const Duration(seconds: 1)),
        ),
        throwsArgumentError,
      );
    });

    test('reset returns to the origin and replays the jump script', () {
      final DateTime start = DateTime.utc(2026, 11, 15, 9);
      final ScriptedClock clock = ScriptedClock(
        descriptor: _descriptor(CapabilityKind.clock),
        initialUtc: start,
      );
      clock.scheduleJump(
        ClockJump.forward(afterReads: 1, amount: const Duration(seconds: 4)),
      );
      clock.nowUtc();
      clock.nowUtc();
      expect(clock.appliedJumps, hasLength(1));

      clock.reset();
      expect(clock.readCount, 0);
      expect(clock.appliedJumps, isEmpty);
      expect(clock.nowUtc(), start);
      expect(
        clock.nowUtc(),
        start.add(const Duration(seconds: 4)),
        reason: 'the scheduled jump is still armed after reset',
      );
    });

    test('rejects non-positive jumps and a wrong descriptor kind', () {
      expect(
        () => ClockJump.forward(afterReads: 0, amount: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => ClockJump.backward(
          afterReads: -1,
          amount: const Duration(seconds: 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => ScriptedClock(descriptor: _descriptor(CapabilityKind.ids)),
        throwsArgumentError,
      );
    });
  });

  group('SequenceIds', () {
    test('produces valid v4 ids and deterministic idempotency keys', () {
      final SequenceIds ids = SequenceIds(
        descriptor: _descriptor(CapabilityKind.ids),
      );
      final RegExp uuidV4 = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
        r'[0-9a-f]{12}$',
      );

      final String first = ids.newId();
      final String second = ids.newId();
      expect(first, matches(uuidV4));
      expect(second, matches(uuidV4));
      expect(first, isNot(second));
      expect(ids.newIdempotencyKey(), 'idempotency-key-000001');
      expect(ids.newIdempotencyKey(), 'idempotency-key-000002');
    });

    test('reset returns to the configured first value', () {
      final SequenceIds ids = SequenceIds(
        descriptor: _descriptor(CapabilityKind.ids),
        firstValue: 7,
      );
      expect(ids.newId(), '00000000-0000-4000-8000-000000000007');
      ids.newId();
      ids.newIdempotencyKey();
      ids.reset();

      expect(ids.newId(), '00000000-0000-4000-8000-000000000007');
      expect(ids.newIdempotencyKey(), 'idempotency-key-000001');
    });

    test('rejects a wrong descriptor kind and an invalid first value', () {
      expect(
        () => SequenceIds(descriptor: _descriptor(CapabilityKind.clock)),
        throwsArgumentError,
      );
      expect(
        () => SequenceIds(
          descriptor: _descriptor(CapabilityKind.ids),
          firstValue: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('faultExceptionFor', () {
    test('maps every fault kind to its typed catalog exception', () {
      final Map<FaultKind, Type> expected = <FaultKind, Type>{
        FaultKind.storageFull: StorageFullException,
        FaultKind.shortWrite: StorageWriteException,
        FaultKind.fsyncFailure: StorageWriteException,
        FaultKind.writeInterrupted: StorageWriteException,
        FaultKind.keystoreUnavailable: KeystoreUnavailableException,
        FaultKind.keystoreReset: KeystoreUnavailableException,
        FaultKind.corruptKeyMaterial: KeyUnavailableException,
        FaultKind.exportFailure: ExportFailedException,
      };

      for (final MapEntry<FaultKind, Type> entry in expected.entries) {
        final FeldexaException exception = faultExceptionFor(
          InjectedFault(kind: entry.key, point: 'harness', callIndex: 1),
        );
        expect(exception.runtimeType, entry.value, reason: entry.key.name);
        expect(exception.code, entry.key.catalogCode, reason: entry.key.name);
      }
    });

    test('keeps aggregate and global key failures distinct', () {
      final FeldexaException aggregate = faultExceptionFor(
        const InjectedFault(
          kind: FaultKind.corruptKeyMaterial,
          point: FaultPoints.storeRead,
          callIndex: 1,
        ),
      );
      final FeldexaException global = faultExceptionFor(
        const InjectedFault(
          kind: FaultKind.keystoreUnavailable,
          point: FaultPoints.storeRead,
          callIndex: 1,
        ),
      );
      final FeldexaException reset = faultExceptionFor(
        const InjectedFault(
          kind: FaultKind.keystoreReset,
          point: FaultPoints.keystoreUnwrap,
          callIndex: 1,
        ),
      );

      expect(aggregate, isA<KeyUnavailableException>());
      expect(aggregate.code, 'SAVE-002');
      expect(aggregate.retryable, isFalse);
      expect(global, isA<KeystoreUnavailableException>());
      expect(global.code, 'SAVE-008');
      expect(global.retryable, isTrue);
      expect(reset, isA<KeystoreUnavailableException>());
      expect(reset.code, 'SAVE-008');
      expect(
        reset.retryable,
        isFalse,
        reason: 'a device-wide reset has no retry recovery',
      );
    });

    test('quota and write-interruption exceptions stay retryable', () {
      final FeldexaException quota = faultExceptionFor(
        const InjectedFault(
          kind: FaultKind.storageFull,
          point: FaultPoints.storeWrite,
          callIndex: 1,
        ),
      );
      final FeldexaException interrupted = faultExceptionFor(
        const InjectedFault(
          kind: FaultKind.writeInterrupted,
          point: FaultPoints.storeCommit,
          callIndex: 1,
        ),
      );

      expect(quota, isA<StorageFullException>());
      expect(quota.retryable, isTrue);
      expect(interrupted, isA<StorageWriteException>());
      expect(interrupted.retryable, isTrue);
    });
  });

  group('FaultingSecureStore', () {
    late _RecordingStore delegate;
    late FaultingSecureStore store;

    setUp(() {
      delegate = _RecordingStore(_descriptor(CapabilityKind.secureStore));
    });

    FaultingSecureStore build(FaultInjector injector) {
      store = FaultingSecureStore(delegate: delegate, injector: injector);
      return store;
    }

    test(
      'maps a quota fault at store.write and does not run the write',
      () async {
        final FaultingSecureStore value = build(
          _injectorFor(
            FaultRule(
              point: FaultPoints.storeWrite,
              kind: FaultKind.storageFull,
            ),
          ),
        );
        bool ran = false;

        await expectLater(
          value.guardWrite(() {
            ran = true;
            return 'committed';
          }),
          throwsA(
            isA<StorageFullException>().having(
              (StorageFullException error) => error.code,
              'code',
              'SAVE-001',
            ),
          ),
        );
        expect(ran, isFalse);
      },
    );

    test(
      'does not check internal fsync or commit before the delegate runs',
      () async {
        final FaultInjector injector = FaultInjector(
          FaultPlan(<FaultRule>[
            FaultRule(
              point: FaultPoints.storeFsync,
              kind: FaultKind.fsyncFailure,
            ),
            FaultRule(
              point: FaultPoints.storeCommit,
              kind: FaultKind.writeInterrupted,
            ),
          ]),
        );
        build(injector);
        bool ran = false;

        expect(
          await store.guardWrite(() {
            ran = true;
            return 'delegate-ran';
          }),
          'delegate-ran',
        );
        expect(ran, isTrue);
        expect(
          injector.callsAt(FaultPoints.storeFsync),
          0,
          reason: 'fsync is inside the adapter transaction, not the port guard',
        );
        expect(
          injector.callsAt(FaultPoints.storeCommit),
          0,
          reason:
              'commit is inside the adapter transaction, not the port guard',
        );
        expect(injector.callsAt(FaultPoints.storeWrite), 1);
      },
    );

    test('checks the phase-aware seam inside the adapter transaction', () {
      final FaultInjector injector = _injectorFor(
        FaultRule(
          point: FaultPoints.storeStage,
          kind: FaultKind.shortWrite,
          startsAt: 2,
        ),
      );
      final StagedWriteFaultSeam seam = StagedWriteFaultSeam(
        injector: injector,
      );

      seam.beforeStagedWrite();
      expect(
        () => seam.afterStagedWrite(),
        throwsA(isA<StorageWriteException>()),
      );
      expect(injector.callsAt(FaultPoints.storeStage), 2);
    });

    test('runs the write when no fault matches', () async {
      build(FaultInjector());
      expect(await store.guardWrite(() => 'committed'), 'committed');
    });

    test('does not convert a real delegate exception into a fault', () async {
      build(FaultInjector());
      await expectLater(
        store.guardWrite<void>(() async {
          throw StateError('real storage failure');
        }),
        throwsStateError,
      );
      expect(store.injector.injectedFaults, isEmpty);
    });

    test('checks keystore.unwrap before a document read', () async {
      final FaultingSecureStore value = build(
        _injectorFor(
          FaultRule(
            point: FaultPoints.keystoreUnwrap,
            kind: FaultKind.corruptKeyMaterial,
          ),
        ),
      );

      await expectLater(
        value.loadDocument('00000000-0000-4000-8000-000000000001'),
        throwsA(isA<KeyUnavailableException>()),
      );
      expect(delegate.loadCalls, 0, reason: 'the delegate must not run');
      expect(store.injector.callsAt(FaultPoints.keystoreUnwrap), 1);
      expect(
        store.injector.callsAt(FaultPoints.storeRead),
        0,
        reason: 'unwrap fails before the read point is reached',
      );
    });

    test('checks keystore.unwrap on the write path', () async {
      final FaultingSecureStore value = build(
        _injectorFor(
          FaultRule(
            point: FaultPoints.keystoreUnwrap,
            kind: FaultKind.corruptKeyMaterial,
          ),
        ),
      );
      bool ran = false;

      await expectLater(
        value.guardWrite(() {
          ran = true;
          return 'never';
        }),
        throwsA(isA<KeyUnavailableException>()),
      );
      expect(ran, isFalse);
      expect(store.injector.callsAt(FaultPoints.storeWrite), 0);
    });

    test('surfaces both SAVE-008 contexts at the unwrap point', () async {
      final (
        FaultingSecureStore outageStore,
        FaultingSecureStore resetStore,
      ) = (
        FaultingSecureStore(
          delegate: delegate,
          injector: _injectorFor(
            FaultRule(
              point: FaultPoints.keystoreUnwrap,
              kind: FaultKind.keystoreUnavailable,
            ),
          ),
        ),
        FaultingSecureStore(
          delegate: delegate,
          injector: _injectorFor(
            FaultRule(
              point: FaultPoints.keystoreUnwrap,
              kind: FaultKind.keystoreReset,
            ),
          ),
        ),
      );

      await expectLater(
        outageStore.loadDocument('00000000-0000-4000-8000-000000000001'),
        throwsA(
          isA<KeystoreUnavailableException>().having(
            (KeystoreUnavailableException error) => error.retryable,
            'retryable',
            isTrue,
          ),
        ),
      );
      await expectLater(
        resetStore.loadDocument('00000000-0000-4000-8000-000000000001'),
        throwsA(
          isA<KeystoreUnavailableException>().having(
            (KeystoreUnavailableException error) => error.retryable,
            'retryable',
            isFalse,
          ),
        ),
      );
      expect(delegate.loadCalls, 0);
    });

    test('surfaces an aggregate key fault at store.read', () async {
      final FaultingSecureStore value = build(
        _injectorFor(
          FaultRule(
            point: FaultPoints.storeRead,
            kind: FaultKind.corruptKeyMaterial,
          ),
        ),
      );

      await expectLater(
        value.loadDocument('00000000-0000-4000-8000-000000000001'),
        throwsA(isA<KeyUnavailableException>()),
      );
      expect(delegate.loadCalls, 0);
    });

    test(
      'surfaces a quota fault through the writeSignature port method',
      () async {
        final FaultingSecureStore value = build(
          _injectorFor(
            FaultRule(
              point: FaultPoints.storeWrite,
              kind: FaultKind.storageFull,
            ),
          ),
        );
        final WriteSignatureRequest request = WriteSignatureRequest(
          documentId: '00000000-0000-4000-8000-000000000001',
          assetId: '00000000-0000-4000-8000-000000000002',
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
          sha256: List<String>.filled(64, '0').join(),
        );

        await expectLater(
          value.writeSignature(request),
          throwsA(isA<StorageFullException>()),
        );
        expect(delegate.writeCalls, 0, reason: 'the delegate must not run');
      },
    );

    test('delegates a clean load to the wrapped adapter', () async {
      build(FaultInjector());
      await expectLater(
        store.loadDocument('00000000-0000-4000-8000-000000000001'),
        throwsA(isA<UnsupportedOperationException>()),
      );
      expect(delegate.loadCalls, 1);
    });

    test('guardWrite counts unwrap and pre-stage gate per attempt', () async {
      build(
        _injectorFor(
          FaultRule(
            point: FaultPoints.storeWrite,
            kind: FaultKind.storageFull,
            times: 1,
          ),
        ),
      );

      await expectLater(
        store.guardWrite(() => 'first'),
        throwsA(isA<StorageFullException>()),
      );
      expect(await store.guardWrite(() => 'second'), 'second');
      expect(store.injector.callsAt(FaultPoints.keystoreUnwrap), 2);
      expect(store.injector.callsAt(FaultPoints.storeWrite), 2);
      expect(store.injector.callsAt(FaultPoints.storeFsync), 0);
      expect(store.injector.callsAt(FaultPoints.storeCommit), 0);
    });
  });

  group('StagedWriteFaultSeam', () {
    // This is a contract model of storage-format.md §3.1, not an adapter
    // implementation. It proves that the seam exposes a failure before the
    // staged object exists, after it exists, at the fsync checkpoint, and after
    // revision promotion. Real files and durable-head assertions belong to the
    // adapter task that calls the seam: T028's Dart adapter can use this Dart
    // seam in its tests, while T026's Kotlin EncryptedStore needs an equivalent
    // native seam in T026. This model is not production evidence.
    test('promotes the head only when every phase is clear', () {
      final _CommitModel model = _CommitModel(
        StagedWriteFaultSeam(injector: FaultInjector()),
      );

      expect(model.save(), 'rev-1');
      expect(model.head, 'rev-1');
      expect(model.revisions, <String>{'rev-0', 'rev-1'});
      expect(model.staged, isNull);
      expect(model.promoted, isNull);
      expect(model.fsynced, isTrue);
      expect(model.cleanupCount, 0);
    });

    test('a fault before the staged write leaves no partial state', () {
      final _CommitModel model = _CommitModel(
        StagedWriteFaultSeam(
          injector: _injectorFor(
            FaultRule(
              point: FaultPoints.storeStage,
              kind: FaultKind.storageFull,
              startsAt: 1,
            ),
          ),
        ),
      );

      expect(() => _attemptCommit(model), throwsA(isA<StorageFullException>()));
      expect(model.staged, isNull);
      expect(model.promoted, isNull);
      expect(model.head, 'rev-0');
      expect(model.revisions, <String>{'rev-0'});
      expect(model.cleanupCount, 0);
    });

    test('a short write after staging removes the staged object', () {
      final _CommitModel model = _CommitModel(
        StagedWriteFaultSeam(
          injector: _injectorFor(
            FaultRule(
              point: FaultPoints.storeStage,
              kind: FaultKind.shortWrite,
              startsAt: 2,
            ),
          ),
        ),
      );

      expect(
        () => _attemptCommit(model),
        throwsA(isA<StorageWriteException>()),
      );
      expect(model.staged, isNull);
      expect(model.head, 'rev-0');
      expect(model.revisions, <String>{'rev-0'});
      expect(model.cleanupCount, 1);
    });

    test('beforeFsync models a failed fsync, not a post-fsync abort', () {
      final _CommitModel model = _CommitModel(
        StagedWriteFaultSeam(
          injector: _injectorFor(
            FaultRule(
              point: FaultPoints.storeFsync,
              kind: FaultKind.fsyncFailure,
            ),
          ),
        ),
      );

      expect(
        () => _attemptCommit(model),
        throwsA(isA<StorageWriteException>()),
      );
      expect(
        model.fsynced,
        isFalse,
        reason: 'the fault fires immediately before fd.sync()',
      );
      expect(model.staged, isNull);
      expect(model.head, 'rev-0');
      expect(model.revisions, <String>{'rev-0'});
      expect(model.cleanupCount, 1);
    });

    test('a commit fault after promotion keeps the old head and prunes', () {
      final _CommitModel model = _CommitModel(
        StagedWriteFaultSeam(
          injector: _injectorFor(
            FaultRule(
              point: FaultPoints.storeCommit,
              kind: FaultKind.writeInterrupted,
            ),
          ),
        ),
      );

      expect(
        () => _attemptCommit(model),
        throwsA(isA<StorageWriteException>()),
      );
      expect(model.staged, isNull);
      expect(model.promoted, isNull);
      expect(model.head, 'rev-0');
      expect(model.revisions, <String>{
        'rev-0',
      }, reason: 'the unreferenced promoted revision is removed');
      expect(model.cleanupCount, 2);
    });
  });

  group('FaultingPdfExport', () {
    late _RecordingExport delegate;

    setUp(() {
      delegate = _RecordingExport(_descriptor(CapabilityKind.pdfExport));
    });

    test(
      'maps a validation fault to EXP-002 without running the delegate',
      () async {
        final FaultingPdfExport export = FaultingPdfExport(
          delegate: delegate,
          injector: _injectorFor(
            FaultRule(
              point: FaultPoints.exportValidate,
              kind: FaultKind.exportFailure,
            ),
          ),
        );
        bool ran = false;

        await expectLater(
          export.guardValidate(() {
            ran = true;
            return 'valid';
          }),
          throwsA(
            isA<ExportFailedException>().having(
              (ExportFailedException error) => error.code,
              'code',
              'EXP-002',
            ),
          ),
        );
        expect(ran, isFalse);
      },
    );

    test('maps a write fault to EXP-002 and produces no candidate', () async {
      final FaultingPdfExport export = FaultingPdfExport(
        delegate: delegate,
        injector: _injectorFor(
          FaultRule(
            point: FaultPoints.exportWrite,
            kind: FaultKind.exportFailure,
          ),
        ),
      );
      bool ran = false;

      await expectLater(
        export.guardExport(() {
          ran = true;
          return 'artifact';
        }),
        throwsA(isA<ExportFailedException>()),
      );
      expect(ran, isFalse);
      expect(export.cleanupFailures, isEmpty);
    });

    test('deletes a candidate that fails the injected verification', () async {
      final FaultingPdfExport export = FaultingPdfExport(
        delegate: delegate,
        injector: _injectorFor(
          FaultRule(
            point: FaultPoints.exportVerify,
            kind: FaultKind.exportFailure,
          ),
        ),
      );
      bool ran = false;
      String? deleted;

      await expectLater(
        export.guardExport(
          () {
            ran = true;
            return 'artifact-1';
          },
          artifactId: (String value) => value,
          deleteArtifact: (String id) async {
            deleted = id;
          },
        ),
        throwsA(isA<ExportFailedException>()),
      );
      expect(ran, isTrue);
      expect(deleted, 'artifact-1');
      expect(export.cleanupFailures, isEmpty);
    });

    test(
      'records a best-effort cleanup failure and still throws EXP-002',
      () async {
        final FaultingPdfExport export = FaultingPdfExport(
          delegate: delegate,
          injector: _injectorFor(
            FaultRule(
              point: FaultPoints.exportVerify,
              kind: FaultKind.exportFailure,
            ),
          ),
        );

        await expectLater(
          export.guardExport(
            () => 'artifact-2',
            artifactId: (String value) => value,
            deleteArtifact: (String id) async {
              throw StateError('cleanup failed');
            },
          ),
          throwsA(isA<ExportFailedException>()),
        );
        expect(export.cleanupFailures, hasLength(1));
        expect(export.cleanupFailures.single, isA<StateError>());
      },
    );

    test('returns the candidate when both points are clear', () async {
      final FaultingPdfExport export = FaultingPdfExport(
        delegate: delegate,
        injector: FaultInjector(),
      );
      expect(await export.guardExport(() => 'artifact-3'), 'artifact-3');
    });
  });

  group('FakeRegistry', () {
    test('exposes ten ports with descriptors in capability order', () {
      final FakeRegistry registry = FakeRegistry(
        initialUtc: DateTime.utc(2026, 11, 15, 9),
      );

      final List<PlatformCapability> ports = <PlatformCapability>[
        registry.import,
        registry.raster,
        registry.ocr,
        registry.store,
        registry.export,
        registry.delivery,
        registry.lifecycle,
        registry.clock,
        registry.ids,
        registry.diagnostics,
      ];
      expect(
        ports.map((PlatformCapability port) => port.descriptor.kind),
        CapabilityKind.values,
      );
      expect(registry.descriptors, hasLength(10));
      expect(registry.hasSimulatedCapabilities, isTrue);
      expect(registry.isDevelopmentEnvironment, isTrue);
      expect(
        registry.descriptors.every(
          (CapabilityDescriptor value) =>
              value.evidence.evidenceClass == EvidenceClass.simulated,
        ),
        isTrue,
      );
    });

    test('provides the same deterministic clock, IDs, and lifecycle', () async {
      final FakeRegistry registry = FakeRegistry(
        initialUtc: DateTime.utc(2026, 11, 15, 9),
      );

      expect(registry.clock.nowUtc(), DateTime.utc(2026, 11, 15, 9));
      registry.clock.advance(const Duration(seconds: 2));
      expect(registry.clock.nowUtc(), DateTime.utc(2026, 11, 15, 9, 0, 2));

      expect(registry.ids.newId(), '00000000-0000-4000-8000-000000000001');
      expect(registry.ids.newId(), '00000000-0000-4000-8000-000000000002');
      expect(registry.ids.newIdempotencyKey(), 'idempotency-key-000001');

      final List<AppLifecycleSignal> seen = <AppLifecycleSignal>[];
      final StreamSubscription<AppLifecycleSignal> subscription = registry
          .lifecycle
          .signals
          .listen(seen.add);
      registry.lifecycle.emitAll(<AppLifecycleSignal>[
        AppLifecycleSignal.inactive,
        AppLifecycleSignal.paused,
        AppLifecycleSignal.resumed,
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(seen, <AppLifecycleSignal>[
        AppLifecycleSignal.inactive,
        AppLifecycleSignal.paused,
        AppLifecycleSignal.resumed,
      ]);
      expect(registry.lifecycle.emitted, hasLength(3));
      await subscription.cancel();
      await registry.lifecycle.close();
    });

    test('wires the same injector into store and export', () {
      final FakeRegistry registry = FakeRegistry();

      expect(identical(registry.store.injector, registry.faults), isTrue);
      expect(identical(registry.export.injector, registry.faults), isTrue);
      expect(identical(registry.writeSeam.injector, registry.faults), isTrue);
      expect(registry.store.delegate, isNotNull);
      expect(registry.export.delegate, isNotNull);
    });

    test('injects a keystore fault through the registry store', () async {
      final FakeRegistry registry = FakeRegistry(
        faults: _injectorFor(
          FaultRule(
            point: FaultPoints.storeRead,
            kind: FaultKind.keystoreUnavailable,
          ),
        ),
      );

      await expectLater(
        registry.store.loadDocument('00000000-0000-4000-8000-000000000001'),
        throwsA(isA<KeystoreUnavailableException>()),
      );
    });

    test('injects an export fault through the registry export', () async {
      final FakeRegistry registry = FakeRegistry(
        faults: _injectorFor(
          FaultRule(
            point: FaultPoints.exportWrite,
            kind: FaultKind.exportFailure,
          ),
        ),
      );

      await expectLater(
        registry.export.guardExport(() => 'artifact'),
        throwsA(isA<ExportFailedException>()),
      );
    });

    test('unprovided capabilities fail with the typed PLT-001 exception', () {
      final FakeRegistry registry = FakeRegistry();

      expect(
        () => registry.import.pickAndImport(ImportRequest()),
        throwsA(
          isA<UnsupportedOperationException>().having(
            (UnsupportedOperationException error) => error.code,
            'code',
            'PLT-001',
          ),
        ),
      );
      expect(
        () => registry.diagnostics.event('probe'),
        throwsA(isA<UnsupportedOperationException>()),
      );
    });

    test('a non-simulated fake registry reports no simulated capability', () {
      final FakeRegistry registry = FakeRegistry(simulated: false);

      expect(registry.hasSimulatedCapabilities, isFalse);
      expect(registry.isDevelopmentEnvironment, isFalse);
      expect(
        registry.descriptors.every(
          (CapabilityDescriptor value) =>
              value.evidence.evidenceClass == EvidenceClass.none,
        ),
        isTrue,
      );
    });

    test('rejects an override descriptor for the wrong capability', () {
      expect(
        () => FakeRegistry(
          documentImport: _WrongKindImport(_descriptor(CapabilityKind.clock)),
        ),
        throwsArgumentError,
      );
    });
  });
}

/// A minimal contract model of the §3.1 verified-commit protocol.
///
/// It is deliberately not a production adapter: it has no files, no
/// encryption, and no Android Keystore. It exists only to prove that the seam
/// fires at a real phase boundary and that a failed attempt can keep the old
/// head and prune the unreferenced promoted revision.
final class _CommitModel {
  _CommitModel(this.seam);

  final StagedWriteFaultSeam seam;
  final Set<String> revisions = <String>{'rev-0'};

  String head = 'rev-0';
  String? staged;
  String? promoted;
  bool fsynced = false;
  int cleanupCount = 0;

  String save() {
    seam.beforeStagedWrite();
    staged = 'rev-1';
    seam.afterStagedWrite();
    seam.beforeFsync();
    fsynced = true;
    promoted = 'rev-1';
    revisions.add(promoted!);
    seam.beforeHeadCommit();
    head = promoted!;
    staged = null;
    promoted = null;
    return head;
  }

  void cleanupAfterFailure() {
    if (staged != null) {
      staged = null;
      cleanupCount++;
    }
    final String? candidate = promoted;
    if (candidate != null && candidate != head) {
      revisions.remove(candidate);
      promoted = null;
      cleanupCount++;
    }
  }
}

void _attemptCommit(_CommitModel model) {
  try {
    model.save();
  } catch (_) {
    model.cleanupAfterFailure();
    rethrow;
  }
}

/// A store whose read count proves whether a fault short-circuited delegation.
final class _RecordingStore implements SecureStorePort {
  _RecordingStore(this.descriptor);

  @override
  final CapabilityDescriptor descriptor;

  int loadCalls = 0;
  int writeCalls = 0;

  @override
  Future<LoadedDocument> loadDocument(String documentId) async {
    loadCalls++;
    throw UnsupportedOperationException();
  }

  @override
  Future<void> writeSignature(WriteSignatureRequest request) async {
    writeCalls++;
    throw UnsupportedOperationException();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedOperationException();
  }
}

/// An export adapter that records whether a guard reached it.
final class _RecordingExport implements PdfExportPort {
  _RecordingExport(this.descriptor);

  @override
  final CapabilityDescriptor descriptor;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedOperationException();
  }
}

/// A deliberately mismatched import port for the descriptor-order check.
final class _WrongKindImport implements DocumentImportPort {
  _WrongKindImport(this.descriptor);

  @override
  final CapabilityDescriptor descriptor;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedOperationException();
  }
}
