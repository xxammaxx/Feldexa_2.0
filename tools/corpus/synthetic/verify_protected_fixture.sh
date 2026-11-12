#!/usr/bin/env bash
#
# Independent password-gate check for the T009 protected fixture.
#
# Proves with Poppler (not the generator) that:
#   - the file is genuinely encrypted;
#   - no password and a wrong user password are rejected;
#   - the documented user password opens it;
#   - the documented owner password opens it.
#
# Usage:
#   tools/corpus/synthetic/verify_protected_fixture.sh [path]
#
# Exit codes: 0 pass, 1 gate failure, 3 required tooling unavailable.
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
FIXTURE=${1:-"$ROOT_DIR/apps/feldexa_app/assets/fixtures/sf-protected.pdf"}
USER_PASSWORD=feldexa-user
OWNER_PASSWORD=feldexa-owner

for tool in pdfinfo pdftotext; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'error: %s is required for the independent protected-fixture check\n' "$tool" >&2
    exit 3
  }
done
[ -f "$FIXTURE" ] || {
  printf 'error: %s not found\n' "$FIXTURE" >&2
  exit 1
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# 1. Encrypted with a non-empty user password: pdfinfo must refuse without one.
if pdfinfo "$FIXTURE" >/tmp/t009-pdfinfo-empty.out 2>&1; then
  fail "pdfinfo opened the protected fixture without a password"
fi
grep -qi 'Incorrect password' /tmp/t009-pdfinfo-empty.out ||
  fail "pdfinfo failed for a reason other than the password"

# 2. Empty user password must not extract content.
if pdftotext "$FIXTURE" - >/tmp/t009-pdftotext-empty.out 2>/tmp/t009-pdftotext-empty.err; then
  fail "pdftotext extracted text with an empty user password"
fi
if grep -q 'Geschütztes synthetisches Dokument' /tmp/t009-pdftotext-empty.out; then
  fail "empty-password extraction leaked fixture text"
fi

# 3. Wrong user password must not extract content.
if pdftotext -upw definitely-wrong "$FIXTURE" - \
  >/tmp/t009-pdftotext-wrong.out 2>/tmp/t009-pdftotext-wrong.err; then
  fail "pdftotext accepted a wrong user password"
fi
grep -qi 'Incorrect password' /tmp/t009-pdftotext-wrong.err ||
  fail "wrong password failed for a reason other than the password"

# 4. Correct user password must extract content.
pdftotext -upw "$USER_PASSWORD" "$FIXTURE" - \
  >/tmp/t009-pdftotext-user.out 2>/tmp/t009-pdftotext-user.err ||
  fail "pdftotext rejected the documented user password"
grep -q 'Geschütztes synthetisches Dokument' /tmp/t009-pdftotext-user.out ||
  fail "correct user password did not extract the expected text"

# 5. Owner password must also open the document.
pdftotext -opw "$OWNER_PASSWORD" "$FIXTURE" - \
  >/tmp/t009-pdftotext-owner.out 2>/tmp/t009-pdftotext-owner.err ||
  fail "pdftotext rejected the documented owner password"
grep -q 'Geschütztes synthetisches Dokument' /tmp/t009-pdftotext-owner.out ||
  fail "owner password did not extract the expected text"

# 6. Poppler must identify the encryption handler.
pdfinfo -upw "$USER_PASSWORD" "$FIXTURE" >/tmp/t009-pdfinfo-user.out 2>&1 ||
  fail "pdfinfo did not open with the documented user password"
grep -qi 'Encrypted:.*yes' /tmp/t009-pdfinfo-user.out ||
  fail "pdfinfo did not report the file as encrypted"
grep -qi 'algorithm:RC4' /tmp/t009-pdfinfo-user.out ||
  fail "pdfinfo did not report the RC4 handler"

printf 'PASS protected fixture is password-gated: empty/wrong rejected, user/owner accepted\n'
