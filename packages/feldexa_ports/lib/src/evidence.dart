// T014 capability evidence vocabulary.
//
// Owner: `packages/feldexa_ports/lib/src/evidence.dart` (T014, issue #14).
// Normative sources:
//   * `contracts/ports.md` §1 — `EvidenceClass` and `CapabilityEvidence`;
//   * `contracts/error-catalog.de.md` — report tokens and failure semantics;
//   * constitution Principle VIII — `SIMULATED`, `EMULATOR`, and `DEVICE` are
//     separate evidence classes and are never merged into one claim.
//
// This file is the single declaration of both types. The already-implemented
// T011 toolkit consumes `EvidenceClass` from this package through
// `package:feldexa_ports/evidence.dart`; it no longer declares its own enum.
//
// These types are metadata. Constructing a label never upgrades a run's class:
// only the harness that actually executed a check may assign `EMULATOR` or
// `DEVICE`, and Web/fixture work stays `SIMULATED`.

/// The evidence classes defined by constitution Principle VIII.
///
/// The declaration order matches `contracts/ports.md` §1. `none` is the class
/// for static analysis, formatting, and host-VM unit tests; it is not a weaker
/// runtime class and must never be reported as runtime evidence.
enum EvidenceClass {
  /// Web fixtures, simulated adapters, and Chrome interactions.
  simulated(
    'SIMULATED',
    'Deterministic Web/fixture/simulated-adapter evidence.',
  ),

  /// Android emulator runtime evidence.
  emulator('EMULATOR', 'Android emulator runtime evidence.'),

  /// Physical Android device runtime evidence.
  device('DEVICE', 'Physical Android device runtime evidence.'),

  /// Static analysis, formatting, and host-VM unit tests.
  none('NONE', 'No runtime evidence class (static or host-VM check only).');

  const EvidenceClass(this.label, this.description);

  /// Uppercase report token, for example `SIMULATED`.
  ///
  /// The tokens are the only values permitted in report fields and in the
  /// `SIMULATED` UI label required by FR-087.
  final String label;

  /// Human-readable scope of what this class can establish.
  final String description;

  /// Whether this class is produced on Android hardware or an emulator.
  bool get isAndroid => this == emulator || this == device;

  /// Whether this class is produced by an executing runtime.
  bool get isRuntime => this != none;

  /// Parses a report token or enum name, case-insensitively.
  ///
  /// Throws [FormatException] for unknown values. There is deliberately no
  /// fallback: an unlabelled result must not become `NONE` by accident.
  static EvidenceClass parse(String value) {
    final String normalized = value.trim().toLowerCase();
    for (final EvidenceClass evidenceClass in values) {
      if (evidenceClass.name == normalized ||
          evidenceClass.label.toLowerCase() == normalized) {
        return evidenceClass;
      }
    }
    throw FormatException(
      'Unknown evidence class "$value"; expected one of '
      '${values.map((EvidenceClass value) => value.label).join(', ')}.',
    );
  }

  /// Like [parse], but returns `null` for an unknown token.
  static EvidenceClass? tryParse(String value) {
    try {
      return parse(value);
    } on FormatException {
      return null;
    }
  }
}

/// A capability result's evidence classification.
///
/// `contracts/ports.md` §1 defines `simulated` as `true` if and only if
/// [evidenceClass] is [EvidenceClass.simulated]. The field is derived here
/// instead of being accepted from callers, so an inconsistent pair cannot be
/// constructed even in a release build.
final class CapabilityEvidence {
  /// Classifies a capability result.
  ///
  /// A simulated class should carry a short, content-free [simulatedReason]
  /// (for example `web.simulated-adapter`); a non-simulated class must not
  /// carry one. Both rules are enforced as constructor assertions so a
  /// mislabelled result fails the test that constructed it.
  const CapabilityEvidence({
    required this.evidenceClass,
    required this.adapterId,
    this.simulatedReason,
  }) : simulated = evidenceClass == EvidenceClass.simulated,
       assert(adapterId != '', 'adapterId must not be empty'),
       assert(
         evidenceClass == EvidenceClass.simulated || simulatedReason == null,
         'only simulated evidence may carry a simulatedReason',
       ),
       assert(
         evidenceClass != EvidenceClass.simulated ||
             simulatedReason == null ||
             simulatedReason != '',
         'simulatedReason must not be empty when supplied',
       );

  /// Evidence for a deterministic Web or fixture adapter.
  ///
  /// This is the constructor referenced by `plan.md` §Architecture Decisions 9:
  /// a simulated adapter returns `CapabilityEvidence.simulated`, and every
  /// downstream surface must keep that label.
  const CapabilityEvidence.simulated({
    required this.adapterId,
    this.simulatedReason,
  }) : evidenceClass = EvidenceClass.simulated,
       simulated = true,
       assert(adapterId != '', 'adapterId must not be empty'),
       assert(
         simulatedReason == null || simulatedReason != '',
         'simulatedReason must not be empty when supplied',
       );

  /// Evidence for a real Android adapter.
  ///
  /// Android adapters declare [EvidenceClass.none]; the environment class
  /// (`EMULATOR` or `DEVICE`) is attached by the test harness that actually
  /// executed the run, never by the adapter itself.
  const CapabilityEvidence.android({required this.adapterId})
    : evidenceClass = EvidenceClass.none,
      simulated = false,
      simulatedReason = null,
      assert(adapterId != '', 'adapterId must not be empty');

  /// The evidence class of this result.
  final EvidenceClass evidenceClass;

  /// `true` if and only if [evidenceClass] is [EvidenceClass.simulated].
  final bool simulated;

  /// Stable adapter identity, for example `android.pdfbox.v1`.
  final String adapterId;

  /// Why this result is simulated, for reports and structured logs.
  ///
  /// Must be short and must not contain document content, file names, paths,
  /// OCR text, field values, or signature data.
  final String? simulatedReason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CapabilityEvidence &&
          other.evidenceClass == evidenceClass &&
          other.simulated == simulated &&
          other.adapterId == adapterId &&
          other.simulatedReason == simulatedReason;

  @override
  int get hashCode =>
      Object.hash(evidenceClass, simulated, adapterId, simulatedReason);

  @override
  String toString() => 'CapabilityEvidence(${evidenceClass.label}, $adapterId)';
}
