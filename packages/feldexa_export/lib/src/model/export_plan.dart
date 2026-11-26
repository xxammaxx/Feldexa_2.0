// Feldexa export contract models (T022).
//
// Owner: `packages/feldexa_export/lib/src/model/export_plan.dart` (T022).
// Normative sources:
//   * `contracts/export-plan.md` §1–§2 — the deterministic instruction set,
//     the v1 canonical JSON schema, page/op fields, and forbidden content;
//   * `contracts/export-plan.md` §3–§4 — layout products, blocking warnings,
//     and the warning payload (`code`, `fieldId`, `pageIndex`, `fieldLabel`,
//     `reason`);
//   * `data-model.md` §3.15 — `ExportPlan`, `ExportValidation`, and
//     `ArtifactVerification`/`ExportArtifact` ownership (the artifact and
//     verification types live in `export_artifact.dart`);
//   * `contracts/ports.md` §1 and §2.5 — the export contract types and the
//     `PdfExportPort.validate` result;
//   * `spec.md` FR-062, FR-068, and FR-072 — a plan is only produced for
//     confirmed content, clip/overflow blocks, and a failed export is never
//     presented as successful.
//
// The plan is the complete, deterministic instruction set. It contains no PDF
// bytes, no platform calls, no OCR or suggestion content, no labels beyond the
// validation warning payload, and no absolute file paths. This file reuses the
// canonical T015/T016 geometry value objects (`Rect`, `Size`, `PageGeometry`)
// and the T018 `Provenance` vocabulary instead of declaring second copies.
//
// `ExportPlan.evidenceClass` is deliberately a plain string token
// (`simulated | emulator | device | none`) as `contracts/export-plan.md` §2
// requires; `feldexa_export` never imports `feldexa_ports`.
//
// Every model validates in release mode and preserves unknown same-schema JSON
// fields (`data-model.md` §6). Forbidden plan content is refused instead of
// being retained, so an extension cannot smuggle values, OCR text, screenshots,
// field labels, or interactive form definitions into an export plan.
library;

import 'dart:collection';
import 'dart:math' as math;

import 'package:feldexa_core/feldexa_core.dart';

/// The only export-plan schema version this build writes and accepts.
const int exportPlanSchemaVersion = 1;

/// The evidence-class tokens allowed in `ExportPlan.evidenceClass`.
///
/// These are plan tokens, not `feldexa_ports.EvidenceClass` values; the export
/// package intentionally does not depend on the ports package.
const Set<String> exportEvidenceClassTokens = <String>{
  'simulated',
  'emulator',
  'device',
  'none',
};

/// The catalog codes a blocking `PdfExportPort.validate` result may carry.
///
/// `contracts/export-plan.md` §4 defines exactly these blocking codes.
const Set<String> exportBlockingWarningCodes = <String>{
  'EXP-001',
  'EXP-002',
  'EXP-003',
  'EXP-004',
  'EXP-005',
  'EXP-006',
  'SAVE-001',
};

/// Maximum accepted source page count (`data-model.md` §3.2).
const int _maxExportPageCount = 100;

/// Geometry comparison tolerance for derived display size and CTM values.
const double _geometryTolerance = 1e-6;

/// Keys that must never appear anywhere in an export plan (`export-plan.md`
/// §2.3). They are refused recursively instead of being retained as unknown
/// same-schema extensions.
const Set<String> _forbiddenPlanKeys = <String>{
  'values',
  'value',
  'signatures',
  'signature',
  'signaturebytes',
  'suggestions',
  'suggestion',
  'ocr',
  'ocrtext',
  'screenshots',
  'screenshot',
  'pageimage',
  'pageimages',
  'label',
  'fieldlabel',
  'acroform',
  'formfields',
  'widgets',
  'annotations',
  'interactivefields',
  'absolutepath',
  'devicename',
  'devicemodel',
  'deviceid',
  'buildfingerprint',
  'user',
  'userid',
  'useridentifier',
  'username',
  'owner',
  'author',
  'createdby',
  'updatedby',
  'email',
  'account',
  'accountid',
  'device',
  'manufacturer',
  'androidid',
  'advertisingid',
  'imei',
  'macaddress',
  'serial',
  'serialnumber',
  'hostname',
};

const Set<String> _exportPlanJsonKeys = <String>{
  'schemaVersion',
  'documentId',
  'revisionId',
  'sourceSha256',
  'pageCount',
  'evidenceClass',
  'font',
  'pages',
  'warnings',
  'info',
};

const Set<String> _exportFontJsonKeys = <String>{
  'family',
  'regularAsset',
  'boldAsset',
  'metricsVersion',
};

const Set<String> _exportPlanInfoJsonKeys = <String>{
  'emptyFieldCount',
  'unresolvedSuggestionCount',
};

const Set<String> _exportPageJsonKeys = <String>{
  'index',
  'rotation',
  'mediaBox',
  'cropBox',
  'displaySize',
  'ctm',
  'ops',
};

const Set<String> _exportCtmJsonKeys = <String>{'a', 'b', 'c', 'd', 'e', 'f'};

const Set<String> _exportOpJsonKeys = <String>{
  'op',
  'fieldId',
  'provenance',
  'rect',
  'pdfRect',
};

const Set<String> _exportTextOpJsonKeys = <String>{
  ..._exportOpJsonKeys,
  'fontSizePt',
  'lineHeightPt',
  'baselineFromTopPt',
  'color',
  'lines',
  'overflow',
};

const Set<String> _exportCheckboxOpJsonKeys = <String>{
  ..._exportOpJsonKeys,
  'checked',
  'insetPt',
  'strokeWidthPt',
};

const Set<String> _exportImageOpJsonKeys = <String>{
  ..._exportOpJsonKeys,
  'assetId',
  'fit',
  'align',
};

const Set<String> _exportValidationJsonKeys = <String>{
  'warnings',
  'validatedAt',
};

const Set<String> _exportValidationWarningJsonKeys = <String>{
  'code',
  'reason',
  'fieldId',
  'pageIndex',
  'fieldLabel',
};

final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
final RegExp _emailPattern = RegExp(
  r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
);
final RegExp _deviceNamePattern = RegExp(
  r'\b(?:Pixel(?:\s*\d+)?|Samsung|Galaxy|SM-[A-Z0-9]{3,}|Exynos|emulator-\d+)\b',
  caseSensitive: false,
);
final RegExp _userIdPattern = RegExp(
  r'\buser[\s_-]?\d{3,}\b',
  caseSensitive: false,
);
final RegExp _uriSchemePattern = RegExp(r'[A-Za-z][A-Za-z0-9+.-]*://');
final RegExp _userHandlePattern = RegExp(r'(?<![\w.])@[A-Za-z0-9_]{3,}');
const String _schemeAlternation =
    r'file|content|data|http|https|mailto|tel|urn|android\.resource|intent|'
    r'package|javascript|vbscript|about|chrome|blob|ws|wss|ftp|sftp|ssh|git|'
    r'svn|sms|geo|market';
final RegExp _knownSchemePattern = RegExp(
  '^(?:$_schemeAlternation):',
  caseSensitive: false,
);
final RegExp _knownSchemeContextPattern = RegExp(
  '(?:^|[\\s(:=,;<>|])(?:$_schemeAlternation):',
  caseSensitive: false,
);
final RegExp _windowsDrivePattern = RegExp(r'^[A-Za-z]:[\\/]');

