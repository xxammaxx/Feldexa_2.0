// T013 adapter registry contract.
//
// Owner: `packages/feldexa_ports/lib/src/registry.dart` (T013).
// Normative source: `contracts/ports.md` §4.
//
// `AdapterRegistry` is an interface, never an implementation. The app
// bootstrap resolves exactly one registry per build:
//   * `registry_android.dart` — real adapters only;
//   * `registry_web.dart` — deterministic SIMULATED adapters where required;
//   * `registry_unsupported.dart` — throws `PLT-001` for every capability.
//
// In a release build, a registry that reports `hasSimulatedCapabilities` must
// fail fast with `SIM-001` before any capability is used.

import 'descriptor.dart';
import 'ports/clock_port.dart';
import 'ports/delivery_port.dart';
import 'ports/document_import_port.dart';
import 'ports/diagnostics_port.dart';
import 'ports/id_port.dart';
import 'ports/lifecycle_port.dart';
import 'ports/ocr_port.dart';
import 'ports/page_raster_port.dart';
import 'ports/pdf_export_port.dart';
import 'ports/secure_store_port.dart';

/// The single resolved set of platform capabilities for one build
/// (`contracts/ports.md` §4).
///
/// Every getter returns the adapter chosen by the build's registry. Consumers
/// never construct an adapter directly; the registry is the only composition
/// point.
abstract interface class AdapterRegistry {
  /// Picker, staging, and source verification.
  DocumentImportPort get import;

  /// Page geometry and raster rendering.
  PageRasterPort get raster;

  /// On-device text recognition.
  OcrPort get ocr;

  /// Encrypted document and template store.
  SecureStorePort get store;

  /// Plan validation and flattened PDF export.
  PdfExportPort get export;

  /// Save, share, and print hand-off.
  DeliveryPort get delivery;

  /// Application lifecycle signals.
  LifecyclePort get lifecycle;

  /// UTC wall clock.
  ClockPort get clock;

  /// UUIDv4 and idempotency-key generation.
  IdPort get ids;

  /// Content-free on-device diagnostics.
  DiagnosticsPort get diagnostics;

  /// Whether this registry was selected for the Web development surface.
  bool get isDevelopmentEnvironment;

  /// Whether any registered capability is simulated.
  ///
  /// A release build must refuse this registry with `SIM-001`.
  bool get hasSimulatedCapabilities;

  /// One descriptor per capability, in [CapabilityKind] declaration order.
  List<CapabilityDescriptor> get descriptors;
}
