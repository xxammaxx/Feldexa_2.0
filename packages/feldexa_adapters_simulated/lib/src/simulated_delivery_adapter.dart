// T028 SIMULATED delivery adapter.
//
// The browser cannot open Android's SAF creator, share sheet, or print flow.
// The substitute reports a deterministic, clearly labelled `SIMULATED`
// hand-off for an existing preview artifact and records it in the backend so a
// browser journey can assert what was requested. It never claims a real file
// was saved, shared, or printed.
//
// The location hint is German display text without a path or URI
// (`contracts/ports.md` §2.6). User cancellation is `completed: false` and is
// not an error.
library;

import 'package:feldexa_ports/feldexa_ports.dart';

import 'simulated_backend.dart';
import 'simulated_contract.dart';

/// Deterministic `DeliveryPort` substitute.
final class SimulatedDeliveryAdapter implements DeliveryPort {
  /// Creates the delivery adapter.
  SimulatedDeliveryAdapter({required this.backend});

  /// Shared simulated backend.
  final SimulatedBackend backend;

  bool _cancelNext = false;

  static final CapabilityDescriptor _descriptor = simulatedDescriptor(
    kind: CapabilityKind.delivery,
    adapterId: simulatedDeliveryAdapterId,
    supportedFeatures: const <String>[
      'simulated-save',
      'simulated-share',
      'simulated-print',
      'cancellation',
    ],
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  /// Evidence label carried by every delivery outcome.
  CapabilityEvidence get evidence => _descriptor.evidence;

  /// Makes the next delivery simulate a user cancellation.
  void cancelNextDelivery() {
    _cancelNext = true;
  }

  @override
  Future<DeliveryOutcome> deliver({
    required DeliveryAction action,
    required String artifactId,
  }) async {
    final bool cancelled = _cancelNext;
    _cancelNext = false;
    if (backend.artifact(artifactId) == null) {
      // No verified preview exists; a hand-off cannot be simulated on nothing.
      throw ExportFailedException();
    }
    final DeliveryOutcome outcome;
    if (cancelled) {
      outcome = DeliveryOutcome(
        action: action,
        completed: false,
        evidence: evidence,
      );
    } else {
      outcome = DeliveryOutcome(
        action: action,
        completed: true,
        userVisibleLocationHint: _hintFor(action),
        evidence: evidence,
      );
    }
    backend.recordDelivery(
      SimulatedDeliveryRecord(
        action: action,
        artifactId: artifactId,
        completed: outcome.completed,
        at: backend.context.nowUtc(),
      ),
    );
    return outcome;
  }

  static String _hintFor(DeliveryAction action) {
    return switch (action) {
      DeliveryAction.save => 'SIMULATED: Speichern im Browser',
      DeliveryAction.share => 'SIMULATED: Freigabe im Browser',
      DeliveryAction.print => 'SIMULATED: Druck im Browser',
    };
  }
}
