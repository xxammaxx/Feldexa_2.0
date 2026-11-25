// T113 export preflight tests.
//
// These are host-VM tests (`NONE` evidence). They pin `contracts/export-plan.md`
// §1 step [1], §3.4, and §4: empty fields never block, unresolved suggestions
// are excluded and counted only under the provisional OD-1 behavior, geometry
// beyond 0.5 pt blocks with EXP-003, incompatible content blocks, and every
// warning names the field, page, label, and machine reason. They cannot prove
// the German dialog text (T029/T117).
@TestOn('vm')
library;

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_export/feldexa_export.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/export_fixtures.dart';

void main() {
  group('empty fields', () {
    test('are allowed, counted, and never block the export', () {
      final ConfirmedField filled = confirmedField(
        id: uuid(10),
        type: FieldType.text,
        rect: Rect.fromLTWH(40, 40, 200, 20),
        label: 'Name',
        order: 0,
      );
      final ConfirmedField unset = confirmedField(
        id: uuid(11),
        type: FieldType.number,
        rect: Rect.fromLTWH(40, 80, 200, 20),
        label: 'Betrag',
        order: 1,
      );
      final ConfirmedField blank = confirmedField(
        id: uuid(12),
        type: FieldType.multiline,
        rect: Rect.fromLTWH(40, 120, 200, 40),
        label: 'Bemerkung',
        order: 2,
      );
      final ConfirmedField unchecked = confirmedField(
        id: uuid(13),
        type: FieldType.checkbox,
        rect: Rect.fromLTWH(40, 180, 10, 10),
        label: 'Zustimmung',
        order: 3,
      );
      final Document document = buildDocument(
        fields: <ConfirmedField>[filled, unset, blank, unchecked],
        values: <String, FieldValue>{
          filled.id: textValue('Müller'),
          blank.id: multilineValue('  '),
          unchecked.id: checkboxValue(checked: false),
        },
      );

      final ExportPreflightResult result = const ExportPreflight().run(
        document: document,
        pageGeometries: <PageGeometry>[a4()],
        values: document.values,
        signatures: document.signatures,
        validatedAt: at(),
      );
      expect(result.validation.isValid, isTrue);
      expect(result.validation.warnings, isEmpty);
      // An undecided checkbox is a state, not missing content.
      expect(result.emptyFieldCount, 2);
      expect(
        result.fields.map((ExportPreflightField field) => field.field.id),
        <String>[filled.id, unset.id, blank.id, unchecked.id],
      );
      expect(result.fields.first.value, isA<TextValue>());
    });
  });

  group('empty-field counting (§3.4)', () {
    test('an unset checkbox is a decided state, not an empty field', () {
      // §3.4 counts empty confirmed fields and says nothing about checkboxes.
      // By the layout rule (§3.2) an unchecked box draws no mark, so an unset
      // checkbox is a decided state, not missing content: it must not inflate
      // the "N Felder sind noch leer" hint.
      final ConfirmedField withoutValue = confirmedField(
        id: uuid(14),
        type: FieldType.checkbox,
        rect: Rect.fromLTWH(40, 40, 10, 10),
      );
      final Document document = buildDocument(
        fields: <ConfirmedField>[withoutValue],
      );
      final ExportPreflightResult result = const ExportPreflight().run(
        document: document,
        pageGeometries: <PageGeometry>[a4()],
        values: document.values,
        signatures: document.signatures,
        validatedAt: at(),
      );
      expect(result.validation.isValid, isTrue);
      expect(result.emptyFieldCount, 0);
    });
  });

  group('unresolved suggestions (provisional, OD-1)', () {
    test('are excluded and counted without blocking', () {
      final ConfirmedField field = confirmedField(
        id: uuid(20),
        type: FieldType.text,
        rect: Rect.fromLTWH(40, 40, 200, 20),
      );
      final Document document = buildDocument(
        fields: <ConfirmedField>[field],
        values: <String, FieldValue>{field.id: textValue('Wert')},
        suggestions: <FieldSuggestion>[
          suggestion(ordinal: 1),
          suggestion(ordinal: 2),
          suggestion(ordinal: 3, resolution: SuggestionResolution.rejected),
        ],
      );

      final ExportPreflightResult result = const ExportPreflight().run(
        document: document,
        pageGeometries: <PageGeometry>[a4()],
        values: document.values,
        signatures: document.signatures,
        validatedAt: at(),
      );
      expect(result.validation.isValid, isTrue);
      expect(result.unresolvedSuggestionCount, 2);
      // Only confirmed fields enter the plan; no suggestion content does.
      expect(result.fields.length, 1);
    });
  });

  group('geometry inside the page bounds', () {
    test('blocks a rect beyond the display box with EXP-003', () {
      // The stored document page is larger than the exported page: the field
      // is valid in the document but outside the page being exported.
      final ConfirmedField field = confirmedField(
        id: uuid(30),
        type: FieldType.text,
        rect: Rect.fromLTWH(600, 100, 80, 20),
        label: 'Randfeld',
      );
      final Document document = buildDocument(
        fields: <ConfirmedField>[field],
        pageGeometry: PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 700, 900)),
      );

      final ExportPreflightResult result = const ExportPreflight().run(
        document: document,
        pageGeometries: <PageGeometry>[a4()],
        values: document.values,
        signatures: document.signatures,
        validatedAt: at(),
      );
      expect(result.isBlocking, isTrue);
      final ExportValidationWarning warning = result.validation.warnings.single;
      expect(warning.code, 'EXP-003');
      expect(warning.reason, 'outside_page');
      expect(warning.fieldId, field.id);
      expect(warning.pageIndex, 0);
      expect(warning.fieldLabel, 'Randfeld');
    });

    test('tolerates at most 0.5 pt of overshoot', () {
      final ConfirmedField field = confirmedField(
        id: uuid(31),
        type: FieldType.text,
        rect: Rect.fromLTWH(400, 100, 195.5, 20),
      );
      final Document document = buildDocument(fields: <ConfirmedField>[field]);
      final ExportPreflightResult result = const ExportPreflight().run(
        document: document,
        pageGeometries: <PageGeometry>[a4()],
        values: document.values,
        signatures: document.signatures,
        validatedAt: at(),
      );
      // a4 is 595.28 pt wide, so 595.5 is an overshoot of 0.22 pt: this case
      // does not pin the boundary itself.
      expect(result.validation.isValid, isTrue);
    });

    test('pins the 0.5 pt boundary (0.49 passes, 0.51 blocks)', () {
      // The document page is larger than the exported page, so the field is
      // valid in the document and only the export-time overshoot is measured.
      final PageGeometry documentPage = PageGeometry(
        mediaBox: Rect.fromLTWH(0, 0, 700, 900),
      );
      final ConfirmedField insideLimit = confirmedField(
        id: uuid(32),
        type: FieldType.text,
        rect: Rect.fromLTWH(400, 100, 195.77, 20),
      );
      final Document passingDocument = buildDocument(
        fields: <ConfirmedField>[insideLimit],
        pageGeometry: documentPage,
      );
      final ExportPreflightResult passing = const ExportPreflight().run(
        document: passingDocument,
        pageGeometries: <PageGeometry>[a4()],
        values: passingDocument.values,
        signatures: passingDocument.signatures,
        validatedAt: at(),
      );
      // 595.77 - 595.28 = 0.49 pt overshoot: inside the 0.5 pt tolerance.
      expect(passing.validation.isValid, isTrue);

      final ConfirmedField outsideLimit = confirmedField(
        id: uuid(33),
        type: FieldType.text,
        rect: Rect.fromLTWH(400, 100, 195.79, 20),
      );
      final Document blockedDocument = buildDocument(
        fields: <ConfirmedField>[outsideLimit],
        pageGeometry: documentPage,
      );
      final ExportPreflightResult blocked = const ExportPreflight().run(
        document: blockedDocument,
        pageGeometries: <PageGeometry>[a4()],
        values: blockedDocument.values,
        signatures: blockedDocument.signatures,
        validatedAt: at(),
      );
      // 595.79 - 595.28 = 0.51 pt overshoot: beyond the tolerance.
      expect(blocked.isBlocking, isTrue);
      expect(blocked.validation.warnings.single.code, 'EXP-003');
    });
  });

  group('type and value compatibility', () {
    test('blocks preserved incompatible content', () {
      final ConfirmedField field = confirmedField(
        id: uuid(40),
        type: FieldType.checkbox,
        rect: Rect.fromLTWH(40, 40, 10, 10),
        validation: FieldValidation.warning(
          WarningCode.incompatibleContent,
          'fld002',
        ),
      );
      final Document document = buildDocument(fields: <ConfirmedField>[field]);
      final ExportPreflightResult result = const ExportPreflight().run(
        document: document,
        pageGeometries: <PageGeometry>[a4()],
        values: <String, FieldValue>{
          field.id: IncompatibleValue(
            preservedText: 'Alttext',
            reasonCode: 'type_change',
            lastEditedAt: at(),
          ),
        },
        signatures: document.signatures,
        validatedAt: at(),
      );
      expect(result.validation.warnings.single.code, 'EXP-001');
      expect(result.validation.warnings.single.reason, 'incompatible_value');
      // Preserved content is not renderable content, so it is not "empty".
      expect(result.emptyFieldCount, 0);
    });

    test('blocks a field whose validation state is a blocking error', () {
      final ConfirmedField field = confirmedField(
        id: uuid(41),
        type: FieldType.number,
        rect: Rect.fromLTWH(40, 40, 200, 20),
        validation: FieldValidation.error('NUM-001'),
      );
      final Document document = buildDocument(fields: <ConfirmedField>[field]);
      final ExportPreflightResult result = const ExportPreflight().run(
        document: document,
        pageGeometries: <PageGeometry>[a4()],
        values: <String, FieldValue>{
          field.id: IncompatibleValue(
            preservedText: 'zwölf',
            reasonCode: 'parse_failed',
            lastEditedAt: at(),
          ),
        },
        signatures: document.signatures,
        validatedAt: at(),
      );
      expect(
        result.validation.warnings.map(
          (ExportValidationWarning warning) => warning.reason,
        ),
        containsAll(<String>['field_validation_error', 'incompatible_value']),
      );
      expect(result.validation.isBlocking, isTrue);
    });

    test('blocks a value that does not match its field type', () {
      final ConfirmedField field = confirmedField(
        id: uuid(42),
        type: FieldType.text,
        rect: Rect.fromLTWH(40, 40, 200, 20),
      );
      final Document document = buildDocument(fields: <ConfirmedField>[field]);
      final ExportPreflightResult result = const ExportPreflight().run(
        document: document,
        pageGeometries: <PageGeometry>[a4()],
        values: <String, FieldValue>{field.id: checkboxValue()},
        signatures: document.signatures,
        validatedAt: at(),
      );
      expect(result.validation.warnings.single.reason, 'value_type_mismatch');
    });

    test('blocks a signature value without its capture', () {
      final ConfirmedField field = confirmedField(
        id: uuid(43),
        type: FieldType.signature,
        rect: Rect.fromLTWH(40, 40, 200, 60),
      );
      final Document document = buildDocument(fields: <ConfirmedField>[field]);
      final ExportPreflightResult result = const ExportPreflight().run(
        document: document,
        pageGeometries: <PageGeometry>[a4()],
        values: <String, FieldValue>{field.id: signatureValue(uuid(44))},
        signatures: document.signatures,
        validatedAt: at(),
      );
      expect(
        result.validation.warnings.single.reason,
        'signature_asset_missing',
      );
    });
  });

  group('snapshot integrity', () {
    test('refuses a page-geometry list that does not cover the document', () {
      final ConfirmedField field = confirmedField(
        id: uuid(50),
        type: FieldType.text,
        rect: Rect.fromLTWH(40, 40, 200, 20),
      );
      final Document document = buildDocument(
        fields: <ConfirmedField>[field],
        pageCount: 2,
      );
      expect(
        () => const ExportPreflight().run(
          document: document,
          pageGeometries: <PageGeometry>[a4()],
          values: document.values,
          signatures: document.signatures,
          validatedAt: at(),
        ),
        throwsArgumentError,
      );
    });

    test('refuses content that references an unknown field', () {
      final Document document = buildDocument(fields: const <ConfirmedField>[]);
      expect(
        () => const ExportPreflight().run(
          document: document,
          pageGeometries: <PageGeometry>[a4()],
          values: <String, FieldValue>{uuid(51): textValue('Wert')},
          signatures: const <String, SignatureMark>{},
          validatedAt: at(),
        ),
        throwsArgumentError,
      );
    });

    test('refuses a local validation timestamp', () {
      final Document document = buildDocument(fields: const <ConfirmedField>[]);
      expect(
        () => const ExportPreflight().run(
          document: document,
          pageGeometries: <PageGeometry>[a4()],
          values: const <String, FieldValue>{},
          signatures: const <String, SignatureMark>{},
          validatedAt: DateTime(2026, 11, 20, 9),
        ),
        throwsArgumentError,
      );
    });
  });
}
