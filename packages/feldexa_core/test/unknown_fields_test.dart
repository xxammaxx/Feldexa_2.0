// T017/T018 unknown-field preservation regressions.
//
// `data-model.md` §6 requires unknown JSON fields of the same schema version to
// survive a read/write round. These host-VM tests (evidence class NONE) inject
// extensions at the document root and at every nested persisted object —
// source, page, page geometry, rects, failure, suggestion, evidence, field,
// validation, values, signatures, verification, template origin, durable
// pointer, preferences, and metadata — and assert byte-identical canonical
// JSON after a round-trip.
//
// The tests also pin the deliberate exceptions: transient `status`, derived
// `renderCacheKey`, and the legacy `lowContrast` spelling are consumed and not
// re-emitted.

import 'dart:convert';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:flutter_test/flutter_test.dart';

const String _sha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

String _uuid(int value) {
  return '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
}

DateTime _at([int minute = 0]) => DateTime.utc(2026, 11, 14, 12, minute);

Rect _rect({
  double left = 50,
  double top = 60,
  double width = 140,
  double height = 20,
}) {
  return Rect.fromLTWH(left, top, width, height);
}

PageGeometry _geometry() {
  return PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842));
}

SourceFileRef _source() {
  return SourceFileRef(
    id: _uuid(1),
    sha256: _sha256,
    sizeBytes: 1234,
    pageCount: 1,
    originalName: 'form.pdf',
    importedAt: _at(),
  );
}

Page _page() {
  return Page(
    index: 0,
    geometry: _geometry(),
    analysis: AnalysisState.failed,
    failure: PageFailure(
      pageIndex: 0,
      category: PageFailureCategory.rasterization,
      messageKey: 'REC-002',
    ),
  );
}

DurablePointer _pointer() {
  return DurablePointer(
    revisionId: _uuid(90),
    kind: DurablePointer.autosaveKind,
    committedAt: _at(1),
    sha256: _sha256,
  );
}

FieldSuggestion _suggestion() {
  return FieldSuggestion(
    id: FieldSuggestion.idFor(pageIndex: 0, ordinal: 1),
    pageIndex: 0,
    rect: _rect(),
    proposedType: FieldType.text,
    confidence: 0.82,
    labelText: 'Name',
    evidence: SuggestionEvidence(
      cues: const <SuggestionCue>[SuggestionCue.line],
    ),
  );
}

ConfirmedField _field({
  required String id,
  required int order,
  FieldType type = FieldType.text,
  String label = 'Name',
}) {
  return ConfirmedField(
    id: id,
    pageIndex: 0,
    rect: _rect(),
    type: type,
    provenance: Provenance.user,
    label: label,
    order: order,
    createdAt: _at(),
    updatedAt: _at(),
  );
}

Document _richDocument() {
  final ConfirmedField textField = _field(id: _uuid(20), order: 0);
  final ConfirmedField signatureField = _field(
    id: _uuid(21),
    order: 1,
    type: FieldType.signature,
    label: 'Unterschrift',
  );
  final SignatureMark mark = SignatureMark(
    assetId: _uuid(30),
    fieldId: signatureField.id,
    pageIndex: 0,
    rect: _rect(width: 100, height: 40),
    widthPx: 100,
    heightPx: 40,
    capturedAt: _at(),
    sha256: _sha256,
  );
  return Document(
    id: _uuid(2),
    title: 'Antrag',
    createdAt: _at(),
    updatedAt: _at(1),
    source: _source(),
    pages: <Page>[_page()],
    suggestions: <FieldSuggestion>[_suggestion()],
    fields: <ConfirmedField>[textField, signatureField],
    fieldOrder: <String>[textField.id, signatureField.id],
    values: <String, FieldValue>{
      textField.id: TextValue(text: 'Erika', lastEditedAt: _at(2)),
      signatureField.id: SignatureValue(
        signatureAssetId: _uuid(30),
        lastEditedAt: _at(3),
      ),
    },
    signatures: <String, SignatureMark>{signatureField.id: mark},
    verification: <String, FieldVerification>{
      textField.id: FieldVerification(
        state: FieldVerificationState.confirmed,
        reviewedAt: _at(4),
      ),
    },
    templateOrigin: TemplateOrigin(
      templateId: _uuid(40),
      templateVersionId: _uuid(41),
      templateVersionNumber: 2,
    ),
    lastDurable: _pointer(),
    preferences: DocumentPreferences(
      zoom: 1.5,
      currentPage: 0,
      reviewOrderMode: ReviewOrderMode.pageOrder,
    ),
    status: DocumentStatus.saved,
  );
}

