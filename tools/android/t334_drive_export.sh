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
#   4. clears the test app data so the journey starts with an empty store, then
#      runs `flutter test integration_test/android_export_test.dart -d <serial>`
#      in the foreground and writes the log;
#   5. after a green run, picks the artifact bytes the test left in the
#      app-internal cache up with `run-as`, verifies them against the digest and
#      size the test printed, and clears the app data again;
#   6. proves the picked file with external tools on the host: `pdfinfo` page
#      count and page size against the source fixture, `pdftotext` for the
#      entered umlaut value, and a byte search for `/AcroForm`;
#   7. records device identity, fixture/APK hashes, git identity (HEAD/tree/
#      branch/subject/status), the permit admission, the marker sequence
#      extracted from the integration log, and a source-level and log-level
#      privacy check.
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
ARTIFACT_REL="e2e/export-artifact.pdf"
EXPECTED_VALUE="Müller"

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
EVIDENCE_DIR="${T334_EVIDENCE_DIR:-$ROOT/specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t342-driver-hardening}"
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
: >"$SEQUENCE"
: >"$ADB_STDERR_LOG"

# Device-side stderr is a diagnosis trail, never noise: it lands in the run log
# (`adb-stderr.log`, part of the evidence bundle) while the exit code of the adb
# call stays visible to the caller, which checks it at every decision point.
adb_shell() {
  timeout 120 "$ADB" -s "$SERIAL" shell "$@" 2>>"$ADB_STDERR_LOG" | tr -d '\r'
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
    apk-sha256.txt \
    git-identity.txt \
    artifact-pickup.txt \
    poppler-pdfinfo.txt \
    poppler-pdftotext.txt \
    artifact-bytes-acroform.txt \
    privacy-source-check.txt \
    privacy-log-check.txt \
    host-flutter-pub-get.log; do
    if [[ -f "$RUN_DIR/$file" ]]; then
      sed -e "s|$ROOT/||g" -e "s|$ROOT|.|g" -e "s|$HOME/|~/|g" "$RUN_DIR/$file" \
        >"$EVIDENCE_DIR/$file" ||
        fail "cannot write evidence file $file"
    fi
  done
  if [[ -f "$RUN_DIR/export-artifact.pdf" ]]; then
    cp "$RUN_DIR/export-artifact.pdf" "$EVIDENCE_DIR/export-artifact.pdf" ||
      fail "cannot write the picked-up artifact into the evidence directory"
  fi
  log "T334 DRIVER: evidence written to $EVIDENCE_DIR"
}

log "T334 DRIVER: run directory $RUN_DIR"
log "T334 DRIVER: shared heavy-work permits admitted (build, emulator)"

if [[ ! -x "$FLUTTER" ]]; then
  fail "flutter executable not found at $FLUTTER"
fi
if [[ ! -x "$ADB" ]]; then
  fail "adb executable not found at $ADB"
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
ALL_TRANSPORTS="$("$ADB" devices | awk 'NR>1 && NF>=1 && $1 !~ /^(List|of|devices)$/ {print $1}')"
ALL_DEVICES="$("$ADB" devices | awk 'NR>1 && NF>=2 && $2=="device" {print $1}')"
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
STORE_EMPTY_PROBE='for d in files/feldexa/docs files/feldexa/templates; do if [ -e $d ]; then if [ -n "$(ls -A $d)" ]; then echo "leftover entries in $d"; exit 1; fi; fi; done; echo STORE_EMPTY_OK'

adb_shell am force-stop "$PACKAGE" >/dev/null ||
  fail "could not stop $PACKAGE before the pre-run clear"
INSTALLED_PACKAGES="$(adb_shell pm list packages "$PACKAGE")" ||
  fail "cannot query the installed packages for $PACKAGE"
if printf '%s\n' "$INSTALLED_PACKAGES" | grep -qx "package:$PACKAGE"; then
  adb_shell pm clear "$PACKAGE" >/dev/null ||
    fail "pre-run pm clear of $PACKAGE failed"
  PRE_STORE_STATE="$(adb_shell "run-as $PACKAGE sh -c '$STORE_EMPTY_PROBE'")"
  [[ "$PRE_STORE_STATE" == *STORE_EMPTY_OK* ]] ||
    fail "the pre-run clear did not leave an empty store: ${PRE_STORE_STATE:-no answer from the store probe}"
  record "pre-run: app data cleared, store proved empty"
else
  record "pre-run: package not installed, no stored state exists"
fi
adb_shell mkdir -p "$STAGING" >/dev/null ||
  fail "cannot create the device staging directory $STAGING"
