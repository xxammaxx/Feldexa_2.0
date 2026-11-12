#!/usr/bin/env bash
#
# Feldexa 2.0 local gate (T004).
#
# Purpose: run the mandatory analysis, formatting, shared-package, app
# unit/widget, browser interaction, and browser integration checks locally
# without a hosted CI service. Every executed check is fail-closed: a real
# analyzer finding, formatter drift, or test failure exits non-zero.
#
# Planned layers that do not exist yet are reported as ABSENT and make the
# gate INCOMPLETE (exit 3) unless --allow-absent is explicitly given. Missing
# tooling is reported as UNAVAILABLE and makes the gate INCOMPLETE (exit 3)
# unless --allow-unavailable is explicitly given. Neither escape hatch is
# valid for the final acceptance gate T145.
#
# Browser integration tests need the Flutter web driver: chromedriver must be
# on PATH (or CHROMEDRIVER set) and apps/feldexa_app/test_driver/integration_test.dart
# must exist. A missing driver artifact is ABSENT; a missing chromedriver is
# UNAVAILABLE. Neither is silently skipped or reported as a pass.
#
# Evidence separation (constitution Principle VIII):
#   - static analysis, formatting, and host-VM tests produce NO runtime
#     evidence class;
#   - browser tests (app test/ and integration_test/web_*) are SIMULATED and
#     are labelled as such;
#   - Android/emulator/device integration tests are never run by this gate
#     and never claimed as acceptance evidence.
#
# Usage:
#   tools/gate.sh [--offline] [--allow-unavailable] [--allow-absent]
#                 [--log-dir DIR]
#
# Environment:
#   FELDEXA_FLUTTER   Path to the Flutter executable (otherwise PATH, then
#                     FLUTTER_ROOT/bin/flutter, then $HOME/flutter/bin/flutter).
#   CHROME_EXECUTABLE Path to a Chrome/Chromium executable for app browser
#                     tests (otherwise google-chrome, google-chrome-stable,
#                     chromium, or chromium-browser on PATH).
#   CHROMEDRIVER      Path to chromedriver for web integration tests (otherwise
#                     chromedriver on PATH).
#   PUB_CACHE         Standard Pub cache override, honoured by Flutter.
#
# Exit codes:
#   0  all present checks passed and no planned layer is absent or unavailable
#      (with --allow-* escape hatches: qualified pass that is not a complete
#      gate)
#   1  at least one executed check failed
#   2  gate configuration or usage error
#   3  required tooling is unavailable or a planned test layer is absent and
#      the corresponding escape hatch was not given
#
set -u

