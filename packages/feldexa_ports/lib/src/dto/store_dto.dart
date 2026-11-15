// T013 `SecureStorePort` request and result DTOs.
//
// Owner: `packages/feldexa_ports/lib/src/dto/store_dto.dart` (T013).
// Normative sources:
//   * `contracts/ports.md` §2.4, §2.10, and §4 — the store interface, its list
//     read model, and the write requests;
//   * `contracts/storage-format.md` — encrypted objects, verified revisions,
//     and recovery stamps;
//   * `data-model.md` §3.13 — durable heads and recovery.
//
// Canonical `DocumentMeta`, `Page`, `ConfirmedField`, `RevisionContent`,
// `RevisionKind`, `SourceFileRef`, and `StoredTemplate` come from
// `feldexa_core`; this file must not redeclare them. `StoredMeta` is the single
// port-level list read model, not a second persisted document type (T095).

import 'dart:typed_data';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/evidence.dart';

import 'validation.dart';

/// The two encrypted storage aggregates (`contracts/ports.md` §2.4).
enum StoreKind {
  /// A working document derived from an imported source.
  document,

  /// A reusable template aggregate.
  template,
}

/// Store health and capacity (`contracts/ports.md` §2.4).
///
/// A missing key does not throw for the whole store; [keyAvailable] is a
/// non-fatal summary that can be false for aggregate-scoped `SAVE-002` or
/// global `SAVE-008`. It does not identify the scope; loads throw the matching
/// typed exception (FR-052).
final class StoreStatus {
  /// Creates a store-status result.
  ///
  /// [objectCount] and [totalBytes] must be non-negative. Invalid values throw
  /// a safe [ArgumentError].
  factory StoreStatus({
    required bool keyAvailable,
    required int objectCount,
    required int totalBytes,
    required CapabilityEvidence evidence,
  }) {
    return StoreStatus._(
      keyAvailable: keyAvailable,
      objectCount: requireNonNegativeInt(objectCount, 'objectCount'),
      totalBytes: requireNonNegativeInt(totalBytes, 'totalBytes'),
      evidence: evidence,
    );
  }

  const StoreStatus._({
    required this.keyAvailable,
    required this.objectCount,
    required this.totalBytes,
    required this.evidence,
  });

  /// Whether the device key material is available for this store.
  final bool keyAvailable;

  /// Number of stored objects.
  final int objectCount;

  /// Total encrypted bytes stored.
  final int totalBytes;

  /// Evidence class of the adapter that produced this status.
  final CapabilityEvidence evidence;

  @override
  String toString() {
    return 'StoreStatus(keyAvailable: $keyAvailable, '
        'objectCount: $objectCount, totalBytes: $totalBytes)';
  }
}

/// The port-level list read model (`contracts/ports.md` §2.4).
///
/// It is projected from a persisted `DocumentMeta` or `TemplateMeta`; the UI's
/// `DocumentSummary` is a derived projection of this type plus counts, not a
/// second persisted record (T095).
final class StoredMeta {
  /// Creates a list entry.
  ///
  /// [id] and [latestRevisionId] are lowercase UUIDv4 values, [title] is 1–200
  /// characters after trimming, and timestamps are UTC. A readable entry must
  /// not carry an [unreadableReasonCode]; an unreadable entry may omit it when
  /// the failure has no specific catalog key. Invalid values throw a safe
  /// [ArgumentError] that does not echo the title.
  factory StoredMeta({
    required String id,
    required StoreKind kind,
    required String title,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? latestRevisionId,
    DateTime? lastDurableAt,
    bool readable = true,
    String? unreadableReasonCode,
  }) {
    final String checkedId = requireUuidV4(id, 'id');
    final String checkedTitle = requireTitle(title);
    final DateTime checkedCreated = requireUtc(createdAt, 'createdAt');
    final DateTime checkedUpdated = requireUtc(updatedAt, 'updatedAt');
    final String? checkedRevision = optionalUuidV4(
      latestRevisionId,
      'latestRevisionId',
    );
    final DateTime? checkedDurable = optionalUtc(
      lastDurableAt,
      'lastDurableAt',
    );
    if (readable && unreadableReasonCode != null) {
      throw ArgumentError(
        'unreadableReasonCode must be null when readable is true',
      );
    }
    final String? checkedReason = unreadableReasonCode == null
        ? null
        : requireCatalogCode(unreadableReasonCode, 'unreadableReasonCode');
    return StoredMeta._(
      id: checkedId,
      kind: kind,
      title: checkedTitle,
      createdAt: checkedCreated,
      updatedAt: checkedUpdated,
      latestRevisionId: checkedRevision,
      lastDurableAt: checkedDurable,
      readable: readable,
      unreadableReasonCode: checkedReason,
    );
  }

