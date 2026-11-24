// T263 German OCR character and Unicode reference suite (declarations).
//
// Additive fixture for the dev catalogue in `tools/corpus/synthetic/`. The
// German reference is `sf-005` and is emitted by the **same** generator run as
// the other synthetic fixtures, so the catalogue, the delivery mirrors, and the
// expected-OCR file cannot drift. Existing fixtures keep their exact bytes and
// SHA-256 pins (`sf-001` 22c939cc…, `sf-004` 009c3bab…); this module only adds
// one new fixture and never rewrites the frozen real corpus
// (`tools/corpus/manifest.json`) or its provenance.
//
// The base-14/`WinAnsiEncoding` writer cannot encode U+1E9E (ẞ), so this fixture
// uses the additive embedded-font writer in `ttf_embed.dart` with the bundled
// Noto Sans Regular (OFL); the generator pins the font SHA-256 and every glyph
// is resolved through the font's own cmap, which is the coverage proof.
//
// The layout below is the single source for three artifacts that therefore
// cannot drift:
//  * the printable PDF (`reference-de.pdf`, embedded Noto Sans, real ẞ/€/²/³),
//  * the pre-annotated ground truth (`reference-de.ground-truth.json`):
//    printed text lines with display-space rectangles, roles, NFC and NFD
//    spellings, the special-character inventory, and the label/field roles,
//  * the pre-declared degradation variants and their baseline thresholds,
//    which are committed before the first scored run (research.md D-18).
//
// Every name, authority, and value is fictional. No personal data, no network,
// no randomness, no clock, no locale-dependent formatting.

import 'dart:convert';
import 'dart:typed_data';

import 'ttf_embed.dart';

/// Suite/annotation version. Any change to text, layout, or thresholds needs a
/// new version and a new, separately reported run.
const String suiteId = 'de-ocr-1.0.0';

/// Fixture id used by the catalogue, run files, and metrics reports.
const String fixtureId = 'sf-005';

/// Canonical dev-catalogue path of the generated PDF.
const String pdfAssetPath = 'apps/feldexa_app/assets/fixtures/sf-005.pdf';

/// Android/`adb push` mirror path of the generated PDF.
const String corpusPdfPath = 'tools/corpus/synthetic/sf-005.pdf';

/// Expected-OCR path inside the canonical dev directory.
const String expectedOcrFileName = 'sf-005.expected-ocr.json';

/// Catalogue role of the fixture (`editor | navigation | geometry | fields |
/// import-failure`).
const String fixtureRole = 'fields';

/// Catalogue title.
const String fixtureTitle = 'Deutsche OCR-Sonderzeichen-Referenz';

/// Catalogue description.
const String fixtureDescription =
    'Two-page additive reference for German special characters (Ä Ö Ü ä ö ü ß '
    'ẞ), €, m²/m³, authority terms, and fictional names, printed with the '
    'bundled Noto Sans font embedded as a Type0/CIDFontType2 font so the real '
    'ẞ glyph exists and the text layer stays character-faithful.';

/// Catalogue strata.
const List<String> fixtureStrata = <String>[
  'characters:german',
  'characters:unicode-case',
  'currency:eur',
  'units:superscript',
  'ground-truth:per-line',
  'labels:german',
];

/// Generator identity recorded in the ground truth.
const String generatorPath = 'tools/corpus/de-ocr/generate.dart';

/// Generator version.
const String generatorVersion = '1.0.0';

/// Pinned embedded font (project-bundled Noto Sans Regular, OFL).
const String fontAssetPath =
    'apps/feldexa_app/assets/fonts/NotoSans-Regular.ttf';

/// SHA-256 of [fontAssetPath]; the generator rejects any other bytes.
const String fontSha256 =
    '97eaf07030b89da4eceace86b12f4d7debb3cb212082c3938803eac7111221c9';

/// A4 page width in display points.
const double pageWidthPt = 595.28;

/// A4 page height in display points.
const double pageHeightPt = 841.89;

/// Left margin used by every generated line.
const double marginLeftPt = 56.7;

/// Characters the issue requires to be qualified end to end.
const List<String> requiredCharacters = <String>[
  'Ä',
  'Ö',
  'Ü',
  'ä',
  'ö',
  'ü',
  'ß',
  'ẞ',
  '€',
  '²',
  '³',
];

