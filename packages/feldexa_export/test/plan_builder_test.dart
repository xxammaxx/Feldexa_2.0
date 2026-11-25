// T102 export plan builder tests.
//
// These are host-VM tests (`NONE` evidence). They pin `contracts/export-plan.md`
// §1 (preflight → layout → plan), §2 (canonical plan shape, deterministic op
// order), §2.3 (no forbidden plan content), and
// `contracts/coordinates-and-geometry.md` §5 (per-op `pdfRect` and the page
// CTM). They prove plan construction only; they cannot prove PDF output
// (T108/T109).
@TestOn('vm')
library;

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_export/feldexa_export.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/export_fixtures.dart';

late final ExportFontMetrics _metrics;
late final ExportPlanBuilder _builder;

void main() {
  setUpAll(() {
    _metrics = loadBundledMetrics();
    _builder = ExportPlanBuilder(metrics: _metrics);
  });

  test('builds one op per field in field order with the page CTM', () {
    final ConfirmedField name = confirmedField(
      id: uuid(10),
      type: FieldType.text,
      rect: Rect.fromLTWH(148.5, 302, 210, 14.5),
      label: 'Name',
      order: 0,
      provenance: Provenance.template,
    );
    final ConfirmedField amount = confirmedField(
      id: uuid(11),
      type: FieldType.number,
      rect: Rect.fromLTWH(148.5, 330, 120, 14.5),
      label: 'Betrag',
      order: 1,
    );
    final ConfirmedField date = confirmedField(
      id: uuid(12),
      type: FieldType.date,
      rect: Rect.fromLTWH(148.5, 360, 120, 14.5),
      label: 'Datum',
      order: 2,
    );
    final ConfirmedField agreed = confirmedField(
      id: uuid(13),
      type: FieldType.checkbox,
      rect: Rect.fromLTWH(420, 210, 10, 10),
      label: 'Zustimmung',
      order: 3,
    );
    final ConfirmedField declined = confirmedField(
      id: uuid(14),
      type: FieldType.checkbox,
      rect: Rect.fromLTWH(440, 210, 10, 10),
      label: 'Ablehnung',
      order: 4,
    );
    final ConfirmedField note = confirmedField(
      id: uuid(15),
      type: FieldType.multiline,
      rect: Rect.fromLTWH(40, 400, 300, 60),
      label: 'Bemerkung',
      order: 5,
    );
    final ConfirmedField empty = confirmedField(
      id: uuid(16),
      type: FieldType.text,
      rect: Rect.fromLTWH(40, 500, 300, 14.5),
      label: 'Leerfeld',
      order: 6,
    );
    final ConfirmedField signatureField = confirmedField(
      id: uuid(17),
      type: FieldType.signature,
      rect: Rect.fromLTWH(320, 720, 180, 50),
      label: 'Unterschrift',
      order: 7,
    );
    final Document document = buildDocument(
      fields: <ConfirmedField>[
        name,
        amount,
        date,
        agreed,
        declined,
        note,
        empty,
        signatureField,
      ],
      values: <String, FieldValue>{
        name.id: textValue('Müller-Lüdenscheidt'),
        amount.id: numberValue('1234.56', rawGerman: '1.234,56'),
        date.id: dateValue('2026-01-05'),
        agreed.id: checkboxValue(),
        declined.id: checkboxValue(checked: false),
        note.id: multilineValue('Zeile eins\nZeile zwei  '),
        signatureField.id: signatureValue(uuid(18)),
      },
      signatures: <String, SignatureMark>{
        signatureField.id: signatureMark(
          assetId: uuid(18),
          fieldId: signatureField.id,
          fieldRect: signatureField.rect,
        ),
      },
    );

    final ExportPlanBuildResult result = _builder.build(
      document: document,
      pageGeometries: <PageGeometry>[a4()],
      values: document.values,
      signatures: document.signatures,
      evidenceClass: 'emulator',
      sourceSha256: sourceSha256,
      revisionId: uuid(19),
      validatedAt: at(),
    );
    expect(result, isA<ExportPlanBuildSuccess>());
    final ExportPlan plan = (result as ExportPlanBuildSuccess).plan;

    expect(plan.schemaVersion, exportPlanSchemaVersion);
    expect(plan.documentId, document.id);
    expect(plan.revisionId, uuid(19));
    expect(plan.sourceSha256, sourceSha256);
    expect(plan.pageCount, 1);
    expect(plan.evidenceClass, 'emulator');
    expect(plan.font.family, 'NotoSans');
    expect(plan.font.metricsVersion, 'noto-sans-2.013-v1');
    expect(plan.warnings, isEmpty);
    expect(plan.info.emptyFieldCount, 1);
    expect(plan.info.unresolvedSuggestionCount, 0);
    expect(result.trimmedTrailingSpaceCount, 2);

    final ExportPage page = plan.pages.single;
    expect(page.index, 0);
    expect(page.rotation, 0);
    expect(page.mediaBox.width, closeTo(595.28, 1e-9));
    expect(page.displaySize.height, closeTo(841.89, 1e-9));
    expect(page.ctm.toJson(), ExportCtm.fromGeometry(a4()).toJson());

    // One op per field with content, in field order; the unchecked box and
    // the empty field draw nothing.
    expect(page.ops.map((ExportOp op) => op.fieldId), <String>[
      name.id,
      amount.id,
      date.id,
      agreed.id,
      note.id,
      signatureField.id,
    ]);
    final ExportTextOp nameOp = page.ops.first as ExportTextOp;
    expect(nameOp.lines, <String>['Müller-Lüdenscheidt']);
    expect(nameOp.provenance, Provenance.template);
    expect(nameOp.pdfRect, a4().displayRectToPdf(name.rect));
    final ExportTextOp amountOp = page.ops[1] as ExportTextOp;
    expect(amountOp.lines, <String>['1234,56']);
    expect(amountOp.provenance, Provenance.user);
    final ExportTextOp dateOp = page.ops[2] as ExportTextOp;
    expect(dateOp.lines, <String>['05.01.2026']);
    final ExportCheckboxOp checkboxOp = page.ops[3] as ExportCheckboxOp;
    expect(checkboxOp.checked, isTrue);
    expect(checkboxOp.insetPt, 1.5);
    final ExportTextOp noteOp = page.ops[4] as ExportTextOp;
    expect(noteOp.lines, <String>['Zeile eins', 'Zeile zwei']);
    final ExportImageOp signatureOp = page.ops[5] as ExportImageOp;
    expect(signatureOp.assetId, uuid(18));
    expect(signatureOp.fit, 'contain');
    expect(signatureOp.align, 'center');
  });

  test(
    'produces a canonical, round-trippable plan without forbidden content',
    () {
      final ConfirmedField name = confirmedField(
        id: uuid(20),
        type: FieldType.text,
        rect: Rect.fromLTWH(148.5, 302, 210, 14.5),
        label: 'FeldbezeichnungNurImDialog',
      );
      final Document document = buildDocument(
        fields: <ConfirmedField>[name],
        values: <String, FieldValue>{name.id: textValue('Straße 42')},
      );
      final ExportPlanBuildSuccess built = _builder.build(
        document: document,
        pageGeometries: <PageGeometry>[a4()],
        values: document.values,
        signatures: document.signatures,
        evidenceClass: 'device',
        sourceSha256: sourceSha256,
        revisionId: uuid(21),
        validatedAt: at(),
      ) as ExportPlanBuildSuccess;
      final Map<String, Object?> json = built.plan.toJson();

      // Round-trip: the canonical JSON reads back to an equal plan.
      expect(ExportPlan.fromJson(json), built.plan);
      // Determinism: the same snapshot yields the same canonical bytes.
      final ExportPlanBuildSuccess again = _builder.build(
        document: document,
        pageGeometries: <PageGeometry>[a4()],
        values: document.values,
        signatures: document.signatures,
        evidenceClass: 'device',
        sourceSha256: sourceSha256,
        revisionId: uuid(21),
        validatedAt: at(),
      ) as ExportPlanBuildSuccess;
      expect(
        canonicalJsonEncode(again.plan.toJson()),
        canonicalJsonEncode(json),
      );

      // §2.3: no field labels, no absolute paths, no URIs, no form definitions.
      final String encoded = canonicalJsonEncode(json);
      expect(encoded.contains('FeldbezeichnungNurImDialog'), isFalse);
      expect(encoded.contains('"/'), isFalse);
      expect(encoded.contains('://'), isFalse);
      expect(encoded.contains('acroform'), isFalse);
      expect(json.keys.toSet(), <String>{
        'schemaVersion',
        'documentId',
        'revisionId',
        'sourceSha256',
        'pageCount',
        'evidenceClass',
        'font',
        'pages',
        'warnings',
        'info',
      });
    },
  );

  test('records the trimmed trailing spaces in info', () {
    final ConfirmedField note = confirmedField(
      id: uuid(30),
      type: FieldType.multiline,
      rect: Rect.fromLTWH(40, 400, 300, 60),
    );
    final Document document = buildDocument(
      fields: <ConfirmedField>[note],
      values: <String, FieldValue>{note.id: multilineValue('Hallo   \nWelt  ')},
    );
    final ExportPlanBuildSuccess built = _builder.build(
      document: document,
      pageGeometries: <PageGeometry>[a4()],
      values: document.values,
      signatures: document.signatures,
      evidenceClass: 'none',
      sourceSha256: sourceSha256,
      revisionId: uuid(31),
      validatedAt: at(),
    ) as ExportPlanBuildSuccess;
    expect(built.trimmedTrailingSpaceCount, 5);
    expect(built.plan.info.toJson()['trimmedTrailingSpaceCount'], 5);
    expect(
      ExportPlan.fromJson(built.plan.toJson()).info.toJson(),
      built.plan.info.toJson(),
    );
  });

  test('keeps every page, its own geometry, and its own CTM', () {
    final PageGeometry portrait = a4();
    final PageGeometry landscape = PageGeometry(
      mediaBox: Rect.fromLTWH(0, 0, 595.28, 841.89),
      rotation: 90,
    );
    final ConfirmedField first = confirmedField(
      id: uuid(40),
      type: FieldType.text,
      rect: Rect.fromLTWH(100, 50, 120, 20),
      pageIndex: 0,
      order: 0,
    );
    final ConfirmedField second = confirmedField(
      id: uuid(41),
      type: FieldType.text,
      rect: Rect.fromLTWH(100, 50, 120, 20),
      pageIndex: 1,
      order: 1,
    );
    final Document document = buildDocument(
      fields: <ConfirmedField>[first, second],
      pageCount: 2,
      values: <String, FieldValue>{
        first.id: textValue('Seite eins'),
        second.id: textValue('Seite zwei'),
      },
    );
    final ExportPlanBuildSuccess built = _builder.build(
      document: document,
      pageGeometries: <PageGeometry>[portrait, landscape],
      values: document.values,
      signatures: document.signatures,
      evidenceClass: 'emulator',
      sourceSha256: sourceSha256,
      revisionId: uuid(42),
      validatedAt: at(),
    ) as ExportPlanBuildSuccess;
    final ExportPlan plan = built.plan;

    expect(plan.pageCount, 2);
    expect(plan.pages[0].rotation, 0);
    expect(plan.pages[1].rotation, 90);
    expect(plan.pages[0].ops.single.fieldId, first.id);
    expect(plan.pages[1].ops.single.fieldId, second.id);
    expect(
      plan.pages[1].ctm.toJson(),
      ExportCtm.fromGeometry(landscape).toJson(),
    );
    expect(plan.pages[1].displaySize.width, closeTo(841.89, 1e-9));
    // Each op keeps the display rect and the matching PDF rect.
    for (int index = 0; index < plan.pages.length; index++) {
      final ExportPage page = plan.pages[index];
      final ExportOp op = page.ops.single;
      expect(op.rect, Rect.fromLTWH(100, 50, 120, 20));
      expect(op.pdfRect, page.geometry.displayRectToPdf(op.rect));
    }
  });

  group('blocking snapshots', () {
    test('returns the validation instead of a plan for text overflow', () {
      final double width = _metrics.advanceWidthPt('Müller-Lüdenscheidt', 12);
      final ConfirmedField field = confirmedField(
        id: uuid(50),
        type: FieldType.text,
        rect: Rect.fromLTWH(40, 40, width + 2.0, 20),
        label: 'Name',
      );
      final Document document = buildDocument(
        fields: <ConfirmedField>[field],
        values: <String, FieldValue>{
          field.id: textValue('Müller-Lüdenscheidt'),
        },
      );
      final ExportPlanBuildResult result = _builder.build(
        document: document,
        pageGeometries: <PageGeometry>[a4()],
        values: document.values,
        signatures: document.signatures,
        evidenceClass: 'emulator',
        sourceSha256: sourceSha256,
        revisionId: uuid(51),
        validatedAt: at(),
      );
      expect(result, isA<ExportPlanBuildBlocked>());
      final ExportValidation validation =
          (result as ExportPlanBuildBlocked).validation;
      expect(validation.isBlocking, isTrue);
      expect(validation.validatedAt, at());
      final ExportValidationWarning warning = validation.warnings.single;
      expect(warning.code, 'EXP-001');
      expect(warning.reason, 'too_wide');
      expect(warning.fieldId, field.id);
      expect(warning.fieldLabel, 'Name');
    });

    test('returns the validation instead of a plan for a missing glyph', () {
      final ConfirmedField field = confirmedField(
        id: uuid(60),
        type: FieldType.text,
        rect: Rect.fromLTWH(40, 40, 300, 20),
      );
      final Document document = buildDocument(
        fields: <ConfirmedField>[field],
        values: <String, FieldValue>{field.id: textValue('Prüfung \u{1F600}')},
      );
      final ExportPlanBuildResult result = _builder.build(
        document: document,
        pageGeometries: <PageGeometry>[a4()],
        values: document.values,
        signatures: document.signatures,
        evidenceClass: 'emulator',
        sourceSha256: sourceSha256,
        revisionId: uuid(61),
        validatedAt: at(),
      );
      final ExportValidation validation =
          (result as ExportPlanBuildBlocked).validation;
      expect(validation.warnings.single.code, 'EXP-004');
      expect(validation.warnings.single.reason, 'glyph_missing');
    });

    test('blocks geometry beyond the exported page', () {
      final ConfirmedField field = confirmedField(
        id: uuid(70),
        type: FieldType.text,
        rect: Rect.fromLTWH(600, 100, 80, 20),
      );
      final Document document = buildDocument(
        fields: <ConfirmedField>[field],
        pageGeometry: PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 700, 900)),
        values: <String, FieldValue>{field.id: textValue('Rand')},
      );
      final ExportPlanBuildResult result = _builder.build(
        document: document,
        pageGeometries: <PageGeometry>[a4()],
        values: document.values,
        signatures: document.signatures,
        evidenceClass: 'emulator',
        sourceSha256: sourceSha256,
        revisionId: uuid(71),
        validatedAt: at(),
      );
      final ExportValidation validation =
          (result as ExportPlanBuildBlocked).validation;
      expect(validation.warnings.single.code, 'EXP-003');
      expect(validation.warnings.single.reason, 'outside_page');
    });

    test('still returns a valid plan for an empty document snapshot', () {
      final ConfirmedField field = confirmedField(
        id: uuid(80),
        type: FieldType.text,
        rect: Rect.fromLTWH(40, 40, 200, 20),
      );
      final Document document = buildDocument(fields: <ConfirmedField>[field]);
      final ExportPlanBuildResult result = _builder.build(
        document: document,
        pageGeometries: <PageGeometry>[a4()],
        values: document.values,
        signatures: document.signatures,
        evidenceClass: 'emulator',
        sourceSha256: sourceSha256,
        revisionId: uuid(81),
        validatedAt: at(),
      );
      final ExportPlan plan = (result as ExportPlanBuildSuccess).plan;
      expect(plan.pages.single.ops, isEmpty);
      expect(plan.info.emptyFieldCount, 1);
    });
  });

  group('snapshot integrity', () {
    test('refuses a page-geometry list that does not cover the document', () {
      final Document document = buildDocument(
        fields: const <ConfirmedField>[],
        pageCount: 2,
      );
      expect(
        () => _builder.build(
          document: document,
          pageGeometries: <PageGeometry>[a4()],
          values: document.values,
          signatures: document.signatures,
          evidenceClass: 'emulator',
          sourceSha256: sourceSha256,
          revisionId: uuid(90),
          validatedAt: at(),
        ),
        throwsArgumentError,
      );
    });

    test('refuses an unsupported evidence-class token', () {
      final Document document = buildDocument(fields: const <ConfirmedField>[]);
      expect(
        () => _builder.build(
          document: document,
          pageGeometries: <PageGeometry>[a4()],
          values: document.values,
          signatures: document.signatures,
          evidenceClass: 'production',
          sourceSha256: sourceSha256,
          revisionId: uuid(91),
          validatedAt: at(),
        ),
        throwsArgumentError,
      );
    });

    test('refuses a source hash that is not a SHA-256', () {
      final Document document = buildDocument(fields: const <ConfirmedField>[]);
      expect(
        () => _builder.build(
          document: document,
          pageGeometries: <PageGeometry>[a4()],
          values: document.values,
          signatures: document.signatures,
          evidenceClass: 'emulator',
          sourceSha256: 'not-a-hash',
          revisionId: uuid(92),
          validatedAt: at(),
        ),
        throwsArgumentError,
      );
    });
  });
}