  const StoredMeta._({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.latestRevisionId,
    required this.lastDurableAt,
    required this.readable,
    required this.unreadableReasonCode,
  });

  /// UUIDv4 of the document or template aggregate.
  final String id;

  /// Which aggregate this entry describes.
  final StoreKind kind;

  /// User-visible German title.
  final String title;

  /// When the aggregate was created, in UTC.
  final DateTime createdAt;

  /// When the aggregate was last updated, in UTC.
  final DateTime updatedAt;

  /// UUIDv4 of the latest revision or template version, when known.
  final String? latestRevisionId;

  /// When the last verified durable commit happened, in UTC.
  final DateTime? lastDurableAt;

  /// Whether the aggregate can currently be loaded.
  final bool readable;

  /// Catalog code explaining an unreadable aggregate, for example `SAVE-002`
  /// (aggregate-scoped) or `SAVE-008` (global provider/reset).
  final String? unreadableReasonCode;

  @override
  String toString() {
    return 'StoredMeta(kind: ${kind.name}, readable: $readable, '
        'titleLength: ${title.length})';
  }
}

/// A decrypted, verified document load (`contracts/ports.md` §2.4).
///
/// [sourceBytes] is decrypted, bounded, and owned by the caller after the
/// return; the adapter keeps no path or file handle in the result.
final class LoadedDocument {
  /// Creates a loaded document.
  ///
  /// [sourceBytes] must be non-empty. Invalid values throw a safe
  /// [ArgumentError].
  factory LoadedDocument({
    required DocumentMeta meta,
    required RevisionContent content,
    required Uint8List sourceBytes,
    required CapabilityEvidence evidence,
  }) {
    if (sourceBytes.isEmpty) {
      throw ArgumentError('sourceBytes must contain the decrypted source');
    }
    return LoadedDocument._(
      meta: meta,
      content: content,
      sourceBytes: sourceBytes,
      evidence: evidence,
    );
  }

  const LoadedDocument._({
    required this.meta,
    required this.content,
    required this.sourceBytes,
    required this.evidence,
  });

  /// Persisted document metadata.
  final DocumentMeta meta;

  /// The current revision snapshot.
  final RevisionContent content;

  /// Decrypted source bytes; the caller must release them.
  final Uint8List sourceBytes;

  /// Evidence class of the adapter that produced this load.
  final CapabilityEvidence evidence;

  @override
  String toString() {
    return 'LoadedDocument(pageCount: ${content.pageCount}, '
        'sourceBytesLength: ${sourceBytes.length})';
  }
}

/// A decrypted, verified template load (`contracts/ports.md` §2.10).
final class LoadedTemplate {
  /// Creates a loaded template.
  ///
  /// [sourceBytes] must be non-empty. Invalid values throw a safe
  /// [ArgumentError].
  factory LoadedTemplate({
    required StoredTemplate template,
    required Uint8List sourceBytes,
    required CapabilityEvidence evidence,
  }) {
    if (sourceBytes.isEmpty) {
      throw ArgumentError('sourceBytes must contain the decrypted source');
    }
    return LoadedTemplate._(
      template: template,
      sourceBytes: sourceBytes,
      evidence: evidence,
    );
  }

  const LoadedTemplate._({
    required this.template,
    required this.sourceBytes,
    required this.evidence,
  });

  /// The canonical template aggregate projection.
  final StoredTemplate template;

  /// Decrypted source bytes; the caller must release them.
  final Uint8List sourceBytes;

  /// Evidence class of the adapter that produced this load.
  final CapabilityEvidence evidence;

  @override
  String toString() {
    return 'LoadedTemplate(versionNumber: '
        '${template.version.versionNumber}, '
        'sourceBytesLength: ${sourceBytes.length})';
  }
}

/// Creates a document for an already staged source (`contracts/ports.md`
/// §2.10).
final class CreateDocumentRequest {
  /// Creates a document-creation request.
  ///
  /// [title] is 1–200 characters after trimming. Invalid values throw a safe
  /// [ArgumentError] that does not echo the title.
  factory CreateDocumentRequest({
    required String title,
    required SourceFileRef source,
  }) {
    return CreateDocumentRequest._(title: requireTitle(title), source: source);
  }

  const CreateDocumentRequest._({required this.title, required this.source});

  /// User-visible German title.
  final String title;

