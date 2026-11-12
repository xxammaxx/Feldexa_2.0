#!/usr/bin/env bash
#
# Reproduce the T006 Noto Sans bundle from its pinned upstream release.
#
# The committed bytes in apps/feldexa_app/assets/fonts/ are the authoritative
# inputs for later tasks. This script exists so those bytes can be re-derived
# and audited without trusting a local copy. It downloads the exact release
# archive, verifies the archive SHA-256, extracts only the two static TTFs and
# the OFL licence, and verifies each extracted file's SHA-256 before replacing
# the bundled files.
#
# Usage:
#   bash tools/fonts/fetch_noto_sans.sh
#   NOTO_SANS_ZIP=/path/to/NotoSans-v2.013.zip bash tools/fonts/fetch_noto_sans.sh
#
# The archive is about 124 MiB. NOTO_SANS_ZIP avoids a second download when the
# pinned archive is already available locally. After either form, run:
#   python3 tools/fonts/verify_fonts.py
#
set -euo pipefail

VERSION="2.013"
REPO="notofonts/latin-greek-cyrillic"
ASSET="NotoSans-v${VERSION}.zip"
URL="https://github.com/${REPO}/releases/download/NotoSans-v${VERSION}/${ASSET}"

# Pinned by T006 evidence: the release asset downloaded on 2026-11-12.
ARCHIVE_SHA256="9fd595dd701d7ea103a9ba8a9cfdcf0c35c5574ef754fecabe718eadad8bccde"

readonly REGULAR_SHA256="97eaf07030b89da4eceace86b12f4d7debb3cb212082c3938803eac7111221c9"
readonly BOLD_SHA256="53b53721b1910c7e058c4f012126b41273d493b04d69c1ac50924f7eff8e8039"
readonly OFL_SHA256="cee9892f9f0cc8fe882c9e9537ee6a89621d86ee7ceaf70b02e2b2b1c25c061a"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
DEST="${ROOT}/apps/feldexa_app/assets/fonts"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

for tool in sha256sum unzip; do
  command -v "${tool}" >/dev/null 2>&1 || fail "required tool not found: ${tool}"
done

if [[ -z "${NOTO_SANS_ZIP:-}" ]]; then
  command -v curl >/dev/null 2>&1 || fail "curl not found; set NOTO_SANS_ZIP to a local ${ASSET}"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

archive="${tmp}/${ASSET}"
if [[ -n "${NOTO_SANS_ZIP:-}" ]]; then
  [[ -f "${NOTO_SANS_ZIP}" ]] || fail "NOTO_SANS_ZIP is not a file: ${NOTO_SANS_ZIP}"
  cp -- "${NOTO_SANS_ZIP}" "${archive}"
  printf 'Using local archive %s\n' "${NOTO_SANS_ZIP}"
else
  printf 'Downloading %s\n' "${URL}"
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --output "${archive}" "${URL}"
fi

printf '%s  %s\n' "${ARCHIVE_SHA256}" "${archive}" | sha256sum --check --status \
  || fail "archive SHA-256 mismatch for ${ASSET}"
printf 'Verified archive SHA-256 %s\n' "${ARCHIVE_SHA256}"

mkdir -p "${tmp}/out"
unzip -q -j "${archive}" \
  "NotoSans/googlefonts/ttf/NotoSans-Regular.ttf" \
  "NotoSans/googlefonts/ttf/NotoSans-Bold.ttf" \
  "OFL.txt" \
  -d "${tmp}/out"

(
  cd "${tmp}/out"
  printf '%s  %s\n' \
    "${REGULAR_SHA256}" "NotoSans-Regular.ttf" \
    "${BOLD_SHA256}" "NotoSans-Bold.ttf" \
    "${OFL_SHA256}" "OFL.txt" \
    | sha256sum --check --status
) || fail "extracted file SHA-256 mismatch"

mkdir -p "${DEST}"
for file in NotoSans-Regular.ttf NotoSans-Bold.ttf OFL.txt; do
  cp -- "${tmp}/out/${file}" "${DEST}/${file}"
  chmod 0644 "${DEST}/${file}"
  printf 'Installed %s (SHA-256 %s)\n' "${DEST}/${file}" "$(sha256sum "${DEST}/${file}" | cut -d' ' -f1)"
done

printf '\nNext: python3 tools/fonts/verify_fonts.py\n'
