// Feldexa core: platform-independent model, geometry, value types, validation,
// and undo/redo.
//
// This package has no Flutter widget, rendering, file-system, or platform
// imports, so the same sources run on Android and Web and are testable on the
// host VM.
library;

export 'src/geometry/page_geometry.dart';
export 'src/geometry/rect.dart';
export 'src/model/canonical_json.dart';
export 'src/model/document.dart';
export 'src/model/durable_pointer.dart';
export 'src/model/field.dart';
export 'src/model/page_failure.dart';
export 'src/model/persistence.dart';
export 'src/model/template_origin.dart';
