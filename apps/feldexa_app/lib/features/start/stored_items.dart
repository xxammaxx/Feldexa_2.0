// T095 start-area document and template groups.
//
// Owner: `apps/feldexa_app/lib/features/start/stored_items.dart` (T095,
// issue #95).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/spec.md` FR-058, FR-097, and FR-098
//     (separate document and template groups, newest first, with the stored
//     status and last-edited date) and clarification 3;
//   * `specs/001-scanned-form-workflow/data-model.md` section 3.1, where
//     `DocumentSummary` is a derived read model and never a second persisted
//     record;
//   * `specs/001-scanned-form-workflow/contracts/editor-interactions.md`
//     section 7 (a status is conveyed by icon and text, never colour alone);
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// What this surface is
// -----------------
// [DocumentSummary] is an immutable projection of the port-level [StoredMeta].
// Its status is derived on demand and is not persisted; `exportReady` cannot be
// inferred from storage and is reserved for a caller-authored summary. The
// [StoredItemsView] is presentation-only: it receives caller-owned summaries
// and callbacks, performs no store, file, network, clock, or route call, and
// owns no delete flow. Deletion confirmation belongs to a later task; when a
// delete callback is supplied this view only forwards the entry id.
//
// Evidence
// --------
// Covered by host-VM widget tests only. No Android, device, screen-reader, or
// visual claim; evidence class NONE.

import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart';

/// The presentation state of one stored document or template entry.
///
/// [saved] and [draft] are derived from [StoredMeta]; [exportReady] is authored
/// by the application and is never inferred from storage; [unreadable] wins
/// over every readable state.
enum StoredItemStatus {
  /// Editable work that is not covered by a verified durable commit.
  draft,

  /// The newest edit is covered by a verified durable commit.
  saved,

  /// The application has verified an export of the current content.
  exportReady,

  /// The aggregate cannot currently be loaded.
  unreadable,
}

/// The start-list projection of one document or template.
///
/// This is a derived read model, not a persisted record: [title], [id], and
/// [updatedAt] are copied from [StoredMeta] unchanged, and [status] is decided
/// by [DocumentSummary.fromStoredMeta] or by an application caller. Field
/// counts are optional and are never invented by the projection factory.
final class DocumentSummary {
  /// Creates an app-authored summary.
  ///
  /// A caller may set [StoredItemStatus.exportReady] here because storage
  /// cannot express an export result. A template is projected from its
  /// [StoredMeta] exactly like a document; this type does not claim a kind.
  const DocumentSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.status,
    this.fieldCount,
    this.filledCount,
  });

  /// Projects the port-level list entry [meta].
  ///
  /// An unreadable entry is [StoredItemStatus.unreadable] regardless of its
  /// durable timestamp. Otherwise the entry is [StoredItemStatus.saved] only
  /// when a durable time exists and the last update is not newer than it;
  /// everything else is [StoredItemStatus.draft]. This factory never produces
  /// [StoredItemStatus.exportReady], never reads a clock, and never rewrites the
  /// stored id, title, or timestamp.
  factory DocumentSummary.fromStoredMeta(StoredMeta meta) {
    final StoredItemStatus status;
    if (!meta.readable) {
      status = StoredItemStatus.unreadable;
    } else {
      final DateTime? lastDurableAt = meta.lastDurableAt;
      status = lastDurableAt != null && !meta.updatedAt.isAfter(lastDurableAt)
          ? StoredItemStatus.saved
          : StoredItemStatus.draft;
    }
    return DocumentSummary(
      id: meta.id,
      title: meta.title,
      updatedAt: meta.updatedAt,
      status: status,
    );
  }

  /// The stored aggregate id, copied unchanged.
  final String id;

  /// The user-visible title, copied unchanged and never truncated here.
  final String title;

  /// The last update time in UTC, copied unchanged.
  final DateTime updatedAt;

  /// The presentation state of this entry.
  final StoredItemStatus status;

  /// Total confirmed fields, when the caller derived them.
  final int? fieldCount;

  /// Confirmed fields with a value, when the caller derived them.
  final int? filledCount;
}

/// The start area's separate document and template groups.
///
/// Both sections are always rendered with their localized heading. Each list is
/// copied and sorted newest first by [DocumentSummary.updatedAt], with equal
/// timestamps ordered by ascending [DocumentSummary.id]; the caller's lists are
/// never mutated. Open callbacks receive the entry id; an optional delete
/// callback is forwarded without a confirmation dialog. The root is a
/// [ListView], so the surface is reachable by scrolling and needs no parent
/// scroll view.
class StoredItemsView extends StatelessWidget {
  /// Creates the two-group start list.
  const StoredItemsView({
    required this.documents,
    required this.templates,
    required this.onOpenDocument,
    required this.onOpenTemplate,
    this.onDelete,
    super.key,
  });

