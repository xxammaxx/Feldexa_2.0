// Issue #334 export preview tests.
//
// Evidence class: NONE. Host-VM widget tests with injected fake ports; no
// platform channel, no PDF, no path, no URI, and no artifact bytes are
// involved.
//
// They prove the preview contract of `contracts/editor-interactions.md` §10
// points 4–6 and `contracts/platform-channel.md` §7/§11 point 7: the page count
// and byte size of the verified artifact are shown, the four ARB actions exist,
// each action is one delivery port call, a cancellation is not an error, the
// artifact is deleted when the route is left and when the platform detaches the
// view, and the export route applies `FLAG_SECURE` through the runtime.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/export/export_preview.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart' hide PageView;
import 'package:flutter_test/flutter_test.dart';

const String _artifactId = '0a1b2c3d-4e5f-4a6b-8c7d-8e9f0a1b2c3d';
const String _documentId = '5f0c3a52-3a6a-4f0b-9c2d-1b7e4d8a6c01';
const String _revisionId = '9a1b2c3d-4e5f-4a6b-8c7d-8e9f0a1b2c3d';
final String _artifactSha256 = List<String>.filled(64, 'b').join();
final DateTime _at = DateTime.utc(2026, 11, 25, 9);

final CapabilityEvidence _noneEvidence = CapabilityEvidence(
  evidenceClass: EvidenceClass.none,
  adapterId: 'test.export-preview.v1',
);

final CapabilityDescriptor _exportDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.pdfExport,
  adapterId: 'test.export-preview.export.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final CapabilityDescriptor _deliveryDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.delivery,
  adapterId: 'test.export-preview.delivery.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

ExportArtifact _artifact({int byteSize = 4096, int pageCount = 2}) {
  return ExportArtifact.start(
    id: _artifactId,
    documentId: _documentId,
    revisionId: _revisionId,
    pageCount: pageCount,
    createdAt: _at,
  ).startRendering().startVerification().succeed(
    byteSize: byteSize,
    sha256: _artifactSha256,
    verification: ArtifactVerification(
      pageCountMatches: true,
      mediaBoxesMatch: true,
      fontGlyphsPresent: true,
      noInteractiveFields: true,
      overlayBoundsWithinPage: true,
      checkedAt: _at,
    ),
  );
}

final class _FakeExportPort implements PdfExportPort {
  final List<String> deleted = <String>[];
  Object? deleteError;

  @override
  CapabilityDescriptor get descriptor => _exportDescriptor;

  @override
  Future<ExportValidationResult> validate(ExportPlan plan) async {
    throw UnsupportedOperationException();
  }

  @override
  Future<ExportResult> export(ExportRequest request) async {
    throw UnsupportedOperationException();
  }

  @override
  Future<Uint8List> readArtifact(String artifactId) async {
    throw UnsupportedOperationException();
  }

  @override
  Future<void> deleteArtifact(String artifactId) async {
    deleted.add(artifactId);
    final Object? failure = deleteError;
    if (failure != null) {
      throw failure;
    }
  }
}

final class _FakeDeliveryPort implements DeliveryPort {
  _FakeDeliveryPort({this.completed = true, this.failure});

  bool completed;
  Object? failure;
  final List<DeliveryAction> actions = <DeliveryAction>[];
  final List<String> artifactIds = <String>[];

  @override
  CapabilityDescriptor get descriptor => _deliveryDescriptor;

  @override
  Future<DeliveryOutcome> deliver({
    required DeliveryAction action,
    required String artifactId,
  }) async {
    actions.add(action);
    artifactIds.add(artifactId);
    final Object? error = failure;
    if (error != null) {
      throw error;
    }
    return DeliveryOutcome(
      action: action,
      completed: completed,
      userVisibleLocationHint: completed ? 'In „Downloads“ gespeichert' : null,
      evidence: _noneEvidence,
    );
  }
}

final class _FakeRuntime implements EditorRuntime {
  _FakeRuntime({_FakeExportPort? exportPort, _FakeDeliveryPort? deliveryPort})
    : exportPort = exportPort ?? _FakeExportPort(),
      deliveryPort = deliveryPort ?? _FakeDeliveryPort();

  final _FakeExportPort exportPort;
  final _FakeDeliveryPort deliveryPort;
  final List<SensitiveRoute> routes = <SensitiveRoute>[];
  Object? sensitiveRouteError;

  @override
  PdfExportPort get export => exportPort;

  @override
  DeliveryPort get delivery => deliveryPort;

  @override
  Future<bool> setSensitiveRoute(SensitiveRoute route) async {
    routes.add(route);
    final Object? failure = sensitiveRouteError;
    if (failure != null) {
      throw failure;
    }
    return route.requiresProtection;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedOperationException();
  }
}

