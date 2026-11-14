// T013 `DeliveryPort` action and result DTOs.
//
// Owner: `packages/feldexa_ports/lib/src/dto/delivery_dto.dart` (T013).
// Normative source: `contracts/ports.md` §2.6.
//
// User cancellation is reported as `completed: false` and is not an error. The
// location hint is German display text only; it never exposes an internal path
// or URI.

import 'package:feldexa_ports/evidence.dart';

import 'validation.dart';

/// The three delivery hand-offs (`contracts/ports.md` §2.6).
enum DeliveryAction {
  /// Save through the platform document creator.
  save,

  /// Share through the platform share sheet.
  share,

  /// Print through the system print flow.
  print,
}

/// The outcome of one delivery attempt (`contracts/ports.md` §2.6).
final class DeliveryOutcome {
  /// Creates a delivery outcome.
  ///
  /// [userVisibleLocationHint], when present, is a short German display hint
  /// without a path, URI, or control character. Invalid values throw a safe
  /// [ArgumentError] that does not echo the hint.
  factory DeliveryOutcome({
    required DeliveryAction action,
    required bool completed,
    String? userVisibleLocationHint,
    required CapabilityEvidence evidence,
  }) {
    return DeliveryOutcome._(
      action: action,
      completed: completed,
      userVisibleLocationHint: optionalLocationHint(userVisibleLocationHint),
      evidence: evidence,
    );
  }

  const DeliveryOutcome._({
    required this.action,
    required this.completed,
    required this.userVisibleLocationHint,
    required this.evidence,
  });

  /// The attempted hand-off.
  final DeliveryAction action;

  /// Whether the platform completed the hand-off; user cancellation is false.
  final bool completed;

  /// Optional German location hint, for example `In „Downloads“ gespeichert`.
  final String? userVisibleLocationHint;

  /// Evidence class of the adapter that produced this outcome.
  final CapabilityEvidence evidence;

  @override
  String toString() {
    return 'DeliveryOutcome(action: ${action.name}, completed: $completed)';
  }
}
