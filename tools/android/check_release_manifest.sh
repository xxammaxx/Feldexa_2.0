#!/usr/bin/env bash
# T003: release-manifest privacy regression check.
#
# Feldexa's release manifest must not request network permissions or carry
# ML Kit's Google DataTransport telemetry components. The app's release-only
# overlay (apps/feldexa_app/android/app/src/release/AndroidManifest.xml)
# removes those contributions; this script fails the gate if they reappear.
#
# Usage:
#   tools/android/check_release_manifest.sh [MERGED_MANIFEST.xml|APP.apk]
#   tools/android/check_release_manifest.sh --self-test
#
# With no argument it checks the standard AGP release merged-manifest path.
# With an APK argument it prints the APK manifest through apkanalyzer.
# Exit codes: 0 = clean, 1 = forbidden entry found, 2 = tool/usage error.

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
DEFAULT_MANIFEST="$REPO_ROOT/apps/feldexa_app/build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml"

FORBIDDEN_PERMISSIONS=(
  "android.permission.INTERNET"
  "android.permission.ACCESS_NETWORK_STATE"
)
FORBIDDEN_COMPONENT_MARKER="com.google.android.datatransport"

check_manifest() {
  local manifest="$1"
  local failed=0
  local permission

  if [[ ! -f "$manifest" ]]; then
    echo "ERROR: manifest not found: $manifest" >&2
    return 2
  fi

  for permission in "${FORBIDDEN_PERMISSIONS[@]}"; do
    if grep -q "$permission" "$manifest"; then
      echo "FAIL: release manifest contains forbidden permission: $permission" >&2
      failed=1
    fi
  done

  if grep -q "$FORBIDDEN_COMPONENT_MARKER" "$manifest"; then
    echo "FAIL: release manifest contains forbidden DataTransport component" >&2
    failed=1
  fi

  if [[ "$failed" -ne 0 ]]; then
    echo "Release-manifest privacy check FAILED for: $manifest" >&2
    return 1
  fi

  echo "PASS: release manifest has no INTERNET/ACCESS_NETWORK_STATE and no DataTransport component: $manifest"
  return 0
}

resolve_apk_manifest() {
  local apk="$1"
  local apkanalyzer=""

  if [[ -n "${ANDROID_HOME:-}" && -x "${ANDROID_HOME}/cmdline-tools/latest/bin/apkanalyzer" ]]; then
    apkanalyzer="${ANDROID_HOME}/cmdline-tools/latest/bin/apkanalyzer"
  elif [[ -n "${ANDROID_SDK_ROOT:-}" && -x "${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/apkanalyzer" ]]; then
    apkanalyzer="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/apkanalyzer"
  elif [[ -x "${HOME:-}/Android/Sdk/cmdline-tools/latest/bin/apkanalyzer" ]]; then
    apkanalyzer="${HOME}/Android/Sdk/cmdline-tools/latest/bin/apkanalyzer"
  elif command -v apkanalyzer >/dev/null 2>&1; then
    apkanalyzer=$(command -v apkanalyzer)
  else
    echo "ERROR: apkanalyzer not found; set ANDROID_HOME or pass a merged manifest" >&2
    return 2
  fi

  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/feldexa-manifest.XXXXXX.xml")
  if ! "$apkanalyzer" manifest print "$apk" > "$tmp"; then
    rm -f "$tmp"
    echo "ERROR: apkanalyzer could not read $apk" >&2
    return 2
  fi
  local status=0
  check_manifest "$tmp" || status=$?
  rm -f "$tmp"
  return "$status"
}

self_test() {
  local tmp
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/feldexa-manifest-selftest.XXXXXX")
  trap 'rm -rf "${tmp:-}"' EXIT

  cat > "$tmp/clean.xml" <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="de.feldexa.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION" />
</manifest>
XML

  cat > "$tmp/bad-internet.xml" <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
</manifest>
XML

  cat > "$tmp/bad-network-state.xml" <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
</manifest>
XML

  cat > "$tmp/bad-datatransport.xml" <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application>
        <service android:name="com.google.android.datatransport.runtime.backends.TransportBackendDiscovery" />
    </application>
</manifest>
XML

  check_manifest "$tmp/clean.xml" >/dev/null
  if check_manifest "$tmp/bad-internet.xml" >/dev/null 2>&1; then
    echo "SELF-TEST FAILED: INTERNET manifest was accepted" >&2
    return 1
  fi
  if check_manifest "$tmp/bad-network-state.xml" >/dev/null 2>&1; then
    echo "SELF-TEST FAILED: ACCESS_NETWORK_STATE manifest was accepted" >&2
    return 1
  fi
  if check_manifest "$tmp/bad-datatransport.xml" >/dev/null 2>&1; then
    echo "SELF-TEST FAILED: DataTransport manifest was accepted" >&2
    return 1
  fi
  rm -rf "$tmp"
  trap - EXIT
  echo "SELF-TEST PASS: clean manifest accepted; INTERNET, ACCESS_NETWORK_STATE and DataTransport manifests rejected."
  return 0
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit $?
fi

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [MERGED_MANIFEST.xml|APP.apk|--self-test]" >&2
  exit 2
fi

target="${1:-$DEFAULT_MANIFEST}"
if [[ "$target" == *.apk ]]; then
  resolve_apk_manifest "$target"
else
  check_manifest "$target"
fi
