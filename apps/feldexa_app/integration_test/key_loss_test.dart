// T093 key-loss isolation suite and quick-start unlock assertion (FR-052,
// FR-050, FR-049; `quickstart.md` §8).
//
// Run only on an exclusively allocated Android emulator:
//   flutter test integration_test/key_loss_test.dart -d emulator-5554
//
// Two lanes, honestly separated:
//   * EMULATOR — the real Dart -> MethodChannel -> native EncryptedStore path
//     (`AndroidStoreClient`, T027). A saved document opens with no app
//     password and no mandatory biometric unlock: the load call performs no
//     unlock interaction at all and succeeds directly.
//   * SIMULATED — the deterministic `SimulatedBackend` key seams
//     (`simulateAggregateKeyLoss` -> SAVE-002,
//     `simulateGlobalKeyUnavailable` -> SAVE-008). Android offers no safe,
//     root-free seam to remove a real Keystore key from inside the app
//     process, so the isolation behavior is proven on the simulated lane and
//     reported as such (FR-088: it is not Android evidence).
//
// Both lanes clean up only their own synthetic aggregates.

library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const int _sourceByte = 37; // '%'

/// Runs [body] with real async support and asserts it yields a value.
Future<T> _run<T>(WidgetTester tester, Future<T> Function() body) async {
  final T? value = await tester.runAsync(body);
  return value as T;
}

Future<StoredMeta> _seedAndroid(AndroidStoreClient store, String title) async {
  final AndroidIdClient ids = AndroidIdClient();
  final String documentId = ids.newId();
  final String sourceId = ids.newId();
  final Uint8List source = Uint8List.fromList(const <int>[
    _sourceByte,
    80,
    68,
    70,
    45,
    49,
    46,
    55,
    10,
  ]);
  final String sourceSha = crypto.sha256.convert(source).toString();
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
            .convert(canonicalJsonBytes(_content().toJson()))
            .toString(),
        content: _content(),
      ),
    ),
  );
}

RevisionContent _content() => RevisionContent(
  pages: <Page>[
    Page(
      index: 0,
      geometry: PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842)),
    ),
  ],
  fieldOrder: const <String>[],
);

Future<void> _cleanupAndroid(AndroidStoreClient store, StoredMeta meta) async {
  try {
    await store.delete(
      StoreKind.document,
      meta.id,
      DeleteConfirmation(title: meta.title, acknowledged: true),
    );
  } catch (_) {
    // Best-effort cleanup.
  }
}

