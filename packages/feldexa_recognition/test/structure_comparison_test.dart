// T264 host-VM tests for the OCR-count-independent structure comparison.
// ignore_for_file: depend_on_referenced_packages

@TestOn('vm')
library;

import 'package:feldexa_recognition/src/field_inventory.dart';
import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/structure_comparison.dart';
import 'package:flutter_test/flutter_test.dart';

DisplayRect _rect(double x, double y, double width, double height) =>
    DisplayRect(x: x, y: y, width: width, height: height);

ExpectedField _expected(
  DisplayRect rect, {
  FieldInventoryKind kind = FieldInventoryKind.text,
  String? label,
  int page = 0,
}) {
  return ExpectedField(
    pageIndex: page,
    rect: rect,
    kind: kind,
    labelText: label,
  );
}

ObservedField _observed(
  DisplayRect rect, {
  FieldInventoryKind kind = FieldInventoryKind.text,
  String? label,
  int page = 0,
}) {
  return ObservedField(
    pageIndex: page,
    rect: rect,
    kind: kind,
    labelText: label,
  );
}

void main() {
  group('same count is not evidence', () {
    test('equal totals with displaced geometry fail', () {
      final StructureComparisonResult result = StructureComparison.compare(
        expected: <ExpectedField>[
          _expected(_rect(50, 50, 11, 11), kind: FieldInventoryKind.checkbox),
        ],
        observed: <ObservedField>[
          _observed(_rect(55, 50, 11, 11), kind: FieldInventoryKind.checkbox),
        ],
      );

      expect(result.expectedCount, result.observedCount);
      expect(result.verdict, StructureVerdict.fail);
      expect(result.failureCodes, contains('geometry_mismatch'));
      expect(result.geometryMismatchedMatches, hasLength(1));
      expect(result.sameCountWrongGeometry, isTrue);
      expect(result.missingExpected, isEmpty);
      expect(result.extraObserved, isEmpty);
    });

    test('equal totals with unrelated positions fail as missing and extra', () {
      final StructureComparisonResult result = StructureComparison.compare(
        expected: <ExpectedField>[
          _expected(_rect(50, 50, 100, 18)),
          _expected(_rect(50, 100, 100, 18)),
        ],
        observed: <ObservedField>[
          _observed(_rect(200, 200, 100, 18)),
          _observed(_rect(200, 240, 100, 18)),
        ],
      );

      expect(result.verdict, StructureVerdict.fail);
      expect(result.expectedCount, result.observedCount);
      expect(result.missingExpected, hasLength(2));
      expect(result.extraObserved, hasLength(2));
      expect(
        result.failureCodes,
        containsAll(<String>['missing_fields', 'extra_fields']),
      );
    });

    test('a correct page passes', () {
      final StructureComparisonResult result = StructureComparison.compare(
        expected: <ExpectedField>[
          _expected(_rect(50, 50, 100, 18), label: 'Name'),
          _expected(_rect(50, 100, 11, 11), kind: FieldInventoryKind.checkbox),
        ],
        observed: <ObservedField>[
          _observed(_rect(50, 50, 100, 18), label: 'Name'),
          _observed(_rect(50, 100, 11, 11), kind: FieldInventoryKind.checkbox),
        ],
      );

      expect(result.verdict, StructureVerdict.pass);
      expect(result.failureCodes, isEmpty);
      expect(result.matches, hasLength(2));
      expect(result.meanMatchedIou, 1.0);
      expect(result.sameCountWrongGeometry, isFalse);
    });
  });

  group('missing, duplicate, overlapping', () {
    test('a missing field is reported and fails', () {
      final StructureComparisonResult result = StructureComparison.compare(
        expected: <ExpectedField>[
          _expected(_rect(50, 50, 100, 18)),
          _expected(_rect(50, 90, 100, 18)),
        ],
        observed: <ObservedField>[_observed(_rect(50, 50, 100, 18))],
      );

      expect(result.verdict, StructureVerdict.fail);
      expect(result.missingExpected, <int>[1]);
      expect(result.failureCodes, contains('missing_fields'));
    });

    test('a duplicate checkbox is a duplicate, not an extra field', () {
      final StructureComparisonResult result = StructureComparison.compare(
        expected: <ExpectedField>[
          _expected(_rect(50, 50, 11, 11), kind: FieldInventoryKind.checkbox),
        ],
        observed: <ObservedField>[
          _observed(_rect(50, 50, 11, 11), kind: FieldInventoryKind.checkbox),
          _observed(_rect(50, 50, 11, 11), kind: FieldInventoryKind.checkbox),
        ],
      );

      expect(result.verdict, StructureVerdict.fail);
      expect(result.duplicates, hasLength(1));
      expect(result.duplicates.single.ofObservedIndex, 0);
      expect(result.extraObserved, isEmpty);
      expect(result.failureCodes, contains('duplicate_fields'));
    });

    test('overlapping observations are surfaced for review', () {
      final StructureComparisonResult result = StructureComparison.compare(
        expected: <ExpectedField>[_expected(_rect(50, 50, 20, 20))],
        observed: <ObservedField>[
          _observed(_rect(50, 50, 20, 20)),
          _observed(_rect(53, 53, 20, 20)),
        ],
      );

      expect(result.overlaps, hasLength(1));
      expect(result.failureCodes, contains('duplicate_fields'));
    });

    test('multiple adjacent fields are matched individually', () {
      final StructureComparisonResult result = StructureComparison.compare(
        expected: <ExpectedField>[
          for (int index = 0; index < 3; index++)
            _expected(
              _rect(50 + index * 13, 50, 11, 11),
              kind: FieldInventoryKind.checkbox,
            ),
        ],
        observed: <ObservedField>[
          for (int index = 0; index < 3; index++)
            _observed(
              _rect(50 + index * 13, 50, 11, 11),
              kind: FieldInventoryKind.checkbox,
            ),
        ],
      );

      expect(result.verdict, StructureVerdict.pass);
      expect(result.matches, hasLength(3));
      expect(
        result.matches.map((StructureMatch match) => match.expectedIndex),
        <int>[0, 1, 2],
      );
    });
  });

  group('types, labels, ambiguity', () {
    test('a wrong type fails without changing the count', () {
      final StructureComparisonResult result = StructureComparison.compare(
        expected: <ExpectedField>[
          _expected(_rect(50, 50, 11, 11), kind: FieldInventoryKind.checkbox),
        ],
        observed: <ObservedField>[
          _observed(_rect(50, 50, 11, 11), kind: FieldInventoryKind.text),
        ],
      );

      expect(result.verdict, StructureVerdict.fail);
      expect(result.typeMismatchedMatches, hasLength(1));
      expect(result.failureCodes, contains('type_mismatch'));
    });

    test('an unknown observation type is a strict type mismatch', () {
      final StructureComparisonResult result = StructureComparison.compare(
        expected: <ExpectedField>[
          _expected(_rect(50, 50, 11, 11), kind: FieldInventoryKind.checkbox),
        ],
        observed: <ObservedField>[
          _observed(_rect(50, 50, 11, 11), kind: FieldInventoryKind.unknown),
        ],
      );

      expect(result.verdict, StructureVerdict.fail);
      expect(result.failureCodes, contains('type_mismatch'));
    });

    test(
      'an unlabelled observation is reported and only fails when required',
      () {
        final List<ExpectedField> expected = <ExpectedField>[
          _expected(_rect(50, 50, 100, 18), label: 'Name'),
        ];
        final List<ObservedField> observed = <ObservedField>[
          _observed(_rect(50, 50, 100, 18)),
        ];

        final StructureComparisonResult tolerant = StructureComparison.compare(
          expected: expected,
          observed: observed,
        );
        expect(tolerant.verdict, StructureVerdict.pass);
        expect(tolerant.unlabelledObserved, <int>[0]);

        final StructureComparisonResult strict = StructureComparison.compare(
          expected: expected,
          observed: observed,
          config: const StructureComparisonConfig(requireLabels: true),
        );
        expect(strict.verdict, StructureVerdict.fail);
        expect(strict.failureCodes, contains('unlabelled_fields'));
      },
    );

    test('a differing label is a label mismatch, never a silent rename', () {
      final StructureComparisonResult result = StructureComparison.compare(
        expected: <ExpectedField>[
          _expected(_rect(50, 50, 100, 18), label: 'Straße'),
        ],
        observed: <ObservedField>[
          _observed(_rect(50, 50, 100, 18), label: 'Strasse'),
        ],
        config: const StructureComparisonConfig(requireLabels: true),
      );

      expect(result.verdict, StructureVerdict.fail);
      expect(result.labelMismatchedMatches, <int>[0]);
      expect(result.failureCodes, contains('label_mismatch'));
    });

    test('an observation between two ground-truth fields is ambiguous', () {
      final StructureComparisonResult result = StructureComparison.compare(
        expected: <ExpectedField>[
          _expected(_rect(50, 50, 100, 20)),
          _expected(_rect(50, 50, 100, 21)),
        ],
        observed: <ObservedField>[_observed(_rect(50, 50, 100, 20))],
      );

      expect(result.ambiguousObserved, <int>[0]);
      expect(result.failureCodes, contains('ambiguous_fields'));
    });
  });

  group('ground-truth honesty', () {
    test('a declared zero-field page passes when it stays empty', () {
      final StructureComparisonResult result = StructureComparison.compare(
        expected: const <ExpectedField>[],
        observed: const <ObservedField>[],
        groundTruthPages: <int>{0},
      );

      expect(result.verdict, StructureVerdict.pass);
      expect(result.failureCodes, isEmpty);
    });

    test('a declared zero-field page fails on an invented field', () {
      final StructureComparisonResult result = StructureComparison.compare(
        expected: const <ExpectedField>[],
        observed: <ObservedField>[_observed(_rect(50, 50, 100, 18))],
        groundTruthPages: <int>{0},
      );

      expect(result.verdict, StructureVerdict.fail);
      expect(result.failureCodes, contains('extra_fields'));
    });

    test('an empty ground truth cannot prove completeness', () {
      final StructureComparisonResult result = StructureComparison.compare(
        expected: const <ExpectedField>[],
        observed: <ObservedField>[_observed(_rect(50, 50, 100, 18))],
      );

      expect(result.verdict, StructureVerdict.unverified);
      expect(result.failureCodes, contains('unknown_expected_count'));
    });

    test('an observed page without ground truth is never a pass', () {
      final StructureComparisonResult result = StructureComparison.compare(
        expected: <ExpectedField>[_expected(_rect(50, 50, 100, 18))],
        observed: <ObservedField>[
          _observed(_rect(50, 50, 100, 18)),
          _observed(_rect(50, 50, 100, 18), page: 1),
        ],
      );

      expect(result.unknownGroundTruthPages, <int>[1]);
      expect(result.verdict, StructureVerdict.unverified);
    });

    test('buckets separate pages and kinds', () {
      final StructureComparisonResult result = StructureComparison.compare(
        expected: <ExpectedField>[
          _expected(_rect(50, 50, 100, 18)),
          _expected(
            _rect(50, 90, 11, 11),
            kind: FieldInventoryKind.checkbox,
            page: 1,
          ),
        ],
        observed: <ObservedField>[
          _observed(_rect(50, 50, 100, 18)),
          _observed(
            _rect(50, 90, 11, 11),
            kind: FieldInventoryKind.checkbox,
            page: 1,
          ),
        ],
      );

      expect(result.verdict, StructureVerdict.pass);
      expect(result.buckets, hasLength(2));
      expect(result.buckets.first.pageIndex, 0);
      expect(result.buckets.last.pageIndex, 1);
      expect(result.buckets.last.kind, FieldInventoryKind.checkbox);
    });

    test('equal input produces equal JSON', () {
      final List<ExpectedField> expected = <ExpectedField>[
        _expected(_rect(50, 50, 100, 18), label: 'Name'),
      ];
      final List<ObservedField> observed = <ObservedField>[
        _observed(_rect(50, 50, 100, 18), label: 'Name'),
      ];
      final StructureComparisonResult first = StructureComparison.compare(
        expected: expected,
        observed: observed,
      );
      final StructureComparisonResult second = StructureComparison.compare(
        expected: expected,
        observed: observed,
      );
      expect(first.toJson(), second.toJson());
    });
  });
}
