#!/usr/bin/env bash
# Verify the committed T027 final evidence against the candidate source tree.
# The APK files are local, git-ignored build outputs; this script checks the
# committed source manifest and, when present, the exact local APK bytes.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
echo "HEAD=$(git rev-parse HEAD)"
sha256sum -c specs/001-scanned-form-workflow/reports/artifacts/t027-final-d45f4df/source-sha256.txt
if [ -d build/t027-evidence-final/apks ]; then
  (cd build/t027-evidence-final/apks && sha256sum -c \
    "$ROOT/specs/001-scanned-form-workflow/reports/artifacts/t027-final-d45f4df/apk-sha256.txt")
fi
