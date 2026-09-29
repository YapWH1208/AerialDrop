#!/bin/bash
# Offline smoke tests for the standalone installer and its release parser.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="${ROOT}/install.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Sourcing defines the production parser but does not run the installer.
source "$INSTALLER"

ASSET="AerialDrop-1.1.7-macOS.zip"
SHA_A="$(printf '%064d' 0 | tr 0 a)"
SHA_B="$(printf '%064d' 0 | tr 0 b)"

expect_sha() {
  local label="$1" json="$2" expected="$3" actual
  actual="$(printf '%s' "$json" | release_asset_sha "$ASSET")" || {
    echo "FAIL: ${label}: parser rejected a valid release" >&2; exit 1;
  }
  [[ "$actual" == "$expected" ]] || {
    echo "FAIL: ${label}: got ${actual}, expected ${expected}" >&2; exit 1;
  }
}

reject_sha() {
  local label="$1" json="$2"
  if printf '%s' "$json" | release_asset_sha "$ASSET" >/dev/null 2>&1; then
    echo "FAIL: ${label}: parser accepted invalid release metadata" >&2; exit 1
  fi
}

expect_sha 'compact multiasset, target first' \
  "{\"assets\":[{\"name\":\"${ASSET}\",\"digest\":\"sha256:${SHA_A}\"},{\"name\":\"other.zip\",\"digest\":\"sha256:${SHA_B}\"}]}" "$SHA_A"
expect_sha 'pretty JSON and reversed field order' \
  "$(cat <<EOF
{
  "assets": [
    { "name": "${ASSET}.sig", "digest": "sha256:${SHA_B}" },
    { "digest": "sha256:${SHA_A}", "name": "${ASSET}" }
  ]
}
EOF
)" "$SHA_A"
expect_sha 'uppercase hexadecimal normalized' \
  "{\"assets\":[{\"name\":\"${ASSET}\",\"digest\":\"sha256:$(printf '%s' "$SHA_A" | tr '[:lower:]' '[:upper:]')\"}]}" "$SHA_A"

reject_sha 'wrong asset only' "{\"assets\":[{\"name\":\"${ASSET}.sig\",\"digest\":\"sha256:${SHA_A}\"}]}"
reject_sha 'missing digest' "{\"assets\":[{\"name\":\"${ASSET}\"}]}"
reject_sha 'wrong algorithm' "{\"assets\":[{\"name\":\"${ASSET}\",\"digest\":\"sha1:${SHA_A}\"}]}"
reject_sha 'malformed hex' "{\"assets\":[{\"name\":\"${ASSET}\",\"digest\":\"sha256:${SHA_A%a}g\"}]}"
reject_sha 'duplicate exact asset' "{\"assets\":[{\"name\":\"${ASSET}\",\"digest\":\"sha256:${SHA_A}\"},{\"name\":\"${ASSET}\",\"digest\":\"sha256:${SHA_B}\"}]}"
reject_sha 'trailing newline in name' "{\"assets\":[{\"name\":\"${ASSET}\\n\",\"digest\":\"sha256:${SHA_A}\"}]}"
reject_sha 'missing assets array' '{"tag_name":"v1.1.7"}'
reject_sha 'invalid JSON' '{"assets":'

mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/uname" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == -m ]]; then echo arm64; else echo Darwin; fi
EOF
cat > "$TMP_DIR/bin/sw_vers" <<'EOF'
#!/bin/bash
echo 26.0
EOF
cat > "$TMP_DIR/bin/gh" <<'EOF'
#!/bin/bash
printf 'gh\n' >> "$AERIALDROP_TEST_CALLS"
exit 99
EOF
cat > "$TMP_DIR/bin/curl" <<'EOF'
#!/bin/bash
printf 'curl\n' >> "$AERIALDROP_TEST_CALLS"
exit 99
EOF
chmod +x "$TMP_DIR/bin/"*
export PATH="$TMP_DIR/bin:$PATH"
export AERIALDROP_TEST_CALLS="$TMP_DIR/calls"
: > "$AERIALDROP_TEST_CALLS"

