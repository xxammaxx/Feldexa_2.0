// T047 SIMULATED browser import journey.
//
// Runs the German import flow in a real Chrome browser against the committed
// deterministic fixture catalogue and the T028 SIMULATED import adapter. It
// proves the browser import journey and its SIMULATED labels; it is not
// Android runtime evidence (FR-086/FR-087/FR-088).
//
// The file lives under `integration_test/` because T047 owns that path, but it
// is a `flutter_test` browser test rather than an `integration_test` device
// driver. `flutter test --platform chrome` cannot compile a test file outside
// `test/` directly: its generated entrypoint imports
// `org-dartlang-app:///../integration_test/...` and the browser test server
// does not serve that path. The committed host/browser copy
// `test/web_import_browser_entry_test.dart` carries the identical suite (the
// T062 "no symlink" rule; `.specify/init-options.json` sets
// `allow_symlinks: false`), so the browser runner compiles the same journey
// from `test/`. The headless
// browser lane was unblocked on 2026-11-28 (test bootstrap `kIsWeb` guard);
// the working command is:
//
//   dart run tools/corpus/synthetic/serve_web_fixtures.dart \
//     --root apps/feldexa_app/web --port 8765
//   cd apps/feldexa_app
//   flutter test --no-pub --platform chrome test/web_import_browser_entry_test.dart
//
// The fixture server is a loopback-only, no-cache static mirror of the
// committed `apps/feldexa_app/web/fixtures/` files. No product backend and no
// external network are used. Without the server the tests fail instead of
// silently skipping; a skipped run is not evidence.
//
// `dart:html` is used intentionally: this file only compiles for the browser,
// and the app does not take a dependency on a web interop package.

// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

@TestOn('browser')
library;

import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_app/features/start/import_error_mapper.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_app/l10n/app_localizations_de.dart';
import 'package:feldexa_app/platform/registry.dart';
import 'package:feldexa_app/platform/registry_web.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Loopback base URL of the committed fixture mirror.
const String _fixtureBaseUrl = String.fromEnvironment(
  'FIXTURE_BASE_URL',
  defaultValue: 'http://127.0.0.1:8765',
);

const String _fixturePrerequisite =
    'the committed fixture mirror must be served on 127.0.0.1:8765 with '
    'dart run tools/corpus/synthetic/serve_web_fixtures.dart '
    '--root apps/feldexa_app/web --port 8765';

Map<String, Object?> _map(Object? value) {
  return (value as Map<Object?, Object?>).cast<String, Object?>();
}

List<Object?> _list(Object? value) => value as List<Object?>;

Future<Uint8List> _fetch(String path) async {
  final html.HttpRequest request = await html.HttpRequest.request(
    '$_fixtureBaseUrl/fixtures/$path',
    method: 'GET',
    responseType: 'arraybuffer',
  );
  if (request.status != 200) {
    throw StateError(
      'GET $path failed with HTTP ${request.status}; $_fixturePrerequisite',
    );
  }
  final Object? response = request.response;
  if (response is ByteBuffer) {
    return response.asUint8List();
  }
  if (response is Uint8List) {
    return response;
  }
  throw StateError(
    'GET $path returned unexpected ${response.runtimeType}; '
    '$_fixturePrerequisite',
  );
}

Future<Map<String, Object?>> _fetchJson(String path) async {
  return _map(jsonDecode(utf8.decode(await _fetch(path))));
}

/// Loads and verifies the committed fixture catalogue in the browser.
///
/// `SimulatedFixtureCatalog.parse` re-checks every SHA-256 and byte size pin,
/// the page geometry, the typed rejection expectations, and the expected-OCR
/// shapes. A drifting fixture therefore fails before an import runs.
Future<SimulatedFixtureCatalog> _loadCatalog() async {
  final Map<String, Object?> catalog = await _fetchJson('catalog.json');
  final Map<String, Uint8List> pdfBytes = <String, Uint8List>{};
  final Map<String, Map<String, Object?>> expectedOcr =
      <String, Map<String, Object?>>{};
  for (final Object? value in _list(catalog['fixtures'])) {
    final Map<String, Object?> fixture = _map(value);
    final String id = fixture['id'] as String;
    pdfBytes[id] = await _fetch('$id.pdf');
    final Object? ocr = fixture['expectedOcr'];
    if (ocr != null) {
      expectedOcr[id] = await _fetchJson('$id.expected-ocr.json');
    }
  }
  return SimulatedFixtureCatalog.parse(
    catalogJson: jsonEncode(catalog),
    pdfBytesById: pdfBytes,
    expectedOcrById: expectedOcr,
  );
}

