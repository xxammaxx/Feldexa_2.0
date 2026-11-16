// T031 host-VM startup sweep tests.
//
// Evidence class: NONE. These are host checks with in-memory fakes; they are
// not SIMULATED browser evidence and they are not EMULATOR or DEVICE Android
// runtime evidence. The tests exercise the failure cases required by
// constitution Principle VIII and `contracts/storage-format.md` §4/§5:
//
//   * aggregate-scoped key loss (`SAVE-002`) and global key-store loss
//     (`SAVE-008`) delete nothing and never report success;
//   * corrupt head (`SAVE-003`) and head fallback (`SAVE-004`);
//   * storage exhaustion (`SAVE-001`) with the last durable state intact;
//   * stale versus fresh `tmp/` and export-preview artifacts, with visible
//     documents/templates untouched;
//   * deterministic outcome and the documented processing bound.
//
// The fakes are local to this test file on purpose: `apps/feldexa_app` has no
// dependency on the simulated adapter or testkit packages, and adding one
// would change the reviewed dependency graph.

@TestOn('vm')
library;

import 'dart:io';

import 'package:feldexa_app/bootstrap/startup_sweep.dart';
import 'package:feldexa_app/bootstrap/startup_sweep_io.dart';
import 'package:feldexa_app/bootstrap/startup_sweep_platform.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

/// Fixed wall clock used by every test; the sweep must never call
/// `DateTime.now`.
final DateTime _now = DateTime.utc(2026, 11, 16, 12);

/// Committed German resources, read through the generated ARB.
final AppLocalizations _de = lookupAppLocalizations(const Locale('de'));

