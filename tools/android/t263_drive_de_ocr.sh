#!/usr/bin/env bash
# T263 host driver: real EMULATOR German OCR qualification run (issue #263).
#
# What this script does, in order:
#   1. binds the device from the ADB transport table, without any supervisor
#      allocation: exactly one attached `emulator-<n>` transport, that transport
#      equal to the requested serial, an emulator-only serial, the expected
#      Pixel 7 API 35 AVD, and a completed boot. Other attached devices (for
#      example a physical handset or a wireless transport) are counted but never
#      addressed: every adb device command is scoped with `-s` and the serial
#      must be an emulator serial;
#   2. builds the T263 scan variants on the host (Poppler render plus the
#      declared pixel degradations) and stages the additive `sf-005` reference
#      PDF, its pre-annotated ground truth, and those rasters in an
#      app-writable staging directory, verifying every SHA-256;
#   3. runs `flutter test integration_test/android_de_ocr_test.dart`, which
#      executes the production raster port, the production bundled ML Kit OCR
#      port, and the production `AnalyzeDocument` pipeline for every variant and
#      writes two run files (EMULATOR and EMULATOR_INJECTED_RASTER) plus a
#      label-takeover store round trip;
#   4. pulls the run files into the evidence directory and scores them with
#      `tools/metrics/de_ocr_qualification.dart`, so the report is reproducible
#      from the committed bytes;
#   5. also records the PDF text-layer control run (no device);
#   6. captures device identity, APK and fixture hashes, git identity, the
#      marker log, and a privacy check that the integration log contains no
#      recognized document text;
#   7. removes every staged file and stops the app.
#
# Report-bound artifacts are never deleted or truncated. Working files live in a
# fresh `mktemp` run directory; the evidence set is copied into the repository
# evidence directory. A non-empty evidence directory is refused unless
# `T263_REPLACE_EVIDENCE=1` is set, in which case it is backed up first.
#
# Usage (repo root): tools/android/t263_drive_de_ocr.sh
set -uo pipefail

SERIAL="${T263_SERIAL:-emulator-5554}"
EXPECTED_AVD="${T263_AVD:-T025_Pixel7_API35_KVM_20261115}"
ADB="${T263_ADB:-$HOME/Android/Sdk/platform-tools/adb}"
FLUTTER="${T263_FLUTTER:-$HOME/flutter/bin/flutter}"
DART="${T263_DART:-$HOME/flutter/bin/dart}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/apps/feldexa_app"
TEST_FILE="integration_test/android_de_ocr_test.dart"
RUN_DIR="${T263_RUN_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/feldexa-t263-run.XXXXXX")}"
EVIDENCE_DIR="${T263_EVIDENCE_DIR:-$ROOT/specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263}"
LOG="$RUN_DIR/integration-android-t263.log"
SEQUENCE="$RUN_DIR/marker-sequence.txt"
BACKUP_DIR=""

STAGING="/data/local/tmp/t263-fixtures"
# The integration test writes its run files into the app cache directory and
# reports the absolute path as `T263_OUTPUT_PATH=<dir>`. That directory is
# writable by the app without a storage permission and is pulled through
# `adb exec-out run-as <app id>` while the test is still running, because the
# test runner uninstalls the app when it exits (which also deletes
# `Android/data/<package>`). Writing to `Android/data/<package>` directly is
# not permitted for a targetSdk 36 app.
APP_ID="de.feldexa.app"
DEVICE_OUTPUT_DIR=""
FIXTURE_PDF="$ROOT/apps/feldexa_app/assets/fixtures/sf-005.pdf"
GROUND_TRUTH="$ROOT/tools/corpus/de-ocr/reference-de.ground-truth.json"
VARIANTS_DIR="$RUN_DIR/variants"

TEST_PID=""
TEST_EXIT=255
CLEANED=0
PRIVACY_PASS=0
# Set only after the device gate has bound the serial. Device commands are
# refused before that, so the cleanup trap can never address a serial the gate
# did not validate (an unvalidated serial could be the physical handset).
DEVICE_BOUND=0

adb_shell() {
  [[ "$DEVICE_BOUND" -eq 1 ]] || return 1
  "$ADB" -s "$SERIAL" shell "$@" 2>/dev/null | tr -d '\r'
}

