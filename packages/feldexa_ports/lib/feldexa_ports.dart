// Feldexa ports: the only permitted way for application and UI code to reach a
// platform capability (constitution Principles II and III).
//
// Owner: T013 for descriptors, ports, registry, and port-local DTOs; T014 for
// the error taxonomy and capability evidence vocabulary. This barrel re-exports
// the canonical public entrypoints `errors.dart` and `evidence.dart` and every
// T013 declaration. It deliberately does not re-export `feldexa_core` or
// `feldexa_export`: consumers import those packages directly for the canonical
// `Page`, `RevisionContent`, `StoredTemplate`, `ExportPlan`, and artifact
// types, which this package only consumes.
//
// No type re-exported here may be declared a second time. The ownership table
// in `specs/001-scanned-form-workflow/tasks.md` (Foundational Type Ownership)
// and `contracts/ports.md` §1 are normative.

library;

export 'errors.dart';
export 'evidence.dart';
export 'src/descriptor.dart';
export 'src/dto/delivery_dto.dart';
export 'src/dto/export_dto.dart';
export 'src/dto/import_dto.dart';
export 'src/dto/lifecycle_dto.dart';
export 'src/dto/ocr_dto.dart';
export 'src/dto/raster_dto.dart';
export 'src/dto/store_dto.dart';
export 'src/ports/clock_port.dart';
export 'src/ports/delivery_port.dart';
export 'src/ports/diagnostics_port.dart';
export 'src/ports/document_import_port.dart';
export 'src/ports/id_port.dart';
export 'src/ports/lifecycle_port.dart';
export 'src/ports/ocr_port.dart';
export 'src/ports/page_raster_port.dart';
export 'src/ports/pdf_export_port.dart';
export 'src/ports/secure_store_port.dart';
export 'src/registry.dart';
