// T013 capability descriptor vocabulary.
//
// Owner: `packages/feldexa_ports/lib/src/descriptor.dart` (T013, issue #13).
// Normative sources:
//   * `contracts/ports.md` §1 — `CapabilityKind`, `CapabilityDescriptor`, and
//     `PlatformCapability`;
//   * `contracts/ports.md` §4 — the registry exposes one descriptor per
//     capability;
//   * constitution Principles II and III — every platform capability is a port,
//     and simulated evidence is structurally labelled.
//
// `CapabilityEvidence` and `EvidenceClass` are owned by T014 and are only
// consumed here. This file must not declare a second copy.
//
// A descriptor is developer-supplied metadata. It never carries document
// content, file names, paths, OCR text, field values, or signature bytes, and
// its `toString()` omits the adapter id for the same reason the T014 evidence
// label does: log lines are a possible leak channel.

import 'evidence.dart';

/// The ten capabilities every platform adapter set must provide
/// (`contracts/ports.md` §1).
///
/// The declaration order matches the contract, because the registry exposes
/// one descriptor per capability and tests compare the two lists.
enum CapabilityKind {
  /// `DocumentImportPort`: picker, staging, and source verification.
  documentImport,

  /// `PageRasterPort`: page dimensions and raster rendering.
  pageRaster,

  /// `OcrPort`: on-device text recognition.
  ocr,

  /// `SecureStorePort`: encrypted document and template storage.
  secureStore,

  /// `PdfExportPort`: plan validation and flattened PDF creation.
  pdfExport,

  /// `DeliveryPort`: save, share, and print hand-off.
  delivery,

  /// `LifecyclePort`: application lifecycle signals.
  lifecycle,

  /// `ClockPort`: UTC wall clock.
  clock,

  /// `IdPort`: UUIDv4 and idempotency-key generation.
  ids,

  /// `DiagnosticsPort`: on-device, content-free event ring buffer.
  diagnostics,
}

/// A platform capability that exposes its own [CapabilityDescriptor].
///
/// Every port in `lib/src/ports/` implements this interface. A caller can
/// therefore inspect a capability without knowing its concrete adapter type,
/// and the production bootstrap can reject a simulated descriptor before any
/// capability is used.
abstract interface class PlatformCapability {
  /// Identity, contract version, simulation state, and evidence class of the
  /// adapter behind this capability.
  CapabilityDescriptor get descriptor;
}

/// Static description of one registered capability adapter
/// (`contracts/ports.md` §1).
///
/// The constructor validates at runtime, not only with assertions, because a
/// release build must not accept a simulated descriptor that claims to be
/// real. The descriptor's adapter id and simulated flag must agree with its
/// [evidence]; an inconsistent descriptor would defeat the production guard.
final class CapabilityDescriptor {
  /// Creates a capability descriptor.
  ///
  /// [adapterId] must equal `evidence.adapterId`, [isSimulated] must equal
  /// `evidence.simulated`, and [version] must be a positive adapter contract
  /// version such as `1` or `1.2`. [supportedFeatures] contains short,
  /// non-empty capability tokens without control characters. Invalid values
  /// throw a safe [ArgumentError] that does not echo the rejected value.
  factory CapabilityDescriptor({
    required CapabilityKind kind,
    required String adapterId,
    required String version,
    required bool isSimulated,
    required CapabilityEvidence evidence,
    Iterable<String> supportedFeatures = const <String>[],
  }) {
    if (evidence.adapterId != adapterId) {
      throw ArgumentError('adapterId must equal evidence.adapterId');
    }
    if (evidence.simulated != isSimulated) {
      throw ArgumentError(
        'isSimulated must match the evidence class; simulated evidence is '
        'never reported as a real capability',
      );
    }
    if (!_versionPattern.hasMatch(version)) {
      throw ArgumentError(
        'version must be a positive adapter contract version such as 1',
      );
    }
    final Set<String> features = <String>{};
    for (final String feature in supportedFeatures) {
      if (feature.isEmpty ||
          feature.length > _maxFeatureLength ||
          _unsafeFeaturePattern.hasMatch(feature)) {
        throw ArgumentError(
          'supportedFeatures must contain short non-empty tokens without '
          'whitespace or control characters',
        );
      }
      features.add(feature);
    }
    return CapabilityDescriptor._(
      kind: kind,
      adapterId: adapterId,
      version: version,
      isSimulated: isSimulated,
      evidence: evidence,
      supportedFeatures: Set<String>.unmodifiable(features),
    );
  }

  const CapabilityDescriptor._({
    required this.kind,
    required this.adapterId,
    required this.version,
    required this.isSimulated,
    required this.evidence,
    required this.supportedFeatures,
  });

  /// The capability this adapter provides.
  final CapabilityKind kind;

  /// Stable adapter identity, for example `android.pdfbox.v1`.
  ///
  /// The value is validated by [CapabilityEvidence] and must equal
  /// `evidence.adapterId`. It is metadata, never document content.
  final String adapterId;

  /// Adapter contract version; the first version is `1`.
  final String version;

  /// Whether this adapter is a deterministic simulated implementation.
  ///
  /// Must equal `evidence.simulated`; a release build refuses a simulated
  /// capability before it is resolved.
  final bool isSimulated;

  /// The capability evidence vocabulary owned by T014.
  final CapabilityEvidence evidence;

  /// Feature tokens the adapter supports, in the caller's order.
  ///
  /// The set is an unmodifiable copy; no caller can mutate a registered
  /// descriptor after startup.
  final Set<String> supportedFeatures;

  static final RegExp _versionPattern = RegExp(r'^[1-9][0-9]*(\.[0-9]+)*$');
  static final RegExp _unsafeFeaturePattern = RegExp(r'[\s\x00-\x1F\x7F]');
  static const int _maxFeatureLength = 64;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CapabilityDescriptor &&
            other.kind == kind &&
            other.adapterId == adapterId &&
            other.version == version &&
            other.isSimulated == isSimulated &&
            other.evidence == evidence &&
            _setsEqual<String>(other.supportedFeatures, supportedFeatures);
  }

  @override
  int get hashCode {
    return Object.hash(
      kind,
      adapterId,
      version,
      isSimulated,
      evidence,
      Object.hashAllUnordered(supportedFeatures),
    );
  }

  /// Redacted identity for logs.
  ///
  /// The adapter id and feature tokens are omitted; callers that need them read
  /// the fields explicitly.
  @override
  String toString() {
    return 'CapabilityDescriptor(kind: ${kind.name}, version: $version, '
        'simulated: $isSimulated, features: ${supportedFeatures.length})';
  }
}

bool _setsEqual<T>(Set<T> a, Set<T> b) {
  return a.length == b.length && a.containsAll(b);
}
