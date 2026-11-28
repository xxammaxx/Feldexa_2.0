#!/usr/bin/env bash
#
# Chrome launch shim for the Flutter browser test lane (T072/T087/T101/...).
#
# Purpose: hand the Flutter test runner (`flutter test --platform chrome`) and
# `flutter drive` a Chrome that starts with the flags this host needs, without
# patching Flutter. Use it as CHROME_EXECUTABLE:
#
#   CHROME_EXECUTABLE=$PWD/tools/browser/chrome_launch.sh \
#     flutter test --platform chrome test/web_review_browser_entry_test.dart
#
# The real browser is FELDEXA_CHROME_BIN when set, otherwise the Playwright
# Chromium For Testing builds installed under ~/.cache/ms-playwright, newest
# first. Every argument passed by Flutter is forwarded unchanged.
#
# Flags: --no-sandbox (no usable SUID sandbox for this checkout/binary),
#        --disable-dev-shm-usage (small /dev/shm in containers),
#        --disable-gpu (no usable GPU in the headless lane),
#        --enable-unsafe-swiftshader (Chrome 137+ refuses the automatic software
#        WebGL fallback without it; Flutter's CanvasKit renderer then never
#        produces a frame and the test suite never starts).
#        --use-angle=swiftshader is kept for the older builds.
set -u

if [ -n "${FELDEXA_CHROME_BIN:-}" ]; then
  chrome=$FELDEXA_CHROME_BIN
else
  chrome=""
  for candidate in \
    "$HOME/.cache/ms-playwright/chromium-1248/chrome-linux64/chrome" \
    "$HOME/.cache/ms-playwright/chromium-1234/chrome-linux64/chrome" \
    "$HOME/.cache/ms-playwright/chromium_headless_shell-1248/chrome-headless-shell-linux64/chrome-headless-shell" \
    "$HOME/.cache/ms-playwright/chromium_headless_shell-1234/chrome-headless-shell-linux64/chrome-headless-shell"
  do
    if [ -x "$candidate" ]; then
      chrome=$candidate
      break
    fi
  done
fi

if [ -z "$chrome" ] || [ ! -x "$chrome" ]; then
  printf 'chrome_launch: no Chrome binary found; set FELDEXA_CHROME_BIN\n' >&2
  exit 127
fi

exec "$chrome" --no-sandbox --disable-dev-shm-usage --disable-gpu \
  --enable-unsafe-swiftshader --use-angle=swiftshader "$@"
