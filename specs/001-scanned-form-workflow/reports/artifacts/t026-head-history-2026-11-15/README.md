# T026 head-history evidence bundle (2026-11-15)

This bundle binds the owner-decided bounded head history and automatic
retention implementation without publishing raw logcat or APK binaries.

## Bound evidence

- base commit `d78114fdb703c405fe4692fe287e71095b50fc59`;
- implementation commit `c30cb669c1a23f4eaea13ad9da42f775b4dd4935`;
- app APK `b35ba8609ba126ea70d914073f7183de7f6899231ba8dd8a03d596762cdc2535`
  and test APK `b9102dd9cc89b9f1a07c706a8850eec0a855de53a304c7177af7045099f1058f`,
  including the guest-pulled copies;
- seven JUnit XML files for the 118-test JVM suite;
- `16/16` T026 and `28/28` T025+T026 instrumentation results on the Orca
  Pixel 7 API 35 AVD;
- the device profile, allocation record, toolchain, and the policy summary;
- hashes (not contents) of the raw local logcat files.

## Verify

```sh
cd specs/001-scanned-form-workflow/reports/artifacts/t026-head-history-2026-11-15
./verify.sh
```

Raw logcat, absolute paths, raw Orca session/runtime ids, and APK binaries are
intentionally not published. `verify.sh` checks every committed file and the
APK hashes when the local build output exists.
