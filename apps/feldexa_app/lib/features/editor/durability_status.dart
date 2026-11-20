// T091 durability labels, status surface, and PRIV-001 disclosure.
//
// Owner: `apps/feldexa_app/lib/features/editor/durability_status.dart` (T091,
// issue #91).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/spec.md` FR-046 (only a verified commit
//     is presented as durable) and FR-051 (pre-emptive key and backup
//     disclosure before loss);
//   * `contracts/editor-interactions.md` section 7 (the status uses the
//     catalog label and never shows a green check for unsaved work) and
//     section 11 (status is never colour-only and 200 % text scale reflows);
//   * `contracts/error-catalog.de.md` section 3 (the durability labels);
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// What this surface is
// -----------------
// Two presentation-only widgets. They map an already-decided
// `DurabilityStatus` and a caller-owned `visible` flag to the committed German
// ARB text. They perform no I/O, hold no document or key handle, read no
// clock, and expose no action. The caller owns durability and visibility.
//
// Durability honesty
// ------------------
// Only `clean` and `saved` may render a check. `saving`, `unsaved`, and
// `saveFailed` keep a distinct icon and wording, so a scan of the tree cannot
// mistake a pending or failed save for durable content. Status is conveyed by
// text plus icon, never by colour alone.
//
// Evidence
// --------
// Covered by host-VM widget tests only. No Android, device, screen-reader, or
// visual claim; evidence class NONE.

import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Stable key for the one durability status surface.
const ValueKey<String> durabilityStatusLabelKey = ValueKey<String>(
  'durability-status-label',
);

/// Stable key for the visible PRIV-001 key/backup disclosure.
const ValueKey<String> privacyKeyDisclosureKey = ValueKey<String>(
  'privacy-key-disclosure',
);

/// Formats [time] as a local 24-hour `HH:mm` durability label.
///
/// Applies [DateTime.toLocal] exactly once and reads no clock. A null time
/// renders the visible `--:--` fallback; this surface composes no German
/// sentence of its own for a missing timestamp.
String durabilityTimeLabel(DateTime? time) {
  if (time == null) {
    return '--:--';
  }
  final DateTime local = time.toLocal();
  final String hour = local.hour.toString().padLeft(2, '0');
  final String minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// Presentation-only durability label for the editor and document overview.
///
/// [status] is decided by the caller. [lastDurableAt], when non-null, is the
/// caller-supplied durable time and takes precedence; otherwise a
/// [SavedDurabilityStatus] uses its own UTC `lastDurableAt`. Only
/// [CleanDurabilityStatus] and [SavedDurabilityStatus] render a check. The
/// widget holds one semantic status node whose label is exactly the visible
/// text; the icon or spinner is decorative.
class DurabilityStatusLabel extends StatelessWidget {
  /// Creates a durability label for [status].
  const DurabilityStatusLabel({
    required this.status,
    this.lastDurableAt,
    super.key,
  });

  /// The already-decided durability state.
  final DurabilityStatus status;

  /// Caller-supplied durable time, taking precedence over the saved state's
  /// own timestamp.
  final DateTime? lastDurableAt;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String timeLabel = durabilityTimeLabel(
      lastDurableAt ?? _savedTime(status),
    );

    final ({String text, IconData? icon, bool loading}) presentation =
        switch (status) {
          CleanDurabilityStatus() => (
            text: l10n.durabilityClean,
            icon: Icons.check_circle_outline,
            loading: false,
          ),
          SavingDurabilityStatus() => (
            text: l10n.durabilitySaving,
            icon: null,
            loading: true,
          ),
          UnsavedDurabilityStatus() => (
            text: l10n.durabilityUnsaved,
            icon: Icons.warning_amber_rounded,
            loading: false,
          ),
          SavedDurabilityStatus() => (
            text: l10n.durabilitySaved(timeLabel),
            icon: Icons.check_circle,
            loading: false,
          ),
          SaveFailedDurabilityStatus() => (
            text: l10n.durabilitySaveFailed(timeLabel),
            icon: Icons.error_outline,
            loading: false,
          ),
          RecoveryFallbackDurabilityStatus() => (
            text: l10n.durabilityRecoveryFallback,
            icon: Icons.restore,
            loading: false,
          ),
        };

    final Color iconColor = switch (status) {
      CleanDurabilityStatus() || SavedDurabilityStatus() => colors.primary,
      SavingDurabilityStatus() => colors.onSurfaceVariant,
      UnsavedDurabilityStatus() || SaveFailedDurabilityStatus() => colors.error,
      RecoveryFallbackDurabilityStatus() => colors.tertiary,
    };

    final Widget marker = presentation.loading
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: iconColor),
          )
        : Icon(presentation.icon, size: 20, color: iconColor);

    return Semantics(
      key: durabilityStatusLabelKey,
      container: true,
      excludeSemantics: true,
      role: SemanticsRole.status,
      label: presentation.text,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ExcludeSemantics(child: marker),
          const SizedBox(width: 8),
          Expanded(child: Text(presentation.text)),
        ],
      ),
    );
  }
}

/// Persistent PRIV-001 key and backup disclosure.
///
/// [visible] is supplied by the caller and is never changed internally. When
/// false the widget renders a zero-sized placeholder with no semantics, text,
/// key, or reserved space. When true it renders one card with the exact
/// `priv001` sentence from the committed application ARB. There is no dismiss,
/// close, retry, or tap action; only a rebuild with `visible == false` hides
/// it. The lock icon is decorative and the text is the only user-visible
/// wording.
class PrivacyKeyDisclosure extends StatelessWidget {
  /// Creates a disclosure controlled by [visible].
  const PrivacyKeyDisclosure({this.visible = true, super.key});

  /// Whether the disclosure is currently shown.
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox.shrink();
    }

    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final String message = l10n.priv001;

    return Semantics(
      key: privacyKeyDisclosureKey,
      container: true,
      excludeSemantics: true,
      label: message,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border.all(color: colors.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.lock_outline,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Returns the saved state's own UTC time, or null for every other state.
DateTime? _savedTime(DurabilityStatus status) {
  if (status is SavedDurabilityStatus) {
    return status.lastDurableAt;
  }
  return null;
}
