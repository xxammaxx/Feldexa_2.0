// T055 host-VM tests for overlap and conflict handling.
//
// Normative sources:
//  * specs/001-scanned-form-workflow/contracts/recognition-output.md
//    section 2 (`conflictsWith`), section 5.2/5.4 (deterministic ordering and
//    1/8 pt rounding), and section 6 (overlap and conflict handling);
//  * specs/001-scanned-form-workflow/spec.md FR-025.
//
// The module is pure and deterministic: these tests assert the inclusive
// IoU 0.5 and centre-containment/4 pt boundaries on rounded geometry, exact
// 1/8 pt rounding, symmetric graph output, retention and input immutability,
// sorted unique id lists, exact-duplicate collapse, content-free validation,
// and input-order independence. No test writes a file or mutates an input.
@TestOn('vm')
library;

import 'package:feldexa_recognition/src/conflicts.dart';
import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:flutter_test/flutter_test.dart';

DisplayRect _rect(double x, double y, double width, double height) {
  return DisplayRect(x: x, y: y, width: width, height: height);
}

ConflictItem _item(
  String id,
  DisplayRect rect, {
  String type = 'text',
  int detectorPass = 0,
}) {
  return ConflictItem(
    id: id,
    rect: rect,
    type: type,
    detectorPass: detectorPass,
  );
}

/// Stable, content-free rendering of one graph for order comparisons.
String _snapshot(ConflictGraph graph) {
  final String entries = graph.conflictsWith.entries
      .map((MapEntry<String, List<String>> entry) {
        return '${entry.key}:${entry.value.join(',')}';
      })
      .join(';');
  final String pairs = graph.pairs
      .map((ConflictPair pair) => '${pair.first}>${pair.second}')
      .join(',');
  return '[$entries]#[$pairs]';
}

String _representatives(DuplicateCollapseResult result) {
  return result.representatives.map((ConflictItem item) => item.id).join(',');
}

