// Flutter web driver entrypoint for the SIMULATED browser integration tests.
//
// `tools/gate.sh` check 7 runs the `integration_test/web_*_test.dart` suites
// through `flutter drive` against a real Chrome; this file is the driver side
// of that pair. It only forwards the `integration_test` results, so a suite
// that never reports (compilation failure, renderer hang, hidden skip) is a
// failure rather than a silent pass.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
