// Synthetic fixture catalogue for the Feldexa Web development surface (T009).
//
// Every document here is fictional and generated from this file. There is no
// third-party form content, no personal data, no network access, and no
// randomness. The layout doubles as the source for the expected OCR blocks and
// the ground-truth field rectangles, so the three artifacts cannot drift.
//
// Geometry is in page display points (top-left origin, y down), matching
// `contracts/coordinates-and-geometry.md`.

import 'pdf_writer.dart';

/// A rectangle in page display points.
class PtRect {
  const PtRect(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, Object> toJsonPoints() {
    return <String, Object>{'x': x, 'y': y, 'width': width, 'height': height};
  }

  Map<String, Object> toJsonManifest() {
    return <String, Object>{
      'xPt': x,
      'yPt': y,
      'widthPt': width,
      'heightPt': height,
    };
  }
}

/// One printed OCR line.
class OcrLine {
  const OcrLine(this.rect, this.text, this.confidence);

  final PtRect rect;
  final String text;
  final double confidence;

  Map<String, Object> toJson() {
    return <String, Object>{
      'rect': rect.toJsonPoints(),
      'text': text,
      'confidence': confidence,
    };
  }
}

/// One expected OCR block returned by the SIMULATED OCR adapter.
class OcrBlock {
  const OcrBlock({
    required this.rect,
    required this.text,
    required this.confidence,
  });

  final PtRect rect;
  final String text;
  final double confidence;

  Map<String, Object> toJson() {
    return <String, Object>{
      'rect': rect.toJsonPoints(),
      'text': text,
      'confidence': confidence,
      'lines': <Map<String, Object>>[OcrLine(rect, text, confidence).toJson()],
    };
  }
}

/// One page of expected OCR output.
class OcrPage {
  OcrPage({
    required this.pageIndex,
    required this.widthPt,
    required this.heightPt,
    required this.rotation,
    required this.blocks,
  });

  final int pageIndex;
  final double widthPt;
  final double heightPt;
  final int rotation;
  final List<OcrBlock> blocks;

  Map<String, Object?> toJson() {
    final List<OcrBlock> sorted = List<OcrBlock>.of(blocks)
      ..sort((OcrBlock a, OcrBlock b) {
        final int byTop = _roundEighth(a.rect.y)
            .compareTo(_roundEighth(b.rect.y));
        if (byTop != 0) {
          return byTop;
        }
        final int byLeft = _roundEighth(a.rect.x)
            .compareTo(_roundEighth(b.rect.x));
        if (byLeft != 0) {
          return byLeft;
        }
        return a.text.compareTo(b.text);
      });
    return <String, Object?>{
      'pageIndex': pageIndex,
      'widthPt': widthPt,
      'heightPt': heightPt,
      'rotation': rotation,
      'blocks': sorted.map((OcrBlock block) => block.toJson()).toList(),
    };
  }
}

int _roundEighth(double value) => (value * 8).round();

/// One ground-truth input region.
class GtField {
  const GtField({
    required this.id,
    required this.type,
    required this.pageIndex,
    required this.rect,
    required this.label,
    this.required = false,
  });

  final String id;
  final String type;
  final int pageIndex;
  final PtRect rect;
  final String label;
  final bool required;

  Map<String, Object> toJson() {
    return <String, Object>{
      'id': id,
      'type': type,
      'pageIndex': pageIndex,
      'rect': rect.toJsonManifest(),
      'label': label,
      'required': required,
    };
  }
}

/// One page plus its expected OCR blocks and ground truth.
class FormPage {
  FormPage({
    required this.pageIndex,
    required this.page,
    this.ocrConfidence = 0.97,
  }) {
    if (pageIndex < 0) {
      throw ArgumentError('pageIndex must be non-negative');
    }
  }

  final int pageIndex;
  final PdfPage page;
  final double ocrConfidence;
  final List<OcrBlock> blocks = <OcrBlock>[];
  final List<GtField> fields = <GtField>[];

  double get width => page.displayWidth;
  double get height => page.displayHeight;

  void text(
    String value,
    double x,
    double yTop, {
    double size = 10,
    bool bold = false,
    double? confidence,
    bool recordOcr = true,
  }) {
    page.text(x: x, yTop: yTop, size: size, text: value, bold: bold);
    if (recordOcr) {
      final double width = approxTextWidth(value, size, bold: bold);
      final PtRect rect = PtRect(x, yTop, width, size * 1.2);
      blocks.add(
        OcrBlock(
          rect: rect,
          text: value,
          confidence: confidence ?? ocrConfidence,
        ),
      );
    }
  }

