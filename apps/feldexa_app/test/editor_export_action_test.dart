// Issue #334 editor export action tests.
//
// Evidence class: NONE. Host-VM widget tests with injected fake ports and the
// committed font metrics asset; no platform channel, no PDF, and no document
// bytes reach a platform.
//
// They prove the app-bar export action of `contracts/editor-interactions.md`
// §10: the action is enabled only for an exportable document state, the
// pre-export sheet shows the empty-field and the ratified OD-1/Q1=A
// unresolved-suggestion information without blocking, a blocking plan is shown
// and never starts, a verified artifact opens the preview route, and a failure
// shows the catalog sentence.

@TestOn('vm')
library;

import 'dart:async';

import 'package:feldexa_app/features/editor/document_overview.dart'
    show documentOverviewRowKeyPrefix;
import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/features/editor/field_value_sheet.dart'
    show fieldValueSaveKey;
import 'package:feldexa_app/features/editor/page_view.dart' as viewer;
import 'package:feldexa_app/features/export/export_preview.dart';
import 'package:feldexa_app/features/export/export_progress.dart';
import 'package:feldexa_app/features/fill/text_control.dart'
    show fieldTextControlInputKey;
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart' hide PageView;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _documentId = '5f0c3a52-3a6a-4f0b-9c2d-1b7e4d8a6c01';
const String _sourceId = '7b2d4c1e-5f3a-4b8c-8a9d-2e6f0c1b3d42';
const String _revisionId = '9a1b2c3d-4e5f-4a6b-8c7d-8e9f0a1b2c3d';
const String _artifactId = '0a1b2c3d-4e5f-4a6b-8c7d-8e9f0a1b2c3d';
const String _savedRevisionId = '1b2c3d4e-5f6a-4b7c-8d9e-0f1a2b3c4d5e';
const String _confirmedFieldId = '00000000-0000-4000-8000-000000000101';
const String _fieldId = '00000000-0000-4000-8000-000000000001';
const String _noteFieldId = '00000000-0000-4000-8000-000000000002';
final String _sha256 = List<String>.filled(64, 'a').join();
final String _artifactSha256 = List<String>.filled(64, 'b').join();
final Uint8List _sourceBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
final DateTime _at = DateTime.utc(2026, 11, 25, 9);

/// The committed font table, read once: a widget-test fake-async zone never
/// completes an asset-bundle read, so the same table is handed in directly.
late final ExportFontMetrics _metrics;

Future<ExportFontMetrics> _loadMetrics() async => _metrics;

final CapabilityEvidence _noneEvidence = CapabilityEvidence(
  evidenceClass: EvidenceClass.none,
  adapterId: 'test.editor-export-action.v1',
);

final CapabilityDescriptor _storeDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.secureStore,
  adapterId: 'test.editor-export-action.store.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final CapabilityDescriptor _exportDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.pdfExport,
  adapterId: 'test.editor-export-action.export.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final CapabilityDescriptor _deliveryDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.delivery,
  adapterId: 'test.editor-export-action.delivery.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final CapabilityDescriptor _clockDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.clock,
  adapterId: 'test.editor-export-action.clock.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

final CapabilityDescriptor _idsDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.ids,
  adapterId: 'test.editor-export-action.ids.v1',
  version: '1',
  isSimulated: false,
  evidence: _noneEvidence,
);

core.PageGeometry _geometry() {
  return core.PageGeometry(mediaBox: core.Rect.fromLTWH(0, 0, 595.28, 841.89));
}

