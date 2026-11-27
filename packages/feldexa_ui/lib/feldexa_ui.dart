/// Shared Feldexa UI widgets and semantics.
///
/// The `SIMULATED` evidence surface is deliberately part of the production
/// package: Web development may substitute platform behavior, but every
/// substituted surface must stay visibly and semantically labeled (FR-087;
/// constitution Principle II).
library;

export 'src/field_geometry.dart';
export 'src/field_overlay.dart';
export 'src/field_selection.dart';
export 'src/provenance_badge.dart';
export 'src/simulated_banner.dart';
export 'src/uncertainty_badge.dart';
