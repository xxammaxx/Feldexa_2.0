@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// T005 scaffold contract: German is the only release locale and the
/// generated localizations come from the committed German template ARB.
void main() {
  test('German is the only supported release locale', () {
    expect(AppLocalizations.supportedLocales, const <Locale>[Locale('de')]);
    expect(
      AppLocalizations.localizationsDelegates,
      contains(AppLocalizations.delegate),
    );
  });

  test('l10n.yaml points at the German template and committed output', () {
    final config = File('l10n.yaml').readAsStringSync();

    expect(config, contains('arb-dir: lib/l10n'));
    expect(config, contains('template-arb-file: app_de.arb'));
    expect(
      config,
      contains('output-localization-file: app_localizations.dart'),
    );
    expect(config, contains('nullable-getter: false'));
    expect(config, contains('format: true'));
  });

  test('app_de.arb is the only ARB file and declares the de locale', () {
    final arbFiles =
        Directory('lib/l10n')
            .listSync()
            .whereType<File>()
            .map((file) => file.path.split(Platform.pathSeparator).last)
            .where((name) => name.endsWith('.arb'))
            .toList()
          ..sort();

    expect(arbFiles, const <String>['app_de.arb']);

    final arb = jsonDecode(
      File('lib/l10n/app_de.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(arb['@@locale'], 'de');
    expect(arb['appTitle'], 'Feldexa');
    expect(arb['startTitle'], 'Meine Dokumente');
  });

  test('web host declares German as the document language', () {
    final indexHtml = File('web/index.html').readAsStringSync();
    final manifest = jsonDecode(
      File('web/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    expect(indexHtml, contains('<html lang="de">'));
    expect(manifest['lang'], 'de');
  });
}
