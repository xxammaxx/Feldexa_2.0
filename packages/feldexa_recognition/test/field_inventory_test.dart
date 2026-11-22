// T264 host-VM tests for the geometry-first field inventory.
// ignore_for_file: depend_on_referenced_packages

@TestOn('vm')
library;

import 'package:feldexa_recognition/src/field_inventory.dart';
import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/type_inference.dart';
import 'package:flutter_test/flutter_test.dart';

const double _pageWidth = 400;
const double _pageHeight = 300;

DisplayRect _rect(double x, double y, double width, double height) =>
    DisplayRect(x: x, y: y, width: width, height: height);

GeometryCandidate _candidate(
  DisplayRect rect,
  List<String> cues, {
  double ink = 0,
}) {
  return GeometryCandidate(rect: rect, cues: cues, inkCoverage: ink);
}

FieldInventory _build(
  List<GeometryCandidate> candidates, {
  List<LabelObservation> labels = const <LabelObservation>[],
  List<FieldTypeHint> hints = const <FieldTypeHint>[],
}) {
  return FieldInventoryBuilder.build(
    pageIndex: 0,
    pageWidthPt: _pageWidth,
    pageHeightPt: _pageHeight,
    candidates: candidates,
    labels: labels,
    typeHints: hints,
  );
}

