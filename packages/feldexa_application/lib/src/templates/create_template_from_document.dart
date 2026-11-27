// T115 "Als Vorlage speichern" use case.
//
// Owner: `packages/feldexa_application/lib/src/templates/create_template_from_document.dart`
// (T115).
// Normative sources:
//   * `spec.md` FR-054, FR-055, FR-056, FR-057, FR-061, and the FR-106
//     pattern — an explicit action, available only for a reviewed field
//     structure, that stores the original pages plus confirmed field
//     definitions and never any entered value or signature, and reports
//     success only after the stored template is confirmed readable;
//   * clarification 4 — templates are created only by this explicit action,
//     never automatically during import, analysis, save, or export (FR-061);
//   * `contracts/ports.md` §2.4/§2.10 — `SecureStorePort.createTemplate` is
//     atomic and read-back-verified, and typed `SAVE-*` failures keep their
//     exact catalog codes;
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// The use case performs exactly one `SecureStorePort.createTemplate` call.
// It keeps no state, retries nothing, and is never invoked by import,
// analysis, autosave, or export (FR-061): the only entry point is the
// explicit call below. `ConfirmedField` and `Page` have no value, signature,
// suggestion-resolution, or verification member by model, and the template
// aggregate refuses the corresponding payload keys, so passing the reviewed
// document snapshot's pages and fields through this use case cannot leak
// entered values or signatures (FR-056/FR-057).
//
// Failure results expose only a stable catalog code. No exception text,
// title, path, field value, or raw error detail is embedded in a result or
// logged here.
library;

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';

/// Whether a document snapshot's field structure is reviewed (FR-055).
enum TemplateStructureReadiness {
  /// Every suggestion is resolved and every user-added field has a
  /// verification state other than unreviewed.
  reviewed,

  /// At least one suggestion is unresolved, or at least one user-added field
  /// is still unreviewed.
  unreviewed,
}

/// Classifies [content] for FR-055.
///
/// The structure is reviewed exactly when no suggestion is still
/// `unresolved` (rejected and confirmed suggestions count as reviewed) and
/// every **user-added** field carries a verification entry whose state is not
/// `unreviewed`. Fields of machine provenance are covered by their
/// suggestion's resolution, and fields of [Provenance.template] are inherited
/// from a reviewed template version (FR-055 covers user-added fields only),
/// so neither may permanently block a derived document from being saved as a
/// template again.
TemplateStructureReadiness templateStructureReadiness(RevisionContent content) {
  for (final FieldSuggestion suggestion in content.suggestions) {
    if (suggestion.resolution == SuggestionResolution.unresolved) {
      return TemplateStructureReadiness.unreviewed;
    }
  }
  for (final ConfirmedField field in content.fields) {
    if (field.provenance == Provenance.user) {
      final FieldVerification? verification = content.verification[field.id];
      if (verification == null ||
          verification.state == FieldVerificationState.unreviewed) {
        return TemplateStructureReadiness.unreviewed;
      }
    }
  }
  return TemplateStructureReadiness.reviewed;
}

/// Rejects layout objects whose `unknownFields` extensions — at the top
/// level and on every modeled nested object (`PageGeometry` incl. CropBox,
/// `PageFailure`, `Rect`, `FieldValidation`) — carry forbidden template
/// payload keys (`values`, `signatures`, `suggestions`, `templateOrigin`).
///
/// The template decoders refuse these keys, so a tampered or future document
/// revision carrying them would otherwise turn the freshly written template
/// unreadable on the next load instead of failing closed at write time
/// (FR-057/SC-013, defense in depth). The guard throws
/// [CorruptDataException] (`SAVE-003`) rather than an [ArgumentError]: the
/// input comes from a persisted document snapshot, so this is a data-
/// integrity failure that the calling sheet reports through the regular
/// failure path, not a programmer error.
void rejectForbiddenLayoutExtensions(
  Iterable<Page> pages,
  Iterable<ConfirmedField> fields,
) {
  const Set<String> forbidden = <String>{
    'values',
    'signatures',
    'suggestions',
    'templateOrigin',
  };
  void check(Map<String, Object?> unknownFields, String what) {
    for (final String key in unknownFields.keys) {
      if (forbidden.contains(key)) {
        throw CorruptDataException();
      }
    }
  }

  for (final Page page in pages) {
    check(page.unknownFields, 'a page');
    check(page.geometry.unknownFields, 'a page geometry');
    check(page.geometry.cropBox.unknownFields, 'a crop box');
    if (page.failure != null) {
      check(page.failure!.unknownFields, 'a page failure');
    }
  }
  for (final ConfirmedField field in fields) {
    check(field.unknownFields, 'a confirmed field');
    check(field.rect.unknownFields, 'a field rectangle');
    check(field.validation.unknownFields, 'a field validation');
  }
}

