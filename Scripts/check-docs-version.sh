#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

version=$(sed -n 's/.*static let shortVersion = "\([^"]*\)".*/\1/p' Sources/AerialDrop/AppVersion.swift)
if [ -z "$version" ]; then
    echo "Could not read shortVersion from Sources/AerialDrop/AppVersion.swift" >&2
    exit 1
fi

versions=$(
    {
        grep -E 'termOut1|termOut4|releaseTag|expectVersion|Options:.*install\.sh|unzipCmd|unzipCopy' docs/index.html
        grep -E 'rel\.tag_name \|\||applyRelease\(.*null' docs/app.js
    } | grep -Eo 'v?[0-9]+\.[0-9]+\.[0-9]+' | sed 's/^v//' | sort -u
)
if [ -z "$versions" ]; then
    echo "No release fallback versions found in docs/index.html or docs/app.js" >&2
    exit 1
fi

for found in $versions; do
    if [ "$found" != "$version" ]; then
        echo "Website fallback version $found does not match AppVersion.shortVersion $version" >&2
        exit 1
    fi
done

grep -Fq "AerialDrop-$version-macOS.zip" docs/index.html
grep -Fq "applyRelease(\"v$version\", null)" docs/app.js
grep -Fq "rel.tag_name || \"v$version\"" docs/app.js

printf 'Website release fallbacks match AerialDrop %s.\n' "$version"
