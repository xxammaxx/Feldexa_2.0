// T068 per-candidate conflict resolution sheet.
//
// Owner: `apps/feldexa_app/lib/features/editor/review_conflict_sheet.dart`
// (T068).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/contracts/editor-interactions.md` §3
//     (red conflict badge on both candidates; a conflict cannot be resolved by
//     a single swipe; each candidate requires an explicit choice);
//   * `specs/001-scanned-form-workflow/contracts/recognition-output.md` §6
//     (conflicts are symmetric, both remain, per-candidate resolution);
//   * `specs/001-scanned-form-workflow/data-model.md` §3.4/§3.5
//     (suggestion resolution state machine);
//   * `specs/001-scanned-form-workflow/spec.md` FR-025, FR-083, FR-085,
//     FR-090, FR-094;
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// The sheet is a presentation surface only. It computes the symmetric conflict
// group for one tapped suggestion, shows every candidate with its current
// resolution, and forwards an explicit confirm or reject for exactly that
// candidate. It never mutates another candidate, never adds undo state, and
// never saves; the parent remains the sole owner of persistence and undo.
// Every user-visible sentence comes from the German ARB; this file holds no
// German literal.

import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Stable key for the modal conflict sheet.
const String reviewConflictSheetKey = 'review-conflict-sheet';

/// Stable key prefix for a conflict badge button in the review panel.
const String conflictBadgeKeyPrefix = 'conflict-badge-';

/// Stable key prefix for one conflict candidate row in the sheet.
const String conflictCandidateKeyPrefix = 'conflict-candidate-';

/// Stable key prefix for one conflict confirm action.
const String conflictConfirmKeyPrefix = 'conflict-confirm-';

/// Stable key prefix for one conflict reject action.
const String conflictRejectKeyPrefix = 'conflict-reject-';

/// Stable key for the sheet close action.
const String conflictCloseKey = 'conflict-close';

/// Opens the per-candidate conflict sheet for [tapped].
///
/// [suggestions] is the whole current suggestion set, including confirmed and
/// rejected records, so resolved candidates remain visible in the group.
Future<void> showReviewConflictSheet({
  required BuildContext context,
  required core.FieldSuggestion tapped,
  required Iterable<core.FieldSuggestion> suggestions,
  required ValueChanged<core.FieldSuggestion> onConfirm,
  required ValueChanged<core.FieldSuggestion> onReject,
  bool busy = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext sheetContext) {
      return ReviewConflictSheet(
        tapped: tapped,
        suggestions: suggestions,
        onConfirm: onConfirm,
        onReject: onReject,
        busy: busy,
      );
    },
  );
}

/// The symmetric conflict group for [tapped] within [suggestions].
///
/// The group contains the tapped suggestion, every suggestion whose
/// `conflictsWith` contains the tapped id, and every id in the tapped
/// suggestion's own `conflictsWith` that resolves to a suggestion. It is
/// deduplicated by id, retains resolved candidates, and is ordered with the
/// same deterministic rule as the review panel: page, rounded y, rounded x,
/// type ordinal, id. A stale reference matches nothing and is simply absent;
/// the caller still receives the tapped candidate.
List<core.FieldSuggestion> resolveConflictGroup({
  required core.FieldSuggestion tapped,
  required Iterable<core.FieldSuggestion> suggestions,
}) {
  final List<core.FieldSuggestion> all = List<core.FieldSuggestion>.of(
    suggestions,
  );
  final Map<String, core.FieldSuggestion> byId =
      <String, core.FieldSuggestion>{};
  for (final core.FieldSuggestion suggestion in all) {
    byId.putIfAbsent(suggestion.id, () => suggestion);
  }

  final Set<String> ids = <String>{tapped.id, ...tapped.conflictsWith};
  for (final core.FieldSuggestion suggestion in all) {
    if (suggestion.conflictsWith.contains(tapped.id)) {
      ids.add(suggestion.id);
    }
  }

  final Map<String, core.FieldSuggestion> group =
      <String, core.FieldSuggestion>{};
  for (final String id in ids) {
    final core.FieldSuggestion? suggestion = id == tapped.id
        ? tapped
        : byId[id];
    if (suggestion != null) {
      group.putIfAbsent(suggestion.id, () => suggestion);
    }
  }

  final List<core.FieldSuggestion> ordered = group.values.toList()
    ..sort(compareReviewSuggestions);
  return ordered;
}

