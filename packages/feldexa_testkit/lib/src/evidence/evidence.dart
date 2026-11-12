// T011 evidence-class primitives.
//
// Constitution Principle VIII and plan §Evidence Plan require every result to
// be reported in exactly one clearly labelled class. This file gives the
// toolkit typed labels so a host-VM check cannot silently describe itself as
// Android runtime evidence, and a SIMULATED browser result cannot be merged
// with an EMULATOR/DEVICE claim.
//
// These types are metadata only. Using this package never upgrades a run's
// class: the harness that actually executed the test assigns it.

/// The evidence classes defined by constitution Principle VIII.
enum EvidenceClass {
  /// Static analysis, formatting, and host-VM unit tests. Not runtime evidence.
  none('NONE', 'No runtime evidence class (static or host-VM check only).'),

  /// Web fixtures, simulated adapters, and Chrome interactions.
  simulated(
    'SIMULATED',
    'Deterministic Web/fixture/simulated-adapter evidence.',
  ),

  /// Android emulator runtime evidence.
  emulator('EMULATOR', 'Android emulator runtime evidence.'),

  /// Physical Android device runtime evidence.
  device('DEVICE', 'Physical Android device runtime evidence.');

  const EvidenceClass(this.label, this.description);

  /// Uppercase report token, for example `SIMULATED`.
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

/// A labelled claim about what a run can prove.
///
/// [surface] names the actual execution surface (`host-vm`, `chrome`,
/// `android-emulator`, `android-device`, ...). Keeping it explicit prevents a
/// host test from being described as a browser or Android run.
final class EvidenceLabel {
  const EvidenceLabel(this.evidenceClass, this.surface, {this.detail = ''});

  /// Static or host-VM check; carries no runtime evidence class.
  const EvidenceLabel.hostVm([this.surface = 'host-vm', this.detail = ''])
    : evidenceClass = EvidenceClass.none;

  /// Deterministic fixture or simulated-adapter input.
  const EvidenceLabel.simulatedFixture([
    this.surface = 'host-vm',
    this.detail = 'SIMULATED synthetic fixture input',
  ]) : evidenceClass = EvidenceClass.simulated;

  /// Chrome/Web interaction evidence.
  const EvidenceLabel.simulatedBrowser([
    this.surface = 'chrome',
    this.detail = 'SIMULATED browser run',
  ]) : evidenceClass = EvidenceClass.simulated;

  /// Android emulator runtime evidence.
  const EvidenceLabel.androidEmulator([
    this.surface = 'android-emulator',
    this.detail = 'EMULATOR Android runtime',
  ]) : evidenceClass = EvidenceClass.emulator;

  /// Physical Android device runtime evidence.
  const EvidenceLabel.androidDevice([
    this.surface = 'android-device',
    this.detail = 'DEVICE Android runtime',
  ]) : evidenceClass = EvidenceClass.device;

  final EvidenceClass evidenceClass;

  /// The environment that produced the result.
  final String surface;

  /// Optional short explanation; must not contain document content.
  final String detail;

  bool get isAndroid => evidenceClass.isAndroid;

  bool get isRuntime => evidenceClass.isRuntime;

  /// The report token for this label.
  String get tag => evidenceClass.label;

  Map<String, Object?> toJson() => <String, Object?>{
    'evidenceClass': tag,
    'surface': surface,
    if (detail.isNotEmpty) 'detail': detail,
  };

  @override
  String toString() =>
      detail.isEmpty ? '$tag[$surface]' : '$tag[$surface]: $detail';

  @override
  bool operator ==(Object other) =>
      other is EvidenceLabel &&
      other.evidenceClass == evidenceClass &&
      other.surface == surface &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(evidenceClass, surface, detail);
}

/// A small ledger that keeps evidence classes visibly separate.
///
/// A report may contain host checks next to one runtime class, but it must not
/// merge SIMULATED evidence with EMULATOR or DEVICE evidence into one claim.
final class EvidenceLedger {
  final List<EvidenceLabel> _entries = <EvidenceLabel>[];

  /// Records one labelled result.
  void record(EvidenceLabel label) {
    _entries.add(label);
  }

  /// All recorded labels, in insertion order.
  List<EvidenceLabel> get entries => List<EvidenceLabel>.unmodifiable(_entries);

  /// Classes actually present in the ledger.
  Set<EvidenceClass> get classes => <EvidenceClass>{
    for (final EvidenceLabel label in _entries) label.evidenceClass,
  };

  /// Labels recorded for [evidenceClass].
  Iterable<EvidenceLabel> forClass(EvidenceClass evidenceClass) => _entries
      .where((EvidenceLabel label) => label.evidenceClass == evidenceClass);

  /// Whether SIMULATED and Android runtime evidence are both present.
  bool get isMerged {
    final Set<EvidenceClass> present = classes;
    return present.contains(EvidenceClass.simulated) &&
        present.any((EvidenceClass evidenceClass) => evidenceClass.isAndroid);
  }

  /// Throws [StateError] instead of allowing a merged evidence claim.
  void requireSeparated() {
    if (!isMerged) {
      return;
    }
    final Iterable<String> android = entries
        .where((EvidenceLabel label) => label.isAndroid)
        .map((EvidenceLabel label) => label.toString());
    throw StateError(
      'SIMULATED evidence must be reported separately from Android evidence; '
      'found ${android.join(', ')}.',
    );
  }

  /// Report-ready summary, one line per class.
  String summarize() {
    final StringBuffer buffer = StringBuffer();
    for (final EvidenceClass evidenceClass in EvidenceClass.values) {
      final Iterable<EvidenceLabel> labels = forClass(evidenceClass);
      if (labels.isEmpty) {
        continue;
      }
      buffer.writeln('${evidenceClass.label}: ${labels.length}');
    }
    return buffer.toString().trimRight();
  }
}
