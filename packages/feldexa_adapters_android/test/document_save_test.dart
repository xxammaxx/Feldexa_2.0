import 'dart:async';

import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('de.feldexa/platform');
  const document = '123e4567-e89b-42d3-a456-426614174000';
  const revision = '123e4567-e89b-42d3-a456-426614174001';
  const operationId = '123e4567-e89b-42d3-a456-426614174002';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late StreamController<Object?> events;
  late AndroidOperationClient operations;
  late AndroidDocumentSaveClient client;
  setUp(() {
    events = StreamController<Object?>.broadcast(sync: true);
    operations = AndroidOperationClient(
      channel: channel,
      results: events.stream,
    );
    client = AndroidDocumentSaveClient(
      operations: operations,
      channel: channel,
    );
  });
  tearDown(() async {
    await operations.dispose();
    await events.close();
    messenger.setMockMethodCallHandler(channel, null);
  });

  SaveRevisionRequest request() => SaveRevisionRequest(
    documentId: document,
    content: RevisionContent(
      pages: <Page>[
        Page(
          index: 0,
          geometry: PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842)),
        ),
      ],
      fieldOrder: <String>[],
    ),
    kind: RevisionKind.autosave,
  );

  void install({required bool verified, String returnedRevision = revision}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'store.saveRevision') {
        events.add({
          'schemaVersion': 1,
          'event': 'operation.result',
          'operationId': operationId,
          'ok': true,
          'data': {
            'revisionId': revision,
            'committedAt': '2026-01-01T00:00:00Z',
            'sha256': 'a' * 64,
            'verified': verified,
            'prunedRevisions': 0,
          },
        });
        return {
          'schemaVersion': 1,
          'ok': true,
          'data': {'operationId': operationId},
        };
      }
      expect(call.method, 'store.list');
      return {
        'schemaVersion': 1,
        'ok': true,
        'data': {
          'items': [
            {
              'id': document,
              'kind': 'document',
              'title': 'Antrag',
              'createdAt': '2026-01-01T00:00:00Z',
              'updatedAt': '2026-01-01T00:00:00Z',
              'latestRevisionId': returnedRevision,
              'lastDurableAt': '2026-01-01T00:00:00Z',
              'readable': true,
            },
          ],
        },
      };
    });
  }

  test(
    'returns actual stored metadata for the verified committed revision',
    () async {
      install(verified: true);
      final saved = await client.saveRevision(request());
      expect(saved.id, document);
      expect(saved.latestRevisionId, revision);
      expect(saved.title, 'Antrag');
    },
  );
  test('rejects a commit that was not verified', () async {
    install(verified: false);
    await expectLater(client.saveRevision(request()), throwsFormatException);
  });
  test('does not return metadata for a different head', () async {
    install(
      verified: true,
      returnedRevision: '123e4567-e89b-42d3-a456-426614174003',
    );
    await expectLater(client.saveRevision(request()), throwsStateError);
  });
}
