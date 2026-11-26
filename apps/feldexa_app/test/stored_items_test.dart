// T095 start-area document and template group host widget tests.
//
// Evidence class: NONE. These are host-VM widget tests with synthetic
// summaries and the committed German ARB. They build no platform channel, open
// no document, invoke no editor, persistence, file, network, or localization
// service, and make no Android, device, screen-reader, or visual claim.
//
// They prove the pinned T095 behaviour:
//   * `DocumentSummary.fromStoredMeta` derives saved/draft/unreadable exactly,
//     copies the stored identity unconditionally, and never infers the
//     application-only `exportReady` state;
//   * documents and templates render as separate, labelled groups sorted newest
//     first with a deterministic id tie-break, without mutating caller lists;
//   * every entry shows the full title, the local zero-padded `dd.MM.yyyy`
//     last-edited date, and an icon plus the exact status label;
//   * empty groups show their exact ARB message independently;
//   * open and optional delete callbacks receive the exact id exactly once, and
//     no delete control exists without a callback;
//   * stable section and entry keys exist, status is never colour-only, 200 %
//     text scale reflows at 280 logical pixels, and 50 entries stay scrollable;
//   * the production source stays presentation-only with only the three
//     authorized imports.

@TestOn('vm')
library;

import 'dart:io';

import 'package:feldexa_app/features/start/stored_items.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/package_root.dart';

/// Narrow bounded width used to force wrapping at 200 % text scale.
const double _narrowWidth = 280;

const ValueKey<String> _documentsSectionKey = ValueKey<String>(
  'documents-section',
);
const ValueKey<String> _templatesSectionKey = ValueKey<String>(
  'templates-section',
);

final AppLocalizations _de = lookupAppLocalizations(const Locale('de'));

/// Builds a valid lowercase UUIDv4 from a test-sequence number.
String _uuid(int value) {
  return '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
}

/// A fixed UTC timestamp on 2026-11-14.
DateTime _at({int day = 14, int hour = 12, int minute = 0}) {
  return DateTime.utc(2026, 11, day, hour, minute);
}

/// Builds a valid [StoredMeta] fixture.
StoredMeta _meta({
  String? id,
  StoreKind kind = StoreKind.document,
  String title = 'Antrag',
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? lastDurableAt,
  bool readable = true,
}) {
  return StoredMeta(
    id: id ?? _uuid(1),
    kind: kind,
    title: title,
    createdAt: createdAt ?? _at(day: 1),
    updatedAt: updatedAt ?? _at(),
    lastDurableAt: lastDurableAt,
    readable: readable,
    unreadableReasonCode: readable ? null : 'SAVE-002',
  );
}

/// Builds a caller-authored summary without touching storage.
DocumentSummary _summary({
  required String id,
  required String title,
  required DateTime updatedAt,
  StoredItemStatus status = StoredItemStatus.draft,
}) {
  return DocumentSummary(
    id: id,
    title: title,
    updatedAt: updatedAt,
    status: status,
  );
}

/// Stable entry key used by the view and these tests.
ValueKey<String> _entryKey(String id) {
  return ValueKey<String>('stored-item-$id');
}

/// Stable delete key used by the view and these tests.
ValueKey<String> _deleteKey(String id) {
  return ValueKey<String>('stored-item-delete-$id');
}

/// Mirrors the production local `dd.MM.yyyy` formatting for expected values.
String _localDate(DateTime timestamp) {
  final DateTime local = timestamp.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.'
      '${local.year.toString().padLeft(4, '0')}';
}

Widget _view({
  List<DocumentSummary> documents = const <DocumentSummary>[],
  List<DocumentSummary> templates = const <DocumentSummary>[],
  ValueChanged<String>? onOpenDocument,
  ValueChanged<String>? onOpenTemplate,
  ValueChanged<String>? onDelete,
}) {
  return StoredItemsView(
    documents: documents,
    templates: templates,
    onOpenDocument: onOpenDocument ?? (String _) {},
    onOpenTemplate: onOpenTemplate ?? (String _) {},
    onDelete: onDelete,
  );
}

Widget _host(
  Widget child, {
  double textScale = 1.0,
  double width = 480,
  double height = 700,
}) {
  return MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (BuildContext context, Widget? child) {
      return MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      );
    },
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, height: height, child: child),
      ),
    ),
  );
}

