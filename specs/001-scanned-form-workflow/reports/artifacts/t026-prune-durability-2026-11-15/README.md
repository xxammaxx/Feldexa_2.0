# T026 prune-durability evidence bundle (2026-11-15)

This bundle binds the security-review correction that keeps the head history
complete until prune deletes are durably fsynced, without publishing raw
logcat or APK binaries.

## Bound evidence

- base commit `d78114fdb703c405fe4692fe287e71095b50fc59`;
- implementation commit `0c75c57fdaa592c8a5ec4ccf8339e8b31e800965`;
- app APK `2a7b04d6e7394f29c2a8cccffd34d20eac8cd011159eb6ab8e1210bf2b43f04e`
  and test APK `ce28c7357d4a0cbbac64c58b8d0ea47384bca4ba1772950589fe3b41e764ffe0`,
  including the guest-pulled copies;
- eight JUnit XML files for the 120-test JVM suite;
- `17/17` T026 and `29/29` T025+T026 instrumentation results on the Orca
  Pixel 7 API 35 AVD;
- the device profile, allocation record, toolchain, and the prune-durability
  finding summary;
- hashes (not contents) of the raw local logcat files.

## Verify

```sh
cd specs/001-scanned-form-workflow/reports/artifacts/t026-prune-durability-2026-11-15
./verify.sh
```

Raw logcat, absolute paths, raw Orca session/runtime ids, and APK binaries are
intentionally not published. `verify.sh` checks every committed file and the
APK hashes when the local build output exists.
