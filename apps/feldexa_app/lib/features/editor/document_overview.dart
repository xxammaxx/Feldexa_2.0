// T086D document overview with per-field completion and continue filling.
//
// Owner: `apps/feldexa_app/lib/features/editor/document_overview.dart` (T086D,
// issue #282).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/spec.md` US4 scenario 8 (a partially
//     filled form shows per-field completion in the document overview and the
//     user can continue filling) and FR-041;
//   * `contracts/editor-interactions.md` section 1 (the document overview is a
//     separate route, reachable without losing edits) and section 7 (per-field
//     completion plus the same durability status, never a check for unsaved
//     work);
//   * `apps/feldexa_app/lib/features/editor/field_completion.dart` (T085, the
//     single completion classifier) and `field_order.dart` (T073, the field
//     order read model);
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// What this surface is
// -----------------
// A presentation route over an already-derived read model. [entries] are the
// T073 `FieldOrderEntry` rows for one revision, so a field is never dropped,
// reordered, or invented here. Completion comes from the T085 state carried by
// each row; this file only maps it to the committed German ARB text and one
// decorative icon. Durability is the existing `DurabilityStatusLabel`, so the
// overview makes no second durability claim.
//
// Continue filling
// ---------------
// The route pops exactly one [DocumentOverviewOutcome]. „Weiter ausfüllen“
// returns to the editor without a field; tapping a field row returns its id so
// the editor can select and open that field. The editor owns all documents,
// values, and edits: this route reads no store, no clock, and no network, and
// it cannot lose a value because it never owns one.
//
// Evidence
// --------
// Covered by host-VM widget tests and the Android emulator PASS recorded in
// `reports/2026-11-22-emulator-t086d-overview.md`; DEVICE, screen-reader,
// stylus, visual and performance claims remain NOT_RUN.

library;

import 'package:feldexa_app/features/editor/durability_status.dart';
import 'package:feldexa_app/features/editor/field_completion.dart';
import 'package:feldexa_app/features/editor/field_order.dart';
import 'package:feldexa_app/features/editor/recognition_summary.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';

/// Stable key for the whole document overview route.
const ValueKey<String> documentOverviewScreenKey = ValueKey<String>(
  'document-overview-screen',
);

/// Stable key for the „Weiter ausfüllen“ action.
const ValueKey<String> documentOverviewContinueKey = ValueKey<String>(
  'document-overview-continue',
);

/// Stable key for the visible field-count summary.
const ValueKey<String> documentOverviewCountsKey = ValueKey<String>(
  'document-overview-counts',
);

/// Stable key prefix for one selectable field row.
const String documentOverviewRowKeyPrefix = 'document-overview-row-';

/// Stable key prefix for one visible completion label.
const String documentOverviewCompletionKeyPrefix =
    'document-overview-completion-';

/// The field counts shown above the overview list.
///
/// [filled] counts exactly the T085 states whose
/// [FieldCompletionStateSemantics.countsAsComplete] is true (complete,
/// optionalEmpty, warning); [blocking] counts exactly the blocking states.
/// Optional-empty is therefore a valid filled state and not a defect, matching
/// the T085 semantics and the existing `fieldCount` ARB sentence.
final class DocumentOverviewCounts {
  /// Creates an explicit count projection.
  const DocumentOverviewCounts({
    required this.total,
    required this.filled,
    required this.blocking,
  });

  /// Derives the counts from the T073 overview rows.
  factory DocumentOverviewCounts.fromEntries(
    Iterable<FieldOrderEntry> entries,
  ) {
    int total = 0;
    int filled = 0;
    int blocking = 0;
    for (final FieldOrderEntry entry in entries) {
      total += 1;
      if (entry.completion.countsAsComplete) {
        filled += 1;
      }
      if (entry.completion.isBlocking) {
        blocking += 1;
      }
    }
    return DocumentOverviewCounts(
      total: total,
      filled: filled,
      blocking: blocking,
    );
  }

  /// Every confirmed field in the document.
  final int total;

  /// Fields that count as complete under T085, including optional-empty.
  final int filled;

  /// Fields that block progress or export under T085.
  final int blocking;

  /// Whether the document has no confirmed field at all.
  bool get isEmpty => total == 0;
}

/// The single result of leaving the document overview.
///
/// A non-null [fieldId] means the user selected that field to continue filling;
/// null means „Weiter ausfüllen“ without a selection. The editor resolves the
/// id against its live revision, so a stale id can never edit a value.
final class DocumentOverviewOutcome {
  /// Returns to the editor without selecting a field.
  const DocumentOverviewOutcome.continueEditing() : fieldId = null;

  /// Returns to the editor with [fieldId] selected for filling.
  const DocumentOverviewOutcome.openField(this.fieldId);

