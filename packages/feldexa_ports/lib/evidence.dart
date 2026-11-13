// Public entrypoint for the T014 capability evidence vocabulary.
//
// The normative declaration lives in `src/evidence.dart`; this file exposes it
// without making consumers import `src/`. T013's `feldexa_ports.dart` barrel
// re-exports the same declaration and must not create a second copy.
library;

export 'src/evidence.dart';