/// Additional printable characters exercised on the punctuation line.
const List<String> secondaryCharacters = <String>[
  '„',
  '“',
  '–',
  '—',
  '…',
  '§',
  '·',
];

/// German authority terms the issue names explicitly.
const List<String> requiredAuthorityTerms = <String>[
  'Straße',
  'Größe',
  'Gebühr',
  'Geschäftszeichen',
  'Staatsangehörigkeit',
  'Überweisung',
  'Erklärung',
  'Anträge',
];

/// One printed ground-truth text line.
final class GtLine {
  const GtLine({
    required this.id,
    required this.pageIndex,
    required this.text,
    required this.role,
    required this.xPt,
    required this.yPt,
    required this.widthPt,
    required this.heightPt,
    required this.fontSizePt,
    required this.bold,
    this.critical = false,
    this.fieldId,
  });

  /// Stable line id.
  final String id;

  /// Page index this line is printed on.
  final int pageIndex;

  /// Verbatim printed text (NFC); never normalized for the raw comparison.
  final String text;

  /// Line role (`special_characters`, `authority_term`, `label`, ...).
  final String role;

  /// Display-space left edge in points.
  final double xPt;

  /// Display-space top edge in points.
  final double yPt;

  /// Measured advance width in points.
  final double widthPt;

  /// Line box height in points (`1.2 ×` font size, the corpus convention).
  final double heightPt;

  /// Font size in points.
  final double fontSizePt;

  /// Whether the line is drawn with the faux-bold render mode.
  final bool bold;

  /// Whether a clean reference render must reproduce this line exactly.
  final bool critical;

  /// Field id when this line is a label of a declared field.
  final String? fieldId;

  /// Required characters that appear in this line.
  List<String> get presentRequiredCharacters => <String>[
    for (final String character in requiredCharacters)
      if (text.contains(character)) character,
  ];

  /// Secondary characters that appear in this line.
  List<String> get presentSecondaryCharacters => <String>[
    for (final String character in secondaryCharacters)
      if (text.contains(character)) character,
  ];

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'pageIndex': pageIndex,
      'role': role,
      'critical': critical,
      'fieldId': fieldId,
      'fontSizePt': fontSizePt,
      'bold': bold,
      'rect': <String, Object?>{
        'xPt': xPt,
        'yPt': yPt,
        'widthPt': widthPt,
        'heightPt': heightPt,
      },
      'text': text,
      'textNfd': toNfd(text),
      'codePoints': <String>[
        for (final int rune in text.runes) 'U+${_hex4(rune)}',
      ],
      'presentRequiredCharacters': presentRequiredCharacters,
      'presentSecondaryCharacters': presentSecondaryCharacters,
    };
  }
}

/// One declared field with its label line and blank input region.
final class GtField {
  const GtField({
    required this.id,
    required this.pageIndex,
    required this.type,
    required this.label,
    required this.labelLineId,
    required this.xPt,
    required this.yPt,
    required this.widthPt,
    required this.heightPt,
  });

  /// Stable field id.
  final String id;

  /// Page index of the blank input region.
  final int pageIndex;

  /// Expected field type from `contracts/recognition-output.md` §2.
  final String type;

  /// Expected label text, verbatim.
  final String label;

  /// Ground-truth line id of the printed label.
  final String labelLineId;

  /// Display-space input region.
  final double xPt;
  final double yPt;
  final double widthPt;
  final double heightPt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'pageIndex': pageIndex,
      'type': type,
      'label': label,
      'labelLineId': labelLineId,
      'rect': <String, Object?>{
        'xPt': xPt,
        'yPt': yPt,
        'widthPt': widthPt,
        'heightPt': heightPt,
      },
    };
  }
}

/// The complete reference suite: PDF bytes plus ground truth.
final class DeOcrReferenceSuite {
  DeOcrReferenceSuite._({
    required this.font,
    required List<FontPdfPage> pages,
    required List<GtLine> lines,
    required List<GtField> fields,
  }) : _pages = List<FontPdfPage>.unmodifiable(pages),
       lines = List<GtLine>.unmodifiable(lines),
       fields = List<GtField>.unmodifiable(fields);

