#!/usr/bin/env bash
# T061 host driver: runs the real EMULATOR recognition integration test.
#
# No system picker is driven (T046/T149 own the picker). This script:
#   1. verifies the exclusively allocated Pixel 7 API 35 AVD
#      `T025_Pixel7_API35_KVM_20261115` on the single attached serial
#      `emulator-5554`, including the Orca device inventory;
#   2. pushes the committed synthetic `sf-001.pdf` fixture to an app-readable
#      staging directory and verifies its SHA-256;
#   3. starts `flutter test integration_test/android_recognition_test.dart` in
#      the background and waits for the `T061_*` screenshot markers;
#   4. captures page-0 suggestions, page-1 failure, and navigation screenshots
#      with `adb exec-out screencap -p`, then acknowledges each phase to the
#      test through a file in the staging directory;
#   5. captures the test log, marker-filtered logcat, device identity, fixture
#      hashes, APK hashes, git identity, and a source-level privacy check in a
#      fresh per-run directory;
#   6. removes every pushed fixture, screenshot acknowledgement, and dump and
#      restores the device settings it changed.
#
# Report-bound artifacts are never deleted or truncated. Every working file is
# written under a fresh `mktemp` run directory and the final evidence set is
# copied to the repository evidence directory. A non-empty evidence target is
# refused unless `T061_REPLACE_EVIDENCE=1` is set, in which case the existing
# directory is backed up under the run directory first.
#
# Test-only tooling: it adds no production dependency and changes no app file.
# Usage (repo root): tools/android/t061_drive_recognition.sh
set -uo pipefail

SERIAL="${T061_SERIAL:-emulator-5554}"
EXPECTED_AVD="${T061_AVD:-T025_Pixel7_API35_KVM_20261115}"
ADB="${T061_ADB:-$HOME/Android/Sdk/platform-tools/adb}"
FLUTTER="${T061_FLUTTER:-$HOME/flutter/bin/flutter}"
ORCA="${T061_ORCA:-orca}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/apps/feldexa_app"
TEST_FILE="integration_test/android_recognition_test.dart"
RUN_DIR="${T061_RUN_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/feldexa-t061-run.XXXXXX")}"
EVIDENCE_DIR="${T061_EVIDENCE_DIR:-$ROOT/specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-t061}"
LOG="$RUN_DIR/integration-android-t061.log"
SEQUENCE="$RUN_DIR/marker-sequence.txt"
BACKUP_DIR=""

STAGING="/data/local/tmp/t061-fixtures"
DUMPS=("/sdcard/t061-window.xml")

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
  log "T061 DRIVER: $*"
  printf '%s\n' "$*" >>"$SEQUENCE"
}

fail() {
  log "T061 DRIVER: $*"
  exit 1
}

if [[ -n "${T061_RUN_DIR:-}" ]]; then
  if [[ -e "$RUN_DIR" ]]; then
    log "T061 DRIVER: refusing to reuse existing run directory $RUN_DIR"
    exit 1
  fi
  mkdir -p "$RUN_DIR" || {
    log "T061 DRIVER: cannot create run directory $RUN_DIR"
    exit 1
  }
else
  [[ -n "$RUN_DIR" ]] || {
    log "T061 DRIVER: cannot create a temporary run directory"
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
  adb_shell rm -f "${DUMPS[@]}" >/dev/null
  adb_shell run-as de.feldexa rm -f cache/t061-damaged-*.pdf >/dev/null 2>&1
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
      if [[ "${T061_REPLACE_EVIDENCE:-0}" != "1" ]]; then
        fail "refusing to overwrite existing evidence in $EVIDENCE_DIR; bind a fresh T061_EVIDENCE_DIR or set T061_REPLACE_EVIDENCE=1 to back up and replace"
      fi
      BACKUP_DIR="$RUN_DIR/evidence-backup"
      mkdir -p "$BACKUP_DIR" || fail "cannot create evidence backup directory"
      cp -a "$EVIDENCE_DIR"/. "$BACKUP_DIR"/ || fail "evidence backup failed"
      log "T061 DRIVER: backed up existing evidence to $BACKUP_DIR"
    fi
  else
    mkdir -p "$EVIDENCE_DIR" || fail "cannot create evidence directory $EVIDENCE_DIR"
  fi
}

collect_evidence() {
  local file
  for file in \
    integration-android-t061.log \
    marker-sequence.txt \
    device-identity.txt \
    fixture-sha256.txt \
    apk-sha256.txt \
    git-identity.txt \
    orca-emulator-devices.json \
    orca-emulator-sessions.json \
    logcat-flutter.log \
    logcat-t061-markers.log \
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
  log "T061 DRIVER: evidence written to $EVIDENCE_DIR"
}