  /// The caller-supplied document summaries.
  final List<DocumentSummary> documents;

  /// The caller-supplied template summaries.
  final List<DocumentSummary> templates;

  /// Called with the document id when a document entry is tapped.
  final ValueChanged<String> onOpenDocument;

  /// Called with the template id when a template entry is tapped.
  final ValueChanged<String> onOpenTemplate;

  /// Called with the entry id when the optional delete control is tapped.
  ///
  /// When null, no delete control is rendered. This view shows no dialog; a
  /// caller that needs confirmation wraps this callback.
  final ValueChanged<String>? onDelete;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ListView(
      key: const ValueKey<String>('stored-items-list'),
      children: <Widget>[
        _StoredSection(
          key: const ValueKey<String>('documents-section'),
          heading: l10n.documentsGroup,
          emptyMessage: l10n.emptyDocuments,
          items: _sortedByRecency(documents),
          onOpen: onOpenDocument,
          onDelete: onDelete,
        ),
        const Divider(height: 1),
        _StoredSection(
          key: const ValueKey<String>('templates-section'),
          heading: l10n.templatesGroup,
          emptyMessage: l10n.emptyTemplates,
          items: _sortedByRecency(templates),
          onOpen: onOpenTemplate,
          onDelete: onDelete,
        ),
      ],
    );
  }
}

/// One labelled group with its empty message or its sorted entries.
class _StoredSection extends StatelessWidget {
  const _StoredSection({
    required this.heading,
    required this.emptyMessage,
    required this.items,
    required this.onOpen,
    this.onDelete,
    super.key,
  });

  final String heading;
  final String emptyMessage;
  final List<DocumentSummary> items;
  final ValueChanged<String> onOpen;
  final ValueChanged<String>? onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(heading, style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(emptyMessage)
          else
            for (final DocumentSummary item in items)
              _StoredItemEntry(item: item, onOpen: onOpen, onDelete: onDelete),
        ],
      ),
    );
  }
}

/// One tappable entry with title, last-edited date, status, and optional delete.
class _StoredItemEntry extends StatelessWidget {
  const _StoredItemEntry({
    required this.item,
    required this.onOpen,
    this.onDelete,
  });

  final DocumentSummary item;
  final ValueChanged<String> onOpen;
  final ValueChanged<String>? onDelete;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ValueChanged<String>? delete = onDelete;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: InkWell(
              key: ValueKey<String>('stored-item-${item.id}'),
              onTap: () => onOpen(item.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Deliberately unbounded: the full title wraps and is never
                    // replaced by an ellipsis in the start list.
                    Text(item.title),
                    const SizedBox(height: 4),
                    Text(l10n.lastEdited(_localDate(item.updatedAt))),
                    const SizedBox(height: 4),
                    _StoredItemStatusRow(status: item.status, l10n: l10n),
                  ],
                ),
              ),
            ),
          ),
          if (delete != null)
            IconButton(
              key: ValueKey<String>('stored-item-delete-${item.id}'),
              onPressed: () => delete(item.id),
              tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
    );
  }
}

/// The status icon and its exact visible label.
class _StoredItemStatusRow extends StatelessWidget {
  const _StoredItemStatusRow({required this.status, required this.l10n});

  final StoredItemStatus status;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ({String text, IconData icon}) presentation = switch (status) {
      StoredItemStatus.draft => (
        text: l10n.statusDraft,
        icon: Icons.edit_outlined,
      ),
      StoredItemStatus.saved => (
        text: l10n.durabilityClean,
        icon: Icons.check_circle_outline,
      ),
      StoredItemStatus.exportReady => (
        text: l10n.statusExportReady,
        icon: Icons.picture_as_pdf_outlined,
      ),
      StoredItemStatus.unreadable => (
        text: l10n.statusUnreadable,
        icon: Icons.error_outline,
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(presentation.icon, size: 18),
        const SizedBox(width: 6),
        Flexible(child: Text(presentation.text)),
      ],
    );
  }
}

/// Returns a newest-first copy, tie-breaking equal instants by ascending id.
List<DocumentSummary> _sortedByRecency(List<DocumentSummary> items) {
  final List<DocumentSummary> sorted = List<DocumentSummary>.of(items);
  sorted.sort((DocumentSummary a, DocumentSummary b) {
    final int byTime = b.updatedAt.compareTo(a.updatedAt);
    if (byTime != 0) {
      return byTime;
    }
    return a.id.compareTo(b.id);
  });
  return sorted;
}

/// Formats [timestamp] as the local zero-padded `dd.MM.yyyy` list date.
///
/// The conversion applies [DateTime.toLocal] exactly once and never reads the
/// wall clock.
String _localDate(DateTime timestamp) {
  final DateTime local = timestamp.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.'
      '${local.year.toString().padLeft(4, '0')}';
}
