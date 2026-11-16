// T027 host-VM tests for the Android store thin client.
//
// These tests use mocked Flutter channels and are `NONE`-class evidence. They
// prove envelope validation, request shaping, typed failure mapping, and the
// "metadata only from a committed readable aggregate" rule. They do not prove
// Android runtime behavior; the instrumentation test does that.

import 'dart:async';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _documentId = '123e4567-e89b-42d3-a456-426614174000';
const String _sourceId = '123e4567-e89b-42d3-a456-426614174001';
const String _revisionId = '123e4567-e89b-42d3-a456-426614174002';
const String _assetId = '123e4567-e89b-42d3-a456-426614174003';
const String _sha =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late List<MethodCall> calls;
  late Object? Function(MethodCall call) handler;

  setUp(() {
    calls = <MethodCall>[];
    channel = const MethodChannel('de.feldexa/platform');
    handler = (MethodCall call) => _envelope(<String, Object?>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return handler(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'createDocument carries the approved identity and initial revision',
    () async {
      handler = (MethodCall call) {
        expect(call.method, 'store.createDocument');
        final Map<Object?, Object?> payload =
            call.arguments as Map<Object?, Object?>;
        expect(payload['schemaVersion'], 1);
        expect(payload['documentId'], _documentId);
        expect(payload['title'], 'Antrag');
        final Map<Object?, Object?> source =
            payload['source']! as Map<Object?, Object?>;
        expect(source['id'], _sourceId);
        final Map<Object?, Object?> initial =
            payload['initialRevision']! as Map<Object?, Object?>;
        expect(initial['id'], _revisionId);
        expect(initial['documentId'], _documentId);
        expect(initial['parentRevisionId'], isNull);
        return _envelope(_storedMeta());
      };
      final client = AndroidStoreClient(channel: channel);
      final CreateDocumentRequest request = _createRequest();
      final StoredMeta meta = await client.createDocument(request);
      expect(meta.id, _documentId);
      expect(meta.latestRevisionId, _revisionId);
      expect(meta.readable, isTrue);
      expect(meta.kind, StoreKind.document);
    },
  );

  test('duplicate create maps SAVE-006 without returning metadata', () async {
    handler = (MethodCall call) {
      throw PlatformException(
        code: 'SAVE-006',
        message: 'save.concurrentWrite',
        details: const <String, Object?>{'retryable': true},
      );
    };
    final client = AndroidStoreClient(channel: channel);
    await expectLater(
      client.createDocument(_createRequest()),
      throwsA(
        isA<AndroidConcurrentWriteException>().having(
          (e) => e.code,
          'code',
          'SAVE-006',
        ),
      ),
    );
  });

  test(
    'saveRevision returns metadata only when list agrees with the receipt',
    () async {
      final StreamController<Object?> results = StreamController<Object?>();
      handler = (MethodCall call) {
        if (call.method == 'store.list') {
          return _envelope(<String, Object?>{
            'items': <Object?>[_storedMeta()],
          });
        }
        return _envelope(<String, Object?>{'operationId': _assetId});
      };
      final AndroidOperationClient operations = AndroidOperationClient(
        channel: channel,
        results: results.stream,
      );
      final client = AndroidStoreClient(
        channel: channel,
        operations: operations,
      );
      final SaveRevisionRequest request = SaveRevisionRequest(
        documentId: _documentId,
        expectedHead: _revisionId,
        content: _content(),
        kind: RevisionKind.autosave,
      );
      final Future<StoredMeta> future = client.saveRevision(request);
      await Future<void>.delayed(Duration.zero);
      results.add(<String, Object?>{
        'schemaVersion': 1,
        'event': 'operation.result',
        'operationId': _assetId,
        'ok': true,
        'data': <String, Object?>{
          'revisionId': _revisionId,
          'committedAt': '2026-11-16T12:00:00.000Z',
          'sha256': _sha256(_content().toJson()),
          'verified': true,
          'prunedRevisions': 0,
        },
      });
      final StoredMeta meta = await future;
      expect(meta.latestRevisionId, _revisionId);
      final MethodCall start = calls.firstWhere(
        (MethodCall call) => call.method == 'store.saveRevision',
      );
      final Map<Object?, Object?> payload =
          start.arguments as Map<Object?, Object?>;
      expect(payload['documentId'], _documentId);
      expect(payload['expectedHead'], _revisionId);
      expect(payload['kind'], 'autosave');
      await operations.dispose();
      await results.close();
    },
  );

  test('saveRevision refuses a mismatched list head', () async {
    final StreamController<Object?> results = StreamController<Object?>();
    handler = (MethodCall call) {
      if (call.method == 'store.list') {
        return _envelope(<String, Object?>{
          'items': <Object?>[_storedMeta(latestRevisionId: _assetId)],
        });
      }
      return _envelope(<String, Object?>{'operationId': _assetId});
    };
    final client = AndroidStoreClient(
      channel: channel,
      operations: AndroidOperationClient(
        channel: channel,
        results: results.stream,
      ),
    );
    final Future<StoredMeta> future = client.saveRevision(
      SaveRevisionRequest(
        documentId: _documentId,
        expectedHead: _revisionId,
        content: _content(),
        kind: RevisionKind.explicit,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    results.add(<String, Object?>{
      'schemaVersion': 1,
      'event': 'operation.result',
      'operationId': _assetId,
      'ok': true,
      'data': <String, Object?>{
        'revisionId': _revisionId,
        'committedAt': '2026-11-16T12:00:00.000Z',
        'sha256': _sha256(_content().toJson()),
        'verified': true,
        'prunedRevisions': 0,
      },
    });
    await expectLater(future, throwsA(isA<StateError>()));
    await results.close();
  });

  test('loadDocument validates the head hash and reads source bytes', () async {
    handler = (MethodCall call) {
      if (call.method == 'store.loadDocument') {
        return _envelope(<String, Object?>{
          'meta': _documentMeta(),
          'revision': _content().toJson(),
          'head': <String, Object?>{
            'revisionId': _revisionId,
            'plaintextSha256': _sha256(_content().toJson()),
            'committedAt': '2026-11-16T12:00:00.000Z',
            'parentRevisionId': null,
            'kind': 'explicit',
            'history': <Object?>[],
          },
        });
      }
      if (call.method == 'store.readSource') {
        return _binaryEnvelope(Uint8List.fromList(<int>[1, 2, 3]));
      }
      return _envelope(<String, Object?>{});
    };
    final client = AndroidStoreClient(channel: channel);
    final LoadedDocument loaded = await client.loadDocument(_documentId);
    expect(loaded.meta.id, _documentId);
    expect(loaded.content.pageCount, 1);
    expect(loaded.sourceBytes, <int>[1, 2, 3]);
  });

  test(
    'loadDocument rejects a head that does not match the revision',
    () async {
      handler = (MethodCall call) {
        if (call.method == 'store.loadDocument') {
          return _envelope(<String, Object?>{
            'meta': _documentMeta(),
            'revision': _content().toJson(),
            'head': <String, Object?>{
              'revisionId': _revisionId,
              'plaintextSha256': _sha,
              'committedAt': '2026-11-16T12:00:00.000Z',
              'parentRevisionId': null,
              'kind': 'explicit',
              'history': <Object?>[],
            },
          });
        }
        return _envelope(<String, Object?>{});
      };
      final client = AndroidStoreClient(channel: channel);
      await expectLater(
        client.loadDocument(_documentId),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('SAVE-002 and SAVE-008 keep their distinct recovery meaning', () async {
    final client = AndroidStoreClient(channel: channel);
    handler = (MethodCall call) {
      throw PlatformException(code: 'SAVE-002');
    };
    await expectLater(client.status(), throwsA(isA<KeyUnavailableException>()));
    handler = (MethodCall call) {
      throw PlatformException(
        code: 'SAVE-008',
        details: const <String, Object?>{'retryable': false},
      );
    };
    await expectLater(
      client.status(),
      throwsA(
        isA<KeystoreUnavailableException>().having(
          (e) => e.retryable,
          'retryable',
          isFalse,
        ),
      ),
    );
  });

  test(
    'stageSource and native startup recovery are available to T031',
    () async {
      handler = (MethodCall call) {
        if (call.method == 'store.stageSource') {
          return _envelope(<String, Object?>{
            'sourceId': _sourceId,
            'sha256': _sha,
            'sizeBytes': 3,
            'verified': true,
          });
        }
        if (call.method == 'store.startupRecovery') {
          return _envelope(<String, Object?>{
            'tempEntriesRemoved': 1,
            'incompleteAggregatesRemoved': 2,
            'unreadableAggregates': 0,
            'fallbackAdoptions': 0,
            'orphanAliasesRemoved': 1,
            'orphanAliasesRetained': 0,
            'orphanAliasesFailed': 0,
            'aliasSweepSkipped': false,
            'ambiguousRevisionOrder': 0,
            'prunedRevisions': 0,
          });
        }
        return _envelope(<String, Object?>{});
      };
      final client = AndroidStoreClient(channel: channel);
      await client.stageSource(
        documentId: _documentId,
        sourceId: _sourceId,
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        sha256: _sha,
      );
      final AndroidRecoveryReport report = await client.runStartupRecovery();
      expect(report.tempEntriesRemoved, 1);
      expect(report.incompleteAggregatesRemoved, 2);
      expect(report.orphanAliasesRemoved, 1);
    },
  );
}

CreateDocumentRequest _createRequest() {
  return CreateDocumentRequest(
    documentId: _documentId,
    title: 'Antrag',
    source: _source(),
    initialRevision: Revision(
      id: _revisionId,
      documentId: _documentId,
      kind: RevisionKind.explicit,
      createdAt: DateTime.utc(2026, 11, 16, 12),
      plaintextSha256: _sha256(_content().toJson()),
      content: _content(),
    ),
  );
}

SourceFileRef _source() {
  return SourceFileRef(
    id: _sourceId,
    sha256: _sha,
    sizeBytes: 3,
    pageCount: 1,
    importedAt: DateTime.utc(2026, 11, 16, 12),
  );
}

RevisionContent _content() {
  return RevisionContent(
    pages: <Page>[
      Page(
        index: 0,
        geometry: PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842)),
      ),
    ],
    fieldOrder: const <String>[],
  );
}

Map<String, Object?> _documentMeta() {
  return <String, Object?>{
    'id': _documentId,
    'kind': 'document',
    'title': 'Antrag',
    'createdAt': '2026-11-16T12:00:00.000Z',
    'updatedAt': '2026-11-16T12:00:00.000Z',
    'source': _source().toJson(),
    'latestRevisionId': _revisionId,
    'lastDurableAt': '2026-11-16T12:00:00.000Z',
    'readable': true,
    'unreadableReasonCode': null,
  };
}

Map<String, Object?> _storedMeta({String latestRevisionId = _revisionId}) {
  return <String, Object?>{
    'id': _documentId,
    'kind': 'document',
    'title': 'Antrag',
    'createdAt': '2026-11-16T12:00:00.000Z',
    'updatedAt': '2026-11-16T12:00:00.000Z',
    'latestRevisionId': latestRevisionId,
    'lastDurableAt': '2026-11-16T12:00:00.000Z',
    'readable': true,
    'unreadableReasonCode': null,
  };
}

Map<String, Object?> _envelope(Map<String, Object?> data) {
  return <String, Object?>{'schemaVersion': 1, 'ok': true, 'data': data};
}

Map<String, Object?> _binaryEnvelope(Uint8List data) {
  return <String, Object?>{'schemaVersion': 1, 'ok': true, 'data': data};
}

String _sha256(Map<String, Object?> content) {
  return crypto.sha256.convert(canonicalJsonBytes(content)).toString();
}
