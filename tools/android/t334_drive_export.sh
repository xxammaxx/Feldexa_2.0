#!/usr/bin/env bash
# T334 host driver: runs the filled-value export journey and picks up the PDF.
#
# The journey is issue #334 acceptance criterion 5 (`integration_test/
# android_export_test.dart`): import the committed two-page `sf-001.pdf`,
# analyze both real pages, confirm the fixture-declared field „Familienname“ by
# its label, fill it through the production value sheet with a value that
# carries umlauts, export the live revision through the production
# `ExportController`, assert the verified artifact, and delete it again through
# the production preview route.
#
# This script:
#   1. admits the whole run into the shared heavy-work permits by re-executing
#      itself through `compute_slot.py --wait --resource build --resource
#      emulator`, so emulator foreground use, Gradle, and the Flutter test share
#      one host permit with every other heavy job. There is deliberately no Orca
#      command and no Orca gate, one admission mode only, and no detached job;
#   2. binds the device by ADB serial and AVD identity: exactly one attached
#      `emulator-<n>` transport, the expected serial, AVD name, API level,
#      `qemu=1`, and a completed boot. A wireless or physical phone transport is
#      counted but never addressed;
#   3. stages the committed synthetic `sf-001.pdf` fixture and verifies its
#      SHA-256 and size on the host and on the device;
#   4. clears the test app data so the journey starts with an empty store (the
#      store probe is exercised on a scratch tree first, so its three outcomes
#      are evidenced), then runs `flutter test
#      integration_test/android_export_test.dart -d <serial>` in the foreground
#      and writes the log;
#   5. after a green run, picks the artifact bytes the test left in the
#      app-internal cache up with `run-as`, verifies them against the digest and
#      size the test printed, and clears the app data again;
#   6. proves the picked file with external tools on the host: `pdfinfo` page
#      count and page size against the source fixture, `pdftotext` for the
#      expected value, a byte search for `/AcroForm`, `/Widget`, and `/FT /Tx`,
#      and — for every leg that drew a value — the 1 mm placement verdict of
#      `tools/pdf_verify/placement.py`. The driver measures no placement itself:
#      one metric, derived from the layout code that draws the value, and a
#      drawn value without a `PROVEN` verdict ends the run;
#   7. records device identity, fixture/APK hashes, git identity (HEAD/tree/
#      branch/subject/status), the permit admission, the `flutter analyze` and
#      `dart format` gates, the marker sequence extracted from the integration
#      log, and a source-level and log-level privacy check.
#
# The third artifact is the flattening proof of issue #344: `sf-acroform-001.pdf`
# really carries an AcroForm text field (proved in `fixture-acroform-proof.txt`
# from `pdfinfo` and a byte search), is exported unchanged through the
# production controller, and its artifact has to be free of `/AcroForm`,
# `/Widget`, and `/FT /Tx` while `pdftotext` still yields the fixture's field
# value — the flattening kept the visible content instead of dropping it.
#
# The tree must be committed before the run: the working tree must be clean.
#
# Evidence class is EMULATOR only when step 2 passes. Without a booted,
# available emulator the script exits 2 with `EMULATOR NOT_RUN`; the physical
# Samsung S23 is never addressed.
#
# The evidence metadata files are committed, so the driver records
# repo-relative paths only (`apps/...` instead of `/home/...`). The driver fails
# closed: a missing marker, a digest mismatch, a missing Poppler tool, or
# SIGINT/SIGTERM can never end as a pass.
#
# Test-only tooling: adds no production dependency and changes no app file.
# Usage (repo root): tools/android/t334_drive_export.sh
set -uo pipefail

# Device identity is fixed by the workspace policy (AGENTS.md): the one KVM
# emulator `emulator-5554`, AVD `T025_Pixel7_API35_KVM_20261115`, API 35. The
# `T334_*` overrides stay for a renamed AVD, but they never act silently and
# never move the run to a physical device; see the announcement block below.
SERIAL="emulator-5554"
EXPECTED_AVD="T025_Pixel7_API35_KVM_20261115"
EXPECTED_API="35"
ADB="${T334_ADB:-$HOME/Android/Sdk/platform-tools/adb}"
FLUTTER="${T334_FLUTTER:-$HOME/flutter/bin/flutter}"
DART="${T334_DART:-$(dirname "$FLUTTER")/dart}"
COMPUTE_SLOT="${T334_COMPUTE_SLOT:-$HOME/.pi/agent/skills/pi-maintainer/scripts/compute_slot.py}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SELF="$ROOT/tools/android/t334_drive_export.sh"
APP="$ROOT/apps/feldexa_app"
TEST_FILE="integration_test/android_export_test.dart"
BACKUP_DIR=""

STAGING="/data/local/tmp/t334-fixtures"
PACKAGE="de.feldexa.app"
FIXTURE="sf-001.pdf"
FIXTURE_SHA256="22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038"
FIXTURE_SIZE_BYTES=5956
EXPECTED_PAGE_COUNT=2
# The third leg exports a source that really carries an AcroForm text field, so
# the flattening (`EXP-002`/FR-069) is proven instead of being asserted on a
# source without fields. Its field value lives in the widget appearance; the
# host's `pdftotext` run proves that the flattening kept it visible.
ACROFORM_FIXTURE="sf-acroform-001.pdf"
ACROFORM_FIXTURE_SHA256="7f4e014482425518058e28c497b9e8bcf4a4930dec1dbd5edb74cb8c8992af9a"
ACROFORM_FIXTURE_SIZE_BYTES=1424
ACROFORM_PAGE_COUNT=1
ACROFORM_VALUE="Feldwert"
ARTIFACT_COUNT=4
EXPECTED_VALUE="Müller"
# Per-artifact expectations of the pickup and Poppler proof. Index 1/2 export
# `sf-001.pdf` (2 pages, the journey's drawn `Müller` value); index 3 exports the
# one-page AcroForm fixture unchanged (its own value `Feldwert`, no drawn value,
# so no 1 mm placement claim); index 4 is the T109 mark leg: a two-page `sf-001`
# export with one text value, a checked and an unchecked checkbox, and two
# signatures, verified with the T105 harness and the test's own field rects.
artifact_source_fixture() {
  case "$1" in
    1 | 2 | 4) printf '%s\n' "$FIXTURE" ;;
    3) printf '%s\n' "$ACROFORM_FIXTURE" ;;
    *) return 1 ;;
  esac
}

artifact_source_pages() {
  case "$1" in
    1 | 2 | 4) printf '%s\n' "$EXPECTED_PAGE_COUNT" ;;
    3) printf '%s\n' "$ACROFORM_PAGE_COUNT" ;;
    *) return 1 ;;
  esac
}

artifact_expected_value() {
  case "$1" in
    1 | 2 | 4) printf '%s\n' "$EXPECTED_VALUE" ;;
    3) printf '%s\n' "$ACROFORM_VALUE" ;;
    *) return 1 ;;
  esac
}

# The in-app cache path of artifact [index] (see `_artifactRelativePath` in the
# integration test: index 1 keeps the historical file name).
artifact_relative_path() {
  case "$1" in
    1) printf '%s\n' 'e2e/export-artifact.pdf' ;;
    *) printf '%s\n' "e2e/export-artifact-$1.pdf" ;;
  esac
}

# 1 mm in PDF points (1 pt = 1/72 in). This is a verification threshold of the
# host measurement, never a product value.
PLACEMENT_TOLERANCE_PT="2.835"

TEST_PID=""
TEST_EXIT=255
CLEANED=0
PRIVACY_PASS=0

log() {
  printf '%s\n' "$*"
}

fail() {
  log "T334 DRIVER: $*"
  exit 1
}

not_run() {
  log "T334 EMULATOR NOT_RUN: $*"
  exit 2
}

# Evidence files are committed, so they never carry an absolute host path.
host_relative() {
  local path="$1"
  if [[ "$path" == "$ROOT/"* ]]; then
    printf '%s\n' "${path#"$ROOT"/}"
  elif [[ "$path" == "$HOME/"* ]]; then
    printf '~/%s\n' "${path#"$HOME"/}"
  else
    printf '%s\n' "$path"
  fi
}

# --- 0a. Workspace device identity (AGENTS.md) -------------------------------
# An override is announced on the console before anything is admitted, and a
# serial that is not an emulator transport is refused here instead of being
# addressed: the physical Samsung S23 is never a target of this driver.
if [[ -n "${T334_SERIAL:-}" && "$T334_SERIAL" != "$SERIAL" ]]; then
  [[ "$T334_SERIAL" =~ ^emulator-[0-9]+$ ]] ||
    fail "T334_SERIAL override refuses a non-emulator serial: $T334_SERIAL"
  log "T334 DRIVER: WARNING T334_SERIAL=$T334_SERIAL overrides the workspace serial $SERIAL"
  SERIAL="$T334_SERIAL"
fi
if [[ -n "${T334_AVD:-}" && "$T334_AVD" != "$EXPECTED_AVD" ]]; then
  log "T334 DRIVER: WARNING T334_AVD=$T334_AVD overrides the workspace AVD $EXPECTED_AVD"
  EXPECTED_AVD="$T334_AVD"
fi
if [[ -n "${T334_API:-}" && "$T334_API" != "$EXPECTED_API" ]]; then
  log "T334 DRIVER: WARNING T334_API=$T334_API overrides the workspace API level $EXPECTED_API"
  EXPECTED_API="$T334_API"
fi

# --- 0. Shared heavy-work permit admission ----------------------------------
# The whole journey (emulator foreground use, Gradle, Flutter test) runs inside
# the cooperative host permits, both declared up front: `build` (which also
# claims the HDD-intensive `io` slot) and `emulator`. The guard token stops a
# re-exec loop; a caller that already holds the permits sets it and the driver
# runs inside that same critical section.
if [[ "${T334_COMPUTE_LOCK_HELD:-0}" != "1" ]]; then
  [[ -f "$COMPUTE_SLOT" ]] ||
    fail "shared heavy-work lock script not found at $COMPUTE_SLOT"
  log "T334 DRIVER: admitting the run into the shared heavy-work permits (build, emulator)"
  exec python3 "$COMPUTE_SLOT" --wait --resource build --resource emulator -- \
    env T334_COMPUTE_LOCK_HELD=1 \
    T334_SERIAL="$SERIAL" \
    T334_AVD="$EXPECTED_AVD" \
    T334_API="$EXPECTED_API" \
    T334_ADB="$ADB" \
    T334_FLUTTER="$FLUTTER" \
    T334_COMPUTE_SLOT="$COMPUTE_SLOT" \
    T334_RUN_DIR="${T334_RUN_DIR:-}" \
    T334_EVIDENCE_DIR="${T334_EVIDENCE_DIR:-}" \
    bash "$SELF" "$@"
