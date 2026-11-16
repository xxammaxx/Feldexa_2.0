# T026 review-correction evidence bundle (2026-11-15)

This bundle makes the T026 review-correction evidence verifiable from a normal
checkout, without publishing sensitive raw logs or the 216 MiB app APK.

## What is bound

- base commit `d78114fdb703c405fe4692fe287e71095b50fc59`;
- implementation commit `84f2276a4ccf9ae7345a56861cad9d82c1d39e80`;
- app and instrumentation-test APK paths, byte sizes, and SHA-256 values;
- the five JUnit XML result files from the 109-test JVM run;
- the redacted T026 and combined instrumentation logs (`13/13` and `25/25`);
- the Pixel 7 / API 35 device profile, boot, package-service, and guest CPU
  flags, plus the redacted Orca allocation/exclusivity record;
- the toolchain versions;
- deterministic reproduction summaries for the race, memory, recovery, and
  pruning findings;
- hashes (not contents) of the raw local logcat files.

## What is intentionally not published

- raw logcat (potential device/app noise) - only its size, SHA-256, and FATAL
  count are in `manifest.json`;
- APK binaries (the app APK is 216 MiB) - their exact hashes are bound and the
  build commands are reproducible; `verify.sh` reports them `ABSENT` when the
  build output is not present in the checkout;
- absolute home/worktree/SDK paths, raw Orca session/runtime ids, and terminal
  or task ids. Logs were redacted; JUnit `hostname` is replaced with `host`.

## Verify the bundle

```sh
cd specs/001-scanned-form-workflow/reports/artifacts/t026-review-2026-11-15
./verify.sh
```

The script checks every committed file against `manifest.json`. It also checks
the app/test APKs when the local build output exists; otherwise it prints
`ABSENT` and still verifies the rest of the bundle.

## Rebuild and re-run

Follow the reproducibility steps in
`../../2026-11-15-t026-review-corrections-evidence.md` and
`../../2026-11-15-emulator-t026-review-corrections-pixel7-api35.md`.
The APK hashes are bound to the toolchain in `logs/toolchain-versions.log`; a
different debug build may not be byte-identical, but the test suites and
assertions are the review gate.

## Host KVM

`emulator -accel-check` was `UNAVAILABLE` inside the worker sandbox (no
`/dev/kvm`). The guest reports `hypervisor`, `avx`, and `f16c`, uses
`ro.kernel.qemu=1`, and the AVD is the T025-provisioned Pixel 7 API 35 image.
No independent host-KVM claim is made.