"$ADB" -s "$SERIAL" push "$APP/assets/fixtures/$FIXTURE" \
  "$STAGING/$FIXTURE" >/dev/null || fail "staging push failed: $FIXTURE"
adb_shell chmod 755 "$STAGING" >/dev/null
adb_shell chmod 644 "$STAGING/$FIXTURE" >/dev/null
# A previous aborted run can leave the pickup acknowledgement behind; remove it
# before the test starts so no wait can return on a stale ack.
adb_shell rm -f "$STAGING/ack-artifact-picked-up" >/dev/null

DEVICE_FIXTURE_SHA="$(adb_shell sha256sum "$STAGING/$FIXTURE" | awk '{print $1}')"
HOST_FIXTURE_SHA="$(sha256sum "$APP/assets/fixtures/$FIXTURE" | awk '{print $1}')"
DEVICE_FIXTURE_SIZE="$(adb_shell stat -c %s "$STAGING/$FIXTURE")"
[[ "$DEVICE_FIXTURE_SHA" == "$FIXTURE_SHA256" ]] ||
  fail "device fixture sha256 $DEVICE_FIXTURE_SHA != $FIXTURE_SHA256"
[[ "$HOST_FIXTURE_SHA" == "$FIXTURE_SHA256" ]] ||
  fail "host fixture sha256 $HOST_FIXTURE_SHA != $FIXTURE_SHA256"
[[ "$DEVICE_FIXTURE_SIZE" == "$FIXTURE_SIZE_BYTES" ]] ||
  fail "device fixture size $DEVICE_FIXTURE_SIZE != $FIXTURE_SIZE_BYTES"

{
  log "staging $STAGING/$FIXTURE sha256=$DEVICE_FIXTURE_SHA size=$DEVICE_FIXTURE_SIZE"
  log "host $(host_relative "$APP/assets/fixtures/$FIXTURE") sha256=$HOST_FIXTURE_SHA"
  log "pages=$EXPECTED_PAGE_COUNT (the committed fixture is used unchanged)"
} >"$RUN_DIR/fixture-sha256.txt"

# --- 3. Privacy source check -------------------------------------------------
# A grep error (exit 2) is not "no match" (exit 1): only exit 1 proves the
# absence of a network reference, everything else fails the run.
if (cd "$APP" && grep -nE '\b(HttpClient|HttpRequest|Socket|WebSocket|RawDatagramSocket|NetworkImage)\b|https?://' \
  "$TEST_FILE") >"$RUN_DIR/privacy-source-check.txt" 2>&1; then
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
  local deadline=$((SECONDS + 60)) power window
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
  fail "the screen did not reach the awake, unlocked state within 60s"
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
  exec "${FLUTTER_ENV[@]}" "$FLUTTER" pub get --offline
) >"$RUN_DIR/host-flutter-pub-get.log" 2>&1 ||
  fail "flutter pub get --offline failed; see host-flutter-pub-get.log"

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

log "T334 DRIVER: waiting for the stored-artifact marker"
if ! wait_for_marker "ARTIFACT_STORED" 2400; then
  log "T334 DRIVER: stored-artifact marker not observed; test log follows"
  tail -160 "$LOG"
  fail "missing marker T334_ARTIFACT_STORED before the pickup"
fi

PICKUP_LINE="$(grep -oE 'T334_ARTIFACT_STORED:PATH=[^:]*:BYTES=[0-9]+:SHA256=[0-9a-f]{64}' "$LOG" | tail -1)"
[[ -n "$PICKUP_LINE" ]] ||
  fail "the integration log carries no T334_ARTIFACT_STORED marker"
MARKER_BYTES="$(printf '%s\n' "$PICKUP_LINE" | sed -E 's/.*:BYTES=([0-9]+):SHA256=.*/\1/')"
MARKER_SHA256="$(printf '%s\n' "$PICKUP_LINE" | sed -E 's/.*:SHA256=([0-9a-f]{64}).*/\1/')"
MARKER_PATH="$(printf '%s\n' "$PICKUP_LINE" | sed -E 's/^T334_ARTIFACT_STORED:PATH=([^:]*):.*/\1/')"

[[ "$MARKER_PATH" == *"/$ARTIFACT_REL" ]] ||
  fail "the artifact marker path does not end in /$ARTIFACT_REL: $MARKER_PATH"

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

adb_shell rm -f "$STAGING/ack-artifact-picked-up" >/dev/null
PICKUP_OK=0
for attempt in 1 2 3; do
  if timeout 180 "$ADB" -s "$SERIAL" exec-out run-as "$PACKAGE" cat "$DEVICE_ARTIFACT_REL" \
    >"$RUN_DIR/export-artifact.pdf" 2>>"$ADB_STDERR_LOG" &&
    [[ -s "$RUN_DIR/export-artifact.pdf" ]] &&
    [[ "$(sha256sum "$RUN_DIR/export-artifact.pdf" | awk '{print $1}')" == "$MARKER_SHA256" ]]; then
    PICKUP_OK=1
    break
  fi
  sleep 2
