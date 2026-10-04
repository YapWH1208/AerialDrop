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

# Maintenance tests may use Python to split the shared fixture. install.sh does not.
python3 - "$ROOT/Tests/DistributionFixtures/compatibility.json" "$TMP_DIR" <<'PYTHON'
import json, pathlib, sys
fixture=json.loads(pathlib.Path(sys.argv[1]).read_text())
out=pathlib.Path(sys.argv[2])
(out/'policy.json').write_text(json.dumps(fixture['policy']))
for name, catalogue in fixture['catalogues'].items():
    (out/f'{name}.json').write_text(json.dumps(catalogue))
with (out/'cases.tsv').open('w') as handle:
    for case in fixture['cases']:
        print(case['name'], case['catalogue'], case['macos'], case['arch'],
              case.get('version','-'), case['expected_version'] or '-', sep='\t', file=handle)
PYTHON

validate_policy_json "$(cat "$TMP_DIR/policy.json")" || { echo 'FAIL: shared policy invalid' >&2; exit 1; }
api_get() { cat "$AERIALDROP_TEST_RELEASES"; }
while IFS=$'\t' read -r name catalogue os arch pin expected; do
  export AERIALDROP_TEST_RELEASES="$TMP_DIR/$catalogue.json"
  [[ "$pin" == '-' ]] && pin=''
  if resolve_releases "$os" "$arch" "$pin"; then
    [[ "$SELECTED_VERSION" == "$expected" ]] || {
      echo "FAIL: $name selected $SELECTED_VERSION, expected $expected" >&2; exit 1;
    }
  else
    [[ "$expected" == '-' ]] || { echo "FAIL: $name rejected a valid release" >&2; exit 1; }
  fi
done < "$TMP_DIR/cases.tsv"

# Policy errors and duplicate catalogue tags must fail explicitly.
if validate_policy_json '{"schema_version":2,"releases":[]}'; then
  echo 'FAIL: malformed policy accepted' >&2; exit 1
fi
validate_policy_json "$(cat "$TMP_DIR/policy.json")"
printf '[%s,%s]' "$(cat "$TMP_DIR/base.json" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)[0]))')" "$(cat "$TMP_DIR/base.json" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)[0]))')" > "$TMP_DIR/duplicates.json"
export AERIALDROP_TEST_RELEASES="$TMP_DIR/duplicates.json"
if resolve_releases 26 arm64 ''; then
  echo 'FAIL: duplicate release tags accepted' >&2; exit 1
fi

# A full first page cannot be mistaken for the end of GitHub pagination.
python3 - "$TMP_DIR" <<'PYTHON'
import json, pathlib, sys
out=pathlib.Path(sys.argv[1])
page=[{'tag_name':f'v9.0.{n}','draft':False,'prerelease':False,
       'published_at':'2026-01-01T00:00:00Z','assets':[]} for n in range(100)]
(out/'page1.json').write_text(json.dumps(page))
(out/'oversized-page.json').write_text(json.dumps(page + [{'tag_name': 'v9.0.100'}]))
base=json.loads((out/'base.json').read_text())
(out/'page2.json').write_text(json.dumps(base[:3]))
PYTHON
api_get() {
  case "$1" in
    *page=1) cat "$TMP_DIR/page1.json" ;;
    *page=2) cat "$TMP_DIR/page2.json" ;;
    *) return 1 ;;
  esac
}
resolve_releases 26 arm64 ''
[[ "$SELECTED_VERSION" == 1.1.9 ]] || { echo 'FAIL: pagination lost compatible release' >&2; exit 1; }
api_get() { cat "$TMP_DIR/oversized-page.json"; }
if resolve_releases 26 arm64 ''; then
  echo 'FAIL: oversized release page accepted' >&2; exit 1
fi
[[ "$RESOLVE_ERROR" == *oversized* ]] || { echo 'FAIL: oversized page has no actionable error' >&2; exit 1; }