/// The v1 export instruction set (`contracts/export-plan.md` §2).
///
/// A plan is only produced for confirmed fields of one immutable revision. It
/// carries every source page in order and one operation per field. The
/// constructor refuses an overflowing text op, a duplicate field op, a page
/// gap, mismatched CTM/display size, and any forbidden plan content.
///
/// Unknown same-schema JSON fields are retained across a read/write round
/// (`data-model.md` §6); forbidden keys are refused instead.
final class ExportPlan extends JsonObject {
  /// Creates and validates an export plan.
  ///
  /// [documentId] and [revisionId] must be lowercase UUIDv4 values.
  /// [sourceSha256] must be 64 lowercase hex characters. [pageCount] must equal
  /// [pages].length and be between 1 and 100. [evidenceClass] must be one of
  /// [exportEvidenceClassTokens]. Pages must be ordered contiguously from index
  /// 0. Unknown [unknownFields] are retained unless they are forbidden plan
  /// content.
  ///
  /// Throws [ArgumentError] for every invalid value. Errors never echo user
  /// content.
  factory ExportPlan({
    required String documentId,
    required String revisionId,
    required String sourceSha256,
    required int pageCount,
    required String evidenceClass,
    required ExportFont font,
    required Iterable<ExportPage> pages,
    Iterable<String> warnings = const <String>[],
    required ExportPlanInfo info,
    int schemaVersion = exportPlanSchemaVersion,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    if (schemaVersion != exportPlanSchemaVersion) {
      throw ArgumentError('schemaVersion must be $exportPlanSchemaVersion');
    }
    final String checkedDocumentId = _checkUuidV4(documentId, 'documentId');
    final String checkedRevisionId = _checkUuidV4(revisionId, 'revisionId');
    final String checkedSourceSha256 = _checkSha256(
      sourceSha256,
      'sourceSha256',
    );
    if (pageCount < 1 || pageCount > _maxExportPageCount) {
      throw ArgumentError(
        'pageCount must be between 1 and $_maxExportPageCount',
      );
    }
    if (!exportEvidenceClassTokens.contains(evidenceClass)) {
      throw ArgumentError('evidenceClass is not a supported token');
    }
    final List<ExportPage> checkedPages = List<ExportPage>.unmodifiable(
      pages.toList(growable: false),
    );
    if (checkedPages.length != pageCount) {
      throw ArgumentError('pages.length must equal pageCount');
    }
    for (int index = 0; index < checkedPages.length; index++) {
      if (checkedPages[index].index != index) {
        throw ArgumentError('pages must be ordered contiguously from index 0');
      }
    }
    final List<String> checkedWarnings = <String>[];
    for (final String warning in warnings) {
      if (warning.isEmpty) {
        throw ArgumentError('warnings must not contain empty entries');
      }
      _rejectForbiddenPlanContent(warning, scanValues: true);
      checkedWarnings.add(warning);
    }
    _rejectForbiddenPlanContent(unknownFields, scanValues: true);
    return ExportPlan._(
      schemaVersion: schemaVersion,
      documentId: checkedDocumentId,
      revisionId: checkedRevisionId,
      sourceSha256: checkedSourceSha256,
      pageCount: pageCount,
      evidenceClass: evidenceClass,
      font: font,
      pages: checkedPages,
      warnings: List<String>.unmodifiable(checkedWarnings),
      info: info,
      unknownFields: freezeUnknownJsonFields(unknownFields),
    );
  }

  const ExportPlan._({
    required this.schemaVersion,
    required this.documentId,
    required this.revisionId,
    required this.sourceSha256,
    required this.pageCount,
    required this.evidenceClass,
    required this.font,
    required this.pages,
    required this.warnings,
    required this.info,
    required super.unknownFields,
  });

  /// Reads a canonical v1 export plan.
  ///
  /// Throws [FormatException] for missing, mistyped, invalid, or forbidden
  /// content. Unknown same-schema keys are retained for a later write.
  factory ExportPlan.fromJson(Map<String, Object?> json) {
    _rejectForbiddenPlanContent(json, asJson: true);
    try {
      final List<Object?> rawPages = _readList(json, 'pages');
      final List<ExportPage> parsedPages = <ExportPage>[
        for (final Object? page in rawPages)
          ExportPage.fromJson(_asObject(page, 'pages entry')),
      ];
      return ExportPlan(
        schemaVersion: _readInt(json, 'schemaVersion'),
        documentId: _readNonEmptyString(json, 'documentId'),
        revisionId: _readNonEmptyString(json, 'revisionId'),
        sourceSha256: _readNonEmptyString(json, 'sourceSha256'),
        pageCount: _readInt(json, 'pageCount'),
        evidenceClass: _readNonEmptyString(json, 'evidenceClass'),
        font: ExportFont.fromJson(_readObject(json, 'font')),
        pages: parsedPages,
        warnings: <String>[
          for (final Object? warning in _readList(json, 'warnings'))
            _asString(warning, 'warnings entry'),
        ],
        info: ExportPlanInfo.fromJson(_readObject(json, 'info')),
        unknownFields: unknownJsonFields(json, _exportPlanJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid export plan JSON: ${error.message}');
    }
  }

  /// The only accepted plan schema version.
  final int schemaVersion;

  /// Parent document UUIDv4.
  final String documentId;

  /// Exported revision UUIDv4.
  final String revisionId;

  /// SHA-256 of the immutable source bytes.
  final String sourceSha256;

  /// Number of source pages; equals [pages].length.
  final int pageCount;

  /// Evidence token (`simulated`, `emulator`, `device`, or `none`).
  final String evidenceClass;

  /// The bundled font contract.
  final ExportFont font;

  /// One entry per source page, ordered from index 0 without gaps.
  final List<ExportPage> pages;

  /// Non-blocking plan warnings; blocking conditions prevent plan creation.
  final List<String> warnings;

  /// Export-time informational counts.
  final ExportPlanInfo info;

  /// Serializes this plan to the v1 canonical JSON shape.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'schemaVersion': schemaVersion,
      'documentId': documentId,
      'revisionId': revisionId,
      'sourceSha256': sourceSha256,
      'pageCount': pageCount,
      'evidenceClass': evidenceClass,
      'font': font.toJson(),
      'pages': <Map<String, Object?>>[
        for (final ExportPage page in pages) page.toJson(),
      ],
      'warnings': warnings,
      'info': info.toJson(),
    });
  }

  @override
  bool operator ==(Object other) {
    return other is ExportPlan &&
        other.schemaVersion == schemaVersion &&
        other.documentId == documentId &&
        other.revisionId == revisionId &&
        other.sourceSha256 == sourceSha256 &&
        other.pageCount == pageCount &&
        other.evidenceClass == evidenceClass &&
        other.font == font &&
        _listEquals(other.pages, pages) &&
        _listEquals(other.warnings, warnings) &&
        other.info == info;
  }

  @override
  int get hashCode {
    return Object.hash(
      schemaVersion,
      documentId,
      revisionId,
      sourceSha256,
      pageCount,
      evidenceClass,
      font,
      Object.hashAll(pages),
      Object.hashAll(warnings),
      info,
    );
  }

  @override
  String toString() => 'ExportPlan(pageCount: $pageCount)';
}