  /// The immutable encrypted source already staged by the importer.
  final SourceFileRef source;

  @override
  String toString() {
    return 'CreateDocumentRequest(titleLength: ${title.length})';
  }
}

/// Saves one atomic revision of a document (`contracts/ports.md` §2.10).
final class SaveRevisionRequest {
  /// Creates a revision-save request.
  ///
  /// [documentId] is a lowercase UUIDv4 and [expectedHead], when present, is
  /// the UUIDv4 of the last verified head. [expectedHead] is null only before
  /// the first revision. Invalid values throw a safe [ArgumentError].
  factory SaveRevisionRequest({
    required String documentId,
    String? expectedHead,
    required RevisionContent content,
    required RevisionKind kind,
  }) {
    return SaveRevisionRequest._(
      documentId: requireUuidV4(documentId, 'documentId'),
      expectedHead: optionalUuidV4(expectedHead, 'expectedHead'),
      content: content,
      kind: kind,
    );
  }

  const SaveRevisionRequest._({
    required this.documentId,
    required this.expectedHead,
    required this.content,
    required this.kind,
  });

  /// UUIDv4 of the document to save.
  final String documentId;

  /// UUIDv4 of the last verified head, or null before the first revision.
  final String? expectedHead;

  /// The full snapshot to commit.
  final RevisionContent content;

  /// Why this revision is written.
  final RevisionKind kind;

  @override
  String toString() {
    return 'SaveRevisionRequest(kind: ${kind.wireName}, '
        'pageCount: ${content.pageCount})';
  }
}

/// Creates a template aggregate (`contracts/ports.md` §2.10).
final class CreateTemplateRequest {
  /// Creates a template-creation request.
  ///
  /// [title] is 1–200 characters after trimming and [pages] must contain at
  /// least one page. Invalid values throw a safe [ArgumentError] that does not
  /// echo the title or any label.
  factory CreateTemplateRequest({
    required String title,
    required SourceFileRef source,
    required Iterable<Page> pages,
    Iterable<ConfirmedField> fields = const <ConfirmedField>[],
    required Iterable<String> fieldOrder,
  }) {
    final List<Page> pageList = freezeList<Page>(pages);
    if (pageList.isEmpty) {
      throw ArgumentError('pages must contain at least one page');
    }
    return CreateTemplateRequest._(
      title: requireTitle(title),
      source: source,
      pages: pageList,
      fields: freezeList<ConfirmedField>(fields),
      fieldOrder: freezeList<String>(fieldOrder),
    );
  }

  const CreateTemplateRequest._({
    required this.title,
    required this.source,
    required this.pages,
    required this.fields,
    required this.fieldOrder,
  });

  /// User-visible German title.
  final String title;

  /// The immutable encrypted source already staged by the importer.
  final SourceFileRef source;

  /// Template pages, ordered contiguously from index 0.
  final List<Page> pages;

  /// Confirmed fields to copy into the template.
  final List<ConfirmedField> fields;

  /// Confirmed field ids in user-visible order.
  final List<String> fieldOrder;

  @override
  String toString() {
    return 'CreateTemplateRequest(titleLength: ${title.length}, '
        'pages: ${pages.length}, fields: ${fields.length})';
  }
}

/// Saves one immutable template version (`contracts/ports.md` §2.10).
final class SaveTemplateVersionRequest {
  /// Creates a template-version save request.
  ///
  /// [templateId] is a lowercase UUIDv4, [expectedHead] is the UUIDv4 of the
  /// current version head when present, and [pageSnapshot] must contain at
  /// least one page. Invalid values throw a safe [ArgumentError].
  factory SaveTemplateVersionRequest({
    required String templateId,
    String? expectedHead,
    required Iterable<Page> pageSnapshot,
    Iterable<ConfirmedField> fieldSnapshot = const <ConfirmedField>[],
  }) {
    final List<Page> pages = freezeList<Page>(pageSnapshot);
    if (pages.isEmpty) {
      throw ArgumentError('pageSnapshot must contain at least one page');
    }
    return SaveTemplateVersionRequest._(
      templateId: requireUuidV4(templateId, 'templateId'),
      expectedHead: optionalUuidV4(expectedHead, 'expectedHead'),
      pageSnapshot: pages,
      fieldSnapshot: freezeList<ConfirmedField>(fieldSnapshot),
    );
  }

  const SaveTemplateVersionRequest._({
    required this.templateId,
    required this.expectedHead,
    required this.pageSnapshot,
    required this.fieldSnapshot,
  });