  /// The embedded font.
  final TrueTypeFont font;

  final List<FontPdfPage> _pages;

  /// Every printed line in drawing order.
  final List<GtLine> lines;

  /// Every declared field.
  final List<GtField> fields;

  /// Page count of the reference document.
  int get pageCount => _pages.length;

  /// Builds the suite with the pinned font.
  static DeOcrReferenceSuite build(TrueTypeFont font) {
    final _PageBuilder first = _PageBuilder(font: font, pageIndex: 0);
    _drawHeaders(
      first,
      title: 'Zeichensatz- und Unicode-Referenz',
      subtitle:
          'Deutsche Sonderzeichen, Währung, Einheiten und Behördenbegriffe.',
    );

    first.section('1. Grundzeichen (Groß- und Kleinschreibung)', 126);
    first.line(
      'Ä Ö Ü ä ö ü ß ẞ',
      yTop: 150,
      size: 15,
      role: 'special_characters',
      critical: true,
    );
    first.line(
      'Ärger Öffnung Übung Äußerst',
      yTop: 180,
      size: 13,
      role: 'special_characters',
      critical: true,
    );
    first.line(
      'ärger öffnung übung äußerst',
      yTop: 206,
      size: 13,
      role: 'special_characters',
      critical: true,
    );
    first.line(
      'Straße Größe Äußerung',
      yTop: 232,
      size: 13,
      role: 'authority_term',
      critical: true,
    );

    first.section('2. Währung, Einheiten und Satzzeichen', 266);
    first.line(
      'Gebühr: 12,50 € · Fläche: 45 m² · Raum: 7 m³',
      yTop: 290,
      size: 12,
      role: 'currency_and_units',
      critical: true,
    );
    first.line(
      '„Deutsch“ – Gedankenstrich — Auslassung … § 5',
      yTop: 314,
      size: 12,
      role: 'punctuation',
      critical: true,
    );

    first.section('3. Behördenbegriffe', 348);
    first.line(
      'Straße und Hausnummer',
      yTop: 372,
      size: 11,
      role: 'authority_term',
      critical: true,
    );
    first.line(
      'Größe, Gebühr, Geschäftszeichen, Staatsangehörigkeit',
      yTop: 396,
      size: 11,
      role: 'authority_term',
      critical: true,
    );
    first.line(
      'Überweisung, Erklärung, Anträge, Begründung',
      yTop: 420,
      size: 11,
      role: 'authority_term',
      critical: true,
    );
    first.line(
      'Rückumschlag, Äußerung, Antragstellung, Bürgerdienste',
      yTop: 444,
      size: 11,
      role: 'authority_term',
      critical: true,
    );

    first.section('4. Frei erfundene Namen', 478);
    first.line(
      'Jürgen Mühlbach, Bärbel Süßbier, Käthe Gröhnert, Matthäus Ölmüller',
      yTop: 502,
      size: 12,
      role: 'fictional_name',
      critical: true,
    );
    first.line(
      'MÜLLER-GRÄBER, SCHRÖDER-WEISS, BÄUERLE, ÖHMICHEN',
      yTop: 528,
      size: 12,
      role: 'fictional_name',
      critical: true,
    );
    first.line(
      'Zeichen: ẞ ß Ä Ö Ü ä ö ü € m² m³',
      yTop: 562,
      size: 11,
      role: 'special_characters',
      critical: true,
    );

    first.line(
      'Hinweis: Dieses Dokument ist synthetisch und enthält keine realen '
      'Personendaten.',
      yTop: 700,
      size: 8,
      role: 'notice',
    );
    first.line(
      'Es dient ausschließlich der Entwicklung und Prüfung des Editors.',
      yTop: 716,
      size: 8,
      role: 'notice',
    );
    first.footer('Seite 1 von 2');

    final _PageBuilder second = _PageBuilder(font: font, pageIndex: 1);
    _drawHeaders(
      second,
      title: 'Bezeichnungen und Feldübernahme',
      subtitle:
          'Deutsche Feldbezeichnungen mit Sonderzeichen für die '
          'Label-Übernahme.',
    );

    second.section('1. Felder mit deutschen Bezeichnungen', 126);
    second.field(
      id: 'p1-strasse',
      label: 'Straße und Hausnummer',
      type: 'text',
      yTop: 150,
    );
    second.field(
      id: 'p1-groesse',
      label: 'Größe in cm',
      type: 'number',
      yTop: 186,
    );
    second.field(
      id: 'p1-gebuhr',
      label: 'Gebühr in €',
      type: 'number',
      yTop: 222,
    );
    second.field(
      id: 'p1-geschaeftszeichen',
      label: 'Geschäftszeichen',
      type: 'text',
      yTop: 258,
    );
    second.field(
      id: 'p1-staatsangehoerigkeit',
      label: 'Staatsangehörigkeit',
      type: 'text',
      yTop: 294,
    );
    second.field(
      id: 'p1-ueberweisung',
      label: 'Überweisung an',
      type: 'text',
      yTop: 330,
    );
    second.field(
      id: 'p1-antraege',
      label: 'Anträge vom',
      type: 'text',
      yTop: 366,
    );
    second.field(
      id: 'p1-familienname',
      label: 'Familienname',
      type: 'text',
      yTop: 402,
    );
    second.field(id: 'p1-vorname', label: 'Vorname', type: 'text', yTop: 438);
    second.field(
      id: 'p1-geburtsdatum',
      label: 'Geburtsdatum',
      type: 'date',
      yTop: 474,
      hint: 'TT.MM.JJJJ',
    );

    second.section('2. Mehrzeilige Erklärung', 516);
    second.multiline(
      id: 'p1-erklaerung',
      label: 'Erklärung und Äußerung',
      yTop: 540,
    );

    second.section('3. Einverständnis und Unterschrift', 624);
    second.checkbox(
      id: 'p1-einverstaendnis',
      label: 'Einverständnis erteilt',
      xPt: 190,
      yPt: 648,
    );
    second.signature(id: 'p1-unterschrift', label: 'Unterschrift', yTop: 682);
    second.line(
      'Beispiel: Müller-Gräber, Äußere Straße 12, 8 m²',
      yTop: 750,
      size: 10,
      role: 'printed_value',
      critical: true,
    );
    second.footer('Seite 2 von 2');

    return DeOcrReferenceSuite._(
      font: font,
      pages: <FontPdfPage>[first.page, second.page],
      lines: <GtLine>[...first.lines, ...second.lines],
      fields: <GtField>[...first.fields, ...second.fields],
    );
  }