fi

RUN_DIR="${T334_RUN_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/feldexa-t334-run.XXXXXX")}"
EVIDENCE_DIR="${T334_EVIDENCE_DIR:-$ROOT/specs/001-scanned-form-workflow/reports/artifacts/2026-11-27-t109-export-harness}"
LOG="$RUN_DIR/integration-android-t334.log"
SEQUENCE="$RUN_DIR/marker-sequence.txt"
ADB_STDERR_LOG="$RUN_DIR/adb-stderr.log"

if [[ -n "${T334_RUN_DIR:-}" ]]; then
  if [[ -e "$RUN_DIR" ]]; then
    log "T334 DRIVER: refusing to reuse existing run directory $RUN_DIR"
    exit 1
  fi
  mkdir -p "$RUN_DIR" || {
    log "T334 DRIVER: cannot create run directory $RUN_DIR"
    exit 1
  }
fi
: >"$SEQUENCE" || fail "cannot create the marker sequence file $SEQUENCE"
: >"$ADB_STDERR_LOG" || fail "cannot create the adb stderr log $ADB_STDERR_LOG"

# Device-side stderr is a diagnosis trail, never noise: it lands in the run log
# (`adb-stderr.log`, part of the evidence bundle) while the exit code of the adb
# call stays visible to the caller, which checks it at every decision point.
# Every call is bounded by `ADB_SHELL_TIMEOUT` (default 120s) so no wait loop can
# hang on a dead transport; a caller with a tighter deadline lowers the limit.
adb_shell() {
  timeout "${ADB_SHELL_TIMEOUT:-120}" "$ADB" -s "$SERIAL" shell "$@" 2>>"$ADB_STDERR_LOG" | tr -d '\r'
  return "${PIPESTATUS[0]}"
}

record() {
  log "T334 DRIVER: $*"
  printf '%s\n' "$*" >>"$SEQUENCE"
}

cleanup() {
  if [[ "$CLEANED" -eq 1 ]]; then
    return
  fi
  CLEANED=1
  set +e
  if [[ -n "$TEST_PID" ]] && kill -0 "$TEST_PID" 2>/dev/null; then
    kill "$TEST_PID" 2>/dev/null
    wait "$TEST_PID" 2>/dev/null
  fi
  adb_shell rm -rf "$STAGING" >/dev/null
  adb_shell am force-stop "$PACKAGE" >/dev/null
  adb_shell pm clear "$PACKAGE" >/dev/null 2>&1
}
trap cleanup EXIT

on_signal() {
  local signal="$1" code="$2"
  trap - EXIT INT TERM
  log "T334 DRIVER: received SIG$signal; cleaning up and aborting"
  cleanup
  exit "$code"
}
trap 'on_signal INT 130' INT
trap 'on_signal TERM 143' TERM

transport_summary() {
  local all="$1" emulators="$2"
  local all_count emulator_count
  all_count="$(printf '%s\n' "$all" | sed '/^$/d' | wc -l)"
  emulator_count="$(printf '%s\n' "$emulators" | sed '/^$/d' | wc -l)"
  log "all_attached_transports_count=$all_count"
  log "emulator_transports=$emulator_count"
  log "non_emulator_transports=$((all_count - emulator_count))"
}

prepare_evidence_dir() {
  if [[ "$EVIDENCE_DIR" == "$RUN_DIR" ]]; then
    fail "evidence directory must not be the run directory root"
  fi
  if [[ -L "$EVIDENCE_DIR" ]]; then
    fail "evidence path must not be a symbolic link: $EVIDENCE_DIR"
  fi
  if [[ -e "$EVIDENCE_DIR" ]]; then
    [[ -d "$EVIDENCE_DIR" ]] || fail "evidence path is not a directory: $EVIDENCE_DIR"
    local first
    # A `find` failure is a tool failure, not an empty directory: it must not
    # skip the backup guard below.
    first="$(find "$EVIDENCE_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ||
      fail "cannot scan the existing evidence directory $EVIDENCE_DIR"
    if [[ -n "$first" ]]; then
      if [[ "${T334_REPLACE_EVIDENCE:-0}" != "1" ]]; then
        fail "refusing to overwrite existing evidence in $EVIDENCE_DIR; bind a fresh T334_EVIDENCE_DIR or set T334_REPLACE_EVIDENCE=1 to back up and replace"
      fi
      BACKUP_DIR="$RUN_DIR/evidence-backup"
      mkdir -p "$BACKUP_DIR" || fail "cannot create evidence backup directory"
      cp -a "$EVIDENCE_DIR"/. "$BACKUP_DIR"/ || fail "evidence backup failed"
      log "T334 DRIVER: backed up existing evidence to $BACKUP_DIR"
    fi
  else
    mkdir -p "$EVIDENCE_DIR" || fail "cannot create evidence directory $EVIDENCE_DIR"
  fi
}

collect_evidence() {
  local file
  local -a artifact_files=()
  local index
  for index in $(seq 1 "$ARTIFACT_COUNT"); do
    artifact_files+=(
      "artifact-$index-pickup.txt"
      "artifact-$index-pdfinfo.txt"
      "artifact-$index-pdftotext.txt"
      "artifact-$index-acroform.txt"
      "artifact-$index-placement.txt"
      "harness-artifact-$index.json"
      "harness-artifact-$index-console.txt"
      "expectations-artifact-$index.json"
    )
  done
  for file in \
    integration-android-t334.log \
    adb-stderr.log \
    markers-integration.txt \
    marker-sequence.txt \
    run-status.txt \
    device-identity.txt \
    device-binding.txt \
    compute-lock.txt \
    fixture-sha256.txt \
    fixture-acroform-proof.txt \
    pdfinfo-source-acroform.txt \
    apk-sha256.txt \
    git-identity.txt \
    "${artifact_files[@]}" \
    privacy-source-check.txt \
    privacy-log-check.txt \
    store-probe.txt \
    gate-analyze.txt \
    gate-format.txt \
    host-flutter-pub-get.log; do
    if [[ -f "$RUN_DIR/$file" ]]; then
      sed -e "s|$ROOT/||g" -e "s|$ROOT|.|g" -e "s|$HOME/|~/|g" "$RUN_DIR/$file" \
        >"$EVIDENCE_DIR/$file" ||
        fail "cannot write evidence file $file"
    fi
  done
  for index in $(seq 1 "$ARTIFACT_COUNT"); do
    if [[ -f "$RUN_DIR/export-artifact-$index.pdf" ]]; then
      cp "$RUN_DIR/export-artifact-$index.pdf" "$EVIDENCE_DIR/export-artifact-$index.pdf" ||
        fail "cannot write artifact $index into the evidence directory"
    fi
  done
  log "T334 DRIVER: evidence written to $EVIDENCE_DIR"
}

# The bundle is committed, so no evidence text file may carry an absolute home
# path; [collect_evidence] rewrites the host paths on the way in. This is the
# last decision point before the result is fixed: only grep exit 1 (no match)
# is clean, 0 is a hit, and >=2 is a tool error that must not read as clean.
scan_evidence_home_paths() {
  local hits scan_exit
  hits="$(grep -rl --include='*.txt' -F '/home/' "$EVIDENCE_DIR")"
  scan_exit=$?
  if [[ "$scan_exit" -gt 1 ]]; then
    log "T334 DRIVER: the evidence home-path scan failed with exit $scan_exit"
    return 2
  fi
  if [[ -n "$hits" ]]; then
    log "T334 DRIVER: an evidence text file still carries an absolute home path: $hits"
    return 1
  fi
  return 0
}

log "T334 DRIVER: run directory $RUN_DIR"
log "T334 DRIVER: shared heavy-work permits admitted (build, emulator)"

if [[ ! -x "$FLUTTER" ]]; then
  fail "flutter executable not found at $FLUTTER"
fi
if [[ ! -x "$ADB" ]]; then
  fail "adb executable not found at $ADB"
fi
if [[ ! -x "$DART" ]]; then
  fail "dart executable not found at $DART"
fi

