#!/usr/bin/env bash
# T071 host driver: runs the real EMULATOR Android touch move/resize review test.
#
# The journey is issue #71 / T071: the real import -> analysis -> confirm flow of
# the composed editor, then the T071B touch geometry layer driven on the
# emulator's touch surface — body drags at 0.5x/1x/3x/8x fit-width (plus one
# page-clamp drag), all four corner and all four edge resize handles, the 4 x 4
# pt minimum size, pointer cancel, undo, and two-finger pan/pinch. This script:
#   1. requires the exclusively allocated Orca Pixel 7 API 35 emulator session
#      attached to this worktree (`orca emulator list` is worktree-scoped);
#   2. stages the committed synthetic `sf-001.pdf` fixture and verifies its
#      SHA-256; the integration test then derives the T061 damaged-page-2 source
#      deterministically (5956 bytes, SHA-256 57c1ade1...) before import, so page
#      1 stays usable and page 2 imports as unreadable;
#   3. clears the test app data so the journey starts with an empty store;
#   4. starts `flutter test integration_test/android_review_test.dart` in the
#      background and captures the twelve screenshot phases; stale ack files are
#      removed first, every screenshot marker must be observed, and all twelve
#      screenshot hashes must be distinct;
#   5. records device identity, fixture/APK hashes, git identity (HEAD/tree/
#      branch/subject/status), marker-filtered logcat, the marker sequence
#      extracted from the integration log, the exact host/emulator commands with
#      their exit codes, and source-level plus log-level privacy checks;
#   6. removes pushed fixtures/acks and clears the test app data again.
#
# T071 markers are printed by the integration-test process through the test
# harness, not by the app process, so `logcat-flutter.log` contains only engine
# `flutter` tag lines. The authoritative marker sequence is extracted from the
# integration log into `markers-integration.txt`.
#
# The tree must be committed before the run: only the pre-existing
# ` M apps/feldexa_app/android/gradlew.bat` line-ending change may be present.
#
# Evidence class is EMULATOR only when step 1 passes. Without a worktree-bound
# Orca allocation the script exits 2 with `EMULATOR NOT_RUN`; it never rebinds
# or steals another worktree's emulator session.
#
# Test-only tooling: adds no production dependency and changes no app file.
# Usage (repo root): tools/android/t071_drive_touch.sh
set -uo pipefail

SERIAL="${T071_SERIAL:-emulator-5554}"
EXPECTED_AVD="${T071_AVD:-T025_Pixel7_API35_KVM_20261115}"
EXPECTED_API="${T071_API:-35}"
ADB="${T071_ADB:-$HOME/Android/Sdk/platform-tools/adb}"
FLUTTER="${T071_FLUTTER:-$HOME/flutter/bin/flutter}"
ORCA="${T071_ORCA:-orca}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/apps/feldexa_app"
TEST_FILE="integration_test/android_review_test.dart"
RUN_DIR="${T071_RUN_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/feldexa-t071-run.XXXXXX")}"
EVIDENCE_DIR="${T071_EVIDENCE_DIR:-$ROOT/specs/001-scanned-form-workflow/reports/artifacts/2026-11-21-t071-touch}"
LOG="$RUN_DIR/integration-android-t071.log"
SEQUENCE="$RUN_DIR/marker-sequence.txt"
COMMANDS="$RUN_DIR/commands.txt"
BACKUP_DIR=""

STAGING="/data/local/tmp/t071-fixtures"
PACKAGE="de.feldexa.app"
FIXTURE="sf-001.pdf"
FIXTURE_SHA256="22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038"
# Derived in-test from the staged fixture, never pushed or committed.
DAMAGED_FIXTURE_SHA256="57c1ade1ab2c00375ac61703db3d4ce5d27b996ea067647aba585866dc6ec221"
FIXTURE_SIZE_BYTES=5956
SCREENSHOT_COUNT=12

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
  log "T071 DRIVER: $*"
  printf '%s\n' "$*" >>"$SEQUENCE"
}

# Records a host or emulator command with its exit code, so the evidence names
# exactly what ran instead of paraphrasing it.
record_cmd() {
  local exit_code="$1"
  shift
  printf 'exit=%s cmd=%s\n' "$exit_code" "$*" >>"$COMMANDS"
}

fail() {
  log "T071 DRIVER: $*"
  exit 1
}

not_run() {
  log "T071 EMULATOR NOT_RUN: $*"
  exit 2
}