/// Opens the preview as a pushed route, so closing it really leaves it.
Future<void> _pumpPreview(
  WidgetTester tester,
  _FakeRuntime runtime, {
  ExportArtifact? artifact,
}) async {
  final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const <Locale>[Locale('de')],
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  );
  unawaited(
    navigator.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ExportPreviewScreen(
          runtime: runtime,
          artifact: artifact ?? _artifact(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the page count, the size, and the four actions', (
    WidgetTester tester,
  ) async {
    final _FakeRuntime runtime = _FakeRuntime();

    await _pumpPreview(tester, runtime);

    expect(find.text('Seiten: 2'), findsOneWidget);
    expect(find.text('Dateigröße: 4,0 kB'), findsOneWidget);
    expect(find.text('Speichern'), findsOneWidget);
    expect(find.text('Teilen'), findsOneWidget);
    expect(find.text('Drucken'), findsOneWidget);
    expect(find.text('Schließen'), findsOneWidget);
  });

  testWidgets('formats the byte size with a German decimal comma', (
    WidgetTester tester,
  ) async {
    expect(formatExportByteSize(512), '512 B');
    expect(formatExportByteSize(1536), '1,5 kB');
    expect(formatExportByteSize(3 * 1024 * 1024), '3,0 MB');

    await _pumpPreview(
      tester,
      _FakeRuntime(),
      artifact: _artifact(byteSize: 3 * 1024 * 1024),
    );
    expect(find.text('Dateigröße: 3,0 MB'), findsOneWidget);
  });

  testWidgets('each action is one delivery call for this artifact', (
    WidgetTester tester,
  ) async {
    final _FakeRuntime runtime = _FakeRuntime();
    await _pumpPreview(tester, runtime);

    await tester.tap(find.byKey(const ValueKey<String>('export-preview-save')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('export-preview-share')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('export-preview-print')),
    );
    await tester.pumpAndSettle();

    expect(runtime.deliveryPort.actions, <DeliveryAction>[
      DeliveryAction.save,
      DeliveryAction.share,
      DeliveryAction.print,
    ]);
    expect(runtime.deliveryPort.artifactIds, everyElement(_artifactId));
    expect(find.text('In „Downloads“ gespeichert'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>(exportPreviewDeliveryFailedKey)),
      findsNothing,
    );
  });

  testWidgets('a cancelled hand-off is not an error', (
    WidgetTester tester,
  ) async {
    final _FakeRuntime runtime = _FakeRuntime(
      deliveryPort: _FakeDeliveryPort(completed: false),
    );
    await _pumpPreview(tester, runtime);

    await tester.tap(
      find.byKey(const ValueKey<String>('export-preview-print')),
    );
    await tester.pumpAndSettle();

    expect(runtime.deliveryPort.actions, <DeliveryAction>[
      DeliveryAction.print,
    ]);
    expect(
      find.byKey(const ValueKey<String>(exportPreviewDeliveryFailedKey)),
      findsNothing,
    );
  });

  testWidgets('a failed hand-off leaves a content-free state and no sentence', (
    WidgetTester tester,
  ) async {
    final _FakeRuntime runtime = _FakeRuntime(
      deliveryPort: _FakeDeliveryPort(failure: UnsupportedOperationException()),
    );
    await _pumpPreview(tester, runtime);

    await tester.tap(find.byKey(const ValueKey<String>('export-preview-save')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>(exportPreviewDeliveryFailedKey)),
      findsOneWidget,
    );
    // The catalog has no German sentence for a delivery failure, so none is
    // invented; the actions stay available for a retry.
    expect(find.text('Speichern'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Speichern'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('the export route protects the window and the editor route '
      'takes over after leaving', (WidgetTester tester) async {
    final _FakeRuntime runtime = _FakeRuntime();

    await _pumpPreview(tester, runtime);

    expect(runtime.routes, <SensitiveRoute>[SensitiveRoute.export]);
    expect(runtime.exportPort.deleted, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey<String>('export-preview-close')),
    );
    await tester.pumpAndSettle();

    expect(runtime.exportPort.deleted, <String>[_artifactId]);
    expect(runtime.routes, <SensitiveRoute>[
      SensitiveRoute.export,
      SensitiveRoute.editor,
    ]);
  });

  testWidgets('closing deletes the artifact exactly once', (
    WidgetTester tester,
  ) async {
    final _FakeRuntime runtime = _FakeRuntime();
    await _pumpPreview(tester, runtime);

    await tester.tap(
      find.byKey(const ValueKey<String>('export-preview-close')),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(runtime.exportPort.deleted, <String>[_artifactId]);
  });

  testWidgets('a detached view deletes the artifact', (
    WidgetTester tester,
  ) async {
    final _FakeRuntime runtime = _FakeRuntime();
    await _pumpPreview(tester, runtime);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pumpAndSettle();

    expect(runtime.exportPort.deleted, <String>[_artifactId]);
  });

  testWidgets('a failing delete is never reported as a successful one', (
    WidgetTester tester,
  ) async {
    final _FakeExportPort exportPort = _FakeExportPort()
      ..deleteError = UnsupportedOperationException();
    final _FakeRuntime runtime = _FakeRuntime(exportPort: exportPort);

    await _pumpPreview(tester, runtime);
    await tester.tap(
      find.byKey(const ValueKey<String>('export-preview-close')),
    );
    await tester.pumpAndSettle();

    // The delete was attempted and the failure stayed inside the preview: the
    // route was still left (the editor route is re-applied) and nothing claims
    // a successful delete.
    expect(exportPort.deleted, <String>[_artifactId]);
    expect(runtime.routes, <SensitiveRoute>[
      SensitiveRoute.export,
      SensitiveRoute.editor,
    ]);
  });

  testWidgets('a failing sensitive route keeps the preview usable', (
    WidgetTester tester,
  ) async {
    final _FakeRuntime runtime = _FakeRuntime()
      ..sensitiveRouteError = UnsupportedOperationException();

    await _pumpPreview(tester, runtime);

    expect(runtime.routes, <SensitiveRoute>[SensitiveRoute.export]);
    expect(find.text('Speichern'), findsOneWidget);
  });
}