/// The bundled font contract from `contracts/export-plan.md` §2.
///
/// Asset paths are relative, repo-bundled paths; absolute paths and URIs are
/// refused so a plan can never leak a host location.
final class ExportFont extends JsonObject {
  /// Creates and validates a font contract.
  ///
  /// Throws [ArgumentError] for empty values or an absolute/URI asset path.
  factory ExportFont({
    required String family,
    required String regularAsset,
    required String boldAsset,
    required String metricsVersion,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    final String checkedFamily = _checkNonEmpty(family, 'family');
    final String checkedRegular = _checkBundledAssetPath(
      regularAsset,
      'regularAsset',
    );
    final String checkedBold = _checkBundledAssetPath(boldAsset, 'boldAsset');
    final String checkedMetrics = _checkNonEmpty(
      metricsVersion,
      'metricsVersion',
    );
    _checkPrivateMetadata(checkedFamily, 'family');
    _checkPrivateMetadata(checkedRegular, 'regularAsset');
    _checkPrivateMetadata(checkedBold, 'boldAsset');
    _checkPrivateMetadata(checkedMetrics, 'metricsVersion');
    _rejectForbiddenPlanContent(unknownFields, scanValues: true);
    return ExportFont._(
      family: checkedFamily,
      regularAsset: checkedRegular,
      boldAsset: checkedBold,
      metricsVersion: checkedMetrics,
      unknownFields: freezeUnknownJsonFields(unknownFields),
    );
  }

  const ExportFont._({
    required this.family,
    required this.regularAsset,
    required this.boldAsset,
    required this.metricsVersion,
    required super.unknownFields,
  });

  /// Reads a font contract.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  factory ExportFont.fromJson(Map<String, Object?> json) {
    _rejectForbiddenPlanContent(json, asJson: true);
    try {
      return ExportFont(
        family: _readNonEmptyString(json, 'family'),
        regularAsset: _readNonEmptyString(json, 'regularAsset'),
        boldAsset: _readNonEmptyString(json, 'boldAsset'),
        metricsVersion: _readNonEmptyString(json, 'metricsVersion'),
        unknownFields: unknownJsonFields(json, _exportFontJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid export font JSON: ${error.message}');
    }
  }

  /// Bundled font family.
  final String family;

  /// Relative regular font asset path.
  final String regularAsset;

  /// Relative bold font asset path.
  final String boldAsset;

  /// Identifier of the generated metrics table.
  final String metricsVersion;

  /// Serializes the font contract.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'family': family,
      'regularAsset': regularAsset,
      'boldAsset': boldAsset,
      'metricsVersion': metricsVersion,
    });
  }

  @override
  bool operator ==(Object other) {
    return other is ExportFont &&
        other.family == family &&
        other.regularAsset == regularAsset &&
        other.boldAsset == boldAsset &&
        other.metricsVersion == metricsVersion;
  }

  @override
  int get hashCode {
    return Object.hash(family, regularAsset, boldAsset, metricsVersion);
  }

  @override
  String toString() => 'ExportFont(family: $family)';
}

/// Export-time informational counts from `contracts/export-plan.md` §3.4.
final class ExportPlanInfo extends JsonObject {
  /// Creates the informational counts.
  ///
  /// Both counts must be non-negative. Empty fields do not block export; the
  /// count is shown to the user.
  factory ExportPlanInfo({
    required int emptyFieldCount,
    required int unresolvedSuggestionCount,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    if (emptyFieldCount < 0) {
      throw ArgumentError('emptyFieldCount must not be negative');
    }
    if (unresolvedSuggestionCount < 0) {
      throw ArgumentError('unresolvedSuggestionCount must not be negative');
    }
    _rejectForbiddenPlanContent(unknownFields, scanValues: true);
    return ExportPlanInfo._(
      emptyFieldCount: emptyFieldCount,
      unresolvedSuggestionCount: unresolvedSuggestionCount,
      unknownFields: freezeUnknownJsonFields(unknownFields),
    );
  }

  const ExportPlanInfo._({
    required this.emptyFieldCount,
    required this.unresolvedSuggestionCount,
    required super.unknownFields,
  });

  /// Reads the informational counts.
  ///
  /// Throws [FormatException] for missing or negative values.
  factory ExportPlanInfo.fromJson(Map<String, Object?> json) {
    _rejectForbiddenPlanContent(json, asJson: true);
    try {
      return ExportPlanInfo(
        emptyFieldCount: _readInt(json, 'emptyFieldCount'),
        unresolvedSuggestionCount: _readInt(json, 'unresolvedSuggestionCount'),
        unknownFields: unknownJsonFields(json, _exportPlanInfoJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid export plan info JSON: ${error.message}');
    }
  }

  /// Number of confirmed fields left empty.
  final int emptyFieldCount;

  /// Number of unresolved suggestions excluded (OD-1/Q1=A).
  final int unresolvedSuggestionCount;

  /// Serializes the informational counts.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'emptyFieldCount': emptyFieldCount,
      'unresolvedSuggestionCount': unresolvedSuggestionCount,
    });
  }

  @override
  bool operator ==(Object other) {
    return other is ExportPlanInfo &&
        other.emptyFieldCount == emptyFieldCount &&
        other.unresolvedSuggestionCount == unresolvedSuggestionCount;
  }

  @override
  int get hashCode {
    return Object.hash(emptyFieldCount, unresolvedSuggestionCount);
  }

  @override
  String toString() =>
      'ExportPlanInfo(empty: $emptyFieldCount, unresolved: $unresolvedSuggestionCount)';
}

/// One source page in the export plan (`contracts/export-plan.md` §2.1).
///
/// The effective crop box, display size, and display→PDF CTM are derived from
/// the T016 [PageGeometry]; a serialized CTM is accepted only when it matches
/// the normative matrix for that geometry. Every op's `pdfRect` must equal the
/// geometry mapping of its display `rect`.
final class ExportPage extends JsonObject {
  /// Creates and validates one plan page.
  ///
  /// [index] is 0-based and must match the page's position in the plan. [ctm]
  /// may be omitted, in which case the normative matrix is derived. Ops are
  /// deterministic by field order and each field appears at most once.
  ///
  /// Throws [ArgumentError] for duplicate fields, a CTM mismatch, or a
  /// `pdfRect` that does not match the display rectangle.
  factory ExportPage({
    required int index,
    required PageGeometry geometry,
    Iterable<ExportOp> ops = const <ExportOp>[],
    ExportCtm? ctm,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    if (index < 0) {
      throw ArgumentError('index must not be negative');
    }
    final List<ExportOp> checkedOps = List<ExportOp>.unmodifiable(
      ops.toList(growable: false),
    );
    final Set<String> fieldIds = <String>{};
    for (final ExportOp op in checkedOps) {
      if (!fieldIds.add(op.fieldId)) {
        throw ArgumentError('a page may contain only one op per field');
      }
      final Rect expectedPdfRect = geometry.displayRectToPdf(op.rect);
      if (!_rectMatches(op.pdfRect, expectedPdfRect)) {
        throw ArgumentError('pdfRect must equal the display rectangle mapping');
      }
    }
    final ExportCtm expectedCtm = ExportCtm.fromGeometry(geometry);
    if (ctm != null && !ctm.matches(expectedCtm)) {
      throw ArgumentError('ctm must match the page geometry');
    }
    _rejectForbiddenPlanContent(geometry.unknownFields, scanValues: true);
    _rejectForbiddenPlanContent(
      geometry.mediaBox.unknownFields,
      scanValues: true,
    );
    _rejectForbiddenPlanContent(
      geometry.cropBox.unknownFields,
      scanValues: true,
    );
    _rejectForbiddenPlanContent(unknownFields, scanValues: true);
    return ExportPage._(
      index: index,
      geometry: geometry,
      ctm: ctm ?? expectedCtm,
      ops: checkedOps,
      unknownFields: freezeUnknownJsonFields(unknownFields),
    );
  }

  const ExportPage._({
    required this.index,
    required this.geometry,
    required this.ctm,
    required this.ops,
    required super.unknownFields,
  });

  /// Reads one plan page.
  ///
  /// [displaySize] is validated against the geometry instead of replacing the
  /// derived value. Throws [FormatException] for missing, mistyped, or
  /// inconsistent fields.
  factory ExportPage.fromJson(Map<String, Object?> json) {
    _rejectForbiddenPlanContent(json, asJson: true);
    try {
      final PageGeometry geometry = PageGeometry(
        mediaBox: Rect.fromJson(_readObject(json, 'mediaBox')),
        cropBox: Rect.fromJson(_readObject(json, 'cropBox')),
        rotation: _readInt(json, 'rotation'),
      );
      final Size serializedDisplaySize = Size.fromJson(
        _readObject(json, 'displaySize'),
      );
      if (!_sizeMatches(serializedDisplaySize, geometry.displaySize)) {
        throw const FormatException('displaySize must match the page geometry');
      }
      final List<Object?> rawOps = _readList(json, 'ops');
      return ExportPage(
        index: _readInt(json, 'index'),
        geometry: geometry,
        ctm: ExportCtm.fromJson(_readObject(json, 'ctm')),
        ops: <ExportOp>[
          for (final Object? op in rawOps)
            ExportOp.fromJson(_asObject(op, 'ops entry')),
        ],
        unknownFields: unknownJsonFields(json, _exportPageJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid export page JSON: ${error.message}');
    }
  }

  /// 0-based page index, contiguous from 0.
  final int index;

  /// Source page geometry; owns MediaBox, CropBox, and rotation.
  final PageGeometry geometry;

  /// Display→PDF affine matrix (normative, derived from [geometry]).
  final ExportCtm ctm;

  /// Operations in deterministic field order; at most one per field.
  final List<ExportOp> ops;

  /// PDF MediaBox.
  Rect get mediaBox => geometry.mediaBox;

  /// Effective PDF CropBox.
  Rect get cropBox => geometry.cropBox;

  /// Stored page rotation.
  int get rotation => geometry.rotation;

  /// Display-space page size derived from the geometry.
  Size get displaySize => geometry.displaySize;

  /// Serializes the page.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'index': index,
      'rotation': rotation,
      'mediaBox': mediaBox.toJson(),
      'cropBox': cropBox.toJson(),
      'displaySize': displaySize.toJson(),
      'ctm': ctm.toJson(),
      'ops': <Map<String, Object?>>[for (final ExportOp op in ops) op.toJson()],
    });
  }