Map<String, Object?> _withExtra(
  Map<String, Object?> json,
  String key,
  Object? value,
) {
  return <String, Object?>{...json, key: value};
}

Map<String, Object?> _map(Object? value) {
  return Map<String, Object?>.from(value! as Map<String, Object?>);
}

List<Object?> _list(Object? value) {
  return List<Object?>.from(value! as List<Object?>);
}

Map<String, Object?> _extendedDocumentJson(Document document) {
  final Map<String, Object?> json = Map<String, Object?>.from(
    document.toJson(),
  );
  json['futureRoot'] = <String, Object?>{
    'nested': <Object?>[1, true, null],
  };

  final Map<String, Object?> source = _map(json['source']);
  source['futureSource'] = 'source';
  json['source'] = source;

  final List<Object?> pages = _list(json['pages']);
  final Map<String, Object?> page = _map(pages[0]);
  page['futurePage'] = 'page';
  final Map<String, Object?> geometry = _map(page['geometry']);
  geometry['futureGeometry'] = 'geometry';
  final Map<String, Object?> mediaBox = _map(geometry['mediaBox']);
  mediaBox['futureRect'] = 'mediaBox';
  geometry['mediaBox'] = mediaBox;
  final Map<String, Object?> cropBox = _map(geometry['cropBox']);
  cropBox['futureRect'] = 'cropBox';
  geometry['cropBox'] = cropBox;
  page['geometry'] = geometry;
  final Map<String, Object?> failure = _map(page['failure']);
  failure['futureFailure'] = 'failure';
  page['failure'] = failure;
  pages[0] = page;
  json['pages'] = pages;

  final List<Object?> suggestions = _list(json['suggestions']);
  final Map<String, Object?> suggestion = _map(suggestions[0]);
  suggestion['futureSuggestion'] = 'suggestion';
  final Map<String, Object?> suggestionRect = _map(suggestion['rect']);
  suggestionRect['futureRect'] = 'suggestionRect';
  suggestion['rect'] = suggestionRect;
  final Map<String, Object?> evidence = _map(suggestion['evidence']);
  evidence['futureEvidence'] = 'evidence';
  suggestion['evidence'] = evidence;
  suggestions[0] = suggestion;
  json['suggestions'] = suggestions;

  final List<Object?> fields = _list(json['fields']);
  final Map<String, Object?> field = _map(fields[0]);
  field['futureField'] = 'field';
  final Map<String, Object?> fieldRect = _map(field['rect']);
  fieldRect['futureRect'] = 'fieldRect';
  field['rect'] = fieldRect;
  final Map<String, Object?> validation = _map(field['validation']);
  validation['futureValidation'] = 'validation';
  field['validation'] = validation;
  fields[0] = field;
  final Map<String, Object?> signatureField = _map(fields[1]);
  signatureField['futureSignatureField'] = 'signatureField';
  fields[1] = signatureField;
  json['fields'] = fields;

  final ConfirmedField textField = document.fields[0];
  final ConfirmedField signatureFieldModel = document.fields[1];

  final Map<String, Object?> values = _map(json['values']);
  final Map<String, Object?> textValue = _map(values[textField.id]);
  textValue['futureValue'] = 'value';
  values[textField.id] = textValue;
  final Map<String, Object?> signatureValue = _map(
    values[signatureFieldModel.id],
  );
  signatureValue['futureSignatureValue'] = 'signatureValue';
  values[signatureFieldModel.id] = signatureValue;
  json['values'] = values;

  final Map<String, Object?> signatures = _map(json['signatures']);
  final Map<String, Object?> signature = _map(
    signatures[signatureFieldModel.id],
  );
  signature['futureSignature'] = 'signature';
  final Map<String, Object?> signatureRect = _map(signature['rect']);
  signatureRect['futureRect'] = 'signatureRect';
  signature['rect'] = signatureRect;
  signatures[signatureFieldModel.id] = signature;
  json['signatures'] = signatures;

  final Map<String, Object?> verification = _map(json['verification']);
  final Map<String, Object?> textVerification = _map(
    verification[textField.id],
  );
  textVerification['futureVerification'] = 'verification';
  verification[textField.id] = textVerification;
  json['verification'] = verification;

  final Map<String, Object?> origin = _map(json['templateOrigin']);
  origin['futureOrigin'] = 'origin';
  json['templateOrigin'] = origin;

  final Map<String, Object?> pointer = _map(json['lastDurable']);
  pointer['futurePointer'] = 'pointer';
  json['lastDurable'] = pointer;

  final Map<String, Object?> preferences = _map(json['preferences']);
  preferences['futurePreferences'] = 'preferences';
  json['preferences'] = preferences;

  return json;
}

