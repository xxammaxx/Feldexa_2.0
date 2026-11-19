// T058 suggestion, resolution, and provenance persistence tests.
//
// These are host-VM tests (evidence class NONE). They pin
// `contracts/recognition-output.md` §7 and `data-model.md` §3.3–§3.5, §6, and
// §7:
//   * the persisted `duplicateOfConfirmed` flag (default, omission, legacy
//     JSON, canonical JSON, equality, copy-with, unknown-field retention);
//   * the recognized-suggestion/machine-field consistency invariants in both
//     `Document` and `RevisionContent`;
//   * the pure, deterministic reanalysis duplicate marker with exact canonical
//     1/8 pt IoU arithmetic and the inclusive 0.8 boundary;
//   * revision/document round-trips of resolution and provenance;
//   * content-free invariant errors.

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

SuggestionEvidence _evidence() {
  return SuggestionEvidence(cues: const <SuggestionCue>[SuggestionCue.line]);
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
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return FieldSuggestion(
    id: FieldSuggestion.idFor(pageIndex: pageIndex, ordinal: ordinal),
    pageIndex: pageIndex,
    rect: rect ?? _rect(),
    proposedType: proposedType,
    confidence: confidence,
    labelText: labelText,
    evidence: _evidence(),
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
    updatedAt: _at(1),
  );
}

ConfirmedField _userField({
  Rect? rect,
  FieldType type = FieldType.text,
  int order = 0,
}) {
  return ConfirmedField(
    id: _uuid(30 + order),
    pageIndex: 0,
    rect: rect ?? _rect(),
    type: type,
    provenance: Provenance.user,
    label: 'Feld',
    order: order,
    createdAt: _at(),
    updatedAt: _at(1),
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
  );
}

RevisionContent _content({
  List<Page>? pages,
  List<FieldSuggestion> suggestions = const <FieldSuggestion>[],
  List<ConfirmedField> fields = const <ConfirmedField>[],
  List<String>? fieldOrder,
}) {
  return RevisionContent(
    pages: pages ?? <Page>[_page()],
    suggestions: suggestions,
    fields: fields,
    fieldOrder:
        fieldOrder ??
        <String>[for (final ConfirmedField field in fields) field.id],
  );
}

Revision _revision(RevisionContent content) {
  return Revision(
    id: _uuid(91),
    documentId: _uuid(2),
    kind: RevisionKind.explicit,
    createdAt: _at(2),
    plaintextSha256: _sha256,
    content: content,
  );
}

({FieldSuggestion suggestion, ConfirmedField field}) _confirmedPair({
  double suggestionConfidence = 0.82,
  double fieldConfidence = 0.82,
  Rect? rect,
}) {
  final FieldSuggestion suggestion = _suggestion(
    rect: rect,
    confidence: suggestionConfidence,
    resolution: SuggestionResolution.confirmed,
  );
  return (
    suggestion: suggestion,
    field: _machineField(
      sourceSuggestionId: suggestion.id,
      suggestionConfidence: fieldConfidence,
      rect: rect,
    ),
  );
}

/// A valid snapshot with one confirmed suggestion, its machine field, and one
/// duplicate-marked suggestion at the inclusive 0.8 IoU boundary.
({List<FieldSuggestion> suggestions, List<ConfirmedField> fields})
_duplicateSet() {
  final Rect base = _rect(left: 50, top: 60, width: 100, height: 100);
  final FieldSuggestion confirmed = _suggestion(
    rect: base,
    resolution: SuggestionResolution.confirmed,
  );
  final ConfirmedField machine = _machineField(
    sourceSuggestionId: confirmed.id,
    rect: base,
  );
  final FieldSuggestion duplicate = _suggestion(
    ordinal: 2,
    rect: _rect(left: 60, top: 60, width: 80, height: 100),
    duplicateOfConfirmed: true,
  );
  return (
    suggestions: <FieldSuggestion>[confirmed, duplicate],
    fields: <ConfirmedField>[machine],
  );
}

