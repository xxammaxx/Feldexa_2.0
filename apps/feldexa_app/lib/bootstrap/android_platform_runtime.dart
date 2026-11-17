// T027 Android composition root.
//
// This is the only application file that constructs the Android thin clients.
// It is imported by the Android bootstrap (T031) behind a conditional import;
// the Web build must never resolve this file or the adapter package.
//
// `runStartupRecovery()` is the native T026 recovery for §4 steps 1–3 and 5–6.
// Under the owner decision of 2026-11-17 (`contracts/storage-format.md` §4 and
// `contracts/platform-channel.md` §4) T031 runs its Dart export-preview cleanup
// (step 4) first, then calls this native recovery, which performs its own steps
// in the 1 → 2 → 3 → 5 → 6 order. T031 must not duplicate those native steps in
// Dart. The Dart sweep then performs only the contract-visible
// list/recoveryStamp reads.

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

  /// Runs the native T026 startup recovery (storage-format §4 native steps
  /// 1–3 and 5–6). T031 calls this after the Dart export-preview step 4.
  Future<AndroidRecoveryReport> runStartupRecovery() =>
      store.runStartupRecovery();
}
