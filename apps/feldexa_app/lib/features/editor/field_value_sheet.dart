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
// catalog sentence and is never handed to the caller. Text and multiline input
// are checked against the same model limits as the value constructors (at most
// 10,000 runes; no control characters, with `\n` allowed only in multiline)
// before a value is built, so a rejected edit shows the catalog `SAVE-007`
// sentence in the open sheet, stores nothing, and never throws. Long input is
// never truncated.
//
// Commit triggers: the explicit save button, focus loss, single-line Enter, and
// the multiline done action (T079 `onCommitted`) all run the same validated
// `_save()` path. The explicit close button is the one exception: it sets
// `_closing` before popping so the focus loss caused by closing cannot turn
// into a save. A failed save leaves the sheet open and editable and displays
// the caller-supplied content-free message; no `saved` claim is made here.
//
// The sheet root is keyboard-safe: the real view insets lift the visible sheet
// box above the software keyboard on the 411 x 914 logical phone surface, and
// the box is bounded by the remaining view height so the title, control, save,
// and close actions stay reachable.
//
// T073 adds two contract surfaces to the same sheet:
//   * the per-field action „In Reihenfolge verschieben“
//     (`contracts/editor-interactions.md` §3, FR-026): it commits the open
//     draft through the same validated path and then asks the caller to open
//     the field-order review;
//   * previous/next field actions (`contracts/editor-interactions.md` §5,
//     US4 scenario 4): the draft is committed first, then the caller swaps the
//     field inside this still-open sheet so the next/previous control takes
//     focus. Both are disabled at the order boundaries, and a failed commit
//     keeps the current field and shows the existing error instead of moving.
//
// Signature editing is not faked. No production signature-asset write flow is
// composed by T071A, so the sheet visibly marks signature editing `NOT_RUN`
// and offers no save action. Overflow measurement is also not implemented in
// T071A: T084 is rendered only when the caller already marked the stored value
// `overflow`, and the journey report records layout measurement as `NOT_RUN`.

import 'dart:async';

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

/// Stable key for the per-field „In Reihenfolge verschieben“ action.
const ValueKey<String> fieldValueReorderKey = ValueKey<String>(
  'field-value-reorder',
);

/// Stable key for the previous-field traversal action.
const ValueKey<String> fieldValuePreviousKey = ValueKey<String>(
  'field-value-previous',
);

/// Stable key for the next-field traversal action.
const ValueKey<String> fieldValueNextKey = ValueKey<String>('field-value-next');

/// The direction of one focus move in the current field order
/// (`contracts/editor-interactions.md` §5).
enum FieldValueNavigation {
  /// Move to the field before this one in the current order.
  previous,

  /// Move to the field after this one in the current order.
  next,
}

/// What the sheet asks the caller to do after it closes.
enum FieldValueSheetOutcome {
  /// Open the FR-026 field-order review for the same document.
  reorder,
}

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
    this.onNavigate,
    this.canGoPrevious = false,
    this.canGoNext = false,
    super.key,
  });

  /// The confirmed field being edited.
  final core.ConfirmedField field;

  /// The currently committed value, or null when the field has no value.
  final core.FieldValue? currentValue;

  /// Saves one validated value; the caller stamps the real edit instant,
  /// applies `setFieldValue`, and persists the revision.
  final Future<FieldValueCommitResult> Function(core.FieldValue value) onCommit;

  /// Moves focus to the previous/next field in the current order.
  ///
  /// The caller keeps this sheet open and swaps the field; when null, the
  /// traversal actions are not rendered.
  final ValueChanged<FieldValueNavigation>? onNavigate;

  /// Whether a previous field exists in the current order.
  final bool canGoPrevious;

  /// Whether a next field exists in the current order.
  final bool canGoNext;

  @override
  State<FieldValueSheet> createState() => _FieldValueSheetState();
}

class _FieldValueSheetState extends State<FieldValueSheet> {
  late String _text;
  late bool _checked;
  String? _error;
  bool _busy = false;

  /// Set while the sheet is leaving the current field.
  ///
  /// Explicit close, the reorder hand-off, and a next/previous swap all move
  /// focus away from the text control. That focus loss would otherwise report
  /// the same draft through `onCommitted` and save it a second time (or save a
  /// draft the user cancelled), so the transition sets this flag first.
  bool _closing = false;

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
        if (!_isTextWithinModelLimits(_text, multiline: false)) {
          _error = l10n.save007;
          return null;
        }
        return core.TextValue(
          text: _text,
          lastEditedAt: _draftEditedAt,
          overflow: widget.currentValue?.overflow ?? false,
        );
      case core.FieldType.multiline:
        if (!_isTextWithinModelLimits(_text, multiline: true)) {
          _error = l10n.save007;
          return null;
        }
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

