// ignore_for_file: implementation_imports

// T089 debounced autosave coordinator tests.
//
// These are host-VM tests (evidence class NONE). They pin
// `packages/feldexa_application/lib/src/persistence/autosave.dart` against
// research D-08/D-09, FR-045/FR-046/FR-047, SC-020, and CHK001/CR-1:
//   * the debounce is exactly 2 s after the latest committed change and a mark
//     restarts it;
//   * foreground signals and explicit saves flush immediately;
//   * at most one verified save is in flight and newer changes coalesce into
//     one follow-up revision with the latest snapshot and head;
//   * failures preserve the previous durable head and stop retrying until a
//     later mark or flush;
//   * disposed coordinators own no timer, subscription, or new write.
//
// The tests use Flutter's fake async clock (`tester.pump`), never a real delay,
// and only content-free identifiers.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:feldexa_application/src/persistence/autosave.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';

const String _documentId = '00000000-0000-4000-8000-000000000100';
const String _initialHead = '00000000-0000-4000-8000-000000000200';
const Duration _debounce = Duration(seconds: 2);
final DateTime _createdAt = DateTime.utc(2026, 11, 20, 12);

String _uuid(int value) {
  return '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
}

RevisionContent _content() {
  return RevisionContent(
    pages: <Page>[
      Page(
        index: 0,
        geometry: PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 100, 100)),
      ),
    ],
    fieldOrder: const <String>[],
  );
}

final CapabilityDescriptor _storeDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.secureStore,
  adapterId: 'test.store.v1',
  version: '1',
  isSimulated: false,
  evidence: CapabilityEvidence(
    evidenceClass: EvidenceClass.none,
    adapterId: 'test.store.v1',
  ),
);

final CapabilityDescriptor _clockDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.clock,
  adapterId: 'test.clock.v1',
  version: '1',
  isSimulated: false,
  evidence: CapabilityEvidence(
    evidenceClass: EvidenceClass.none,
    adapterId: 'test.clock.v1',
  ),
);

final CapabilityDescriptor _lifecycleDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.lifecycle,
  adapterId: 'test.lifecycle.v1',
  version: '1',
  isSimulated: false,
  evidence: CapabilityEvidence(
    evidenceClass: EvidenceClass.none,
    adapterId: 'test.lifecycle.v1',
  ),
);

final class _FakeStore implements SecureStorePort {
  final List<SaveRevisionRequest> requests = <SaveRevisionRequest>[];
  final List<StoredMeta> responses = <StoredMeta>[];

  /// When set, a save waits for the caller to supply its [StoredMeta].
  Completer<StoredMeta>? gate;

  /// When set, the next non-gated save throws this failure.
  FeldexaException? failure;

  int _nextRevision = 1;

  @override
  CapabilityDescriptor get descriptor => _storeDescriptor;

  @override
  Future<StoredMeta> saveRevision(SaveRevisionRequest request) async {
    requests.add(request);
    final Completer<StoredMeta>? pending = gate;
    if (pending != null) {
      final StoredMeta stored = await pending.future;
      responses.add(stored);
      return stored;
    }
    final FeldexaException? error = failure;
    if (error != null) {
      throw error;
    }
    final StoredMeta stored = newMeta();
    responses.add(stored);
    return stored;
  }

  /// Builds one valid result with a fresh verified revision id.
  StoredMeta newMeta() {
    final StoredMeta meta = StoredMeta(
      id: _documentId,
      kind: StoreKind.document,
      title: 'Test document',
      createdAt: _createdAt,
      updatedAt: _createdAt,
      latestRevisionId: _uuid(1000 + _nextRevision),
    );
    _nextRevision++;
    return meta;
  }

  @override
  Future<StoreStatus> status() => throw UnsupportedError('not used');

  @override
  Future<StoredMeta> createDocument(CreateDocumentRequest request) =>
      throw UnsupportedError('not used');

  @override
  Future<LoadedDocument> loadDocument(String documentId) =>
      throw UnsupportedError('not used');

  @override
  Future<Uint8List> readSignature(String documentId, String assetId) =>
      throw UnsupportedError('not used');

  @override
  Future<void> writeSignature(WriteSignatureRequest request) =>
      throw UnsupportedError('not used');

  @override
  Future<List<StoredMeta>> list(StoreKind kind) =>
      throw UnsupportedError('not used');

  @override
  Future<void> delete(
    StoreKind kind,
    String id,
    DeleteConfirmation confirmation,
  ) => throw UnsupportedError('not used');

