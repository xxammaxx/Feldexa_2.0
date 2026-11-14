// T017 document aggregate tests.
//
// These are host-VM tests (evidence class NONE). They pin `data-model.md`
// §3.1–§3.3, §3.9, §3.13, §4.1, §5, and §6:
//   * `SourceFileRef`, `PageFailure`, `TemplateOrigin`, `DurablePointer`,
//     `Page`, `DocumentPreferences`, `DocumentMeta`, and `Document`;
//   * page, field, value, signature, and verification aggregate invariants;
//   * the status/durable honesty rules and the schema-version guard;
//   * canonical JSON round-trips and the "no content in toString" rule.

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

SourceFileRef _source({
  int pageCount = 1,
  SourceIntegrityState integrity = SourceIntegrityState.verified,
  String? originalName = 'form.pdf',
}) {
  return SourceFileRef(
    id: _uuid(1),
    sha256: _sha256,
    sizeBytes: 1234,
    pageCount: pageCount,
    originalName: originalName,
    importedAt: _at(),
    integrity: integrity,
  );
}

Page _page({
  int index = 0,
  AnalysisState analysis = AnalysisState.pending,
  PageFailure? failure,
  bool unreadable = false,
  String? renderCacheKey,
}) {
  return Page(
    index: index,
    geometry: _geometry(),
    analysis: analysis,
    failure: failure,
    unreadable: unreadable,
    renderCacheKey: renderCacheKey,
  );
}

DurablePointer _pointer({
  String? revisionId,
  String? parentRevisionId,
  String kind = DurablePointer.autosaveKind,
  DateTime? committedAt,
  String? sha256,
}) {
  return DurablePointer(
    revisionId: revisionId ?? _uuid(90),
    parentRevisionId: parentRevisionId,
    kind: kind,
    committedAt: committedAt ?? _at(1),
    sha256: sha256 ?? _sha256,
  );
}

FieldSuggestion _suggestion({
  int pageIndex = 0,
  int ordinal = 1,
  Rect? rect,
  FieldType proposedType = FieldType.text,
  double confidence = 0.82,
  String? labelText = 'Name',
  List<String> conflictsWith = const <String>[],
  SuggestionResolution resolution = SuggestionResolution.unresolved,
}) {
  return FieldSuggestion(
    id: FieldSuggestion.idFor(pageIndex: pageIndex, ordinal: ordinal),
    pageIndex: pageIndex,
    rect: rect ?? _rect(),
    proposedType: proposedType,
    confidence: confidence,
    labelText: labelText,
    evidence: SuggestionEvidence(
      cues: const <SuggestionCue>[SuggestionCue.line],
    ),
    conflictsWith: conflictsWith,
    resolution: resolution,
  );
}

