// T028 SIMULATED adapter evidence and descriptor constants.
//
// Every adapter in this package is a deterministic substitute for a platform
// capability that only exists on Android. The evidence class is therefore
// `EvidenceClass.simulated` for all six adapters, including page
// rasterization: browser rendering cannot produce Android runtime evidence
// (`contracts/ports.md` §1; constitution Principle II; FR-087/FR-088).
//
// The adapter ids are stable machine identifiers used by reports, structured
// logs, and the UI banner. The `simulatedReason` token identifies the whole
// package as fixture-backed; it is never a path, a fixture name, or content.
library;

import 'package:feldexa_ports/feldexa_ports.dart';

/// Package-wide reason token consumed by structured logs and reports.
const String simulatedReasonToken = 'web.simulated-adapter';

/// Adapter id for the fixture-backed import adapter.
const String simulatedImportAdapterId = 'web.sim.import.v1';

/// Adapter id for the deterministic page-raster adapter.
const String simulatedRasterAdapterId = 'web.sim.raster.v1';

/// Adapter id for the pre-authored OCR adapter.
const String simulatedOcrAdapterId = 'web.sim.ocr.v1';

/// Adapter id for the in-memory secure-store substitute.
const String simulatedStoreAdapterId = 'web.sim.storage.v1';

/// Adapter id for the preview-PDF export substitute.
const String simulatedExportAdapterId = 'web.sim.export.v1';

/// Adapter id for the simulated save/share/print hand-off.
const String simulatedDeliveryAdapterId = 'web.sim.delivery.v1';

/// Adapter contract version shared by the six T028 adapters.
const String simulatedAdapterVersion = '1';

/// Builds the SIMULATED evidence label for one adapter id.
///
/// This is the only evidence constructor used by the package. A caller cannot
/// upgrade the label: only the harness that actually executed an Android run
/// may attach `EMULATOR` or `DEVICE` (`contracts/ports.md` §1).
CapabilityEvidence simulatedEvidence(String adapterId) {
  return CapabilityEvidence.simulated(
    adapterId: adapterId,
    simulatedReason: simulatedReasonToken,
  );
}

/// Builds a complete descriptor for one simulated capability.
CapabilityDescriptor simulatedDescriptor({
  required CapabilityKind kind,
  required String adapterId,
  Iterable<String> supportedFeatures = const <String>[],
}) {
  return CapabilityDescriptor(
    kind: kind,
    adapterId: adapterId,
    version: simulatedAdapterVersion,
    isSimulated: true,
    evidence: simulatedEvidence(adapterId),
    supportedFeatures: supportedFeatures,
  );
}
