// T082 reusable checkbox control for the filling surface.
//
// Owner: `apps/feldexa_app/lib/features/fill/checkbox_control.dart` (T082).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/contracts/editor-interactions.md`
//     section 5 (a checkbox is a tappable box with 48 dp hit slop; it toggles
//     on tap and the exported mark is independent of the hit area) and
//     section 11 (minimum touch target 48 x 48 dp, visual handles may be
//     smaller, and 200 % text scale reflows);
//   * `specs/001-scanned-form-workflow/spec.md` FR-042 (every checkbox field
//     has an individually settable checked or unchecked state) and FR-094
//     (state is never signalled by colour alone);
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// What this file is
// -----------------
// A presentational checkbox. The caller owns the value; this widget only
// reports a requested new value through `onChanged`. It never reads a
// document, editor, analysis result, store, file, or network, and it adds no
// group semantics: two controls remain independent because each value comes
// from its own caller.
//
// Geometry
// --------
// The drawn box is 24 dp. The tappable region is a separate explicit
// constraint of at least 48 x 48 dp and the whole box-plus-label row uses an
// opaque tap handler, so the hit area does not shrink with the glyph and does
// not depend on padding around it. The label is never truncated; at 200 %
// text scale it wraps and the row grows while the 48 dp hit area stays intact.
//
// User-visible text
// -----------------
// Every visible label comes from the constructor. This file imports no
// localization or generated ARB module and composes no literal user-facing
// sentence, so the application ARB remains the single source of German UI
// text.
//
// Evidence
// --------
// This widget is covered by host-VM widget tests only. It makes no Android,
// device, screen-reader, or visual claim, and its tests produce no evidence
// class above NONE.

import 'package:flutter/material.dart';

/// Stable key for the outer checkbox control and its tappable hit region.
const ValueKey<String> fieldCheckboxControlKey = ValueKey<String>(
  'field-checkbox-control',
);

/// Stable key for the visibly drawn checkbox glyph.
///
/// The glyph is deliberately smaller than the surrounding hit region.
const ValueKey<String> fieldCheckboxBoxKey = ValueKey<String>(
  'field-checkbox-box',
);

/// Minimum width and height of the tappable region.
const double _minimumHitExtent = 48;

/// Width and height of the drawn checkbox glyph.
const double _boxExtent = 24;

/// Width of the drawn checkbox border.
const double _boxBorderWidth = 2;

/// Horizontal gap between the hit region and the visible label.
const double _labelGap = 12;

/// A caller-labelled, presentation-only checkbox for one field value.
///
/// [value] is supplied by the parent and is never changed internally. A tap
/// anywhere in the at-least-48-by-48-dp hit region reports `!value` through
/// [onChanged] exactly once. The visible box is drawn smaller than that region.
///
/// The whole box-plus-label row is one control. The caller label is shown next
/// to the box and is also the accessible name unless [semanticLabel] overrides
/// it. Semantics expose the checked state, the enabled state, and the read-only
/// state as a single accessible node; the painted glyph and the visible text
/// are not separate nodes.
///
/// A disabled or read-only control neither toggles nor calls [onChanged].
class FieldCheckboxControl extends StatelessWidget {
  /// Creates a checkbox for one field value.
  const FieldCheckboxControl({
    required this.label,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.enabled = true,
    this.readOnly = false,
    super.key,
  });

  /// Caller-supplied label shown next to the box.
  ///
  /// The same text is the accessible name when [semanticLabel] is null.
  final String label;

  /// Whether the box is currently checked.
  final bool value;

  /// Called with the requested new value when the user toggles the control.
  ///
  /// Never called while [enabled] is false or [readOnly] is true.
  final ValueChanged<bool> onChanged;

  /// Optional caller-supplied accessible name.
  ///
  /// When null, [label] is used. The visible text remains [label] either way.
  final String? semanticLabel;

  /// Whether the control accepts taps.
  final bool enabled;

  /// Whether the value is read-only even when the control is enabled.
  final bool readOnly;

  bool get _interactive => enabled && !readOnly;

  void _handleTap() {
    if (!_interactive) {
      return;
    }
    onChanged(!value);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool interactive = _interactive;
    final Color foreground = interactive
        ? colors.onSurface
        : colors.onSurface.withValues(alpha: 0.38);
    final Color fill = value
        ? (interactive ? colors.primary : foreground)
        : Colors.transparent;
    final Color mark = interactive ? colors.onPrimary : colors.surface;
    final TextStyle labelStyle =
        (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
          color: foreground,
        );

    return Semantics(
      key: fieldCheckboxControlKey,
      container: true,
      excludeSemantics: true,
      enabled: enabled,
      readOnly: readOnly,
      checked: value,
      label: semanticLabel ?? label,
      onTap: interactive ? _handleTap : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: _minimumHitExtent,
          minHeight: _minimumHitExtent,
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: interactive ? _handleTap : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: _minimumHitExtent,
                height: _minimumHitExtent,
                child: Center(
                  child: Container(
                    key: fieldCheckboxBoxKey,
                    width: _boxExtent,
                    height: _boxExtent,
                    decoration: BoxDecoration(
                      color: fill,
                      border: Border.all(
                        color: foreground,
                        width: _boxBorderWidth,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: value
                        ? Icon(Icons.check, size: 16, color: mark)
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: _labelGap),
              Flexible(child: Text(label, style: labelStyle)),
            ],
          ),
        ),
      ),
    );
  }
}