log() {
  printf '%s\n' "$*"
}

record() {
  log "T263 DRIVER: $*"
  printf '%s\n' "$*" >>"$SEQUENCE"
}

fail() {
  log "T263 DRIVER: $*"
  exit 1
}

# An emulator gate failure is not a run failure: nothing was measured, so the
# evidence class stays NOT_RUN.
not_run() {
  log "T263 EMULATOR NOT_RUN: $*"
  exit 2
}

# Evidence files are committed, so they never carry an absolute host path: repo
# paths become `apps/...` and tool paths become `~/...`.
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

# Evidence must not repeat a foreign device identity, so the attached ADB
# transports are counted by class rather than listed.
transport_summary() {
  local all="$1" emulators="$2"
  local all_count emulator_count
  # "attached" means every transport adb lists, regardless of its state
  # (unauthorized/offline devices still count as attached).
  all_count="$(printf '%s\n' "$all" | sed '/^$/d' | wc -l)"
  emulator_count="$(printf '%s\n' "$emulators" | sed '/^$/d' | wc -l)"
  log "all_attached_transports_count=$all_count"
  log "emulator_transports=$emulator_count"
  log "non_emulator_transports=$((all_count - emulator_count))"
}

mkdir -p "$RUN_DIR" || {
  log "T263 DRIVER: cannot create run directory $RUN_DIR"
  exit 1
}
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
  if [[ -n "$DEVICE_OUTPUT_DIR" ]]; then
    adb_shell run-as "$APP_ID" rm -rf "$DEVICE_OUTPUT_DIR" >/dev/null
  fi
  adb_shell am force-stop "$APP_ID" >/dev/null
  rm -f "$RUN_DIR/logcat-full.txt"
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
      if [[ "${T263_REPLACE_EVIDENCE:-0}" != "1" ]]; then
        fail "refusing to overwrite existing evidence in $EVIDENCE_DIR; bind a fresh T263_EVIDENCE_DIR or set T263_REPLACE_EVIDENCE=1"
      fi
      BACKUP_DIR="$RUN_DIR/evidence-backup"
      mkdir -p "$BACKUP_DIR" || fail "cannot create evidence backup directory"
      cp -a "$EVIDENCE_DIR"/. "$BACKUP_DIR"/ || fail "evidence backup failed"
      log "T263 DRIVER: backed up existing evidence to $BACKUP_DIR"
    fi
  else
    mkdir -p "$EVIDENCE_DIR" || fail "cannot create evidence directory $EVIDENCE_DIR"
  fi
}

collect_evidence() {
  local file
  for file in \
    integration-android-t263.log \
    marker-sequence.txt \
    device-identity.txt \
    device-binding.txt \
    fixture-sha256.txt \
    apk-sha256.txt \
    git-identity.txt \
    logcat-t263-markers.log \
    privacy-log-check.txt \
    privacy-source-check.txt \
    t263-variants.json \
    host-generate-check.log \
    host-suite-verify.log \
    metrics-emulator.log \
    metrics-text-layer.log \
    t263-report.json \
    t263-report.md \
    t263-text-layer-run.json \
    t263-text-layer-report.json \
    commands.txt; do
    if [[ -f "$RUN_DIR/$file" ]]; then
      cp "$RUN_DIR/$file" "$EVIDENCE_DIR/$file" ||
        fail "cannot write evidence file $file"
    fi
  done
  for file in t263-run-emulator.json t263-run-injected.json; do
    if [[ -f "$RUN_DIR/pulled/$file" ]]; then
      cp "$RUN_DIR/pulled/$file" "$EVIDENCE_DIR/$file" ||
        fail "cannot write run file $file"
    fi
  done
  log "T263 DRIVER: evidence written to $EVIDENCE_DIR"
}

prepare_evidence_dir
log "T263 DRIVER: run directory $RUN_DIR"
log "T263 DRIVER: evidence directory $EVIDENCE_DIR"

for executable in "$FLUTTER" "$ADB" "$DART"; do
  [[ -x "$executable" ]] || fail "required executable not found: $executable"
done
[[ -f "$FIXTURE_PDF" ]] || fail "missing fixture $FIXTURE_PDF"
[[ -f "$GROUND_TRUTH" ]] || fail "missing ground truth $GROUND_TRUTH"

