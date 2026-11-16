// T027 Android composition root.
//
// This is the only application file that constructs the Android thin clients.
// It is imported by the Android bootstrap (T031) behind a conditional import;
// the Web build must never resolve this file or the adapter package.
//
// `runStartupRecovery()` is the prerequisite T031 calls before its
// `StartupSweep.run()`: the native T026 recovery owns stale-temp, incomplete
// aggregate, head-fallback, signature, and orphan-alias reconciliation. The
// Dart sweep then performs only the contract-visible list/recoveryStamp reads.

import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';

import '../platform/registry.dart';
import '../platform/registry_android.dart';

/// Fully composed Android runtime adapters.
final class AndroidPlatformRuntime {
  AndroidPlatformRuntime._({
    required this.adapters,
    required this.store,
    required this.registry,
  });

  /// The ten real adapters used by the Android registry.
  final PlatformAdapterSet adapters;

  /// The concrete store client exposing `stageSource` and native recovery.
  final AndroidStoreClient store;

  /// The validated real-only registry.
  final AndroidAdapterRegistry registry;

  /// Builds the Android runtime.
  ///
  /// [sourceBytes] resolves decrypted source bytes for the PDFium raster port;
  /// [ocrPageSize] supplies the source-page display size that the T013
  /// `OcrRequest` DTO does not carry. Both are explicit production seams, not
  /// simulated substitutes.
  static AndroidPlatformRuntime create({
    required SourceBytesResolver sourceBytes,
    required OcrPageSizeResolver ocrPageSize,
  }) {
    final AndroidOperationClient operations = AndroidOperationClient();
    final AndroidStoreClient store = AndroidStoreClient(operations: operations);
    final PlatformAdapterSet adapters = PlatformAdapterSet(
      import: AndroidImportClient(operations: operations),
      raster: AndroidPdfrxRasterClient(sourceBytes: sourceBytes),
      ocr: AndroidOcrClient(
        operations: operations,
        pageSizeResolver: ocrPageSize,
      ),
      store: store,
      export: AndroidPdfExportClient(operations: operations),
      delivery: AndroidDeliveryClient(),
      lifecycle: AndroidLifecycleClient(),
      clock: const AndroidClockClient(),
      ids: AndroidIdClient(),
      diagnostics: AndroidDiagnosticsClient(),
    );
    return AndroidPlatformRuntime._(
      adapters: adapters,
      store: store,
      registry: AndroidAdapterRegistry(adapters),
    );
  }

  /// Runs the native T026 startup recovery. T031 must call this before
  /// `StartupSweep.run()`.
  Future<AndroidRecoveryReport> runStartupRecovery() =>
      store.runStartupRecovery();
}
