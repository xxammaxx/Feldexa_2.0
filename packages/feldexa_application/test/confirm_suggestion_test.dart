// T065 suggestion-review command tests.
//
// These are host-VM tests (evidence class NONE). They pin the T065 deliverable
// in `packages/feldexa_application/lib/src/review/confirm_suggestion.dart`
// against the normative lifecycle in `data-model.md` §3.4–§3.5,
// `contracts/recognition-output.md` §7, FR-021, FR-022, FR-027, and FR-028:
//   * confirm creates exactly one machine field with copied page, rect, type,
//     confidence, and provenance, appended order, and explicit UTC timestamps;
//   * reject and undo rejection never touch confirmed fields;
//   * confirm undo removes only the untouched generated field, renumbers the
//     remaining fields contiguously, and fails closed with `fieldTouched` when
//     the field was edited, moved, reordered, re-typed, retimed, or used;
//   * every result is a valid core `RevisionContent`;
//   * inputs are never mutated, commands are deterministic and free of
//     I/O/clock/id randomness, and every error is content-free.

import 'dart:convert';
import 'dart:io';

import 'package:feldexa_application/src/review/confirm_suggestion.dart';
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

TemplateOrigin _origin() {
  return TemplateOrigin(
    templateId: _uuid(80),
    templateVersionId: _uuid(81),
    templateVersionNumber: 3,
  );
}

SuggestionEvidence _evidence({
  List<SuggestionCue> cues = const <SuggestionCue>[SuggestionCue.line],
}) {
  return SuggestionEvidence(cues: cues);
}