/// Enlarges the host viewport for layouts taller than the default test surface.
void _setSurfaceSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('DocumentSummary.fromStoredMeta', () {
    test('readable with lastDurableAt equal to updatedAt is saved', () {
      final DateTime instant = _at(hour: 9);
      final DocumentSummary summary = DocumentSummary.fromStoredMeta(
        _meta(updatedAt: instant, lastDurableAt: instant),
      );

      expect(summary.status, StoredItemStatus.saved);
    });

    test('readable with lastDurableAt after updatedAt is saved', () {
      final DocumentSummary summary = DocumentSummary.fromStoredMeta(
        _meta(updatedAt: _at(hour: 9), lastDurableAt: _at(hour: 10)),
      );

      expect(summary.status, StoredItemStatus.saved);
    });

    test('readable with lastDurableAt before updatedAt is draft', () {
      final DocumentSummary summary = DocumentSummary.fromStoredMeta(
        _meta(updatedAt: _at(hour: 10), lastDurableAt: _at(hour: 9)),
      );

      expect(summary.status, StoredItemStatus.draft);
    });

    test('readable without lastDurableAt is draft', () {
      final DocumentSummary summary = DocumentSummary.fromStoredMeta(
        _meta(updatedAt: _at(hour: 10)),
      );

      expect(summary.status, StoredItemStatus.draft);
    });

    test('unreadable wins over a durable timestamp', () {
      final DocumentSummary summary = DocumentSummary.fromStoredMeta(
        _meta(
          updatedAt: _at(hour: 9),
          lastDurableAt: _at(hour: 10),
          readable: false,
        ),
      );

      expect(summary.status, StoredItemStatus.unreadable);
    });

    test('copies id, title, and UTC updatedAt unchanged', () {
      final DateTime updatedAt = _at(hour: 7, minute: 5);
      final StoredMeta meta = _meta(
        id: _uuid(41),
        title: 'Prüfbericht – März 2026',
        updatedAt: updatedAt,
        lastDurableAt: updatedAt,
      );

      final DocumentSummary summary = DocumentSummary.fromStoredMeta(meta);

      expect(summary.id, meta.id);
      expect(summary.title, meta.title);
      expect(summary.updatedAt, meta.updatedAt);
      expect(summary.updatedAt.isUtc, isTrue);
      expect(summary.fieldCount, isNull);
      expect(summary.filledCount, isNull);
    });

    test('never infers exportReady from any StoredMeta fixture', () {
      final List<StoredMeta> fixtures = <StoredMeta>[
        _meta(id: _uuid(51), lastDurableAt: _at(hour: 10)),
        _meta(id: _uuid(52), updatedAt: _at(hour: 10)),
        _meta(
          id: _uuid(53),
          updatedAt: _at(hour: 10),
          lastDurableAt: _at(hour: 11),
          readable: false,
        ),
      ];

      for (final StoredMeta meta in fixtures) {
        final DocumentSummary summary = DocumentSummary.fromStoredMeta(meta);
        expect(
          summary.status,
          isNot(StoredItemStatus.exportReady),
          reason: 'storage cannot author an export result',
        );
      }
    });

    test('a manually constructed exportReady summary keeps that status', () {
      final DocumentSummary summary = DocumentSummary(
        id: _uuid(61),
        title: 'Exportiertes Dokument',
        updatedAt: _at(),
        status: StoredItemStatus.exportReady,
        fieldCount: 7,
        filledCount: 3,
      );

      expect(summary.status, StoredItemStatus.exportReady);
      expect(summary.fieldCount, 7);
      expect(summary.filledCount, 3);
    });
  });

  testWidgets('renders exact group headings and keeps entries in their group', (
    WidgetTester tester,
  ) async {
    final DocumentSummary document = _summary(
      id: _uuid(71),
      title: 'Dokument A',
      updatedAt: _at(hour: 10),
    );
    final DocumentSummary template = _summary(
      id: _uuid(72),
      title: 'Vorlage A',
      updatedAt: _at(hour: 11),
    );

    await tester.pumpWidget(
      _host(
        _view(
          documents: <DocumentSummary>[document],
          templates: <DocumentSummary>[template],
        ),
      ),
    );

    expect(find.text(_de.documentsGroup), findsOneWidget);
    expect(find.text(_de.templatesGroup), findsOneWidget);
    expect(find.byKey(_documentsSectionKey), findsOneWidget);
    expect(find.byKey(_templatesSectionKey), findsOneWidget);

    expect(
      find.descendant(
        of: find.byKey(_documentsSectionKey),
        matching: find.byKey(_entryKey(document.id)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(_templatesSectionKey),
        matching: find.byKey(_entryKey(document.id)),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(_templatesSectionKey),
        matching: find.byKey(_entryKey(template.id)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(_documentsSectionKey),
        matching: find.byKey(_entryKey(template.id)),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sorts each group newest first with an ascending-id tie and copies lists',
    (WidgetTester tester) async {
      final DocumentSummary newestTieHigh = _summary(
        id: _uuid(83),
        title: 'Tie hohe Id',
        updatedAt: _at(hour: 13),
      );
      final DocumentSummary newestTieLow = _summary(
        id: _uuid(81),
        title: 'Tie niedrige Id',
        updatedAt: _at(hour: 13),
      );
      final DocumentSummary middle = _summary(
        id: _uuid(82),
        title: 'Mittlere Zeit',
        updatedAt: _at(hour: 12),
      );
      final DocumentSummary oldest = _summary(
        id: _uuid(84),
        title: 'Älteste Zeit',
        updatedAt: _at(hour: 11),
      );
      final DocumentSummary newestTemplate = _summary(
        id: _uuid(86),
        title: 'Neuere Vorlage',
        updatedAt: _at(hour: 15),
      );
      final DocumentSummary olderTemplate = _summary(
        id: _uuid(85),
        title: 'Ältere Vorlage',
        updatedAt: _at(hour: 14),
      );
      final List<DocumentSummary> documents = <DocumentSummary>[
        oldest,
        newestTieHigh,
        middle,
        newestTieLow,
      ];
      final List<DocumentSummary> templates = <DocumentSummary>[
        olderTemplate,
        newestTemplate,
      ];
      final List<String> originalDocumentIds = documents
          .map((DocumentSummary item) => item.id)
          .toList();
      final List<String> originalTemplateIds = templates
          .map((DocumentSummary item) => item.id)
          .toList();

      await tester.pumpWidget(
        _host(_view(documents: documents, templates: templates), height: 1400),
      );

      final List<DocumentSummary> expectedDocuments = <DocumentSummary>[
        newestTieLow,
        newestTieHigh,
        middle,
        oldest,
      ];
      double previousTop = double.negativeInfinity;
      for (final DocumentSummary item in expectedDocuments) {
        final double top = tester.getTopLeft(find.byKey(_entryKey(item.id))).dy;
        expect(top, greaterThan(previousTop), reason: item.title);
        previousTop = top;
      }

      final List<DocumentSummary> expectedTemplates = <DocumentSummary>[
        newestTemplate,
        olderTemplate,
      ];
      previousTop = double.negativeInfinity;
      for (final DocumentSummary item in expectedTemplates) {
        final double top = tester.getTopLeft(find.byKey(_entryKey(item.id))).dy;
        expect(top, greaterThan(previousTop), reason: item.title);
        previousTop = top;
      }

      expect(
        documents.map((DocumentSummary item) => item.id).toList(),
        originalDocumentIds,
      );
      expect(
        templates.map((DocumentSummary item) => item.id).toList(),
        originalTemplateIds,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shows the full title, local dd.MM.yyyy date, and no ellipsis', (
    WidgetTester tester,
  ) async {
    final String longTitle =
        'Sehr langer Titel für ein gescanntes Dokument, der in der Startliste '
        'vollständig sichtbar bleibt und nicht durch Auslassungspunkte ersetzt '
        'wird';
    final DateTime updatedAt = DateTime.utc(2026, 3, 4, 23, 30);
    final DocumentSummary item = _summary(
      id: _uuid(91),
      title: longTitle,
      updatedAt: updatedAt,
      status: StoredItemStatus.saved,
    );

    await tester.pumpWidget(_host(_view(documents: <DocumentSummary>[item])));

    expect(find.text(longTitle), findsOneWidget);
    final Text title = tester.widget<Text>(find.text(longTitle));
    expect(title.maxLines, isNull);
    expect(title.overflow, isNull);

    final String expectedDate = _localDate(updatedAt);
    expect(expectedDate, matches(RegExp(r'^\d{2}\.\d{2}\.\d{4}$')));
    expect(
      find.descendant(
        of: find.byKey(_entryKey(item.id)),
        matching: find.text(_de.lastEdited(expectedDate)),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders all four exact status labels with pinned icons', (
    WidgetTester tester,
  ) async {
    final List<({DocumentSummary item, String label, IconData icon})> cases =
        <({DocumentSummary item, String label, IconData icon})>[
          (
            item: _summary(
              id: _uuid(101),
              title: 'Entwurf',
              updatedAt: _at(hour: 10),
              status: StoredItemStatus.draft,
            ),
            label: _de.statusDraft,
            icon: Icons.edit_outlined,
          ),
          (
            item: _summary(
              id: _uuid(102),
              title: 'Dokument gespeichert',
              updatedAt: _at(hour: 11),
              status: StoredItemStatus.saved,
            ),
            label: _de.durabilityClean,
            icon: Icons.check_circle_outline,
          ),
          (
            item: _summary(
              id: _uuid(103),
              title: 'Dokument exportbereit',
              updatedAt: _at(hour: 12),
              status: StoredItemStatus.exportReady,
            ),
            label: _de.statusExportReady,
            icon: Icons.picture_as_pdf_outlined,
          ),
          (
            item: _summary(
              id: _uuid(104),
              title: 'Unlesbar',
              updatedAt: _at(hour: 13),
              status: StoredItemStatus.unreadable,
            ),
            label: _de.statusUnreadable,
            icon: Icons.error_outline,
          ),
        ];

    await tester.pumpWidget(
      _host(
        _view(
          documents: cases.map((
            ({DocumentSummary item, String label, IconData icon}) entry,
          ) {
            return entry.item;
          }).toList(),
        ),
        height: 1200,
      ),
    );

    for (final ({DocumentSummary item, String label, IconData icon}) entry
        in cases) {
      expect(
        find.descendant(
          of: find.byKey(_entryKey(entry.item.id)),
          matching: find.text(entry.label),
        ),
        findsOneWidget,
        reason: entry.item.title,
      );
      expect(
        find.descendant(
          of: find.byKey(_entryKey(entry.item.id)),
          matching: find.byIcon(entry.icon),
        ),
        findsOneWidget,
        reason: entry.item.title,
      );
    }
    expect(find.text(_de.statusDraft), findsOneWidget);
    expect(find.text(_de.durabilityClean), findsOneWidget);
    expect(find.text(_de.statusExportReady), findsOneWidget);
    expect(find.text(_de.statusUnreadable), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows both empty messages when both groups are empty', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(_view(), height: 700));

    expect(find.text(_de.documentsGroup), findsOneWidget);
    expect(find.text(_de.templatesGroup), findsOneWidget);
    expect(find.text(_de.emptyDocuments), findsOneWidget);
    expect(find.text(_de.emptyTemplates), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('documents empty shows only the documents empty message', (
    WidgetTester tester,
  ) async {
    final DocumentSummary template = _summary(
      id: _uuid(111),
      title: 'Vorlage B',
      updatedAt: _at(hour: 10),
    );

    await tester.pumpWidget(
      _host(_view(templates: <DocumentSummary>[template])),
    );

    expect(find.text(_de.emptyDocuments), findsOneWidget);
    expect(find.text(_de.emptyTemplates), findsNothing);
    expect(find.byKey(_entryKey(template.id)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('templates empty shows only the templates empty message', (
    WidgetTester tester,
  ) async {
    final DocumentSummary document = _summary(
      id: _uuid(112),
      title: 'Dokument B',
      updatedAt: _at(hour: 10),
    );

    await tester.pumpWidget(
      _host(_view(documents: <DocumentSummary>[document])),
    );

    expect(find.text(_de.emptyTemplates), findsOneWidget);
    expect(find.text(_de.emptyDocuments), findsNothing);
    expect(find.byKey(_entryKey(document.id)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open callbacks receive the exact id exactly once', (
    WidgetTester tester,
  ) async {
    final DocumentSummary document = _summary(
      id: _uuid(121),
      title: 'Dokument C',
      updatedAt: _at(hour: 10),
    );
    final DocumentSummary template = _summary(
      id: _uuid(122),
      title: 'Vorlage C',
      updatedAt: _at(hour: 11),
    );
    final List<String> openedDocuments = <String>[];
    final List<String> openedTemplates = <String>[];

    await tester.pumpWidget(
      _host(
        _view(
          documents: <DocumentSummary>[document],
          templates: <DocumentSummary>[template],
          onOpenDocument: openedDocuments.add,
          onOpenTemplate: openedTemplates.add,
        ),
      ),
    );

    await tester.tap(find.byKey(_entryKey(document.id)));
    await tester.pump();

    expect(openedDocuments, <String>[document.id]);
    expect(openedTemplates, isEmpty);

    await tester.tap(find.byKey(_entryKey(template.id)));
    await tester.pump();

    expect(openedTemplates, <String>[template.id]);
    expect(openedDocuments, <String>[document.id]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('optional delete forwards once without invoking open callbacks', (
    WidgetTester tester,
  ) async {
    final DocumentSummary document = _summary(
      id: _uuid(131),
      title: 'Dokument D',
      updatedAt: _at(hour: 10),
    );
    final DocumentSummary template = _summary(
      id: _uuid(132),
      title: 'Vorlage D',
      updatedAt: _at(hour: 11),
    );
    final List<String> openedDocuments = <String>[];
    final List<String> openedTemplates = <String>[];
    final List<String> deleted = <String>[];

    await tester.pumpWidget(
      _host(
        _view(
          documents: <DocumentSummary>[document],
          templates: <DocumentSummary>[template],
          onOpenDocument: openedDocuments.add,
          onOpenTemplate: openedTemplates.add,
          onDelete: deleted.add,
        ),
      ),
    );

    expect(find.byKey(_deleteKey(document.id)), findsOneWidget);
    expect(find.byKey(_deleteKey(template.id)), findsOneWidget);

    final BuildContext entryContext = tester.element(
      find.byKey(_entryKey(document.id)),
    );
    final IconButton deleteButton = tester.widget<IconButton>(
      find.byKey(_deleteKey(document.id)),
    );
    expect(
      deleteButton.tooltip,
      MaterialLocalizations.of(entryContext).deleteButtonTooltip,
    );

    await tester.tap(find.byKey(_deleteKey(document.id)));
    await tester.pump();

    expect(deleted, <String>[document.id]);
    expect(openedDocuments, isEmpty);
    expect(openedTemplates, isEmpty);

    await tester.tap(find.byKey(_deleteKey(template.id)));
    await tester.pump();

    expect(deleted, <String>[document.id, template.id]);
    expect(openedDocuments, isEmpty);
    expect(openedTemplates, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no delete control exists without a delete callback', (
    WidgetTester tester,
  ) async {
    final DocumentSummary document = _summary(
      id: _uuid(141),
      title: 'Dokument E',
      updatedAt: _at(hour: 10),
    );

    await tester.pumpWidget(
      _host(_view(documents: <DocumentSummary>[document])),
    );

    expect(find.byKey(_deleteKey(document.id)), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(_entryKey(document.id)),
        matching: find.byType(IconButton),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stable keys identify both sections and every entry', (
    WidgetTester tester,
  ) async {
    final DocumentSummary document = _summary(
      id: _uuid(151),
      title: 'Dokument F',
      updatedAt: _at(hour: 10),
    );
    final DocumentSummary template = _summary(
      id: _uuid(152),
      title: 'Vorlage F',
      updatedAt: _at(hour: 11),
    );

    await tester.pumpWidget(
      _host(
        _view(
          documents: <DocumentSummary>[document],
          templates: <DocumentSummary>[template],
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('documents-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('templates-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey<String>('stored-item-${document.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey<String>('stored-item-${template.id}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '200 percent text scale reflows at 280 logical pixels without overflow',
    (WidgetTester tester) async {
      final String longTitle =
          'Sehr langer Titel für ein gescanntes Dokument, der auch bei '
          'doppelter Schriftgröße vollständig sichtbar bleibt';
      final List<DocumentSummary> documents = <DocumentSummary>[
        _summary(
          id: _uuid(161),
          title: longTitle,
          updatedAt: _at(hour: 10),
          status: StoredItemStatus.draft,
        ),
        _summary(
          id: _uuid(162),
          title: 'Gespeichertes Dokument',
          updatedAt: _at(hour: 11),
          status: StoredItemStatus.saved,
        ),
        _summary(
          id: _uuid(163),
          title: 'Exportiertes Dokument',
          updatedAt: _at(hour: 12),
          status: StoredItemStatus.exportReady,
        ),
        _summary(
          id: _uuid(164),
          title: 'Nicht lesbares Dokument',
          updatedAt: _at(hour: 13),
          status: StoredItemStatus.unreadable,
        ),
      ];

      _setSurfaceSize(tester, const Size(_narrowWidth, 2400));
      await tester.pumpWidget(
        _host(
          _view(documents: documents),
          textScale: 2.0,
          width: _narrowWidth,
          height: 2400,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text(_de.documentsGroup), findsOneWidget);
      expect(find.text(_de.templatesGroup), findsOneWidget);
      expect(find.text(_de.emptyTemplates), findsOneWidget);

      final Text title = tester.widget<Text>(find.text(longTitle));
      expect(title.maxLines, isNull);
      expect(title.overflow, isNull);

      for (final String label in <String>[
        _de.statusDraft,
        _de.durabilityClean,
        _de.statusExportReady,
        _de.statusUnreadable,
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      for (final IconData icon in <IconData>[
        Icons.edit_outlined,
        Icons.check_circle_outline,
        Icons.picture_as_pdf_outlined,
        Icons.error_outline,
      ]) {
        expect(find.byIcon(icon), findsOneWidget);
      }
    },
  );

  // This case pins the surface contract (keys, ordering, rect containment,
  // scrolling). The ratified 50-entry latency bound lives in
  // `stored_list_50_test.dart` (T097); the overlap is deliberate.
  testWidgets('50 document entries render and the last is reachable', (
    WidgetTester tester,
  ) async {
    final List<DocumentSummary> documents = <DocumentSummary>[
      for (int index = 0; index < 50; index++)
        _summary(
          id: _uuid(1000 + index),
          title: 'Dokument ${index + 1}',
          updatedAt: _at(minute: index),
        ),
    ];
    final ValueKey<String> lastKey = _entryKey(_uuid(1000));

    await tester.pumpWidget(
      _host(_view(documents: documents), width: 400, height: 700),
    );

    expect(tester.takeException(), isNull);
    // The newest entry is visible; lazy viewport rendering (FR-100, T097)
    // means the oldest is not built until the viewport reaches it.
    expect(find.byKey(_entryKey(_uuid(1049))), findsOneWidget);
    expect(find.byKey(lastKey), findsNothing);
    final int builtEntries = tester.widgetList(find.byType(InkWell)).length;
    expect(builtEntries, lessThan(50));
    final Rect viewport = tester.getRect(find.byType(CustomScrollView));
    await tester.scrollUntilVisible(
      find.byKey(lastKey),
      400,
      scrollable: find.byType(Scrollable),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(lastKey), findsOneWidget);
    final Rect lastRect = tester.getRect(find.byKey(lastKey));
    expect(lastRect.top, greaterThanOrEqualTo(viewport.top - 0.5));
    expect(lastRect.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable),
    );
    expect(scrollable.position.pixels, greaterThan(0));
  });

  test('production source stays presentation-only with authorized imports', () {
    final File file = File(
      '${packageRoot.path}/lib/features/start/stored_items.dart',
    );
    expect(file.existsSync(), isTrue);

    final String source = file.readAsStringSync();
    final List<String> imports = RegExp(
      r"^import '([^']+)';",
      multiLine: true,
    ).allMatches(source).map((Match match) => match.group(1)!).toList();

    expect(imports, <String>[
      'package:feldexa_app/l10n/app_localizations.dart',
      'package:feldexa_ports/feldexa_ports.dart',
      'package:flutter/material.dart',
    ]);
    for (final String getter in <String>[
      'l10n.documentsGroup',
      'l10n.templatesGroup',
      'l10n.emptyDocuments',
      'l10n.emptyTemplates',
      'l10n.lastEdited',
      'l10n.statusDraft',
      'l10n.statusExportReady',
      'l10n.statusUnreadable',
      'l10n.durabilityClean',
    ]) {
      expect(source, contains(getter));
    }
    for (final String forbidden in <String>[
      'dart:io',
      'package:http',
      'SecureStorePort',
      'DateTime.now',
      'showDialog',
      'AlertDialog',
      'SharedPreferences',
      'sqflite',
    ]) {
      expect(
        source,
        isNot(contains(forbidden)),
        reason: 'The presentation surface must not reference $forbidden.',
      );
    }
  });
}