  static void _drawHeaders(
    _PageBuilder page, {
    required String title,
    required String subtitle,
  }) {
    page.line('MUSTERSTADT', yTop: 32, size: 9, role: 'heading', bold: true);
    page.line(
      'Musteramt für Bürgerdienste',
      yTop: 44,
      size: 9,
      role: 'heading',
    );
    page.line(
      'SYNTHETISCHES TESTDOKUMENT – kein amtliches Formular',
      xPt: 330,
      yTop: 44,
      size: 7,
      role: 'notice',
    );
    page.page.line(56.7, 62, pageWidthPt - 56.7, 62, width: 1.2);
    page.line(title, yTop: 76, size: 15, role: 'title', bold: true);
    page.line(subtitle, yTop: 98, size: 9, role: 'subtitle');
  }

  /// Builds the PDF bytes.
  Uint8List pdfBytes() {
    return EmbeddedFontPdf(font: font, pages: _pages).build();
  }

  /// Builds the SIMULATED expected-OCR document for the dev catalogue.
  ///
  /// The blocks are declared, not measured: this is the fixture contract the
  /// SIMULATED adapters use, never OCR evidence.
  Map<String, Object?> expectedOcrJson(int pageCount) {
    return <String, Object?>{
      'schemaVersion': 1,
      'fixtureId': fixtureId,
      'language': 'de',
      'evidenceClass': 'simulated',
      'generatorVersion': generatorVersion,
      'notes':
          'Declared expectations for the SIMULATED adapters, derived from the '
          'same per-line ground truth as the PDF. They are not ML Kit output '
          'and not evidence about Android behaviour.',
      'pages': <Object>[
        for (int index = 0; index < pageCount; index++)
          <String, Object?>{
            'pageIndex': index,
            'widthPt': pageWidthPt,
            'heightPt': pageHeightPt,
            'rotation': 0,
            'blocks': <Object>[
              for (final GtLine line in lines)
                if (line.pageIndex == index)
                  <String, Object?>{
                    'rect': <String, Object?>{
                      'x': line.xPt,
                      'y': line.yPt,
                      'width': line.widthPt,
                      'height': line.heightPt,
                    },
                    'text': line.text,
                    'confidence': 0.97,
                    'lines': <Object>[
                      <String, Object?>{
                        'rect': <String, Object?>{
                          'x': line.xPt,
                          'y': line.yPt,
                          'width': line.widthPt,
                          'height': line.heightPt,
                        },
                        'text': line.text,
                        'confidence': 0.97,
                      },
                    ],
                  },
            ],
          },
      ],
    };
  }