# --- 1. Host fixture checks -------------------------------------------------
(
  cd "$ROOT" || exit 1
  "$DART" run tools/corpus/synthetic/generate.dart --check
) >"$RUN_DIR/host-generate-check.log" 2>&1 ||
  fail "generator --check is not current; see host-generate-check.log"
(
  cd "$ROOT" || exit 1
  bash tools/corpus/de-ocr/verify.sh
) >"$RUN_DIR/host-suite-verify.log" 2>&1 ||
  fail "suite verification failed; see host-suite-verify.log"

# --- 2. Device identity and scoped target ----------------------------------
# No supervisor layer is asked for an allocation: the gate reads the ADB
# transport table directly and fails closed in this order.
#   1. count the emulator transports; exactly one is required;
#   2. that emulator must be the requested serial;
#   3. the requested serial must itself be an emulator serial, so a physical
#      handset can never be addressed even when it is the only attached device.
# Other attached devices (physical handset, wireless transport) are counted but
# never addressed, because every adb device command is scoped with `-s $SERIAL`
# and the serial passed the emulator check first.
ADB_TABLE="$("$ADB" devices)"
ALL_TRANSPORTS="$(printf '%s\n' "$ADB_TABLE" | awk 'NR>1 && NF>=1 && $1 !~ /^(List|of|devices)$/ {print $1}')"
ALL_DEVICES="$(printf '%s\n' "$ADB_TABLE" | awk 'NR>1 && NF>=2 && $2=="device" {print $1}')"
EMULATOR_DEVICES="$(printf '%s\n' "$ALL_DEVICES" | grep -E '^emulator-[0-9]+$' || true)"
[[ "$(printf '%s\n' "$EMULATOR_DEVICES" | sed '/^$/d' | wc -l)" -eq 1 ]] ||
  not_run "expected exactly one attached emulator, got: ${EMULATOR_DEVICES:-none}"
[[ "$EMULATOR_DEVICES" == "$SERIAL" ]] ||
  not_run "attached emulator is $EMULATOR_DEVICES, expected $SERIAL"
[[ "$SERIAL" =~ ^emulator-[0-9]+$ ]] ||
  not_run "refusing a non-emulator serial: $SERIAL (physical devices are prohibited)"
# The serial is now proven to be the one attached emulator, so every later adb
# command (including the cleanup trap) may address it.
DEVICE_BOUND=1

SDK="$(adb_shell getprop ro.build.version.sdk)"
[[ "$SDK" == "35" ]] || not_run "API 35 required, device reports sdk=$SDK"
AVD_NAME="$(adb_shell getprop ro.boot.qemu.avd_name)"
[[ "$AVD_NAME" == "$EXPECTED_AVD" ]] ||
  not_run "AVD $EXPECTED_AVD required, device reports '$AVD_NAME'"
[[ "$(adb_shell getprop sys.boot_completed)" == "1" ]] ||
  not_run "device has not completed boot"
record "target device serial=$SERIAL (all adb commands scoped with -s)"

{
  log "serial=$SERIAL"
  log "emulator_serials=$(printf '%s\n' "$EMULATOR_DEVICES" | sed '/^$/d' | paste -sd, -)"
  transport_summary "$ALL_TRANSPORTS" "$EMULATOR_DEVICES"
  log "addressed_serial=$SERIAL"
  log "non_emulator_transports_addressed=none"
} >"$RUN_DIR/device-binding.txt"

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

# --- 3. Variants and staging ------------------------------------------------
mkdir -p "$VARIANTS_DIR" || fail "cannot create variants directory"
(
  cd "$ROOT" || exit 1
  python3 tools/corpus/de-ocr/make_variants.py \
    --pdf "$FIXTURE_PDF" --output "$VARIANTS_DIR"
) >"$RUN_DIR/host-variants.log" 2>&1 ||
  fail "variant generation failed; see host-variants.log"
cp "$VARIANTS_DIR/t263-variants.json" "$RUN_DIR/t263-variants.json"