void main() {
  group('Document root and nested round-trip', () {
    test('preserves extensions at every persisted object level', () {
      final Document document = _richDocument();
      final Map<String, Object?> extended = _extendedDocumentJson(document);
      final Document decoded = Document.fromJson(extended);
      final Map<String, Object?> output = decoded.toJson();

      expect(canonicalJsonEncode(output), canonicalJsonEncode(extended));

      final Map<String, Object?> tree =
          jsonDecode(canonicalJsonEncode(output)) as Map<String, Object?>;
      expect(tree['futureRoot'], <String, Object?>{
        'nested': <Object?>[1, true, null],
      });
      expect(_map(tree['source'])['futureSource'], 'source');
      final List<Object?> pages = _list(tree['pages']);
      final Map<String, Object?> page = _map(pages[0]);
      expect(page['futurePage'], 'page');
      final Map<String, Object?> geometry = _map(page['geometry']);
      expect(geometry['futureGeometry'], 'geometry');
      expect(_map(geometry['mediaBox'])['futureRect'], 'mediaBox');
      expect(_map(geometry['cropBox'])['futureRect'], 'cropBox');
      expect(_map(page['failure'])['futureFailure'], 'failure');
      final Map<String, Object?> suggestion = _map(
        _list(tree['suggestions'])[0],
      );
      expect(suggestion['futureSuggestion'], 'suggestion');
      expect(_map(suggestion['rect'])['futureRect'], 'suggestionRect');
      expect(_map(suggestion['evidence'])['futureEvidence'], 'evidence');
      final List<Object?> fields = _list(tree['fields']);
      final Map<String, Object?> field = _map(fields[0]);
      expect(field['futureField'], 'field');
      expect(_map(field['rect'])['futureRect'], 'fieldRect');
      expect(_map(field['validation'])['futureValidation'], 'validation');
      expect(_map(fields[1])['futureSignatureField'], 'signatureField');
      final ConfirmedField textField = document.fields[0];
      final ConfirmedField signatureField = document.fields[1];
      final Map<String, Object?> values = _map(tree['values']);
      expect(_map(values[textField.id])['futureValue'], 'value');
      expect(
        _map(values[signatureField.id])['futureSignatureValue'],
        'signatureValue',
      );
      final Map<String, Object?> signatures = _map(tree['signatures']);
      final Map<String, Object?> signature = _map(
        signatures[signatureField.id],
      );
      expect(signature['futureSignature'], 'signature');
      expect(_map(signature['rect'])['futureRect'], 'signatureRect');
      final Map<String, Object?> verification = _map(tree['verification']);
      expect(
        _map(verification[textField.id])['futureVerification'],
        'verification',
      );
      expect(_map(tree['templateOrigin'])['futureOrigin'], 'origin');
      expect(_map(tree['lastDurable'])['futurePointer'], 'pointer');
      expect(_map(tree['preferences'])['futurePreferences'], 'preferences');
    });

    test('copyWith retains root extensions', () {
      final Document document = Document.fromJson(
        _withExtra(_richDocument().toJson(), 'futureRoot', 'root'),
      );
      expect(document.copyWith(title: 'Neu').toJson()['futureRoot'], 'root');
    });

    test('modeled keys win over a colliding extension', () {
      final Document document = Document(
        id: _uuid(2),
        title: 'Antrag',
        createdAt: _at(),
        updatedAt: _at(1),
        source: _source(),
        pages: <Page>[_page()],
        fieldOrder: const <String>[],
        lastDurable: _pointer(),
        unknownFields: <String, Object?>{'title': 'evil', 'id': 'evil'},
      );
      expect(document.toJson()['title'], 'Antrag');
      expect(document.toJson()['id'], _uuid(2));
    });

    test('drops transient status and derived renderCacheKey', () {
      final Map<String, Object?> documentJson = _withExtra(
        _richDocument().toJson(),
        'status',
        'dirty',
      );
      expect(
        Document.fromJson(documentJson).toJson().containsKey('status'),
        isFalse,
      );

      final Map<String, Object?> pageJson = _withExtra(
        _page().toJson(),
        'renderCacheKey',
        'cache',
      );
      expect(
        Page.fromJson(pageJson).toJson().containsKey('renderCacheKey'),
        isFalse,
      );
    });
  });

  group('nested object round-trips', () {
    test('SourceFileRef', () {
      final Map<String, Object?> output = SourceFileRef.fromJson(
        _withExtra(_source().toJson(), 'futureSource', 'x'),
      ).toJson();
      expect(output['futureSource'], 'x');
    });

    test('Page retains its own extensions and its nested failure', () {
      final Map<String, Object?> pageJson = _withExtra(
        _page().toJson(),
        'futurePage',
        'page',
      );
      final Map<String, Object?> failure = _map(pageJson['failure']);
      failure['futureFailure'] = 'failure';
      pageJson['failure'] = failure;
      final Page page = Page.fromJson(pageJson);
      final Map<String, Object?> output = page.toJson();
      expect(output['futurePage'], 'page');
      expect(_map(output['failure'])['futureFailure'], 'failure');
      expect(page.copyWith(unreadable: true).toJson()['futurePage'], 'page');
    });

    test('PageGeometry and its Rect boxes', () {
      final Map<String, Object?> geometryJson = _withExtra(
        _geometry().toJson(),
        'futureGeometry',
        'geometry',
      );
      final Map<String, Object?> mediaBox = _map(geometryJson['mediaBox']);
      mediaBox['futureRect'] = 'mediaBox';
      geometryJson['mediaBox'] = mediaBox;
      final Map<String, Object?> output = PageGeometry.fromJson(geometryJson)
          .toJson();
      expect(output['futureGeometry'], 'geometry');
      expect(_map(output['mediaBox'])['futureRect'], 'mediaBox');
    });

    test('Rect', () {
      final Map<String, Object?> output = Rect.fromJson(
        _withExtra(_rect().toJson(), 'futureRect', 'rect'),
      ).toJson();
      expect(output['futureRect'], 'rect');
    });

    test('PageFailure', () {
      final PageFailure failure = PageFailure(
        pageIndex: 0,
        category: PageFailureCategory.rasterization,
        messageKey: 'REC-002',
      );
      final Map<String, Object?> output = PageFailure.fromJson(
        _withExtra(failure.toJson(), 'futureFailure', 'failure'),
      ).toJson();
      expect(output['futureFailure'], 'failure');
    });

    test('FieldSuggestion, evidence, and rect', () {
      final Map<String, Object?> suggestionJson = _withExtra(
        _suggestion().toJson(),
        'futureSuggestion',
        'suggestion',
      );
      final Map<String, Object?> rect = _map(suggestionJson['rect']);
      rect['futureRect'] = 'rect';
      suggestionJson['rect'] = rect;
      final Map<String, Object?> evidence = _map(suggestionJson['evidence']);
      evidence['futureEvidence'] = 'evidence';
      suggestionJson['evidence'] = evidence;
      final FieldSuggestion suggestion = FieldSuggestion.fromJson(
        suggestionJson,
      );
      final Map<String, Object?> output = suggestion.toJson();
      expect(output['futureSuggestion'], 'suggestion');
      expect(_map(output['rect'])['futureRect'], 'rect');
      expect(_map(output['evidence'])['futureEvidence'], 'evidence');
      expect(
        suggestion.copyWith(confidence: 0.81).toJson()['futureSuggestion'],
        'suggestion',
      );
    });

    test('ConfirmedField, validation, and rect', () {
      final ConfirmedField field = _field(id: _uuid(20), order: 0);
      final Map<String, Object?> fieldJson = _withExtra(
        field.toJson(),
        'futureField',
        'field',
      );
      final Map<String, Object?> validation = _map(fieldJson['validation']);
      validation['futureValidation'] = 'validation';
      fieldJson['validation'] = validation;
      final ConfirmedField decoded = ConfirmedField.fromJson(fieldJson);
      final Map<String, Object?> output = decoded.toJson();
      expect(output['futureField'], 'field');
      expect(_map(output['validation'])['futureValidation'], 'validation');
      expect(decoded.copyWith(label: 'Neu').toJson()['futureField'], 'field');
    });

    test('FieldValue variants retain extensions', () {
      final FieldValue text = TextValue(text: 'Erika', lastEditedAt: _at());
      final Map<String, Object?> output = FieldValue.fromJson(
        _withExtra(text.toJson(), 'futureValue', 'value'),
      ).toJson();
      expect(output['futureValue'], 'value');

      final FieldValue checkbox = CheckboxValue(
        checked: true,
        lastEditedAt: _at(),
      );
      expect(
        FieldValue.fromJson(
          _withExtra(checkbox.toJson(), 'futureValue', 'checkbox'),
        ).toJson()['futureValue'],
        'checkbox',
      );
    });

    test('FieldValidation ok, warning, and error', () {
      final FieldValidation ok = FieldValidation.fromJson(
        _withExtra(FieldValidation.ok.toJson(), 'futureValidation', 'ok'),
      );
      expect(ok.toJson()['futureValidation'], 'ok');
      expect(
        FieldValidation.ok.toJson().containsKey('futureValidation'),
        isFalse,
      );

      final FieldValidation warning = FieldValidation.fromJson(
        _withExtra(
          FieldValidation.warning(WarningCode.overflow, 'FLD-001').toJson(),
          'futureValidation',
          'warning',
        ),
      );
      expect(warning.toJson()['futureValidation'], 'warning');

      final FieldValidation error = FieldValidation.fromJson(
        _withExtra(
          FieldValidation.error('NUM-001').toJson(),
          'futureValidation',
          'error',
        ),
      );
      expect(error.toJson()['futureValidation'], 'error');
    });

    test('SignatureMark and FieldVerification', () {
      final SignatureMark mark = SignatureMark(
        assetId: _uuid(30),
        fieldId: _uuid(21),
        pageIndex: 0,
        rect: _rect(width: 100, height: 40),
        widthPx: 100,
        heightPx: 40,
        capturedAt: _at(),
        sha256: _sha256,
      );
      final Map<String, Object?> markJson = _withExtra(
        mark.toJson(),
        'futureSignature',
        'signature',
      );
      final Map<String, Object?> rect = _map(markJson['rect']);
      rect['futureRect'] = 'rect';
      markJson['rect'] = rect;
      final Map<String, Object?> markOutput = SignatureMark.fromJson(markJson)
          .toJson();
      expect(markOutput['futureSignature'], 'signature');
      expect(_map(markOutput['rect'])['futureRect'], 'rect');

      final FieldVerification verification = FieldVerification(
        state: FieldVerificationState.confirmed,
        reviewedAt: _at(),
      );
      final Map<String, Object?> verificationOutput =
          FieldVerification.fromJson(
            _withExtra(
              verification.toJson(),
              'futureVerification',
              'verification',
            ),
          ).toJson();
      expect(verificationOutput['futureVerification'], 'verification');
    });

    test('TemplateOrigin, DurablePointer, and DocumentPreferences', () {
      final TemplateOrigin origin = TemplateOrigin(
        templateId: _uuid(40),
        templateVersionId: _uuid(41),
        templateVersionNumber: 2,
      );
      expect(
        TemplateOrigin.fromJson(
          _withExtra(origin.toJson(), 'futureOrigin', 'origin'),
        ).toJson()['futureOrigin'],
        'origin',
      );

      final DurablePointer pointer = _pointer();
      expect(
        DurablePointer.fromJson(
          _withExtra(pointer.toJson(), 'futurePointer', 'pointer'),
        ).toJson()['futurePointer'],
        'pointer',
      );

      final DocumentPreferences preferences = DocumentPreferences(zoom: 1.5);
      expect(
        DocumentPreferences.fromJson(
          _withExtra(preferences.toJson(), 'futurePreferences', 'preferences'),
        ).toJson()['futurePreferences'],
        'preferences',
      );
    });

    test('DocumentMeta and its source', () {
      final DocumentMeta meta = DocumentMeta(
        id: _uuid(2),
        title: 'Antrag',
        createdAt: _at(),
        updatedAt: _at(1),
        source: _source(),
        latestRevisionId: _uuid(90),
        lastDurableAt: _at(1),
      );
      final Map<String, Object?> metaJson = _withExtra(
        meta.toJson(),
        'futureMeta',
        'meta',
      );
      final Map<String, Object?> source = _map(metaJson['source']);
      source['futureSource'] = 'source';
      metaJson['source'] = source;
      final Map<String, Object?> output = DocumentMeta.fromJson(metaJson)
          .toJson();
      expect(output['futureMeta'], 'meta');
      expect(_map(output['source'])['futureSource'], 'source');
    });

    test('legacy lowContrast is normalized away, not retained', () {
      final SuggestionEvidence evidence = SuggestionEvidence(
        cues: const <SuggestionCue>[SuggestionCue.line],
      );
      final Map<String, Object?> legacy = <String, Object?>{
        ...evidence.toJson(),
        'lowContrast': true,
      };
      final Map<String, Object?> output = SuggestionEvidence.fromJson(legacy)
          .toJson();
      expect(output.containsKey('lowContrast'), isFalse);
      expect(output['contrast'], 'normal');
    });
  });

  group('defensive deep immutability', () {
    test('unknownJsonFields deep-copies input maps and lists', () {
      final Map<String, Object?> input = <String, Object?>{
        'future': <String, Object?>{
          'nested': <Object?>[
            1,
            <String, Object?>{'deep': true},
          ],
        },
      };
      final Map<String, Object?> frozen = unknownJsonFields(
        input,
        const <String>{},
      );
      final String before = canonicalJsonEncode(frozen);

      final Map<String, Object?> inputFuture =
          input['future']! as Map<String, Object?>;
      final List<Object?> inputList = inputFuture['nested']! as List<Object?>;
      inputList.add(2);
      (inputList[1]! as Map<String, Object?>)['deep'] = false;
      inputFuture['added'] = 'x';

      expect(canonicalJsonEncode(frozen), before);
      final Map<String, Object?> frozenFuture =
          frozen['future']! as Map<String, Object?>;
      final List<Object?> frozenList = frozenFuture['nested']! as List<Object?>;
      expect(() => frozenFuture['added'] = 'x', throwsUnsupportedError);
      expect(() => frozenList.add(2), throwsUnsupportedError);
      expect(
        () => (frozenList[1]! as Map<String, Object?>)['deep'] = false,
        throwsUnsupportedError,
      );
    });

    test('Document.fromJson copies nested extensions away from the input', () {
      final Map<String, Object?> extension = <String, Object?>{
        'nested': <Object?>[1],
      };
      final Map<String, Object?> extended = _withExtra(
        _richDocument().toJson(),
        'futureRoot',
        extension,
      );
      final Document document = Document.fromJson(extended);
      final List<int> before = canonicalJsonBytes(document.toJson());

      (extension['nested']! as List<Object?>).add(2);
      extension['added'] = 'x';
      (extended['futureRoot']! as Map<String, Object?>)['other'] = 'y';

      expect(canonicalJsonBytes(document.toJson()), before);
      final Map<String, Object?> stored =
          document.unknownFields['futureRoot']! as Map<String, Object?>;
      expect(() => stored['other'] = 'y', throwsUnsupportedError);
    });

    test('public constructors copy nested extensions before storing', () {
      final Map<String, Object?> extension = <String, Object?>{
        'nested': <Object?>[1],
      };
      final Document document = _richDocument().copyWith(
        unknownFields: <String, Object?>{'futureRoot': extension},
      );
      final List<int> before = canonicalJsonBytes(document.toJson());

      (extension['nested']! as List<Object?>).add(2);
      extension['added'] = 'x';

      expect(canonicalJsonBytes(document.toJson()), before);
    });

    test('nested value objects copy extensions before storing', () {
      final Map<String, Object?> extension = <String, Object?>{
        'list': <Object?>[1],
      };
      final Rect rect = Rect.fromLTWH(
        1,
        2,
        3,
        4,
        unknownFields: <String, Object?>{'future': extension},
      );
      final String before = canonicalJsonEncode(rect.toJson());

      (extension['list']! as List<Object?>).add(2);

      expect(canonicalJsonEncode(rect.toJson()), before);
    });

    test('mergeUnknownJsonFields isolates mutable extension input', () {
      final Map<String, Object?> extension = <String, Object?>{
        'list': <Object?>[1],
      };
      final Map<String, Object?> merged = mergeUnknownJsonFields(
        <String, Object?>{'known': true},
        <String, Object?>{'future': extension},
      );
      final String before = canonicalJsonEncode(merged);

      (extension['list']! as List<Object?>).add(2);

      expect(canonicalJsonEncode(merged), before);
      expect(
        () => (merged['future']! as Map<String, Object?>)['added'] = 'x',
        throwsUnsupportedError,
      );
    });

    test('mutating returned JSON cannot change a later digest', () {
      final Map<String, Object?> extended = _withExtra(
        _richDocument().toJson(),
        'futureRoot',
        <String, Object?>{
          'nested': <Object?>[1],
        },
      );
      final Document document = Document.fromJson(extended);
      final List<int> before = canonicalJsonBytes(document.toJson());

      final Map<String, Object?> output = document.toJson();
      final Map<String, Object?> root =
          output['futureRoot']! as Map<String, Object?>;
      final List<Object?> list = root['nested']! as List<Object?>;
      expect(() => root['added'] = 'x', throwsUnsupportedError);
      expect(() => list.add(2), throwsUnsupportedError);

      // The returned top-level map is a fresh object; replacing an entry there
      // is allowed and cannot affect the model.
      output['futureRoot'] = 'replaced';
      expect(canonicalJsonBytes(document.toJson()), before);
    });

    test('rejects non-JSON and cyclic extension values', () {
      expect(
        () => freezeUnknownJsonFields(<String, Object?>{
          'when': DateTime.utc(2026, 11, 14),
        }),
        throwsArgumentError,
      );
      expect(
        () => freezeUnknownJsonFields(<String, Object?>{'number': double.nan}),
        throwsArgumentError,
      );

      final Map<String, Object?> cycle = <String, Object?>{};
      cycle['self'] = cycle;
      expect(() => freezeUnknownJsonFields(cycle), throwsArgumentError);

      final Map<String, Object?> nestedCycle = <String, Object?>{
        'list': <Object?>[],
      };
      (nestedCycle['list']! as List<Object?>).add(nestedCycle);
      expect(() => freezeUnknownJsonFields(nestedCycle), throwsArgumentError);
    });
  });
}
