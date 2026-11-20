// T064 suggestion-lifecycle contract tests.
//
// These are host-VM tests (evidence class NONE). They pin the lifecycle in
// `data-model.md` §3.4–§3.5 and `contracts/recognition-output.md` §7:
//   * confirm: `unresolved -> confirmed` creates one `Provenance.machine` field
//     and copies geometry, type, and confidence without mutating the suggestion;
//   * reject and undo: `unresolved -> rejected -> unresolved` never creates or
//     removes a confirmed field;
//   * confirm undo: `confirmed -> unresolved` is valid once the generated
//     untouched machine field is removed;
//   * aggregate invariants for duplicate flags, orphaned machine fields,
//     confidence/page mismatches, and machine-only provenance fields;
//   * provenance preservation when a confirmed field is edited later;
//   * canonical JSON determinism, unknown-field retention, content-free errors;
//   * exactly three resolution states; `duplicateOfConfirmed` is an audit flag.

import 'dart:convert';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:flutter_test/flutter_test.dart';

const String _sha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

String _uuid(int value) {
  return '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
}

DateTime _at([int minute = 0]) => DateTime.utc(2026, 11, 20, 12, minute);

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

Page _page([int index = 0]) {
  return Page(index: index, geometry: _geometry());
}

Map<String, Object?> _jsonRoundTrip(Map<String, Object?> json) {
  return jsonDecode(jsonEncode(json)) as Map<String, Object?>;
}

Map<String, Object?> _canonicalRoundTrip(Map<String, Object?> json) {
  return jsonDecode(canonicalJsonEncode(json)) as Map<String, Object?>;
}

String _messageOf(void Function() action) {
  try {
    action();
  } on ArgumentError catch (error) {
    return error.message.toString();
  }
  fail('expected an ArgumentError');
}

