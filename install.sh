#!/bin/bash
#
# AerialDrop installer — alternative to Homebrew / manual download.
#
# Downloads the official release zip from GitHub, verifies its sha256
# checksum against the release metadata, installs AerialDrop.app into
# /Applications, and clears the download quarantine so Gatekeeper does
# not block the ad-hoc signed (not notarized) app.
#
# Usage:
#   ./install.sh                 install the latest release
#   ./install.sh 1.1.3           install a specific version
#   ./install.sh --open          also launch the app after installing
#   ./install.sh --force         replace an existing install without asking
#   ./install.sh --install-dir /tmp/apps   install somewhere else
#
# Security note: this is an UNSIGNED, NOT NOTARIZED app. Removing the
# quarantine disables Apple's malware check for this app; only install
# from the official repository (https://github.com/YapWH1208/AerialDrop).

set -euo pipefail

REPO="YapWH1208/AerialDrop"
API_HOST="https://api.github.com"
DL_BASE="https://github.com/${REPO}/releases/download"
DEFAULT_INSTALL_DIR="/Applications"

VERSION=""
INSTALL_DIR="${AERIALDROP_INSTALL_DIR:-${DEFAULT_INSTALL_DIR}}"
OPEN_AFTER=0
FORCE=0

usage() {
  sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# Fetch a GitHub REST API path and print the response body on stdout.
# Prefers the authenticated gh CLI (5000 req/hr) over unauthenticated
# curl (60 req/hr per IP). Fails fast on 404; retries transient errors.
api_get() {
  local path="$1"
  local body code tmp

  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if body="$(gh api "$path" 2>/dev/null)"; then
      printf '%s\n' "$body"
      return 0
    fi
  fi

  tmp="$(mktemp)"
  for attempt in 1 2 3; do
    code="$(curl -sSL -o "$tmp" -w '%{http_code}' "${API_HOST}/${path}" 2>/dev/null || echo 000)"
    case "$code" in
      200)
        cat "$tmp"
        rm -f "$tmp"
        return 0 ;;
      404)
        rm -f "$tmp"
        return 1 ;;
    esac
    sleep "$((attempt * 5))"
  done
  rm -f "$tmp"
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --open) OPEN_AFTER=1; shift ;;
    --force) FORCE=1; shift ;;
    --install-dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "error: unknown option: $1" >&2; usage; exit 1 ;;
    *)
      if [[ -n "$VERSION" ]]; then
        echo "error: unexpected argument: $1" >&2; exit 1
      fi
      VERSION="$1"; shift ;;
  esac
done

[[ -n "$INSTALL_DIR" ]] || { echo "error: --install-dir requires a path" >&2; exit 1; }

echo "==> Checking environment"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "error: AerialDrop is a macOS app; install it on macOS Tahoe 26 or later." >&2
  exit 1
fi

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [[ "${MACOS_MAJOR:-0}" -lt 26 ]]; then
  echo "error: AerialDrop requires macOS Tahoe 26 or later (this Mac runs $(sw_vers -productVersion))." >&2
  exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "error: release builds are Apple Silicon (arm64) only; this Mac is $(uname -m)." >&2
  exit 1
fi

command -v curl >/dev/null || { echo "error: curl is required" >&2; exit 1; }

echo "==> Resolving release"

if [[ -z "$VERSION" ]]; then
  echo "    Querying the latest release from ${REPO}…"
  if ! API_JSON="$(api_get "repos/${REPO}/releases/latest")"; then
    echo "error: could not fetch release info from GitHub (network, rate limit, or API outage)." >&2
    exit 1
  fi
  VERSION="$(printf '%s' "$API_JSON" | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -1)"
  [[ -n "$VERSION" ]] || { echo "error: could not resolve the latest release" >&2; exit 1; }
  echo "    Latest release: v${VERSION}"
else
  VERSION="${VERSION#v}"
  echo "    Pinned version: v${VERSION}"
fi

ASSET="AerialDrop-${VERSION}-macOS.zip"
URL="${DL_BASE}/v${VERSION}/${ASSET}"
echo "    Asset: ${ASSET}"

echo "==> Fetching expected checksum"
if ! EXPECTED_SHA="$(api_get "repos/${REPO}/releases/tags/v${VERSION}" | awk -v name="$ASSET" '
  /"name":[ ]*/ { in_asset = index($0, name) > 0 }
  in_asset && /"digest":[ ]*"sha256:/ {
    line = $0
    sub(/^.*sha256:/, "", line)
    print substr(line, 1, 64)
    exit
  }
')"; then
  echo "error: could not fetch the checksum for ${ASSET} (is v${VERSION} published?)." >&2
  exit 1
fi
if [[ "${#EXPECTED_SHA}" -ne 64 ]]; then
  echo "error: no sha256 digest found for ${ASSET} in release v${VERSION} (is it published?)." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
ZIP="${TMP_DIR}/${ASSET}"

echo "==> Downloading ${URL}"
if ! curl -fSL --retry 3 --retry-delay 3 -o "$ZIP" "$URL"; then
  echo "error: download failed — check the version (v${VERSION}) exists in the Releases page." >&2
  exit 1
fi

echo "==> Verifying checksum"
ACTUAL_SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
  echo "error: checksum mismatch — expected ${EXPECTED_SHA}, got ${ACTUAL_SHA}. Aborting." >&2
  exit 1
fi
echo "    sha256 OK (${ACTUAL_SHA})"

echo "==> Extracting"
ditto -x -k "$ZIP" "$TMP_DIR"
APP_SRC="${TMP_DIR}/AerialDrop.app"
[[ -d "$APP_SRC" ]] || { echo "error: AerialDrop.app not found in the archive" >&2; exit 1; }

APP_DST="${INSTALL_DIR}/AerialDrop.app"
if [[ -d "$APP_DST" ]]; then
  if [[ "$FORCE" -eq 0 ]]; then
    read -r -p "AerialDrop is already installed at ${APP_DST}. Replace it? [y/N] " REPLY
    [[ "$REPLY" =~ ^[yY] ]] || { echo "Install cancelled."; exit 0; }
  fi
  rm -rf "$APP_DST"
fi
mkdir -p "$INSTALL_DIR"

echo "==> Installing to ${APP_DST}"
mv "$APP_SRC" "$APP_DST"
[[ -x "${APP_DST}/Contents/MacOS/AerialDrop" ]] || { echo "error: installed app is missing its executable" >&2; exit 1; }

echo "==> Clearing download quarantine"
xattr -dr com.apple.quarantine "$APP_DST" 2>/dev/null || true

cat <<EOF

✅ AerialDrop v${VERSION} installed at ${APP_DST}

Note: AerialDrop is ad-hoc signed and NOT notarized by Apple; the download
quarantine was cleared so it opens without Gatekeeper blocking it. You are
trusting the publisher instead of Apple — only install from the official
repository (https://github.com/YapWH1208/AerialDrop).

Open it now:
    open "${APP_DST}"

(Or use Homebrew: brew install --cask yapwh1208/tap/aerialdrop)
EOF

if [[ "$OPEN_AFTER" -eq 1 ]]; then
  echo "==> Launching AerialDrop"
  open "$APP_DST"
fi
