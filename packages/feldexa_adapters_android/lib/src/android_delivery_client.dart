// T027 Android `DeliveryPort` thin client.
//
// Delivery is synchronous on the channel: the MethodChannel reply is the
// terminal result. The client never invents a location hint and treats user
// cancellation as `completed: false`, not as an error.

import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/services.dart';

import 'android_channel.dart';

/// Android `DeliveryPort` channel client.
final class AndroidDeliveryClient implements DeliveryPort {
  AndroidDeliveryClient({MethodChannel? channel, CapabilityEvidence? evidence})
    : _channel = channel ?? const MethodChannel('de.feldexa/platform'),
      _evidence =
          evidence ??
          CapabilityEvidence.android(adapterId: 'android.delivery.v1');

  final MethodChannel _channel;
  final CapabilityEvidence _evidence;

  static final CapabilityDescriptor _descriptor = CapabilityDescriptor(
    kind: CapabilityKind.delivery,
    adapterId: 'android.delivery.v1',
    version: '1',
    isSimulated: false,
    evidence: CapabilityEvidence.android(adapterId: 'android.delivery.v1'),
    supportedFeatures: const <String>[
      'saf-create-document',
      'file-provider-share',
      'system-print',
      'verified-save',
    ],
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  CapabilityEvidence get evidence => _evidence;

  @override
  Future<DeliveryOutcome> deliver({
    required DeliveryAction action,
    required String artifactId,
  }) async {
    final String method;
    final Map<String, Object?> payload;
    switch (action) {
      case DeliveryAction.save:
        method = 'delivery.save';
        payload = <String, Object?>{
          'artifactId': artifactId,
          'suggestedName': 'Feldexa_Dokument.pdf',
        };
        break;
      case DeliveryAction.share:
        method = 'delivery.share';
        payload = <String, Object?>{
          'artifactId': artifactId,
          'mimeType': 'application/pdf',
        };
        break;
      case DeliveryAction.print:
        method = 'delivery.print';
        payload = <String, Object?>{
          'artifactId': artifactId,
          'jobName': 'Feldexa Dokument',
        };
        break;
    }
    try {
      final Map<String, Object?> data = androidEnvelopeData(
        await _channel.invokeMethod<Object?>(method, <String, Object?>{
          'schemaVersion': 1,
          ...payload,
        }),
        method: method,
      );
      final Object? completed = data['completed'];
      final Object? cancelled = data['cancelled'];
      final Object? hint = data['locationHint'];
      if (completed is! bool ||
          cancelled is! bool ||
          (hint != null && hint is! String) ||
          (completed && cancelled)) {
        throw const FormatException('Invalid delivery outcome');
      }
      try {
        return DeliveryOutcome(
          action: action,
          completed: completed,
          userVisibleLocationHint: hint as String?,
          evidence: _evidence,
        );
      } on ArgumentError {
        throw const FormatException('Invalid delivery outcome');
      }
    } catch (error) {
      throwAndroidChannelError(error);
    }
  }
}