expect_cli_status() {
  local label="$1" expected="$2" status=0
  shift 2
  bash "$INSTALLER" "$@" > "$TMP_DIR/cli-output" 2>&1 || status=$?
  [[ "$status" -eq "$expected" ]] || {
    echo "FAIL: ${label}: exit ${status}, expected ${expected}" >&2; exit 1;
  }
  [[ ! -s "$AERIALDROP_TEST_CALLS" ]] || {
    echo "FAIL: ${label}: invoked network command" >&2; exit 1;
  }
}

expect_cli_status 'help' 0 --help
expect_cli_status 'unknown option' 1 --unknown
expect_cli_status 'missing version' 1 --version
expect_cli_status 'empty version' 1 --version ''
expect_cli_status 'option used as version' 1 --version --open
expect_cli_status 'missing install dir' 1 --install-dir
expect_cli_status 'empty install dir' 1 --install-dir ''
expect_cli_status 'option used as install dir' 1 --install-dir --force

# A tiny local archive exercises the actual release lookup and install path.
# Mocked gh/curl never make network requests; all files stay in TMP_DIR.
mkdir -p "$TMP_DIR/payload/AerialDrop.app/Contents/MacOS"
printf '#!/bin/sh\nexit 0\n' > "$TMP_DIR/payload/AerialDrop.app/Contents/MacOS/AerialDrop"
chmod +x "$TMP_DIR/payload/AerialDrop.app/Contents/MacOS/AerialDrop"
ditto -c -k --keepParent "$TMP_DIR/payload/AerialDrop.app" "$TMP_DIR/release.zip"
REAL_SHA="$(shasum -a 256 "$TMP_DIR/release.zip" | awk '{print $1}')"
cat > "$TMP_DIR/release.json" <<EOF
{"tag_name":"v1.1.7","assets":[{"name":"${ASSET}","digest":"sha256:${REAL_SHA}"},{"name":"other.zip","digest":"sha256:${SHA_B}"}]}
EOF
cat > "$TMP_DIR/bin/gh" <<'EOF'
#!/bin/bash
case "${1:-}" in
  auth) exit 0 ;;
  api) printf 'gh:%s\n' "$2" >> "$AERIALDROP_TEST_CALLS"; cat "$AERIALDROP_TEST_RELEASE" ;;
  *) exit 99 ;;
esac
EOF
cat > "$TMP_DIR/bin/curl" <<'EOF'
#!/bin/bash
printf 'curl\n' >> "$AERIALDROP_TEST_CALLS"
while [[ $# -gt 0 ]]; do
  if [[ "$1" == -o ]]; then
    cp "$AERIALDROP_TEST_ZIP" "$2"
    exit 0
  fi
  shift
done
exit 99
EOF
chmod +x "$TMP_DIR/bin/gh" "$TMP_DIR/bin/curl"
export AERIALDROP_TEST_RELEASE="$TMP_DIR/release.json"
export AERIALDROP_TEST_ZIP="$TMP_DIR/release.zip"

bash "$INSTALLER" --version 1.1.7 --install-dir "$TMP_DIR/installed-pinned" > "$TMP_DIR/cli-output" 2>&1 || {
  cat "$TMP_DIR/cli-output" >&2; echo 'FAIL: pinned offline install' >&2; exit 1;
}
[[ -x "$TMP_DIR/installed-pinned/AerialDrop.app/Contents/MacOS/AerialDrop" ]]

bash "$INSTALLER" --install-dir "$TMP_DIR/installed-latest" > "$TMP_DIR/cli-output" 2>&1 || {
  cat "$TMP_DIR/cli-output" >&2; echo 'FAIL: latest offline install' >&2; exit 1;
}
[[ -x "$TMP_DIR/installed-latest/AerialDrop.app/Contents/MacOS/AerialDrop" ]]

echo 'PASS: installer release parsing, argument statuses, and offline installs'
