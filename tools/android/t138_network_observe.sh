#!/usr/bin/env bash
# T138 host-side socket observation for the offline journey (SC-007/SC-008;
# FR-078/FR-079/FR-080; CHK020).
#
# Android 15 (API 35) denies the app UID any `/proc/net` access, so the
# integration test cannot read its own socket table. This driver samples the
# kernel tables from the shell UID on the exclusively allocated
# `emulator-5554` while the T138 integration test runs the production startup,
# import, encrypted staging, preflight, and first analysis (ML Kit OCR), filters
# every row to the app UID, and fails if any non-loopback outbound socket
# (ESTABLISHED/SYN_SENT/SYN_RECV/CLOSE_WAIT) appears at any sample.
#
# Usage:
#   tools/android/t138_network_observe.sh
#
# Environment:
#   ADB     path to adb (default: $HOME/Android/Sdk/platform-tools/adb)
#
# Exit codes: 0 = test PASS and zero outbound rows; 1 = outbound row or test
# failure; 2 = missing tooling/device.

set -uo pipefail

SERIAL=${SERIAL:-emulator-5554}
ADB=${ADB:-$HOME/Android/Sdk/platform-tools/adb}
REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
APP_ID=de.feldexa.app
FIXTURE="$REPO_ROOT/tools/corpus/synthetic/sf-001.pdf"
STAGE=/data/local/tmp/t138-fixtures
FIXTURE_SHA256=22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038
WORK=$(mktemp -d "${TMPDIR:-/tmp}/t138-network.XXXXXX")
trap 'rm -rf "${WORK:-}"' EXIT

fail() {
  printf 'T138_OBSERVE_FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -x "$ADB" ]] || {
  printf 'ERROR: adb not executable: %s\n' "$ADB" >&2
  exit 2
}
[[ -f "$FIXTURE" ]] || {
  printf 'ERROR: fixture missing: %s\n' "$FIXTURE" >&2
  exit 2
}
[[ "$(sha256sum "$FIXTURE" | cut -d' ' -f1)" == "$FIXTURE_SHA256" ]] ||
  fail "fixture SHA-256 mismatch"

"$ADB" -s "$SERIAL" get-state >/dev/null 2>&1 ||
  fail "device $SERIAL is not available"

"$ADB" -s "$SERIAL" shell "mkdir -p $STAGE" ||
  fail "could not create fixture staging directory"
"$ADB" -s "$SERIAL" push "$FIXTURE" "$STAGE/sf-001.pdf" >/dev/null ||
  fail "could not stage the fixture"

app_uid() {
  "$ADB" -s "$SERIAL" shell "cmd package list packages -U $APP_ID" 2>/dev/null |
    sed -n 's/.*uid:\([0-9][0-9]*\).*/\1/p' | head -n 1
}

# One snapshot of both TCP tables, restricted to the app UID and to outbound
# states with a non-loopback remote address. Emits nothing when clean.
sample_tables() {
  local uid=$1
  "$ADB" -s "$SERIAL" shell 'cat /proc/net/tcp /proc/net/tcp6' 2>/dev/null |
    awk -v uid="$uid" '
      NF >= 10 {
        state = $4
        row_uid = $8
        remote = $3
        if (row_uid != uid) next
        if (state != "01" && state != "02" && state != "03" && state != "08") next
        split(remote, parts, ":")
        addr = parts[1]
        if (addr == "00000000" || addr == "0100007F") next
        if (length(addr) == 32 && (addr ~ /^0+$/ || addr == "00000000000000000000000001000000")) next
        print state " " remote
      }'
}

(
  cd "$REPO_ROOT/apps/feldexa_app" || exit 1
  "$HOME/flutter/bin/flutter" test --no-pub --reporter expanded \
    -d "$SERIAL" integration_test/network_observation_test.dart \
    --plain-name 'no unexpected outbound sockets during startup, import and first analysis'
) >"$WORK/test.log" 2>&1 &
TEST_PID=$!

UID_VALUE=""
SAMPLES=0
OUTBOUND="$WORK/outbound.txt"
: >"$OUTBOUND"

while kill -0 "$TEST_PID" 2>/dev/null; do
  if [[ -z "$UID_VALUE" ]]; then
    UID_VALUE=$(app_uid)
  fi
  if [[ -n "$UID_VALUE" ]]; then
    SAMPLES=$((SAMPLES + 1))
    sample_tables "$UID_VALUE" >>"$OUTBOUND"
  fi
  sleep 0.25
done
wait "$TEST_PID"
TEST_RC=$?

# Final sample after the journey, using the last known UID.
if [[ -n "$UID_VALUE" ]]; then
  SAMPLES=$((SAMPLES + 1))
  sample_tables "$UID_VALUE" >>"$OUTBOUND"
fi

sort -u "$OUTBOUND" -o "$OUTBOUND"
OUTBOUND_COUNT=$(wc -l <"$OUTBOUND" | tr -d '[:space:]')

printf 'T138_OBSERVE:uid=%s:samples=%s:outbound=%s:test_rc=%s\n' \
  "${UID_VALUE:-unknown}" "$SAMPLES" "$OUTBOUND_COUNT" "$TEST_RC"

if [[ $TEST_RC -ne 0 ]]; then
  tail -n 40 "$WORK/test.log" | sed 's/^/  /'
  fail "the T138 integration test failed (rc=$TEST_RC)"
fi
if [[ -z "$UID_VALUE" ]]; then
  fail "could not determine the app UID; observation was not possible"
fi
if [[ "$OUTBOUND_COUNT" -ne 0 ]]; then
  sed 's/^/T138_OUTBOUND: /' "$OUTBOUND" >&2
  fail "$OUTBOUND_COUNT non-loopback outbound row(s) observed for uid $UID_VALUE"
fi

grep -q 'NETWORK_AUDIT_COMPLETE' "$WORK/test.log" ||
  fail "the test did not reach NETWORK_AUDIT_COMPLETE"
printf 'T138_OBSERVE_PASS: zero non-loopback outbound sockets across %s samples for uid %s\n' \
  "$SAMPLES" "$UID_VALUE"
