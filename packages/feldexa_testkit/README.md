# `feldexa_testkit` (test-only, T011)

Deterministic test seams required by `plan.md` §Architecture Decisions 10 and
`research.md` D-17: a fake clock, a validating loader for the SIMULATED fixture
catalogue, and declarative fault hooks. The package is **never imported by
production code**.

## What it provides

| Import | Contents |
| --- | --- |
| `package:feldexa_testkit/feldexa_testkit.dart` | Fake clock, fault rules/injector, fixture catalogue and loader, in-memory source, evidence labels, SHA-256. No `dart:io`. |
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

### Evidence labels

`EvidenceClass` is owned by `feldexa_ports` (T014) and re-exported here; the
toolkit no longer declares a second enum. `EvidenceClass` and `EvidenceLabel`
encode `NONE`, `SIMULATED`, `EMULATOR`, and `DEVICE`.
`EvidenceLedger.requireSeparated()` rejects a report that merges SIMULATED with
EMULATOR/DEVICE. Using this package never upgrades a run's class: T011's own
package tests are host-VM checks and therefore produce no runtime evidence.

## Verification

```sh
flutter analyze --no-pub packages/feldexa_testkit
flutter test --no-pub packages/feldexa_testkit
```

Both are host-side checks. They do not prove Android import, storage, OCR,
export, or device acceptance; those remain with their own tasks and must be
reported as `EMULATOR` or `DEVICE` evidence.
