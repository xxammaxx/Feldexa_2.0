// T117 immutable template versions, derived-document pinning, and the
// "Vorlage verwenden" flow.
//
// Owner: `packages/feldexa_application/lib/src/templates/template_versions.dart`
// (T117).
// Normative sources:
//   * `spec.md` FR-059, FR-103, FR-104, FR-105, FR-060, and the FR-106
//     pattern;
//   * `data-model.md` §3.9–§3.11 — `TemplateOrigin` pins one immutable
//     version; versions are never rewritten; derived documents live in their
//     own aggregate;
//   * `contracts/ports.md` §2.4/§2.10 — `saveTemplateVersion` is atomic and
//     read-back-verified; `createDocument` writes the caller's first
//     revision;
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// `saveTemplateVersion` performs exactly one `SecureStorePort.saveTemplateVersion`
// call and reports success only when the returned metadata proves the new
// version head is readable and differs from the expected head (FR-106
// pattern). `useTemplate` loads the requested (default: latest, FR-105)
// version, builds a new independent document from the pinned version's
// layout snapshot with empty values, no signatures, no suggestions, and a
// `TemplateOrigin` pin (FR-059/FR-104), and creates it with exactly one
// `SecureStorePort.createDocument` call. Neither function mutates the
// template aggregate or any sibling document (FR-060); the template's
// deletion never touches the derived aggregate (FR-060/FR-099, T119).
//
// Snapshot fields are re-provenanced to `Provenance.template` in the derived
// document: the version snapshot carries no suggestions, so machine-provenance
// fields would violate the T058 suggestion/provenance cross-check. Layout
// (pages, geometry, field definitions, order) is copied unchanged.
//
// Failure results expose only a stable catalog code; no content passes
// through a result or a log line here.
library;

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';

import 'create_template_from_document.dart'
    show rejectForbiddenLayoutExtensions;

/// The outcome of [saveTemplateVersion].
final class SaveTemplateVersionResult {
  const SaveTemplateVersionResult._({
    required this.success,
    required this.meta,
    required this.errorCode,
  });

  /// Whether the new version was verified as durable.
  final bool success;

  /// The verified store read model, or null on failure.
  final StoredMeta? meta;

  /// Stable catalog code such as `SAVE-003`, or null on success.
  final String? errorCode;

  /// True iff [success].
  bool get isSuccess => success;

  @override
  String toString() {
    return 'SaveTemplateVersionResult(success: $success, '
        'errorCode: $errorCode)';
  }
}

/// Atomically saves one immutable template version (FR-103, FR-106 pattern).
///
/// Calls [SecureStorePort.saveTemplateVersion] exactly once with the caller's
/// [templateId] and [expectedHead]. Success requires all of: the call did not
/// throw, the returned [StoredMeta.id] equals [templateId], the metadata is
/// readable, and a non-null head exists that differs from [expectedHead]
/// (a null [expectedHead] is not a valid head for a version save: the first
/// version is written by [SecureStorePort.createTemplate]). Malformed
/// metadata fails as `SAVE-003` without exposing the unverified meta.
///
/// A [FeldexaException] maps to its exact catalog code; any other thrown
/// object maps to `SAVE-003`. No retry, follow-up write, or status
/// bookkeeping happens here.
Future<SaveTemplateVersionResult> saveTemplateVersion({
  required SecureStorePort store,
  required String templateId,
  required String expectedHead,
  required Iterable<Page> pageSnapshot,
  required Iterable<ConfirmedField> fieldSnapshot,
}) async {
  final SaveTemplateVersionRequest request = SaveTemplateVersionRequest(
    templateId: templateId,
    expectedHead: expectedHead,
    pageSnapshot: pageSnapshot,
    fieldSnapshot: fieldSnapshot,
  );
  rejectForbiddenLayoutExtensions(pageSnapshot, fieldSnapshot);

  try {
    final StoredMeta meta = await store.saveTemplateVersion(request);
    final String? latestVersionId = meta.latestRevisionId;
    final bool verified =
        meta.id == templateId &&
        meta.readable &&
        latestVersionId != null &&
        latestVersionId != expectedHead;
    if (!verified) {
      return const SaveTemplateVersionResult._(
        success: false,
        meta: null,
        errorCode: 'SAVE-003',
      );
    }
    return SaveTemplateVersionResult._(
      success: true,
      meta: meta,
      errorCode: null,
    );
  } on FeldexaException catch (error) {
    return SaveTemplateVersionResult._(
      success: false,
      meta: null,
      errorCode: error.code,
    );
  } catch (_) {
    // Unexpected failures fail closed. No detail is exposed.
    return const SaveTemplateVersionResult._(
      success: false,
      meta: null,
      errorCode: 'SAVE-003',
    );
  }
}

/// The outcome of [useTemplate].
final class UseTemplateResult {
  const UseTemplateResult._({
    required this.success,
    required this.meta,
    required this.pinnedVersionId,
    required this.pinnedVersionNumber,
    required this.content,
    required this.errorCode,
  });

  /// Whether the derived document was created and verified.
  final bool success;

  /// The verified store read model, or null on failure.
  final StoredMeta? meta;

  /// The pinned template version (FR-104), or null on failure.
  final String? pinnedVersionId;

  /// The display number of the pinned version, or 0 on failure.
  final int pinnedVersionNumber;