  @override
  bool operator ==(Object other) {
    return other is ExportPage &&
        other.index == index &&
        other.geometry == geometry &&
        other.ctm == ctm &&
        _listEquals(other.ops, ops);
  }

  @override
  int get hashCode {
    return Object.hash(index, geometry, ctm, Object.hashAll(ops));
  }

  @override
  String toString() => 'ExportPage(index: $index, ops: ${ops.length})';
}

/// The display→PDF affine matrix from `coordinates-and-geometry.md` §5.
///
/// The matrix maps display points `(x, y)` to
/// `(a·x + c·y + e, b·x + d·y + f)`.
final class ExportCtm extends JsonObject {
  /// Creates a finite affine matrix.
  ///
  /// Throws [ArgumentError] for a non-finite coefficient.
  factory ExportCtm({
    required double a,
    required double b,
    required double c,
    required double d,
    required double e,
    required double f,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    _checkFinite(a, 'a');
    _checkFinite(b, 'b');
    _checkFinite(c, 'c');
    _checkFinite(d, 'd');
    _checkFinite(e, 'e');
    _checkFinite(f, 'f');
    _rejectForbiddenPlanContent(unknownFields, scanValues: true);
    return ExportCtm._(
      a: a,
      b: b,
      c: c,
      d: d,
      e: e,
      f: f,
      unknownFields: freezeUnknownJsonFields(unknownFields),
    );
  }

  const ExportCtm._({
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.e,
    required this.f,
    required super.unknownFields,
  });

  /// Derives the normative matrix for [geometry].
  ///
  /// The formulas are exactly `coordinates-and-geometry.md` §5; `cx0`/`cy0`
  /// and `cx1`/`cy1` are the effective CropBox corners.
  factory ExportCtm.fromGeometry(PageGeometry geometry) {
    final Rect crop = geometry.cropBox;
    final double cx0 = crop.left;
    final double cy0 = crop.top;
    final double cx1 = crop.right;
    final double cy1 = crop.bottom;
    return switch (geometry.rotation) {
      0 => ExportCtm(a: 1, b: 0, c: 0, d: -1, e: cx0, f: cy1),
      90 => ExportCtm(a: 0, b: 1, c: 1, d: 0, e: cx0, f: cy0),
      180 => ExportCtm(a: -1, b: 0, c: 0, d: 1, e: cx1, f: cy0),
      270 => ExportCtm(a: 0, b: -1, c: -1, d: 0, e: cx1, f: cy1),
      _ => throw StateError('unreachable rotation ${geometry.rotation}'),
    };
  }

  /// Reads a matrix.
  ///
  /// Throws [FormatException] for missing or non-finite coefficients.
  factory ExportCtm.fromJson(Map<String, Object?> json) {
    _rejectForbiddenPlanContent(json, asJson: true);
    try {
      return ExportCtm(
        a: _readNumber(json, 'a'),
        b: _readNumber(json, 'b'),
        c: _readNumber(json, 'c'),
        d: _readNumber(json, 'd'),
        e: _readNumber(json, 'e'),
        f: _readNumber(json, 'f'),
        unknownFields: unknownJsonFields(json, _exportCtmJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid export CTM JSON: ${error.message}');
    }
  }

  /// x scale / y shear coefficient.
  final double a;

  /// x shear / y scale coefficient.
  final double b;

  /// x shear / y scale coefficient.
  final double c;

  /// y scale coefficient.
  final double d;

  /// x translation in PDF points.
  final double e;

  /// y translation in PDF points.
  final double f;

  /// Whether [other] has the same coefficients within the geometry tolerance.
  bool matches(ExportCtm other) {
    return _numberMatches(a, other.a) &&
        _numberMatches(b, other.b) &&
        _numberMatches(c, other.c) &&
        _numberMatches(d, other.d) &&
        _numberMatches(e, other.e) &&
        _numberMatches(f, other.f);
  }

  /// Serializes the matrix.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'a': a,
      'b': b,
      'c': c,
      'd': d,
      'e': e,
      'f': f,
    });
  }

  @override
  bool operator ==(Object other) {
    return other is ExportCtm &&
        other.a == a &&
        other.b == b &&
        other.c == c &&
        other.d == d &&
        other.e == e &&
        other.f == f;
  }

  @override
  int get hashCode => Object.hash(a, b, c, d, e, f);

  @override
  String toString() => 'ExportCtm($a, $b, $c, $d, $e, $f)';
}

/// A deterministic layout operation from `contracts/export-plan.md` §2.2.
///
/// Every op carries the field identity, the T018 [Provenance] vocabulary, the
/// display-space [rect], and the mapped PDF-space [pdfRect]. Provenance is
/// never drawn and never includes labels.
sealed class ExportOp extends JsonObject {
  const ExportOp({
    required this.fieldId,
    required this.provenance,
    required this.rect,
    required this.pdfRect,
    super.unknownFields,
  });

  /// Reads one operation and dispatches on the `op` discriminator.
  ///
  /// Throws [FormatException] for an unknown discriminator or invalid payload.
  static ExportOp fromJson(Map<String, Object?> json) {
    _rejectForbiddenPlanContent(json, asJson: true);
    final String op = _readNonEmptyString(json, 'op');
    return switch (op) {
      'text' => ExportTextOp.fromJson(json),
      'checkbox' => ExportCheckboxOp.fromJson(json),
      'image' => ExportImageOp.fromJson(json),
      _ => throw const FormatException('Unknown export op discriminator'),
    };
  }

  /// Confirmed field id.
  final String fieldId;

  /// Where the field came from; never drawn.
  final Provenance provenance;

  /// Display-space rectangle in points.
  final Rect rect;

