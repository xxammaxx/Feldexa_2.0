// Feldexa document-side template reference (T017).
//
// Owner: `packages/feldexa_core/lib/src/model/template_origin.dart` (T017).
// Normative source: `data-model.md` §3.9.
//
// `TemplateOrigin` belongs to `Document`, not to the `Template` aggregate.
// Moving it here breaks the former T017 <-> T021 reference cycle: T021 owns
// `Template`, `TemplateVersion`, and the template-side pointer, while this file
// owns only the immutable document-to-version pin. A document never re-points
// to a newer template version (FR-104).
library;

/// The immutable template version pinned by a derived document
/// (`data-model.md` §3.9).
final class TemplateOrigin {
  /// Creates a template origin.
  ///
  /// [templateId] and [templateVersionId] must be lowercase UUIDv4 values.
  /// [templateVersionNumber] is at least 1 and display-only.
  ///
  /// Throws [ArgumentError] for every invalid value.
  factory TemplateOrigin({
    required String templateId,
    required String templateVersionId,
    required int templateVersionNumber,
  }) {
    if (!_uuidV4Pattern.hasMatch(templateId)) {
      throw ArgumentError('templateId must be a lowercase UUIDv4');
    }
    if (!_uuidV4Pattern.hasMatch(templateVersionId)) {
      throw ArgumentError('templateVersionId must be a lowercase UUIDv4');
    }
    if (templateVersionNumber < 1) {
      throw ArgumentError('templateVersionNumber must be at least 1');
    }
    return TemplateOrigin._(
      templateId: templateId,
      templateVersionId: templateVersionId,
      templateVersionNumber: templateVersionNumber,
    );
  }

  const TemplateOrigin._({
    required this.templateId,
    required this.templateVersionId,
    required this.templateVersionNumber,
  });

  /// Reads a persisted template origin.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  factory TemplateOrigin.fromJson(Map<String, Object?> json) {
    final Object? templateId = json['templateId'];
    if (templateId is! String) {
      throw const FormatException('JSON field "templateId" must be a string');
    }
    final Object? templateVersionId = json['templateVersionId'];
    if (templateVersionId is! String) {
      throw const FormatException(
        'JSON field "templateVersionId" must be a string',
      );
    }
    final Object? templateVersionNumber = json['templateVersionNumber'];
    if (templateVersionNumber is! int) {
      throw const FormatException(
        'JSON field "templateVersionNumber" must be an integer',
      );
    }
    try {
      return TemplateOrigin(
        templateId: templateId,
        templateVersionId: templateVersionId,
        templateVersionNumber: templateVersionNumber,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid template origin JSON: ${error.message}');
    }
  }

  /// UUIDv4 of the template aggregate.
  final String templateId;

  /// UUIDv4 of the pinned, immutable template version.
  final String templateVersionId;

  /// One-based version number for display only.
  final int templateVersionNumber;

  /// Returns a copy with the supplied fields replaced.
  ///
  /// The result is revalidated by the public constructor. Re-pinning is an
  /// explicit caller decision; this type never changes a pin by itself.
  TemplateOrigin copyWith({
    String? templateId,
    String? templateVersionId,
    int? templateVersionNumber,
  }) {
    return TemplateOrigin(
      templateId: templateId ?? this.templateId,
      templateVersionId: templateVersionId ?? this.templateVersionId,
      templateVersionNumber:
          templateVersionNumber ?? this.templateVersionNumber,
    );
  }

  /// Serializes to the persisted template-origin object.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'templateId': templateId,
      'templateVersionId': templateVersionId,
      'templateVersionNumber': templateVersionNumber,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is TemplateOrigin &&
        other.templateId == templateId &&
        other.templateVersionId == templateVersionId &&
        other.templateVersionNumber == templateVersionNumber;
  }

  @override
  int get hashCode {
    return Object.hash(templateId, templateVersionId, templateVersionNumber);
  }

  @override
  String toString() {
    return 'TemplateOrigin(templateVersionNumber: $templateVersionNumber)';
  }
}

final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
