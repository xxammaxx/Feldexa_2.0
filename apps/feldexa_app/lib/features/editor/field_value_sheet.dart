// T071A type-appropriate field value sheet.
//
// Owner: `apps/feldexa_app/lib/features/editor/field_value_sheet.dart`
// (T071A, issue #244).
//
// Normative sources:
//   * `spec.md` FR-033/FR-035/FR-036/FR-039/FR-040 and FR-045–FR-047 — a
//     selected field is edited with its type-appropriate control, invalid
//     input is never stored, and only a verified commit is durable;
//   * `contracts/editor-interactions.md` §2 (selection opens the control),
//     §5 (per-type filling rules), and §11 (200 % text scale reflows);
//   * `contracts/error-catalog.de.md` §6 (`NUM-001`, `DATE-001`, `DATE-002`);
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// This sheet is composition only. It reuses T079 `FieldTextControl`, T082
// `FieldCheckboxControl`, T084 `FieldOverflowWarning`, the T080/T081 pure
// parsers, and the T091 durability surface owned by the editor. It performs no
// store, file, network, clock, or editor call of its own: the caller supplies
// one `onCommit` callback and owns persistence, `setFieldValue`, and the
// verified durability state.
//
// Invalid number/date input remains in the control with the committed German
// catalog sentence and is never handed to the caller. A failed save leaves the
// sheet open and editable and displays the caller-supplied content-free
// message; no `saved` claim is made here.
//
// Signature editing is not faked. No production signature-asset write flow is
// composed by T071A, so the sheet visibly marks signature editing `NOT_RUN`
// and offers no save action. Overflow measurement is also not implemented in
// T071A: T084 is rendered only when the caller already marked the stored value
// `overflow`, and the journey report records layout measurement as `NOT_RUN`.

import 'package:feldexa_app/features/fill/checkbox_control.dart';
import 'package:feldexa_app/features/fill/overflow_warning.dart';
import 'package:feldexa_app/features/fill/text_control.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';

/// Stable key for the sheet root.
const ValueKey<String> fieldValueSheetKey = ValueKey<String>(
  'field-value-sheet',
);

/// Stable key for the commit action.
const ValueKey<String> fieldValueSaveKey = ValueKey<String>('field-value-save');

/// Stable key for the close action.
const ValueKey<String> fieldValueCloseKey = ValueKey<String>(
  'field-value-close',
);

/// Stable key for the visible validation/save error.
const ValueKey<String> fieldValueErrorKey = ValueKey<String>(
  'field-value-error',
);

/// Stable key for the visible `NOT_RUN` signature marker.
const ValueKey<String> fieldValueSignatureNotRunKey = ValueKey<String>(
  'field-value-signature-not-run',
);

/// The outcome of one caller-owned value commit.
final class FieldValueCommitResult {
  /// The caller verified and persisted the value.
  const FieldValueCommitResult.saved() : message = null;

  /// The caller did not persist the value; [message] is a German catalog
  /// sentence or a content-free failure message to show in the open sheet.
  const FieldValueCommitResult.failed(this.message);

  /// The content-free failure message, or null on success.
  final String? message;

  /// Whether the caller persisted the value.
  bool get isSaved => message == null;
}

/// Type-appropriate editor for one confirmed field value.
///
/// The sheet owns only transient draft state. [currentValue] is copied once as
/// the initial draft; later caller rebuilds do not overwrite active input. The
/// field type decides the control:
///
/// * `text` and `multiline` use T079 with the matching line-break behavior;
/// * `number` and `date` use T079 plus the T080/T081 parsers and the catalog
///   error text; invalid input stays in the control;
/// * `checkbox` uses T082;
/// * `signature` is visibly `NOT_RUN` and offers no save action.
///
/// The sheet calls [onCommit] exactly once per save action. A successful result
/// pops with `true`; a failed result keeps the sheet open with the returned
/// message. The sheet never writes a store, reads a clock, or calls the
/// application command itself.
class FieldValueSheet extends StatefulWidget {
  /// Creates a value sheet for [field].
  const FieldValueSheet({
    required this.field,
    required this.currentValue,
    required this.onCommit,
    super.key,
  });

  /// The confirmed field being edited.
  final core.ConfirmedField field;

  /// The currently committed value, or null when the field has no value.
  final core.FieldValue? currentValue;

  /// Saves one validated value; the caller stamps the real edit instant,
  /// applies `setFieldValue`, and persists the revision.
  final Future<FieldValueCommitResult> Function(core.FieldValue value) onCommit;

  @override
  State<FieldValueSheet> createState() => _FieldValueSheetState();
}

