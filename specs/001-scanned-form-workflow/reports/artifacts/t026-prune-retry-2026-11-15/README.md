# T026 prune-retry evidence bundle (2026-11-15)

This bundle binds the security-review correction that confirms directory
durability before dropping a missing known revision from history, without
publishing raw logcat or APK binaries.

## Bound evidence

- base commit `d78114fdb703c405fe4692fe287e71095b50fc59`;
- implementation commit `57ce38bf0d1f9487926c8b7d775397604f7f125d`;
- app APK `518a0a37fe50e956482d0d313b16c953843f6519b18eb22700ede9c920d51860`
  and test APK `00f73e17e6f734a8260baa139f3e4880e056b8979038041d44d5723b5e6e3452`,
  including the guest-pulled copies;
- eight JUnit XML files for the 122-test JVM suite;
- `18/18` T026 and `30/30` T025+T026 instrumentation results on the Orca
  Pixel 7 API 35 AVD;
- the device profile, allocation record, toolchain, and the retry finding
  summary;
- hashes (not contents) of the raw local logcat files.

## Verify

```sh
cd specs/001-scanned-form-workflow/reports/artifacts/t026-prune-retry-2026-11-15
./verify.sh
```

Raw logcat, absolute paths, raw Orca session/runtime ids, and APK binaries are
intentionally not published. `verify.sh` checks every committed file and the
APK hashes when the local build output exists.
