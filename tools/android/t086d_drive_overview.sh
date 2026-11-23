#!/usr/bin/env bash
# T086D host driver: runs the real EMULATOR document-overview journey.
#
# The journey is issue #282 / T086D (US4 scenario 8): import the committed
# two-page `sf-001.pdf`, confirm one real text suggestion on each page, open the
# new document overview, fill the page-1 value through the real value sheet,
# verify the visible per-field completion on a partially filled document,
# continue filling the page-2 field from its overview row, verify both fields
# complete, reopen the first field to verify the value is preserved, and return
# through „Weiter ausfüllen“ without losing either value. This script:
#   1. requires the exclusively allocated Orca Pixel 7 API 35 emulator session
#      attached to this worktree (`orca emulator list` is worktree-scoped);
#   2. stages the committed synthetic `sf-001.pdf` fixture, both pages readable,
#      and verifies its SHA-256 (no damaged-page variant is derived);
#   3. clears the test app data so the journey starts with an empty store;
#   4. starts `flutter test integration_test/android_overview_test.dart` in the
#      background and captures the three screenshot phases; stale ack files are
#      removed first, and the three screenshot hashes must be distinct;
#   5. records device identity, fixture/APK hashes, git identity (HEAD/tree/
#      branch/subject/status), marker-filtered logcat, the marker sequence
#      extracted from the integration log, and a source-level privacy check;
#   6. removes pushed fixtures/acks and clears the test app data again.
#
# T086D markers are printed by the integration-test process through the test
# harness, not by the app process, so `logcat-flutter.log` contains only engine
# `flutter` tag lines. The authoritative marker sequence is extracted from the
# integration log into `markers-integration.txt`.
#
# The tree must be committed before the run: the working tree must be clean.
#
# Evidence class is EMULATOR only when step 1 passes. Without a worktree-bound
# Orca allocation the script exits 2 with `EMULATOR NOT_RUN`; it never rebinds
# or steals another worktree's emulator session.
#
# Test-only tooling: adds no production dependency and changes no app file.
# Usage (repo root): tools/android/t086d_drive_overview.sh
set -uo pipefail

SERIAL="${T086D_SERIAL:-emulator-5554}"
EXPECTED_AVD="${T086D_AVD:-T025_Pixel7_API35_KVM_20261115}"
EXPECTED_API="${T086D_API:-35}"
ADB="${T086D_ADB:-$HOME/Android/Sdk/platform-tools/adb}"
FLUTTER="${T086D_FLUTTER:-$HOME/flutter/bin/flutter}"
ORCA="${T086D_ORCA:-orca}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/apps/feldexa_app"
TEST_FILE="integration_test/android_overview_test.dart"
RUN_DIR="${T086D_RUN_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/feldexa-t086d-run.XXXXXX")}"
EVIDENCE_DIR="${T086D_EVIDENCE_DIR:-$ROOT/specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t086d-overview}"
LOG="$RUN_DIR/integration-android-t086d.log"
SEQUENCE="$RUN_DIR/marker-sequence.txt"
BACKUP_DIR=""

STAGING="/data/local/tmp/t086d-fixtures"
PACKAGE="de.feldexa.app"
FIXTURE="sf-001.pdf"
FIXTURE_SHA256="22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038"
FIXTURE_SIZE_BYTES=5956

TEST_PID=""
TEST_EXIT=255
CLEANED=0
PRIVACY_PASS=0

adb_shell() {
  "$ADB" -s "$SERIAL" shell "$@" 2>/dev/null | tr -d '\r'
}

settings_get() {
  adb_shell settings get "$1" "$2"
}

log() {
  printf '%s\n' "$*"
}

record() {
  log "T086D DRIVER: $*"
  printf '%s\n' "$*" >>"$SEQUENCE"
}

fail() {
  log "T086D DRIVER: $*"
  exit 1
}