  /// Display rectangle mapped to PDF user space; verification only.
  final Rect pdfRect;

  /// Stable `op` discriminator.
  String get kind;

  /// Serializes this operation.
  Map<String, Object?> toJson();

  /// Serializes the shared op members.
  Map<String, Object?> baseJson() {
    return <String, Object?>{
      'op': kind,
      'fieldId': fieldId,
      'provenance': provenance.wireName,
      'rect': rect.toJson(),
      'pdfRect': pdfRect.toJson(),
    };
  }

  /// Validates the shared op members.
  static void checkBase({
    required String fieldId,
    required Provenance provenance,
    required Rect rect,
    required Rect pdfRect,
  }) {
    _checkNonEmpty(fieldId, 'fieldId');
    _checkPrivateMetadata(fieldId, 'fieldId');
    if (!Provenance.values.contains(provenance)) {
      throw ArgumentError('provenance is not a supported token');
    }
    if (!rect.width.isFinite || !rect.height.isFinite) {
      throw ArgumentError('rect must be finite');
    }
    if (!pdfRect.width.isFinite || !pdfRect.height.isFinite) {
      throw ArgumentError('pdfRect must be finite');
    }
    _rejectForbiddenPlanContent(rect.unknownFields, scanValues: true);
    _rejectForbiddenPlanContent(pdfRect.unknownFields, scanValues: true);
  }
}

/// A text value layout operation (`contracts/export-plan.md` §2.2).
final class ExportTextOp extends ExportOp {
  /// Creates and validates a text op.
  ///
  /// [fontSizePt] must equal the §2.2 clamp formula rounded to 0.1,
  /// [lineHeightPt] must equal 1.2 × [fontSizePt] rounded to 0.01, and
  /// [baselineFromTopPt] must equal 1.5 + 0.8 × [fontSizePt] and fit inside
  /// [rect]. The §2 example's stale `8.1` baseline is therefore refused; the
  /// normative §2.2 rule wins explicitly rather than accepting both values.
  /// [color] must be `#000000`, [lines] must be non-empty with no trailing
  /// whitespace or materialized newlines, and [overflow] must be `false`
  /// because an overflowing plan is never produced (`EXP-001`).
  ///
  /// Throws [ArgumentError] for every invalid value.
  factory ExportTextOp({
    required String fieldId,
    required Provenance provenance,
    required Rect rect,
    required Rect pdfRect,
    required double fontSizePt,
    required double lineHeightPt,
    required double baselineFromTopPt,
    String color = '#000000',
    required Iterable<String> lines,
    bool overflow = false,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    ExportOp.checkBase(
      fieldId: fieldId,
      provenance: provenance,
      rect: rect,
      pdfRect: pdfRect,
    );
    _checkFinite(fontSizePt, 'fontSizePt');
    final double expectedFontSize = _roundTo(
      (0.6 * rect.height).clamp(7.0, 12.0).toDouble(),
      1,
    );
    if (!_numberMatches(fontSizePt, expectedFontSize)) {
      throw ArgumentError(
        'fontSizePt must equal the §2.2 clamp(0.6 × rect.height, 7.0, 12.0)'
        ' rounded to 0.1',
      );
    }
    _checkPositive(lineHeightPt, 'lineHeightPt');
    final double expectedLineHeight = _roundTo(1.2 * fontSizePt, 2);
    if (!_numberMatches(lineHeightPt, expectedLineHeight)) {
      throw ArgumentError(
        'lineHeightPt must equal the §2.2 1.2 × fontSizePt rounded to 0.01',
      );
    }
    _checkFinite(baselineFromTopPt, 'baselineFromTopPt');
    final double expectedBaseline = 1.5 + 0.8 * fontSizePt;
    if (!_numberMatches(baselineFromTopPt, expectedBaseline)) {
      throw ArgumentError(
        'baselineFromTopPt must equal the §2.2 1.5 + 0.8 × fontSizePt',
      );
    }
    if (baselineFromTopPt < 0 ||
        baselineFromTopPt > rect.height + _geometryTolerance) {
      throw ArgumentError('baselineFromTopPt must fit inside rect');
    }
    if (color != '#000000') {
      throw ArgumentError('color must be #000000');
    }
    final List<String> checkedLines = lines.toList(growable: false);
    if (checkedLines.isEmpty) {
      throw ArgumentError('lines must not be empty');
    }
    for (final String line in checkedLines) {
      if (line.contains('\n') || line.contains('\r')) {
        throw ArgumentError('lines must materialize newlines');
      }
      if (line.trimRight() != line) {
        throw ArgumentError('lines must not end with trailing spaces');
      }
    }
    if (overflow) {
      throw ArgumentError(
        'overflow must be false; an overflowing plan is not produced',
      );
    }
    _rejectForbiddenPlanContent(unknownFields, scanValues: true);
    return ExportTextOp._(
      fieldId: fieldId,
      provenance: provenance,
      rect: rect,
      pdfRect: pdfRect,
      fontSizePt: fontSizePt,
      lineHeightPt: lineHeightPt,
      baselineFromTopPt: baselineFromTopPt,
      color: color,
      lines: List<String>.unmodifiable(checkedLines),
      overflow: overflow,
      unknownFields: freezeUnknownJsonFields(unknownFields),
    );
  }

  const ExportTextOp._({
    required super.fieldId,
    required super.provenance,
    required super.rect,
    required super.pdfRect,
    required this.fontSizePt,
    required this.lineHeightPt,
    required this.baselineFromTopPt,
    required this.color,
    required this.lines,
    required this.overflow,
    required super.unknownFields,
  });

  /// Reads a text op.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  factory ExportTextOp.fromJson(Map<String, Object?> json) {
    _rejectForbiddenPlanContent(json, asJson: true);
    try {
      return ExportTextOp(
        fieldId: _readNonEmptyString(json, 'fieldId'),
        provenance: Provenance.fromWire(json['provenance']),
        rect: Rect.fromJson(_readObject(json, 'rect')),
        pdfRect: Rect.fromJson(_readObject(json, 'pdfRect')),
        fontSizePt: _readNumber(json, 'fontSizePt'),
        lineHeightPt: _readNumber(json, 'lineHeightPt'),
        baselineFromTopPt: _readNumber(json, 'baselineFromTopPt'),
        color: _readNonEmptyString(json, 'color'),
        lines: <String>[
          for (final Object? line in _readList(json, 'lines'))
            _asString(line, 'lines entry'),
        ],
        overflow: _readBool(json, 'overflow'),
        unknownFields: unknownJsonFields(json, _exportTextOpJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid export text op JSON: ${error.message}');
    }
  }

  /// Planned font size in points.
  final double fontSizePt;

  /// Planned line advance in points.
  final double lineHeightPt;

  /// Baseline offset from the top of [rect] in points.
  final double baselineFromTopPt;

  /// Ink color; v1 permits only `#000000`.
  final String color;

  /// Materialized lines, in render order.
  final List<String> lines;

  /// Always `false` in a produced plan.
  final bool overflow;

  @override
  String get kind => 'text';

  /// Serializes the text op.
  @override
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      ...baseJson(),
      'fontSizePt': fontSizePt,
      'lineHeightPt': lineHeightPt,
      'baselineFromTopPt': baselineFromTopPt,
      'color': color,
      'lines': lines,
      'overflow': overflow,
    });
  }

  @override
  bool operator ==(Object other) {
    return other is ExportTextOp &&
        other.fieldId == fieldId &&
        other.provenance == provenance &&
        other.rect == rect &&
        other.pdfRect == pdfRect &&
        other.fontSizePt == fontSizePt &&
        other.lineHeightPt == lineHeightPt &&
        other.baselineFromTopPt == baselineFromTopPt &&
        other.color == color &&
        _listEquals(other.lines, lines) &&
        other.overflow == overflow;
  }

  @override
  int get hashCode {
    return Object.hash(
      fieldId,
      provenance,
      rect,
      pdfRect,
      fontSizePt,
      lineHeightPt,
      baselineFromTopPt,
      color,
      Object.hashAll(lines),
      overflow,
    );
  }

  @override
  String toString() => 'ExportTextOp(lines: ${lines.length})';
}

