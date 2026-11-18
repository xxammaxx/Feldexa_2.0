#!/usr/bin/env bash
# T149 host driver: runs the EMULATOR US1 journey and drives the real picker.
#
# The Flutter integration test cannot tap another app's window. This script:
#   1. verifies the exclusively allocated `emulator-5554` identity;
#   2. pushes the two synthetic fixtures to the picker-visible Downloads
#      directory and to an app-readable staging directory;
#   3. rotates the emulator to landscape so the 600 dp page-strip breakpoint is
#      crossed (real device UI, not a simulated viewport);
#   4. starts `flutter test integration_test/android_us1_journey_test.dart` in
#      the background and waits for the `T149_PICKER_READY:<n>` logcat markers;
#   5. drives DocumentsUI with `uiautomator dump` + `input tap`: open the
#      roots drawer, select Downloads, and tap the exact `t149-sf-*.pdf` row;
#   6. captures logs, dumps, device identity, and fixture hashes in a fresh
#      per-run directory;
#   7. restores rotation and removes every pushed fixture and device dump.
#
# Report-bound artifacts are never deleted or truncated. By default every
# working file and the final evidence set are written under a fresh `mktemp`
# run directory (`$T149_RUN_DIR` may name a new, not-yet-existing directory).
# `T149_EVIDENCE_DIR` may bind an explicit evidence directory; a non-empty
# target is refused unless `T149_REPLACE_EVIDENCE=1` is set, in which case the
# existing directory is backed up under the run directory before files are
# replaced. Temporary host dumps are removed by the cleanup trap; the run
# directory itself is retained for review.
#
# Test-only tooling: it adds no production dependency and changes no app file.
# Usage (repo root): tools/android/t149_drive_picker.sh
set -uo pipefail

SERIAL="${T149_SERIAL:-emulator-5554}"
ADB="${T149_ADB:-$HOME/Android/Sdk/platform-tools/adb}"
FLUTTER="${T149_FLUTTER:-$HOME/flutter/bin/flutter}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/apps/feldexa_app"
RUN_DIR="${T149_RUN_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/feldexa-t149-run.XXXXXX")}"
EVIDENCE_DIR="${T149_EVIDENCE_DIR:-$RUN_DIR/evidence}"
LOG="$RUN_DIR/integration-android-us1.log"
XML_DIR="$RUN_DIR/working-xml"
SEQUENCE="$RUN_DIR/picker-sequence.txt"
BACKUP_DIR=""

DOWNLOADS="/sdcard/Download"
STAGING="/data/local/tmp/t149-fixtures"
DUMPS=("/sdcard/t149-window-round1.xml" "/sdcard/t149-window-round2.xml")

FIXTURES=(
  "sf-001.pdf:t149-sf-001.pdf"
  "sf-protected.pdf:t149-sf-protected.pdf"
)
ROUND_FILES=("t149-sf-001.pdf" "t149-sf-protected.pdf")

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
  log "T149 DRIVER: $*"
  printf '%s\n' "$*" >>"$SEQUENCE"
}

fail() {
  log "T149 DRIVER: $*"
  exit 1
}

if [[ -n "${T149_RUN_DIR:-}" ]]; then
  if [[ -e "$RUN_DIR" ]]; then
    log "T149 DRIVER: refusing to reuse existing run directory $RUN_DIR"
    exit 1
  fi
  mkdir -p "$RUN_DIR" "$XML_DIR" || {
    log "T149 DRIVER: cannot create run directory $RUN_DIR"
    exit 1
  }
else
  [[ -n "$RUN_DIR" ]] || {
    log "T149 DRIVER: cannot create a temporary run directory"
    exit 1
  }
  mkdir -p "$XML_DIR" || {
    log "T149 DRIVER: cannot create $XML_DIR"
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
  adb_shell rm -f "$DOWNLOADS"/t149-sf-001.pdf "$DOWNLOADS"/t149-sf-protected.pdf >/dev/null
  adb_shell rm -rf "$STAGING" >/dev/null
  adb_shell rm -f "${DUMPS[@]}" /sdcard/t149-probe.pdf >/dev/null
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
      if [[ "${T149_REPLACE_EVIDENCE:-0}" != "1" ]]; then
        fail "refusing to overwrite existing evidence in $EVIDENCE_DIR; bind a fresh T149_EVIDENCE_DIR or set T149_REPLACE_EVIDENCE=1 to back up and replace"
      fi
      BACKUP_DIR="$RUN_DIR/evidence-backup"
      mkdir -p "$BACKUP_DIR" || fail "cannot create evidence backup directory"
      cp -a "$EVIDENCE_DIR"/. "$BACKUP_DIR"/ || fail "evidence backup failed"
      log "T149 DRIVER: backed up existing evidence to $BACKUP_DIR"
    fi
  else
    mkdir -p "$EVIDENCE_DIR" || fail "cannot create evidence directory $EVIDENCE_DIR"
  fi
}

