// Issue #334 `FLAG_SECURE` caller tests (`contracts/platform-channel.md` §11
// point 7).
//
// Evidence class: NONE. Host-VM widget tests with a fake runtime; no platform
// channel and no Android window exist here, so the flag itself is not observed —
// only the Dart caller contract is.
//
// They prove the chosen fail-safe variant: entering the editor route requests
// the protection, a `false` answer or a thrown call keeps the editor usable and
// is never read as "protected", and leaving the editor clears the flag before
// the runtime is disposed.

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/page_view.dart' as viewer;
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart' hide PageView;
import 'package:flutter_test/flutter_test.dart';

const String _documentId = '5f0c3a52-3a6a-4f0b-9c2d-1b7e4d8a6c01';
const String _sourceId = '7b2d4c1e-5f3a-4b8c-8a9d-2e6f0c1b3d42';
final String _sha256 = List<String>.filled(64, 'a').join();
final Uint8List _sourceBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

final CapabilityEvidence _noneEvidence = CapabilityEvidence(
  evidenceClass: EvidenceClass.none,
  adapterId: 'test.sensitive-route.v1',
);

final class _RouteRuntime implements EditorRuntime {
  _RouteRuntime({this.applied = true, this.failure});

  /// The read-back state the fake reports.
  bool applied;

  /// When set, every `setSensitiveRoute` call throws it.
  Object? failure;

  final List<SensitiveRoute> routes = <SensitiveRoute>[];
  bool disposed = false;

  /// Records the order of the two teardown steps.
  final List<String> calls = <String>[];

  @override
  Future<bool> setSensitiveRoute(SensitiveRoute route) async {
    routes.add(route);
    calls.add('route:${route.wireName}');
    final Object? error = failure;
    if (error != null) {
      throw error;
    }
    return applied;
  }

  /// The editor has no revision store here; the US1 viewer still opens through
  /// its own source-bytes closure and no analysis, save, or export is invented.
  @override
  Future<LoadedDocument> loadDocument(String documentId) async {
    throw UnsupportedOperationException();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    calls.add('dispose');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedOperationException();
  }
}

final class _FakePageRenderer implements viewer.PageViewRenderer {
  @override
  int get pageCount => 1;

  @override
  Widget buildPage(
    BuildContext context,
    int pageIndex, {
    required ValueChanged<viewer.PageViewLoadException> onFailure,
  }) {
    return ColoredBox(
      key: ValueKey<String>('fake-page-$pageIndex'),
      color: const Color(0xFF00FF00),
    );
  }

  @override
  Future<void> dispose() async {}
}

Future<viewer.PageViewRenderer> _renderer(Uint8List bytes) async {
  return _FakePageRenderer();
}

ImportedSource _source() {
  return ImportedSource(
    documentId: _documentId,
    sourceId: _sourceId,
    sha256: _sha256,
    sizeBytes: _sourceBytes.length,
    pageCount: 1,
    pages: <core.PageGeometry>[
      core.PageGeometry(mediaBox: core.Rect.fromLTWH(0, 0, 595.28, 841.89)),
    ],
    pageFailures: const <core.PageFailure>[],
    evidence: _noneEvidence,
  );
}

Future<void> _pumpEditor(WidgetTester tester, _RouteRuntime runtime) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const <Locale>[Locale('de')],
      home: EditorScreen(
        source: _source(),
        sourceBytes: (String _) async => _sourceBytes,
        runtime: runtime,
        rendererFactory: _renderer,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _unprotectedMarker =>
    find.byKey(const ValueKey<String>(editorSensitiveRouteUnprotectedKey));

void main() {
  testWidgets('entering the editor requests the editor route protection', (
    WidgetTester tester,
  ) async {
    final _RouteRuntime runtime = _RouteRuntime();

    await _pumpEditor(tester, runtime);

    expect(runtime.routes, <SensitiveRoute>[SensitiveRoute.editor]);
    expect(_unprotectedMarker, findsNothing);
  });

  testWidgets('a not-applied protection keeps the editor usable and is never '
      'read as protected', (WidgetTester tester) async {
    final _RouteRuntime runtime = _RouteRuntime(applied: false);

    await _pumpEditor(tester, runtime);

    expect(runtime.routes, <SensitiveRoute>[SensitiveRoute.editor]);
    expect(_unprotectedMarker, findsOneWidget);
    // The editor itself is fully available: the page view and the app bar
    // actions exist.
    expect(find.byKey(const ValueKey<String>('editor-page-view')), findsOne);
    expect(find.byKey(editorOverviewActionKey), findsOne);
  });

  testWidgets('a failing sensitive route never blocks the editor', (
    WidgetTester tester,
  ) async {
    final _RouteRuntime runtime = _RouteRuntime(
      failure: UnsupportedOperationException(),
    );

    await _pumpEditor(tester, runtime);

    expect(runtime.routes, <SensitiveRoute>[SensitiveRoute.editor]);
    expect(_unprotectedMarker, findsOneWidget);
    expect(find.byKey(const ValueKey<String>('editor-page-view')), findsOne);
  });

  testWidgets('leaving the editor clears the flag before the runtime is '
      'disposed', (WidgetTester tester) async {
    final _RouteRuntime runtime = _RouteRuntime();
    await _pumpEditor(tester, runtime);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(runtime.routes, <SensitiveRoute>[
      SensitiveRoute.editor,
      SensitiveRoute.none,
    ]);
    expect(runtime.calls, <String>['route:editor', 'route:none', 'dispose']);
    expect(runtime.disposed, isTrue);
  });
}