adb_shell am force-stop "$APP_ID" >/dev/null
adb_shell rm -rf "$STAGING" >/dev/null
adb_shell mkdir -p "$STAGING" >/dev/null
# The integration test reads the additive reference PDF as `reference-de.pdf`.
"$ADB" -s "$SERIAL" push "$FIXTURE_PDF" "$STAGING/reference-de.pdf" >/dev/null ||
  fail "fixture push failed"
"$ADB" -s "$SERIAL" push "$GROUND_TRUTH" "$STAGING/reference-de.ground-truth.json" >/dev/null ||
  fail "ground truth push failed"
"$ADB" -s "$SERIAL" push "$VARIANTS_DIR/t263-variants.json" "$STAGING/t263-variants.json" >/dev/null ||
  fail "variant manifest push failed"
for raster in "$VARIANTS_DIR"/*.gray8; do
  [[ -f "$raster" ]] || continue
  "$ADB" -s "$SERIAL" push "$raster" "$STAGING/$(basename "$raster")" >/dev/null ||
    fail "raster push failed: $(basename "$raster")"
done
adb_shell chmod 777 "$STAGING" >/dev/null
adb_shell chmod 666 "$STAGING/reference-de.pdf" "$STAGING/reference-de.ground-truth.json" \
  "$STAGING/t263-variants.json" >/dev/null

GT_SHA="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['pdf']['sha256'])" "$GROUND_TRUTH")"
DEVICE_FIXTURE_SHA="$(adb_shell sha256sum "$STAGING/reference-de.pdf" | awk '{print $1}')"
HOST_FIXTURE_SHA="$(sha256sum "$FIXTURE_PDF" | awk '{print $1}')"
[[ "$HOST_FIXTURE_SHA" == "$GT_SHA" ]] ||
  fail "host fixture sha256 $HOST_FIXTURE_SHA != ground truth $GT_SHA"
[[ "$DEVICE_FIXTURE_SHA" == "$GT_SHA" ]] ||
  fail "device fixture sha256 $DEVICE_FIXTURE_SHA != ground truth $GT_SHA"
{
  log "fixture_pdf_sha256=$GT_SHA"
  log "host_fixture_sha256=$HOST_FIXTURE_SHA"
  log "device_fixture_sha256=$DEVICE_FIXTURE_SHA"
  log "device_ground_truth_sha256=$(adb_shell sha256sum "$STAGING/reference-de.ground-truth.json" | awk '{print $1}')"
  log "host_ground_truth_sha256=$(sha256sum "$GROUND_TRUTH" | awk '{print $1}')"
  log "host_variants_sha256=$(sha256sum "$RUN_DIR/t263-variants.json" | awk '{print $1}')"
  log "staging_mode=$(adb_shell stat -c '%a' "$STAGING")"
} >"$RUN_DIR/fixture-sha256.txt"

# --- 4. Privacy source check ------------------------------------------------
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

# --- 6. Run the integration test -------------------------------------------
adb_shell logcat -c >/dev/null
(
  cd "$APP" || exit 1
  exec "${FLUTTER_ENV[@]}" "$FLUTTER" test --no-pub "$TEST_FILE" -d "$SERIAL"
) >"$LOG" 2>&1 &
TEST_PID=$!

marker_present() {
  grep -F "T263_$1" "$LOG" >/dev/null 2>&1 && return 0
  "$ADB" -s "$SERIAL" logcat -d 2>/dev/null | grep -F "T263_$1" >/dev/null
}

# Reads the value of a `T263_<key>=<value>` marker from the test log or logcat.
marker_value() {
  local key="$1" line
  line="$(grep -F "T263_$key=" "$LOG" 2>/dev/null | tail -1)"
  if [[ -z "$line" ]]; then
    line="$("$ADB" -s "$SERIAL" logcat -d 2>/dev/null | grep -F "T263_$key=" | tail -1 | tr -d '\r')"
  fi
  printf '%s' "${line##*T263_$key=}"
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
    sleep 2
  done
  return 1
}

# --- 7. Pull the run files while the test still runs ------------------------
# `flutter test -d <serial>` uninstalls the app when it exits, which deletes its
# cache directory, so the pull has to happen as soon as the run files exist.
# The integration test's markers reach this log through Flutter's buffered
# stdout, so they can arrive only after the runner has already uninstalled the
# app (which deletes its cache directory). The run files are therefore polled and
# pulled straight from the app while it is still installed; the marker is used
# only to report the device path when it is available.
PULL_OK=0
DEVICE_OUTPUT_DIR="$(marker_value OUTPUT_PATH)"
if [[ -z "$DEVICE_OUTPUT_DIR" ]]; then
  DEVICE_OUTPUT_DIR="/data/user/0/de.feldexa.app/code_cache/t263-output"
fi
record "device output directory $DEVICE_OUTPUT_DIR"
mkdir -p "$RUN_DIR/pulled"
for attempt in $(seq 1 900); do
  for run_file in t263-run-emulator.json t263-run-injected.json; do
    "$ADB" -s "$SERIAL" exec-out run-as "$APP_ID" cat "$DEVICE_OUTPUT_DIR/$run_file" \
      >"$RUN_DIR/pulled/$run_file" 2>"$RUN_DIR/pulled/pull-$run_file.err" || true
  done
  if python3 - "$RUN_DIR/pulled" <<'PYCHECK'
import json, pathlib, sys
base = pathlib.Path(sys.argv[1])
for name in ("t263-run-emulator.json", "t263-run-injected.json"):
    path = base / name
    if not path.is_file() or path.stat().st_size == 0:
        raise SystemExit(1)
    json.loads(path.read_text(encoding="utf-8"))
PYCHECK
  then
    PULL_OK=1
    break
  fi
  if ! kill -0 "$TEST_PID" 2>/dev/null; then
    break
  fi
  sleep 1
done
[[ "$PULL_OK" -eq 1 ]] ||
  fail "cannot pull both run files from $DEVICE_OUTPUT_DIR (see pulled/pull-*.err)"
for run_file in t263-run-emulator.json t263-run-injected.json; do
  sha256sum "$RUN_DIR/pulled/$run_file" >>"$RUN_DIR/pulled/run-sha256.txt"
done
for marker in FIXTURE_VERIFIED VARIANTS_DONE RUN_FILES_WRITTEN; do
  log "T263 DRIVER: waiting for marker $marker"
  if ! wait_for_marker "$marker"; then
    log "T263 DRIVER: marker $marker not observed; test log follows"
    tail -160 "$LOG"
    fail "missing marker T263_$marker"
  fi
  record "marker $marker observed"
done

record "run files pulled ($(grep -c '' "$RUN_DIR/pulled/run-sha256.txt") files)"

for marker in LABEL_TAKEOVER_STORE_VERIFIED CLEANUP_DONE; do
  log "T263 DRIVER: waiting for marker $marker"
  if ! wait_for_marker "$marker"; then
    log "T263 DRIVER: marker $marker not observed; test log follows"
    tail -160 "$LOG"
    fail "missing marker T263_$marker"
  fi
  record "marker $marker observed"
done

TEST_DEADLINE=$((SECONDS + 900))
while kill -0 "$TEST_PID" 2>/dev/null; do
  if ((SECONDS >= TEST_DEADLINE)); then
    kill "$TEST_PID" 2>/dev/null
    wait "$TEST_PID" 2>/dev/null
    fail "integration test did not exit within 900s after the last marker"
  fi
  sleep 2
done
wait "$TEST_PID"
TEST_EXIT=$?

# --- 8. Score the pulled run files -----------------------------------------
(
  cd "$ROOT" || exit 1
  "$DART" run tools/metrics/de_ocr_qualification.dart \
    --run "$RUN_DIR/pulled/t263-run-emulator.json" \
    --run "$RUN_DIR/pulled/t263-run-injected.json" \
    --output "$RUN_DIR/t263-report.json" \
    --markdown "$RUN_DIR/t263-report.md" \
    --require-device-evidence
) >"$RUN_DIR/metrics-emulator.log" 2>&1
METRICS_EXIT=$?
record "metrics exit $METRICS_EXIT (0 = PASS, 1 = gate failure or unresolved)"

(
  cd "$ROOT" || exit 1
  python3 tools/metrics/build_text_layer_run.py \
    --pdf "$FIXTURE_PDF" \
    --ground-truth "$GROUND_TRUTH" \
    --output "$RUN_DIR/t263-text-layer-run.json" &&
    "$DART" run tools/metrics/de_ocr_qualification.dart \
      --run "$RUN_DIR/t263-text-layer-run.json" \
      --output "$RUN_DIR/t263-text-layer-report.json"
) >"$RUN_DIR/metrics-text-layer.log" 2>&1
TEXT_LAYER_EXIT=$?
record "text-layer control exit $TEXT_LAYER_EXIT"

# --- 8. Evidence collection ------------------------------------------------
{
  for apk in "$APP"/build/app/outputs/flutter-apk/*.apk; do
    [[ -f "$apk" ]] || continue
    log "path=$(host_relative "$apk")"
    log "sha256=$(sha256sum "$apk" | awk '{print $1}')"
    log "bytes=$(stat -c %s "$apk")"
  done
} >"$RUN_DIR/apk-sha256.txt"

{
  log "head=$(git -C "$ROOT" rev-parse HEAD)"
  log "tree=$(git -C "$ROOT" rev-parse HEAD^{tree})"
  log "branch=$(git -C "$ROOT" branch --show-current)"
  log "status_porcelain:"
  git -C "$ROOT" status --porcelain
  log "flutter=$("${FLUTTER_ENV[@]}" "$FLUTTER" --version 2>/dev/null | head -1)"
  log "dart=$("$DART" --version 2>&1 | head -1)"
  log "pdftoppm=$(pdftoppm -v 2>&1 | head -1)"
  log "magick=$(magick -version 2>/dev/null | head -1)"
} >"$RUN_DIR/git-identity.txt"

{
  printf '%s\n' \
    'dart run tools/corpus/synthetic/generate.dart --check' \
    'bash tools/corpus/de-ocr/verify.sh' \
    "python3 tools/corpus/de-ocr/make_variants.py --pdf apps/feldexa_app/assets/fixtures/sf-005.pdf --output <run>/variants" \
    "flutter test --no-pub integration_test/android_de_ocr_test.dart -d $SERIAL" \
    'dart run tools/metrics/de_ocr_qualification.dart --run <emulator> --run <injected> --output <report> --require-device-evidence' \
    'python3 tools/metrics/build_text_layer_run.py --pdf apps/feldexa_app/assets/fixtures/sf-005.pdf --ground-truth tools/corpus/de-ocr/reference-de.ground-truth.json --output <run>' \
    'dart run tools/metrics/de_ocr_qualification.dart --run <text-layer> --output <report>'
} >"$RUN_DIR/commands.txt"

"$ADB" -s "$SERIAL" logcat -d -v threadtime >"$RUN_DIR/logcat-full.txt" 2>/dev/null
grep -E "T263_" "$RUN_DIR/logcat-full.txt" >"$RUN_DIR/logcat-t263-markers.log" 2>/dev/null
rm -f "$RUN_DIR/logcat-full.txt"

# Recognized document text must never reach the integration log.
if grep -nE 'Musteramt|Musterstadt|Zeichensatz|Geschäftszeichen|Straße|Mühlbach|MÜLLER' \
  "$LOG" "$RUN_DIR/logcat-t263-markers.log" >"$RUN_DIR/privacy-log-check.txt" 2>&1; then
  printf 'FAIL: recognized document text or a fixture label appeared in the integration log\n' \
    >>"$RUN_DIR/privacy-log-check.txt"
  PRIVACY_PASS=0
else
  printf 'PASS: no recognized document text or fixture label in the integration log\n' \
    >>"$RUN_DIR/privacy-log-check.txt"
fi

collect_evidence

OVERALL_EXIT="$TEST_EXIT"
if [[ "$TEST_EXIT" -eq 0 ]] && [[ "$PRIVACY_PASS" -eq 1 ]]; then
  record "PASS (flutter test exit 0; privacy checks PASS; metrics exit $METRICS_EXIT; text-layer exit $TEXT_LAYER_EXIT)"
  log "T263 DRIVER: PASS (metrics verdict is reported separately in t263-report.md)"
else
  OVERALL_EXIT=1
  record "FAIL (flutter test exit $TEST_EXIT; privacy $([[ "$PRIVACY_PASS" -eq 1 ]] && echo PASS || echo FAIL))"
  log "T263 DRIVER: FAIL"
  tail -160 "$LOG"
fi

exit "$OVERALL_EXIT"
