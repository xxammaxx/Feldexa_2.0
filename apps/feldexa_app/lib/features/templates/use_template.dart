// T117 "Vorlage verwenden" UI flow (FR-059, FR-103, FR-104, FR-105, FR-060;
// clarification 4).
//
// Owner: `apps/feldexa_app/lib/features/templates/use_template.dart`.
// Normative sources:
//   * `spec.md` FR-059/FR-103/FR-104/FR-105/FR-060;
//   * `contracts/editor-interactions.md` — the start-area conventions;
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// The sheet is presentation-only: it shows the German independent-document
// notice (a new document with empty values; the template stays unchanged),
// and calls the injected create callback exactly once on confirm. The
// callback performs the single T117 use-case call. All user-visible text
// comes from the German ARB; no German literal appears in this file. The
// resolved result is returned to the caller; the sheet closes only after a
// verified success (FR-106 pattern).
//
// Evidence: host-VM widget tests only; evidence class NONE.

// The T117 use case has no public barrel file; this consumer imports its
// stable source library deliberately, matching the editor composition.
// ignore_for_file: implementation_imports

import 'package:feldexa_application/src/templates/template_versions.dart'
    as versions;
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Stable keys of the sheet's surfaces.
const String useTemplateSheetKey = 'use-template-sheet';
const String useTemplateConfirmKey = 'use-template-confirm';
const String useTemplateCancelKey = 'use-template-cancel';
const String useTemplateStatusKey = 'use-template-status';

/// Shows the German "Vorlage verwenden" sheet for one template.
///
/// [templateTitle] names the template and [versionNumber] is the display
/// number of the version a new document will pin (FR-103/FR-105). [onCreate]
/// is invoked exactly once when the user confirms; it must perform the single
/// explicit template use. Resolves with the verified result, or null when
/// the user cancels or the creation failed.
Future<versions.UseTemplateResult?> showUseTemplateSheet(
  BuildContext context, {
  required String templateTitle,
  required int versionNumber,
  required Future<versions.UseTemplateResult> Function() onCreate,
}) {
  return showDialog<versions.UseTemplateResult>(
    context: context,
    builder: (BuildContext dialogContext) {
      final AppLocalizations dialogL10n = AppLocalizations.of(dialogContext);
      bool busy = false;
      bool failed = false;
      return StatefulBuilder(
        builder: (BuildContext sheetContext, StateSetter setSheetState) {
          Future<void> confirm() async {
            if (busy) {
              return;
            }
            setSheetState(() {
              busy = true;
              failed = false;
            });
            final versions.UseTemplateResult result = await onCreate();
            if (!sheetContext.mounted) {
              return;
            }
            if (result.isSuccess) {
              Navigator.of(sheetContext).pop(result);
              return;
            }
            // Content-free failure notice (FR-106 pattern): no optimistic
            // success, no document opened.
            setSheetState(() {
              busy = false;
              failed = true;
            });
          }

          return AlertDialog(
            key: const ValueKey<String>(useTemplateSheetKey),
            scrollable: true,
            title: Text(dialogL10n.useTemplateSheetTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(templateTitle),
                Text(dialogL10n.templateEditorVersionLabel(versionNumber)),
                const SizedBox(height: 8),
                Text(dialogL10n.useTemplateNotice),
                if (failed)
                  Text(
                    dialogL10n.useTemplateFailed,
                    key: const ValueKey<String>(useTemplateStatusKey),
                  ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                key: const ValueKey<String>(useTemplateCancelKey),
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: Text(
                  MaterialLocalizations.of(sheetContext).cancelButtonLabel,
                ),
              ),
              TextButton(
                key: const ValueKey<String>(useTemplateConfirmKey),
                onPressed: busy ? null : confirm,
                child: Text(dialogL10n.useTemplateConfirm),
              ),
            ],
          );
        },
      );
    },
  );
}
