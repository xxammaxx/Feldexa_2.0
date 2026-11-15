// T036 failure-injection harness and FakeRegistry test seam.
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/tasks.md` T036;
//   * `specs/001-scanned-form-workflow/contracts/ports.md` §4 (test seam);
//   * `specs/001-scanned-form-workflow/research.md` D-17 (fault injection:
//     ENOSPC, short write, fsync failure, keystore loss/corruption, and a
//     controllable clock);
//   * constitution Principle VIII (failure-case tests and separated evidence).
//
// The T011 fault injector already owns the rule/plan vocabulary. This file is
// the T036 layer on top of it:
//   * `ScriptedClock` — a deterministic `ClockPort` with manual advance and
//     scripted forward/backward wall-clock jumps;
//   * `faultExceptionFor` — the single mapping from an injected fault to the
//     T014 typed exception required by `contracts/ports.md` §3;
//   * `FaultingSecureStore` and `FaultingPdfExport` — decorators that check
//     documented fault points before delegating to the real adapter, so quota,
//     keystore, interruption, and export failures surface as typed exceptions;
//   * `StagedWriteFaultSeam` — phase-aware checkpoints that an adapter calls
//     inside its verified-commit transaction, so staged-write, fsync, and
//     commit faults are injected at the real boundary instead of before the
//     delegate;
//   * `FakeRegistry` — the `contracts/ports.md` §4 test seam with a
//     deterministic clock, ID sequence, scripted lifecycle, and fault-injecting
//     store/export adapters.
//
// The harness is test scaffolding, not evidence. It never upgrades a result's
// evidence class: a host-VM test stays `NONE`, a browser run stays `SIMULATED`,
// and only an actual Android emulator/device run may be reported as
// `EMULATOR`/`DEVICE`.
//
// No production contract type is declared here. All port interfaces, DTOs,
// evidence types, and typed exceptions are consumed from `feldexa_ports`;
// `InjectedFault`, `FaultRule`, and `FaultPlan` stay owned by T011.

import 'dart:async';
import 'dart:typed_data';

import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';

import 'clock/fake_clock.dart';
import 'faults/fault_injector.dart';
import 'faults/fault_kind.dart';
import 'faults/fault_rule.dart';

export 'faults/fault_injector.dart';
export 'faults/fault_kind.dart';
export 'faults/fault_rule.dart';

/// Whether a [ClockJump] moves the wall clock forward or backward.
enum ClockJumpKind {
  /// The clock jumps ahead of the previous reading.
  forward,

  /// The clock jumps behind the previous reading.
  backward,
}

/// One scripted wall-clock jump.
///
/// A real device wall clock can move forward or backward between two reads
/// (time-zone database corrections, NTP corrections, a user changing the
/// clock). Tests use a jump instead of sleeping so the behavior is
/// deterministic and the jump is recorded.
final class ClockJump {
  /// Jumps [amount] forward after [afterReads] completed [ClockPort.nowUtc]
  /// reads.
  ///
  /// [afterReads] is the number of reads that must already have happened;
  /// `0` applies before the first read. [amount] must be positive.
  ClockJump.forward({required int afterReads, required Duration amount})
    : this._(ClockJumpKind.forward, afterReads, amount);

  /// Jumps [amount] backward after [afterReads] completed reads.
  ClockJump.backward({required int afterReads, required Duration amount})
    : this._(ClockJumpKind.backward, afterReads, amount);

  ClockJump._(this.kind, this.afterReads, this.amount) {
    if (afterReads < 0) {
      throw ArgumentError.value(
        afterReads,
        'afterReads',
        'must not be negative',
      );
    }
    if (amount <= Duration.zero) {
      throw ArgumentError.value(amount, 'amount', 'must be positive');
    }
  }

  /// Direction of the jump.
  final ClockJumpKind kind;

  /// Number of reads completed before the jump applies.
  final int afterReads;

  /// Absolute jump distance; always positive.
  final Duration amount;

  @override
  String toString() {
    return 'ClockJump(${kind.name} after $afterReads reads: $amount)';
  }
}

/// A deterministic [ClockPort] with manual advance and scripted jumps.
///
/// Time never advances on its own. Tests call [advance], [advanceTo], or
/// [setUtc] explicitly, or schedule a [ClockJump] to model an uncontrolled
/// wall-clock correction.
final class ScriptedClock implements ClockPort {
  /// Creates a UTC clock at [initialUtc], or at the Unix epoch when omitted.
  ///
  /// A local [DateTime] is normalized to UTC. The descriptor must identify the
  /// `clock` capability; this constructor validates the kind so a registry
  /// cannot silently attach the clock descriptor to another capability.
  ScriptedClock({required this.descriptor, DateTime? initialUtc})
    : _clock = FakeClock(initialUtc: initialUtc) {
    if (descriptor.kind != CapabilityKind.clock) {
      throw ArgumentError('descriptor.kind must be CapabilityKind.clock');
    }
  }

  @override
  final CapabilityDescriptor descriptor;

  final FakeClock _clock;
  final List<ClockJump> _jumps = <ClockJump>[];
  final List<bool> _applied = <bool>[];
  final List<ClockJump> _appliedJumps = <ClockJump>[];

  /// Currently scheduled jumps, in registration order.
  List<ClockJump> get jumps => List<ClockJump>.unmodifiable(_jumps);

  /// Jumps that have already been applied, in application order.
  List<ClockJump> get appliedJumps =>
      List<ClockJump>.unmodifiable(_appliedJumps);

  /// Number of [nowUtc] reads, including reads that triggered a jump.
  int get readCount => _clock.readCount;

  /// The current instant without counting a read.
  DateTime get currentUtc => _clock.currentUtc;

  /// The instant this clock was created at.
  DateTime get startedAt => _clock.startedAt;

  /// Elapsed fake time since creation.
  Duration get elapsed => _clock.elapsed;

  /// Schedules [jump].
  ///
  /// The jump cannot be scheduled for a read that already happened; this
  /// prevents a test from silently losing a jump.
  void scheduleJump(ClockJump jump) {
    if (jump.afterReads < _clock.readCount) {
      throw ArgumentError.value(
        jump.afterReads,
        'afterReads',
        'must not be before the current read count ${_clock.readCount}',
      );
    }
    _jumps.add(jump);
    _applied.add(false);
  }

  @override
  DateTime nowUtc() {
    _applyDueJumps();
    return _clock.nowUtc();
  }

  /// Advances by [by]; a negative duration is rejected.
  void advance(Duration by) {
    _clock.advance(by);
  }

  /// Advances to [instant], which must not be before the current instant.
  void advanceTo(DateTime instant) {
    _clock.advanceTo(instant);
  }

  /// Sets the clock explicitly, including backwards.
  void setUtc(DateTime instant) {
    _clock.setUtc(instant);
  }

  /// Returns to the creation instant and replays every scheduled jump.
  void reset() {
    _clock.reset();
    for (int index = 0; index < _applied.length; index++) {
      _applied[index] = false;
    }
    _appliedJumps.clear();
  }

  void _applyDueJumps() {
    for (int index = 0; index < _jumps.length; index++) {
      final ClockJump jump = _jumps[index];
      if (_applied[index] || jump.afterReads != _clock.readCount) {
        continue;
      }
      _applied[index] = true;
      _appliedJumps.add(jump);
      switch (jump.kind) {
        case ClockJumpKind.forward:
          _clock.advance(jump.amount);
        case ClockJumpKind.backward:
          _clock.setUtc(_clock.currentUtc.subtract(jump.amount));
      }
    }
  }
}

/// Maps an injected fault to the T014 typed exception the production path must
/// surface (`contracts/ports.md` §3).
///
/// The mapping is the single place where test-only [FaultKind] values meet the
/// product error taxonomy. Adding a fault kind without adding its exception
/// here is a compile error, not a silent fallback.
FeldexaException faultExceptionFor(InjectedFault fault) {
  return switch (fault.kind) {
    FaultKind.storageFull => StorageFullException(),
    FaultKind.shortWrite ||
    FaultKind.fsyncFailure ||
    FaultKind.writeInterrupted => StorageWriteException(),
    FaultKind.keystoreUnavailable => KeystoreUnavailableException(),
    FaultKind.keystoreReset => KeystoreUnavailableException(retryable: false),
    FaultKind.corruptKeyMaterial => KeyUnavailableException(),
    FaultKind.exportFailure => ExportFailedException(),
  };
}

/// Checks T011 fault rules and converts an [InjectedFault] to its typed
/// exception.
void _checkFault(FaultInjector injector, String point) {
  try {
    injector.check(point);
  } on InjectedFault catch (fault) {
    throw faultExceptionFor(fault);
  }
}

/// Phase-aware checkpoints for the §3.1 verified-commit protocol.
///
/// A [SecureStorePort] only exposes `saveRevision`; the port boundary cannot
/// tell whether a failure happened before the staged file existed, after it was
/// written, at fsync, or after the revision was promoted but before `head.fx1`
/// was replaced. The decorator therefore cannot inject those later phases
/// without creating the impossible "fault before the delegate" state the review
/// found.
///
/// An adapter that owns the transaction calls these methods at the documented
/// points instead:
///
/// 1. [beforeStagedWrite] — before `tmp/<txnId>.part` is created;
/// 2. [afterStagedWrite] — after the staged bytes were written, before fsync;
/// 3. [beforeFsync] — immediately before `fd.sync()`, so an injected
///    `fsyncFailure` means fsync did not complete;
/// 4. [beforeHeadCommit] — after the revision was promoted, before the head
///    rename.
///
/// `store.stage` is checked twice so tests can distinguish a failure before the
/// staged object exists (`startsAt: 1`) from one after it exists
/// (`startsAt: 2`). There is deliberately no post-fsync abort point: a fault
/// raised after a successful fsync would model cleanup after an interruption,
/// not an fsync failure, and would mislabel the phase. The seam is test
/// scaffolding: it does not create files, preserve a head, or clean staging.
/// Those are adapter obligations; a real durable-head assertion is only
/// possible once the adapter transaction under test calls this seam. T028's
/// Dart simulated storage adapter can use this Dart seam in its tests; T026's
/// Kotlin `EncryptedStore` needs an equivalent native fault-injection/test seam
/// in T026.
final class StagedWriteFaultSeam {
  /// Creates a seam that reads faults from [injector].
  StagedWriteFaultSeam({required this.injector});

  /// The scripted fault plan for this transaction.
  final FaultInjector injector;

  /// Checks the pre-stage fault point (`store.stage`, first call).
  void beforeStagedWrite() {
    _checkFault(injector, FaultPoints.storeStage);
  }

  /// Checks the post-stage fault point (`store.stage`, second call).
  ///
  /// A fault here happens while `tmp/<txnId>.part` exists and before fsync.
  void afterStagedWrite() {
    _checkFault(injector, FaultPoints.storeStage);
  }

  /// Checks the fsync fault point immediately before `fd.sync()`.
  ///
  /// A fault here happens while `tmp/<txnId>.part` exists and means the fsync
  /// never completed; it is not a post-fsync abort.
  void beforeFsync() {
    _checkFault(injector, FaultPoints.storeFsync);
  }

  /// Checks the commit fault point after revision promotion.
  ///
  /// A fault here leaves the old `head.fx1` in place and the newly promoted
  /// revision unreferenced; the adapter must keep the old head and remove the
  /// unreferenced object.
  void beforeHeadCommit() {
    _checkFault(injector, FaultPoints.storeCommit);
  }
}

/// Decorates a [SecureStorePort] with the pre-stage quota gate and keystore
/// fault points.
///
/// The decorator owns no storage behavior: it checks the fault script and then
/// delegates to the real or simulated adapter. It deliberately checks only the
/// points that are visible at the port boundary:
///
/// * `keystore.unwrap` before any read or write that needs the aggregate key;
/// * `store.write` as the free-space/pre-stage gate;
/// * `store.read` before a document, template, or signature read.
///
/// The internal `store.stage`, `store.fsync`, and `store.commit` phases belong
/// to the adapter transaction and are exposed through [writeSeam]. Checking
/// them here would fire before the delegate and could never exercise a partial
/// staged state.
final class FaultingSecureStore implements SecureStorePort {
  /// Wraps [delegate] and reads faults from [injector].
  FaultingSecureStore({required this.delegate, required this.injector})
    : writeSeam = StagedWriteFaultSeam(injector: injector);

  /// The adapter whose behavior is under test.
  final SecureStorePort delegate;

  /// The scripted faults for this store.
  final FaultInjector injector;

  /// Phase-aware checkpoints for an adapter's verified-commit transaction.
  final StagedWriteFaultSeam writeSeam;

  @override
  CapabilityDescriptor get descriptor => delegate.descriptor;

  /// Checks the aggregate key unwrap, then [FaultPoints.storeRead], then
  /// [action].
  Future<T> guardRead<T>(FutureOr<T> Function() action) async {
    _checkFault(injector, FaultPoints.keystoreUnwrap);
    _checkFault(injector, FaultPoints.storeRead);
    return await action();
  }

  /// Checks the aggregate key unwrap and the pre-stage quota gate, then
  /// [action].
  ///
  /// The staged write, fsync, and commit phases are checked by the adapter
  /// through [writeSeam]; this guard cannot observe them.
  Future<T> guardWrite<T>(FutureOr<T> Function() action) async {
    _checkFault(injector, FaultPoints.keystoreUnwrap);
    _checkFault(injector, FaultPoints.storeWrite);
    return await action();
  }

  @override
  Future<StoreStatus> status() => delegate.status();

  @override
  Future<StoredMeta> createDocument(CreateDocumentRequest request) =>
      guardWrite(() => delegate.createDocument(request));

  @override
  Future<StoredMeta> saveRevision(SaveRevisionRequest request) =>
      guardWrite(() => delegate.saveRevision(request));

  @override
  Future<LoadedDocument> loadDocument(String documentId) =>
      guardRead(() => delegate.loadDocument(documentId));

  @override
  Future<Uint8List> readSignature(String documentId, String assetId) =>
      guardRead(() => delegate.readSignature(documentId, assetId));

  @override
  Future<void> writeSignature(WriteSignatureRequest request) =>
      guardWrite(() => delegate.writeSignature(request));

  @override
  Future<List<StoredMeta>> list(StoreKind kind) => delegate.list(kind);

  @override
  Future<void> delete(
    StoreKind kind,
    String id,
    DeleteConfirmation confirmation,
  ) => delegate.delete(kind, id, confirmation);

  @override
  Future<StoredMeta> createTemplate(CreateTemplateRequest request) =>
      guardWrite(() => delegate.createTemplate(request));

  @override
  Future<StoredMeta> saveTemplateVersion(SaveTemplateVersionRequest request) =>
      guardWrite(() => delegate.saveTemplateVersion(request));

  @override
  Future<LoadedTemplate> loadTemplate(String templateId, {String? versionId}) =>
      guardRead(() => delegate.loadTemplate(templateId, versionId: versionId));

  @override
  Future<RecoveryStamp> recoveryStamp(String id, StoreKind kind) =>
      delegate.recoveryStamp(id, kind);
}

/// Decorates a [PdfExportPort] with export-write and verification fault points.
///
/// A write fault fires before the delegate runs, so no artifact is produced. A
/// verification fault fires after the delegate returned a result; the decorator
/// best-effort deletes the reported artifact and then throws `EXP-002`, so a
/// partial artifact is never left behind as a success.
final class FaultingPdfExport implements PdfExportPort {
  /// Wraps [delegate] and reads faults from [injector].
  FaultingPdfExport({required this.delegate, required this.injector});

  /// The adapter whose behavior is under test.
  final PdfExportPort delegate;

  /// The scripted faults for this export adapter.
  final FaultInjector injector;

  /// Best-effort cleanup failures observed while discarding a candidate that
  /// failed the injected verification point.
  final List<Object> _cleanupFailures = <Object>[];

  /// Best-effort cleanup failures, in occurrence order.
  List<Object> get cleanupFailures =>
      List<Object>.unmodifiable(_cleanupFailures);

  @override
  CapabilityDescriptor get descriptor => delegate.descriptor;

  /// Runs plan validation through [FaultPoints.exportValidate] and [action].
  Future<T> guardValidate<T>(FutureOr<T> Function() action) async {
    _checkFault(injector, FaultPoints.exportValidate);
    return await action();
  }

  /// Runs one export through the write and verification fault points.
  ///
  /// [action] produces the candidate result. When a verification fault fires,
  /// [artifactId] and [deleteArtifact] are used for best-effort cleanup before
  /// `EXP-002` is thrown.
  Future<T> guardExport<T>(
    FutureOr<T> Function() action, {
    String Function(T value)? artifactId,
    Future<void> Function(String id)? deleteArtifact,
  }) async {
    _checkFault(injector, FaultPoints.exportWrite);
    final T value = await action();
    try {
      injector.check(FaultPoints.exportVerify);
    } on InjectedFault catch (fault) {
      final String Function(T)? idOf = artifactId;
      final Future<void> Function(String)? remove = deleteArtifact;
      if (idOf != null && remove != null) {
        try {
          await remove(idOf(value));
        } catch (error) {
          _cleanupFailures.add(error);
        }
      }
      throw faultExceptionFor(fault);
    }
    return value;
  }

  @override
  Future<ExportValidationResult> validate(ExportPlan plan) =>
      guardValidate(() => delegate.validate(plan));

  @override
  Future<ExportResult> export(ExportRequest request) =>
      guardExport<ExportResult>(
        () => delegate.export(request),
        artifactId: (ExportResult value) => value.artifact.id,
        deleteArtifact: delegate.deleteArtifact,
      );

  @override
  Future<Uint8List> readArtifact(String artifactId) =>
      delegate.readArtifact(artifactId);

  @override
  Future<void> deleteArtifact(String artifactId) =>
      delegate.deleteArtifact(artifactId);
}

/// Builds a deterministic capability descriptor for a test seam.
///
/// Simulated descriptors use `EvidenceClass.simulated`; non-simulated ones use
/// `EvidenceClass.none`, never `EMULATOR` or `DEVICE`, because a fake adapter
/// does not execute on those runtimes.
CapabilityDescriptor fakeCapabilityDescriptor(
  CapabilityKind kind, {
  bool simulated = true,
  String? adapterId,
}) {
  final String id = adapterId ?? 'test.fake.${kind.name.toLowerCase()}.v1';
  final CapabilityEvidence evidence = simulated
      ? CapabilityEvidence.simulated(
          adapterId: id,
          simulatedReason: 'test.fake-adapter',
        )
      : CapabilityEvidence(evidenceClass: EvidenceClass.none, adapterId: id);
  return CapabilityDescriptor(
    kind: kind,
    adapterId: id,
    version: '1',
    isSimulated: simulated,
    evidence: evidence,
    supportedFeatures: <String>['test-seam'],
  );
}

/// A deterministic UUIDv4 and idempotency-key sequence.
final class SequenceIds implements IdPort {
  /// Creates a sequence whose first generated id uses [firstValue].
  SequenceIds({required this.descriptor, int firstValue = 1})
    : _firstValue = firstValue,
      _nextId = firstValue {
    if (descriptor.kind != CapabilityKind.ids) {
      throw ArgumentError('descriptor.kind must be CapabilityKind.ids');
    }
    if (firstValue < 1 || firstValue > _maxSequenceValue) {
      throw ArgumentError(
        'firstValue must be between 1 and $_maxSequenceValue',
      );
    }
  }

  @override
  final CapabilityDescriptor descriptor;

  static const int _maxSequenceValue = 0xFFFFFFFFFFFF;

  final int _firstValue;
  int _nextId;
  int _nextKey = 1;

  @override
  String newId() {
    final int value = _nextId;
    if (value > _maxSequenceValue) {
      throw StateError('deterministic id sequence exhausted');
    }
    _nextId++;
    return '00000000-0000-4000-8000-${value.toRadixString(16).padLeft(12, '0')}';
  }

  @override
  String newIdempotencyKey() {
    final String key = 'idempotency-key-${_nextKey.toString().padLeft(6, '0')}';
    _nextKey++;
    return key;
  }

  /// Restarts the id and idempotency-key sequences at their first values.
  void reset() {
    _nextId = _firstValue;
    _nextKey = 1;
  }
}

/// A broadcast lifecycle stream driven explicitly by the test.
///
/// Events are recorded even when no listener is attached yet, so a test can
/// emit before subscribing and assert the emitted order from [emitted].
final class ScriptedLifecycle implements LifecyclePort {
  /// Creates a scripted lifecycle stream for [descriptor].
  ScriptedLifecycle({required this.descriptor}) {
    if (descriptor.kind != CapabilityKind.lifecycle) {
      throw ArgumentError('descriptor.kind must be CapabilityKind.lifecycle');
    }
  }

  @override
  final CapabilityDescriptor descriptor;

  final StreamController<AppLifecycleSignal> _controller =
      StreamController<AppLifecycleSignal>.broadcast(sync: true);
  final List<AppLifecycleSignal> _emitted = <AppLifecycleSignal>[];

  /// Every signal emitted by the test, in order.
  List<AppLifecycleSignal> get emitted =>
      List<AppLifecycleSignal>.unmodifiable(_emitted);

  /// Whether the underlying stream is closed.
  bool get isClosed => _controller.isClosed;

  @override
  Stream<AppLifecycleSignal> get signals => _controller.stream;

  /// Emits one lifecycle [signal].
  void emit(AppLifecycleSignal signal) {
    if (_controller.isClosed) {
      throw StateError('cannot emit on a closed lifecycle stream');
    }
    _emitted.add(signal);
    _controller.add(signal);
  }

  /// Emits [signals] in iteration order.
  void emitAll(Iterable<AppLifecycleSignal> signals) {
    for (final AppLifecycleSignal signal in signals) {
      emit(signal);
    }
  }

  /// Closes the broadcast stream.
  Future<void> close() => _controller.close();
}

/// The `contracts/ports.md` §4 test seam.
///
/// The registry composes a deterministic clock, ID sequence, scripted
/// lifecycle, and fault-injecting store/export adapters. Capabilities that a
/// test does not provide are deterministic unavailable stubs that throw the
/// typed `PLT-001` failure instead of a raw `UnimplementedError`.
///
/// Passing a real adapter for `secureStore` or `pdfExport` wraps it in the
/// fault decorator; pass the injector through [faults] or read it back from the
/// registry. Every descriptor is derived from the live adapter, so a fake port
/// with a mismatched capability kind fails registry construction.
final class FakeRegistry implements AdapterRegistry {
  /// Builds a registry from optional adapter overrides.
  ///
  /// [simulated] controls only the generated default descriptors. An explicit
  /// adapter keeps its own descriptor, and [hasSimulatedCapabilities] is always
  /// derived from the descriptors actually returned.
  factory FakeRegistry({
    FaultInjector? faults,
    ScriptedClock? clock,
    SequenceIds? ids,
    ScriptedLifecycle? lifecycle,
    DocumentImportPort? documentImport,
    PageRasterPort? pageRaster,
    OcrPort? ocr,
    SecureStorePort? secureStore,
    PdfExportPort? pdfExport,
    DeliveryPort? delivery,
    DiagnosticsPort? diagnostics,
    bool simulated = true,
    bool? isDevelopmentEnvironment,
    DateTime? initialUtc,
  }) {
    final FaultInjector faultInjector = faults ?? FaultInjector();
    final ScriptedClock clockPort =
        clock ??
        ScriptedClock(
          descriptor: fakeCapabilityDescriptor(
            CapabilityKind.clock,
            simulated: simulated,
          ),
          initialUtc: initialUtc,
        );
    final SequenceIds idsPort =
        ids ??
        SequenceIds(
          descriptor: fakeCapabilityDescriptor(
            CapabilityKind.ids,
            simulated: simulated,
          ),
        );
    final ScriptedLifecycle lifecyclePort =
        lifecycle ??
        ScriptedLifecycle(
          descriptor: fakeCapabilityDescriptor(
            CapabilityKind.lifecycle,
            simulated: simulated,
          ),
        );

    final DocumentImportPort importPort =
        documentImport ??
        _UnavailablePort(
          fakeCapabilityDescriptor(
            CapabilityKind.documentImport,
            simulated: simulated,
          ),
        );
    final PageRasterPort rasterPort =
        pageRaster ??
        _UnavailablePort(
          fakeCapabilityDescriptor(
            CapabilityKind.pageRaster,
            simulated: simulated,
          ),
        );
    final OcrPort ocrPort =
        ocr ??
        _UnavailablePort(
          fakeCapabilityDescriptor(CapabilityKind.ocr, simulated: simulated),
        );
    final SecureStorePort storeDelegate =
        secureStore ??
        _UnavailablePort(
          fakeCapabilityDescriptor(
            CapabilityKind.secureStore,
            simulated: simulated,
          ),
        );
    final PdfExportPort exportDelegate =
        pdfExport ??
        _UnavailablePort(
          fakeCapabilityDescriptor(
            CapabilityKind.pdfExport,
            simulated: simulated,
          ),
        );
    final DeliveryPort deliveryPort =
        delivery ??
        _UnavailablePort(
          fakeCapabilityDescriptor(
            CapabilityKind.delivery,
            simulated: simulated,
          ),
        );
    final DiagnosticsPort diagnosticsPort =
        diagnostics ??
        _UnavailablePort(
          fakeCapabilityDescriptor(
            CapabilityKind.diagnostics,
            simulated: simulated,
          ),
        );

    final FaultingSecureStore storePort = FaultingSecureStore(
      delegate: storeDelegate,
      injector: faultInjector,
    );
    final FaultingPdfExport exportPort = FaultingPdfExport(
      delegate: exportDelegate,
      injector: faultInjector,
    );

    final List<CapabilityDescriptor> descriptorList =
        List<CapabilityDescriptor>.unmodifiable(<CapabilityDescriptor>[
          importPort.descriptor,
          rasterPort.descriptor,
          ocrPort.descriptor,
          storePort.descriptor,
          exportPort.descriptor,
          deliveryPort.descriptor,
          lifecyclePort.descriptor,
          clockPort.descriptor,
          idsPort.descriptor,
          diagnosticsPort.descriptor,
        ]);
    for (int index = 0; index < CapabilityKind.values.length; index++) {
      if (descriptorList[index].kind != CapabilityKind.values[index]) {
        throw ArgumentError(
          'descriptor ${index + 1} must describe '
          '${CapabilityKind.values[index].name}',
        );
      }
    }

    return FakeRegistry._(
      faults: faultInjector,
      importPort: importPort,
      rasterPort: rasterPort,
      ocrPort: ocrPort,
      storePort: storePort,
      exportPort: exportPort,
      deliveryPort: deliveryPort,
      lifecyclePort: lifecyclePort,
      clockPort: clockPort,
      idsPort: idsPort,
      diagnosticsPort: diagnosticsPort,
      descriptors: descriptorList,
      isDevelopmentEnvironment:
          isDevelopmentEnvironment ??
          descriptorList.any((CapabilityDescriptor value) => value.isSimulated),
    );
  }

  FakeRegistry._({
    required this.faults,
    required DocumentImportPort importPort,
    required PageRasterPort rasterPort,
    required OcrPort ocrPort,
    required FaultingSecureStore storePort,
    required FaultingPdfExport exportPort,
    required DeliveryPort deliveryPort,
    required ScriptedLifecycle lifecyclePort,
    required ScriptedClock clockPort,
    required SequenceIds idsPort,
    required DiagnosticsPort diagnosticsPort,
    required this.descriptors,
    required this.isDevelopmentEnvironment,
  }) : _import = importPort,
       _raster = rasterPort,
       _ocr = ocrPort,
       _store = storePort,
       _export = exportPort,
       _delivery = deliveryPort,
       _lifecycle = lifecyclePort,
       _clock = clockPort,
       _ids = idsPort,
       _diagnostics = diagnosticsPort;

  /// The fault script shared by the store and export decorators.
  final FaultInjector faults;

  @override
  final bool isDevelopmentEnvironment;

  @override
  final List<CapabilityDescriptor> descriptors;

  final DocumentImportPort _import;
  final PageRasterPort _raster;
  final OcrPort _ocr;
  final FaultingSecureStore _store;
  final FaultingPdfExport _export;
  final DeliveryPort _delivery;
  final ScriptedLifecycle _lifecycle;
  final ScriptedClock _clock;
  final SequenceIds _ids;
  final DiagnosticsPort _diagnostics;

  @override
  DocumentImportPort get import => _import;

  @override
  PageRasterPort get raster => _raster;

  @override
  OcrPort get ocr => _ocr;

  @override
  FaultingSecureStore get store => _store;

  /// Phase-aware commit checkpoints shared with [store].
  ///
  /// A test adapter receives this seam so it can inject `store.stage`,
  /// `store.fsync`, and `store.commit` inside its own transaction; the
  /// registry itself cannot observe those phases.
  StagedWriteFaultSeam get writeSeam => _store.writeSeam;

  @override
  FaultingPdfExport get export => _export;

  @override
  DeliveryPort get delivery => _delivery;

  @override
  ScriptedLifecycle get lifecycle => _lifecycle;

  @override
  ScriptedClock get clock => _clock;

  @override
  SequenceIds get ids => _ids;

  @override
  DiagnosticsPort get diagnostics => _diagnostics;

  @override
  bool get hasSimulatedCapabilities =>
      descriptors.any((CapabilityDescriptor value) => value.isSimulated);
}

/// A deterministic stub for a capability the test did not provide.
///
/// It carries a real `CapabilityDescriptor` so registry metadata stays honest;
/// every other member fails with the typed `PLT-001` exception.
final class _UnavailablePort
    implements
        DocumentImportPort,
        PageRasterPort,
        OcrPort,
        SecureStorePort,
        PdfExportPort,
        DeliveryPort,
        LifecyclePort,
        ClockPort,
        IdPort,
        DiagnosticsPort {
  _UnavailablePort(this.descriptor);

  @override
  final CapabilityDescriptor descriptor;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedOperationException();
  }
}
