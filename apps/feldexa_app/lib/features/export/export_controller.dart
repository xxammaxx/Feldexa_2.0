// Issue #334 export controller for the editor/export route (T106/T107 UI).
//
// Owner: `apps/feldexa_app/lib/features/export/export_controller.dart`.
//
// Normative sources:
//   * `contracts/export-plan.md` §1 (preflight → layout → plan), §2 (the
//     canonical plan), §3.4 (empty-field and unresolved-suggestion info), §4
//     (blocking codes), and §5 (a returned artifact is verified);
//   * `contracts/ports.md` §2.5 (`PdfExportPort.validate`/`export`) and §2.6
//     (`DeliveryPort`);
//   * `contracts/error-catalog.de.md` §4 and §10 — the German texts and the
//     developer-only codes of the export flow;
//   * `contracts/editor-interactions.md` §10 (the export flow: preflight
//     information before the export, blocking warnings stop it);
//   * FR-062, FR-068, FR-070, FR-072.
//
// The controller is the whole non-visual export step: it builds the canonical
// plan from the editor's verified snapshot, asks the port to validate it, and
// only then asks the port to render. Blocking validation never starts a render
// and never produces an artifact. It performs no widget work, holds no path,
// URI, or artifact bytes, and never logs content.
//
// The provisional OD-1 behavior is inherited from `feldexa_export` and is not
// re-decided here: unresolved suggestions are excluded from the plan and
// counted in `ExportPlanInfo.unresolvedSuggestionCount`; they do not block.

import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// The asset path declared in `apps/feldexa_app/pubspec.yaml` (T007).
const String exportFontMetricsAsset = 'assets/fonts/metrics.json';

/// Loads the bundled Noto Sans advance table used by the export layout.
///
/// The table is the committed `assets/fonts/metrics.json`; it is read through
/// the Flutter asset bundle, so no build path or file system location is
/// involved.
Future<ExportFontMetrics> loadExportFontMetrics({AssetBundle? bundle}) async {
  final String source = await (bundle ?? rootBundle).loadString(
    exportFontMetricsAsset,
  );
  return ExportFontMetrics.decode(source);
}

/// A plan was built; the export may be validated and rendered.
final class ExportPreparationReady extends ExportPreparation {
  const ExportPreparationReady(this.plan);

  /// The canonical, deterministic plan of this snapshot.
  final ExportPlan plan;

  /// Pre-export information shown before the export starts (`§3.4`).
  ExportPlanInfo get info => plan.info;
}

/// The snapshot cannot be exported; no plan exists (`EXP-001`, `EXP-003`,
/// `EXP-004`, `EXP-005`, `EXP-006`, or `SAVE-001`).
final class ExportPreparationBlocked extends ExportPreparation {
  const ExportPreparationBlocked(this.validation);

  /// The blocking warnings in canonical order.
  final ExportValidation validation;
}

/// The outcome of [ExportController.prepare].
sealed class ExportPreparation {
  const ExportPreparation();
}

/// The outcome of [ExportController.run].
sealed class ExportAttempt {
  const ExportAttempt();
}

/// A verified artifact exists and the preview may open.
final class ExportAttemptSucceeded extends ExportAttempt {
  const ExportAttemptSucceeded({required this.plan, required this.artifact});

  /// The plan the artifact was rendered from.
  final ExportPlan plan;

  /// The verified artifact; it carries the session id, page count, and size.
  final ExportArtifact artifact;
}

/// Validation blocked the export; no artifact exists.
final class ExportAttemptBlocked extends ExportAttempt {
  const ExportAttemptBlocked(this.validation);

  /// The blocking warnings in canonical order.
  final ExportValidation validation;
}

/// The export failed or was cancelled; no artifact exists.
final class ExportAttemptFailed extends ExportAttempt {
  const ExportAttemptFailed(this.code);

  /// Stable catalog code, for example `EXP-002`, `SAVE-001`, or `PLT-004`.
  final String code;
}

/// Builds, validates, and renders one export from the editor snapshot.
///
/// The controller never mutates the snapshot and never touches the document
/// store: the source document and the stored revision stay unchanged
/// (FR-073).
final class ExportController {
  /// Creates a controller over one session's ports.
  ///
  /// [metrics] is the bundled advance table ([loadExportFontMetrics]),
  /// [clock] supplies the UTC validation time, and [evidenceClass] is one of
  /// the `contracts/export-plan.md` §2 tokens (`simulated`, `emulator`,
  /// `device`, `none`). [builder] exists so a test can inject the same builder
  /// without re-reading the asset.
  ExportController({
    required this.exportPort,
    required this.clock,
    required this.metrics,
    required this.evidenceClass,
    ExportPlanBuilder? builder,
  }) : _builder = builder ?? ExportPlanBuilder(metrics: metrics);

  /// The export port of this session.
  final PdfExportPort exportPort;

