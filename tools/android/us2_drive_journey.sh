#!/usr/bin/env bash
# Issue #217 Phase B2 host driver: runs the real EMULATOR US2 journey.
#
# The Flutter integration test cannot tap another app's window. This script:
#   1. verifies the exclusively allocated Orca emulator identity and API 35;
#   2. pushes the committed synthetic `sf-001.pdf` fixture to the
#      picker-visible Downloads directory and to an app-readable staging
#      directory;
#   3. starts `flutter test integration_test/android_us2_journey_test.dart` in
#      the background and waits for the `US2_PICKER_READY` marker;
#   4. drives DocumentsUI with `uiautomator dump` + `input tap`;
#   5. captures the `editor-ready`, `suggestions-visible`, and `after-review`
#      screenshots with `adb exec-out screencap -p` when the test markers
#      appear;
#   6. captures the test log, device identity, fixture hashes, APK hash, and a
#      marker-filtered logcat excerpt in a fresh per-run directory;
#   7. restores device settings and removes every pushed fixture and dump.
#
# Report-bound artifacts are never deleted or truncated. By default every
# working file is written under a fresh `mktemp` run directory and the final
# evidence set is copied to the repository evidence directory. A non-empty
# evidence target is refused unless `US2_REPLACE_EVIDENCE=1` is set, in which
# case the existing directory is backed up under the run directory first.
#
# Test-only tooling: it adds no production dependency and changes no app file.
# Usage (repo root): tools/android/us2_drive_journey.sh
set -uo pipefail

SERIAL="${US2_SERIAL:-emulator-5554}"
ADB="${US2_ADB:-$HOME/Android/Sdk/platform-tools/adb}"
FLUTTER="${US2_FLUTTER:-$HOME/flutter/bin/flutter}"
ORCA="${US2_ORCA:-orca}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/apps/feldexa_app"
RUN_DIR="${US2_RUN_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/feldexa-us2-run.XXXXXX")}"
EVIDENCE_DIR="${US2_EVIDENCE_DIR:-$ROOT/specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration}"
LOG="$RUN_DIR/integration-android-us2.log"
XML_DIR="$RUN_DIR/working-xml"
SEQUENCE="$RUN_DIR/picker-sequence.txt"
BACKUP_DIR=""

DOWNLOADS="/sdcard/Download"
STAGING="/data/local/tmp/us2-fixtures"
DUMPS=("/sdcard/us2-window-round1.xml")

FIXTURE="sf-001.pdf"
PICKER_FILE="us2-sf-001.pdf"

TEST_PID=""
TEST_EXIT=255
CLEANED=0

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
  log "US2 DRIVER: $*"
  printf '%s\n' "$*" >>"$SEQUENCE"
}

fail() {
  log "US2 DRIVER: $*"
  exit 1
}

if [[ -n "${US2_RUN_DIR:-}" ]]; then
  if [[ -e "$RUN_DIR" ]]; then
    log "US2 DRIVER: refusing to reuse existing run directory $RUN_DIR"
    exit 1
  fi
  mkdir -p "$RUN_DIR" "$XML_DIR" || {
    log "US2 DRIVER: cannot create run directory $RUN_DIR"
    exit 1
  }
else
  [[ -n "$RUN_DIR" ]] || {
    log "US2 DRIVER: cannot create a temporary run directory"
    exit 1
  }
  mkdir -p "$XML_DIR" || {
    log "US2 DRIVER: cannot create $XML_DIR"
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
  adb_shell rm -f "$DOWNLOADS/$PICKER_FILE" >/dev/null
  adb_shell rm -rf "$STAGING" >/dev/null
  adb_shell rm -f "${DUMPS[@]}" /sdcard/us2-probe.pdf >/dev/null
  rm -rf "$XML_DIR"
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
      if [[ "${US2_REPLACE_EVIDENCE:-0}" != "1" ]]; then
        fail "refusing to overwrite existing evidence in $EVIDENCE_DIR; bind a fresh US2_EVIDENCE_DIR or set US2_REPLACE_EVIDENCE=1 to back up and replace"
      fi
      BACKUP_DIR="$RUN_DIR/evidence-backup"
      mkdir -p "$BACKUP_DIR" || fail "cannot create evidence backup directory"
      cp -a "$EVIDENCE_DIR"/. "$BACKUP_DIR"/ || fail "evidence backup failed"
      log "US2 DRIVER: backed up existing evidence to $BACKUP_DIR"
    fi
  else
    mkdir -p "$EVIDENCE_DIR" || fail "cannot create evidence directory $EVIDENCE_DIR"
  fi
}

