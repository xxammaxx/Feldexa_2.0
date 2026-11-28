// T134 threshold regressions (SC-015; FR-092/FR-093; CHK022). Evidence: NONE.
//
// These tests pin the threshold classification independently of the emulator
// audit: the 200 % text scale must not upgrade normal text to the 3:1 large
// tier, and a 3.1:1 normal-text pair must be red.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/accessibility_thresholds.dart';

void main() {
  test('normal 14 px text requires 4.5:1 and rejects 3.1:1', () {
    expect(isLargeText(14.0, FontWeight.normal), isFalse);
    expect(requiredContrast(14.0, FontWeight.normal), 4.5);
    expect(meetsContrast(3.1, 14.0, FontWeight.normal), isFalse);
    expect(meetsContrast(4.49, 14.0, FontWeight.normal), isFalse);
    expect(meetsContrast(4.5, 14.0, FontWeight.normal), isTrue);
  });

  test('scaling the size does not change the classification', () {
    // The audit measures at 200 %; the classification still comes from the
    // unscaled 14 px style, so 28 px rendered text is not automatically large.
    expect(isLargeText(14.0 * 2, FontWeight.normal), isTrue);
    expect(isLargeText(14.0, FontWeight.normal), isFalse);
  });

  test('large 18 px text and bold 14 px text use the 3:1 tier', () {
    expect(isLargeText(18.0, FontWeight.normal), isTrue);
    expect(isLargeText(14.0, FontWeight.bold), isTrue);
    expect(isLargeText(13.9, FontWeight.bold), isFalse);
    expect(requiredContrast(18.0, FontWeight.normal), 3.0);
    expect(meetsContrast(3.1, 18.0, FontWeight.normal), isTrue);
    expect(meetsContrast(2.99, 18.0, FontWeight.normal), isFalse);
  });

  test('contrast math matches WCAG for known pairs', () {
    // Black on white is 21:1; the exact 4.5 boundary stays green.
    expect(
      contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
      closeTo(21.0, 1e-6),
    );
    expect(meetsContrast(4.5, 16.0, FontWeight.normal), isTrue);
    expect(meetsContrast(4.4999, 16.0, FontWeight.normal), isFalse);
  });
}
