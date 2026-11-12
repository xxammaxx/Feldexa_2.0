#!/usr/bin/env bash
#
# T009 SIMULATED browser runtime check for the dev-only Web fixtures.
#
# Serves `apps/feldexa_app/build/web` over loopback with CORS, then runs
# `apps/feldexa_app/test/web_fixtures_browser_test.dart` in Chrome via
# `flutter test --platform chrome`. The test fetches `/fixtures/...` exactly as
# the Flutter Web dev server serves it.
#
# Prerequisites:
#   flutter build web --no-pub        (or  PASS  FIXTURE_ROOT=apps/feldexa_app/web)
#   CHROME_EXECUTABLE                 (auto-detected from PATH and Playwright)
#   curl, dart, flutter
#
# Usage:
#   tools/corpus/synthetic/test_web_fixtures.sh
#   FIXTURE_ROOT=apps/feldexa_app/web tools/corpus/synthetic/test_web_fixtures.sh
#
# Exit codes: 0 pass, 1 test failure, 2 missing build/tool, 3 Chrome/server
# unavailable. Skipping this script is not browser evidence.
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
PORT=${FIXTURE_PORT:-8765}
SITE_ROOT=${FIXTURE_ROOT:-"$ROOT_DIR/apps/feldexa_app/build/web"}
SERVER_LOG="$ROOT_DIR/.dart_tool/t009-fixture-server.log"

fail() {
  printf 'error: %s\n' "$1" >&2
  exit "${2:-2}"
}

[ -f "$SITE_ROOT/fixtures/catalog.json" ] || fail \
  "no Web fixtures under $SITE_ROOT; run 'flutter build web --no-pub' or set FIXTURE_ROOT=apps/feldexa_app/web"

FLUTTER_BIN=${FELDEXA_FLUTTER:-}
if [ -z "$FLUTTER_BIN" ]; then
  FLUTTER_BIN=$(command -v flutter || true)
fi
if [ -z "$FLUTTER_BIN" ] && [ -x "$ROOT_DIR/.dart_tool/toolchain-flutter/bin/flutter" ]; then
  FLUTTER_BIN="$ROOT_DIR/.dart_tool/toolchain-flutter/bin/flutter"
fi
[ -n "$FLUTTER_BIN" ] || fail "flutter not found; set FELDEXA_FLUTTER"

DART_BIN=${DART:-}
if [ -z "$DART_BIN" ]; then
  DART_BIN=$(command -v dart || true)
fi
if [ -z "$DART_BIN" ] && [ -x "$(dirname -- "$FLUTTER_BIN")/dart" ]; then
  DART_BIN="$(dirname -- "$FLUTTER_BIN")/dart"
fi
[ -n "$DART_BIN" ] || fail "dart not found; set DART"

if [ -z "${CHROME_EXECUTABLE:-}" ]; then
  for candidate in google-chrome google-chrome-stable chromium chromium-browser chrome; do
    if command -v "$candidate" >/dev/null 2>&1; then
      CHROME_EXECUTABLE=$(command -v "$candidate")
      break
    fi
  done
fi
if [ -z "${CHROME_EXECUTABLE:-}" ]; then
  for candidate in "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux64/chrome; do
    if [ -x "$candidate" ]; then
      CHROME_EXECUTABLE="$candidate"
      break
    fi
  done
fi
[ -n "${CHROME_EXECUTABLE:-}" ] || fail \
  "Chrome not found; set CHROME_EXECUTABLE (for example the Playwright Chromium binary)" 3

command -v curl >/dev/null 2>&1 || fail "curl is required to wait for the fixture server" 3

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.dart_tool"
"$DART_BIN" run tools/corpus/synthetic/serve_web_fixtures.dart \
  --root "$SITE_ROOT" --port "$PORT" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
cleanup() {
  kill "$SERVER_PID" >/dev/null 2>&1 || true
  wait "$SERVER_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

ready=0
for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:$PORT/fixtures/catalog.json" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.25
done
if [ "$ready" -ne 1 ]; then
  cat "$SERVER_LOG" >&2 || true
  fail "fixture server did not become ready on 127.0.0.1:$PORT" 3
fi

printf 'SIMULATED browser fixture check: Chrome=%s site=%s\n' \
  "$CHROME_EXECUTABLE" "$SITE_ROOT"
cd "$ROOT_DIR/apps/feldexa_app"
CHROME_EXECUTABLE="$CHROME_EXECUTABLE" "$FLUTTER_BIN" test \
  --platform chrome --no-pub \
  --dart-define=FIXTURE_RUNTIME=true \
  --dart-define=FIXTURE_BASE_URL="http://127.0.0.1:$PORT" \
  test/web_fixtures_browser_test.dart
