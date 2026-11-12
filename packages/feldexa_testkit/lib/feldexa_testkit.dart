// Feldexa test toolkit (T011).
//
// Test-only helpers required by plan §Architecture Decisions 10:
//   * a deterministic fake clock (ClockPort-shaped),
//   * a validating fixture loader for the T009 SIMULATED catalogue,
//   * declarative fault hooks for storage, keystore, and export failures,
//   * typed SIMULATED / EMULATOR / DEVICE evidence labels.
//
// This package is never imported by production code. The default barrel has no
// dart:io import, so browser tests can reuse the catalogue model, clock, fault
// injector, and in-memory source. Host tests additionally import
// `package:feldexa_testkit/io.dart`.
//
// Evidence boundary: using this package never upgrades a result's class. Host
// checks remain NONE; Chrome runs remain SIMULATED; only an actual Android
// emulator or device run may be reported as EMULATOR or DEVICE.
library;

export 'src/clock/fake_clock.dart';
export 'src/evidence/evidence.dart';
export 'src/faults/fault_injector.dart';
export 'src/faults/fault_kind.dart';
export 'src/faults/fault_rule.dart';
export 'src/fixtures/fixture_catalog.dart';
export 'src/fixtures/fixture_loader.dart';
export 'src/fixtures/fixture_path.dart';
export 'src/fixtures/fixture_source.dart';
export 'src/fixtures/sha256.dart' show sha256Hex;
