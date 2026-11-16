# T027 Review-B correction evidence artifacts

Candidate code commit: `94ef57b059c71fad01b0f3d46743996325a08dc7`
Candidate tree: `0444e300e6a4bb0d7b7e21705cc65d635c98c5d0`
Base: `15aab0c55c7e77df0d4c4fe199e89c6661ea3db2`
Date: 2026-11-16 (Europe/Berlin)

This directory binds the host (`NONE`) and Android `EMULATOR` evidence for the
accepted Review B finding on `db8ce0f`: `SignaturePng` accepted opaque colour
types 0/2/3 without an alpha channel or a valid `tRNS` chunk, while
`contracts/storage-format.md` §2.4 requires a signature PNG to carry alpha.
The correction accepts native alpha colour types 4/6 and validates a `tRNS`
chunk's type, bit depth, palette length/order and sample ranges; truly
alpha-free images are rejected with canonical `SAVE-007` without transcoding
or mutating the signed bytes, and prior signature bytes/head/revisions stay
unchanged.

- `source-sha256.txt` — 281 tracked source/input files; the before- and
  after-run manifests are byte-identical (`dd96bdf1…`).
- `generated-config-sha256.txt` — the four generated config files used by the
  build (`64843c67…`); a second offline `pub get` reproduced them.
- `junit/` — 13 JVM XML files (260 tests), `storage-connected.xml` (34 tests)
  and `channel-connected.xml` (20 tests), unmodified.
- `logs/` — path-redacted committed copies. Raw, local copies and their
  SHA-256 values are in `raw-evidence-sha256.txt`; they live under the
  git-ignored `build/t027-review3/`.
- `apk-sha256.txt` — standalone app, AndroidTest and Dart integration-harness
  APK hashes; the APKs themselves are local, git-ignored build outputs.
- `manifest.json` — machine-readable counts, SHAs and artifact byte/hash rows.
- `final-artifacts.txt` — flat artifact listing.
- `verify.sh` — re-checks the committed source manifest and, when present, the
  local APK bytes.

The report and this bundle are in a later docs-only commit; the code commit
above is the reviewed candidate. The final branch SHA is named in the active
`worker_done` attestation.

Run from the repository root:

```sh
bash specs/001-scanned-form-workflow/reports/artifacts/t027-review-b-94ef57b/verify.sh
```