void main() {
  // The browser integration lane runs this file through `flutter drive`
  // (test_driver/integration_test.dart), whose result channel is served by
  // the integration_test binding; a plain test binding would leave the
  // driver without a verdict.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'loads the committed deterministic SIMULATED fixture catalogue',
    () async {
      final SimulatedFixtureCatalog catalog = await _loadCatalog();

      expect(catalog.catalogVersion, 'fixtures-1.1.0');
      expect(catalog.fixtures, hasLength(8));
      expect(catalog.ids, <String>[
        'sf-001',
        'sf-002',
        'sf-003',
        'sf-004',
        'sf-005',
        'sf-protected',
        'sf-truncated',
        'sf-not-a-pdf',
      ]);
      expect(
        catalog.fixtures.where((SimulatedFixture value) => value.isImportable),
        hasLength(5),
      );
      expect(catalog.fixture('sf-003').pageCount, 5);
      expect(catalog.fixture('sf-003').role, SimulatedFixtureRole.geometry);
      expect(catalog.fixture('sf-protected').expectedErrorCode, 'IMP-001');
      expect(catalog.fixture('sf-truncated').expectedErrorCode, 'IMP-002');
      expect(catalog.fixture('sf-not-a-pdf').expectedErrorCode, 'IMP-004');
    },
  );

  test(
    'imports sf-003 through the SIMULATED adapter with page order and geometry',
    () async {
      final SimulatedFixtureCatalog catalog = await _loadCatalog();
      final SimulatedFixture fixture = catalog.fixture('sf-003');
      final SimulatedBackend backend = SimulatedBackend();
      final SimulatedDocumentImportAdapter adapter =
          SimulatedDocumentImportAdapter(backend: backend, catalog: catalog);
      final AppLocalizations l10n = AppLocalizationsDe();
      final List<ImportedSource> created = <ImportedSource>[];
      final ImportFlow flow = ImportFlow(
        localizations: l10n,
        createDocument: (ImportedDocumentCandidate candidate) async {
          created.add(candidate.source);
        },
      );

      adapter.picker.enqueueFixture('sf-003');
      final ImportOutcome outcome = await flow.run(
        port: adapter,
        request: ImportRequest(),
      );

      expect(outcome, isA<ImportAccepted>());
      final ImportAccepted accepted = outcome as ImportAccepted;
      expect(accepted.warning, isNull);
      expect(created, hasLength(1));

      final ImportedSource source = accepted.document.source;
      expect(identical(source, created.single), isTrue);
      expect(source.displayName, 'sf-003.pdf');
      expect(source.pageCount, 5);
      expect(source.pages, hasLength(5));
      expect(source.sha256, fixture.sha256);
      expect(source.sizeBytes, fixture.sizeBytes);
      expect(source.pageFailures, isEmpty);
      expect(source.evidence.evidenceClass, EvidenceClass.simulated);
      expect(source.evidence.simulated, isTrue);
      expect(source.evidence.evidenceClass.isAndroid, isFalse);
      expect(source.evidence.adapterId, simulatedImportAdapterId);
      expect(source.evidence.simulatedReason, simulatedReasonToken);

      // Page order is the returned list order; geometry is the catalogue's
      // declared display size after rotation, including the 90/180/270 pages.
      for (int index = 0; index < fixture.pages.length; index++) {
        final SimulatedFixturePage expected = fixture.pages[index];
        final PageGeometry actual = source.pages[index];
        expect(
          actual.rotation,
          expected.rotation,
          reason: 'page $index rotation',
        );
        expect(
          actual.displaySize.width,
          closeTo(expected.widthPt, 0.01),
          reason: 'page $index display width',
        );
        expect(
          actual.displaySize.height,
          closeTo(expected.heightPt, 0.01),
          reason: 'page $index display height',
        );
      }

      final SimulatedStagedSource? staged = backend.stagedSource(
        source.sourceId,
      );
      expect(staged, isNotNull);
      expect(staged!.fixtureId, 'sf-003');
      expect(staged.sha256, fixture.sha256);
      expect(staged.bytes, equals(fixture.bytes));
      expect(sha256.convert(staged.bytes).toString(), fixture.sha256);

      expect(backend.documents, hasLength(1));
      final SimulatedDocumentRecord? record =
          backend.documents[source.documentId];
      expect(record, isNotNull);
      expect(record!.id, source.documentId);
      expect(record.title, fixture.title);
      expect(record.source.sha256, fixture.sha256);
      expect(record.source.pageCount, 5);

      final SourceIntegrity integrity = await adapter.verifySource(
        source.sourceId,
      );
      expect(integrity.readable, isTrue);
      expect(integrity.actualSha256, fixture.sha256);
      expect(integrity.pageCount, 5);
      expect(integrity.evidence.evidenceClass, EvidenceClass.simulated);
      expect(adapter.picker.isEmpty, isTrue);
    },
  );

  test('rejects every failure fixture with the exact German text and no stored record', () async {
    final SimulatedFixtureCatalog catalog = await _loadCatalog();
    final AppLocalizations l10n = AppLocalizationsDe();
    final List<_RejectionCase> cases = <_RejectionCase>[
      _RejectionCase(
        fixtureId: 'sf-protected',
        code: 'IMP-001',
        message: l10n.imp001,
        recovery: l10n.imp001Recovery,
        password: true,
      ),
      _RejectionCase(
        fixtureId: 'sf-truncated',
        code: 'IMP-002',
        message: l10n.imp002,
        recovery: l10n.imp002Recovery,
        password: false,
      ),
      _RejectionCase(
        fixtureId: 'sf-not-a-pdf',
        code: 'IMP-004',
        message: l10n.imp004,
        recovery: l10n.imp004Recovery,
        password: false,
      ),
    ];

    for (final _RejectionCase expected in cases) {
      final SimulatedBackend backend = SimulatedBackend();
      final SimulatedDocumentImportAdapter adapter =
          SimulatedDocumentImportAdapter(backend: backend, catalog: catalog);
      int createDocumentCalls = 0;
      final ImportFlow flow = ImportFlow(
        localizations: l10n,
        createDocument: (ImportedDocumentCandidate candidate) async {
          createDocumentCalls++;
        },
      );

      adapter.picker.enqueueFixture(expected.fixtureId);
      final ImportOutcome outcome = await flow.run(
        port: adapter,
        request: ImportRequest(),
      );

      expect(outcome, isA<ImportRejected>(), reason: expected.fixtureId);
      final ImportRejected rejected = outcome as ImportRejected;
      expect(rejected.failure.code, expected.code);
      expect(rejected.failure.presentationCode, expected.code);
      expect(rejected.failure.message, expected.message);
      expect(rejected.failure.recovery, expected.recovery);
      expect(rejected.failure.isCancellation, isFalse);
      expect(rejected.failure.isUnrecognized, isFalse);
      expect(rejected.failure.passwordProtectionConfirmed, expected.password);
      expect(rejected.failure.toString(), isNot(contains('IMP-')));
      expect(rejected.failure.message, isNot(contains('IMP-')));

      // FR-009: no document, draft, template, or staged source exists after
      // a rejection, and the document writer was never called.
      expect(createDocumentCalls, 0, reason: expected.fixtureId);
      expect(backend.documents, isEmpty, reason: expected.fixtureId);
      expect(backend.stagedSources, isEmpty, reason: expected.fixtureId);
      expect(adapter.picker.isEmpty, isTrue);
    }

    // The exact catalog sentences are asserted above; these anchors make the
    // observed German text visible in the test source and browser log.
    expect(l10n.imp001, startsWith('Diese PDF-Datei ist passwortgeschützt.'));
    expect(l10n.imp002, startsWith('Die Datei konnte nicht gelesen werden.'));
    expect(l10n.imp004, startsWith('Diese Datei ist kein unterstütztes PDF.'));
  });

  test(
    'cancels the SIMULATED picker without a message or stored record',
    () async {
      final SimulatedFixtureCatalog catalog = await _loadCatalog();
      final SimulatedBackend backend = SimulatedBackend();
      final SimulatedDocumentImportAdapter adapter =
          SimulatedDocumentImportAdapter(backend: backend, catalog: catalog);
      final AppLocalizations l10n = AppLocalizationsDe();
      int createDocumentCalls = 0;
      final ImportFlow flow = ImportFlow(
        localizations: l10n,
        createDocument: (ImportedDocumentCandidate candidate) async {
          createDocumentCalls++;
        },
      );

      adapter.picker.enqueueCancel();
      final ImportOutcome outcome = await flow.run(
        port: adapter,
        request: ImportRequest(),
      );

      expect(outcome, isA<ImportCancelled>());
      expect(createDocumentCalls, 0);
      expect(backend.documents, isEmpty);
      expect(backend.stagedSources, isEmpty);
    },
  );

  test('composes the Web registry with SIMULATED evidence only', () async {
    final SimulatedFixtureCatalog catalog = await _loadCatalog();
    final SimulatedBackend backend = SimulatedBackend();
    final SimulatedAdapterContext context = backend.context;
    final SimulatedDocumentImportAdapter importAdapter =
        SimulatedDocumentImportAdapter(backend: backend, catalog: catalog);

    // The four non-journey capabilities have no T028 adapter. They are inert,
    // test-local composition seams whose descriptors still carry the canonical
    // SIMULATED evidence class, so the Web registry can validate all ten ports
    // without claiming an Android capability.
    final PlatformAdapterSet adapters = PlatformAdapterSet(
      import: importAdapter,
      raster: SimulatedPageRasterAdapter(backend: backend),
      ocr: SimulatedOcrAdapter(backend: backend, catalog: catalog),
      store: SimulatedSecureStoreAdapter(backend: backend),
      export: SimulatedPdfExportAdapter(backend: backend),
      delivery: SimulatedDeliveryAdapter(backend: backend),
      lifecycle: _SeamPort(kind: CapabilityKind.lifecycle, context: context),
      clock: _SeamPort(kind: CapabilityKind.clock, context: context),
      ids: _SeamPort(kind: CapabilityKind.ids, context: context),
      diagnostics: _SeamPort(
        kind: CapabilityKind.diagnostics,
        context: context,
      ),
    );

    final AdapterRegistry registry = createRegistry(adapters);
    expect(registry, isA<WebAdapterRegistry>());
    expect(registry.isDevelopmentEnvironment, isTrue);
    expect(registry.hasSimulatedCapabilities, isTrue);
    expect(registry.import, same(importAdapter));
    expect(registry.descriptors, hasLength(CapabilityKind.values.length));

    const Set<String> simulatedAdapterIds = <String>{
      simulatedImportAdapterId,
      simulatedRasterAdapterId,
      simulatedOcrAdapterId,
      simulatedStoreAdapterId,
      simulatedExportAdapterId,
      simulatedDeliveryAdapterId,
    };
    final Set<String> observedAdapterIds = <String>{};
    for (final CapabilityDescriptor descriptor in registry.descriptors) {
      expect(descriptor.evidence.evidenceClass, EvidenceClass.simulated);
      expect(descriptor.evidence.simulated, isTrue);
      expect(descriptor.evidence.evidenceClass.isAndroid, isFalse);
      expect(descriptor.isSimulated, isTrue);
      expect(descriptor.evidence.adapterId, descriptor.adapterId);
      if (simulatedAdapterIds.contains(descriptor.adapterId)) {
        observedAdapterIds.add(descriptor.adapterId);
      }
    }
    expect(observedAdapterIds, simulatedAdapterIds);

    // The release guard still rejects this dev-only registry with SIM-001.
    expect(
      () => resolveRegistry(adapters, isReleaseBuild: true),
      throwsA(
        isA<SimulatedInProductionException>().having(
          (SimulatedInProductionException error) => error.code,
          'code',
          'SIM-001',
        ),
      ),
    );
  });

  testWidgets('resolves and renders the committed SIMULATED banner in German', (
    WidgetTester tester,
  ) async {
    final AppLocalizationsDe l10n = AppLocalizationsDe();
    expect(l10n.simulatedToken, 'SIMULATED');
    expect(l10n.simulatedLogPrefix, '[SIMULATED]');
    expect(l10n.simulatedBanner, startsWith('SIMULATED'));
    expect(l10n.simulatedBanner, contains('Keine Android-Prüfung.'));
    expect(l10n.simulatedBannerContext, contains('nicht als Android-Nachweis'));

    // T129 still owns the production banner wiring. This check proves that the
    // committed German banner string is resolvable and renderable in Chrome
    // through the same generated localizations the app uses.
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (BuildContext context) {
            final AppLocalizations resolved = AppLocalizations.of(context);
            return Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    Text(resolved.simulatedBanner),
                    Text(resolved.simulatedBannerContext),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.simulatedBanner), findsOneWidget);
    expect(find.text(l10n.simulatedBannerContext), findsOneWidget);
  });
}

