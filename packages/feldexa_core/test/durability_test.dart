// T088 durability-state contract tests.
//
// These are host-VM tests (evidence class NONE). They pin the
// `DurabilityStatus` contract from `data-model.md` §2.5 and FR-046:
//   * the six states, their exact wire tokens, and honest durability;
//   * const singleton and payload-based value equality;
//   * UTC preservation and content-free rejection for `saved`;
//   * catalog-code validation for `saveFailed`;
//   * lowercase UUIDv4 validation for `recoveryFallback`;
//   * safe, stable diagnostics that never expose a German user sentence.
//
// No device, emulator, Android, UI, or visual claim is made here.

import 'package:feldexa_core/feldexa_core.dart';
import 'package:flutter_test/flutter_test.dart';

const String _revisionId = '1b4e28ba-2fa1-4d3b-a1f8-6f2a3c4d5e6f';
const String _otherRevisionId = '2c5f39cb-3ab2-4e4c-b2f9-7a3b4d5e6f70';
const String _revisionIdVariant8 = '1b4e28ba-2fa1-4d3b-81f8-6f2a3c4d5e6f';
const String _revisionIdVariant9 = '1b4e28ba-2fa1-4d3b-91f8-6f2a3c4d5e6f';
const String _savedTimestampText = '2026-11-14T12:05:06.789Z';

final RegExp _wireTokenPattern = RegExp(r'^[a-z][A-Za-z]*$');
final RegExp _catalogCodePattern = RegExp(r'^[A-Z]{2,6}-[0-9]{3}$');
final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

const List<String> _userVisibleGermanWords = <String>[
  'Gespeichert',
  'Speichern',
  'Ungespeichert',
  'Fehler',
  'Wiederherstellung',
];

typedef _StateCase = ({
  DurabilityStatus status,
  String wireName,
  bool durable,
  Type type,
  String diagnostic,
});

DateTime _savedAt() => DateTime.utc(2026, 11, 14, 12, 5, 6, 789);

List<_StateCase> _stateCases() {
  return <_StateCase>[
    (
      status: DurabilityStatus.clean,
      wireName: 'clean',
      durable: true,
      type: CleanDurabilityStatus,
      diagnostic: 'DurabilityStatus.clean',
    ),
    (
      status: DurabilityStatus.saving,
      wireName: 'saving',
      durable: false,
      type: SavingDurabilityStatus,
      diagnostic: 'DurabilityStatus.saving',
    ),
    (
      status: DurabilityStatus.unsaved,
      wireName: 'unsaved',
      durable: false,
      type: UnsavedDurabilityStatus,
      diagnostic: 'DurabilityStatus.unsaved',
    ),
    (
      status: DurabilityStatus.saved(lastDurableAt: _savedAt()),
      wireName: 'saved',
      durable: true,
      type: SavedDurabilityStatus,
      diagnostic: 'DurabilityStatus.saved(lastDurableAt: $_savedTimestampText)',
    ),
    (
      status: DurabilityStatus.saveFailed('SAVE-003'),
      wireName: 'saveFailed',
      durable: false,
      type: SaveFailedDurabilityStatus,
      diagnostic: 'DurabilityStatus.saveFailed(SAVE-003)',
    ),
    (
      status: DurabilityStatus.recoveryFallback(_revisionId),
      wireName: 'recoveryFallback',
      durable: false,
      type: RecoveryFallbackDurabilityStatus,
      diagnostic: 'DurabilityStatus.recoveryFallback($_revisionId)',
    ),
  ];
}

ArgumentError _expectArgumentError(
  void Function() action, {
  required String reason,
}) {
  try {
    action();
  } on ArgumentError catch (error) {
    expect(error.message, isA<String>(), reason: reason);
    return error;
  }
  fail('expected ArgumentError: $reason');
}

/// A diagnostic is a single developer-facing line, not a localized sentence.
void _expectDiagnosticText(String text, {required String reason}) {
  expect(text, isNotEmpty, reason: reason);
  expect(text.contains('\n'), isFalse, reason: reason);
  expect(text.endsWith('.'), isFalse, reason: reason);
  expect(text.endsWith('!'), isFalse, reason: reason);
  expect(text.endsWith('?'), isFalse, reason: reason);
  for (final String word in _userVisibleGermanWords) {
    expect(text.contains(word), isFalse, reason: '$reason contains "$word"');
  }
}