class _FieldValueSheetState extends State<FieldValueSheet> {
  late String _text;
  late bool _checked;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _text = _initialText();
    final core.FieldValue? value = widget.currentValue;
    _checked = value is core.CheckboxValue ? value.checked : false;
  }

  String _initialText() {
    final core.FieldValue? value = widget.currentValue;
    if (value is core.TextValue) {
      return value.text;
    }
    if (value is core.MultilineValue) {
      return value.text;
    }
    if (value is core.NumberValue) {
      return value.rawGerman;
    }
    if (value is core.DateValue) {
      return _germanDate(value.canonical);
    }
    if (value is core.IncompatibleValue) {
      return value.preservedText;
    }
    return '';
  }

  DateTime get _draftEditedAt => widget.field.updatedAt;

  core.FieldValue? _buildValue() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    switch (widget.field.type) {
      case core.FieldType.text:
        return core.TextValue(
          text: _text,
          lastEditedAt: _draftEditedAt,
          overflow: widget.currentValue?.overflow ?? false,
        );
      case core.FieldType.multiline:
        return core.MultilineValue(
          text: _text,
          lastEditedAt: _draftEditedAt,
          overflow: widget.currentValue?.overflow ?? false,
        );
      case core.FieldType.number:
        final String raw = _text.trim();
        final String? canonical = core.parseGermanNumber(raw);
        if (canonical == null) {
          _error = l10n.num001;
          return null;
        }
        return core.NumberValue(
          canonical: canonical,
          rawGerman: raw,
          lastEditedAt: _draftEditedAt,
          overflow: widget.currentValue?.overflow ?? false,
        );
      case core.FieldType.date:
        final core.DateParseResult parsed = core.parseGermanDate(_text);
        if (!parsed.isSuccess) {
          _error = parsed.errorCode == 'DATE-002' ? l10n.date002 : l10n.date001;
          return null;
        }
        return core.DateValue(
          canonical: parsed.canonical!,
          lastEditedAt: _draftEditedAt,
          overflow: widget.currentValue?.overflow ?? false,
        );
      case core.FieldType.checkbox:
        return core.CheckboxValue(
          checked: _checked,
          lastEditedAt: _draftEditedAt,
          overflow: widget.currentValue?.overflow ?? false,
        );
      case core.FieldType.signature:
        return null;
    }
  }

  Future<void> _save() async {
    if (_busy || widget.field.type == core.FieldType.signature) {
      return;
    }
    setState(() {
      _error = null;
    });
    final core.FieldValue? value = _buildValue();
    if (value == null) {
      if (mounted) {
        setState(() {});
      }
      return;
    }
    setState(() {
      _busy = true;
    });
    FieldValueCommitResult result;
    try {
      result = await widget.onCommit(value);
    } catch (_) {
      if (!mounted) {
        return;
      }
      result = FieldValueCommitResult.failed(
        AppLocalizations.of(context).save003,
      );
    }
    if (!mounted) {
      return;
    }
    if (result.isSaved) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool signature = widget.field.type == core.FieldType.signature;
    final bool overflow = widget.currentValue?.overflow ?? false;
    return Padding(
      key: fieldValueSheetKey,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                widget.field.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(_typeLabel(l10n, widget.field.type)),
              const SizedBox(height: 12),
              AbsorbPointer(absorbing: _busy, child: _buildControl(l10n)),
              if (!signature) ...<Widget>[
                const SizedBox(height: 12),
                FieldOverflowWarning(visible: overflow),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    key: fieldValueErrorKey,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  key: fieldValueSaveKey,
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.saveNow),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                key: fieldValueCloseKey,
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).maybePop(false),
                child: Text(l10n.reviewConflictCloseAction),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControl(AppLocalizations l10n) {
    switch (widget.field.type) {
      case core.FieldType.text:
        return FieldTextControl(
          label: widget.field.label,
          value: _text,
          autofocus: true,
          onChanged: (String value) => _text = value,
          onCommitted: (String value) => _text = value,
        );
      case core.FieldType.multiline:
        return FieldTextControl(
          label: widget.field.label,
          value: _text,
          multiline: true,
          autofocus: true,
          onChanged: (String value) => _text = value,
          onCommitted: (String value) => _text = value,
        );
      case core.FieldType.number:
      case core.FieldType.date:
        return FieldTextControl(
          label: widget.field.label,
          value: _text,
          autofocus: true,
          onChanged: (String value) => _text = value,
          onCommitted: (String value) => _text = value,
        );
      case core.FieldType.checkbox:
        return FieldCheckboxControl(
          label: widget.field.label,
          value: _checked,
          onChanged: (bool value) {
            setState(() {
              _checked = value;
            });
          },
        );
      case core.FieldType.signature:
        return Column(
          key: fieldValueSignatureNotRunKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.a11ySignatureUnsigned),
            const SizedBox(height: 8),
            Text(
              'NOT_RUN',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ],
        );
    }
  }
}

String _germanDate(String canonical) {
  final DateTime? date = DateTime.tryParse(canonical);
  if (date == null) {
    return canonical;
  }
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year}';
}

String _typeLabel(AppLocalizations l10n, core.FieldType type) {
  return switch (type) {
    core.FieldType.text => l10n.suggestionTypeText,
    core.FieldType.multiline => l10n.suggestionTypeMultiline,
    core.FieldType.number => l10n.suggestionTypeNumber,
    core.FieldType.date => l10n.suggestionTypeDate,
    core.FieldType.checkbox => l10n.suggestionTypeCheckbox,
    core.FieldType.signature => l10n.suggestionTypeSignature,
  };
}