  /// UUIDv4 of the template aggregate.
  final String templateId;

  /// UUIDv4 of the current version head, or null before the first version.
  final String? expectedHead;

  /// Pages captured into the new version.
  final List<Page> pageSnapshot;

  /// Confirmed fields captured into the new version.
  final List<ConfirmedField> fieldSnapshot;

  @override
  String toString() {
    return 'SaveTemplateVersionRequest(pages: ${pageSnapshot.length}, '
        'fields: ${fieldSnapshot.length})';
  }
}

/// Writes one signature image asset (`contracts/ports.md` §2.10).
final class WriteSignatureRequest {
  /// Creates a signature-write request.
  ///
  /// [documentId] and [assetId] are lowercase UUIDv4 values, [bytes] is
  /// non-empty, and [sha256] is the 64-character lowercase digest of [bytes].
  /// Invalid values throw a safe [ArgumentError] that does not echo bytes.
  factory WriteSignatureRequest({
    required String documentId,
    required String assetId,
    required Uint8List bytes,
    required String sha256,
  }) {
    if (bytes.isEmpty) {
      throw ArgumentError('bytes must contain the signature image');
    }
    return WriteSignatureRequest._(
      documentId: requireUuidV4(documentId, 'documentId'),
      assetId: requireUuidV4(assetId, 'assetId'),
      bytes: bytes,
      sha256: requireSha256(sha256, 'sha256'),
    );
  }

  const WriteSignatureRequest._({
    required this.documentId,
    required this.assetId,
    required this.bytes,
    required this.sha256,
  });

  /// UUIDv4 of the owning document.
  final String documentId;

  /// UUIDv4 of the signature asset.
  final String assetId;

  /// PNG bytes of the signature image.
  final Uint8List bytes;

  /// SHA-256 of [bytes].
  final String sha256;

  @override
  String toString() {
    return 'WriteSignatureRequest(bytesLength: ${bytes.length})';
  }
}

/// Explicit user confirmation for a destructive delete
/// (`contracts/ports.md` §2.4).
///
/// The adapter must refuse a delete unless [acknowledged] is true and [title]
/// names the item; the DTO itself carries the user's explicit input.
final class DeleteConfirmation {
  /// Creates a delete confirmation.
  ///
  /// [title] is 1–200 characters after trimming. Invalid values throw a safe
  /// [ArgumentError] that does not echo the title.
  factory DeleteConfirmation({
    required String title,
    required bool acknowledged,
  }) {
    return DeleteConfirmation._(
      title: requireTitle(title),
      acknowledged: acknowledged,
    );
  }

  const DeleteConfirmation._({required this.title, required this.acknowledged});

  /// User-visible German title of the item being deleted.
  final String title;

  /// Whether the user explicitly confirmed the deletion.
  final bool acknowledged;

  @override
  String toString() {
    return 'DeleteConfirmation(titleLength: ${title.length}, '
        'acknowledged: $acknowledged)';
  }
}

/// Durability information after a store recovery (`contracts/ports.md` §2.4).
final class RecoveryStamp {
  /// Creates a recovery stamp.
  ///
  /// [verifiedRevisionId], when present, is a lowercase UUIDv4 and
  /// [committedAt], when present, is UTC. Invalid values throw a safe
  /// [ArgumentError].
  factory RecoveryStamp({
    String? verifiedRevisionId,
    DateTime? committedAt,
    required bool headCorrupt,
    required bool fellBackToOlderRevision,
  }) {
    return RecoveryStamp._(
      verifiedRevisionId: optionalUuidV4(
        verifiedRevisionId,
        'verifiedRevisionId',
      ),
      committedAt: optionalUtc(committedAt, 'committedAt'),
      headCorrupt: headCorrupt,
      fellBackToOlderRevision: fellBackToOlderRevision,
    );
  }

  const RecoveryStamp._({
    required this.verifiedRevisionId,
    required this.committedAt,
    required this.headCorrupt,
    required this.fellBackToOlderRevision,
  });

  /// UUIDv4 of the last revision whose read-back verification succeeded.
  final String? verifiedRevisionId;

  /// When the verified revision was committed, in UTC.
  final DateTime? committedAt;

  /// Whether the head pointer was found corrupt.
  final bool headCorrupt;

  /// Whether recovery had to use an older revision than the head.
  final bool fellBackToOlderRevision;

  @override
  String toString() {
    return 'RecoveryStamp(headCorrupt: $headCorrupt, '
        'fellBackToOlderRevision: $fellBackToOlderRevision)';
  }
}