{
  log "mode=shared-heavy-work-permits"
  log "admission=python3 $(host_relative "$COMPUTE_SLOT") --wait --resource build --resource emulator -- <driver>"
  log "resources=build(+io),emulator"
  log "inside_permits=1 (T334_COMPUTE_LOCK_HELD=1)"
  log "orca_command_used=0"
  log "detached_jobs=0"
  log "admitted_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >"$RUN_DIR/compute-lock.txt"

# --- 1. Device identity, emulator only --------------------------------------
ALL_TRANSPORTS="$(timeout 60 "$ADB" devices | awk 'NR>1 && NF>=1 && $1 !~ /^(List|of|devices)$/ {print $1}')"
ALL_DEVICES="$(timeout 60 "$ADB" devices | awk 'NR>1 && NF>=2 && $2=="device" {print $1}')"
EMULATOR_DEVICES="$(printf '%s\n' "$ALL_DEVICES" | grep -E '^emulator-[0-9]+$')"
EMULATOR_GREP_EXIT=$?
[[ "$EMULATOR_GREP_EXIT" -le 1 ]] ||
  not_run "cannot read the attached emulator transports (grep exit $EMULATOR_GREP_EXIT)"
[[ "$(printf '%s\n' "$EMULATOR_DEVICES" | sed '/^$/d' | wc -l)" -eq 1 ]] ||
  not_run "expected exactly one attached emulator, got: ${EMULATOR_DEVICES:-none}"
[[ "$EMULATOR_DEVICES" == "$SERIAL" ]] ||
  not_run "attached emulator is $EMULATOR_DEVICES, expected $SERIAL"
[[ "$SERIAL" =~ ^emulator-[0-9]+$ ]] ||
  not_run "refusing a non-emulator serial: $SERIAL"

SDK="$(adb_shell getprop ro.build.version.sdk)"
AVD_NAME="$(adb_shell getprop ro.boot.qemu.avd_name)"
QEMU="$(adb_shell getprop ro.kernel.qemu)"
[[ "$SDK" == "$EXPECTED_API" ]] ||
  not_run "API $EXPECTED_API required, device reports sdk=$SDK"
[[ "$AVD_NAME" == "$EXPECTED_AVD" ]] ||
  not_run "AVD $EXPECTED_AVD required, device reports '$AVD_NAME'"
[[ "$QEMU" == "1" ]] ||
  not_run "device is not a QEMU/KVM emulator (ro.kernel.qemu=$QEMU)"
[[ "$(adb_shell getprop sys.boot_completed)" == "1" ]] ||
  not_run "device has not completed boot"

{
  log "serial=$SERIAL"
  log "emulator_serials=$(printf '%s\n' "$EMULATOR_DEVICES" | sed '/^$/d' | paste -sd, -)"
  transport_summary "$ALL_TRANSPORTS" "$EMULATOR_DEVICES"
  log "addressed_serial=$SERIAL"
  log "non_emulator_transports_addressed=none"
} >"$RUN_DIR/device-binding.txt"

# --- 1b. Commit-before-run gate ---------------------------------------------
DIRTY_STATUS="$(git -C "$ROOT" status --porcelain)" ||
  fail "cannot read git status for $ROOT"
if [[ -n "$DIRTY_STATUS" ]]; then
  while IFS= read -r dirty_line; do
    fail "working tree is dirty; commit-before-run required (status line: $dirty_line)"
  done <<<"$DIRTY_STATUS"
fi
log "T334 DRIVER: commit-before-run gate passed (working tree must be clean)"

prepare_evidence_dir
log "T334 DRIVER: evidence directory $EVIDENCE_DIR"

{
  log "serial=$SERIAL"
  log "avd=$AVD_NAME"
  log "fingerprint=$(adb_shell getprop ro.build.fingerprint)"
  log "android_release=$(adb_shell getprop ro.build.version.release)"
  log "sdk=$SDK"
  log "abi=$(adb_shell getprop ro.product.cpu.abi)"
  log "boot_completed=$(adb_shell getprop sys.boot_completed)"
  log "qemu=$QEMU"
  log "wm_size=$(adb_shell wm size | tr '\n' ' ')"
  log "wm_density=$(adb_shell wm density | tr '\n' ' ')"
} >"$RUN_DIR/device-identity.txt"

# --- 2. Fixture -------------------------------------------------------------
# The pre-run clear is what makes the journey start from an empty store, so it
# is proved instead of assumed. `flutter test` installs the debug app itself, so
# a first run finds no package to clear (and therefore no stored state); as soon
# as the package exists, the clear has to succeed and both store containers have
# to be free of aggregates afterwards. The probe inspects the root the app uses
# (`MainActivity.STORE_ROOT_DIR` = `files/feldexa`) through `run-as`; a missing
# root is the wiped case, any listed entry is a leftover document or template.
# A failing `ls` reports itself (exit 3), so a toybox error can never read as
# "empty" the way an unchecked command substitution would.
STORE_ROOT_ON_DEVICE="files/feldexa"
STORE_PROBE_BODY='base="$1"; for d in "$base/docs" "$base/templates"; do if [ -e "$d" ]; then entries="$(ls -A "$d")" || { echo "PROBE_TOOL_ERROR ls -A $d"; exit 3; }; if [ -n "$entries" ]; then echo "leftover entries in $d"; exit 1; fi; fi; done; echo STORE_EMPTY_OK; exit 0'

adb_shell am force-stop "$PACKAGE" >/dev/null ||
  fail "could not stop $PACKAGE before the pre-run clear"
INSTALLED_PACKAGES="$(adb_shell pm list packages "$PACKAGE")" ||
  fail "cannot query the installed packages for $PACKAGE"
printf '%s\n' "$INSTALLED_PACKAGES" | grep -qx "package:$PACKAGE"
INSTALLED_GREP_EXIT=$?
# Exit 1 is "not installed", a grep error (>=2) is a tool failure, not a state.
[[ "$INSTALLED_GREP_EXIT" -le 1 ]] ||
  fail "the installed-package grep failed with exit $INSTALLED_GREP_EXIT"
if [[ "$INSTALLED_GREP_EXIT" -eq 0 ]]; then
  adb_shell pm clear "$PACKAGE" >/dev/null ||
    fail "pre-run pm clear of $PACKAGE failed"
  PRE_STORE_STATE="$(adb_shell "run-as $PACKAGE sh -c '$STORE_PROBE_BODY' sh '$STORE_ROOT_ON_DEVICE'")"
  [[ "$PRE_STORE_STATE" == *STORE_EMPTY_OK* ]] ||
    fail "the pre-run clear did not leave an empty store: ${PRE_STORE_STATE:-no answer from the store probe}"
  record "pre-run: app data cleared, store proved empty"
else
  record "pre-run: package not installed, no stored state exists"
fi
adb_shell mkdir -p "$STAGING" >/dev/null ||
  fail "cannot create the device staging directory $STAGING"
for staged_fixture in "$FIXTURE" "$ACROFORM_FIXTURE"; do
  timeout 300 "$ADB" -s "$SERIAL" push "$APP/assets/fixtures/$staged_fixture" \
    "$STAGING/$staged_fixture" >/dev/null ||
    fail "staging push failed or timed out: $staged_fixture"
done
adb_shell chmod 755 "$STAGING" >/dev/null ||
  fail "cannot set the mode of the device staging directory $STAGING"
for staged_fixture in "$FIXTURE" "$ACROFORM_FIXTURE"; do
  adb_shell chmod 644 "$STAGING/$staged_fixture" >/dev/null ||
    fail "cannot set the mode of the staged fixture $STAGING/$staged_fixture"
done

# The probe decides the pre-run store state, so its three outcomes are exercised
# with the same body the run uses: an empty root (`STORE_EMPTY_OK`), a leftover
# aggregate (exit 1), and a missing root (the wiped case, `STORE_EMPTY_OK`). The
# transcripts and exit codes go into the evidence bundle.
PROBE_SELFTEST_DIR="$STAGING/store-probe-selftest"
adb_shell rm -rf "$PROBE_SELFTEST_DIR" >/dev/null ||
  fail "cannot reset the store-probe scratch tree $PROBE_SELFTEST_DIR"
adb_shell mkdir -p "$PROBE_SELFTEST_DIR/empty/docs" "$PROBE_SELFTEST_DIR/empty/templates" \
  "$PROBE_SELFTEST_DIR/leftover/docs" >/dev/null ||
  fail "cannot create the store-probe scratch tree $PROBE_SELFTEST_DIR"
adb_shell touch "$PROBE_SELFTEST_DIR/leftover/docs/aggregate.bin" >/dev/null ||
  fail "cannot stage the store-probe leftover aggregate"
{
  log "probe_body=$STORE_PROBE_BODY"
  log "probe_root_used_by_the_run=$STORE_ROOT_ON_DEVICE (MainActivity.STORE_ROOT_DIR)"
  log "expected_exits: empty=0 leftover=1 missing=0 ls_tool_error=3"
} >"$RUN_DIR/store-probe.txt"
for probe_case in empty leftover missing; do  case "$probe_case" in
    empty | missing) PROBE_EXPECTED_EXIT=0 ;;
    leftover) PROBE_EXPECTED_EXIT=1 ;;
  esac
  PROBE_OUTPUT="$(adb_shell "sh -c '$STORE_PROBE_BODY' sh '$PROBE_SELFTEST_DIR/$probe_case'")"
  PROBE_EXIT=$?
  printf '%s\n' "case=$probe_case expected_exit=$PROBE_EXPECTED_EXIT observed_exit=$PROBE_EXIT output=${PROBE_OUTPUT:-<no output>}" \
    >>"$RUN_DIR/store-probe.txt"
  [[ "$PROBE_EXIT" -eq "$PROBE_EXPECTED_EXIT" ]] ||
    fail "store-probe self-test case '$probe_case' exited $PROBE_EXIT, expected $PROBE_EXPECTED_EXIT"
  if [[ "$probe_case" == "leftover" ]]; then
    [[ "$PROBE_OUTPUT" == *"leftover entries in"* ]] ||
      fail "store-probe self-test case 'leftover' did not report the leftover entry"
  else
    [[ "$PROBE_OUTPUT" == *STORE_EMPTY_OK* ]] ||
      fail "store-probe self-test case '$probe_case' did not report STORE_EMPTY_OK"
  fi
done
printf '%s\n' "result=all three store-probe cases behave as expected" >>"$RUN_DIR/store-probe.txt"

# A previous aborted run can leave a pickup acknowledgement behind; remove every
# index before the test starts so no wait can return on a stale ack.
for ack_index in $(seq 1 "$ARTIFACT_COUNT"); do
  adb_shell rm -f "$STAGING/ack-artifact-picked-up-$ack_index" >/dev/null ||
    fail "cannot remove a stale pickup acknowledgement $ack_index from $STAGING"
done

DEVICE_FIXTURE_SHA="$(adb_shell sha256sum "$STAGING/$FIXTURE" | awk '{print $1}')"
HOST_FIXTURE_SHA="$(sha256sum "$APP/assets/fixtures/$FIXTURE" | awk '{print $1}')"
DEVICE_FIXTURE_SIZE="$(adb_shell stat -c %s "$STAGING/$FIXTURE")"
[[ "$DEVICE_FIXTURE_SHA" == "$FIXTURE_SHA256" ]] ||
  fail "device fixture sha256 $DEVICE_FIXTURE_SHA != $FIXTURE_SHA256"
[[ "$HOST_FIXTURE_SHA" == "$FIXTURE_SHA256" ]] ||
  fail "host fixture sha256 $HOST_FIXTURE_SHA != $FIXTURE_SHA256"
[[ "$DEVICE_FIXTURE_SIZE" == "$FIXTURE_SIZE_BYTES" ]] ||
  fail "device fixture size $DEVICE_FIXTURE_SIZE != $FIXTURE_SIZE_BYTES"
DEVICE_ACROFORM_SHA="$(adb_shell sha256sum "$STAGING/$ACROFORM_FIXTURE" | awk '{print $1}')"
HOST_ACROFORM_SHA="$(sha256sum "$APP/assets/fixtures/$ACROFORM_FIXTURE" | awk '{print $1}')"
DEVICE_ACROFORM_SIZE="$(adb_shell stat -c %s "$STAGING/$ACROFORM_FIXTURE")"
[[ "$DEVICE_ACROFORM_SHA" == "$ACROFORM_FIXTURE_SHA256" ]] ||
  fail "device AcroForm fixture sha256 $DEVICE_ACROFORM_SHA != $ACROFORM_FIXTURE_SHA256"
[[ "$HOST_ACROFORM_SHA" == "$ACROFORM_FIXTURE_SHA256" ]] ||
  fail "host AcroForm fixture sha256 $HOST_ACROFORM_SHA != $ACROFORM_FIXTURE_SHA256"
[[ "$DEVICE_ACROFORM_SIZE" == "$ACROFORM_FIXTURE_SIZE_BYTES" ]] ||
  fail "device AcroForm fixture size $DEVICE_ACROFORM_SIZE != $ACROFORM_FIXTURE_SIZE_BYTES"