void main() {
  group('checkbox candidates', () {
    test('a small empty square is an unconfirmed checkbox candidate', () {
      final FieldInventory inventory = _build(<GeometryCandidate>[
        _candidate(_rect(50, 50, 11, 11), <String>['small_square', 'box']),
      ]);

      expect(inventory.fieldCandidates, hasLength(1));
      final FieldInventoryEntry entry = inventory.fieldCandidates.single;
      expect(entry.kind, FieldInventoryKind.checkbox);
      expect(entry.role, InventoryRole.fieldCandidate);
      expect(entry.cues, <String>['box', 'small_square']);
      expect(entry.id, 'g_p0_0000');
    });

    test('a lightly marked box (14 % ink) is already filled', () {
      final FieldInventory inventory = _build(<GeometryCandidate>[
        _candidate(_rect(50, 50, 11, 11), <String>[
          'small_square',
          'box',
        ], ink: 0.14),
      ]);

      expect(inventory.fieldCandidates, isEmpty);
      expect(inventory.filledRegions, hasLength(1));
    });

    test('a marked box is a filled region, not an empty input', () {
      final FieldInventory inventory = _build(<GeometryCandidate>[
        _candidate(_rect(50, 50, 11, 11), <String>[
          'small_square',
          'box',
        ], ink: 0.42),
      ]);

      expect(inventory.fieldCandidates, isEmpty);
      expect(inventory.filledRegions, hasLength(1));
      expect(
        inventory.filledRegions.single.evidence,
        contains('already_filled'),
      );
      expect(inventory.coverage.filledRegions, 1);
    });

    test('a sub-4-pt interior is a glyph counter, not a checkbox', () {
      final FieldInventory inventory = _build(<GeometryCandidate>[
        _candidate(_rect(100, 100, 3, 3), <String>['whitespace']),
      ]);

      expect(inventory.entries, isEmpty);
      expect(
        inventory.exclusions.single.reason,
        InventoryExclusionReason.letterInterior,
      );
      expect(inventory.coverage.letterInteriorRejections, 1);
    });
  });

  group('page furniture', () {
    test('a print-margin band region is excluded', () {
      final FieldInventory inventory = _build(<GeometryCandidate>[
        _candidate(_rect(2, 2, 12, 12), <String>['whitespace']),
      ]);

      expect(inventory.entries, isEmpty);
      expect(
        inventory.exclusions.single.reason,
        InventoryExclusionReason.printMargin,
      );
      expect(inventory.coverage.printMarginRejections, 1);
    });

    test('a page-spanning frame is a decorative frame', () {
      final FieldInventory inventory = _build(<GeometryCandidate>[
        _candidate(_rect(10, 10, 380, 280), <String>['box']),
      ]);

      expect(inventory.entries, isEmpty);
      expect(
        inventory.exclusions.single.reason,
        InventoryExclusionReason.decorativeFrame,
      );
    });

    test('an empty table cell is a table field and the top row is flagged', () {
      final FieldInventory inventory = _build(<GeometryCandidate>[
        _candidate(_rect(60, 100, 80, 20), <String>['grid_cell', 'table_cell']),
        _candidate(_rect(140, 100, 80, 20), <String>[
          'grid_cell',
          'table_cell',
        ]),
        _candidate(_rect(60, 130, 80, 20), <String>['grid_cell', 'table_cell']),
      ]);

      expect(inventory.fieldCandidates, hasLength(3));
      expect(
        inventory.fieldCandidates
            .where(
              (FieldInventoryEntry entry) =>
                  entry.kind == FieldInventoryKind.tableField,
            )
            .length,
        3,
      );
      expect(inventory.coverage.tableHeaderRowCells, 2);
    });
  });

  group('input kinds', () {
    test('an underline band is a single-line text candidate', () {
      final FieldInventory inventory = _build(<GeometryCandidate>[
        _candidate(_rect(40, 80, 120, 18), <String>['underline']),
      ]);

      expect(inventory.fieldCandidates.single.kind, FieldInventoryKind.text);
      expect(
        inventory.fieldCandidates.single.evidence,
        contains('underline_cue'),
      );
    });

    test('a tall bounded region is multiline', () {
      final FieldInventory inventory = _build(<GeometryCandidate>[
        _candidate(_rect(40, 80, 120, 18), <String>['underline']),
        _candidate(_rect(40, 140, 120, 80), <String>['box', 'whitespace']),
      ]);

      final List<FieldInventoryKind> kinds = <FieldInventoryKind>[
        for (final FieldInventoryEntry entry in inventory.fieldCandidates)
          entry.kind,
      ];
      expect(kinds, contains(FieldInventoryKind.multiline));
    });

    test('signature and date cues set the kind', () {
      final FieldInventory inventory = _build(<GeometryCandidate>[
        _candidate(_rect(40, 60, 200, 60), <String>['signature_area', 'box']),
        _candidate(_rect(40, 160, 100, 18), <String>[
          'underline',
          'date_context',
        ]),
      ]);

      expect(
        inventory.fieldCandidates.map(
          (FieldInventoryEntry entry) => entry.kind,
        ),
        containsAll(<FieldInventoryKind>[
          FieldInventoryKind.signature,
          FieldInventoryKind.date,
        ]),
      );
    });

    test('a pipeline type hint exposes a numeric field', () {
      final DisplayRect rect = _rect(40, 80, 120, 18);
      final FieldInventory inventory = _build(
        <GeometryCandidate>[
          _candidate(rect, <String>['underline']),
        ],
        hints: <FieldTypeHint>[
          FieldTypeHint(rect: rect, proposedType: 'number'),
        ],
      );

      final FieldInventoryEntry entry = inventory.fieldCandidates.single;
      expect(entry.kind, FieldInventoryKind.number);
      expect(entry.evidence, contains('type_hint_number'));
      expect(
        fieldInventoryKindForSuggestionType('number'),
        FieldInventoryKind.number,
      );
      expect(fieldInventoryKindForSuggestionType('nonsense'), isNull);
    });

    test('a contradicting hint never overrides a geometric checkbox', () {
      final DisplayRect rect = _rect(50, 50, 11, 11);
      final FieldInventory inventory = _build(
        <GeometryCandidate>[
          _candidate(rect, <String>['small_square', 'box']),
        ],
        hints: <FieldTypeHint>[FieldTypeHint(rect: rect, proposedType: 'text')],
      );

      final FieldInventoryEntry entry = inventory.fieldCandidates.single;
      expect(entry.kind, FieldInventoryKind.checkbox);
      expect(entry.reviewFlags, contains(InventoryReviewFlag.ambiguousKind));
      expect(entry.evidence, contains('type_hint_conflict_text'));
    });
  });

  group('deduplication and relations', () {
    test('a near-identical inset is collapsed with the union of its cues', () {
      final FieldInventory inventory = _build(<GeometryCandidate>[
        _candidate(_rect(50, 50, 100, 30), <String>['box']),
        _candidate(_rect(50.25, 50.25, 99.75, 29.75), <String>['whitespace']),
      ]);

      expect(inventory.entries, hasLength(1));
      expect(inventory.coverage.deduplicatedCount, 1);
      expect(inventory.entries.single.cues, <String>['box', 'whitespace']);
      expect(
        inventory.exclusions.single.reason,
        InventoryExclusionReason.duplicateGeometry,
      );
    });

    test('adjacent boxes stay separate and are reported as adjacent', () {
      final FieldInventory inventory = _build(<GeometryCandidate>[
        _candidate(_rect(50, 50, 11, 11), <String>['small_square', 'box']),
        _candidate(_rect(62, 50, 11, 11), <String>['small_square', 'box']),
      ]);

      expect(inventory.fieldCandidates, hasLength(2));
      expect(
        inventory.relations.map(
          (FieldInventoryRelation relation) => relation.kind,
        ),
        contains(InventoryRelationKind.adjacent),
      );
      expect(inventory.coverage.adjacentPairs, 1);
    });

    test('overlapping candidates are both retained and reported', () {
      final FieldInventory inventory = _build(<GeometryCandidate>[
        _candidate(_rect(50, 50, 20, 20), <String>['whitespace']),
        _candidate(_rect(53, 53, 20, 20), <String>['whitespace']),
      ]);

      expect(inventory.fieldCandidates, hasLength(2));
      expect(inventory.coverage.overlappingPairs, 1);
      for (final FieldInventoryEntry entry in inventory.fieldCandidates) {
        expect(
          entry.reviewFlags,
          contains(InventoryReviewFlag.overlappingCandidates),
        );
      }
    });

    test('a nested candidate is a relation, never a silent drop', () {
      final FieldInventory inventory = _build(<GeometryCandidate>[
        _candidate(_rect(50, 50, 100, 60), <String>['box']),
        _candidate(_rect(60, 60, 60, 30), <String>['whitespace']),
      ]);

      expect(inventory.fieldCandidates, hasLength(2));
      expect(inventory.coverage.nestedPairs, 1);
    });
  });

  group('label context and determinism', () {
    test(
      'nearest credible label becomes label context without changing kind',
      () {
        final DisplayRect rect = _rect(100, 100, 120, 18);
        final FieldInventory inventory = _build(
          <GeometryCandidate>[
            _candidate(rect, <String>['underline']),
          ],
          labels: <LabelObservation>[
            LabelObservation(
              text: '  Straße  ',
              rect: _rect(20, 100, 60, 18),
              ocrConfidence: 0.9,
            ),
          ],
        );

        final FieldInventoryEntry entry = inventory.fieldCandidates.single;
        expect(entry.kind, FieldInventoryKind.text);
        expect(entry.labelText, 'Straße');
        expect(entry.reviewFlags, isEmpty);
      },
    );

    test('a low-confidence label is not label context', () {
      final DisplayRect rect = _rect(100, 100, 120, 18);
      final FieldInventory inventory = _build(
        <GeometryCandidate>[
          _candidate(rect, <String>['underline']),
        ],
        labels: <LabelObservation>[
          LabelObservation(
            text: 'Name',
            rect: _rect(20, 100, 60, 18),
            ocrConfidence: 0.4,
          ),
        ],
      );

      expect(inventory.fieldCandidates.single.labelText, isNull);
      expect(
        inventory.fieldCandidates.single.reviewFlags,
        contains(InventoryReviewFlag.noLabelContext),
      );
      expect(inventory.coverage.unlabelledFieldCandidates, 1);
    });

    test('equal input produces an equal inventory', () {
      final List<GeometryCandidate> candidates = <GeometryCandidate>[
        _candidate(_rect(50, 50, 11, 11), <String>['small_square', 'box']),
        _candidate(_rect(50, 120, 120, 18), <String>['underline']),
      ];
      final FieldInventory first = _build(candidates);
      final FieldInventory second = _build(candidates);
      expect(first.toJson(), second.toJson());
    });

    test('an out-of-page candidate is rejected before any analysis', () {
      expect(
        () => _build(<GeometryCandidate>[
          _candidate(_rect(390, 290, 40, 40), <String>['box']),
        ]),
        throwsArgumentError,
      );
    });
  });
}