ConfirmedField _field({
  String? id,
  int pageIndex = 0,
  Rect? rect,
  FieldType type = FieldType.text,
  Provenance provenance = Provenance.user,
  String? sourceSuggestionId,
  double? suggestionConfidence,
  String label = 'Name',
  int order = 0,
  FieldValidation validation = FieldValidation.ok,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return ConfirmedField(
    id: id ?? _uuid(20 + order),
    pageIndex: pageIndex,
    rect: rect ?? _rect(),
    type: type,
    provenance: provenance,
    sourceSuggestionId: sourceSuggestionId,
    suggestionConfidence: suggestionConfidence,
    label: label,
    order: order,
    createdAt: createdAt ?? _at(),
    updatedAt: updatedAt ?? _at(),
    validation: validation,
  );
}

Document _document({
  String title = 'Antrag',
  SourceFileRef? source,
  List<Page>? pages,
  List<FieldSuggestion> suggestions = const <FieldSuggestion>[],
  List<ConfirmedField> fields = const <ConfirmedField>[],
  List<String>? fieldOrder,
  Map<String, FieldValue> values = const <String, FieldValue>{},
  Map<String, SignatureMark> signatures = const <String, SignatureMark>{},
  Map<String, FieldVerification> verification =
      const <String, FieldVerification>{},
  TemplateOrigin? templateOrigin,
  DurablePointer? lastDurable,
  DocumentPreferences? preferences,
  DocumentStatus? status,
  int schemaVersion = documentSchemaVersion,
}) {
  final SourceFileRef checkedSource = source ?? _source();
  return Document(
    schemaVersion: schemaVersion,
    id: _uuid(2),
    title: title,
    createdAt: _at(),
    updatedAt: _at(1),
    source: checkedSource,
    pages:
        pages ??
        <Page>[
          for (int index = 0; index < checkedSource.pageCount; index++)
            _page(index: index),
        ],
    suggestions: suggestions,
    fields: fields,
    fieldOrder:
        fieldOrder ??
        <String>[for (final ConfirmedField field in fields) field.id],
    values: values,
    signatures: signatures,
    verification: verification,
    templateOrigin: templateOrigin,
    lastDurable: lastDurable ?? _pointer(),
    preferences: preferences,
    status: status,
  );
}

Map<String, Object?> _jsonRoundTrip(Map<String, Object?> json) {
  return jsonDecode(jsonEncode(json)) as Map<String, Object?>;
}

Document _richDocument() {
  final SourceFileRef source = _source(pageCount: 2);
  final ConfirmedField name = _field(id: _uuid(20), order: 0);
  final ConfirmedField consent = _field(
    id: _uuid(21),
    order: 1,
    type: FieldType.checkbox,
    label: 'Zustimmung',
  );
  return _document(
    source: source,
    suggestions: <FieldSuggestion>[_suggestion(pageIndex: 0)],
    fields: <ConfirmedField>[name, consent],
    fieldOrder: <String>[name.id, consent.id],
    values: <String, FieldValue>{
      name.id: TextValue(text: 'Erika Mustermann', lastEditedAt: _at(2)),
      consent.id: CheckboxValue(checked: true, lastEditedAt: _at(3)),
    },
    verification: <String, FieldVerification>{
      name.id: FieldVerification(
        state: FieldVerificationState.confirmed,
        reviewedAt: _at(4),
      ),
    },
    templateOrigin: TemplateOrigin(
      templateId: _uuid(40),
      templateVersionId: _uuid(41),
      templateVersionNumber: 2,
    ),
    preferences: DocumentPreferences(
      zoom: 1.75,
      currentPage: 1,
      reviewOrderMode: ReviewOrderMode.pageOrder,
    ),
    status: DocumentStatus.saved,
  );
}

void _expectCanonical(Object? value) {
  if (value is Map<String, Object?>) {
    final List<String> keys = value.keys.toList(growable: false);
    final List<String> sorted = <String>[...keys]..sort();
    expect(keys, sorted);
    for (final Object? item in value.values) {
      _expectCanonical(item);
    }
    return;
  }
  if (value is List<Object?>) {
    for (final Object? item in value) {
      _expectCanonical(item);
    }
  }
}

void main() {
  group('SourceFileRef', () {
    test('accepts the source bounds and round-trips JSON', () {
      final SourceFileRef ref = SourceFileRef(
        id: _uuid(1),
        sha256: _sha256,
        sizeBytes: maxSourceSizeBytes,
        pageCount: maxSourcePageCount,
        originalName: '  Antrag.pdf  ',
        importedAt: _at(),
        integrity: SourceIntegrityState.unreadable,
      );

      expect(ref.originalName, 'Antrag.pdf');
      expect(ref.sizeBytes, 83886080);
      expect(ref.pageCount, 100);
      expect(SourceFileRef.fromJson(_jsonRoundTrip(ref.toJson())), ref);
      expect(ref.toString(), isNot(contains('Antrag')));
    });

    test('normalizes a blank name to null and copyWith can clear it', () {
      final SourceFileRef ref = _source(originalName: '   ');
      expect(ref.originalName, isNull);
      final SourceFileRef renamed = ref.copyWith(originalName: 'a.pdf');
      expect(renamed.originalName, 'a.pdf');
      expect(renamed.copyWith(originalName: null).originalName, isNull);
    });

    test('rejects out-of-range size, page count, ids, and names', () {
      expect(
        () => SourceFileRef(
          id: _uuid(1),
          sha256: _sha256,
          sizeBytes: 0,
          pageCount: 1,
          importedAt: _at(),
        ),
        throwsArgumentError,
      );
      expect(
        () => SourceFileRef(
          id: _uuid(1),
          sha256: _sha256,
          sizeBytes: maxSourceSizeBytes + 1,
          pageCount: 1,
          importedAt: _at(),
        ),
        throwsArgumentError,
      );
      expect(
        () => SourceFileRef(
          id: _uuid(1),
          sha256: _sha256,
          sizeBytes: 1,
          pageCount: 0,
          importedAt: _at(),
        ),
        throwsArgumentError,
      );
      expect(
        () => SourceFileRef(
          id: 'not-a-uuid',
          sha256: _sha256,
          sizeBytes: 1,
          pageCount: 1,
          importedAt: _at(),
        ),
        throwsArgumentError,
      );
      expect(
        () => SourceFileRef(
          id: _uuid(1),
          sha256: 'abc',
          sizeBytes: 1,
          pageCount: 1,
          importedAt: _at(),
        ),
        throwsArgumentError,
      );
      expect(() => _source(originalName: 'a\nb.pdf'), throwsArgumentError);
      expect(() => _source(originalName: 'x' * 256), throwsArgumentError);
    });

    test('rejects local import timestamps and malformed JSON', () {
      expect(
        () => SourceFileRef(
          id: _uuid(1),
          sha256: _sha256,
          sizeBytes: 1,
          pageCount: 1,
          importedAt: DateTime(2026, 11, 14),
        ),
        throwsArgumentError,
      );
      expect(
        () => SourceFileRef.fromJson(<String, Object?>{'id': _uuid(1)}),
        throwsFormatException,
      );
      expect(
        () => SourceFileRef.fromJson(<String, Object?>{
          'id': _uuid(1),
          'sha256': _sha256,
          'sizeBytes': '1',
          'pageCount': 1,
          'originalName': null,
          'importedAt': '2026-11-14T12:00:00.000Z',
          'integrity': 'verified',
        }),
        throwsFormatException,
      );
    });
  });

  group('PageFailure', () {
    test('uses exactly the three core categories', () {
      expect(PageFailureCategory.values.length, 3);
      expect(
        PageFailureCategory.fromWire('unsupported_structure'),
        PageFailureCategory.unsupportedStructure,
      );
      expect(() => PageFailureCategory.fromWire('ocr'), throwsFormatException);
      expect(() => PageFailureCategory.fromWire(1), throwsFormatException);
    });

    test('round-trips and validates the catalog message key', () {
      final PageFailure failure = PageFailure(
        pageIndex: 2,
        category: PageFailureCategory.rasterization,
        messageKey: 'IMP-006',
      );
      expect(PageFailure.fromJson(_jsonRoundTrip(failure.toJson())), failure);
      expect(
        () => PageFailure(
          pageIndex: -1,
          category: PageFailureCategory.unreadable,
          messageKey: 'REC-002',
        ),
        throwsArgumentError,
      );
      expect(
        () => PageFailure(
          pageIndex: 0,
          category: PageFailureCategory.unreadable,
          messageKey: 'unsupported',
        ),
        throwsArgumentError,
      );
    });

    test('copyWith revalidates', () {
      final PageFailure failure = PageFailure(
        pageIndex: 0,
        category: PageFailureCategory.unreadable,
        messageKey: 'REC-003',
      );
      expect(failure.copyWith(pageIndex: 1).pageIndex, 1);
      expect(() => failure.copyWith(pageIndex: -1), throwsArgumentError);
    });
  });

  group('TemplateOrigin', () {
    test('round-trips the immutable version pin', () {
      final TemplateOrigin origin = TemplateOrigin(
        templateId: _uuid(40),
        templateVersionId: _uuid(41),
        templateVersionNumber: 7,
      );
      expect(TemplateOrigin.fromJson(_jsonRoundTrip(origin.toJson())), origin);
      expect(origin.templateVersionNumber, 7);
    });

    test('rejects malformed ids and non-positive version numbers', () {
      expect(
        () => TemplateOrigin(
          templateId: 'bad',
          templateVersionId: _uuid(41),
          templateVersionNumber: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => TemplateOrigin(
          templateId: _uuid(40),
          templateVersionId: _uuid(41),
          templateVersionNumber: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => TemplateOrigin.fromJson(<String, Object?>{
          'templateId': _uuid(40),
          'templateVersionId': _uuid(41),
          'templateVersionNumber': '1',
        }),
        throwsFormatException,
      );
    });
  });

  group('DurablePointer', () {
    test('round-trips a verified pointer and its explicit parent', () {
      final DurablePointer pointer = _pointer(
        parentRevisionId: _uuid(89),
        kind: DurablePointer.explicitKind,
      );
      final Map<String, Object?> json = _jsonRoundTrip(pointer.toJson());
      expect(json['verifyReadBack'], isTrue);
      expect(DurablePointer.fromJson(json), pointer);
      expect(pointer.toString(), isNot(contains(_sha256)));
    });

    test('requires verifyReadBack to be true in the constructor and JSON', () {
      expect(() => _pointerWith(verifyReadBack: false), throwsArgumentError);
      final Map<String, Object?> json = _pointer().toJson();
      json['verifyReadBack'] = false;
      expect(() => DurablePointer.fromJson(json), throwsFormatException);
      json.remove('verifyReadBack');
      expect(() => DurablePointer.fromJson(json), throwsFormatException);
    });

    test('validates kind, parent, timestamp, and hash', () {
      expect(() => _pointerWith(kind: 'manual'), throwsArgumentError);
      expect(
        () => _pointerWith(parentRevisionId: _uuid(90)),
        throwsArgumentError,
      );
      expect(
        () => _pointerWith(committedAt: DateTime(2026, 11, 14)),
        throwsArgumentError,
      );
      expect(() => _pointerWith(sha256: 'xyz'), throwsArgumentError);
    });

    test('copyWith can clear the parent and keeps read-back verification', () {
      final DurablePointer pointer = _pointer(parentRevisionId: _uuid(89));
      final DurablePointer first = pointer.copyWith(parentRevisionId: null);
      expect(first.parentRevisionId, isNull);
      expect(first.toJson()['verifyReadBack'], isTrue);
      expect(DurablePointer.fromJson(_jsonRoundTrip(first.toJson())), first);
    });
  });

  group('Page and AnalysisState', () {
    test('uses the four analysis tokens', () {
      expect(AnalysisState.fromWire('failed'), AnalysisState.failed);
      expect(() => AnalysisState.fromWire('cancelled'), throwsFormatException);
    });

    test('requires a matching failure exactly for the failed state', () {
      final PageFailure failure = PageFailure(
        pageIndex: 1,
        category: PageFailureCategory.unsupportedStructure,
        messageKey: 'REC-003',
      );
      final Page failed = _page(
        index: 1,
        analysis: AnalysisState.failed,
        failure: failure,
      );
      expect(Page.fromJson(_jsonRoundTrip(failed.toJson())), failed);
      expect(
        () => _page(index: 0, analysis: AnalysisState.failed),
        throwsArgumentError,
      );
      expect(() => _page(index: 0, failure: failure), throwsArgumentError);
      expect(
        () => _page(index: 0, analysis: AnalysisState.failed, failure: failure),
        throwsArgumentError,
      );
    });

    test('keeps renderCacheKey derived, unpersisted, and out of equality', () {
      final Page cached = _page(renderCacheKey: 'page-0-v1');
      final Page plain = _page();
      expect(cached, plain);
      expect(cached.toJson().containsKey('renderCacheKey'), isFalse);
      expect(
        _page().copyWith(renderCacheKey: 'page-0-v1').renderCacheKey,
        'page-0-v1',
      );
      expect(cached.copyWith(renderCacheKey: null).renderCacheKey, isNull);
      expect(() => _page(renderCacheKey: 'has space'), throwsArgumentError);
    });

    test('a retry copy clears the failure and keeps other fields', () {
      final Page failed = _page(
        analysis: AnalysisState.failed,
        failure: PageFailure(
          pageIndex: 0,
          category: PageFailureCategory.rasterization,
          messageKey: 'REC-002',
        ),
        unreadable: true,
      );
      final Page retried = failed.copyWith(
        analysis: AnalysisState.running,
        failure: null,
      );
      expect(retried.analysis, AnalysisState.running);
      expect(retried.failure, isNull);
      expect(retried.unreadable, isTrue);
    });
  });

  group('DocumentPreferences', () {
    test('defaults to no zoom preference and document order', () {
      final DocumentPreferences preferences = DocumentPreferences();
      expect(preferences.zoom, isNull);
      expect(preferences.currentPage, 0);
      expect(preferences.reviewOrderMode, ReviewOrderMode.documentOrder);
    });

    test('accepts the zoom-ratio bounds and round-trips JSON', () {
      final DocumentPreferences preferences = DocumentPreferences(
        zoom: 8,
        currentPage: 2,
        reviewOrderMode: ReviewOrderMode.pageOrder,
      );
      expect(
        DocumentPreferences.fromJson(_jsonRoundTrip(preferences.toJson())),
        preferences,
      );
      expect(DocumentPreferences(zoom: 0.5).zoom, 0.5);
    });

    test('rejects invalid zoom values, pages, and review modes', () {
      expect(() => DocumentPreferences(zoom: 0.49), throwsArgumentError);
      expect(() => DocumentPreferences(zoom: 8.01), throwsArgumentError);
      expect(() => DocumentPreferences(zoom: double.nan), throwsArgumentError);
      expect(() => DocumentPreferences(currentPage: -1), throwsArgumentError);
      expect(
        () => ReviewOrderMode.fromWire('reading_order'),
        throwsFormatException,
      );
    });

    test('copyWith can clear the zoom preference', () {
      final DocumentPreferences preferences = DocumentPreferences(zoom: 1.5);
      expect(preferences.copyWith(zoom: null).zoom, isNull);
      expect(preferences.copyWith(currentPage: 3).currentPage, 3);
    });
  });

  group('DocumentMeta', () {
    test('round-trips the persisted metadata envelope', () {
      final DocumentMeta meta = DocumentMeta(
        id: _uuid(2),
        title: '  Antrag  ',
        createdAt: _at(),
        updatedAt: _at(1),
        source: _source(),
        latestRevisionId: _uuid(90),
        lastDurableAt: _at(1),
      );

      expect(meta.title, 'Antrag');
      expect(meta.kind, 'document');
      expect(DocumentMeta.fromJson(_jsonRoundTrip(meta.toJson())), meta);
      expect(meta.toJson().containsKey('pages'), isFalse);
      expect(meta.toString(), isNot(contains('Antrag')));
    });

    test('ties readable and unreadableReasonCode together', () {
      final DocumentMeta unreadable = DocumentMeta(
        id: _uuid(2),
        title: 'Antrag',
        createdAt: _at(),
        updatedAt: _at(1),
        source: _source(),
        readable: false,
        unreadableReasonCode: 'SAVE-002',
      );
      expect(
        DocumentMeta.fromJson(_jsonRoundTrip(unreadable.toJson())),
        unreadable,
      );
      final DocumentMeta unexplained = DocumentMeta(
        id: _uuid(2),
        title: 'Antrag',
        createdAt: _at(),
        updatedAt: _at(1),
        source: _source(),
        readable: false,
      );
      expect(unexplained.unreadableReasonCode, isNull);
      expect(
        DocumentMeta.fromJson(_jsonRoundTrip(unexplained.toJson())),
        unexplained,
      );
      expect(
        () => DocumentMeta(
          id: _uuid(2),
          title: 'Antrag',
          createdAt: _at(),
          updatedAt: _at(1),
          source: _source(),
          unreadableReasonCode: 'SAVE-002',
        ),
        throwsArgumentError,
      );
      expect(
        () => DocumentMeta(
          id: _uuid(2),
          title: 'Antrag',
          createdAt: _at(),
          updatedAt: _at(1),
          source: _source(),
          readable: false,
          unreadableReasonCode: 'not-a-code',
        ),
        throwsArgumentError,
      );
    });

    test('accepts independent revision pointers and rejects local time', () {
      final DocumentMeta revisionOnly = DocumentMeta(
        id: _uuid(2),
        title: 'Antrag',
        createdAt: _at(),
        updatedAt: _at(1),
        source: _source(),
        latestRevisionId: _uuid(90),
      );
      expect(revisionOnly.lastDurableAt, isNull);
      expect(
        DocumentMeta.fromJson(_jsonRoundTrip(revisionOnly.toJson())),
        revisionOnly,
      );

      final DocumentMeta dateOnly = DocumentMeta(
        id: _uuid(2),
        title: 'Antrag',
        createdAt: _at(),
        updatedAt: _at(1),
        source: _source(),
        lastDurableAt: _at(1),
      );
      expect(dateOnly.latestRevisionId, isNull);
      expect(
        DocumentMeta.fromJson(_jsonRoundTrip(dateOnly.toJson())),
        dateOnly,
      );

      expect(
        () => DocumentMeta(
          id: _uuid(2),
          title: 'Antrag',
          createdAt: DateTime(2026, 11, 14),
          updatedAt: _at(1),
          source: _source(),
        ),
        throwsArgumentError,
      );
    });

    test('validates title, ids, and JSON discriminators', () {
      expect(
        () => DocumentMeta(
          id: 'bad',
          title: 'Antrag',
          createdAt: _at(),
          updatedAt: _at(1),
          source: _source(),
        ),
        throwsArgumentError,
      );
      expect(
        () => DocumentMeta(
          id: _uuid(2),
          title: '  ',
          createdAt: _at(),
          updatedAt: _at(1),
          source: _source(),
        ),
        throwsArgumentError,
      );
      expect(
        () => DocumentMeta(
          id: _uuid(2),
          title: 'x' * 201,
          createdAt: _at(),
          updatedAt: _at(1),
          source: _source(),
        ),
        throwsArgumentError,
      );
      expect(
        () => DocumentMeta.fromJson(<String, Object?>{
          ..._minimalMetaJson(),
          'kind': 'template',
        }),
        throwsFormatException,
      );
    });
  });

  group('Document canonical JSON', () {
    test('round-trips the full aggregate and canonicalizes its JSON', () {
      final Document document = _richDocument();
      final Document decoded = Document.fromJson(
        _jsonRoundTrip(document.toJson()),
      );

      expect(decoded, document);
      final String canonical = canonicalJsonEncode(document.toJson());
      expect(canonical, canonicalJsonEncode(decoded.toJson()));
      expect(canonicalJsonBytes(document.toJson()), utf8.encode(canonical));
      expect(canonical.contains('\n'), isFalse);

      final Map<String, Object?> tree =
          jsonDecode(canonical) as Map<String, Object?>;
      _expectCanonical(tree);
      expect(tree['schemaVersion'], documentSchemaVersion);
      expect(tree['kind'], 'document');
      expect(tree.containsKey('status'), isFalse);
      expect(tree['fieldOrder'], <String>[_uuid(20), _uuid(21)]);
      expect(document.toString(), isNot(contains('Erika')));
      expect(document.toString(), isNot(contains('Antrag')));
    });

    test('restores the safe derived status and never persists status', () {
      expect(_document().status, DocumentStatus.draft);
      final Document draft = _document(status: DocumentStatus.draft);
      expect(draft.status, DocumentStatus.draft);
      expect(draft.toJson().containsKey('status'), isFalse);
      expect(
        Document.fromJson(_jsonRoundTrip(draft.toJson())).status,
        DocumentStatus.saved,
      );
    });

    test('derives and enforces the unreadable status', () {
      final SourceFileRef source = _source(
        integrity: SourceIntegrityState.unreadable,
      );
      expect(_document(source: source).status, DocumentStatus.unreadable);
      expect(
        () => _document(source: source, status: DocumentStatus.saved),
        throwsArgumentError,
      );
      expect(
        () => _document(status: DocumentStatus.unreadable),
        throwsArgumentError,
      );
      expect(
        () => _document(status: DocumentStatus.deleted),
        throwsArgumentError,
      );
      expect(
        Document.fromJson(_jsonRoundTrip(_document(source: source).toJson()))
            .status,
        DocumentStatus.unreadable,
      );
    });

    test('rejects a higher schema version without touching the data', () {
      final Map<String, Object?> json = _richDocument().toJson();
      json['schemaVersion'] = 2;
      expect(() => Document.fromJson(json), throwsFormatException);
      expect(() => _document(schemaVersion: 2), throwsArgumentError);
    });

    test('rejects wrong discriminators and mistyped containers', () {
      final Map<String, Object?> json = _richDocument().toJson();
      json['kind'] = 'template';
      expect(() => Document.fromJson(json), throwsFormatException);

      final Map<String, Object?> missingPages = _richDocument().toJson()
        ..remove('pages');
      expect(() => Document.fromJson(missingPages), throwsFormatException);

      final Map<String, Object?> badPages = _richDocument().toJson();
      badPages['pages'] = 'not-an-array';
      expect(() => Document.fromJson(badPages), throwsFormatException);

      final Map<String, Object?> localTimestamp = _richDocument().toJson();
      localTimestamp['createdAt'] = '2026-11-14T12:00:00';
      expect(() => Document.fromJson(localTimestamp), throwsFormatException);
    });
  });

  group('Document aggregate validation', () {
    test('requires one contiguous page per preflight page', () {
      expect(
        () => _document(
          source: _source(pageCount: 2),
          pages: <Page>[_page(index: 0)],
        ),
        throwsArgumentError,
      );
      expect(
        () => _document(
          source: _source(pageCount: 2),
          pages: <Page>[_page(index: 1), _page(index: 0)],
        ),
        throwsArgumentError,
      );
      expect(
        () => _document(
          source: _source(pageCount: 2),
          pages: <Page>[_page(index: 0), _page(index: 0)],
        ),
        throwsArgumentError,
      );
    });

    test('validates suggestion pages, bounds, ids, and conflicts', () {
      expect(
        () => _document(
          source: _source(),
          suggestions: <FieldSuggestion>[_suggestion(pageIndex: 1)],
        ),
        throwsArgumentError,
      );
      expect(
        () => _document(
          source: _source(),
          suggestions: <FieldSuggestion>[
            _suggestion(rect: Rect.fromLTWH(500, 10, 100, 20)),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => _document(
          source: _source(),
          suggestions: <FieldSuggestion>[
            _suggestion(conflictsWith: <String>['s_p0_0002']),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => _document(
          source: _source(),
          suggestions: <FieldSuggestion>[
            _suggestion(ordinal: 1, conflictsWith: <String>['s_p0_0002']),
            _suggestion(ordinal: 2),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('keeps suggestions in canonical page and ordinal order', () {
      final Document document = _document(
        source: _source(),
        suggestions: <FieldSuggestion>[
          _suggestion(ordinal: 2),
          _suggestion(ordinal: 1),
        ],
      );
      expect(
        document.suggestions.map((FieldSuggestion item) => item.id).toList(),
        <String>['s_p0_0001', 's_p0_0002'],
      );
    });

    test('accepts symmetric conflicts and round-trips both candidates', () {
      final Document document = _document(
        source: _source(),
        suggestions: <FieldSuggestion>[
          _suggestion(ordinal: 2, conflictsWith: <String>['s_p0_0001']),
          _suggestion(ordinal: 1, conflictsWith: <String>['s_p0_0002']),
        ],
        status: DocumentStatus.saved,
      );
      expect(document.suggestions.length, 2);
      expect(Document.fromJson(_jsonRoundTrip(document.toJson())), document);
    });

    test('validates field ids, pages, bounds, and fieldOrder', () {
      final ConfirmedField field = _field(order: 0);
      expect(() => _document(fields: <ConfirmedField>[field]), returnsNormally);
      expect(
        () =>
            _document(fields: <ConfirmedField>[field], fieldOrder: <String>[]),
        throwsArgumentError,
      );
      expect(
        () => _document(
          fields: <ConfirmedField>[field],
          fieldOrder: <String>[_uuid(99)],
        ),
        throwsArgumentError,
      );
      expect(
        () => _document(
          fields: <ConfirmedField>[field],
          fieldOrder: <String>[field.id, field.id],
        ),
        throwsArgumentError,
      );
      expect(
        () => _document(fields: <ConfirmedField>[_field(order: 1)]),
        throwsArgumentError,
      );
      expect(
        () => _document(
          fields: <ConfirmedField>[
            _field(id: _uuid(20), order: 0),
            _field(id: _uuid(20), order: 1),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => _document(
          fields: <ConfirmedField>[
            _field(rect: Rect.fromLTWH(600, 10, 20, 20)),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => _document(
          source: _source(),
          fields: <ConfirmedField>[_field(pageIndex: 1)],
        ),
        throwsArgumentError,
      );
    });

    test('orders fields by fieldOrder and validates order values', () {
      final ConfirmedField first = _field(id: _uuid(20), order: 1);
      final ConfirmedField second = _field(id: _uuid(21), order: 0);
      final Document document = _document(
        fields: <ConfirmedField>[first, second],
        fieldOrder: <String>[second.id, first.id],
      );
      expect(
        document.fields.map((ConfirmedField item) => item.id).toList(),
        <String>[second.id, first.id],
      );
    });

    test('validates values against fields and reclassification warnings', () {
      final ConfirmedField field = _field(order: 0);
      expect(
        () => _document(
          fields: <ConfirmedField>[field],
          values: <String, FieldValue>{
            _uuid(99): TextValue(text: 'x', lastEditedAt: _at()),
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => _document(
          fields: <ConfirmedField>[_field(order: 0, type: FieldType.checkbox)],
          values: <String, FieldValue>{
            _uuid(20): TextValue(text: 'x', lastEditedAt: _at()),
          },
        ),
        throwsArgumentError,
      );

      final IncompatibleValue preserved = IncompatibleValue(
        preservedText: '12.13.2020',
        reasonCode: 'incompatible_type',
        lastEditedAt: _at(),
      );
      expect(
        () => _document(
          fields: <ConfirmedField>[field],
          values: <String, FieldValue>{field.id: preserved},
        ),
        throwsArgumentError,
      );
      expect(
        () => _document(
          fields: <ConfirmedField>[
            _field(
              order: 0,
              validation: FieldValidation.warning(
                WarningCode.incompatibleContent,
                'FLD-001',
              ),
            ),
          ],
          values: <String, FieldValue>{
            _uuid(20): TextValue(text: 'x', lastEditedAt: _at()),
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => _document(
          fields: <ConfirmedField>[
            _field(
              order: 0,
              validation: FieldValidation.warning(
                WarningCode.incompatibleContent,
                'FLD-001',
              ),
            ),
          ],
          values: <String, FieldValue>{_uuid(20): preserved},
        ),
        returnsNormally,
      );
    });

    test('validates verification references and currentPage', () {
      final ConfirmedField field = _field(order: 0);
      expect(
        () => _document(
          fields: <ConfirmedField>[field],
          verification: <String, FieldVerification>{
            _uuid(99): FieldVerification(
              state: FieldVerificationState.confirmed,
              reviewedAt: _at(),
            ),
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => _document(preferences: DocumentPreferences(currentPage: 1)),
        throwsArgumentError,
      );
      expect(
        () => _document(
          fields: <ConfirmedField>[field],
          verification: <String, FieldVerification>{
            field.id: FieldVerification(
              state: FieldVerificationState.confirmed,
              reviewedAt: _at(),
            ),
          },
          preferences: DocumentPreferences(currentPage: 0, zoom: 1),
        ),
        returnsNormally,
      );
    });

    test('normalizes the title and rejects empty, control, or long titles', () {
      expect(_document(title: '  Antrag  ').title, 'Antrag');
      expect(() => _document(title: '   '), throwsArgumentError);
      expect(() => _document(title: 'Ant\nrag'), throwsArgumentError);
      expect(() => _document(title: 'x' * 201), throwsArgumentError);
    });
  });

  group('Signature invariants', () {
    Document signatureDocument({
      String assetId = '',
      String valueAssetId = '',
      bool includeMark = true,
      bool includeValue = true,
      FieldType fieldType = FieldType.signature,
    }) {
      final String asset = assetId.isEmpty ? _uuid(30) : assetId;
      final String valueAsset = valueAssetId.isEmpty ? _uuid(30) : valueAssetId;
      final ConfirmedField field = _field(
        id: _uuid(20),
        type: fieldType,
        order: 0,
      );
      final SignatureMark mark = SignatureMark(
        assetId: asset,
        fieldId: field.id,
        pageIndex: 0,
        rect: _rect(width: 100, height: 40),
        widthPx: 100,
        heightPx: 40,
        capturedAt: _at(),
        sha256: _sha256,
      );
      return _document(
        fields: <ConfirmedField>[field],
        fieldOrder: <String>[field.id],
        values: includeValue
            ? <String, FieldValue>{
                field.id: SignatureValue(
                  signatureAssetId: valueAsset,
                  lastEditedAt: _at(),
                ),
              }
            : const <String, FieldValue>{},
        signatures: includeMark
            ? <String, SignatureMark>{field.id: mark}
            : const <String, SignatureMark>{},
        status: DocumentStatus.saved,
      );
    }

    test('round-trips a signature field with its mark and value', () {
      final Document document = signatureDocument();
      expect(Document.fromJson(_jsonRoundTrip(document.toJson())), document);
      expect(document.signatures.length, 1);
    });

    test('requires the mark and value to exist together with one asset', () {
      expect(() => signatureDocument(includeMark: false), throwsArgumentError);
      expect(() => signatureDocument(includeValue: false), throwsArgumentError);
      expect(
        () => signatureDocument(valueAssetId: _uuid(31)),
        throwsArgumentError,
      );
    });

    test('rejects marks on non-signature fields', () {
      expect(
        () => signatureDocument(fieldType: FieldType.text),
        throwsArgumentError,
      );
    });

    test('rejects duplicate signature asset ids in the document', () {
      final ConfirmedField first = _field(
        id: _uuid(20),
        type: FieldType.signature,
        order: 0,
      );
      final ConfirmedField second = _field(
        id: _uuid(21),
        type: FieldType.signature,
        order: 1,
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
        () => _document(
          fields: <ConfirmedField>[first, second],
          fieldOrder: <String>[first.id, second.id],
          values: <String, FieldValue>{
            first.id: SignatureValue(
              signatureAssetId: _uuid(30),
              lastEditedAt: _at(),
            ),
            second.id: SignatureValue(
              signatureAssetId: _uuid(30),
              lastEditedAt: _at(),
            ),
          },
          signatures: <String, SignatureMark>{
            first.id: firstMark,
            second.id: secondMark,
          },
        ),
        throwsArgumentError,
      );
    });
  });

  group('privacy', () {
    test('toString never echoes titles, labels, values, or filenames', () {
      final SourceFileRef source = _source(originalName: 'streng-geheim.pdf');
      final ConfirmedField field = _field(order: 0, label: 'Geheimfeld');
      final Document document = _document(
        title: 'Geheimes Dokument',
        source: source,
        fields: <ConfirmedField>[field],
        fieldOrder: <String>[field.id],
        values: <String, FieldValue>{
          field.id: TextValue(text: 'streng geheim', lastEditedAt: _at()),
        },
      );

      expect(source.toString(), isNot(contains('streng-geheim')));
      expect(document.toString(), isNot(contains('Geheimes Dokument')));
      expect(document.toString(), isNot(contains('Geheimfeld')));
      expect(document.toString(), isNot(contains('streng geheim')));
    });

    test('validation errors never echo the rejected content', () {
      expect(
        () => _document(title: 'Geheim${'x' * 200}'),
        throwsA(
          predicate<Object>(
            (Object error) => !error.toString().contains('Geheim'),
          ),
        ),
      );
    });
  });
}

DurablePointer _pointerWith({
  String? parentRevisionId,
  String kind = DurablePointer.autosaveKind,
  DateTime? committedAt,
  String? sha256,
  bool verifyReadBack = true,
}) {
  return DurablePointer(
    revisionId: _uuid(90),
    parentRevisionId: parentRevisionId,
    kind: kind,
    committedAt: committedAt ?? _at(1),
    sha256: sha256 ?? _sha256,
    verifyReadBack: verifyReadBack,
  );
}

Map<String, Object?> _minimalMetaJson() {
  return <String, Object?>{
    'id': _uuid(2),
    'kind': 'document',
    'title': 'Antrag',
    'createdAt': '2026-11-14T12:00:00.000Z',
    'updatedAt': '2026-11-14T12:01:00.000Z',
    'source': _source().toJson(),
    'latestRevisionId': null,
    'lastDurableAt': null,
    'readable': true,
    'unreadableReasonCode': null,
  };
}