{
  log "staging $STAGING/$FIXTURE sha256=$DEVICE_FIXTURE_SHA size=$DEVICE_FIXTURE_SIZE"
  log "host $(host_relative "$APP/assets/fixtures/$FIXTURE") sha256=$HOST_FIXTURE_SHA"
  log "pages=$EXPECTED_PAGE_COUNT (the committed fixture is used unchanged)"
  log "staging $STAGING/$ACROFORM_FIXTURE sha256=$DEVICE_ACROFORM_SHA size=$DEVICE_ACROFORM_SIZE"
  log "host $(host_relative "$APP/assets/fixtures/$ACROFORM_FIXTURE") sha256=$HOST_ACROFORM_SHA"
  log "pages=$ACROFORM_PAGE_COUNT (the committed AcroForm fixture is used unchanged)"
} >"$RUN_DIR/fixture-sha256.txt"

# --- 2b. The AcroForm fixture must really carry the form it is named after --
# Without this proof the third leg would only repeat the two existing legs: a
# source without fields cannot show that the flattening works. Two independent
# witnesses are recorded: Poppler's structural answer (`Form: AcroForm`) and a
# byte search for the three markers the export has to remove.
{
  log "command=pdfinfo $(host_relative "$APP/assets/fixtures/$ACROFORM_FIXTURE")"
  pdfinfo "$APP/assets/fixtures/$ACROFORM_FIXTURE" 2>&1
  log "expected: Form: AcroForm"
  log "command=LC_ALL=C grep -a -o -F <token> <fixture> | wc -l"
  for form_token in '/AcroForm' '/Widget' '/FT /Tx'; do
    token_hits="$(LC_ALL=C grep -a -o -F "$form_token" "$APP/assets/fixtures/$ACROFORM_FIXTURE" | wc -l)"
    log "fixture_token '$form_token' occurrences=$token_hits"
  done
} >"$RUN_DIR/fixture-acroform-proof.txt" 2>&1
ACROFORM_FIXTURE_FORM="$(pdfinfo "$APP/assets/fixtures/$ACROFORM_FIXTURE" 2>/dev/null | awk '/^Form:/ {sub(/^Form:[[:space:]]*/, ""); print}')"
[[ "$ACROFORM_FIXTURE_FORM" == "AcroForm" ]] ||
  fail "the committed AcroForm fixture reports 'Form: ${ACROFORM_FIXTURE_FORM:-<none>}', expected 'AcroForm'"
for form_token in '/AcroForm' '/Widget' '/FT /Tx'; do
  SOURCE_TOKEN_HITS="$(LC_ALL=C grep -a -o -F "$form_token" "$APP/assets/fixtures/$ACROFORM_FIXTURE" | wc -l)"
  [[ "$SOURCE_TOKEN_HITS" -ge 1 ]] ||
    fail "the committed AcroForm fixture carries no '$form_token' byte sequence"
done
record "AcroForm fixture proved: Form: AcroForm, /AcroForm, /Widget, /FT /Tx present"

# --- 3. Privacy source check -------------------------------------------------
# A grep error (exit 2) is not "no match" (exit 1): only exit 1 proves the
# absence of a network reference, everything else fails the run. The file is
# addressed by absolute path, so a `cd` failure can never read as "no match".
if grep -nE '\b(HttpClient|HttpRequest|Socket|WebSocket|RawDatagramSocket|NetworkImage)\b|https?://' \
  "$APP/$TEST_FILE" >"$RUN_DIR/privacy-source-check.txt" 2>&1; then
  printf 'FAIL: network API reference found in %s\n' "$TEST_FILE" \
    >>"$RUN_DIR/privacy-source-check.txt"
  PRIVACY_PASS=0
else
  PRIVACY_SOURCE_GREP_EXIT=$?
  if [[ "$PRIVACY_SOURCE_GREP_EXIT" -eq 1 ]]; then
    printf 'PASS: no network API reference in %s\n' "$TEST_FILE" \
      >>"$RUN_DIR/privacy-source-check.txt"
    PRIVACY_PASS=1
  else
    printf 'FAIL: the privacy source grep failed with exit %s\n' "$PRIVACY_SOURCE_GREP_EXIT" \
      >>"$RUN_DIR/privacy-source-check.txt"
    fail "the privacy source grep failed with exit $PRIVACY_SOURCE_GREP_EXIT; see privacy-source-check.txt"
  fi
fi

# --- 4. Device setup ---------------------------------------------------------
adb_shell settings put system accelerometer_rotation 0 >/dev/null ||
  fail "cannot pin the device rotation (accelerometer_rotation)"
adb_shell settings put system user_rotation 0 >/dev/null ||
  fail "cannot pin the device rotation (user_rotation)"
adb_shell svc power stayon true >/dev/null ||
  fail "cannot keep the device awake (svc power stayon)"

# The journey drives the real UI, so the screen has to be awake and unlocked
# before the test starts. That is proved from device state with a deadline
# instead of a fixed sleep: `mWakefulness=Awake` from `dumpsys power`, plus
# `mAwake=true`, `mScreenOnFully=true` and `isKeyguardShowing=false` from
# `dumpsys window`.
wait_for_awake_unlocked_screen() {
  local deadline=$((SECONDS + 120)) power window
  # A tighter per-call limit keeps the loop deadline hard: without it one dead
  # transport would stretch a single iteration to four 120s adb timeouts.
  local ADB_SHELL_TIMEOUT=20
  local wakefulness="" awake="" screen_on="" keyguard=""
  while ((SECONDS < deadline)); do
    adb_shell input keyevent KEYCODE_WAKEUP >/dev/null
    adb_shell wm dismiss-keyguard >/dev/null
    power="$(adb_shell dumpsys power)" ||
      fail "cannot read the device power state"
    window="$(adb_shell dumpsys window)" ||
      fail "cannot read the device window state"
    wakefulness="$(printf '%s\n' "$power" | grep -m1 -o 'mWakefulness=[A-Za-z]*')"
    awake="$(printf '%s\n' "$window" | grep -m1 -o 'mAwake=[a-z]*')"
    screen_on="$(printf '%s\n' "$window" | grep -m1 -o 'mScreenOnFully=[a-z]*')"
    keyguard="$(printf '%s\n' "$window" | grep -m1 -o 'isKeyguardShowing=[a-z]*')"
    if [[ "$wakefulness" == "mWakefulness=Awake" && "$awake" == "mAwake=true" &&
      "$screen_on" == "mScreenOnFully=true" &&
      "$keyguard" == "isKeyguardShowing=false" ]]; then
      return 0
    fi
    sleep 1
  done
  log "T334 DRIVER: observed ${wakefulness:-mWakefulness=<none>} ${awake:-mAwake=<none>} ${screen_on:-mScreenOnFully=<none>} ${keyguard:-isKeyguardShowing=<none>}"
  return 1
}
wait_for_awake_unlocked_screen ||
  fail "the screen did not reach the awake, unlocked state within 120s"
record "screen awake and unlocked before the test start"

# --- 5. Host preparation -----------------------------------------------------
FLUTTER_ENV=(env "PATH=$HOME/flutter/bin:$HOME/Android/Sdk/platform-tools:$PATH")
if [[ -n "${JAVA_HOME:-}" ]]; then
  FLUTTER_ENV+=("JAVA_HOME=$JAVA_HOME")
elif [[ -x "$HOME/.feldexa-toolchain/jdk/bin/java" ]]; then
  FLUTTER_ENV+=("JAVA_HOME=$HOME/.feldexa-toolchain/jdk")
fi
(
  cd "$APP" || exit 1
  exec timeout 900 "${FLUTTER_ENV[@]}" "$FLUTTER" pub get --offline
) >"$RUN_DIR/host-flutter-pub-get.log" 2>&1 ||
  fail "flutter pub get --offline failed or timed out; see host-flutter-pub-get.log"

# --- 5b. Static gates --------------------------------------------------------
# The run report claims "No issues found!" for `flutter analyze` and "0 changed"
# for `dart format`; both commands run here, their exit status decides the run
# (fail closed, both are bounded), and their literal output is evidence.
(
  cd "$APP" || exit 1
  exec timeout 900 "${FLUTTER_ENV[@]}" "$FLUTTER" analyze --no-pub
) >"$RUN_DIR/gate-analyze.txt" 2>&1 ||
  fail "flutter analyze did not pass; see gate-analyze.txt"
(
  cd "$APP" || exit 1
  exec timeout 300 "${FLUTTER_ENV[@]}" "$DART" format --output=none --set-exit-if-changed .
) >"$RUN_DIR/gate-format.txt" 2>&1 ||
  fail "dart format reported unformatted files; see gate-format.txt"
record "static gates: flutter analyze clean, dart format 0 changed"

# --- 6. Run the integration test --------------------------------------------
adb_shell logcat -c >/dev/null ||
  fail "cannot clear the device logcat buffer; refusing to run with a stale window"
record "test start $(date -u +%Y-%m-%dT%H:%M:%SZ)"
(
  cd "$APP" || exit 1
  exec "${FLUTTER_ENV[@]}" "$FLUTTER" test --no-pub \
    "$TEST_FILE" -d "$SERIAL"
) >"$LOG" 2>&1 &
TEST_PID=$!

# `flutter test` uninstalls the app when it exits, so the artifact has to be
# picked up while the test is still running. The test prints its stored-artifact
# marker and then waits for the acknowledgement this driver writes after a
# digest-verified pickup (the same handshake shape as the T086 driver).
marker_present() {
  grep -F "T334_$1" "$LOG" >/dev/null 2>&1
}

wait_for_marker() {
  local marker="$1" deadline=$((SECONDS + ${2:-1800}))
  while ((SECONDS < deadline)); do
    if marker_present "$marker"; then
      return 0
    fi
    if ! kill -0 "$TEST_PID" 2>/dev/null; then
      return 2
    fi
    sleep 1
  done
  return 1
}

