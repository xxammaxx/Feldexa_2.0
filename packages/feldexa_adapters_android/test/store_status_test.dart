import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('de.feldexa/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'status unwraps the versioned response and marks Android evidence',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'store.status');
        expect(call.arguments, {'schemaVersion': 1});
        return {
          'schemaVersion': 1,
          'ok': true,
          'data': {'keyAvailable': false, 'objectCount': 3, 'totalBytes': 42},
        };
      });
      final status = await AndroidStoreStatusClient().status();
      expect(status.keyAvailable, isFalse);
      expect(status.objectCount, 3);
      expect(status.totalBytes, 42);
      expect(status.evidence.evidenceClass, EvidenceClass.none);
      expect(status.evidence.simulated, isFalse);
    },
  );

  test('status rejects an invalid envelope', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'schemaVersion': 2,
        'ok': true,
        'data': <String, Object?>{},
      },
    );
    await expectLater(
      AndroidStoreStatusClient().status(),
      throwsFormatException,
    );
  });

  test('recovery stamp reads the verified revision from the channel', () async {
    const id = '123e4567-e89b-42d3-a456-426614174000';
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'store.recoveryStamp');
      expect(call.arguments, {
        'schemaVersion': 1,
        'id': id,
        'kind': 'document',
      });
      return {
        'schemaVersion': 1,
        'ok': true,
        'data': {
          'verifiedRevisionId': id,
          'committedAt': '2026-01-01T00:00:00Z',
          'headCorrupt': true,
          'fellBackToOlderRevision': true,
        },
      };
    });
    final stamp = await AndroidStoreStatusClient().recoveryStamp(
      id,
      StoreKind.document,
    );
    expect(stamp.verifiedRevisionId, id);
    expect(stamp.committedAt, DateTime.utc(2026));
    expect(stamp.fellBackToOlderRevision, isTrue);
  });

  test(
    'recovery stamp rejects a malformed identifier before sending',
    () async {
      var called = false;
      messenger.setMockMethodCallHandler(channel, (_) async {
        called = true;
        return null;
      });
      await expectLater(
        AndroidStoreStatusClient().recoveryStamp('../bad', StoreKind.document),
        throwsArgumentError,
      );
      expect(called, isFalse);
    },
  );

  test('recovery stamp maps aggregate key failure', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'SAVE-002'),
    );
    await expectLater(
      AndroidStoreStatusClient().recoveryStamp(
        '123e4567-e89b-42d3-a456-426614174000',
        StoreKind.document,
      ),
      throwsA(isA<KeyUnavailableException>()),
    );
  });

  test('recovery stamp rejects malformed response data', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'schemaVersion': 1,
        'ok': true,
        'data': {'headCorrupt': 'yes', 'fellBackToOlderRevision': false},
      },
    );
    await expectLater(
      AndroidStoreStatusClient().recoveryStamp(
        '123e4567-e89b-42d3-a456-426614174000',
        StoreKind.document,
      ),
      throwsFormatException,
    );
  });
}
