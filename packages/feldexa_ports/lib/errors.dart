// Public entrypoint for the T014 error taxonomy.
//
// The normative declarations live in `src/errors.dart`; this file exposes them
// without making consumers import `src/`. T013's `feldexa_ports.dart` barrel
// re-exports the same declarations and must not create a second copy.
library;

export 'src/errors.dart';
