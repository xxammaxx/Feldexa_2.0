// T020 persistence value-object tests.
//
// These are host-VM tests (evidence class NONE). They pin `data-model.md`
// §2.5, §3.12, and §3.13 and `contracts/storage-format.md` §2.4/§3.1:
//   * `DurabilityStatus` states, payload validation, and the honesty rule;
//   * `RevisionKind` wire tokens shared with the T017 `DurablePointer`;
//   * `RevisionContent` snapshot composition, invariants, canonical JSON,
//     source-byte exclusion, and unknown-field preservation;
//   * `Revision` identity, timestamp/hash validation, round-trips, and the
//     verified durable-pointer mapping.

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

Page _page({
  int index = 0,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return Page(
    index: index,
    geometry: _geometry(),
    unknownFields: unknownFields,
  );
}

FieldSuggestion _suggestion({
  int pageIndex = 0,
  int ordinal = 1,
  Rect? rect,
  List<String> conflictsWith = const <String>[],
  Map<String, Object?> unknownFields = const <String, Object?>{},
  Map<String, Object?> evidenceUnknownFields = const <String, Object?>{},
}) {
  return FieldSuggestion(
    id: FieldSuggestion.idFor(pageIndex: pageIndex, ordinal: ordinal),
    pageIndex: pageIndex,
    rect: rect ?? _rect(),
    proposedType: FieldType.text,
    confidence: 0.82,
    labelText: 'Name',
    evidence: SuggestionEvidence(
      cues: const <SuggestionCue>[SuggestionCue.line],
      unknownFields: evidenceUnknownFields,
    ),
    conflictsWith: conflictsWith,
    unknownFields: unknownFields,
  );
}

ConfirmedField _field({
  String? id,
  int pageIndex = 0,
  Rect? rect,
  FieldType type = FieldType.text,
  String label = 'Name',
  int order = 0,
  FieldValidation validation = FieldValidation.ok,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return ConfirmedField(
    id: id ?? _uuid(20 + order),
    pageIndex: pageIndex,
    rect: rect ?? _rect(),
    type: type,
    provenance: Provenance.user,
    label: label,
    order: order,
    createdAt: _at(),
    updatedAt: _at(),
    validation: validation,
    unknownFields: unknownFields,
  );
}

TemplateOrigin _origin({Map<String, Object?> unknownFields = const {}}) {
  return TemplateOrigin(
    templateId: _uuid(40),
    templateVersionId: _uuid(41),
    templateVersionNumber: 2,
    unknownFields: unknownFields,
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

RevisionContent _minimalContent({
  Iterable<Page>? pages,
  Iterable<FieldSuggestion> suggestions = const <FieldSuggestion>[],
  Iterable<ConfirmedField> fields = const <ConfirmedField>[],
  Iterable<String>? fieldOrder,
  Map<String, FieldValue> values = const <String, FieldValue>{},
  Map<String, SignatureMark> signatures = const <String, SignatureMark>{},
  Map<String, FieldVerification> verification =
      const <String, FieldVerification>{},
  TemplateOrigin? templateOrigin,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return RevisionContent(
    pages: pages ?? <Page>[_page()],
    suggestions: suggestions,
    fields: fields,
    fieldOrder: fieldOrder ?? const <String>[],
    values: values,
    signatures: signatures,
    verification: verification,
    templateOrigin: templateOrigin,
    unknownFields: unknownFields,
  );
}

RevisionContent _richContent({
  Map<String, Object?> unknownFields = const <String, Object?>{},
  Map<String, Object?> fieldUnknownFields = const <String, Object?>{},
  Map<String, Object?> validationUnknownFields = const <String, Object?>{},
  Map<String, Object?> valueUnknownFields = const <String, Object?>{},
  Map<String, Object?> signatureUnknownFields = const <String, Object?>{},
  Map<String, Object?> verificationUnknownFields = const <String, Object?>{},
  Map<String, Object?> pageUnknownFields = const <String, Object?>{},
  Map<String, Object?> suggestionUnknownFields = const <String, Object?>{},
  Map<String, Object?> evidenceUnknownFields = const <String, Object?>{},
  Map<String, Object?> originUnknownFields = const <String, Object?>{},
}) {
  final ConfirmedField text = _field(
    id: _uuid(20),
    order: 0,
    validation: FieldValidation.warning(
      WarningCode.overflow,
      'field.overflow',
      unknownFields: validationUnknownFields,
    ),
    unknownFields: fieldUnknownFields,
  );
  final ConfirmedField signature = _field(
    id: _uuid(21),
    order: 1,
    type: FieldType.signature,
    label: 'Unterschrift',
  );
  final String asset = _uuid(30);
  final SignatureMark mark = SignatureMark(
    assetId: asset,
    fieldId: signature.id,
    pageIndex: 0,
    rect: _rect(width: 100, height: 40),
    widthPx: 100,
    heightPx: 40,
    capturedAt: _at(),
    sha256: _sha256,
    unknownFields: signatureUnknownFields,
  );
  return RevisionContent(
    pages: <Page>[_page(unknownFields: pageUnknownFields)],
    suggestions: <FieldSuggestion>[
      _suggestion(
        unknownFields: suggestionUnknownFields,
        evidenceUnknownFields: evidenceUnknownFields,
      ),
    ],
    fields: <ConfirmedField>[text, signature],
    fieldOrder: <String>[text.id, signature.id],
    values: <String, FieldValue>{
      text.id: TextValue(
        text: 'Max Mustermann',
        lastEditedAt: _at(),
        unknownFields: valueUnknownFields,
      ),
      signature.id: SignatureValue(
        signatureAssetId: asset,
        lastEditedAt: _at(),
      ),
    },
    signatures: <String, SignatureMark>{signature.id: mark},
    verification: <String, FieldVerification>{
      text.id: FieldVerification(
        state: FieldVerificationState.confirmed,
        reviewedAt: _at(2),
        unknownFields: verificationUnknownFields,
      ),
    },
    templateOrigin: _origin(unknownFields: originUnknownFields),
    unknownFields: unknownFields,
  );
}

Document _document() {
  final ConfirmedField text = _field(id: _uuid(20), order: 0);
  final ConfirmedField signature = _field(
    id: _uuid(21),
    order: 1,
    type: FieldType.signature,
    label: 'Unterschrift',
  );
  final String asset = _uuid(30);
  return Document(
    id: _uuid(1),
    title: 'Formular',
    createdAt: _at(),
    updatedAt: _at(),
    source: _source(),
    pages: <Page>[_page()],
    suggestions: <FieldSuggestion>[_suggestion()],
    fields: <ConfirmedField>[text, signature],
    fieldOrder: <String>[text.id, signature.id],
    values: <String, FieldValue>{
      text.id: TextValue(text: 'Max Mustermann', lastEditedAt: _at()),
      signature.id: SignatureValue(
        signatureAssetId: asset,
        lastEditedAt: _at(),
      ),
    },
    signatures: <String, SignatureMark>{
      signature.id: SignatureMark(
        assetId: asset,
        fieldId: signature.id,
        pageIndex: 0,
        rect: _rect(width: 100, height: 40),
        widthPx: 100,
        heightPx: 40,
        capturedAt: _at(),
        sha256: _sha256,
      ),
    },
    verification: <String, FieldVerification>{
      text.id: FieldVerification(
        state: FieldVerificationState.confirmed,
        reviewedAt: _at(2),
      ),
    },
    templateOrigin: _origin(),
    lastDurable: _pointer(),
    preferences: DocumentPreferences(zoom: 1.5),
    status: DocumentStatus.saved,
  );
}

Revision _revision({
  String? id,
  String? documentId,
  String? parentRevisionId,
  RevisionKind kind = RevisionKind.autosave,
  DateTime? createdAt,
  String? plaintextSha256,
  RevisionContent? content,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return Revision(
    id: id ?? _uuid(50),
    documentId: documentId ?? _uuid(1),
    parentRevisionId: parentRevisionId,
    kind: kind,
    createdAt: createdAt ?? _at(),
    plaintextSha256: plaintextSha256 ?? _sha256,
    content: content ?? _minimalContent(),
    unknownFields: unknownFields,
  );
}

Map<String, Object?> _decoded(Map<String, Object?> json) {
  return jsonDecode(canonicalJsonEncode(json)) as Map<String, Object?>;
}

void main() {
  group('DurabilityStatus', () {
    test('clean is durable and has the canonical token', () {
      const DurabilityStatus status = DurabilityStatus.clean;
      expect(status.wireName, 'clean');
      expect(status.isDurable, isTrue);
      expect(status, DurabilityStatus.clean);
      expect(status, isA<CleanDurabilityStatus>());
    });

    test('saving is not durable', () {
      const DurabilityStatus status = DurabilityStatus.saving;
      expect(status.wireName, 'saving');
      expect(status.isDurable, isFalse);
    });

    test('unsaved is not durable and keeps the risk semantics', () {
      const DurabilityStatus status = DurabilityStatus.unsaved;
      expect(status.wireName, 'unsaved');
      expect(status.isDurable, isFalse);
    });

    test('saved carries a UTC timestamp and is durable', () {
      final DurabilityStatus status = DurabilityStatus.saved(
        lastDurableAt: _at(5),
      );
      expect(status, isA<SavedDurabilityStatus>());
      expect((status as SavedDurabilityStatus).lastDurableAt, _at(5));
      expect(status.wireName, 'saved');
      expect(status.isDurable, isTrue);
      expect(status.toString(), contains('2026-11-14T12:05:00.000Z'));
    });

    test('saved rejects a local timestamp', () {
      expect(
        () => DurabilityStatus.saved(lastDurableAt: DateTime(2026, 11, 14, 12)),
        throwsArgumentError,
      );
    });

    test('saveFailed carries a catalog code and is not durable', () {
      final DurabilityStatus status = DurabilityStatus.saveFailed('SAVE-003');
      expect(status, isA<SaveFailedDurabilityStatus>());
      expect((status as SaveFailedDurabilityStatus).errorCode, 'SAVE-003');
      expect(status.wireName, 'saveFailed');
      expect(status.isDurable, isFalse);
      expect(status.toString(), contains('SAVE-003'));
    });

    test('saveFailed rejects a sentence or malformed code', () {
      for (final String code in <String>[
        '',
        'save-003',
        'SAVE_003',
        'Speichern fehlgeschlagen',
        'SAVE-03',
        'TOO-LONG-CODE-003',
      ]) {
        expect(
          () => DurabilityStatus.saveFailed(code),
          throwsArgumentError,
          reason: code,
        );
      }
    });

    test('recoveryFallback carries a revision id and is not durable', () {
      final DurabilityStatus status = DurabilityStatus.recoveryFallback(
        _uuid(77),
      );
      expect(status, isA<RecoveryFallbackDurabilityStatus>());
      expect(
        (status as RecoveryFallbackDurabilityStatus).revisionId,
        _uuid(77),
      );
      expect(status.wireName, 'recoveryFallback');
      expect(status.isDurable, isFalse);
    });

    test('recoveryFallback rejects a non-UUID revision id', () {
      expect(
        () => DurabilityStatus.recoveryFallback('latest'),
        throwsArgumentError,
      );
    });

    test('only clean and saved may be presented as durable', () {
      final List<DurabilityStatus> statuses = <DurabilityStatus>[
        DurabilityStatus.clean,
        DurabilityStatus.saving,
        DurabilityStatus.unsaved,
        DurabilityStatus.saved(lastDurableAt: _at()),
        DurabilityStatus.saveFailed('SAVE-004'),
        DurabilityStatus.recoveryFallback(_uuid(77)),
      ];
      expect(
        statuses.where((DurabilityStatus status) => status.isDurable),
        <DurabilityStatus>[DurabilityStatus.clean, statuses[3]],
      );
    });

    test('states use value equality', () {
      expect(
        DurabilityStatus.saved(lastDurableAt: _at()),
        DurabilityStatus.saved(lastDurableAt: _at()),
      );
      expect(
        DurabilityStatus.saveFailed('SAVE-003'),
        DurabilityStatus.saveFailed('SAVE-003'),
      );
      expect(
        DurabilityStatus.recoveryFallback(_uuid(77)),
        DurabilityStatus.recoveryFallback(_uuid(77)),
      );
      expect(
        DurabilityStatus.saveFailed('SAVE-003'),
        isNot(DurabilityStatus.saveFailed('SAVE-004')),
      );
    });
  });

  group('RevisionKind', () {
    test('wire tokens match the T017 durable-pointer vocabulary', () {
      expect(RevisionKind.autosave.wireName, DurablePointer.autosaveKind);
      expect(RevisionKind.explicit.wireName, DurablePointer.explicitKind);
      expect(RevisionKind.recovery.wireName, DurablePointer.recoveryKind);
    });

    test('fromWire accepts only the three canonical tokens', () {
      expect(RevisionKind.fromWire('autosave'), RevisionKind.autosave);
      expect(RevisionKind.fromWire('explicit'), RevisionKind.explicit);
      expect(RevisionKind.fromWire('recovery'), RevisionKind.recovery);
      for (final Object? token in <Object?>['AUTOSAVE', 'saved', '', null, 1]) {
        expect(
          () => RevisionKind.fromWire(token),
          throwsFormatException,
          reason: '$token',
        );
      }
    });
  });

  group('RevisionContent construction', () {
    test('minimal snapshot has the eight canonical payload keys', () {
      final RevisionContent content = _minimalContent();
      final Map<String, Object?> json = content.toJson();
      expect(json.keys.toSet(), <String>{
        'pages',
        'suggestions',
        'fields',
        'fieldOrder',
        'values',
        'signatures',
        'verification',
        'templateOrigin',
      });
      expect(json.containsKey('source'), isFalse);
      expect(content.pageCount, 1);
      expect(content.toString(), contains('pages: 1'));
    });

    test('pages must be non-empty', () {
      expect(() => _minimalContent(pages: const <Page>[]), throwsArgumentError);
    });

    test('pages must be ordered contiguously from index 0', () {
      expect(
        () => _minimalContent(pages: <Page>[_page(index: 1)]),
        throwsArgumentError,
      );
      expect(
        () => _minimalContent(pages: <Page>[_page(index: 0), _page(index: 0)]),
        throwsArgumentError,
      );
    });

    test('suggestions are sorted canonically regardless of input order', () {
      final RevisionContent first = _minimalContent(
        suggestions: <FieldSuggestion>[
          _suggestion(ordinal: 3),
          _suggestion(ordinal: 1),
          _suggestion(ordinal: 2),
        ],
      );
      final RevisionContent second = _minimalContent(
        suggestions: <FieldSuggestion>[
          _suggestion(ordinal: 1),
          _suggestion(ordinal: 2),
          _suggestion(ordinal: 3),
        ],
      );
      expect(
        first.suggestions.map((FieldSuggestion value) => value.id),
        <String>['s_p0_0001', 's_p0_0002', 's_p0_0003'],
      );
      expect(first, second);
      expect(
        canonicalJsonEncode(first.toJson()),
        canonicalJsonEncode(second.toJson()),
      );
    });

    test('duplicate suggestion ids are rejected', () {
      expect(
        () => _minimalContent(
          suggestions: <FieldSuggestion>[_suggestion(), _suggestion()],
        ),
        throwsArgumentError,
      );
    });

    test('a suggestion must reference an existing page', () {
      expect(
        () => _minimalContent(
          suggestions: <FieldSuggestion>[_suggestion(pageIndex: 1)],
        ),
        throwsArgumentError,
      );
    });

    test('a suggestion must fit its page display box', () {
      expect(
        () => _minimalContent(
          suggestions: <FieldSuggestion>[
            _suggestion(rect: _rect(left: 900, top: 60)),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('suggestion conflicts must exist and be symmetric', () {
      final FieldSuggestion first = _suggestion(
        ordinal: 1,
        conflictsWith: <String>['s_p0_0002'],
      );
      final FieldSuggestion second = _suggestion(
        ordinal: 2,
        conflictsWith: <String>['s_p0_0001'],
      );
      expect(
        _minimalContent(suggestions: <FieldSuggestion>[second, first])
            .suggestions
            .length,
        2,
      );
      expect(
        () => _minimalContent(
          suggestions: <FieldSuggestion>[first, _suggestion(ordinal: 2)],
        ),
        throwsArgumentError,
      );
      expect(
        () => _minimalContent(
          suggestions: <FieldSuggestion>[
            _suggestion(conflictsWith: <String>['s_p0_0099']),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('duplicate confirmed field ids are rejected', () {
      final ConfirmedField first = _field(id: _uuid(20), order: 0);
      expect(
        () => _minimalContent(
          fields: <ConfirmedField>[first, first],
          fieldOrder: <String>[first.id],
        ),
        throwsArgumentError,
      );
    });

    test('a confirmed field must reference an existing page', () {
      final ConfirmedField field = _field(pageIndex: 1);
      expect(
        () => _minimalContent(
          fields: <ConfirmedField>[field],
          fieldOrder: <String>[field.id],
        ),
        throwsArgumentError,
      );
    });

    test('a confirmed field must fit its page display box', () {
      final ConfirmedField field = _field(rect: _rect(left: 900));
      expect(
        () => _minimalContent(
          fields: <ConfirmedField>[field],
          fieldOrder: <String>[field.id],
        ),
        throwsArgumentError,
      );
    });

    test('fieldOrder must be a complete permutation with matching orders', () {
      final ConfirmedField first = _field(id: _uuid(20), order: 0);
      final ConfirmedField second = _field(id: _uuid(21), order: 1);
      expect(
        _minimalContent(
          fields: <ConfirmedField>[second, first],
          fieldOrder: <String>[first.id, second.id],
        ).fields.map((ConfirmedField value) => value.id),
        <String>[first.id, second.id],
      );
      expect(
        () => _minimalContent(
          fields: <ConfirmedField>[first],
          fieldOrder: const <String>[],
        ),
        throwsArgumentError,
      );
      expect(
        () => _minimalContent(
          fields: <ConfirmedField>[first],
          fieldOrder: <String>[first.id, first.id],
        ),
        throwsArgumentError,
      );
      expect(
        () => _minimalContent(
          fields: <ConfirmedField>[first],
          fieldOrder: <String>[_uuid(99)],
        ),
        throwsArgumentError,
      );
      expect(
        () => _minimalContent(
          fields: <ConfirmedField>[first],
          fieldOrder: <String>[second.id],
        ),
        throwsArgumentError,
      );
    });

    test('field.order must equal its position in fieldOrder', () {
      final ConfirmedField field = _field(id: _uuid(20), order: 2);
      expect(
        () => _minimalContent(
          fields: <ConfirmedField>[field],
          fieldOrder: <String>[field.id],
        ),
        throwsArgumentError,
      );
    });

    test('a value must reference a confirmed field', () {
      expect(
        () => _minimalContent(
          values: <String, FieldValue>{
            _uuid(99): TextValue(text: 'x', lastEditedAt: _at()),
          },
        ),
        throwsArgumentError,
      );
    });

    test('incompatible content and its warning must occur together', () {
      final ConfirmedField plain = _field(id: _uuid(20));
      final ConfirmedField flagged = _field(
        id: _uuid(21),
        order: 0,
        validation: FieldValidation.warning(
          WarningCode.incompatibleContent,
          'field.incompatible_content',
        ),
      );
      final IncompatibleValue preserved = IncompatibleValue(
        preservedText: 'alt',
        reasonCode: 'reclassified',
        lastEditedAt: _at(),
      );
      expect(
        _minimalContent(
          fields: <ConfirmedField>[flagged],
          fieldOrder: <String>[flagged.id],
          values: <String, FieldValue>{flagged.id: preserved},
        ).values.length,
        1,
      );
      expect(
        () => _minimalContent(
          fields: <ConfirmedField>[plain],
          fieldOrder: <String>[plain.id],
          values: <String, FieldValue>{plain.id: preserved},
        ),
        throwsArgumentError,
      );
      expect(
        () => _minimalContent(
          fields: <ConfirmedField>[flagged],
          fieldOrder: <String>[flagged.id],
          values: <String, FieldValue>{
            flagged.id: TextValue(text: 'x', lastEditedAt: _at()),
          },
        ),
        throwsArgumentError,
      );
    });

    test('a signature must reference a signature field on the same page', () {
      final ConfirmedField text = _field(id: _uuid(20), order: 0);
      final SignatureMark mark = SignatureMark(
        assetId: _uuid(30),
        fieldId: text.id,
        pageIndex: 0,
        rect: _rect(width: 100, height: 40),
        widthPx: 100,
        heightPx: 40,
        capturedAt: _at(),
        sha256: _sha256,
      );
      expect(
        () => _minimalContent(
          fields: <ConfirmedField>[text],
          fieldOrder: <String>[text.id],
          signatures: <String, SignatureMark>{text.id: mark},
          values: <String, FieldValue>{
            text.id: SignatureValue(
              signatureAssetId: mark.assetId,
              lastEditedAt: _at(),
            ),
          },
        ),
        throwsArgumentError,
      );
    });

    test('signature asset ids must be unique', () {
      final ConfirmedField first = _field(
        id: _uuid(20),
        order: 0,
        type: FieldType.signature,
      );
      final ConfirmedField second = _field(
        id: _uuid(21),
        order: 1,
        type: FieldType.signature,
      );
      final SignatureMark firstMark = SignatureMark(
        assetId: _uuid(30),
        fieldId: first.id,
        pageIndex: 0,
        rect: _rect(width: 100, height: 40),
        widthPx: 100,
        heightPx: 40,
        capturedAt: _at(),
        sha256: _sha256,
      );
      final SignatureMark secondMark = SignatureMark(
        assetId: _uuid(30),
        fieldId: second.id,
        pageIndex: 0,
        rect: _rect(width: 100, height: 40),
        widthPx: 100,
        heightPx: 40,
        capturedAt: _at(),
        sha256: _sha256,
      );
      expect(
        () => _minimalContent(
          fields: <ConfirmedField>[first, second],
          fieldOrder: <String>[first.id, second.id],
          signatures: <String, SignatureMark>{
            first.id: firstMark,
            second.id: secondMark,
          },
          values: <String, FieldValue>{
            first.id: SignatureValue(
              signatureAssetId: firstMark.assetId,
              lastEditedAt: _at(),
            ),
            second.id: SignatureValue(
              signatureAssetId: secondMark.assetId,
              lastEditedAt: _at(),
            ),
          },
        ),
        throwsArgumentError,
      );
    });

    test('a signature mark requires the matching value', () {
      final ConfirmedField field = _field(
        id: _uuid(20),
        type: FieldType.signature,
      );
      final SignatureMark mark = SignatureMark(
        assetId: _uuid(30),
        fieldId: field.id,
        pageIndex: 0,
        rect: _rect(width: 100, height: 40),
        widthPx: 100,
        heightPx: 40,
        capturedAt: _at(),
        sha256: _sha256,
      );
      expect(
        () => _minimalContent(
          fields: <ConfirmedField>[field],
          fieldOrder: <String>[field.id],
          signatures: <String, SignatureMark>{field.id: mark},
        ),
        throwsArgumentError,
      );
    });

    test('a signature value requires the matching mark', () {
      final ConfirmedField field = _field(
        id: _uuid(20),
        type: FieldType.signature,
      );
      expect(
        () => _minimalContent(
          fields: <ConfirmedField>[field],
          fieldOrder: <String>[field.id],
          values: <String, FieldValue>{
            field.id: SignatureValue(
              signatureAssetId: _uuid(30),
              lastEditedAt: _at(),
            ),
          },
        ),
        throwsArgumentError,
      );
    });

    test('verification must reference a confirmed field', () {
      expect(
        () => _minimalContent(
          verification: <String, FieldVerification>{
            _uuid(99): FieldVerification(
              state: FieldVerificationState.confirmed,
              reviewedAt: _at(),
            ),
          },
        ),
        throwsArgumentError,
      );
    });

    test('a rich snapshot round-trips through canonical JSON', () {
      final RevisionContent content = _richContent();
      final Map<String, Object?> json = _decoded(content.toJson());
      final RevisionContent decoded = RevisionContent.fromJson(json);
      expect(decoded, content);
      expect(
        canonicalJsonEncode(decoded.toJson()),
        canonicalJsonEncode(content.toJson()),
      );
      expect(decoded.pageCount, 1);
      expect(decoded.fields.length, 2);
      expect(decoded.suggestions.single.id, 's_p0_0001');
      expect(decoded.templateOrigin, _origin());
    });

    test('fromDocument copies only snapshot fields', () {
      final Document document = _document();
      final RevisionContent content = RevisionContent.fromDocument(document);
      expect(content.pages, document.pages);
      expect(content.suggestions, document.suggestions);
      expect(content.fields, document.fields);
      expect(content.fieldOrder, document.fieldOrder);
      expect(content.values, document.values);
      expect(content.signatures, document.signatures);
      expect(content.verification, document.verification);
      expect(content.templateOrigin, document.templateOrigin);
      expect(content.toJson().containsKey('source'), isFalse);
      expect(content.toJson().containsKey('title'), isFalse);
      expect(content.toJson().containsKey('lastDurable'), isFalse);
      expect(content.toJson().containsKey('preferences'), isFalse);
    });

    test('source bytes are rejected on read and never emitted', () {
      final Map<String, Object?> json = _minimalContent().toJson();
      json['source'] = <String, Object?>{'id': _uuid(1)};
      expect(
        () => RevisionContent.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('source'),
          ),
        ),
      );
      expect(_minimalContent().toJson().containsKey('source'), isFalse);
    });

    test('missing required payload keys are rejected', () {
      for (final String key in <String>[
        'pages',
        'suggestions',
        'fields',
        'fieldOrder',
        'values',
        'signatures',
        'verification',
      ]) {
        final Map<String, Object?> json = _minimalContent().toJson()
          ..remove(key);
        expect(
          () => RevisionContent.fromJson(json),
          throwsFormatException,
          reason: key,
        );
      }
    });

    test('a missing templateOrigin is accepted as null', () {
      final Map<String, Object?> json = _minimalContent().toJson()
        ..remove('templateOrigin');
      expect(RevisionContent.fromJson(json).templateOrigin, isNull);
    });

    test('mistyped payload sections are rejected', () {
      for (final MapEntry<String, Object?> replacement in <String, Object?>{
        'pages': 'not-an-array',
        'suggestions': <Object?>[1],
        'fields': <String, Object?>{},
        'fieldOrder': <Object?>[1],
        'values': <String, Object?>{'x': 1},
        'signatures': 'not-an-object',
        'verification': <Object?>[],
        'templateOrigin': <String, Object?>{},
      }.entries) {
        final Map<String, Object?> json = _minimalContent().toJson();
        json[replacement.key] = replacement.value;
        expect(
          () => RevisionContent.fromJson(json),
          throwsFormatException,
          reason: replacement.key,
        );
      }
    });
  });

  group('RevisionContent unknown fields', () {
    test('unknown fields survive at every persisted layer', () {
      final RevisionContent content = _richContent(
        unknownFields: <String, Object?>{
          'xRoot': 1,
          'xNested': <String, Object?>{'a': true},
        },
        fieldUnknownFields: <String, Object?>{'xField': 'kept'},
        validationUnknownFields: <String, Object?>{'xValidation': 'kept'},
        valueUnknownFields: <String, Object?>{'xValue': 2},
        signatureUnknownFields: <String, Object?>{'xSignature': 3},
        verificationUnknownFields: <String, Object?>{'xVerification': 4},
        pageUnknownFields: <String, Object?>{'xPage': 5},
        suggestionUnknownFields: <String, Object?>{'xSuggestion': 6},
        evidenceUnknownFields: <String, Object?>{'xEvidence': 7},
        originUnknownFields: <String, Object?>{'xOrigin': 8},
      );
      final Map<String, Object?> json = _decoded(content.toJson());
      final RevisionContent decoded = RevisionContent.fromJson(json);
      expect(
        canonicalJsonEncode(decoded.toJson()),
        canonicalJsonEncode(content.toJson()),
      );
      expect(decoded.unknownFields['xRoot'], 1);
      expect(decoded.pages.single.unknownFields['xPage'], 5);
      expect(decoded.suggestions.single.unknownFields['xSuggestion'], 6);
      expect(decoded.suggestions.single.evidence.unknownFields['xEvidence'], 7);
      expect(decoded.fields.first.unknownFields['xField'], 'kept');
      expect(
        decoded.fields.first.validation.unknownFields['xValidation'],
        'kept',
      );
      expect(decoded.values.values.first.unknownFields['xValue'], 2);
      expect(decoded.signatures.values.single.unknownFields['xSignature'], 3);
      expect(
        decoded.verification.values.single.unknownFields['xVerification'],
        4,
      );
      expect(decoded.templateOrigin!.unknownFields['xOrigin'], 8);
    });

    test('unknown fields are retained in canonical byte order', () {
      final RevisionContent content = _richContent(
        unknownFields: <String, Object?>{'zLast': 1, 'aFirst': 2},
      );
      final String json = canonicalJsonEncode(content.toJson());
      expect(json.indexOf('"aFirst"'), lessThan(json.indexOf('"zLast"')));
      final RevisionContent decoded = RevisionContent.fromJson(
        jsonDecode(json) as Map<String, Object?>,
      );
      expect(canonicalJsonEncode(decoded.toJson()), json);
    });

    test('unknown fields do not participate in equality', () {
      final RevisionContent plain = _minimalContent();
      final RevisionContent extended = _minimalContent(
        unknownFields: <String, Object?>{'xRoot': 1},
      );
      expect(extended, plain);
      expect(extended.hashCode, plain.hashCode);
      expect(extended.toString(), isNot(contains('xRoot')));
    });
  });

  group('Revision', () {
    test('a valid first revision serializes all modeled keys', () {
      final Revision revision = _revision();
      final Map<String, Object?> json = revision.toJson();
      expect(json.keys.toSet(), <String>{
        'id',
        'documentId',
        'parentRevisionId',
        'kind',
        'createdAt',
        'plaintextSha256',
        'content',
      });
      expect(json['parentRevisionId'], isNull);
      expect(json['kind'], 'autosave');
      expect(json['createdAt'], '2026-11-14T12:00:00.000Z');
      expect(json['content'], isA<Map<String, Object?>>());
      expect(revision.content.pageCount, 1);
      expect(revision.toString(), contains('autosave'));
      expect(revision.toString(), isNot(contains('Max Mustermann')));
    });

    test('revision JSON round-trips canonically', () {
      final Revision revision = _revision(
        parentRevisionId: _uuid(49),
        kind: RevisionKind.explicit,
        content: _richContent(),
      );
      final Map<String, Object?> json = _decoded(revision.toJson());
      final Revision decoded = Revision.fromJson(json);
      expect(decoded, revision);
      expect(
        canonicalJsonEncode(decoded.toJson()),
        canonicalJsonEncode(revision.toJson()),
      );
      expect(decoded.kind, RevisionKind.explicit);
      expect(decoded.parentRevisionId, _uuid(49));
    });

    test('all revision kinds round-trip through JSON', () {
      for (final RevisionKind kind in RevisionKind.values) {
        final Revision revision = _revision(kind: kind);
        expect(Revision.fromJson(_decoded(revision.toJson())).kind, kind);
      }
    });

    test('unknown fields survive at the revision and content roots', () {
      final Revision revision = _revision(
        content: _richContent(unknownFields: <String, Object?>{'xContent': 1}),
        unknownFields: <String, Object?>{'xRevision': 2},
      );
      final Map<String, Object?> json = _decoded(revision.toJson());
      final Revision decoded = Revision.fromJson(json);
      expect(decoded.unknownFields['xRevision'], 2);
      expect(decoded.content.unknownFields['xContent'], 1);
      expect(
        canonicalJsonEncode(decoded.toJson()),
        canonicalJsonEncode(revision.toJson()),
      );
    });

    test('revision identity, parent, timestamp, and hash are validated', () {
      expect(() => _revision(id: 'not-a-uuid'), throwsArgumentError);
      expect(() => _revision(documentId: 'not-a-uuid'), throwsArgumentError);
      expect(
        () => _revision(parentRevisionId: 'not-a-uuid'),
        throwsArgumentError,
      );
      expect(
        () => _revision(id: _uuid(50), parentRevisionId: _uuid(50)),
        throwsArgumentError,
      );
      expect(
        () => _revision(createdAt: DateTime(2026, 11, 14, 12)),
        throwsArgumentError,
      );
      for (final String hash in <String>[
        '',
        'ABCDEF',
        'A'.padRight(64, 'A'),
        'a'.padRight(63, 'a'),
        'g'.padRight(64, 'g'),
      ]) {
        expect(
          () => _revision(plaintextSha256: hash),
          throwsArgumentError,
          reason: hash,
        );
      }
    });

    test('fromJson rejects missing and mistyped modeled fields', () {
      final Map<String, Object?> valid = _revision().toJson();
      for (final String key in <String>[
        'id',
        'documentId',
        'kind',
        'createdAt',
        'plaintextSha256',
        'content',
      ]) {
        final Map<String, Object?> json = Map<String, Object?>.from(valid)
          ..remove(key);
        expect(
          () => Revision.fromJson(json),
          throwsFormatException,
          reason: key,
        );
      }
      for (final MapEntry<String, Object?> replacement in <String, Object?>{
        'id': 1,
        'documentId': 1,
        'parentRevisionId': 1,
        'kind': 'AUTOSAVE',
        'createdAt': 'yesterday',
        'plaintextSha256': 1,
        'content': 'not-an-object',
      }.entries) {
        final Map<String, Object?> json = Map<String, Object?>.from(valid)
          ..[replacement.key] = replacement.value;
        expect(
          () => Revision.fromJson(json),
          throwsFormatException,
          reason: replacement.key,
        );
      }
    });

    test('a revision with a clearable parent copies and validates', () {
      final Revision revision = _revision(parentRevisionId: _uuid(49));
      expect(revision.copyWith().parentRevisionId, _uuid(49));
      expect(
        revision.copyWith(parentRevisionId: null).parentRevisionId,
        isNull,
      );
      expect(() => revision.copyWith(id: 'not-a-uuid'), throwsArgumentError);
    });

    test('toDurablePointer maps the verified commit exactly', () {
      final Revision revision = _revision(
        parentRevisionId: _uuid(49),
        kind: RevisionKind.recovery,
      );
      final DurablePointer pointer = revision.toDurablePointer(
        committedAt: _at(7),
      );
      expect(pointer.revisionId, revision.id);
      expect(pointer.parentRevisionId, _uuid(49));
      expect(pointer.kind, DurablePointer.recoveryKind);
      expect(pointer.committedAt, _at(7));
      expect(pointer.sha256, _sha256);
      expect(pointer.toJson()['verifyReadBack'], isTrue);
      expect(
        () =>
            revision.toDurablePointer(committedAt: DateTime(2026, 11, 14, 12)),
        throwsArgumentError,
      );
    });

    test('revision equality and hash include content', () {
      final Revision first = _revision();
      final Revision same = _revision();
      final Revision different = _revision(kind: RevisionKind.explicit);
      expect(first, same);
      expect(first.hashCode, same.hashCode);
      expect(first, isNot(different));
      expect(first.toString(), isNot(contains('content')));
    });
  });
}