  @override
  Future<StoredMeta> createTemplate(CreateTemplateRequest request) =>
      throw UnsupportedError('not used');

  @override
  Future<StoredMeta> saveTemplateVersion(SaveTemplateVersionRequest request) =>
      throw UnsupportedError('not used');

  @override
  Future<LoadedTemplate> loadTemplate(String templateId, {String? versionId}) =>
      throw UnsupportedError('not used');

  @override
  Future<RecoveryStamp> recoveryStamp(String id, StoreKind kind) =>
      throw UnsupportedError('not used');
}

final class _FixedClock implements ClockPort {
  _FixedClock(this.now);

  DateTime now;

  @override
  DateTime nowUtc() => now;

  @override
  CapabilityDescriptor get descriptor => _clockDescriptor;
}

final class _FakeLifecycle implements LifecyclePort {
  final StreamController<AppLifecycleSignal> _controller =
      StreamController<AppLifecycleSignal>.broadcast();
  bool _closed = false;

  @override
  Stream<AppLifecycleSignal> get signals => _controller.stream;

  @override
  CapabilityDescriptor get descriptor => _lifecycleDescriptor;

  void emit(AppLifecycleSignal signal) => _controller.add(signal);

  Future<void> close() {
    if (_closed) {
      return Future<void>.value();
    }
    _closed = true;
    return _controller.close();
  }
}

final class _Harness {
  _Harness({this.initialHead = _initialHead, Duration debounce = _debounce})
    : clock = _FixedClock(_createdAt),
      store = _FakeStore(),
      lifecycle = _FakeLifecycle() {
    coordinator = AutosaveCoordinator(
      store: store,
      clock: clock,
      lifecycle: lifecycle,
      documentId: _documentId,
      content: () {
        contentCalls++;
        return snapshot;
      },
      initialHead: initialHead,
      debounce: debounce,
    );
  }

  final String? initialHead;
  final _FixedClock clock;
  final _FakeStore store;
  final _FakeLifecycle lifecycle;
  late final AutosaveCoordinator coordinator;

  RevisionContent snapshot = _content();
  int contentCalls = 0;

  Future<void> dispose(WidgetTester tester) async {
    // `dispose` awaits the lifecycle subscription cancellation. Run it in the
    // real async zone so Flutter's fake clock is not advanced by the stream
    // cancellation future.
    await tester.runAsync(() => coordinator.dispose());
  }
}

