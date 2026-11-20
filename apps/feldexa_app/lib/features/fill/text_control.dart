// T079 reusable text-entry control for the filling surface.
//
// Owner: `apps/feldexa_app/lib/features/fill/text_control.dart` (T079).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/contracts/editor-interactions.md`
//     section 5 (single-line text rejects line breaks; multiline preserves
//     them; values commit on focus loss, the done action, or Enter; the
//     previous/next field actions move focus in field order) and section 11
//     (accessible labels, 48 dp controls, 200 % text scale);
//   * `specs/001-scanned-form-workflow/spec.md` FR-033, FR-035, FR-038,
//     FR-039, FR-040;
//   * `specs/001-scanned-form-workflow/data-model.md` section 3.6 (the
//     10,000-character model limit belongs to validation, not this control);
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// What this file is
// -----------------
// A presentational text input. It owns one `TextEditingController` and either
// uses the caller's `FocusNode` or creates and disposes its own. It never
// reads a document, editor, analysis result, store, file, or network. It
// writes nothing; `onChanged` reports each edit and `onCommitted` reports the
// final text once when it differs from the last committed or externally
// supplied value. The parent remains the sole owner of editing state,
// validation (including the 10,000-character limit), persistence, and undo.
//
// Text is never truncated, no `maxLength` or character counter is added, and
// a single-line control filters carriage returns and line feeds from typed or
// pasted input. A multiline control keeps line breaks and uses the platform
// multiline keyboard; its optional caller-labelled done action commits and
// unfocuses without replacing the newline behaviour.
//
// User-visible text
// -----------------
// Every visible label and tooltip comes from the constructor. This file
// imports no localization or generated ARB module and composes no literal
// user-facing sentence, so the application ARB remains the single source of
// German UI text.
//
// Evidence
// --------
// This widget is covered by host-VM widget tests only. It makes no Android,
// device, input-method, screen-reader, or visual claim, and its tests produce
// no evidence class above NONE.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Stable key for the editable text field.
const ValueKey<String> fieldTextControlInputKey = ValueKey<String>(
  'field-text-control-input',
);

/// Stable key for the optional previous-field button.
const ValueKey<String> fieldTextControlPreviousKey = ValueKey<String>(
  'field-text-control-previous',
);

/// Stable key for the optional next-field button.
const ValueKey<String> fieldTextControlNextKey = ValueKey<String>(
  'field-text-control-next',
);

/// Stable key for the optional multiline done action.
const ValueKey<String> fieldTextControlDoneKey = ValueKey<String>(
  'field-text-control-done',
);

/// A caller-labelled, presentation-only text input for one field value.
///
/// The control is intentionally unaware of field identity and document state.
/// It reports edits through [onChanged] and reports a final value through
/// [onCommitted] exactly once after the text differs from the last committed
/// or externally supplied value. [value] is synchronized into the field only
/// while the field is unfocused, so a rebuild with a stale value cannot
/// overwrite active typing.
///
/// In single-line mode a carriage return or line feed is removed from typed or
/// pasted input. The keyboard action is next when [onNext] is supplied and done
/// otherwise; submitting commits first and then invokes [onNext] or unfocuses.
///
/// In multiline mode line breaks are preserved and the platform multiline
/// keyboard inserts them. When [doneLabel] is supplied, a caller-tooltipped
/// done button commits once and unfocuses.
///
/// The optional previous and next buttons use [previousLabel] and [nextLabel]
/// as their tooltips and are omitted when their callback is null. Focus order
/// and movement remain the caller's responsibility; this widget adds no focus
/// traversal group or ordering policy.
///
/// A read-only or disabled control neither commits nor changes its text.
class FieldTextControl extends StatefulWidget {
  /// Creates a text input for one field value.
  const FieldTextControl({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onCommitted,
    this.focusNode,
    this.multiline = false,
    this.readOnly = false,
    this.onNext,
    this.onPrevious,
    this.nextLabel,
    this.previousLabel,
    this.doneLabel,
    this.autofocus = false,
    this.enabled = true,
    super.key,
  });

  /// Caller-supplied label shown on the field and exposed to assistive
  /// technology.
  final String label;

  /// Current value supplied by the parent.
  ///
  /// The field adopts it initially and again whenever it changes while the
  /// field is not focused.
  final String value;

  /// Called with the current text after every accepted edit.
  final ValueChanged<String> onChanged;

  /// Called once with the final text after a commit-worthy change.
  ///
  /// A commit is triggered by focus loss, by Enter in single-line mode, or by
  /// the multiline done action. No commit is reported when the text equals the
  /// last committed or externally supplied value.
  final ValueChanged<String> onCommitted;

  /// Optional caller-owned focus node.
  ///
  /// When null the control creates and disposes its own node.
  final FocusNode? focusNode;

  /// Whether this is a multiline field.
  final bool multiline;

  /// Whether the user may change the text.
  final bool readOnly;

