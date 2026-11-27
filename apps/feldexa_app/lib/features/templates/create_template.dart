// T115 "Als Vorlage speichern" UI entry (FR-054, FR-055, FR-056, FR-057,
// FR-061; clarification 4).
//
// Owner: `apps/feldexa_app/lib/features/templates/create_template.dart`.
// Normative sources:
//   * `spec.md` FR-054–FR-057 and FR-061;
//   * `contracts/editor-interactions.md` — the editor sheet conventions used
//     by the export and field-order sheets;
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// The sheet is presentation-only: it takes the reviewed snapshot's readiness,
// a German title input, and an injected asynchronous create callback, shows
// the value/signature exclusion notice (FR-057), and reports the outcome
// content-free. All user-visible text comes from the German ARB
// (`app_de.arb`); no German literal appears in this file. The callback is the
// only place the store is touched, and it is invoked exactly once per
// confirmed submit — the template is never created automatically (FR-061).
// The dialog stateful widget owns its controller and outcome notifier and
// disposes them only when the dialog is fully dismissed.
//
// Evidence: host-VM widget tests only; evidence class NONE.

// The T115 use case has no public barrel file; this consumer imports its
// stable source library deliberately, matching the editor composition.
// ignore_for_file: implementation_imports

import 'package:feldexa_application/src/templates/create_template_from_document.dart'
    as create_template;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

/// Stable key of the editor app-bar action that opens the sheet.
const String editorTemplateActionKey = 'editor-template-action';

/// Stable keys of the sheet's surfaces.
const String createTemplateSheetKey = 'create-template-sheet';
const String createTemplateTitleFieldKey = 'create-template-title-field';
const String createTemplateConfirmKey = 'create-template-confirm';
const String createTemplateCancelKey = 'create-template-cancel';
const String createTemplateStatusKey = 'create-template-status';

/// Shows the German "Als Vorlage speichern" sheet.
///
/// [reviewed] is the FR-055 readiness of the current snapshot; when it is
/// `false` the confirm action stays disabled and the pending notice is shown.
/// [onCreate] is called exactly once with the trimmed title when the user
/// confirms; it must perform the single explicit template creation. The
/// returned [create_template.CreateTemplateResult] is reported content-free
/// below the form, and the sheet closes only after a verified success.
Future<void> showCreateTemplateSheet(
  BuildContext context, {
  required bool reviewed,
  required String initialTitle,
  required Future<create_template.CreateTemplateResult> Function(String title)
  onCreate,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => _CreateTemplateDialog(
      reviewed: reviewed,
      initialTitle: initialTitle,
      onCreate: onCreate,
    ),
  );
}

class _CreateTemplateDialog extends StatefulWidget {
  const _CreateTemplateDialog({
    required this.reviewed,
    required this.initialTitle,
    required this.onCreate,
  });

  final bool reviewed;
  final String initialTitle;
  final Future<create_template.CreateTemplateResult> Function(String title)
  onCreate;

  @override
  State<_CreateTemplateDialog> createState() => _CreateTemplateDialogState();
}

class _CreateTemplateDialogState extends State<_CreateTemplateDialog> {
  late final TextEditingController _titleController = TextEditingController(
    text: widget.initialTitle,
  );
  final ValueNotifier<create_template.CreateTemplateResult?> _outcome =
      ValueNotifier<create_template.CreateTemplateResult?>(null);
  bool _busy = false;

  @override
  void dispose() {
    _titleController.dispose();
    _outcome.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final String title = _titleController.text.trim();
    if (!widget.reviewed || title.isEmpty || _busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    final NavigatorState navigator = Navigator.of(context);
    final create_template.CreateTemplateResult result = await widget.onCreate(
      title,
    );
    if (!mounted) {
      return;
    }
    _outcome.value = result;
    setState(() {
      _busy = false;
    });
    if (result.isSuccess) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey<String>(createTemplateSheetKey),
      scrollable: true,
      title: Text(l10n.createTemplateSheetTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            key: const ValueKey<String>(createTemplateTitleFieldKey),
            controller: _titleController,
            maxLength: 200,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.singleLineFormatter,
            ],
            decoration: InputDecoration(
              labelText: l10n.createTemplateTitleLabel,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(l10n.createTemplateExclusionNotice),
          const SizedBox(height: 8),
          if (!widget.reviewed)
            Text(
              l10n.createTemplateStructurePending,
              key: const ValueKey<String>('create-template-pending'),
            ),
          ValueListenableBuilder<create_template.CreateTemplateResult?>(
            valueListenable: _outcome,
            builder:
                (
                  BuildContext context,
                  create_template.CreateTemplateResult? result,
                  _,
                ) {
                  if (result == null) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    key: const ValueKey<String>(createTemplateStatusKey),
                    result.isSuccess
                        ? l10n.createTemplateSuccess
                        : l10n.createTemplateFailed,
                  );
                },
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>(createTemplateCancelKey),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        TextButton(
          key: const ValueKey<String>(createTemplateConfirmKey),
          onPressed:
              widget.reviewed &&
                  _titleController.text.trim().isNotEmpty &&
                  !_busy
              ? _confirm
              : null,
          child: Text(l10n.createTemplateConfirm),
        ),
      ],
    );
  }
}
