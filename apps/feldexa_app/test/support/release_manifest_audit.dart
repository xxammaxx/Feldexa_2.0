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
// The checks parse the XML rather than matching file substrings: each
// `uses-permission`/component is identified by its `android:name` element and
// its own `tools:node="remove"` attribute. A merge of the main manifest and the
// release overlay is then simulated element by element, so a plain INTERNET
// entry in the release overlay cannot be hidden by an unrelated remove entry.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

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

const String _androidName = 'android:name';
const String _toolsNode = 'tools:node';

String? _nameOf(XmlElement element) => element.getAttribute(_androidName);

bool _removes(XmlElement element) =>
    element.getAttribute(_toolsNode) == 'remove';

List<XmlElement> _permissions(XmlDocument document) => document.rootElement
    .findElements('uses-permission')
    .toList(growable: false);

Set<String> _permissionNames(XmlDocument document) =>
    _permissions(document).map(_nameOf).whereType<String>().toSet();

/// Simulates `tools:node="remove"`/normal merging of two source manifests.
Set<String> _mergePermissionNames(XmlDocument main, XmlDocument release) {
  final Set<String> effective = _permissionNames(main).toSet();
  for (final XmlElement permission in _permissions(release)) {
    final String? name = _nameOf(permission);
    if (name == null) {
      continue;
    }
    if (_removes(permission)) {
      effective.remove(name);
    } else {
      effective.add(name);
    }
  }
  return effective;
}

/// Component tag + `android:name` identities merged the same way.
Set<String> _mergeComponents(XmlDocument main, XmlDocument release) {
  Set<String> collect(XmlDocument document) {
    final Set<String> names = <String>{};
    for (final XmlElement element
        in document.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'service' && element.name.local != 'receiver') {
        continue;
      }
      final String? name = _nameOf(element);
      if (name != null) {
        names.add('${element.name.local}|$name');
      }
    }
    return names;
  }

  final Set<String> effective = collect(main);
  for (final XmlElement element
      in release.descendants.whereType<XmlElement>()) {
    if (element.name.local != 'service' && element.name.local != 'receiver') {
      continue;
    }
    final String? name = _nameOf(element);
    if (name == null) {
      continue;
    }
    final String key = '${element.name.local}|$name';
    if (_removes(element)) {
      effective.remove(key);
    } else {
      effective.add(key);
    }
  }
  return effective;
}

