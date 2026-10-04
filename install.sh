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
#   ./install.sh                 install the newest compatible release
#   ./install.sh 1.1.3           install a specific version
#   ./install.sh --print-version print a compatible version without installing
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
POLICY_URL="https://raw.githubusercontent.com/${REPO}/main/docs/release-compatibility.json"

VERSION=""
INSTALL_DIR="${AERIALDROP_INSTALL_DIR:-${DEFAULT_INSTALL_DIR}}"
OPEN_AFTER=0
FORCE=0
PRINT_VERSION=0
PINNED=0

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

fail() { echo "error: $*" >&2; return 1; }

# plutil reads JSON as well as property lists. Keep the complete JSON intact:
# converting a subtree back to JSON fails when it contains JSON null values.
JSON_STRING=""
json_string() {
  local value
  JSON_STRING=""
  value="$(printf '%s' "$1" | /usr/bin/plutil -extract "$2" raw -expect string -n -o - - 2>/dev/null && printf '.')" || return 1
  # Return through a variable: a caller's $(...) would strip newlines again.
  JSON_STRING="${value%.}"
}

json_integer() {
  local value
  value="$(printf '%s' "$1" | /usr/bin/plutil -extract "$2" raw -expect integer -o - - 2>/dev/null)" || return 1
  [[ "$value" =~ ^(0|[1-9][0-9]*)$ ]] || return 1
  printf '%s' "$value"
}

json_bool() {
  printf '%s' "$1" | /usr/bin/plutil -extract "$2" raw -expect bool -o - - 2>/dev/null
}

json_count() {
  local count
  count="$(printf '%s' "$1" | /usr/bin/plutil -extract "$2" raw -expect array -o - - 2>/dev/null)" || return 1
  [[ "$count" =~ ^(0|[1-9][0-9]*)$ ]] || return 1
  printf '%s' "$count"
}

json_keys() {
  printf '%s' "$1" | /usr/bin/plutil -extract "$2" raw -expect dictionary -o - - 2>/dev/null
}

valid_version() {
  [[ "$1" =~ ^(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})$ ]]
}

valid_major() {
  [[ "$1" =~ ^(0|[1-9][0-9]{0,2})$ ]] && (( $1 >= 26 && $1 <= 999 ))
}

# All version strings have bounded, unpadded decimal components.
version_greater() {
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<< "$1"
  IFS=. read -r b1 b2 b3 <<< "$2"
  (( a1 > b1 || (a1 == b1 && a2 > b2) || (a1 == b1 && a2 == b2 && a3 > b3) ))
}

POLICY_VERSIONS=()
POLICY_MINS=()
POLICY_MAXS=()
POLICY_ARCHS=()
POLICY_COUNT=0

validate_policy_json() {
  local json="{\"policy\":${1}}" count schema index keys version minimum maximum max_type arch_count arch_index arch archs previous
  POLICY_VERSIONS=(); POLICY_MINS=(); POLICY_MAXS=(); POLICY_ARCHS=()
  POLICY_COUNT=0
  keys="$(json_keys "$json" policy)" || return 1
  [[ "$keys" == $'releases\nschema_version' ]] || return 1
  schema="$(json_integer "$json" policy.schema_version)" || return 1
  [[ "$schema" == 1 ]] || return 1
  count="$(json_count "$json" policy.releases)" || return 1
  (( count > 0 )) || return 1
  for ((index = 0; index < count; index++)); do
    keys="$(json_keys "$json" "policy.releases.${index}")" || return 1
    [[ "$keys" == $'architectures\nmax_macos\nmin_macos\nversion' ]] || return 1
    json_string "$json" "policy.releases.${index}.version" || return 1
    version="$JSON_STRING"
    valid_version "$version" || return 1
    for ((arch_index = 0; arch_index < POLICY_COUNT; arch_index++)); do
      [[ "${POLICY_VERSIONS[$arch_index]}" != "$version" ]] || return 1
    done
    minimum="$(json_integer "$json" "policy.releases.${index}.min_macos")" || return 1
    valid_major "$minimum" || return 1
    max_type="$(printf '%s' "$json" | /usr/bin/plutil -type "policy.releases.${index}.max_macos" -o - - 2>/dev/null)" || return 1
    case "$max_type" in
      '(any)') maximum="" ;;
      integer)
        maximum="$(json_integer "$json" "policy.releases.${index}.max_macos")" || return 1
        valid_major "$maximum" && (( maximum >= minimum )) || return 1 ;;
      *) return 1 ;;
    esac
    arch_count="$(json_count "$json" "policy.releases.${index}.architectures")" || return 1
    (( arch_count > 0 )) || return 1
    archs=,
    for ((arch_index = 0; arch_index < arch_count; arch_index++)); do
      json_string "$json" "policy.releases.${index}.architectures.${arch_index}" || return 1
      arch="$JSON_STRING"
      [[ "$arch" == arm64 || "$arch" == x86_64 ]] || return 1
      [[ "$archs" != *",${arch},"* ]] || return 1
      archs="${archs}${arch},"
    done
    POLICY_VERSIONS+=("$version")
    POLICY_MINS+=("$minimum")
    POLICY_MAXS+=("$maximum")
    POLICY_ARCHS+=("$archs")
    ((POLICY_COUNT += 1))
  done
}