  /// UTC clock used for `validatedAt`.
  final ClockPort clock;

  /// The bundled font metrics of the plan.
  final ExportFontMetrics metrics;

  /// The `evidenceClass` token written into the plan.
  final String evidenceClass;

  final ExportPlanBuilder _builder;

  /// Builds the plan for [loaded]; no port is called.
  ///
  /// Returns [ExportPreparationBlocked] for every blocking preflight or layout
  /// warning (FR-068): an overflowing, unplaceable, or unrenderable value is
  /// never silently shrunk, truncated, or omitted.
  ///
  /// Throws [StateError] when the snapshot carries no durable revision id or no
  /// source hash, because the plan cannot identify what it exports then. Both
  /// values are store-verified, so the failure is a programming error in the
  /// caller, not user data.
  ExportPreparation prepare(LoadedDocument loaded) {
    final String? revisionId = loaded.meta.latestRevisionId;
    if (revisionId == null) {
      throw StateError('the export requires a durable revision');
    }
    final core.Document document = _exportDocument(loaded, revisionId);
    final ExportPlanBuildResult built = _builder.build(
      document: document,
      pageGeometries: <core.PageGeometry>[
        for (final core.Page page in loaded.content.pages) page.geometry,
      ],
      values: loaded.content.values,
      signatures: loaded.content.signatures,
      evidenceClass: evidenceClass,
      sourceSha256: loaded.meta.source.sha256,
      revisionId: revisionId,
      validatedAt: clock.nowUtc().toUtc(),
    );
    if (built case ExportPlanBuildSuccess(:final ExportPlan plan)) {
      return ExportPreparationReady(plan);
    }
    return ExportPreparationBlocked(
      (built as ExportPlanBuildBlocked).validation,
    );
  }

  /// Validates and renders [preparation]; never calls `export` when validation
  /// blocks.
  ///
  /// A returned artifact is the port's verified result; a throw becomes
  /// [ExportAttemptFailed] with the catalog code of the failure. An
  /// unclassified throw is reported as `EXP-002`, which is exactly the true
  /// statement \"the export failed and no valid PDF file was created\"; no
  /// cause is invented.
  Future<ExportAttempt> run(ExportPreparationReady preparation) async {
    final ExportPlan plan = preparation.plan;
    try {
      final ExportValidationResult validation = await exportPort.validate(plan);
      if (validation.isBlocking) {
        return ExportAttemptBlocked(validation.validation);
      }
      final ExportResult result = await exportPort.export(
        ExportRequest(
          documentId: plan.documentId,
          revisionId: plan.revisionId,
          plan: plan,
        ),
      );
      return ExportAttemptSucceeded(plan: plan, artifact: result.artifact);
    } on ExportBlockedException catch (error) {
      return ExportAttemptFailed(error.code);
    } on FeldexaException catch (error) {
      return ExportAttemptFailed(error.code);
    } on FormatException {
      // A malformed channel answer is a broken export, not a produced file.
      return const ExportAttemptFailed('EXP-002');
    }
  }

  /// Builds the transient `core.Document` the shared export stages consume.
  ///
  /// Field provenance, so every value here is traceable:
  ///   * `id`, `title`, `createdAt`, `updatedAt`, and `source` come from the
  ///     store-verified `DocumentMeta` of the load;
  ///   * `pages`, `suggestions`, `fields`, `fieldOrder`, `values`,
  ///     `signatures`, `verification`, and `templateOrigin` are the verified
  ///     `RevisionContent` of the same load, unchanged and unfiltered;
  ///   * `lastDurable` is *not* part of a revision snapshot
  ///     (`RevisionContent.fromDocument` excludes the durable head), so it is
  ///     reconstructed from the store values `latestRevisionId` and
  ///     `lastDurableAt`. Its `sha256` is filled with the verified
  ///     **source** hash: the revision hash is not exposed by the store port,
  ///     and no export stage reads this field.
  ///
  /// Preflight, layout, and plan assembly read only the page count, the
  /// confirmed fields, the suggestions, and the values/signatures maps; none
  /// of them reads `lastDurable`. The document is therefore transient: it must
  /// never be persisted, serialized, or logged, and it is passed only to the
  /// plan builder. Replacing this reconstruction with an export-side snapshot
  /// constructor is tracked as a follow-up.
  core.Document _exportDocument(LoadedDocument loaded, String revisionId) {
    final core.DocumentMeta meta = loaded.meta;
    final core.RevisionContent content = loaded.content;
    return core.Document(
      id: meta.id,
      title: meta.title,
      createdAt: meta.createdAt,
      updatedAt: meta.updatedAt,
      source: meta.source,
      pages: content.pages,
      suggestions: content.suggestions,
      fields: content.fields,
      fieldOrder: content.fieldOrder,
      values: content.values,
      signatures: content.signatures,
      verification: content.verification,
      templateOrigin: content.templateOrigin,
      lastDurable: core.DurablePointer(
        revisionId: revisionId,
        kind: 'autosave',
        committedAt: meta.lastDurableAt ?? meta.updatedAt,
        sha256: meta.source.sha256,
      ),
    );
  }
}

