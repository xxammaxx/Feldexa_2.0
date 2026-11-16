// Feldexa SIMULATED adapters (T028).
//
// This package is the Web development surface's substitute for Android
// platform capabilities. Every adapter returns `CapabilityEvidence.simulated`;
// there is no unlabelled path (`contracts/ports.md` §1; plan §Architecture
// Decisions 9). The Android registry must never import this package, and a
// browser run is never Android runtime evidence (FR-087/FR-088).
//
// The six ports implemented here are import, page rasterization, OCR, secure
// storage, PDF export, and delivery. Clock, ids, lifecycle, and diagnostics
// remain the Web registry's T023/T027 composition seam; this package only
// consumes a deterministic input context.
library;

export 'src/simulated_backend.dart';
export 'src/simulated_context.dart';
export 'src/simulated_contract.dart';
export 'src/simulated_delivery_adapter.dart';
export 'src/simulated_export_adapter.dart';
export 'src/simulated_fixtures.dart';
export 'src/simulated_import_adapter.dart';
export 'src/simulated_ocr_adapter.dart';
export 'src/simulated_raster_adapter.dart';
export 'src/simulated_store_adapter.dart';
