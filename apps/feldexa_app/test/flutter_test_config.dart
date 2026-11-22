// Shared Flutter test bootstrap for the app's host-VM tests.
//
// T086C adds one production-like startup step: the FLD-001 text-fit
// measurement reads the bundled `assets/fonts/metrics.json` advance table
// (`initializeFieldTextMeasure`), exactly as `main()` does before `runApp`.
// Loading it here means every app test measures with the same Noto Sans
// metrics the export layout uses, instead of silently running with the
// measurement disabled or with a test-font approximation.
//
// Evidence class: NONE. This file only wires state; it makes no Android,
// device, screen-reader, or visual claim.

import 'dart:async';

import 'package:feldexa_app/features/fill/field_text_fit.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // A missing or unreadable table degrades to "no FLD-001 warning"; it must
  // never fail a host test that does not care about overflow.
  await initializeFieldTextMeasure();
  await testMain();
}
