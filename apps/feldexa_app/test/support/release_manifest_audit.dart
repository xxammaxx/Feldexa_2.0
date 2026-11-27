// Shared T138 release-manifest audit (SC-007/SC-008; FR-078/FR-079/FR-080).
//
// Evidence class: `NONE` (host static check). The audit is exercised from two
// entry points so it runs both in the ordinary app suite (gate check 5) and in
// the T138 `integration_test/network_observation_test.dart` file:
//   * `test/release_manifest_audit_test.dart` — the host lane;
//   * `integration_test/network_observation_test.dart` — on the device the
//     repository tree is not mounted, so the function records
//     `MANIFEST_AUDIT:SKIPPED_ON_DEVICE` and returns without a false pass.
//
// It proves that the committed release manifest cannot carry debug or fixture
// entries: the main manifest requests no network permission, only the
// debug/profile overlays keep INTERNET for the Flutter tool, the release
// overlay removes INTERNET, ACCESS_NETWORK_STATE, and the three ML Kit
// DataTransport components, no manifest is debuggable or permits cleartext,
// the debug-only import channel never appears in manifest declarations, and no
// synthetic fixture directory is packaged as an asset. The committed checker's
// own negative controls (`check_release_manifest.sh --self-test`) must pass on
// the same tree.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Directory? _repoRoot() {
  Directory current = Directory.current;
  for (int i = 0; i < 5; i++) {
    final File marker = File(
      '${current.path}/apps/feldexa_app/android/app/src/main/AndroidManifest.xml',
    );
    if (marker.existsSync()) {
      return current;
    }
    if (current.parent.path == current.path) {
      break;
    }
    current = current.parent;
  }
  return null;
}

String _read(File file) => file.readAsStringSync();

void _expectAbsent(String text, String needle, String what) {
  expect(
    text.contains(needle),
    isFalse,
    reason: '$what must not contain $needle',
  );
}

/// Runs the complete release-manifest audit against the current tree.
void runReleaseManifestAudit({void Function(String)? marker}) {
  final void Function(String) emit = marker ?? debugPrint;
  final Directory? root = _repoRoot();
  if (root == null) {
    emit('MANIFEST_AUDIT:SKIPPED_ON_DEVICE');
    return;
  }
  final String base = '${root.path}/apps/feldexa_app/android/app/src';
  final File mainManifest = File('$base/main/AndroidManifest.xml');
  final File debugManifest = File('$base/debug/AndroidManifest.xml');
  final File profileManifest = File('$base/profile/AndroidManifest.xml');
  final File releaseManifest = File('$base/release/AndroidManifest.xml');
  for (final File file in <File>[
    mainManifest,
    debugManifest,
    profileManifest,
    releaseManifest,
  ]) {
    expect(file.existsSync(), isTrue, reason: 'missing ${file.path}');
  }
  final String mainText = _read(mainManifest);
  final String debugText = _read(debugManifest);
  final String profileText = _read(profileManifest);
  final String releaseText = _read(releaseManifest);

  int checks = 0;

  // Release capabilities: the main manifest has no network permission and the
  // release overlay removes the ML Kit DataTransport contributions.
  _expectAbsent(mainText, 'android.permission.INTERNET', 'main manifest');
  _expectAbsent(
    mainText,
    'android.permission.ACCESS_NETWORK_STATE',
    'main manifest',
  );
  checks += 2;
  for (final String permission in <String>[
    'android.permission.INTERNET',
    'android.permission.ACCESS_NETWORK_STATE',
  ]) {
    expect(
      releaseText.contains(permission) &&
          releaseText.contains('tools:node="remove"'),
      isTrue,
      reason: 'release overlay must remove $permission',
    );
    checks++;
  }
  for (final String component in <String>[
    'com.google.android.datatransport.runtime.backends.TransportBackendDiscovery',
    'com.google.android.datatransport.runtime.scheduling.jobscheduling.JobInfoSchedulerService',
    'com.google.android.datatransport.runtime.scheduling.jobscheduling.AlarmManagerSchedulerBroadcastReceiver',
  ]) {
    expect(
      releaseText.contains(component) &&
          releaseText.contains('tools:node="remove"'),
      isTrue,
      reason: 'release overlay must remove $component',
    );
    checks++;
  }

  // Debug/fixture entries must never appear in the production or release
  // manifest, and only the debug/profile overlays may carry INTERNET (the
  // Flutter tool needs it for hot reload).
  for (final String text in <String>[mainText, releaseText]) {
    for (final String forbidden in <String>[
      'android:debuggable="true"',
      'android:usesCleartextTraffic="true"',
      'de.feldexa/test',
      'de.feldexa.test',
      'assets/fixtures',
    ]) {
      _expectAbsent(text, forbidden, 'production/release manifest');
      checks++;
    }
  }
  expect(debugText.contains('android.permission.INTERNET'), isTrue);
  expect(profileText.contains('android.permission.INTERNET'), isTrue);
  checks += 2;

  // Synthetic fixtures stay out of the packaged asset list. Comments in the
  // pubspec explain the exclusion and are not asset entries.
  final File pubspec = File('${root.path}/apps/feldexa_app/pubspec.yaml');
  final String pubspecText = _read(pubspec);
  final int assetsStart = pubspecText.indexOf('\n  assets:');
  expect(assetsStart, greaterThanOrEqualTo(0));
  final String assetsSection = pubspecText.substring(assetsStart);
  final List<String> assetEntries = assetsSection
      .split('\n')
      .map((String line) => line.trim())
      .where((String line) => line.startsWith('- '))
      .map((String line) => line.substring(2).trim())
      .toList();
  expect(
    assetEntries.where((String entry) => entry.startsWith('assets/fixtures')),
    isEmpty,
    reason: 'packaged assets must not include the synthetic fixture tree',
  );
  checks++;

  // The committed checker's own negative controls must pass on this tree.
  final ProcessResult selfTest = Process.runSync('bash', <String>[
    'tools/android/check_release_manifest.sh',
    '--self-test',
  ], workingDirectory: root.path);
  expect(
    selfTest.exitCode,
    0,
    reason:
        'check_release_manifest.sh --self-test failed: '
        '${selfTest.stdout}${selfTest.stderr}',
  );
  expect(selfTest.stdout.toString().contains('SELF-TEST PASS'), isTrue);
  checks++;

  emit(
    'MANIFEST_AUDIT:PASS:checks=$checks:'
    'releaseRemovals=5:debugInternet=1:fixtureAssets=0',
  );
}