# Both artifacts are picked up through the same handshake, one after the other:
# the test prints `T334_ARTIFACT_STORED:INDEX=<n>` and then waits for the
# acknowledgement of that index, so the driver finishes artifact n before the
# test starts artifact n+1.
declare -a MARKER_BYTES_BY_INDEX=() MARKER_SHA256_BY_INDEX=() MARKER_PATH_BY_INDEX=()
declare -a HOST_SHA_BY_INDEX=() HOST_SIZE_BY_INDEX=()
for PICKUP_INDEX in $(seq 1 "$ARTIFACT_COUNT"); do
  PICKUP_REL="$(artifact_relative_path "$PICKUP_INDEX")" ||
    fail "no artifact path is defined for index $PICKUP_INDEX"
  PICKUP_FILE="$RUN_DIR/export-artifact-$PICKUP_INDEX.pdf"
  log "T334 DRIVER: waiting for the stored-artifact marker of artifact $PICKUP_INDEX"
  if ! wait_for_marker "ARTIFACT_STORED:INDEX=$PICKUP_INDEX" 2400; then
    log "T334 DRIVER: stored-artifact marker of artifact $PICKUP_INDEX not observed; test log follows"
    tail -160 "$LOG"
    fail "missing marker T334_ARTIFACT_STORED:INDEX=$PICKUP_INDEX before the pickup"
  fi

  PICKUP_LINE="$(grep -oE "T334_ARTIFACT_STORED:INDEX=$PICKUP_INDEX:PATH=[^:]*:BYTES=[0-9]+:SHA256=[0-9a-f]{64}" "$LOG" | tail -1)"
  [[ -n "$PICKUP_LINE" ]] ||
    fail "the integration log carries no T334_ARTIFACT_STORED marker for artifact $PICKUP_INDEX"
  MARKER_BYTES="$(printf '%s\n' "$PICKUP_LINE" | sed -E 's/.*:BYTES=([0-9]+):SHA256=.*/\1/')"
  MARKER_SHA256="$(printf '%s\n' "$PICKUP_LINE" | sed -E 's/.*:SHA256=([0-9a-f]{64}).*/\1/')"
  MARKER_PATH="$(printf '%s\n' "$PICKUP_LINE" | sed -E 's/^T334_ARTIFACT_STORED:INDEX=[0-9]+:PATH=([^:]*):.*/\1/')"

  [[ "$MARKER_PATH" == *"/$PICKUP_REL" ]] ||
    fail "the marker path of artifact $PICKUP_INDEX does not end in /$PICKUP_REL: $MARKER_PATH"

  # The test writes through `Directory.systemTemp`, which the Flutter engine on
  # Android resolves to the app's `code_cache` directory. The run-as path is that
  # marker path with the app data root removed, so the driver never guesses a
  # directory name.
  DEVICE_DATA_PREFIX="/data/user/0/$PACKAGE/"
  [[ "$MARKER_PATH" == "$DEVICE_DATA_PREFIX"* ]] ||
    DEVICE_DATA_PREFIX="/data/data/$PACKAGE/"
  [[ "$MARKER_PATH" == "$DEVICE_DATA_PREFIX"* ]] ||
    fail "the artifact marker path is not inside the app data directory: $MARKER_PATH"
  DEVICE_ARTIFACT_REL="${MARKER_PATH#"$DEVICE_DATA_PREFIX"}"

  adb_shell rm -f "$STAGING/ack-artifact-picked-up-$PICKUP_INDEX" >/dev/null ||
    fail "cannot remove a stale pickup acknowledgement before the pickup retry"
  PICKUP_OK=0
  for attempt in 1 2 3; do
    if timeout 180 "$ADB" -s "$SERIAL" exec-out run-as "$PACKAGE" cat "$DEVICE_ARTIFACT_REL" \
      >"$PICKUP_FILE" 2>>"$ADB_STDERR_LOG" &&
      [[ -s "$PICKUP_FILE" ]] &&
      [[ "$(sha256sum "$PICKUP_FILE" | awk '{print $1}')" == "$MARKER_SHA256" ]]; then
      PICKUP_OK=1
      break
    fi
    sleep 2
  done
  [[ "$PICKUP_OK" -eq 1 ]] ||
    fail "could not read $DEVICE_ARTIFACT_REL through run-as with the marker digest of artifact $PICKUP_INDEX"
  adb_shell touch "$STAGING/ack-artifact-picked-up-$PICKUP_INDEX" >/dev/null ||
    fail "could not acknowledge the pickup of artifact $PICKUP_INDEX to the test"
  MARKER_BYTES_BY_INDEX[PICKUP_INDEX]="$MARKER_BYTES"
  MARKER_SHA256_BY_INDEX[PICKUP_INDEX]="$MARKER_SHA256"
  MARKER_PATH_BY_INDEX[PICKUP_INDEX]="$MARKER_PATH"
  record "host pickup artifact $PICKUP_INDEX: $MARKER_BYTES bytes, sha256 $MARKER_SHA256 (marker matches)"
done

TEST_DEADLINE=$((SECONDS + 1800))
while kill -0 "$TEST_PID" 2>/dev/null; do
  if ((SECONDS >= TEST_DEADLINE)); then
    kill "$TEST_PID" 2>/dev/null
    fail "the integration test did not exit within 1800s after the pickup"
  fi
  sleep 2
done
wait "$TEST_PID"
TEST_EXIT=$?
TEST_PID=""
record "test exit=$TEST_EXIT"

MARKERS="$(grep -E "T334_|T109_" "$LOG")"
MARKERS_GREP_EXIT=$?
[[ "$MARKERS_GREP_EXIT" -le 1 ]] ||
  fail "cannot read the marker lines from the integration log (grep exit $MARKERS_GREP_EXIT)"
if [[ -n "$MARKERS" ]]; then
  printf '%s\n' "$MARKERS" >"$RUN_DIR/markers-integration.txt"
else
  : >"$RUN_DIR/markers-integration.txt"
fi

if [[ "$TEST_EXIT" -ne 0 ]]; then
  record "FAIL (flutter test exit $TEST_EXIT)"
  printf 'result=FAIL\nflutter_test_exit=%s\n' "$TEST_EXIT" \
    >"$RUN_DIR/run-status.txt"
  collect_evidence
  log "T334 DRIVER: FAIL (flutter test exit $TEST_EXIT); log tail follows"
  tail -200 "$LOG"
  exit 1
fi

if ! grep -F 'T334_CLEANUP_DONE' "$LOG" >/dev/null 2>&1; then
  fail "flutter test exited 0 but the cleanup marker is missing"
fi
if ! grep -F 'All tests passed' "$LOG" >/dev/null 2>&1; then
  fail "flutter test exited 0 without the 'All tests passed' summary line"
fi

for PICKUP_INDEX in $(seq 1 "$ARTIFACT_COUNT"); do
  PICKUP_FILE="$RUN_DIR/export-artifact-$PICKUP_INDEX.pdf"
  HOST_ARTIFACT_SHA="$(sha256sum "$PICKUP_FILE" | awk '{print $1}')"
  HOST_ARTIFACT_SIZE="$(stat -c %s "$PICKUP_FILE")"
  [[ "$HOST_ARTIFACT_SIZE" == "${MARKER_BYTES_BY_INDEX[PICKUP_INDEX]}" ]] ||
    fail "picked-up size of artifact $PICKUP_INDEX ($HOST_ARTIFACT_SIZE) != marker size ${MARKER_BYTES_BY_INDEX[PICKUP_INDEX]}"
  [[ "$HOST_ARTIFACT_SHA" == "${MARKER_SHA256_BY_INDEX[PICKUP_INDEX]}" ]] ||
    fail "picked-up sha256 of artifact $PICKUP_INDEX ($HOST_ARTIFACT_SHA) != marker sha256 ${MARKER_SHA256_BY_INDEX[PICKUP_INDEX]}"
  HOST_SHA_BY_INDEX[PICKUP_INDEX]="$HOST_ARTIFACT_SHA"
  HOST_SIZE_BY_INDEX[PICKUP_INDEX]="$HOST_ARTIFACT_SIZE"
  {
    log "index=$PICKUP_INDEX"
    log "path=$(host_relative "$PICKUP_FILE")"
    log "device_path=${MARKER_PATH_BY_INDEX[PICKUP_INDEX]} (read via run-as from the app-internal temp directory)"
    log "sha256=$HOST_ARTIFACT_SHA"
    log "bytes=$HOST_ARTIFACT_SIZE"
    log "marker_sha256=${MARKER_SHA256_BY_INDEX[PICKUP_INDEX]}"
    log "marker_bytes=${MARKER_BYTES_BY_INDEX[PICKUP_INDEX]}"
    log "sha256_matches_marker=1"
    log "size_matches_marker=1"
  } >"$RUN_DIR/artifact-$PICKUP_INDEX-pickup.txt"
done

adb_shell am force-stop "$PACKAGE" >/dev/null ||
  fail "could not stop $PACKAGE after the pickup"
# `flutter test` uninstalls the app when it exits, so after a green run there may
# be nothing left to clear; that is the desired post-condition, not a failure.
# The query and the match are both checked: an adb or grep tool error must never
# be recorded as "the app is gone".
POST_INSTALLED_PACKAGES="$(adb_shell pm list packages "$PACKAGE")" ||
  fail "cannot query the installed packages for $PACKAGE after the pickup"
printf '%s\n' "$POST_INSTALLED_PACKAGES" | grep -qx "package:$PACKAGE"
POST_INSTALLED_GREP_EXIT=$?
[[ "$POST_INSTALLED_GREP_EXIT" -le 1 ]] ||
  fail "the post-pickup installed-package grep failed with exit $POST_INSTALLED_GREP_EXIT"
if [[ "$POST_INSTALLED_GREP_EXIT" -eq 0 ]]; then
  adb_shell pm clear "$PACKAGE" >/dev/null 2>&1 ||
    fail "could not clear the app data after the pickup"
  record "app data cleared after the pickup"
else
  record "app is no longer installed after the test (no app data to clear)"
fi

# --- 8. External proof on the host (Poppler, a byte search, and the 1 mm
#        placement measurement) ---------------------------------------------
command -v pdfinfo >/dev/null || fail "pdfinfo (poppler-utils) not found on the host"
command -v pdftotext >/dev/null || fail "pdftotext (poppler-utils) not found on the host"

pdfinfo "$APP/assets/fixtures/$FIXTURE" >"$RUN_DIR/pdfinfo-source.txt" 2>&1 ||
  fail "pdfinfo failed on the source fixture $FIXTURE"
pdfinfo "$APP/assets/fixtures/$ACROFORM_FIXTURE" >"$RUN_DIR/pdfinfo-source-acroform.txt" 2>&1 ||
  fail "pdfinfo failed on the source fixture $ACROFORM_FIXTURE"

# The per-artifact proof compares against the source it was exported from, so a
# leg can never inherit the pages, page size, or value of another leg.
source_pdfinfo() {
  case "$1" in
    "$FIXTURE") printf '%s\n' "$RUN_DIR/pdfinfo-source.txt" ;;
    "$ACROFORM_FIXTURE") printf '%s\n' "$RUN_DIR/pdfinfo-source-acroform.txt" ;;
    *) return 1 ;;
  esac
}

# The T109 marks leg runs after the flattening leg, confirms its own
# „Familienname“ text field, and stores artifact 4. Its rect is a second
# T334_FIELD_RECT after the boundary, so each drawn leg gets its own rect.
FLATTENING_LEG_LINE="$(grep -n -F 'T334_ACROFORM_LEG_START' "$LOG" | head -1 | cut -d: -f1)"
[[ "$FLATTENING_LEG_LINE" =~ ^[0-9]+$ ]] ||
  fail "the integration log carries no T334_ACROFORM_LEG_START marker; the drawn-value legs cannot be attributed"