usage() {
  cat <<'EOF'
Feldexa local gate

Usage: tools/gate.sh [options]

Options:
  --offline             Run `flutter pub get --offline` instead of allowing
                        the normal package resolution path.
  --allow-unavailable   Do not fail when required tooling (for example
                        Chrome) is missing. The summary still reports the
                        missing checks as UNAVAILABLE. Not valid for the
                        final acceptance gate T145.
  --allow-absent        Do not fail when a planned test layer has no test
                        files yet. The summary still reports the layer as
                        ABSENT and prints a qualified, non-complete pass.
                        Not valid for the final acceptance gate T145.
  --log-dir DIR         Keep per-check logs in DIR (relative to the repository
                        root) instead of a temporary directory that is removed.
  -h, --help            Show this help.

Checks:
  1. dependency resolution (flutter pub get; lockfile must stay unchanged)
  2. formatting (dart format --set-exit-if-changed, page width from
     .analysis_options.yaml)
  3. static analysis (flutter analyze)
  4. shared-package Dart tests (flutter test in every packages/*/test with
     *_test.dart present)
  5. app unit/widget tests (flutter test in apps/feldexa_app)
  6. SIMULATED app browser/interaction tests (flutter test --platform chrome
     in apps/feldexa_app)
  7. SIMULATED browser integration tests (integration_test/web_*_test.dart)
     via flutter drive with chromedriver and test_driver/integration_test.dart;
     non-browser integration tests are reported as NOT RUN because they belong
     to the EMULATOR/DEVICE layer

Evidence classes:
  SIMULATED  app browser/interaction and web integration tests only
  EMULATOR   never run by this gate
  DEVICE     never run by this gate
EOF
}

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd) || exit 2
cd "$ROOT_DIR" || exit 2

ALLOW_UNAVAILABLE=0
ALLOW_ABSENT=0
OFFLINE=0
LOG_DIR=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --offline)
      OFFLINE=1
      ;;
    --allow-unavailable)
      ALLOW_UNAVAILABLE=1
      ;;
    --allow-absent)
      ALLOW_ABSENT=1
      ;;
    --log-dir)
      shift
      if [ "$#" -eq 0 ] || [ -z "$1" ]; then
        printf 'gate: --log-dir requires a value\n' >&2
        exit 2
      fi
      LOG_DIR=$1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'gate: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ ! -f "$ROOT_DIR/.analysis_options.yaml" ]; then
  printf '[FAIL] analysis configuration: %s is missing\n' \
    "$ROOT_DIR/.analysis_options.yaml" >&2
  exit 2
fi
if [ ! -f "$ROOT_DIR/analysis_options.yaml" ]; then
  printf '[FAIL] analysis configuration: %s is missing\n' \
    "$ROOT_DIR/analysis_options.yaml" >&2
  exit 2
fi
if ! grep -Eq '^[[:space:]]*include:[[:space:]]*\.analysis_options\.yaml[[:space:]]*$' \
  "$ROOT_DIR/analysis_options.yaml"; then
  printf '[FAIL] analysis configuration: analysis_options.yaml must include .analysis_options.yaml\n' >&2
  exit 2
fi

if [ -n "$LOG_DIR" ]; then
  mkdir -p "$LOG_DIR" || exit 2
  RUN_DIR="$LOG_DIR"
  CLEANUP_RUN_DIR=0
else
  RUN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/feldexa-gate.XXXXXX") || exit 2
  CLEANUP_RUN_DIR=1
fi

CHROMEDRIVER_PID=""
cleanup() {
  if [ -n "${CHROMEDRIVER_PID:-}" ] && kill -0 "$CHROMEDRIVER_PID" 2>/dev/null; then
    kill "$CHROMEDRIVER_PID" 2>/dev/null || true
    wait "$CHROMEDRIVER_PID" 2>/dev/null || true
  fi
  if [ "${CLEANUP_RUN_DIR:-0}" -eq 1 ]; then
    rm -rf "$RUN_DIR"
  fi
}
trap cleanup EXIT

PASS_COUNT=0
FAIL_COUNT=0
UNAVAILABLE_COUNT=0
ABSENT_COUNT=0

info() {
  printf '%s\n' "$*"
}

unavailable() {
  info "[UNAVAILABLE] $*"
  UNAVAILABLE_COUNT=$((UNAVAILABLE_COUNT + 1))
}

absent() {
  info "[ABSENT] $*"
  ABSENT_COUNT=$((ABSENT_COUNT + 1))
}

# run_check <label> <evidence-class> <log-name> <function> [function args...]
# The function must exit non-zero to fail. Output is captured to a log.
run_check() {
  local label=$1
  local evidence=$2
  local log_name=$3
  local check_fn=$4
  shift 4
  local log="$RUN_DIR/$log_name.log"

  info "[ RUN ] $label"
  if "$check_fn" "$@" >"$log" 2>&1; then
    info "[ PASS] $label (evidence: $evidence)"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    local rc=$?
    info "[ FAIL] $label (exit $rc, evidence: $evidence)"
    info "        log: $log"
    tail -n 40 "$log" | sed 's/^/        /'
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

find_test_files() {
  local dir=$1
  [ -d "$dir" ] || return 0
  find "$dir" -type f -name '*_test.dart' 2>/dev/null | LC_ALL=C sort
}

find_flutter() {
  if [ -n "${FELDEXA_FLUTTER:-}" ]; then
    if [ -x "$FELDEXA_FLUTTER" ]; then
      printf '%s\n' "$FELDEXA_FLUTTER"
      return 0
    fi
    return 1
  fi
  if command -v flutter >/dev/null 2>&1; then
    command -v flutter
    return 0
  fi
  if [ -n "${FLUTTER_ROOT:-}" ] && [ -x "$FLUTTER_ROOT/bin/flutter" ]; then
    printf '%s\n' "$FLUTTER_ROOT/bin/flutter"
    return 0
  fi
  if [ -x "$HOME/flutter/bin/flutter" ]; then
    printf '%s\n' "$HOME/flutter/bin/flutter"
    return 0
  fi
  return 1
}

find_chrome() {
  if [ -n "${CHROME_EXECUTABLE:-}" ]; then
    if [ -x "$CHROME_EXECUTABLE" ]; then
      printf '%s\n' "$CHROME_EXECUTABLE"
      return 0
    fi
    return 1
  fi
  local candidate
  for candidate in google-chrome google-chrome-stable chromium chromium-browser; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

find_chromedriver() {
  if [ -n "${CHROMEDRIVER:-}" ]; then
    if [ -x "$CHROMEDRIVER" ]; then
      printf '%s\n' "$CHROMEDRIVER"
      return 0
    fi
    return 1
  fi
  if command -v chromedriver >/dev/null 2>&1; then
    command -v chromedriver
    return 0
  fi
  return 1
}

FLUTTER_BIN=$(find_flutter) || {
  printf '[UNAVAILABLE] Flutter executable not found\n' >&2
  printf 'Set FELDEXA_FLUTTER, FLUTTER_ROOT, or put flutter on PATH.\n' >&2
  printf 'GATE INCOMPLETE (Flutter unavailable)\n' >&2
  exit 3
}

FLUTTER_DIR=$(cd -- "$(dirname -- "$FLUTTER_BIN")" && pwd -P) || exit 2
DART_BIN="$FLUTTER_DIR/dart"
if [ ! -x "$DART_BIN" ]; then
  DART_BIN=$(command -v dart 2>/dev/null || true)
fi
if [ -z "$DART_BIN" ] || [ ! -x "$DART_BIN" ]; then
  printf '[UNAVAILABLE] Dart executable not found next to Flutter or on PATH\n' >&2
  printf 'GATE INCOMPLETE (Dart unavailable)\n' >&2
  exit 3
fi

CHROME_BIN=$(find_chrome || true)
CHROMEDRIVER_BIN=$(find_chromedriver || true)
INTEGRATION_DRIVER="$ROOT_DIR/apps/feldexa_app/test_driver/integration_test.dart"

FLUTTER_FLAGS=(--no-version-check)
PUB_FLAGS=()
if [ "$OFFLINE" -eq 1 ]; then
  PUB_FLAGS+=(--offline)
fi
export FLUTTER_SUPPRESS_ANALYTICS=true

info "Feldexa local gate (T004)"
info "Repository: $ROOT_DIR"
info "Flutter:    $FLUTTER_BIN"
info "Dart:       $DART_BIN"
if [ -n "$CHROME_BIN" ]; then
  info "Chrome:     $CHROME_BIN"
else
  info "Chrome:     not found (browser tests will be UNAVAILABLE if present)"
fi
if [ -n "$CHROMEDRIVER_BIN" ]; then
  info "ChromeDriver: $CHROMEDRIVER_BIN"
else
  info "ChromeDriver: not found (web integration tests will be UNAVAILABLE if present)"
fi
info "Logs:       $RUN_DIR"
info ""
info "Evidence separation: this gate produces SIMULATED browser evidence and"
info "host-only static/unit checks. It does NOT run EMULATOR or DEVICE checks"
info "and must not be cited as Android acceptance evidence."
info ""

resolve_dependencies() {
  "$FLUTTER_BIN" "${FLUTTER_FLAGS[@]}" pub get "${PUB_FLAGS[@]}"
  if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
    if [ -f pubspec.lock ]; then
      git diff --exit-code -- pubspec.lock
    fi
  fi
}

check_format() {
  "$DART_BIN" format --output=none --set-exit-if-changed .
}

check_analyze() {
  "$FLUTTER_BIN" "${FLUTTER_FLAGS[@]}" analyze --no-pub
}

run_shared_package_tests() {
  local pkg_dir=$1
  (
    cd "$pkg_dir" || exit 1
    "$FLUTTER_BIN" "${FLUTTER_FLAGS[@]}" test --no-pub
  )
}

check_app_unit_tests() {
  (
    cd apps/feldexa_app || exit 1
    "$FLUTTER_BIN" "${FLUTTER_FLAGS[@]}" test --no-pub
  )
}

check_app_browser_tests() {
  (
    cd apps/feldexa_app || exit 1
    CHROME_EXECUTABLE="$CHROME_BIN" \
      "$FLUTTER_BIN" "${FLUTTER_FLAGS[@]}" test --no-pub --platform chrome
  )
}

BROWSER_INTEGRATION_FILES=()
NON_BROWSER_INTEGRATION_COUNT=0

collect_browser_integration_files() {
  local rel
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    local abs="$ROOT_DIR/apps/feldexa_app/$rel"
    case "$(basename "$rel")" in
      web_*_test.dart)
        BROWSER_INTEGRATION_FILES+=("$rel")
        ;;
      *)
        if grep -qE "@TestOn[[:space:]]*\([[:space:]]*'browser'[[:space:]]*\)" "$abs" 2>/dev/null; then
          BROWSER_INTEGRATION_FILES+=("$rel")
        else
          NON_BROWSER_INTEGRATION_COUNT=$((NON_BROWSER_INTEGRATION_COUNT + 1))
        fi
        ;;
    esac
  done < <(cd "$ROOT_DIR/apps/feldexa_app" && find integration_test -type f -name '*_test.dart' 2>/dev/null | LC_ALL=C sort)
}

start_chromedriver() {
  "$CHROMEDRIVER_BIN" --port=4444 >"$RUN_DIR/chromedriver.log" 2>&1 &
  CHROMEDRIVER_PID=$!
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if ! kill -0 "$CHROMEDRIVER_PID" 2>/dev/null; then
      return 1
    fi
    if (echo >/dev/tcp/127.0.0.1/4444) >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

stop_chromedriver() {
  if [ -n "${CHROMEDRIVER_PID:-}" ] && kill -0 "$CHROMEDRIVER_PID" 2>/dev/null; then
    kill "$CHROMEDRIVER_PID" 2>/dev/null || true
    wait "$CHROMEDRIVER_PID" 2>/dev/null || true
  fi
  CHROMEDRIVER_PID=""
}

run_browser_integration_file() {
  local rel=$1
  (
    cd apps/feldexa_app || exit 1
    CHROME_EXECUTABLE="$CHROME_BIN" \
      "$FLUTTER_BIN" "${FLUTTER_FLAGS[@]}" drive \
      --driver=test_driver/integration_test.dart \
      --target="$rel" \
      -d web-server \
      --browser-name=chrome \
      --chrome-binary="$CHROME_BIN" \
      --headless
  )
}

APP_TEST_FILES=$(find_test_files "$ROOT_DIR/apps/feldexa_app/test")
collect_browser_integration_files

run_check "dependency resolution (pub.dev or cache)" "none" \
  "01-pub-get" resolve_dependencies
run_check "formatting (dart format, page width 80)" "none" \
  "02-format" check_format
run_check "static analysis (flutter analyze)" "none" \
  "03-analyze" check_analyze

SHARED_PACKAGES_WITH_TESTS=0
for pkg_dir in "$ROOT_DIR"/packages/*; do
  [ -d "$pkg_dir" ] || continue
  pkg_name=$(basename "$pkg_dir")
  pkg_tests=$(find_test_files "$pkg_dir/test")
  if [ -z "$pkg_tests" ]; then
    info "[ABSENT] shared package tests: $pkg_name has no test/*_test.dart"
    continue
  fi

  SHARED_PACKAGES_WITH_TESTS=$((SHARED_PACKAGES_WITH_TESTS + 1))
  run_check "shared package tests: $pkg_name (flutter test)" "none (host VM)" \
    "05-shared-$pkg_name" run_shared_package_tests "$pkg_dir"
done
if [ "$SHARED_PACKAGES_WITH_TESTS" -eq 0 ]; then
  absent "shared-package test layer (no packages/*/test/*_test.dart)"
fi

if [ -z "$APP_TEST_FILES" ]; then
  absent "app unit/widget test layer (no apps/feldexa_app/test/*_test.dart)"
  absent "SIMULATED app browser/interaction test layer (no apps/feldexa_app/test/*_test.dart)"
else
  run_check "app unit/widget tests (flutter test)" "none (host VM)" \
    "04-app-unit" check_app_unit_tests

  if [ -n "$CHROME_BIN" ]; then
    run_check "SIMULATED app browser/interaction tests (flutter test --platform chrome)" \
      "SIMULATED" "06-app-browser" check_app_browser_tests
  else
    unavailable "SIMULATED app browser/interaction tests (Chrome/Chromium not found; set CHROME_EXECUTABLE)"
  fi
fi

if [ "${#BROWSER_INTEGRATION_FILES[@]}" -eq 0 ]; then
  if [ "$NON_BROWSER_INTEGRATION_COUNT" -gt 0 ]; then
    absent "SIMULATED browser integration test layer (no integration_test/web_*_test.dart; $NON_BROWSER_INTEGRATION_COUNT non-browser integration test(s) belong to EMULATOR/DEVICE)"
  else
    absent "SIMULATED browser integration test layer (no integration_test/web_*_test.dart)"
  fi
elif [ ! -f "$INTEGRATION_DRIVER" ]; then
  absent "SIMULATED browser integration test driver (apps/feldexa_app/test_driver/integration_test.dart missing; ${#BROWSER_INTEGRATION_FILES[@]} web integration test(s) present)"
elif [ -z "$CHROMEDRIVER_BIN" ]; then
  unavailable "SIMULATED browser integration tests (chromedriver not found; set CHROMEDRIVER; ${#BROWSER_INTEGRATION_FILES[@]} web integration test(s) present)"
elif [ -z "$CHROME_BIN" ]; then
  unavailable "SIMULATED browser integration tests (Chrome/Chromium binary not found; ${#BROWSER_INTEGRATION_FILES[@]} web integration test(s) present)"
elif start_chromedriver; then
  for rel in "${BROWSER_INTEGRATION_FILES[@]}"; do
    run_check "SIMULATED browser integration test: $rel" "SIMULATED" \
      "07-integration-$(basename "$rel")" run_browser_integration_file "$rel"
  done
  stop_chromedriver
else
  stop_chromedriver
  unavailable "SIMULATED browser integration tests (chromedriver failed to start; see $RUN_DIR/chromedriver.log)"
fi

if [ "$NON_BROWSER_INTEGRATION_COUNT" -gt 0 ]; then
  info "[NOT RUN] EMULATOR/DEVICE integration tests present: $NON_BROWSER_INTEGRATION_COUNT (not executed by this local gate)"
fi

info ""
info "Evidence classes:"
info "  SIMULATED: app browser/interaction and web integration tests"
info "  EMULATOR : NOT RUN by this gate"
info "  DEVICE   : NOT RUN by this gate"
info ""
info "Checks passed: $PASS_COUNT; failed: $FAIL_COUNT; unavailable: $UNAVAILABLE_COUNT; absent planned layers: $ABSENT_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
  info "GATE FAILED"
  exit 1
fi

INCOMPLETE=0
[ "$UNAVAILABLE_COUNT" -gt 0 ] && INCOMPLETE=1
[ "$ABSENT_COUNT" -gt 0 ] && INCOMPLETE=1
if [ "$INCOMPLETE" -eq 1 ]; then
  BLOCKED=0
  if [ "$UNAVAILABLE_COUNT" -gt 0 ] && [ "$ALLOW_UNAVAILABLE" -eq 0 ]; then
    BLOCKED=1
  fi
  if [ "$ABSENT_COUNT" -gt 0 ] && [ "$ALLOW_ABSENT" -eq 0 ]; then
    BLOCKED=1
  fi
  if [ "$BLOCKED" -eq 1 ]; then
    if [ "$UNAVAILABLE_COUNT" -gt 0 ] && [ "$ABSENT_COUNT" -gt 0 ]; then
      info "GATE INCOMPLETE (unavailable checks and absent planned layers; see above)"
    elif [ "$UNAVAILABLE_COUNT" -gt 0 ]; then
      info "GATE INCOMPLETE (unavailable checks; see above)"
    else
      info "GATE INCOMPLETE (absent planned layers; see above)"
    fi
    exit 3
  fi
  info "GATE PASSED WITH INCOMPLETE LAYERS (not a complete gate)"
  exit 0
fi
info "GATE PASSED"
exit 0
