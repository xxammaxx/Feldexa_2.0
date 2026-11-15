import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/services.dart';

/// Android channel client for the store's non-fatal availability summary.
/// Other SecureStorePort operations require separate adapters and are not
/// represented by this partial client.
final class AndroidStoreStatusClient {
  AndroidStoreStatusClient({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('de.feldexa/platform');

  final MethodChannel _channel;

  Future<StoreStatus> status() async {
    final Object? response = await _channel.invokeMethod<Object?>(
      'store.status',
      <String, Object?>{'schemaVersion': 1},
    );
    if (response is! Map ||
        response['schemaVersion'] != 1 ||
        response['ok'] != true) {
      throw const FormatException('Invalid platform response envelope');
    }
    final Object? data = response['data'];
    if (data is! Map ||
        data['keyAvailable'] is! bool ||
        data['objectCount'] is! int ||
        data['totalBytes'] is! int) {
      throw const FormatException('Invalid store status response');
    }
    return StoreStatus(
      keyAvailable: data['keyAvailable'] as bool,
      objectCount: data['objectCount'] as int,
      totalBytes: data['totalBytes'] as int,
      evidence: CapabilityEvidence.android(adapterId: 'android.store.v1'),
    );
  }
}
