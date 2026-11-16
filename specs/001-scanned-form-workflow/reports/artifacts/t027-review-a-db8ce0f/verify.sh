#!/usr/bin/env bash
# Verify the T027 Review-A correction evidence against the committed source
# tree. The APKs are local, git-ignored build outputs; when present, their bytes
# are checked too.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
echo "HEAD=$(git rev-parse HEAD)"
sha256sum -c specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/source-sha256.txt
if [ -d build/t027-review2/apks ]; then
  (cd build/t027-review2/apks && sha256sum -c \
    "$ROOT/specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/apk-sha256.txt")
else
  echo "APKs absent (local, git-ignored): source manifest verified only"
fi
