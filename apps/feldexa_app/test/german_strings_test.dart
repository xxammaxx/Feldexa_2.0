@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:feldexa_app/l10n/app_localizations_de.dart';
import 'package:flutter_test/flutter_test.dart';

/// T029 German string contract (FR-090, SC-014; corrected
/// `contracts/error-catalog.de.md`).
///
/// The catalog is the source of truth. This host-VM test parses it and compares
/// every user-facing code row, label, dialog, and accessibility template with
/// the German ARB and the committed generated localization code. It produces no
/// `SIMULATED`, `EMULATOR`, or `DEVICE` evidence.
const String _catalogPath =
    '../../specs/001-scanned-form-workflow/contracts/error-catalog.de.md';
const String _arbPath = 'lib/l10n/app_de.arb';
const String _generatedPath = 'lib/l10n/app_localizations_de.dart';

/// Non-code catalog items use the semantic ARB keys below. `appTitle` is the
/// T005 shell title and is documented as the one key not defined in the
/// catalog; every other key maps to a catalog label, dialog, durability state,
/// action, or accessibility fragment.
///
/// T031: `startupRecoveryIncomplete` and `startupRecoveryIncompleteRecovery`
/// are the German notice and guidance for a timed-out, thrown, or degraded
/// startup sweep. Owner decision 2026-11-17 added them as
/// `contracts/error-catalog.de.md` §8 rows ("Startup recovery incomplete" and
/// its guidance); the section-8 assertion below fails if the catalog text and
/// the ARB text diverge.
const Set<String> _nonCodeArbKeys = <String>{
  'startupRecoveryIncomplete',
  'startupRecoveryIncompleteRecovery',
  'a11yCheckbox',
  'a11yCheckboxChecked',
  'a11yCheckboxUnchecked',
  'a11yFieldConflict',
  'a11yFieldOverlay',
  'a11yFieldStatusConfirmed',
  'a11yFieldStatusSelfCreated',
  'a11yFieldStatusSuggestion',
  'a11yFieldUncertain',
  'a11yFieldValueEmpty',
  'a11yFieldValueFilled',
  'a11yPageNavigation',
  'a11ySignature',
  'a11ySignatureSigned',
  'a11ySignatureUnsigned',
  'a11ySuggestion',
  'a11yZoom',
  'actionCheckStorage',
  'actionRetry',
  'actionUnderstood',
  'appTitle',
  'deleteDocumentDialog',
  'deleteTemplateDialog',
  'deletionConfirmation',
  'documentsGroup',
  'durabilityClean',
  'durabilityRecoveryFallback',
  'durabilitySaveFailed',
  'durabilitySaved',
  'durabilitySaving',
  'durabilityUnsaved',
  'emptyDocuments',
  'emptyTemplates',
  'exportAction',
  'exportSuccess',
  'fieldCount',
  'fillAction',
  'importAction',
  'lastEdited',
  'pageAnalysisAnalyzing',
  'pageAnalysisAnalyzingHint',
  'pageAnalysisComplete',
  'pageAnalysisCompleteHint',
  'pageAnalysisFailed',
  'pageAnalysisFailedHint',
  'pageAnalysisPending',
  'pageAnalysisPendingHint',
  'preExportEmptyFields',
  'preExportUnreviewedSuggestions',
  'previewFooter',
  'priv001',
  'reviewAction',
  'saveNow',
  'simulatedBanner',
  'simulatedBannerContext',
  'simulatedExportFooterContext',
  'simulatedLogPrefix',
  'simulatedStorageContext',
  'simulatedToken',
  'startTitle',
  'statusDraft',
  'statusExportReady',
  'statusUnreadable',
  'suggestionsLabel',
  // Issue #217 Phase B2 review-panel UI keys. The error catalog documents the
  // review surfaces semantically in §3 of editor-interactions.md; these keys
  // carry the panel's visible labels/actions and are not error-catalog codes.
  'suggestionEmpty',
  'suggestionAllReviewed',
  'suggestionOpenCount',
  'suggestionFieldCount',
  'suggestionReviewProgress',
  'suggestionRowFallback',
  'suggestionFieldLabel',
  'suggestionPage',
  'suggestionPosition',
  'suggestionConfidence',
  'suggestionUncertain',
  'suggestionConflict',
  'suggestionTypeText',
  'suggestionTypeNumber',
  'suggestionTypeDate',
  'suggestionTypeCheckbox',
  'suggestionTypeMultiline',
  'suggestionTypeSignature',
  'suggestionConfirmAction',
  'suggestionRejectAction',
  'suggestionUndoAction',
  'templateEditorHint',
  'templateLabel',
  'templateNewVersionSaved',
  'templateSaveAction',
  'templateVersionLabel',
  'templatesGroup',
  'unsavedBadge',
  'unsavedRiskBanner',
};

