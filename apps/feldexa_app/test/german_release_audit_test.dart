@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/package_root.dart';

/// T133 release-only German-string audit (SC-014; FR-087; CHK023/CHK025;
/// constitution Principles II and VIII).
///
/// T029 (`german_strings_test.dart`) pins the error catalog, the German ARB,
/// and the generated localization text to each other. This audit is the
/// release-surface check the T029 comment reserves for T133: the release
/// locale set must contain German only, every translatable ARB value must be
/// German apart from the mandated `SIMULATED` token and a documented
/// allowlist of proper nouns and units, and `SIMULATED` must stay byte-exact
/// wherever it is required.
///
/// This is a host-VM check. It produces no `SIMULATED`, `EMULATOR`, or
/// `DEVICE` evidence.
void main() {
  final File arbFile = File('${packageRoot.path}/lib/l10n/app_de.arb');
  final Map<String, dynamic> arb =
      jsonDecode(arbFile.readAsStringSync()) as Map<String, dynamic>;

  /// Non-German tokens that are deliberately not translated: product and
  /// platform names, the mandatory simulated-result label, and fixed units.
  /// Every other ASCII word must come from German UI text.
  const Set<String> allowedForeignTokens = <String>{
    'SIMULATED',
    'PDF',
    'PDFium',
    'Feldexa',
    'Android',
    'MiB',
    'Bytes',
  };

  /// English UI words that must never appear untranslated in a release string.
  /// Deliberately excludes words that are also German (`in`, `die`, `ist`,
  /// `was`, ...). Matched case-insensitively after placeholders are removed.
  const Set<String> englishWords = <String>{
    'the',
    'and',
    'please',
    'error',
    'errors',
    'failed',
    'failure',
    'file',
    'files',
    'cancel',
    'settings',
    'loading',
    'success',
    'successful',
    'invalid',
    'required',
    'save',
    'saved',
    'delete',
    'deleted',
    'open',
    'opened',
    'close',
    'closed',
    'this',
    'that',
    'with',
    'without',
    'your',
    'you',
    'cannot',
    'could',
    'from',
    'user',
    'page',
    'pages',
    'field',
    'fields',
    'document',
    'documents',
    'template',
    'templates',
    'storage',
    'import',
    'share',
    'print',
    'retry',
    'warning',
    'title',
    'name',
    'date',
    'signature',
  };

  // Strip only simple `{name}` placeholders. ICU plural/select skeletons are
  // deliberately not stripped: their branch texts (`=0{...}`, `one{...}`,
  // `other{...}`) are user-visible German text and must be scanned too.
  String withoutPlaceholders(String value) =>
      value.replaceAll(RegExp(r'\{[A-Za-z_][A-Za-z0-9_]*\}'), '');

  test('release locale set is German-only', () {
    final List<String> arbFiles =
        Directory('${packageRoot.path}/lib/l10n')
            .listSync()
            .whereType<File>()
            .map((File file) => file.uri.pathSegments.last)
            .where((String name) => name.endsWith('.arb'))
            .toList()
          ..sort();
    expect(arbFiles, <String>[
      'app_de.arb',
    ], reason: 'the release surface must ship exactly one German ARB file');

    final String generated = File(
      '${packageRoot.path}/lib/l10n/app_localizations.dart',
    ).readAsStringSync();
    expect(
      generated,
      contains(
        "static const List<Locale> supportedLocales = <Locale>[Locale('de')];",
      ),
      reason: 'the generated localization class must support German only',
    );

    final String app = File('${packageRoot.path}/lib/main.dart')
        .readAsStringSync();
    expect(app, contains("locale: const Locale('de')"));
    expect(
      app,
      contains('supportedLocales: AppLocalizations.supportedLocales'),
    );
  });

  test('every translatable ARB value is German or allowlisted', () {
    int checked = 0;
    int allowlistedTokens = 0;
    final RegExp asciiWord = RegExp('[A-Za-z]+');

    for (final MapEntry<String, dynamic> entry in arb.entries) {
      if (entry.key.startsWith('@')) {
        continue;
      }
      final dynamic value = entry.value;
      if (value is! String) {
        fail('${entry.key} must be a translatable string');
      }
      checked++;
      final String stripped = withoutPlaceholders(value);
      for (final RegExpMatch match in asciiWord.allMatches(stripped)) {
        final String word = match.group(0)!;
        if (allowedForeignTokens.contains(word)) {
          allowlistedTokens++;
          continue;
        }
        expect(
          englishWords,
          isNot(contains(word.toLowerCase())),
          reason: '${entry.key} contains the untranslated English word "$word"',
        );
      }
    }

    expect(checked, greaterThan(200));
    expect(
      allowlistedTokens,
      greaterThan(0),
      reason: 'the German surface must use at least one allowlisted token',
    );
  });

  test('SIMULATED is exact and allowlisted everywhere', () {
    final List<String> simulatedValues = <String>[
      arb['simulatedToken'] as String,
      arb['simulatedLogPrefix'] as String,
      arb['simulatedBanner'] as String,
    ];
    expect(simulatedValues[0], 'SIMULATED');
    expect(simulatedValues[1], '[SIMULATED]');
    expect(simulatedValues[2], startsWith('SIMULATED'));

    final RegExp simulatedWord = RegExp(
      r'[Ss][Ii][Mm][Uu][Ll][Aa][Tt][Ee][Dd]',
    );
    for (final MapEntry<String, dynamic> entry in arb.entries) {
      if (entry.key.startsWith('@')) {
        continue;
      }
      final String value = entry.value as String;
      for (final RegExpMatch match in simulatedWord.allMatches(value)) {
        expect(
          match.group(0),
          'SIMULATED',
          reason:
              '${entry.key} must keep the mandated token byte-exact; '
              'only the uppercase SIMULATED label is allowlisted',
        );
      }
    }

    final String generated = File(
      '${packageRoot.path}/lib/l10n/app_localizations_de.dart',
    ).readAsStringSync();
    for (final String key in arb.keys) {
      if (key.startsWith('@')) {
        continue;
      }
      expect(
        generated,
        anyOf(contains('String get $key =>'), contains('String $key(')),
        reason: 'the generated German class must expose $key',
      );
    }
  });
}
