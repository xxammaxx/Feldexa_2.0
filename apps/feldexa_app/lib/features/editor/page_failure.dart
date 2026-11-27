// T123 German explanations for failed pages and unsupported structures
// (FR-084; US8 scenario 2; `contracts/error-catalog.de.md` REC-002/REC-003).
//
// Builds on the T044 page-`unreadable` + `IMP-006` seam: `EditorScreen`
// already persists an import-unreadable page as `failed` with the
// `IMP-006` message key and keeps every other page usable. This file adds
// the per-page presentation of that state and of the analysis failures
// REC-002 (detection failed) and REC-003 (unsupported/damaged structure),
// with the exact catalog texts and recovery guidance from the ARB — no
// Dart literals.
//
// Honesty rules (FR-085, error catalog §2): a failure notice never states
// or implies completeness. It names only the failed page, says that other
// pages and already-recognized data remain unchanged, and always carries
// the catalog recovery guidance. The notice is a live region so screen
// readers announce it (FR-094).

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// The failure explanation for one page, in German.
///
/// [message] and [recovery] are exact catalog texts from the ARB; [code] is
/// the developer-facing catalog code (`REC-002`, `REC-003`, `IMP-006`) and
/// is never rendered as user-visible English.
final class PageFailureExplanation {
  const PageFailureExplanation({
    required this.code,
    required this.message,
    required this.recovery,
  });

  /// The error-catalog code that produced this explanation.
  final String code;

  /// The catalog German message for the failed page.
  final String message;

  /// The catalog German recovery guidance.
  final String recovery;
}

/// Maps one page's canonical failure message key to its catalog explanation.
///
/// [pageIndex] is zero-based, matching `PageState`; the catalog texts are
/// phrased one-based, so the helper adds one exactly here. Unknown or null
/// keys return `null`: a page without a failure key has no failure notice,
/// and inventing an explanation for an unknown key would fabricate state.
PageFailureExplanation? explainPageFailure(
  AppLocalizations l10n, {
  required int pageIndex,
  required String? messageKey,
}) {
  final int page = pageIndex + 1;
  return switch (messageKey) {
    'REC-002' => PageFailureExplanation(
      code: 'REC-002',
      message: l10n.rec002(page),
      recovery: l10n.rec002Recovery,
    ),
    'REC-003' => PageFailureExplanation(
      code: 'REC-003',
      message: l10n.rec003(page),
      recovery: l10n.rec003Recovery,
    ),
    'IMP-006' => PageFailureExplanation(
      code: 'IMP-006',
      message: l10n.imp006('$page'),
      recovery: l10n.imp006Recovery,
    ),
    _ => null,
  };
}

/// Stable key for the failure notice of one page in widget tests.
const String pageFailureNoticeKeyPrefix = 'page-failure-notice-';

/// A stable key for the recovery guidance line of one page's notice.
const String pageFailureRecoveryKeyPrefix = 'page-failure-recovery-';

/// The German failure notice rendered on or next to a failed page.
///
/// The notice shows the catalog message and the recovery guidance as two
/// separate text blocks (never concatenated), exposes them as one live
/// region so the failure is announced without color or icon (FR-094), and
/// wraps at 200 % text scale. It offers no action of its own: the page
/// remains usable for manual field work around it (FR-084).
class PageFailureNotice extends StatelessWidget {
  const PageFailureNotice({super.key, required this.explanation});

  /// The explanation from [explainPageFailure]; never constructed ad hoc.
  final PageFailureExplanation explanation;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      header: true,
      child: Column(
        key: ValueKey<String>('$pageFailureNoticeKeyPrefix${explanation.code}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            explanation.message,
            style: theme.textTheme.bodyMedium,
            softWrap: true,
          ),
          const SizedBox(height: 4),
          Text(
            explanation.recovery,
            key: const ValueKey<String>(pageFailureRecoveryKeyPrefix),
            style: theme.textTheme.bodySmall,
            softWrap: true,
          ),
        ],
      ),
    );
  }
}