prepare_evidence_dir
log "T061 DRIVER: run directory $RUN_DIR"
log "T061 DRIVER: evidence directory $EVIDENCE_DIR"

if [[ ! -x "$FLUTTER" ]]; then
  fail "flutter executable not found at $FLUTTER"
fi
if [[ ! -x "$ADB" ]]; then
  fail "adb executable not found at $ADB"
fi

# --- 1. Device identity and exclusive allocation ---------------------------
DEVICES="$("$ADB" devices | awk 'NR>1 && NF>=2 && $2=="device" {print $1}')"
[[ "$(printf '%s\n' "$DEVICES" | sed '/^$/d' | wc -l)" -eq 1 ]] ||
  fail "expected exactly one attached device, got: ${DEVICES:-none}"
[[ "$DEVICES" == "$SERIAL" ]] ||
  fail "attached device is $DEVICES, expected $SERIAL"

SDK="$(adb_shell getprop ro.build.version.sdk)"
[[ "$SDK" == "35" ]] || fail "API 35 required, device reports sdk=$SDK"
AVD_NAME="$(adb_shell getprop ro.boot.qemu.avd_name)"
[[ "$AVD_NAME" == "$EXPECTED_AVD" ]] ||
  fail "AVD $EXPECTED_AVD required, device reports '$AVD_NAME'"
[[ "$(adb_shell getprop sys.boot_completed)" == "1" ]] ||
  fail "device has not completed boot"

if ! "$ORCA" emulator devices --json >"$RUN_DIR/orca-emulator-devices.json" 2>/dev/null; then
  fail "orca emulator devices --json failed; no Orca allocation evidence"
fi
python3 - "$RUN_DIR/orca-emulator-devices.json" "$SERIAL" "$EXPECTED_AVD" <<'PY' ||
import json
import sys

path, serial, avd = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding='utf-8') as handle:
    payload = json.load(handle)
devices = payload.get('result')
if not isinstance(devices, list):
    raise SystemExit('orca emulator devices result is not a list')
matches = [device for device in devices if device.get('id') == serial]
if len(matches) != 1:
    raise SystemExit(f'expected exactly one Orca device for {serial}')
device = matches[0]
if device.get('name') != avd:
    raise SystemExit(f"unexpected Orca device name {device.get('name')!r}")
if str(device.get('apiLevel')) != '35':
    raise SystemExit(f"unexpected Orca API level {device.get('apiLevel')!r}")
if device.get('state') != 'booted':
    raise SystemExit(f"Orca device is not booted: {device.get('state')!r}")
PY
  fail "Orca device inventory does not confirm the exclusive AVD/serial/API 35"

"$ORCA" emulator list --json >"$RUN_DIR/orca-emulator-sessions.json" 2>/dev/null || true

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
  log "orca_inventory_device=$(python3 -c "import json;d=json.load(open('$RUN_DIR/orca-emulator-devices.json'));print([x for x in d['result'] if x.get('id')=='$SERIAL'][0]['name'])")"
} >"$RUN_DIR/device-identity.txt"

# --- 2. Fixture -------------------------------------------------------------
adb_shell am force-stop de.feldexa >/dev/null
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
  log "staging_mode=$(adb_shell stat -c '%a' "$STAGING")"
  log "fixture_mode=$(adb_shell stat -c '%a' "$STAGING/$FIXTURE")"
} >"$RUN_DIR/fixture-sha256.txt"

# --- 3. Privacy source check ------------------------------------------------
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

# --- 4. Device setup: portrait and screen awake -----------------------------
adb_shell settings put system accelerometer_rotation 0 >/dev/null
adb_shell settings put system user_rotation 0 >/dev/null
adb_shell svc power stayon true >/dev/null
adb_shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
adb_shell wm dismiss-keyguard >/dev/null 2>&1
sleep 2

# --- 5. Host preparation ----------------------------------------------------
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

# --- 6. Start the integration test -----------------------------------------
adb_shell logcat -c >/dev/null
mkdir -p "$RUN_DIR/screenshots" >/dev/null

(
  cd "$APP" || exit 1
  exec "${FLUTTER_ENV[@]}" "$FLUTTER" test --no-pub \
    "$TEST_FILE" -d "$SERIAL"
) >"$LOG" 2>&1 &
TEST_PID=$!

