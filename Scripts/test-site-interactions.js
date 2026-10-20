#!/usr/bin/env node
/* Execute shared production interactivity with a small DOM; Node built-ins only. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const compatibility = require('../docs/compatibility.js');
const source = fs.readFileSync(path.join(__dirname, '../docs/app.js'), 'utf8');
const styles = fs.readFileSync(path.join(__dirname, '../docs/styles.css'), 'utf8');
const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, '../Tests/DistributionFixtures/compatibility.json'), 'utf8'));

function page({ clipboard, legacy = false, fetcher } = {}) {
  const listeners = new Map();
  const statuses = [];
  let document, legacyCalls = 0;
  function element(textContent = '') {
    const attrs = new Map(), events = new Map(), classes = new Set();
    return {
      textContent, style: {}, hidden: false, disabled: false,
      classList: {
        add(...names) { names.forEach(name => classes.add(name)); },
        remove(...names) { names.forEach(name => classes.delete(name)); },
        contains(name) { return classes.has(name); },
        toggle(name, force) {
          const on = force === undefined ? !classes.has(name) : Boolean(force);
          if (on) classes.add(name); else classes.delete(name);
          return on;
        }
      },
      setAttribute(key, value) { attrs.set(key, String(value)); },
      getAttribute(key) { return attrs.get(key) || null; },
      addEventListener(key, callback) { events.set(key, callback); },
      fire(key, event = {}) { events.get(key)({ preventDefault() { event.prevented = true; }, ...event }); },
      removeAttribute(key) { attrs.delete(key); },
      focus() { document.activeElement = this; },
      select() { document.activeElement = this; },
      closest() { return this.scope || null; },
      insertAdjacentElement(position, status) { statuses.push(status); this.copyStatus = status; },
      getBoundingClientRect() { return this.bounds || { left: 0, right: 100 }; }
    };
  }
  const buttons = [element('Copy'), element('Copy')];
  buttons.forEach((button, i) => button.setAttribute('data-copy', 'command-' + i));
  const ids = Object.fromEntries([
    'macosSelect', 'customMacos', 'customMacosLabel', 'releaseStatus', 'retryRelease',
    'releaseTag', 'releaseSize', 'expectVersion', 'unzipCmd', 'unzipCopy', 'termOut1', 'termOut4'
  ].map(id => [id, element()]));
  ids.unzipCopy.setAttribute('data-copy', '');
  ids.unzipCopy.classList.remove('is-copied', 'is-failed');
  const navToggle = element('Menu');
  const navLinks = element();
  const navLink = element('Install');
  navLinks.querySelectorAll = selector => selector === 'a' ? [navLink] : [];
  const rail = element();
  rail.clientWidth = 320;
  rail.scrollWidth = 600;
  rail.scrollLeft = 0;
  rail.bounds = { left: 0, right: 320 };
  const methods = Array.from({ length: 4 }, (_, i) => {
    const tab = element();
    tab.setAttribute('data-tab', 'panel-' + i);
    tab.setAttribute('aria-selected', i === 0 ? 'true' : 'false');
    tab.getBoundingClientRect = () => ({ left: i * 150 - rail.scrollLeft, right: (i + 1) * 150 - rail.scrollLeft });
    return tab;
  });
  const panels = methods.map((_, i) => Object.assign(element(), { id: 'panel-' + i }));
  const installer = element();
  installer.querySelector = selector => selector === '.installer__rail' ? rail : null;
  installer.querySelectorAll = selector => selector === '.method' ? methods : selector === '.panel' ? panels : [];
  document = {
    activeElement: buttons[0],
    documentElement: { getAttribute() { return 'dark'; } },
    body: { appendChild() {}, removeChild() {} },
    createElement: () => element(),
    execCommand() { legacyCalls++; return legacy; },
    querySelector: selector => selector === '#installer' ? installer : selector === '#navToggle' ? navToggle : selector === '#navLinks' ? navLinks : selector.startsWith('#') ? ids[selector.slice(1)] || null : null,
    querySelectorAll: selector => selector === '.cmd__copy, .term-copy' ? [...buttons, ids.unzipCopy] : [],
    getElementById(id) { return ids[id] || null; }
  };
  const window = {
    matchMedia: () => ({ matches: true }),
    addEventListener: (name, callback) => listeners.set(name, callback),
    fetch: fetcher,
    AerialDropCompatibility: compatibility
  };
  vm.runInNewContext(source, { document, window, navigator: { clipboard }, fetch: fetcher, setTimeout() {}, clearTimeout() {} });
  return { ids, buttons, methods, panels, statuses, document, rail, navToggle, navLinks, navLink, legacyCalls: () => legacyCalls, resize: () => listeners.get('resize')() };
}
const flush = () => new Promise(resolve => setImmediate(resolve));
function deferred() { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; }
function response(data) { return { ok: true, json: async () => data }; }
function standardFetch(url) { return Promise.resolve(response(url === 'release-compatibility.json' ? fixture.policy : fixture.catalogues.base)); }

async function main() {
  const tabletRules = styles.slice(styles.indexOf('@media (max-width: 960px)'), styles.indexOf('@media (max-width: 720px)'));
  assert.match(tabletRules, /\.nav__links\s*\{[^}]*flex:\s*1 1 100%/s, 'navigation links get a wrapping fallback row without JavaScript');
  assert.doesNotMatch(tabletRules, /\.nav__links\s*\{[^}]*display:\s*none/s, 'navigation links stay visible without JavaScript');
  assert.match(tabletRules, /\.nav__toggle\.is-enhanced\s*\{\s*display:\s*flex/, 'menu toggle appears only after its handler initializes');
  assert.match(tabletRules, /\.nav__links\.is-collapsible\s*\{[^}]*display:\s*none/s, 'initialized navigation collapses at the tablet breakpoint');
  assert.match(tabletRules, /\.nav__links\.is-collapsible\.open\s*\{\s*display:\s*flex/, 'collapsed navigation remains available when opened');
  const pending = [];
  const ui = page({ clipboard: { writeText() { const result = deferred(); pending.push(result); return result.promise; } } });
  const [button, other] = ui.buttons;
  assert(ui.navToggle.classList.contains('is-enhanced'));
  assert(ui.navLinks.classList.contains('is-collapsible'));
  ui.navToggle.fire('click');
  assert(ui.navLinks.classList.contains('open'));
  assert.equal(ui.navToggle.getAttribute('aria-expanded'), 'true');
  ui.navLink.fire('click');
  assert(!ui.navLinks.classList.contains('open'));
  assert.equal(ui.navToggle.getAttribute('aria-expanded'), 'false');
  assert(ui.statuses.every(status => status.getAttribute('role') === 'status' && !status.textContent));
  assert.equal(button.getAttribute('aria-describedby'), ui.statuses[0].id);
  button.fire('click');
  pending[0].resolve();
  await flush();
  assert.equal(ui.statuses[0].textContent, 'Command copied.');
  assert.equal(button.textContent, 'Copy');
  assert.equal(ui.document.activeElement, button);
  button.fire('click');
  button.fire('click');
  pending[2].reject();
  await flush();
  const failure = ui.statuses[0].textContent;
  assert.match(failure, /Select the command text.*⌘C or Ctrl\+C/);
  pending[1].resolve();
  await flush();
  assert.equal(ui.statuses[0].textContent, failure, 'old success must not replace newer failure');
  button.fire('click');
  button.fire('click');
  pending[4].resolve();
  await flush();
  const beforeStaleFallback = ui.legacyCalls();
  pending[3].reject();
  await flush();
  assert.equal(ui.statuses[0].textContent, 'Command copied.', 'old failure must not run fallback or replace success');
  assert.equal(ui.legacyCalls(), beforeStaleFallback, 'stale rejection cannot touch clipboard or focus');
  other.fire('click');
  pending[5].reject();
  await flush();
  assert.equal(ui.statuses[0].textContent, 'Command copied.', 'other command feedback is scoped');
  assert.match(ui.statuses[1].textContent, /Couldn’t copy/);
  button.fire('click');
  button.setAttribute('data-copy', 'new-command');
  pending[6].resolve();
  await flush();
  assert.equal(ui.statuses[0].textContent, '', 'changed command invalidates pending outcome');

  button.fire('click');
  button.disabled = true;
  pending[7].resolve();
  await flush();
  assert.equal(ui.statuses[0].textContent, '', 'disabled command invalidates pending outcome');

  for (const legacy of [true, false]) {
    const fallback = page({ legacy });
    const originalFocus = fallback.buttons[1];
    originalFocus.focus();
    fallback.buttons[0].fire('click');
    assert.equal(fallback.document.activeElement, originalFocus, 'legacy copy restores existing focus');
    assert.match(fallback.statuses[0].textContent, legacy ? /Command copied/ : /copy it manually/);
  }
  const development = page({ legacy: true });
  const devButton = development.buttons[0];
  devButton.setAttribute('data-copy', '');
  devButton.parentElement = { querySelector() { return { innerText: 'swift build\n swift test' }; } };
  devButton.fire('click');
  assert.equal(development.statuses[0].textContent, 'Command copied.', 'development page commands use code text');

  const thrown = page({ clipboard: { writeText() { throw new Error('unavailable'); } }, legacy: true });
  thrown.buttons[0].fire('click');
  assert.equal(thrown.statuses[0].textContent, 'Command copied.', 'synchronous API failure falls back');

  for (const copySucceeds of [true, false]) {
    const releasePage = page({
      clipboard: { writeText() { return copySucceeds ? Promise.resolve() : Promise.reject(new Error('denied')); } },
      fetcher: standardFetch
    });
    const { ids } = releasePage;
    const zipCopy = ids.unzipCopy;
    ids.macosSelect.value = '26';
    ids.macosSelect.fire('change');
    await flush();
    assert.match(zipCopy.getAttribute('data-copy'), /AerialDrop-1\.1\.9-macOS\.zip/);
    zipCopy.fire('click');
    await flush();
    assert(copySucceeds ? zipCopy.classList.contains('is-copied') : zipCopy.classList.contains('is-failed'));
    assert.notEqual(zipCopy.copyStatus.textContent, '');

    ids.macosSelect.value = '27';
    ids.macosSelect.fire('change');
    assert.equal(zipCopy.disabled, true);
    assert.equal(zipCopy.copyStatus.textContent, '', 'changing release clears old copy feedback immediately');
    assert.equal(zipCopy.classList.contains('is-copied'), false);
    assert.equal(zipCopy.classList.contains('is-failed'), false);
    await flush();
    assert.match(zipCopy.getAttribute('data-copy'), /AerialDrop-1\.1\.10-macOS\.zip/);
    assert.equal(zipCopy.copyStatus.textContent, '', 'resolved release does not restore stale copy feedback');
  }

  const staleReleaseCopy = deferred();
  const pendingReleasePage = page({
    clipboard: { writeText() { return staleReleaseCopy.promise; } },
    fetcher: standardFetch
  });
  const pendingReleaseZipCopy = pendingReleasePage.ids.unzipCopy;
  pendingReleasePage.ids.macosSelect.value = '26';
  pendingReleasePage.ids.macosSelect.fire('change');
  await flush();
  pendingReleaseZipCopy.fire('click');
  pendingReleasePage.ids.macosSelect.value = '27';
  pendingReleasePage.ids.macosSelect.fire('change');
  assert.equal(pendingReleaseZipCopy.copyStatus.textContent, '', 'release change clears pending copy feedback');
  await flush();
  pendingReleasePage.ids.macosSelect.value = '26';
  pendingReleasePage.ids.macosSelect.fire('change');
  await flush();
  assert.match(pendingReleaseZipCopy.getAttribute('data-copy'), /AerialDrop-1\.1\.9-macOS\.zip/);
  staleReleaseCopy.resolve();
  await flush();
  assert.equal(pendingReleaseZipCopy.copyStatus.textContent, '', 'old pending copy cannot restore feedback after returning to its release');
  assert.equal(pendingReleaseZipCopy.classList.contains('is-copied'), false);

  function selected(index) {
    ui.methods.forEach((method, i) => {
      assert.equal(method.getAttribute('aria-selected'), i === index ? 'true' : 'false');
      assert.equal(method.getAttribute('tabindex'), i === index ? '0' : '-1');
      assert.equal(ui.panels[i].hidden, i !== index);
    });
    const bounds = ui.methods[index].getBoundingClientRect();
    assert(bounds.left >= 0 && bounds.right <= ui.rail.clientWidth, 'selected method remains visible in the rail');
  }
  selected(0);
  ui.methods[0].fire('keydown', { key: 'End' });
  selected(3);
  assert.equal(ui.document.activeElement, ui.methods[3]);
  ui.rail.clientWidth = 390;
  ui.rail.bounds.right = 390;
  ui.rail.scrollLeft = 0;
  ui.resize();
  selected(3);
  assert.equal(ui.document.activeElement, ui.methods[3], 'resize does not move focus');
  ui.methods[3].fire('keydown', { key: 'Home' });
  selected(0);
  assert.equal(ui.document.activeElement, ui.methods[0]);
  ui.methods[0].fire('keydown', { key: 'ArrowLeft' });
  selected(3);
  ui.methods[3].fire('keydown', { key: 'ArrowRight' });
  selected(0);
  ui.methods[2].fire('click');
  selected(2);
  console.log('Site interactions: clipboard outcomes/races/fallback focus and tab keyboard/resize visibility passed.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