if [[ -n "${T071_RUN_DIR:-}" ]]; then
  if [[ -e "$RUN_DIR" ]]; then
    log "T071 DRIVER: refusing to reuse existing run directory $RUN_DIR"
    exit 1
  fi
  mkdir -p "$RUN_DIR" || {
    log "T071 DRIVER: cannot create run directory $RUN_DIR"
    exit 1
  }
else
  [[ -n "$RUN_DIR" ]] || {
    log "T071 DRIVER: cannot create a temporary run directory"
    exit 1
  }
fi
: >"$SEQUENCE"
: >"$COMMANDS"

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
  record_cmd "$?" "adb -s $SERIAL shell pm clear $PACKAGE (cleanup)"
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
      if [[ "${T071_REPLACE_EVIDENCE:-0}" != "1" ]]; then
        fail "refusing to overwrite existing evidence in $EVIDENCE_DIR; bind a fresh T071_EVIDENCE_DIR or set T071_REPLACE_EVIDENCE=1 to back up and replace"
      fi
      BACKUP_DIR="$RUN_DIR/evidence-backup"
      mkdir -p "$BACKUP_DIR" || fail "cannot create evidence backup directory"
      cp -a "$EVIDENCE_DIR"/. "$BACKUP_DIR"/ || fail "evidence backup failed"
      log "T071 DRIVER: backed up existing evidence to $BACKUP_DIR"
    fi
  else
    mkdir -p "$EVIDENCE_DIR" || fail "cannot create evidence directory $EVIDENCE_DIR"
  fi
}

collect_evidence() {
  local file
  for file in \
    integration-android-t071.log \
    markers-integration.txt \
    marker-sequence.txt \
    commands.txt \
    screenshot-hashes.txt \
    run-status.txt \
    device-identity.txt \
    fixture-sha256.txt \
    apk-sha256.txt \
    git-identity.txt \
    orca-emulator-devices.json \
    orca-emulator-sessions.json \
    logcat-flutter.log \
    logcat-t071-markers.log \
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
  log "T071 DRIVER: evidence written to $EVIDENCE_DIR"
}

log "T071 DRIVER: run directory $RUN_DIR"

if [[ ! -x "$FLUTTER" ]]; then
  fail "flutter executable not found at $FLUTTER"
fi
if [[ ! -x "$ADB" ]]; then
  fail "adb executable not found at $ADB"
fi

# --- 1. Exclusive worktree-bound Orca emulator allocation -------------------
DEVICES="$("$ADB" devices | awk 'NR>1 && NF>=2 && $2=="device" {print $1}')"
record_cmd "$?" "adb devices"
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
record_cmd "$?" "orca emulator devices --json"
if ! "$ORCA" emulator list --worktree "path:$ROOT" --json >"$RUN_DIR/orca-emulator-sessions.json" 2>/dev/null; then
  not_run "orca emulator list --json failed; no worktree session evidence"
fi
record_cmd "$?" "orca emulator list --worktree path:$ROOT --json"
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
# Evidence is bound to a committed HEAD. The only tolerated dirty line is the
# pre-existing gradlew.bat line-ending change, which must never be staged.
ALLOWED_DIRTY_LINE=" M apps/feldexa_app/android/gradlew.bat"
DIRTY_STATUS="$(git -C "$ROOT" status --porcelain)"
if [[ -n "$DIRTY_STATUS" ]]; then
  while IFS= read -r dirty_line; do
    if [[ "$dirty_line" != "$ALLOWED_DIRTY_LINE" ]]; then
      fail "working tree is dirty; commit-before-run required (unexpected status line: $dirty_line)"
    fi
  done <<<"$DIRTY_STATUS"
fi
log "T071 DRIVER: commit-before-run gate passed (only the pre-existing gradlew.bat change may be present)"

prepare_evidence_dir
log "T071 DRIVER: evidence directory $EVIDENCE_DIR"

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
record_cmd "$?" "adb -s $SERIAL shell pm clear $PACKAGE"
adb_shell mkdir -p "$STAGING" >/dev/null
"$ADB" -s "$SERIAL" push "$APP/assets/fixtures/$FIXTURE" \
  "$STAGING/$FIXTURE" >/dev/null || fail "staging push failed: $FIXTURE"
