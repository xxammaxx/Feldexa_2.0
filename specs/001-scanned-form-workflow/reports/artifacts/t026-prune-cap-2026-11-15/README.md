# T026 prune-cap evidence bundle (2026-11-15)

This bundle binds the security-review correction that prevents the 16-entry
history cap from silently evicting an unconfirmed missing revision, without
publishing raw logcat or APK binaries.

## Bound evidence

- base commit `d78114fdb703c405fe4692fe287e71095b50fc59`;
- implementation commit `df625d7e938cdc34b2b893191a0dea9a0bbe426a`;
- app APK `753c9e285b2a847a5d30940730b7321cd20a91f471f00ffe160d24daf2c4bf0d`
  and test APK `290b1fca7ffca5913dc91e4bc54a6894723fc8e39672c1799cd0e39cdc338c18`,
  including the guest-pulled copies;
- eight JUnit XML files for the 123-test JVM suite;
- `19/19` T026 and `31/31` T025+T026 instrumentation results on the Orca
  Pixel 7 API 35 AVD;
- the device profile, allocation record, toolchain, capacity finding summary,
  and the documented alternative options;
- hashes (not contents) of the raw local logcat files.

## Verify

```sh
cd specs/001-scanned-form-workflow/reports/artifacts/t026-prune-cap-2026-11-15
./verify.sh
```

Raw logcat, absolute paths, raw Orca session/runtime ids, and APK binaries are
intentionally not published. `verify.sh` checks every committed file and the
APK hashes when the local build output exists.
