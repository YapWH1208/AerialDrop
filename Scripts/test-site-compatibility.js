#!/usr/bin/env node
/* Offline browser contract and release selector checks; Node built-ins only. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const compatibility = require('../docs/compatibility.js');

const root = path.resolve(__dirname, '..');
const fixture = JSON.parse(fs.readFileSync(path.join(root, 'Tests/DistributionFixtures/compatibility.json'), 'utf8'));
const source = fs.readFileSync(path.join(root, 'docs/app.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'docs/index.html'), 'utf8');

function element(value = '') {
  const attributes = new Map();
  const listeners = new Map();
  return {
    textContent: value, value, hidden: false, disabled: false,
    classList: { add() {}, remove() {}, toggle() {} },
    style: {},
    setAttribute(key, val) { attributes.set(key, String(val)); },
    removeAttribute(key) { attributes.delete(key); },
    getAttribute(key) { return attributes.get(key) || null; },
    addEventListener(key, callback) { listeners.set(key, callback); },
    trigger(key) { const callback = listeners.get(key); assert(callback, `missing ${key} listener`); callback({ target: this }); }
  };
}

function page(fetcher) {
  const ids = {};
  ['macosSelect', 'customMacos', 'customMacosLabel', 'releaseStatus', 'retryRelease',
    'releaseTag', 'releaseSize', 'expectVersion', 'unzipCmd', 'unzipCopy', 'termOut1', 'termOut4']
    .forEach(id => { ids[id] = element(); });
  const downloads = [element(), element()];
  const labels = [element(), element()];
  const document = {
    documentElement: { getAttribute() { return 'dark'; } },
    querySelector(selector) { return selector.startsWith('#') ? ids[selector.slice(1)] || null : null; },
    querySelectorAll(selector) {
      if (selector === '[data-download]') return downloads;
      if (selector === '[data-download-label]') return labels;
      return [];
    },
    getElementById(id) { return ids[id] || null; }
  };
  const window = { fetch: fetcher, AerialDropCompatibility: compatibility, matchMedia() { return { matches: true }; } };
  const context = { document, window, fetch: fetcher, navigator: {}, setTimeout() {}, clearTimeout() {}, Date, Promise, Number, String, Object, Array, isFinite };
  vm.runInNewContext(source, context, { filename: 'docs/app.js' });
  return { ids, downloads, labels };
}

async function flush() {
  await new Promise(resolve => setImmediate(resolve));
  await new Promise(resolve => setImmediate(resolve));
}

function response(data, ok = true, status = 200) { return { ok, status, json: async () => data }; }
function standardFetch(policy = fixture.policy, releases = fixture.catalogues.base) {
  return async url => url === 'release-compatibility.json' ? response(policy) : response(releases);
}

async function main() {
  for (const item of fixture.cases) {
    let selected = null;
    try { selected = compatibility.resolveRelease(fixture.policy, fixture.catalogues[item.catalogue], item.macos, item.arch, item.version).version; }
    catch (error) { assert.equal(item.expected_version, null, `${item.name}: ${error.message}`); }
    assert.equal(selected, item.expected_version, item.name);
  }
  assert.throws(() => compatibility.validatePolicy({ ...fixture.policy, schema_version: 2 }), /schema/);
  assert.throws(() => compatibility.validatePolicy({ ...fixture.policy, releases: [fixture.policy.releases[0], fixture.policy.releases[0]] }), /duplicate/);
  assert.throws(() => compatibility.validatePolicy({ ...fixture.policy, releases: [{ ...fixture.policy.releases[0], version: '1.1.8\n' }] }), /version/);
  assert.throws(() => compatibility.resolveRelease(fixture.policy, [{}, ...fixture.catalogues.base], 26, 'arm64'), /tag_name/);
  assert.throws(() => compatibility.resolveRelease(fixture.policy, [fixture.catalogues.base[0], fixture.catalogues.base[0]], 26, 'arm64'), /duplicate/);
  const current = fixture.catalogues.base[1];
  const badAsset = changes => [{ ...current, assets: [{ ...current.assets[0], ...changes }] }];
  assert.throws(() => compatibility.resolveRelease(fixture.policy, [{ ...current, tag_name: 'v1.1.9\n' }], 26, 'arm64'), /no compatible/);
  assert.throws(() => compatibility.resolveRelease(fixture.policy, badAsset({ digest: current.assets[0].digest + '\n' }), 26, 'arm64'), /no compatible/);
  assert.throws(() => compatibility.resolveRelease(fixture.policy, badAsset({ browser_download_url: current.assets[0].browser_download_url + '\n' }), 26, 'arm64'), /no compatible/);

  const paged = [];
  const catalogue = await compatibility.loadCatalogue(async url => {
    paged.push(url);
    return response(paged.length === 1 ? Array(100).fill(fixture.catalogues.base[0]) : [fixture.catalogues.base[1]]);
  });
  assert.equal(catalogue.length, 101);
  assert.match(paged[0], /per_page=100&page=1$/);
  assert.match(paged[1], /per_page=100&page=2$/);
  await assert.rejects(compatibility.loadCatalogue(async url => {
    if (url.endsWith('page=1')) return response(Array(100).fill(fixture.catalogues.base[0]));
    return response({}, false, 503);
  }), /HTTP 503/);

  assert.match(html, /<label for="macosSelect">/);
  assert.match(html, /<noscript>/);
  assert(!/data-download[^>]*href=/.test(html), 'static ZIP link must not target global latest');
  const sourceCommand = html.match(/<pre><code>(VERSION="[\s\S]*?)<\/code><\/pre>\s*<button class="cmd__copy" type="button" data-copy="([^"]+)"/);
  assert(sourceCommand, 'source tag command and copy control are missing');
  const decode = text => text.replace(/&quot;/g, '"').replace(/&amp;/g, '&');
  assert.equal(decode(sourceCommand[1]), decode(sourceCommand[2]), 'source tag copy differs from displayed command');
  assert.match(decode(sourceCommand[1]), /bash install\.sh --print-version/);
  assert.match(decode(sourceCommand[1]), /git clone --branch "v\$VERSION"/);

  const ui = page(standardFetch());
  assert.equal(ui.ids.unzipCopy.disabled, true);
  assert.equal(ui.downloads[0].getAttribute('href'), null);
  ui.ids.macosSelect.value = '26';
  ui.ids.macosSelect.trigger('change');
  await flush();
  assert.equal(ui.ids.releaseTag.textContent, 'v1.1.9');
  assert.equal(ui.ids.expectVersion.textContent, '1.1.9');
  assert.match(ui.ids.unzipCmd.textContent, /AerialDrop-1\.1\.9-macOS\.zip/);
  assert.equal(ui.ids.unzipCopy.getAttribute('data-copy'), ui.ids.unzipCmd.textContent);
  assert.equal(ui.ids.unzipCopy.disabled, false);
  assert.equal(ui.downloads[0].getAttribute('href'), fixture.catalogues.base[1].assets[0].browser_download_url);
  assert.match(ui.ids.termOut1.textContent, /1\.1\.9/);
  assert.match(ui.ids.termOut4.textContent, /1\.1\.9/);
  ui.ids.macosSelect.value = '27';
  ui.ids.macosSelect.trigger('change');
  assert.equal(ui.ids.unzipCopy.disabled, true, 'changing OS clears stale copy command immediately');
  assert.equal(ui.downloads[0].getAttribute('href'), null, 'changing OS clears stale link immediately');
  await flush();
  assert.equal(ui.ids.releaseTag.textContent, 'v1.1.10');
  assert.equal(ui.ids.expectVersion.textContent, '1.1.10');
  ui.ids.macosSelect.value = 'other';
  ui.ids.customMacos.value = '25';
  ui.ids.macosSelect.trigger('change');
  assert.equal(ui.ids.customMacos.hidden, false);
  assert.equal(ui.downloads[0].getAttribute('href'), null);
  assert.equal(ui.ids.unzipCopy.getAttribute('data-copy'), null);
  assert.match(ui.ids.releaseStatus.textContent, /Enter a macOS major version/);
  assert.equal(ui.ids.expectVersion.textContent, 'Resolve on this Mac');

  const noMatch = page(standardFetch(fixture.policy, fixture.catalogues.empty));
  noMatch.ids.macosSelect.value = '26';
  noMatch.ids.macosSelect.trigger('change');
  await flush();
  assert.match(noMatch.ids.releaseStatus.textContent, /No compatible published release/);
  assert.equal(noMatch.downloads[0].getAttribute('href'), null);

  const network = page(async url => url === 'release-compatibility.json' ? response(fixture.policy) : response({}, false, 503));
  network.ids.macosSelect.value = '26';
  network.ids.macosSelect.trigger('change');
  await flush();
  assert.match(network.ids.releaseStatus.textContent, /Couldn’t verify/);
  assert.equal(network.ids.retryRelease.hidden, false);
  assert.equal(network.downloads[0].getAttribute('href'), null);

  let policyRecovered = false, policyFetches = 0;
  const badPolicy = page(async url => {
    if (url === 'release-compatibility.json') {
      policyFetches++;
      return response(policyRecovered ? fixture.policy : { ...fixture.policy, schema_version: 2 });
    }
    return response(fixture.catalogues.base);
  });
  badPolicy.ids.macosSelect.value = '26';
  badPolicy.ids.macosSelect.trigger('change');
  await flush();
  assert.match(badPolicy.ids.releaseStatus.textContent, /Couldn’t verify/);
  assert.equal(badPolicy.downloads[0].getAttribute('href'), null);
  policyRecovered = true;
  badPolicy.ids.retryRelease.trigger('click');
  await flush();
  assert.equal(policyFetches, 2, 'retry refetches successfully fetched but invalid policy');
  assert.equal(badPolicy.ids.releaseTag.textContent, 'v1.1.9', 'retry recovers after invalid metadata is replaced');

  let finish;
  const pending = new Promise(resolve => { finish = resolve; });
  const race = page(async url => url === 'release-compatibility.json' ? response(fixture.policy) : pending);
  race.ids.macosSelect.value = '26';
  race.ids.macosSelect.trigger('change');
  race.ids.macosSelect.value = '27';
  race.ids.macosSelect.trigger('change');
  finish(response(fixture.catalogues.base));
  await flush();
  assert.equal(race.ids.releaseTag.textContent, 'v1.1.10', 'stale selection cannot overwrite newer selection');

  console.log(`Site compatibility: ${fixture.cases.length} shared cases, pagination, links, copy, empty, network and race passed.`);
}

main().catch(error => { console.error(error); process.exitCode = 1; });
