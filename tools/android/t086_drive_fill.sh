#!/usr/bin/env bash
# T086 host driver: runs the real EMULATOR two-page touch fill journey.
#
# The journey is issue #86 / T086 (US4 Independent Test): import the committed
# two-page `sf-001.pdf`, analyze both real pages, confirm one real machine text
# suggestion on each page, seed the remaining field types on the real pages,
# fill page 1 and page 2 entirely by touch through the real overlay and value
# sheet (text with umlauts/ß, number, date, checkbox, multiline, drawn
# signature, and a text that deliberately exceeds its region), navigate between
# the pages, and verify that no value is truncated, every value survives the
# navigation, and every field stays editable.
#
# This script:
#   1. admits the whole run into the shared heavy-work lock by re-executing
#      itself through `compute_slot.py --wait`, so emulator use, Gradle, and the
#      Flutter test share one host permit with every other heavy job. There is
#      deliberately no Orca command and no Orca gate;
#   2. binds the device by ADB serial and AVD identity: exactly one attached
#      `emulator-<n>` transport, the expected serial, AVD name, API level,
#      `qemu=1`, and a completed boot. A wireless or physical phone transport is
#      recorded but never addressed;
#   3. stages the committed synthetic `sf-001.pdf` fixture and verifies its
#      SHA-256 and size on the host and on the device;
#   4. clears the test app data so the journey starts with an empty store;
#   5. starts `flutter test integration_test/android_fill_test.dart` in the
#      background and captures the four screenshot phases; stale ack files are
#      removed first, and the four screenshot hashes must be distinct;
#   6. records device identity, fixture/APK hashes, git identity (HEAD/tree/
#      branch/subject/status), the shared-lock admission, marker-filtered
#      logcat, the marker sequence extracted from the integration log, and a
#      source-level and log-level privacy check;
#   7. removes pushed fixtures/acks and clears the test app data again.
#
# T086 markers are printed by the integration-test process through the test
# harness, not by the app process, so `logcat-flutter.log` contains only engine
# `flutter` tag lines. The authoritative marker sequence is extracted from the
# integration log into `markers-integration.txt`.
#
# The tree must be committed before the run: the working tree must be clean.
#
# Evidence class is EMULATOR only when step 2 passes. Without a booted,
# available emulator the script exits 2 with `EMULATOR NOT_RUN`; the physical
# Samsung S23 is never addressed.
#
# Test-only tooling: adds no production dependency and changes no app file.
# Usage (repo root): tools/android/t086_drive_fill.sh
set -uo pipefail

SERIAL="${T086_SERIAL:-emulator-5554}"
EXPECTED_AVD="${T086_AVD:-T025_Pixel7_API35_KVM_20261115}"
EXPECTED_API="${T086_API:-35}"
ADB="${T086_ADB:-$HOME/Android/Sdk/platform-tools/adb}"
FLUTTER="${T086_FLUTTER:-$HOME/flutter/bin/flutter}"
COMPUTE_SLOT="${T086_COMPUTE_SLOT:-$HOME/.agents/skills/pi-maintainer/scripts/compute_slot.py}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SELF="$ROOT/tools/android/t086_drive_fill.sh"
APP="$ROOT/apps/feldexa_app"
TEST_FILE="integration_test/android_fill_test.dart"
BACKUP_DIR=""

STAGING="/data/local/tmp/t086-fixtures"
PACKAGE="de.feldexa.app"
FIXTURE="sf-001.pdf"
FIXTURE_SHA256="22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038"
FIXTURE_SIZE_BYTES=5956
SCREENSHOTS=(overflow-warning page1-values page2-signed page1-preserved)

TEST_PID=""
TEST_EXIT=255
CLEANED=0
PRIVACY_PASS=0

log() {
  printf '%s\n' "$*"
}

fail() {
  log "T086 DRIVER: $*"
  exit 1
}

not_run() {
  log "T086 EMULATOR NOT_RUN: $*"
  exit 2
}

