// Host-VM tests for the value-fit admission rule (issue #340).
//
// The rule is a pure function of one candidate rect and one proposed type, so
// the tests pin the contract-derived boundaries instead of a fixture:
// `contracts/export-plan.md` §2.2 (minimum font size 7.0 pt, baseline
// `1.5 + 0.8 × fontSizePt`, `baselineFromTopPt ≤ rect.height`), §3.1 (1.5 pt
// padding per side) and `contracts/coordinates-and-geometry.md` §3 (model
// minimum 4 pt × 4 pt).
//
// Evidence class: NONE. Host-VM unit tests; no Android, device, or screen claim.

@TestOn('vm')
library;

import 'package:feldexa_recognition/src/fillable_geometry.dart';
import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/suggestion_schema.dart';
import 'package:flutter_test/flutter_test.dart';

DisplayRect _rect({required double width, required double height}) {
  return DisplayRect(x: 100, y: 100, width: width, height: height);
}

bool _admits(String type, {required double width, required double height}) {
  return admitsValueOfType(
    rect: _rect(width: width, height: height),
    proposedType: type,
  );
}

void main() {
  group('text-bearing types', () {
    for (final String type in <String>['text', 'number', 'date', 'multiline']) {
      test('$type needs the 7.1 pt baseline height', () {
        // 1.5 + 0.8 × 7.0 = 7.1: the first baseline of the smallest contract
        // font starts 7.1 pt below the rect top, so a shorter rect can never
        // render one line at any font size.
        expect(_admits(type, width: 300, height: 7.1), isTrue);
        expect(_admits(type, width: 300, height: 7.0), isFalse);
      });

      test('$type needs a positive available width', () {
        // §3.1 pads 1.5 pt per side: availableWidth = width − 3.0.
        expect(_admits(type, width: 3.125, height: 18), isTrue);
        expect(_admits(type, width: 3.0, height: 18), isFalse);
      });
    }

    test('the reported #340 rect is rejected on both counts', () {
      // The first suggestion of sf-001 measured on the 200 DPI page raster:
      // x 114.5, y 33.875, 2.875 x 3.875 pt inside the printed label.
      expect(_admits('text', width: 2.875, height: 3.875), isFalse);
    });

    test('a real 300 x 18 pt fixture field is admitted', () {
      expect(_admits('text', width: 300, height: 18), isTrue);
    });
  });

  group('checkbox', () {
    test('needs the 4 pt small-square floor on the shorter side', () {
      expect(_admits('checkbox', width: 9.375, height: 9.375), isTrue);
      expect(_admits('checkbox', width: 4.0, height: 18), isTrue);
      expect(_admits('checkbox', width: 3.875, height: 18), isFalse);
      expect(_admits('checkbox', width: 2.875, height: 3.875), isFalse);
    });
  });

  group('signature', () {
    test('stays admitted by the filter although the export has a floor', () {
      // The filter keeps every rect (default branch). The *export* floor is
      // derived elsewhere: export-plan §3.3 pads 1.0 pt per side and blocks
      // `signature_too_small` when min(width, height) ≤ 2.0 pt (`layout.dart`,
      // `exportSignaturePaddingPt`), so a 1 x 1 signature proposal would fail
      // at export time. Enforcing that floor here is a documented residual of
      // this rule, not a decided contract minimum of the filter.
      expect(_admits('signature', width: 1, height: 1), isTrue);
    });
  });

  group('schema coverage', () {
    test('every proposed type except signature has its own bound', () {
      // The filter branches on the type tokens. A renamed or newly added token
      // in `SuggestionSchema.proposedTypes` would fall into `default: true`
      // silently and the filter would stop guarding it; this pin holds the
      // coupling, so a rename turns this test red.
      final List<String> admittedAt1x1 = SuggestionSchema.proposedTypes
          .where((String type) => _admits(type, width: 1, height: 1))
          .toList();
      expect(admittedAt1x1, <String>['signature']);
    });

    test('a type outside the schema list is admitted on purpose', () {
      // "a new type is never silently dropped by this rule": an unknown type
      // takes the default branch and stays visible to the user.
      expect(_admits('future_type', width: 1, height: 1), isTrue);
    });
  });

  test('the derived constants are the contract numbers', () {
    expect(minimumValueHeightPt, closeTo(1.5 + 0.8 * 7.0, 1e-12));
    expect(minimumValueWidthPt, 2 * 1.5);
    expect(minCheckboxSidePt, 4);
  });
}