marker_present() {
  grep -F "T061_$1" "$LOG" >/dev/null 2>&1 && return 0
  "$ADB" -s "$SERIAL" logcat -d 2>/dev/null | grep -F "T061_$1" >/dev/null
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
    log "T061 DRIVER: screenshot marker $marker not observed; test log follows"
    tail -120 "$LOG"
    fail "missing marker T061_$marker before screenshot $name"
  fi
  sleep 1
  "$ADB" -s "$SERIAL" exec-out screencap -p \
    >"$RUN_DIR/screenshots/$name.png" ||
    fail "screenshot $name failed"
  record "screenshot $name after T061_$marker"
  adb_shell touch "$STAGING/ack-$name" >/dev/null
  record "screenshot ack $name"
}

log "T061 DRIVER: waiting for page-0 suggestions marker"
# The first marker can only appear after the debug APK build, install, startup,
# and the single-page analysis, so its bound covers the whole host build.
capture_screenshot "page0-suggestions" "SCREENSHOT_PAGE0_SUGGESTIONS" 1800

log "T061 DRIVER: waiting for page-1 failure marker"
capture_screenshot "page1-failure" "SCREENSHOT_PAGE1_FAILURE"

log "T061 DRIVER: waiting for navigation marker"
capture_screenshot "navigation" "SCREENSHOT_NAVIGATION"

TEST_DEADLINE=$((SECONDS + 1800))
while kill -0 "$TEST_PID" 2>/dev/null; do
  if ((SECONDS >= TEST_DEADLINE)); then
    kill "$TEST_PID" 2>/dev/null
    wait "$TEST_PID" 2>/dev/null
    fail "integration test did not exit within 1800s after the navigation screenshot"
  fi
  sleep 2
done
wait "$TEST_PID"
TEST_EXIT=$?

# --- 7. Evidence collection -------------------------------------------------
{
  for apk in "$APP"/build/app/outputs/flutter-apk/*.apk; do
    [[ -f "$apk" ]] || continue
    sha256sum "$apk"
  done
} >"$RUN_DIR/apk-sha256.txt"

{
  log "head=$(git -C "$ROOT" rev-parse HEAD)"
  log "branch=$(git -C "$ROOT" branch --show-current)"
  log "status_porcelain:"
  git -C "$ROOT" status --porcelain
  log "diff_name_status_base_1ee20f0:"
  git -C "$ROOT" diff --name-status 1ee20f0..HEAD
  log "flutter=$("${FLUTTER_ENV[@]}" "$FLUTTER" --version 2>/dev/null | head -1)"
} >"$RUN_DIR/git-identity.txt"

adb_shell logcat -d -v threadtime >"$RUN_DIR/logcat-full.txt" 2>/dev/null
"$ADB" -s "$SERIAL" logcat -d -v threadtime -s flutter >"$RUN_DIR/logcat-flutter.log" 2>/dev/null
grep -E "T061_|ActivityTaskManager.*(de\\.feldexa|START)" \
  "$RUN_DIR/logcat-full.txt" >"$RUN_DIR/logcat-t061-markers.log" 2>/dev/null
rm -f "$RUN_DIR/logcat-full.txt"

if grep -nE 'Meldebescheinigung|Musterstadt|sf-001\.pdf|/data/local/tmp/t061-fixtures' \
  "$LOG" >"$RUN_DIR/privacy-log-check.txt" 2>&1; then
  printf 'FAIL: document content or fixture path found in the integration log\n' \
    >>"$RUN_DIR/privacy-log-check.txt"
  PRIVACY_PASS=0
else
  printf 'PASS: no document content or fixture path in the integration log\n' \
    >>"$RUN_DIR/privacy-log-check.txt"
fi

collect_evidence

OVERALL_EXIT="$TEST_EXIT"
if [[ "$TEST_EXIT" -eq 0 ]] &&
  marker_present "CLEANUP_DONE" &&
  [[ "$PRIVACY_PASS" -eq 1 ]]; then
  record "PASS (flutter test exit 0; cleanup marker observed; privacy checks PASS)"
  log "T061 DRIVER: PASS"
else
  OVERALL_EXIT=1
  record "FAIL (flutter test exit $TEST_EXIT; cleanup marker $(
    marker_present "CLEANUP_DONE" && echo present || echo absent
  ); privacy $([[ "$PRIVACY_PASS" -eq 1 ]] && echo PASS || echo FAIL))"
  log "T061 DRIVER: FAIL"
  tail -160 "$LOG"
fi

exit "$OVERALL_EXIT"
