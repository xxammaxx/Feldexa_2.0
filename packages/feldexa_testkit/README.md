# `feldexa_testkit` (test-only, T011/T036)

Deterministic test seams required by `plan.md` §Architecture Decisions 10 and
`research.md` D-17: a fake clock, a validating loader for the SIMULATED fixture
catalogue, declarative fault hooks, and the T036 failure-injection harness with
a `FakeRegistry`. The package is **never imported by production code**.

## What it provides

| Import | Contents |
| --- | --- |
| `package:feldexa_testkit/feldexa_testkit.dart` | Fake and scripted clock, fault rules/injector, faulting store/export decorators, `FakeRegistry`, fixture catalogue and loader, in-memory source, evidence labels, SHA-256. No `dart:io`. |
| `package:feldexa_testkit/io.dart` | `FileFixtureSource` and `FixtureCheckout` for host VM tests. |

### Fake clock

```dart
final FakeClock clock = FakeClock(initialUtc: DateTime.utc(2026, 11, 13));
clock.advance(const Duration(seconds: 2));
expect(clock.nowUtc(), DateTime.utc(2026, 11, 13, 0, 0, 2));
```

`nowUtc()` matches the `ClockPort` method shape from
`contracts/ports.md` §2.8. Time never advances on its own; `advance` rejects a
negative duration and `advanceTo` rejects moving backwards. Use `setUtc` for an
explicit rewind.

### Fixture loader

```dart
final FixtureCheckout checkout = FixtureCheckout.locate();
final FixtureLoader loader = await checkout.openLoader();

final LoadedFixture pdf = await loader.load('sf-001');
final Map<String, Object?> ocr = await loader.loadExpectedOcr('sf-001');
```

The loader validates `catalog.json` first (schema, SIMULATED class, rights,
dev-only delivery, pages, ground truth, failure codes), then checks the
declared size, SHA-256, and PDF shape for each fixture's status. It works with
an `InMemoryFixtureSource` (browser tests) or any other `FixtureSource`.

### Path safety

Every catalogue-derived path is treated as untrusted data. The public
`validatePortableRelativePath` and `validateWebBasePath` helpers require
portable, relative, `/`-separated paths and reject:

- backslashes (`..\..\outside` is not a portable path), drive letters, URL
  schemes, alternate-data-stream colons, and control characters;
- absolute paths, UNC/protocol-relative values, and traversal `.`/`..`
  segments;
- empty segments, trailing slashes, and segments with leading/trailing
  whitespace or a trailing dot (Windows strips those and can reinterpret the
  segment).

Delivery directories, fixture and expected-OCR paths, generator paths, and
the Web base path are all checked before `FileFixtureSource` or a checkout
source can join them. The source API uses the same rule through
`validateFixturePath`.

The three T009 copies remain distinct:

| Target | Directory | Use |
| --- | --- | --- |
| `canonicalDev` | `apps/feldexa_app/assets/fixtures` | canonical host source |
| `web` | `apps/feldexa_app/web/fixtures` | `/fixtures/...` Web delivery |
| `corpus` | `tools/corpus/synthetic` | `adb push` transport for Android tests |

### Fault hooks

```dart
final FaultInjector faults = FaultInjector(
  FaultPlan(<FaultRule>[
    FaultRule(
      point: FaultPoints.storeWrite,
      kind: FaultKind.storageFull,
      startsAt: 1,
      times: 1,
    ),
  ]),
);

faults.check(FaultPoints.storeWrite); // throws InjectedFault(SAVE-001)
```

Rules are counted per point; `startsAt` is one-based, `times: null` means every
matching call. The injector records calls and injected faults so a test can
assert what happened. Faults are scaffolding, not evidence: a browser run stays
SIMULATED and an Android run stays EMULATOR/DEVICE.

### T036 failure-injection harness

`package:feldexa_testkit/feldexa_testkit.dart` also exposes the T036 layer on
top of the T011 rules:

- `ScriptedClock` is a deterministic `ClockPort` with manual `advance`,
  `advanceTo`, and `setUtc` controls plus scheduled forward/backward
  `ClockJump`s. A jump models an uncontrolled wall-clock correction and is
  applied before the read after its configured read count; `appliedJumps`
  records it.
- `faultExceptionFor` maps every `FaultKind` to its T014 typed exception:
  `SAVE-001` (`StorageFullException`), `SAVE-003`
  (`StorageWriteException`), `SAVE-008` (`KeystoreUnavailableException`),
  `SAVE-002` (`KeyUnavailableException`), and `EXP-002`
  (`ExportFailedException`).
- `FaultingSecureStore` wraps any `SecureStorePort`. Writes pass
  `store.write`, `store.fsync`, and `store.commit`; document, template, and
  signature reads pass `store.read`. The decorator checks the script and then
  delegates, so a test wraps the adapter under test rather than reimplementing
  it.
- `FaultingPdfExport` wraps any `PdfExportPort` and checks
  `export.validate`, `export.write`, and `export.verify`. A verification fault
  best-effort deletes the candidate artifact before throwing `EXP-002`.
- `FakeRegistry` is the `contracts/ports.md` §4 test seam. It composes a
  `ScriptedClock`, deterministic `SequenceIds`, `ScriptedLifecycle`, and the two
  fault decorators. Capabilities a test does not override fail with the typed
  `PLT-001` `UnsupportedOperationException`, and descriptors always come from
  the live adapter, with kinds checked in `CapabilityKind` order.

```dart
test('global Keystore outage surfaces SAVE-008', () async {
  final FakeRegistry registry = FakeRegistry(
    faults: FaultInjector(
      FaultPlan(<FaultRule>[
        FaultRule(
          point: FaultPoints.storeRead,
          kind: FaultKind.keystoreUnavailable,
        ),
      ]),
    ),
    initialUtc: DateTime.utc(2026, 11, 15, 9),
  );

  await expectLater(
    registry.store.loadDocument('00000000-0000-4000-8000-000000000001'),
    throwsA(isA<KeystoreUnavailableException>()),
  );
});
```

### Evidence labels

`EvidenceClass` is owned by `feldexa_ports` (T014) and re-exported here; the
toolkit no longer declares a second enum. `EvidenceClass` and `EvidenceLabel`
encode `NONE`, `SIMULATED`, `EMULATOR`, and `DEVICE`.
`EvidenceLedger.requireSeparated()` rejects a report that merges SIMULATED with
EMULATOR/DEVICE. `EvidenceLabel.toString()` is a redacted log identity that
omits free-form detail; `toJson()` exposes it only when a caller explicitly
serializes a report. Using this package never upgrades a run's class: T011's own
package tests are host-VM checks and therefore produce no runtime evidence.

## Verification

```sh
flutter analyze --no-pub packages/feldexa_testkit
flutter test --no-pub packages/feldexa_testkit
```

Both are host-side checks. They do not prove Android import, storage, OCR,
export, or device acceptance; those remain with their own tasks and must be
reported as `EMULATOR` or `DEVICE` evidence.
