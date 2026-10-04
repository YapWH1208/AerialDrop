#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

node <<'NODE'
const fs = require('node:fs');
const assert = require('node:assert/strict');
const compatibility = require('./docs/compatibility.js');
const appVersion = fs.readFileSync('Sources/AerialDrop/AppVersion.swift', 'utf8');
const packageFile = fs.readFileSync('Package.swift', 'utf8');
const html = fs.readFileSync('docs/index.html', 'utf8');
const app = fs.readFileSync('docs/app.js', 'utf8');
const version = appVersion.match(/static let shortVersion\s*=\s*"([^"]+)"/);
const minimum = packageFile.match(/\.macOS\("([0-9]+)\.0"\)/);
assert(version, 'missing AppVersion.shortVersion');
assert(minimum, 'missing Package.swift macOS minimum');
const policy = compatibility.validatePolicy(JSON.parse(fs.readFileSync('docs/release-compatibility.json', 'utf8')));
const record = policy.releases.find(release => release.version === version[1]);
assert(record, `source version ${version[1]} is absent from compatibility policy`);
assert.equal(record.min_macos, Number(minimum[1]), 'source and policy macOS minima differ');
assert(record.architectures.includes('arm64'), 'source version lacks Apple Silicon support');
assert(html.includes(`The current source version is ${version[1]}`), 'site source version guidance is stale');
assert(!/data-download[^>]*href=|href="[^"]*releases\/latest"[^>]*data-download/.test(html), 'static download must not point to global latest');
assert(app.includes('window.AerialDropCompatibility.resolveRelease'), 'site must use compatibility resolver');
console.log(`Website source guidance and compatibility minimum match AerialDrop ${version[1]}.`);
NODE