  /// Whether [text] satisfies the value model's text limits.
  ///
  /// At most 10,000 runes. A control character (`< 0x20`, or `0x7F..0x9F`) is
  /// rejected; `\n` is the only control character allowed, and only for a
  /// multiline value. This mirrors the core constructor without constructing a
  /// throwing value, so the sheet can show the catalog sentence instead.
  bool _isTextWithinModelLimits(String text, {required bool multiline}) {
    int runes = 0;
    for (final int rune in text.runes) {
      runes++;
      if (rune == 0x0A) {
        if (!multiline) {
          return false;
        }
        continue;
      }
      if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
        return false;
      }
    }
    return runes <= 10000;
  }

  /// Commits the current text through the same validated save path.
  ///
  /// T079 reports focus loss, single-line Enter, and the multiline done action
  /// here. The text is assigned first so the value is current even if the
  /// control's rebuild order changes.
  void _commit(String value) {
    _text = value;
    unawaited(_save());
  }

  /// Cancels the sheet without saving a focus-loss commit.
  void _close() {
    _closing = true;
    Navigator.of(context).maybePop();
  }

  /// Commits the current draft through the one validated save path.
  ///
  /// Returns null when the sheet is busy or leaving, the field type has no
  /// storable value, or the widget unmounted during the save. Otherwise returns
  /// the caller's result; a failed result is already shown through [_error].
  Future<FieldValueCommitResult?> _commitDraft() async {
    if (_busy || _closing || widget.field.type == core.FieldType.signature) {
      return null;
    }
    setState(() {
      _error = null;
    });
    final core.FieldValue? value = _buildValue();
    if (value == null) {
      if (mounted) {
        setState(() {});
      }
      return null;
    }
    setState(() {
      _busy = true;
    });
    FieldValueCommitResult result;
    try {
      result = await widget.onCommit(value);
    } catch (_) {
      if (!mounted) {
        return null;
      }
      result = FieldValueCommitResult.failed(
        AppLocalizations.of(context).save003,
      );
    }
    if (!mounted) {
      return null;
    }
    if (!result.isSaved) {
      // A failed save stays editable on the same field and shows the message.
      setState(() {
        _busy = false;
        _error = result.message;
      });
    }
    // On success the sheet stays busy until it pops, swaps fields, or hands
    // off to the order review. That keeps a focus-loss commit and the action
    // that moved focus from saving the same draft twice.
    return result;
  }

  Future<void> _save() async {
    final FieldValueCommitResult? result = await _commitDraft();
    if (result == null || !result.isSaved || !mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  /// Commits the draft and then moves to the next/previous field.
  ///
  /// The caller keeps this sheet open and swaps in the target field, so the
  /// next control requests focus without a new route. A failed commit keeps the
  /// current field and the entered text.
  Future<void> _navigate(FieldValueNavigation direction) async {
    if (_busy || _closing) {
      return;
    }
    final ValueChanged<FieldValueNavigation>? onNavigate = widget.onNavigate;
    if (onNavigate == null) {
      return;
    }
    if (widget.field.type != core.FieldType.signature) {
      final FieldValueCommitResult? result = await _commitDraft();
      if (result == null || !result.isSaved || !mounted) {
        return;
      }
    }
    _closing = true;
    onNavigate(direction);
  }

  /// Commits the draft and hands the field-order review to the caller.
  ///
  /// The sheet closes with [FieldValueSheetOutcome.reorder]; the caller opens
  /// the review only after the commit is verified, so a failed save keeps the
  /// field and the draft.
  Future<void> _reorder() async {
    if (_busy || _closing) {
      return;
    }
    if (widget.field.type != core.FieldType.signature) {
      final FieldValueCommitResult? result = await _commitDraft();
      if (result == null || !result.isSaved || !mounted) {
        return;
      }
    }
    _closing = true;
    Navigator.of(context).pop(FieldValueSheetOutcome.reorder);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool signature = widget.field.type == core.FieldType.signature;
    final bool overflow = widget.currentValue?.overflow ?? false;
    final MediaQueryData media = MediaQuery.of(context);
    final double insets = media.viewInsets.bottom;
    final double availableHeight =
        media.size.height - insets - media.padding.top;
    final double maxHeight = availableHeight < 1 ? 1 : availableHeight;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: insets),
      child: ConstrainedBox(
        // The key marks the visible, keyboard-safe sheet box rather than the
        // animated keyboard spacer, so the global rect stays above the IME.
        key: fieldValueSheetKey,
        constraints: BoxConstraints(maxHeight: maxHeight),
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
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
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
                const SizedBox(height: 12),
                OutlinedButton(
                  key: fieldValueReorderKey,
                  onPressed: _busy
                      ? null
                      : () {
                          unawaited(_reorder());
                        },
                  child: Text(l10n.fieldOrderMoveAction),
                ),
                if (widget.onNavigate != null)
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextButton(
                          key: fieldValuePreviousKey,
                          onPressed: !_busy && !_closing && widget.canGoPrevious
                              ? () {
                                  unawaited(
                                    _navigate(FieldValueNavigation.previous),
                                  );
                                }
                              : null,
                          child: Text(l10n.fieldOrderPreviousField),
                        ),
                      ),
                      Expanded(
                        child: TextButton(
                          key: fieldValueNextKey,
                          onPressed: !_busy && !_closing && widget.canGoNext
                              ? () {
                                  unawaited(
                                    _navigate(FieldValueNavigation.next),
                                  );
                                }
                              : null,
                          child: Text(l10n.fieldOrderNextField),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                TextButton(
                  key: fieldValueCloseKey,
                  onPressed: _busy ? null : _close,
                  child: Text(l10n.reviewConflictCloseAction),
                ),
              ],
            ),
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
          onCommitted: _commit,
        );
      case core.FieldType.multiline:
        return FieldTextControl(
          label: widget.field.label,
          value: _text,
          multiline: true,
          autofocus: true,
          doneLabel: l10n.pageAnalysisComplete,
          onChanged: (String value) => _text = value,
          onCommitted: _commit,
        );
      case core.FieldType.number:
      case core.FieldType.date:
        return FieldTextControl(
          label: widget.field.label,
          value: _text,
          autofocus: true,
          onChanged: (String value) => _text = value,
          onCommitted: _commit,
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