record_cmd "$?" "adb -s $SERIAL push $APP/assets/fixtures/$FIXTURE $STAGING/$FIXTURE"
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
  log "expected_damaged_sha256=$DAMAGED_FIXTURE_SHA256"
  log "damaged_derivation=T061 second MediaBox replaced by 29 spaces; same $FIXTURE_SIZE_BYTES bytes; derived in-test before import"
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
) >"$RUN_DIR/host-flutter-pub-get.log" 2>&1
record_cmd "$?" "cd apps/feldexa_app && flutter pub get --offline"
grep -q 'Got dependencies' "$RUN_DIR/host-flutter-pub-get.log" ||
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
record "started: cd apps/feldexa_app && flutter test --no-pub $TEST_FILE -d $SERIAL (pid $TEST_PID)"

marker_present() {
  grep -F "T071_$1" "$LOG" >/dev/null 2>&1 && return 0
  "$ADB" -s "$SERIAL" logcat -d 2>/dev/null | grep -F "T071_$1" >/dev/null
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
    log "T071 DRIVER: screenshot marker $marker not observed; test log follows"
    tail -160 "$LOG"
    fail "missing marker T071_$marker before screenshot $name"
  fi
  sleep 1
  "$ADB" -s "$SERIAL" exec-out screencap -p \
    >"$RUN_DIR/screenshots/$name.png" ||
    fail "screenshot $name failed"
  record_cmd "$?" "adb -s $SERIAL exec-out screencap -p > screenshots/$name.png"
  record "screenshot $name after T071_$marker"
  adb_shell touch "$STAGING/ack-$name" >/dev/null
  record "screenshot ack $name"
}

log "T071 DRIVER: waiting for the corner-resize marker (import, analysis, confirm, four corner drags)"
capture_screenshot "resize-corners" "SCREENSHOT_RESIZE_CORNERS" 2400

log "T071 DRIVER: waiting for the edge-resize marker"
capture_screenshot "resize-edges" "SCREENSHOT_RESIZE_EDGES"

log "T071 DRIVER: waiting for the 0.5x body-drag marker"
capture_screenshot "move-0.5x" "SCREENSHOT_MOVE_0_5X"

log "T071 DRIVER: waiting for the 1x body-drag marker"
capture_screenshot "move-1x" "SCREENSHOT_MOVE_1X"

log "T071 DRIVER: waiting for the 3x body-drag marker"
capture_screenshot "move-3x" "SCREENSHOT_MOVE_3X"

log "T071 DRIVER: waiting for the 8x body-drag marker"
capture_screenshot "move-8x" "SCREENSHOT_MOVE_8X"

log "T071 DRIVER: waiting for the page-clamp marker"
capture_screenshot "move-clamped" "SCREENSHOT_MOVE_CLAMPED"

log "T071 DRIVER: waiting for the undo marker"
capture_screenshot "undo" "SCREENSHOT_UNDO"

log "T071 DRIVER: waiting for the pointer-cancel marker"
capture_screenshot "cancel" "SCREENSHOT_CANCEL"

log "T071 DRIVER: waiting for the two-finger pinch marker"
capture_screenshot "two-finger-pinch" "SCREENSHOT_TWO_FINGER_PINCH"

log "T071 DRIVER: waiting for the two-finger pan marker"
capture_screenshot "two-finger-pan" "SCREENSHOT_TWO_FINGER_PAN"

log "T071 DRIVER: waiting for the minimum-size marker"
capture_screenshot "min-size" "SCREENSHOT_MIN_SIZE"

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
record_cmd "$TEST_EXIT" "flutter test --no-pub $TEST_FILE -d $SERIAL"

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
  for name in resize-corners resize-edges move-0.5x move-1x move-3x move-8x \
    move-clamped undo cancel two-finger-pinch two-finger-pan min-size; do
    shot="$RUN_DIR/screenshots/$name.png"
    if [[ ! -s "$shot" ]]; then
      log "$name MISSING"
      continue
    fi
    log "$name bytes=$(stat -c %s "$shot") sha256=$(sha256sum "$shot" | awk '{print $1}')"
  done
} >"$RUN_DIR/screenshot-hashes.txt"
UNIQUE_SCREENSHOTS="$(awk -F'sha256=' '/sha256=/ {print $2}' "$RUN_DIR/screenshot-hashes.txt" | sort -u | wc -l)"
CAPTURED_SCREENSHOTS="$(grep -c 'sha256=' "$RUN_DIR/screenshot-hashes.txt")"
[[ "$CAPTURED_SCREENSHOTS" -eq "$SCREENSHOT_COUNT" ]] ||
  fail "only $CAPTURED_SCREENSHOTS of $SCREENSHOT_COUNT screenshots were captured; see screenshot-hashes.txt"
[[ "$UNIQUE_SCREENSHOTS" -eq "$SCREENSHOT_COUNT" ]] ||
  fail "the $SCREENSHOT_COUNT screenshot hashes are not distinct ($UNIQUE_SCREENSHOTS unique); see screenshot-hashes.txt"