Future<StoredMeta> _seedSimulated(
  SimulatedSecureStoreAdapter store,
  SimulatedBackend backend,
  String title,
) async {
  final Uint8List bytes = Uint8List.fromList(const <int>[
    _sourceByte,
    80,
    68,
    70,
    45,
    49,
    46,
    55,
    10,
  ]);
  final SimulatedFixture fixture = SimulatedFixture(
    id: 'sf-t093',
    role: SimulatedFixtureRole.editor,
    status: SimulatedFixtureStatus.valid,
    title: title,
    displayName: 't093.pdf',
    bytes: bytes,
    sha256: crypto.sha256.convert(bytes).toString(),
    sizeBytes: bytes.length,
    pages: <SimulatedFixturePage>[
      const SimulatedFixturePage(
        index: 0,
        widthPt: 595,
        heightPt: 842,
        rotation: 0,
      ),
    ],
    expectedOcr: const <SimulatedOcrPage>[],
    expectedErrorCode: null,
  );
  backend.stageSource(sourceId: backend.context.newId(), fixture: fixture);
  final SimulatedStagedSource staged = backend.stagedSources.values.last;
  final RevisionContent content = _content();
  final String documentId = backend.context.newId();
  return store.createDocument(
    CreateDocumentRequest(
      documentId: documentId,
      title: title,
      source: SourceFileRef(
        id: staged.sourceId,
        sha256: staged.sha256,
        sizeBytes: staged.bytes.length,
        pageCount: staged.pageCount,
        importedAt: backend.context.nowUtc(),
      ),
      initialRevision: Revision(
        id: backend.context.newId(),
        documentId: documentId,
        kind: RevisionKind.explicit,
        createdAt: backend.context.nowUtc(),
        plaintextSha256: crypto.sha256
            .convert(canonicalJsonBytes(content.toJson()))
            .toString(),
        content: content,
      ),
    ),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a saved document opens without an app password and without biometric unlock',
    (WidgetTester tester) async {
      final AndroidStoreClient store = AndroidStoreClient();
      final StoredMeta meta = await _run(
        tester,
        () => _seedAndroid(store, 'T093 Quickstart'),
      );
      try {
        // The direct load performs no unlock interaction: no password prompt,
        // no biometric gate — the platform Keystore unlock (if any) is part of
        // the device itself, never a Feldexa app gate (FR-049/FR-050).
        final LoadedDocument loaded = await _run(
          tester,
          () => store.loadDocument(meta.id),
        );
        expect(loaded.meta.id, meta.id);
        expect(loaded.meta.readable, isTrue);
        expect(loaded.content.pageCount, 1);
        expect(loaded.sourceBytes.length, greaterThan(0));

        // The same holds after a new revision: reopen stays unlock-free.
        final StoredMeta saved = await _run(
          tester,
          () => store.saveRevision(
            SaveRevisionRequest(
              documentId: meta.id,
              expectedHead: meta.latestRevisionId,
              content: _content(),
              kind: RevisionKind.autosave,
            ),
          ),
        );
        final LoadedDocument reopened = await _run(
          tester,
          () => store.loadDocument(meta.id),
        );
        expect(reopened.meta.latestRevisionId, saved.latestRevisionId);
        expect(reopened.meta.readable, isTrue);
      } finally {
        await _run(tester, () => _cleanupAndroid(store, meta));
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('SIMULATED: key loss is isolated to one aggregate and other documents stay readable', () async {
    final SimulatedBackend backend = SimulatedBackend(
      context: SimulatedAdapterContext(),
      maxTotalBytes: 4 << 20,
    );
    final SimulatedSecureStoreAdapter store = SimulatedSecureStoreAdapter(
      backend: backend,
    );
    final StoredMeta lost = await _seedSimulated(
      store,
      backend,
      'T093 verloren',
    );
    final StoredMeta intact = await _seedSimulated(
      store,
      backend,
      'T093 intakt',
    );

    store.simulateAggregateKeyLoss(lost.id);

    // The affected aggregate throws the exact aggregate-scoped code.
    await expectLater(
      store.loadDocument(lost.id),
      throwsA(
        isA<KeyUnavailableException>().having(
          (KeyUnavailableException e) => e.code,
          'code',
          'SAVE-002',
        ),
      ),
    );

    // Isolation: every other aggregate keeps its own key and loads normally.
    final LoadedDocument other = await store.loadDocument(intact.id);
    expect(other.meta.id, intact.id);
    expect(other.meta.readable, isTrue);

    // Nothing is deleted to "handle" the loss (FR-052, FR-076).
    final List<StoredMeta> listed = await store.list(StoreKind.document);
    expect(
      listed.map((StoredMeta meta) => meta.id),
      containsAll(<String>[lost.id, intact.id]),
    );
    expect(backend.document(lost.id), isNotNull);

    // After the key returns, the aggregate recovers with unchanged content.
    store.restoreAggregateKey(lost.id);
    final LoadedDocument recovered = await store.loadDocument(lost.id);
    expect(recovered.meta.readable, isTrue);
    expect(recovered.meta.latestRevisionId, lost.latestRevisionId);
  });

  test('SIMULATED: a global key-provider outage maps to SAVE-008 and preserves ciphertext', () async {
    final SimulatedBackend backend = SimulatedBackend(
      context: SimulatedAdapterContext(),
      maxTotalBytes: 4 << 20,
    );
    final SimulatedSecureStoreAdapter store = SimulatedSecureStoreAdapter(
      backend: backend,
    );
    final StoredMeta meta = await _seedSimulated(store, backend, 'T093 global');

    store.simulateGlobalKeyUnavailable();
    expect(store.isGlobalKeyUnavailable, isTrue);

    await expectLater(
      store.loadDocument(meta.id),
      throwsA(
        isA<KeystoreUnavailableException>().having(
          (KeystoreUnavailableException e) => e.code,
          'code',
          'SAVE-008',
        ),
      ),
    );

    // The aggregate record and its revisions are untouched.
    final SimulatedDocumentRecord? record = backend.document(meta.id);
    expect(record, isNotNull);
    expect(record!.head, meta.latestRevisionId);

    store.restoreGlobalKey();
    final LoadedDocument recovered = await store.loadDocument(meta.id);
    expect(recovered.meta.readable, isTrue);
  });
}