/// One German message with its recovery guidance from the committed ARB.
final class ExportFailureText {
  const ExportFailureText({required this.message, this.recovery});

  /// The catalog message (`contracts/error-catalog.de.md` §4).
  final String message;

  /// The catalog recovery guidance, when the row has one.
  final String? recovery;
}

/// Maps a blocking validation to one German text per distinct catalog code.
///
/// Every sentence comes from the committed ARB; no wording is composed here.
/// The `{fields}` placeholder is filled only with the `fieldLabel` values the
/// warnings carry — the catalog's own field labels are user content and are
/// never inferred from a field id, so a warning set without labels falls back
/// to the generic `EXP-002` sentence instead of rendering a dangling
/// placeholder. A `EXP-006` row without a page index is treated the same way
/// rather than inventing a page number.
List<ExportFailureText> exportBlockedTexts(
  AppLocalizations l10n,
  ExportValidation validation,
) {
  final List<String> codes = <String>[];
  for (final ExportValidationWarning warning in validation.warnings) {
    if (!codes.contains(warning.code)) {
      codes.add(warning.code);
    }
  }
  return <ExportFailureText>[
    for (final String code in codes) _blockedText(l10n, code, validation),
  ];
}

/// Maps one failure code to its German text, or null when the catalog has no
/// user-facing message for it.
///
/// `PLT-002`, `PLT-003`, and `PLT-004` are developer-only codes (§10) with no
/// ARB row. A rejected payload (`PLT-002`, `PLT-003`) still means no valid PDF
/// was created, so it reports the generic `EXP-002` sentence; a cancelled
/// operation (`PLT-004`) reports nothing because the user cancelled it.
ExportFailureText? exportFailureCodeText(AppLocalizations l10n, String code) {
  return switch (code) {
    'PLT-004' => null,
    'PLT-002' || 'PLT-003' => _genericFailure(l10n),
    'EXP-002' => ExportFailureText(
      message: l10n.exp002,
      recovery: l10n.exp002Recovery,
    ),
    'EXP-005' => ExportFailureText(
      message: l10n.exp005,
      recovery: l10n.exp005Recovery,
    ),
    'SAVE-001' => ExportFailureText(
      message: l10n.save001Export,
      recovery: l10n.save001ExportRecovery,
    ),
    _ => _genericFailure(l10n),
  };
}

ExportFailureText _blockedText(
  AppLocalizations l10n,
  String code,
  ExportValidation validation,
) {
  final List<ExportValidationWarning> matching = <ExportValidationWarning>[
    for (final ExportValidationWarning warning in validation.warnings)
      if (warning.code == code) warning,
  ];
  switch (code) {
    case 'SAVE-001':
      return ExportFailureText(
        message: l10n.save001Export,
        recovery: l10n.save001ExportRecovery,
      );
    case 'EXP-003':
      final String? fields = _fieldList(matching);
      if (fields != null) {
        return ExportFailureText(
          message: l10n.exp003(fields),
          recovery: l10n.exp003Recovery,
        );
      }
    case 'EXP-004':
      final String? fields = _fieldList(matching);
      if (fields != null) {
        return ExportFailureText(
          message: l10n.exp004(fields),
          recovery: l10n.exp004Recovery,
        );
      }
    case 'EXP-001':
      final String? fields = _fieldList(matching);
      if (fields != null) {
        return ExportFailureText(
          message: l10n.exp001(matching.length, fields),
          recovery: l10n.exp001Recovery,
        );
      }
    case 'EXP-006':
      final int? pageIndex = matching.isEmpty ? null : matching.first.pageIndex;
      if (pageIndex != null) {
        return ExportFailureText(
          message: l10n.exp006(pageIndex + 1),
          recovery: l10n.exp006Recovery,
        );
      }
    case 'EXP-005':
      return ExportFailureText(
        message: l10n.exp005,
        recovery: l10n.exp005Recovery,
      );
  }
  return _genericFailure(l10n);
}

ExportFailureText _genericFailure(AppLocalizations l10n) {
  return ExportFailureText(message: l10n.exp002, recovery: l10n.exp002Recovery);
}

/// The `{fields}` value of a warning set, or null when any label is missing.
String? _fieldList(List<ExportValidationWarning> warnings) {
  final List<String> labels = <String>[];
  for (final ExportValidationWarning warning in warnings) {
    final String? label = warning.fieldLabel;
    if (label == null || label.trim().isEmpty) {
      return null;
    }
    labels.add(label);
  }
  return labels.isEmpty ? null : labels.join(', ');
}
