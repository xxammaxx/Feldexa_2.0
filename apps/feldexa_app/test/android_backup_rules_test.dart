@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _manifestPath = 'android/app/src/main/AndroidManifest.xml';
const _rulesPath = 'android/app/src/main/res/xml/data_extraction_rules.xml';
const _domains = <String>[
  'root',
  'file',
  'database',
  'sharedpref',
  'external',
  'device_root',
  'device_file',
  'device_database',
  'device_sharedpref',
];
const _transferSections = <String>['cloud-backup', 'device-transfer'];

void main() {
  final appRoot = _findAppRoot();
  final manifest = File('${appRoot.path}/$_manifestPath').readAsStringSync();
  final rules = File('${appRoot.path}/$_rulesPath').readAsStringSync();

  test('manifest disables backup and points at the extraction rules', () {
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
  });

  test('every transfer mode excludes every app data domain', () {
    for (final sectionName in _transferSections) {
      final section = _section(rules, sectionName);
      expect(section, isNotNull, reason: '$sectionName section is missing');

      for (final domain in _domains) {
        expect(
          section,
          contains('<exclude domain="$domain" path="." />'),
          reason: '$sectionName does not exclude domain $domain',
        );
      }
    }
  });

  test('cross-platform transfer is not declared without an iOS identity', () {
    // Android's BackupEligibilityRules only allows cross-platform transfer when
    // allowBackup is true and platform-specific-params exist for a matching iOS
    // app. Feldexa has no iOS identity, so allowBackup=false makes the mode
    // ineligible; an incomplete section is not a valid opt-in and is omitted.
    expect(rules, isNot(contains('<cross-platform-transfer')));
    expect(rules, isNot(contains('<platform-specific-params')));
  });
}

String? _section(String xml, String name) {
  final match = RegExp(
    '<$name\\b[^>]*>(.*?)</$name>',
    dotAll: true,
  ).firstMatch(xml);
  return match?.group(0);
}

Directory _findAppRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/$_manifestPath').existsSync()) {
      return dir;
    }

    final nested = Directory('${dir.path}/apps/feldexa_app');
    if (File('${nested.path}/$_manifestPath').existsSync()) {
      return nested;
    }

    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'Could not locate apps/feldexa_app from ${Directory.current.path}',
      );
    }
    dir = parent;
  }
}
