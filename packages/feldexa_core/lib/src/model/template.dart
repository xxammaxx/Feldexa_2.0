// Feldexa core template model (T021).
//
// Owner: `packages/feldexa_core/lib/src/model/template.dart` (T021).
// Normative sources:
//   * `spec.md` FR-101–FR-106 — layout-only editing, immutable versions,
//     pinned derived documents, use of the latest version, and the document
//     save atomicity rule applied to template saves;
//   * `data-model.md` §3.10–§3.11 — `Template` and `TemplateVersion`;
//   * `data-model.md` §4.1 — `TemplateMeta`, `TemplateVersionContent`, and
//     `StoredTemplate` are the template envelopes and read model;
//   * `data-model.md` §5–§6 — field-order/containment invariants, canonical
//     JSON, schema-version refusal, and same-schema unknown-field retention;
//   * `contracts/storage-format.md` §2.4 and §3.3 — the `meta.fx1` and
//     `ver/<versionId>.fx1` plaintext formats and the immutable version commit;
//   * `contracts/ports.md` §2.4 and §2.10 — the storage-port template shapes and
//     the `StoredTemplate` that `loadTemplate` returns.
//
// The document-side `TemplateOrigin` pin is T017-owned and deliberately not
// redeclared here (`data-model.md` §3.9): a template never embeds the origin of
// the document it was derived from.
//
// Every type is immutable and validates in release builds. Templates are
// layout-only: no type in this file has a field-value or signature member, so a
// template can never store field content (FR-102/SC-013). A save appends a new
// immutable `TemplateVersion`; existing versions are never modified (FR-103) and
// derived documents keep their own pinned version (FR-104). New documents read
// `latestVersion` (FR-105). Errors and `Object.toString` never echo a title or
// label.
//
// Templates and their versions are not persisted as one JSON document: the
// canonical on-disk payloads are `TemplateMeta` (`meta.fx1`) and
// `TemplateVersionContent` (`ver/<versionId>.fx1`). `Template`,
// `TemplateVersion`, and `TemplateVersionPointer` carry JSON round-trips as
// canonical in-memory projections of those payloads; `StoredTemplate` is the
// verified in-memory join and is intentionally not serializable.

library;

import 'canonical_json.dart';
import 'document.dart';
import 'field.dart';

/// The template schema version accepted by this build (`data-model.md` §6).
const int templateSchemaVersion = 1;

