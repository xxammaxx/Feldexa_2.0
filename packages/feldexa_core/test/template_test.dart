// T021 template model tests.
//
// These are host-VM tests (evidence class NONE). They pin `spec.md`
// FR-101–FR-106, `data-model.md` §3.10–§3.11 and §4.1, and
// `contracts/storage-format.md` §2.4/§3.3:
//   * `TemplateVersionPointer`, `TemplateVersion`, and `Template` identity,
//     ordering, and validation;
//   * `TemplateMeta` as the `meta.fx1` envelope and `TemplateVersionContent` as
//     the `ver/<versionId>.fx1` payload, including schema-version refusal;
//   * the envelope boundary: the v1 `TemplateMeta` has no mandatory
//     `schemaVersion`, while an explicit marker must be 1 and a newer one is
//     refused;
//   * forbidden template payloads: `values`, `signatures`, `suggestions`, and
//     `templateOrigin` are refused at the root and in every modeled nested
//     object (pages, fields, snapshots, source, pointers, page geometry/boxes/
//     failure, field rectangle/validation) instead of being retained
//     (FR-057/FR-102/SC-013);
//   * `StoredTemplate` as the verified join of both persisted objects;
//   * layout-only templates (no value, signature, or template-origin member);
//   * immutable versions: an existing version is never rewritten (FR-103) and
//     derived-document pins are not part of the template (FR-104);
//   * latest-version selection (FR-105) as a model invariant;
//   * canonical JSON and same-schema unknown-field retention at every level
//     (`data-model.md` §6), including deep freezing of extension data.

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

PageGeometry _geometry({int rotation = 0}) {
  return PageGeometry(
    mediaBox: Rect.fromLTWH(0, 0, 595, 842),
    rotation: rotation,
  );
}