T109_LEG_LINE="$(grep -n -F 'T334_T109_MARKS_LEG_START' "$LOG" | head -1 | cut -d: -f1)"
[[ "$T109_LEG_LINE" =~ ^[0-9]+$ ]] ||
  fail "the integration log carries no T334_T109_MARKS_LEG_START marker; the T109 drawn leg cannot be attributed"
read -r RECT_MARKERS_BEFORE RECT_MARKERS_AFTER <<<"$(awk -v boundary="$FLATTENING_LEG_LINE" '
  /^T334_FIELD_RECT:PAGE=/ { if (NR < boundary) before++; else after++ }
  END { printf "%d %d\n", before, after }' "$LOG")"
[[ "$RECT_MARKERS_BEFORE" -eq 1 ]] ||
  fail "the log carries $RECT_MARKERS_BEFORE field rect markers before the flattening leg, expected exactly one (one confirmed field)"
[[ "$RECT_MARKERS_AFTER" -eq 1 ]] ||
  fail "the log carries $RECT_MARKERS_AFTER field rect markers after T334_ACROFORM_LEG_START, expected exactly one (the T109 text field)"
PRE_RECT_LINE="$(awk -v boundary="$FLATTENING_LEG_LINE" '
  /^T334_FIELD_RECT:PAGE=/ && NR < boundary { print; exit }' "$LOG")"
POST_RECT_LINE="$(awk -v boundary="$FLATTENING_LEG_LINE" '
  /^T334_FIELD_RECT:PAGE=/ && NR > boundary { print; exit }' "$LOG")"
[[ -n "$PRE_RECT_LINE" && -n "$POST_RECT_LINE" ]] ||
  fail "a per-leg T334_FIELD_RECT marker is missing (pre='$PRE_RECT_LINE' post='$POST_RECT_LINE')"

# A leg drew a value when its artifact was stored before the flattening leg, or
# in the T109 marks leg that opens at T334_T109_MARKS_LEG_START. Artifact 3 (the
# AcroForm fixture, stored between those two markers) drew no value.
DRAWN_LEGS="$(awk -v boundary="$FLATTENING_LEG_LINE" -v t109="$T109_LEG_LINE" '
  match($0, /^T334_ARTIFACT_STORED:INDEX=[0-9]+/) {
    leg = substr($0, RSTART, RLENGTH)
    sub(/.*INDEX=/, "", leg)
    if (NR < boundary || NR > t109) print leg
  }' "$LOG" | sort -n | uniq | paste -sd' ' -)"
[[ -n "$DRAWN_LEGS" ]] ||
  fail "the log stores no artifact for a drawn-value leg; no placement is attributable"
POST_LEGS="$(awk -v t109="$T109_LEG_LINE" '
  NR > t109 && match($0, /^T334_ARTIFACT_STORED:INDEX=[0-9]+/) {
    leg = substr($0, RSTART, RLENGTH)
    sub(/.*INDEX=/, "", leg)
    print leg
  }' "$LOG" | sort -n | uniq | paste -sd' ' -)"
DRAWN_LEG_COUNT="$(printf '%s\n' "$DRAWN_LEGS" | wc -w)"
if [[ "$DRAWN_LEG_COUNT" -gt 2 ]]; then
  # Several legs then share a field rect marker, which is only attributable
  # because the test asserts the rectangle survived the reopen.
  REOPEN_MARKERS="$(grep -oE '^T334_DOCUMENT_REOPENED:PAGES=[0-9]+:FIELD_RECT_MATCH=1:VALUE_MATCH=1$' "$LOG")"
  [[ -n "$REOPEN_MARKERS" ]] ||
    fail "$DRAWN_LEG_COUNT drawn-value legs share field rect markers, but the log carries no DOCUMENT_REOPENED:FIELD_RECT_MATCH=1 marker that proves the rectangle survives the reopen"
fi

PLACEMENT_TOOL_REL="tools/pdf_verify/placement.py"
[[ -f "$ROOT/$PLACEMENT_TOOL_REL" ]] ||
  fail "the verified placement tool is missing: $PLACEMENT_TOOL_REL"
LAYOUT_SOURCE_REL="packages/feldexa_export/lib/src/layout.dart"
APPLIER_SOURCE_REL="apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/export/ExportPlanValidation.kt"
FONT_METRICS_REL="apps/feldexa_app/assets/fonts/metrics.json"
for placement_source in "$LAYOUT_SOURCE_REL" "$APPLIER_SOURCE_REL" "$FONT_METRICS_REL"; do
  [[ -f "$ROOT/$placement_source" ]] ||
    fail "a placement source the tool reads is missing: $placement_source"
done
declare -a ARTIFACT_PLACEMENT_VERDICT=()