# CLI mocks keep all archives and install destinations inside TMP_DIR.
mkdir -p "$TMP_DIR/bin" "$TMP_DIR/payload/AerialDrop.app/Contents/MacOS"
cat > "$TMP_DIR/bin/uname" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == -m ]]; then echo "${AERIALDROP_TEST_ARCH:-arm64}"; else echo Darwin; fi
EOF
cat > "$TMP_DIR/bin/sw_vers" <<'EOF'
#!/bin/bash
echo "${AERIALDROP_TEST_MACOS:-26.0}"
EOF
cat > "$TMP_DIR/bin/gh" <<'EOF'
#!/bin/bash
case "${1:-}" in
  auth) exit 0 ;;
  api)
    printf 'gh:%s\n' "$2" >> "$AERIALDROP_TEST_CALLS"
    [[ "${AERIALDROP_TEST_CATALOGUE_FAIL:-0}" != 1 ]] || exit 1
    cat "$AERIALDROP_TEST_RELEASES" ;;
  *) exit 99 ;;
esac
EOF
cat > "$TMP_DIR/bin/curl" <<'EOF'
#!/bin/bash
printf 'curl:%s\n' "$*" >> "$AERIALDROP_TEST_CALLS"
for arg in "$@"; do
  case "$arg" in
    https://raw.githubusercontent.com/*)
      [[ "${AERIALDROP_TEST_POLICY_FAIL:-0}" != 1 ]] || exit 22
      cat "$AERIALDROP_TEST_POLICY"; exit $? ;;
    https://api.github.com/*) printf '404'; exit 0 ;;
  esac