String _id(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

StartupSweepEntry _entry(
  String name,
  Duration age, {
  bool isDirectory = false,
}) {
  return StartupSweepEntry(
    name: name,
    lastModifiedUtc: _now.subtract(age),
    isDirectory: isDirectory,
  );
}

StoredMeta _meta({
  required String id,
  StoreKind kind = StoreKind.document,
  String title = 'Dokument',
  bool readable = true,
  String? unreadableReasonCode,
}) {
  return StoredMeta(
    id: id,
    kind: kind,
    title: title,
    createdAt: _now.subtract(const Duration(days: 2)),
    updatedAt: _now.subtract(const Duration(hours: 1)),
    latestRevisionId: readable ? id : null,
    lastDurableAt: readable ? _now.subtract(const Duration(hours: 1)) : null,
    readable: readable,
    unreadableReasonCode: unreadableReasonCode,
  );
}

RecoveryStamp _healthyStamp() {
  return RecoveryStamp(
    verifiedRevisionId: _id(99),
    committedAt: _now.subtract(const Duration(minutes: 5)),
    headCorrupt: false,
    fellBackToOlderRevision: false,
  );
}

void main() {
  group('order and platform seam', () {
    test('export sweep precedes native recovery and contract reads', () async {
      final List<String> trace = <String>[];
      final StoredMeta document = _meta(id: _id(1));
      final StoredMeta template = _meta(id: _id(2), kind: StoreKind.template);
      final _FakeStore store = _FakeStore(
        trace: trace,
        documents: <StoredMeta>[document],
        templates: <StoredMeta>[template],
        stamps: <String, RecoveryStamp>{
          document.id: _healthyStamp(),
          template.id: _healthyStamp(),
        },
      );
      final _FakeFileSystem files = _FakeFileSystem(trace: trace);
      final _FixedClock clock = _FixedClock(_now);
      final StartupSweep sweep = StartupSweep(
        store: store,
        clock: clock,
        files: files,
        nativeRecovery: () async {
          trace.add('native');
          return const StartupRecoveryCounts.none();
        },
      );

      final StartupSweepResult result = await sweep.run();

      // T031-B2: Dart-owned §4 step 4 runs before the monolithic native
      // call so it stays before native steps 5–6.
      expect(trace, <String>[
        'export.list',
        'native',
        'temp.list',
        'list:document',
        'stamp:${document.id}',
        'list:template',
        'stamp:${template.id}',
      ]);
      expect(result.status, StartupSweepStatus.clean);
      expect(result.isComplete, isTrue);
      expect(clock.reads, 1);
      expect(store.deleteCalls, 0);
    });

    test('the platform selector has no native recovery without a runtime', () {
      // On the host VM this selects the Android binding but the runtime is not
      // an AndroidPlatformRuntime, so the callback stays null. On Web the stub
      // always returns null. Either way the sweep performs reads only.
      expect(platformStartupRecovery(null), isNull);
      expect(platformStartupRecovery(Object()), isNull);
    });
  });

  group('key material unavailable', () {
    test('aggregate SAVE-002 deletes nothing and is reported', () async {
      final StoredMeta readable = _meta(id: _id(1));
      final StoredMeta unreadable = _meta(
        id: _id(2),
        title: 'Nicht lesbar',
        readable: false,
        unreadableReasonCode: 'SAVE-002',
      );
      final _FakeStore store = _FakeStore(
        documents: <StoredMeta>[readable, unreadable],
        stamps: <String, RecoveryStamp>{readable.id: _healthyStamp()},
      );
      final _FakeFileSystem files = _FakeFileSystem(
        temporaryEntries: <StartupSweepEntry>[
          _entry('scratch.tmp', Duration.zero),
        ],
      );

      final StartupSweepResult result = await StartupSweep(
        store: store,
        clock: _FixedClock(_now),
        files: files,
      ).run();

      expect(result.status, StartupSweepStatus.degraded);
      expect(result.isComplete, isFalse);
      expect(result.unreadableCount, 1);
      // No aggregate data is ever deletable through the sweep surface.
      expect(store.deleteCalls, 0);
      expect(store.documents, <StoredMeta>[readable, unreadable]);
      expect(store.calls, isNot(contains('stamp:${unreadable.id}')));
      // §4 step 1 still applies: unknown staging names are stale immediately.
      expect(files.deletedTemporary, <String>['scratch.tmp']);

      final StartupSweepNotice notice = result.notices.singleWhere(
        (StartupSweepNotice value) => value.code == 'SAVE-002',
      );
      expect(notice.statusLabel, _de.statusUnreadable);
      expect(notice.message, _de.save002);
      expect(notice.recovery, _de.save002Recovery);
      expect(notice.aggregateId, unreadable.id);
    });

    test('global SAVE-008 deletes nothing and is reported', () async {
      final StoredMeta document = _meta(id: _id(1));
      final StoredMeta template = _meta(id: _id(2), kind: StoreKind.template);
      final _FakeStore store = _FakeStore(
        documents: <StoredMeta>[document],
        templates: <StoredMeta>[template],
        listErrors: <StoreKind, Object>{
          StoreKind.document: KeystoreUnavailableException(),
          StoreKind.template: KeystoreUnavailableException(),
        },
      );
      final _FakeFileSystem files = _FakeFileSystem(
        temporaryEntries: <StartupSweepEntry>[
          _entry('scratch.tmp', Duration.zero),
        ],
      );

      final StartupSweepResult result = await StartupSweep(
        store: store,
        clock: _FixedClock(_now),
        files: files,
      ).run();

      expect(result.status, StartupSweepStatus.degraded);
      expect(result.isComplete, isFalse);
      expect(store.deleteCalls, 0);
      expect(store.documents, <StoredMeta>[document]);
      expect(store.templates, <StoredMeta>[template]);
      expect(
        result.issues.map((StartupSweepIssue value) => value.catalogCode),
        contains('SAVE-008'),
      );
      final StartupSweepNotice notice = result.notices.singleWhere(
        (StartupSweepNotice value) => value.code == 'SAVE-008',
      );
      expect(notice.statusLabel, _de.statusUnreadable);
      expect(notice.message, _de.save008);
      expect(notice.recovery, _de.save008Recovery);
      expect(notice.aggregateId, isNull);
    });

    test(
      'a native SAVE-008 still sweeps plaintext previews and skips reads',
      () async {
        final _FakeStore store = _FakeStore(
          documents: <StoredMeta>[_meta(id: _id(1))],
        );
        final _FakeFileSystem files = _FakeFileSystem(
          temporaryEntries: <StartupSweepEntry>[
            _entry('scratch.tmp', const Duration(days: 3)),
          ],
          exportArtifacts: <StartupSweepEntry>[
            _entry('preview.pdf', const Duration(days: 3)),
          ],
        );

        final StartupSweepResult result = await StartupSweep(
          store: store,
          clock: _FixedClock(_now),
          files: files,
          nativeRecovery: () async => throw KeystoreUnavailableException(),
        ).run();

        expect(result.status, StartupSweepStatus.degraded);
        expect(result.isComplete, isFalse);
        // T031-A2: plaintext export cleanup is never skipped by a native
        // recovery failure. This replaces the unsafe "no deletion"
        // expectation of the first candidate.
        expect(files.deletedExports, <String>['preview.pdf']);
        expect(files.deletedTemporary, <String>['scratch.tmp']);
        expect(files.exportArtifacts, isEmpty);
        // Aggregate reads need decryption, so they are skipped.
        expect(store.calls, isEmpty);
        expect(store.deleteCalls, 0);
        expect(result.issues.single.catalogCode, 'SAVE-008');
        expect(result.notices.single.code, 'SAVE-008');
      },
    );
  });

  group('corrupt head and recovery fallback', () {
    test(
      'native fallback adoption survives later stamps that report false',
      () async {
        // T031-A1 regression: native recovery commits the repaired head, so
        // the later recoveryStamp reads all report
        // `fellBackToOlderRevision: false`. The positive native adoption count
        // must still produce the SAVE-004 warning.
        final StoredMeta document = _meta(id: _id(1));
        final _FakeStore store = _FakeStore(
          documents: <StoredMeta>[document],
          stamps: <String, RecoveryStamp>{document.id: _healthyStamp()},
        );
        const StartupRecoveryCounts native = StartupRecoveryCounts(
          tempEntriesRemoved: 0,
          incompleteAggregatesRemoved: 0,
          unreadableAggregates: 0,
          fallbackAdoptions: 1,
          orphanAliasesRemoved: 0,
          orphanAliasesRetained: 0,
          orphanAliasesFailed: 0,
          aliasSweepSkipped: false,
          ambiguousRevisionOrder: 0,
          prunedRevisions: 0,
        );

        final StartupSweepResult result = await StartupSweep(
          store: store,
          clock: _FixedClock(_now),
          files: _FakeFileSystem(),
          nativeRecovery: () async => native,
        ).run();

        expect(result.status, StartupSweepStatus.recovered);
        expect(result.nativeFallbackCount, 1);
        // The later stamp itself reports no fallback.
        expect(result.fallbackCount, 0);
        final StartupSweepNotice notice = result.notices.singleWhere(
          (StartupSweepNotice value) => value.code == 'SAVE-004',
        );
        expect(notice.statusLabel, _de.durabilityRecoveryFallback);
        expect(notice.message, _de.save004);
        expect(notice.recovery, _de.save004Recovery);
        expect(notice.aggregateId, isNull);
      },
    );

    test('SAVE-004 fallback surfaces the German guidance', () async {
      final StoredMeta document = _meta(id: _id(1));
      final RecoveryStamp stamp = RecoveryStamp(
        verifiedRevisionId: _id(9),
        committedAt: _now.subtract(const Duration(minutes: 7)),
        headCorrupt: true,
        fellBackToOlderRevision: true,
      );
      final _FakeStore store = _FakeStore(
        documents: <StoredMeta>[document],
        stamps: <String, RecoveryStamp>{document.id: stamp},
      );

      final StartupSweepResult result = await StartupSweep(
        store: store,
        clock: _FixedClock(_now),
        files: _FakeFileSystem(),
      ).run();

      expect(result.status, StartupSweepStatus.recovered);
      expect(result.isComplete, isTrue);
      expect(result.fallbackCount, 1);
      expect(result.unreadableCount, 0);
      final AggregateRecovery aggregate = result.aggregates.single;
      expect(aggregate.fellBackToOlderRevision, isTrue);
      // Values come only from the adapter's verified stamp.
      expect(aggregate.verifiedRevisionId, _id(9));
      expect(aggregate.committedAt, stamp.committedAt);

      final StartupSweepNotice notice = result.notices.single;
      expect(notice.code, 'SAVE-004');
      expect(notice.statusLabel, _de.durabilityRecoveryFallback);
      expect(notice.message, _de.save004);
      expect(notice.recovery, _de.save004Recovery);
      expect(notice.aggregateId, document.id);
      expect(notice.kind, StoreKind.document);
    });

    test('corrupt head without a verified revision is degraded', () async {
      final StoredMeta document = _meta(id: _id(1));
      final _FakeStore store = _FakeStore(
        documents: <StoredMeta>[document],
        stamps: <String, RecoveryStamp>{
          document.id: RecoveryStamp(
            headCorrupt: true,
            fellBackToOlderRevision: false,
          ),
        },
      );

      final StartupSweepResult result = await StartupSweep(
        store: store,
        clock: _FixedClock(_now),
        files: _FakeFileSystem(),
      ).run();

      expect(result.status, StartupSweepStatus.degraded);
      expect(result.isComplete, isFalse);
      expect(result.unreadableCount, 1);
      expect(result.fallbackCount, 0);
      expect(result.notices, isEmpty);
      expect(result.issues.single.catalogCode, 'SAVE-003');
    });

    test('a fallback without a verified revision is never success', () async {
      final StoredMeta document = _meta(id: _id(1));
      final _FakeStore store = _FakeStore(
        documents: <StoredMeta>[document],
        stamps: <String, RecoveryStamp>{
          document.id: RecoveryStamp(
            headCorrupt: true,
            fellBackToOlderRevision: true,
          ),
        },
      );

      final StartupSweepResult result = await StartupSweep(
        store: store,
        clock: _FixedClock(_now),
        files: _FakeFileSystem(),
      ).run();

      expect(result.status, StartupSweepStatus.degraded);
      expect(result.isComplete, isFalse);
      expect(result.unreadableCount, 1);
      expect(
        result.notices.where(
          (StartupSweepNotice value) => value.code == 'SAVE-004',
        ),
        isEmpty,
      );
      expect(
        result.issues.map((StartupSweepIssue value) => value.catalogCode),
        contains('SAVE-003'),
      );
    });
  });

  group('storage exhaustion', () {
    test(
      'SAVE-001 is surfaced and the last durable state stays intact',
      () async {
        final StoredMeta document = _meta(id: _id(1));
        final StoredMeta template = _meta(id: _id(2), kind: StoreKind.template);
        final _FakeStore store = _FakeStore(
          documents: <StoredMeta>[document],
          templates: <StoredMeta>[template],
          listErrors: <StoreKind, Object>{
            StoreKind.document: StorageFullException(),
          },
          stamps: <String, RecoveryStamp>{template.id: _healthyStamp()},
        );

        final StartupSweepResult result = await StartupSweep(
          store: store,
          clock: _FixedClock(_now),
          files: _FakeFileSystem(),
        ).run();

        expect(result.status, StartupSweepStatus.degraded);
        expect(result.isComplete, isFalse);
        expect(store.deleteCalls, 0);
        // The durable projection is unchanged and the template read still ran.
        expect(store.documents, <StoredMeta>[document]);
        expect(store.calls, contains('list:template'));
        expect(result.issues.single.stage, StartupSweepStage.documentList);
        expect(result.issues.single.catalogCode, 'SAVE-001');
        expect(result.issues.single.retryable, isTrue);
        final StartupSweepNotice notice = result.notices.singleWhere(
          (StartupSweepNotice value) => value.code == 'SAVE-001',
        );
        expect(notice.message, _de.save001);
        expect(notice.recovery, _de.save001Recovery);
        expect(notice.statusLabel, isNull);
      },
    );

    test('SAVE-005 schema-too-new surfaces the update guidance', () async {
      final _FakeStore store = _FakeStore(
        listErrors: <StoreKind, Object>{
          StoreKind.document: SchemaTooNewException(),
        },
      );

      final StartupSweepResult result = await StartupSweep(
        store: store,
        clock: _FixedClock(_now),
        files: _FakeFileSystem(),
      ).run();

      expect(result.status, StartupSweepStatus.degraded);
      expect(result.isComplete, isFalse);
      expect(result.issues.single.catalogCode, 'SAVE-005');
      final StartupSweepNotice notice = result.notices.singleWhere(
        (StartupSweepNotice value) => value.code == 'SAVE-005',
      );
      expect(notice.statusLabel, isNull);
      expect(notice.message, _de.save005);
      expect(notice.recovery, _de.save005Recovery);
    });
  });

  group('temporary and export-preview ages', () {
    test(
      'stale entries are removed, fresh entries and aggregates are kept',
      () async {
        final StoredMeta document = _meta(id: _id(1));
        final StoredMeta template = _meta(id: _id(2), kind: StoreKind.template);
        final _FakeStore store = _FakeStore(
          documents: <StoredMeta>[document],
          templates: <StoredMeta>[template],
          stamps: <String, RecoveryStamp>{
            document.id: _healthyStamp(),
            template.id: _healthyStamp(),
          },
        );
        final _FakeFileSystem files = _FakeFileSystem(
          temporaryEntries: <StartupSweepEntry>[
            _entry('${_id(1)}.part', const Duration(hours: 25)),
            _entry('${_id(2)}.head', const Duration(hours: 23)),
            _entry('${_id(3)}.meta', const Duration(hours: 24)),
            _entry('scratch.tmp', Duration.zero),
            _entry('unknown-dir', Duration.zero, isDirectory: true),
          ],
          exportArtifacts: <StartupSweepEntry>[
            _entry('exp-1.pdf', const Duration(hours: 25)),
            _entry('exp-2.pdf.tmp', const Duration(hours: 25)),
            _entry('exp-3.pdf', const Duration(hours: 23)),
            _entry('exp-4.pdf.tmp', const Duration(hours: 24)),
          ],
        );

        final StartupSweepResult result = await StartupSweep(
          store: store,
          clock: _FixedClock(_now),
          files: files,
        ).run();

        expect(result.temporary.scanned, 5);
        expect(result.temporary.removed, 3);
        expect(result.temporary.kept, 2);
        expect(result.temporary.failed, 0);
        expect(files.deletedTemporary, <String>[
          '${_id(1)}.part',
          'scratch.tmp',
          'unknown-dir',
        ]);
        expect(result.exportPreviews.scanned, 4);
        expect(result.exportPreviews.removed, 2);
        expect(result.exportPreviews.kept, 2);
        expect(files.deletedExports, <String>['exp-1.pdf', 'exp-2.pdf.tmp']);
        // Nothing in the aggregate namespace is reachable by the sweep.
        expect(store.deleteCalls, 0);
        expect(store.documents, <StoredMeta>[document]);
        expect(store.templates, <StoredMeta>[template]);
        expect(result.boundReached, isFalse);
      },
    );

    test(
      'session end removes every export preview regardless of age',
      () async {
        final _FakeFileSystem files = _FakeFileSystem(
          exportArtifacts: <StartupSweepEntry>[
            _entry('fresh.pdf', Duration.zero),
            _entry('old.pdf.tmp', const Duration(hours: 48)),
          ],
        );
        final StartupSweep sweep = StartupSweep(
          store: _FakeStore(),
          clock: _FixedClock(_now),
          files: files,
        );

        final StartupSweepRemoval first = await sweep.sweepSessionEnd();
        final StartupSweepRemoval second = await sweep.sweepSessionEnd();

        expect(first.removed, 2);
        expect(first.kept, 0);
        expect(first.listingFailed, isFalse);
        expect(files.deletedExports, <String>['fresh.pdf', 'old.pdf.tmp']);
        expect(second.removed, 0);
        expect(second.scanned, 0);
      },
    );

    test(
      'session end reports a listing failure instead of false success',
      () async {
        final _FakeFileSystem files = _FakeFileSystem()
          ..listExportError = SecurityException();
        final StartupSweep sweep = StartupSweep(
          store: _FakeStore(),
          clock: _FixedClock(_now),
          files: files,
        );

        final StartupSweepRemoval result = await sweep.sweepSessionEnd();

        expect(result.listingFailed, isTrue);
        expect(result.removed, 0);
        expect(result.scanned, 0);
        expect(files.deletedExports, isEmpty);
      },
    );

    test('a deletion failure is surfaced, not swallowed', () async {
      final _FakeFileSystem files = _FakeFileSystem(
        temporaryEntries: <StartupSweepEntry>[
          _entry('${_id(1)}.part', const Duration(hours: 30)),
        ],
      )..deleteTemporaryErrors['${_id(1)}.part'] = SecurityException();

      final StartupSweepResult result = await StartupSweep(
        store: _FakeStore(),
        clock: _FixedClock(_now),
        files: files,
      ).run();

      expect(result.status, StartupSweepStatus.degraded);
      expect(result.temporary.failed, 1);
      expect(result.temporary.removed, 0);
      expect(files.deletedTemporary, isEmpty);
      expect(result.issues.single.catalogCode, 'PLT-002');
    });
  });

  group('determinism and bound', () {
    test(
      'the documented bound is pinned and reached deterministically',
      () async {
        expect(StartupSweep.defaultMaxEntriesPerCategory, 512);
        expect(StartupSweep.staleAge, const Duration(hours: 24));

        final List<StartupSweepEntry> entries = <StartupSweepEntry>[
          for (int index = 1; index <= 5; index++)
            _entry('${_id(index)}.part', const Duration(hours: 30)),
        ];
        final _FakeFileSystem files = _FakeFileSystem(
          temporaryEntries: entries,
        );
        final _FixedClock clock = _FixedClock(_now);

        final StartupSweepResult result = await StartupSweep(
          store: _FakeStore(),
          clock: clock,
          files: files,
          maxEntriesPerCategory: 3,
        ).run();

        expect(result.boundReached, isTrue);
        expect(result.temporary.scanned, 3);
        expect(result.temporary.removed, 3);
        expect(result.temporary.boundReached, isTrue);
        expect(result.status, StartupSweepStatus.degraded);
        expect(files.deletedTemporary, <String>[
          '${_id(1)}.part',
          '${_id(2)}.part',
          '${_id(3)}.part',
        ]);
        expect(files.deletedTemporary, isNot(contains('${_id(4)}.part')));
        expect(clock.reads, 1);
      },
    );

    test('identical inputs produce the same outcome', () async {
      final StartupSweepResult first = await _buildDeterministicFixture().run();
      final StartupSweepResult second = await _buildDeterministicFixture()
          .run();

      expect(second.status, first.status);
      expect(second.temporary.scanned, first.temporary.scanned);
      expect(second.temporary.removed, first.temporary.removed);
      expect(second.temporary.kept, first.temporary.kept);
      expect(second.exportPreviews.removed, first.exportPreviews.removed);
      expect(second.boundReached, first.boundReached);
      expect(
        second.aggregates.map((AggregateRecovery value) => value.meta.id),
        first.aggregates.map((AggregateRecovery value) => value.meta.id),
      );
      expect(
        second.notices.map((StartupSweepNotice value) => value.code),
        first.notices.map((StartupSweepNotice value) => value.code),
      );
    });
  });

  group('production io filesystem adapter', () {
    late Directory root;
    late Directory exports;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('t031_io_');
      exports = Directory(
        '${root.path}${Platform.pathSeparator}feldexa_exports',
      );
      await exports.create(recursive: true);
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('lists only exports and reports staging as native-owned', () async {
      final File old = File('${exports.path}${Platform.pathSeparator}old.pdf')
        ..writeAsStringSync('old');
      old.setLastModifiedSync(_now.subtract(const Duration(hours: 25)));
      final File fresh = File(
        '${exports.path}${Platform.pathSeparator}fresh.pdf.tmp',
      )..writeAsStringSync('fresh');
      fresh.setLastModifiedSync(_now);
      Directory('${exports.path}${Platform.pathSeparator}nested').createSync();
      final IoStartupSweepFileSystem files = IoStartupSweepFileSystem(
        exportDirectory: exports,
      );

      expect(await files.listTemporaryEntries(), isEmpty);
      final List<StartupSweepEntry> entries = await files.listExportArtifacts();
      expect(
        entries.map((StartupSweepEntry value) => value.name).toSet(),
        <String>{'old.pdf', 'fresh.pdf.tmp', 'nested'},
      );
      expect(
        entries
            .singleWhere((StartupSweepEntry value) => value.name == 'nested')
            .isDirectory,
        isTrue,
      );
      // Native T026 owns staging; the Dart adapter must refuse it.
      await expectLater(
        files.deleteTemporaryEntry(entries.first),
        throwsA(isA<UnsupportedOperationException>()),
      );
      // A directory is never deleted recursively.
      await expectLater(
        files.deleteExportArtifact(
          entries.singleWhere(
            (StartupSweepEntry value) => value.name == 'nested',
          ),
        ),
        throwsA(isA<SecurityException>()),
      );
      expect(
        Directory('${exports.path}${Platform.pathSeparator}nested')
            .existsSync(),
        isTrue,
      );
    });

    test('full sweep removes stale previews and keeps fresh ones', () async {
      final File old = File('${exports.path}${Platform.pathSeparator}old.pdf')
        ..writeAsStringSync('old');
      old.setLastModifiedSync(_now.subtract(const Duration(hours: 25)));
      final File fresh = File(
        '${exports.path}${Platform.pathSeparator}fresh.pdf.tmp',
      )..writeAsStringSync('fresh');
      fresh.setLastModifiedSync(_now);
      final StoredMeta document = _meta(id: _id(1));
      final _FakeStore store = _FakeStore(
        documents: <StoredMeta>[document],
        stamps: <String, RecoveryStamp>{document.id: _healthyStamp()},
      );

      final StartupSweepResult result = await StartupSweep(
        store: store,
        clock: _FixedClock(_now),
        files: IoStartupSweepFileSystem(exportDirectory: exports),
      ).run();

      expect(result.status, StartupSweepStatus.recovered);
      expect(result.exportPreviews.removed, 1);
      expect(result.exportPreviews.kept, 1);
      expect(await old.exists(), isFalse);
      expect(await fresh.exists(), isTrue);
      expect(store.deleteCalls, 0);
    });

    test('a missing export directory is empty and is not created', () async {
      final Directory missing = Directory(
        '${root.path}${Platform.pathSeparator}missing_exports',
      );
      final IoStartupSweepFileSystem files = IoStartupSweepFileSystem(
        exportDirectory: missing,
      );

      expect(await files.listExportArtifacts(), isEmpty);
      expect(await missing.exists(), isFalse);
    });
  });
}

StartupSweep _buildDeterministicFixture() {
  final StoredMeta document = _meta(id: _id(1));
  final StoredMeta template = _meta(id: _id(2), kind: StoreKind.template);
  return StartupSweep(
    store: _FakeStore(
      documents: <StoredMeta>[document],
      templates: <StoredMeta>[template],
      stamps: <String, RecoveryStamp>{
        document.id: _healthyStamp(),
        template.id: _healthyStamp(),
      },
    ),
    clock: _FixedClock(_now),
    files: _FakeFileSystem(
      temporaryEntries: <StartupSweepEntry>[
        _entry('${_id(10)}.part', const Duration(hours: 30)),
        _entry('${_id(11)}.head', const Duration(hours: 1)),
        _entry('scratch.tmp', Duration.zero),
      ],
      exportArtifacts: <StartupSweepEntry>[
        _entry('preview.pdf', const Duration(hours: 30)),
        _entry('active.pdf', Duration.zero),
      ],
    ),
  );
}

final class _FixedClock implements ClockPort {
  _FixedClock(this._nowUtc);

  final DateTime _nowUtc;
  int reads = 0;

  @override
  DateTime nowUtc() {
    reads++;
    return _nowUtc;
  }

  @override
  CapabilityDescriptor get descriptor => _clockDescriptor;

  static final CapabilityDescriptor _clockDescriptor = CapabilityDescriptor(
    kind: CapabilityKind.clock,
    adapterId: 'test.fake.clock.v1',
    version: '1',
    isSimulated: true,
    evidence: CapabilityEvidence.simulated(
      adapterId: 'test.fake.clock.v1',
      simulatedReason: 'test.fake-adapter',
    ),
    supportedFeatures: const <String>['fixed'],
  );
}

final class _FakeStore implements SecureStorePort {
  _FakeStore({
    List<String>? trace,
    List<StoredMeta>? documents,
    List<StoredMeta>? templates,
    Map<String, RecoveryStamp>? stamps,
    Map<StoreKind, Object>? listErrors,
    Map<String, Object>? stampErrors,
  }) : trace = trace ?? <String>[],
       documents = List<StoredMeta>.of(documents ?? const <StoredMeta>[]),
       templates = List<StoredMeta>.of(templates ?? const <StoredMeta>[]),
       stamps = Map<String, RecoveryStamp>.of(
         stamps ?? const <String, RecoveryStamp>{},
       ),
       listErrors = Map<StoreKind, Object>.of(
         listErrors ?? const <StoreKind, Object>{},
       ),
       stampErrors = Map<String, Object>.of(
         stampErrors ?? const <String, Object>{},
       );

  final List<String> trace;
  final List<StoredMeta> documents;
  final List<StoredMeta> templates;
  final Map<String, RecoveryStamp> stamps;
  final Map<StoreKind, Object> listErrors;
  final Map<String, Object> stampErrors;
  final List<String> calls = <String>[];
  final List<String> deletedIds = <String>[];
  int deleteCalls = 0;

  @override
  Future<List<StoredMeta>> list(StoreKind kind) async {
    _record('list:${kind.name}');
    final Object? error = listErrors[kind];
    if (error != null) {
      throw error;
    }
    return List<StoredMeta>.unmodifiable(
      kind == StoreKind.document ? documents : templates,
    );
  }

  @override
  Future<RecoveryStamp> recoveryStamp(String id, StoreKind kind) async {
    _record('stamp:$id');
    final Object? error = stampErrors[id];
    if (error != null) {
      throw error;
    }
    final RecoveryStamp? configured = stamps[id];
    if (configured != null) {
      return configured;
    }
    return RecoveryStamp(
      verifiedRevisionId: _meta(id: id, kind: kind).latestRevisionId,
      committedAt: _now.subtract(const Duration(minutes: 1)),
      headCorrupt: false,
      fellBackToOlderRevision: false,
    );
  }

  @override
  Future<void> delete(
    StoreKind kind,
    String id,
    DeleteConfirmation confirmation,
  ) async {
    deleteCalls++;
    deletedIds.add(id);
    final List<StoredMeta> entries = kind == StoreKind.document
        ? documents
        : templates;
    entries.removeWhere((StoredMeta value) => value.id == id);
  }

  @override
  CapabilityDescriptor get descriptor => _storeDescriptor;

  void _record(String event) {
    calls.add(event);
    trace.add(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('not used by StartupSweep');
  }

  static final CapabilityDescriptor _storeDescriptor = CapabilityDescriptor(
    kind: CapabilityKind.secureStore,
    adapterId: 'test.fake.store.v1',
    version: '1',
    isSimulated: true,
    evidence: CapabilityEvidence.simulated(
      adapterId: 'test.fake.store.v1',
      simulatedReason: 'test.fake-adapter',
    ),
    supportedFeatures: const <String>['startup-sweep-test'],
  );
}

final class _FakeFileSystem implements StartupSweepFileSystem {
  _FakeFileSystem({
    List<String>? trace,
    List<StartupSweepEntry>? temporaryEntries,
    List<StartupSweepEntry>? exportArtifacts,
  }) : trace = trace ?? <String>[],
       temporaryEntries = List<StartupSweepEntry>.of(
         temporaryEntries ?? const <StartupSweepEntry>[],
       ),
       exportArtifacts = List<StartupSweepEntry>.of(
         exportArtifacts ?? const <StartupSweepEntry>[],
       );

  final List<String> trace;
  final List<StartupSweepEntry> temporaryEntries;
  final List<StartupSweepEntry> exportArtifacts;
  final List<String> events = <String>[];
  final List<String> deletedTemporary = <String>[];
  final List<String> deletedExports = <String>[];
  final Map<String, Object> deleteTemporaryErrors = <String, Object>{};
  final Map<String, Object> deleteExportErrors = <String, Object>{};
  Object? listTemporaryError;
  Object? listExportError;

  @override
  Future<List<StartupSweepEntry>> listTemporaryEntries() async {
    _record('temp.list');
    final Object? error = listTemporaryError;
    if (error != null) {
      throw error;
    }
    return List<StartupSweepEntry>.unmodifiable(temporaryEntries);
  }

  @override
  Future<List<StartupSweepEntry>> listExportArtifacts() async {
    _record('export.list');
    final Object? error = listExportError;
    if (error != null) {
      throw error;
    }
    return List<StartupSweepEntry>.unmodifiable(exportArtifacts);
  }

  @override
  Future<void> deleteTemporaryEntry(StartupSweepEntry entry) async {
    _record('temp.delete:${entry.name}');
    final Object? error = deleteTemporaryErrors[entry.name];
    if (error != null) {
      throw error;
    }
    deletedTemporary.add(entry.name);
    temporaryEntries.removeWhere(
      (StartupSweepEntry value) => value.name == entry.name,
    );
  }

  @override
  Future<void> deleteExportArtifact(StartupSweepEntry entry) async {
    _record('export.delete:${entry.name}');
    final Object? error = deleteExportErrors[entry.name];
    if (error != null) {
      throw error;
    }
    deletedExports.add(entry.name);
    exportArtifacts.removeWhere(
      (StartupSweepEntry value) => value.name == entry.name,
    );
  }

  void _record(String event) {
    events.add(event);
    trace.add(event);
  }
}
