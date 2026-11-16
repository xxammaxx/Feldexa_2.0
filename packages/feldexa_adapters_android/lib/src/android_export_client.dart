// T027 Android `PdfExportPort` thin client.
//
// The PDFBox renderer/verifier belongs to its own task. This client only
// transports the canonical export plan and reconstructs a canonical
// `ExportArtifact` through its strict state machine; it never fabricates a
// succeeded artifact without the native verification payload.

import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/services.dart';

import 'android_channel.dart';
import 'android_operation_client.dart';

/// Android `PdfExportPort` channel client.
final class AndroidPdfExportClient implements PdfExportPort {
  AndroidPdfExportClient({
    MethodChannel? channel,
    AndroidOperationClient? operations,
    CapabilityEvidence? evidence,
  }) : _channel = channel ?? const MethodChannel('de.feldexa/platform'),
       _operations =
           operations ??
           AndroidOperationClient(
             channel: channel ?? const MethodChannel('de.feldexa/platform'),
           ),
       _evidence =
           evidence ??
           CapabilityEvidence.android(adapterId: 'android.pdfbox.v1');

  final MethodChannel _channel;
  final AndroidOperationClient _operations;
  final CapabilityEvidence _evidence;

  static final CapabilityDescriptor _descriptor = CapabilityDescriptor(
    kind: CapabilityKind.pdfExport,
    adapterId: 'android.pdfbox.v1',
    version: '1',
    isSimulated: false,
    evidence: CapabilityEvidence.android(adapterId: 'android.pdfbox.v1'),
    supportedFeatures: const <String>[
      'pdfbox-flatten',
      'artifact-verification',
      'no-interactive-fields',
      'atomic-output',
    ],
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  CapabilityEvidence get evidence => _evidence;

  @override
  Future<ExportValidationResult> validate(ExportPlan plan) async {
    try {
      final Object? raw = await _operations.invoke(
        'export.validate',
        <String, Object?>{'plan': plan.toJson()},
      );
      final Map<String, Object?> data = androidMap(raw, 'export validation');
      if (data['ok'] != true) {
        throw const FormatException('Export validation is not ok');
      }
      final Object? warnings = data['warnings'];
      if (warnings is! List) {
        throw const FormatException('Invalid export warnings');
      }
      final ExportValidation validation = ExportValidation(
        warnings: <ExportValidationWarning>[
          for (final Object? warning in warnings)
            ExportValidationWarning.fromJson(
              androidMap(warning, 'export warning'),
            ),
        ],
        validatedAt: DateTime.now().toUtc(),
      );
      return ExportValidationResult(
        validation: validation,
        evidence: _evidence,
      );
    } catch (error) {
      throwAndroidChannelError(error);
    }
  }

  @override
  Future<ExportResult> export(ExportRequest request) async {
    try {
      final Object? raw = await _operations.invoke(
        'export.render',
        <String, Object?>{'plan': request.plan.toJson()},
      );
      final Map<String, Object?> data = androidMap(raw, 'export result');
      final Object? pageCount = data['pageCount'];
      final Object? byteSize = data['byteSize'];
      final Object? verification = data['verification'];
      if (pageCount is! int ||
          byteSize is! int ||
          byteSize < 1 ||
          verification is! Map) {
        throw const FormatException('Invalid export result');
      }
      final ArtifactVerification parsedVerification =
          ArtifactVerification.fromJson(
            androidMap(verification, 'verification'),
          );
      // `export.render` returns the verification record but not the attempt
      // start. The verified check time is the conservative creation bound: it
      // cannot make verification predate creation, and a later UI attempt time
      // is not known to this transport-only client.
      final ExportArtifact artifact =
          ExportArtifact.start(
            id: androidUuid(data['artifactId'], 'artifactId'),
            documentId: request.documentId,
            revisionId: request.revisionId,
            pageCount: pageCount,
            createdAt: parsedVerification.checkedAt,
          ).startRendering().startVerification().succeed(
            byteSize: byteSize,
            sha256: androidSha256(data['sha256'], 'sha256'),
            verification: parsedVerification,
          );
      if (!artifact.isPreviewAvailable) {
        throw const FormatException('Export artifact is not available');
      }
      return ExportResult(artifact: artifact, evidence: _evidence);
    } catch (error) {
      throwAndroidChannelError(error);
    }
  }

  @override
  Future<Uint8List> readArtifact(String artifactId) async {
    try {
      final Object? raw = await _channel.invokeMethod<Object?>(
        'export.readArtifact',
        <String, Object?>{'schemaVersion': 1, 'artifactId': artifactId},
      );
      final Object? value = androidEnvelopeValue(
        raw,
        method: 'export.readArtifact',
      );
      final Uint8List? data = androidBytes(value);
      if (data == null || data.isEmpty) {
        throw const FormatException('Invalid export artifact bytes');
      }
      return data;
    } catch (error) {
      throwAndroidChannelError(error);
    }
  }

  @override
  Future<void> deleteArtifact(String artifactId) async {
    try {
      final Map<String, Object?> data = androidEnvelopeData(
        await _channel.invokeMethod<Object?>(
          'export.deleteArtifact',
          <String, Object?>{'schemaVersion': 1, 'artifactId': artifactId},
        ),
        method: 'export.deleteArtifact',
      );
      if (data['deleted'] != true) {
        throw const FormatException('Artifact was not deleted');
      }
    } catch (error) {
      throwAndroidChannelError(error);
    }
  }
}