/// The outcome of [createTemplateFromDocument].
///
/// A success always carries the verified [meta] and no [errorCode]; a failure
/// always carries a stable [errorCode] and no metadata. The constructor is
/// private so an optimistic-success or metadata-carrying failure state cannot
/// be built elsewhere.
final class CreateTemplateResult {
  const CreateTemplateResult._({
    required this.success,
    required this.meta,
    required this.errorCode,
  });

  /// Whether the template creation was verified as durable.
  final bool success;

  /// The verified store read model, or null on failure.
  final StoredMeta? meta;

  /// Stable catalog code such as `SAVE-003`, or null on success.
  final String? errorCode;

  /// True iff [success].
  bool get isSuccess => success;

  @override
  String toString() {
    // Content-free: catalog codes only, never metadata or exception detail.
    return 'CreateTemplateResult(success: $success, errorCode: $errorCode)';
  }
}

/// Creates a template from a reviewed document snapshot.
///
/// The [CreateTemplateRequest] is built from [content]'s pages, confirmed
/// fields, and field order before any port call, so an invalid [title] throws
/// an [ArgumentError] and performs no I/O; this programmer-error path is never
/// converted to `SAVE-003`. [content] is passed by identity and never mutated,
/// and the request carries no value, signature, or verification data because
/// the template DTOs have no such member (FR-057).
///
/// Calls [SecureStorePort.createTemplate] exactly once. Success requires all
/// of: the call did not throw, the returned [StoredMeta.id] equals the id the
/// caller will use, the metadata is readable, its kind is [StoreKind.template],
/// and a non-null [StoredMeta.latestRevisionId] (the first immutable template
/// version) exists. Malformed metadata fails as `SAVE-003` without exposing
/// the unverified meta.
///
/// A [FeldexaException] maps to its exact catalog code. Any other thrown
/// object maps to `SAVE-003`. This function performs no retry, follow-up
/// write, or status bookkeeping.
Future<CreateTemplateResult> createTemplateFromDocument({
  required SecureStorePort store,
  required String title,
  required SourceFileRef source,
  required RevisionContent content,
}) async {
  final CreateTemplateRequest request = CreateTemplateRequest(
    title: title,
    source: source,
    pages: content.pages,
    fields: content.fields,
    fieldOrder: content.fieldOrder,
  );
  try {
    rejectForbiddenLayoutExtensions(content.pages, content.fields);
    final StoredMeta meta = await store.createTemplate(request);
    final String? latestVersionId = meta.latestRevisionId;
    final bool verified =
        meta.kind == StoreKind.template &&
        meta.readable &&
        latestVersionId != null;
    if (!verified) {
      return const CreateTemplateResult._(
        success: false,
        meta: null,
        errorCode: 'SAVE-003',
      );
    }
    return CreateTemplateResult._(success: true, meta: meta, errorCode: null);
  } on FeldexaException catch (error) {
    return CreateTemplateResult._(
      success: false,
      meta: null,
      errorCode: error.code,
    );
  } catch (_) {
    // Unexpected failures fail closed. No detail is exposed.
    return const CreateTemplateResult._(
      success: false,
      meta: null,
      errorCode: 'SAVE-003',
    );
  }
}