  /// The verified first revision content, or null on failure.
  final RevisionContent? content;

  /// Stable catalog code such as `SAVE-003`, or null on success.
  final String? errorCode;

  /// True iff [success].
  bool get isSuccess => success;

  @override
  String toString() {
    return 'UseTemplateResult(success: $success, errorCode: $errorCode, '
        'pinnedVersionNumber: $pinnedVersionNumber)';
  }
}

/// Creates a new independent document from a template version
/// (FR-059/FR-103/FR-104/FR-105).
///
/// Loads [templateId] at [versionId] (null selects the latest version,
/// FR-105), then calls [SecureStorePort.createDocument] exactly once with a
/// first revision that copies the pinned version's pages and layout fields,
/// carries empty values, no signatures, no suggestions, no verification
/// entries, and the `TemplateOrigin` pin (FR-059/FR-104). The layout of the
/// template aggregate is never mutated, and no sibling document is touched
/// (FR-060).
///
/// [documentId] and [initialRevisionId] must be fresh lowercase UUIDv4 ids
/// from the caller's id port. [source] is the template aggregate's immutable
/// source reference; the caller must have staged the source bytes under
/// `source.id` (the import port stages; this use case stages nothing).
/// [createdAt] must be UTC.
///
/// The [documentId] or title input is validated before any port call, so a
/// programmer error throws [ArgumentError] and performs no I/O; it is never
/// converted to `SAVE-003`. Load failures surface their exact catalog code;
/// any other thrown object maps to `SAVE-003`.
Future<UseTemplateResult> useTemplate({
  required SecureStorePort store,
  required String templateId,
  String? versionId,
  required String documentId,
  required String initialRevisionId,
  required RevisionKind initialKind,
  required String title,
  required DateTime createdAt,
  required SourceFileRef source,
}) async {
  final String checkedDocumentId = _requireUuidV4(documentId, 'documentId');
  final String checkedRevisionId = _requireUuidV4(
    initialRevisionId,
    'initialRevisionId',
  );
  _requireUtc(createdAt);

  try {
    final LoadedTemplate loaded = await store.loadTemplate(
      templateId,
      versionId: versionId,
    );
    final TemplateVersionContent snapshot = loaded.template.content;
    // Layout is copied; provenance is normalized to the pinned template so
    // the derived document's T058 cross-check holds without suggestions.
    final List<ConfirmedField> fields = <ConfirmedField>[
      for (final ConfirmedField field in snapshot.fieldSnapshot)
        field.provenance == Provenance.template
            ? field
            : ConfirmedField(
                id: field.id,
                pageIndex: field.pageIndex,
                rect: field.rect,
                type: field.type,
                provenance: Provenance.template,
                label: field.label,
                order: field.order,
                createdAt: field.createdAt,
                updatedAt: field.updatedAt,
                validation: field.validation,
              ),
    ];
    final TemplateOrigin origin = TemplateOrigin(
      templateId: templateId,
      templateVersionId: loaded.template.version.id,
      templateVersionNumber: loaded.template.version.versionNumber,
    );
    final RevisionContent content = RevisionContent(
      pages: snapshot.pageSnapshot,
      fields: fields,
      fieldOrder: snapshot.fieldOrder,
      templateOrigin: origin,
    );
    final Revision revision = Revision(
      id: checkedRevisionId,
      documentId: checkedDocumentId,
      kind: initialKind,
      createdAt: createdAt,
      plaintextSha256: crypto.sha256
          .convert(canonicalJsonBytes(content.toJson()))
          .toString(),
      content: content,
    );
    final StoredMeta meta = await store.createDocument(
      CreateDocumentRequest(
        documentId: checkedDocumentId,
        initialRevision: revision,
        title: title,
        source: source,
      ),
    );
    final String? latestRevisionId = meta.latestRevisionId;
    final bool verified =
        meta.id == checkedDocumentId &&
        meta.kind == StoreKind.document &&
        meta.readable &&
        latestRevisionId != null;
    if (!verified) {
      return const UseTemplateResult._(
        success: false,
        meta: null,
        pinnedVersionId: null,
        pinnedVersionNumber: 0,
        content: null,
        errorCode: 'SAVE-003',
      );
    }
    return UseTemplateResult._(
      success: true,
      meta: meta,
      pinnedVersionId: loaded.template.version.id,
      pinnedVersionNumber: loaded.template.version.versionNumber,
      content: content,
      errorCode: null,
    );
  } on FeldexaException catch (error) {
    return UseTemplateResult._(
      success: false,
      meta: null,
      pinnedVersionId: null,
      pinnedVersionNumber: 0,
      content: null,
      errorCode: error.code,
    );
  } catch (_) {
    // Unexpected failures fail closed. No detail is exposed.
    return UseTemplateResult._(
      success: false,
      meta: null,
      pinnedVersionId: null,
      pinnedVersionNumber: 0,
      content: null,
      errorCode: 'SAVE-003',
    );
  }
}

String _requireUuidV4(String value, String name) {
  final RegExp pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  if (!pattern.hasMatch(value)) {
    throw ArgumentError('$name must be a lowercase UUIDv4');
  }
  return value;
}

void _requireUtc(DateTime value) {
  if (!value.isUtc) {
    throw ArgumentError('timestamps must be UTC');
  }
}
