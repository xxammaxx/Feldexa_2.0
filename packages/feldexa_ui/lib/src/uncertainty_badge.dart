// T122 confidence/uncertainty badge (FR-083; US8).
//
// Normative sources:
//   * `contracts/recognition-output.md` §3.4 — uncertainty presentation
//     thresholds: ≥ 0.75 solid outline, 0.50–0.74 dashed outline,
//     < 0.50 dashed outline + „unsicher“ badge + explanatory semantics label;
//   * `spec.md` FR-083 — uncertainty for low-confidence suggestions is
//     visible on the document itself, not behind a separate report.
//
// Presentation only: the caller supplies the already-localized label and
// semantics label from the app ARB, exactly as `ProvenanceBadge` does, so
// this package keeps no user-facing German copy. The badge never claims
// completeness and never upgrades a suggestion: it only marks uncertainty.

import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

/// The confidence thresholds of `contracts/recognition-output.md` §3.4.
///
/// Shared by the T071A overlay outlines and this badge so the document view
/// and the review surface can never disagree about what is uncertain.
abstract final class UncertaintyThresholds {
  /// At or above this confidence the suggestion outline is solid.
  static const double solid = 0.75;

  /// Below this confidence the „unsicher“ badge is shown.
  static const double uncertain = 0.50;

  /// Whether the FR-083 badge is required for [confidence].
  ///
  /// `null` confidence is a non-machine field and never uncertain.
  static bool badgeRequired(double? confidence) =>
      confidence != null && confidence < uncertain;
}

/// A non-interactive uncertainty pill for low-confidence suggestions.
///
/// The pill renders a dashed outline — the same visual language as the
/// uncertain T071A overlay outline — with the caller-supplied localized
/// label (for example `AppLocalizations.suggestionUncertain`, „unsicher“).
/// The widget is gated: it renders the pill only when
/// [UncertaintyThresholds.badgeRequired] holds for [confidence]; any other
/// confidence renders nothing, so a caller cannot accidentally badge a
/// confident field.
///
/// The [semanticsLabel] carries the explanatory semantics label required by
/// `contracts/recognition-output.md` §3.4 for the sub-0.50 treatment; when
/// omitted or blank, the visible [label] is exposed instead, so the
/// semantic node is never empty.
///
/// The pill always reserves at least the 48 × 48 dp accessible minimum
/// (T122 acceptance), and its label wraps at 200 % text scale instead of
/// truncating. It is non-interactive: no tap handler, no gesture.
///
/// When [key] is omitted, the badge uses the stable default
/// `ValueKey('uncertainty-badge')`. Callers that render more than one badge
/// in one subtree must supply distinct keys, because sibling widgets cannot
/// share a key.
class UncertaintyBadge extends StatelessWidget {
  const UncertaintyBadge({
    super.key,
    required this.confidence,
    required this.label,
    this.semanticsLabel,
  });

  /// The suggestion confidence on `0.0 … 1.0`; `null` for non-machine
  /// fields. The badge renders only when
  /// [UncertaintyThresholds.badgeRequired] holds for it.
  final double? confidence;

  /// The already-localized visible label, for example „unsicher“.
  final String label;

  /// The explanatory screen-reader label; falls back to [label].
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    if (!UncertaintyThresholds.badgeRequired(confidence)) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    final String effectiveSemanticsLabel =
        semanticsLabel?.trim().isNotEmpty ?? false ? semanticsLabel! : label;
    return KeyedSubtree(
      key: key ?? const ValueKey<String>('uncertainty-badge'),
      child: Semantics(
        label: effectiveSemanticsLabel,
        excludeSemantics: true,
        child: CustomPaint(
          foregroundPainter: _DashedPillBorderPainter(
            color: theme.colorScheme.error,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Text(
                label,
                style: theme.textTheme.labelSmall,
                textAlign: TextAlign.center,
                softWrap: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the dashed rounded outline shared with the uncertain overlay.
///
/// The dash pattern is fixed (6 px dash, 4 px gap, 1.5 px stroke) and uses a
/// 3:1-contrast color supplied by the caller's theme, matching the T071A
/// uncertain outline so the two treatments read as one system.
class _DashedPillBorderPainter extends CustomPainter {
  _DashedPillBorderPainter({required this.color});

  final Color color;

  static const double _strokeWidth = 1.5;
  static const double _dashLength = 6;
  static const double _gapLength = 4;
  static const double _radius = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    final RRect rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(_radius),
    );
    final Path track = Path()..addRRect(rrect);
    final Path dashed = Path();
    for (final PathMetric metric in track.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double end = math.min(distance + _dashLength, metric.length);
        dashed.addPath(metric.extractPath(distance, end), Offset.zero);
        distance = end + _gapLength;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(_DashedPillBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
