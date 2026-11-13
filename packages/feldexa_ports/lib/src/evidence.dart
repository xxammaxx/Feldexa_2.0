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
//
// Privacy boundary (quality-review correction): adapter ids and simulated
// reasons are validated as bounded machine tokens at runtime, never merely by
// debug assertions, and no untrusted input is echoed in a thrown error or in
// `toString()`. A caller that passes a path, file name, free-form sentence, or
// other content-like value gets a safe `ArgumentError` that names the rule but
// not the rejected value.

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
  /// Throws [FormatException] for unknown values. The exception deliberately
  /// does not echo the rejected input: a report parser may receive fixture
  /// text, a path, or another untrusted token, and an error string is a common
  /// leak channel. There is no fallback to `NONE`; an unlabelled result must
  /// not silently become host-only evidence.
  static EvidenceClass parse(String value) {
    final String normalized = value.trim().toLowerCase();
    for (final EvidenceClass evidenceClass in values) {
      if (evidenceClass.name == normalized ||
          evidenceClass.label.toLowerCase() == normalized) {
        return evidenceClass;
      }
    }
    throw const FormatException(
      'Unknown evidence class token; expected '
      'SIMULATED, EMULATOR, DEVICE, or NONE.',
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
///
/// The constructor is deliberately **not** `const`: validation must execute in
/// release builds, where assertions are disabled. This is a security
/// requirement, not an API accident.
final class CapabilityEvidence {
  /// Classifies a capability result.
  ///
  /// [adapterId] must be a lowercase dotted machine identifier such as
  /// `android.pdfbox.v1` or `web.sim.storage.v1`. [simulatedReason], when
  /// supplied, must be a short lowercase machine token such as
  /// `web.simulated-adapter`; it may only be supplied for simulated evidence.
  /// The precise rules are documented on [adapterId] and [simulatedReason].
  /// Invalid values throw a safe [ArgumentError] that never includes the
  /// rejected value.
  CapabilityEvidence({
    required this.evidenceClass,
    required String adapterId,
    String? simulatedReason,
  }) : simulated = evidenceClass == EvidenceClass.simulated,
       adapterId = _validateAdapterId(adapterId),
       simulatedReason = _validateSimulatedReason(
         simulatedReason,
         evidenceClass,
       );

  /// Evidence for a deterministic Web or fixture adapter.
  ///
  /// This is the constructor referenced by `plan.md` §Architecture Decisions 9:
  /// a simulated adapter returns `CapabilityEvidence.simulated`, and every
  /// downstream surface must keep that label.
  CapabilityEvidence.simulated({
    required String adapterId,
    String? simulatedReason,
  }) : this(
         evidenceClass: EvidenceClass.simulated,
         adapterId: adapterId,
         simulatedReason: simulatedReason,
       );

  /// Evidence for a real Android adapter.
  ///
  /// Android adapters declare [EvidenceClass.none]; the environment class
  /// (`EMULATOR` or `DEVICE`) is attached by the test harness that actually
  /// executed the run, never by the adapter itself.
  CapabilityEvidence.android({required String adapterId})
    : this(evidenceClass: EvidenceClass.none, adapterId: adapterId);

  /// The evidence class of this result.
  final EvidenceClass evidenceClass;

  /// `true` if and only if [evidenceClass] is [EvidenceClass.simulated].
  final bool simulated;

  /// Stable adapter identity, for example `android.pdfbox.v1`.
  ///
  /// Must be 1–64 characters: a lowercase ASCII letter, then lowercase ASCII
  /// letters, digits, `_`, or `-`, with at least one dot-separated non-empty
  /// segment. Paths, spaces, free-form text, and segments that are document
  /// or image file extensions (`pdf`, `png`, `jpg`, `txt`, `json`, `fx1`, …)
  /// are rejected. The value is developer-supplied metadata, never document
  /// content.
  final String adapterId;

  /// Why this result is simulated, for reports and structured logs.
  ///
  /// Must be 1–96 characters: a lowercase machine token using letters, digits,
  /// `_`, `-`, and at least one dot-separated non-empty segment. It must not
  /// contain spaces, path separators, document/image file-extension segments,
  /// OCR text, field values, signatures, or any other content. `null` is
  /// allowed; a non-simulated class must not carry a reason.
  final String? simulatedReason;

  static final RegExp _adapterIdPattern = RegExp(
    r'^[a-z][a-z0-9_-]*(\.[a-z0-9_-]+)+$',
  );
  static final RegExp _reasonPattern = RegExp(
    r'^[a-z][a-z0-9_-]*(\.[a-z0-9_-]+)+$',
  );
  static const int _maxAdapterIdLength = 64;
  static const int _maxReasonLength = 96;

  /// File-extension segments that must never appear in evidence metadata.
  ///
  /// A path or a file name is not an adapter id or a reason, even when it
  /// happens to be lowercase. Rejecting these segments closes the obvious
  /// leak without constraining legitimate identifiers such as `pdfbox` or
  /// `export`.
  static const Set<String> _contentExtensionSegments = <String>{
    'pdf',
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'heic',
    'txt',
    'json',
    'xml',
    'csv',
    'doc',
    'docx',
    'eml',
    'zip',
    'fx1',
  };

  static bool _hasContentExtensionSegment(String value) =>
      value.split('.').any(_contentExtensionSegments.contains);

  static String _validateAdapterId(String value) {
    if (value.length > _maxAdapterIdLength ||
        !_adapterIdPattern.hasMatch(value) ||
        _hasContentExtensionSegment(value)) {
      throw ArgumentError(
        'adapterId must be a lowercase machine identifier of at most '
        '$_maxAdapterIdLength characters with dot-separated segments and no '
        'file-extension segments',
      );
    }
    return value;
  }

  static String? _validateSimulatedReason(
    String? value,
    EvidenceClass evidenceClass,
  ) {
    if (value == null) {
      return null;
    }
    if (evidenceClass != EvidenceClass.simulated) {
      throw ArgumentError(
        'simulatedReason is only valid for simulated evidence',
      );
    }
    if (value.length > _maxReasonLength ||
        !_reasonPattern.hasMatch(value) ||
        _hasContentExtensionSegment(value)) {
      throw ArgumentError(
        'simulatedReason must be a lowercase machine token of at most '
        '$_maxReasonLength characters with no file-extension segments',
      );
    }
    return value;
  }

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

  /// Redacted identity for logs.
  ///
  /// The adapter id and simulated reason are omitted because log lines are a
  /// possible leak channel for fixture-derived metadata. Callers that need the
  /// adapter id read the field explicitly.
  @override
  String toString() => 'CapabilityEvidence(${evidenceClass.label})';
}