FieldSuggestion _suggestion({
  int pageIndex = 0,
  int ordinal = 1,
  Rect? rect,
  FieldType proposedType = FieldType.text,
  double confidence = 0.82,
  String? labelText = 'Name',
  SuggestionResolution resolution = SuggestionResolution.unresolved,
  bool duplicateOfConfirmed = false,
  List<SuggestionCue> cues = const <SuggestionCue>[SuggestionCue.line],
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return FieldSuggestion(
    id: FieldSuggestion.idFor(pageIndex: pageIndex, ordinal: ordinal),
    pageIndex: pageIndex,
    rect: rect ?? _rect(),
    proposedType: proposedType,
    confidence: confidence,
    labelText: labelText,
    evidence: _evidence(cues: cues),
    resolution: resolution,
    duplicateOfConfirmed: duplicateOfConfirmed,
    unknownFields: unknownFields,
  );
}

ConfirmedField _machineField({
  required String id,
  required String sourceSuggestionId,
  int pageIndex = 0,
  Rect? rect,
  FieldType type = FieldType.text,
  double suggestionConfidence = 0.82,
  String label = 'Feld',
  int order = 0,
  DateTime? createdAt,
  DateTime? updatedAt,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return ConfirmedField(
    id: id,
    pageIndex: pageIndex,
    rect: rect ?? _rect(),
    type: type,
    provenance: Provenance.machine,
    sourceSuggestionId: sourceSuggestionId,
    suggestionConfidence: suggestionConfidence,
    label: label,
    order: order,
    createdAt: createdAt ?? _at(),
    updatedAt: updatedAt ?? _at(1),
    unknownFields: unknownFields,
  );
}

ConfirmedField _userField({
  required String id,
  required int order,
  String label = 'Bemerkung',
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return ConfirmedField(
    id: id,
    pageIndex: 0,
    rect: _rect(top: 200.0 + order * 40.0),
    type: FieldType.text,
    provenance: Provenance.user,
    label: label,
    order: order,
    createdAt: _at(),
    updatedAt: _at(1),
    unknownFields: unknownFields,
  );
}

RevisionContent _content({
  List<FieldSuggestion> suggestions = const <FieldSuggestion>[],
  List<ConfirmedField> fields = const <ConfirmedField>[],
  List<String>? fieldOrder,
  Map<String, FieldValue> values = const <String, FieldValue>{},
  Map<String, SignatureMark> signatures = const <String, SignatureMark>{},
  Map<String, FieldVerification> verification =
      const <String, FieldVerification>{},
  TemplateOrigin? templateOrigin,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return RevisionContent(
    pages: <Page>[_page()],
    suggestions: suggestions,
    fields: fields,
    fieldOrder:
        fieldOrder ??
        <String>[for (final ConfirmedField field in fields) field.id],
    values: values,
    signatures: signatures,
    verification: verification,
    templateOrigin: templateOrigin,
    unknownFields: unknownFields,
  );
}

RevisionContent _edited(
  RevisionContent base, {
  List<FieldSuggestion>? suggestions,
  List<ConfirmedField>? fields,
  List<String>? fieldOrder,
  Map<String, FieldValue>? values,
  Map<String, SignatureMark>? signatures,
  Map<String, FieldVerification>? verification,
}) {
  return RevisionContent(
    pages: base.pages,
    suggestions: suggestions ?? base.suggestions,
    fields: fields ?? base.fields,
    fieldOrder: fieldOrder ?? base.fieldOrder,
    values: values ?? base.values,
    signatures: signatures ?? base.signatures,
    verification: verification ?? base.verification,
    templateOrigin: base.templateOrigin,
    unknownFields: base.unknownFields,
  );
}

String _bytes(RevisionContent content) {
  return canonicalJsonEncode(content.toJson());
}

RevisionContent _reload(RevisionContent content) {
  return RevisionContent.fromJson(
    jsonDecode(canonicalJsonEncode(content.toJson())) as Map<String, Object?>,
  );
}

void _expectCanonicalRoundTrip(RevisionContent content) {
  final String bytes = _bytes(content);
  final RevisionContent reloaded = _reload(content);
  expect(reloaded, content);
  expect(_bytes(reloaded), bytes);
}

SuggestionReviewException _errorOf(void Function() action) {
  try {
    action();
  } on SuggestionReviewException catch (error) {
    return error;
  }
  fail('expected a SuggestionReviewException');
}

void _expectCode(void Function() action, SuggestionReviewErrorCode code) {
  expect(_errorOf(action).code, code);
}

void main() {
  group('confirmSuggestion', () {
    test('creates one machine field and copies provenance, page, rect, type, '
        'confidence, label, order, and timestamps', () {
      final FieldSuggestion suggestion = _suggestion(
        confidence: 0.82,
        labelText: 'Name',
        unknownFields: <String, Object?>{'x_t065_suggestion': 'kept'},
      );
      final ConfirmedField user = _userField(id: _uuid(30), order: 0);
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[suggestion],
        fields: <ConfirmedField>[user],
      );
      final String bytesBefore = _bytes(content);
      const String newFieldId = '00000000-0000-4000-8000-000000000028';

      final SuggestionReviewChange change = confirmSuggestion(
        content,
        suggestion.id,
        newFieldId,
        '  Betrag  ',
        _at(3),
      );

      expect(change.kind, SuggestionReviewChangeKind.confirmed);
      expect(change.suggestionId, suggestion.id);
      expect(change.fieldId, newFieldId);
      expect(change.confirmedField, isNotNull);

      final ConfirmedField field = change.confirmedField!;
      expect(field.id, newFieldId);
      expect(field.provenance, Provenance.machine);
      expect(field.sourceSuggestionId, suggestion.id);
      expect(field.suggestionConfidence, suggestion.confidence);
      expect(field.pageIndex, suggestion.pageIndex);
      expect(field.rect, suggestion.rect);
      expect(field.type, suggestion.proposedType);
      expect(field.label, 'Betrag');
      expect(field.order, 1);
      expect(field.createdAt, _at(3));
      expect(field.updatedAt, _at(3));
      expect(field.validation.isOk, isTrue);

      expect(change.content.fields.length, 2);
      expect(change.content.fields.last, field);
      expect(change.content.fieldOrder, <String>[user.id, newFieldId]);
      expect(
        change.content.suggestions.single.resolution,
        SuggestionResolution.confirmed,
      );
      expect(change.content.suggestions.single.labelText, 'Name');
      expect(
        change.content.suggestions.single.unknownFields['x_t065_suggestion'],
        'kept',
      );

      // The input snapshot is never mutated.
      expect(_bytes(content), bytesBefore);
      expect(
        content.suggestions.single.resolution,
        SuggestionResolution.unresolved,
      );
      expect(content.fields.single, user);

      _expectCanonicalRoundTrip(change.content);
    });

    test('preserves pages, unrelated fields, values, verification, template '
        'origin, and content unknown fields', () {
      final FieldSuggestion suggestion = _suggestion();
      final ConfirmedField user = _userField(id: _uuid(30), order: 0);
      final TextValue value = TextValue(
        text: 'unverändert',
        lastEditedAt: _at(),
      );
      final FieldVerification verification = FieldVerification(
        state: FieldVerificationState.confirmed,
        reviewedAt: _at(2),
      );
      final TemplateOrigin origin = _origin();
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[suggestion],
        fields: <ConfirmedField>[user],
        values: <String, FieldValue>{user.id: value},
        verification: <String, FieldVerification>{user.id: verification},
        templateOrigin: origin,
        unknownFields: <String, Object?>{
          'x_t065_content': <String, Object?>{'round': 1},
        },
      );

      final SuggestionReviewChange change = confirmSuggestion(
        content,
        suggestion.id,
        _uuid(40),
        'Feld',
        _at(),
      );

      expect(change.content.pages, content.pages);
      expect(change.content.fields.first, user);
      expect(change.content.values, <String, FieldValue>{user.id: value});
      expect(change.content.verification, <String, FieldVerification>{
        user.id: verification,
      });
      expect(change.content.templateOrigin, origin);
      expect(change.content.unknownFields, content.unknownFields);
      expect(change.content.signatures, content.signatures);
    });

    test('a missing suggestion is suggestionNotFound', () {
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[_suggestion()],
      );
      final String bytesBefore = _bytes(content);

      _expectCode(
        () => confirmSuggestion(content, 's_p0_0999', _uuid(40), 'Feld', _at()),
        SuggestionReviewErrorCode.suggestionNotFound,
      );
      expect(_bytes(content), bytesBefore);
    });

    test('a rejected or already confirmed suggestion is wrongState', () {
      final FieldSuggestion rejected = _suggestion(
        resolution: SuggestionResolution.rejected,
      );
      final RevisionContent rejectedContent = _content(
        suggestions: <FieldSuggestion>[rejected],
      );
      _expectCode(
        () => confirmSuggestion(
          rejectedContent,
          rejected.id,
          _uuid(40),
          'Feld',
          _at(),
        ),
        SuggestionReviewErrorCode.wrongState,
      );

      final FieldSuggestion confirmed = _suggestion(
        resolution: SuggestionResolution.confirmed,
      );
      final ConfirmedField field = _machineField(
        id: _uuid(21),
        sourceSuggestionId: confirmed.id,
      );
      final RevisionContent confirmedContent = _content(
        suggestions: <FieldSuggestion>[confirmed],
        fields: <ConfirmedField>[field],
      );
      final String bytesBefore = _bytes(confirmedContent);

      _expectCode(
        () => confirmSuggestion(
          confirmedContent,
          confirmed.id,
          _uuid(40),
          'Feld',
          _at(),
        ),
        SuggestionReviewErrorCode.wrongState,
      );
      // No second field is silently created for the same suggestion.
      expect(confirmedContent.fields.length, 1);
      expect(_bytes(confirmedContent), bytesBefore);
    });

    test('an unresolved suggestion with an existing machine field is '
        'unrepresentable in the core aggregate', () {
      final FieldSuggestion unresolved = _suggestion();
      final ConfirmedField orphan = _machineField(
        id: _uuid(21),
        sourceSuggestionId: unresolved.id,
      );

      expect(
        () => _content(
          suggestions: <FieldSuggestion>[unresolved],
          fields: <ConfirmedField>[orphan],
        ),
        throwsArgumentError,
      );
    });

    test('a duplicateOfConfirmed suggestion is duplicateNotConfirmable', () {
      final FieldSuggestion confirmed = _suggestion(
        resolution: SuggestionResolution.confirmed,
      );
      final ConfirmedField machine = _machineField(
        id: _uuid(21),
        sourceSuggestionId: confirmed.id,
        rect: confirmed.rect,
        type: confirmed.proposedType,
      );
      final FieldSuggestion duplicate = _suggestion(
        ordinal: 2,
        rect: confirmed.rect,
        proposedType: confirmed.proposedType,
        duplicateOfConfirmed: true,
        labelText: 'T065-DUPLICATE-LABEL',
      );
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[confirmed, duplicate],
        fields: <ConfirmedField>[machine],
      );
      final String bytesBefore = _bytes(content);

      _expectCode(
        () =>
            confirmSuggestion(content, duplicate.id, _uuid(40), 'Feld', _at()),
        SuggestionReviewErrorCode.duplicateNotConfirmable,
      );
      expect(content.fields.length, 1);
      expect(_bytes(content), bytesBefore);
    });

    test('an invalid field id is invalidInput', () {
      final FieldSuggestion suggestion = _suggestion();
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[suggestion],
      );

      for (final String invalidId in <String>[
        'not-a-uuid',
        '00000000-0000-4000-8000-0000000000AA',
        '00000000-0000-1000-8000-000000000000',
        '00000000-0000-4000-7000-000000000000',
      ]) {
        _expectCode(
          () => confirmSuggestion(
            content,
            suggestion.id,
            invalidId,
            'Feld',
            _at(),
          ),
          SuggestionReviewErrorCode.invalidInput,
        );
      }
    });

    test('an invalid label is invalidInput', () {
      final FieldSuggestion suggestion = _suggestion();
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[suggestion],
      );

      for (final String invalidLabel in <String>[
        '',
        '   ',
        List<String>.filled(121, 'X').join(),
        'T065\u0000GEHEIM',
      ]) {
        _expectCode(
          () => confirmSuggestion(
            content,
            suggestion.id,
            _uuid(40),
            invalidLabel,
            _at(),
          ),
          SuggestionReviewErrorCode.invalidInput,
        );
      }
    });

    test('a non-UTC timestamp is invalidInput', () {
      final FieldSuggestion suggestion = _suggestion();
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[suggestion],
      );

      _expectCode(
        () => confirmSuggestion(
          content,
          suggestion.id,
          _uuid(40),
          'Feld',
          DateTime(2026, 11, 20, 12),
        ),
        SuggestionReviewErrorCode.invalidInput,
      );
    });

    test('a field id already used by a confirmed field is invalidInput', () {
      final FieldSuggestion suggestion = _suggestion();
      final ConfirmedField user = _userField(id: _uuid(30), order: 0);
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[suggestion],
        fields: <ConfirmedField>[user],
      );

      _expectCode(
        () => confirmSuggestion(content, suggestion.id, user.id, 'Feld', _at()),
        SuggestionReviewErrorCode.invalidInput,
      );
    });
  });

  group('rejectSuggestion', () {
    test('rejects without changing any confirmed field or other content', () {
      final FieldSuggestion first = _suggestion();
      final FieldSuggestion second = _suggestion(ordinal: 2, labelText: 'Ort');
      final ConfirmedField user = _userField(id: _uuid(30), order: 0);
      final TextValue value = TextValue(text: 'bleibt', lastEditedAt: _at());
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[first, second],
        fields: <ConfirmedField>[user],
        values: <String, FieldValue>{user.id: value},
        verification: <String, FieldVerification>{
          user.id: FieldVerification(
            state: FieldVerificationState.corrected,
            reviewedAt: _at(2),
          ),
        },
        templateOrigin: _origin(),
        unknownFields: <String, Object?>{'x_t065_content': true},
      );
      final String bytesBefore = _bytes(content);

      final SuggestionReviewChange change = rejectSuggestion(
        content,
        second.id,
      );

      expect(change.kind, SuggestionReviewChangeKind.rejected);
      expect(change.suggestionId, second.id);
      expect(change.fieldId, isNull);
      expect(change.confirmedField, isNull);
      expect(change.content.fields, content.fields);
      expect(change.content.fieldOrder, content.fieldOrder);
      expect(change.content.values, content.values);
      expect(change.content.verification, content.verification);
      expect(change.content.templateOrigin, content.templateOrigin);
      expect(change.content.unknownFields, content.unknownFields);
      expect(
        change.content.suggestions.first.resolution,
        SuggestionResolution.unresolved,
      );
      expect(
        change.content.suggestions.last.resolution,
        SuggestionResolution.rejected,
      );
      expect(_bytes(content), bytesBefore);
      _expectCanonicalRoundTrip(change.content);
    });

    test('rejecting a flagged duplicate is allowed and creates no field', () {
      final FieldSuggestion confirmed = _suggestion(
        resolution: SuggestionResolution.confirmed,
      );
      final ConfirmedField machine = _machineField(
        id: _uuid(21),
        sourceSuggestionId: confirmed.id,
        rect: confirmed.rect,
        type: confirmed.proposedType,
      );
      final FieldSuggestion duplicate = _suggestion(
        ordinal: 2,
        rect: confirmed.rect,
        proposedType: confirmed.proposedType,
        duplicateOfConfirmed: true,
      );
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[confirmed, duplicate],
        fields: <ConfirmedField>[machine],
      );

      final SuggestionReviewChange change = rejectSuggestion(
        content,
        duplicate.id,
      );

      expect(
        change.content.suggestions.last.resolution,
        SuggestionResolution.rejected,
      );
      expect(change.content.suggestions.last.duplicateOfConfirmed, isTrue);
      expect(change.content.fields, content.fields);
      _expectCanonicalRoundTrip(change.content);
    });

    test('wrong states and missing suggestions fail closed', () {
      final RevisionContent unresolved = _content(
        suggestions: <FieldSuggestion>[_suggestion()],
      );
      _expectCode(
        () => rejectSuggestion(unresolved, 's_p0_0999'),
        SuggestionReviewErrorCode.suggestionNotFound,
      );

      final FieldSuggestion rejected = _suggestion(
        resolution: SuggestionResolution.rejected,
      );
      final RevisionContent rejectedContent = _content(
        suggestions: <FieldSuggestion>[rejected],
      );
      _expectCode(
        () => rejectSuggestion(rejectedContent, rejected.id),
        SuggestionReviewErrorCode.wrongState,
      );

      final FieldSuggestion confirmed = _suggestion(
        resolution: SuggestionResolution.confirmed,
      );
      final ConfirmedField machine = _machineField(
        id: _uuid(21),
        sourceSuggestionId: confirmed.id,
      );
      final RevisionContent confirmedContent = _content(
        suggestions: <FieldSuggestion>[confirmed],
        fields: <ConfirmedField>[machine],
      );
      _expectCode(
        () => rejectSuggestion(confirmedContent, confirmed.id),
        SuggestionReviewErrorCode.wrongState,
      );
    });
  });

  group('undoRejection', () {
    test('restores unresolved without touching fields or other content', () {
      final FieldSuggestion candidate = _suggestion(
        resolution: SuggestionResolution.rejected,
        unknownFields: <String, Object?>{'x_t065_suggestion': 'kept'},
      );
      final ConfirmedField user = _userField(id: _uuid(30), order: 0);
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[candidate],
        fields: <ConfirmedField>[user],
        values: <String, FieldValue>{
          user.id: TextValue(text: 'bleibt', lastEditedAt: _at()),
        },
      );
      final String bytesBefore = _bytes(content);

      final SuggestionReviewChange change = undoRejection(
        content,
        candidate.id,
      );

      expect(change.kind, SuggestionReviewChangeKind.rejectionUndone);
      expect(change.suggestionId, candidate.id);
      expect(change.fieldId, isNull);
      expect(change.confirmedField, isNull);
      expect(
        change.content.suggestions.single.resolution,
        SuggestionResolution.unresolved,
      );
      expect(
        change.content.suggestions.single.unknownFields['x_t065_suggestion'],
        'kept',
      );
      expect(change.content.fields, content.fields);
      expect(change.content.fieldOrder, content.fieldOrder);
      expect(change.content.values, content.values);
      expect(_bytes(content), bytesBefore);
      _expectCanonicalRoundTrip(change.content);
    });

    test('wrong states and missing suggestions fail closed', () {
      final FieldSuggestion unresolved = _suggestion();
      final RevisionContent unresolvedContent = _content(
        suggestions: <FieldSuggestion>[unresolved],
      );
      _expectCode(
        () => undoRejection(unresolvedContent, unresolved.id),
        SuggestionReviewErrorCode.wrongState,
      );
      _expectCode(
        () => undoRejection(unresolvedContent, 's_p0_0999'),
        SuggestionReviewErrorCode.suggestionNotFound,
      );

      final FieldSuggestion confirmed = _suggestion(
        resolution: SuggestionResolution.confirmed,
      );
      final ConfirmedField machine = _machineField(
        id: _uuid(21),
        sourceSuggestionId: confirmed.id,
      );
      final RevisionContent confirmedContent = _content(
        suggestions: <FieldSuggestion>[confirmed],
        fields: <ConfirmedField>[machine],
      );
      _expectCode(
        () => undoRejection(confirmedContent, confirmed.id),
        SuggestionReviewErrorCode.wrongState,
      );
    });
  });

  group('undoConfirmation', () {
    late FieldSuggestion suggestion;
    late ConfirmedField first;
    late ConfirmedField generated;
    late ConfirmedField last;
    late RevisionContent confirmedContent;
    late SuggestionReviewChange confirmation;

    setUp(() {
      suggestion = _suggestion(
        unknownFields: <String, Object?>{'x_t065_suggestion': 'kept'},
      );
      first = _userField(id: _uuid(30), order: 0);
      final RevisionContent base = _content(
        suggestions: <FieldSuggestion>[suggestion],
        fields: <ConfirmedField>[first],
        values: <String, FieldValue>{
          first.id: TextValue(text: 'unberührt', lastEditedAt: _at()),
        },
        templateOrigin: _origin(),
        unknownFields: <String, Object?>{'x_t065_content': true},
      );
      confirmation = confirmSuggestion(
        base,
        suggestion.id,
        _uuid(40),
        'Feld',
        _at(3),
      );
      generated = confirmation.confirmedField!;
      last = _userField(id: _uuid(31), order: 2, label: 'Ort');
      confirmedContent = _edited(
        confirmation.content,
        fields: <ConfirmedField>[first, generated, last],
        fieldOrder: <String>[first.id, generated.id, last.id],
        values: <String, FieldValue>{
          first.id: TextValue(text: 'unberührt', lastEditedAt: _at()),
          last.id: TextValue(text: 'auch', lastEditedAt: _at()),
        },
        verification: <String, FieldVerification>{
          last.id: FieldVerification(
            state: FieldVerificationState.confirmed,
            reviewedAt: _at(2),
          ),
        },
      );
    });

    test('removes the untouched generated field and renumbers the remaining '
        'fields contiguously in fieldOrder sequence', () {
      final String bytesBefore = _bytes(confirmedContent);

      final SuggestionReviewChange change = undoConfirmation(
        confirmedContent,
        suggestion.id,
        generated,
      );

      expect(change.kind, SuggestionReviewChangeKind.confirmationUndone);
      expect(change.suggestionId, suggestion.id);
      expect(change.fieldId, generated.id);
      expect(change.confirmedField, isNull);

      expect(
        change.content.suggestions.single.resolution,
        SuggestionResolution.unresolved,
      );
      expect(
        change.content.suggestions.single.unknownFields['x_t065_suggestion'],
        'kept',
      );
      expect(change.content.fieldOrder, <String>[first.id, last.id]);
      expect(change.content.fields.length, 2);
      expect(change.content.fields.first, first);
      expect(change.content.fields.last.id, last.id);
      expect(change.content.fields.last.order, 1);
      // Renumbering changes only `order`; the field's history is preserved.
      expect(change.content.fields.last.createdAt, last.createdAt);
      expect(change.content.fields.last.updatedAt, last.updatedAt);
      expect(change.content.values, confirmedContent.values);
      expect(change.content.verification, confirmedContent.verification);
      expect(change.content.templateOrigin, confirmedContent.templateOrigin);
      expect(change.content.unknownFields, confirmedContent.unknownFields);
      expect(change.content.pages, confirmedContent.pages);

      // The input snapshot is never mutated.
      expect(_bytes(confirmedContent), bytesBefore);
      expect(confirmedContent.fields.length, 3);

      _expectCanonicalRoundTrip(change.content);

      // A second undo is a wrong state, not a silent second removal.
      _expectCode(
        () => undoConfirmation(change.content, suggestion.id, generated),
        SuggestionReviewErrorCode.wrongState,
      );
    });

    test('removing the last field keeps the remaining order unchanged', () {
      final ConfirmedField only = _userField(id: _uuid(30), order: 0);
      final FieldSuggestion candidate = _suggestion();
      final RevisionContent base = _content(
        suggestions: <FieldSuggestion>[candidate],
        fields: <ConfirmedField>[only],
      );
      final SuggestionReviewChange confirmation = confirmSuggestion(
        base,
        candidate.id,
        _uuid(41),
        'Feld',
        _at(4),
      );

      final SuggestionReviewChange change = undoConfirmation(
        confirmation.content,
        candidate.id,
        confirmation.confirmedField!,
      );

      expect(change.content.fieldOrder, <String>[only.id]);
      expect(change.content.fields.single.id, only.id);
      expect(change.content.fields.single.order, 0);
      _expectCanonicalRoundTrip(change.content);
    });

    test('an expected field id that is absent is fieldNotFound', () {
      final ConfirmedField absent = _machineField(
        id: _uuid(99),
        sourceSuggestionId: suggestion.id,
        rect: suggestion.rect,
        type: suggestion.proposedType,
        order: 1,
      );

      _expectCode(
        () => undoConfirmation(confirmedContent, suggestion.id, absent),
        SuggestionReviewErrorCode.fieldNotFound,
      );
    });

    test('an expected field that exists but is not the linked machine field '
        'is fieldTouched', () {
      _expectCode(
        () => undoConfirmation(confirmedContent, suggestion.id, first),
        SuggestionReviewErrorCode.fieldTouched,
      );
    });

    test('a changed label is fieldTouched and leaves content unchanged', () {
      final RevisionContent editedContent = _edited(
        confirmedContent,
        fields: <ConfirmedField>[
          first,
          generated.copyWith(label: 'Geändert'),
          last,
        ],
      );
      final String bytesBefore = _bytes(editedContent);

      _expectCode(
        () => undoConfirmation(editedContent, suggestion.id, generated),
        SuggestionReviewErrorCode.fieldTouched,
      );
      expect(_bytes(editedContent), bytesBefore);
      expect(editedContent.fields.length, 3);
    });

    test('a changed type is fieldTouched', () {
      final RevisionContent editedContent = _edited(
        confirmedContent,
        fields: <ConfirmedField>[
          first,
          generated.copyWith(type: FieldType.number),
          last,
        ],
      );

      _expectCode(
        () => undoConfirmation(editedContent, suggestion.id, generated),
        SuggestionReviewErrorCode.fieldTouched,
      );
    });

    test('a changed rect is fieldTouched', () {
      final RevisionContent editedContent = _edited(
        confirmedContent,
        fields: <ConfirmedField>[
          first,
          generated.copyWith(rect: _rect(left: 70, top: 80)),
          last,
        ],
      );

      _expectCode(
        () => undoConfirmation(editedContent, suggestion.id, generated),
        SuggestionReviewErrorCode.fieldTouched,
      );
    });

    test('a changed order is fieldTouched', () {
      final RevisionContent editedContent = _edited(
        confirmedContent,
        fields: <ConfirmedField>[
          generated.copyWith(order: 0),
          first.copyWith(order: 1),
          last,
        ],
        fieldOrder: <String>[generated.id, first.id, last.id],
      );

      _expectCode(
        () => undoConfirmation(editedContent, suggestion.id, generated),
        SuggestionReviewErrorCode.fieldTouched,
      );
    });

    test('a changed timestamp is fieldTouched', () {
      final RevisionContent editedContent = _edited(
        confirmedContent,
        fields: <ConfirmedField>[
          first,
          generated.copyWith(updatedAt: _at(9)),
          last,
        ],
      );

      _expectCode(
        () => undoConfirmation(editedContent, suggestion.id, generated),
        SuggestionReviewErrorCode.fieldTouched,
      );
    });

    test('an attached value is fieldTouched and leaves content unchanged', () {
      final RevisionContent editedContent = _edited(
        confirmedContent,
        values: <String, FieldValue>{
          ...confirmedContent.values,
          generated.id: TextValue(text: 'genutzt', lastEditedAt: _at()),
        },
      );
      final String bytesBefore = _bytes(editedContent);

      _expectCode(
        () => undoConfirmation(editedContent, suggestion.id, generated),
        SuggestionReviewErrorCode.fieldTouched,
      );
      expect(_bytes(editedContent), bytesBefore);
      expect(editedContent.values.containsKey(generated.id), isTrue);
    });

    test('an attached verification entry is fieldTouched', () {
      final RevisionContent editedContent = _edited(
        confirmedContent,
        verification: <String, FieldVerification>{
          ...confirmedContent.verification,
          generated.id: FieldVerification(
            state: FieldVerificationState.confirmed,
            reviewedAt: _at(),
          ),
        },
      );

      _expectCode(
        () => undoConfirmation(editedContent, suggestion.id, generated),
        SuggestionReviewErrorCode.fieldTouched,
      );
    });

    test('an attached signature value and mark are fieldTouched', () {
      final FieldSuggestion signatureSuggestion = _suggestion(
        ordinal: 2,
        rect: _rect(left: 50, top: 400, width: 180, height: 50),
        proposedType: FieldType.signature,
        confidence: 0.9,
        labelText: 'Unterschrift',
        cues: const <SuggestionCue>[SuggestionCue.signatureArea],
      );
      final ConfirmedField signatureField = _machineField(
        id: _uuid(42),
        sourceSuggestionId: signatureSuggestion.id,
        rect: signatureSuggestion.rect,
        type: FieldType.signature,
        suggestionConfidence: signatureSuggestion.confidence,
        label: 'Unterschrift',
        order: 0,
      );
      final FieldSuggestion confirmedSignature = signatureSuggestion.copyWith(
        resolution: SuggestionResolution.confirmed,
      );
      const String assetId = '00000000-0000-4000-8000-000000000073';
      final SignatureMark mark = SignatureMark(
        assetId: assetId,
        fieldId: signatureField.id,
        pageIndex: 0,
        rect: signatureField.rect,
        widthPx: 320,
        heightPx: 120,
        capturedAt: _at(),
        sha256: _sha256,
      );
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[confirmedSignature],
        fields: <ConfirmedField>[signatureField],
        values: <String, FieldValue>{
          signatureField.id: SignatureValue(
            signatureAssetId: assetId,
            lastEditedAt: _at(),
          ),
        },
        signatures: <String, SignatureMark>{signatureField.id: mark},
      );

      _expectCode(
        () => undoConfirmation(content, signatureSuggestion.id, signatureField),
        SuggestionReviewErrorCode.fieldTouched,
      );
    });

    test('missing suggestions and wrong states fail closed', () {
      final RevisionContent unresolvedContent = _content(
        suggestions: <FieldSuggestion>[_suggestion()],
      );
      _expectCode(
        () => undoConfirmation(unresolvedContent, 's_p0_0999', generated),
        SuggestionReviewErrorCode.suggestionNotFound,
      );
      _expectCode(
        () => undoConfirmation(unresolvedContent, _suggestion().id, generated),
        SuggestionReviewErrorCode.wrongState,
      );

      final FieldSuggestion rejected = _suggestion(
        resolution: SuggestionResolution.rejected,
      );
      final RevisionContent rejectedContent = _content(
        suggestions: <FieldSuggestion>[rejected],
      );
      _expectCode(
        () => undoConfirmation(rejectedContent, rejected.id, generated),
        SuggestionReviewErrorCode.wrongState,
      );
    });

    test('clears a duplicate flag that loses its supporting machine field', () {
      final FieldSuggestion target = _suggestion();
      final SuggestionReviewChange confirmation = confirmSuggestion(
        _content(suggestions: <FieldSuggestion>[target]),
        target.id,
        _uuid(40),
        'Feld',
        _at(),
      );
      final FieldSuggestion duplicate = _suggestion(
        ordinal: 2,
        rect: target.rect,
        proposedType: target.proposedType,
        duplicateOfConfirmed: true,
      );
      final RevisionContent content = _edited(
        confirmation.content,
        suggestions: <FieldSuggestion>[
          confirmation.content.suggestions.single,
          duplicate,
        ],
      );
      expect(content.fields.single.id, _uuid(40));
      expect(content.suggestions.last.duplicateOfConfirmed, isTrue);

      final SuggestionReviewChange change = undoConfirmation(
        content,
        target.id,
        confirmation.confirmedField!,
      );

      expect(change.content.fields, isEmpty);
      expect(change.content.suggestions.last.duplicateOfConfirmed, isFalse);
      expect(
        change.content.suggestions.last.resolution,
        SuggestionResolution.unresolved,
      );
      _expectCanonicalRoundTrip(change.content);
    });
  });

  group('cross-cutting guarantees', () {
    test('every successful command leaves its input unchanged', () {
      final FieldSuggestion candidate = _suggestion();
      final ConfirmedField user = _userField(id: _uuid(30), order: 0);
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[candidate],
        fields: <ConfirmedField>[user],
        values: <String, FieldValue>{
          user.id: TextValue(text: 'unverändert', lastEditedAt: _at()),
        },
        templateOrigin: _origin(),
        unknownFields: <String, Object?>{'x_t065_content': true},
      );
      final String bytesBefore = _bytes(content);
      final List<FieldSuggestion> suggestionsBefore = content.suggestions;
      final List<ConfirmedField> fieldsBefore = content.fields;

      final SuggestionReviewChange confirmation = confirmSuggestion(
        content,
        candidate.id,
        _uuid(40),
        'Feld',
        _at(),
      );
      expect(_bytes(content), bytesBefore);
      expect(identical(content.suggestions, suggestionsBefore), isTrue);
      expect(identical(content.fields, fieldsBefore), isTrue);

      final SuggestionReviewChange rejection = rejectSuggestion(
        content,
        candidate.id,
      );
      expect(_bytes(content), bytesBefore);
      expect(
        rejection.content.suggestions.single.resolution,
        isNot(SuggestionResolution.unresolved),
      );

      final RevisionContent rejectedContent = rejection.content;
      final String rejectedBytes = _bytes(rejectedContent);
      undoRejection(rejectedContent, candidate.id);
      expect(_bytes(rejectedContent), rejectedBytes);

      final RevisionContent confirmedContent = confirmation.content;
      final String confirmedBytes = _bytes(confirmedContent);
      undoConfirmation(
        confirmedContent,
        candidate.id,
        confirmation.confirmedField!,
      );
      expect(_bytes(confirmedContent), confirmedBytes);
    });

    test('commands are deterministic for identical inputs', () {
      RevisionContent makeContent() {
        final FieldSuggestion candidate = _suggestion();
        final ConfirmedField user = _userField(id: _uuid(30), order: 0);
        return _content(
          suggestions: <FieldSuggestion>[candidate],
          fields: <ConfirmedField>[user],
          values: <String, FieldValue>{
            user.id: TextValue(text: 'gleich', lastEditedAt: _at()),
          },
          unknownFields: <String, Object?>{'x_t065_content': true},
        );
      }

      final RevisionContent firstInput = makeContent();
      final RevisionContent secondInput = makeContent();
      final SuggestionReviewChange first = confirmSuggestion(
        firstInput,
        _suggestion().id,
        _uuid(40),
        'Feld',
        _at(3),
      );
      final SuggestionReviewChange second = confirmSuggestion(
        secondInput,
        _suggestion().id,
        _uuid(40),
        'Feld',
        _at(3),
      );

      expect(first, second);
      expect(_bytes(first.content), _bytes(second.content));

      final SuggestionReviewChange firstUndo = undoConfirmation(
        first.content,
        _suggestion().id,
        first.confirmedField!,
      );
      final SuggestionReviewChange secondUndo = undoConfirmation(
        second.content,
        _suggestion().id,
        second.confirmedField!,
      );
      expect(firstUndo, secondUndo);
      expect(_bytes(firstUndo.content), _bytes(secondUndo.content));
    });

    test('every success returns content accepted by the core aggregate', () {
      final FieldSuggestion candidate = _suggestion();
      RevisionContent content = _content(
        suggestions: <FieldSuggestion>[candidate],
      );
      _expectCanonicalRoundTrip(content);

      final SuggestionReviewChange confirmation = confirmSuggestion(
        content,
        candidate.id,
        _uuid(40),
        'Feld',
        _at(),
      );
      _expectCanonicalRoundTrip(confirmation.content);

      final SuggestionReviewChange undo = undoConfirmation(
        confirmation.content,
        candidate.id,
        confirmation.confirmedField!,
      );
      _expectCanonicalRoundTrip(undo.content);
      expect(undo.content.suggestions.single, candidate);
      expect(undo.content.fields, isEmpty);

      final SuggestionReviewChange rejection = rejectSuggestion(
        undo.content,
        candidate.id,
      );
      _expectCanonicalRoundTrip(rejection.content);

      final SuggestionReviewChange undoRejectionChange = undoRejection(
        rejection.content,
        candidate.id,
      );
      _expectCanonicalRoundTrip(undoRejectionChange.content);
      expect(undoRejectionChange.content, content);
    });

    test('every error message is content-free', () {
      final FieldSuggestion candidate = _suggestion(
        labelText: 'T065-GEHEIM-LABEL',
      );
      final RevisionContent content = _content(
        suggestions: <FieldSuggestion>[candidate],
      );
      final ConfirmedField user = _userField(id: _uuid(30), order: 0);
      final RevisionContent contentWithField = _content(
        suggestions: <FieldSuggestion>[candidate],
        fields: <ConfirmedField>[user],
      );
      final FieldSuggestion confirmed = _suggestion(
        resolution: SuggestionResolution.confirmed,
      );
      final ConfirmedField machine = _machineField(
        id: _uuid(21),
        sourceSuggestionId: confirmed.id,
      );
      final RevisionContent confirmedContent = _content(
        suggestions: <FieldSuggestion>[confirmed],
        fields: <ConfirmedField>[machine],
      );
      final FieldSuggestion duplicate = _suggestion(
        ordinal: 2,
        rect: confirmed.rect,
        proposedType: confirmed.proposedType,
        duplicateOfConfirmed: true,
      );
      final RevisionContent duplicateContent = _content(
        suggestions: <FieldSuggestion>[confirmed, duplicate],
        fields: <ConfirmedField>[machine],
      );

      final List<SuggestionReviewException> errors =
          <SuggestionReviewException>[
            _errorOf(
              () => confirmSuggestion(
                content,
                's_p0_0999',
                _uuid(40),
                'T065-GEHEIM-LABEL',
                _at(),
              ),
            ),
            _errorOf(
              () => confirmSuggestion(
                contentWithField,
                candidate.id,
                'T065-GEHEIM-ID',
                'T065-GEHEIM-LABEL',
                _at(),
              ),
            ),
            _errorOf(
              () => confirmSuggestion(
                duplicateContent,
                duplicate.id,
                _uuid(40),
                'Feld',
                _at(),
              ),
            ),
            _errorOf(
              () => confirmSuggestion(
                confirmedContent,
                confirmed.id,
                _uuid(40),
                'Feld',
                _at(),
              ),
            ),
            _errorOf(
              () => confirmSuggestion(
                content,
                candidate.id,
                'T065-GEHEIM-ID',
                'Feld',
                _at(),
              ),
            ),
            _errorOf(
              () => undoConfirmation(
                confirmedContent,
                confirmed.id,
                _machineField(
                  id: _uuid(99),
                  sourceSuggestionId: confirmed.id,
                  rect: confirmed.rect,
                  type: confirmed.proposedType,
                  label: 'Feld',
                ),
              ),
            ),
            _errorOf(
              () => undoConfirmation(
                confirmedContent,
                confirmed.id,
                machine.copyWith(label: 'T065-GEHEIM-LABEL'),
              ),
            ),
          ];

      expect(
        errors.map((SuggestionReviewException error) => error.code).toSet(),
        <SuggestionReviewErrorCode>{
          SuggestionReviewErrorCode.suggestionNotFound,
          SuggestionReviewErrorCode.wrongState,
          SuggestionReviewErrorCode.duplicateNotConfirmable,
          SuggestionReviewErrorCode.invalidInput,
          SuggestionReviewErrorCode.fieldNotFound,
          SuggestionReviewErrorCode.fieldTouched,
        },
      );

      for (final SuggestionReviewException error in errors) {
        expect(error.message, isNotEmpty);
        expect(error.message, isNot(contains('T065-GEHEIM')));
        expect(error.toString(), isNot(contains('T065-GEHEIM')));
        expect(error.message, isNot(contains('s_p0')));
        expect(error.toString(), isNot(contains('s_p0')));
        expect(error.message, isNot(contains(_uuid(30))));
        expect(error.toString(), isNot(contains(_uuid(30))));
        expect(error.message, isNot(contains('/')));
      }

      for (final SuggestionReviewErrorCode code
          in SuggestionReviewErrorCode.values) {
        final SuggestionReviewException exception = SuggestionReviewException(
          code,
        );
        expect(exception.message, isNotEmpty);
        expect(exception.toString(), contains(code.name));
        expect(exception.message, isNot(contains('T065-GEHEIM')));
      }
    });

    test('the command library has no I/O, clock, or id-randomness path', () {
      final File library = File('lib/src/review/confirm_suggestion.dart');
      expect(library.existsSync(), isTrue);
      final String source = library.readAsStringSync();

      for (final String forbidden in <String>[
        'dart:io',
        'dart:math',
        'DateTime.now',
        'Random(',
        'Stopwatch',
        'package:uuid',
        'Uuid().v4',
      ]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason: 'the pure command library must not contain $forbidden',
        );
      }
    });
  });
}