not_run() {
  log "T086D EMULATOR NOT_RUN: $*"
  exit 2
}

if [[ -n "${T086D_RUN_DIR:-}" ]]; then
  if [[ -e "$RUN_DIR" ]]; then
    log "T086D DRIVER: refusing to reuse existing run directory $RUN_DIR"
    exit 1
  fi
  mkdir -p "$RUN_DIR" || {
    log "T086D DRIVER: cannot create run directory $RUN_DIR"
    exit 1
  }
else
  [[ -n "$RUN_DIR" ]] || {
    log "T086D DRIVER: cannot create a temporary run directory"
    exit 1
  }
fi
: >"$SEQUENCE"

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
      if [[ "${T086D_REPLACE_EVIDENCE:-0}" != "1" ]]; then
        fail "refusing to overwrite existing evidence in $EVIDENCE_DIR; bind a fresh T086D_EVIDENCE_DIR or set T086D_REPLACE_EVIDENCE=1 to back up and replace"
      fi
      BACKUP_DIR="$RUN_DIR/evidence-backup"
      mkdir -p "$BACKUP_DIR" || fail "cannot create evidence backup directory"
      cp -a "$EVIDENCE_DIR"/. "$BACKUP_DIR"/ || fail "evidence backup failed"
      log "T086D DRIVER: backed up existing evidence to $BACKUP_DIR"
    fi
  else
    mkdir -p "$EVIDENCE_DIR" || fail "cannot create evidence directory $EVIDENCE_DIR"
  fi
}

collect_evidence() {
  local file
  for file in \
    integration-android-t086d.log \
    markers-integration.txt \
    marker-sequence.txt \
    screenshot-hashes.txt \
    run-status.txt \
    device-identity.txt \
    fixture-sha256.txt \
    apk-sha256.txt \
    git-identity.txt \
    orca-emulator-devices.json \
    orca-emulator-sessions.json \
    logcat-flutter.log \
    logcat-t086d-markers.log \
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
  log "T086D DRIVER: evidence written to $EVIDENCE_DIR"
}

log "T086D DRIVER: run directory $RUN_DIR"

if [[ ! -x "$FLUTTER" ]]; then
  fail "flutter executable not found at $FLUTTER"
fi
if [[ ! -x "$ADB" ]]; then
  fail "adb executable not found at $ADB"
fi

# --- 1. Exclusive worktree-bound Orca emulator allocation -------------------
DEVICES="$("$ADB" devices | awk 'NR>1 && NF>=2 && $2=="device" {print $1}')"
[[ "$(printf '%s\n' "$DEVICES" | sed '/^$/d' | wc -l)" -eq 1 ]] ||
  not_run "expected exactly one attached device, got: ${DEVICES:-none}"
[[ "$DEVICES" == "$SERIAL" ]] ||
  not_run "attached device is $DEVICES, expected $SERIAL"

SDK="$(adb_shell getprop ro.build.version.sdk)"
AVD_NAME="$(adb_shell getprop ro.boot.qemu.avd_name)"
[[ "$SDK" == "$EXPECTED_API" ]] ||
  not_run "API $EXPECTED_API required, device reports sdk=$SDK"
[[ "$AVD_NAME" == "$EXPECTED_AVD" ]] ||
  not_run "AVD $EXPECTED_AVD required, device reports '$AVD_NAME'"
[[ "$(adb_shell getprop sys.boot_completed)" == "1" ]] ||
  not_run "device has not completed boot"

if ! "$ORCA" emulator devices --json >"$RUN_DIR/orca-emulator-devices.json" 2>/dev/null; then
  not_run "orca emulator devices --json failed; no allocation evidence"
fi
if ! "$ORCA" emulator list --worktree "path:$ROOT" --json >"$RUN_DIR/orca-emulator-sessions.json" 2>/dev/null; then
  not_run "orca emulator list --json failed; no worktree session evidence"