void main() {
  group('T055 conflict predicate', () {
    test('IoU of exactly 0.5 conflicts', () {
      final DisplayRect a = _rect(0, 0, 10, 10);
      // The wider b puts the centre distance at 5 pt, so only IoU can
      // explain the conflict.
      final DisplayRect b = _rect(0, 0, 20, 10);

      expect(ConflictDetector.iou(a, b), 0.5);
      expect(ConflictDetector.iou(b, a), 0.5);
      expect(ConflictDetector.conflicts(a, b), isTrue);
      expect(ConflictDetector.conflicts(b, a), isTrue);
    });

    test('IoU just below 0.5 does not conflict', () {
      final DisplayRect a = _rect(0, 0, 10, 10);
      final DisplayRect b = _rect(0.125, 0, 20, 10);

      // The 1/8 pt shift is the smallest possible below the inclusive
      // boundary; the centre distance is 5.125 pt, so the centre rule is out.
      expect(ConflictDetector.iou(a, b), lessThan(0.5));
      expect(ConflictDetector.iou(a, b), greaterThan(0.49));
      expect(ConflictDetector.conflicts(a, b), isFalse);
      expect(ConflictDetector.conflicts(b, a), isFalse);
    });

    test('IoU is 0 for disjoint rects and 1 for identical rects', () {
      final DisplayRect a = _rect(0, 0, 10, 10);
      final DisplayRect disjoint = _rect(20, 0, 10, 10);
      final DisplayRect identical = _rect(0, 0, 10, 10);

      expect(ConflictDetector.iou(a, disjoint), 0.0);
      expect(ConflictDetector.iou(a, identical), 1.0);
      expect(ConflictDetector.conflicts(a, disjoint), isFalse);
      expect(ConflictDetector.conflicts(a, identical), isTrue);
    });

    test('1/8 pt rounding keeps near-threshold float noise stable', () {
      final DisplayRect a = _rect(0, 0, 10, 10);

      // 0.0624999999 * 8 rounds to 0 eighths, so IoU is exactly 0.5.
      expect(
        ConflictDetector.conflicts(a, _rect(0.0624999999, 0, 20, 10)),
        isTrue,
      );
      // 0.0625000001 * 8 rounds to 1 eighth, so IoU falls below 0.5.
      expect(
        ConflictDetector.conflicts(a, _rect(0.0625000001, 0, 20, 10)),
        isFalse,
      );
    });

    test('rounding ties are taken away from zero', () {
      final DisplayRect a = _rect(0, 0, 10, 10);

      // 0.0625 * 8 is exactly 0.5; ties away from zero give 1 eighth and no
      // conflict. Ties-to-even would give 0 eighths and a 0.5 IoU conflict.
      expect(ConflictDetector.conflicts(a, _rect(0.0625, 0, 20, 10)), isFalse);
      // 4.8125 * 8 is exactly 38.5; ties away from zero give 39 eighths.
      // Ties-to-even would give 38 eighths and IoU 0.475 instead.
      expect(ConflictDetector.iou(a, _rect(0, 0, 10, 4.8125)), 0.4875);
    });

    test('the centre rule conflicts at exactly 4 pt', () {
      final DisplayRect a = _rect(0, 0, 20, 20);
      final DisplayRect b = _rect(13.5, 9.5, 1, 1);

      // Centres are (10, 10) and (14, 10): distance exactly 4 pt. The IoU is
      // 0.0025, so only the centre rule can explain the conflict.
      expect(ConflictDetector.iou(a, b), 0.0025);
      expect(ConflictDetector.conflicts(a, b), isTrue);
      expect(ConflictDetector.conflicts(b, a), isTrue);
    });

    test('the centre rule does not conflict just above 4 pt', () {
      final DisplayRect a = _rect(0, 0, 20, 20);
      final DisplayRect b = _rect(13.625, 9.5, 1, 1);

      // Centres are (10, 10) and (14.125, 10): distance 4.125 pt.
      expect(ConflictDetector.conflicts(a, b), isFalse);
      expect(ConflictDetector.conflicts(b, a), isFalse);
    });

    test('centre containment is inclusive at the rect edge', () {
      final DisplayRect a = _rect(12, 0, 8, 20);
      final DisplayRect b = _rect(19.5, 9.5, 1, 1);

      // b's centre is (20, 10), exactly on a's right edge; a's centre is
      // (16, 10), so the centre distance is exactly 4 pt.
      expect(ConflictDetector.iou(a, b), lessThan(0.5));
      expect(ConflictDetector.conflicts(a, b), isTrue);
      expect(ConflictDetector.conflicts(b, a), isTrue);
    });

    test('centre distance uses rounded geometry for near-threshold noise', () {
      final DisplayRect a = _rect(0, 0, 20, 20);
      final DisplayRect noisy = _rect(13.5000000001, 9.5, 1, 1);

      // 13.5000000001 * 8 rounds to 108 eighths, so the centre is exactly
      // 14 pt and the distance is exactly 4 pt.
      expect(ConflictDetector.conflicts(a, noisy), isTrue);
    });
  });

  group('T055 symmetric graph and retention', () {
    test('conflicts are symmetric and recorded in both directions', () {
      final ConflictItem a = _item('a', _rect(0, 0, 10, 10));
      final ConflictItem b = _item('b', _rect(0, 0, 10, 5));
      // c's centre is 2.375 pt above b's centre and 4.875 pt above a's:
      // b-c conflicts through the centre rule, a-c does not.
      final ConflictItem c = _item('c', _rect(4.5, 0, 1, 0.2));

      final ConflictGraph graph = ConflictDetector.detect(<ConflictItem>[
        a,
        b,
        c,
      ]);

      expect(graph.conflictsWith['a'], <String>['b']);
      expect(graph.conflictsWith['b'], <String>['a', 'c']);
      expect(graph.conflictsWith['c'], <String>['b']);
      expect(
        graph.pairs
            .map((ConflictPair pair) => '${pair.first}>${pair.second}')
            .toList(),
        <String>['a>b', 'b>c'],
      );
    });

    test('each item has a sorted, unique conflict list', () {
      final DisplayRect same = _rect(0, 0, 10, 10);
      final ConflictItem a = _item('a', same);
      final ConflictItem b = _item('b', same);
      final ConflictItem c = _item('c', same);

      final ConflictGraph graph = ConflictDetector.detect(<ConflictItem>[
        c,
        a,
        b,
      ]);

      expect(graph.conflictsWith.keys.toList(), <String>['a', 'b', 'c']);
      expect(graph.conflictsWith['a'], <String>['b', 'c']);
      expect(graph.conflictsWith['b'], <String>['a', 'c']);
      expect(graph.conflictsWith['c'], <String>['a', 'b']);
      expect(graph.pairs.length, 3);
      expect(
        graph.pairs
            .map((ConflictPair pair) => '${pair.first}>${pair.second}')
            .toList(),
        <String>['a>b', 'a>c', 'b>c'],
      );
    });

    test('no item is removed, merged, or re-ranked', () {
      final DisplayRect same = _rect(0, 0, 10, 10);
      final List<ConflictItem> items = <ConflictItem>[
        _item('c', same),
        _item('a', same),
        _item('b', same),
      ];

      final ConflictGraph graph = ConflictDetector.detect(items);

      expect(items.length, 3);
      expect(graph.conflictsWith.length, 3);
      expect(graph.conflictsWith.containsKey('a'), isTrue);
      expect(graph.conflictsWith.containsKey('b'), isTrue);
      expect(graph.conflictsWith.containsKey('c'), isTrue);
      // Three pairwise conflicts, not one merged representative.
      expect(graph.pairs.length, 3);
    });

    test('the input list and the returned graph are immutable', () {
      final DisplayRect same = _rect(0, 0, 10, 10);
      final ConflictItem a = _item('a', same);
      final ConflictItem b = _item('b', same);
      final List<ConflictItem> items = <ConflictItem>[a, b];
      final List<ConflictItem> before = List<ConflictItem>.of(items);

      final ConflictGraph graph = ConflictDetector.detect(items);

      expect(items, before);
      expect(identical(items[0], a), isTrue);
      expect(identical(items[1], b), isTrue);
      expect(() => graph.conflictsWith['a']!.add('x'), throwsUnsupportedError);
      expect(
        () => graph.conflictsWith['x'] = <String>[],
        throwsUnsupportedError,
      );
      expect(() => graph.pairs.clear(), throwsUnsupportedError);
    });

    test('empty and single-item inputs produce a complete empty graph', () {
      final ConflictGraph empty = ConflictDetector.detect(<ConflictItem>[]);
      expect(empty.conflictsWith, isEmpty);
      expect(empty.pairs, isEmpty);

      final ConflictGraph single = ConflictDetector.detect(<ConflictItem>[
        _item('only', _rect(0, 0, 10, 10)),
      ]);
      expect(single.conflictsWith.keys.toList(), <String>['only']);
      expect(single.conflictsWith['only'], isEmpty);
      expect(single.pairs, isEmpty);
    });
  });

  group('T055 deterministic duplicate collapse', () {
    test('same type and pass above IoU 0.98 collapses to the lowest id', () {
      final ConflictItem a = _item('a', _rect(0, 0, 10, 10));
      final ConflictItem b = _item('b', _rect(0, 0, 10, 10.125));

      expect(ConflictDetector.iou(a.rect, b.rect), greaterThan(0.98));
      expect(ExactDuplicateCollapser.areExactDuplicates(a, b), isTrue);
      expect(ExactDuplicateCollapser.areExactDuplicates(b, a), isTrue);

      final DuplicateCollapseResult result = ExactDuplicateCollapser.collapse(
        <ConflictItem>[b, a],
      );
      expect(_representatives(result), 'a');
      expect(result.representatives.length, 1);
      expect(result.collapsedCount, 1);
    });

    test('a duplicate at or below IoU 0.98 is retained', () {
      final ConflictItem a = _item('a', _rect(0, 0, 10, 10));
      final ConflictItem b = _item('b', _rect(0, 0, 10, 9.75));

      expect(ConflictDetector.iou(a.rect, b.rect), lessThanOrEqualTo(0.98));
      expect(ExactDuplicateCollapser.areExactDuplicates(a, b), isFalse);

      final DuplicateCollapseResult result = ExactDuplicateCollapser.collapse(
        <ConflictItem>[a, b],
      );
      expect(_representatives(result), 'a,b');
      expect(result.collapsedCount, 0);
    });

    test('duplicates never collapse across types', () {
      final ConflictItem text = _item('a', _rect(0, 0, 10, 10), type: 'text');
      final ConflictItem number = _item(
        'b',
        _rect(0, 0, 10, 10.125),
        type: 'number',
      );

      expect(ExactDuplicateCollapser.areExactDuplicates(text, number), isFalse);
      final DuplicateCollapseResult result = ExactDuplicateCollapser.collapse(
        <ConflictItem>[text, number],
      );
      expect(result.collapsedCount, 0);
      expect(result.representatives.length, 2);
    });

    test('duplicates never collapse across detector passes', () {
      final ConflictItem firstPass = _item(
        'a',
        _rect(0, 0, 10, 10),
        detectorPass: 0,
      );
      final ConflictItem secondPass = _item(
        'b',
        _rect(0, 0, 10, 10.125),
        detectorPass: 1,
      );

      expect(
        ExactDuplicateCollapser.areExactDuplicates(firstPass, secondPass),
        isFalse,
      );
      final DuplicateCollapseResult result = ExactDuplicateCollapser.collapse(
        <ConflictItem>[firstPass, secondPass],
      );
      expect(result.collapsedCount, 0);
      expect(result.representatives.length, 2);
    });

    test('the representative and count are independent of input order', () {
      final DisplayRect rect = _rect(0, 0, 10, 10);
      final List<ConflictItem> items = <ConflictItem>[
        _item('z', rect),
        _item('a', rect),
        _item('m', rect),
      ];

      final DuplicateCollapseResult forward = ExactDuplicateCollapser.collapse(
        items,
      );
      final DuplicateCollapseResult reversed = ExactDuplicateCollapser.collapse(
        items.reversed.toList(),
      );

      expect(_representatives(forward), 'a');
      expect(forward.collapsedCount, 2);
      expect(_representatives(reversed), 'a');
      expect(reversed.collapsedCount, 2);
      expect(_representatives(forward), _representatives(reversed));
      expect(() => forward.representatives.clear(), throwsUnsupportedError);
    });

    test('collapse does not chain through a non-duplicate pair', () {
      final ConflictItem a = _item('a', _rect(0, 0, 100, 100));
      final ConflictItem b = _item('b', _rect(0.25, 0, 100, 100));
      final ConflictItem c = _item('c', _rect(1.125, 0, 100, 100));

      // a~b and b~c are exact duplicates, but a~c is not (IoU <= 0.98).
      expect(ExactDuplicateCollapser.areExactDuplicates(a, b), isTrue);
      expect(ExactDuplicateCollapser.areExactDuplicates(b, c), isTrue);
      expect(ExactDuplicateCollapser.areExactDuplicates(a, c), isFalse);

      final DuplicateCollapseResult result = ExactDuplicateCollapser.collapse(
        <ConflictItem>[c, b, a],
      );
      // The documented greedy rule keeps the lowest id and collapses only
      // items that directly duplicate a retained representative.
      expect(_representatives(result), 'a,c');
      expect(result.collapsedCount, 1);
    });

    test('empty and single-item collapse results are complete', () {
      final DuplicateCollapseResult empty = ExactDuplicateCollapser.collapse(
        <ConflictItem>[],
      );
      expect(empty.representatives, isEmpty);
      expect(empty.collapsedCount, 0);

      final ConflictItem only = _item('only', _rect(0, 0, 10, 10));
      final DuplicateCollapseResult single = ExactDuplicateCollapser.collapse(
        <ConflictItem>[only],
      );
      expect(single.representatives.length, 1);
      expect(identical(single.representatives.single, only), isTrue);
      expect(single.collapsedCount, 0);
    });
  });

  group('T055 validation and determinism', () {
    test('an empty id is rejected content-free', () {
      expect(
        () => _item('', _rect(0, 0, 10, 10)),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message.toString(),
            'message',
            'conflict item id must not be empty',
          ),
        ),
      );
    });

    test('a negative detector pass is rejected content-free', () {
      expect(
        () => _item('a', _rect(0, 0, 10, 10), detectorPass: -1),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message.toString(),
            'message',
            'conflict item detector pass must be non-negative',
          ),
        ),
      );
    });

    test('duplicate ids are rejected content-free by both entry points', () {
      final ConflictItem first = _item('dup-secret', _rect(0, 0, 10, 10));
      final ConflictItem second = _item('dup-secret', _rect(0, 0, 10, 5));
      final Matcher rejection = throwsA(
        isA<ArgumentError>().having(
          (ArgumentError error) => error.message.toString(),
          'message',
          isNot(contains('dup-secret')),
        ),
      );

      expect(
        () => ConflictDetector.detect(<ConflictItem>[first, second]),
        rejection,
      );
      expect(
        () => ExactDuplicateCollapser.collapse(<ConflictItem>[first, second]),
        rejection,
      );
    });

    test('non-finite rect values cannot enter the model', () {
      expect(() => _rect(double.nan, 0, 10, 10), throwsArgumentError);
      expect(() => _rect(0, 0, double.infinity, 10), throwsArgumentError);
      // A finite coordinate whose 1/8 pt scaling overflows is rejected with
      // a fixed, content-free message before it can enter a graph.
      expect(
        () => _item('secret-id', _rect(double.maxFinite, 0, 10, 10)),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message.toString(),
            'message',
            isNot(contains('secret-id')),
          ),
        ),
      );
    });

    test('conflict detection is independent of input order', () {
      final List<ConflictItem> items = <ConflictItem>[
        _item('e', _rect(0, 0, 10, 10)),
        _item('b', _rect(0, 0, 10, 5)),
        _item('d', _rect(20, 0, 10, 10)),
        _item('a', _rect(0, 0, 10, 10.125)),
        _item('c', _rect(0, 0, 10, 4.875)),
      ];
      final List<ConflictItem> shuffled = <ConflictItem>[
        items[3],
        items[0],
        items[4],
        items[2],
        items[1],
      ];

      final ConflictGraph baseline = ConflictDetector.detect(items);
      final ConflictGraph reordered = ConflictDetector.detect(shuffled);

      expect(_snapshot(reordered), _snapshot(baseline));
    });

    test('duplicate collapse is independent of input order', () {
      final List<ConflictItem> items = <ConflictItem>[
        _item('d', _rect(0, 0, 10, 10), detectorPass: 1),
        _item('c', _rect(0, 0, 10, 10)),
        _item('b', _rect(0, 0, 10, 10.125), type: 'number'),
        _item('a', _rect(0, 0, 10, 10.125)),
      ];
      final List<ConflictItem> shuffled = <ConflictItem>[
        items[2],
        items[0],
        items[3],
        items[1],
      ];

      final DuplicateCollapseResult baseline = ExactDuplicateCollapser.collapse(
        items,
      );
      final DuplicateCollapseResult reordered =
          ExactDuplicateCollapser.collapse(shuffled);

      expect(_representatives(reordered), _representatives(baseline));
      expect(reordered.collapsedCount, baseline.collapsedCount);
    });
  });
}