done
[[ "$PICKUP_OK" -eq 1 ]] ||
  fail "could not read $DEVICE_ARTIFACT_REL through run-as with the marker digest"
adb_shell touch "$STAGING/ack-artifact-picked-up" >/dev/null ||
  fail "could not acknowledge the pickup to the test"
record "host pickup: $MARKER_BYTES bytes, sha256 $MARKER_SHA256 (marker matches)"

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

MARKERS="$(grep -E "T334_" "$LOG")"
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

HOST_ARTIFACT_SHA="$(sha256sum "$RUN_DIR/export-artifact.pdf" | awk '{print $1}')"
HOST_ARTIFACT_SIZE="$(stat -c %s "$RUN_DIR/export-artifact.pdf")"
[[ "$HOST_ARTIFACT_SIZE" == "$MARKER_BYTES" ]] ||
  fail "picked-up size $HOST_ARTIFACT_SIZE != marker size $MARKER_BYTES"
[[ "$HOST_ARTIFACT_SHA" == "$MARKER_SHA256" ]] ||
  fail "picked-up sha256 $HOST_ARTIFACT_SHA != marker sha256 $MARKER_SHA256"

SNAPSHOT_SHA="$(sha256sum "$RUN_DIR/export-artifact.pdf" | awk '{print $1}')"
{
  log "path=$(host_relative "$RUN_DIR/export-artifact.pdf")"
  log "device_path=$MARKER_PATH (read via run-as from the app-internal temp directory)"
  log "sha256=$SNAPSHOT_SHA"
  log "bytes=$HOST_ARTIFACT_SIZE"
  log "marker_sha256=$MARKER_SHA256"
  log "marker_bytes=$MARKER_BYTES"
  log "sha256_matches_marker=1"
  log "size_matches_marker=1"
} >"$RUN_DIR/artifact-pickup.txt"

adb_shell am force-stop "$PACKAGE" >/dev/null
# `flutter test` uninstalls the app when it exits, so after a green run there may
# be nothing left to clear; that is the desired post-condition, not a failure.
if adb_shell pm list packages "$PACKAGE" | grep -qx "package:$PACKAGE"; then
  adb_shell pm clear "$PACKAGE" >/dev/null 2>&1 ||
    fail "could not clear the app data after the pickup"
  record "app data cleared after the pickup"
else
  record "app is no longer installed after the test (no app data to clear)"
fi

# --- 8. External proof on the host (Poppler and a byte search) --------------
command -v pdfinfo >/dev/null || fail "pdfinfo (poppler-utils) not found on the host"
command -v pdftotext >/dev/null || fail "pdftotext (poppler-utils) not found on the host"

pdfinfo "$APP/assets/fixtures/$FIXTURE" >"$RUN_DIR/pdfinfo-source.txt" 2>&1 ||
  fail "pdfinfo failed on the source fixture"
pdfinfo "$RUN_DIR/export-artifact.pdf" >"$RUN_DIR/pdfinfo-artifact.txt" 2>&1 ||
  fail "pdfinfo failed on the picked-up artifact"
{
  log "command=pdfinfo $(host_relative "$APP/assets/fixtures/$FIXTURE")"
  cat "$RUN_DIR/pdfinfo-source.txt"
  log "command=pdfinfo <artifact>"
  cat "$RUN_DIR/pdfinfo-artifact.txt"
} >"$RUN_DIR/poppler-pdfinfo.txt"

SOURCE_PAGES="$(awk '/^Pages:/ {print $2}' "$RUN_DIR/pdfinfo-source.txt")"
ARTIFACT_PAGES="$(awk '/^Pages:/ {print $2}' "$RUN_DIR/pdfinfo-artifact.txt")"
SOURCE_PAGE_SIZE="$(awk '/^Page size:/ {sub(/^Page size:[[:space:]]*/, ""); print}' "$RUN_DIR/pdfinfo-source.txt")"
ARTIFACT_PAGE_SIZE="$(awk '/^Page size:/ {sub(/^Page size:[[:space:]]*/, ""); print}' "$RUN_DIR/pdfinfo-artifact.txt")"
[[ "$ARTIFACT_PAGES" == "$EXPECTED_PAGE_COUNT" ]] ||
  fail "artifact page count $ARTIFACT_PAGES != $EXPECTED_PAGE_COUNT"