collect_evidence() {
  local file
  for file in \
    integration-android-us1.log \
    picker-sequence.txt \
    picker-round1-roots.xml \
    picker-round1-drawer.xml \
    picker-round1-downloads.xml \
    picker-round2-downloads.xml \
    device-identity.txt \
    fixture-sha256.txt \
    apk-sha256.txt \
    logcat-flutter.log \
    logcat-picker-markers.log; do
    if [[ -f "$RUN_DIR/$file" ]]; then
      cp "$RUN_DIR/$file" "$EVIDENCE_DIR/$file" ||
        fail "cannot write evidence file $file"
    fi
  done
  log "T149 DRIVER: evidence written to $EVIDENCE_DIR"
}

prepare_evidence_dir
log "T149 DRIVER: run directory $RUN_DIR"
log "T149 DRIVER: evidence directory $EVIDENCE_DIR"

# --- 1. Device identity -----------------------------------------------------
DEVICES="$("$ADB" devices | awk 'NR>1 && NF>=2 && $2=="device" {print $1}')"
[[ "$(printf '%s\n' "$DEVICES" | sed '/^$/d' | wc -l)" -eq 1 ]] ||
  fail "expected exactly one attached device, got: ${DEVICES:-none}"
[[ "$DEVICES" == "$SERIAL" ]] ||
  fail "attached device is $DEVICES, expected $SERIAL"

ORIGINAL_ROTATION="$(settings_get system user_rotation || true)"
ORIGINAL_ACCELEROMETER="$(settings_get system accelerometer_rotation || true)"
ORIGINAL_STAY_ON="$(settings_get global stay_on_while_plugged_in || true)"

{
  log "serial=$SERIAL"
  log "avd=$(adb_shell getprop ro.boot.qemu.avd_name)"
  log "fingerprint=$(adb_shell getprop ro.build.fingerprint)"
  log "android_release=$(adb_shell getprop ro.build.version.release)"
  log "sdk=$(adb_shell getprop ro.build.version.sdk)"
  log "abi=$(adb_shell getprop ro.product.cpu.abi)"
  log "boot_completed=$(adb_shell getprop sys.boot_completed)"
  log "qemu=$(adb_shell getprop ro.kernel.qemu)"
  log "wm_size=$(adb_shell wm size | tr '\n' ' ')"
  log "wm_density=$(adb_shell wm density | tr '\n' ' ')"
  log "mem_total_kb=$(adb_shell cat /proc/meminfo | awk '/MemTotal/ {print $2}')"
  log "documentsui=$(adb_shell pm list packages com.google.android.documentsui)"
} >"$RUN_DIR/device-identity.txt"

# --- 2. Fixtures ------------------------------------------------------------
adb_shell mkdir -p "$STAGING" >/dev/null
for entry in "${FIXTURES[@]}"; do
  source_name="${entry%%:*}"
  picker_name="${entry##*:}"
  "$ADB" -s "$SERIAL" push "$APP/assets/fixtures/$source_name" \
    "$DOWNLOADS/$picker_name" >/dev/null || fail "push failed: $source_name"
  "$ADB" -s "$SERIAL" push "$APP/assets/fixtures/$source_name" \
    "$STAGING/$source_name" >/dev/null || fail "staging push failed: $source_name"
  adb_shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
    -d "file://$DOWNLOADS/$picker_name" >/dev/null