fi
python3 - "$RUN_DIR/orca-emulator-devices.json" "$RUN_DIR/orca-emulator-sessions.json" "$SERIAL" "$EXPECTED_AVD" "$EXPECTED_API" <<'PY' ||
import json
import sys

devices_path, sessions_path, serial, avd, api = sys.argv[1:6]
with open(devices_path, encoding='utf-8') as handle:
    devices_payload = json.load(handle)
devices = devices_payload.get('result')
if not isinstance(devices, list):
    raise SystemExit('orca emulator devices result is not a list')
matches = [device for device in devices if device.get('id') == serial]
if len(matches) != 1:
    raise SystemExit(f'expected exactly one Orca device for {serial}')
device = matches[0]
if device.get('name') != avd:
    raise SystemExit(f"unexpected Orca device name {device.get('name')!r}")
if str(device.get('apiLevel')) != api:
    raise SystemExit(f"unexpected Orca API level {device.get('apiLevel')!r}")
if device.get('state') != 'booted':
    raise SystemExit(f"Orca device is not booted: {device.get('state')!r}")

with open(sessions_path, encoding='utf-8') as handle:
    sessions_payload = json.load(handle)
result = sessions_payload.get('result')
if not isinstance(result, dict):
    raise SystemExit('orca emulator list result is not an object')
sessions = result.get('sessions')
if not isinstance(sessions, list):
    raise SystemExit('orca emulator list sessions is not a list')
if not sessions:
    raise SystemExit(
        f'no Orca emulator session is attached to this worktree for {serial}'
    )
if not any(serial in json.dumps(session) for session in sessions):
    raise SystemExit(
        f'no worktree-bound Orca session references {serial}'
    )
PY
  not_run "emulator-5554 is booted but no exclusively allocated Orca session is attached to this worktree; do not reuse another worktree's allocation"

[[ -s "$RUN_DIR/orca-emulator-devices.json" ]] ||
  not_run "Orca device inventory is empty"
[[ -s "$RUN_DIR/orca-emulator-sessions.json" ]] ||
  not_run "Orca worktree session inventory is empty"

# --- 1b. Commit-before-run gate ---------------------------------------------
# Evidence is bound to a committed HEAD: the working tree must be clean.
DIRTY_STATUS="$(git -C "$ROOT" status --porcelain)"
if [[ -n "$DIRTY_STATUS" ]]; then
  while IFS= read -r dirty_line; do
    fail "working tree is dirty; commit-before-run required (status line: $dirty_line)"
  done <<<"$DIRTY_STATUS"
fi
log "T086D DRIVER: commit-before-run gate passed (working tree must be clean)"

prepare_evidence_dir
log "T086D DRIVER: evidence directory $EVIDENCE_DIR"

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
  log "qemu=$(adb_shell getprop ro.kernel.qemu)"
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
  log "pages=2 (both readable; no damaged-page variant derived)"
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
  grep -F "T086D_$1" "$LOG" >/dev/null 2>&1 && return 0
  "$ADB" -s "$SERIAL" logcat -d 2>/dev/null | grep -F "T086D_$1" >/dev/null
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
    log "T086D DRIVER: screenshot marker $marker not observed; test log follows"
    tail -160 "$LOG"
    fail "missing marker T086D_$marker before screenshot $name"
  fi
  sleep 1
  "$ADB" -s "$SERIAL" exec-out screencap -p \
    >"$RUN_DIR/screenshots/$name.png" ||
    fail "screenshot $name failed"
  record "screenshot $name after T086D_$marker"
  adb_shell touch "$STAGING/ack-$name" >/dev/null
  record "screenshot ack $name"
}

log "T086D DRIVER: waiting for the partial-overview marker"
capture_screenshot "overview-partial" "SCREENSHOT_OVERVIEW_PARTIAL" 1800

log "T086D DRIVER: waiting for the continued-overview marker"
capture_screenshot "overview-continued" "SCREENSHOT_OVERVIEW_CONTINUED" 900

