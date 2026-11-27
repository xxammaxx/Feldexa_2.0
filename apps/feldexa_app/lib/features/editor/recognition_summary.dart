// T124 provenance distinction in the document summary (FR-085; US8
// scenarios 3 and 5).
//
// Normative sources:
//   * `spec.md` FR-085 — users MUST be able to distinguish automatic
//     suggestions from confirmed fields and their own manual entries, at a
//     glance and in any summary;
//   * `contracts/recognition-output.md` §2 (no-completeness note) and §7
//     (confirming a suggestion creates a `ConfirmedField` with
//     `provenance = machine`, `sourceSuggestionId`, and
//     `suggestionConfidence`);
//   * `contracts/error-catalog.de.md` §2 — the summary uses „Vorschläge“,
//     „unsicher“, and „bestätigt“ and never states or implies that
//     recognition is complete or error-free.
//
// The projection is pure: `RecognitionSummaryCounts.fromParts` consumes the
// canonical core value objects (`FieldSuggestion`, `ConfirmedField`) and the
// widget renders German labels from the ARB only. The summary never claims
// completeness: the note line states explicitly that detection is
// provisional until every suggestion is reviewed.

import 'package:feldexa_core/feldexa_core.dart';
// T122: the summary's „unsicher“ sub-count uses the shared uncertainty
// thresholds, so document view, review badge, and summary can never drift.
import 'package:feldexa_ui/feldexa_ui.dart' show UncertaintyThresholds;
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Stable key for the summary card in widget tests.
const String recognitionSummaryKey = 'recognition-summary';

/// Key prefix for one summary row, followed by the group name.
const String recognitionSummaryRowKeyPrefix = 'recognition-summary-row-';

/// Stable key for the summary's no-completeness note line.
const String recognitionSummaryNoteKey = 'recognition-summary-note';

/// The provenance groups of the recognition summary.
///
/// The order is fixed and rendered top to bottom: the user's own manual
/// entries, suggestions adopted by confirmation, fields inherited from a
/// pinned template version, and the suggestions that are still open.
enum RecognitionSummaryGroup {
  /// Fields the user created manually (`Provenance.user`).
  manual('manual'),

  /// Suggestions confirmed by the user (`Provenance.machine`).
  adopted('adopted'),

  /// Fields inherited from a pinned template version
  /// (`Provenance.template`).
  template('template'),

  /// Suggestions neither confirmed nor rejected yet.
  open('open');

  const RecognitionSummaryGroup(this.name);

  /// Stable token used in widget-test keys.
  final String name;
}

/// Counts per provenance group, plus the open-but-uncertain overlap.
@immutable
final class RecognitionSummaryCounts {
  const RecognitionSummaryCounts({
    required this.manual,
    required this.adopted,
    required this.template,
    required this.open,
    required this.openUncertain,
  });

  /// Projects the summary from confirmed fields and unresolved suggestions.
  ///
  /// Suggestions in any resolution state other than `unresolved` (confirmed
  /// or rejected) are not counted again as open: a confirmed suggestion
  /// appears under [RecognitionSummaryGroup.adopted] through its
  /// `ConfirmedField`, a rejected suggestion appears nowhere — it is
  /// excluded from the review stream by contract §7.
  factory RecognitionSummaryCounts.fromParts(
    Iterable<ConfirmedField> confirmedFields,
    Iterable<FieldSuggestion> suggestions,
  ) {
    int manual = 0;
    int adopted = 0;
    int template = 0;
    for (final ConfirmedField field in confirmedFields) {
      switch (field.provenance) {
        case Provenance.user:
          manual += 1;
        case Provenance.machine:
          adopted += 1;
        case Provenance.template:
          template += 1;
      }
    }
    int open = 0;
    int openUncertain = 0;
    for (final FieldSuggestion suggestion in suggestions) {
      if (suggestion.resolution != SuggestionResolution.unresolved) {
        continue;
      }
      open += 1;
      if (suggestion.confidence < UncertaintyThresholds.uncertain) {
        openUncertain += 1;
      }
    }
    return RecognitionSummaryCounts(
      manual: manual,
      adopted: adopted,
      template: template,
      open: open,
      openUncertain: openUncertain,
    );
  }

  /// Fields the user created manually.
  final int manual;

  /// Suggestions the user confirmed („übernommen“).
  final int adopted;

  /// Fields inherited from a pinned template version.
  final int template;

  /// Suggestions still awaiting a decision.
  final int open;

  /// How many of [open] carry the sub-0.50 „unsicher“ marker (FR-083).
  final int openUncertain;

  /// Whether every group is empty.
  bool get isEmpty => manual == 0 && adopted == 0 && template == 0 && open == 0;
}

/// The document-summary provenance card (FR-085).
///
/// Renders one German row per provenance group, visible at a glance and at
/// 200 % text scale, plus the mandatory no-completeness note. The card is
/// read-only: it proposes no action and asserts nothing about recognition
/// quality beyond the counts and the „unsicher“ marker.
class RecognitionSummary extends StatelessWidget {
  const RecognitionSummary({super.key, required this.counts});

  /// The projection to render.
  final RecognitionSummaryCounts counts;

  String _label(AppLocalizations l10n, RecognitionSummaryGroup group) {
    return switch (group) {
      RecognitionSummaryGroup.manual => l10n.recognitionSummaryManual(
        counts.manual,
      ),
      RecognitionSummaryGroup.adopted => l10n.recognitionSummaryAdopted(
        counts.adopted,
      ),
      RecognitionSummaryGroup.template => l10n.recognitionSummaryTemplate(
        counts.template,
      ),
      RecognitionSummaryGroup.open =>
        counts.openUncertain > 0
            ? '${l10n.recognitionSummaryOpen(counts.open)} '
                  '${l10n.recognitionSummaryUncertain(counts.openUncertain)}'
            : l10n.recognitionSummaryOpen(counts.open),
    };
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Column(
        key: const ValueKey<String>(recognitionSummaryKey),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            AppLocalizations.of(context).recognitionSummaryTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final RecognitionSummaryGroup group
              in RecognitionSummaryGroup.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _label(AppLocalizations.of(context), group),
                key: ValueKey<String>(
                  '$recognitionSummaryRowKeyPrefix${group.name}',
                ),
                style: theme.textTheme.bodyMedium,
                softWrap: true,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).recognitionSummaryNote,
            key: const ValueKey<String>(recognitionSummaryNoteKey),
            style: theme.textTheme.bodySmall,
            softWrap: true,
          ),
        ],
      ),
    );
  }
}