POLICY_INDEX=-1
policy_lookup() {
  local wanted="$1" macos="$2" arch="$3" index
  POLICY_INDEX=-1
  for ((index = 0; index < POLICY_COUNT; index++)); do
    if [[ "${POLICY_VERSIONS[$index]}" == "$wanted" ]]; then
      POLICY_INDEX=$index
      (( macos >= POLICY_MINS[index] )) || return 1
      [[ -z "${POLICY_MAXS[$index]}" ]] || (( macos <= POLICY_MAXS[index] )) || return 1
      [[ "${POLICY_ARCHS[$index]}" == *",${arch},"* ]] || return 1
      return 0
    fi
  done
  return 1
}

SELECTED_VERSION=""
SELECTED_SHA=""
SELECTED_URL=""
SELECTED_MINIMUM=""
SEEN_TAGS=()
SEEN_COUNT=0

consider_release() {
  local json="$1" prefix="$2" macos="$3" arch="$4" pin="$5"
  local tag candidate prior draft prerelease published count index name expected digest size url matches sha=""
  json_string "$json" "${prefix}.tag_name" || return 1
  tag="$JSON_STRING"
  for ((index = 0; index < SEEN_COUNT; index++)); do
    [[ "${SEEN_TAGS[$index]}" != "$tag" ]] || return 1
  done
  SEEN_TAGS+=("$tag")
  ((SEEN_COUNT += 1))
  [[ "$tag" == v* ]] || return 0
  candidate="${tag#v}"
  valid_version "$candidate" || return 0
  [[ -z "$pin" || "$pin" == "$candidate" ]] || return 0
  policy_lookup "$candidate" "$macos" "$arch" || return 0
  draft="$(json_bool "$json" "${prefix}.draft")" || return 0
  prerelease="$(json_bool "$json" "${prefix}.prerelease")" || return 0
  [[ "$draft" == false && "$prerelease" == false ]] || return 0
  json_string "$json" "${prefix}.published_at" || return 0
  published="$JSON_STRING"
  [[ -n "$published" ]] || return 0
  count="$(json_count "$json" "${prefix}.assets")" || return 0
  expected="AerialDrop-${candidate}-macOS.zip"
  matches=0
  for ((index = 0; index < count; index++)); do
    json_string "$json" "${prefix}.assets.${index}.name" || continue
    name="$JSON_STRING"
    if [[ "$name" == "$expected" ]]; then
      ((matches += 1))
      [[ "$matches" -eq 1 ]] || return 0
      json_string "$json" "${prefix}.assets.${index}.digest" || return 0
      digest="$JSON_STRING"
      [[ "$digest" =~ ^sha256:([[:xdigit:]]{64})$ ]] || return 0
      sha="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
      size="$(json_integer "$json" "${prefix}.assets.${index}.size")" || return 0
      (( size > 0 )) || return 0
      json_string "$json" "${prefix}.assets.${index}.browser_download_url" || return 0
      url="$JSON_STRING"
      [[ "$url" == "${DL_BASE}/v${candidate}/${expected}" ]] || return 0
    fi
  done
  [[ "$matches" -eq 1 ]] || return 0
  if [[ -z "$SELECTED_VERSION" ]] || version_greater "$candidate" "$SELECTED_VERSION"; then
    SELECTED_VERSION="$candidate"
    SELECTED_SHA="$sha"
    SELECTED_URL="$url"
    SELECTED_MINIMUM="${POLICY_MINS[$POLICY_INDEX]}"
  fi
}