void _expectContentFreeRejection(
  void Function() action, {
  required Iterable<String> rejectedInputs,
  required String reason,
}) {
  final ArgumentError error = _expectArgumentError(action, reason: reason);
  final String diagnostic = error.toString();
  final String message = error.message as String;

  _expectDiagnosticText(diagnostic, reason: reason);
  _expectDiagnosticText(message, reason: reason);

  for (final String rejectedInput in rejectedInputs) {
    if (rejectedInput.isEmpty) {
      // The empty string is a substring of every string, so an echo check is
      // vacuous. The generic diagnostic checks above still apply.
      continue;
    }
    expect(
      diagnostic.contains(rejectedInput),
      isFalse,
      reason: '$reason must not echo "$rejectedInput" in toString()',
    );
    expect(
      message.contains(rejectedInput),
      isFalse,
      reason: '$reason must not echo "$rejectedInput" in message',
    );
    final Object? invalidValue = error.invalidValue;
    if (invalidValue != null) {
      expect(
        invalidValue.toString().contains(rejectedInput),
        isFalse,
        reason: '$reason must not echo "$rejectedInput" in invalidValue',
      );
    }
  }
}

void main() {
  group('six states', () {
    test('constructs every sealed variant with its exact runtime type', () {
      final List<_StateCase> cases = _stateCases();
      expect(cases, hasLength(6));
      for (final _StateCase item in cases) {
        expect(item.status.runtimeType, item.type, reason: item.wireName);
        expect(item.status, isA<DurabilityStatus>(), reason: item.wireName);
      }
    });

    test('exposes the exact wire tokens in contract order', () {
      expect(
        _stateCases().map((_StateCase item) => item.wireName).toList(),
        <String>[
          'clean',
          'saving',
          'unsaved',
          'saved',
          'saveFailed',
          'recoveryFallback',
        ],
      );
      expect(
        _stateCases().map((_StateCase item) => item.status.wireName).toList(),
        <String>[
          'clean',
          'saving',
          'unsaved',
          'saved',
          'saveFailed',
          'recoveryFallback',
        ],
      );
      for (final _StateCase item in _stateCases()) {
        expect(
          item.status.wireName,
          matches(_wireTokenPattern),
          reason: item.wireName,
        );
      }
    });

    test('is durable only for clean and saved', () {
      for (final _StateCase item in _stateCases()) {
        expect(item.status.isDurable, item.durable, reason: item.wireName);
      }
      expect(
        _stateCases()
            .where((_StateCase item) => item.status.isDurable)
            .map((_StateCase item) => item.wireName)
            .toList(),
        <String>['clean', 'saved'],
      );
    });

    test('non-durable states never compare equal to a durable state', () {
      final DurabilityStatus savedStatus = DurabilityStatus.saved(
        lastDurableAt: _savedAt(),
      );
      for (final _StateCase item in _stateCases()) {
        if (item.durable) {
          continue;
        }
        expect(
          item.status,
          isNot(DurabilityStatus.clean),
          reason: item.wireName,
        );
        expect(item.status, isNot(savedStatus), reason: item.wireName);
        expect(
          DurabilityStatus.clean,
          isNot(item.status),
          reason: item.wireName,
        );
        expect(savedStatus, isNot(item.status), reason: item.wireName);
      }
    });
  });

  group('const singletons and value equality', () {
    test('the three const singletons equal themselves', () {
      expect(DurabilityStatus.clean, DurabilityStatus.clean);
      expect(DurabilityStatus.saving, DurabilityStatus.saving);
      expect(DurabilityStatus.unsaved, DurabilityStatus.unsaved);
    });

    test('the three const singletons are pairwise unequal', () {
      final List<DurabilityStatus> singletons = <DurabilityStatus>[
        DurabilityStatus.clean,
        DurabilityStatus.saving,
        DurabilityStatus.unsaved,
      ];
      for (int left = 0; left < singletons.length; left++) {
        for (int right = 0; right < singletons.length; right++) {
          if (left == right) {
            continue;
          }
          expect(singletons[left], isNot(singletons[right]));
        }
      }
    });

    test('saved equality includes the UTC timestamp', () {
      final DateTime at = _savedAt();
      final DurabilityStatus first = DurabilityStatus.saved(lastDurableAt: at);
      final DurabilityStatus sameInstant = DurabilityStatus.saved(
        lastDurableAt: DateTime.fromMillisecondsSinceEpoch(
          at.millisecondsSinceEpoch,
          isUtc: true,
        ),
      );
      final DurabilityStatus later = DurabilityStatus.saved(
        lastDurableAt: DateTime.utc(2026, 11, 14, 12, 5, 6, 790),
      );

      expect(first, sameInstant);
      expect(first.hashCode, sameInstant.hashCode);
      expect(first, isNot(later));
      expect(first, isNot(DurabilityStatus.clean));
      expect(DurabilityStatus.clean, isNot(first));
    });

    test('saveFailed equality includes the catalog code', () {
      final DurabilityStatus first = DurabilityStatus.saveFailed('SAVE-003');
      final DurabilityStatus same = DurabilityStatus.saveFailed('SAVE-003');
      final DurabilityStatus other = DurabilityStatus.saveFailed('SAVE-008');

      expect(first, same);
      expect(first.hashCode, same.hashCode);
      expect(first, isNot(other));
    });

    test('recoveryFallback equality includes the revision id', () {
      final DurabilityStatus first = DurabilityStatus.recoveryFallback(
        _revisionId,
      );
      final DurabilityStatus same = DurabilityStatus.recoveryFallback(
        _revisionId,
      );
      final DurabilityStatus other = DurabilityStatus.recoveryFallback(
        _otherRevisionId,
      );

      expect(first, same);
      expect(first.hashCode, same.hashCode);
      expect(first, isNot(other));
    });
  });

  group('saved', () {
    test('preserves the UTC timestamp at millisecond precision', () {
      final DateTime timestamp = _savedAt();
      final DurabilityStatus status = DurabilityStatus.saved(
        lastDurableAt: timestamp,
      );

      expect(status, isA<SavedDurabilityStatus>());
      final SavedDurabilityStatus saved = status as SavedDurabilityStatus;
      expect(saved.lastDurableAt.isUtc, isTrue);
      expect(
        saved.lastDurableAt.millisecondsSinceEpoch,
        timestamp.millisecondsSinceEpoch,
      );
      expect(saved.lastDurableAt.millisecond, 789);
      expect(saved.lastDurableAt.microsecond, 0);
      expect(saved.lastDurableAt, timestamp);
    });

    test('rejects local timestamps with a content-free ArgumentError', () {
      final DateTime local = DateTime(2026, 11, 14, 12, 5, 6, 789);
      final DateTime localFromMilliseconds =
          DateTime.fromMillisecondsSinceEpoch(
            _savedAt().millisecondsSinceEpoch,
            isUtc: false,
          );
      expect(local.isUtc, isFalse);
      expect(localFromMilliseconds.isUtc, isFalse);

      for (final DateTime rejected in <DateTime>[
        local,
        localFromMilliseconds,
      ]) {
        _expectContentFreeRejection(
          () => DurabilityStatus.saved(lastDurableAt: rejected),
          rejectedInputs: <String>[
            rejected.toIso8601String(),
            rejected.toString(),
            rejected.millisecondsSinceEpoch.toString(),
            _savedTimestampText,
          ],
          reason: 'saved must reject a local timestamp without echo',
        );
      }
    });
  });

  group('saveFailed', () {
    test('stores shape-valid catalog codes exactly', () {
      // The production validator is shape-only: it accepts every token
      // matching ^[A-Z]{2,6}-[0-9]{3}$. These are real German catalog codes,
      // including 3-letter prefixes; shape validity is not a claim of catalog
      // membership.
      for (final String code in <String>[
        'SAVE-003',
        'SAVE-008',
        'DATE-001',
        'IMP-001',
        'DEL-001',
        'FLD-001',
      ]) {
        final DurabilityStatus status = DurabilityStatus.saveFailed(code);
        expect(status, isA<SaveFailedDurabilityStatus>());
        final SaveFailedDurabilityStatus failed =
            status as SaveFailedDurabilityStatus;
        expect(failed.errorCode, code);
        expect(failed.errorCode, matches(_catalogCodePattern));
      }
    });

    test('accepts a shape-valid non-catalog token by design', () {
      // Deliberately synthetic: the production validator checks shape only,
      // not membership in the German catalog. This is not a catalog code and
      // must not be presented as one.
      const String synthetic = 'ZZ-999';
      final SaveFailedDurabilityStatus failed =
          DurabilityStatus.saveFailed(synthetic) as SaveFailedDurabilityStatus;
      expect(failed.errorCode, synthetic);
      expect(failed.errorCode, matches(_catalogCodePattern));
    });

    test('rejects malformed codes with a content-free ArgumentError', () {
      for (final String code in <String>[
        '',
        'save-003',
        'SAVE_003',
        'SAVE-03',
        'SAVE-0003',
        'S-003',
        'TOOLONG-003',
        'Speichern fehlgeschlagen',
      ]) {
        _expectContentFreeRejection(
          () => DurabilityStatus.saveFailed(code),
          rejectedInputs: <String>[code],
          reason: 'saveFailed must reject "$code" without echo',
        );
      }
    });
  });

  group('recoveryFallback', () {
    test('stores lowercase UUIDv4 ids with all [89ab] variant nibbles', () {
      for (final String revisionId in <String>[
        _revisionIdVariant8,
        _revisionIdVariant9,
        _revisionId,
        _otherRevisionId,
      ]) {
        final DurabilityStatus status = DurabilityStatus.recoveryFallback(
          revisionId,
        );

        expect(status, isA<RecoveryFallbackDurabilityStatus>());
        final RecoveryFallbackDurabilityStatus fallback =
            status as RecoveryFallbackDurabilityStatus;
        expect(fallback.revisionId, revisionId);
        expect(fallback.revisionId, matches(_uuidV4Pattern));
        expect(revisionId[19], isIn(<String>['8', '9', 'a', 'b']));
      }
    });

    test('rejects malformed ids with a content-free ArgumentError', () {
      for (final String revisionId in <String>[
        '',
        'latest',
        '1B4E28BA-2FA1-4D3B-A1F8-6F2A3C4D5E6F',
        '1b4e28ba-2fa1-1d3b-a1f8-6f2a3c4d5e6f',
        '1b4e28ba-2fa1-5d3b-a1f8-6f2a3c4d5e6f',
        '1b4e28ba-2fa1-4d3b-c1f8-6f2a3c4d5e6f',
        '1b4e28ba2fa1-4d3b-a1f8-6f2a3c4d5e6f',
        '1b4e28ba-2fa1-4d3b-a1f8-6f2a3c4d5e6fa',
      ]) {
        _expectContentFreeRejection(
          () => DurabilityStatus.recoveryFallback(revisionId),
          rejectedInputs: <String>[revisionId],
          reason: 'recoveryFallback must reject "$revisionId" without echo',
        );
      }
    });
  });

  group('diagnostics', () {
    test('exposes tokens and contract-shaped payloads, never a sentence', () {
      for (final _StateCase item in _stateCases()) {
        expect(
          item.status.wireName,
          matches(_wireTokenPattern),
          reason: item.wireName,
        );
        _expectDiagnosticText(item.status.toString(), reason: item.wireName);
      }

      final SaveFailedDurabilityStatus failed =
          DurabilityStatus.saveFailed('SAVE-003') as SaveFailedDurabilityStatus;
      expect(failed.errorCode, matches(_catalogCodePattern));

      final RecoveryFallbackDurabilityStatus fallback =
          DurabilityStatus.recoveryFallback(_revisionId)
              as RecoveryFallbackDurabilityStatus;
      expect(fallback.revisionId, matches(_uuidV4Pattern));
    });

    test('toString is deterministic, single-line, and non-durable safe', () {
      for (final _StateCase item in _stateCases()) {
        final String first = item.status.toString();
        final String second = item.status.toString();

        expect(first, second, reason: item.wireName);
        expect(first.contains('\n'), isFalse, reason: item.wireName);
        expect(
          first,
          startsWith('DurabilityStatus.${item.wireName}'),
          reason: item.wireName,
        );
        for (final String word in _userVisibleGermanWords) {
          expect(
            first.contains(word),
            isFalse,
            reason: '${item.wireName} contains "$word"',
          );
        }
        if (!item.durable) {
          expect(
            first.contains('DurabilityStatus.clean'),
            isFalse,
            reason: item.wireName,
          );
          expect(
            first.contains('DurabilityStatus.saved'),
            isFalse,
            reason: item.wireName,
          );
        }
      }
    });

    test('pins the exact diagnostic strings', () {
      for (final _StateCase item in _stateCases()) {
        expect(item.status.toString(), item.diagnostic, reason: item.wireName);
      }
      expect(DurabilityStatus.clean.toString(), 'DurabilityStatus.clean');
      expect(DurabilityStatus.saving.toString(), 'DurabilityStatus.saving');
      expect(DurabilityStatus.unsaved.toString(), 'DurabilityStatus.unsaved');
      expect(
        DurabilityStatus.saved(lastDurableAt: _savedAt()).toString(),
        'DurabilityStatus.saved('
        'lastDurableAt: 2026-11-14T12:05:06.789Z)',
      );
      expect(
        DurabilityStatus.saveFailed('SAVE-003').toString(),
        'DurabilityStatus.saveFailed(SAVE-003)',
      );
      expect(
        DurabilityStatus.recoveryFallback(_revisionId).toString(),
        'DurabilityStatus.recoveryFallback($_revisionId)',
      );
    });
  });
}