done
adb_shell chmod 644 "$STAGING"/*.pdf >/dev/null

{
  for entry in "${FIXTURES[@]}"; do
    source_name="${entry%%:*}"
    picker_name="${entry##*:}"
    log "picker $DOWNLOADS/$picker_name $(adb_shell sha256sum "$DOWNLOADS/$picker_name")"
    log "staging $STAGING/$source_name $(adb_shell sha256sum "$STAGING/$source_name")"
  done
} >"$RUN_DIR/fixture-sha256.txt"

# --- 3. Device setup: landscape and screen awake ---------------------------
adb_shell settings put system accelerometer_rotation 0 >/dev/null
adb_shell settings put system user_rotation 1 >/dev/null
adb_shell svc power stayon true >/dev/null
sleep 2

# --- 4. Start the integration test -----------------------------------------
adb_shell logcat -c >/dev/null

FLUTTER_ENV=(env "PATH=$HOME/flutter/bin:$HOME/Android/Sdk/platform-tools:$PATH")
if [[ -n "${JAVA_HOME:-}" ]]; then
  FLUTTER_ENV+=("JAVA_HOME=$JAVA_HOME")
fi
(
  cd "$APP" || exit 1
  exec "${FLUTTER_ENV[@]}" "$FLUTTER" test \
    integration_test/android_us1_journey_test.dart -d "$SERIAL"
) >"$LOG" 2>&1 &
TEST_PID=$!

marker_present() {
  # `flutter test -d` streams test `print`/`debugPrint` output to the host log,
  # not to Android logcat; the device logcat buffer is the fallback.
  grep -F "T149_$1" "$LOG" >/dev/null 2>&1 && return 0
  "$ADB" -s "$SERIAL" logcat -d 2>/dev/null | grep -F "T149_$1" >/dev/null
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

# The open drawer overlays the list while the covered file rows still appear in
# the accessibility dump; handle the drawer before any file row.
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


# The acceptance path always navigates to the Downloads root first, even when
# the default Recent view already lists the file. This keeps the sequence
# deterministic and independent of Recent ordering.
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

# Fallback: no roots control but the exact row is visible.
point = file_row_point()
if point:
    print('TAP %d %d file' % point)
    sys.exit(0)

print('NONE')
PY
}

drive_picker() {
  local round="$1" target="$2"
  local xml="$XML_DIR/picker-round$round.xml"
  local device_dump="${DUMPS[$((round - 1))]}"
  local attempts=0

  wait_for_picker || fail "DocumentsUI did not become the resumed activity for round $round"

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
          roots) cp "$xml" "$RUN_DIR/picker-round$round-roots.xml" ;;
          downloads) cp "$xml" "$RUN_DIR/picker-round$round-drawer.xml" ;;
          file) cp "$xml" "$RUN_DIR/picker-round$round-downloads.xml" ;;
        esac
        record "round $round attempt $attempts tab $4 at $2,$3"
        adb_shell input tap "$2" "$3" >/dev/null
        if [[ "$4" == "file" ]]; then
          return 0
        fi
        sleep 1
        ;;
      SCROLL)
        record "round $round attempt $attempts scroll Downloads at 1300,950 -> 1300,450"
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
  fail "could not tap '$target' in DocumentsUI for round $round"
}

# --- 5. Marker / picker coordination ---------------------------------------
log "T149 DRIVER: waiting for the start surface and round 1 picker marker"
if ! wait_for_marker "PICKER_READY:1" 600; then
  log "T149 DRIVER: round 1 marker not observed; test log follows"
  tail -40 "$LOG"
  wait "$TEST_PID"
  TEST_EXIT=$?
  exit "$TEST_EXIT"
fi
drive_picker 1 "${ROUND_FILES[0]}"

if ! wait_for_marker "ROUND1_OK" 300; then
  log "T149 DRIVER: round 1 did not reach ROUND1_OK; test log follows"
  tail -60 "$LOG"
  wait "$TEST_PID"
  TEST_EXIT=$?
  exit "$TEST_EXIT"
fi
log "T149 DRIVER: round 1 accepted import and page navigation verified"

log "T149 DRIVER: waiting for round 2 picker marker"
if ! wait_for_marker "PICKER_READY:2" 180; then
  log "T149 DRIVER: round 2 marker not observed; test log follows"
  tail -60 "$LOG"
  wait "$TEST_PID"
  TEST_EXIT=$?
  exit "$TEST_EXIT"
fi
drive_picker 2 "${ROUND_FILES[1]}"

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
grep -E "T149_|ActivityTaskManager.*(documentsui|de\.feldexa)|ActivityTaskManager.*START" \
  "$RUN_DIR/logcat-full.txt" >"$RUN_DIR/logcat-picker-markers.log" 2>/dev/null
rm -f "$RUN_DIR/logcat-full.txt"

collect_evidence

if [[ "$TEST_EXIT" -eq 0 ]] && marker_present "CLEANUP_DONE"; then
  log "T149 DRIVER: PASS (flutter test exit 0; cleanup marker observed)"
else
  log "T149 DRIVER: FAIL (flutter test exit $TEST_EXIT; cleanup marker $(
    marker_present "CLEANUP_DONE" && echo present || echo absent
  ))"
  tail -80 "$LOG"
fi

exit "$TEST_EXIT"
