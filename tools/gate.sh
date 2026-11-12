#!/usr/bin/env bash
#
# Feldexa 2.0 local gate (T004).
#
# Purpose: run the mandatory analysis, formatting, unit/widget, and browser
# checks locally without a hosted CI service. Every check is fail-closed:
# a real analyzer finding, formatter drift, or test failure exits non-zero.
# Missing required tooling is reported as UNAVAILABLE and makes the gate
# INCOMPLETE (exit 3) unless --allow-unavailable is explicitly given.
#
# Evidence separation (constitution Principle VIII):
#   - static analysis, formatting, and host-VM tests produce NO runtime
#     evidence class;
#   - browser tests are SIMULATED and are labelled as such;
#   - this gate never runs EMULATOR or DEVICE checks and never claims
#     Android acceptance. The final summary says so explicitly.
#
# Usage:
#   tools/gate.sh [--offline] [--allow-unavailable] [--log-dir DIR]
#
# Environment:
#   FELDEXA_FLUTTER   Path to the Flutter executable (otherwise PATH, then
#                     FLUTTER_ROOT/bin/flutter, then $HOME/flutter/bin/flutter).
#   CHROME_EXECUTABLE Path to a Chrome/Chromium executable for browser tests
#                     (otherwise google-chrome, google-chrome-stable,
#                     chromium, or chromium-browser on PATH).
#   PUB_CACHE         Standard Pub cache override, honoured by Flutter.
#
# Exit codes:
#   0  all checks passed (with --allow-unavailable: unavailable checks are
#      reported but do not block)
#   1  at least one executed check failed
#   2  gate configuration or usage error
#   3  required tooling is unavailable and --allow-unavailable was not given
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
  --log-dir DIR         Keep per-check logs in DIR (relative to the repository
                        root) instead of a temporary directory that is removed.
  -h, --help            Show this help.

Checks:
  1. dependency resolution (flutter pub get; lockfile must stay unchanged)
  2. formatting (dart format --set-exit-if-changed, page width from
     .analysis_options.yaml)
  3. static analysis (flutter analyze)
  4. host unit/widget tests (flutter test)
  5. SIMULATED browser tests (flutter test --platform chrome)

Evidence classes:
  SIMULATED  browser tests only
  EMULATOR   never run by this gate
  DEVICE     never run by this gate
EOF
}

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd) || exit 2
cd "$ROOT_DIR" || exit 2

ALLOW_UNAVAILABLE=0
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
if [ "$CLEANUP_RUN_DIR" -eq 1 ]; then
  trap 'rm -rf "$RUN_DIR"' EXIT
fi

PASS_COUNT=0
FAIL_COUNT=0
UNAVAILABLE_COUNT=0

info() {
  printf '%s\n' "$*"
}

unavailable() {
  info "[UNAVAILABLE] $*"
  UNAVAILABLE_COUNT=$((UNAVAILABLE_COUNT + 1))
}

# run_check <label> <evidence-class> <log-name> <function>
# The function must exit non-zero to fail. Output is captured to a log.
run_check() {
  local label=$1
  local evidence=$2
  local log_name=$3
  local check_fn=$4
  local log="$RUN_DIR/$log_name.log"

  info "[ RUN ] $label"
  if "$check_fn" >"$log" 2>&1; then
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
  info "Chrome:     not found (SIMULATED browser tests will be UNAVAILABLE)"
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

check_unit_tests() {
  (
    cd apps/feldexa_app || exit 1
    "$FLUTTER_BIN" "${FLUTTER_FLAGS[@]}" test --no-pub
  )
}

check_browser_tests() {
  if [ -z "$CHROME_BIN" ]; then
    return 125
  fi
  (
    cd apps/feldexa_app || exit 1
    CHROME_EXECUTABLE="$CHROME_BIN" \
      "$FLUTTER_BIN" "${FLUTTER_FLAGS[@]}" test --no-pub --platform chrome
  )
}

if ! find apps/feldexa_app/test -type f -name '*_test.dart' 2>/dev/null |
  grep -q .; then
  info "[ FAIL] no Dart test files under apps/feldexa_app/test"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

run_check "dependency resolution (pub.dev or cache)" "none" \
  "01-pub-get" resolve_dependencies
run_check "formatting (dart format, page width 80)" "none" \
  "02-format" check_format
run_check "static analysis (flutter analyze)" "none" \
  "03-analyze" check_analyze
run_check "host unit/widget tests (flutter test)" "none (host VM)" \
  "04-unit" check_unit_tests

# Browser tests need Chrome. Evaluate availability explicitly so a missing
# browser is reported as UNAVAILABLE rather than as a misleading test failure.
if [ -n "$CHROME_BIN" ]; then
  run_check "SIMULATED browser tests (flutter test --platform chrome)" \
    "SIMULATED" "05-browser" check_browser_tests
else
  unavailable "SIMULATED browser tests (Chrome/Chromium not found; set CHROME_EXECUTABLE)"
fi

info ""
info "Evidence classes:"
info "  SIMULATED: browser tests (if executed above)"
info "  EMULATOR : NOT RUN by this gate"
info "  DEVICE   : NOT RUN by this gate"
info ""
info "Checks passed: $PASS_COUNT; failed: $FAIL_COUNT; unavailable: $UNAVAILABLE_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
  info "GATE FAILED"
  exit 1
fi
if [ "$UNAVAILABLE_COUNT" -gt 0 ]; then
  if [ "$ALLOW_UNAVAILABLE" -eq 1 ]; then
    info "GATE PASSED WITH UNAVAILABLE CHECKS (not a complete gate)"
    exit 0
  fi
  info "GATE INCOMPLETE (unavailable checks; see above)"
  exit 3
fi
info "GATE PASSED"
exit 0