adb_shell logcat -d -v threadtime >"$RUN_DIR/logcat-full.txt" 2>/dev/null
"$ADB" -s "$SERIAL" logcat -d -v threadtime -s flutter >"$RUN_DIR/logcat-flutter.log" 2>/dev/null
grep -E "T071_|ActivityTaskManager.*(de\\.feldexa|START)" \
  "$RUN_DIR/logcat-full.txt" >"$RUN_DIR/logcat-t071-markers.log" 2>/dev/null
grep -E "T071_" "$LOG" >"$RUN_DIR/markers-integration.txt" 2>/dev/null || true
rm -f "$RUN_DIR/logcat-full.txt"

if grep -nE 'Müller|Söhne|Meldebescheinigung|Musterstadt|sf-001\.pdf|/data/local/tmp/t071-fixtures' \
  "$LOG" >"$RUN_DIR/privacy-log-check.txt" 2>&1; then
  printf 'FAIL: document content or fixture path found in the integration log\n' \
    >>"$RUN_DIR/privacy-log-check.txt"
  PRIVACY_PASS=0
else
  printf 'PASS: no document content or fixture path in the integration log\n' \
    >>"$RUN_DIR/privacy-log-check.txt"
fi

# --- 8. Phase-marker contract ------------------------------------------------
REQUIRED_MARKERS=(
  "T071_FIXTURE_READY:BYTES=5956:MATCH=1"
  "T071_DAMAGED_FIXTURE_READY:BYTES=5956:MATCH=1"
  "T071_FIELD_CONFIRMED:PAGE=0"
  "T071_RESIZE_CORNERS_DONE:"
  "T071_HIT_REGION:EDGE=centerLeft:"
  "T071_RESIZE_EDGES_DONE:"
  "T071_MOVE:move-0.5x:"
  "T071_MOVE:move-1x:"
  "T071_MOVE:move-3x:"
  "T071_MOVE:move-8x:"
  "T071_MOVE:move-clamped:"
  "T071_UNDO:RESTORED_EXACT=1:"
  "T071_CANCEL:PAGE=0"
  "T071_TWO_FINGER:pinch:COMMITS=0"
  "T071_TWO_FINGER:pan:COMMITS=0"
  "T071_MIN_SIZE:PT=4"
  "T071_READBACK:OK:"
  "T071_CLEANUP_DONE"
)
MISSING_MARKERS=0
{
  printf 'required-marker check (integration log)\n'
  for required in "${REQUIRED_MARKERS[@]}"; do
    if grep -F "$required" "$LOG" >/dev/null 2>&1; then
      printf 'PRESENT %s\n' "$required"
    else
      printf 'MISSING %s\n' "$required"
    fi
  done
} >"$RUN_DIR/marker-contract.txt"
MISSING_MARKERS="$(grep -c '^MISSING ' "$RUN_DIR/marker-contract.txt")"
printf 'missing=%s\n' "$MISSING_MARKERS" >>"$RUN_DIR/marker-contract.txt"
[[ "$MISSING_MARKERS" -eq 0 ]] ||
  fail "$MISSING_MARKERS required phase markers are missing; see marker-contract.txt"

OVERALL_EXIT="$TEST_EXIT"
if [[ "$TEST_EXIT" -eq 0 ]] &&
  marker_present "CLEANUP_DONE" &&
  [[ "$PRIVACY_PASS" -eq 1 ]]; then
  record "PASS (flutter test exit 0; cleanup marker observed; marker contract complete; privacy checks PASS)"
  log "T071 DRIVER: PASS"
else
  OVERALL_EXIT=1
  record "FAIL (flutter test exit $TEST_EXIT; cleanup marker $(
    marker_present "CLEANUP_DONE" && echo present || echo absent
  ); privacy $([[ "$PRIVACY_PASS" -eq 1 ]] && echo PASS || echo FAIL))"
  log "T071 DRIVER: FAIL"
  tail -200 "$LOG"
fi
printf 'result=%s\nflutter_test_exit=%s\n' \
  "$([[ "$OVERALL_EXIT" -eq 0 ]] && echo PASS || echo FAIL)" \
  "$TEST_EXIT" >"$RUN_DIR/run-status.txt"

collect_evidence
cp "$RUN_DIR/marker-contract.txt" "$EVIDENCE_DIR/marker-contract.txt" 2>/dev/null || true
exit "$OVERALL_EXIT"