String _messageOf(void Function() action) {
  try {
    action();
  } on ArgumentError catch (error) {
    return error.message.toString();
  }
  fail('expected an ArgumentError');
}

void main() {
  group('duplicateOfConfirmed persistence flag', () {
    test('defaults to false and is omitted from JSON', () {
      final FieldSuggestion suggestion = _suggestion();
      expect(suggestion.duplicateOfConfirmed, isFalse);
      expect(suggestion.toJson().containsKey('duplicateOfConfirmed'), isFalse);
      final FieldSuggestion parsed = FieldSuggestion.fromJson(
        _jsonRoundTrip(suggestion.toJson()),
      );
      expect(parsed.duplicateOfConfirmed, isFalse);
      expect(parsed, suggestion);
    });

    test('serializes only when true and round-trips', () {
      final FieldSuggestion suggestion = _suggestion(
        duplicateOfConfirmed: true,
      );
      final Map<String, Object?> json = suggestion.toJson();
      expect(json['duplicateOfConfirmed'], isTrue);
      final FieldSuggestion parsed = FieldSuggestion.fromJson(
        _jsonRoundTrip(json),
      );
      expect(parsed.duplicateOfConfirmed, isTrue);
      expect(parsed, suggestion);
      expect(parsed.hashCode, suggestion.hashCode);
      expect(FieldSuggestion.fromLegacyJson(_jsonRoundTrip(json)), suggestion);
    });

    test('legacy JSON without the flag decodes as false', () {
      final FieldSuggestion suggestion = _suggestion();
      final Map<String, Object?> legacy = Map<String, Object?>.from(
        _jsonRoundTrip(suggestion.toJson()),
      );
      expect(legacy.containsKey('duplicateOfConfirmed'), isFalse);
      expect(FieldSuggestion.fromJson(legacy), suggestion);
      expect(FieldSuggestion.fromLegacyJson(legacy), suggestion);
    });

    test('rejects non-boolean or explicit null flag values', () {
      for (final Object? invalid in <Object?>['yes', 1, null]) {
        final Map<String, Object?> json = Map<String, Object?>.from(
          _jsonRoundTrip(_suggestion().toJson()),
        )..['duplicateOfConfirmed'] = invalid;
        expect(
          () => FieldSuggestion.fromJson(json),
          throwsFormatException,
          reason: 'value: $invalid',
        );
      }
    });

    test('copyWith sets and clears the flag; equality and JSON include it', () {
      final FieldSuggestion base = _suggestion();
      final FieldSuggestion flagged = base.copyWith(duplicateOfConfirmed: true);
      expect(flagged.duplicateOfConfirmed, isTrue);
      expect(flagged, isNot(equals(base)));
      expect(base.copyWith(duplicateOfConfirmed: false), base);
      expect(flagged.copyWith(confidence: 0.5).duplicateOfConfirmed, isTrue);

      final String baseJson = canonicalJsonEncode(base.toJson());
      final String flaggedJson = canonicalJsonEncode(flagged.toJson());
      expect(baseJson, isNot(flaggedJson));
      expect(baseJson, isNot(contains('duplicateOfConfirmed')));
      expect(flaggedJson, contains('"duplicateOfConfirmed":true'));
      expect(
        canonicalJsonEncode(
          FieldSuggestion.fromJson(_jsonRoundTrip(flagged.toJson())).toJson(),
        ),
        flaggedJson,
      );
    });

    test('rejects the flag on a confirmed suggestion', () {
      final String message = _messageOf(
        () => _suggestion(
          resolution: SuggestionResolution.confirmed,
          duplicateOfConfirmed: true,
          labelText: 'Streng-Geheim',
        ),
      );
      expect(message, isNot(contains('Streng-Geheim')));
      expect(message, isNot(contains('s_p0')));

      final FieldSuggestion confirmed = _suggestion(
        resolution: SuggestionResolution.confirmed,
      );
      expect(
        () => confirmed.copyWith(duplicateOfConfirmed: true),
        throwsArgumentError,
      );
      final FieldSuggestion flagged = _suggestion(duplicateOfConfirmed: true);
      expect(
        () => flagged.copyWith(resolution: SuggestionResolution.confirmed),
        throwsArgumentError,
      );
    });

    test('retains unknown fields alongside the flag', () {
      final Map<String, Object?> unknowns = <String, Object?>{
        'x_future': <String, Object?>{'n': 1},
      };
      final FieldSuggestion suggestion = _suggestion(
        duplicateOfConfirmed: true,
        unknownFields: unknowns,
      );
      final Map<String, Object?> json = _jsonRoundTrip(suggestion.toJson());
      expect(json['duplicateOfConfirmed'], isTrue);
      expect(json['x_future'], unknowns['x_future']);
      final FieldSuggestion parsed = FieldSuggestion.fromJson(json);
      expect(parsed.duplicateOfConfirmed, isTrue);
      expect(parsed.unknownFields['x_future'], unknowns['x_future']);
      expect(parsed, suggestion);
    });
  });

  group('markDuplicatesOfConfirmed', () {
    test(
      'flags an exact canonical 0.8 duplicate and not one grid step below',
      () {
        final ConfirmedField field = _machineField(
          sourceSuggestionId: 's_p0_0001',
          rect: _rect(left: 50, top: 60, width: 100, height: 100),
        );
        final FieldSuggestion boundary = _suggestion(
          rect: _rect(left: 60, top: 60, width: 80, height: 100),
        );
        final FieldSuggestion below = _suggestion(
          ordinal: 2,
          rect: _rect(left: 60, top: 60, width: 79.875, height: 100),
        );

        final List<FieldSuggestion> marked = markDuplicatesOfConfirmed(
          suggestions: <FieldSuggestion>[boundary, below],
          confirmedFields: <ConfirmedField>[field],
        );

        expect(marked[0].duplicateOfConfirmed, isTrue);
        expect(marked[1].duplicateOfConfirmed, isFalse);
        // Inputs are never mutated.
        expect(boundary.duplicateOfConfirmed, isFalse);
        expect(below.duplicateOfConfirmed, isFalse);
      },
    );

    test('rounds both rects to the canonical 1/8 pt grid first', () {
      final ConfirmedField field = _machineField(
        sourceSuggestionId: 's_p0_0001',
        rect: Rect.fromLTWH(49.97, 59.99, 100.02, 100.04),
      );
      final FieldSuggestion boundary = _suggestion(
        rect: _rect(left: 60, top: 60, width: 80, height: 100),
      );

      final List<FieldSuggestion> marked = markDuplicatesOfConfirmed(
        suggestions: <FieldSuggestion>[boundary],
        confirmedFields: <ConfirmedField>[field],
      );

      expect(marked.single.duplicateOfConfirmed, isTrue);
    });

    test('ignores a different type and non-machine fields', () {
      final FieldSuggestion suggestion = _suggestion(
        rect: _rect(left: 60, top: 60, width: 80, height: 100),
      );
      final ConfirmedField wrongType = _machineField(
        sourceSuggestionId: 's_p0_0001',
        rect: _rect(left: 50, top: 60, width: 100, height: 100),
        type: FieldType.date,
      );
      final ConfirmedField userField = _userField(
        rect: _rect(left: 50, top: 60, width: 100, height: 100),
      );

      expect(
        markDuplicatesOfConfirmed(
          suggestions: <FieldSuggestion>[suggestion],
          confirmedFields: <ConfirmedField>[wrongType],
        ).single.duplicateOfConfirmed,
        isFalse,
      );
      expect(
        markDuplicatesOfConfirmed(
          suggestions: <FieldSuggestion>[suggestion],
          confirmedFields: <ConfirmedField>[userField],
        ).single.duplicateOfConfirmed,
        isFalse,
      );
    });

    test('leaves an already-confirmed suggestion unchanged', () {
      final Rect base = _rect(left: 50, top: 60, width: 100, height: 100);
      final FieldSuggestion confirmed = _suggestion(
        rect: base,
        resolution: SuggestionResolution.confirmed,
      );
      final ConfirmedField field = _machineField(
        sourceSuggestionId: confirmed.id,
        rect: base,
      );

      final List<FieldSuggestion> marked = markDuplicatesOfConfirmed(
        suggestions: <FieldSuggestion>[confirmed],
        confirmedFields: <ConfirmedField>[field],
      );

      expect(identical(marked.single, confirmed), isTrue);
      expect(marked.single.resolution, SuggestionResolution.confirmed);
      expect(marked.single.duplicateOfConfirmed, isFalse);
    });

    test('is deterministic and order-preserving under shuffled input', () {
      final ConfirmedField first = _machineField(
        sourceSuggestionId: 's_p0_0001',
        rect: _rect(left: 50, top: 60, width: 100, height: 100),
      );
      final ConfirmedField second = _machineField(
        sourceSuggestionId: 's_p0_0002',
        rect: _rect(left: 300, top: 60, width: 100, height: 100),
        order: 1,
      );
      final FieldSuggestion a = _suggestion(
        ordinal: 1,
        rect: _rect(left: 60, top: 60, width: 80, height: 100),
      );
      final FieldSuggestion b = _suggestion(
        ordinal: 2,
        rect: _rect(left: 310, top: 60, width: 80, height: 100),
      );
      final FieldSuggestion c = _suggestion(
        ordinal: 3,
        rect: _rect(left: 60, top: 60, width: 79.875, height: 100),
      );
      final FieldSuggestion d = _suggestion(
        ordinal: 4,
        rect: _rect(left: 500, top: 700, width: 20, height: 20),
      );

      Map<String, bool> flagsOf(
        List<FieldSuggestion> suggestions,
        List<ConfirmedField> fields,
      ) {
        return <String, bool>{
          for (final FieldSuggestion suggestion in markDuplicatesOfConfirmed(
            suggestions: suggestions,
            confirmedFields: fields,
          ))
            suggestion.id: suggestion.duplicateOfConfirmed,
        };
      }

      final Map<String, bool> original = flagsOf(
        <FieldSuggestion>[a, b, c, d],
        <ConfirmedField>[first, second],
      );
      expect(original, <String, bool>{
        a.id: true,
        b.id: true,
        c.id: false,
        d.id: false,
      });
      expect(
        flagsOf(<FieldSuggestion>[d, b, a, c], <ConfirmedField>[second, first]),
        original,
      );
      expect(
        flagsOf(<FieldSuggestion>[c, a, d, b], <ConfirmedField>[first, second]),
        original,
      );

      final List<FieldSuggestion> shuffled = <FieldSuggestion>[c, b, d, a];
      final List<FieldSuggestion> marked = markDuplicatesOfConfirmed(
        suggestions: shuffled,
        confirmedFields: <ConfirmedField>[second, first],
      );
      expect(
        marked.map((FieldSuggestion item) => item.id).toList(),
        shuffled.map((FieldSuggestion item) => item.id).toList(),
      );
      expect(marked.length, shuffled.length);
      expect(
        marked.map((FieldSuggestion item) => item.resolution).toList(),
        shuffled.map((FieldSuggestion item) => item.resolution).toList(),
      );
    });
  });

  group('aggregate suggestion/provenance invariants', () {
    test('accepts a confirmed suggestion with its machine field', () {
      final ({FieldSuggestion suggestion, ConfirmedField field}) pair =
          _confirmedPair();

      for (final Object aggregate in <Object>[
        _document(
          suggestions: <FieldSuggestion>[pair.suggestion],
          fields: <ConfirmedField>[pair.field],
        ),
        _content(
          suggestions: <FieldSuggestion>[pair.suggestion],
          fields: <ConfirmedField>[pair.field],
        ),
      ]) {
        expect(aggregate, isA<Object>());
      }

      final Document document = _document(
        suggestions: <FieldSuggestion>[pair.suggestion],
        fields: <ConfirmedField>[pair.field],
      );
      final Document reloaded = Document.fromJson(
        _jsonRoundTrip(document.toJson()),
      );
      expect(reloaded, document);
      expect(
        reloaded.suggestions.single.resolution,
        SuggestionResolution.confirmed,
      );
      expect(reloaded.fields.single.provenance, Provenance.machine);
      expect(reloaded.fields.single.sourceSuggestionId, pair.suggestion.id);
      expect(reloaded.fields.single.suggestionConfidence, 0.82);
    });

    test('accepts a valid duplicate marker and round-trips it', () {
      final ({List<FieldSuggestion> suggestions, List<ConfirmedField> fields})
      set = _duplicateSet();
      final Document document = _document(
        suggestions: set.suggestions,
        fields: set.fields,
      );
      final RevisionContent content = _content(
        suggestions: set.suggestions,
        fields: set.fields,
      );

      expect(document.suggestions.last.duplicateOfConfirmed, isTrue);
      expect(content.suggestions.last.duplicateOfConfirmed, isTrue);

      final Document reloadedDocument = Document.fromJson(
        _jsonRoundTrip(document.toJson()),
      );
      final RevisionContent reloadedContent = RevisionContent.fromJson(
        _jsonRoundTrip(content.toJson()),
      );
      expect(reloadedDocument, document);
      expect(reloadedContent, content);
      expect(reloadedDocument.suggestions.last.duplicateOfConfirmed, isTrue);
      expect(reloadedContent.suggestions.last.duplicateOfConfirmed, isTrue);
      expect(
        reloadedContent.suggestions.last.resolution,
        SuggestionResolution.unresolved,
      );
      expect(reloadedContent.fields.single.provenance, Provenance.machine);
    });

    test('allows a rejected duplicate marker', () {
      final Rect base = _rect(left: 50, top: 60, width: 100, height: 100);
      final FieldSuggestion confirmed = _suggestion(
        rect: base,
        resolution: SuggestionResolution.confirmed,
      );
      final ConfirmedField machine = _machineField(
        sourceSuggestionId: confirmed.id,
        rect: base,
      );
      final FieldSuggestion rejected = _suggestion(
        ordinal: 2,
        rect: _rect(left: 60, top: 60, width: 80, height: 100),
        resolution: SuggestionResolution.rejected,
        duplicateOfConfirmed: true,
      );

      expect(
        () => _document(
          suggestions: <FieldSuggestion>[confirmed, rejected],
          fields: <ConfirmedField>[machine],
        ),
        returnsNormally,
      );
      expect(
        () => _content(
          suggestions: <FieldSuggestion>[confirmed, rejected],
          fields: <ConfirmedField>[machine],
        ),
        returnsNormally,
      );
    });

    test(
      'rejects a confirmed suggestion without exactly one machine field',
      () {
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

        final ConfirmedField first = _machineField(
          sourceSuggestionId: confirmed.id,
          order: 0,
        );
        final ConfirmedField second = _machineField(
          sourceSuggestionId: confirmed.id,
          order: 1,
        );
        expect(
          () => _document(
            suggestions: <FieldSuggestion>[confirmed],
            fields: <ConfirmedField>[first, second],
          ),
          throwsArgumentError,
        );
        expect(
          () => _content(
            suggestions: <FieldSuggestion>[confirmed],
            fields: <ConfirmedField>[first, second],
          ),
          throwsArgumentError,
        );
      },
    );

    test('rejects a machine field without a confirmed suggestion', () {
      final ConfirmedField field = _machineField(
        sourceSuggestionId: 's_p0_0001',
      );
      expect(
        () => _document(fields: <ConfirmedField>[field]),
        throwsArgumentError,
      );
      expect(
        () => _content(fields: <ConfirmedField>[field]),
        throwsArgumentError,
      );
    });

    test('rejects a machine field whose confidence does not match', () {
      final ({FieldSuggestion suggestion, ConfirmedField field}) pair =
          _confirmedPair(fieldConfidence: 0.81);
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
    });

    test('rejects a machine field that references an unresolved or rejected '
        'suggestion', () {
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
    });

    test('rejects a duplicate flag without a matching machine field', () {
      final FieldSuggestion duplicate = _suggestion(duplicateOfConfirmed: true);
      expect(
        () => _document(suggestions: <FieldSuggestion>[duplicate]),
        throwsArgumentError,
      );
      expect(
        () => _content(suggestions: <FieldSuggestion>[duplicate]),
        throwsArgumentError,
      );

      final ({FieldSuggestion suggestion, ConfirmedField field}) pair =
          _confirmedPair();
      final FieldSuggestion farAway = _suggestion(
        ordinal: 2,
        rect: _rect(left: 500, top: 700, width: 20, height: 20),
        duplicateOfConfirmed: true,
      );
      expect(
        () => _document(
          suggestions: <FieldSuggestion>[pair.suggestion, farAway],
          fields: <ConfirmedField>[pair.field],
        ),
        throwsArgumentError,
      );
      expect(
        () => _content(
          suggestions: <FieldSuggestion>[pair.suggestion, farAway],
          fields: <ConfirmedField>[pair.field],
        ),
        throwsArgumentError,
      );
    });

    test('rejects a cross-page machine-field reference', () {
      expect(
        () => ConfirmedField(
          id: _uuid(20),
          pageIndex: 1,
          rect: _rect(),
          type: FieldType.text,
          provenance: Provenance.machine,
          sourceSuggestionId: 's_p0_0001',
          suggestionConfidence: 0.82,
          label: 'Feld',
          order: 0,
          createdAt: _at(),
          updatedAt: _at(1),
        ),
        throwsArgumentError,
      );
    });

    test('invariant errors never echo labels, ids, or content', () {
      final FieldSuggestion confirmed = _suggestion(
        resolution: SuggestionResolution.confirmed,
        labelText: 'Streng-Geheim',
      );
      final ConfirmedField machine = _machineField(
        sourceSuggestionId: 's_p0_0999',
        label: 'Geheim-Feld',
      );

      for (final String message in <String>[
        _messageOf(() => _document(suggestions: <FieldSuggestion>[confirmed])),
        _messageOf(() => _content(suggestions: <FieldSuggestion>[confirmed])),
        _messageOf(() => _document(fields: <ConfirmedField>[machine])),
        _messageOf(() => _content(fields: <ConfirmedField>[machine])),
      ]) {
        expect(message, isNot(contains('Streng-Geheim')));
        expect(message, isNot(contains('Geheim-Feld')));
        expect(message, isNot(contains('s_p0')));
        expect(message, isNot(contains('Name')));
        expect(message, isNot(contains('/')));
      }
    });
  });

  group('revision persistence round-trips', () {
    test('a revision with a confirmed suggestion and machine field reloads '
        'unchanged', () {
      final ({FieldSuggestion suggestion, ConfirmedField field}) pair =
          _confirmedPair();
      final Revision revision = _revision(
        _content(
          suggestions: <FieldSuggestion>[pair.suggestion],
          fields: <ConfirmedField>[pair.field],
        ),
      );

      final Map<String, Object?> json = _jsonRoundTrip(revision.toJson());
      final Revision parsed = Revision.fromJson(json);

      expect(parsed, revision);
      expect(
        parsed.content.suggestions.single.resolution,
        SuggestionResolution.confirmed,
      );
      expect(parsed.content.suggestions.single.duplicateOfConfirmed, isFalse);
      expect(parsed.content.fields.single.provenance, Provenance.machine);
      expect(
        parsed.content.fields.single.sourceSuggestionId,
        pair.suggestion.id,
      );
      expect(parsed.content.fields.single.suggestionConfidence, 0.82);

      final Map<String, Object?> contentJson =
          json['content']! as Map<String, Object?>;
      final Map<String, Object?> suggestionJson =
          (contentJson['suggestions']! as List<Object?>).single
              as Map<String, Object?>;
      final Map<String, Object?> fieldJson =
          (contentJson['fields']! as List<Object?>).single
              as Map<String, Object?>;
      expect(suggestionJson['resolution'], 'confirmed');
      expect(suggestionJson.containsKey('duplicateOfConfirmed'), isFalse);
      expect(fieldJson['provenance'], 'machine');
      expect(fieldJson['sourceSuggestionId'], pair.suggestion.id);
      expect(fieldJson['suggestionConfidence'], 0.82);
    });

    test('a revision with rejected and unresolved suggestions without machine '
        'fields reloads unchanged', () {
      final FieldSuggestion rejected = _suggestion(
        resolution: SuggestionResolution.rejected,
      );
      final FieldSuggestion unresolved = _suggestion(ordinal: 2);
      final Revision revision = _revision(
        _content(suggestions: <FieldSuggestion>[unresolved, rejected]),
      );

      final Revision parsed = Revision.fromJson(
        _jsonRoundTrip(revision.toJson()),
      );

      expect(parsed, revision);
      expect(parsed.content.fields, isEmpty);
      expect(
        <String, SuggestionResolution>{
          for (final FieldSuggestion suggestion in parsed.content.suggestions)
            suggestion.id: suggestion.resolution,
        },
        <String, SuggestionResolution>{
          rejected.id: SuggestionResolution.rejected,
          unresolved.id: SuggestionResolution.unresolved,
        },
      );
    });

    test('a document round-trips the duplicate flag, resolution, and '
        'provenance', () {
      final ({List<FieldSuggestion> suggestions, List<ConfirmedField> fields})
      set = _duplicateSet();
      final Document document = _document(
        suggestions: set.suggestions,
        fields: set.fields,
      );

      final Document parsed = Document.fromJson(
        _jsonRoundTrip(document.toJson()),
      );

      expect(parsed, document);
      expect(
        parsed.suggestions.first.resolution,
        SuggestionResolution.confirmed,
      );
      expect(parsed.suggestions.last.duplicateOfConfirmed, isTrue);
      expect(
        parsed.suggestions.last.resolution,
        SuggestionResolution.unresolved,
      );
      expect(parsed.fields.single.provenance, Provenance.machine);
    });

    test('unknown fields survive a document round-trip with the flag', () {
      final Rect base = _rect(left: 50, top: 60, width: 100, height: 100);
      final FieldSuggestion confirmed = _suggestion(
        rect: base,
        resolution: SuggestionResolution.confirmed,
      );
      final ConfirmedField machine = _machineField(
        sourceSuggestionId: confirmed.id,
        rect: base,
      );
      final FieldSuggestion duplicate = _suggestion(
        ordinal: 2,
        rect: _rect(left: 60, top: 60, width: 80, height: 100),
        duplicateOfConfirmed: true,
        unknownFields: <String, Object?>{
          'x_future': <String, Object?>{'v': 2},
        },
      );
      final Document document = _document(
        suggestions: <FieldSuggestion>[confirmed, duplicate],
        fields: <ConfirmedField>[machine],
      );

      final Document parsed = Document.fromJson(
        _jsonRoundTrip(document.toJson()),
      );

      expect(parsed.suggestions.last.duplicateOfConfirmed, isTrue);
      expect(
        parsed.suggestions.last.unknownFields['x_future'],
        <String, Object?>{'v': 2},
      );
    });
  });
}