/// One expected typed rejection in the browser journey.
final class _RejectionCase {
  const _RejectionCase({
    required this.fixtureId,
    required this.code,
    required this.message,
    required this.recovery,
    required this.password,
  });

  final String fixtureId;
  final String code;
  final String message;
  final String recovery;
  final bool password;
}

/// One inert composition-seam port for the four capabilities T028 does not
/// implement. It carries a real SIMULATED descriptor; no method is part of the
/// import journey.
final class _SeamPort
    implements LifecyclePort, ClockPort, IdPort, DiagnosticsPort {
  _SeamPort({required CapabilityKind kind, required this.context})
    : descriptor = simulatedDescriptor(
        kind: kind,
        adapterId: 'web.test.${kind.name}.v1',
        supportedFeatures: const <String>['test-seam'],
      );

  final SimulatedAdapterContext context;

  @override
  final CapabilityDescriptor descriptor;

  final List<String> events = <String>[];

  @override
  Stream<AppLifecycleSignal> get signals =>
      const Stream<AppLifecycleSignal>.empty();

  @override
  DateTime nowUtc() => context.nowUtc();

  @override
  String newId() => context.newId();

  @override
  String newIdempotencyKey() => context.newIdempotencyKey();

  @override
  void event(
    String code, {
    Map<String, Object?> scalarFields = const <String, Object?>{},
  }) {
    events.add(code);
  }

  @override
  Future<void> clear() async {
    events.clear();
  }
}
