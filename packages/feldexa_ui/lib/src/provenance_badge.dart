// T074 provenance badges for review mode (FR-028/FR-094;
// `contracts/editor-interactions.md` §3 and §11;
// `data-model.md` §2.4, §3.4, and §3.5).
//
// Presentation only: the caller supplies the already-localized label, so this
// package contains no user-facing German copy and the app ARB remains the
// single source. The four provenances are distinguished by color *and* an
// icon *and* readable text; color is never the only signal (FR-094).

import 'package:flutter/material.dart';

/// The provenance states rendered by [ProvenanceBadge].
///
/// The values mirror the review treatment in
/// `contracts/editor-interactions.md` §3: a machine suggestion, a confirmed
/// machine field, a user-created field, and a field inherited from a pinned
/// template version.
enum ProvenanceBadgeKind {
  /// An unresolved recognition candidate.
  suggestion,

  /// A field confirmed from a machine suggestion.
  confirmed,

  /// A field created manually by the user.
  userCreated,

  /// A layout-only field inherited from a pinned template version.
  template,
}

/// The fixed palette and shape/icon pairing for each [ProvenanceBadgeKind].
extension ProvenanceBadgeKindVisuals on ProvenanceBadgeKind {
  /// The outline, icon, and text color for this provenance.
  ///
  /// Every color clears the WCAG 4.5:1 normal-text floor against white; the
  /// outline separately clears the 3:1 non-text floor. The badge always pairs
  /// the color with [icon] and readable text, so the provenance is never
  /// conveyed by color alone (FR-094).
  Color get color => switch (this) {
    ProvenanceBadgeKind.suggestion => const Color(0xFF1565C0), // blue 800
    ProvenanceBadgeKind.confirmed => const Color(0xFF2E7D32), // green 800
    // Deep orange 900: 5.60:1 on white, so 11–12 px text also clears 4.5:1.
    ProvenanceBadgeKind.userCreated => const Color(0xFFBF360C),
    ProvenanceBadgeKind.template => const Color(0xFF7B1FA2), // purple 700
  };

  /// The shape/icon paired with [color].
  ///
  /// The icon is part of the provenance signal and is never omitted, even when
  /// the badge is [ProvenanceBadge.compact].
  IconData get icon => switch (this) {
    ProvenanceBadgeKind.suggestion => Icons.auto_awesome,
    ProvenanceBadgeKind.confirmed => Icons.verified,
    ProvenanceBadgeKind.userCreated => Icons.edit,
    ProvenanceBadgeKind.template => Icons.dashboard_customize,
  };
}

/// A non-interactive provenance pill for review surfaces.
///
/// The badge renders a solid 1.5 px outline, an icon, and caller-supplied
/// [text]. This solid pill is the T074 provenance treatment; the
/// confidence-based dashed outline lives in `field_overlay.dart` and encodes
/// confidence, not provenance. The caller passes the localized label (for
/// example from the app ARB); this package deliberately has no built-in label.
/// Because the badge is non-interactive, it does not reserve a 48 × 48 dp touch
/// target. The [compact] variant may be used inline in dense rows or lists.
///
/// One semantic node exposes `semanticsLabel ?? text`; a null or
/// whitespace-only [semanticsLabel] falls back to [text], so the node never
/// carries an empty label. The visual icon and text are excluded from
/// semantics so assistive technology does not announce the same provenance
/// twice.
///
/// When [key] is omitted, the badge uses the stable default
/// `ValueKey('provenance-badge-<kind>')`. Callers that render more than one
/// badge of the same kind in one subtree must supply distinct keys, because
/// sibling widgets cannot share a key.
class ProvenanceBadge extends StatelessWidget {
  /// Creates a provenance badge.
  ///
  /// Leading and trailing whitespace is removed from [text]. Throws an
  /// [ArgumentError] when [text] is empty or contains only whitespace. The
  /// error message never echoes the supplied text.
  ProvenanceBadge({
    required this.kind,
    required String text,
    String? semanticsLabel,
    this.compact = false,
    Key? key,
  }) : text = _requireNonEmptyText(text),
       semanticsLabel = _normalizeSemanticsLabel(semanticsLabel),
       super(key: key ?? ValueKey<String>('provenance-badge-${kind.name}'));

  /// The provenance rendered by this badge.
  final ProvenanceBadgeKind kind;

  /// The caller-supplied, already-localized visible label, trimmed.
  final String text;

  /// An optional screen-reader label; null or blank falls back to [text].
  final String? semanticsLabel;

  /// Whether to use the smaller inline padding and typography.
  ///
  /// Compact badges remain non-interactive; they may be placed inline where a
  /// full-size badge would consume too much space.
  final bool compact;

  /// The solid outline width in logical pixels.
  static const double outlineWidth = 1.5;

  /// The pill radius; larger than any expected badge height.
  static const BorderRadius borderRadius = BorderRadius.all(
    Radius.circular(999),
  );

  /// The opaque fill used to keep contrast independent of the parent surface.
  static const Color backgroundColor = Color(0xFFFFFFFF);

  /// Padding for the default size.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 6,
  );

  /// Smaller padding for [compact].
  static const EdgeInsets compactPadding = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 3,
  );

  /// Icon size for the default size.
  static const double iconSize = 16;

  /// Smaller icon size for [compact].
  static const double compactIconSize = 14;

  /// Gap between the icon and the text for the default size.
  static const double iconSpacing = 6;

  /// Smaller icon-to-text gap for [compact].
  static const double compactIconSpacing = 4;

  /// Visible text size for the default size, before platform text scaling.
  static const double fontSize = 12;

  /// Smaller visible text size for [compact], before platform text scaling.
  static const double compactFontSize = 11;

  @override
  Widget build(BuildContext context) {
    final Color provenanceColor = kind.color;
    final TextStyle baseStyle =
        (compact
            ? Theme.of(context).textTheme.labelSmall
            : Theme.of(context).textTheme.labelMedium) ??
        const TextStyle();

    return Semantics(
      container: true,
      label: semanticsLabel ?? text,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            border: Border.all(color: provenanceColor, width: outlineWidth),
            borderRadius: borderRadius,
          ),
          child: Padding(
            padding: compact ? compactPadding : padding,
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: compact ? compactIconSpacing : iconSpacing,
              runSpacing: 2,
              children: <Widget>[
                Icon(
                  kind.icon,
                  color: provenanceColor,
                  size: compact ? compactIconSize : iconSize,
                ),
                Text(
                  text,
                  style: baseStyle.copyWith(
                    color: provenanceColor,
                    fontSize: compact ? compactFontSize : fontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _requireNonEmptyText(String text) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError(
      'ProvenanceBadge.text must not be empty or whitespace only.',
    );
  }
  return trimmed;
}

String? _normalizeSemanticsLabel(String? semanticsLabel) {
  final String? trimmed = semanticsLabel?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