# --- 0. Shared heavy-work lock admission ------------------------------------
# The whole journey (emulator foreground use, Gradle, Flutter test) runs inside
# the cooperative host permit. Without the guard token the driver re-executes
# itself through compute_slot, so one permit covers the complete run instead of
# acquiring it around individual commands. A caller that already holds the
# permit (an outer compute_slot wrapper) sets the token and the driver runs
# inside that same critical section. The token prevents a re-exec loop.
if [[ "${T086_COMPUTE_LOCK_HELD:-0}" != "1" ]]; then
  [[ -f "$COMPUTE_SLOT" ]] ||
    fail "shared heavy-work lock script not found at $COMPUTE_SLOT"
  log "T086 DRIVER: admitting the run into the shared heavy-work lock"
  exec python3 "$COMPUTE_SLOT" --wait -- \
    env T086_COMPUTE_LOCK_HELD=1 \
    T086_SERIAL="$SERIAL" \
    T086_AVD="$EXPECTED_AVD" \
    T086_API="$EXPECTED_API" \
    T086_ADB="$ADB" \
    T086_FLUTTER="$FLUTTER" \
    T086_COMPUTE_SLOT="$COMPUTE_SLOT" \
    T086_RUN_DIR="${T086_RUN_DIR:-}" \
    T086_EVIDENCE_DIR="${T086_EVIDENCE_DIR:-}" \
    bash "$SELF" "$@"
fi

RUN_DIR="${T086_RUN_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/feldexa-t086-run.XXXXXX")}"
EVIDENCE_DIR="${T086_EVIDENCE_DIR:-$ROOT/specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill}"
LOG="$RUN_DIR/integration-android-t086.log"
SEQUENCE="$RUN_DIR/marker-sequence.txt"

if [[ -n "${T086_RUN_DIR:-}" ]]; then
  if [[ -e "$RUN_DIR" ]]; then
    log "T086 DRIVER: refusing to reuse existing run directory $RUN_DIR"
    exit 1
  fi
  mkdir -p "$RUN_DIR" || {
    log "T086 DRIVER: cannot create run directory $RUN_DIR"
    exit 1
  }
else
  [[ -n "$RUN_DIR" ]] || {
    log "T086 DRIVER: cannot create a temporary run directory"
    exit 1
  }
fi
: >"$SEQUENCE"

adb_shell() {
  "$ADB" -s "$SERIAL" shell "$@" 2>/dev/null | tr -d '\r'
}

settings_get() {
  adb_shell settings get "$1" "$2"
}

record() {
  log "T086 DRIVER: $*"
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
  rm -f "$RUN_DIR/logcat-full.txt"
  if [[ -n "${ORIGINAL_ROTATION:-}" ]]; then
    adb_shell settings put system user_rotation "$ORIGINAL_ROTATION" >/dev/null
  fi
  if [[ -n "${ORIGINAL_ACCELEROMETER:-}" ]]; then
    adb_shell settings put system accelerometer_rotation "$ORIGINAL_ACCELEROMETER" >/dev/null
  fi
  if [[ -n "${ORIGINAL_STAY_ON:-}" && "$ORIGINAL_STAY_ON" != "null" ]]; then
    adb_shell settings put global stay_on_while_plugged_in "$ORIGINAL_STAY_ON" >/dev/null
  fi
}
trap cleanup EXIT INT TERM

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
    first="$(find "$EVIDENCE_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)"
    if [[ -n "$first" ]]; then
      if [[ "${T086_REPLACE_EVIDENCE:-0}" != "1" ]]; then
        fail "refusing to overwrite existing evidence in $EVIDENCE_DIR; bind a fresh T086_EVIDENCE_DIR or set T086_REPLACE_EVIDENCE=1 to back up and replace"
      fi
      BACKUP_DIR="$RUN_DIR/evidence-backup"
      mkdir -p "$BACKUP_DIR" || fail "cannot create evidence backup directory"
      cp -a "$EVIDENCE_DIR"/. "$BACKUP_DIR"/ || fail "evidence backup failed"
      log "T086 DRIVER: backed up existing evidence to $BACKUP_DIR"
    fi
  else
    mkdir -p "$EVIDENCE_DIR" || fail "cannot create evidence directory $EVIDENCE_DIR"
  fi
}