[[ "$SOURCE_PAGES" == "$EXPECTED_PAGE_COUNT" ]] ||
  fail "source page count $SOURCE_PAGES != $EXPECTED_PAGE_COUNT"
[[ "$ARTIFACT_PAGE_SIZE" == "$SOURCE_PAGE_SIZE" ]] ||
  fail "artifact page size '$ARTIFACT_PAGE_SIZE' != source page size '$SOURCE_PAGE_SIZE'"

pdftotext -enc UTF-8 "$RUN_DIR/export-artifact.pdf" "$RUN_DIR/artifact.txt" ||
  fail "pdftotext failed on the picked-up artifact"
# Exit 1 (no match) is a real answer, exit 2 (tool error) is a `fail`: the
# entered value and the encoded umlaut are both read from the same extraction.
VALUE_MATCHES="$(grep -n -F "$EXPECTED_VALUE" "$RUN_DIR/artifact.txt")"
VALUE_GREP_EXIT=$?
[[ "$VALUE_GREP_EXIT" -le 1 ]] ||
  fail "the entered-value grep failed with exit $VALUE_GREP_EXIT"
VALUE_HITS="$(printf '%s\n' "$VALUE_MATCHES" | sed '/^$/d' | wc -l)"
[[ "$VALUE_HITS" -ge 1 ]] ||
  fail "the entered value is not present in the extracted artifact text"
MANGLED_UMLAUTS="$(grep -c -F "M?ller" "$RUN_DIR/artifact.txt")"
MANGLED_GREP_EXIT=$?
[[ "$MANGLED_GREP_EXIT" -le 1 ]] ||
  fail "the mangled-umlaut grep failed with exit $MANGLED_GREP_EXIT"
[[ "$MANGLED_UMLAUTS" -eq 0 ]] ||
  fail "the extracted text carries 'M?ller': the umlaut was not encoded"
{
  log "command=pdftotext -enc UTF-8 <artifact> <text>"
  log "entered_value_occurrences=$VALUE_HITS"
  log "value = \`Müller\` (synthetic fixture content entered by the journey)"
  log "umlaut_replaced_by_question_mark=$MANGLED_UMLAUTS"
  log "extracted_text_lines=$(wc -l <"$RUN_DIR/artifact.txt")"
  log "matched_lines:"
  log "$VALUE_MATCHES"
} >"$RUN_DIR/poppler-pdftotext.txt"

ACROFORM_HITS="$(LC_ALL=C grep -a -o -F '/AcroForm' "$RUN_DIR/export-artifact.pdf" | wc -l)"
{
  log "command=LC_ALL=C grep -a -o -F '/AcroForm' <artifact> | wc -l"
  log "acroform_byte_occurrences=$ACROFORM_HITS"
  log "note=byte-level search only; this is not a structural PDF analysis"
} >"$RUN_DIR/artifact-bytes-acroform.txt"
[[ "$ACROFORM_HITS" -eq 0 ]] ||
  fail "the artifact carries $ACROFORM_HITS /AcroForm byte occurrences"

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
if grep -nE "$EXPECTED_VALUE|Familienname|t334-export\.pdf|/data/local/tmp/t334-fixtures" \
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
  record "PASS (flutter test exit 0; cleanup marker observed; artifact picked up; poppler proof; privacy checks PASS)"
  printf 'result=PASS\nflutter_test_exit=0\nartifact_sha256=%s\nartifact_bytes=%s\n' \
    "$SNAPSHOT_SHA" "$HOST_ARTIFACT_SIZE" >"$RUN_DIR/run-status.txt"
  collect_evidence
  # The bundle is committed, so no evidence text file may carry an absolute
  # home path; [collect_evidence] rewrites the host paths on the way in. The
  # scan is a decision point, so its exit code is checked: only "no match" (1)
  # may lead to PASS.
  HOME_PATH_HITS="$(grep -rl --include='*.txt' -F '/home/' "$EVIDENCE_DIR")"
  HOME_PATH_GREP_EXIT=$?
  [[ "$HOME_PATH_GREP_EXIT" -le 1 ]] ||
    fail "the evidence home-path scan failed with exit $HOME_PATH_GREP_EXIT"
  [[ -z "$HOME_PATH_HITS" ]] ||
    fail "an evidence text file still carries an absolute home path: $HOME_PATH_HITS"
  log "T334 DRIVER: PASS"
  exit 0
fi

record "FAIL (privacy checks FAIL)"
printf 'result=FAIL\nflutter_test_exit=0\n' >"$RUN_DIR/run-status.txt"
collect_evidence
fail "privacy checks failed; see privacy-source-check.txt and privacy-log-check.txt"
