// T148 US1 import/viewer/page-strip/page-state composition tests.
//
// Evidence class: NONE. These are host-VM widget tests with injected fakes and
// synthetic in-memory sources. They construct no platform channel, open no PDF,
// start no browser, emulator, or device, and make no Android runtime claim.
//
// They prove the composition delivered by T148:
//   * the start surface renders the committed German catalog strings;
//   * an accepted import opens the editor with every page in the strip and
//     resolves the protected bytes through the runtime read-back for the
//     imported documentId (not the opaque viewer sourceId);
//   * a rejection renders the catalog message/recovery with no code and no
//     navigation, and creates no document;
//   * a cancellation returns to the unchanged start surface;
//   * a partial source derives and renders the IMP-006 warning while the
//     affected page is marked unreadable in the strip.

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/page_view.dart';
import 'package:feldexa_app/features/start/import_runtime.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_app/main.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart' hide PageView;
import 'package:flutter_test/flutter_test.dart';

const String _documentId = '5f0c3a52-3a6a-4f0b-9c2d-1b7e4d8a6c01';
const String _sourceId = '7b2d4c1e-5f3a-4b8c-8a9d-2e6f0c1b3d42';
final String _sha256 = List<String>.filled(64, 'a').join();
final Uint8List _pdfBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

final AppLocalizations _de = lookupAppLocalizations(const Locale('de'));

ImportedSource _source({
  int pageCount = 3,
  List<int> unreadablePages = const <int>[],
}) {
  return ImportedSource(
    documentId: _documentId,
    sourceId: _sourceId,
    sha256: _sha256,
    sizeBytes: 4096,
    pageCount: pageCount,
    pages: <core.PageGeometry>[
      for (int index = 0; index < pageCount; index++)
        core.PageGeometry(mediaBox: core.Rect.fromLTWH(0, 0, 595, 842)),
    ],
    pageFailures: <core.PageFailure>[
      for (final int pageIndex in unreadablePages)
        core.PageFailure(
          pageIndex: pageIndex,
          category: core.PageFailureCategory.unreadable,
          messageKey: 'IMP-006',
        ),
    ],
    evidence: CapabilityEvidence.android(adapterId: 'test.fake.import.v1'),
  );
}

/// A fake `DocumentImportPort` that never touches a platform channel.
final class _FakeImportPort implements DocumentImportPort {
  _FakeImportPort.accept(ImportedSource source)
    : _result = ((ImportRequest _) async => source);

  _FakeImportPort.reject(Object error)
    : _result = ((ImportRequest _) async => throw error);

  final Future<ImportedSource> Function(ImportRequest request) _result;
  int calls = 0;

  static final CapabilityDescriptor _descriptor = CapabilityDescriptor(
    kind: CapabilityKind.documentImport,
    adapterId: 'test.fake.import.v1',
    version: '1',
    isSimulated: false,
    evidence: CapabilityEvidence.android(adapterId: 'test.fake.import.v1'),
    supportedFeatures: const <String>['fake-import'],
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  @override
  Future<ImportedSource> pickAndImport(ImportRequest request) {
    calls++;
    return _result(request);
  }

  @override
  Future<SourceIntegrity> verifySource(String sourceId) {
    throw UnsupportedOperationException();
  }
}

ImportRuntime _runtimeFor(
  _FakeImportPort port, {
  required List<String> readDocumentIds,
}) {
  return ImportRuntime(
    importPort: port,
    readSourceBytes: (String documentId) async {
      readDocumentIds.add(documentId);
      return _pdfBytes;
    },
  );
}

/// A fake renderer seam: no PDFium, no platform view, no file.
final class _FakeRendererFactory {
  _FakeRendererFactory(this.pageCount);

  final int pageCount;
  int calls = 0;
  Uint8List? lastBytes;

  Future<PageViewRenderer> call(Uint8List bytes) async {
    calls++;
    lastBytes = bytes;
    return _FakePageRenderer(pageCount);
  }
}

final class _FakePageRenderer implements PageViewRenderer {
  _FakePageRenderer(this.pageCount);

  @override
  final int pageCount;

  @override
  Widget buildPage(
    BuildContext context,
    int pageIndex, {
    required ValueChanged<PageViewLoadException> onFailure,
  }) {
    return ColoredBox(
      key: ValueKey<String>('fake-page-$pageIndex'),
      color: const Color(0xFF00FF00),
    );
  }

  @override
  Future<void> dispose() async {}
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required _FakeImportPort port,
  required _FakeRendererFactory rendererFactory,
  required List<String> readDocumentIds,
}) async {
  await tester.pumpWidget(
    FeldexaApp(
      importRuntimeFactory: () =>
          _runtimeFor(port, readDocumentIds: readDocumentIds),
      pageRendererFactory: rendererFactory.call,
    ),
  );
}

