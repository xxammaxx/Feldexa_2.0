import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/services.dart';

/// Android channel client for the store's non-fatal availability summary.
/// Other SecureStorePort operations require separate adapters and are not
/// represented by this partial client.
final class AndroidStoreStatusClient {
  AndroidStoreStatusClient({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('de.feldexa/platform');

  final MethodChannel _channel;

  /// Reads the native store's verified recovery state for one aggregate.
  Future<RecoveryStamp> recoveryStamp(String id, StoreKind kind) async {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(id)) {
      throw ArgumentError('id must be a lowercase UUIDv4');
    }
    final Object? response;
    try {
      response = await _channel.invokeMethod<Object?>(
        'store.recoveryStamp',
        <String, Object?>{'schemaVersion': 1, 'id': id, 'kind': kind.name},
      );
    } on PlatformException catch (error) {
      switch (error.code) {
        case 'SAVE-002':
          throw KeyUnavailableException();
        case 'SAVE-003':
          throw CorruptDataException();
        case 'SAVE-008':
          final details = error.details;
          if (details is! Map || details['retryable'] is! bool) rethrow;
          throw KeystoreUnavailableException(
            retryable: details['retryable'] as bool,
          );
        default:
          rethrow;
      }
    }
    if (response is! Map ||
        response['schemaVersion'] != 1 ||
        response['ok'] != true) {
      throw const FormatException('Invalid platform response envelope');
    }
    final data = response['data'];
    if (data is! Map ||
        data['headCorrupt'] is! bool ||
        data['fellBackToOlderRevision'] is! bool ||
        (data['verifiedRevisionId'] != null &&
            data['verifiedRevisionId'] is! String) ||
        (data['committedAt'] != null && data['committedAt'] is! String)) {
      throw const FormatException('Invalid recovery stamp response');
    }
    final committed = data['committedAt'] as String?;
    final DateTime? timestamp = committed == null
        ? null
        : DateTime.tryParse(committed);
    if (committed != null && (timestamp == null || !timestamp.isUtc)) {
      throw const FormatException('Invalid recovery timestamp');
    }
    try {
      return RecoveryStamp(
        verifiedRevisionId: data['verifiedRevisionId'] as String?,
        committedAt: timestamp,
        headCorrupt: data['headCorrupt'] as bool,
        fellBackToOlderRevision: data['fellBackToOlderRevision'] as bool,
      );
    } on ArgumentError {
      throw const FormatException('Invalid recovery stamp response');
    }
  }

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