  /// Builds the ground-truth JSON document.
  ///
  /// [pdfSha256] and [pdfSizeBytes] pin the exact PDF these annotations
  /// describe, so a metrics run can prove it scored the annotated bytes.
  Map<String, Object?> groundTruthJson({
    required String pdfSha256,
    required int pdfSizeBytes,
  }) {
    return <String, Object?>{
      'schemaVersion': 1,
      'suiteId': suiteId,
      'fixtureId': fixtureId,
      'title': 'Deutsche OCR-Sonderzeichen-Referenz',
      'description':
          'Additive synthetic reference for German special characters, '
          'Unicode case forms, currency and unit characters, German authority '
          'terms, and fictional names. Printed with the bundled Noto Sans '
          'Regular (OFL) embedded as a Type0/CIDFontType2 font so U+1E9E '
          '(ẞ) is a real glyph and the text layer is character-faithful.',
      'annotationClass': 'GROUND_TRUTH',
      'rights': <String, Object?>{
        'kind': 'synthetic',
        'thirdPartyContent': false,
        'containsPersonalData': false,
        'rightsCleared': true,
        'legalBasis':
            'project-generated fictional content; bundled font Noto Sans '
            'under SIL Open Font License 1.1',
        'notes':
            'All authorities, names, values, and addresses are invented. The '
            'document carries a visible synthetic marker on every page.',
      },
      'generator': <String, Object?>{
        'path': generatorPath,
        'version': generatorVersion,
        'deterministic': true,
        'checkCommand': 'dart run $generatorPath --check',
        'notes':
            'No randomness, wall clock, locale, or network input. Fixed '
            'object order, fixed document id, un-compressed streams, whole '
            'font embedded verbatim (no subsetting).',
      },
      'font': <String, Object?>{
        'assetPath': fontAssetPath,
        'sha256': fontSha256,
        'family': 'Noto Sans',
        'licence': 'SIL Open Font License 1.1',
      },
      'pdf': <String, Object?>{
        'path': pdfAssetPath,
        'corpusPath': corpusPdfPath,
        'expectedOcrPath': expectedOcrFileName,
        'sha256': pdfSha256,
        'sizeBytes': pdfSizeBytes,
        'pageCount': pageCount,
      },
      'requiredCharacters': <Object>[
        for (final String character in requiredCharacters)
          <String, Object?>{
            'character': character,
            'codePoint': 'U+${_hex4(character.runes.first)}',
            'nfd': toNfd(character),
            'lowerCase': character.toLowerCase(),
            'upperCase': character.toUpperCase(),
            'matchingFold': matchingFold(character),
          },
      ],
      'secondaryCharacters': <Object>[
        for (final String character in secondaryCharacters)
          <String, Object?>{
            'character': character,
            'codePoint': 'U+${_hex4(character.runes.first)}',
          },
      ],
      'requiredAuthorityTerms': requiredAuthorityTerms,
      'metricsPolicy': <String, Object?>{
        'rawText': <String, Object?>{
          'normalization': 'none',
          'unit': 'unicode_code_points',
          'cer':
              'Levenshtein distance over aligned character pairs divided by '
              'the ground-truth code-point count; unaligned ground-truth '
              'characters are deletions, unaligned OCR characters are '
              'insertions',
          'lineAssociation':
              'A ground-truth line and an OCR line belong together when the '
              'OCR line vertical centre lies inside the ground-truth line box '
              'grown by 4 pt and the horizontal overlap covers at least 30 % '
              'of the narrower box. Association is geometry only and never '
              'uses text similarity.',
          'specialCharacterPrecisionRecall':
              'Computed from the edit-distance alignment over the required '
              'character set only; precision = correctly kept required '
              'characters / all required characters produced by OCR, recall = '
              'correctly kept required characters / all required characters '
              'in the ground truth. The confusion matrix counts every aligned '
              'ground-truth-to-OCR pair whose source is a required character, '
              'plus missing-position deletions.',
        },
        'semantic': <String, Object?>{
          'matchingAliases': <String>[
            'NFC',
            'NFD',
            'case-insensitive',
            'ä↔ae, ö↔oe, ü↔ue, ß↔ss (matching only, never for raw text)',
          ],
          'noSilentCorrection': <String>[
            'ocr-confusion StraBe for Straße is never rewritten to ß',
            'Grosse for Größe is never rewritten and never counted as a match',
            'missing umlaut dots are reported, not repaired',
            'a missing or ambiguous label stays unresolved and is never '
                'converted into a forced type',
          ],
          'fieldDetection':
              'contracts/recognition-output.md §3.2 via the production '
              'TypeInference label-proximity rule; a field counts as detected '
              'only when a credible label is assigned and the label text '
              'matches after the declared matching aliases',
          'labelGeometry':
              'IoU between the assigned OCR label rectangle and the '
              'ground-truth label rectangle',
        },
        'unresolved':
            'An unresolved case is reported as UNRESOLVED and never as an '
            'accuracy PASS. Critical lines must match exactly on the clean '
            'reference variant or be listed as explicitly unresolved with the '
            'observed difference.',
        'evidenceClasses': <String, Object?>{
          'EMULATOR':
              'production raster port (PDFium/pdfrx) plus production bundled '
              'ML Kit OCR on the emulator; the only class that can satisfy a '
              'device gate for the clean reference variant',
          'EMULATOR_INJECTED_RASTER':
              'production bundled ML Kit OCR on the emulator over a raster '
              'degraded outside the production raster path (scan photo '
              'simulation); never reported as clean production-path evidence',
          'SIMULATED': 'simulated adapters or host-only output',
          'TEXT_LAYER':
              'PDF text layer (pdftotext); control path proving the printed '
              'code points, never OCR evidence',
        },
      },
      'variants': <Object>[
        for (final Map<String, Object?> variant in variantBaselines) variant,
      ],
      'pages': <Object>[
        for (int index = 0; index < pageCount; index++)
          <String, Object?>{
            'index': index,
            'widthPt': pageWidthPt,
            'heightPt': pageHeightPt,
            'rotation': 0,
          },
      ],
      'lines': <Object>[for (final GtLine line in lines) line.toJson()],
      'fields': <Object>[for (final GtField field in fields) field.toJson()],
    };
  }
}