/// German quotes wrap every catalog text. The catalog also nests German quotes
/// inside a sentence (deletion dialogs and the unsaved banner), so the match is
/// deliberately greedy from the first opening to the last closing quote.
String? _quoted(String cell) {
  final int start = cell.indexOf('„');
  final int end = cell.lastIndexOf('“');
  if (start < 0 || end <= start) {
    return null;
  }
  return cell.substring(start + 1, end);
}

List<String> _cells(String line) {
  final String trimmed = line.trim();
  return trimmed
      .substring(1, trimmed.length - 1)
      .split('|')
      .map((String cell) => cell.trim())
      .toList();
}

final class _CatalogRow {
  const _CatalogRow({
    required this.code,
    required this.message,
    required this.recovery,
  });

  final String code;
  final String? message;
  final String? recovery;
}

/// Every catalog table row that carries a stable code, in document order.
List<_CatalogRow> _catalogRows(String catalog) {
  final List<_CatalogRow> rows = <_CatalogRow>[];
  for (final String line in catalog.split('\n')) {
    if (!line.startsWith('|')) {
      continue;
    }
    final List<String> cells = _cells(line);
    if (cells.length < 3) {
      continue;
    }
    final RegExpMatch? match = RegExp(r'^`([A-Z]{2,6}-\d{3})`$')
        .firstMatch(cells[0]);
    if (match == null) {
      continue;
    }
    rows.add(
      _CatalogRow(
        code: match.group(1)!,
        message: _quoted(cells[2]),
        recovery: cells.length > 3 ? _quoted(cells[3]) : null,
      ),
    );
  }
  return rows;
}

/// Catalog codes are stable identifiers, not ARB keys: gen-l10n requires valid
/// Dart method names, so `IMP-007` becomes `imp007`. The catalog reuses
/// `SAVE-001` for the export no-space row; that second occurrence gets the
/// `save001Export` suffix.
String _catalogKey(String code, int occurrence) {
  final String base = code.toLowerCase().replaceAll('-', '');
  return occurrence == 1 ? base : '${base}Export';
}

Map<String, dynamic> _readArb() {
  return jsonDecode(File(_arbPath).readAsStringSync()) as Map<String, dynamic>;
}

Iterable<String> _messageKeys(Map<String, dynamic> arb) {
  return arb.keys.where((String key) => !key.startsWith('@'));
}

List<String> _tableCellsInSection(String catalog, String sectionPrefix) {
  final List<String> lines = catalog.split('\n');
  final int start = lines.indexWhere(
    (String line) => line.startsWith(sectionPrefix),
  );
  if (start < 0) {
    return const <String>[];
  }
  final List<String> rows = <String>[];
  for (final String line in lines.skip(start + 1)) {
    if (line.startsWith('## ')) {
      break;
    }
    if (line.startsWith('|')) {
      rows.add(line);
    }
  }
  return rows;
}

/// The complete catalog-to-ARB key mapping: code-derived keys plus the
/// documented semantic keys for non-code items.
Set<String> _expectedKeys(String catalog) {
  final Set<String> keys = <String>{..._nonCodeArbKeys};
  final Map<String, int> seen = <String, int>{};
  for (final _CatalogRow row in _catalogRows(catalog)) {
    if (row.message == null) {
      continue;
    }
    final int occurrence = (seen[row.code] ?? 0) + 1;
    seen[row.code] = occurrence;
    final String key = _catalogKey(row.code, occurrence);
    keys.add(key);
    if (row.recovery != null) {
      keys.add('${key}Recovery');
    }
  }
  return keys;
}