/// A revision that already ran its first analysis, so the editor opens in the
/// deterministic `analysis-skipped` state and writes nothing.
core.RevisionContent _content({
  Map<String, core.FieldValue>? values,
  bool withSuggestion = false,
  bool overflowing = false,
}) {
  return core.RevisionContent(
    pages: <core.Page>[
      core.Page(
        index: 0,
        geometry: _geometry(),
        analysis: core.AnalysisState.complete,
      ),
    ],
    suggestions: <core.FieldSuggestion>[
      if (withSuggestion)
        core.FieldSuggestion(
          id: 's_p0_0001',
          pageIndex: 0,
          rect: core.Rect.fromLTWH(40, 120, 120, 14),
          proposedType: core.FieldType.text,
          confidence: 0.5,
          labelText: null,
          evidence: core.SuggestionEvidence(
            cues: const <core.SuggestionCue>[core.SuggestionCue.underline],
            ocrUsed: false,
          ),
        ),
    ],
    fields: <core.ConfirmedField>[
      core.ConfirmedField(
        id: _fieldId,
        pageIndex: 0,
        rect: core.Rect.fromLTWH(40, 40, 200, 14),
        type: core.FieldType.text,
        provenance: core.Provenance.user,
        label: 'Name',
        order: 0,
        createdAt: _at,
        updatedAt: _at,
      ),
      core.ConfirmedField(
        id: _noteFieldId,
        pageIndex: 0,
        rect: core.Rect.fromLTWH(40, 80, 200, 14),
        type: core.FieldType.text,
        provenance: core.Provenance.user,
        label: 'Hinweis',
        order: 1,
        createdAt: _at,
        updatedAt: _at,
      ),
    ],
    fieldOrder: const <String>[_fieldId, _noteFieldId],
    values:
        values ??
        <String, core.FieldValue>{
          _fieldId: core.TextValue(
            text: overflowing ? 'a' * 400 : 'Erika Mustermann',
            lastEditedAt: _at,
          ),
        },
  );
}

LoadedDocument _loaded({core.RevisionContent? content}) {
  final core.RevisionContent revision = content ?? _content();
  return LoadedDocument(
    meta: core.DocumentMeta(
      id: _documentId,
      title: 'Antrag',
      createdAt: _at,
      updatedAt: _at,
      source: core.SourceFileRef(
        id: _sourceId,
        sha256: _sha256,
        sizeBytes: _sourceBytes.length,
        pageCount: 1,
        importedAt: _at,
      ),
      latestRevisionId: _revisionId,
      lastDurableAt: _at,
    ),
    content: revision,
    sourceBytes: _sourceBytes,
    evidence: _noneEvidence,
  );
}

ImportedSource _source() {
  return ImportedSource(
    documentId: _documentId,
    sourceId: _sourceId,
    sha256: _sha256,
    sizeBytes: _sourceBytes.length,
    pageCount: 1,
    pages: <core.PageGeometry>[_geometry()],
    pageFailures: const <core.PageFailure>[],
    evidence: _noneEvidence,
  );
}

final class _FakeStore implements SecureStorePort {
  _FakeStore({required this.loaded, this.loadGate});

  LoadedDocument loaded;
  final Completer<void>? loadGate;

  @override
  CapabilityDescriptor get descriptor => _storeDescriptor;

  @override
  Future<LoadedDocument> loadDocument(String documentId) async {
    final Completer<void>? gate = loadGate;
    if (gate != null) {
      await gate.future;
    }
    return loaded;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedOperationException();
  }
}

final class _FakeClock implements ClockPort {
  @override
  CapabilityDescriptor get descriptor => _clockDescriptor;

  @override
  DateTime nowUtc() => _at;
}

final class _FakeIds implements IdPort {
  int _next = 100;

  @override
  CapabilityDescriptor get descriptor => _idsDescriptor;

  @override
  String newId() {
    _next++;
    return '00000000-0000-4000-8000-${_next.toString().padLeft(12, '0')}';
  }

  @override
  String newIdempotencyKey() => newId();
}

final class _FakeExportPort implements PdfExportPort {
  final List<ExportPlan> validated = <ExportPlan>[];
  final List<ExportRequest> exported = <ExportRequest>[];
  final List<String> deleted = <String>[];
  Object? validateError;
  Object? exportError;

  /// Holds [validate] open, so a test can cancel before a render id exists.
  Completer<void>? validateGate;

  /// Holds [export] open, so a test can dispose the editor mid-flight, read the
  /// progress surface, or cancel a running render.
  Completer<void>? exportGate;

