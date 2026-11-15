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
}
