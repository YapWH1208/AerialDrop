#!/usr/bin/env node
/* Offline browser contract and release selector checks; Node built-ins only. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const compatibility = require('../docs/compatibility.js');

const root = path.resolve(__dirname, '..');
const fixture = JSON.parse(fs.readFileSync(path.join(root, 'Tests/DistributionFixtures/compatibility.json'), 'utf8'));
const source = fs.readFileSync(path.join(root, 'docs/app.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'docs/index.html'), 'utf8');
const styles = fs.readFileSync(path.join(root, 'docs/styles.css'), 'utf8');

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

function page(fetcher, navigator = {}) {
  const ids = {};
  ['macosSelect', 'detectionStatus', 'releaseStatus', 'retryRelease',
    'releaseTag', 'releaseSize', 'expectVersion', 'unzipCmd', 'unzipCopy', 'termOut1', 'termOut4']
    .forEach(id => { ids[id] = element(); });
  ids.macosSelect.disabled = true;
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
  const window = { fetch: fetcher, navigator, AerialDropCompatibility: compatibility, matchMedia() { return { matches: true }; } };
  const context = { document, window, fetch: fetcher, navigator, setTimeout() {}, clearTimeout() {}, Date, Promise, Number, String, Object, Array, isFinite };
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

function clientHints(platformVersion, { platform = 'macOS', mobile = false } = {}) {
  return {
    platform,
    mobile,
    async getHighEntropyValues() { return { platform, mobile, platformVersion }; }
  };
}

function chooseMacos(ui, value) {
  ui.ids.macosSelect.value = value;
  ui.ids.macosSelect.trigger('change');
}

function assertZipUnavailable(ui, message) {
  for (const download of ui.downloads) {
    assert.equal(download.getAttribute('href'), null, message);
    assert.equal(download.getAttribute('aria-disabled'), 'true', message);
  }
  assert.equal(ui.ids.unzipCopy.disabled, true, message);
  assert.equal(ui.ids.unzipCopy.getAttribute('data-copy'), null, message);
}

async function testMacosDetection() {
  for (const [macos, platformVersion, release] of [
    ['26', '26.4.1', fixture.catalogues.base[1]],
    ['27', '27.0.0', fixture.catalogues.base[2]]
  ]) {
    const requests = [];
    const hints = {
      ...clientHints(platformVersion),
      async getHighEntropyValues(names) {
        requests.push(Array.from(names));
        return { platformVersion };
      }
    };
    const ui = page(standardFetch(), { userAgentData: hints });
    assert.equal(ui.ids.macosSelect.disabled, false, 'manual choice is available while detecting');
    await flush();
    assert.deepEqual(requests, [['platformVersion']], 'detection requests only the OS version hint');
    assert.equal(ui.ids.macosSelect.value, macos);
    assert.equal(ui.ids.detectionStatus.textContent, `Detected macOS ${macos}. You can change this selection.`);
    assert.match(ui.ids.releaseStatus.textContent, new RegExp(`macOS ${macos} on Apple Silicon`));
    assert.equal(ui.ids.releaseTag.textContent, release.tag_name);
    assert.equal(ui.ids.unzipCopy.disabled, false);
    for (const download of ui.downloads) {
      assert.equal(download.getAttribute('href'), release.assets[0].browser_download_url);
      assert.equal(download.getAttribute('aria-disabled'), null);
    }
    chooseMacos(ui, '');
    assert.equal(ui.ids.detectionStatus.textContent, '');
    assertZipUnavailable(ui);
  }

  const fallbackCases = [
    ['missing hints despite a Mac user agent', {
      platform: 'MacIntel',
      userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 26_0) AppleWebKit/605.1.15 Version/26.0 Safari/605.1.15'
    }],
    ['missing high-entropy API', { userAgentData: { platform: 'macOS', mobile: false } }],
    ['denied hints', { userAgentData: {
      ...clientHints('26.0.0'),
      async getHighEntropyValues() { throw new Error('Client hints denied'); }
    } }],
    ['throwing hints method', { userAgentData: {
      ...clientHints('26.0.0'),
      getHighEntropyValues() { throw new Error('Client hints unavailable'); }
    } }],
    ['throwing hints accessor', {
      get userAgentData() { throw new Error('Client hints unavailable'); }
    }],
    ['missing hint result', { userAgentData: {
      ...clientHints('26.0.0'),
      async getHighEntropyValues() { return null; }
    } }],
    ['missing platform version', { userAgentData: clientHints(undefined) }],
    ['malformed platform version', { userAgentData: clientHints('26.0.0-extra') }],
    ['version with trailing whitespace', { userAgentData: clientHints('27.0.0 ') }],
    ['non-string platform version', { userAgentData: clientHints(27) }],
    ['non-macOS desktop', { userAgentData: clientHints('26.0.0', { platform: 'Windows' }) }],
    ['mobile browser', { userAgentData: clientHints('27.0.0', { mobile: true }) }],
    ['old macOS version', { userAgentData: clientHints('25.0.0') }],
    ['future macOS version', { userAgentData: clientHints('28.0.0') }]
  ];
  for (const [name, navigator] of fallbackCases) {
    const requests = [];
    const fetch = standardFetch();
    const ui = page(url => {
      requests.push(url);
      return fetch(url);
    }, navigator);
    await flush();
    assert.equal(ui.ids.macosSelect.value, '', name);
    assert.equal(ui.ids.macosSelect.disabled, false, name);
    assert.match(ui.ids.detectionStatus.textContent, /Choose macOS 26 or 27.*install script/, name);
    assert.match(ui.ids.detectionStatus.textContent, /Apple menu → About This Mac/, name);
    assert.equal(ui.ids.releaseStatus.textContent, '', `${name}: avoid duplicate selection guidance`);
    assert.deepEqual(requests, [], name);
    assertZipUnavailable(ui, name);
  }

  for (const resetToBlank of [false, true]) {
    let finishDetection;
    const pendingDetection = new Promise(resolve => { finishDetection = resolve; });
    const navigator = { userAgentData: {
      ...clientHints('26.0.0'),
      getHighEntropyValues() { return pendingDetection; }
    } };
    const ui = page(standardFetch(), navigator);
    await flush();
    assert.equal(ui.ids.macosSelect.value, '');
    chooseMacos(ui, '27');
    if (resetToBlank) chooseMacos(ui, '');
    finishDetection({ platform: 'macOS', mobile: false, platformVersion: '26.0.0' });
    await flush();
    assert.equal(ui.ids.detectionStatus.textContent, '', 'a late detection leaves manual status intact');
    if (resetToBlank) {
      assert.equal(ui.ids.macosSelect.value, '', 'a late detection respects a return to the placeholder');
      assertZipUnavailable(ui);
    } else {
      assert.equal(ui.ids.macosSelect.value, '27', 'a late detection respects a manual choice');
      assert.equal(ui.ids.releaseTag.textContent, 'v1.1.10');
    }
  }
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

  const chooser = html.match(/<div class="compatibility-chooser\b[\s\S]*?<\/div>/);
  assert(chooser, 'macOS chooser is missing');
  assert.match(chooser[0], /<label for="macosSelect">/);
  assert.doesNotMatch(chooser[0], /<input\b/, 'there is no custom macOS field');
  const select = chooser[0].match(/<select\b[^>]*\bid="macosSelect"[^>]*>([\s\S]*?)<\/select>/);
  assert(select, 'macOS selector is missing');
  const options = Array.from(select[1].matchAll(/<option\b[^>]*>/g), ([option]) => option);
  const values = options.map(option => option.match(/\bvalue="([^"]*)"/)?.[1]);
  assert.deepEqual(values, ['', '26', '27'], 'macOS selector offers a placeholder and the two supported versions');
  assert(options.every(option => !/\bdisabled\b/.test(option)), 'all macOS selector options can be chosen');
  assert.match(select[0], /^<select\b[^>]*\bdisabled\b/, 'selector stays disabled without JavaScript');
  assert.match(select[0], /aria-describedby="[^"]*\bdetectionStatus\b/);
  const detectionStatus = chooser[0].match(/<p\b(?=[^>]*\bid="detectionStatus")[^>]*>/);
  assert(detectionStatus, 'detection status is missing');
  assert.match(detectionStatus[0], /\brole="status"/);
  assert.match(detectionStatus[0], /\baria-live="polite"/);
  assert.match(chooser[0], /ZIP downloads are for Apple Silicon Macs; automatic detection checks only macOS/);
  const noscript = html.match(/<noscript>([\s\S]*?)<\/noscript>/);
  assert(noscript, 'no-JavaScript instructions are missing');
  assert.match(noscript[1], /Homebrew checks compatibility on your Mac/);
  assert.match(noscript[1], /bash install\.sh/);
  assert(!/html\.js\s+\.reveal\s*\{[^}]*opacity:\s*0/s.test(styles), 'head bootstrap must not hide unrevealed content');
  assert.match(styles, /\.reveal\.in\s*\{[^}]*animation:\s*reveal-in/s, 'initialized reveal should retain its entrance animation');
  assert.match(styles, /@media\s*\(prefers-reduced-motion:\s*reduce\)[\s\S]*?\.reveal\.in\s*\{[^}]*animation:\s*none/s,
    'Reduced Motion must disable the reveal animation');

  const trustSummary = html.indexOf('class="trust-summary"');
  const firstRunnableCommand = html.indexOf('data-copy=');
  assert(trustSummary >= 0 && trustSummary < firstRunnableCommand, 'visible trust notice must precede the first runnable command');
  const summary = html.slice(trustSummary, html.indexOf('</aside>', trustSummary));
  assert.match(summary, /ad-hoc signed/);
  assert.match(summary, /not notarized by Apple/);
  assert.match(summary, /Homebrew and the install script clear/);
  assert.match(summary, /manual ZIP keeps the quarantine attribute/);
  assert.match(summary, /approving first launch saves a Gatekeeper exception/);
  assert.match(summary, /removing that attribute separately uses/);
  assert.match(summary, /local source build is not a quarantined download/);

  const panelText = id => {
    const start = html.indexOf(`id="${id}"`);
    const end = html.indexOf('<!--', start);
    assert(start >= 0 && end > start, `${id} panel is missing`);
    return html.slice(start, end);
  };
  assert.match(panelText('panel-homebrew'), /clears its download quarantine/);
  assert.match(panelText('panel-script'), /clears the quarantine/);
  assert.match(panelText('panel-release'), /retains its download quarantine/);
  assert.match(panelText('panel-release'), /Apple Silicon Macs can download/);
  assert.match(panelText('panel-release'), /First-launch approval saves a Gatekeeper exception/);
  assert.match(panelText('panel-release'), /remove the quarantine attribute separately/);
  assert.match(panelText('panel-source'), /without a download quarantine because it was built locally/);
  const securityNoticeStart = html.indexOf('<details class="notice reveal">');
  const securityNoticeEnd = html.indexOf('</details>', securityNoticeStart);
  const securityNotice = html.slice(securityNoticeStart, securityNoticeEnd);
  assert.match(securityNotice, /manual ZIP retains the quarantine attribute/);
  assert.match(securityNotice, /saves a Gatekeeper exception but does not remove that attribute/);
  assert.match(securityNotice, /to remove it, run the provided/);
  const staticDownloads = Array.from(html.matchAll(/<a\b(?=[^>]*\bdata-download(?:\s|=|>))[^>]*>/g), ([tag]) => tag);
  assert(staticDownloads.length > 0, 'ZIP download controls are missing');
  staticDownloads.forEach(tag => assert.doesNotMatch(tag, /\bhref\s*=/i, 'ZIP links must stay disabled without verification'));
  const sourceCommand = html.match(/<pre><code>(VERSION="[\s\S]*?)<\/code><\/pre>\s*<button class="cmd__copy" type="button" data-copy="([^"]+)"/);
  assert(sourceCommand, 'source tag command and copy control are missing');
  const decode = text => text.replace(/&quot;/g, '"').replace(/&amp;/g, '&');
  assert.equal(decode(sourceCommand[1]), decode(sourceCommand[2]), 'source tag copy differs from displayed command');
  assert.match(decode(sourceCommand[1]), /bash install\.sh --print-version/);
  assert.match(decode(sourceCommand[1]), /git clone --branch "v\$VERSION"/);

  const verificationBlocks = Array.from(html.matchAll(/<pre><code>([\s\S]*?)<\/code><\/pre>\s*<button class="cmd__copy"[^>]*data-copy="([^"]+)"/g))
    .filter(match => /\bls(?: -d)? (?:\/Applications|dist)\/AerialDrop\.app/.test(decode(match[1])));
  assert.equal(verificationBlocks.length, 4, 'each installation method has one bundle verification');
  verificationBlocks.forEach(match => {
    assert.equal(decode(match[1]), decode(match[2]), 'displayed verification and copied command agree');
    assert.match(decode(match[1]), /(?:^|&& )ls -d (?:\/Applications|dist)\/AerialDrop\.app$/);
  });
  ['panel-homebrew', 'panel-script', 'panel-release'].forEach(id => {
    assert.match(panelText(id), /Expected output: <code>\/Applications\/AerialDrop\.app<\/code>/);
    assert.match(panelText(id), /No such file or directory/);
  });
  assert.match(panelText('panel-source'), /Expected final line: <code>dist\/AerialDrop\.app<\/code>/);
  assert.match(panelText('panel-source'), /Packaging or launch errors stop the command before this check/);
  assert.match(panelText('panel-source'), /No such file or directory/);

  // Exercise only ls with isolated bundles; never execute installer/build/open commands.
  const verificationHome = fs.mkdtempSync(path.join(os.tmpdir(), 'aerialdrop-site-verify-'));
  try {
    const relativeBundle = 'dist/AerialDrop.app';
    const absoluteBundle = path.join(verificationHome, 'Applications/AerialDrop.app');
    fs.mkdirSync(path.join(verificationHome, relativeBundle, 'Contents'), { recursive: true });
    fs.mkdirSync(path.join(absoluteBundle, 'Contents'), { recursive: true });
    for (const target of [relativeBundle, absoluteBundle]) {
      const present = spawnSync('ls', ['-d', target], { cwd: verificationHome, encoding: 'utf8', env: { ...process.env, LC_ALL: 'C' } });
      assert.equal(present.status, 0);
      assert.equal(present.stdout.trim(), target, 'ls -d prints the bundle path rather than Contents');
      fs.rmSync(path.resolve(verificationHome, target), { recursive: true });
      const missing = spawnSync('ls', ['-d', target], { cwd: verificationHome, encoding: 'utf8', env: { ...process.env, LC_ALL: 'C' } });
      assert.notEqual(missing.status, 0);
      assert.equal(missing.stdout, '');
      assert.match(missing.stderr, /No such file or directory/);
    }
  } finally {
    fs.rmSync(verificationHome, { recursive: true, force: true });
  }

  await testMacosDetection();

  const ui = page(standardFetch());
  assertZipUnavailable(ui);
  await flush();
  chooseMacos(ui, '26');
  await flush();
  assert.equal(ui.ids.detectionStatus.textContent, '');
  assert.equal(ui.ids.releaseTag.textContent, 'v1.1.9');
  assert.equal(ui.ids.expectVersion.textContent, '1.1.9');
  assert.match(ui.ids.unzipCmd.textContent, /AerialDrop-1\.1\.9-macOS\.zip/);
  assert.equal(ui.ids.unzipCopy.getAttribute('data-copy'), ui.ids.unzipCmd.textContent);
  assert.equal(ui.ids.unzipCopy.disabled, false);
  assert.equal(ui.downloads[0].getAttribute('href'), fixture.catalogues.base[1].assets[0].browser_download_url);
  assert.match(ui.ids.termOut1.textContent, /1\.1\.9/);
  assert.match(ui.ids.termOut4.textContent, /1\.1\.9/);
  chooseMacos(ui, '27');
  assertZipUnavailable(ui, 'changing OS clears stale ZIP controls immediately');
  await flush();
  assert.equal(ui.ids.releaseTag.textContent, 'v1.1.10');
  assert.equal(ui.ids.expectVersion.textContent, '1.1.10');
  chooseMacos(ui, '');
  assertZipUnavailable(ui);
  assert.match(ui.ids.releaseStatus.textContent, /Choose your Mac/);
  assert.equal(ui.ids.expectVersion.textContent, 'Resolve on this Mac');

  const noMatch = page(standardFetch(fixture.policy, fixture.catalogues.empty));
  chooseMacos(noMatch, '26');
  await flush();
  assert.match(noMatch.ids.releaseStatus.textContent, /No compatible published release/);
  assertZipUnavailable(noMatch);

  const network = page(async url => url === 'release-compatibility.json' ? response(fixture.policy) : response({}, false, 503));
  chooseMacos(network, '26');
  await flush();
  assert.match(network.ids.releaseStatus.textContent, /Couldn’t verify/);
  assert.equal(network.ids.retryRelease.hidden, false);
  assertZipUnavailable(network);

  let policyRecovered = false, policyFetches = 0;
  const badPolicy = page(async url => {
    if (url === 'release-compatibility.json') {
      policyFetches++;
      return response(policyRecovered ? fixture.policy : { ...fixture.policy, schema_version: 2 });
    }
    return response(fixture.catalogues.base);
  });
  chooseMacos(badPolicy, '26');
  await flush();
  assert.match(badPolicy.ids.releaseStatus.textContent, /Couldn’t verify/);
  assertZipUnavailable(badPolicy);
  policyRecovered = true;
  badPolicy.ids.retryRelease.trigger('click');
  await flush();
  assert.equal(policyFetches, 2, 'retry refetches successfully fetched but invalid policy');
  assert.equal(badPolicy.ids.releaseTag.textContent, 'v1.1.9', 'retry recovers after invalid metadata is replaced');

  let finish;
  const pending = new Promise(resolve => { finish = resolve; });
  const race = page(async url => url === 'release-compatibility.json' ? response(fixture.policy) : pending);
  chooseMacos(race, '26');
  chooseMacos(race, '27');
  finish(response(fixture.catalogues.base));
  await flush();
  assert.equal(race.ids.releaseTag.textContent, 'v1.1.10', 'stale selection cannot overwrite newer selection');

  console.log(`Site compatibility: ${fixture.cases.length} shared cases, detection, manual choice, pagination, links, copy, empty, network, retry and races passed.`);
}

main().catch(error => { console.error(error); process.exitCode = 1; });