/// A checkbox mark operation (`contracts/export-plan.md` §2.2).
final class ExportCheckboxOp extends ExportOp {
  /// Creates and validates a checkbox op.
  ///
  /// [insetPt] must equal the §2.2 clamp of 0.15 × min(width, height) and
  /// [strokeWidthPt] must equal the §2.2 clamp of 0.08 × min(width, height)
  /// rounded to 0.1. `checked: false` is permitted; the applier draws nothing
  /// for it.
  ///
  /// Throws [ArgumentError] for an invalid mark.
  factory ExportCheckboxOp({
    required String fieldId,
    required Provenance provenance,
    required Rect rect,
    required Rect pdfRect,
    required bool checked,
    required double insetPt,
    required double strokeWidthPt,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    ExportOp.checkBase(
      fieldId: fieldId,
      provenance: provenance,
      rect: rect,
      pdfRect: pdfRect,
    );
    _checkFinite(insetPt, 'insetPt');
    final double minSide = math.min(rect.width, rect.height).toDouble();
    final double expectedInset = (0.15 * minSide).clamp(0.5, 3.0).toDouble();
    if (!_numberMatches(insetPt, expectedInset)) {
      throw ArgumentError(
        'insetPt must equal the §2.2 clamp(0.15 × min(width, height),'
        ' 0.5, 3.0)',
      );
    }
    _checkFinite(strokeWidthPt, 'strokeWidthPt');
    final double expectedStroke = _roundTo(
      (0.08 * minSide).clamp(0.6, 1.4).toDouble(),
      1,
    );
    if (!_numberMatches(strokeWidthPt, expectedStroke)) {
      throw ArgumentError(
        'strokeWidthPt must equal the §2.2 clamp(0.08 × min(width, height),'
        ' 0.6, 1.4) rounded to 0.1',
      );
    }
    _rejectForbiddenPlanContent(unknownFields, scanValues: true);
    return ExportCheckboxOp._(
      fieldId: fieldId,
      provenance: provenance,
      rect: rect,
      pdfRect: pdfRect,
      checked: checked,
      insetPt: insetPt,
      strokeWidthPt: strokeWidthPt,
      unknownFields: freezeUnknownJsonFields(unknownFields),
    );
  }

  const ExportCheckboxOp._({
    required super.fieldId,
    required super.provenance,
    required super.rect,
    required super.pdfRect,
    required this.checked,
    required this.insetPt,
    required this.strokeWidthPt,
    required super.unknownFields,
  });

  /// Reads a checkbox op.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  factory ExportCheckboxOp.fromJson(Map<String, Object?> json) {
    _rejectForbiddenPlanContent(json, asJson: true);
    try {
      return ExportCheckboxOp(
        fieldId: _readNonEmptyString(json, 'fieldId'),
        provenance: Provenance.fromWire(json['provenance']),
        rect: Rect.fromJson(_readObject(json, 'rect')),
        pdfRect: Rect.fromJson(_readObject(json, 'pdfRect')),
        checked: _readBool(json, 'checked'),
        insetPt: _readNumber(json, 'insetPt'),
        strokeWidthPt: _readNumber(json, 'strokeWidthPt'),
        unknownFields: unknownJsonFields(json, _exportCheckboxOpJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException(
        'Invalid export checkbox op JSON: ${error.message}',
      );
    }
  }

  /// Honest checkbox state.
  final bool checked;

  /// Inset from the checkbox rect in points.
  final double insetPt;

  /// Stroke width in points.
  final double strokeWidthPt;

  @override
  String get kind => 'checkbox';

  /// Serializes the checkbox op.
  @override
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      ...baseJson(),
      'checked': checked,
      'insetPt': insetPt,
      'strokeWidthPt': strokeWidthPt,
    });
  }

  @override
  bool operator ==(Object other) {
    return other is ExportCheckboxOp &&
        other.fieldId == fieldId &&
        other.provenance == provenance &&
        other.rect == rect &&
        other.pdfRect == pdfRect &&
        other.checked == checked &&
        other.insetPt == insetPt &&
        other.strokeWidthPt == strokeWidthPt;
  }

  @override
  int get hashCode {
    return Object.hash(
      fieldId,
      provenance,
      rect,
      pdfRect,
      checked,
      insetPt,
      strokeWidthPt,
    );
  }

  @override
  String toString() => 'ExportCheckboxOp(checked: $checked)';
}

/// A signature-image operation (`contracts/export-plan.md` §2.2).
final class ExportImageOp extends ExportOp {
  /// Creates and validates an image op.
  ///
  /// [assetId] must be non-empty and [fit]/[align] are the v1 fixed values
  /// `contain`/`center`.
  ///
  /// Throws [ArgumentError] for an invalid image contract.
  factory ExportImageOp({
    required String fieldId,
    required Provenance provenance,
    required Rect rect,
    required Rect pdfRect,
    required String assetId,
    String fit = 'contain',
    String align = 'center',
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    ExportOp.checkBase(
      fieldId: fieldId,
      provenance: provenance,
      rect: rect,
      pdfRect: pdfRect,
    );
    final String checkedAssetId = _checkNonEmpty(assetId, 'assetId');
    _checkPrivateMetadata(checkedAssetId, 'assetId');
    if (fit != 'contain') {
      throw ArgumentError('fit must be contain');
    }
    if (align != 'center') {
      throw ArgumentError('align must be center');
    }
    _rejectForbiddenPlanContent(unknownFields, scanValues: true);
    return ExportImageOp._(
      fieldId: fieldId,
      provenance: provenance,
      rect: rect,
      pdfRect: pdfRect,
      assetId: checkedAssetId,
      fit: fit,
      align: align,
      unknownFields: freezeUnknownJsonFields(unknownFields),
    );
  }

  const ExportImageOp._({
    required super.fieldId,
    required super.provenance,
    required super.rect,
    required super.pdfRect,
    required this.assetId,
    required this.fit,
    required this.align,
    required super.unknownFields,
  });

  /// Reads an image op.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  factory ExportImageOp.fromJson(Map<String, Object?> json) {
    _rejectForbiddenPlanContent(json, asJson: true);
    try {
      return ExportImageOp(
        fieldId: _readNonEmptyString(json, 'fieldId'),
        provenance: Provenance.fromWire(json['provenance']),
        rect: Rect.fromJson(_readObject(json, 'rect')),
        pdfRect: Rect.fromJson(_readObject(json, 'pdfRect')),
        assetId: _readNonEmptyString(json, 'assetId'),
        fit: _readNonEmptyString(json, 'fit'),
        align: _readNonEmptyString(json, 'align'),
        unknownFields: unknownJsonFields(json, _exportImageOpJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid export image op JSON: ${error.message}');
    }
  }

  /// Signature asset id in the same document.
  final String assetId;

  /// v1 fixed fit.
  final String fit;

  /// v1 fixed alignment.
  final String align;

  @override
  String get kind => 'image';

  /// Serializes the image op.
  @override
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      ...baseJson(),
      'assetId': assetId,
      'fit': fit,
      'align': align,
    });
  }

  @override
  bool operator ==(Object other) {
    return other is ExportImageOp &&
        other.fieldId == fieldId &&
        other.provenance == provenance &&
        other.rect == rect &&
        other.pdfRect == pdfRect &&
        other.assetId == assetId &&
        other.fit == fit &&
        other.align == align;
  }

  @override
  int get hashCode {
    return Object.hash(fieldId, provenance, rect, pdfRect, assetId, fit, align);
  }

  @override
  String toString() => 'ExportImageOp(fit: $fit, align: $align)';
}

