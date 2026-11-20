// T096 reusable start-list deletion confirmation.
//
// Owner: `apps/feldexa_app/lib/features/start/delete_item.dart` (T096,
// issue #96).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/spec.md` FR-053 and FR-099;
//   * `specs/001-scanned-form-workflow/contracts/error-catalog.de.md` section 7
//     (DEL-002, DEL-003, and the post-deletion confirmation);
//   * `specs/001-scanned-form-workflow/contracts/editor-interactions.md`
//     section 7;
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// This surface is presentation-only: it resolves exactly one existing German
// ARB message, shows one confirmation dialog, and returns the user's choice. It
// performs no deletion, store, route, or snackbar action; the caller deletes
// only after a `true` result.
//
// Evidence: host-VM widget tests only. No Android, device, screen-reader, or
// visual claim; evidence class NONE.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// The stored entry kind whose deletion is being confirmed.
enum DeleteItemKind {
  /// A document with its stored pages, fields, inputs, and signatures.
  document,

  /// A template with all of its versions.
  template,
}

/// Shows the one German deletion confirmation for [kind] and [title].
///
/// The message is resolved from the existing ARB getter for the kind before the
/// dialog is shown. Confirm returns `true`, while cancel and barrier dismissal
/// return `false`. No deletion, store, file, network, clock, route, or snackbar
/// action is performed here; the caller deletes only after `true`.
Future<bool> showDeleteItemConfirmation(
  BuildContext context, {
  required DeleteItemKind kind,
  required String title,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final String message = switch (kind) {
    DeleteItemKind.document => l10n.deleteDocumentDialog(title),
    DeleteItemKind.template => l10n.deleteTemplateDialog(title),
  };
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        key: const ValueKey<String>('delete-item-dialog'),
        scrollable: true,
        content: Text(message),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('delete-item-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          TextButton(
            key: const ValueKey<String>('delete-item-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

/// Returns the exact post-deletion sentence for [title].
String deletionConfirmationMessage(AppLocalizations l10n, String title) {
  return l10n.deletionConfirmation(title);
}