resolve_releases() {
  local macos="$1" arch="$2" pin="$3" page=1 json wrapped count index
  RESOLVE_ERROR=""
  SELECTED_VERSION=""; SELECTED_SHA=""; SELECTED_URL=""; SELECTED_MINIMUM=""; SEEN_TAGS=(); SEEN_COUNT=0
  while :; do
    (( page <= 100 )) || {
      RESOLVE_ERROR="release catalogue exceeds 100 pages"; return 1;
    }
    json="$(api_get "repos/${REPO}/releases?per_page=100&page=${page}")" || {
      RESOLVE_ERROR="could not fetch the complete release catalogue from GitHub"; return 1;
    }
    wrapped="{\"items\":${json}}"
    count="$(json_count "$wrapped" items)" || {
      RESOLVE_ERROR="GitHub returned a malformed release catalogue"; return 1;
    }
    (( count <= 100 )) || {
      RESOLVE_ERROR="GitHub returned an oversized release page"; return 1;
    }
    for ((index = 0; index < count; index++)); do
      consider_release "$wrapped" "items.${index}" "$macos" "$arch" "$pin" || {
        RESOLVE_ERROR="GitHub returned a malformed or duplicate release entry"; return 1;
      }
    done
    (( count == 100 )) || break
    ((page += 1))
  done
  [[ -n "$SELECTED_VERSION" ]] || {
    RESOLVE_ERROR="no compatible published release with an official ZIP asset is available"; return 1;
  }
}

PLIST_STRING=""
plist_string() {
  local value
  PLIST_STRING=""
  value="$(/usr/bin/plutil -extract "$2" raw -expect string -n -o - "$1" 2>/dev/null && printf '.')" || return 1
  PLIST_STRING="${value%.}"
}

log() {
  (( PRINT_VERSION == 1 )) || printf '%s\n' "$*"
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
      VERSION="$2"; PINNED=1; shift 2 ;;
    --open) OPEN_AFTER=1; shift ;;
    --force) FORCE=1; shift ;;
    --print-version) PRINT_VERSION=1; shift ;;
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
      VERSION="$1"; PINNED=1; shift ;;
  esac
done

[[ -n "$INSTALL_DIR" ]] || { echo "error: --install-dir requires a path" >&2; exit 1; }
if (( PRINT_VERSION == 1 && (OPEN_AFTER == 1 || FORCE == 1) )); then
  echo "error: --print-version cannot be combined with --open or --force" >&2
  exit 1
fi

log "==> Checking environment"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "error: AerialDrop is a macOS app; install it on macOS Tahoe 26 or later." >&2
  exit 1
fi

MACOS_VERSION="$(sw_vers -productVersion)"
MACOS_MAJOR="${MACOS_VERSION%%.*}"
if ! valid_major "$MACOS_MAJOR"; then
  echo "error: AerialDrop requires macOS Tahoe 26 or later (this Mac runs $(sw_vers -productVersion))." >&2
  exit 1
fi

ARCH="$(uname -m)"
if [[ "$ARCH" != arm64 && "$ARCH" != x86_64 ]]; then
  echo "error: unsupported architecture: ${ARCH}." >&2
  exit 1
fi

command -v curl >/dev/null || { echo "error: curl is required" >&2; exit 1; }

VERSION="${VERSION#v}"
if (( PINNED == 1 )) && ! valid_version "$VERSION"; then
  echo "error: version must be a stable numeric X.Y.Z without leading zeroes" >&2
  exit 1
fi
log "==> Resolving release for macOS ${MACOS_MAJOR} on ${ARCH}"
POLICY_JSON="$(curl -fSL --retry 3 --retry-delay 3 "$POLICY_URL")" || {
  echo "error: could not fetch the compatibility policy" >&2; exit 1;
}
validate_policy_json "$POLICY_JSON" || {
  echo "error: compatibility policy is malformed or unsupported" >&2; exit 1;
}
if (( PINNED == 1 )); then
  if ! policy_lookup "$VERSION" "$MACOS_MAJOR" "$ARCH"; then
    if (( POLICY_INDEX < 0 )); then
      echo "error: v${VERSION} is not declared in the compatibility policy" >&2
    else
      echo "error: v${VERSION} is incompatible with macOS ${MACOS_MAJOR} on ${ARCH}" >&2
    fi
    exit 1
  fi