/// The blocking result of `PdfExportPort.validate` (`contracts/ports.md` §2.5).
///
/// `contracts/export-plan.md` §4 lists exactly the blocking codes. A valid
/// result has no warnings and permits the applier to start; any warning stops
/// export and carries the German catalog code plus the optional field context.
/// A failed or partial export is therefore never represented as a valid plan.
final class ExportValidation extends JsonObject {
  /// Creates a validation result.
  ///
  /// [validatedAt] must be UTC. Warnings are retained in input order.
  ///
  /// Throws [ArgumentError] for a local timestamp or an invalid warning.
  factory ExportValidation({
    required Iterable<ExportValidationWarning> warnings,
    required DateTime validatedAt,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    _checkUtc(validatedAt, 'validatedAt');
    final List<ExportValidationWarning> checkedWarnings =
        List<ExportValidationWarning>.unmodifiable(
          warnings.toList(growable: false),
        );
    for (final ExportValidationWarning warning in checkedWarnings) {
      if (!exportBlockingWarningCodes.contains(warning.code)) {
        throw ArgumentError('warning code is not a blocking export code');
      }
    }
    return ExportValidation._(
      warnings: checkedWarnings,
      validatedAt: validatedAt,
      unknownFields: freezeUnknownJsonFields(unknownFields),
    );
  }

  const ExportValidation._({
    required this.warnings,
    required this.validatedAt,
    required super.unknownFields,
  });

  /// Reads a validation result.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  factory ExportValidation.fromJson(Map<String, Object?> json) {
    try {
      return ExportValidation(
        warnings: <ExportValidationWarning>[
          for (final Object? warning in _readList(json, 'warnings'))
            ExportValidationWarning.fromJson(
              _asObject(warning, 'warnings entry'),
            ),
        ],
        validatedAt: parseCanonicalUtcTimestamp(
          json['validatedAt'],
          name: 'validatedAt',
        ),
        unknownFields: unknownJsonFields(json, _exportValidationJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid export validation JSON: ${error.message}');
    }
  }

  /// Blocking warnings; empty means the plan may be applied.
  final List<ExportValidationWarning> warnings;

  /// Validation time in UTC.
  final DateTime validatedAt;

  /// Whether no blocking warning exists.
  bool get isValid => warnings.isEmpty;

  /// Whether at least one blocking warning exists.
  bool get isBlocking => warnings.isNotEmpty;

  /// Alias used by export use cases.
  bool get hasBlockingWarnings => warnings.isNotEmpty;

  /// Serializes the validation result.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'warnings': <Map<String, Object?>>[
        for (final ExportValidationWarning warning in warnings)
          warning.toJson(),
      ],
      'validatedAt': canonicalUtcTimestamp(validatedAt),
    });
  }

  @override
  bool operator ==(Object other) {
    return other is ExportValidation &&
        _listEquals(other.warnings, warnings) &&
        other.validatedAt == validatedAt;
  }

  @override
  int get hashCode {
    return Object.hash(Object.hashAll(warnings), validatedAt);
  }

  @override
  String toString() => 'ExportValidation(warnings: ${warnings.length})';
}

/// One blocking export warning (`contracts/export-plan.md` §4).
///
/// [fieldLabel] is user content and is deliberately excluded from
/// [toString]; it appears only in the blocking dialog and is never logged.
final class ExportValidationWarning extends JsonObject {
  /// Creates a blocking warning.
  ///
  /// [code] must be one of [exportBlockingWarningCodes], [reason] must be a
  /// non-empty machine reason, [pageIndex] must be non-negative, and
  /// [fieldId] must be non-empty when present.
  ///
  /// Throws [ArgumentError] for every invalid value.
  factory ExportValidationWarning({
    required String code,
    required String reason,
    String? fieldId,
    int? pageIndex,
    String? fieldLabel,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    if (!exportBlockingWarningCodes.contains(code)) {
      throw ArgumentError('code is not a blocking export code');
    }
    final String checkedReason = _checkNonEmpty(reason, 'reason');
    final String? checkedFieldId = fieldId == null
        ? null
        : _checkNonEmpty(fieldId, 'fieldId');
    if (pageIndex != null && pageIndex < 0) {
      throw ArgumentError('pageIndex must not be negative');
    }
    return ExportValidationWarning._(
      code: code,
      reason: checkedReason,
      fieldId: checkedFieldId,
      pageIndex: pageIndex,
      fieldLabel: fieldLabel,
      unknownFields: freezeUnknownJsonFields(unknownFields),
    );
  }

  const ExportValidationWarning._({
    required this.code,
    required this.reason,
    required this.fieldId,
    required this.pageIndex,
    required this.fieldLabel,
    required super.unknownFields,
  });

  /// Reads a blocking warning.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  factory ExportValidationWarning.fromJson(Map<String, Object?> json) {
    try {
      final Object? pageIndex = json['pageIndex'];
      return ExportValidationWarning(
        code: _readNonEmptyString(json, 'code'),
        reason: _readNonEmptyString(json, 'reason'),
        fieldId: json['fieldId'] == null
            ? null
            : _readNonEmptyString(json, 'fieldId'),
        pageIndex: pageIndex == null ? null : _asInt(pageIndex, 'pageIndex'),
        fieldLabel: json['fieldLabel'] == null
            ? null
            : _asString(json['fieldLabel'], 'fieldLabel'),
        unknownFields: unknownJsonFields(
          json,
          _exportValidationWarningJsonKeys,
        ),
      );
    } on ArgumentError catch (error) {
      throw FormatException(
        'Invalid export validation warning JSON: ${error.message}',
      );
    }
  }

  /// Stable catalog code such as `EXP-001`.
  final String code;

  /// Machine reason such as `too_wide` or `glyph_missing`.
  final String reason;

  /// Affected field id when the warning is field-specific.
  final String? fieldId;

  /// Affected 0-based page index when known.
  final int? pageIndex;

  /// User-visible field label; never logged.
  final String? fieldLabel;

  /// Serializes the warning; null optional members are omitted.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'code': code,
      'reason': reason,
      if (fieldId != null) 'fieldId': fieldId,
      if (pageIndex != null) 'pageIndex': pageIndex,
      if (fieldLabel != null) 'fieldLabel': fieldLabel,
    });
  }

  @override
  bool operator ==(Object other) {
    return other is ExportValidationWarning &&
        other.code == code &&
        other.reason == reason &&
        other.fieldId == fieldId &&
        other.pageIndex == pageIndex &&
        other.fieldLabel == fieldLabel;
  }

  @override
  int get hashCode {
    return Object.hash(code, reason, fieldId, pageIndex, fieldLabel);
  }

  @override
  String toString() => 'ExportValidationWarning(code: $code)';
}