collect_evidence() {
  local file
  for file in \
    integration-android-t086.log \
    markers-integration.txt \
    marker-sequence.txt \
    screenshot-hashes.txt \
    run-status.txt \
    device-identity.txt \
    device-binding.txt \
    compute-lock.txt \
    fixture-sha256.txt \
    apk-sha256.txt \
    git-identity.txt \
    logcat-flutter.log \
    logcat-t086-markers.log \
    privacy-source-check.txt \
    privacy-log-check.txt \
    host-flutter-pub-get.log; do
    if [[ -f "$RUN_DIR/$file" ]]; then
      cp "$RUN_DIR/$file" "$EVIDENCE_DIR/$file" ||
        fail "cannot write evidence file $file"
    fi
  done
  if [[ -d "$RUN_DIR/screenshots" ]]; then
    mkdir -p "$EVIDENCE_DIR/screenshots" ||
      fail "cannot create evidence screenshots directory"
    cp "$RUN_DIR"/screenshots/*.png "$EVIDENCE_DIR/screenshots"/ ||
      fail "cannot write evidence screenshots"
  fi
  log "T086 DRIVER: evidence written to $EVIDENCE_DIR"
}

log "T086 DRIVER: run directory $RUN_DIR"
log "T086 DRIVER: shared heavy-work lock admitted (compute_slot.py --wait)"

if [[ ! -x "$FLUTTER" ]]; then
  fail "flutter executable not found at $FLUTTER"
fi
if [[ ! -x "$ADB" ]]; then
  fail "adb executable not found at $ADB"
fi

LOCK_PATH="/tmp/orca-maintainer-heavy-$(id -u).lock"
{
  log "mode=shared-heavy-work-lock"
  log "require=python3 $COMPUTE_SLOT --wait <command>"
  log "lock_path=$LOCK_PATH"
  log "inside_lock=1 (T086_COMPUTE_LOCK_HELD=1: the run is inside compute_slot.py's critical section)"
  log "orca_command_used=0"
  log "admitted_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >"$RUN_DIR/compute-lock.txt"

# --- 1. Device identity without Orca ---------------------------------------
ALL_DEVICES="$("$ADB" devices | awk 'NR>1 && NF>=2 && $2=="device" {print $1}')"
EMULATOR_DEVICES="$(printf '%s\n' "$ALL_DEVICES" | grep -E '^emulator-[0-9]+$' || true)"
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
  log "all_attached_transports=$(printf '%s\n' "$ALL_DEVICES" | sed '/^$/d' | paste -sd, -)"
  log "addressed_serial=$SERIAL"
  log "non_emulator_transports_addressed=none"
} >"$RUN_DIR/device-binding.txt"

# --- 1b. Commit-before-run gate ---------------------------------------------
# Evidence is bound to a committed HEAD: the working tree must be clean.
DIRTY_STATUS="$(git -C "$ROOT" status --porcelain)" \
  || fail "cannot read git status for $ROOT"
if [[ -n "$DIRTY_STATUS" ]]; then
  while IFS= read -r dirty_line; do
    fail "working tree is dirty; commit-before-run required (status line: $dirty_line)"
  done <<<"$DIRTY_STATUS"
fi
log "T086 DRIVER: commit-before-run gate passed (working tree must be clean)"

prepare_evidence_dir
log "T086 DRIVER: evidence directory $EVIDENCE_DIR"

ORIGINAL_ROTATION="$(settings_get system user_rotation || true)"
ORIGINAL_ACCELEROMETER="$(settings_get system accelerometer_rotation || true)"
ORIGINAL_STAY_ON="$(settings_get global stay_on_while_plugged_in || true)"

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
  log "mem_total_kb=$(adb_shell cat /proc/meminfo | awk '/MemTotal/ {print $2}')"
} >"$RUN_DIR/device-identity.txt"

# --- 2. Fixture --------------------------------------------------------------
adb_shell am force-stop "$PACKAGE" >/dev/null
adb_shell pm clear "$PACKAGE" >/dev/null 2>&1
adb_shell mkdir -p "$STAGING" >/dev/null
"$ADB" -s "$SERIAL" push "$APP/assets/fixtures/$FIXTURE" \
  "$STAGING/$FIXTURE" >/dev/null || fail "staging push failed: $FIXTURE"
adb_shell chmod 755 "$STAGING" >/dev/null
adb_shell chmod 644 "$STAGING/$FIXTURE" >/dev/null

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
  log "host $APP/assets/fixtures/$FIXTURE sha256=$HOST_FIXTURE_SHA"
  log "pages=2 (the committed fixture is used unchanged; no damaged-page variant)"
} >"$RUN_DIR/fixture-sha256.txt"

# --- 3. Privacy source check -------------------------------------------------
if grep -nE '\b(HttpClient|HttpRequest|Socket|WebSocket|RawDatagramSocket|NetworkImage)\b|https?://' \
  "$APP/$TEST_FILE" >"$RUN_DIR/privacy-source-check.txt" 2>&1; then
  printf 'FAIL: network API reference found in %s\n' "$TEST_FILE" \
    >>"$RUN_DIR/privacy-source-check.txt"
  PRIVACY_PASS=0
else
  printf 'PASS: no network API reference in %s\n' "$TEST_FILE" \
    >>"$RUN_DIR/privacy-source-check.txt"
  PRIVACY_PASS=1
fi

# --- 4. Device setup ---------------------------------------------------------
adb_shell settings put system accelerometer_rotation 0 >/dev/null
adb_shell settings put system user_rotation 0 >/dev/null
adb_shell svc power stayon true >/dev/null
adb_shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
adb_shell wm dismiss-keyguard >/dev/null 2>&1
sleep 2

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

# --- 6. Start the integration test ------------------------------------------
adb_shell logcat -c >/dev/null
mkdir -p "$RUN_DIR/screenshots" >/dev/null
# A previous aborted run can leave acknowledgements behind. Remove them before
# the test starts so no `_waitForDriver` can return on a stale ack.
adb_shell rm -f "$STAGING"/ack-* >/dev/null

(
  cd "$APP" || exit 1
  exec "${FLUTTER_ENV[@]}" "$FLUTTER" test --no-pub \
    "$TEST_FILE" -d "$SERIAL"
) >"$LOG" 2>&1 &
TEST_PID=$!

marker_present() {
  grep -F "T086_$1" "$LOG" >/dev/null 2>&1 && return 0
  "$ADB" -s "$SERIAL" logcat -d 2>/dev/null | grep -F "T086_$1" >/dev/null
}

wait_for_marker() {
  local marker="$1" deadline=$((SECONDS + ${2:-300}))
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

capture_screenshot() {
  local name="$1" marker="$2" timeout="${3:-900}"
  if ! wait_for_marker "$marker" "$timeout"; then
    log "T086 DRIVER: screenshot marker $marker not observed; test log follows"
    tail -160 "$LOG"
    fail "missing marker T086_$marker before screenshot $name"
  fi
  sleep 1
  "$ADB" -s "$SERIAL" exec-out screencap -p \
    >"$RUN_DIR/screenshots/$name.png" ||
    fail "screenshot $name failed"
  record "screenshot $name after T086_$marker"
  adb_shell touch "$STAGING/ack-$name" >/dev/null
  record "screenshot ack $name"
}

log "T086 DRIVER: waiting for the FLD-001 overflow marker"
capture_screenshot "overflow-warning" "SCREENSHOT_OVERFLOW_WARNING" 2400

log "T086 DRIVER: waiting for the filled page-1 marker"
capture_screenshot "page1-values" "SCREENSHOT_PAGE1_VALUES" 900

log "T086 DRIVER: waiting for the signed page-2 marker"
capture_screenshot "page2-signed" "SCREENSHOT_PAGE2_SIGNED" 900

log "T086 DRIVER: waiting for the preserved page-1 marker"
capture_screenshot "page1-preserved" "SCREENSHOT_PAGE1_PRESERVED" 1200

TEST_DEADLINE=$((SECONDS + 2400))
while kill -0 "$TEST_PID" 2>/dev/null; do
  if ((SECONDS >= TEST_DEADLINE)); then
    kill "$TEST_PID" 2>/dev/null
    wait "$TEST_PID" 2>/dev/null
    fail "integration test did not exit within 2400s after the last screenshot"
  fi
  sleep 2
done
wait "$TEST_PID"
TEST_EXIT=$?

# --- 7. Evidence collection -------------------------------------------------
{
  for apk in "$APP"/build/app/outputs/flutter-apk/*.apk; do
    [[ -f "$apk" ]] || continue
    log "path=$apk"
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
  log "driver_sha256=$(sha256sum "$ROOT/tools/android/t086_drive_fill.sh" | awk '{print $1}')"
  log "flutter=$("${FLUTTER_ENV[@]}" "$FLUTTER" --version 2>/dev/null | head -1)"
} >"$RUN_DIR/git-identity.txt"

{
  for name in "${SCREENSHOTS[@]}"; do
    shot="$RUN_DIR/screenshots/$name.png"
    if [[ ! -s "$shot" ]]; then
      log "$name MISSING"
      continue
    fi
    log "$name bytes=$(stat -c %s "$shot") sha256=$(sha256sum "$shot" | awk '{print $1}')"
  done
} >"$RUN_DIR/screenshot-hashes.txt"
UNIQUE_SCREENSHOTS="$(awk -F'sha256=' '/sha256=/ {print $2}' "$RUN_DIR/screenshot-hashes.txt" | sort -u | wc -l)"
[[ "$UNIQUE_SCREENSHOTS" -eq "${#SCREENSHOTS[@]}" ]] ||
  fail "the ${#SCREENSHOTS[@]} screenshot hashes are not distinct ($UNIQUE_SCREENSHOTS unique); see screenshot-hashes.txt"

adb_shell logcat -d -v threadtime >"$RUN_DIR/logcat-full.txt" 2>/dev/null
"$ADB" -s "$SERIAL" logcat -d -v threadtime -s flutter >"$RUN_DIR/logcat-flutter.log" 2>/dev/null
grep -E "T086_|ActivityTaskManager.*(de\\.feldexa|START)" \
  "$RUN_DIR/logcat-full.txt" >"$RUN_DIR/logcat-t086-markers.log" 2>/dev/null
grep -E "T086_" "$LOG" >"$RUN_DIR/markers-integration.txt" 2>/dev/null || true
rm -f "$RUN_DIR/logcat-full.txt"

if grep -nE 'Müller|Söhne|Berlin|1\.234,56|24\.12\.2025|Zeile eins|t086-fill\.pdf|/data/local/tmp/t086-fixtures' \
  "$LOG" >"$RUN_DIR/privacy-log-check.txt" 2>&1; then
  printf 'FAIL: document content, display name, or fixture path found in the integration log\n' \
    >>"$RUN_DIR/privacy-log-check.txt"
  PRIVACY_PASS=0
else
  printf 'PASS: no document content, display name, or fixture path in the integration log\n' \
    >>"$RUN_DIR/privacy-log-check.txt"
fi

OVERALL_EXIT="$TEST_EXIT"
if [[ "$TEST_EXIT" -eq 0 ]] &&
  marker_present "CLEANUP_DONE" &&
  [[ "$PRIVACY_PASS" -eq 1 ]]; then
  record "PASS (flutter test exit 0; cleanup marker observed; privacy checks PASS)"
  log "T086 DRIVER: PASS"
else
  OVERALL_EXIT=1
  record "FAIL (flutter test exit $TEST_EXIT; cleanup marker $(
    marker_present "CLEANUP_DONE" && echo present || echo absent
  ); privacy $([[ "$PRIVACY_PASS" -eq 1 ]] && echo PASS || echo FAIL))"
  log "T086 DRIVER: FAIL"
  tail -200 "$LOG"
fi
printf 'result=%s\nflutter_test_exit=%s\n' \
  "$([[ "$OVERALL_EXIT" -eq 0 ]] && echo PASS || echo FAIL)" \
  "$TEST_EXIT" >"$RUN_DIR/run-status.txt"

collect_evidence
exit "$OVERALL_EXIT"