for PICKUP_INDEX in $(seq 1 "$ARTIFACT_COUNT"); do
  PICKUP_FILE="$RUN_DIR/export-artifact-$PICKUP_INDEX.pdf"
  ARTIFACT_TEXT="$RUN_DIR/artifact-$PICKUP_INDEX.txt"
  SOURCE_FIXTURE="$(artifact_source_fixture "$PICKUP_INDEX")" ||
    fail "no source fixture is defined for artifact $PICKUP_INDEX"
  EXPECTED_PAGES="$(artifact_source_pages "$PICKUP_INDEX")" ||
    fail "no page count is defined for artifact $PICKUP_INDEX"
  EXPECTED_TEXT="$(artifact_expected_value "$PICKUP_INDEX")" ||
    fail "no value is defined for artifact $PICKUP_INDEX"
  SOURCE_INFO="$(source_pdfinfo "$SOURCE_FIXTURE")" ||
    fail "no source pdfinfo is recorded for $SOURCE_FIXTURE"
  SOURCE_PAGES="$(awk '/^Pages:/ {print $2}' "$SOURCE_INFO")"
  SOURCE_PAGE_SIZE="$(awk '/^Page size:/ {sub(/^Page size:[[:space:]]*/, ""); print}' "$SOURCE_INFO")"
  [[ "$SOURCE_PAGES" == "$EXPECTED_PAGES" ]] ||
    fail "source page count of $SOURCE_FIXTURE is $SOURCE_PAGES, expected $EXPECTED_PAGES"

  # --- pdfinfo: page count and page size against the source ---------------
  pdfinfo "$PICKUP_FILE" >"$RUN_DIR/pdfinfo-artifact-$PICKUP_INDEX.txt" 2>&1 ||
    fail "pdfinfo failed on picked-up artifact $PICKUP_INDEX"
  ARTIFACT_PAGES="$(awk '/^Pages:/ {print $2}' "$RUN_DIR/pdfinfo-artifact-$PICKUP_INDEX.txt")"
  ARTIFACT_PAGE_SIZE="$(awk '/^Page size:/ {sub(/^Page size:[[:space:]]*/, ""); print}' "$RUN_DIR/pdfinfo-artifact-$PICKUP_INDEX.txt")"
  ARTIFACT_FORM="$(awk '/^Form:/ {sub(/^Form:[[:space:]]*/, ""); print}' "$RUN_DIR/pdfinfo-artifact-$PICKUP_INDEX.txt")"
  [[ "$ARTIFACT_PAGES" == "$EXPECTED_PAGES" ]] ||
    fail "artifact $PICKUP_INDEX page count $ARTIFACT_PAGES != $EXPECTED_PAGES"
  [[ "$ARTIFACT_PAGE_SIZE" == "$SOURCE_PAGE_SIZE" ]] ||
    fail "artifact $PICKUP_INDEX page size '$ARTIFACT_PAGE_SIZE' != source page size '$SOURCE_PAGE_SIZE'"
  # Artifact 3 comes from a source that carries an AcroForm: the flattening has
  # to remove it, so the exported form field must be gone structurally too.
  if [[ "$PICKUP_INDEX" -eq 3 ]]; then
    [[ "$ARTIFACT_FORM" != "AcroForm" ]] ||
      fail "artifact 3 still reports 'Form: AcroForm' after the export"
  fi
  {
    log "index=$PICKUP_INDEX"
    log "command=pdfinfo $(host_relative "$APP/assets/fixtures/$SOURCE_FIXTURE")"
    cat "$SOURCE_INFO"
    log "command=pdfinfo <artifact-$PICKUP_INDEX>"
    cat "$RUN_DIR/pdfinfo-artifact-$PICKUP_INDEX.txt"
    log "source_fixture=$SOURCE_FIXTURE"
    log "pages: source=$SOURCE_PAGES artifact=$ARTIFACT_PAGES (expected=$EXPECTED_PAGES)"
    log "page_size: source=$SOURCE_PAGE_SIZE artifact=$ARTIFACT_PAGE_SIZE (must match)"
    log "form: source=$([[ "$PICKUP_INDEX" -eq 3 ]] && printf "AcroForm" || printf "none") artifact=${ARTIFACT_FORM:-none}"
  } >"$RUN_DIR/artifact-$PICKUP_INDEX-pdfinfo.txt"

  # --- the expected value in the extracted text ---------------------------
  pdftotext -enc UTF-8 "$PICKUP_FILE" "$ARTIFACT_TEXT" ||
    fail "pdftotext failed on picked-up artifact $PICKUP_INDEX"
  # Exit 1 (no match) is a real answer, exit 2 (tool error) is a `fail`: the
  # expected value (the journey's entered `Müller` for index 1/2, the fixture's
  # own field value for index 3) and the encoded umlaut are both read from the
  # same extraction.
  VALUE_MATCHES="$(grep -n -F "$EXPECTED_TEXT" "$ARTIFACT_TEXT")"
  VALUE_GREP_EXIT=$?
  [[ "$VALUE_GREP_EXIT" -le 1 ]] ||
    fail "the expected-value grep failed with exit $VALUE_GREP_EXIT"
  VALUE_HITS="$(printf '%s\n' "$VALUE_MATCHES" | sed '/^$/d' | wc -l)"
  [[ "$VALUE_HITS" -ge 1 ]] ||
    fail "the expected value is not present in the extracted text of artifact $PICKUP_INDEX"
  MANGLED_UMLAUTS="not_applicable"
  if [[ "$EXPECTED_TEXT" == "$EXPECTED_VALUE" ]]; then
    MANGLED_UMLAUTS="$(grep -c -F "M?ller" "$ARTIFACT_TEXT")"
    MANGLED_GREP_EXIT=$?
    [[ "$MANGLED_GREP_EXIT" -le 1 ]] ||
      fail "the mangled-umlaut grep failed with exit $MANGLED_GREP_EXIT"
    [[ "$MANGLED_UMLAUTS" -eq 0 ]] ||
      fail "the extracted text of artifact $PICKUP_INDEX carries 'M?ller': the umlaut was not encoded"
  fi
  {
    log "index=$PICKUP_INDEX"
    log "command=pdftotext -enc UTF-8 <artifact-$PICKUP_INDEX> <text>"
    log "source_fixture=$SOURCE_FIXTURE"
    log "expected_value_occurrences=$VALUE_HITS"
    if [[ "$EXPECTED_TEXT" == "$EXPECTED_VALUE" ]]; then
      log "value = \`Müller\` (synthetic fixture content entered by the journey)"
    else
      log "value = \`$ACROFORM_VALUE\` (the AcroForm fixture's own field value; it lives in the widget appearance, so a flattening that dropped appearances would lose it)"
    fi
    log "umlaut_replaced_by_question_mark=$MANGLED_UMLAUTS"
    log "extracted_text_lines=$(wc -l <"$ARTIFACT_TEXT")"
    log "matched_lines:"
    log "$VALUE_MATCHES"
  } >"$RUN_DIR/artifact-$PICKUP_INDEX-pdftotext.txt"

  # --- byte searches for the form markers the export must remove ----------
  # Index 3 is the flattening proof: its source really carries all three
  # markers, so all three have to be gone in the artifact.
  ACROFORM_HITS="$(LC_ALL=C grep -a -o -F '/AcroForm' "$PICKUP_FILE" | wc -l)"
  ACROFORM_GREP_EXIT=$?
  WIDGET_HITS="$(LC_ALL=C grep -a -o -F '/Widget' "$PICKUP_FILE" | wc -l)"
  WIDGET_GREP_EXIT=$?
  TEXTFIELD_HITS="$(LC_ALL=C grep -a -o -F '/FT /Tx' "$PICKUP_FILE" | wc -l)"
  TEXTFIELD_GREP_EXIT=$?
  # Exit 1 (no match) is the target, exit 0 means the marker is there, and a
  # status above 1 is a grep tool failure: `wc -l` reports 0 hits for an
  # unreadable file, so the status has to be read separately from the count.
  {
    log "index=$PICKUP_INDEX"
    log "command=LC_ALL=C grep -a -o -F '/AcroForm' <artifact-$PICKUP_INDEX> | wc -l"
    log "acroform_grep_exit=$ACROFORM_GREP_EXIT (0=hits, 1=no match, >=2=tool error)"
    log "acroform_byte_occurrences=$ACROFORM_HITS"
    log "command=LC_ALL=C grep -a -o -F '/Widget' <artifact-$PICKUP_INDEX> | wc -l"
    log "widget_grep_exit=$WIDGET_GREP_EXIT (0=hits, 1=no match, >=2=tool error)"
    log "widget_byte_occurrences=$WIDGET_HITS"
    log "command=LC_ALL=C grep -a -o -F '/FT /Tx' <artifact-$PICKUP_INDEX> | wc -l"
    log "textfield_grep_exit=$TEXTFIELD_GREP_EXIT (0=hits, 1=no match, >=2=tool error)"
    log "textfield_byte_occurrences=$TEXTFIELD_HITS"
    log "note=byte-level search only; this is not a structural PDF analysis"
  } >"$RUN_DIR/artifact-$PICKUP_INDEX-acroform.txt"
  for token_grep_exit in "$ACROFORM_GREP_EXIT" "$WIDGET_GREP_EXIT" "$TEXTFIELD_GREP_EXIT"; do
    [[ "$token_grep_exit" -le 1 ]] ||
      fail "a form-marker byte search failed with exit $token_grep_exit on artifact $PICKUP_INDEX"
  done
  [[ "$ACROFORM_HITS" -eq 0 ]] ||
    fail "artifact $PICKUP_INDEX carries $ACROFORM_HITS /AcroForm byte occurrences"
  [[ "$WIDGET_HITS" -eq 0 ]] ||
    fail "artifact $PICKUP_INDEX carries $WIDGET_HITS /Widget byte occurrences"
  [[ "$TEXTFIELD_HITS" -eq 0 ]] ||
    fail "artifact $PICKUP_INDEX carries $TEXTFIELD_HITS /FT /Tx byte occurrences"

  if [[ " $DRAWN_LEGS " != *" $PICKUP_INDEX "* ]]; then
    if [[ "$PICKUP_INDEX" -eq 3 ]]; then
      NOT_APPLICABLE_REASON="artifact 3 exports the AcroForm fixture unchanged (T334_ACROFORM_LEG_START, log line $FLATTENING_LEG_LINE): the leg confirms and fills nothing, draws no value, and prints no field rect; there is no placement to measure"
    else
      NOT_APPLICABLE_REASON="artifact $PICKUP_INDEX has no drawn value: its leg region carries no field rect marker and no value word"
    fi
    {
      log "index=$PICKUP_INDEX"
      log "verdict=NOT_APPLICABLE"
      log "reason=$NOT_APPLICABLE_REASON"
      log "field_rect_marker=none_for_this_leg"
      log "field_rect_markers_total_before=$RECT_MARKERS_BEFORE after=$RECT_MARKERS_AFTER; drawn_value_legs=$(printf '%s' "$DRAWN_LEGS" | tr ' ' ',')"
      log "artifact_sha256=${HOST_SHA_BY_INDEX[$PICKUP_INDEX]}"
    } >"$RUN_DIR/artifact-$PICKUP_INDEX-placement.txt"
    ARTIFACT_PLACEMENT_VERDICT[PICKUP_INDEX]="NOT_APPLICABLE"
    continue
  fi

  LEG_RECT_LINE="$PRE_RECT_LINE"
  if [[ " $POST_LEGS " == *" $PICKUP_INDEX "* ]]; then
    LEG_RECT_LINE="$POST_RECT_LINE"
  fi

  # --- 1 mm placement: one metric, the verified tool ----------------------
  # The driver measures nothing itself. `tools/pdf_verify/placement.py` derives
  # the origin the layout code draws the value at (padding, baseline factor,
  # font-size clamp, bundled font metrics) and compares it with the glyph box
  # Poppler reports, so the number the evidence carries is the distance between
  # two positions and no longer a centre-to-centre distance of a left-aligned
  # value inside a wide field. A drawn value must come out `PROVEN`: every
  # refusal of the tool (exit 2..6) and every failed check (exit 1) ends the run.
  PLACEMENT_OUTPUT="$(cd "$RUN_DIR" && python3 \
    "$ROOT/$PLACEMENT_TOOL_REL" \
    --pdf "export-artifact-$PICKUP_INDEX.pdf" \
    --value-word "$EXPECTED_VALUE" \
    --field-rect-marker "$LEG_RECT_LINE" \
    --layout "$ROOT/$LAYOUT_SOURCE_REL" \
    --applier-source "$ROOT/$APPLIER_SOURCE_REL" \
    --font-metrics "$ROOT/$FONT_METRICS_REL" \
    --tolerance-pt "$PLACEMENT_TOLERANCE_PT" 2>&1)"
  PLACEMENT_EXIT=$?
  {
    log "index=$PICKUP_INDEX"
    log "placement_metric=origin of the drawn value as the layout code places it, measured with $PLACEMENT_TOOL_REL; this is not a centre-to-centre distance"
    log "drawn_value_legs=$(printf '%s' "$DRAWN_LEGS" | tr ' ' ',')"
    log "field_rect_marker=$LEG_RECT_LINE"
    printf '%s\n' "$PLACEMENT_OUTPUT"
    log "placement_tool_exit=$PLACEMENT_EXIT"
  } >"$RUN_DIR/artifact-$PICKUP_INDEX-placement.txt"
  TOOL_PDF_SHA="$(printf '%s\n' "$PLACEMENT_OUTPUT" | awk -F= '/^pdf_sha256=/ {print $2}')"
  TOOL_VERDICT="$(printf '%s\n' "$PLACEMENT_OUTPUT" | awk -F= '/^placement_verdict=/ {print $2}')"
  TOOL_CONTAINMENT="$(printf '%s\n' "$PLACEMENT_OUTPUT" | awk -F= '/^containment_verdict=/ {print $2}')"
  case "$PLACEMENT_EXIT" in
    0) ;;
    1)
      fail "the placement tool measured artifact $PICKUP_INDEX outside the $PLACEMENT_TOLERANCE_PT pt tolerance (exit 1); see artifact-$PICKUP_INDEX-placement.txt"
      ;;
    *)
      fail "the placement tool refused a verdict for artifact $PICKUP_INDEX (exit $PLACEMENT_EXIT; 2=usage, 3=value word not found, 4=ambiguous word match, 5=unreadable input, 6=Poppler failure): a drawn value without a verdict fails the run; see artifact-$PICKUP_INDEX-placement.txt"
      ;;
  esac
  [[ "$TOOL_VERDICT" == "PROVEN" ]] ||
    fail "artifact $PICKUP_INDEX drew a value but the placement tool did not report PROVEN (got '${TOOL_VERDICT:-no verdict}')"
  [[ "$TOOL_CONTAINMENT" == "PASS" ]] ||
    fail "artifact $PICKUP_INDEX reported containment_verdict=${TOOL_CONTAINMENT:-missing}"
  [[ "$TOOL_PDF_SHA" == "${HOST_SHA_BY_INDEX[$PICKUP_INDEX]}" ]] ||
    fail "the placement tool hashed '${TOOL_PDF_SHA:-nothing}' for artifact $PICKUP_INDEX, the picked-up digest is '${HOST_SHA_BY_INDEX[$PICKUP_INDEX]}'"
  ARTIFACT_PLACEMENT_VERDICT[PICKUP_INDEX]="$TOOL_VERDICT"
done

PLACEMENT_VERDICT="PROVEN"
PLACEMENT_SUMMARY=""
for placement_index in $(seq 1 "$ARTIFACT_COUNT"); do
  PLACEMENT_SUMMARY="$PLACEMENT_SUMMARY artifact_$placement_index=${ARTIFACT_PLACEMENT_VERDICT[$placement_index]}"
  case "${ARTIFACT_PLACEMENT_VERDICT[$placement_index]}" in
    PROVEN | NOT_APPLICABLE) ;;
    *) PLACEMENT_VERDICT="NOT_PROVEN" ;;
  esac
done
PLACEMENT_SUMMARY="${PLACEMENT_SUMMARY# }"
log "T334 DRIVER: 1 mm placement verdicts:$PLACEMENT_SUMMARY"
log "T334 DRIVER: 1 mm placement claim: verdict=$PLACEMENT_VERDICT (measured for the drawn-value legs $DRAWN_LEGS, NOT_APPLICABLE where no value was drawn)"

