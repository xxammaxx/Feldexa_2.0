# T026 mtime-durability evidence bundle (2026-11-15)

This bundle binds the security-review correction for revision-order metadata
durability without publishing raw logcat or the 216 MiB app APK.

## Bound evidence

- base commit `d78114fdb703c405fe4692fe287e71095b50fc59`;
- implementation commit `53ffe78e0f9c7ed1939fc1ec0846c3e391927588`;
- app APK `93b92c585e3a5b401c5e0dbd14d322fcfdc171216b1f7760f799672d8b0e0ac5`
  and test APK `82711d4215d6fa24d754f5b26490effec216bf6db8155ff105f2d7768890d8a2`,
  including the guest-pulled copies;
- seven JUnit XML files for the 114-test JVM suite;
- `13/13` T026 and `25/25` T025+T026 instrumentation results on the Orca
  Pixel 7 API 35 AVD;
- the device profile, allocation record, and toolchain;
- the exact ordering-finding note;
- hashes (not contents) of the raw local logcat files.

## Verify

```sh
cd specs/001-scanned-form-workflow/reports/artifacts/t026-mtime-2026-11-15
./verify.sh
```

Raw logcat, absolute paths, raw Orca session/runtime ids, and the APK binaries
are intentionally not published. `verify.sh` checks every committed file and
the APK hashes when the local build output exists.
