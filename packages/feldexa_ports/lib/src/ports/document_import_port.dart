// T013 `DocumentImportPort` interface.
//
// Owner: `packages/feldexa_ports/lib/src/ports/document_import_port.dart`
// (T013). Normative source: `contracts/ports.md` §2.1.
//
// The implementation lives only in an adapter package. This interface must not
// accept or return a file path, a `File`, a `content://` URI, or a widget, and
// it must not log document content.

import '../descriptor.dart';
import '../dto/import_dto.dart';

/// Picks a source document, stages it into encrypted storage, and verifies
/// stored sources (`contracts/ports.md` §2.1).
///
/// Failures are reported by throwing the T014 typed exceptions, never by
/// returning `null`. Cancellation throws `ImportCancelledException`; storage
/// exhaustion throws `StorageFullException`; a failed staged write throws
/// `StorageWriteException`.
abstract interface class DocumentImportPort implements PlatformCapability {
  /// Opens the platform document picker and streams the selection into the
  /// encrypted source store.
  ///
  /// The method returns only after the source is written, read back, and
  /// hash-verified. The picked file is opened read-only and is never modified.
  Future<ImportedSource> pickAndImport(ImportRequest request);

  /// Re-validates an existing stored source without user interaction.
  Future<SourceIntegrity> verifySource(String sourceId);
}
