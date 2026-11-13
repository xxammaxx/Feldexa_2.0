// T011 fault injector.

import 'dart:async';

import 'fault_kind.dart';
import 'fault_rule.dart';

/// A deterministic, call-counting fault injector.
///
/// Adapters call [check] at a documented fault point (or wrap the operation in
/// [run]/[runAsync]). The injector throws [InjectedFault] exactly where the
/// script says, so tests exercise recovery paths instead of asserting them.
///
/// The injector is scaffolding, not evidence. A browser run that uses it is
/// still SIMULATED; an emulator/device run is still EMULATOR/DEVICE. It never
/// upgrades a result's evidence class.
final class FaultInjector {
  /// Creates an injector from [plan] (or an empty plan when omitted).
  FaultInjector([FaultPlan? plan])
    : _rules = <FaultRule>[...?plan?.rules],
      _remaining = <FaultRule, int?>{
        for (final FaultRule rule in plan?.rules ?? const <FaultRule>[])
          rule: rule.times,
      };

  final List<FaultRule> _rules;
  final Map<FaultRule, int?> _remaining;
  final Map<String, int> _calls = <String, int>{};
  final List<InjectedFault> _injected = <InjectedFault>[];
  int _totalCalls = 0;

  /// Currently armed rules in registration order.
  List<FaultRule> get rules => List<FaultRule>.unmodifiable(_rules);

  /// Faults that were actually injected, in order.
  List<InjectedFault> get injectedFaults =>
      List<InjectedFault>.unmodifiable(_injected);

  /// Total calls to [check]/[run]/[runAsync] across all points.
  int get totalCalls => _totalCalls;

  /// Calls observed for [point], including a call that injected a fault.
  int callsAt(String point) => _calls[point] ?? 0;

  /// Faults injected at [point], optionally filtered by [kind].
  Iterable<InjectedFault> faultsAt(String point, {FaultKind? kind}) =>
      _injected.where(
        (InjectedFault fault) =>
            fault.point == point && (kind == null || fault.kind == kind),
      );

  /// Arms one additional rule.
  void arm(FaultRule rule) {
    for (final FaultRule existing in _rules) {
      if (existing.point == rule.point && existing.startsAt == rule.startsAt) {
        throw ArgumentError(
          'A rule for ${rule.point} at call ${rule.startsAt} is already armed.',
        );
      }
    }
    _rules.add(rule);
    _remaining[rule] = rule.times;
  }

  /// Removes every rule for [point]. Existing call counts are preserved.
  void disarm(String point) {
    _rules.removeWhere((FaultRule rule) => rule.point == point);
    _remaining.removeWhere((FaultRule rule, int? _) => rule.point == point);
  }

  /// Removes all rules and clears recorded calls and faults.
  void clear() {
    _rules.clear();
    _remaining.clear();
    _calls.clear();
    _injected.clear();
    _totalCalls = 0;
  }

  /// Counts one call at [point] and throws if a rule is armed for it.
  ///
  /// Rules are evaluated in registration order; the first applicable rule with
  /// remaining injections wins. A fault thrown here has already been counted.
  void check(String point) {
    _totalCalls++;
    final int callIndex = (_calls[point] ?? 0) + 1;
    _calls[point] = callIndex;

    for (final FaultRule rule in _rules) {
      if (!rule.matches(point, callIndex)) {
        continue;
      }
      final int? remaining = _remaining[rule];
      if (remaining == 0) {
        continue;
      }
      if (remaining != null) {
        _remaining[rule] = remaining - 1;
      }
      final InjectedFault fault = InjectedFault(
        kind: rule.kind,
        point: point,
        callIndex: callIndex,
        message: rule.message,
      );
      _injected.add(fault);
      throw fault;
    }
  }

  /// Checks [point], then runs [action] synchronously.
  T run<T>(String point, T Function() action) {
    check(point);
    return action();
  }

  /// Checks [point], then runs [action] asynchronously.
  Future<T> runAsync<T>(String point, FutureOr<T> Function() action) async {
    check(point);
    return await action();
  }
}
