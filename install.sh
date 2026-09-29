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

# Read GitHub release JSON from stdin. Match the asset name exactly so another
# asset's digest cannot be mistaken for the zip's, regardless of JSON layout.
release_asset_sha() {
  local expected_asset="$1" release_json count index name digest expected_sha="" matches=0
  release_json="$(cat)"
  count="$(printf '%s' "$release_json" | /usr/bin/plutil -extract assets raw -expect array -o - - 2>/dev/null)" || return 1
  [[ "$count" =~ ^[0-9]+$ ]] || return 1

  for ((index = 0; index < count; index++)); do
    # The sentinel preserves trailing newlines in JSON names during command
    # substitution; stripping them could turn a different name into a match.
    name="$(printf '%s' "$release_json" | /usr/bin/plutil -extract "assets.${index}.name" raw -expect string -n -o - - 2>/dev/null && printf '.')" || return 1
    name="${name%.}"
    if [[ "$name" == "$expected_asset" ]]; then
      ((matches += 1))
      [[ "$matches" -eq 1 ]] || return 1
      digest="$(printf '%s' "$release_json" | /usr/bin/plutil -extract "assets.${index}.digest" raw -expect string -n -o - - 2>/dev/null && printf '.')" || return 1
      digest="${digest%.}"
      [[ "$digest" =~ ^sha256:([[:xdigit:]]{64})$ ]] || return 1
      expected_sha="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
    fi
  done

  [[ "$matches" -eq 1 ]] || return 1
  printf '%s\n' "$expected_sha"
}

# The smoke test sources this file to exercise the production parser without
# performing network requests or installing an app.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
        echo "error: --version requires a version" >&2; exit 1
      fi
      VERSION="$2"; shift 2 ;;
    --open) OPEN_AFTER=1; shift ;;
    --force) FORCE=1; shift ;;
    --install-dir)
      if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
        echo "error: --install-dir requires a path" >&2; exit 1
      fi
      INSTALL_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "error: unknown option: $1" >&2; usage >&2; exit 1 ;;
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
  if ! VERSION="$(printf '%s' "$API_JSON" | /usr/bin/plutil -extract tag_name raw -expect string -o - - 2>/dev/null)" || [[ "$VERSION" != v?* ]]; then
    echo "error: could not resolve the latest release" >&2; exit 1
  fi
  VERSION="${VERSION#v}"
  echo "    Latest release: v${VERSION}"
else
  VERSION="${VERSION#v}"
  echo "    Pinned version: v${VERSION}"
fi

ASSET="AerialDrop-${VERSION}-macOS.zip"
URL="${DL_BASE}/v${VERSION}/${ASSET}"
echo "    Asset: ${ASSET}"

echo "==> Fetching expected checksum"
if ! EXPECTED_SHA="$(api_get "repos/${REPO}/releases/tags/v${VERSION}" | release_asset_sha "$ASSET")"; then
  echo "error: could not fetch the checksum for ${ASSET} (is v${VERSION} published?)." >&2
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