collect_evidence() {
  local file
  for file in \
    integration-android-us2.log \
    picker-sequence.txt \
    picker-round1-roots.xml \
    picker-round1-drawer.xml \
    picker-round1-downloads.xml \
    device-identity.txt \
    fixture-sha256.txt \
    apk-sha256.txt \
    orca-emulator-session.json \
    logcat-flutter.log \
    logcat-us2-markers.log; do
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
  log "US2 DRIVER: evidence written to $EVIDENCE_DIR"
}

prepare_evidence_dir
log "US2 DRIVER: run directory $RUN_DIR"
log "US2 DRIVER: evidence directory $EVIDENCE_DIR"

# --- 1. Device identity and Orca allocation --------------------------------
DEVICES="$("$ADB" devices | awk 'NR>1 && NF>=2 && $2=="device" {print $1}')"
[[ "$(printf '%s\n' "$DEVICES" | sed '/^$/d' | wc -l)" -eq 1 ]] ||
  fail "expected exactly one attached device, got: ${DEVICES:-none}"
[[ "$DEVICES" == "$SERIAL" ]] ||
  fail "attached device is $DEVICES, expected $SERIAL"

SDK="$(adb_shell getprop ro.build.version.sdk)"
[[ "$SDK" == "35" ]] || fail "API 35 required, device reports sdk=$SDK"
[[ "$(adb_shell getprop sys.boot_completed)" == "1" ]] ||
  fail "device has not completed boot"

if ! "$ORCA" emulator list --json >"$RUN_DIR/orca-emulator-session.json" 2>/dev/null; then
  fail "orca emulator list --json failed; no Orca emulator allocation evidence"
fi
python3 - "$RUN_DIR/orca-emulator-session.json" "$SERIAL" "$ROOT" <<'PY' ||
import json
import sys

path, serial, root = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding='utf-8') as handle:
    payload = json.load(handle)
sessions = (payload.get('result') or {}).get('sessions') or []
matches = [session for session in sessions if session.get('deviceUdid') == serial]
if not matches:
    raise SystemExit(f'no Orca session for {serial}')
session = matches[0]
if session.get('streamUrl') != f'scrcpy://{serial}':
    raise SystemExit(f"unexpected streamUrl {session.get('streamUrl')!r}")
if not session.get('streamCodec'):
    raise SystemExit('empty streamCodec')
worktree = session.get('worktreeId') or ''
if not worktree.endswith(root):
    raise SystemExit(f'Orca session worktree {worktree!r} does not bind {root!r}')
PY
  fail "Orca emulator session is not bound to this worktree/serial"

ORIGINAL_ROTATION="$(settings_get system user_rotation || true)"
ORIGINAL_ACCELEROMETER="$(settings_get system accelerometer_rotation || true)"
ORIGINAL_STAY_ON="$(settings_get global stay_on_while_plugged_in || true)"

{
  log "serial=$SERIAL"
  log "avd=$(adb_shell getprop ro.boot.qemu.avd_name)"
  log "fingerprint=$(adb_shell getprop ro.build.fingerprint)"
  log "android_release=$(adb_shell getprop ro.build.version.release)"
  log "sdk=$SDK"
  log "abi=$(adb_shell getprop ro.product.cpu.abi)"
  log "boot_completed=$(adb_shell getprop sys.boot_completed)"
  log "qemu=$(adb_shell getprop ro.kernel.qemu)"
  log "wm_size=$(adb_shell wm size | tr '\n' ' ')"
  log "wm_density=$(adb_shell wm density | tr '\n' ' ')"
  log "mem_total_kb=$(adb_shell cat /proc/meminfo | awk '/MemTotal/ {print $2}')"
  log "documentsui=$(adb_shell pm list packages com.google.android.documentsui)"
  log "orca_stream_url=$(python3 -c "import json;d=json.load(open('$RUN_DIR/orca-emulator-session.json'));s=[x for x in (d.get('result') or {}).get('sessions') or [] if x.get('deviceUdid')=='$SERIAL'][0];print(s.get('streamUrl'))")"
  log "orca_stream_codec=$(python3 -c "import json;d=json.load(open('$RUN_DIR/orca-emulator-session.json'));s=[x for x in (d.get('result') or {}).get('sessions') or [] if x.get('deviceUdid')=='$SERIAL'][0];print(s.get('streamCodec'))")"
} >"$RUN_DIR/device-identity.txt"

# --- 2. Fixture -------------------------------------------------------------
adb_shell mkdir -p "$STAGING" >/dev/null
"$ADB" -s "$SERIAL" push "$APP/assets/fixtures/$FIXTURE" \
  "$DOWNLOADS/$PICKER_FILE" >/dev/null || fail "push failed: $FIXTURE"
"$ADB" -s "$SERIAL" push "$APP/assets/fixtures/$FIXTURE" \
  "$STAGING/$FIXTURE" >/dev/null || fail "staging push failed: $FIXTURE"
