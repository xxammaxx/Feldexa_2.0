// T148 fail-closed import composition for non-Android targets.
//
// Owner: `apps/feldexa_app/lib/features/start/import_runtime_unavailable.dart`
// (T148). This is the default branch of `import_runtime.dart` and also the
// explicit `dart.library.js_interop` branch. It imports no adapter package and
// constructs no simulated substitute.
//
// The app's Web surface is a development surface, not a production import
// target. An import attempt therefore fails closed with the typed
// `UnsupportedOperationException`, which the existing `ImportFlow` maps to the
// committed German `IMP-005` text; no document, draft, or source is created.
// This is not an evidence claim of any class.

import 'package:feldexa_ports/feldexa_ports.dart';

import 'import_runtime.dart';

/// Builds the fail-closed non-Android composition.
ImportRuntime createImportRuntime() {
  return ImportRuntime(
    importPort: const _UnavailableDocumentImportPort(),
    readSourceBytes: (String documentId) async => null,
  );
}

final class _UnavailableDocumentImportPort implements DocumentImportPort {
  const _UnavailableDocumentImportPort();

  static final CapabilityDescriptor _descriptor = CapabilityDescriptor(
    kind: CapabilityKind.documentImport,
    adapterId: 'app.import.unavailable.v1',
    version: '1',
    isSimulated: false,
    evidence: CapabilityEvidence(
      evidenceClass: EvidenceClass.none,
      adapterId: 'app.import.unavailable.v1',
    ),
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  @override
  Future<ImportedSource> pickAndImport(ImportRequest request) {
    throw UnsupportedOperationException();
  }

  @override
  Future<SourceIntegrity> verifySource(String sourceId) {
    throw UnsupportedOperationException();
  }
}