SuggestionEvidence _evidence({
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return SuggestionEvidence(
    cues: const <SuggestionCue>[SuggestionCue.line],
    unknownFields: unknownFields,
  );
}

FieldSuggestion _suggestion({
  int pageIndex = 0,
  int ordinal = 1,
  Rect? rect,
  FieldType proposedType = FieldType.text,
  double confidence = 0.82,
  String? labelText = 'Name',
  SuggestionEvidence? evidence,
  SuggestionResolution resolution = SuggestionResolution.unresolved,
  bool duplicateOfConfirmed = false,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return FieldSuggestion(
    id: FieldSuggestion.idFor(pageIndex: pageIndex, ordinal: ordinal),
    pageIndex: pageIndex,
    rect: rect ?? _rect(),
    proposedType: proposedType,
    confidence: confidence,
    labelText: labelText,
    evidence: evidence ?? _evidence(),
    resolution: resolution,
    duplicateOfConfirmed: duplicateOfConfirmed,
    unknownFields: unknownFields,
  );
}

ConfirmedField _machineField({
  int pageIndex = 0,
  required String sourceSuggestionId,
  double suggestionConfidence = 0.82,
  Rect? rect,
  FieldType type = FieldType.text,
  String label = 'Feld',
  int order = 0,
  DateTime? updatedAt,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return ConfirmedField(
    id: _uuid(20 + order),
    pageIndex: pageIndex,
    rect: rect ?? _rect(),
    type: type,
    provenance: Provenance.machine,
    sourceSuggestionId: sourceSuggestionId,
    suggestionConfidence: suggestionConfidence,
    label: label,
    order: order,
    createdAt: _at(),
    updatedAt: updatedAt ?? _at(1),
    unknownFields: unknownFields,
  );
}

ConfirmedField _userField({
  String label = 'Feld',
  int order = 0,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return ConfirmedField(
    id: _uuid(30 + order),
    pageIndex: 0,
    rect: _rect(),
    type: FieldType.text,
    provenance: Provenance.user,
    label: label,
    order: order,
    createdAt: _at(),
    updatedAt: _at(1),
    unknownFields: unknownFields,
  );
}

SourceFileRef _source({int pageCount = 1}) {
  return SourceFileRef(
    id: _uuid(1),
    sha256: _sha256,
    sizeBytes: 1234,
    pageCount: pageCount,
    originalName: 'form.pdf',
    importedAt: _at(),
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

Document _document({
  List<Page>? pages,
  List<FieldSuggestion> suggestions = const <FieldSuggestion>[],
  List<ConfirmedField> fields = const <ConfirmedField>[],
  List<String>? fieldOrder,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  final List<Page> pageList = pages ?? <Page>[_page()];
  return Document(
    schemaVersion: documentSchemaVersion,
    id: _uuid(2),
    title: 'Antrag',
    createdAt: _at(),
    updatedAt: _at(1),
    source: _source(pageCount: pageList.length),
    pages: pageList,
    suggestions: suggestions,
    fields: fields,
    fieldOrder:
        fieldOrder ??
        <String>[for (final ConfirmedField field in fields) field.id],
    lastDurable: _pointer(),
    status: DocumentStatus.saved,
    unknownFields: unknownFields,
  );
}

RevisionContent _content({
  List<Page>? pages,
  List<FieldSuggestion> suggestions = const <FieldSuggestion>[],
  List<ConfirmedField> fields = const <ConfirmedField>[],
  List<String>? fieldOrder,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return RevisionContent(
    pages: pages ?? <Page>[_page()],
    suggestions: suggestions,
    fields: fields,
    fieldOrder:
        fieldOrder ??
        <String>[for (final ConfirmedField field in fields) field.id],
    unknownFields: unknownFields,
  );
}

({FieldSuggestion suggestion, ConfirmedField field}) _confirmedPair({
  double suggestionConfidence = 0.82,
  double? fieldConfidence,
  Rect? rect,
  String? labelText = 'Name',
}) {
  final Rect targetRect = rect ?? _rect();
  final FieldSuggestion unresolved = _suggestion(
    rect: targetRect,
    confidence: suggestionConfidence,
    labelText: labelText,
  );
  final FieldSuggestion confirmed = unresolved.copyWith(
    resolution: SuggestionResolution.confirmed,
  );
  return (
    suggestion: confirmed,
    field: _machineField(
      sourceSuggestionId: confirmed.id,
      suggestionConfidence: fieldConfidence ?? confirmed.confidence,
      rect: confirmed.rect,
      type: confirmed.proposedType,
      label: confirmed.labelText ?? 'Feld',
    ),
  );
}

void main() {
  group('confirm: unresolved -> confirmed', () {
    test('creates one machine field and copies provenance, geometry, type, '
        'and confidence', () {
      final ({FieldSuggestion suggestion, ConfirmedField field}) pair =
          _confirmedPair();

      expect(pair.suggestion.resolution, SuggestionResolution.confirmed);
      expect(pair.field.provenance, Provenance.machine);
      expect(pair.field.sourceSuggestionId, pair.suggestion.id);
      expect(pair.field.suggestionConfidence, pair.suggestion.confidence);
      expect(pair.field.pageIndex, pair.suggestion.pageIndex);
      expect(pair.field.type, pair.suggestion.proposedType);
      expect(pair.field.rect, pair.suggestion.rect);
      expect(pair.field.label, pair.suggestion.labelText);
      expect(pair.field.order, 0);

      final Document document = _document(
        suggestions: <FieldSuggestion>[pair.suggestion],
        fields: <ConfirmedField>[pair.field],
      );
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[pair.suggestion],
        fields: <ConfirmedField>[pair.field],
      );

      expect(
        document.suggestions.single.resolution,
        SuggestionResolution.confirmed,
      );
      expect(document.fields.single, pair.field);
      expect(
        content.suggestions.single.resolution,
        SuggestionResolution.confirmed,
      );
      expect(content.fields.single, pair.field);

      // Confirmation never rewrites the audit record.
      expect(document.suggestions.single.proposedType, FieldType.text);
      expect(document.suggestions.single.rect, _rect());
      expect(document.suggestions.single.confidence, 0.82);
      expect(document.suggestions.single.labelText, 'Name');
      expect(content.suggestions.single.proposedType, FieldType.text);
      expect(content.suggestions.single.rect, _rect());
      expect(content.suggestions.single.confidence, 0.82);
      expect(content.suggestions.single.labelText, 'Name');
    });

    test('the confirmed document and revision content round-trip through '
        'canonical JSON unchanged', () {
      final ({FieldSuggestion suggestion, ConfirmedField field}) pair =
          _confirmedPair();
      final Document document = _document(
        suggestions: <FieldSuggestion>[pair.suggestion],
        fields: <ConfirmedField>[pair.field],
      );
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[pair.suggestion],
        fields: <ConfirmedField>[pair.field],
      );

      final String documentBytes = canonicalJsonEncode(document.toJson());
      final String contentBytes = canonicalJsonEncode(content.toJson());

      final Document reloadedDocument = Document.fromJson(
        _canonicalRoundTrip(document.toJson()),
      );
      final RevisionContent reloadedContent = RevisionContent.fromJson(
        _canonicalRoundTrip(content.toJson()),
      );

      expect(reloadedDocument, document);
      expect(reloadedContent, content);
      expect(canonicalJsonEncode(reloadedDocument.toJson()), documentBytes);
      expect(canonicalJsonEncode(reloadedContent.toJson()), contentBytes);
      expect(
        reloadedDocument.suggestions.single.resolution,
        SuggestionResolution.confirmed,
      );
      expect(reloadedDocument.fields.single.provenance, Provenance.machine);
      expect(
        reloadedDocument.fields.single.sourceSuggestionId,
        pair.field.sourceSuggestionId,
      );
      expect(
        reloadedContent.suggestions.single.resolution,
        SuggestionResolution.confirmed,
      );
      expect(reloadedContent.fields.single.suggestionConfidence, 0.82);
    });
  });

  group('reject and undo: unresolved -> rejected -> unresolved', () {
    test('rejecting creates no machine field and reloads with other fields '
        'intact', () {
      final ({FieldSuggestion suggestion, ConfirmedField field}) pair =
          _confirmedPair();
      final FieldSuggestion candidate = _suggestion(
        ordinal: 2,
        labelText: 'Ort',
      );
      final FieldSuggestion rejected = candidate.copyWith(
        resolution: SuggestionResolution.rejected,
      );

      expect(rejected.resolution, SuggestionResolution.rejected);
      expect(rejected.proposedType, candidate.proposedType);
      expect(rejected.rect, candidate.rect);
      expect(rejected.confidence, candidate.confidence);

      final Document before = _document(
        suggestions: <FieldSuggestion>[pair.suggestion, candidate],
        fields: <ConfirmedField>[pair.field],
      );
      final Document rejectedDocument = _document(
        suggestions: <FieldSuggestion>[pair.suggestion, rejected],
        fields: <ConfirmedField>[pair.field],
      );
      final RevisionContent rejectedContent = _content(
        suggestions: <FieldSuggestion>[pair.suggestion, rejected],
        fields: <ConfirmedField>[pair.field],
      );

      expect(rejectedDocument.fields, before.fields);
      expect(rejectedContent.fields.single, pair.field);
      expect(
        rejectedDocument.fields.any(
          (ConfirmedField field) => field.sourceSuggestionId == candidate.id,
        ),
        isFalse,
      );
      expect(
        rejectedDocument.suggestions.last.resolution,
        SuggestionResolution.rejected,
      );

      final Document reloadedDocument = Document.fromJson(
        _canonicalRoundTrip(rejectedDocument.toJson()),
      );
      final RevisionContent reloadedContent = RevisionContent.fromJson(
        _canonicalRoundTrip(rejectedContent.toJson()),
      );

      expect(reloadedDocument, rejectedDocument);
      expect(reloadedContent, rejectedContent);
      expect(
        reloadedDocument.suggestions.last.resolution,
        SuggestionResolution.rejected,
      );
      expect(
        reloadedContent.suggestions.last.resolution,
        SuggestionResolution.rejected,
      );
      expect(reloadedDocument.fields.single, pair.field);
      expect(reloadedContent.fields.single, pair.field);
    });

    test('undoing a rejection restores unresolved without touching fields', () {
      final ({FieldSuggestion suggestion, ConfirmedField field}) pair =
          _confirmedPair();
      final FieldSuggestion candidate = _suggestion(
        ordinal: 2,
        labelText: 'Ort',
      );
      final FieldSuggestion rejected = candidate.copyWith(
        resolution: SuggestionResolution.rejected,
      );
      final FieldSuggestion undone = rejected.copyWith(
        resolution: SuggestionResolution.unresolved,
      );

      expect(undone, candidate);
      expect(undone.resolution, SuggestionResolution.unresolved);

      final Document undoneDocument = _document(
        suggestions: <FieldSuggestion>[pair.suggestion, undone],
        fields: <ConfirmedField>[pair.field],
      );
      final RevisionContent undoneContent = _content(
        suggestions: <FieldSuggestion>[pair.suggestion, undone],
        fields: <ConfirmedField>[pair.field],
      );

      expect(
        undoneDocument.suggestions.last.resolution,
        SuggestionResolution.unresolved,
      );
      expect(undoneDocument.fields.single, pair.field);
      expect(
        undoneContent.suggestions.last.resolution,
        SuggestionResolution.unresolved,
      );
      expect(undoneContent.fields.single, pair.field);

      final Document reloadedDocument = Document.fromJson(
        _canonicalRoundTrip(undoneDocument.toJson()),
      );
      final RevisionContent reloadedContent = RevisionContent.fromJson(
        _canonicalRoundTrip(undoneContent.toJson()),
      );

      expect(reloadedDocument, undoneDocument);
      expect(reloadedContent, undoneContent);
      expect(
        reloadedDocument.suggestions.last.resolution,
        SuggestionResolution.unresolved,
      );
      expect(
        reloadedContent.suggestions.last.resolution,
        SuggestionResolution.unresolved,
      );
      expect(reloadedDocument.fields.single, pair.field);
      expect(reloadedContent.fields.single, pair.field);
    });
  });

  group('confirm undo: confirmed -> unresolved', () {
    test('removing an untouched generated field and restoring unresolved is '
        'valid and round-trips', () {
      final ({FieldSuggestion suggestion, ConfirmedField field}) pair =
          _confirmedPair();
      final ConfirmedField generated = pair.field;

      // The model has no "touched" marker: "untouched" is a caller
      // precondition owned by the confirm/undo command. This test uses the
      // field exactly as confirmation produced it, so it exercises the lawful
      // transition without inventing a model-level enforcement.
      final FieldSuggestion undone = pair.suggestion.copyWith(
        resolution: SuggestionResolution.unresolved,
      );
      expect(undone.resolution, SuggestionResolution.unresolved);
      expect(undone.proposedType, generated.type);
      expect(undone.rect, generated.rect);
      expect(undone.confidence, generated.suggestionConfidence);

      final Document document = _document(
        suggestions: <FieldSuggestion>[undone],
      );
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[undone],
      );

      expect(document.fields, isEmpty);
      expect(content.fields, isEmpty);
      expect(document.suggestions.single, undone);
      expect(content.suggestions.single, undone);

      final Document reloadedDocument = Document.fromJson(
        _canonicalRoundTrip(document.toJson()),
      );
      final RevisionContent reloadedContent = RevisionContent.fromJson(
        _canonicalRoundTrip(content.toJson()),
      );

      expect(reloadedDocument, document);
      expect(reloadedContent, content);
      expect(
        reloadedDocument.suggestions.single.resolution,
        SuggestionResolution.unresolved,
      );
      expect(
        reloadedContent.suggestions.single.resolution,
        SuggestionResolution.unresolved,
      );
      expect(reloadedDocument.fields, isEmpty);
      expect(reloadedContent.fields, isEmpty);
    });
  });

  group('invariants', () {
    test('a duplicateOfConfirmed suggestion can never be confirmed', () {
      expect(
        () => _suggestion(
          resolution: SuggestionResolution.confirmed,
          duplicateOfConfirmed: true,
          labelText: 'T064-DUPLICATE-LABEL',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.toString(),
            'toString',
            isNot(contains('T064-DUPLICATE-LABEL')),
          ),
        ),
      );

      final FieldSuggestion confirmed = _suggestion(
        resolution: SuggestionResolution.confirmed,
      );
      expect(
        () => confirmed.copyWith(duplicateOfConfirmed: true),
        throwsArgumentError,
      );
    });

    test('a confirmed suggestion without exactly one machine field is '
        'rejected by both aggregates', () {
      final FieldSuggestion confirmed = _suggestion(
        resolution: SuggestionResolution.confirmed,
      );

      expect(
        () => _document(suggestions: <FieldSuggestion>[confirmed]),
        throwsArgumentError,
      );
      expect(
        () => _content(suggestions: <FieldSuggestion>[confirmed]),
        throwsArgumentError,
      );

      final ({FieldSuggestion suggestion, ConfirmedField field}) pair =
          _confirmedPair();
      final ConfirmedField second = _machineField(
        sourceSuggestionId: pair.suggestion.id,
        order: 1,
      );
      expect(
        () => _document(
          suggestions: <FieldSuggestion>[pair.suggestion],
          fields: <ConfirmedField>[pair.field, second],
        ),
        throwsArgumentError,
      );
      expect(
        () => _content(
          suggestions: <FieldSuggestion>[pair.suggestion],
          fields: <ConfirmedField>[pair.field, second],
        ),
        throwsArgumentError,
      );
    });

    test('a machine field without a confirmed suggestion is rejected by both '
        'aggregates', () {
      for (final SuggestionResolution resolution in <SuggestionResolution>[
        SuggestionResolution.unresolved,
        SuggestionResolution.rejected,
      ]) {
        final FieldSuggestion suggestion = _suggestion(resolution: resolution);
        final ConfirmedField field = _machineField(
          sourceSuggestionId: suggestion.id,
        );
        expect(
          () => _document(
            suggestions: <FieldSuggestion>[suggestion],
            fields: <ConfirmedField>[field],
          ),
          throwsArgumentError,
        );
        expect(
          () => _content(
            suggestions: <FieldSuggestion>[suggestion],
            fields: <ConfirmedField>[field],
          ),
          throwsArgumentError,
        );
      }

      final ConfirmedField orphan = _machineField(
        sourceSuggestionId: 's_p0_0009',
      );
      expect(
        () => _document(fields: <ConfirmedField>[orphan]),
        throwsArgumentError,
      );
      expect(
        () => _content(fields: <ConfirmedField>[orphan]),
        throwsArgumentError,
      );
    });

    test('confidence and page mismatches are rejected', () {
      final ({FieldSuggestion suggestion, ConfirmedField field}) pair =
          _confirmedPair(fieldConfidence: 0.81);
      expect(pair.field.suggestionConfidence, 0.81);
      expect(pair.suggestion.confidence, 0.82);
      expect(
        () => _document(
          suggestions: <FieldSuggestion>[pair.suggestion],
          fields: <ConfirmedField>[pair.field],
        ),
        throwsArgumentError,
      );
      expect(
        () => _content(
          suggestions: <FieldSuggestion>[pair.suggestion],
          fields: <ConfirmedField>[pair.field],
        ),
        throwsArgumentError,
      );

      // The suggestion id embeds its page, so a cross-page machine reference
      // is rejected when the field is constructed.
      expect(
        () => _machineField(pageIndex: 0, sourceSuggestionId: 's_p1_0001'),
        throwsArgumentError,
      );
      expect(
        () => _machineField(pageIndex: 1, sourceSuggestionId: 's_p0_0001'),
        throwsArgumentError,
      );
    });

    test('sourceSuggestionId and suggestionConfidence are required exactly for '
        'Provenance.machine', () {
      expect(
        () => ConfirmedField(
          id: _uuid(40),
          pageIndex: 0,
          rect: _rect(),
          type: FieldType.text,
          provenance: Provenance.machine,
          label: 'Feld',
          order: 0,
          createdAt: _at(),
          updatedAt: _at(1),
        ),
        throwsArgumentError,
      );
      expect(
        () => ConfirmedField(
          id: _uuid(41),
          pageIndex: 0,
          rect: _rect(),
          type: FieldType.text,
          provenance: Provenance.machine,
          sourceSuggestionId: 's_p0_0001',
          label: 'Feld',
          order: 0,
          createdAt: _at(),
          updatedAt: _at(1),
        ),
        throwsArgumentError,
      );
      expect(
        () => ConfirmedField(
          id: _uuid(42),
          pageIndex: 0,
          rect: _rect(),
          type: FieldType.text,
          provenance: Provenance.user,
          sourceSuggestionId: 's_p0_0001',
          label: 'Feld',
          order: 0,
          createdAt: _at(),
          updatedAt: _at(1),
        ),
        throwsArgumentError,
      );
      expect(
        () => ConfirmedField(
          id: _uuid(43),
          pageIndex: 0,
          rect: _rect(),
          type: FieldType.text,
          provenance: Provenance.user,
          suggestionConfidence: 0.82,
          label: 'Feld',
          order: 0,
          createdAt: _at(),
          updatedAt: _at(1),
        ),
        throwsArgumentError,
      );
      expect(
        () => ConfirmedField(
          id: _uuid(44),
          pageIndex: 0,
          rect: _rect(),
          type: FieldType.text,
          provenance: Provenance.template,
          sourceSuggestionId: 's_p0_0001',
          suggestionConfidence: 0.82,
          label: 'Feld',
          order: 0,
          createdAt: _at(),
          updatedAt: _at(1),
        ),
        throwsArgumentError,
      );
      expect(_userField(), isA<ConfirmedField>());

      final Map<String, Object?> userJson = _jsonRoundTrip(
        _userField().toJson(),
      )..['sourceSuggestionId'] = 's_p0_0001';
      expect(() => ConfirmedField.fromJson(userJson), throwsFormatException);

      final Map<String, Object?> machineJson = _jsonRoundTrip(
        _machineField(sourceSuggestionId: 's_p0_0001').toJson(),
      )..remove('suggestionConfidence');
      expect(() => ConfirmedField.fromJson(machineJson), throwsFormatException);
    });
  });

  group('provenance preservation', () {
    test('later type and label edits do not rewrite the suggestion record', () {
      final ({FieldSuggestion suggestion, ConfirmedField field}) pair =
          _confirmedPair();
      final ConfirmedField edited = pair.field.copyWith(
        type: FieldType.number,
        label: 'Betrag',
        updatedAt: _at(5),
      );

      expect(edited.type, FieldType.number);
      expect(edited.label, 'Betrag');
      expect(edited.sourceSuggestionId, pair.suggestion.id);
      expect(edited.suggestionConfidence, pair.suggestion.confidence);

      final Document document = _document(
        suggestions: <FieldSuggestion>[pair.suggestion],
        fields: <ConfirmedField>[edited],
      );
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[pair.suggestion],
        fields: <ConfirmedField>[edited],
      );

      expect(document.suggestions.single.proposedType, FieldType.text);
      expect(document.suggestions.single.rect, pair.field.rect);
      expect(document.suggestions.single.confidence, 0.82);
      expect(document.suggestions.single.labelText, 'Name');
      expect(
        document.suggestions.single.resolution,
        SuggestionResolution.confirmed,
      );
      expect(content.suggestions.single.proposedType, FieldType.text);
      expect(content.suggestions.single.confidence, 0.82);

      final Document reloadedDocument = Document.fromJson(
        _canonicalRoundTrip(document.toJson()),
      );
      final RevisionContent reloadedContent = RevisionContent.fromJson(
        _canonicalRoundTrip(content.toJson()),
      );

      expect(reloadedDocument, document);
      expect(reloadedContent, content);
      expect(reloadedDocument.fields.single.type, FieldType.number);
      expect(reloadedDocument.fields.single.label, 'Betrag');
      expect(reloadedDocument.suggestions.single.proposedType, FieldType.text);
      expect(reloadedContent.fields.single.type, FieldType.number);
      expect(reloadedContent.suggestions.single.proposedType, FieldType.text);
      expect(reloadedContent.suggestions.single.labelText, 'Name');
    });
  });

  group('determinism and JSON', () {
    test('every lifecycle state round-trips through canonical JSON '
        'deterministically', () {
      final FieldSuggestion unresolved = _suggestion();
      final FieldSuggestion rejected = unresolved.copyWith(
        resolution: SuggestionResolution.rejected,
      );
      final ({FieldSuggestion suggestion, ConfirmedField field}) pair =
          _confirmedPair();
      final FieldSuggestion undone = pair.suggestion.copyWith(
        resolution: SuggestionResolution.unresolved,
      );

      final List<
        ({List<FieldSuggestion> suggestions, List<ConfirmedField> fields})
      >
      states =
          <({List<FieldSuggestion> suggestions, List<ConfirmedField> fields})>[
            (
              suggestions: <FieldSuggestion>[unresolved],
              fields: <ConfirmedField>[],
            ),
            (
              suggestions: <FieldSuggestion>[rejected],
              fields: <ConfirmedField>[],
            ),
            (
              suggestions: <FieldSuggestion>[pair.suggestion],
              fields: <ConfirmedField>[pair.field],
            ),
            (
              suggestions: <FieldSuggestion>[undone],
              fields: <ConfirmedField>[],
            ),
          ];

      for (final ({
            List<FieldSuggestion> suggestions,
            List<ConfirmedField> fields,
          })
          state
          in states) {
        final Document document = _document(
          suggestions: state.suggestions,
          fields: state.fields,
        );
        final RevisionContent content = _content(
          suggestions: state.suggestions,
          fields: state.fields,
        );

        final String documentBytes = canonicalJsonEncode(document.toJson());
        final String contentBytes = canonicalJsonEncode(content.toJson());

        final Document reloadedDocument = Document.fromJson(
          _canonicalRoundTrip(document.toJson()),
        );
        final RevisionContent reloadedContent = RevisionContent.fromJson(
          _canonicalRoundTrip(content.toJson()),
        );

        expect(reloadedDocument, document);
        expect(reloadedContent, content);
        expect(canonicalJsonEncode(reloadedDocument.toJson()), documentBytes);
        expect(canonicalJsonEncode(reloadedContent.toJson()), contentBytes);
        expect(
          reloadedDocument.suggestions.single.resolution,
          state.suggestions.single.resolution,
        );
        expect(
          reloadedContent.suggestions.single.resolution,
          state.suggestions.single.resolution,
        );

        final Document rebuilt = _document(
          suggestions: state.suggestions,
          fields: state.fields,
        );
        expect(canonicalJsonEncode(rebuilt.toJson()), documentBytes);
      }
    });

    test('unknown same-schema fields survive the lifecycle round-trip at every '
        'level', () {
      final FieldSuggestion suggestion = _suggestion(
        evidence: _evidence(
          unknownFields: <String, Object?>{
            'x_t064_evidence': <String, Object?>{'v': 1},
          },
        ),
        unknownFields: <String, Object?>{'x_t064_suggestion': 'kept'},
      ).copyWith(resolution: SuggestionResolution.confirmed);
      final ConfirmedField field = _machineField(
        sourceSuggestionId: suggestion.id,
        rect: suggestion.rect,
        type: suggestion.proposedType,
        label: suggestion.labelText ?? 'Feld',
        unknownFields: <String, Object?>{'x_t064_field': 7},
      );
      final Document document = _document(
        suggestions: <FieldSuggestion>[suggestion],
        fields: <ConfirmedField>[field],
        unknownFields: <String, Object?>{
          'x_t064_document': <String, Object?>{'round': 1},
        },
      );
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[suggestion],
        fields: <ConfirmedField>[field],
        unknownFields: <String, Object?>{'x_t064_content': true},
      );

      final Document reloadedDocument = Document.fromJson(
        _canonicalRoundTrip(document.toJson()),
      );
      final RevisionContent reloadedContent = RevisionContent.fromJson(
        _canonicalRoundTrip(content.toJson()),
      );

      expect(
        reloadedDocument.suggestions.single.unknownFields['x_t064_suggestion'],
        'kept',
      );
      expect(
        reloadedDocument
            .suggestions
            .single
            .evidence
            .unknownFields['x_t064_evidence'],
        <String, Object?>{'v': 1},
      );
      expect(reloadedDocument.fields.single.unknownFields['x_t064_field'], 7);
      expect(
        reloadedDocument.unknownFields['x_t064_document'],
        <String, Object?>{'round': 1},
      );
      expect(
        reloadedContent.suggestions.single.unknownFields['x_t064_suggestion'],
        'kept',
      );
      expect(
        reloadedContent
            .suggestions
            .single
            .evidence
            .unknownFields['x_t064_evidence'],
        <String, Object?>{'v': 1},
      );
      expect(reloadedContent.fields.single.unknownFields['x_t064_field'], 7);
      expect(reloadedContent.unknownFields['x_t064_content'], true);
    });

    test('lifecycle invariant errors never echo label text', () {
      const String secret = 'T064-GEHEIM-LABEL';
      final FieldSuggestion confirmed = _suggestion(
        resolution: SuggestionResolution.confirmed,
        labelText: secret,
      );
      final FieldSuggestion unaffected = _suggestion(ordinal: 2);

      final List<String> messages = <String>[
        _messageOf(() => _document(suggestions: <FieldSuggestion>[confirmed])),
        _messageOf(() => _content(suggestions: <FieldSuggestion>[confirmed])),
        _messageOf(
          () =>
              _document(suggestions: <FieldSuggestion>[confirmed, unaffected]),
        ),
        _messageOf(
          () => _content(suggestions: <FieldSuggestion>[confirmed, unaffected]),
        ),
        _messageOf(
          () => _suggestion(labelText: List<String>.filled(201, 'X').join()),
        ),
        _messageOf(
          () => _machineField(
            sourceSuggestionId: 's_p0_0001',
            label: List<String>.filled(121, 'Y').join(),
          ),
        ),
        _messageOf(
          () => _suggestion(
            resolution: SuggestionResolution.confirmed,
            duplicateOfConfirmed: true,
            labelText: secret,
          ),
        ),
      ];

      for (final String message in messages) {
        expect(message, isNot(contains(secret)));
        expect(message, isNot(contains('XXXX')));
        expect(message, isNot(contains('YYYY')));
        expect(message, isNot(contains('s_p0')));
        expect(message, isNot(contains('Name')));
        expect(message, isNot(contains('/')));
      }
    });
  });

  group('no duplicate state model', () {
    test('resolution has exactly the three contract states', () {
      expect(
        SuggestionResolution.values
            .map((SuggestionResolution value) => value.wireName)
            .toList(),
        <String>['unresolved', 'confirmed', 'rejected'],
      );
      for (final SuggestionResolution value in SuggestionResolution.values) {
        expect(SuggestionResolution.fromWire(value.wireName), value);
      }
      for (final String rejectedToken in <String>[
        'duplicate_of_confirmed',
        'duplicateOfConfirmed',
        'confirmed_duplicate',
      ]) {
        expect(
          () => SuggestionResolution.fromWire(rejectedToken),
          throwsFormatException,
        );
      }
    });

    test('duplicateOfConfirmed is an audit flag on an unresolved suggestion, '
        'not a fourth resolution', () {
      final Rect base = _rect(left: 50, top: 60, width: 100, height: 100);
      final FieldSuggestion confirmed = _suggestion(
        rect: base,
        resolution: SuggestionResolution.confirmed,
      );
      final ConfirmedField machine = _machineField(
        sourceSuggestionId: confirmed.id,
        rect: base,
      );
      final FieldSuggestion flagged = _suggestion(
        ordinal: 2,
        rect: _rect(left: 60, top: 60, width: 80, height: 100),
        duplicateOfConfirmed: true,
      );

      expect(flagged.resolution, SuggestionResolution.unresolved);
      expect(flagged.duplicateOfConfirmed, isTrue);
      expect(flagged.toJson()['resolution'], 'unresolved');
      expect(flagged.toJson()['duplicateOfConfirmed'], true);
      expect(
        SuggestionResolution.values.map(
          (SuggestionResolution value) => value.wireName,
        ),
        isNot(contains('duplicateOfConfirmed')),
      );

      final Document document = _document(
        suggestions: <FieldSuggestion>[confirmed, flagged],
        fields: <ConfirmedField>[machine],
      );
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[confirmed, flagged],
        fields: <ConfirmedField>[machine],
      );

      expect(
        document.suggestions.last.resolution,
        SuggestionResolution.unresolved,
      );
      expect(document.suggestions.last.duplicateOfConfirmed, isTrue);
      expect(
        content.suggestions.last.resolution,
        SuggestionResolution.unresolved,
      );
      expect(content.suggestions.last.duplicateOfConfirmed, isTrue);

      final Document reloadedDocument = Document.fromJson(
        _canonicalRoundTrip(document.toJson()),
      );
      final RevisionContent reloadedContent = RevisionContent.fromJson(
        _canonicalRoundTrip(content.toJson()),
      );

      expect(
        reloadedDocument.suggestions.last.resolution,
        SuggestionResolution.unresolved,
      );
      expect(reloadedDocument.suggestions.last.duplicateOfConfirmed, isTrue);
      expect(
        reloadedContent.suggestions.last.resolution,
        SuggestionResolution.unresolved,
      );
      expect(reloadedContent.suggestions.last.duplicateOfConfirmed, isTrue);
    });
  });
}
