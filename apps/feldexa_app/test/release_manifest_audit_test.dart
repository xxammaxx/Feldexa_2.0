// T138 host lane for the release-manifest audit (SC-007/SC-008;
// FR-078/FR-079/FR-080; CHK020). Evidence class: `NONE`.
//
// The same `runReleaseManifestAudit` function is called from
// `integration_test/network_observation_test.dart`; this wrapper makes it part
// of the ordinary app suite (gate check 5) where the repository tree is
// available.
//
// The audit reads the manifest files from the repository tree through
// `dart:io` (it starts at `Directory.current`), so it is a host-VM suite. The
// tag says so; without it the browser lane picks the file up and fails with
// `Unsupported operation: _Namespace` instead of skipping it.

@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/release_manifest_audit.dart';

void main() {
  test('release manifests carry no debug or fixture entries', () {
    runReleaseManifestAudit();
  });
}