/// A pointer to one immutable template version (`data-model.md` §3.10–§3.11).
///
/// The pointer is what `TemplateMeta` (`meta.fx1`) lists and what
/// `head.fx1` mirrors. It carries the version identity, the one-based display
/// number, and the version creation time; the payload lives in
/// `ver/<versionId>.fx1` and the verified hash in the version record.
/// Unknown same-schema JSON fields are retained across a read/write round
/// (`data-model.md` §6).
final class TemplateVersionPointer extends JsonObject {
  /// Creates a version pointer.
  ///
  /// [versionId] must be a lowercase UUIDv4, [versionNumber] at least 1, and
  /// [createdAt] UTC. [unknownFields] are opaque same-schema JSON extensions
  /// retained for a later write.
  ///
  /// Throws [ArgumentError] for every invalid value.
  factory TemplateVersionPointer({
    required String versionId,
    required int versionNumber,
    required DateTime createdAt,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    return TemplateVersionPointer._(
      versionId: _validateUuidV4(versionId, 'versionId'),
      versionNumber: _validateVersionNumber(versionNumber),
      createdAt: _checkUtc(createdAt, 'createdAt'),
      unknownFields: freezeUnknownJsonFields(unknownFields),
    );
  }

  const TemplateVersionPointer._({
    required this.versionId,
    required this.versionNumber,
    required this.createdAt,
    required super.unknownFields,
  });

  /// Reads a persisted version pointer.
  ///
  /// Unknown same-schema keys are retained for a later write.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  factory TemplateVersionPointer.fromJson(Map<String, Object?> json) {
    try {
      return TemplateVersionPointer(
        versionId: _readString(json, 'versionId'),
        versionNumber: _readInt(json, 'versionNumber'),
        createdAt: parseCanonicalUtcTimestamp(
          json['createdAt'],
          name: 'createdAt',
        ),
        unknownFields: unknownJsonFields(json, _templateVersionPointerJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException(
        'Invalid template version pointer JSON: ${error.message}',
      );
    }
  }

  /// UUIDv4 of the immutable version.
  final String versionId;

  /// One-based version number, strictly increasing per template.
  final int versionNumber;

  /// Version creation time in UTC.
  final DateTime createdAt;

  /// Returns a copy with the supplied fields replaced.
  ///
  /// The result is revalidated by the public constructor.
  TemplateVersionPointer copyWith({
    String? versionId,
    int? versionNumber,
    DateTime? createdAt,
    Map<String, Object?>? unknownFields,
  }) {
    return TemplateVersionPointer(
      versionId: versionId ?? this.versionId,
      versionNumber: versionNumber ?? this.versionNumber,
      createdAt: createdAt ?? this.createdAt,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  /// Serializes the pointer.
  ///
  /// Unknown same-schema fields are emitted beneath the modeled keys.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'versionId': versionId,
      'versionNumber': versionNumber,
      'createdAt': canonicalUtcTimestamp(createdAt),
    });
  }

  @override
  bool operator ==(Object other) {
    return other is TemplateVersionPointer &&
        other.versionId == versionId &&
        other.versionNumber == versionNumber &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode {
    return Object.hash(versionId, versionNumber, createdAt);
  }

  @override
  String toString() {
    return 'TemplateVersionPointer(versionNumber: $versionNumber)';
  }
}

/// The canonical plaintext payload of `ver/<versionId>.fx1`
/// (`data-model.md` §3.11, `contracts/storage-format.md` §2.4).
///
/// A version content holds only the page geometry snapshot, the layout-only
/// field snapshot, the user-visible field order, and the schema version. It has
/// no value, signature, suggestion, verification, or template-origin member, so
/// template content can never carry filled data (FR-102/SC-013). Unknown
/// same-schema JSON fields are retained across a read/write round
/// (`data-model.md` §6).
final class TemplateVersionContent extends JsonObject {
  /// Creates and validates a version content payload.
  ///
  /// [pageSnapshot] must be non-empty and ordered contiguously from index 0.
  /// Fields must have unique ids, reference an existing page, and fit that
  /// page's display box. [fieldOrder] must be a permutation of the field ids
  /// whose field `order` equals the field's position. [schemaVersion] must be
  /// [templateSchemaVersion]. [unknownFields] are opaque same-schema JSON
  /// extensions retained for a later write.
  ///
  /// Throws [ArgumentError] for every invalid value. The error never echoes a
  /// label.
  factory TemplateVersionContent({
    required Iterable<Page> pageSnapshot,
    Iterable<ConfirmedField> fieldSnapshot = const <ConfirmedField>[],
    required Iterable<String> fieldOrder,
    int schemaVersion = templateSchemaVersion,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    if (schemaVersion != templateSchemaVersion) {
      throw ArgumentError('schemaVersion must be $templateSchemaVersion');
    }
    final List<Page> pages = _checkedPages(pageSnapshot);
    final List<ConfirmedField> fields = _checkedFields(
      pages: pages,
      fields: fieldSnapshot,
      fieldOrder: fieldOrder,
    );
    return TemplateVersionContent._(
      schemaVersion: schemaVersion,
      pageSnapshot: pages,
      fieldSnapshot: fields,
      fieldOrder: List<String>.unmodifiable(fieldOrder.toList(growable: false)),
      unknownFields: freezeUnknownJsonFields(unknownFields),
    );
  }

  const TemplateVersionContent._({
    required this.schemaVersion,
    required this.pageSnapshot,
    required this.fieldSnapshot,
    required this.fieldOrder,
    required super.unknownFields,
  });

  /// Reads a persisted version content payload.
  ///
  /// Only [templateSchemaVersion] is accepted; a higher version fails closed so
  /// the caller can refuse to save without data loss (FR-044/`data-model.md`
  /// §6). Unknown same-schema keys are retained for a later write.
  ///
  /// Throws [FormatException] for missing, mistyped, invalid, or unsupported
  /// fields.
  factory TemplateVersionContent.fromJson(Map<String, Object?> json) {
    final Object? rawSchemaVersion = json['schemaVersion'];
    if (rawSchemaVersion is! int) {
      throw const FormatException(
        'JSON field "schemaVersion" must be an integer',
      );
    }
    if (rawSchemaVersion != templateSchemaVersion) {
      throw FormatException(
        'Unsupported template version schema version $rawSchemaVersion',
      );
    }
    try {
      return TemplateVersionContent(
        schemaVersion: rawSchemaVersion,
        pageSnapshot: _readObjectList(
          json,
          'pageSnapshot',
        ).map(Page.fromJson).toList(growable: false),
        fieldSnapshot: _readObjectList(
          json,
          'fieldSnapshot',
        ).map(ConfirmedField.fromJson).toList(growable: false),
        fieldOrder: _readStringList(json, 'fieldOrder'),
        unknownFields: unknownJsonFields(json, _templateVersionContentJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException(
        'Invalid template version content JSON: ${error.message}',
      );
    }
  }

  /// The template schema version.
  final int schemaVersion;

  /// The page geometry snapshot, ordered contiguously from index 0.
  final List<Page> pageSnapshot;

  /// The layout-only field snapshot, in [fieldOrder] order.
  final List<ConfirmedField> fieldSnapshot;

  /// Field ids in user-visible order.
  final List<String> fieldOrder;

  /// Returns a copy with the supplied fields replaced.
  ///
  /// The caller must supply a consistent combination (for example, fields and
  /// fieldOrder together) because the public constructor revalidates every
  /// invariant.
  TemplateVersionContent copyWith({
    Iterable<Page>? pageSnapshot,
    Iterable<ConfirmedField>? fieldSnapshot,
    Iterable<String>? fieldOrder,
    int? schemaVersion,
    Map<String, Object?>? unknownFields,
  }) {
    return TemplateVersionContent(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      pageSnapshot: pageSnapshot ?? this.pageSnapshot,
      fieldSnapshot: fieldSnapshot ?? this.fieldSnapshot,
      fieldOrder: fieldOrder ?? this.fieldOrder,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  /// Serializes the persisted `ver/<versionId>.fx1` payload.
  ///
  /// Use [canonicalJsonEncode] on this map for the canonical byte form whose
  /// SHA-256 the version record stores. Unknown same-schema fields are emitted
  /// beneath the modeled keys at the root; nested objects emit their own
  /// retained fields.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'schemaVersion': schemaVersion,
      'pageSnapshot': <Map<String, Object?>>[
        for (final Page page in pageSnapshot) page.toJson(),
      ],
      'fieldSnapshot': <Map<String, Object?>>[
        for (final ConfirmedField field in fieldSnapshot) field.toJson(),
      ],
      'fieldOrder': List<String>.unmodifiable(fieldOrder),
    });
  }

  @override
  bool operator ==(Object other) {
    return other is TemplateVersionContent &&
        other.schemaVersion == schemaVersion &&
        _listsEqual<Page>(other.pageSnapshot, pageSnapshot) &&
        _listsEqual<ConfirmedField>(other.fieldSnapshot, fieldSnapshot) &&
        _listsEqual<String>(other.fieldOrder, fieldOrder);
  }

  @override
  int get hashCode {
    return Object.hash(
      schemaVersion,
      Object.hashAll(pageSnapshot),
      Object.hashAll(fieldSnapshot),
      Object.hashAll(fieldOrder),
    );
  }

  @override
  String toString() {
    return 'TemplateVersionContent(pages: ${pageSnapshot.length}, '
        'fields: ${fieldSnapshot.length})';
  }
}

/// One immutable template version (`data-model.md` §3.11).
///
/// The version record composes the stored pointer data (identity, one-based
/// number, creation time), the layout snapshots, and the verified SHA-256 of the
/// canonical plaintext `TemplateVersionContent`. Saving template changes creates
/// a new version; an existing version is never rewritten (FR-103).
/// Unknown same-schema JSON fields are retained across a read/write round
/// (`data-model.md` §6).
final class TemplateVersion extends JsonObject {
  /// Creates a version record.
  ///
  /// [id] and [templateId] must be lowercase UUIDv4 values, [versionNumber] at
  /// least 1, and [createdAt] UTC. [sha256] must be 64 lowercase hexadecimal
  /// characters. [pageSnapshot] must be non-empty and ordered contiguously from
  /// index 0. Fields must have unique ids, reference an existing page, fit that
  /// page's display box, and carry unique, contiguous `order` values.
  /// [unknownFields] are opaque same-schema JSON extensions retained for a
  /// later write.
  ///
  /// Throws [ArgumentError] for every invalid value. The error never echoes a
  /// label.
  factory TemplateVersion({
    required String id,
    required String templateId,
    required int versionNumber,
    required DateTime createdAt,
    Iterable<ConfirmedField> fieldSnapshot = const <ConfirmedField>[],
    required Iterable<Page> pageSnapshot,
    required String sha256,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    final List<Page> pages = _checkedPages(pageSnapshot);
    final List<ConfirmedField> fields = _checkedVersionFieldSnapshot(
      pages: pages,
      fields: fieldSnapshot,
    );
    return TemplateVersion._(
      id: _validateUuidV4(id, 'id'),
      templateId: _validateUuidV4(templateId, 'templateId'),
      versionNumber: _validateVersionNumber(versionNumber),
      createdAt: _checkUtc(createdAt, 'createdAt'),
      fieldSnapshot: fields,
      pageSnapshot: pages,
      sha256: _validateSha256(sha256, 'sha256'),
      unknownFields: freezeUnknownJsonFields(unknownFields),
    );
  }

  const TemplateVersion._({
    required this.id,
    required this.templateId,
    required this.versionNumber,
    required this.createdAt,
    required this.fieldSnapshot,
    required this.pageSnapshot,
    required this.sha256,
    required super.unknownFields,
  });

  /// Reads a persisted version record.
  ///
  /// The on-disk `ver/<versionId>.fx1` payload is [TemplateVersionContent]; an
  /// adapter composes this record from the metadata pointer, the verified
  /// content hash, and the content snapshots. Unknown same-schema keys are
  /// retained for a later write.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  factory TemplateVersion.fromJson(Map<String, Object?> json) {
    try {
      return TemplateVersion(
        id: _readString(json, 'id'),
        templateId: _readString(json, 'templateId'),
        versionNumber: _readInt(json, 'versionNumber'),
        createdAt: parseCanonicalUtcTimestamp(
          json['createdAt'],
          name: 'createdAt',
        ),
        fieldSnapshot: _readObjectList(
          json,
          'fieldSnapshot',
        ).map(ConfirmedField.fromJson).toList(growable: false),
        pageSnapshot: _readObjectList(
          json,
          'pageSnapshot',
        ).map(Page.fromJson).toList(growable: false),
        sha256: _readString(json, 'sha256'),
        unknownFields: unknownJsonFields(json, _templateVersionJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid template version JSON: ${error.message}');
    }
  }

  /// UUIDv4 of this immutable version.
  final String id;

  /// UUIDv4 of the parent template.
  final String templateId;

  /// One-based version number, strictly increasing per template.
  final int versionNumber;

  /// Version creation time in UTC.
  final DateTime createdAt;

  /// The layout-only field snapshot, sorted by `order`.
  final List<ConfirmedField> fieldSnapshot;

  /// The page geometry snapshot, ordered contiguously from index 0.
  final List<Page> pageSnapshot;

  /// SHA-256 of the canonical plaintext [TemplateVersionContent].
  final String sha256;

  /// Returns a copy with the supplied fields replaced.
  ///
  /// The result is revalidated by the public constructor.
  TemplateVersion copyWith({
    String? id,
    String? templateId,
    int? versionNumber,
    DateTime? createdAt,
    Iterable<ConfirmedField>? fieldSnapshot,
    Iterable<Page>? pageSnapshot,
    String? sha256,
    Map<String, Object?>? unknownFields,
  }) {
    return TemplateVersion(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      versionNumber: versionNumber ?? this.versionNumber,
      createdAt: createdAt ?? this.createdAt,
      fieldSnapshot: fieldSnapshot ?? this.fieldSnapshot,
      pageSnapshot: pageSnapshot ?? this.pageSnapshot,
      sha256: sha256 ?? this.sha256,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  /// Returns the pointer that lists this version in template metadata.
  TemplateVersionPointer toPointer() {
    return TemplateVersionPointer(
      versionId: id,
      versionNumber: versionNumber,
      createdAt: createdAt,
    );
  }

  /// Serializes the version record.
  ///
  /// Unknown same-schema fields are emitted beneath the modeled keys; nested
  /// snapshots emit their own retained fields.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'id': id,
      'templateId': templateId,
      'versionNumber': versionNumber,
      'createdAt': canonicalUtcTimestamp(createdAt),
      'fieldSnapshot': <Map<String, Object?>>[
        for (final ConfirmedField field in fieldSnapshot) field.toJson(),
      ],
      'pageSnapshot': <Map<String, Object?>>[
        for (final Page page in pageSnapshot) page.toJson(),
      ],
      'sha256': sha256,
    });
  }

  @override
  bool operator ==(Object other) {
    return other is TemplateVersion &&
        other.id == id &&
        other.templateId == templateId &&
        other.versionNumber == versionNumber &&
        other.createdAt == createdAt &&
        _listsEqual<ConfirmedField>(other.fieldSnapshot, fieldSnapshot) &&
        _listsEqual<Page>(other.pageSnapshot, pageSnapshot) &&
        other.sha256 == sha256;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      templateId,
      versionNumber,
      createdAt,
      Object.hashAll(fieldSnapshot),
      Object.hashAll(pageSnapshot),
      sha256,
    );
  }

  @override
  String toString() {
    return 'TemplateVersion(versionNumber: $versionNumber)';
  }
}

/// The versioned template aggregate root (`data-model.md` §3.10).
///
/// A template owns its layout (pages, layout-only fields, field order), the
/// immutable source reference, and the newest-first version pointer list. It has
/// no value or signature member, so it cannot store filled content
/// (FR-102/SC-013). Saving a change appends a version; existing pointers keep
/// their identity and time (FR-103). [latestVersion] always equals the first
/// entry of [versions] (FR-105). Derived documents live in their own storage and
/// pin their version separately through the T017 `TemplateOrigin` (FR-104).
/// Unknown same-schema JSON fields are retained across a read/write round
/// (`data-model.md` §6), at the root and in every nested JSON object.
final class Template extends JsonObject {
  /// Creates a validated template aggregate.
  ///
  /// [schemaVersion] must be [templateSchemaVersion]. [id] must be a lowercase
  /// UUIDv4 and [title] is trimmed to 1–200 characters. [createdAt] and
  /// [updatedAt] must be UTC. Pages must be exactly `0 … source.pageCount - 1`
  /// in order. Fields must have unique ids, fit their page, and be a permutation
  /// of [fieldOrder] whose `order` equals the field's position. [versions] must
  /// be newest first with unique, strictly decreasing version numbers and
  /// non-increasing creation times; [latestVersion] must equal its first entry.
  /// [unknownFields] are opaque same-schema JSON extensions retained for a later
  /// write.
  ///
  /// Throws [ArgumentError] for every invalid value. The error never echoes a
  /// title or label.
  factory Template({
    required String id,
    required String title,
    required DateTime createdAt,
    required DateTime updatedAt,
    required SourceFileRef source,
    required Iterable<Page> pages,
    Iterable<ConfirmedField> fields = const <ConfirmedField>[],
    required Iterable<String> fieldOrder,
    required TemplateVersionPointer latestVersion,
    required Iterable<TemplateVersionPointer> versions,
    int schemaVersion = templateSchemaVersion,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    if (schemaVersion != templateSchemaVersion) {
      throw ArgumentError('schemaVersion must be $templateSchemaVersion');
    }
    final String checkedId = _validateUuidV4(id, 'id');
    final String checkedTitle = _normalizeTitle(title);
    final DateTime created = _checkUtc(createdAt, 'createdAt');
    final DateTime updated = _checkUtc(updatedAt, 'updatedAt');
    final List<Page> pageList = _checkedPages(pages);
    if (pageList.length != source.pageCount) {
      throw ArgumentError('pages.length must equal source.pageCount');
    }
    final List<ConfirmedField> orderedFields = _checkedFields(
      pages: pageList,
      fields: fields,
      fieldOrder: fieldOrder,
    );
    final List<TemplateVersionPointer> versionList = _checkedVersionPointers(
      versions,
    );
    if (latestVersion != versionList.first) {
      throw ArgumentError(
        'latestVersion must equal the newest entry in versions',
      );
    }
    return Template._(
      schemaVersion: schemaVersion,
      id: checkedId,
      title: checkedTitle,
      createdAt: created,
      updatedAt: updated,
      source: source,
      pages: pageList,
      fields: orderedFields,
      fieldOrder: List<String>.unmodifiable(fieldOrder.toList(growable: false)),
      latestVersion: latestVersion,
      versions: versionList,
      unknownFields: freezeUnknownJsonFields(unknownFields),
    );
  }

  const Template._({
    required this.schemaVersion,
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.source,
    required this.pages,
    required this.fields,
    required this.fieldOrder,
    required this.latestVersion,
    required this.versions,
    required super.unknownFields,
  });

  /// Reads a persisted template aggregate projection.
  ///
  /// Only [templateSchemaVersion] is accepted; a higher version fails closed so
  /// the caller can refuse to save without data loss (FR-044). The `kind`
  /// discriminator must be `template`. Unknown same-schema keys are retained for
  /// a later write.
  ///
  /// Throws [FormatException] for missing, mistyped, invalid, or unsupported
  /// fields.
  factory Template.fromJson(Map<String, Object?> json) {
    final Object? rawSchemaVersion = json['schemaVersion'];
    if (rawSchemaVersion is! int) {
      throw const FormatException(
        'JSON field "schemaVersion" must be an integer',
      );
    }
    if (rawSchemaVersion != templateSchemaVersion) {
      throw FormatException(
        'Unsupported template schema version $rawSchemaVersion',
      );
    }
    if (json['kind'] != 'template') {
      throw const FormatException(
        'JSON field "kind" must be the template discriminator',
      );
    }
    try {
      return Template(
        schemaVersion: rawSchemaVersion,
        id: _readString(json, 'id'),
        title: _readString(json, 'title'),
        createdAt: parseCanonicalUtcTimestamp(
          json['createdAt'],
          name: 'createdAt',
        ),
        updatedAt: parseCanonicalUtcTimestamp(
          json['updatedAt'],
          name: 'updatedAt',
        ),
        source: SourceFileRef.fromJson(_readObject(json, 'source')),
        pages: _readObjectList(
          json,
          'pages',
        ).map(Page.fromJson).toList(growable: false),
        fields: _readObjectList(
          json,
          'fields',
        ).map(ConfirmedField.fromJson).toList(growable: false),
        fieldOrder: _readStringList(json, 'fieldOrder'),
        latestVersion: TemplateVersionPointer.fromJson(
          _readObject(json, 'latestVersion'),
        ),
        versions: _readObjectList(
          json,
          'versions',
        ).map(TemplateVersionPointer.fromJson).toList(growable: false),
        unknownFields: unknownJsonFields(json, _templateJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid template JSON: ${error.message}');
    }
  }

  /// The template schema version.
  final int schemaVersion;

  /// The `template` discriminator.
  String get kind => 'template';

  /// UUIDv4 of the template.
  final String id;

  /// User-visible title, trimmed to 1–200 characters.
  final String title;

  /// Creation time in UTC.
  final DateTime createdAt;

  /// Last metadata change time in UTC.
  final DateTime updatedAt;

  /// The immutable encrypted source.
  final SourceFileRef source;

  /// The pages, ordered contiguously from index 0.
  final List<Page> pages;

  /// Layout-only fields, in [fieldOrder] order. Never carries a value.
  final List<ConfirmedField> fields;

  /// Field ids in user-visible order.
  final List<String> fieldOrder;

  /// The newest version; new documents created from this template use it
  /// (FR-105).
  final TemplateVersionPointer latestVersion;

  /// All version pointers, newest first, at least one.
  final List<TemplateVersionPointer> versions;

  /// Returns a copy with the supplied fields replaced.
  ///
  /// The caller must supply a consistent combination (for example, fields and
  /// fieldOrder together, or a new latestVersion and versions together) because
  /// the public constructor revalidates every invariant.
  Template copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    SourceFileRef? source,
    Iterable<Page>? pages,
    Iterable<ConfirmedField>? fields,
    Iterable<String>? fieldOrder,
    TemplateVersionPointer? latestVersion,
    Iterable<TemplateVersionPointer>? versions,
    int? schemaVersion,
    Map<String, Object?>? unknownFields,
  }) {
    return Template(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source ?? this.source,
      pages: pages ?? this.pages,
      fields: fields ?? this.fields,
      fieldOrder: fieldOrder ?? this.fieldOrder,
      latestVersion: latestVersion ?? this.latestVersion,
      versions: versions ?? this.versions,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  /// Serializes the template aggregate projection.
  ///
  /// Templates are layout-only, so the map has no `values` or `signatures`
  /// entry. Unknown same-schema fields are emitted beneath the modeled keys at
  /// the root; nested objects emit their own retained fields. Use
  /// [canonicalJsonEncode] for the canonical byte form.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'schemaVersion': schemaVersion,
      'id': id,
      'kind': kind,
      'title': title,
      'createdAt': canonicalUtcTimestamp(createdAt),
      'updatedAt': canonicalUtcTimestamp(updatedAt),
      'source': source.toJson(),
      'pages': <Map<String, Object?>>[
        for (final Page page in pages) page.toJson(),
      ],
      'fields': <Map<String, Object?>>[
        for (final ConfirmedField field in fields) field.toJson(),
      ],
      'fieldOrder': List<String>.unmodifiable(fieldOrder),
      'latestVersion': latestVersion.toJson(),
      'versions': <Map<String, Object?>>[
        for (final TemplateVersionPointer pointer in versions) pointer.toJson(),
      ],
    });
  }

  @override
  bool operator ==(Object other) {
    return other is Template &&
        other.schemaVersion == schemaVersion &&
        other.id == id &&
        other.title == title &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.source == source &&
        _listsEqual<Page>(other.pages, pages) &&
        _listsEqual<ConfirmedField>(other.fields, fields) &&
        _listsEqual<String>(other.fieldOrder, fieldOrder) &&
        other.latestVersion == latestVersion &&
        _listsEqual<TemplateVersionPointer>(other.versions, versions);
  }

  @override
  int get hashCode {
    return Object.hash(
      schemaVersion,
      id,
      title,
      createdAt,
      updatedAt,
      source,
      Object.hashAll(pages),
      Object.hashAll(fields),
      Object.hashAll(fieldOrder),
      latestVersion,
      Object.hashAll(versions),
    );
  }

  @override
  String toString() {
    return 'Template(id: $id, versions: ${versions.length})';
  }
}

/// The persisted `templates/<id>/meta.fx1` envelope
/// (`data-model.md` §4.1, `contracts/storage-format.md` §2.4).
///
/// The metadata envelope carries everything the start list needs without
/// decrypting a version payload: identity, title, timestamps, the immutable
/// source reference, the newest version pointer, and the full newest-first
/// pointer list. Pages, fields, and their order live in
/// `ver/<versionId>.fx1`; values and signatures have no representation at all
/// (FR-102). A readable envelope must not carry an unreadable reason; an
/// unreadable one keeps its entry visible with a status. Unknown same-schema
/// JSON fields are retained across a read/write round (`data-model.md` §6).
final class TemplateMeta extends JsonObject {
  /// Creates persisted template metadata.
  ///
  /// [id] must be a lowercase UUIDv4 and [title] is trimmed to 1–200
  /// characters. [createdAt] and [updatedAt] must be UTC. [versions] and
  /// [latestVersion] follow the same newest-first rules as [Template]. A
  /// readable envelope must not carry an [unreadableReasonCode]; an unreadable
  /// envelope may omit it when the failure has no specific catalog key.
  /// [unknownFields] are opaque same-schema JSON extensions retained for a later
  /// write.
  ///
  /// Throws [ArgumentError] for every invalid value.
  factory TemplateMeta({
    required String id,
    required String title,
    required DateTime createdAt,
    required DateTime updatedAt,
    required SourceFileRef source,
    required TemplateVersionPointer latestVersion,
    required Iterable<TemplateVersionPointer> versions,
    bool readable = true,
    String? unreadableReasonCode,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    final String checkedId = _validateUuidV4(id, 'id');
    final String checkedTitle = _normalizeTitle(title);
    final DateTime created = _checkUtc(createdAt, 'createdAt');
    final DateTime updated = _checkUtc(updatedAt, 'updatedAt');
    final List<TemplateVersionPointer> versionList = _checkedVersionPointers(
      versions,
    );
    if (latestVersion != versionList.first) {
      throw ArgumentError(
        'latestVersion must equal the newest entry in versions',
      );
    }
    if (readable && unreadableReasonCode != null) {
      throw ArgumentError(
        'unreadableReasonCode must be null when readable is true',
      );
    }
    if (unreadableReasonCode != null) {
      _validateCatalogCode(unreadableReasonCode, 'unreadableReasonCode');
    }
    return TemplateMeta._(
      id: checkedId,
      title: checkedTitle,
      createdAt: created,
      updatedAt: updated,
      source: source,
      latestVersion: latestVersion,
      versions: versionList,
      readable: readable,
      unreadableReasonCode: unreadableReasonCode,
      unknownFields: freezeUnknownJsonFields(unknownFields),
    );
  }

  const TemplateMeta._({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.source,
    required this.latestVersion,
    required this.versions,
    required this.readable,
    required this.unreadableReasonCode,
    required super.unknownFields,
  });

  /// Reads a persisted metadata envelope.
  ///
  /// The `kind` discriminator must be `template`. Unknown same-schema keys are
  /// retained for a later write.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  factory TemplateMeta.fromJson(Map<String, Object?> json) {
    if (json['kind'] != 'template') {
      throw const FormatException(
        'JSON field "kind" must be the template discriminator',
      );
    }
    final Object? unreadableReasonCode = json['unreadableReasonCode'];
    if (unreadableReasonCode != null && unreadableReasonCode is! String) {
      throw const FormatException(
        'JSON field "unreadableReasonCode" must be a string or null',
      );
    }
    try {
      return TemplateMeta(
        id: _readString(json, 'id'),
        title: _readString(json, 'title'),
        createdAt: parseCanonicalUtcTimestamp(
          json['createdAt'],
          name: 'createdAt',
        ),
        updatedAt: parseCanonicalUtcTimestamp(
          json['updatedAt'],
          name: 'updatedAt',
        ),
        source: SourceFileRef.fromJson(_readObject(json, 'source')),
        latestVersion: TemplateVersionPointer.fromJson(
          _readObject(json, 'latestVersion'),
        ),
        versions: _readObjectList(
          json,
          'versions',
        ).map(TemplateVersionPointer.fromJson).toList(growable: false),
        readable: _readBool(json, 'readable'),
        unreadableReasonCode: unreadableReasonCode as String?,
        unknownFields: unknownJsonFields(json, _templateMetaJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid template metadata JSON: ${error.message}');
    }
  }

  /// The `template` discriminator.
  String get kind => 'template';

  /// UUIDv4 of the template.
  final String id;

  /// User-visible title, trimmed to 1–200 characters.
  final String title;

  /// Creation time in UTC.
  final DateTime createdAt;

  /// Last metadata update time in UTC.
  final DateTime updatedAt;

  /// The immutable encrypted source.
  final SourceFileRef source;

  /// The newest version pointer (FR-105).
  final TemplateVersionPointer latestVersion;

  /// All version pointers, newest first, at least one.
  final List<TemplateVersionPointer> versions;

  /// Whether the record and its source are currently readable.
  final bool readable;

  /// Catalog key explaining an unreadable record, or null when readable.
  final String? unreadableReasonCode;

  /// Returns a copy with the supplied fields replaced.
  ///
  /// [unreadableReasonCode] can be cleared by passing `null`; omitting it keeps
  /// the current value. The result is revalidated by the public constructor.
  TemplateMeta copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    SourceFileRef? source,
    TemplateVersionPointer? latestVersion,
    Iterable<TemplateVersionPointer>? versions,
    bool? readable,
    Object? unreadableReasonCode = _unset,
    Map<String, Object?>? unknownFields,
  }) {
    return TemplateMeta(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source ?? this.source,
      latestVersion: latestVersion ?? this.latestVersion,
      versions: versions ?? this.versions,
      readable: readable ?? this.readable,
      unreadableReasonCode: identical(unreadableReasonCode, _unset)
          ? this.unreadableReasonCode
          : unreadableReasonCode as String?,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  /// Serializes the persisted metadata envelope.
  ///
  /// Unknown same-schema fields are emitted beneath the modeled keys.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'id': id,
      'kind': kind,
      'title': title,
      'createdAt': canonicalUtcTimestamp(createdAt),
      'updatedAt': canonicalUtcTimestamp(updatedAt),
      'source': source.toJson(),
      'latestVersion': latestVersion.toJson(),
      'versions': <Map<String, Object?>>[
        for (final TemplateVersionPointer pointer in versions) pointer.toJson(),
      ],
      'readable': readable,
      'unreadableReasonCode': unreadableReasonCode,
    });
  }

  @override
  bool operator ==(Object other) {
    return other is TemplateMeta &&
        other.id == id &&
        other.title == title &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.source == source &&
        other.latestVersion == latestVersion &&
        _listsEqual<TemplateVersionPointer>(other.versions, versions) &&
        other.readable == readable &&
        other.unreadableReasonCode == unreadableReasonCode;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      title,
      createdAt,
      updatedAt,
      source,
      latestVersion,
      Object.hashAll(versions),
      readable,
      unreadableReasonCode,
    );
  }

  @override
  String toString() {
    return 'TemplateMeta(id: $id, readable: $readable)';
  }
}

/// The loaded-template read model (`data-model.md` §4.1).
///
/// [meta] is the persisted envelope, [version] is the pinned immutable version
/// record, and [content] is the decrypted `ver/<versionId>.fx1` payload. The
/// three must describe the same template version: the version belongs to
/// [meta], it is listed in [meta]'s newest-first pointer list, and [content]
/// carries exactly the version's page and field snapshots. The type has no
/// value or signature member, so a loaded template can never expose filled
/// content (FR-102/SC-013). It is an in-memory join of two persisted objects and
/// is therefore not itself serialized.
final class StoredTemplate {
  /// Creates a verified loaded-template join.
  ///
  /// Throws [ArgumentError] when [version] does not belong to [meta], when
  /// [version] is not listed in [meta], or when [content] does not carry the
  /// version's snapshots.
  factory StoredTemplate({
    required TemplateMeta meta,
    required TemplateVersion version,
    required TemplateVersionContent content,
  }) {
    if (version.templateId != meta.id) {
      throw ArgumentError('version.templateId must equal meta.id');
    }
    bool listed = false;
    for (final TemplateVersionPointer pointer in meta.versions) {
      if (pointer.versionId == version.id &&
          pointer.versionNumber == version.versionNumber &&
          pointer.createdAt == version.createdAt) {
        listed = true;
        break;
      }
    }
    if (!listed) {
      throw ArgumentError('version must be listed in meta.versions');
    }
    if (content.schemaVersion != templateSchemaVersion) {
      throw ArgumentError(
        'content.schemaVersion must be $templateSchemaVersion',
      );
    }
    if (!_listsEqual<Page>(content.pageSnapshot, version.pageSnapshot)) {
      throw ArgumentError(
        'content.pageSnapshot must equal version.pageSnapshot',
      );
    }
    if (!_listsEqual<ConfirmedField>(
      content.fieldSnapshot,
      version.fieldSnapshot,
    )) {
      throw ArgumentError(
        'content.fieldSnapshot must equal version.fieldSnapshot',
      );
    }
    return StoredTemplate._(meta: meta, version: version, content: content);
  }

  const StoredTemplate._({
    required this.meta,
    required this.version,
    required this.content,
  });

  /// The persisted metadata envelope.
  final TemplateMeta meta;

  /// The pinned immutable version record.
  final TemplateVersion version;

  /// The decrypted version content.
  final TemplateVersionContent content;

  /// UUIDv4 of the loaded template.
  String get templateId => meta.id;

  /// The loaded version number.
  int get versionNumber => version.versionNumber;

  /// The layout-only field snapshot of the loaded version.
  List<ConfirmedField> get fields => content.fieldSnapshot;

  /// The page snapshot of the loaded version.
  List<Page> get pages => content.pageSnapshot;

  /// Field ids in user-visible order.
  List<String> get fieldOrder => content.fieldOrder;

  /// Returns a copy with the supplied parts replaced.
  ///
  /// The result is revalidated by the public constructor.
  StoredTemplate copyWith({
    TemplateMeta? meta,
    TemplateVersion? version,
    TemplateVersionContent? content,
  }) {
    return StoredTemplate(
      meta: meta ?? this.meta,
      version: version ?? this.version,
      content: content ?? this.content,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is StoredTemplate &&
        other.meta == meta &&
        other.version == version &&
        other.content == content;
  }

  @override
  int get hashCode {
    return Object.hash(meta, version, content);
  }

  @override
  String toString() {
    return 'StoredTemplate(templateId: $templateId, '
        'versionNumber: $versionNumber)';
  }
}

/// Validates and returns an unmodifiable, contiguous page snapshot.
List<Page> _checkedPages(Iterable<Page> pages) {
  final List<Page> pageList = pages.toList(growable: false);
  if (pageList.isEmpty) {
    throw ArgumentError('pages must contain at least one page');
  }
  for (int index = 0; index < pageList.length; index++) {
    if (pageList[index].index != index) {
      throw ArgumentError('pages must be ordered contiguously from index 0');
    }
  }
  return List<Page>.unmodifiable(pageList);
}

/// Validates a layout with an explicit field order and returns it ordered.
List<ConfirmedField> _checkedFields({
  required List<Page> pages,
  required Iterable<ConfirmedField> fields,
  required Iterable<String> fieldOrder,
}) {
  final List<ConfirmedField> suppliedFields = fields.toList(growable: false);
  final Map<String, ConfirmedField> fieldById = <String, ConfirmedField>{};
  for (final ConfirmedField field in suppliedFields) {
    if (fieldById.containsKey(field.id)) {
      throw ArgumentError('confirmed field ids must be unique');
    }
    fieldById[field.id] = field;
    _checkFieldWithinPages(field, pages);
  }

  final List<String> suppliedOrder = fieldOrder.toList(growable: false);
  if (suppliedOrder.length != fieldById.length) {
    throw ArgumentError(
      'fieldOrder must contain every confirmed field exactly once',
    );
  }
  if (suppliedOrder.toSet().length != suppliedOrder.length) {
    throw ArgumentError('fieldOrder must not contain duplicate ids');
  }
  for (int index = 0; index < suppliedOrder.length; index++) {
    final ConfirmedField? field = fieldById[suppliedOrder[index]];
    if (field == null) {
      throw ArgumentError('fieldOrder references an unknown field id');
    }
    if (field.order != index) {
      throw ArgumentError(
        'field.order must equal the field position in fieldOrder',
      );
    }
  }
  return List<ConfirmedField>.unmodifiable(<ConfirmedField>[
    for (final String fieldId in suppliedOrder) fieldById[fieldId]!,
  ]);
}

/// Validates a version field snapshot without a separate field order.
///
/// The version record stores the snapshots but not `fieldOrder` (that lives in
/// [TemplateVersionContent]); the field `order` values therefore have to be
/// unique and contiguous on their own. The result is sorted by `order`.
List<ConfirmedField> _checkedVersionFieldSnapshot({
  required List<Page> pages,
  required Iterable<ConfirmedField> fields,
}) {
  final List<ConfirmedField> sorted = fields.toList(growable: false)
    ..sort((ConfirmedField a, ConfirmedField b) => a.order.compareTo(b.order));
  final Set<String> ids = <String>{};
  for (int index = 0; index < sorted.length; index++) {
    final ConfirmedField field = sorted[index];
    if (!ids.add(field.id)) {
      throw ArgumentError('confirmed field ids must be unique');
    }
    _checkFieldWithinPages(field, pages);
    if (field.order != index) {
      throw ArgumentError('field orders must be unique and contiguous from 0');
    }
  }
  return List<ConfirmedField>.unmodifiable(sorted);
}

/// Validates that [field] references an existing page and fits its display box.
void _checkFieldWithinPages(ConfirmedField field, List<Page> pages) {
  if (field.pageIndex >= pages.length) {
    throw ArgumentError('a confirmed field references a missing page');
  }
  if (!field.fitsWithinPage(pages[field.pageIndex].geometry.displaySize)) {
    throw ArgumentError('a confirmed field lies outside its page display box');
  }
}

/// Validates and returns an unmodifiable newest-first pointer list.
List<TemplateVersionPointer> _checkedVersionPointers(
  Iterable<TemplateVersionPointer> versions,
) {
  final List<TemplateVersionPointer> versionList = versions.toList(
    growable: false,
  );
  if (versionList.isEmpty) {
    throw ArgumentError('versions must contain at least one version');
  }
  final Set<String> versionIds = <String>{};
  for (int index = 0; index < versionList.length; index++) {
    final TemplateVersionPointer pointer = versionList[index];
    if (!versionIds.add(pointer.versionId)) {
      throw ArgumentError('version pointers must have unique version ids');
    }
    if (index == 0) {
      continue;
    }
    final TemplateVersionPointer newer = versionList[index - 1];
    if (pointer.versionNumber >= newer.versionNumber) {
      throw ArgumentError(
        'versions must be newest first with strictly decreasing '
        'versionNumber values',
      );
    }
    if (pointer.createdAt.isAfter(newer.createdAt)) {
      throw ArgumentError(
        'versions must be newest first with non-increasing createdAt values',
      );
    }
  }
  return List<TemplateVersionPointer>.unmodifiable(versionList);
}

int _validateVersionNumber(int value) {
  if (value < 1) {
    throw ArgumentError('versionNumber must be at least 1');
  }
  return value;
}

String _normalizeTitle(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError('title must not be empty');
  }
  if (trimmed.runes.length > 200) {
    throw ArgumentError('title must be at most 200 characters');
  }
  _checkNoControlCharacters(trimmed, 'title');
  return trimmed;
}

void _checkNoControlCharacters(String value, String name) {
  for (final int rune in value.runes) {
    if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
      throw ArgumentError('$name must not contain control characters');
    }
  }
}

String _validateUuidV4(String value, String name) {
  if (!_uuidV4Pattern.hasMatch(value)) {
    throw ArgumentError('$name must be a lowercase UUIDv4');
  }
  return value;
}

String _validateSha256(String value, String name) {
  if (!_sha256Pattern.hasMatch(value)) {
    throw ArgumentError('$name must be 64 lowercase hexadecimal characters');
  }
  return value;
}

void _validateCatalogCode(String value, String name) {
  if (!_catalogCodePattern.hasMatch(value)) {
    throw ArgumentError('$name must be a catalog code such as SAVE-002');
  }
}

DateTime _checkUtc(DateTime value, String name) {
  if (!value.isUtc) {
    throw ArgumentError('$name must be UTC');
  }
  return value;
}

bool _listsEqual<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int index = 0; index < a.length; index++) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

