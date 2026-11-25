// Feldexa export package public surface.
//
// Owner of the export contract models: T022. The package builds and validates
// deterministic export plans and records one export attempt; it contains no
// platform, Flutter, file-system, or PDF-engine imports.
//
// Shared export stages: `layout.dart` (T103, text/checkbox/signature layout and
// the pure-Dart font metrics), `preflight.dart` (T113, the §1 step [1]
// preflight), and `plan_builder.dart` (T102, canonical plan assembly).
library;

export 'src/layout.dart';
export 'src/model/export_artifact.dart';
export 'src/model/export_plan.dart';
export 'src/plan_builder.dart';
export 'src/preflight.dart';
