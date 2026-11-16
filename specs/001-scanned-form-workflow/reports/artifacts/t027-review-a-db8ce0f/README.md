# T027 Review-A correction evidence artifacts

Candidate code commit: `db8ce0f91e364f64107f860bd69c8dc8cacddb3c`
Candidate tree: `c7c8bcf096f5a1517c65f5a02e5ef3906af89914`
Base: `15aab0c55c7e77df0d4c4fe199e89c6661ea3db2`
Branch: T027 worktree branch (see git ref)
Date: 2026-11-16 (Europe/Berlin)

This directory binds the host (`NONE`) and Android `EMULATOR` evidence for the
two accepted Review A findings: the production store root now matches
`contracts/storage-format.md` §1 (`filesDir/feldexa/`), and a signature upload
is a real, fully decodable PNG with positive dimensions whose long edge is at
most 1024 px. The 2 MiB cap, immutable `PLT-002` refusal, canonical `SAVE-007`,
prior bytes/head/revisions preservation, cryptography, read-back, source
ownership, and privacy rules are unchanged.

- `source-sha256.txt` — 281 tracked source/input files; the before- and
  after-run manifests were byte-identical (`30ea34f9…`).
- `generated-config-sha256.txt` — the four generated config files used by the
  build. `flutter clean` removed and `flutter pub get --offline
  --enforce-lockfile` regenerated `.flutter-plugins-dependencies`; the
  regenerated state (`4f6f9cc7…`) was stable across a second pub-get and the
  build.
- `junit/` — 13 JVM XML files (252 tests), `storage-33-tests.xml`, and
  `channel-20-tests.xml` (unmodified).
- `logs/` — path-redacted committed copies. The raw, local copies and their
  SHA-256 values are listed in `raw-evidence-sha256.txt`; they live under the
  git-ignored `build/t027-review2/`.
- `apk-sha256.txt` — standalone app, AndroidTest, and Dart integration-harness
  APK hashes. APKs themselves are local, git-ignored build outputs.
- `manifest.json` — machine-readable counts, SHAs, and artifact byte/hash rows.
- `final-artifacts.txt` — flat artifact listing.
- `verify.sh` — re-checks the committed source manifest and, when present, the
  local APK bytes.

Run from the repository root:

```sh
bash specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/verify.sh
```
