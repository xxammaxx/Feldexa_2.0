// T090 verified document-save use case tests.
//
// These are host-VM tests (evidence class NONE). They pin
// `packages/feldexa_application/lib/src/persistence/save_document.dart`
// against FR-043/FR-047/FR-048 and the FR-106 pattern:
//   * exactly one `SaveRevisionRequest` carrying the caller's ids, expected
//     head, content identity, and kind;
//   * success only for readable metadata with a non-null and new head;
//   * typed `SAVE-*` failures pass through unchanged while malformed metadata
//     and unexpected throws fail closed as `SAVE-003`;
//   * invalid inputs throw `ArgumentError` before any port call;
//   * no failure path exposes metadata or exception detail.
//
// The tests use an in-memory fake store, never a clock, delay, device,
// emulator, or real storage.

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:feldexa_application/src/persistence/save_document.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';

const String _documentId = '00000000-0000-4000-8000-000000000100';
const String _otherDocumentId = '00000000-0000-4000-8000-000000000101';
const String _initialHead = '00000000-0000-4000-8000-000000000200';
const String _newHead = '00000000-0000-4000-8000-000000000201';

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

StoredMeta _meta({
  String id = _documentId,
  String? latestRevisionId = _newHead,
  bool readable = true,
}) {
  return StoredMeta(
    id: id,
    kind: StoreKind.document,
    title: 'Test document',
    createdAt: _createdAt,
    updatedAt: _createdAt,
    latestRevisionId: latestRevisionId,
    readable: readable,
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

final class _FakeStore implements SecureStorePort {
  final List<SaveRevisionRequest> requests = <SaveRevisionRequest>[];

  /// Returned on a successful call; a valid new-head meta when null.
  StoredMeta? response;

  /// Thrown instead of returning when set.
  FeldexaException? typedFailure;

  /// Thrown instead of returning when set and [typedFailure] is null.
  Object? thrownObject;

  @override
  CapabilityDescriptor get descriptor => _storeDescriptor;

  @override
  Future<StoredMeta> saveRevision(SaveRevisionRequest request) async {
    requests.add(request);
    final Object? thrown = typedFailure ?? thrownObject;
    if (thrown != null) {
      throw thrown;
    }
    return response ?? _meta();
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

Future<SaveDocumentResult> _run(
  _FakeStore store, {
  String documentId = _documentId,
  String? expectedHead = _initialHead,
  RevisionContent? content,
  RevisionKind kind = RevisionKind.autosave,
}) {
  return saveDocument(
    store: store,
    documentId: documentId,
    expectedHead: expectedHead,
    content: content ?? _content(),
    kind: kind,
  );
}

void _expectFailure(
  SaveDocumentResult result,
  String expectedCode,
  _FakeStore store,
) {
  expect(store.requests, hasLength(1));
  expect(result.success, isFalse);
  expect(result.isSuccess, isFalse);
  expect(result.meta, isNull);
  expect(result.errorCode, expectedCode);
}

void main() {
  test(
    'saves once with the exact request and returns verified metadata',
    () async {
      final _FakeStore store = _FakeStore();
      final RevisionContent content = _content();
      final StoredMeta meta = _meta(latestRevisionId: _newHead);
      store.response = meta;

      final SaveDocumentResult result = await saveDocument(
        store: store,
        documentId: _documentId,
        expectedHead: _initialHead,
        content: content,
        kind: RevisionKind.explicit,
      );

      expect(store.requests, hasLength(1));
      final SaveRevisionRequest request = store.requests.single;
      expect(request.documentId, _documentId);
      expect(request.expectedHead, _initialHead);
      expect(identical(request.content, content), isTrue);
      expect(request.kind, RevisionKind.explicit);

      expect(result.success, isTrue);
      expect(result.isSuccess, isTrue);
      expect(identical(result.meta, meta), isTrue);
      expect(result.errorCode, isNull);
      expect(result.meta!.latestRevisionId, _newHead);
    },
  );

  test('allows an initial save with a null expected head', () async {
    final _FakeStore store = _FakeStore();
    final StoredMeta meta = _meta(latestRevisionId: _uuid(300));
    store.response = meta;

    final SaveDocumentResult result = await _run(store, expectedHead: null);

    expect(store.requests, hasLength(1));
    expect(store.requests.single.expectedHead, isNull);
    expect(result.success, isTrue);
    expect(result.isSuccess, isTrue);
    expect(result.errorCode, isNull);
    expect(identical(result.meta, meta), isTrue);
    expect(result.meta!.latestRevisionId, isNotNull);
    expect(result.meta!.latestRevisionId, _uuid(300));
  });

  test('passes through StorageFullException as SAVE-001', () async {
    final _FakeStore store = _FakeStore()
      ..typedFailure = StorageFullException();

    final SaveDocumentResult result = await _run(store);

    _expectFailure(result, 'SAVE-001', store);
  });

  test('passes through KeyUnavailableException as SAVE-002', () async {
    final _FakeStore store = _FakeStore()
      ..typedFailure = KeyUnavailableException();

    final SaveDocumentResult result = await _run(store);

    _expectFailure(result, 'SAVE-002', store);
  });

  test('passes through StorageWriteException as SAVE-003', () async {
    final _FakeStore store = _FakeStore()
      ..typedFailure = StorageWriteException();

    final SaveDocumentResult result = await _run(store);

    _expectFailure(result, 'SAVE-003', store);
  });

  test('rejects success metadata without a latest revision', () async {
    final _FakeStore store = _FakeStore()
      ..response = _meta(latestRevisionId: null);

    final SaveDocumentResult result = await _run(store);

    _expectFailure(result, 'SAVE-003', store);
  });

  test('rejects success metadata for a different document', () async {
    final _FakeStore store = _FakeStore()
      ..response = _meta(id: _otherDocumentId, latestRevisionId: _newHead);

    final SaveDocumentResult result = await _run(store);

    _expectFailure(result, 'SAVE-003', store);
  });

  test('rejects unreadable success metadata', () async {
    final _FakeStore store = _FakeStore()
      ..response = _meta(readable: false, latestRevisionId: _newHead);

    final SaveDocumentResult result = await _run(store);

    _expectFailure(result, 'SAVE-003', store);
  });

  test('rejects a verified head that did not change', () async {
    final _FakeStore store = _FakeStore()
      ..response = _meta(latestRevisionId: _initialHead);

    final SaveDocumentResult result = await _run(store);

    _expectFailure(result, 'SAVE-003', store);
  });

  test('fails closed on an unexpected error without leaking it', () async {
    const String marker = 'unexpected-marker-9f3c';
    final _FakeStore store = _FakeStore()..thrownObject = StateError(marker);

    final SaveDocumentResult result = await _run(store);

    _expectFailure(result, 'SAVE-003', store);
    expect(result.toString(), isNot(contains(marker)));
    expect(result.toString(), isNot(contains(_documentId)));
  });

  test('rejects an invalid document id before any save call', () async {
    final _FakeStore store = _FakeStore();

    await expectLater(
      _run(store, documentId: 'not-a-uuid'),
      throwsArgumentError,
    );

    expect(store.requests, isEmpty);
  });

  test('rejects an invalid expected head before any save call', () async {
    final _FakeStore store = _FakeStore();

    await expectLater(
      _run(store, expectedHead: 'not-a-uuid'),
      throwsArgumentError,
    );

    expect(store.requests, isEmpty);
  });

  test('no failure path reports optimistic success', () async {
    final List<Future<SaveDocumentResult>> saves = <Future<SaveDocumentResult>>[
      _run(_FakeStore()..typedFailure = StorageFullException()),
      _run(_FakeStore()..typedFailure = KeyUnavailableException()),
      _run(_FakeStore()..typedFailure = StorageWriteException()),
      _run(_FakeStore()..response = _meta(latestRevisionId: null)),
      _run(_FakeStore()..response = _meta(id: _otherDocumentId)),
      _run(_FakeStore()..response = _meta(readable: false)),
      _run(_FakeStore()..response = _meta(latestRevisionId: _initialHead)),
      _run(_FakeStore()..thrownObject = StateError('unexpected')),
    ];

    for (final SaveDocumentResult result in await Future.wait(saves)) {
      expect(result.success, isFalse);
      expect(result.isSuccess, isFalse);
      expect(result.meta, isNull);
      expect(result.errorCode, isNotNull);
    }
  });
}
