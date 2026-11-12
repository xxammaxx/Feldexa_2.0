#!/usr/bin/env bash
#
# Run the local verification suite for the T008 corpus manifest verifier.
#
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
    echo "verify_test.sh: python3 is required but was not found" >&2
    exit 2
fi

exec python3 "$SCRIPT_DIR/test_verify.py" "$@"
