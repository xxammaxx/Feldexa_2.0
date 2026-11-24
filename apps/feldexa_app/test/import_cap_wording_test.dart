@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:feldexa_app/features/start/import_error_mapper.dart';
import 'package:feldexa_app/l10n/app_localizations_de.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/package_root.dart';

/// T045 `IMP-007` wording consistency (FR-005; CHK028; CR-3).
///
/// The catalog is the normative source. This host-VM test compares its
/// `IMP-007` row with the committed ARB value, the generated German
/// localization, and the message the T041 mapper presents for a
/// `tooLarge` rejection. It produces no `SIMULATED`, `EMULATOR`, or `DEVICE`
/// evidence.
const String _catalogRelativePath =
    'specs/001-scanned-form-workflow/contracts/error-catalog.de.md';
const String _arbPath = 'lib/l10n/app_de.arb';

/// Exact catalog text, quoted here so a silent catalog/ARB edit that omits
/// the binary boundary fails even if all three runtime sources agree.
const String _expectedImp007 =
    'Die Datei ist zu groß. Feldexa kann PDF-Dateien bis 80 MiB '
    '(83.886.080 Bytes) importieren.';
const String _expectedImp007Recovery =
    'Bitte verkleinern Sie die Datei, zum Beispiel durch eine niedrigere '
    'Scan-Auflösung, und importieren Sie sie erneut.';

/// German quotes wrap every catalog text; nested quotes make the match greedy
/// from the first opening to the last closing quote (same rule as the T029
/// catalog test).
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

/// Reads the `IMP-007` message and recovery cells from the catalog's §1 table.
({String message, String recovery}) _catalogImp007(String catalog) {
  for (final String line in catalog.split('\n')) {
    if (!line.startsWith('|')) {
      continue;
    }
    final List<String> cells = _cells(line);
    if (cells.length < 4 || cells[0] != '`IMP-007`') {
      continue;
    }
    final String? message = _quoted(cells[2]);
    final String? recovery = _quoted(cells[3]);
    if (message == null || recovery == null) {
      break;
    }
    return (message: message, recovery: recovery);
  }
  fail('contracts/error-catalog.de.md §1 has no quoted IMP-007 row');
}

void main() {
  test('catalog, ARB, generated text, and mapper agree on IMP-007', () {
    final String catalog = File('${repositoryRoot.path}/$_catalogRelativePath')
        .readAsStringSync();
    final Map<String, dynamic> arb = jsonDecode(
      File('${packageRoot.path}/$_arbPath').readAsStringSync(),
    ) as Map<String, dynamic>;
    final AppLocalizationsDe l10n = AppLocalizationsDe();
    final ImportErrorMapper mapper = ImportErrorMapper(l10n);
    final ({String message, String recovery}) row = _catalogImp007(catalog);
    final ImportFailurePresentation presentation = mapper.describe(
      ImportRejectedException(ImportRejectionKind.tooLarge),
    );

    // One sentence, four sources: catalog -> ARB -> generated getter -> the
    // German text the import error mapper actually presents.
    expect(row.message, _expectedImp007);
    expect(row.recovery, _expectedImp007Recovery);
    expect(arb['imp007'], row.message);
    expect(arb['imp007Recovery'], row.recovery);
    expect(l10n.imp007, row.message);
    expect(l10n.imp007Recovery, row.recovery);
    expect(presentation.code, 'IMP-007');
    expect(presentation.message, row.message);
    expect(presentation.recovery, row.recovery);
    expect(presentation.retryable, isFalse);

    for (final String text in <String>[
      row.message,
      arb['imp007'] as String,
      l10n.imp007,
      presentation.message!,
    ]) {
      expect(text, contains('80 MiB (83.886.080 Bytes)'));
      // "80 MB" would be 80,000,000 bytes, not the documented 83,886,080.
      expect(text, isNot(contains('80 MB')));
    }
  });
}