/// Pre-declared degradation variants and their scoring expectations.
///
/// Declared before the first scored run; a later change needs a new
/// [suiteId] and a separately reported run (research.md D-18).
const List<Map<String, Object?>> variantBaselines = <Map<String, Object?>>[
  <String, Object?>{
    'id': 'clean-200dpi',
    'description':
        'Clean reference render at the fixed 200 DPI analysis scale over the '
        'production raster and OCR ports; this is the reference variant for '
        'both raw text and semantic assignment.',
    'evidenceClass': 'EMULATOR',
    'requiresExactCriticalLines': true,
    'maxCer': 0.02,
    'maxSpecialCharacterRecallLoss': 0.0,
    'reference': true,
  },
  <String, Object?>{
    'id': 'clean-150dpi',
    'description':
        'Raw OCR capture at 150 DPI through the production raster and OCR '
        'ports. The semantic pipeline keeps its fixed 200 DPI analysis raster, '
        'so this variant qualifies the DPI effect on raw text only.',
    'evidenceClass': 'EMULATOR',
    'requiresExactCriticalLines': false,
    'maxCer': 0.08,
    'maxSpecialCharacterRecallLoss': 0.2,
    'reference': false,
  },
  <String, Object?>{
    'id': 'clean-300dpi',
    'description':
        'Raw OCR capture at 300 DPI through the production raster and OCR '
        'ports. The semantic pipeline keeps its fixed 200 DPI analysis raster, '
        'so this variant qualifies the DPI effect on raw text only.',
    'evidenceClass': 'EMULATOR',
    'requiresExactCriticalLines': false,
    'maxCer': 0.05,
    'maxSpecialCharacterRecallLoss': 0.1,
    'reference': false,
  },
  <String, Object?>{
    'id': 'scan-150dpi-low-contrast',
    'description': '150 DPI scan with reduced contrast and a light gray wash.',
    'evidenceClass': 'EMULATOR_INJECTED_RASTER',
    'requiresExactCriticalLines': false,
    'maxCer': 0.18,
    'maxSpecialCharacterRecallLoss': 0.4,
    'reference': false,
  },
  <String, Object?>{
    'id': 'scan-200dpi-shadow',
    'description': '200 DPI scan with a soft page shadow in one corner.',
    'evidenceClass': 'EMULATOR_INJECTED_RASTER',
    'requiresExactCriticalLines': false,
    'maxCer': 0.15,
    'maxSpecialCharacterRecallLoss': 0.3,
    'reference': false,
  },
  <String, Object?>{
    'id': 'scan-200dpi-skew-3deg',
    'description':
        '200 DPI scan rotated by three degrees about the page '
        'centre on a white background.',
    'evidenceClass': 'EMULATOR_INJECTED_RASTER',
    'requiresExactCriticalLines': false,
    'maxCer': 0.2,
    'maxSpecialCharacterRecallLoss': 0.4,
    'reference': false,
  },
  <String, Object?>{
    'id': 'scan-200dpi-jpeg-q35',
    'description':
        '200 DPI scan compressed as a low-quality JPEG and decoded '
        'back to gray8.',
    'evidenceClass': 'EMULATOR_INJECTED_RASTER',
    'requiresExactCriticalLines': false,
    'maxCer': 0.15,
    'maxSpecialCharacterRecallLoss': 0.3,
    'reference': false,
  },
];