done
while [[ $# -gt 0 ]]; do
  if [[ "$1" == -o ]]; then
    printf 'download\n' >> "$AERIALDROP_TEST_CALLS"
    cp "$AERIALDROP_TEST_ZIP" "$2"
    exit 0
  fi
  shift
done
exit 99
EOF
cat > "$TMP_DIR/bin/open" <<'EOF'
#!/bin/bash
printf 'open:%s\n' "$*" >> "$AERIALDROP_TEST_CALLS"
EOF
cat > "$TMP_DIR/bin/sleep" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$TMP_DIR/bin/"*
export PATH="$TMP_DIR/bin:$PATH"
export AERIALDROP_TEST_CALLS="$TMP_DIR/calls"
export AERIALDROP_TEST_POLICY="$ROOT/docs/release-compatibility.json"
export AERIALDROP_TEST_MACOS=26.0 AERIALDROP_TEST_ARCH=arm64
: > "$AERIALDROP_TEST_CALLS"

expect_cli_status() {
  local label="$1" expected="$2" status=0
  shift 2
  bash "$INSTALLER" "$@" > "$TMP_DIR/cli-output" 2>&1 || status=$?
  [[ "$status" -eq "$expected" ]] || {
    echo "FAIL: ${label}: exit ${status}, expected ${expected}" >&2
    cat "$TMP_DIR/cli-output" >&2
    exit 1
  }
  [[ ! -s "$AERIALDROP_TEST_CALLS" ]] || {
    echo "FAIL: ${label}: invoked network command" >&2; exit 1
  }
}
expect_cli_status 'help' 0 --help
expect_cli_status 'unknown option' 1 --unknown
expect_cli_status 'missing version' 1 --version
expect_cli_status 'empty version' 1 --version ''
expect_cli_status 'option used as version' 1 --version --open
expect_cli_status 'bare v is not an automatic selection' 1 --version v
expect_cli_status 'missing install dir' 1 --install-dir
expect_cli_status 'empty install dir' 1 --install-dir ''
expect_cli_status 'option used as install dir' 1 --install-dir --force
expect_cli_status 'print cannot open' 1 --print-version --open

# Build a real local archive with bundle metadata, then give it an exact
# official-looking catalogue record. No mocked command writes to Applications.
cat > "$TMP_DIR/payload/AerialDrop.app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>1.1.9</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
</dict></plist>
EOF
printf '#!/bin/sh\nexit 0\n' > "$TMP_DIR/payload/AerialDrop.app/Contents/MacOS/AerialDrop"
chmod +x "$TMP_DIR/payload/AerialDrop.app/Contents/MacOS/AerialDrop"
ditto -c -k --keepParent "$TMP_DIR/payload/AerialDrop.app" "$TMP_DIR/release.zip"
export AERIALDROP_TEST_ZIP="$TMP_DIR/release.zip"
REAL_SHA="$(shasum -a 256 "$AERIALDROP_TEST_ZIP" | awk '{print $1}')"
REAL_SIZE="$(stat -f%z "$AERIALDROP_TEST_ZIP")"
cat > "$TMP_DIR/release.json" <<EOF
[{"tag_name":"v1.1.9","draft":false,"prerelease":false,"published_at":"2026-01-01T00:00:00Z","assets":[{"name":"AerialDrop-1.1.9-macOS.zip","digest":"sha256:${REAL_SHA}","size":${REAL_SIZE},"browser_download_url":"https://github.com/YapWH1208/AerialDrop/releases/download/v1.1.9/AerialDrop-1.1.9-macOS.zip"}]}]
EOF
cp "$TMP_DIR/payload/AerialDrop.app/Contents/Info.plist" "$TMP_DIR/good-Info.plist"
python3 - "$ROOT/docs/release-compatibility.json" "$TMP_DIR/release.json" "$TMP_DIR" <<'PYTHON'
import copy, json, pathlib, sys
policy=json.loads(pathlib.Path(sys.argv[1]).read_text())
catalogue=json.loads(pathlib.Path(sys.argv[2]).read_text())
out=pathlib.Path(sys.argv[3])
for field in ('version', 'architectures'):
    altered=copy.deepcopy(policy)
    if field == 'version':
        altered['releases'][-1]['version'] += '\n'
    else:
        altered['releases'][-1]['architectures'][0] += '\n'
    (out/f'newline-policy-{field}.json').write_text(json.dumps(altered))
for field in ('tag_name', 'name', 'digest', 'browser_download_url'):
    altered=copy.deepcopy(catalogue)
    target=altered[0] if field == 'tag_name' else altered[0]['assets'][0]
    target[field] += '\n'
    (out/f'newline-release-{field}.json').write_text(json.dumps(altered))
PYTHON
export AERIALDROP_TEST_RELEASES="$TMP_DIR/release.json"

: > "$AERIALDROP_TEST_CALLS"
PRINTED="$(bash "$INSTALLER" --print-version --install-dir "$TMP_DIR/installed-readonly")" || { echo 'FAIL: print version' >&2; exit 1; }
[[ "$PRINTED" == 1.1.9 ]] || { echo "FAIL: print version emitted $PRINTED" >&2; exit 1; }
[[ ! -d "$TMP_DIR/installed-readonly" ]] || { echo 'FAIL: print version installed app' >&2; exit 1; }
if grep -Eq '^(download|open):?' "$AERIALDROP_TEST_CALLS"; then
  echo 'FAIL: print version downloaded or launched app' >&2; exit 1
fi

bash "$INSTALLER" --version 1.1.9 --install-dir "$TMP_DIR/installed-pinned" > "$TMP_DIR/cli-output" 2>&1 || {
  cat "$TMP_DIR/cli-output" >&2; echo 'FAIL: pinned offline install' >&2; exit 1;
}
[[ -x "$TMP_DIR/installed-pinned/AerialDrop.app/Contents/MacOS/AerialDrop" ]]

bash "$INSTALLER" --install-dir "$TMP_DIR/installed-latest" > "$TMP_DIR/cli-output" 2>&1 || {
  cat "$TMP_DIR/cli-output" >&2; echo 'FAIL: newest-compatible offline install' >&2; exit 1;
}
[[ -x "$TMP_DIR/installed-latest/AerialDrop.app/Contents/MacOS/AerialDrop" ]]

# A selected version that the Mac cannot run fails before downloading.
export AERIALDROP_TEST_POLICY="$TMP_DIR/policy.json"
export AERIALDROP_TEST_RELEASES="$TMP_DIR/base.json"
: > "$AERIALDROP_TEST_CALLS"
if bash "$INSTALLER" --version 1.1.10 --install-dir "$TMP_DIR/invalid-pin" > "$TMP_DIR/cli-output" 2>&1; then
  echo 'FAIL: incompatible version pin accepted' >&2; exit 1
fi
[[ ! -d "$TMP_DIR/invalid-pin" ]]
export AERIALDROP_TEST_POLICY="$ROOT/docs/release-compatibility.json"
export AERIALDROP_TEST_RELEASES="$TMP_DIR/release.json"

# A newer installed app is never silently downgraded, even with --force.
mkdir -p "$TMP_DIR/sentinel/AerialDrop.app/Contents"
printf 'preserve me' > "$TMP_DIR/sentinel/AerialDrop.app/sentinel"
sed 's/1.1.9/1.1.10/' "$TMP_DIR/payload/AerialDrop.app/Contents/Info.plist" > "$TMP_DIR/sentinel/AerialDrop.app/Contents/Info.plist"
if bash "$INSTALLER" --force --install-dir "$TMP_DIR/sentinel" > "$TMP_DIR/cli-output" 2>&1; then
  echo 'FAIL: automatic downgrade accepted' >&2; exit 1
fi
[[ "$(cat "$TMP_DIR/sentinel/AerialDrop.app/sentinel")" == 'preserve me' ]]

expect_preserved_failure() {
  local label="$1" message="$2"
  shift 2
  : > "$AERIALDROP_TEST_CALLS"
  if bash "$INSTALLER" --force --install-dir "$TMP_DIR/sentinel" "$@" > "$TMP_DIR/cli-output" 2>&1; then
    echo "FAIL: $label accepted" >&2; exit 1
  fi
  grep -q "$message" "$TMP_DIR/cli-output" || {
    echo "FAIL: $label gave no matching error" >&2
    cat "$TMP_DIR/cli-output" >&2
    exit 1
  }
  [[ "$(cat "$TMP_DIR/sentinel/AerialDrop.app/sentinel")" == 'preserve me' ]] || {
    echo "FAIL: $label changed installed app" >&2; exit 1
  }
  if grep -Eq '^(download|open):?' "$AERIALDROP_TEST_CALLS"; then
    echo "FAIL: $label downloaded or launched app" >&2; exit 1
  fi
}

printf '{"schema_version":2,"releases":[]}' > "$TMP_DIR/malformed-policy.json"
export AERIALDROP_TEST_POLICY="$TMP_DIR/malformed-policy.json"
expect_preserved_failure 'malformed policy' 'compatibility policy is malformed'
export AERIALDROP_TEST_POLICY="$ROOT/docs/release-compatibility.json"
export AERIALDROP_TEST_POLICY_FAIL=1
expect_preserved_failure 'unavailable policy' 'could not fetch the compatibility policy'
unset AERIALDROP_TEST_POLICY_FAIL

export AERIALDROP_TEST_CATALOGUE_FAIL=1
expect_preserved_failure 'unavailable catalogue' 'could not fetch the complete release catalogue'
unset AERIALDROP_TEST_CATALOGUE_FAIL
printf '{"message":"malformed"}' > "$TMP_DIR/malformed-catalogue.json"
export AERIALDROP_TEST_RELEASES="$TMP_DIR/malformed-catalogue.json"
expect_preserved_failure 'malformed catalogue' 'malformed release catalogue'
export AERIALDROP_TEST_RELEASES="$TMP_DIR/empty.json"
expect_preserved_failure 'no published release' 'no compatible published release'
export AERIALDROP_TEST_RELEASES="$TMP_DIR/release.json"
expect_preserved_failure 'unknown version pin' 'not declared in the compatibility policy' --version 9.9.9
export AERIALDROP_TEST_MACOS=25.0
expect_preserved_failure 'unsupported macOS' 'requires macOS Tahoe 26'
export AERIALDROP_TEST_MACOS=26.0 AERIALDROP_TEST_ARCH=ppc
expect_preserved_failure 'unsupported architecture' 'unsupported architecture'
export AERIALDROP_TEST_ARCH=arm64

# Literal newlines are data. Command substitutions must not turn them into
# valid policy versions, architectures, tags, asset names, digests or URLs.
for field in version architectures; do
  export AERIALDROP_TEST_POLICY="$TMP_DIR/newline-policy-$field.json"
  expect_preserved_failure "newline policy $field" 'compatibility policy is malformed'
done
export AERIALDROP_TEST_POLICY="$ROOT/docs/release-compatibility.json"
for field in tag_name name digest browser_download_url; do
  export AERIALDROP_TEST_RELEASES="$TMP_DIR/newline-release-$field.json"
  expect_preserved_failure "newline release $field" 'no compatible published release'
done
export AERIALDROP_TEST_RELEASES="$TMP_DIR/release.json"

printf 'n\n' | bash "$INSTALLER" --version 1.1.9 --install-dir "$TMP_DIR/sentinel" > "$TMP_DIR/cli-output" 2>&1 || {
  echo 'FAIL: replacement cancellation returned an error' >&2; exit 1;
}
[[ "$(cat "$TMP_DIR/sentinel/AerialDrop.app/sentinel")" == 'preserve me' ]]

# A bad digest or bundle must fail before replacing an existing installation.
sed "s/${REAL_SHA}/${SHA_A}/" "$TMP_DIR/release.json" > "$TMP_DIR/wrong-digest.json"
export AERIALDROP_TEST_RELEASES="$TMP_DIR/wrong-digest.json"
if bash "$INSTALLER" --version 1.1.9 --force --install-dir "$TMP_DIR/sentinel" > "$TMP_DIR/cli-output" 2>&1; then
  echo 'FAIL: checksum mismatch installed app' >&2; exit 1
fi
[[ "$(cat "$TMP_DIR/sentinel/AerialDrop.app/sentinel")" == 'preserve me' ]]

export AERIALDROP_TEST_RELEASES="$TMP_DIR/release.json"
cp "$TMP_DIR/release.zip" "$TMP_DIR/good-release.zip"
sed -i '' 's/1.1.9/1.1.8/' "$TMP_DIR/payload/AerialDrop.app/Contents/Info.plist"
ditto -c -k --keepParent "$TMP_DIR/payload/AerialDrop.app" "$TMP_DIR/release.zip"
NEW_SHA="$(shasum -a 256 "$TMP_DIR/release.zip" | awk '{print $1}')"
NEW_SIZE="$(stat -f%z "$TMP_DIR/release.zip")"
sed -e "s/${REAL_SHA}/${NEW_SHA}/" -e "s/\"size\":${REAL_SIZE}/\"size\":${NEW_SIZE}/" "$TMP_DIR/release.json" > "$TMP_DIR/bad-bundle.json"
export AERIALDROP_TEST_RELEASES="$TMP_DIR/bad-bundle.json"
if bash "$INSTALLER" --version 1.1.9 --force --install-dir "$TMP_DIR/sentinel" > "$TMP_DIR/cli-output" 2>&1; then
  echo 'FAIL: bundle version mismatch installed app' >&2; exit 1
fi
[[ "$(cat "$TMP_DIR/sentinel/AerialDrop.app/sentinel")" == 'preserve me' ]]

# Even a matching ZIP digest cannot authorize a bundle with a different OS
# minimum or a missing executable.
sed -i '' -e 's/1.1.8/1.1.9/' -e 's/26.0/27.0/' "$TMP_DIR/payload/AerialDrop.app/Contents/Info.plist"
ditto -c -k --keepParent "$TMP_DIR/payload/AerialDrop.app" "$TMP_DIR/release.zip"
MIN_SHA="$(shasum -a 256 "$TMP_DIR/release.zip" | awk '{print $1}')"
MIN_SIZE="$(stat -f%z "$TMP_DIR/release.zip")"
sed -e "s/${REAL_SHA}/${MIN_SHA}/" -e "s/\"size\":${REAL_SIZE}/\"size\":${MIN_SIZE}/" "$TMP_DIR/release.json" > "$TMP_DIR/bad-minimum.json"
export AERIALDROP_TEST_RELEASES="$TMP_DIR/bad-minimum.json"
if bash "$INSTALLER" --version 1.1.9 --force --install-dir "$TMP_DIR/sentinel" > "$TMP_DIR/cli-output" 2>&1; then
  echo 'FAIL: bundle minimum mismatch installed app' >&2; exit 1
fi
[[ "$(cat "$TMP_DIR/sentinel/AerialDrop.app/sentinel")" == 'preserve me' ]]

for field in CFBundleShortVersionString LSMinimumSystemVersion; do
  cp "$TMP_DIR/good-Info.plist" "$TMP_DIR/payload/AerialDrop.app/Contents/Info.plist"
  python3 - "$TMP_DIR/payload/AerialDrop.app/Contents/Info.plist" "$field" <<'PYTHON'
import plistlib, pathlib, sys
path=pathlib.Path(sys.argv[1])
with path.open('rb') as handle:
    info=plistlib.load(handle)
info[sys.argv[2]] += '\n'
with path.open('wb') as handle:
    plistlib.dump(info, handle)
PYTHON
  ditto -c -k --keepParent "$TMP_DIR/payload/AerialDrop.app" "$TMP_DIR/release.zip"
  NEWLINE_SHA="$(shasum -a 256 "$TMP_DIR/release.zip" | awk '{print $1}')"
  NEWLINE_SIZE="$(stat -f%z "$TMP_DIR/release.zip")"
  sed -e "s/${REAL_SHA}/${NEWLINE_SHA}/" -e "s/\"size\":${REAL_SIZE}/\"size\":${NEWLINE_SIZE}/" "$TMP_DIR/release.json" > "$TMP_DIR/newline-bundle-$field.json"
  export AERIALDROP_TEST_RELEASES="$TMP_DIR/newline-bundle-$field.json"
  if bash "$INSTALLER" --version 1.1.9 --force --install-dir "$TMP_DIR/sentinel" > "$TMP_DIR/cli-output" 2>&1; then
    echo "FAIL: newline bundle $field installed app" >&2; exit 1
  fi
  [[ "$(cat "$TMP_DIR/sentinel/AerialDrop.app/sentinel")" == 'preserve me' ]]
done

rm "$TMP_DIR/payload/AerialDrop.app/Contents/MacOS/AerialDrop"
ditto -c -k --keepParent "$TMP_DIR/payload/AerialDrop.app" "$TMP_DIR/release.zip"
MISSING_SHA="$(shasum -a 256 "$TMP_DIR/release.zip" | awk '{print $1}')"
MISSING_SIZE="$(stat -f%z "$TMP_DIR/release.zip")"
sed -e "s/${REAL_SHA}/${MISSING_SHA}/" -e "s/\"size\":${REAL_SIZE}/\"size\":${MISSING_SIZE}/" "$TMP_DIR/release.json" > "$TMP_DIR/missing-executable.json"
export AERIALDROP_TEST_RELEASES="$TMP_DIR/missing-executable.json"
if bash "$INSTALLER" --version 1.1.9 --force --install-dir "$TMP_DIR/sentinel" > "$TMP_DIR/cli-output" 2>&1; then
  echo 'FAIL: missing bundle executable installed app' >&2; exit 1
fi
[[ "$(cat "$TMP_DIR/sentinel/AerialDrop.app/sentinel")" == 'preserve me' ]]

# An explicit compatible pin may deliberately replace a newer app.
export AERIALDROP_TEST_ZIP="$TMP_DIR/good-release.zip"
export AERIALDROP_TEST_RELEASES="$TMP_DIR/release.json"
bash "$INSTALLER" --version 1.1.9 --force --install-dir "$TMP_DIR/sentinel" > "$TMP_DIR/cli-output" 2>&1 || {
  cat "$TMP_DIR/cli-output" >&2; echo 'FAIL: explicit pinned replacement' >&2; exit 1;
}
[[ ! -f "$TMP_DIR/sentinel/AerialDrop.app/sentinel" ]]
[[ -x "$TMP_DIR/sentinel/AerialDrop.app/Contents/MacOS/AerialDrop" ]]

: > "$AERIALDROP_TEST_CALLS"
bash "$INSTALLER" --open --install-dir "$TMP_DIR/installed-open" > "$TMP_DIR/cli-output" 2>&1 || {
  cat "$TMP_DIR/cli-output" >&2; echo 'FAIL: offline --open install' >&2; exit 1;
}
[[ -x "$TMP_DIR/installed-open/AerialDrop.app/Contents/MacOS/AerialDrop" ]]
grep -Fxq "open:$TMP_DIR/installed-open/AerialDrop.app" "$AERIALDROP_TEST_CALLS" || {
  echo 'FAIL: --open did not call the mocked app launch' >&2; exit 1
}

echo 'PASS: shared compatibility matrix, paginated release resolution, parser, and offline install safety'