adb_shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
  -d "file://$DOWNLOADS/$PICKER_FILE" >/dev/null
adb_shell chmod 644 "$STAGING/$FIXTURE" >/dev/null

{
  log "picker $DOWNLOADS/$PICKER_FILE $(adb_shell sha256sum "$DOWNLOADS/$PICKER_FILE")"
  log "staging $STAGING/$FIXTURE $(adb_shell sha256sum "$STAGING/$FIXTURE")"
  log "host $(sha256sum "$APP/assets/fixtures/$FIXTURE")"
} >"$RUN_DIR/fixture-sha256.txt"

# --- 3. Device setup: portrait and screen awake ----------------------------
adb_shell settings put system accelerometer_rotation 0 >/dev/null
adb_shell settings put system user_rotation 0 >/dev/null
adb_shell svc power stayon true >/dev/null
sleep 2

# --- 4. Start the integration test -----------------------------------------
adb_shell logcat -c >/dev/null
mkdir -p "$RUN_DIR/screenshots" >/dev/null

FLUTTER_ENV=(env "PATH=$HOME/flutter/bin:$HOME/Android/Sdk/platform-tools:$PATH")
if [[ -n "${JAVA_HOME:-}" ]]; then
  FLUTTER_ENV+=("JAVA_HOME=$JAVA_HOME")
fi
(
  cd "$APP" || exit 1
  exec "${FLUTTER_ENV[@]}" "$FLUTTER" test \
    integration_test/android_us2_journey_test.dart -d "$SERIAL"
) >"$LOG" 2>&1 &
TEST_PID=$!

marker_present() {
  grep -F "US2_$1" "$LOG" >/dev/null 2>&1 && return 0
  "$ADB" -s "$SERIAL" logcat -d 2>/dev/null | grep -F "US2_$1" >/dev/null
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

wait_for_picker() {
  local deadline=$((SECONDS + 45))
  while ((SECONDS < deadline)); do
    if adb_shell dumpsys activity activities |
      grep "topResumedActivity.*com.google.android.documentsui" >/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# Prints one action for the current DocumentsUI frame.
# Output: TAP <x> <y> <role> | SCROLL | NONE | NOT_PICKER
picker_action() {
  local xml="$1" target="$2"
  python3 - "$xml" "$target" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET

path, target = sys.argv[1], sys.argv[2]
root = ET.parse(path).getroot()
nodes = list(root.iter('node'))
parents = {child: parent for parent in nodes for child in parent}


def bounds(node):
    match = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.get('bounds', ''))
    if not match:
        return None
    x1, y1, x2, y2 = (int(value) for value in match.groups())
    return x1, y1, x2, y2


def center(node):
    box = bounds(node)
    if not box:
        return None
    x1, y1, x2, y2 = box
    return (x1 + x2) // 2, (y1 + y2) // 2


def text_of(node):
    return node.get('text', '') or ''


packages = {node.get('package') for node in nodes if node.get('package')}
if packages and 'com.google.android.documentsui' not in packages:
    print('NOT_PICKER')
    sys.exit(0)

drawer_open = any(text_of(node) == 'Open from' for node in nodes)
if drawer_open:
    downloads = [
        node
        for node in nodes
        if text_of(node) == 'Downloads'
        and node.get('resource-id', '') == 'android:id/title'
    ]
    if downloads:
        point = center(downloads[0])
        if point:
            print('TAP %d %d downloads' % point)
            sys.exit(0)
    print('NONE')
    sys.exit(0)


def file_row_point():
    file_node = next((node for node in nodes if text_of(node) == target), None)
    if file_node is None:
        return None
    row = file_node
    while row is not None and row.get('resource-id', '').split('/')[-1] != 'item_root':
        row = parents.get(row)
    return center(row if row is not None else file_node)


in_downloads = any(
    node.get('resource-id', '').endswith('breadcrumb_text')
    and text_of(node) == 'Downloads'
    for node in nodes
) or any(text_of(node) == 'Files in Downloads' for node in nodes)
if in_downloads:
    point = file_row_point()
    if point:
        print('TAP %d %d file' % point)
        sys.exit(0)
    print('SCROLL')
    sys.exit(0)

show_roots = next(
    (
        node
        for node in nodes
        if (node.get('content-desc') or '') == 'Show roots'
        or text_of(node) == 'Show roots'
    ),
    None,
)
if show_roots is not None:
    point = center(show_roots)
    if point:
        print('TAP %d %d roots' % point)
        sys.exit(0)

point = file_row_point()
if point:
    print('TAP %d %d file' % point)
    sys.exit(0)

print('NONE')
PY
}

drive_picker() {
  local target="$1"
  local xml="$XML_DIR/picker-round1.xml"
  local device_dump="${DUMPS[0]}"
  local attempts=0

  wait_for_picker || fail "DocumentsUI did not become the resumed activity"

  while ((attempts < 30)); do
    attempts=$((attempts + 1))
    adb_shell rm -f "$device_dump" >/dev/null
    adb_shell uiautomator dump "$device_dump" >/dev/null
    "$ADB" -s "$SERIAL" pull "$device_dump" "$xml" >/dev/null 2>&1 ||
      { sleep 1; continue; }
    action="$(picker_action "$xml" "$target")"
    case "$action" in
      "TAP "*" file" | "TAP "*" roots" | "TAP "*" downloads")
        # shellcheck disable=SC2086
        set -- $action
        case "$4" in
          roots) cp "$xml" "$RUN_DIR/picker-round1-roots.xml" ;;
          downloads) cp "$xml" "$RUN_DIR/picker-round1-drawer.xml" ;;
          file) cp "$xml" "$RUN_DIR/picker-round1-downloads.xml" ;;
        esac
        record "attempt $attempts tab $4 at $2,$3"
        adb_shell input tap "$2" "$3" >/dev/null
        if [[ "$4" == "file" ]]; then
          return 0
        fi
        sleep 1
        ;;
      SCROLL)
        record "attempt $attempts scroll Downloads at 1300,950 -> 1300,450"
        adb_shell input swipe 1300 950 1300 450 400 >/dev/null
        sleep 1
        ;;
      NOT_PICKER)
        sleep 1
        ;;
      *)
        sleep 1
        ;;
    esac
  done
  fail "could not tap '$target' in DocumentsUI"
}

