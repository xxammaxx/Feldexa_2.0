import 'dart:async';

import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('de.feldexa/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const id = '123e4567-e89b-42d3-a456-426614174000';
  late StreamController<Object?> events;
  late AndroidOperationClient client;
  setUp(() {
    events = StreamController<Object?>.broadcast(sync: true);
    client = AndroidOperationClient(channel: channel, results: events.stream);
  });
  tearDown(() async {
    await client.dispose();
    await events.close();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'reconciles a terminal result arriving before the start reply',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'store.saveRevision');
        events.add({
          'schemaVersion': 1,
          'event': 'operation.result',
          'operationId': id,
          'ok': true,
          'data': {'verified': true},
        });
        return {
          'schemaVersion': 1,
          'ok': true,
          'data': {'operationId': id},
        };
      });
      final result = await client.invoke(
        'store.saveRevision',
        <String, Object?>{},
      );
      expect(result, {'verified': true});
    },
  );

  test('terminal errors retain code without losing retryability', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      scheduleMicrotask(
        () => events.add({
          'schemaVersion': 1,
          'event': 'operation.result',
          'operationId': id,
          'ok': false,
          'error': {
            'code': 'SAVE-008',
            'message': 'save.keystoreUnavailable',
            'details': {'retryable': false},
          },
        }),
      );
      return {
        'schemaVersion': 1,
        'ok': true,
        'data': {'operationId': id},
      };
    });
    await expectLater(
      client.invoke('store.saveRevision', <String, Object?>{}),
      throwsA(
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'SAVE-008')
            .having((e) => (e.details as Map)['retryable'], 'retryable', false),
      ),
    );
  });

  test('rejects malformed start replies', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'schemaVersion': 1,
        'ok': true,
        'data': <String, Object?>{},
      },
    );
    await expectLater(
      client.invoke('store.saveRevision', <String, Object?>{}),
      throwsFormatException,
    );
  });

  test('closed result stream fails a pending accepted operation', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'schemaVersion': 1,
        'ok': true,
        'data': {'operationId': id},
      },
    );
    final pending = client.invoke('store.saveRevision', <String, Object?>{});
    final assertion = expectLater(pending, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    await events.close();
    await assertion;
  });

  test('start exposes the operation ID for cancellation', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'cancel.operation') {
        expect(call.arguments, {'schemaVersion': 1, 'operationId': id});
        return {
          'schemaVersion': 1,
          'ok': true,
          'data': {'cancelled': true},
        };
      }
      return {
        'schemaVersion': 1,
        'ok': true,
        'data': {'operationId': id},
      };
    });
    final operation = await client.start(
      'store.saveRevision',
      <String, Object?>{},
    );
    expect(operation.operationId, id);
    expect(await client.cancel(id), isTrue);
    events.add({
      'schemaVersion': 1,
      'event': 'operation.result',
      'operationId': id,
      'ok': false,
      'error': {
        'code': 'PLT-004',
        'message': 'platform.cancelled',
        'details': <String, Object?>{},
      },
    });
    await expectLater(
      operation.result,
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'PLT-004'),
      ),
    );
  });
}
