#!/usr/bin/env bash
#
# T086B-P RED check for the rule-dense box-detector regression test.
#
# Purpose: prove, on demand and without leaving the worktree modified, that
# `packages/feldexa_recognition/test/geometry_detector_performance_test.dart`
# fails against the pre-T086B detector and passes against the current one. The
# test file's wall-clock budget is what turns the pathological enumeration into
# a deterministic failure; this script only swaps the detector source for the
# duration of one test run.
#
# Usage (repository root, host VM, heavy command under the shared compute slot):
#   bash tools/evaluation/t086bp_red_check.sh
#
# Output: one `T086BP_RED_*` marker per step and the measured dense-page time.
# Exit codes:
#   0  the test failed on the base-revision detector and the worktree detector
#      was restored byte-for-byte
#   1  the test unexpectedly passed, the restore failed, or a prerequisite is
#      missing
#   2  usage error (not run from the repository root)
#
# The script touches exactly one file, always restores it through an EXIT trap,
# and verifies the restored SHA-256. It produces host-VM provenance only: no
# SIMULATED, EMULATOR, or DEVICE evidence and no performance claim.
set -u

DETECTOR="packages/feldexa_recognition/lib/src/geometry_detector.dart"
PACKAGE="packages/feldexa_recognition"
TEST="test/geometry_detector_performance_test.dart"
BASE_COMMIT="2ab14cc93f2452a0153e6ca28293573df8376f48"
BACKUP="$(mktemp -t t086bp-detector-XXXXXX.dart)"

if [ ! -f "$DETECTOR" ] || [ ! -d "$PACKAGE" ]; then
  echo "T086BP_RED_USAGE_ERROR: run from the repository root" >&2
  exit 2
fi

original_sha="$(sha256sum "$DETECTOR" | cut -d' ' -f1)"
cp "$DETECTOR" "$BACKUP"

restore() {
  cp "$BACKUP" "$DETECTOR"
  rm -f "$BACKUP"
}
trap restore EXIT INT TERM

git show "$BASE_COMMIT:$DETECTOR" > "$DETECTOR" || exit 1
base_sha="$(sha256sum "$DETECTOR" | cut -d' ' -f1)"
echo "T086BP_RED_BASE_DETECTOR_SHA256=$base_sha"

( cd "$PACKAGE" && flutter test "$TEST" ) > /tmp/t086bp_red_check.log 2>&1
status=$?

restore
trap - EXIT INT TERM
restored_sha="$(sha256sum "$DETECTOR" | cut -d' ' -f1)"

grep -E 'T086B dense page' /tmp/t086bp_red_check.log || true
echo "T086BP_RED_TEST_EXIT=$status"
echo "T086BP_RED_RESTORED=$([ "$restored_sha" = "$original_sha" ] && echo yes || echo no)"

if [ "$status" -eq 0 ]; then
  echo "T086BP_RED_FAILED: the performance test passed on the base-revision detector"
  exit 1
fi
if [ "$restored_sha" != "$original_sha" ]; then
  echo "T086BP_RED_FAILED: the detector worktree file was not restored" >&2
  exit 1
fi
echo "T086BP_RED_CONFIRMED"
