// T027 Android `DocumentImportPort` thin client.
//
// The picker/preflight/staging engine belongs to T038; this client is the
// transport boundary only. Until that service is registered, the native facade
// rejects the method with `PLT-001` and the client fails closed with
// `UnsupportedOperationException` rather than pretending an import happened.

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/services.dart';

import 'android_channel.dart';
import 'android_operation_client.dart';

/// Android `DocumentImportPort` channel client.
final class AndroidImportClient implements DocumentImportPort {
  AndroidImportClient({
    MethodChannel? channel,
    AndroidOperationClient? operations,
    CapabilityEvidence? evidence,
  }) : _operations =
           operations ??
           AndroidOperationClient(
             channel: channel ?? const MethodChannel('de.feldexa/platform'),
           ),
       _evidence =
           evidence ??
           CapabilityEvidence.android(adapterId: 'android.import.v1');

  final AndroidOperationClient _operations;
  final CapabilityEvidence _evidence;

  static final CapabilityDescriptor _descriptor = CapabilityDescriptor(
    kind: CapabilityKind.documentImport,
    adapterId: 'android.import.v1',
    version: '1',
    isSimulated: false,
    evidence: CapabilityEvidence.android(adapterId: 'android.import.v1'),
    supportedFeatures: const <String>[
      'saf-open-document',
      'streaming-staging',
      'pdf-preflight',
      'source-hash-verification',
      'partial-page-failures',
    ],
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  CapabilityEvidence get evidence => _evidence;

  @override
  Future<ImportedSource> pickAndImport(ImportRequest request) async {
    try {
      final Object? raw = await _operations.invoke(
        'import.pickAndImport',
        <String, Object?>{'maxBytes': request.maxBytes},
      );
      final Map<String, Object?> data = androidMap(raw, 'import result');
      final Object? pages = data['pages'];
      final Object? failures = data['pageFailures'];
      if (pages is! List || failures is! List) {
        throw const FormatException('Invalid import pages');
      }
      final int pageCount = data['pageCount'] is int
          ? data['pageCount'] as int
          : (throw const FormatException('Invalid page count'));
      final List<PageGeometry> geometry = <PageGeometry>[
        for (final Object? page in pages)
          PageGeometry.fromJson(androidMap(page, 'page geometry')),
      ];
      if (geometry.length != pageCount) {
        throw const FormatException('Import page geometry count mismatch');
      }
      final List<PageFailure> pageFailures = <PageFailure>[
        for (final Object? failure in failures)
          PageFailure.fromJson(androidMap(failure, 'page failure')),
      ];
      final Object? displayName = data['displayName'];
      if (displayName != null && displayName is! String) {
        throw const FormatException('Invalid display name');
      }
      try {
        return ImportedSource(
          documentId: androidUuid(data['documentId'], 'documentId'),
          sourceId: androidUuid(data['sourceId'], 'sourceId'),
          sha256: androidSha256(data['sha256'], 'sha256'),
          sizeBytes: data['sizeBytes'] is int
              ? data['sizeBytes'] as int
              : (throw const FormatException('Invalid source size')),
          pageCount: pageCount,
          pages: geometry,
          pageFailures: pageFailures,
          displayName: displayName as String?,
          evidence: _evidence,
        );
      } on ArgumentError {
        throw const FormatException('Invalid import result');
      }
    } catch (error) {
      throwAndroidChannelError(error);
    }
  }

  @override
  Future<SourceIntegrity> verifySource(String sourceId) async {
    try {
      final Object? raw = await _operations.invoke(
        'import.verifySource',
        <String, Object?>{'sourceId': sourceId},
      );
      final Map<String, Object?> data = androidMap(raw, 'source integrity');
      final Object? readable = data['readable'];
      final Object? failures = data['pageFailures'];
      if (readable is! bool || failures is! List) {
        throw const FormatException('Invalid source integrity result');
      }
      final Object? sha = data['sha256'];
      final Object? pageCount = data['pageCount'];
      if (sha != null && sha is! String) {
        throw const FormatException('Invalid source hash');
      }
      if (pageCount != null && pageCount is! int) {
        throw const FormatException('Invalid source page count');
      }
      try {
        return SourceIntegrity(
          readable: readable,
          actualSha256: sha as String?,
          pageCount: pageCount as int?,
          pageFailures: <PageFailure>[
            for (final Object? failure in failures)
              PageFailure.fromJson(androidMap(failure, 'page failure')),
          ],
          evidence: _evidence,
        );
      } on ArgumentError {
        throw const FormatException('Invalid source integrity result');
      }
    } catch (error) {
      throwAndroidChannelError(error);
    }
  }
}