/// Matching fold used only for semantic comparison: case, NFC, and the German
/// umlaut digraphs. Never applied to raw text.
String matchingFold(String text) {
  return toNfc(text)
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss');
}

/// Composes the suite's German characters from NFD back to NFC.
String toNfc(String text) {
  String result = text;
  for (final MapEntry<String, String> entry in _decomposition.entries) {
    result = result.replaceAll(entry.value, entry.key);
  }
  return result;
}

/// Decomposes the suite's German characters to NFD (base letter + combining
/// diaeresis U+0308). Covers exactly the characters this suite prints.
String toNfd(String text) {
  final StringBuffer buffer = StringBuffer();
  for (final int rune in text.runes) {
    final String? decomposed = _decomposition[String.fromCharCode(rune)];
    buffer.write(decomposed ?? String.fromCharCode(rune));
  }
  return buffer.toString();
}

const Map<String, String> _decomposition = <String, String>{
  'Ä': 'A\u0308',
  'Ö': 'O\u0308',
  'Ü': 'U\u0308',
  'ä': 'a\u0308',
  'ö': 'o\u0308',
  'ü': 'u\u0308',
};

String _hex4(int codePoint) {
  return codePoint.toRadixString(16).toUpperCase().padLeft(4, '0');
}

/// One page under construction that records the ground truth as it draws.
final class _PageBuilder {
  _PageBuilder({required this.font, required this.pageIndex})
    : page = FontPdfPage(widthPt: pageWidthPt, heightPt: pageHeightPt);

  final TrueTypeFont font;
  final int pageIndex;
  final FontPdfPage page;
  final List<GtLine> lines = <GtLine>[];
  final List<GtField> fields = <GtField>[];

  String _nextId() =>
      'p$pageIndex-l${(lines.length + 1).toString().padLeft(2, '0')}';

  double line(
    String text, {
    required double yTop,
    required double size,
    required String role,
    double xPt = marginLeftPt,
    bool bold = false,
    bool critical = false,
    String? fieldId,
  }) {
    final double width = page.text(
      x: xPt,
      yTop: yTop,
      size: size,
      text: text,
      font: font,
      bold: bold,
    );
    lines.add(
      GtLine(
        id: _nextId(),
        pageIndex: pageIndex,
        text: text,
        role: role,
        xPt: xPt,
        yPt: yTop,
        widthPt: width,
        heightPt: size * 1.2,
        fontSizePt: size,
        bold: bold,
        critical: critical,
        fieldId: fieldId,
      ),
    );
    return width;
  }