Map<String, Object?> _readObject(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('JSON field "$key" must be an object');
  }
  return value;
}

List<Map<String, Object?>> _readObjectList(
  Map<String, Object?> json,
  String key,
) {
  final Object? value = json[key];
  if (value is! List<Object?>) {
    throw FormatException('JSON field "$key" must be an array');
  }
  final List<Map<String, Object?>> result = <Map<String, Object?>>[];
  for (final Object? item in value) {
    if (item is! Map<String, Object?>) {
      throw FormatException('JSON field "$key" must contain only objects');
    }
    result.add(item);
  }
  return result;
}

String _readString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String) {
    throw FormatException('JSON field "$key" must be a string');
  }
  return value;
}

int _readInt(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! int) {
    throw FormatException('JSON field "$key" must be an integer');
  }
  return value;
}

bool _readBool(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! bool) {
    throw FormatException('JSON field "$key" must be a boolean');
  }
  return value;
}

List<String> _readStringList(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! List<Object?>) {
    throw FormatException('JSON field "$key" must be an array');
  }
  final List<String> result = <String>[];
  for (final Object? item in value) {
    if (item is! String) {
      throw FormatException('JSON field "$key" must contain only strings');
    }
    result.add(item);
  }
  return result;
}

/// Marks an omitted argument that can also be null.
const Object _unset = Object();