  /// Optional next-field action.
  ///
  /// In single-line mode this also selects the next keyboard action.
  final VoidCallback? onNext;

  /// Optional previous-field action.
  final VoidCallback? onPrevious;

  /// Caller-supplied tooltip for the next-field button.
  final String? nextLabel;

  /// Caller-supplied tooltip for the previous-field button.
  final String? previousLabel;

  /// Caller-supplied tooltip and label for the multiline done action.
  ///
  /// When null, no done action is shown and the multiline field relies on the
  /// platform newline action alone.
  final String? doneLabel;

  /// Whether the field requests focus when first built.
  final bool autofocus;

  /// Whether the control accepts input and actions.
  final bool enabled;

  @override
  State<FieldTextControl> createState() => _FieldTextControlState();
}

class _FieldTextControlState extends State<FieldTextControl> {
  /// Removes line breaks from single-line typed and pasted input.
  static final List<TextInputFormatter> _singleLineFormatters =
      <TextInputFormatter>[FilteringTextInputFormatter.deny(RegExp(r'[\r\n]'))];

  late final TextEditingController _controller;
  late FocusNode _focusNode;
  late bool _ownsFocusNode;

  /// Text that was last committed or supplied from outside while unfocused.
  ///
  /// A focus loss or submit only calls `onCommitted` when the current text
  /// differs from this baseline. Synchronizing an external value while
  /// unfocused advances the baseline without reporting a commit.
  late String _committedText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _committedText = widget.value;
    _attachFocusNode(widget.focusNode);
  }

  @override
  void didUpdateWidget(covariant FieldTextControl oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.focusNode != oldWidget.focusNode) {
      _detachFocusNode();
      _attachFocusNode(widget.focusNode);
    }

    if (widget.value != oldWidget.value && !_focusNode.hasFocus) {
      _committedText = widget.value;
      if (_controller.text != widget.value) {
        _controller.value = TextEditingValue(
          text: widget.value,
          selection: TextSelection.collapsed(offset: widget.value.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _detachFocusNode();
    _controller.dispose();
    super.dispose();
  }

  void _attachFocusNode(FocusNode? node) {
    _focusNode = node ?? FocusNode();
    _ownsFocusNode = node == null;
    _focusNode.addListener(_handleFocusChange);
  }

  void _detachFocusNode() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _commitIfChanged();
    }
  }

  /// Commits the current text when it differs from the baseline.
  ///
  /// Returns whether a commit was reported. Read-only and disabled controls
  /// never commit. The baseline is advanced before the callback so a rebuild
  /// or focus change triggered by the caller cannot report the same text
  /// twice.
  bool _commitIfChanged() {
    if (!widget.enabled || widget.readOnly) {
      return false;
    }
    final String text = _controller.text;
    if (text == _committedText) {
      return false;
    }
    _committedText = text;
    widget.onCommitted(text);
    return true;
  }

  void _handleChanged(String text) {
    if (!widget.enabled || widget.readOnly) {
      return;
    }
    widget.onChanged(text);
  }

  void _handleSubmitted(String _) {
    _commitIfChanged();
    if (widget.onNext != null) {
      widget.onNext!();
      return;
    }
    _focusNode.unfocus();
  }

  void _handleDone() {
    _commitIfChanged();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final bool showDone = widget.multiline && widget.doneLabel != null;
    final bool showPrevious = widget.onPrevious != null;
    final bool showNext = widget.onNext != null;
    final bool showActions = showDone || showPrevious || showNext;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          key: fieldTextControlInputKey,
          controller: _controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          autofocus: widget.autofocus,
          maxLines: widget.multiline ? null : 1,
          minLines: 1,
          keyboardType: widget.multiline
              ? TextInputType.multiline
              : TextInputType.text,
          textInputAction: widget.multiline
              ? TextInputAction.newline
              : widget.onNext != null
              ? TextInputAction.next
              : TextInputAction.done,
          inputFormatters: widget.multiline ? null : _singleLineFormatters,
          onChanged: _handleChanged,
          onSubmitted: widget.multiline ? null : _handleSubmitted,
          decoration: InputDecoration(labelText: widget.label),
        ),
        if (showActions)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              if (showDone)
                IconButton(
                  key: fieldTextControlDoneKey,
                  tooltip: widget.doneLabel,
                  onPressed: widget.enabled ? _handleDone : null,
                  icon: const Icon(Icons.check),
                ),
              if (showPrevious)
                IconButton(
                  key: fieldTextControlPreviousKey,
                  tooltip: widget.previousLabel,
                  onPressed: widget.enabled ? widget.onPrevious : null,
                  icon: const Icon(Icons.chevron_left),
                ),
              if (showNext)
                IconButton(
                  key: fieldTextControlNextKey,
                  tooltip: widget.nextLabel,
                  onPressed: widget.enabled ? widget.onNext : null,
                  icon: const Icon(Icons.chevron_right),
                ),
            ],
          ),
      ],
    );
  }
}
