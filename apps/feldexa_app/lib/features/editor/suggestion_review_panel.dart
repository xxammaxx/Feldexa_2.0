// Issue #217 Phase B2 visible suggestion review surface.
//
// Owner: `apps/feldexa_app/lib/features/editor/suggestion_review_panel.dart`
// (Phase B2).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/contracts/editor-interactions.md` §3
//     (review mode, per-field actions, conflict/uncertain badges);
//   * `specs/001-scanned-form-workflow/contracts/recognition-output.md` §2
//     (suggestion fields), §3.4 (presentation bands), and §6 (conflicts);
//   * `specs/001-scanned-form-workflow/data-model.md` §3.4/§3.5;
//   * `specs/001-scanned-form-workflow/spec.md` FR-015, FR-021, FR-022,
//     FR-025, FR-027, FR-028, FR-083, FR-085;
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// This is a list-only B2 surface: it renders each suggestion in deterministic
// document order and exposes confirm/reject/undo callbacks. It paints no
// overlay and no page geometry; T068 (conflict sheet) and T069 (field overlay)
// own those surfaces. Every user-visible sentence comes from the German ARB;
// this widget holds no German literal.
//
// The list is intentionally the unresolved review queue. Confirmed and rejected
// suggestions leave the queue, while the header's counts keep the resolution
// visible and reversible through the undo affordance.

import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Stable key for the whole review panel.
const String suggestionPanelKey = 'suggestion-panel';

/// Stable key prefix for one suggestion row.
const String suggestionRowKeyPrefix = 'suggestion-row-';

/// Stable key prefix for one confirm action.
const String confirmSuggestionKeyPrefix = 'confirm-suggestion-';

/// Stable key prefix for one reject action.
const String rejectSuggestionKeyPrefix = 'reject-suggestion-';

/// Stable key for the undo affordance.
const String undoReviewKey = 'undo-review';

/// Stable key for the empty state.
const String suggestionEmptyKey = 'suggestion-empty';

/// The B2 visible review surface.
///
/// [suggestions] is ordered internally by page, then the canonical display
/// position, then type, then id, so the visible queue does not depend on the
/// caller's list order. Resolved suggestions are retained in the counts but do
/// not appear as actionable rows.
class SuggestionReviewPanel extends StatelessWidget {
  /// Creates the review panel.
  const SuggestionReviewPanel({
    required this.suggestions,
    required this.confirmedFieldCount,
    required this.onConfirm,
    required this.onReject,
    required this.onUndo,
    this.undoAvailable = false,
    this.busy = false,
    super.key,
  });

  /// The current suggestion set, including confirmed and rejected records.
  final Iterable<core.FieldSuggestion> suggestions;

  /// Number of confirmed fields currently stored in the revision.
  final int confirmedFieldCount;

  /// Confirms one unresolved suggestion.
  final ValueChanged<core.FieldSuggestion> onConfirm;

  /// Rejects one unresolved suggestion.
  final ValueChanged<core.FieldSuggestion> onReject;

  /// Reverses the most recent review action on the undo stack.
  final VoidCallback onUndo;

  /// Whether the undo action currently has a reversible entry.
  final bool undoAvailable;