  /// The selected confirmed field id, or null for continue-editing.
  final String? fieldId;
}

/// The German completion label for one T085 state.
String documentOverviewCompletionLabel(
  AppLocalizations l10n,
  FieldCompletionState state,
) {
  return switch (state) {
    FieldCompletionState.complete => l10n.fieldCompletionComplete,
    FieldCompletionState.optionalEmpty => l10n.fieldCompletionOptionalEmpty,
    FieldCompletionState.blockingError => l10n.fieldCompletionBlockingError,
    FieldCompletionState.warning => l10n.fieldCompletionWarning,
    FieldCompletionState.incompatible => l10n.fieldCompletionIncompatible,
  };
}

/// A decorative outline icon for one completion state.
///
/// The visible label is the only completion signal; this icon is never the sole
/// carrier (contracts/editor-interactions.md §7, FR-094).
IconData _completionIcon(FieldCompletionState state) {
  return switch (state) {
    FieldCompletionState.complete => Icons.check_circle_outline,
    FieldCompletionState.optionalEmpty => Icons.radio_button_unchecked,
    FieldCompletionState.blockingError => Icons.error_outline,
    FieldCompletionState.warning => Icons.warning_amber_rounded,
    FieldCompletionState.incompatible => Icons.swap_horiz,
  };
}

/// The separate document overview route (FR-041, US4 scenario 8).
///
/// The caller supplies the T073 `FieldOrderEntry` rows for one revision plus
/// the already-decided durability state. The route is presentation-only and
/// pops one [DocumentOverviewOutcome]; it never mutates the document.
class DocumentOverviewScreen extends StatelessWidget {
  /// Creates the document overview for one revision snapshot.
  const DocumentOverviewScreen({
    required this.entries,
    required this.durabilityStatus,
    this.lastDurableAt,
    this.recognitionSummary,
    super.key,
  });

  /// The T073 rows in the current field order.
  final List<FieldOrderEntry> entries;

  /// The editor's already-decided durability state.
  final core.DurabilityStatus durabilityStatus;

  /// The editor's caller-supplied durable time, if any.
  final DateTime? lastDurableAt;

  /// The T124 provenance summary (FR-085) projected from the live
  /// revision's confirmed fields and suggestions, or `null` when the caller
  /// has no revision snapshot (then no summary card is rendered).
  final RecognitionSummary? recognitionSummary;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DocumentOverviewCounts counts = DocumentOverviewCounts.fromEntries(
      entries,
    );
    return Scaffold(
      key: documentOverviewScreenKey,
      appBar: AppBar(
        title: Text(l10n.documentOverviewTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: SizedBox(
            height: 44,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: DurabilityStatusLabel(
                status: durabilityStatus,
                lastDurableAt: lastDurableAt,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    l10n.fieldCount(counts.total, counts.filled),
                    key: documentOverviewCountsKey,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  // T124 (FR-085): the provenance summary card sits directly
                  // under the field count, visible in the summary surface.
                  if (recognitionSummary != null) ...<Widget>[
                    const SizedBox(height: 12),
                    recognitionSummary!,
                  ],
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: documentOverviewContinueKey,
                    onPressed: () => Navigator.of(context)
                        .pop(const DocumentOverviewOutcome.continueEditing()),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(l10n.documentOverviewContinue),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                key: const ValueKey<String>('document-overview-list'),
                children: <Widget>[
                  for (final FieldOrderEntry entry in entries)
                    _DocumentOverviewRow(entry: entry),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One selectable field row with label, page, type, and completion.
class _DocumentOverviewRow extends StatelessWidget {
  const _DocumentOverviewRow({required this.entry});

  final FieldOrderEntry entry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String completion = documentOverviewCompletionLabel(
      l10n,
      entry.completion,
    );
    return InkWell(
      key: ValueKey<String>('$documentOverviewRowKeyPrefix${entry.fieldId}'),
      onTap: () =>
          Navigator.of(context)
              .pop(DocumentOverviewOutcome.openField(entry.fieldId)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Decorative only; the completion word is always visible below.
                Icon(
                  _completionIcon(entry.completion),
                  size: 18,
                  semanticLabel: null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(entry.label, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _OverviewMeta(l10n.suggestionPage(entry.pageIndex + 1)),
                _OverviewMeta(fieldTypeLabel(l10n, entry.type)),
                _OverviewMeta(
                  completion,
                  textKey: ValueKey<String>(
                    '$documentOverviewCompletionKeyPrefix${entry.fieldId}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One small meta label inside a row.
class _OverviewMeta extends StatelessWidget {
  const _OverviewMeta(this.text, {this.textKey});

  final String text;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      text,
      key: textKey,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
