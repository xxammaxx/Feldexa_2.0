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

/// The four render phases of `contracts/platform-channel.md` §6.
enum AndroidExportPhase {
  /// The stored source PDF is read and checked against the plan hash.
  importing,

  /// Every page is copied and receives its overlay operations.
  drawing,

  /// The written artifact is verified before anything is published.
  verifying,

  /// The verified artifact is renamed into place and published.
  finalizing,
}

/// One content-free progress step of the running export (§6, §8.1).
///
/// It carries the phase and a best-effort fraction and nothing else: no page
/// content, label, value, path, or artifact id.
final class AndroidExportProgress {
  const AndroidExportProgress({required this.phase, required this.fraction});

  /// The reported phase token of §6.
  final AndroidExportPhase phase;

  /// Best-effort completion in `0.0 … 1.0`.
  final double fraction;
}

/// Android `PdfExportPort` channel client.
///
/// Besides the port it owns two capabilities of the same two channels, so the
/// editor can show the progress phases of `§10` point 3 of
/// `contracts/editor-interactions.md` and cancel the running render:
///
/// * [progress] relays the content-free `export.progress` events of
///   `de.feldexa/events` for the operation this client started;
/// * [cancelActiveOperation] issues the synchronous `cancel.operation` call of
///   `contracts/platform-channel.md` §9 for that operation id.
///
/// No second channel and no second operation client is created here.
final class AndroidPdfExportClient implements PdfExportPort {
  AndroidPdfExportClient({
    MethodChannel? channel,
    AndroidOperationClient? operations,
    CapabilityEvidence? evidence,
    Stream<Object?>? events,
  }) : _channel = channel ?? const MethodChannel('de.feldexa/platform'),
       _operations =
           operations ??
           AndroidOperationClient(
             channel: channel ?? const MethodChannel('de.feldexa/platform'),
           ),
       _events =
           events ??
           const EventChannel('de.feldexa/events').receiveBroadcastStream(),
       _evidence =
           evidence ??
           CapabilityEvidence.android(adapterId: 'android.pdfbox.v1');

  final MethodChannel _channel;
  final AndroidOperationClient _operations;
  final Stream<Object?> _events;
  final CapabilityEvidence _evidence;

  /// The `export.render` operation this client started, or null when none runs.
  String? _activeOperationId;

  /// Content-free progress steps of the export this client started.
  ///
  /// Only `export.progress` events whose `operationId` is the id the start
  /// reply of `export.render` returned are relayed; a step that arrives before
  /// that reply is dropped, which §8.1 allows because progress is best-effort
  /// and never authoritative. An event with an unknown phase token or a
  /// non-numeric fraction is ignored instead of being rendered as a stage. The
  /// relay subscribes to the shared event channel only while it is listened to.
  late final Stream<AndroidExportProgress> progress = _events
      .where(
        (Object? event) =>
            event is Map &&
            event['event'] == 'export.progress' &&
            event['operationId'] != null &&
            event['operationId'] == _activeOperationId,
      )
      .map(_progressStep)
      .where((AndroidExportProgress? step) => step != null)
      .cast<AndroidExportProgress>();

  /// Requests cancellation of the export this client started (§9).
  ///
  /// Returns exactly what the platform answered. `false` means "nothing was
  /// cancelled": no operation of this client is running, either because the
  /// start reply has not arrived yet or because the terminal result was already
  /// published. A winning cancellation is never inferred from this answer; it
  /// arrives as the terminal `PLT-004` result of [export].
  Future<bool> cancelActiveOperation() async {
    final String? id = _activeOperationId;
    if (id == null) {
      return false;
    }
    return _operations.cancel(id);
  }

  /// Parses one `export.progress` event, or null when it is not a valid step.
  static AndroidExportProgress? _progressStep(Object? event) {
    if (event is! Map) {
      return null;
    }
    final AndroidExportPhase? phase = switch (event['phase']) {
      'importing' => AndroidExportPhase.importing,
      'drawing' => AndroidExportPhase.drawing,
      'verifying' => AndroidExportPhase.verifying,
      'finalizing' => AndroidExportPhase.finalizing,
      _ => null,
    };
    final Object? fraction = event['fraction'];
    if (phase == null || fraction is! num) {
      return null;
    }
    return AndroidExportProgress(
      phase: phase,
      fraction: fraction.toDouble().clamp(0.0, 1.0),
    );
  }

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
      // `start` instead of `invoke`: the operation id is the reliable
      // cancellation and progress key of §9 and §8.1, and it exists only
      // between the start reply and the terminal result.
      final AndroidOperation operation = await _operations.start(
        'export.render',
        <String, Object?>{'plan': request.plan.toJson()},
      );
      _activeOperationId = operation.operationId;
      try {
        return _verifiedResult(request, await operation.result);
      } finally {
        if (_activeOperationId == operation.operationId) {
          _activeOperationId = null;
        }
      }
    } catch (error) {
      throwAndroidChannelError(error);
    }
  }

  /// Reconstructs the verified [ExportResult] from the terminal render data.
  ExportResult _verifiedResult(ExportRequest request, Object? raw) {
    try {
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