  void section(String value, double y, {double x = 56.7}) {
    text(value, x, y, size: 11, bold: true);
  }

  void field({
    required String id,
    required String label,
    required String type,
    required double y,
    double labelX = 56.7,
    double fieldX = 190,
    double width = 300,
    double height = 18,
    String? hint,
    bool boxed = false,
  }) {
    if (type == 'checkbox' || type == 'signature') {
      throw ArgumentError('use checkbox()/signature() for $type');
    }
    text(label, labelX, y + 2, size: 10);
    if (boxed || type == 'multiline') {
      page.rect(fieldX, y, width, height);
    } else {
      page.line(fieldX, y + height, fieldX + width, y + height, width: 0.7);
    }
    fields.add(
      GtField(
        id: id,
        type: type,
        pageIndex: pageIndex,
        rect: PtRect(fieldX, y, width, height),
        label: label,
      ),
    );
    if (hint != null) {
      text(hint, fieldX + width + 7, y + 5, size: 7);
    }
  }

  void boxedField({
    required String id,
    required String label,
    required String type,
    required double x,
    required double y,
    double width = 140,
    double height = 24,
  }) {
    text(label, x, y - 13, size: 8);
    page.rect(x, y, width, height);
    fields.add(
      GtField(
        id: id,
        type: type,
        pageIndex: pageIndex,
        rect: PtRect(x, y, width, height),
        label: label,
      ),
    );
  }

  void checkbox({
    required String id,
    required String label,
    required double x,
    required double y,
    double size = 10,
  }) {
    page.rect(x, y, size, size);
    fields.add(
      GtField(
        id: id,
        type: 'checkbox',
        pageIndex: pageIndex,
        rect: PtRect(x, y, size, size),
        label: label,
      ),
    );
    text(label, x + size + 6, y - 1, size: 9);
  }

  void signature({
    required String id,
    required String label,
    required double y,
    double labelX = 56.7,
    double lineX = 190,
    double lineWidth = 300,
  }) {
    text(label, labelX, y + 2, size: 10);
    page.line(lineX, y + 30, lineX + lineWidth, y + 30, width: 0.7);
    fields.add(
      GtField(
        id: id,
        type: 'signature',
        pageIndex: pageIndex,
        rect: PtRect(lineX, y, lineWidth, 30),
        label: label,
      ),
    );
  }

  void footer(String pageLabel) {
    page.line(56.7, height - 46, width - 56.7, height - 46, width: 0.6);
    text(
      'Synthetisches Testdokument – kein amtliches Formular – '
      'keine personenbezogenen Daten',
      56.7,
      height - 38,
      size: 7,
    );
    final double labelWidth = approxTextWidth(pageLabel, 8);
    text(pageLabel, width - 56.7 - labelWidth, height - 38, size: 8);
  }
}

/// A generated, valid synthetic form fixture.
class FormFixture {
  const FormFixture({
    required this.id,
    required this.title,
    required this.description,
    required this.role,
    required this.strata,
    required this.pages,
  });

  final String id;
  final String title;
  final String description;
  final String role;
  final List<String> strata;
  final List<FormPage> pages;

  PdfDocument document() {
    return PdfDocument(pages: pages.map((FormPage page) => page.page).toList());
  }