final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
final RegExp _catalogCodePattern = RegExp(r'^[A-Z]{2,4}-[0-9]{3}$');

/// Modeled keys of a persisted template version pointer.
const Set<String> _templateVersionPointerJsonKeys = <String>{
  'versionId',
  'versionNumber',
  'createdAt',
};

/// Modeled keys of a persisted template version content payload.
const Set<String> _templateVersionContentJsonKeys = <String>{
  'schemaVersion',
  'pageSnapshot',
  'fieldSnapshot',
  'fieldOrder',
};

/// Modeled keys of a template version record.
const Set<String> _templateVersionJsonKeys = <String>{
  'id',
  'templateId',
  'versionNumber',
  'createdAt',
  'fieldSnapshot',
  'pageSnapshot',
  'sha256',
};

/// Modeled keys of the persisted template metadata envelope.
const Set<String> _templateMetaJsonKeys = <String>{
  'id',
  'kind',
  'title',
  'createdAt',
  'updatedAt',
  'source',
  'latestVersion',
  'versions',
  'readable',
  'unreadableReasonCode',
};

/// Modeled keys of the template aggregate projection.
const Set<String> _templateJsonKeys = <String>{
  'schemaVersion',
  'id',
  'kind',
  'title',
  'createdAt',
  'updatedAt',
  'source',
  'pages',
  'fields',
  'fieldOrder',
  'latestVersion',
  'versions',
};