log "T086D DRIVER: waiting for the preserved-value marker"
capture_screenshot "value-preserved" "SCREENSHOT_VALUE_PRESERVED" 900

TEST_DEADLINE=$((SECONDS + 1800))
while kill -0 "$TEST_PID" 2>/dev/null; do
  if ((SECONDS >= TEST_DEADLINE)); then
    kill "$TEST_PID" 2>/dev/null
    wait "$TEST_PID" 2>/dev/null
    fail "integration test did not exit within 1800s after the last screenshot"
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
  log "flutter=$("${FLUTTER_ENV[@]}" "$FLUTTER" --version 2>/dev/null | head -1)"
} >"$RUN_DIR/git-identity.txt"

{
  for name in overview-partial overview-continued value-preserved; do
    shot="$RUN_DIR/screenshots/$name.png"
    if [[ ! -s "$shot" ]]; then
      log "$name MISSING"
      continue
    fi
    log "$name bytes=$(stat -c %s "$shot") sha256=$(sha256sum "$shot" | awk '{print $1}')"
  done
} >"$RUN_DIR/screenshot-hashes.txt"
UNIQUE_SCREENSHOTS="$(awk -F'sha256=' '/sha256=/ {print $2}' "$RUN_DIR/screenshot-hashes.txt" | sort -u | wc -l)"
[[ "$UNIQUE_SCREENSHOTS" -eq 3 ]] ||
  fail "the three screenshot hashes are not distinct ($UNIQUE_SCREENSHOTS unique); see screenshot-hashes.txt"

adb_shell logcat -d -v threadtime >"$RUN_DIR/logcat-full.txt" 2>/dev/null
"$ADB" -s "$SERIAL" logcat -d -v threadtime -s flutter >"$RUN_DIR/logcat-flutter.log" 2>/dev/null
grep -E "T086D_|ActivityTaskManager.*(de\\.feldexa|START)" \
  "$RUN_DIR/logcat-full.txt" >"$RUN_DIR/logcat-t086d-markers.log" 2>/dev/null
grep -E "T086D_" "$LOG" >"$RUN_DIR/markers-integration.txt" 2>/dev/null || true
rm -f "$RUN_DIR/logcat-full.txt"

if grep -nE 'Antrag Müller|Berlin|sf-001\.pdf|/data/local/tmp/t086d-fixtures' \
  "$LOG" >"$RUN_DIR/privacy-log-check.txt" 2>&1; then
  printf 'FAIL: document content or fixture path found in the integration log\n' \
    >>"$RUN_DIR/privacy-log-check.txt"
  PRIVACY_PASS=0
else
  printf 'PASS: no document content or fixture path in the integration log\n' \
    >>"$RUN_DIR/privacy-log-check.txt"
fi

OVERALL_EXIT="$TEST_EXIT"
if [[ "$TEST_EXIT" -eq 0 ]] &&
  marker_present "CLEANUP_DONE" &&
  [[ "$PRIVACY_PASS" -eq 1 ]]; then
  record "PASS (flutter test exit 0; cleanup marker observed; privacy checks PASS)"
  log "T086D DRIVER: PASS"
else
  OVERALL_EXIT=1
  record "FAIL (flutter test exit $TEST_EXIT; cleanup marker $(
    marker_present "CLEANUP_DONE" && echo present || echo absent
  ); privacy $([[ "$PRIVACY_PASS" -eq 1 ]] && echo PASS || echo FAIL))"
  log "T086D DRIVER: FAIL"
  tail -200 "$LOG"
fi
printf 'result=%s\nflutter_test_exit=%s\n' \
  "$([[ "$OVERALL_EXIT" -eq 0 ]] && echo PASS || echo FAIL)" \
  "$TEST_EXIT" >"$RUN_DIR/run-status.txt"

collect_evidence
exit "$OVERALL_EXIT"