  List<OcrPage> ocrPages() {
    return pages
        .map(
          (FormPage page) => OcrPage(
            pageIndex: page.pageIndex,
            widthPt: page.width,
            heightPt: page.height,
            rotation: page.page.rotation,
            blocks: page.blocks,
          ),
        )
        .toList();
  }
}

const double a4Width = 595.28;
const double a4Height = 841.89;

/// Builds the four representative Web-development forms.
List<FormFixture> buildFormFixtures() {
  return <FormFixture>[
    _buildMeldebescheinigung(),
    _buildMerkblatt(),
    _buildGeometryReference(),
    _buildFieldReference(),
  ];
}

FormFixture _buildMeldebescheinigung() {
  final List<FormPage> pages = <FormPage>[];

  final FormPage page1 = FormPage(
    pageIndex: 0,
    page: PdfPage(widthPt: a4Width, heightPt: a4Height),
  );
  _municipalHeader(
    page1,
    title: 'Antrag auf Ausstellung einer Meldebescheinigung',
    subtitle: 'Bitte in Druckbuchstaben ausfüllen.',
  );
  page1.section('1. Angaben zur Person', 124);
  double y = 148;
  page1.field(id: 'p0-familienname', label: 'Familienname', type: 'text', y: y);
  y += 34;
  page1.field(id: 'p0-vorname', label: 'Vorname', type: 'text', y: y);
  y += 34;
  page1.field(
    id: 'p0-geburtsdatum',
    label: 'Geburtsdatum',
    type: 'date',
    y: y,
    hint: 'TT.MM.JJJJ',
  );
  y += 34;
  page1.field(id: 'p0-geburtsort', label: 'Geburtsort', type: 'text', y: y);
  y += 34;
  page1.field(
    id: 'p0-staatsangehoerigkeit',
    label: 'Staatsangehörigkeit',
    type: 'text',
    y: y,
  );

  page1.section('2. Anschrift', 330);
  y = 354;
  page1.field(
    id: 'p0-strasse',
    label: 'Straße und Hausnummer',
    type: 'text',
    y: y,
  );
  y += 34;
  page1.field(id: 'p0-plz', label: 'Postleitzahl', type: 'text', y: y);
  y += 34;
  page1.field(id: 'p0-ort', label: 'Ort', type: 'text', y: y);

  page1.section('3. Weitere Angaben', 474);
  page1.text('Geschlecht', 56.7, 502, size: 10);
  page1.checkbox(
    id: 'p0-geschlecht-weiblich',
    label: 'weiblich',
    x: 190,
    y: 502,
  );
  page1.checkbox(
    id: 'p0-geschlecht-maennlich',
    label: 'männlich',
    x: 300,
    y: 502,
  );
  page1.checkbox(id: 'p0-geschlecht-divers', label: 'divers', x: 410, y: 502);

  page1.field(id: 'p0-datum', label: 'Datum', type: 'date', y: 548);
  page1.signature(id: 'p0-unterschrift', label: 'Unterschrift', y: 612);
  page1.footer('Seite 1 von 2');
  pages.add(page1);

  final FormPage page2 = FormPage(
    pageIndex: 1,
    page: PdfPage(widthPt: a4Width, heightPt: a4Height),
  );
  _municipalHeader(
    page2,
    title: 'Antrag auf Ausstellung einer Meldebescheinigung',
    subtitle: 'Seite 2 – Grund, Gebühren und Zahlungsart.',
  );
  page2.section('4. Grund der Beantragung', 130);
  page2.field(
    id: 'p1-grund',
    label: 'Begründung',
    type: 'multiline',
    y: 152,
    width: 348.58,
    height: 76,
    boxed: true,
  );

  page2.section('5. Aufstellung der Gebühren', 262);
  _feeTable(page2, top: 286);

  page2.section('6. Zahlungsart', 452);
  page2.checkbox(id: 'p1-zahlung-bar', label: 'Barzahlung', x: 190, y: 480);
  page2.checkbox(
    id: 'p1-zahlung-ueberweisung',
    label: 'Überweisung',
    x: 330,
    y: 480,
  );

  page2.section('7. Ort, Datum und Unterschrift', 530);
  page2.field(id: 'p1-ort', label: 'Ort', type: 'text', y: 554);
  page2.field(id: 'p1-datum', label: 'Datum', type: 'date', y: 588);
  page2.signature(id: 'p1-unterschrift', label: 'Unterschrift', y: 626);
  page2.footer('Seite 2 von 2');
  pages.add(page2);

  return FormFixture(
    id: 'sf-001',
    title: 'Meldebescheinigung (zweispaltiger Behördenantrag, 2 Seiten)',
    description:
        'Two-page fictional municipal application with underlined text '
        'fields, a date mask, checkbox group, fee table, multiline reason, '
        'and signature lines.',
    role: 'editor',
    strata: <String>[
      'layout:underlined-fields',
      'layout:table',
      'authority:municipal',
      'pages:2',
    ],
    pages: pages,
  );
}

FormFixture _buildMerkblatt() {
  final List<List<String>> pageTexts = <List<String>>[
    <String>[
      'Dieses Merkblatt erläutert das Verfahren zur Ausstellung einer',
      'Meldebescheinigung bei der Musterstadt. Alle Angaben sind synthetisch.',
      'Bitte füllen Sie den Antrag vollständig in Druckbuchstaben aus und',
      'reichen Sie ihn persönlich oder schriftlich ein. Fehlende Angaben',
      'können die Bearbeitung verzögern; es werden keine Daten weitergegeben.',
    ],
    <String>[
      'Für die Bearbeitung wird ein gültiges Ausweisdokument benötigt.',
      'Die Meldebescheinigung wird nach Prüfung der Angaben ausgestellt.',
      'Die Gebühr richtet sich nach der Satzung der Musterstadt. Eine',
      'Quittung wird auf Wunsch ausgestellt. Die Bearbeitung erfolgt',
      'ausschließlich vor Ort; es gibt keinen Online-Versand.',
    ],
    <String>[
      'Die Angaben zur Person werden nur für dieses Verfahren verwendet.',
      'Eine Weitergabe an Dritte erfolgt nur, soweit dies gesetzlich',
      'vorgesehen ist. Nach Abschluss der Bearbeitung werden nicht',
      'benötigte Unterlagen datenschutzkonform vernichtet. Fragen richten',
      'Sie bitte an das Musteramt für Bürgerdienste.',
    ],
    <String>[
      'Bei Rückfragen nennen Sie bitte das Aktenzeichen aus dem Antrag.',
      'Die Bearbeitungszeit beträgt in der Regel fünf Werktage. Eine',
      'persönliche Abholung ist während der Öffnungszeiten möglich. Eine',
      'Zusendung per Post ist nur mit frankiertem Rückumschlag möglich.',
      'Die Musterstadt haftet nicht für Verzögerungen durch die Post.',
    ],
    <String>[
      'Hiermit bestätige ich, dass die gemachten Angaben vollständig und',
      'richtig sind. Mir ist bekannt, dass unrichtige Angaben rechtliche',
      'Folgen haben können. Ich habe das Merkblatt gelesen und verstanden.',
      'Diese Erklärung wird zusammen mit dem Antrag aufbewahrt.',
      'Ort, Datum und Unterschrift bitte auf dem Antrag ergänzen.',
    ],
  ];

  final List<String> fieldIds = <String>[
    'p0-aktenzeichen',
    'p1-datum',
    'p2-kopie',
    'p3-telefon',
    'p4-unterschrift',
  ];
  final List<String> fieldLabels = <String>[
    'Aktenzeichen',
    'Datum',
    'Kopie gewünscht',
    'Telefon',
    'Unterschrift',
  ];
  final List<String> fieldTypes = <String>[
    'text',
    'date',
    'checkbox',
    'text',
    'signature',
  ];

  final List<FormPage> pages = <FormPage>[];
  for (int index = 0; index < 5; index++) {
    final FormPage page = FormPage(
      pageIndex: index,
      page: PdfPage(widthPt: a4Width, heightPt: a4Height),
    );
    _municipalHeader(
      page,
      title: 'Merkblatt zur Antragstellung',
      subtitle: 'Hinweise und Erklärung – Seite ${index + 1} von 5.',
    );
    page.section('Hinweise', 130);
    double y = 156;
    for (final String line in pageTexts[index]) {
      page.text(line, 56.7, y, size: 9.5);
      y += 18;
    }
    page.section('Angaben zum Verfahren', 330);
    if (fieldTypes[index] == 'checkbox') {
      page.text('Unterlagen', 56.7, 360, size: 10);
      page.checkbox(
        id: fieldIds[index],
        label: fieldLabels[index],
        x: 190,
        y: 360,
      );
    } else if (fieldTypes[index] == 'signature') {
      page.signature(id: fieldIds[index], label: fieldLabels[index], y: 386);
    } else {
      page.field(
        id: fieldIds[index],
        label: fieldLabels[index],
        type: fieldTypes[index],
        y: 360,
      );
    }
    page.text(
      'Bearbeitung nur nach vollständiger Prüfung. Es werden keine '
      'personenbezogenen Daten gespeichert.',
      56.7,
      620,
      size: 9,
    );
    page.footer('Seite ${index + 1} von 5');
    pages.add(page);
  }

  return FormFixture(
    id: 'sf-002',
    title: 'Merkblatt und Erklärung (fünf Seiten)',
    description:
        'Five-page fictional information sheet. Exercises page-strip '
        'navigation, page ordering, and one different field type per page.',
    role: 'navigation',
    strata: <String>['pages:5', 'layout:text-lines', 'authority:municipal'],
    pages: pages,
  );
}

FormFixture _buildGeometryReference() {
  final List<FormPage> pages = <FormPage>[];
  final List<_GeometryPage> specs = <_GeometryPage>[
    const _GeometryPage(
      widthPt: a4Width,
      heightPt: a4Height,
      rotation: 0,
      label: 'Seite 1 – A4 hoch, /Rotate 0',
    ),
    const _GeometryPage(
      widthPt: a4Height,
      heightPt: a4Width,
      rotation: 0,
      label: 'Seite 2 – A4 quer, /Rotate 0',
    ),
    const _GeometryPage(
      widthPt: a4Width,
      heightPt: a4Height,
      rotation: 90,
      label: 'Seite 3 – A4 hoch, /Rotate 90 (Anzeige quer)',
    ),
    const _GeometryPage(
      widthPt: a4Width,
      heightPt: a4Height,
      rotation: 180,
      label: 'Seite 4 – A4 hoch, /Rotate 180',
    ),
    const _GeometryPage(
      widthPt: 419.53,
      heightPt: 595.28,
      rotation: 270,
      label: 'Seite 5 – A5 hoch, /Rotate 270 (Anzeige quer)',
    ),
  ];

  for (int index = 0; index < specs.length; index++) {
    final _GeometryPage spec = specs[index];
    final FormPage page = FormPage(
      pageIndex: index,
      page: PdfPage(
        widthPt: spec.widthPt,
        heightPt: spec.heightPt,
        rotation: spec.rotation,
      ),
    );
    final double width = page.width;
    final double height = page.height;
    page.text('Geometrie-Referenz', 36, 34, size: 14, bold: true);
    page.text(spec.label, 36, 56, size: 9);
    page.text(
      'Anzeigefläche: ${width.toStringAsFixed(2)} × '
      '${height.toStringAsFixed(2)} pt',
      36,
      70,
      size: 9,
    );

    page.boxedField(
      id: 'p$index-feld-oben-links',
      label: 'Feld oben links',
      type: 'text',
      x: 36,
      y: 96,
    );
    page.boxedField(
      id: 'p$index-feld-oben-rechts',
      label: 'Feld oben rechts',
      type: 'text',
      x: width - 36 - 140,
      y: 96,
    );
    page.boxedField(
      id: 'p$index-feld-unten-links',
      label: 'Feld unten links',
      type: 'text',
      x: 36,
      y: height - 92,
    );
    page.boxedField(
      id: 'p$index-feld-unten-rechts',
      label: 'Feld unten rechts',
      type: 'text',
      x: width - 36 - 140,
      y: height - 92,
    );
    page.checkbox(
      id: 'p$index-mitte',
      label: 'Mitte',
      x: width / 2 - 5,
      y: height / 2,
    );
    page.footer('Seite ${index + 1} von ${specs.length}');
    pages.add(page);
  }

  return FormFixture(
    id: 'sf-003',
    title: 'Geometrie-Referenz (gemischte Größen und Drehungen)',
    description:
        'Five pages covering A4 portrait, A4 landscape, /Rotate 90, '
        '/Rotate 180, and A5 /Rotate 270 with corner fields and a centered '
        'checkbox for display-space mapping.',
    role: 'geometry',
    strata: <String>[
      'geometry:rotation',
      'geometry:mixed-page-sizes',
      'pages:5',
    ],
    pages: pages,
  );
}

FormFixture _buildFieldReference() {
  final FormPage page = FormPage(
    pageIndex: 0,
    page: PdfPage(widthPt: a4Width, heightPt: a4Height),
  );
  _municipalHeader(
    page,
    title: 'Felder- und Zeichensatz-Referenz',
    subtitle: 'Alle Feldarten, deutsche Sonderzeichen und Überlaufprüfung.',
  );

  page.section('1. Feldarten', 126);
  double y = 150;
  page.field(
    id: 'p0-strasse',
    label: 'Straße und Hausnummer',
    type: 'text',
    y: y,
  );
  y += 36;
  page.field(id: 'p0-groesse', label: 'Größe in cm', type: 'number', y: y);
  y += 36;
  page.field(id: 'p0-betrag', label: 'Betrag in €', type: 'number', y: y);
  y += 36;
  page.field(
    id: 'p0-geburtsdatum',
    label: 'Geburtsdatum',
    type: 'date',
    y: y,
    hint: 'TT.MM.JJJJ',
  );
  y += 36;
  page.field(id: 'p0-telefon', label: 'Telefon', type: 'text', y: y);
  y += 36;
  page.field(
    id: 'p0-langtext',
    label: 'Langtext (Überlaufprüfung)',
    type: 'text',
    y: y,
    fieldX: 260,
    width: 90,
  );

  page.section('2. Mehrzeilige Anmerkung', 392);
  page.field(
    id: 'p0-anmerkung',
    label: 'Begründung / Äußerung',
    type: 'multiline',
    y: 414,
    width: 348.58,
    height: 66,
    boxed: true,
  );

  page.section('3. Einverständnis', 506);
  page.checkbox(
    id: 'p0-einverstaendnis',
    label: 'Einverständnis erteilt',
    x: 190,
    y: 530,
  );
  page.checkbox(id: 'p0-kopie', label: 'Kopie gewünscht', x: 370, y: 530);

  page.signature(id: 'p0-unterschrift', label: 'Unterschrift', y: 582);

  page.text(
    'Sonderzeichen: ÄÖÜäöüß € „Deutsch“ – — … und ein längerer Satz zur '
    'Prüfung der Zeilenbreite.',
    56.7,
    660,
    size: 9.5,
  );
  page.text(
    'Hinweis: Dieses Dokument ist synthetisch und enthält keine realen '
    'Personendaten.',
    56.7,
    690,
    size: 9,
  );
  page.text(
    'Es dient ausschließlich der Entwicklung und Prüfung des Editors.',
    56.7,
    706,
    size: 9,
  );
  page.footer('Seite 1 von 1');

  return FormFixture(
    id: 'sf-004',
    title: 'Felder- und Zeichensatz-Referenz',
    description:
        'Single-page reference with all six field types, German special '
        'characters, a narrow overflow field, and a multiline area.',
    role: 'fields',
    strata: <String>[
      'layout:all-field-types',
      'characters:german',
      'layout:overflow',
    ],
    pages: <FormPage>[page],
  );
}

void _municipalHeader(
  FormPage page, {
  required String title,
  required String subtitle,
}) {
  page.text('MUSTERSTADT', 56.7, 32, size: 9, bold: true);
  page.text('Musteramt für Bürgerdienste', 56.7, 44, size: 9);
  page.text(
    'SYNTHETISCHES TESTDOKUMENT – kein amtliches Formular',
    330,
    44,
    size: 7,
  );
  page.page.line(56.7, 62, page.width - 56.7, 62, width: 1.2);
  page.text(title, 56.7, 76, size: 15, bold: true);
  page.text(subtitle, 56.7, 98, size: 9);
}

void _feeTable(FormPage page, {required double top}) {
  const double left = 56.7;
  const double firstWidth = 60;
  const double secondWidth = 302.3;
  const double thirdWidth = 120;
  const double rowHeight = 26;
  const int rows = 5;
  final double right = left + firstWidth + secondWidth + thirdWidth;
  final double bottom = top + rows * rowHeight;

  page.page.rect(left, top, right - left, bottom - top);
  for (int row = 1; row < rows; row++) {
    page.page.line(left, top + row * rowHeight, right, top + row * rowHeight);
  }
  page.page.line(left + firstWidth, top, left + firstWidth, bottom);
  page.page.line(
    left + firstWidth + secondWidth,
    top,
    left + firstWidth + secondWidth,
    bottom,
  );

  page.text('Position', left + 8, top + 8, size: 9, bold: true);
  page.text('Leistung', left + firstWidth + 8, top + 8, size: 9, bold: true);
  page.text(
    'Betrag',
    left + firstWidth + secondWidth + 8,
    top + 8,
    size: 9,
    bold: true,
  );

  const List<String> positions = <String>['1', '2', '3', '4'];
  const List<String> services = <String>[
    'Meldebescheinigung',
    'Beglaubigung einer Kopie',
    'Versand mit Rückumschlag',
    'Summe',
  ];
  for (int row = 0; row < positions.length; row++) {
    final double rowTop = top + (row + 1) * rowHeight;
    page.text(positions[row], left + 8, rowTop + 8, size: 9);
    page.text(services[row], left + firstWidth + 8, rowTop + 8, size: 9);
    final double cellX = left + firstWidth + secondWidth + 8;
    page.page.line(
      cellX,
      rowTop + rowHeight - 5,
      right - 8,
      rowTop + rowHeight - 5,
      width: 0.6,
    );
    page.fields.add(
      GtField(
        id: 'p1-betrag-${row + 1}',
        type: 'number',
        pageIndex: page.pageIndex,
        rect: PtRect(cellX, rowTop + 4, thirdWidth - 16, 18),
        label: 'Betrag ${positions[row]}',
      ),
    );
  }
}

class _GeometryPage {
  const _GeometryPage({
    required this.widthPt,
    required this.heightPt,
    required this.rotation,
    required this.label,
  });

  final double widthPt;
  final double heightPt;
  final int rotation;
  final String label;
}