  void section(String text, double yTop) {
    line(text, yTop: yTop, size: 11, role: 'section', bold: true);
  }

  void field({
    required String id,
    required String label,
    required String type,
    required double yTop,
    double labelX = marginLeftPt,
    double fieldX = 190,
    double width = 300,
    double height = 18,
    String? hint,
  }) {
    if (type == 'checkbox' || type == 'signature') {
      throw ArgumentError('use checkbox()/signature() for $type');
    }
    final String labelId = _nextId();
    line(
      label,
      yTop: yTop + 2,
      size: 10,
      role: 'label',
      xPt: labelX,
      fieldId: id,
    );
    page.line(fieldX, yTop + height, fieldX + width, yTop + height, width: 0.7);
    fields.add(
      GtField(
        id: id,
        pageIndex: pageIndex,
        type: type,
        label: label,
        labelLineId: labelId,
        xPt: fieldX,
        yPt: yTop,
        widthPt: width,
        heightPt: height,
      ),
    );
    if (hint != null) {
      line(
        hint,
        yTop: yTop + 5,
        size: 7,
        role: 'hint',
        xPt: fieldX + width + 7,
      );
    }
  }

  void multiline({
    required String id,
    required String label,
    required double yTop,
    double labelX = marginLeftPt,
    double fieldX = 190,
    double width = 300,
    double height = 66,
  }) {
    final String labelId = _nextId();
    line(
      label,
      yTop: yTop + 2,
      size: 10,
      role: 'label',
      xPt: labelX,
      fieldId: id,
    );
    page.rect(fieldX, yTop, width, height);
    fields.add(
      GtField(
        id: id,
        pageIndex: pageIndex,
        type: 'multiline',
        label: label,
        labelLineId: labelId,
        xPt: fieldX,
        yPt: yTop,
        widthPt: width,
        heightPt: height,
      ),
    );
  }

  void checkbox({
    required String id,
    required String label,
    required double xPt,
    required double yPt,
    double size = 10,
  }) {
    page.rect(xPt, yPt, size, size);
    final String labelId = _nextId();
    line(
      label,
      yTop: yPt - 1,
      size: 9,
      role: 'label',
      xPt: xPt + size + 6,
      fieldId: id,
    );
    fields.add(
      GtField(
        id: id,
        pageIndex: pageIndex,
        type: 'checkbox',
        label: label,
        labelLineId: labelId,
        xPt: xPt,
        yPt: yPt,
        widthPt: size,
        heightPt: size,
      ),
    );
  }

  void signature({
    required String id,
    required String label,
    required double yTop,
    double labelX = marginLeftPt,
    double lineX = 190,
    double lineWidth = 300,
  }) {
    final String labelId = _nextId();
    line(
      label,
      yTop: yTop + 2,
      size: 10,
      role: 'label',
      xPt: labelX,
      fieldId: id,
    );
    page.line(lineX, yTop + 30, lineX + lineWidth, yTop + 30, width: 0.7);
    fields.add(
      GtField(
        id: id,
        pageIndex: pageIndex,
        type: 'signature',
        label: label,
        labelLineId: labelId,
        xPt: lineX,
        yPt: yTop,
        widthPt: lineWidth,
        heightPt: 30,
      ),
    );
  }

  void footer(String pageLabel) {
    page.line(
      marginLeftPt,
      pageHeightPt - 46,
      pageWidthPt - marginLeftPt,
      pageHeightPt - 46,
    );
    line(
      'Synthetisches Testdokument – kein amtliches Formular – '
      'keine personenbezogenen Daten',
      yTop: pageHeightPt - 38,
      size: 7,
      role: 'footer',
    );
    final double width = font.advancePt(pageLabel, 8);
    line(
      pageLabel,
      yTop: pageHeightPt - 38,
      size: 8,
      role: 'footer',
      xPt: pageWidthPt - marginLeftPt - width,
    );
  }
}

/// UTF-8 encoding helper shared with the generator.
List<int> utf8Bytes(Object? value) {
  return utf8.encode(const JsonEncoder.withIndent('  ').convert(value));
}
