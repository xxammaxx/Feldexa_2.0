// Shared T134 contrast thresholds (SC-015; FR-092/FR-093; CHK022).
//
// The large-text classification is a property of the text style, not of the
// user's text-scale factor: WCAG large text is >= 18 pt, or >= 14 pt bold.
// Flutter logical pixels are treated as CSS pixels here, which is the
// documented `contracts/editor-interactions.md` unit. Scaling the size first
// would classify every 200 % run as large and make the 4.5:1 normal-text
// threshold unreachable.

import 'package:flutter/painting.dart';

/// Normal-text contrast minimum (WCAG AA).
const double minContrastNormal = 4.5;

/// Large-text contrast minimum (WCAG AA).
const double minContrastLarge = 3.0;

/// Large-text threshold in unscaled logical pixels.
const double largeTextMinimumPx = 18.0;

/// Bold large-text threshold in unscaled logical pixels.
const double largeBoldTextMinimumPx = 14.0;

/// Whether [fontSize] (unscaled) at [weight] is WCAG large text.
bool isLargeText(double fontSize, FontWeight weight) {
  final bool bold = weight.value >= FontWeight.w600.value;
  return fontSize >= largeTextMinimumPx ||
      (bold && fontSize >= largeBoldTextMinimumPx);
}

/// The contrast ratio required for the given unscaled text style.
double requiredContrast(double fontSize, FontWeight weight) {
  return isLargeText(fontSize, weight) ? minContrastLarge : minContrastNormal;
}

/// WCAG contrast ratio for two opaque colors.
double contrastRatio(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double lighter = la > lb ? la : lb;
  final double darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Whether [ratio] meets the requirement of [fontSize]/[weight].
///
/// A 1e-9 tolerance keeps exact-threshold values (4.5:1) green after double
/// composition.
bool meetsContrast(double ratio, double fontSize, FontWeight weight) {
  return ratio + 1e-9 >= requiredContrast(fontSize, weight);
}