fi
if ! resolve_releases "$MACOS_MAJOR" "$ARCH" "$VERSION"; then
  echo "error: ${RESOLVE_ERROR}" >&2
  exit 1
fi
VERSION="$SELECTED_VERSION"
ASSET="AerialDrop-${VERSION}-macOS.zip"
URL="$SELECTED_URL"
EXPECTED_SHA="$SELECTED_SHA"
log "    Selected: v${VERSION} (${ASSET})"

if (( PRINT_VERSION == 1 )); then
  printf '%s\n' "$VERSION"
  exit 0
fi

APP_DST="${INSTALL_DIR}/AerialDrop.app"
if [[ -d "$APP_DST" && "$PINNED" == 0 ]]; then
  plist_string "${APP_DST}/Contents/Info.plist" CFBundleShortVersionString || {
    echo "error: cannot read installed version; use an explicit version pin to replace it" >&2; exit 1;
  }
  INSTALLED_VERSION="$PLIST_STRING"
  valid_version "$INSTALLED_VERSION" || {
    echo "error: installed version is invalid; use an explicit version pin to replace it" >&2; exit 1;
  }
  if version_greater "$INSTALLED_VERSION" "$VERSION"; then
    echo "error: installed v${INSTALLED_VERSION} is newer than compatible v${VERSION}; use an explicit pin for a deliberate downgrade" >&2
    exit 1
  fi
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
ZIP="${TMP_DIR}/${ASSET}"

log "==> Downloading ${URL}"
if ! curl -fSL --retry 3 --retry-delay 3 -o "$ZIP" "$URL"; then
  echo "error: download failed — check the version (v${VERSION}) exists in the Releases page." >&2
  exit 1
fi

log "==> Verifying checksum"
ACTUAL_SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
  echo "error: checksum mismatch — expected ${EXPECTED_SHA}, got ${ACTUAL_SHA}. Aborting." >&2
  exit 1
fi
log "    sha256 OK (${ACTUAL_SHA})"

log "==> Extracting"
ditto -x -k "$ZIP" "$TMP_DIR"
APP_SRC="${TMP_DIR}/AerialDrop.app"
[[ -d "$APP_SRC" ]] || { echo "error: AerialDrop.app not found in the archive" >&2; exit 1; }
[[ -x "${APP_SRC}/Contents/MacOS/AerialDrop" ]] || {
  echo "error: downloaded app is missing its executable" >&2; exit 1;
}
plist_string "${APP_SRC}/Contents/Info.plist" CFBundleShortVersionString || {
  echo "error: downloaded app has no valid version in Info.plist" >&2; exit 1;
}
APP_VERSION="$PLIST_STRING"
[[ "$APP_VERSION" == "$VERSION" ]] || {
  echo "error: downloaded app version ${APP_VERSION} differs from v${VERSION}" >&2; exit 1;
}
plist_string "${APP_SRC}/Contents/Info.plist" LSMinimumSystemVersion || {
  echo "error: downloaded app has no valid macOS minimum in Info.plist" >&2; exit 1;
}
APP_MINIMUM="$PLIST_STRING"
[[ "$APP_MINIMUM" == "${SELECTED_MINIMUM}.0" ]] || {
  echo "error: downloaded app macOS minimum ${APP_MINIMUM} differs from compatibility policy" >&2; exit 1;
}

if [[ -d "$APP_DST" ]]; then
  if [[ "$FORCE" -eq 0 ]]; then
    read -r -p "AerialDrop is already installed at ${APP_DST}. Replace it? [y/N] " REPLY
    [[ "$REPLY" =~ ^[yY] ]] || { echo "Install cancelled."; exit 0; }
  fi
  rm -rf "$APP_DST"
fi
mkdir -p "$INSTALL_DIR"

log "==> Installing to ${APP_DST}"
mv "$APP_SRC" "$APP_DST"

log "==> Clearing download quarantine"
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