# --- 8c. T105 harness: every executable contracts/export-plan.md §6 row -----
# The harness is the independent verifier (qpdf, Poppler, MuPDF). Artifact 4 is
# the T109 mark leg: its expectations come from the test's own field rects, so
# the masked appearance diff, placement, no-clipping, checkbox states and
# signatures are all judged on real geometry. Artifacts 1/2 carry the drawn
# text value; artifact 3 has no field or mark and is verified structurally.
HARNESS_TOOL_REL="tools/pdf_verify/verify_artifact.py"
EXPECTATIONS_TOOL_REL="tools/pdf_verify/expectations_from_markers.py"
[[ -f "$ROOT/$HARNESS_TOOL_REL" ]] ||
  fail "the T105 harness is missing: $HARNESS_TOOL_REL"
[[ -f "$ROOT/$EXPECTATIONS_TOOL_REL" ]] ||
  fail "the expectations helper is missing: $EXPECTATIONS_TOOL_REL"
command -v qpdf >/dev/null || fail "qpdf is missing; the §6 structural row cannot run"
command -v mutool >/dev/null || fail "MuPDF (mutool) is missing; the second print engine cannot run"
HARNESS_SUMMARY=""
for HARNESS_INDEX in $(seq 1 "$ARTIFACT_COUNT"); do
  PICKUP_FILE="$RUN_DIR/export-artifact-$HARNESS_INDEX.pdf"
  HARNESS_SOURCE_FIXTURE="$(artifact_source_fixture "$HARNESS_INDEX")" ||
    fail "no source fixture is defined for harness artifact $HARNESS_INDEX"
  HARNESS_EXPECTATIONS=()
  if [[ "$HARNESS_INDEX" -eq 1 || "$HARNESS_INDEX" -eq 2 || "$HARNESS_INDEX" -eq 4 ]]; then
    EXPECTATIONS_FILE="$RUN_DIR/expectations-artifact-$HARNESS_INDEX.json"
    python3 "$ROOT/$EXPECTATIONS_TOOL_REL" \
      --markers "$LOG" \
      --index "$HARNESS_INDEX" \
      --out "$EXPECTATIONS_FILE" >/dev/null ||
      fail "cannot derive the harness expectations of artifact $HARNESS_INDEX from the test markers"
    HARNESS_EXPECTATIONS=(--expectations "$EXPECTATIONS_FILE")
  fi
  HARNESS_JSON="$RUN_DIR/harness-artifact-$HARNESS_INDEX.json"
  if ! python3 "$ROOT/$HARNESS_TOOL_REL" \
    --source "$APP/assets/fixtures/$HARNESS_SOURCE_FIXTURE" \
    --artifact "$PICKUP_FILE" \
    "${HARNESS_EXPECTATIONS[@]}" \
    --source-sha256 "$(sha256sum "$APP/assets/fixtures/$HARNESS_SOURCE_FIXTURE" | awk '{print $1}')" \
    --print-dpi 300 \
    --out "$HARNESS_JSON" >"$RUN_DIR/harness-artifact-$HARNESS_INDEX-console.txt" 2>&1; then
    fail "the T105 harness reported a FAIL for artifact $HARNESS_INDEX; see harness-artifact-$HARNESS_INDEX-console.txt"
  fi
  HARNESS_PASS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["summary"]["pass"])' "$HARNESS_JSON")" ||
    fail "cannot read the harness summary of artifact $HARNESS_INDEX"
  HARNESS_FAIL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["summary"]["fail"])' "$HARNESS_JSON")" ||
    fail "cannot read the harness summary of artifact $HARNESS_INDEX"
  [[ "$HARNESS_FAIL" -eq 0 ]] ||
    fail "the harness summary of artifact $HARNESS_INDEX carries $HARNESS_FAIL FAIL row(s)"
  if [[ "$HARNESS_INDEX" -eq 4 ]]; then
    for required_row in \
      "structural validity" "page count and order" "page geometry" \
      "original appearance" "value placement" "text content" "no clipping" \
      "checkbox states" "signatures" "no interactive controls" \
      "printability" "source integrity"; do
      ROW_STATUS="$(python3 -c '
import json, sys
rows = json.load(open(sys.argv[1]))["rows"]
check = sys.argv[2]
print(next((row["status"] for row in rows if row["check"] == check), "MISSING"))
' "$HARNESS_JSON" "$required_row")" ||
        fail "cannot read harness row '$required_row' of artifact $HARNESS_INDEX"
      [[ "$ROW_STATUS" == "PASS" ]] ||
        fail "harness row '$required_row' of artifact $HARNESS_INDEX is $ROW_STATUS, expected PASS"
    done
  fi
  HARNESS_SUMMARY="$HARNESS_SUMMARY artifact_${HARNESS_INDEX}=${HARNESS_PASS}P/${HARNESS_FAIL}F"
done
HARNESS_SUMMARY="${HARNESS_SUMMARY# }"
log "T334 DRIVER: T105 harness summaries:$HARNESS_SUMMARY"

# --- 9. Evidence -------------------------------------------------------------
# A missing APK is a build/tool failure, never an empty digest file: with
# `nullglob` the array is empty when the glob matched nothing.
shopt -s nullglob
APK_FILES=("$APP"/build/app/outputs/flutter-apk/*.apk)
shopt -u nullglob
[[ "${#APK_FILES[@]}" -ge 1 ]] ||
  fail "no APK found under apps/feldexa_app/build/app/outputs/flutter-apk"
{
  for apk in "${APK_FILES[@]}"; do
    log "path=$(host_relative "$apk")"
    log "sha256=$(sha256sum "$apk" | awk '{print $1}')"
    log "bytes=$(stat -c %s "$apk")"
  done
} >"$RUN_DIR/apk-sha256.txt"

{
  log "head=$(git -C "$ROOT" rev-parse HEAD)"
  log "tree=$(git -C "$ROOT" rev-parse HEAD^{tree})"
  log "branch=$(git -C "$ROOT" branch --show-current)"
  log "subject=$(git -C "$ROOT" log -1 --pretty=%s)"
  log "status_porcelain:"
  git -C "$ROOT" status --porcelain
  log "test_sha256=$(sha256sum "$APP/$TEST_FILE" | awk '{print $1}')"
  log "driver_sha256=$(sha256sum "$ROOT/tools/android/t334_drive_export.sh" | awk '{print $1}')"
  log "flutter=$("${FLUTTER_ENV[@]}" "$FLUTTER" --version 2>/dev/null | head -1)"
} >"$RUN_DIR/git-identity.txt"

# A grep error (exit 2) is not "no match" (exit 1): only exit 1 proves the log
# carries no document content.
if grep -nE "$EXPECTED_VALUE|$ACROFORM_VALUE|Familienname|t334-export\.pdf|t334-acroform\.pdf|/data/local/tmp/t334-fixtures" \
  "$LOG" >"$RUN_DIR/privacy-log-check.txt" 2>&1; then
  printf 'FAIL: document content, field label, display name, or fixture path found in the integration log\n' \
    >>"$RUN_DIR/privacy-log-check.txt"
  PRIVACY_PASS=0
else
  PRIVACY_LOG_GREP_EXIT=$?
  if [[ "$PRIVACY_LOG_GREP_EXIT" -eq 1 ]]; then
    printf 'PASS: no document content, field label, display name, or fixture path in the integration log\n' \
      >>"$RUN_DIR/privacy-log-check.txt"
  else
    printf 'FAIL: the privacy log grep failed with exit %s\n' "$PRIVACY_LOG_GREP_EXIT" \
      >>"$RUN_DIR/privacy-log-check.txt"
    PRIVACY_PASS=0
  fi
fi

if [[ "$PRIVACY_PASS" -eq 1 ]]; then
  # The result is fixed last: the bundle is collected and scanned before the
  # PASS record and before run-status.txt exist, so a failing integrity check
  # can never leave a bundle that carries result=PASS.
  collect_evidence
  scan_evidence_home_paths ||
    fail "the evidence home-path scan did not come back clean; no result was written"
  record "PASS (flutter test exit 0; cleanup marker observed; four artifacts picked up with matching digests; poppler and byte-search proof for all four; AcroForm flattening proved for artifact 3 (no /AcroForm, /Widget, /FT /Tx; field value survives in the text layer); T105 harness PASS for every artifact (artifact 4: appearance, placement, no-clipping, checkbox states and signatures on the test's own rects); static gates clean; privacy checks PASS; 1 mm placement claim $PLACEMENT_VERDICT ($PLACEMENT_SUMMARY))"
  {
    printf 'result=PASS\nflutter_test_exit=0\n'
    for status_index in $(seq 1 "$ARTIFACT_COUNT"); do
      printf 'artifact_%s_sha256=%s\nartifact_%s_bytes=%s\nartifact_%s_placement_verdict=%s\n' \
        "$status_index" "${HOST_SHA_BY_INDEX[$status_index]}" \
        "$status_index" "${HOST_SIZE_BY_INDEX[$status_index]}" \
        "$status_index" "${ARTIFACT_PLACEMENT_VERDICT[$status_index]}"
    done
    printf 'placement_verdict=%s\n' "$PLACEMENT_VERDICT"
    printf 'placement_tolerance_pt=%s\n' "$PLACEMENT_TOLERANCE_PT"
    printf 'placement_metric=origin of the drawn value as the layout code places it (%s)\n' "$PLACEMENT_TOOL_REL"
    printf 'placement_drawn_value_legs=%s\n' "$(printf '%s' "$DRAWN_LEGS" | tr ' ' ',')"
    printf 'placement_reason=%s\n' "none (every drawn-value leg is PROVEN; the drawn-value legs are $DRAWN_LEGS, every other leg drew no value)"
    printf 'harness_summary=%s\n' "$HARNESS_SUMMARY"
    printf 'harness_artifact_4_rows=PASS (appearance, placement, no-clipping, checkbox states, signatures, text, printability, source integrity)\n'
  } >"$RUN_DIR/run-status.txt"
  collect_evidence
  # run-status.txt and the final marker sequence are copied by the second
  # collection; if the scan now fails, the fixation is retracted before exit.
  scan_evidence_home_paths || {
    printf 'result=FAIL\nflutter_test_exit=0\n' >"$RUN_DIR/run-status.txt"
    record "FAIL (evidence integrity check failed after the result fixation)"
    collect_evidence
    fail "the evidence home-path scan did not come back clean after the result fixation"
  }
  log "T334 DRIVER: PASS"
  exit 0
fi

record "FAIL (privacy checks FAIL)"
printf 'result=FAIL\nflutter_test_exit=0\n' >"$RUN_DIR/run-status.txt"
collect_evidence
fail "privacy checks failed; see privacy-source-check.txt and privacy-log-check.txt"