Future<void> _tapImport(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('import-action')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('start surface renders the committed German catalog strings', (
    tester,
  ) async {
    final _FakeRendererFactory rendererFactory = _FakeRendererFactory(1);
    await _pumpApp(
      tester,
      port: _FakeImportPort.accept(_source(pageCount: 1)),
      rendererFactory: rendererFactory,
      readDocumentIds: <String>[],
    );

    expect(find.byKey(const ValueKey<String>('start-screen')), findsOneWidget);
    expect(find.text(_de.appTitle), findsOneWidget);
    expect(find.text(_de.startTitle), findsOneWidget);
    expect(find.text(_de.emptyDocuments), findsOneWidget);
    expect(find.text(_de.importAction), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('editor-screen')), findsNothing);
    expect(rendererFactory.calls, 0);
  });

  testWidgets(
    'accepted import opens the editor, lists every page, and reads the '
    'protected source for the imported documentId',
    (tester) async {
      final _FakeRendererFactory rendererFactory = _FakeRendererFactory(3);
      final _FakeImportPort port = _FakeImportPort.accept(_source());
      final List<String> readDocumentIds = <String>[];

      await _pumpApp(
        tester,
        port: port,
        rendererFactory: rendererFactory,
        readDocumentIds: readDocumentIds,
      );
      await _tapImport(tester);

      expect(port.calls, 1);
      expect(
        find.byKey(const ValueKey<String>('editor-screen')),
        findsOneWidget,
      );
      expect(find.byType(EditorScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('page-strip-page-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('page-strip-page-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('page-strip-page-3')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('imp006-warning')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey<String>('start-screen')), findsNothing);
      expect(readDocumentIds, <String>[_documentId]);
      expect(readDocumentIds, isNot(contains(_sourceId)));
      expect(rendererFactory.calls, 1);
      expect(rendererFactory.lastBytes, _pdfBytes);
    },
  );

  testWidgets(
    'a rejection shows catalog text without a code or navigation and creates '
    'no document',
    (tester) async {
      final _FakeRendererFactory rendererFactory = _FakeRendererFactory(1);
      final _FakeImportPort port = _FakeImportPort.reject(
        ImportRejectedException(ImportRejectionKind.passwordProtected),
      );

      await _pumpApp(
        tester,
        port: port,
        rendererFactory: rendererFactory,
        readDocumentIds: <String>[],
      );
      await _tapImport(tester);

      expect(
        find.byKey(const ValueKey<String>('start-screen')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('import-failure')),
        findsOneWidget,
      );
      expect(find.text(_de.imp001), findsOneWidget);
      expect(find.text(_de.imp001Recovery), findsOneWidget);
      expect(find.textContaining('IMP-001'), findsNothing);
      expect(
        find.textContaining('import.rejected.passwordProtected'),
        findsNothing,
      );
      expect(find.byKey(const ValueKey<String>('editor-screen')), findsNothing);
      expect(rendererFactory.calls, 0);
    },
  );

  testWidgets('a cancelled picker returns to the start surface with no text', (
    tester,
  ) async {
    final _FakeRendererFactory rendererFactory = _FakeRendererFactory(1);
    final _FakeImportPort port = _FakeImportPort.reject(
      ImportCancelledException(),
    );

    await _pumpApp(
      tester,
      port: port,
      rendererFactory: rendererFactory,
      readDocumentIds: <String>[],
    );
    await _tapImport(tester);

    expect(find.byKey(const ValueKey<String>('start-screen')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('import-failure')), findsNothing);
    expect(find.byKey(const ValueKey<String>('editor-screen')), findsNothing);
    expect(find.text(_de.startTitle), findsOneWidget);
    expect(rendererFactory.calls, 0);
  });

  testWidgets(
    'a partial source derives the IMP-006 warning and marks the affected page '
    'unreadable',
    (tester) async {
      final _FakeRendererFactory rendererFactory = _FakeRendererFactory(2);
      final _FakeImportPort port = _FakeImportPort.accept(
        _source(pageCount: 2, unreadablePages: <int>[1]),
      );

      await _pumpApp(
        tester,
        port: port,
        rendererFactory: rendererFactory,
        readDocumentIds: <String>[],
      );
      await _tapImport(tester);

      expect(
        find.byKey(const ValueKey<String>('editor-screen')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('imp006-warning')),
        findsOneWidget,
      );
      expect(find.text(_de.imp006('2')), findsOneWidget);
      expect(find.text(_de.imp006Recovery), findsOneWidget);
      expect(find.text(_de.statusUnreadable), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('page-strip-page-2')),
        findsOneWidget,
      );
      expect(rendererFactory.calls, 1);
    },
  );
}