String? _lineContaining(String catalog, String needle) {
  for (final String line in catalog.split('\n')) {
    if (line.contains(needle)) {
      return line;
    }
  }
  return null;
}

void main() {
  late String catalog;
  late Map<String, dynamic> arb;

  setUpAll(() {
    catalog = File(_catalogPath).readAsStringSync();
    arb = _readArb();
  });

  test('ARB and corrected catalog agree on every coded message', () {
    final Map<String, int> seen = <String, int>{};
    var checked = 0;

    for (final _CatalogRow row in _catalogRows(catalog)) {
      if (row.message == null) {
        continue; // IMP-000, DEL-001, REC-004, and developer-only codes.
      }
      final int occurrence = (seen[row.code] ?? 0) + 1;
      seen[row.code] = occurrence;
      final String key = _catalogKey(row.code, occurrence);

      expect(
        arb[key],
        row.message,
        reason: '$key must carry the exact ${row.code} German message',
      );
      if (row.recovery != null) {
        expect(
          arb['${key}Recovery'],
          row.recovery,
          reason: '${key}Recovery must carry the exact ${row.code} recovery',
        );
      }
      checked++;
    }

    expect(
      checked,
      greaterThanOrEqualTo(34),
      reason: 'all user-facing coded catalog rows must be covered',
    );
    for (final String code in <String>[
      'IMP-001',
      'IMP-006',
      'IMP-007',
      'PAGE-001',
      'REC-001',
      'SAVE-001',
      'SAVE-007',
      'EXP-001',
      'EXP-006',
      'TPL-001',
      'DATE-001',
      'NUM-001',
      'FLD-001',
      'FLD-003',
    ]) {
      expect(
        arb.keys,
        contains(code.toLowerCase().replaceAll('-', '')),
        reason: '$code has no German ARB message',
      );
    }
  });

  test('catalog and ARB key mapping is complete in both directions', () {
    final Set<String> actual = _messageKeys(arb).toSet();
    final Set<String> expected = _expectedKeys(catalog);

    expect(
      actual.difference(expected),
      isEmpty,
      reason:
          'orphan ARB keys have no documented catalog mapping: '
          '${actual.difference(expected)}',
    );
    expect(
      expected.difference(actual),
      isEmpty,
      reason:
          'catalog items have no ARB entry: '
          '${expected.difference(actual)}',
    );
  });

  test('corrected IMP-007 and FLD-001 texts are preserved verbatim', () {
    final AppLocalizationsDe l10n = AppLocalizationsDe();

    expect(
      l10n.imp007,
      'Die Datei ist zu groß. Feldexa kann PDF-Dateien bis 80 MiB '
      '(83.886.080 Bytes) importieren.',
    );
    expect(
      l10n.imp007Recovery,
      'Bitte verkleinern Sie die Datei, zum Beispiel durch eine niedrigere '
      'Scan-Auflösung, und importieren Sie sie erneut.',
    );
    expect(arb['imp007'], contains('80 MiB (83.886.080 Bytes)'));
    expect(arb['imp007'], isNot(contains('80 MB')));
    expect(
      l10n.fld001,
      'Der Text ist länger als das Feld. Er wurde nicht gekürzt. Der Export '
      'wird gestoppt, bis der Text gekürzt oder das Feld vergrößert ist.',
    );
    expect(
      l10n.fld001Recovery,
      'Bitte kürzen Sie den Text oder vergrößern Sie das Feld.',
    );
    expect(arb['fld001'], contains('Der Export wird gestoppt'));
    expect(arb['fld001'], isNot(contains('abgeschnitten')));
  });

  test(
    'PRIV-001 discloses aggregate isolation and the global reset exception',
    () {
      final String disclosure = arb['priv001'] as String;
      expect(
        disclosure,
        contains(
          'Wenn der Schlüssel eines Dokuments oder einer Vorlage verloren geht',
        ),
      );
      expect(
        disclosure,
        contains(
          'Andere Dokumente und Vorlagen bleiben unabhängig davon nutzbar',
        ),
      );
      expect(
        disclosure,
        contains('Ein Zurücksetzen des Geräts oder seiner Schlüssel'),
      );
      expect(
        disclosure,
        contains(
          'alle gespeicherten Dokumente und Vorlagen unlesbar machen oder '
          'entfernen',
        ),
      );
    },
  );

  test('placeholder metadata is complete, typed, and German', () {
    const Set<String> allowedTypes = <String>{'String', 'int'};
    final RegExp placeholderPattern = RegExp(r'\{([A-Za-z][A-Za-z0-9]*)\}');

    for (final String key in _messageKeys(arb)) {
      final String value = arb[key] as String;
      expect(value.trim(), value, reason: '$key has surrounding whitespace');
      expect(value, isNotEmpty, reason: '$key is empty');

      final Map<String, dynamic> meta =
          arb['@$key'] as Map<String, dynamic>? ?? <String, dynamic>{};
      expect(
        meta['description'],
        isA<String>(),
        reason: '$key needs an ARB description tied to the catalog',
      );

      final Set<String> names = placeholderPattern
          .allMatches(value)
          .map((RegExpMatch match) => match.group(1)!)
          .toSet();
      final Map<String, dynamic> placeholders =
          meta['placeholders'] as Map<String, dynamic>? ?? <String, dynamic>{};

      expect(
        names,
        placeholders.keys.toSet(),
        reason: '$key placeholder declarations must match its text',
      );
      for (final String name in names) {
        final Map<String, dynamic> placeholder =
            placeholders[name] as Map<String, dynamic>;
        expect(
          allowedTypes,
          contains(placeholder['type']),
          reason: '$key.$name must declare a supported placeholder type',
        );
      }
    }
  });

  test('generated localization code exposes every ARB key', () {
    final String generated = File(_generatedPath).readAsStringSync();

    for (final String key in _messageKeys(arb)) {
      final RegExp accessor = RegExp(
        r'(String get ' +
            RegExp.escape(key) +
            r'\b|String ' +
            RegExp.escape(key) +
            r'\()',
      );
      expect(
        accessor.hasMatch(generated),
        isTrue,
        reason: 'generated AppLocalizationsDe is missing $key',
      );
    }
  });

  test('start area, status, action, and deletion labels match the catalog', () {
    const Map<String, String> section8Keys = <String, String>{
      'Start title': 'startTitle',
      'Documents group': 'documentsGroup',
      'Templates group': 'templatesGroup',
      'Empty documents': 'emptyDocuments',
      'Empty templates': 'emptyTemplates',
      'Import action': 'importAction',
      'Status: draft': 'statusDraft',
      'Status: export-ready': 'statusExportReady',
      'Status: unreadable': 'statusUnreadable',
      'Field count': 'fieldCount',
      'Last edited': 'lastEdited',
      'Review action': 'reviewAction',
      'Fill action': 'fillAction',
      'Export action': 'exportAction',
      'Template action': 'templateSaveAction',
      'Save now': 'saveNow',
      'Unsaved badge': 'unsavedBadge',
      'Unsaved risk banner': 'unsavedRiskBanner',
      'Startup recovery incomplete': 'startupRecoveryIncomplete',
      'Startup recovery incomplete guidance':
          'startupRecoveryIncompleteRecovery',
      'Page analysis state: pending, short form': 'pageAnalysisPending',
      'Page analysis state: pending, full form': 'pageAnalysisPendingHint',
      'Page analysis state: analyzing, short form': 'pageAnalysisAnalyzing',
      'Page analysis state: analyzing, full form': 'pageAnalysisAnalyzingHint',
      'Page analysis state: complete, short form': 'pageAnalysisComplete',
      'Page analysis state: complete, full form': 'pageAnalysisCompleteHint',
      'Page analysis state: failed, short form': 'pageAnalysisFailed',
      'Page analysis state: failed, full form': 'pageAnalysisFailedHint',
    };

    final List<String> rows = _tableCellsInSection(catalog, '## 8.');
    var checked = 0;
    for (final String row in rows) {
      final List<String> cells = _cells(row);
      if (cells.length < 2 || !section8Keys.containsKey(cells[0])) {
        continue;
      }
      final String key = section8Keys[cells[0]]!;
      expect(
        arb[key],
        _quoted(cells[1]),
        reason: '$key must match the §8 "${cells[0]}" text',
      );
      checked++;
    }
    expect(checked, section8Keys.length);

    expect(_lineContaining(catalog, '**Template labels**'), isNotNull);
    final List<String> templateLabels = RegExp(r'„([^“]*)“')
        .allMatches(_lineContaining(catalog, '**Template labels**')!)
        .map((RegExpMatch match) => match.group(1)!)
        .toList();
    expect(templateLabels, <String>[
      arb['templateSaveAction'] as String,
      arb['templateLabel'] as String,
      arb['templateVersionLabel'] as String,
      arb['templateNewVersionSaved'] as String,
      arb['templateEditorHint'] as String,
    ]);

    final String? documentDialog = _lineContaining(
      catalog,
      'Möchten Sie „{title}“ wirklich löschen',
    );
    final String? templateDialog = _lineContaining(
      catalog,
      'Möchten Sie die Vorlage „{title}“',
    );
    final String? afterDeletion = _lineContaining(
      catalog,
      'wurde gelöscht. Andere Dokumente',
    );
    expect(arb['deleteDocumentDialog'], _quoted(documentDialog!));
    expect(arb['deleteTemplateDialog'], _quoted(templateDialog!));
    expect(arb['deletionConfirmation'], _quoted(afterDeletion!));

    expect(arb['suggestionsLabel'], 'Vorschläge');
    final String? actionsLine = _lineContaining(
      catalog,
      'Error dialogs have one primary action',
    );
    final List<String> actions = RegExp(r'„([^“]*)“')
        .allMatches(actionsLine!)
        .map((RegExpMatch match) => match.group(1)!)
        .toList();
    expect(actions, <String>[
      arb['actionUnderstood'] as String,
      arb['actionRetry'] as String,
      arb['actionCheckStorage'] as String,
    ]);
  });

  test(
    'page analysis-state vocabulary matches §8, the ARB, and generated code',
    () {
      final Map<String, String> contextToKey = <String, String>{
        'Page analysis state: pending, short form': 'pageAnalysisPending',
        'Page analysis state: pending, full form': 'pageAnalysisPendingHint',
        'Page analysis state: analyzing, short form': 'pageAnalysisAnalyzing',
        'Page analysis state: analyzing, full form':
            'pageAnalysisAnalyzingHint',
        'Page analysis state: complete, short form': 'pageAnalysisComplete',
        'Page analysis state: complete, full form': 'pageAnalysisCompleteHint',
        'Page analysis state: failed, short form': 'pageAnalysisFailed',
        'Page analysis state: failed, full form': 'pageAnalysisFailedHint',
      };
      final Map<String, String Function(AppLocalizationsDe)> getters =
          <String, String Function(AppLocalizationsDe)>{
            'pageAnalysisPending': (AppLocalizationsDe l10n) =>
                l10n.pageAnalysisPending,
            'pageAnalysisPendingHint': (AppLocalizationsDe l10n) =>
                l10n.pageAnalysisPendingHint,
            'pageAnalysisAnalyzing': (AppLocalizationsDe l10n) =>
                l10n.pageAnalysisAnalyzing,
            'pageAnalysisAnalyzingHint': (AppLocalizationsDe l10n) =>
                l10n.pageAnalysisAnalyzingHint,
            'pageAnalysisComplete': (AppLocalizationsDe l10n) =>
                l10n.pageAnalysisComplete,
            'pageAnalysisCompleteHint': (AppLocalizationsDe l10n) =>
                l10n.pageAnalysisCompleteHint,
            'pageAnalysisFailed': (AppLocalizationsDe l10n) =>
                l10n.pageAnalysisFailed,
            'pageAnalysisFailedHint': (AppLocalizationsDe l10n) =>
                l10n.pageAnalysisFailedHint,
          };
      expect(getters.keys.toSet(), contextToKey.values.toSet());

      final Map<String, String> catalogTexts = <String, String>{};
      for (final String row in _tableCellsInSection(catalog, '## 8.')) {
        final List<String> cells = _cells(row);
        if (cells.length < 2 || !contextToKey.containsKey(cells[0])) {
          continue;
        }
        final String? text = _quoted(cells[1]);
        expect(text, isNotNull, reason: '${cells[0]} needs German quotes');
        catalogTexts[contextToKey[cells[0]]!] = text!;
      }
      expect(catalogTexts.length, contextToKey.length);

      final AppLocalizationsDe l10n = AppLocalizationsDe();
      for (final MapEntry<String, String> entry in catalogTexts.entries) {
        expect(
          arb[entry.key],
          entry.value,
          reason: '${entry.key} must carry the exact §8 text',
        );
        expect(
          getters[entry.key]!(l10n),
          entry.value,
          reason: 'generated AppLocalizationsDe.${entry.key} drifted from §8',
        );
      }
    },
  );

  test(
    'durability, privacy, export, and SIMULATED labels match the catalog',
    () {
      const Map<String, String> durabilityKeys = <String, String>{
        'clean': 'durabilityClean',
        'saving': 'durabilitySaving',
        'saved': 'durabilitySaved',
        'unsaved': 'durabilityUnsaved',
        'saveFailed': 'durabilitySaveFailed',
        'recoveryFallback': 'durabilityRecoveryFallback',
      };
      for (final String row in _tableCellsInSection(catalog, '## 3.')) {
        final List<String> cells = _cells(row);
        if (cells.length < 2) {
          continue;
        }
        final String? state = RegExp(r'^`([A-Za-z]+)`$')
            .firstMatch(cells[0])
            ?.group(1);
        if (state == null || !durabilityKeys.containsKey(state)) {
          continue;
        }
        expect(
          arb[durabilityKeys[state]],
          _quoted(cells[1]),
          reason: 'durability label $state must match §3',
        );
      }

      final String? privacyLine = _lineContaining(
        catalog,
        'Ihre Dokumente und Vorlagen werden nur auf diesem Gerät',
      );
      expect(arb['priv001'], _quoted(privacyLine!));

      final String? preExportLine = _lineContaining(
        catalog,
        '**Pre-export information**',
      );
      final List<String> preExport = RegExp(r'„([^“]*)“')
          .allMatches(preExportLine!)
          .map((RegExpMatch match) => match.group(1)!)
          .toList();
      expect(preExport, <String>[
        arb['preExportEmptyFields'] as String,
        arb['preExportUnreviewedSuggestions'] as String,
      ]);

      final String? successLine = _lineContaining(
        catalog,
        '**Export success**',
      );
      expect(
        arb['exportSuccess'],
        RegExp(r'„([^“]*)“').firstMatch(successLine!)!.group(1),
      );

      final String? previewLine = _lineContaining(
        catalog,
        '**Preview footer**',
      );
      final List<String> preview = RegExp(r'„([^“]*)“')
          .allMatches(previewLine!)
          .map((RegExpMatch match) => match.group(1)!)
          .toList();
      expect(preview, <String>[
        arb['previewFooter'] as String,
        arb['simulatedToken'] as String,
      ]);

      const Map<String, String> simulatedContextKeys = <String, String>{
        'Global banner (Web)': 'simulatedBannerContext',
        'Simulated export footer': 'simulatedExportFooterContext',
        'Simulated storage notice': 'simulatedStorageContext',
      };
      var contexts = 0;
      for (final String row in _tableCellsInSection(catalog, '## 9.')) {
        final List<String> cells = _cells(row);
        if (cells.length < 3 || !simulatedContextKeys.containsKey(cells[0])) {
          continue;
        }
        final String key = simulatedContextKeys[cells[0]]!;
        expect(
          arb[key],
          _quoted(cells[2]),
          reason: '$key must match the §9 context line',
        );
        expect(
          cells[1],
          contains('SIMULATED'),
          reason: 'the exact SIMULATED token must remain untranslated',
        );
        contexts++;
      }
      expect(contexts, simulatedContextKeys.length);
      expect(arb['simulatedToken'], 'SIMULATED');
      expect(arb['simulatedBanner'], contains('SIMULATED'));
    },
  );

  test(
    'accessibility semantics use the catalog templates and German states',
    () {
      String normalized(String value) {
        return value
            .replaceAll('{filled|leer}', '{filled}')
            .replaceAll('{bestätigt|Vorschlag|selbst erstellt}', '{status}')
            .replaceAll('{, Konflikt}', '{conflict}')
            .replaceAll('{, unsicher}', '{uncertainty}')
            .replaceAll('{aktiviert|nicht aktiviert}', '{state}')
            .replaceAll('{unterschrieben|nicht unterschrieben}', '{state}');
      }

      final Map<String, String> templates = <String, String>{
        'Feld {label}': 'a11yFieldOverlay',
        'Vorschlag für {type}': 'a11ySuggestion',
        'Kontrollkästchen {label}': 'a11yCheckbox',
        'Unterschriftenfeld {label}': 'a11ySignature',
        'Seite {page} von {count}': 'a11yPageNavigation',
        'Vergrößerung {percent} Prozent': 'a11yZoom',
      };
      for (final MapEntry<String, String> entry in templates.entries) {
        final String? line = _lineContaining(catalog, entry.key);
        expect(line, isNotNull, reason: '${entry.value} template is missing');
        expect(
          arb[entry.value],
          normalized(_quoted(line!)!),
          reason: '${entry.value} must match the §8 accessibility template',
        );
      }

      expect(arb['a11yFieldValueFilled'], 'ausgefüllt');
      expect(arb['a11yFieldValueEmpty'], 'leer');
      expect(arb['a11yFieldStatusConfirmed'], 'bestätigt');
      expect(arb['a11yFieldStatusSuggestion'], 'Vorschlag');
      expect(arb['a11yFieldStatusSelfCreated'], 'selbst erstellt');
      expect(arb['a11yFieldConflict'], ', Konflikt');
      expect(arb['a11yFieldUncertain'], ', unsicher');
      expect(arb['a11yCheckboxChecked'], 'aktiviert');
      expect(arb['a11yCheckboxUnchecked'], 'nicht aktiviert');
      expect(arb['a11ySignatureSigned'], 'unterschrieben');
      expect(arb['a11ySignatureUnsigned'], 'nicht unterschrieben');

      final String? bannerLine = _lineContaining(
        catalog,
        'The SIMULATED banner:',
      );
      expect(arb['simulatedBanner'], _quoted(bannerLine!));
    },
  );

  test('no untranslated English UI words remain; SIMULATED is allowlisted', () {
    // SC-014's complete audit is T133; this T029 check catches English UI text
    // regressions in the canonical ARB while allowlisting mandated tokens.
    const Set<String> allowedForeignTokens = <String>{
      'SIMULATED',
      'PDF',
      'Feldexa',
      'Android',
      'MiB',
      'Bytes',
    };
    const Set<String> englishWords = <String>{
      'the',
      'and',
      'please',
      'error',
      'failed',
      'file',
      'cancel',
      'settings',
      'loading',
      'success',
      'invalid',
      'required',
      'save',
      'delete',
      'open',
      'close',
      'this',
      'that',
      'with',
      'without',
      'your',
      'you',
      'cannot',
      'from',
      'user',
      'page',
      'field',
      'document',
      'template',
    };
    final RegExp asciiWord = RegExp(r'[A-Za-z]+');

    for (final String key in _messageKeys(arb)) {
      // Placeholder names are code, not user-facing prose.
      final String value = (arb[key] as String).replaceAll(
        RegExp(r'\{[^}]*\}'),
        '',
      );
      for (final RegExpMatch match in asciiWord.allMatches(value)) {
        final String word = match.group(0)!;
        if (allowedForeignTokens.contains(word)) {
          continue;
        }
        expect(
          englishWords,
          isNot(contains(word.toLowerCase())),
          reason: '$key contains the untranslated English word "$word"',
        );
      }
    }

    expect(arb['simulatedToken'], 'SIMULATED');
    expect(arb['simulatedLogPrefix'], '[SIMULATED]');
    expect(arb['simulatedBanner'], startsWith('SIMULATED'));
  });
}
