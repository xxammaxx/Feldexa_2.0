// T013 `SecureStorePort` interface.
//
// Owner: `packages/feldexa_ports/lib/src/ports/secure_store_port.dart` (T013).
// Normative sources:
//   * `contracts/ports.md` §2.4 — the encrypted store interface;
//   * `contracts/storage-format.md` §5 — durable state after storage failures;
//   * `contracts/error-catalog.de.md` — the typed failures this port throws.
//
// Implementations live only in adapter packages and generate object names
// themselves. No method accepts an arbitrary path. Deletion requires an
// explicit `DeleteConfirmation`; document and template aggregates are never
// mixed.

import 'dart:typed_data';

import '../descriptor.dart';
import '../dto/store_dto.dart';

/// Encrypted document and template storage (`contracts/ports.md` §2.4).
abstract interface class SecureStorePort implements PlatformCapability {
  /// Reports whether every known aggregate key is available, plus object count
  /// and total size.
  ///
  /// A missing key does not throw for the whole store. The summary can be false
  /// for aggregate-scoped `SAVE-002` or global `SAVE-008`; it does not identify
  /// the scope, and loads throw the matching typed exception.
  Future<StoreStatus> status();

  /// Creates a document for an already staged source.
  Future<StoredMeta> createDocument(CreateDocumentRequest request);

  /// Atomically writes and read-back-verifies one revision.
  ///
  /// Success is returned only after the new head is written and read back
  /// (FR-047). A failed staged write throws `StorageWriteException`; storage
  /// exhaustion throws `StorageFullException` and leaves the last durable head
  /// untouched. A missing aggregate key throws `KeyUnavailableException`
  /// (`SAVE-002`); a global provider/reset condition throws
  /// `KeystoreUnavailableException` (`SAVE-008`). The previous head is preserved.
  Future<StoredMeta> saveRevision(SaveRevisionRequest request);

  /// Loads and decrypts the current document revision.
  ///
  /// Throws `KeyUnavailableException` (`SAVE-002`) for one aggregate while
  /// other aggregate keys remain available, `KeystoreUnavailableException`
  /// (`SAVE-008`) for a global provider/reset condition, or
  /// `CorruptDataException`. With `SAVE-002`, other documents remain loadable.
  Future<LoadedDocument> loadDocument(String documentId);

  /// Reads one decrypted signature asset, bounded in size.
  Future<Uint8List> readSignature(String documentId, String assetId);

  /// Writes one signature asset into the document aggregate.
  Future<void> writeSignature(WriteSignatureRequest request);

  /// Lists stored aggregates of one kind, newest first.
  Future<List<StoredMeta>> list(StoreKind kind);

  /// Deletes one aggregate after explicit confirmation.
  ///
  /// The aggregate's objects are removed; no other document or template is
  /// touched (FR-053/FR-099).
  Future<void> delete(
    StoreKind kind,
    String id,
    DeleteConfirmation confirmation,
  );

  /// Creates a template aggregate.
  Future<StoredMeta> createTemplate(CreateTemplateRequest request);

  /// Atomically writes and read-back-verifies one immutable template version.
  Future<StoredMeta> saveTemplateVersion(SaveTemplateVersionRequest request);

  /// Loads a template and one immutable version, defaulting to the latest.
  ///
  /// Throws the same aggregate-scoped `SAVE-002` or global `SAVE-008` key
  /// errors as [loadDocument].
  Future<LoadedTemplate> loadTemplate(String templateId, {String? versionId});

  /// Returns the recovery state for one aggregate.
  Future<RecoveryStamp> recoveryStamp(String id, StoreKind kind);
}