Page _page({
  int index = 0,
  int rotation = 0,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return Page(
    index: index,
    geometry: _geometry(rotation: rotation),
    unknownFields: unknownFields,
  );
}

List<Page> _pages() {
  return <Page>[_page(index: 0), _page(index: 1)];
}

SourceFileRef _source({
  int pageCount = 2,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return SourceFileRef(
    id: _uuid(1),
    sha256: _sha256,
    sizeBytes: 2048,
    pageCount: pageCount,
    originalName: 'antrag.pdf',
    importedAt: _at(),
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
  Provenance provenance = Provenance.user,
  String? sourceSuggestionId,
  double? suggestionConfidence,
  DateTime? createdAt,
  Map<String, Object?> unknownFields = const <String, Object?>{},
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
    updatedAt: createdAt ?? _at(),
    unknownFields: unknownFields,
  );
}

List<ConfirmedField> _fields() {
  return <ConfirmedField>[
    _field(order: 0, label: 'Name'),
    _field(order: 1, type: FieldType.signature, label: 'Unterschrift'),
  ];
}

TemplateVersionPointer _pointer({
  String? versionId,
  int number = 2,
  DateTime? createdAt,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return TemplateVersionPointer(
    versionId: versionId ?? _uuid(41 + number),
    versionNumber: number,
    createdAt: createdAt ?? _at(number),
    unknownFields: unknownFields,
  );
}

List<TemplateVersionPointer> _versions() {
  return <TemplateVersionPointer>[_pointer(number: 2), _pointer(number: 1)];
}

TemplateVersionContent _content({
  Iterable<Page>? pages,
  Iterable<ConfirmedField>? fields,
  Iterable<String>? fieldOrder,
  int schemaVersion = templateSchemaVersion,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  final List<ConfirmedField> fieldList = (fields ?? _fields()).toList(
    growable: false,
  );
  return TemplateVersionContent(
    pageSnapshot: pages ?? _pages(),
    fieldSnapshot: fieldList,
    fieldOrder:
        fieldOrder ??
        <String>[for (final ConfirmedField field in fieldList) field.id],
    schemaVersion: schemaVersion,
    unknownFields: unknownFields,
  );
}

TemplateVersion _version({
  String? id,
  String? templateId,
  int versionNumber = 2,
  DateTime? createdAt,
  Iterable<ConfirmedField>? fieldSnapshot,
  Iterable<Page>? pageSnapshot,
  String? sha256,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return TemplateVersion(
    id: id ?? _uuid(43),
    templateId: templateId ?? _uuid(40),
    versionNumber: versionNumber,
    createdAt: createdAt ?? _at(2),
    fieldSnapshot: fieldSnapshot ?? _fields(),
    pageSnapshot: pageSnapshot ?? _pages(),
    sha256: sha256 ?? _sha256,
    unknownFields: unknownFields,
  );
}

TemplateMeta _meta({
  String? id,
  String? title,
  DateTime? createdAt,
  DateTime? updatedAt,
  SourceFileRef? source,
  TemplateVersionPointer? latestVersion,
  Iterable<TemplateVersionPointer>? versions,
  bool readable = true,
  String? unreadableReasonCode,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  final List<TemplateVersionPointer> versionList = (versions ?? _versions())
      .toList(growable: false);
  return TemplateMeta(
    id: id ?? _uuid(40),
    title: title ?? 'Antrag',
    createdAt: createdAt ?? _at(),
    updatedAt: updatedAt ?? _at(2),
    source: source ?? _source(),
    latestVersion:
        latestVersion ?? (versionList.isEmpty ? _pointer() : versionList.first),
    versions: versionList,
    readable: readable,
    unreadableReasonCode: unreadableReasonCode,
    unknownFields: unknownFields,
  );
}

Template _template({
  String? id,
  String? title,
  DateTime? createdAt,
  DateTime? updatedAt,
  SourceFileRef? source,
  Iterable<Page>? pages,
  Iterable<ConfirmedField>? fields,
  Iterable<String>? fieldOrder,
  TemplateVersionPointer? latestVersion,
  Iterable<TemplateVersionPointer>? versions,
  int schemaVersion = templateSchemaVersion,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  final List<Page> pageList = (pages ?? _pages()).toList(growable: false);
  final List<ConfirmedField> fieldList = (fields ?? _fields()).toList(
    growable: false,
  );
  final List<TemplateVersionPointer> versionList = (versions ?? _versions())
      .toList(growable: false);
  return Template(
    id: id ?? _uuid(40),
    title: title ?? 'Antrag',
    createdAt: createdAt ?? _at(),
    updatedAt: updatedAt ?? _at(2),
    source: source ?? _source(pageCount: pageList.length),
    pages: pageList,
    fields: fieldList,
    fieldOrder:
        fieldOrder ??
        <String>[for (final ConfirmedField field in fieldList) field.id],
    latestVersion:
        latestVersion ?? (versionList.isEmpty ? _pointer() : versionList.first),
    versions: versionList,
    schemaVersion: schemaVersion,
    unknownFields: unknownFields,
  );
}

StoredTemplate _stored({
  TemplateMeta? meta,
  TemplateVersion? version,
  TemplateVersionContent? content,
}) {
  return StoredTemplate(
    meta: meta ?? _meta(),
    version: version ?? _version(),
    content: content ?? _content(),
  );
}

Map<String, Object?> _roundTrip(Map<String, Object?> json) {
  return jsonDecode(canonicalJsonEncode(json)) as Map<String, Object?>;
}

Map<String, Object?> _map(Object? value) {
  return Map<String, Object?>.from(value! as Map<String, Object?>);
}

List<Object?> _list(Object? value) {
  return List<Object?>.from(value! as List<Object?>);
}

void main() {
  group('TemplateVersionPointer', () {
    test('accepts a valid pointer and serializes the canonical timestamp', () {
      final TemplateVersionPointer pointer = _pointer();

      expect(pointer.versionId, _uuid(43));
      expect(pointer.versionNumber, 2);
      expect(pointer.createdAt, _at(2));
      expect(pointer.toJson(), <String, Object?>{
        'versionId': _uuid(43),
        'versionNumber': 2,
        'createdAt': '2026-11-14T12:02:00.000Z',
      });
    });

    test('rejects an invalid identity, number, or timestamp', () {
      expect(() => _pointer(versionId: 'not-a-uuid'), throwsArgumentError);
      expect(
        () => _pointer(versionId: '00000000-0000-4000-8000-00000000004A'),
        throwsArgumentError,
      );
      expect(() => _pointer(number: 0), throwsArgumentError);
      expect(
        () => _pointer(createdAt: DateTime(2026, 11, 14, 12)),
        throwsArgumentError,
      );
    });

    test('copyWith revalidates', () {
      expect(() => _pointer().copyWith(versionNumber: 0), throwsArgumentError);
      expect(_pointer().copyWith(versionNumber: 5).versionNumber, 5);
    });

    test('fromJson rejects missing or mistyped modeled fields', () {
      final Map<String, Object?> json = _pointer().toJson();
      json.remove('createdAt');
      expect(
        () => TemplateVersionPointer.fromJson(json),
        throwsFormatException,
      );
      expect(
        () => TemplateVersionPointer.fromJson(<String, Object?>{
          ..._pointer().toJson(),
          'versionNumber': '2',
        }),
        throwsFormatException,
      );
    });

    test('preserves unknown same-schema fields across a round-trip', () {
      final Map<String, Object?> json = <String, Object?>{
        ..._pointer().toJson(),
        'futurePointer': <String, Object?>{'kind': 'pointer'},
      };

      final TemplateVersionPointer pointer = TemplateVersionPointer.fromJson(
        json,
      );

      expect(pointer.unknownFields.keys, <String>['futurePointer']);
      expect(canonicalJsonEncode(pointer.toJson()), canonicalJsonEncode(json));
      expect(pointer, _pointer());
      expect(pointer.hashCode, _pointer().hashCode);
    });

    test('toString never echoes extension data', () {
      final TemplateVersionPointer pointer = _pointer(
        unknownFields: <String, Object?>{'secret': 'streng geheim'},
      );

      expect(pointer.toString(), isNot(contains('streng geheim')));
    });
  });

  group('TemplateVersionContent', () {
    test('serializes exactly the ver/<versionId>.fx1 payload', () {
      final TemplateVersionContent content = _content();
      final Map<String, Object?> json = content.toJson();

      expect(json.keys.toSet(), <String>{
        'schemaVersion',
        'pageSnapshot',
        'fieldSnapshot',
        'fieldOrder',
      });
      expect(json['schemaVersion'], templateSchemaVersion);
      expect(_list(json['pageSnapshot']), hasLength(2));
      expect(_list(json['fieldSnapshot']), hasLength(2));
      expect(json['fieldOrder'], <String>[_uuid(20), _uuid(21)]);
    });

    test('has no value, signature, suggestion, or origin member', () {
      final Map<String, Object?> json = _content().toJson();

      for (final String forbidden in <String>[
        'values',
        'signatures',
        'suggestions',
        'verification',
        'templateOrigin',
      ]) {
        expect(json.containsKey(forbidden), isFalse, reason: forbidden);
      }
      expect(canonicalJsonEncode(json), isNot(contains('"values"')));
      expect(canonicalJsonEncode(json), isNot(contains('"signatures"')));
    });

    test('orders fields by fieldOrder and keeps them unpacked', () {
      final ConfirmedField name = _field(order: 0, label: 'Name');
      final ConfirmedField signature = _field(
        order: 1,
        type: FieldType.signature,
        label: 'Unterschrift',
      );
      final TemplateVersionContent content = _content(
        fields: <ConfirmedField>[signature, name],
        fieldOrder: <String>[name.id, signature.id],
      );

      expect(
        content.fieldSnapshot.map((ConfirmedField field) => field.id).toList(),
        <String>[name.id, signature.id],
      );
    });

    test('rejects an unsupported schema version', () {
      expect(() => _content(schemaVersion: 2), throwsArgumentError);
      final Map<String, Object?> json = <String, Object?>{
        ..._content().toJson(),
        'schemaVersion': 2,
      };
      expect(
        () => TemplateVersionContent.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects a missing, null, or mistyped schemaVersion', () {
      final Map<String, Object?> missing = _content().toJson();
      missing.remove('schemaVersion');
      expect(
        () => TemplateVersionContent.fromJson(missing),
        throwsFormatException,
      );
      expect(
        () => TemplateVersionContent.fromJson(<String, Object?>{
          ..._content().toJson(),
          'schemaVersion': null,
        }),
        throwsFormatException,
      );
      expect(
        () => TemplateVersionContent.fromJson(<String, Object?>{
          ..._content().toJson(),
          'schemaVersion': '1',
        }),
        throwsFormatException,
      );
    });

    test(
      'refuses forbidden payloads at the root and in page/field objects',
      () {
        final Map<String, Object?> root = _content().toJson();
        for (final String key in <String>[
          'values',
          'signatures',
          'suggestions',
          'templateOrigin',
        ]) {
          expect(
            () => TemplateVersionContent.fromJson(<String, Object?>{
              ...root,
              key: <String, Object?>{},
            }),
            throwsFormatException,
            reason: key,
          );
        }
        final Map<String, Object?> field = _map(
          _list(root['fieldSnapshot'])[0],
        );
        expect(
          () => TemplateVersionContent.fromJson(<String, Object?>{
            ...root,
            'fieldSnapshot': <Object?>[
              <String, Object?>{...field, 'signatures': <String, Object?>{}},
            ],
          }),
          throwsFormatException,
        );
        final Map<String, Object?> page = _map(_list(root['pageSnapshot'])[0]);
        expect(
          () => TemplateVersionContent.fromJson(<String, Object?>{
            ...root,
            'pageSnapshot': <Object?>[
              <String, Object?>{...page, 'values': <String, Object?>{}},
            ],
          }),
          throwsFormatException,
        );
      },
    );

    test('refuses forbidden payloads in deeply modeled objects', () {
      final Map<String, Object?> root = _content().toJson();
      final Map<String, Object?> field = _map(_list(root['fieldSnapshot'])[0]);
      final Map<String, Object?> validation = _map(field['validation']);
      expect(
        () => TemplateVersionContent.fromJson(<String, Object?>{
          ...root,
          'fieldSnapshot': <Object?>[
            <String, Object?>{
              ...field,
              'validation': <String, Object?>{
                ...validation,
                'values': <String, Object?>{},
              },
            },
          ],
        }),
        throwsFormatException,
      );
      final Map<String, Object?> rect = _map(field['rect']);
      expect(
        () => TemplateVersionContent.fromJson(<String, Object?>{
          ...root,
          'fieldSnapshot': <Object?>[
            <String, Object?>{
              ...field,
              'rect': <String, Object?>{
                ...rect,
                'signatures': <String, Object?>{},
              },
            },
          ],
        }),
        throwsFormatException,
      );
      final Map<String, Object?> page = _map(_list(root['pageSnapshot'])[0]);
      final Map<String, Object?> geometry = _map(page['geometry']);
      final Map<String, Object?> mediaBox = _map(geometry['mediaBox']);
      expect(
        () => TemplateVersionContent.fromJson(<String, Object?>{
          ...root,
          'pageSnapshot': <Object?>[
            <String, Object?>{
              ...page,
              'geometry': <String, Object?>{
                ...geometry,
                'mediaBox': <String, Object?>{
                  ...mediaBox,
                  'values': <String, Object?>{},
                },
              },
            },
          ],
        }),
        throwsFormatException,
      );
    });

    test('rejects an empty or non-contiguous page snapshot', () {
      expect(() => _content(pages: const <Page>[]), throwsArgumentError);
      expect(
        () => _content(pages: <Page>[_page(index: 1)]),
        throwsArgumentError,
      );
      expect(
        () => _content(pages: <Page>[_page(index: 0), _page(index: 2)]),
        throwsArgumentError,
      );
    });

    test('rejects a field that does not belong to the snapshot', () {
      expect(
        () => _content(
          pages: <Page>[_page(index: 0)],
          fields: <ConfirmedField>[_field(order: 0, pageIndex: 1)],
          fieldOrder: <String>[_uuid(20)],
        ),
        throwsArgumentError,
      );
      expect(
        () => _content(
          fields: <ConfirmedField>[_field(order: 0, rect: _rect(left: 600))],
          fieldOrder: <String>[_uuid(20)],
        ),
        throwsArgumentError,
      );
    });

    test('rejects a field order that is not a contiguous permutation', () {
      expect(
        () => _content(fieldOrder: <String>[_uuid(20)]),
        throwsArgumentError,
      );
      expect(
        () => _content(fieldOrder: <String>[_uuid(20), _uuid(20)]),
        throwsArgumentError,
      );
      expect(
        () => _content(fieldOrder: <String>[_uuid(20), _uuid(99)]),
        throwsArgumentError,
      );
      expect(
        () => _content(fieldOrder: <String>[_uuid(21), _uuid(20)]),
        throwsArgumentError,
      );
    });

    test('round-trips canonical JSON byte-identically', () {
      final TemplateVersionContent content = _content();
      final Map<String, Object?> json = _roundTrip(content.toJson());
      final TemplateVersionContent parsed = TemplateVersionContent.fromJson(
        json,
      );

      expect(parsed, content);
      expect(parsed.hashCode, content.hashCode);
      expect(
        canonicalJsonEncode(parsed.toJson()),
        canonicalJsonEncode(content.toJson()),
      );
    });

    test('preserves unknown same-schema fields at every level', () {
      final Map<String, Object?> json = Map<String, Object?>.from(
        _content().toJson(),
      );
      json['futureContent'] = <String, Object?>{
        'nested': <Object?>[1, true, null],
      };
      final List<Object?> fields = _list(json['fieldSnapshot']);
      final Map<String, Object?> field = _map(fields[0]);
      field['futureField'] = 'field';
      final Map<String, Object?> rect = _map(field['rect']);
      rect['futureRect'] = 'rect';
      field['rect'] = rect;
      final Map<String, Object?> validation = _map(field['validation']);
      validation['futureValidation'] = 'validation';
      field['validation'] = validation;
      fields[0] = field;
      json['fieldSnapshot'] = fields;
      final List<Object?> pages = _list(json['pageSnapshot']);
      final Map<String, Object?> page = _map(pages[0]);
      page['futurePage'] = 'page';
      final Map<String, Object?> geometry = _map(page['geometry']);
      geometry['futureGeometry'] = 'geometry';
      final Map<String, Object?> mediaBox = _map(geometry['mediaBox']);
      mediaBox['futureRect'] = 'mediaBox';
      geometry['mediaBox'] = mediaBox;
      page['geometry'] = geometry;
      pages[0] = page;
      json['pageSnapshot'] = pages;

      final TemplateVersionContent content = TemplateVersionContent.fromJson(
        json,
      );

      expect(content.unknownFields.keys, <String>['futureContent']);
      expect(canonicalJsonEncode(content.toJson()), canonicalJsonEncode(json));
    });

    test('copyWith revalidates and retains extensions', () {
      final TemplateVersionContent content = _content(
        unknownFields: <String, Object?>{'future': 'kept'},
      );
      final TemplateVersionContent copy = content.copyWith();

      expect(copy, content);
      expect(copy.unknownFields['future'], 'kept');
      expect(() => content.copyWith(schemaVersion: 2), throwsArgumentError);
    });

    test('rejects extension data that is not canonical JSON', () {
      final Map<String, Object?> cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;

      expect(() => _content(unknownFields: cyclic), throwsArgumentError);
      expect(
        () => _content(unknownFields: <String, Object?>{'when': _at()}),
        throwsArgumentError,
      );
    });

    test('deep-freezes extension data against later mutation', () {
      final Map<String, Object?> extension = <String, Object?>{
        'future': <String, Object?>{
          'items': <Object?>[1],
        },
      };
      final TemplateVersionContent content = _content(unknownFields: extension);
      (extension['future']! as Map<String, Object?>)['items'] = <Object?>[2];

      expect(canonicalJsonEncode(content.toJson()), contains('[1]'));
      expect(
        () => (content.unknownFields['future']! as Map<String, Object?>)['x'] =
            'mutated',
        throwsUnsupportedError,
      );
    });

    test('toString reports counts only', () {
      expect(
        _content().toString(),
        'TemplateVersionContent(pages: 2, fields: 2)',
      );
    });
  });

  group('TemplateVersion', () {
    test('composes a pointer for the metadata list', () {
      final TemplateVersion version = _version();
      final TemplateVersionPointer pointer = version.toPointer();

      expect(pointer.versionId, version.id);
      expect(pointer.versionNumber, version.versionNumber);
      expect(pointer.createdAt, version.createdAt);
      expect(pointer, _pointer());
    });

    test('sorts the snapshot by field order', () {
      final ConfirmedField name = _field(order: 0, label: 'Name');
      final ConfirmedField signature = _field(
        order: 1,
        type: FieldType.signature,
        label: 'Unterschrift',
      );
      final TemplateVersion version = _version(
        fieldSnapshot: <ConfirmedField>[signature, name],
      );

      expect(
        version.fieldSnapshot.map((ConfirmedField field) => field.id).toList(),
        <String>[name.id, signature.id],
      );
    });

    test('rejects invalid identity, number, hash, pages, and field order', () {
      expect(() => _version(id: 'x'), throwsArgumentError);
      expect(() => _version(templateId: 'x'), throwsArgumentError);
      expect(() => _version(versionNumber: 0), throwsArgumentError);
      expect(() => _version(sha256: 'xyz'), throwsArgumentError);
      expect(() => _version(pageSnapshot: const <Page>[]), throwsArgumentError);
      expect(
        () => _version(
          fieldSnapshot: <ConfirmedField>[
            _field(order: 0),
            _field(order: 1, id: _uuid(20)),
          ],
          pageSnapshot: _pages(),
        ),
        throwsArgumentError,
      );
      expect(
        () => _version(
          fieldSnapshot: <ConfirmedField>[
            _field(order: 0),
            _field(order: 2, id: _uuid(22)),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => _version(
          fieldSnapshot: <ConfirmedField>[_field(order: 0, pageIndex: 2)],
          pageSnapshot: _pages(),
        ),
        throwsArgumentError,
      );
    });

    test('round-trips canonical JSON and keeps extensions', () {
      final TemplateVersion version = _version(
        unknownFields: <String, Object?>{'futureVersion': 'kept'},
      );
      final TemplateVersion parsed = TemplateVersion.fromJson(
        _roundTrip(version.toJson()),
      );

      expect(parsed, version);
      expect(parsed.hashCode, version.hashCode);
      expect(parsed.unknownFields['futureVersion'], 'kept');
      expect(
        canonicalJsonEncode(parsed.toJson()),
        canonicalJsonEncode(version.toJson()),
      );
    });

    test('fromJson wraps invalid modeled values as FormatException', () {
      expect(
        () => TemplateVersion.fromJson(<String, Object?>{
          ..._version().toJson(),
          'sha256': 'xyz',
        }),
        throwsFormatException,
      );
    });

    test('refuses forbidden payloads at the root and in snapshots', () {
      final Map<String, Object?> root = _version().toJson();
      for (final String key in <String>[
        'values',
        'signatures',
        'suggestions',
        'templateOrigin',
      ]) {
        expect(
          () => TemplateVersion.fromJson(<String, Object?>{
            ...root,
            key: <String, Object?>{},
          }),
          throwsFormatException,
          reason: key,
        );
      }
      final Map<String, Object?> field = _map(_list(root['fieldSnapshot'])[0]);
      expect(
        () => TemplateVersion.fromJson(<String, Object?>{
          ...root,
          'fieldSnapshot': <Object?>[
            <String, Object?>{...field, 'values': <String, Object?>{}},
          ],
        }),
        throwsFormatException,
      );
      final Map<String, Object?> page = _map(_list(root['pageSnapshot'])[0]);
      expect(
        () => TemplateVersion.fromJson(<String, Object?>{
          ...root,
          'pageSnapshot': <Object?>[
            <String, Object?>{...page, 'signatures': <String, Object?>{}},
          ],
        }),
        throwsFormatException,
      );
    });

    test('refuses forbidden payloads in deeply modeled snapshots', () {
      final Map<String, Object?> root = _version().toJson();
      final Map<String, Object?> field = _map(_list(root['fieldSnapshot'])[0]);
      final Map<String, Object?> validation = _map(field['validation']);
      expect(
        () => TemplateVersion.fromJson(<String, Object?>{
          ...root,
          'fieldSnapshot': <Object?>[
            <String, Object?>{
              ...field,
              'validation': <String, Object?>{
                ...validation,
                'signatures': <String, Object?>{},
              },
            },
          ],
        }),
        throwsFormatException,
      );
      final Map<String, Object?> page = _map(_list(root['pageSnapshot'])[0]);
      final Map<String, Object?> geometry = _map(page['geometry']);
      final Map<String, Object?> cropBox = _map(geometry['cropBox']);
      expect(
        () => TemplateVersion.fromJson(<String, Object?>{
          ...root,
          'pageSnapshot': <Object?>[
            <String, Object?>{
              ...page,
              'geometry': <String, Object?>{
                ...geometry,
                'cropBox': <String, Object?>{
                  ...cropBox,
                  'values': <String, Object?>{},
                },
              },
            },
          ],
        }),
        throwsFormatException,
      );
    });

    test('toString reports the version number only', () {
      expect(_version().toString(), 'TemplateVersion(versionNumber: 2)');
    });
  });

  group('Template', () {
    test('builds a layout-only aggregate', () {
      final Template template = _template();
      final Map<String, Object?> json = template.toJson();

      expect(template.kind, 'template');
      expect(template.schemaVersion, templateSchemaVersion);
      expect(template.pages, hasLength(2));
      expect(template.fields, hasLength(2));
      expect(template.fieldOrder, <String>[_uuid(20), _uuid(21)]);
      expect(template.latestVersion, _pointer());
      expect(template.versions, hasLength(2));
      expect(json['kind'], 'template');
      expect(json.containsKey('values'), isFalse);
      expect(json.containsKey('signatures'), isFalse);
      expect(json.containsKey('templateOrigin'), isFalse);
      expect(canonicalJsonEncode(json), isNot(contains('"values"')));
    });

    test('trims the title and preserves German characters', () {
      final Template template = _template(title: '  Antrag Größe 200  ');

      expect(template.title, 'Antrag Größe 200');
    });

    test('rejects an invalid schema version, id, title, or timestamp', () {
      expect(() => _template(schemaVersion: 2), throwsArgumentError);
      expect(() => _template(id: 'x'), throwsArgumentError);
      expect(() => _template(title: '   '), throwsArgumentError);
      expect(() => _template(title: 'x' * 201), throwsArgumentError);
      expect(() => _template(title: 'a\nb'), throwsArgumentError);
      expect(
        () => _template(createdAt: DateTime(2026, 11, 14)),
        throwsArgumentError,
      );
    });

    test('rejects a page list that does not match the source', () {
      expect(
        () => _template(pages: const <Page>[], source: _source()),
        throwsArgumentError,
      );
      expect(
        () => _template(pages: <Page>[_page(index: 1)]),
        throwsArgumentError,
      );
      expect(
        () => _template(pages: <Page>[_page(index: 0), _page(index: 2)]),
        throwsArgumentError,
      );
      expect(
        () => _template(source: _source(pageCount: 1)),
        throwsArgumentError,
      );
    });

    test('rejects fields that do not belong to the layout', () {
      expect(
        () => _template(
          fields: <ConfirmedField>[_field(order: 0), _field(order: 0)],
        ),
        throwsArgumentError,
      );
      expect(
        () => _template(
          fields: <ConfirmedField>[_field(order: 0, pageIndex: 2)],
          fieldOrder: <String>[_uuid(20)],
        ),
        throwsArgumentError,
      );
      expect(
        () => _template(
          fields: <ConfirmedField>[_field(order: 0, rect: _rect(left: 600))],
          fieldOrder: <String>[_uuid(20)],
        ),
        throwsArgumentError,
      );
      expect(
        () => _template(
          fields: <ConfirmedField>[_field(order: 0)],
          fieldOrder: <String>[_uuid(20), _uuid(21)],
        ),
        throwsArgumentError,
      );
    });

    test('rejects a version list that is not newest first', () {
      expect(
        () => _template(
          versions: <TemplateVersionPointer>[
            _pointer(number: 1),
            _pointer(number: 2),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => _template(versions: const <TemplateVersionPointer>[]),
        throwsArgumentError,
      );
      expect(
        () => _template(
          versions: <TemplateVersionPointer>[
            _pointer(number: 2),
            _pointer(number: 1, versionId: _uuid(43)),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => _template(
          versions: <TemplateVersionPointer>[
            _pointer(number: 2),
            _pointer(number: 1),
            _pointer(number: 1, versionId: _uuid(45)),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects non-monotonic version timestamps', () {
      expect(
        () => _template(
          versions: <TemplateVersionPointer>[
            _pointer(number: 2, createdAt: _at(0)),
            _pointer(number: 1, createdAt: _at(5)),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => _template(
          versions: <TemplateVersionPointer>[
            _pointer(number: 2, createdAt: _at(3)),
            _pointer(number: 1, createdAt: _at(3)),
          ],
        ),
        returnsNormally,
      );
    });

    test('requires latestVersion to be the newest pointer (FR-105)', () {
      expect(
        () => _template(latestVersion: _pointer(number: 1)),
        throwsArgumentError,
      );
      expect(_template().latestVersion.versionNumber, 2);
    });

    test('rejects a wrong kind, missing, or newer schema in JSON', () {
      expect(
        () => Template.fromJson(<String, Object?>{
          ..._template().toJson(),
          'kind': 'document',
        }),
        throwsFormatException,
      );
      expect(
        () => Template.fromJson(<String, Object?>{
          ..._template().toJson(),
          'schemaVersion': 2,
        }),
        throwsFormatException,
      );
      final Map<String, Object?> missing = _template().toJson();
      missing.remove('schemaVersion');
      expect(() => Template.fromJson(missing), throwsFormatException);
      expect(
        () => Template.fromJson(<String, Object?>{
          ..._template().toJson(),
          'schemaVersion': null,
        }),
        throwsFormatException,
      );
      expect(
        () => Template.fromJson(<String, Object?>{
          ..._template().toJson(),
          'schemaVersion': '1',
        }),
        throwsFormatException,
      );
    });

    test('refuses forbidden payloads at the root and in modeled objects', () {
      final Map<String, Object?> root = _template().toJson();
      for (final String key in <String>[
        'values',
        'signatures',
        'suggestions',
        'templateOrigin',
      ]) {
        expect(
          () => Template.fromJson(<String, Object?>{
            ...root,
            key: <String, Object?>{},
          }),
          throwsFormatException,
          reason: key,
        );
      }
      final Map<String, Object?> page = _map(_list(root['pages'])[0]);
      expect(
        () => Template.fromJson(<String, Object?>{
          ...root,
          'pages': <Object?>[
            <String, Object?>{...page, 'values': <String, Object?>{}},
          ],
        }),
        throwsFormatException,
      );
      final Map<String, Object?> field = _map(_list(root['fields'])[0]);
      expect(
        () => Template.fromJson(<String, Object?>{
          ...root,
          'fields': <Object?>[
            <String, Object?>{...field, 'signatures': <String, Object?>{}},
          ],
        }),
        throwsFormatException,
      );
      final Map<String, Object?> version = _map(_list(root['versions'])[0]);
      expect(
        () => Template.fromJson(<String, Object?>{
          ...root,
          'versions': <Object?>[
            <String, Object?>{...version, 'values': <String, Object?>{}},
          ],
        }),
        throwsFormatException,
      );
    });

    test('refuses forbidden payloads in deeply modeled page/field objects', () {
      final Map<String, Object?> root = _template().toJson();
      final List<Object?> pages = _list(root['pages']);
      final Map<String, Object?> page = _map(pages[0]);
      final Map<String, Object?> geometry = _map(page['geometry']);
      final Map<String, Object?> mediaBox = _map(geometry['mediaBox']);
      expect(
        () => Template.fromJson(<String, Object?>{
          ...root,
          'pages': <Object?>[
            <String, Object?>{
              ...page,
              'geometry': <String, Object?>{
                ...geometry,
                'mediaBox': <String, Object?>{
                  ...mediaBox,
                  'values': <String, Object?>{},
                },
              },
            },
            pages[1],
          ],
        }),
        throwsFormatException,
      );
      final Map<String, Object?> failedPage = <String, Object?>{
        ...page,
        'analysis': 'failed',
        'failure': <String, Object?>{
          'pageIndex': 0,
          'category': 'rasterization',
          'messageKey': 'REC-002',
          'signatures': <String, Object?>{},
        },
      };
      expect(
        () => Template.fromJson(<String, Object?>{
          ...root,
          'pages': <Object?>[failedPage, pages[1]],
        }),
        throwsFormatException,
      );
      final Map<String, Object?> field = _map(_list(root['fields'])[0]);
      final Map<String, Object?> validation = _map(field['validation']);
      expect(
        () => Template.fromJson(<String, Object?>{
          ...root,
          'fields': <Object?>[
            <String, Object?>{
              ...field,
              'validation': <String, Object?>{
                ...validation,
                'values': <String, Object?>{},
              },
            },
          ],
        }),
        throwsFormatException,
      );
    });

    test('round-trips canonical JSON byte-identically', () {
      final Template template = _template();
      final Template parsed = Template.fromJson(_roundTrip(template.toJson()));

      expect(parsed, template);
      expect(parsed.hashCode, template.hashCode);
      expect(
        canonicalJsonEncode(parsed.toJson()),
        canonicalJsonEncode(template.toJson()),
      );
    });

    test('retains machine provenance in the layout', () {
      final ConfirmedField machine = _field(
        order: 0,
        provenance: Provenance.machine,
        sourceSuggestionId: FieldSuggestion.idFor(pageIndex: 0, ordinal: 1),
        suggestionConfidence: 0.82,
      );
      final Template template = _template(
        fields: <ConfirmedField>[machine],
        fieldOrder: <String>[machine.id],
      );
      final Template parsed = Template.fromJson(_roundTrip(template.toJson()));

      expect(parsed.fields.single.provenance, Provenance.machine);
      expect(
        parsed.fields.single.sourceSuggestionId,
        FieldSuggestion.idFor(pageIndex: 0, ordinal: 1),
      );
      expect(parsed, template);
    });

    test('keeps existing versions immutable when a version is added', () {
      final TemplateVersionContent firstContent = _content();
      final String firstBytes = canonicalJsonEncode(firstContent.toJson());
      final TemplateVersionPointer firstPointer = _pointer(number: 1);
      final Template template = _template(
        versions: <TemplateVersionPointer>[firstPointer],
        latestVersion: firstPointer,
      );
      final TemplateVersion secondVersion = _version(
        id: _uuid(43),
        versionNumber: 2,
        createdAt: _at(10),
      );

      final Template updated = template.copyWith(
        updatedAt: _at(10),
        latestVersion: secondVersion.toPointer(),
        versions: <TemplateVersionPointer>[
          secondVersion.toPointer(),
          ...template.versions,
        ],
      );

      expect(canonicalJsonEncode(firstContent.toJson()), firstBytes);
      expect(updated.versions.last, firstPointer);
      expect(updated.versions.first.versionId, secondVersion.id);
      expect(updated.latestVersion, secondVersion.toPointer());
      expect(template.latestVersion, firstPointer);
      expect(() => updated.versions.add(firstPointer), throwsUnsupportedError);
    });

    test('does not re-point a derived-document pin (FR-104)', () {
      final TemplateVersionPointer pinned = _pointer(number: 1);
      final TemplateOrigin origin = TemplateOrigin(
        templateId: _uuid(40),
        templateVersionId: pinned.versionId,
        templateVersionNumber: pinned.versionNumber,
      );
      final Template template = _template(
        versions: <TemplateVersionPointer>[_pointer(number: 2), pinned],
      );

      expect(origin.templateVersionId, pinned.versionId);
      expect(template.toJson().containsKey('templateOrigin'), isFalse);
      expect(template.latestVersion.versionNumber, 2);
    });

    test('copyWith revalidates and keeps extensions by default', () {
      final Template template = _template(
        unknownFields: <String, Object?>{'future': 'kept'},
      );
      final Template copy = template.copyWith(title: 'Anderer Antrag');

      expect(copy.title, 'Anderer Antrag');
      expect(copy.unknownFields['future'], 'kept');
      expect(() => template.copyWith(schemaVersion: 2), throwsArgumentError);
    });

    test('equality and hashCode ignore extension data', () {
      final Template plain = _template();
      final Template extended = _template(
        unknownFields: <String, Object?>{'future': 'ignored'},
      );

      expect(extended, plain);
      expect(extended.hashCode, plain.hashCode);
      expect(_template(title: 'Anders'), isNot(plain));
      expect(
        canonicalJsonEncode(extended.toJson()),
        isNot(canonicalJsonEncode(plain.toJson())),
      );
    });

    test('rejects extension data that is not canonical JSON', () {
      final Map<String, Object?> cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;

      expect(() => _template(unknownFields: cyclic), throwsArgumentError);
      expect(
        () => _template(unknownFields: <String, Object?>{'when': _at()}),
        throwsArgumentError,
      );
    });

    test('toString and errors never echo the title or labels', () {
      final Template template = _template(
        title: 'Geheime Vorlage',
        fields: <ConfirmedField>[_field(order: 0, label: 'Geheimfeld')],
        fieldOrder: <String>[_uuid(20)],
      );

      expect(template.toString(), isNot(contains('Geheime Vorlage')));
      expect(template.toString(), isNot(contains('Geheimfeld')));
      expect(
        () => _template(title: 'Geheim${'x' * 200}'),
        throwsA(
          predicate<Object>(
            (Object error) => !error.toString().contains('Geheim'),
          ),
        ),
      );
    });
  });

  group('TemplateMeta', () {
    test('serializes the meta.fx1 envelope without layout content', () {
      final TemplateMeta meta = _meta();
      final Map<String, Object?> json = meta.toJson();

      expect(meta.kind, 'template');
      expect(json.keys.toSet(), <String>{
        'id',
        'kind',
        'title',
        'createdAt',
        'updatedAt',
        'source',
        'latestVersion',
        'versions',
        'readable',
        'unreadableReasonCode',
      });
      expect(json.containsKey('pages'), isFalse);
      expect(json.containsKey('fields'), isFalse);
      expect(json.containsKey('fieldOrder'), isFalse);
      expect(json.containsKey('values'), isFalse);
      expect(json.containsKey('signatures'), isFalse);
      expect(json['latestVersion'], _pointer().toJson());
    });

    test('round-trips canonical JSON byte-identically', () {
      final TemplateMeta meta = _meta();
      final TemplateMeta parsed = TemplateMeta.fromJson(
        _roundTrip(meta.toJson()),
      );

      expect(parsed, meta);
      expect(parsed.hashCode, meta.hashCode);
      expect(
        canonicalJsonEncode(parsed.toJson()),
        canonicalJsonEncode(meta.toJson()),
      );
    });

    test('supports an unreadable envelope with a catalog reason', () {
      final TemplateMeta meta = _meta(
        readable: false,
        unreadableReasonCode: 'SAVE-003',
      );

      expect(meta.readable, isFalse);
      expect(meta.unreadableReasonCode, 'SAVE-003');
      expect(TemplateMeta.fromJson(_roundTrip(meta.toJson())), meta);
    });

    test('rejects an inconsistent readable state or code', () {
      expect(
        () => _meta(unreadableReasonCode: 'SAVE-003'),
        throwsArgumentError,
      );
      expect(
        () => _meta(readable: false, unreadableReasonCode: 'kaputt'),
        throwsArgumentError,
      );
      expect(
        () => TemplateMeta.fromJson(<String, Object?>{
          ..._meta().toJson(),
          'unreadableReasonCode': 1,
        }),
        throwsFormatException,
      );
    });

    test('copyWith can clear the unreadable reason', () {
      final TemplateMeta meta = _meta(
        readable: false,
        unreadableReasonCode: 'SAVE-003',
      );
      final TemplateMeta repaired = meta.copyWith(
        readable: true,
        unreadableReasonCode: null,
      );

      expect(repaired.readable, isTrue);
      expect(repaired.unreadableReasonCode, isNull);
      expect(meta.unreadableReasonCode, 'SAVE-003');
    });

    test('rejects a wrong discriminator or missing modeled field', () {
      expect(
        () => TemplateMeta.fromJson(<String, Object?>{
          ..._meta().toJson(),
          'kind': 'document',
        }),
        throwsFormatException,
      );
      final Map<String, Object?> json = _meta().toJson();
      json.remove('readable');
      expect(() => TemplateMeta.fromJson(json), throwsFormatException);
    });

    test('has no mandatory schemaVersion in the v1 envelope', () {
      final Map<String, Object?> json = _meta().toJson();
      expect(json.containsKey('schemaVersion'), isFalse);
      expect(TemplateMeta.fromJson(json), _meta());

      final TemplateMeta normalized = TemplateMeta.fromJson(<String, Object?>{
        ...json,
        'schemaVersion': templateSchemaVersion,
      });
      expect(normalized, _meta());
      expect(normalized.toJson().containsKey('schemaVersion'), isFalse);
    });

    test('refuses a present null, newer, or mistyped schemaVersion marker', () {
      expect(
        () => TemplateMeta.fromJson(<String, Object?>{
          ..._meta().toJson(),
          'schemaVersion': null,
        }),
        throwsFormatException,
      );
      expect(
        () => TemplateMeta.fromJson(<String, Object?>{
          ..._meta().toJson(),
          'schemaVersion': 2,
        }),
        throwsFormatException,
      );
      expect(
        () => TemplateMeta.fromJson(<String, Object?>{
          ..._meta().toJson(),
          'schemaVersion': '1',
        }),
        throwsFormatException,
      );
    });

    test('refuses forbidden payloads at the root and in pointer objects', () {
      final Map<String, Object?> root = _meta().toJson();
      for (final String key in <String>[
        'values',
        'signatures',
        'suggestions',
        'templateOrigin',
      ]) {
        expect(
          () => TemplateMeta.fromJson(<String, Object?>{
            ...root,
            key: <String, Object?>{},
          }),
          throwsFormatException,
          reason: key,
        );
      }
      final Map<String, Object?> latest = _map(root['latestVersion']);
      expect(
        () => TemplateMeta.fromJson(<String, Object?>{
          ...root,
          'latestVersion': <String, Object?>{
            ...latest,
            'values': <String, Object?>{},
          },
        }),
        throwsFormatException,
      );
    });

    test('keeps the newest-first version invariant', () {
      expect(
        () => _meta(
          versions: <TemplateVersionPointer>[
            _pointer(number: 1),
            _pointer(number: 2),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => _meta(latestVersion: _pointer(number: 1)),
        throwsArgumentError,
      );
    });

    test('preserves unknown same-schema fields', () {
      final Map<String, Object?> json = <String, Object?>{
        ..._meta().toJson(),
        'futureMeta': 'kept',
      };
      final TemplateMeta meta = TemplateMeta.fromJson(json);

      expect(meta.unknownFields.keys, <String>['futureMeta']);
      expect(canonicalJsonEncode(meta.toJson()), canonicalJsonEncode(json));
      expect(meta.toString(), isNot(contains('futureMeta')));
    });
  });

  group('StoredTemplate', () {
    test('joins a listed version with its verified content', () {
      final StoredTemplate stored = _stored();

      expect(stored.templateId, _uuid(40));
      expect(stored.versionNumber, 2);
      expect(stored.pages, hasLength(2));
      expect(stored.fields, hasLength(2));
      expect(stored.fieldOrder, <String>[_uuid(20), _uuid(21)]);
    });

    test('rejects a version from another template', () {
      expect(
        () => _stored(version: _version(templateId: _uuid(44))),
        throwsArgumentError,
      );
    });

    test('rejects a version that the metadata does not list', () {
      final TemplateMeta meta = _meta(
        versions: <TemplateVersionPointer>[_pointer(number: 1)],
        latestVersion: _pointer(number: 1),
      );

      expect(() => _stored(meta: meta), throwsArgumentError);
    });

    test('rejects content that does not match the version snapshots', () {
      expect(
        () => _stored(
          version: _version(
            fieldSnapshot: <ConfirmedField>[
              _field(order: 0, label: 'Abweichend'),
              _field(
                order: 1,
                type: FieldType.signature,
                label: 'Unterschrift',
              ),
            ],
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => _stored(
          content: _content(
            pages: <Page>[_page(index: 0, rotation: 90), _page(index: 1)],
          ),
        ),
        throwsArgumentError,
      );
    });

    test('exposes a layout-only model without filled content', () {
      final StoredTemplate stored = _stored();

      expect(
        stored.fields.map((ConfirmedField field) => field.type).toList(),
        <FieldType>[FieldType.text, FieldType.signature],
      );
      expect(stored.content.toJson().containsKey('values'), isFalse);
      expect(stored.content.toJson().containsKey('signatures'), isFalse);
      expect(stored.toString(), isNot(contains('Name')));
      expect(stored.toString(), isNot(contains('Unterschrift')));
    });

    test('copyWith revalidates the join', () {
      final StoredTemplate stored = _stored();

      expect(stored.copyWith(), stored);
      expect(
        () => stored.copyWith(meta: _meta(id: _uuid(44))),
        throwsArgumentError,
      );
    });
  });

  group('save-shape invariants (FR-054–FR-057, SC-013)', () {
    // A filled document snapshot (T058 `RevisionContent` shape: pages,
    // confirmed fields including machine-provenance ones, values, signatures,
    // verification) is the input the explicit "Als Vorlage speichern" action
    // feeds into a template save. These tests pin that the template-side
    // snapshot models keep the layout (FR-056) and cannot carry the filled
    // part (FR-057). The last test drives a REAL filled `RevisionContent`
    // with entered values and a captured signature (value + mark) through the
    // save shape, so the exclusion is proven on the actual document model,
    // not only on constructor echoes.
    test('a real filled RevisionContent with a captured signature saves as a '
        'layout-only template shape (FR-056, FR-057)', () {
      final ConfirmedField textField = _field(order: 0, label: 'Familienname');
      final ConfirmedField signatureField = _field(
        order: 1,
        type: FieldType.signature,
        label: 'Unterschrift',
      );
      final String assetId = _uuid(61);
      final DateTime capturedAt = _at(5);
      final RevisionContent filled = RevisionContent(
        pages: _pages(),
        fields: <ConfirmedField>[textField, signatureField],
        fieldOrder: <String>[textField.id, signatureField.id],
        values: <String, FieldValue>{
          textField.id: TextValue(text: 'Musterfrau', lastEditedAt: capturedAt),
          signatureField.id: SignatureValue(
            signatureAssetId: assetId,
            lastEditedAt: capturedAt,
          ),
        },
        signatures: <String, SignatureMark>{
          signatureField.id: SignatureMark(
            assetId: assetId,
            fieldId: signatureField.id,
            pageIndex: 0,
            rect: signatureField.rect,
            widthPx: 320,
            heightPx: 160,
            capturedAt: capturedAt,
            sha256: _sha256,
          ),
        },
        verification: <String, FieldVerification>{
          textField.id: FieldVerification(
            state: FieldVerificationState.confirmed,
            reviewedAt: capturedAt,
          ),
        },
      );
      expect(filled.values, hasLength(2));
      expect(filled.signatures, hasLength(1));

      // The save shape takes only pages and confirmed fields; the filled
      // part (values, signature value, signature mark, verification) is
      // structurally dropped, and the signature asset id never enters the
      // template payload.
      final TemplateVersionContent saved = TemplateVersionContent(
        pageSnapshot: filled.pages,
        fieldSnapshot: filled.fields,
        fieldOrder: filled.fieldOrder,
      );
      final String canonical = canonicalJsonEncode(saved.toJson());
      expect(canonical.contains('Musterfrau'), isFalse);
      expect(canonical.contains(assetId), isFalse);
      expect(canonical.contains('signatureAssetId'), isFalse);
      expect(
        saved.fieldSnapshot.map((ConfirmedField field) => field.type),
        contains(FieldType.signature),
      );
    });

    test('a filled document snapshot saves as pages plus field definitions '
        '(FR-056)', () {
      final ConfirmedField machineField = _field(
        id: _uuid(30),
        order: 0,
        provenance: Provenance.machine,
        sourceSuggestionId: 's_p0_0001',
        suggestionConfidence: 0.82,
        label: 'Familienname',
      );
      final TemplateVersionContent content = _content(
        fields: <ConfirmedField>[
          machineField,
          _field(order: 1, type: FieldType.signature, label: 'Unterschrift'),
        ],
      );
      expect(content.pageSnapshot, _pages());
      expect(content.fieldSnapshot, hasLength(2));
      expect(content.fieldSnapshot.first.provenance, Provenance.machine);
      expect(content.fieldSnapshot.first.type, FieldType.text);
      expect(content.fieldSnapshot.last.type, FieldType.signature);
      expect(content.fieldOrder, <String>[
        machineField.id,
        content.fieldSnapshot.last.id,
      ]);
    });

    test('the saved payload of a filled snapshot has no value, signature, '
        'verification, or origin key (FR-057)', () {
      final TemplateVersionContent content = _content(
        fields: <ConfirmedField>[
          _field(
            order: 0,
            provenance: Provenance.machine,
            sourceSuggestionId: 's_p0_0001',
            suggestionConfidence: 0.82,
            label: 'Familienname',
          ),
          _field(order: 1, type: FieldType.signature, label: 'Unterschrift'),
        ],
      );
      final Map<String, Object?> json = _roundTrip(content.toJson());
      expect(json.containsKey('values'), isFalse);
      expect(json.containsKey('signatures'), isFalse);
      expect(json.containsKey('suggestions'), isFalse);
      expect(json.containsKey('verification'), isFalse);
      expect(json.containsKey('templateOrigin'), isFalse);
    });

    test('a filled snapshot stored as a template exposes no filled content '
        '(FR-057, SC-013)', () {
      final TemplateVersionContent content = _content(
        fields: <ConfirmedField>[
          _field(
            order: 0,
            provenance: Provenance.machine,
            sourceSuggestionId: 's_p0_0001',
            suggestionConfidence: 0.82,
            label: 'Familienname',
          ),
        ],
      );
      final StoredTemplate stored = _stored(
        version: _version(
          fieldSnapshot: content.fieldSnapshot,
          pageSnapshot: content.pageSnapshot,
        ),
        content: content,
      );
      final Map<String, Object?> metaJson = _roundTrip(stored.meta.toJson());
      final Map<String, Object?> contentJson = _roundTrip(
        stored.content.toJson(),
      );
      for (final Map<String, Object?> json in <Map<String, Object?>>[
        metaJson,
        contentJson,
      ]) {
        expect(json.containsKey('values'), isFalse);
        expect(json.containsKey('signatures'), isFalse);
        expect(json.containsKey('suggestions'), isFalse);
        expect(json.containsKey('verification'), isFalse);
        expect(json.containsKey('templateOrigin'), isFalse);
      }
      expect(stored.meta.versions, isNotEmpty);
      expect(stored.version.fieldSnapshot, hasLength(1));
    });
  });

  group('unknown same-schema fields', () {
    test('survive a full template read/write round at every level', () {
      final Map<String, Object?> json = Map<String, Object?>.from(
        _template().toJson(),
      );
      json['futureTemplate'] = <String, Object?>{
        'nested': <Object?>[1, true, null],
      };
      final Map<String, Object?> latestVersion = _map(json['latestVersion']);
      latestVersion['futurePointer'] = 'latest';
      json['latestVersion'] = latestVersion;
      final List<Object?> versions = _list(json['versions']);
      final Map<String, Object?> version = _map(versions[0]);
      version['futurePointer'] = 'version';
      versions[0] = version;
      json['versions'] = versions;
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
      pages[0] = page;
      json['pages'] = pages;
      final List<Object?> fields = _list(json['fields']);
      final Map<String, Object?> field = _map(fields[0]);
      field['futureField'] = 'field';
      final Map<String, Object?> rect = _map(field['rect']);
      rect['futureRect'] = 'fieldRect';
      field['rect'] = rect;
      final Map<String, Object?> validation = _map(field['validation']);
      validation['futureValidation'] = 'validation';
      field['validation'] = validation;
      fields[0] = field;
      json['fields'] = fields;

      final Template template = Template.fromJson(json);

      expect(template.unknownFields.keys, <String>['futureTemplate']);
      expect(canonicalJsonEncode(template.toJson()), canonicalJsonEncode(json));
    });

    test('are dropped only across a schema boundary (fail closed)', () {
      final Map<String, Object?> json = <String, Object?>{
        ..._template().toJson(),
        'schemaVersion': 2,
        'futureTemplate': 'later',
      };

      expect(() => Template.fromJson(json), throwsFormatException);
      expect(
        () => TemplateVersionContent.fromJson(<String, Object?>{
          ..._content().toJson(),
          'schemaVersion': 2,
        }),
        throwsFormatException,
      );
    });

    test('are not part of equality but are part of writes', () {
      final TemplateMeta plain = _meta();
      final TemplateMeta extended = _meta(
        unknownFields: <String, Object?>{'futureMeta': 'kept'},
      );

      expect(extended, plain);
      expect(
        canonicalJsonEncode(extended.toJson()),
        isNot(canonicalJsonEncode(plain.toJson())),
      );
    });
  });
}
