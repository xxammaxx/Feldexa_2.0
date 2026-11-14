// T023 unsupported-compile-target adapter registry.
//
// Owner: `apps/feldexa_app/lib/platform/registry_unsupported.dart` (T023).
// Normative sources: constitution Principle II; plan §Architecture Decisions 8;
// `contracts/ports.md` §4.
//
// `registry.dart` selects this file when neither the `dart:io` nor the Web
// platform library is available, and tests use it to prove the fail-closed
// path. It exposes no adapter: every capability getter throws the canonical
// `PLT-001` `UnsupportedOperationException` instead of returning a substitute.
// It reports `hasSimulatedCapabilities: false` because it never registers a
// simulated adapter; it simply has no capability at all.

import 'package:feldexa_ports/feldexa_ports.dart';

import 'registry.dart';

/// A registry whose every capability is unsupported on this compile target.
final class UnsupportedAdapterRegistry implements AdapterRegistry {
  /// Creates the fail-closed registry.
  const UnsupportedAdapterRegistry();

  @override
  bool get isDevelopmentEnvironment => false;

  @override
  bool get hasSimulatedCapabilities => false;

  @override
  List<CapabilityDescriptor> get descriptors => const <CapabilityDescriptor>[];

  @override
  DocumentImportPort get import => _unsupported();

  @override
  PageRasterPort get raster => _unsupported();

  @override
  OcrPort get ocr => _unsupported();

  @override
  SecureStorePort get store => _unsupported();

  @override
  PdfExportPort get export => _unsupported();

  @override
  DeliveryPort get delivery => _unsupported();

  @override
  LifecyclePort get lifecycle => _unsupported();

  @override
  ClockPort get clock => _unsupported();

  @override
  IdPort get ids => _unsupported();

  @override
  DiagnosticsPort get diagnostics => _unsupported();

  static Never _unsupported() => throw UnsupportedOperationException();
}

/// Conditional-import entrypoint selected by `registry.dart` on an unsupported
/// target.
///
/// [adapters] is ignored: no adapter can make a capability supported when the
/// compile target cannot host it. The parameter keeps the entrypoint shape
/// identical across the three conditional files.
AdapterRegistry createPlatformRegistry(PlatformAdapterSet adapters) {
  return const UnsupportedAdapterRegistry();
}
