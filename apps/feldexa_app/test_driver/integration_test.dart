// Flutter web driver entrypoint for the SIMULATED browser integration tests.
//
// `tools/gate.sh` check 7 runs the `integration_test/web_*_test.dart` suites
// through `flutter drive` against a real Chrome; this file is the driver side
// of that pair. It only forwards the `integration_test` results, so a suite
// that never reports (compilation failure, renderer hang) is a failure rather
// than a silent pass. An explicitly `skip:`-marked suite reports success with
// zero failures; the four drive targets do not skip today, and a future skip
// must be reviewed instead of trusted.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