  @override
  CapabilityDescriptor get descriptor => _exportDescriptor;

  @override
  Future<ExportValidationResult> validate(ExportPlan plan) async {
    validated.add(plan);
    final Completer<void>? gate = validateGate;
    if (gate != null) {
      await gate.future;
    }
    final Object? failure = validateError;
    if (failure != null) {
      throw failure;
    }
    return ExportValidationResult(
      validation: ExportValidation(
        warnings: const <ExportValidationWarning>[],
        validatedAt: _at,
      ),
      evidence: _noneEvidence,
    );
  }

  @override
  Future<ExportResult> export(ExportRequest request) async {
    exported.add(request);
    final Completer<void>? gate = exportGate;
    if (gate != null) {
      await gate.future;
    }
    final Object? failure = exportError;
    if (failure != null) {
      throw failure;
    }
    return ExportResult(
      artifact:
          ExportArtifact.start(
            id: _artifactId,
            documentId: request.documentId,
            revisionId: request.revisionId,
            pageCount: request.plan.pageCount,
            createdAt: _at,
          ).startRendering().startVerification().succeed(
            byteSize: 4096,
            sha256: _artifactSha256,
            verification: ArtifactVerification(
              pageCountMatches: true,
              mediaBoxesMatch: true,
              fontGlyphsPresent: true,
              noInteractiveFields: true,
              overlayBoundsWithinPage: true,
              checkedAt: _at,
            ),
          ),
      evidence: _noneEvidence,
    );
  }

  @override
  Future<Uint8List> readArtifact(String artifactId) async {
    throw UnsupportedOperationException();
  }

  @override
  Future<void> deleteArtifact(String artifactId) async {
    deleted.add(artifactId);
  }
}

final class _FakeExportOperationControl implements ExportOperationControl {
  _FakeExportOperationControl();

  final StreamController<ExportProgress> _steps =
      StreamController<ExportProgress>.broadcast();

  /// Every cancel request that reached the control.
  final List<void> cancellations = <void>[];

  /// The answer of [cancel]; a test sets it to model a claimed cancellation.
  bool claimed = true;

  @override
  Stream<ExportProgress> get progress => _steps.stream;

  /// Emits one content-free step of the running export.
  void report(ExportPhase phase, double fraction) {
    _steps.add(ExportProgress(phase: phase, fraction: fraction));
  }

  @override
  Future<bool> cancel() async {
    cancellations.add(null);
    return claimed;
  }

  Future<void> close() => _steps.close();
}

final class _FakeDeliveryPort implements DeliveryPort {
  final List<DeliveryAction> actions = <DeliveryAction>[];

  @override
  CapabilityDescriptor get descriptor => _deliveryDescriptor;

  @override
  Future<DeliveryOutcome> deliver({
    required DeliveryAction action,
    required String artifactId,
  }) async {
    actions.add(action);
    return DeliveryOutcome(
      action: action,
      completed: true,
      evidence: _noneEvidence,
    );
  }
}

final class _FakeRuntime implements EditorRuntime {
  _FakeRuntime({required this.fakeStore, _FakeExportPort? exportPort})
    : exportPort = exportPort ?? _FakeExportPort();

  final _FakeStore fakeStore;
  final _FakeExportPort exportPort;
  final _FakeDeliveryPort deliveryPort = _FakeDeliveryPort();
  final _FakeExportOperationControl operationControl =
      _FakeExportOperationControl();
  final List<SensitiveRoute> routes = <SensitiveRoute>[];
  bool disposed = false;

  @override
  SecureStorePort get store => fakeStore;

  @override
  PdfExportPort get export => exportPort;

  @override
  ExportOperationControl get exportOperation => operationControl;

  @override
  DeliveryPort get delivery => deliveryPort;

  @override
  Future<LoadedDocument> loadDocument(String documentId) =>
      fakeStore.loadDocument(documentId);