capture_screenshot() {
  local name="$1"
  sleep 1
  "$ADB" -s "$SERIAL" exec-out screencap -p \
    >"$RUN_DIR/screenshots/$name.png" ||
    fail "screenshot $name failed"
  record "screenshot $name"
  adb_shell touch "$STAGING/ack-$name" >/dev/null
  record "screenshot ack $name"
}

# --- 5. Marker / picker coordination ---------------------------------------
log "US2 DRIVER: waiting for the start surface and picker marker"
if ! wait_for_marker "PICKER_READY" 600; then
  log "US2 DRIVER: picker marker not observed; test log follows"
  tail -60 "$LOG"
  wait "$TEST_PID"
  TEST_EXIT=$?
  exit "$TEST_EXIT"
fi
drive_picker "$PICKER_FILE"

if ! wait_for_marker "SCREENSHOT_EDITOR_READY" 300; then
  log "US2 DRIVER: editor screenshot marker not observed; test log follows"
  tail -80 "$LOG"
  wait "$TEST_PID"
  TEST_EXIT=$?
  exit "$TEST_EXIT"
fi
capture_screenshot "editor-ready"

if ! wait_for_marker "SCREENSHOT_SUGGESTIONS_VISIBLE" 900; then
  log "US2 DRIVER: suggestions screenshot marker not observed; test log follows"
  tail -100 "$LOG"
  wait "$TEST_PID"
  TEST_EXIT=$?
  exit "$TEST_EXIT"
fi
capture_screenshot "suggestions-visible"

if ! wait_for_marker "SCREENSHOT_AFTER_REVIEW" 300; then
  log "US2 DRIVER: after-review screenshot marker not observed; test log follows"
  tail -100 "$LOG"
  wait "$TEST_PID"
  TEST_EXIT=$?
  exit "$TEST_EXIT"
fi
capture_screenshot "after-review"

wait "$TEST_PID"
TEST_EXIT=$?

{
  for apk in "$APP"/build/app/outputs/flutter-apk/*.apk; do
    [[ -f "$apk" ]] || continue
    sha256sum "$apk"
  done
} >"$RUN_DIR/apk-sha256.txt"

adb_shell logcat -d -v threadtime >"$RUN_DIR/logcat-full.txt" 2>/dev/null
"$ADB" -s "$SERIAL" logcat -d -v threadtime -s flutter >"$RUN_DIR/logcat-flutter.log" 2>/dev/null
grep -E "US2_|ActivityTaskManager.*(documentsui|de\.feldexa)|ActivityTaskManager.*START" \
  "$RUN_DIR/logcat-full.txt" >"$RUN_DIR/logcat-us2-markers.log" 2>/dev/null
rm -f "$RUN_DIR/logcat-full.txt"

collect_evidence

if [[ "$TEST_EXIT" -eq 0 ]] && marker_present "CLEANUP_DONE"; then
  log "US2 DRIVER: PASS (flutter test exit 0; cleanup marker observed)"
else
  log "US2 DRIVER: FAIL (flutter test exit $TEST_EXIT; cleanup marker $(
    marker_present "CLEANUP_DONE" && echo present || echo absent
  ))"
  tail -120 "$LOG"
fi

exit "$TEST_EXIT"
