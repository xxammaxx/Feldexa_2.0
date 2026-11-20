// T084 reusable field-overflow warning for the filling surface.
//
// Owner: `apps/feldexa_app/lib/features/fill/overflow_warning.dart` (T084).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/contracts/editor-interactions.md`
//     section 5 (entered text that overflows shows the `FLD-001` warning
//     immediately after commit and the value is kept) and section 11 (status
//     is never colour-only, 48 dp primary controls, and 200 % text scale
//     reflows without clipping);
//   * `specs/001-scanned-form-workflow/spec.md` FR-037 (warn before
//     finalization when content exceeds its field), FR-038 (never silently
//     truncate, drop, reorder, or omit entered information), and FR-068 (stop
//     the export and warn in German when content would be clipped);
//   * `specs/001-scanned-form-workflow/contracts/error-catalog.de.md` FLD-001
//     and EXP-001 (both stop the export until the text is shortened or the
//     field is enlarged);
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// What this file is
// -----------------
// A presentation-only warning banner. The caller owns the overflow decision
// and passes it as `visible`; this widget never measures text, never reads or
// writes a document, editor, store, database, preference, file, or network,
// and it holds no path, field, or byte-buffer handle.
//
// Visibility and dismissal
// ------------------------
// The visible surface is a persistent warning card with an error icon and the
// two FLD-001 sentences. It has no close, dismiss, or retry action: the only
// way to clear it is for the caller to rebuild with `visible == false`, at
// which point the widget returns `SizedBox.shrink()` with no semantics node
// and no reserved space.
//
// User-visible text
// -----------------
// Both sentences come from the existing `fld001` and `fld001Recovery` ARB
// getters; this file composes no user-facing German sentence of its own. The
// error icon is decorative because the text already carries the state, so it
// adds no second semantic announcement.
//
// Evidence
// --------
// This widget is covered by host-VM widget tests only. It makes no Android,
// device, screen-reader, or visual claim, and its tests produce no evidence
// class above NONE.

import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Stable key for the visible overflow warning surface.
const ValueKey<String> fieldOverflowWarningKey = ValueKey<String>(
  'field-overflow-warning',
);

/// Presentation-only FLD-001 overflow warning for one field value.
///
/// [visible] is supplied by the parent and is never changed internally. When
/// false the widget renders a zero-sized placeholder with no semantics and
/// reserves no space. When true it renders a persistent warning card with an
/// error icon and the exact `fld001` and `fld001Recovery` sentences from the
/// application ARB. There is no dismiss action; only a rebuild with
/// `visible == false` clears the warning.
class FieldOverflowWarning extends StatelessWidget {
  /// Creates an overflow warning controlled by [visible].
  const FieldOverflowWarning({required this.visible, super.key});

  /// Whether the warning is currently shown.
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox.shrink();
    }

    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String message = l10n.fld001;
    final String recovery = l10n.fld001Recovery;
    final TextStyle? bodyStyle = textTheme.bodyMedium?.copyWith(
      color: colors.onErrorContainer,
    );

    return Semantics(
      key: fieldOverflowWarningKey,
      container: true,
      liveRegion: true,
      excludeSemantics: true,
      label: '$message\n$recovery',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.errorContainer,
          border: Border.all(color: colors.error),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.error_outline, color: colors.error),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(message, style: bodyStyle),
                    const SizedBox(height: 4),
                    Text(recovery, style: bodyStyle),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