  /// Every accepted revision; a confirm/reject or value edit lands here.
  final List<SaveRevisionRequest> savedRevisions = <SaveRevisionRequest>[];

  @override
  Future<StoredMeta> saveRevision(SaveRevisionRequest request) async {
    savedRevisions.add(request);
    return StoredMeta(
      id: _documentId,
      kind: StoreKind.document,
      title: 'Antrag',
      createdAt: _at,
      updatedAt: _at,
      latestRevisionId: _savedRevisionId,
      lastDurableAt: _at,
    );
  }

  @override
  IdPort get ids => _FakeIds();

  @override
  ClockPort get clock => _FakeClock();

  @override
  Future<bool> setSensitiveRoute(SensitiveRoute route) async {
    routes.add(route);
    return route.requiresProtection;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedOperationException();
  }
}

/// The terminal `PLT-004` of a claimed cancellation (`platform-channel.md` §9).
final class _CancelledExportException extends FeldexaException {
  _CancelledExportException()
    : super(
        code: 'PLT-004',
        messageKey: 'PLT-004',
        message: 'platform.cancelled',
        retryable: true,
        severity: ErrorSeverity.info,
      );
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

Future<void> _pumpEditor(WidgetTester tester, _FakeRuntime runtime) async {
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
        exportFontMetricsLoader: _loadMetrics,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

IconButton _exportButton(WidgetTester tester) {
  return tester.widget<IconButton>(find.byKey(editorExportActionKey));
}

void main() {
  setUpAll(() async {
    // Issue #318: read the declared asset through the bundle, which
    // flutter_test_config mocks to the app package for repository-root runs,
    // instead of resolving `assets/...` against the invocation directory.
    _metrics = ExportFontMetrics.decode(
      await rootBundle.loadString('assets/fonts/metrics.json'),
    );
  });

  testWidgets('the export action is disabled until the document state is '
      'exportable', (WidgetTester tester) async {
    final Completer<void> loadGate = Completer<void>();
    final _FakeRuntime runtime = _FakeRuntime(
      fakeStore: _FakeStore(loaded: _loaded(), loadGate: loadGate),
    );

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
          exportFontMetricsLoader: _loadMetrics,
        ),
      ),
    );
    await tester.pump();

    expect(_exportButton(tester).onPressed, isNull);

    loadGate.complete();
    await tester.pumpAndSettle();

    expect(_exportButton(tester).onPressed, isNotNull);
  });

  testWidgets('the pre-export sheet shows the OD-1 information without '
      'blocking the export', (WidgetTester tester) async {
    final _FakeRuntime runtime = _FakeRuntime(
      fakeStore: _FakeStore(
        loaded: _loaded(content: _content(withSuggestion: true)),
      ),
    );
    await _pumpEditor(tester, runtime);

    await tester.tap(find.byKey(editorExportActionKey));
    await tester.pumpAndSettle();

    // `Hinweis` is empty and one suggestion is still unreviewed.
    expect(
      find.text(
        '1 Felder sind noch leer. Leere Felder werden nicht '
        'ausgefüllt, der Export bleibt möglich.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        '1 Vorschläge sind noch nicht geprüft. Sie werden nicht in '
        'die PDF-Datei übernommen.',
      ),
      findsOneWidget,
    );
    // The ratified OD-1/Q1=A information does not block: the start action exists.
    expect(
      find.byKey(const ValueKey<String>('export-preflight-start')),
      findsOneWidget,
    );
    expect(runtime.exportPort.exported, isEmpty);
  });

  testWidgets(
    'starting the export opens the preview of the verified artifact',
    (WidgetTester tester) async {
      final _FakeRuntime runtime = _FakeRuntime(
        fakeStore: _FakeStore(loaded: _loaded()),
      );
      await _pumpEditor(tester, runtime);

      await tester.tap(find.byKey(editorExportActionKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('export-preflight-start')),
      );
      await tester.pumpAndSettle();

      expect(runtime.exportPort.validated, hasLength(1));
      expect(runtime.exportPort.exported, hasLength(1));
      expect(find.byKey(exportPreviewRouteKey), findsOneWidget);
      expect(find.text('Seiten: 1'), findsOneWidget);
      expect(find.text('Speichern'), findsOneWidget);
    },
  );

  testWidgets('a blocking plan shows its catalog sentence and starts nothing', (
    WidgetTester tester,
  ) async {
    final _FakeRuntime runtime = _FakeRuntime(
      fakeStore: _FakeStore(
        loaded: _loaded(content: _content(overflowing: true)),
      ),
    );
    await _pumpEditor(tester, runtime);

    await tester.tap(find.byKey(editorExportActionKey));
    await tester.pumpAndSettle();

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    expect(find.text(l10n.exp001(1, 'Name')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('export-preflight-start')),
      findsNothing,
    );
    expect(runtime.exportPort.validated, isEmpty);
    expect(runtime.exportPort.exported, isEmpty);
  });

  testWidgets('a failed export shows the catalog sentence and no preview', (
    WidgetTester tester,
  ) async {
    final _FakeExportPort exportPort = _FakeExportPort()
      ..exportError = ExportFailedException();
    final _FakeRuntime runtime = _FakeRuntime(
      fakeStore: _FakeStore(loaded: _loaded()),
      exportPort: exportPort,
    );
    await _pumpEditor(tester, runtime);

    await tester.tap(find.byKey(editorExportActionKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('export-preflight-start')),
    );
    await tester.pumpAndSettle();

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    expect(find.text(l10n.exp002), findsOneWidget);
    expect(find.byKey(exportPreviewRouteKey), findsNothing);
  });

  testWidgets('cancelling the pre-export sheet exports nothing', (
    WidgetTester tester,
  ) async {
    final _FakeRuntime runtime = _FakeRuntime(
      fakeStore: _FakeStore(loaded: _loaded()),
    );
    await _pumpEditor(tester, runtime);

    await tester.tap(find.byKey(editorExportActionKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('export-preflight-close')),
    );
    await tester.pumpAndSettle();

    expect(runtime.exportPort.validated, isEmpty);
    expect(runtime.exportPort.exported, isEmpty);
    expect(find.byKey(exportPreviewRouteKey), findsNothing);
    expect(_exportButton(tester).onPressed, isNotNull);
  });

  testWidgets(
    'the plan is built from the live revision, not from the loaded snapshot',
    (WidgetTester tester) async {
      // The load carries the pre-edit snapshot: two confirmed fields, one filled
      // value, one unreviewed suggestion. Confirming that suggestion and then
      // filling the new field changes `_content` and `_headRevisionId` only.
      final _FakeRuntime runtime = _FakeRuntime(
        fakeStore: _FakeStore(
          loaded: _loaded(content: _content(withSuggestion: true)),
        ),
      );
      await _pumpEditor(tester, runtime);

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(Scaffold).first),
      );

      // Confirm the unreviewed suggestion: this commits a new revision.
      await tester.tap(find.text(l10n.suggestionConfirmAction).first);
      await tester.pumpAndSettle();
      expect(runtime.savedRevisions, hasLength(1));
      expect(runtime.savedRevisions.single.expectedHead, _revisionId);

      // Fill the newly confirmed field through the document overview, which is
      // the existing path from a field list to its value sheet.
      await tester.tap(find.byKey(editorOverviewActionKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            '$documentOverviewRowKeyPrefix$_confirmedFieldId',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(fieldTextControlInputKey), 'Live-Wert');
      await tester.tap(find.byKey(fieldValueSaveKey));
      await tester.pumpAndSettle();
      expect(runtime.savedRevisions, hasLength(2));

      await tester.tap(find.byKey(editorExportActionKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('export-preflight-start')),
      );
      await tester.pumpAndSettle();

      final ExportPlan plan = runtime.exportPort.validated.single;
      // The export identifies and renders the live revision.
      expect(plan.revisionId, _savedRevisionId);
      expect(runtime.exportPort.exported.single.revisionId, _savedRevisionId);
      expect(<String>[
        for (final ExportPage page in plan.pages)
          for (final ExportOp op in page.ops) op.fieldId,
      ], contains(_confirmedFieldId));
    },
  );

  testWidgets('a blocking plan lists the field page and jumps to the field', (
    WidgetTester tester,
  ) async {
    final _FakeRuntime runtime = _FakeRuntime(
      fakeStore: _FakeStore(
        loaded: _loaded(content: _content(overflowing: true)),
      ),
    );
    await _pumpEditor(tester, runtime);

    await tester.tap(find.byKey(editorExportActionKey));
    await tester.pumpAndSettle();

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    // The blocking field is named with its one-based page (§10 point 2).
    expect(find.text(l10n.suggestionPage(1)), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('export-preflight-fields')),
    );
    await tester.pumpAndSettle();

    // The jump opens exactly the blocking field for filling.
    expect(
      find.byKey(const ValueKey<String>('field-value-sheet-$_fieldId')),
      findsOneWidget,
    );
    expect(runtime.exportPort.validated, isEmpty);
  });

  testWidgets('a failed export offers "Erneut versuchen" and exports again', (
    WidgetTester tester,
  ) async {
    final _FakeExportPort exportPort = _FakeExportPort()
      ..exportError = ExportFailedException();
    final _FakeRuntime runtime = _FakeRuntime(
      fakeStore: _FakeStore(loaded: _loaded()),
      exportPort: exportPort,
    );
    await _pumpEditor(tester, runtime);

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );

    await tester.tap(find.byKey(editorExportActionKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('export-preflight-start')),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.exp002), findsOneWidget);
    expect(exportPort.exported, hasLength(1));

    // The retry action runs the same export action again.
    exportPort.exportError = null;
    await tester.tap(find.text(l10n.actionRetry));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('export-preflight-start')),
    );
    await tester.pumpAndSettle();

    expect(exportPort.exported, hasLength(2));
    expect(find.byKey(exportPreviewRouteKey), findsOneWidget);
  });

  testWidgets('the progress surface shows the reported export phases', (
    WidgetTester tester,
  ) async {
    final _FakeExportPort exportPort = _FakeExportPort()
      ..exportGate = Completer<void>();
    final _FakeRuntime runtime = _FakeRuntime(
      fakeStore: _FakeStore(loaded: _loaded()),
      exportPort: exportPort,
    );
    await _pumpEditor(tester, runtime);

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );

    await tester.tap(find.byKey(editorExportActionKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('export-preflight-start')),
    );
    await tester.pump();

    // `§10` point 3: the surface exists while the render runs and offers the
    // cancel action; no phase text is invented before the first event.
    expect(find.byKey(editorExportProgressKey), findsOneWidget);
    expect(find.byKey(editorExportProgressCancelKey), findsOneWidget);
    expect(find.text(l10n.exportProgressImporting), findsNothing);

    runtime.operationControl.report(ExportPhase.importing, 0.0);
    await tester.pump();
    expect(find.text(l10n.exportProgressImporting), findsOneWidget);

    runtime.operationControl.report(ExportPhase.drawing, 0.4);
    await tester.pump();
    expect(find.text(l10n.exportProgressImporting), findsNothing);
    expect(find.text(l10n.exportProgressDrawing), findsOneWidget);

    runtime.operationControl.report(ExportPhase.verifying, 0.85);
    await tester.pump();
    expect(find.text(l10n.exportProgressVerifying), findsOneWidget);

    runtime.operationControl.report(ExportPhase.finalizing, 0.95);
    await tester.pump();
    expect(find.text(l10n.exportProgressFinalizing), findsOneWidget);

    exportPort.exportGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(editorExportProgressKey), findsNothing);
    expect(find.byKey(exportPreviewRouteKey), findsOneWidget);
  });

  testWidgets('the cancel action cancels the running export once and shows no '
      'error', (WidgetTester tester) async {
    final _FakeExportPort exportPort = _FakeExportPort()
      ..exportGate = Completer<void>();
    final _FakeRuntime runtime = _FakeRuntime(
      fakeStore: _FakeStore(loaded: _loaded()),
      exportPort: exportPort,
    );
    await _pumpEditor(tester, runtime);

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );

    await tester.tap(find.byKey(editorExportActionKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('export-preflight-start')),
    );
    await tester.pump();

    await tester.tap(find.byKey(editorExportProgressCancelKey));
    await tester.pump();
    expect(runtime.operationControl.cancellations, hasLength(1));

    // The platform's terminal answer of a claimed cancellation is `PLT-004`
    // (`platform-channel.md` §9); the native side leaves no artifact.
    exportPort.exportError = _CancelledExportException();
    exportPort.exportGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(editorExportProgressKey), findsNothing);
    expect(find.text(l10n.exp002), findsNothing);
    expect(find.text(l10n.actionRetry), findsNothing);
    expect(find.byKey(exportPreviewRouteKey), findsNothing);
    expect(exportPort.deleted, isEmpty);
    expect(_exportButton(tester).onPressed, isNotNull);
  });

  testWidgets('a render that finished after a claimed cancellation is '
      'discarded, not previewed', (WidgetTester tester) async {
    final _FakeExportPort exportPort = _FakeExportPort()
      ..exportGate = Completer<void>();
    final _FakeRuntime runtime = _FakeRuntime(
      fakeStore: _FakeStore(loaded: _loaded()),
      exportPort: exportPort,
    );
    await _pumpEditor(tester, runtime);

    await tester.tap(find.byKey(editorExportActionKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('export-preflight-start')),
    );
    await tester.pump();
    await tester.tap(find.byKey(editorExportProgressCancelKey));
    await tester.pump();
    expect(runtime.operationControl.cancellations, hasLength(1));

    // The render won the race with the cancellation and reports a verified
    // artifact. It must not reach the preview.
    exportPort.exportGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(exportPreviewRouteKey), findsNothing);
    expect(exportPort.deleted, <String>[_artifactId]);
  });

  testWidgets('a cancel before the render starts is refused and the export '
      'still completes', (WidgetTester tester) async {
    final _FakeExportPort exportPort = _FakeExportPort()
      ..validateGate = Completer<void>();
    final _FakeRuntime runtime = _FakeRuntime(
      fakeStore: _FakeStore(loaded: _loaded()),
      exportPort: exportPort,
    );
    runtime.operationControl.claimed = false;
    await _pumpEditor(tester, runtime);

    await tester.tap(find.byKey(editorExportActionKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('export-preflight-start')),
    );
    await tester.pump();

    // No `export.render` id exists yet, so the platform answers `false` (§9).
    await tester.tap(find.byKey(editorExportProgressCancelKey));
    await tester.pump();
    expect(runtime.operationControl.cancellations, hasLength(1));
    expect(find.byKey(editorExportProgressKey), findsOneWidget);

    exportPort.validateGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(exportPreviewRouteKey), findsOneWidget);
    expect(exportPort.deleted, isEmpty);
  });

  testWidgets('an artifact of an export whose editor was disposed is deleted', (
    WidgetTester tester,
  ) async {
    final _FakeExportPort exportPort = _FakeExportPort()
      ..exportGate = Completer<void>();
    final _FakeRuntime runtime = _FakeRuntime(
      fakeStore: _FakeStore(loaded: _loaded()),
      exportPort: exportPort,
    );
    await _pumpEditor(tester, runtime);

    await tester.tap(find.byKey(editorExportActionKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('export-preflight-start')),
    );
    await tester.pump();
    expect(exportPort.exported, hasLength(1));

    // The route is disposed while the port is still rendering.
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const <Locale>[Locale('de')],
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    exportPort.exportGate!.complete();
    await tester.pumpAndSettle();

    // No preview can own the artifact, so the editor deletes it exactly once.
    expect(exportPort.deleted, <String>[_artifactId]);
    expect(find.byKey(exportPreviewRouteKey), findsNothing);
  });
}
