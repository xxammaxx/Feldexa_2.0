// T138 host lane for the release-manifest audit (SC-007/SC-008;
// FR-078/FR-079/FR-080; CHK020). Evidence class: `NONE`.
//
// The same `runReleaseManifestAudit` function is called from
// `integration_test/network_observation_test.dart`; this wrapper makes it part
// of the ordinary app suite (gate check 5) where the repository tree is
// available.

import 'package:flutter_test/flutter_test.dart';

import 'support/release_manifest_audit.dart';

void main() {
  test('release manifests carry no debug or fixture entries', () {
    runReleaseManifestAudit();
  });
}
