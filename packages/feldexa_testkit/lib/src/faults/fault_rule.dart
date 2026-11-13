// T011 injected-fault value types.

import 'fault_kind.dart';

/// The error thrown at an armed fault point.
///
/// It intentionally carries only a kind, point name, and call index. No
/// document bytes, file name, OCR text, value, or signature may be attached.
final class InjectedFault implements Exception {
  const InjectedFault({
    required this.kind,
    required this.point,
    required this.callIndex,
    this.message,
  });

  final FaultKind kind;

  /// The fault point that was reached.
  final String point;

  /// One-based call number for [point] at the time of injection.
  final int callIndex;

  /// Optional test-authored explanation; never product data.
  final String? message;

  /// The catalog code the production path is expected to surface.
  String get catalogCode => kind.catalogCode;

  @override
  String toString() {
    final String suffix = message == null ? '' : ': $message';
    return 'InjectedFault(${kind.name} at $point, call $callIndex)$suffix';
  }
}

/// Declarative instruction to inject [kind] at [point].
///
/// [startsAt] is the one-based call number at which injection begins.
/// [times] is the number of injected faults; `null` means every matching call
/// (use that deliberately, for example to prove repeated retry failure).
final class FaultRule {
  FaultRule({
    required this.point,
    required this.kind,
    this.startsAt = 1,
    this.times = 1,
    this.message,
  }) {
    if (point.trim().isEmpty) {
      throw ArgumentError.value(point, 'point', 'must not be empty');
    }
    if (startsAt < 1) {
      throw ArgumentError.value(startsAt, 'startsAt', 'must be at least 1');
    }
    final int? count = times;
    if (count != null && count < 1) {
      throw ArgumentError.value(count, 'times', 'must be null or at least 1');
    }
    if (message != null && message!.isEmpty) {
      throw ArgumentError.value(message, 'message', 'must not be empty');
    }
  }

  final String point;
  final FaultKind kind;
  final int startsAt;
  final int? times;
  final String? message;

  bool get isUnlimited => times == null;

  /// Whether this rule applies to the [callIndex] call of [candidatePoint].
  bool matches(String candidatePoint, int callIndex) =>
      candidatePoint == point && callIndex >= startsAt;

  @override
  String toString() =>
      'FaultRule(${kind.name} at $point from call $startsAt, '
      'times: ${times ?? 'unlimited'})';
}

/// An immutable set of rules used to construct a [FaultInjector].
final class FaultPlan {
  FaultPlan(Iterable<FaultRule> rules) : rules = List<FaultRule>.of(rules) {
    final Set<String> seen = <String>{};
    for (final FaultRule rule in this.rules) {
      final String key = '${rule.point}@${rule.startsAt}';
      if (!seen.add(key)) {
        throw ArgumentError(
          'Duplicate fault rule for ${rule.point} at call ${rule.startsAt}; '
          'two kinds cannot be injected on the same call.',
        );
      }
    }
  }

  /// A plan that injects nothing.
  factory FaultPlan.empty() => FaultPlan(const <FaultRule>[]);

  final List<FaultRule> rules;
}
