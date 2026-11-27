// T092 force-stop recovery suite for the debounced autosave (SC-009/SC-020).
//
// Run only on an exclusively allocated Android emulator:
//   flutter test integration_test/android_autosave_recovery_test.dart \
//     -d emulator-5554
//
// The suite drives the production `AutosaveCoordinator` (T089) against the
// real Dart -> MethodChannel -> native EncryptedStore path (`AndroidStoreClient`,
// T027) with synthetic bytes and a random document identity. It cleans up its
// own aggregate; it never reads or deletes another document.
//
// Honest scope note: an integration test runs inside the app process, so a
// literal `adb shell am force-stop` of the process under test cannot be
// observed from within the same process. The suite models forced termination
// at the only seam where it is observable — the coordinator is abandoned
// (disposed) and all recovery reads go through fresh store read-backs, which
// is exactly what a restarted process performs (SC-009). The 2 s coalescing
// window and the bounded-loss envelope (SC-020) are exercised with the real
// debounce timer and real store commits.
//
// Evidence class: EMULATOR.

library;

import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:feldexa_application/src/persistence/autosave.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

final class _WallClock implements ClockPort {
  static final CapabilityDescriptor _descriptor = CapabilityDescriptor(
    kind: CapabilityKind.clock,
    adapterId: 'test.clock.v1',
    version: '1',
    isSimulated: true,
    evidence: CapabilityEvidence(
      evidenceClass: EvidenceClass.simulated,
      adapterId: 'test.clock.v1',
    ),
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

final class _FakeLifecycle implements LifecyclePort {
  final StreamController<AppLifecycleSignal> _controller =
      StreamController<AppLifecycleSignal>.broadcast();

  static final CapabilityDescriptor _descriptor = CapabilityDescriptor(
    kind: CapabilityKind.lifecycle,
    adapterId: 'test.lifecycle.v1',
    version: '1',
    isSimulated: true,
    evidence: CapabilityEvidence(
      evidenceClass: EvidenceClass.simulated,
      adapterId: 'test.lifecycle.v1',
    ),
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  @override
  Stream<AppLifecycleSignal> get signals => _controller.stream;

  void emit(AppLifecycleSignal signal) {
    _controller.add(signal);
  }

  Future<void> close() => _controller.close();
}

/// Runs [body] with real async support and asserts it yields a value.
Future<T> _run<T>(WidgetTester tester, Future<T> Function() body) async {
  final T? value = await tester.runAsync(body);
  return value as T;
}

RevisionContent _plainContent() => RevisionContent(
  pages: <Page>[
    Page(
      index: 0,
      geometry: PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842)),
    ),
  ],
  fieldOrder: const <String>[],
);

RevisionContent _markedContent(double marker) => RevisionContent(
  pages: _plainContent().pages,
  fieldOrder: const <String>[],
  unknownFields: <String, Object?>{'t092Marker': marker},
);

double? _markerOf(LoadedDocument loaded) {
  final Object? value = loaded.content.unknownFields['t092Marker'];
  return value is num ? value.toDouble() : null;
}

/// Stages the synthetic source and creates the aggregate with a plain initial
/// revision. Returns the created metadata.
Future<StoredMeta> _seed(AndroidStoreClient store, String title) async {
  final AndroidIdClient ids = AndroidIdClient();
  final String documentId = ids.newId();
  final String sourceId = ids.newId();
  final Uint8List source = Uint8List.fromList(
    const <int>[37, 80, 68, 70, 45, 49, 46, 55, 10], // %PDF-1.7\n
  );
  final String sourceSha = crypto.sha256.convert(source).toString();
  final RevisionContent initial = _plainContent();
  await store.stageSource(
    documentId: documentId,
    sourceId: sourceId,
    bytes: source,
    sha256: sourceSha,
  );
  return store.createDocument(
    CreateDocumentRequest(
      documentId: documentId,
      title: title,
      source: SourceFileRef(
        id: sourceId,
        sha256: sourceSha,
        sizeBytes: source.length,
        pageCount: 1,
        importedAt: DateTime.now().toUtc(),
      ),
      initialRevision: Revision(
        id: ids.newId(),
        documentId: documentId,
        kind: RevisionKind.explicit,
        createdAt: DateTime.now().toUtc(),
        plaintextSha256: crypto.sha256
            .convert(canonicalJsonBytes(initial.toJson()))
            .toString(),
        content: initial,
      ),
    ),
  );
}

Future<void> _cleanup(AndroidStoreClient store, StoredMeta meta) async {
  try {
    await store.delete(
      StoreKind.document,
      meta.id,
      DeleteConfirmation(title: meta.title, acknowledged: true),
    );
  } catch (_) {
    // Best-effort cleanup; the assertions above already recorded results.
  }
}

AutosaveCoordinator _coordinator(
  AndroidStoreClient store,
  _FakeLifecycle lifecycle,
  StoredMeta meta,
  RevisionContent Function() content,
) {
  return AutosaveCoordinator(
    store: store,
    clock: _WallClock(),
    lifecycle: lifecycle,
    documentId: meta.id,
    content: content,
    initialHead: meta.latestRevisionId,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'an edit older than the 2 s window is durable across a forced stop and recovers',
    (WidgetTester tester) async {
      final AndroidStoreClient store = AndroidStoreClient();
      final StoredMeta meta = await _run(
        tester,
        () => _seed(store, 'T092 Force-Stop'),
      );
      try {
        final _FakeLifecycle lifecycle = _FakeLifecycle();
        RevisionContent snapshot = _plainContent();
        final AutosaveCoordinator coordinator = _coordinator(
          store,
          lifecycle,
          meta,
          () => snapshot,
        );

        // An edit committed well outside the final 2 s window: the debounce
        // window elapses fully, so the coordinator must reach a verified,
        // durable revision before the forced stop.
        snapshot = _markedContent(2);
        coordinator.markDirty();
        await _run(
          tester,
          () => Future<void>.delayed(const Duration(seconds: 3)),
        );
        expect(coordinator.hasPendingChanges, isFalse);
        expect(coordinator.lastDurableRevisionId, isNotNull);
        expect(coordinator.lastDurableRevisionId, isNot(meta.latestRevisionId));

        // Forced-stop surrogate: the process state is abandoned; recovery in
        // a fresh process reads only from the store.
        await coordinator.dispose();
        await lifecycle.close();

        final LoadedDocument recovered = await _run(
          tester,
          () => store.loadDocument(meta.id),
        );
        expect(
          recovered.meta.latestRevisionId,
          coordinator.lastDurableRevisionId,
        );
        expect(recovered.meta.readable, isTrue);
        expect(_markerOf(recovered), 2);
      } finally {
        await _run(tester, () => _cleanup(store, meta));
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'edits inside one 2 s window coalesce into exactly one revision',
    (WidgetTester tester) async {
      final AndroidStoreClient store = AndroidStoreClient();
      final StoredMeta meta = await _run(
        tester,
        () => _seed(store, 'T092 Coalescing'),
      );
      try {
        final _FakeLifecycle lifecycle = _FakeLifecycle();
        RevisionContent snapshot = _plainContent();
        final AutosaveCoordinator coordinator = _coordinator(
          store,
          lifecycle,
          meta,
          () => snapshot,
        );

        // Three rapid edits inside a single window: one coalesced revision
        // carrying the latest snapshot must be the only visible outcome.
        snapshot = _markedContent(3);
        coordinator.markDirty();
        snapshot = _markedContent(4);
        coordinator.markDirty();
        snapshot = _markedContent(5);
        coordinator.markDirty();
        await _run(
          tester,
          () => Future<void>.delayed(const Duration(seconds: 3)),
        );
        final String? headAfterWindow = coordinator.lastDurableRevisionId;
        expect(headAfterWindow, isNotNull);
        expect(headAfterWindow, isNot(meta.latestRevisionId));

        // No further writes may appear once the window has settled.
        await _run(
          tester,
          () => Future<void>.delayed(const Duration(seconds: 3)),
        );
        expect(coordinator.lastDurableRevisionId, headAfterWindow);

        final LoadedDocument recovered = await _run(
          tester,
          () => store.loadDocument(meta.id),
        );
        expect(recovered.meta.latestRevisionId, headAfterWindow);
        expect(_markerOf(recovered), 5, reason: 'the latest snapshot wins');

        // A lifecycle flush commits even before the debounce elapses.
        snapshot = _markedContent(6);
        coordinator.markDirty();
        lifecycle.emit(AppLifecycleSignal.paused);
        await _run(
          tester,
          () => Future<void>.delayed(const Duration(seconds: 2)),
        );
        final LoadedDocument flushed = await _run(
          tester,
          () => store.loadDocument(meta.id),
        );
        expect(_markerOf(flushed), 6);

        await coordinator.dispose();
        await lifecycle.close();
      } finally {
        await _run(tester, () => _cleanup(store, meta));
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'an edit inside the final 2 s of a forced stop is not reported durable (SC-020 bound)',
    (WidgetTester tester) async {
      final AndroidStoreClient store = AndroidStoreClient();
      final StoredMeta meta = await _run(
        tester,
        () => _seed(store, 'T092 Bound'),
      );
      try {
        final _FakeLifecycle lifecycle = _FakeLifecycle();
        RevisionContent snapshot = _plainContent();
        final AutosaveCoordinator coordinator = _coordinator(
          store,
          lifecycle,
          meta,
          () => snapshot,
        );

        // The termination happens while the debounce timer is still running:
        // the edit is not durable, and the coordinator must not report it as
        // such (at most the edits committed in the final 2 s are lost).
        snapshot = _markedContent(7);
        coordinator.markDirty();
        expect(coordinator.hasPendingChanges, isTrue);
        await coordinator.dispose();
        await lifecycle.close();

        final LoadedDocument recovered = await _run(
          tester,
          () => store.loadDocument(meta.id),
        );
        expect(recovered.meta.latestRevisionId, meta.latestRevisionId);
        expect(
          _markerOf(recovered),
          isNull,
          reason:
              'the newest edit stayed uncommitted and was never reported '
              'as durable',
        );

        // A recovered coordinator resumes cleanly from the durable head.
        final AutosaveCoordinator resumed = AutosaveCoordinator(
          store: store,
          clock: _WallClock(),
          lifecycle: _FakeLifecycle(),
          documentId: meta.id,
          content: () => snapshot,
          initialHead: recovered.meta.latestRevisionId,
        );
        expect(resumed.status, DurabilityStatus.clean);
        expect(resumed.hasPendingChanges, isFalse);
        await resumed.dispose();
      } finally {
        await _run(tester, () => _cleanup(store, meta));
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