/// Deterministic review order: page, rounded y, rounded x, type, id.
///
/// The panel and the conflict sheet share this rule so a conflict group always
/// appears in the same document order as the review queue.
int compareReviewSuggestions(core.FieldSuggestion a, core.FieldSuggestion b) {
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

int _roundEighth(double value) => (value * 8).round();

/// The T068 per-candidate conflict resolution sheet.
///
/// The sheet is scrollable and safe-area aware. Each candidate shows its
/// label, German type name, one-based page, 1/8 pt position, integer
/// confidence percent, uncertainty and conflict markers, and its resolution
/// state. Only an unresolved candidate exposes confirm/reject actions. An
/// action is forwarded for exactly that candidate and then closes the sheet.
class ReviewConflictSheet extends StatelessWidget {
  /// Creates the conflict sheet.
  const ReviewConflictSheet({
    required this.tapped,
    required this.suggestions,
    required this.onConfirm,
    required this.onReject,
    this.busy = false,
    super.key,
  });

  /// The suggestion whose conflict badge opened the sheet.
  final core.FieldSuggestion tapped;

  /// The whole current suggestion set, including resolved records.
  final Iterable<core.FieldSuggestion> suggestions;

  /// Confirms exactly one candidate.
  final ValueChanged<core.FieldSuggestion> onConfirm;

  /// Rejects exactly one candidate.
  final ValueChanged<core.FieldSuggestion> onReject;

  /// Disables resolution actions while a revision save is in flight.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final List<core.FieldSuggestion> group = resolveConflictGroup(
      tapped: tapped,
      suggestions: suggestions,
    );

    return SafeArea(
      key: const ValueKey<String>(reviewConflictSheetKey),
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l10n.reviewConflictSheetTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  TextButton(
                    key: const ValueKey<String>(conflictCloseKey),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.reviewConflictCloseAction),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                key: const ValueKey<String>('$reviewConflictSheetKey-scroll'),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      l10n.reviewConflictSheetBody,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (group.length < 2) ...<Widget>[
                      const SizedBox(height: 8),
                      _ConflictNote(
                        text: l10n.reviewConflictSingleCandidateNote,
                      ),
                    ],
                    const SizedBox(height: 12),
                    for (final core.FieldSuggestion suggestion in group)
                      _ConflictCandidateRow(
                        suggestion: suggestion,
                        onConfirm: () {
                          onConfirm(suggestion);
                          Navigator.of(context).pop();
                        },
                        onReject: () {
                          onReject(suggestion);
                          Navigator.of(context).pop();
                        },
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
}

class _ConflictCandidateRow extends StatelessWidget {
  const _ConflictCandidateRow({
    required this.suggestion,
    required this.onConfirm,
    required this.onReject,
    required this.busy,
  });

  final core.FieldSuggestion suggestion;
  final VoidCallback onConfirm;
  final VoidCallback onReject;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String label = suggestion.labelText ?? l10n.suggestionRowFallback;
    final bool uncertain = suggestion.confidence < 0.50;
    final int percent = (suggestion.confidence * 100).clamp(0, 100).round();
    final bool unresolved =
        suggestion.resolution == core.SuggestionResolution.unresolved;

    return Container(
      key: ValueKey<String>('$conflictCandidateKeyPrefix${suggestion.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
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
                _SheetBadge(text: l10n.suggestionUncertain, severe: true),
              if (suggestion.conflictsWith.isNotEmpty)
                _SheetBadge(text: l10n.suggestionConflict, severe: true),
              _SheetBadge(
                text: _stateLabel(l10n, suggestion.resolution),
                severe: false,
              ),
            ],
          ),
          if (unresolved) ...<Widget>[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                TextButton(
                  key: ValueKey<String>(
                    '$conflictConfirmKeyPrefix${suggestion.id}',
                  ),
                  onPressed: busy ? null : onConfirm,
                  child: Text(l10n.suggestionConfirmAction),
                ),
                TextButton(
                  key: ValueKey<String>(
                    '$conflictRejectKeyPrefix${suggestion.id}',
                  ),
                  onPressed: busy ? null : onReject,
                  child: Text(l10n.suggestionRejectAction),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _stateLabel(
    AppLocalizations l10n,
    core.SuggestionResolution resolution,
  ) {
    return switch (resolution) {
      core.SuggestionResolution.unresolved =>
        l10n.reviewConflictStateUnresolved,
      core.SuggestionResolution.confirmed => l10n.reviewConflictStateConfirmed,
      core.SuggestionResolution.rejected => l10n.reviewConflictStateRejected,
    };
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

class _ConflictNote extends StatelessWidget {
  const _ConflictNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
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

class _SheetBadge extends StatelessWidget {
  const _SheetBadge({required this.text, required this.severe});

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
