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
# Fail-closed rules:
#   * every table read checks the adb exit status and requires the TCP header;
#     a failed read fails the run and is never counted as a sample;
#   * the result is only PASS when at least one successful read exists, the
#     app UID was known, and the positive control is visible: the integration
#     test opens an app-UID loopback listener and prints its port, and this
#     driver must see that exact LISTEN row in the same run.
#
# Sampling is one adb round-trip at a time (~1 Hz on this host); TCP flows
# shorter than one interval can be missed. The driver makes no claim about
# other UIDs.
#
# Usage:
#   tools/android/t138_network_observe.sh
#
# Environment:
#   ADB     path to adb (default: $HOME/Android/Sdk/platform-tools/adb)
#
# Exit codes: 0 = test PASS, readable tables, visible positive control, zero
# outbound rows; 1 = outbound row, unreadable table, missing positive control,
# or test failure; 2 = missing tooling/device.

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

TABLE_OUTPUT=""
# Reads both TCP tables. Returns non-zero when adb, cat, or the table shape
# fails; callers must not count that iteration as a sample.
read_tables() {
  local output
  output=$("$ADB" -s "$SERIAL" shell 'cat /proc/net/tcp /proc/net/tcp6' \
    2>"$WORK/adb.err") || return 1
  [[ -n "$output" ]] || return 1
  grep -q 'local_address' <<<"$output" || return 1
  TABLE_OUTPUT=$output
  return 0
}

# Parses the last successful read. Appends outbound rows and loopback LISTEN
# rows to the respective files; echoes the number of visible app-UID rows.
parse_tables() {
  local uid=$1
  awk -v uid="$uid" \
    -v outbound="$WORK/outbound.raw" \
    -v listeners="$WORK/listeners.raw" '
    NF >= 10 {
      state = $4
      row_uid = $8
      local_addr = $2
      remote = $3
      if (row_uid != uid) next
      visible++
      split(remote, rparts, ":")
      raddr = rparts[1]
      split(local_addr, lparts, ":")
      laddr = lparts[1]
      if (state == "0A" && (laddr == "0100007F" ||
          laddr == "00000000000000000000000001000000")) {
        print local_addr >> listeners
      }
      if (state != "01" && state != "02" && state != "03" && state != "08") next
      if (raddr == "00000000" || raddr == "0100007F") next
      if (length(raddr) == 32 && (raddr ~ /^0+$/ ||
          raddr == "00000000000000000000000001000000")) next
      print state " " remote >> outbound
    }
    END { print visible + 0 }' <<<"$TABLE_OUTPUT"
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
READ_FAILURES=0
VISIBLE_ROWS=0
: >"$WORK/outbound.raw"
: >"$WORK/listeners.raw"

while kill -0 "$TEST_PID" 2>/dev/null; do
  if [[ -z "$UID_VALUE" ]]; then
    UID_VALUE=$(app_uid)
  fi
  if [[ -n "$UID_VALUE" ]]; then
    if read_tables; then
      SAMPLES=$((SAMPLES + 1))
      VISIBLE_ROWS=$((VISIBLE_ROWS + $(parse_tables "$UID_VALUE")))
    else
      READ_FAILURES=$((READ_FAILURES + 1))
      printf 'T138_READ_FAIL:%s\n' "$(tail -n 1 "$WORK/adb.err" 2>/dev/null)"
    fi
  fi
  sleep 0.25
done
wait "$TEST_PID"
TEST_RC=$?

sort -u "$WORK/outbound.raw" -o "$WORK/outbound.raw" 2>/dev/null || true
sort -u "$WORK/listeners.raw" -o "$WORK/listeners.raw" 2>/dev/null || true
OUTBOUND_COUNT=0
[[ -s "$WORK/outbound.raw" ]] &&
  OUTBOUND_COUNT=$(wc -l <"$WORK/outbound.raw" | tr -d '[:space:]')

POSITIVE_PORT=$(grep -oE 'T138_POSITIVE_CONTROL:port=[0-9]+' "$WORK/test.log" |
  tail -n 1 | cut -d= -f2)
POSITIVE_OK=0
if [[ -n "$POSITIVE_PORT" ]]; then
  PORT_HEX=$(printf '%04X' "$POSITIVE_PORT")
  if grep -q "^0100007F:${PORT_HEX}$" "$WORK/listeners.raw"; then
    POSITIVE_OK=1
  fi
fi

printf 'T138_OBSERVE:uid=%s:samples=%s:read_failures=%s:visible_rows=%s:' \
  "${UID_VALUE:-unknown}" "$SAMPLES" "$READ_FAILURES" "$VISIBLE_ROWS"
printf 'outbound=%s:positive_control=%s:port_hex=%s:test_rc=%s\n' \
  "$OUTBOUND_COUNT" "$POSITIVE_OK" "${PORT_HEX:-none}" "$TEST_RC"

if [[ $TEST_RC -ne 0 ]]; then
  tail -n 40 "$WORK/test.log" | sed 's/^/  /'
  fail "the T138 integration test failed (rc=$TEST_RC)"
fi
if [[ -z "$UID_VALUE" ]]; then
  fail "could not determine the app UID; observation was not possible"
fi
if [[ "$SAMPLES" -eq 0 ]]; then
  fail "no successful table read; observation was not possible"
fi
if [[ "$READ_FAILURES" -ne 0 ]]; then
  fail "$READ_FAILURES table read(s) failed; the zero-outbound result is not evidence"
fi
if [[ "$VISIBLE_ROWS" -eq 0 ]]; then
  fail "no app-UID rows were visible in the tables; observation was not possible"
fi
if [[ "$POSITIVE_OK" -ne 1 ]]; then
  fail "the app-UID loopback positive control was not visible (port ${POSITIVE_PORT:-unknown})"
fi
if [[ "$OUTBOUND_COUNT" -ne 0 ]]; then
  sed 's/^/T138_OUTBOUND: /' "$WORK/outbound.raw" >&2
  fail "$OUTBOUND_COUNT non-loopback outbound row(s) observed for uid $UID_VALUE"
fi

grep -q 'NETWORK_AUDIT_COMPLETE' "$WORK/test.log" ||
  fail "the test did not reach NETWORK_AUDIT_COMPLETE"
printf 'T138_OBSERVE_PASS: zero non-loopback outbound sockets across %s reads ' \
  "$SAMPLES"
printf '(%s app-UID rows) for uid %s; positive control 0100007F:%s visible\n' \
  "$VISIBLE_ROWS" "$UID_VALUE" "$PORT_HEX"