/// Rejects forbidden plan content at any depth (`contracts/export-plan.md`
/// §2.3).
///
/// [scanValues] is used for the two content classes that are not otherwise
/// constrained by the schema: `ExportPlan.warnings` and same-schema unknown
/// fields. It refuses URIs, absolute paths, device names, and user identifiers
/// while leaving relative text and ordinary extension values intact. Known
/// field values such as confirmed text lines are not scanned here; they are the
/// user's export content and must stay exportable.
void _rejectForbiddenPlanContent(
  Object? value, {
  bool asJson = false,
  bool scanValues = false,
}) {
  Never fail(String message) {
    if (asJson) {
      throw FormatException(message);
    }
    throw ArgumentError(message);
  }

  void checkPrivateText(String text) {
    if (_containsForbiddenLocation(text)) {
      fail('Export plan must not contain an absolute path or URI');
    }
    if (_emailPattern.hasMatch(text) ||
        _userHandlePattern.hasMatch(text) ||
        _userIdPattern.hasMatch(text)) {
      fail('Export plan must not contain a user identifier');
    }
    if (_deviceNamePattern.hasMatch(text)) {
      fail('Export plan must not contain a device name');
    }
  }

  final Set<Object> ancestors = HashSet<Object>.identity();
  void walk(Object? node) {
    if (node is Map<Object?, Object?>) {
      if (!ancestors.add(node)) {
        fail('Export plan JSON must not contain cycles');
      }
      for (final MapEntry<Object?, Object?> entry in node.entries) {
        final Object? key = entry.key;
        if (key is! String) {
          fail('Export plan JSON object keys must be strings');
        }
        if (_forbiddenPlanKeys.contains(key.toLowerCase())) {
          fail('Export plan must not contain "$key"');
        }
        if (scanValues) {
          checkPrivateText(key);
        }
        walk(entry.value);
      }
      ancestors.remove(node);
      return;
    }
    if (node is List<Object?>) {
      if (!ancestors.add(node)) {
        fail('Export plan JSON must not contain cycles');
      }
      for (final Object? item in node) {
        walk(item);
      }
      ancestors.remove(node);
      return;
    }
    if (scanValues && node is String) {
      checkPrivateText(node);
    }
  }

  walk(value);
}

/// Whether [value] contains an absolute path or a URI token.
///
/// Relative paths such as `assets/fonts/NotoSans-Regular.ttf` and ordinary
/// punctuation such as `Feld A / B` remain allowed.
bool _containsForbiddenLocation(String value) {
  if (_uriSchemePattern.hasMatch(value) ||
      _knownSchemeContextPattern.hasMatch(value)) {
    return true;
  }
  final List<String> tokens = value.split(RegExp(r'\s+'));
  for (final String raw in tokens) {
    final String token = raw
        .replaceFirst(RegExp(r'''^[\(\[\{"']+'''), '')
        .replaceFirst(RegExp(r'''[\)\]\}"',;:.!?]+$'''), '');
    if (token.isEmpty || token == '/' || token == '\\' || token == '~') {
      continue;
    }
    if (token.startsWith('/') ||
        token.startsWith('\\') ||
        token.startsWith('~/') ||
        token.startsWith('~\\') ||
        _windowsDrivePattern.hasMatch(token) ||
        _knownSchemePattern.hasMatch(token)) {
      return true;
    }
  }
  if (RegExp(r'(?:^|[\s(:=,;<>|])/(?:[^\s)])').hasMatch(value)) {
    return true;
  }
  if (RegExp(r'(?:^|[\s(:=,;<>|])\\\\[^\s]').hasMatch(value)) {
    return true;
  }
  if (RegExp(r'(?:^|[\s(:=,;<>|])[A-Za-z]:[\\/]').hasMatch(value)) {
    return true;
  }
  return false;
}

String _checkUuidV4(String value, String name) {
  if (!_uuidV4Pattern.hasMatch(value)) {
    throw ArgumentError('$name must be a lowercase UUIDv4');
  }
  return value;
}

String _checkSha256(String value, String name) {
  if (!_sha256Pattern.hasMatch(value)) {
    throw ArgumentError('$name must be 64 lowercase hex characters');
  }
  return value;
}

String _checkNonEmpty(String value, String name) {
  if (value.isEmpty) {
    throw ArgumentError('$name must not be empty');
  }
  return value;
}

String _checkBundledAssetPath(String value, String name) {
  _checkNonEmpty(value, name);
  if (value.startsWith('/') ||
      value.startsWith('\\') ||
      value.contains('\\') ||
      value.contains(':')) {
    throw ArgumentError('$name must be a relative bundled asset path');
  }
  final List<String> segments = value.split('/');
  if (segments.any((String segment) => segment.isEmpty || segment == '..')) {
    throw ArgumentError('$name must not contain empty or parent segments');
  }
  return value;
}

/// Rejects private metadata in a schema string that is not user export content.
///
/// `warnings` and unknown fields use [_rejectForbiddenPlanContent] so a JSON
/// read reports a `FormatException`; known metadata strings use this helper and
/// report `ArgumentError`. Confirmed field `lines` are user content and are not
/// passed through this gate.
void _checkPrivateMetadata(String value, String name) {
  if (_containsForbiddenLocation(value)) {
    throw ArgumentError('$name must not contain an absolute path or URI');
  }
  if (_emailPattern.hasMatch(value) ||
      _userHandlePattern.hasMatch(value) ||
      _userIdPattern.hasMatch(value)) {
    throw ArgumentError('$name must not contain a user identifier');
  }
  if (_deviceNamePattern.hasMatch(value)) {
    throw ArgumentError('$name must not contain a device name');
  }
}

void _checkUtc(DateTime value, String name) {
  if (!value.isUtc) {
    throw ArgumentError('$name must be UTC');
  }
}

void _checkFinite(double value, String name) {
  if (!value.isFinite) {
    throw ArgumentError('$name must be finite');
  }
}

void _checkPositive(double value, String name) {
  _checkFinite(value, name);
  if (value <= 0) {
    throw ArgumentError('$name must be positive');
  }
}

double _roundTo(double value, int decimals) {
  final double factor = math.pow(10, decimals).toDouble();
  return (value * factor).roundToDouble() / factor;
}

bool _numberMatches(double left, double right) {
  return (left - right).abs() <= _geometryTolerance;
}

bool _sizeMatches(Size left, Size right) {
  return _numberMatches(left.width, right.width) &&
      _numberMatches(left.height, right.height);
}

bool _rectMatches(Rect left, Rect right) {
  return _numberMatches(left.left, right.left) &&
      _numberMatches(left.top, right.top) &&
      _numberMatches(left.right, right.right) &&
      _numberMatches(left.bottom, right.bottom);
}

String _readNonEmptyString(Map<String, Object?> json, String name) {
  final Object? value = json[name];
  if (value is! String || value.isEmpty) {
    throw FormatException('JSON field "$name" must be a non-empty string');
  }
  return value;
}

int _readInt(Map<String, Object?> json, String name) {
  final Object? value = json[name];
  if (value is! int) {
    throw FormatException('JSON field "$name" must be an integer');
  }
  return value;
}

double _readNumber(Map<String, Object?> json, String name) {
  final Object? value = json[name];
  if (value is! num || !value.isFinite) {
    throw FormatException('JSON field "$name" must be a finite number');
  }
  return value.toDouble();
}

bool _readBool(Map<String, Object?> json, String name) {
  final Object? value = json[name];
  if (value is! bool) {
    throw FormatException('JSON field "$name" must be a boolean');
  }
  return value;
}

Map<String, Object?> _readObject(Map<String, Object?> json, String name) {
  final Object? value = json[name];
  if (value is! Map<String, Object?>) {
    throw FormatException('JSON field "$name" must be an object');
  }
  return value;
}

List<Object?> _readList(Map<String, Object?> json, String name) {
  final Object? value = json[name];
  if (value is! List<Object?>) {
    throw FormatException('JSON field "$name" must be an array');
  }
  return value;
}

Map<String, Object?> _asObject(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$name must be an object');
  }
  return value;
}

String _asString(Object? value, String name) {
  if (value is! String) {
    throw FormatException('$name must be a string');
  }
  return value;
}

int _asInt(Object? value, String name) {
  if (value is! int) {
    throw FormatException('$name must be an integer');
  }
  return value;
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