void main() {
  testWidgets('pins the initial state for a missing and an existing head', (
    WidgetTester tester,
  ) async {
    final _Harness fresh = _Harness(initialHead: null);
    expect(fresh.coordinator.status, DurabilityStatus.unsaved);
    expect(fresh.coordinator.lastDurableRevisionId, isNull);
    expect(fresh.coordinator.lastDurableAt, isNull);
    expect(fresh.coordinator.hasPendingChanges, isFalse);
    expect(fresh.contentCalls, 0);

    fresh.coordinator.markDirty();
    final Future<bool> firstSave = fresh.coordinator.flush();
    await tester.pump();
    expect(await firstSave, isTrue);
    expect(fresh.store.requests.single.expectedHead, isNull);
    await fresh.dispose(tester);

    final _Harness existing = _Harness();
    expect(existing.coordinator.status, DurabilityStatus.clean);
    expect(existing.coordinator.lastDurableRevisionId, _initialHead);
    expect(existing.coordinator.lastDurableAt, isNull);
    expect(existing.coordinator.hasPendingChanges, isFalse);
    await existing.dispose(tester);
  });

  testWidgets('debounces a mark and saves exactly once at two seconds', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness();
    final RevisionContent expected = h.snapshot;

    h.coordinator.markDirty();
    expect(h.coordinator.status, DurabilityStatus.unsaved);
    expect(h.coordinator.hasPendingChanges, isTrue);

    await tester.pump(const Duration(milliseconds: 1999));
    expect(h.store.requests, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(h.store.requests, hasLength(1));
    final SaveRevisionRequest request = h.store.requests.single;
    expect(request.kind, RevisionKind.autosave);
    expect(request.expectedHead, _initialHead);
    expect(identical(request.content, expected), isTrue);
    expect(h.coordinator.status, isA<SavedDurabilityStatus>());
    expect(
      h.coordinator.lastDurableRevisionId,
      h.store.responses.single.latestRevisionId,
    );
    expect(h.coordinator.lastDurableAt, h.clock.nowUtc());
    expect(h.coordinator.hasPendingChanges, isFalse);

    await h.dispose(tester);
  });

  testWidgets('uses the production 2 s default when debounce is omitted', (
    WidgetTester tester,
  ) async {
    final _FakeStore store = _FakeStore();
    final AutosaveCoordinator coordinator = AutosaveCoordinator(
      store: store,
      clock: _FixedClock(_createdAt),
      lifecycle: _FakeLifecycle(),
      documentId: _documentId,
      content: _content,
      initialHead: _initialHead,
    );

    coordinator.markDirty();
    await tester.pump(const Duration(milliseconds: 1999));
    expect(store.requests, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(store.requests, hasLength(1));
    expect(store.requests.single.kind, RevisionKind.autosave);
    expect(coordinator.status, isA<SavedDurabilityStatus>());

    await tester.runAsync(() => coordinator.dispose());
  });

  testWidgets('restarts the debounce timer on every mark and saves once', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness();

    h.coordinator.markDirty();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(h.store.requests, isEmpty);

    h.coordinator.markDirty();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(h.store.requests, isEmpty);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(h.store.requests, hasLength(1));
    expect(h.store.requests.single.kind, RevisionKind.autosave);
    await h.dispose(tester);
  });

  testWidgets(
    'flush saves immediately, cancels the timer, and reports saving',
    (WidgetTester tester) async {
      final _Harness h = _Harness();
      final Completer<StoredMeta> gate = Completer<StoredMeta>();
      h.store.gate = gate;

      h.coordinator.markDirty();
      final Future<bool> flushed = h.coordinator.flush();

      expect(h.store.requests, hasLength(1));
      expect(h.store.requests.single.kind, RevisionKind.autosave);
      expect(h.coordinator.status, DurabilityStatus.saving);

      await tester.pump(const Duration(seconds: 2));
      expect(h.store.requests, hasLength(1));

      gate.complete(h.store.newMeta());
      h.store.gate = null;
      await tester.pump();

      expect(await flushed, isTrue);
      expect(h.coordinator.status, isA<SavedDurabilityStatus>());
      await h.dispose(tester);
    },
  );

  testWidgets(
    'explicit flush saves with no pending change; plain flush is a no-op',
    (WidgetTester tester) async {
      final _Harness h = _Harness();
      expect(h.coordinator.status, DurabilityStatus.clean);

      expect(await h.coordinator.flush(), isFalse);
      expect(h.store.requests, isEmpty);
      expect(h.coordinator.status, DurabilityStatus.clean);

      final Future<bool> explicit = h.coordinator.flush(explicit: true);
      await tester.pump();
      expect(await explicit, isTrue);
      expect(h.store.requests, hasLength(1));
      expect(h.store.requests.single.kind, RevisionKind.explicit);
      expect(h.store.requests.single.expectedHead, _initialHead);
      expect(h.coordinator.hasPendingChanges, isFalse);

      await h.dispose(tester);
    },
  );

  testWidgets('lifecycle pause, inactive, and detach flush; resume does not', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness();

    for (final AppLifecycleSignal signal in <AppLifecycleSignal>[
      AppLifecycleSignal.inactive,
      AppLifecycleSignal.paused,
      AppLifecycleSignal.detached,
    ]) {
      final int before = h.store.requests.length;
      h.coordinator.markDirty();
      h.lifecycle.emit(signal);
      await tester.pump();
      await tester.pump();

      expect(h.store.requests, hasLength(before + 1), reason: '$signal');
      expect(h.store.requests.last.kind, RevisionKind.autosave);
      expect(h.coordinator.hasPendingChanges, isFalse);
    }

    h.coordinator.markDirty();
    final int beforeResume = h.store.requests.length;
    h.lifecycle.emit(AppLifecycleSignal.resumed);
    await tester.pump();
    await tester.pump();

    expect(h.store.requests, hasLength(beforeResume));
    expect(h.coordinator.status, DurabilityStatus.unsaved);
    await h.dispose(tester);
  });

  testWidgets('inactive then paused with one pending change saves once', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness();
    final Completer<StoredMeta> gate = Completer<StoredMeta>();
    h.store.gate = gate;

    h.coordinator.markDirty();
    h.lifecycle.emit(AppLifecycleSignal.inactive);
    await tester.pump();
    expect(h.store.requests, hasLength(1));
    expect(h.coordinator.status, DurabilityStatus.saving);

    // The first save has not verified yet, so pending is still true. This
    // second lifecycle flush must join the active save, not queue an identical
    // follow-up revision.
    h.lifecycle.emit(AppLifecycleSignal.paused);
    await tester.pump();
    expect(h.store.requests, hasLength(1));

    gate.complete(h.store.newMeta());
    h.store.gate = null;
    await tester.pump();
    await tester.pump();

    expect(h.store.requests, hasLength(1));
    expect(h.coordinator.hasPendingChanges, isFalse);
    expect(h.coordinator.status, isA<SavedDurabilityStatus>());

    await h.dispose(tester);
  });

  testWidgets('changes during a save coalesce into one follow-up snapshot', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness();
    final Completer<StoredMeta> firstGate = Completer<StoredMeta>();
    h.store.gate = firstGate;

    h.coordinator.markDirty();
    final Future<bool> firstFlush = h.coordinator.flush();
    expect(h.store.requests, hasLength(1));

    final RevisionContent latest = _content();
    h.snapshot = latest;
    h.coordinator.markDirty();
    expect(h.coordinator.status, DurabilityStatus.saving);

    await tester.pump(const Duration(seconds: 1));
    h.coordinator.markDirty();
    await tester.pump(const Duration(seconds: 1));
    expect(h.store.requests, hasLength(1));

    await tester.pump(const Duration(seconds: 1));
    expect(h.store.requests, hasLength(1));
    expect(h.coordinator.status, DurabilityStatus.saving);

    firstGate.complete(h.store.newMeta());
    h.store.gate = null;
    await tester.pump();
    await tester.pump();

    expect(h.store.requests, hasLength(2));
    expect(h.store.requests[1].kind, RevisionKind.autosave);
    expect(
      h.store.requests[1].expectedHead,
      h.store.responses.first.latestRevisionId,
    );
    expect(identical(h.store.requests[1].content, latest), isTrue);
    expect(await firstFlush, isTrue);
    expect(h.coordinator.hasPendingChanges, isFalse);
    expect(h.coordinator.status, isA<SavedDurabilityStatus>());

    await h.dispose(tester);
  });

  testWidgets('explicit flush during a save upgrades the follow-up', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness();
    final Completer<StoredMeta> firstGate = Completer<StoredMeta>();
    final Completer<StoredMeta> followGate = Completer<StoredMeta>();
    h.store.gate = firstGate;

    h.coordinator.markDirty();
    final Future<bool> firstFlush = h.coordinator.flush();
    expect(h.store.requests, hasLength(1));

    // Queue an autosave follow-up while the first save is still held.
    h.coordinator.markDirty();
    await tester.pump(const Duration(seconds: 2));
    expect(h.store.requests, hasLength(1));

    h.store.gate = followGate;
    final Future<bool> explicitFlush = h.coordinator.flush(explicit: true);
    bool explicitDone = false;
    bool? explicitValue;
    unawaited(
      explicitFlush.then((bool value) {
        explicitDone = true;
        explicitValue = value;
      }),
    );
    await tester.pump();
    expect(explicitDone, isFalse);

    firstGate.complete(h.store.newMeta());
    await tester.pump();

    expect(h.store.requests, hasLength(2));
    expect(h.store.requests[1].kind, RevisionKind.explicit);
    expect(await firstFlush, isTrue);
    expect(explicitDone, isFalse);

    followGate.complete(h.store.newMeta());
    await tester.pump();

    expect(explicitDone, isTrue);
    expect(explicitValue, isTrue);
    expect(await explicitFlush, isTrue);
    expect(h.coordinator.hasPendingChanges, isFalse);
    expect(h.coordinator.status, isA<SavedDurabilityStatus>());

    await h.dispose(tester);
  });

  testWidgets(
    'a storage failure preserves the head until an explicit recovery',
    (WidgetTester tester) async {
      final _Harness h = _Harness();
      h.store.failure = StorageFullException();

      h.coordinator.markDirty();
      final Future<bool> failed = h.coordinator.flush();
      await tester.pump();
      expect(await failed, isFalse);

      expect(h.coordinator.status, DurabilityStatus.saveFailed('SAVE-001'));
      expect(h.coordinator.lastDurableRevisionId, _initialHead);
      expect(h.coordinator.lastDurableAt, isNull);
      expect(h.coordinator.hasPendingChanges, isTrue);
      expect(h.store.requests, hasLength(1));

      // No automatic retry until a later mark or flush.
      await tester.pump(const Duration(seconds: 5));
      expect(h.store.requests, hasLength(1));

      h.store.failure = null;
      final DateTime recoveredAt = DateTime.utc(2026, 11, 20, 12, 30);
      h.clock.now = recoveredAt;
      final Future<bool> recovered = h.coordinator.flush(explicit: true);
      await tester.pump();
      expect(await recovered, isTrue);

      expect(
        h.coordinator.status,
        DurabilityStatus.saved(lastDurableAt: recoveredAt),
      );
      expect(
        h.coordinator.lastDurableRevisionId,
        h.store.responses.single.latestRevisionId,
      );
      expect(h.coordinator.lastDurableAt, recoveredAt);
      expect(h.coordinator.hasPendingChanges, isFalse);
      expect(h.store.requests.last.kind, RevisionKind.explicit);

      await h.dispose(tester);
    },
  );

  testWidgets('a failed clean explicit save keeps no pending change', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness();
    h.store.failure = StorageFullException();

    final Future<bool> save = h.coordinator.flush(explicit: true);
    await tester.pump();
    expect(await save, isFalse);

    expect(h.coordinator.status, DurabilityStatus.saveFailed('SAVE-001'));
    expect(h.coordinator.lastDurableRevisionId, _initialHead);
    expect(h.coordinator.lastDurableAt, isNull);
    expect(h.coordinator.hasPendingChanges, isFalse);

    await h.dispose(tester);
  });

  testWidgets(
    'uses initialHead then the latest id and reads content at save time',
    (WidgetTester tester) async {
      final _Harness h = _Harness();
      expect(h.contentCalls, 0);

      h.coordinator.markDirty();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(h.contentCalls, 1);
      expect(h.store.requests[0].expectedHead, _initialHead);

      final String? firstHead = h.store.responses[0].latestRevisionId;
      final RevisionContent latest = _content();
      h.snapshot = latest;
      h.coordinator.markDirty();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(h.contentCalls, 2);
      expect(h.store.requests[1].expectedHead, firstHead);
      expect(identical(h.store.requests[1].content, latest), isTrue);
      expect(
        h.coordinator.lastDurableRevisionId,
        h.store.responses[1].latestRevisionId,
      );

      await h.dispose(tester);
    },
  );

  testWidgets('markDirty during an in-flight save keeps the saving status', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness();
    final Completer<StoredMeta> gate = Completer<StoredMeta>();
    h.store.gate = gate;

    h.coordinator.markDirty();
    final Future<bool> save = h.coordinator.flush();
    expect(h.coordinator.status, DurabilityStatus.saving);

    h.coordinator.markDirty();
    expect(h.coordinator.status, DurabilityStatus.saving);
    expect(h.coordinator.hasPendingChanges, isTrue);

    gate.complete(h.store.newMeta());
    h.store.gate = null;
    await tester.pump();

    expect(await save, isTrue);
    await h.dispose(tester);
  });

  testWidgets(
    'dispose cancels the timer and lifecycle and blocks later saves',
    (WidgetTester tester) async {
      final _Harness h = _Harness();
      h.coordinator.markDirty();
      await tester.runAsync(() => h.coordinator.dispose());

      await tester.pump(const Duration(seconds: 3));
      expect(h.store.requests, isEmpty);

      h.lifecycle.emit(AppLifecycleSignal.paused);
      await tester.pump();
      expect(h.store.requests, isEmpty);

      h.coordinator.markDirty();
      await tester.pump(const Duration(seconds: 3));
      expect(h.store.requests, isEmpty);
      expect(await h.coordinator.flush(), isFalse);
      expect(await h.coordinator.flush(explicit: true), isFalse);
      expect(h.store.requests, isEmpty);

      await h.dispose(tester);
    },
  );

  testWidgets(
    'dispose completes an outstanding flush false and starts no follow-up',
    (WidgetTester tester) async {
      final _Harness h = _Harness();
      final Completer<StoredMeta> gate = Completer<StoredMeta>();
      h.store.gate = gate;

      h.coordinator.markDirty();
      final Future<bool> save = h.coordinator.flush();
      expect(h.store.requests, hasLength(1));
      expect(h.coordinator.status, DurabilityStatus.saving);

      await tester.runAsync(() => h.coordinator.dispose());
      expect(await save, isFalse);

      h.coordinator.markDirty();
      gate.complete(h.store.newMeta());
      h.store.gate = null;
      await tester.pump();
      await tester.pump();

      expect(h.store.requests, hasLength(1));
      expect(await h.coordinator.flush(explicit: true), isFalse);
      expect(h.store.requests, hasLength(1));

      await h.dispose(tester);
    },
  );
}