/// True when the release overlay contains exactly one [tag]/[name] element
/// and that element removes the merged contribution.
void _expectRemoval(XmlDocument release, String tag, String name) {
  final List<XmlElement> matches = release.descendants
      .whereType<XmlElement>()
      .where((XmlElement e) => e.name.local == tag && _nameOf(e) == name)
      .toList(growable: false);
  expect(
    matches,
    isNotEmpty,
    reason: 'release overlay has no <$tag android:name="$name">',
  );
  expect(
    matches.every(_removes),
    isTrue,
    reason: 'release overlay keeps a non-remove <$tag android:name="$name">',
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
  final File mainFile = File('$base/main/AndroidManifest.xml');
  final File debugFile = File('$base/debug/AndroidManifest.xml');
  final File profileFile = File('$base/profile/AndroidManifest.xml');
  final File releaseFile = File('$base/release/AndroidManifest.xml');
  for (final File file in <File>[
    mainFile,
    debugFile,
    profileFile,
    releaseFile,
  ]) {
    expect(file.existsSync(), isTrue, reason: 'missing ${file.path}');
  }
  final XmlDocument main = XmlDocument.parse(mainFile.readAsStringSync());
  final XmlDocument debug = XmlDocument.parse(debugFile.readAsStringSync());
  final XmlDocument profile = XmlDocument.parse(profileFile.readAsStringSync());
  final XmlDocument release = XmlDocument.parse(releaseFile.readAsStringSync());

  int checks = 0;

  // Main manifest: no network permissions at all.
  final Set<String> mainPermissions = _permissionNames(main);
  for (final String forbidden in <String>[
    'android.permission.INTERNET',
    'android.permission.ACCESS_NETWORK_STATE',
  ]) {
    expect(
      mainPermissions.contains(forbidden),
      isFalse,
      reason: 'main manifest must not declare $forbidden',
    );
    checks++;
  }

  // Release overlay removes each contribution as its own element; then the
  // simulated merge must contain neither permission.
  for (final String permission in <String>[
    'android.permission.INTERNET',
    'android.permission.ACCESS_NETWORK_STATE',
  ]) {
    _expectRemoval(release, 'uses-permission', permission);
    checks++;
  }
  final Set<String> effectivePermissions = _mergePermissionNames(main, release);
  for (final String forbidden in <String>[
    'android.permission.INTERNET',
    'android.permission.ACCESS_NETWORK_STATE',
  ]) {
    expect(
      effectivePermissions.contains(forbidden),
      isFalse,
      reason: 'merged main+release manifest still declares $forbidden',
    );
    checks++;
  }

  // DataTransport components: explicit remove elements and an empty merged
  // component set.
  const List<String> transportComponents = <String>[
    'com.google.android.datatransport.runtime.backends.TransportBackendDiscovery',
    'com.google.android.datatransport.runtime.scheduling.jobscheduling.JobInfoSchedulerService',
    'com.google.android.datatransport.runtime.scheduling.jobscheduling.AlarmManagerSchedulerBroadcastReceiver',
  ];
  for (final String component in transportComponents) {
    final String tag =
        component.endsWith('AlarmManagerSchedulerBroadcastReceiver')
        ? 'receiver'
        : 'service';
    _expectRemoval(release, tag, component);
    checks++;
  }
  final Set<String> mergedComponents = _mergeComponents(main, release);
  for (final String component in transportComponents) {
    expect(
      mergedComponents.where((String key) => key.endsWith('|$component')),
      isEmpty,
      reason: 'merged manifest still declares $component',
    );
    checks++;
  }

  // Debug/profile keep INTERNET for the Flutter tool; the production and
  // release documents never become debuggable or permit cleartext, and never
  // carry the debug import channel or a synthetic fixture path.
  expect(_permissionNames(debug), contains('android.permission.INTERNET'));
  expect(_permissionNames(profile), contains('android.permission.INTERNET'));
  checks += 2;
  for (final XmlDocument document in <XmlDocument>[main, release]) {
    for (final XmlElement element
        in document.descendants.whereType<XmlElement>()) {
      for (final XmlAttribute attribute in element.attributes) {
        final String local = attribute.name.local;
        final String value = attribute.value;
        if (local == 'debuggable') {
          expect(value, isNot('true'), reason: 'debuggable manifest');
          checks++;
        }
        if (local == 'usesCleartextTraffic') {
          expect(value, isNot('true'), reason: 'cleartext traffic enabled');
          checks++;
        }
        for (final String forbidden in <String>[
          'de.feldexa/test',
          'de.feldexa.test',
          'assets/fixtures',
        ]) {
          expect(
            value.contains(forbidden),
            isFalse,
            reason: 'manifest attribute carries $forbidden',
          );
          checks++;
        }
      }
    }
  }

  // Synthetic fixtures stay out of the packaged asset list. Parse the YAML so
  // comments and an inline `assets: [...]` list are handled correctly.
  final File pubspec = File('${root.path}/apps/feldexa_app/pubspec.yaml');
  final YamlMap pubspecYaml = loadYaml(pubspec.readAsStringSync()) as YamlMap;
  final YamlMap flutter = pubspecYaml['flutter'] as YamlMap;
  final Object? assets = flutter['assets'];
  final List<String> assetEntries = assets is YamlList
      ? assets.map((dynamic entry) => entry.toString()).toList(growable: false)
      : const <String>[];
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
    'releaseRemovals=5:effectiveNetworkPermissions=0:'
    'effectiveDataTransport=0:fixtureAssets=0',
  );
}