  /// Disables review actions while a revision save is in flight.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<core.FieldSuggestion> ordered = _ordered(suggestions);
    final List<core.FieldSuggestion> unresolved = <core.FieldSuggestion>[
      for (final core.FieldSuggestion suggestion in ordered)
        if (suggestion.resolution == core.SuggestionResolution.unresolved)
          suggestion,
    ];
    final int confirmed = ordered
        .where(
          (core.FieldSuggestion suggestion) =>
              suggestion.resolution == core.SuggestionResolution.confirmed,
        )
        .length;
    final int rejected = ordered
        .where(
          (core.FieldSuggestion suggestion) =>
              suggestion.resolution == core.SuggestionResolution.rejected,
        )
        .length;
    final bool hasProgress = confirmed > 0 || rejected > 0;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: Card(
        key: const ValueKey<String>(suggestionPanelKey),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.suggestionsLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      _MetaText(l10n.suggestionOpenCount(unresolved.length)),
                      _MetaText(l10n.suggestionFieldCount(confirmedFieldCount)),
                      if (hasProgress)
                        _MetaText(
                          l10n.suggestionReviewProgress(confirmed, rejected),
                        ),
                      if (undoAvailable)
                        TextButton(
                          key: const ValueKey<String>(undoReviewKey),
                          onPressed: busy ? null : onUndo,
                          child: Text(l10n.suggestionUndoAction),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (busy)
              const LinearProgressIndicator(
                key: ValueKey<String>('suggestion-review-busy'),
              ),
            Flexible(
              child: unresolved.isEmpty
                  ? Padding(
                      key: const ValueKey<String>(suggestionEmptyKey),
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        ordered.isEmpty
                            ? l10n.suggestionEmpty
                            : l10n.suggestionAllReviewed,
                      ),
                    )
                  : SingleChildScrollView(
                      key: const ValueKey<String>('suggestion-panel-scroll'),
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (final core.FieldSuggestion suggestion
                              in unresolved)
                            _SuggestionRow(
                              suggestion: suggestion,
                              onConfirm: onConfirm,
                              onReject: onReject,
                              busy: busy,
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Deterministic document order: page, rounded y, rounded x, type, id.
  static List<core.FieldSuggestion> _ordered(
    Iterable<core.FieldSuggestion> input,
  ) {
    final List<core.FieldSuggestion> ordered = List<core.FieldSuggestion>.of(
      input,
    )..sort(_compare);
    return ordered;
  }

  static int _compare(core.FieldSuggestion a, core.FieldSuggestion b) {
    int result = a.pageIndex.compareTo(b.pageIndex);
    if (result != 0) {
      return result;
    }
    result = _roundEighth(a.rect.top).compareTo(_roundEighth(b.rect.top));
    if (result != 0) {
      return result;
    }
    result = _roundEighth(a.rect.left).compareTo(_roundEighth(b.rect.left));
    if (result != 0) {
      return result;
    }
    result = a.proposedType.index.compareTo(b.proposedType.index);
    if (result != 0) {
      return result;
    }
    return a.id.compareTo(b.id);
  }

  static double _roundEighth(double value) => (value * 8).round() / 8;
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.suggestion,
    required this.onConfirm,
    required this.onReject,
    required this.busy,
  });

  final core.FieldSuggestion suggestion;
  final ValueChanged<core.FieldSuggestion> onConfirm;
  final ValueChanged<core.FieldSuggestion> onReject;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String label = suggestion.labelText ?? l10n.suggestionRowFallback;
    final bool uncertain = suggestion.confidence < 0.50;
    final int percent = (suggestion.confidence * 100).clamp(0, 100).round();
    final bool conflicting = suggestion.conflictsWith.isNotEmpty;

    return Container(
      key: ValueKey<String>('$suggestionRowKeyPrefix${suggestion.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              _MetaText(_typeName(l10n, suggestion.proposedType)),
              _MetaText(l10n.suggestionPage(suggestion.pageIndex + 1)),
              _MetaText(
                l10n.suggestionPosition(
                  _formatPoint(suggestion.rect.left),
                  _formatPoint(suggestion.rect.top),
                ),
              ),
              _MetaText(l10n.suggestionConfidence(percent)),
              if (uncertain)
                _Badge(text: l10n.suggestionUncertain, severe: true),
              if (conflicting)
                _Badge(text: l10n.suggestionConflict, severe: true),
            ],
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              TextButton(
                key: ValueKey<String>(
                  '$confirmSuggestionKeyPrefix${suggestion.id}',
                ),
                onPressed: busy ? null : () => onConfirm(suggestion),
                child: Text(l10n.suggestionConfirmAction),
              ),
              TextButton(
                key: ValueKey<String>(
                  '$rejectSuggestionKeyPrefix${suggestion.id}',
                ),
                onPressed: busy ? null : () => onReject(suggestion),
                child: Text(l10n.suggestionRejectAction),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _typeName(AppLocalizations l10n, core.FieldType type) {
    return switch (type) {
      core.FieldType.text => l10n.suggestionTypeText,
      core.FieldType.number => l10n.suggestionTypeNumber,
      core.FieldType.date => l10n.suggestionTypeDate,
      core.FieldType.checkbox => l10n.suggestionTypeCheckbox,
      core.FieldType.multiline => l10n.suggestionTypeMultiline,
      core.FieldType.signature => l10n.suggestionTypeSignature,
    };
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.bodySmall);
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.severe});

  final String text;
  final bool severe;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = severe
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

final NumberFormat _pointFormat = NumberFormat('#,##0.###', 'de');

String _formatPoint(double value) {
  final double rounded = (value * 8).round() / 8;
  return _pointFormat.format(rounded);
}
