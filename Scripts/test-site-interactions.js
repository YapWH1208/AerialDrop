#!/usr/bin/env node
/* Execute shared production interactivity with a small DOM; Node built-ins only. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../docs/app.js'), 'utf8');
const styles = fs.readFileSync(path.join(__dirname, '../docs/styles.css'), 'utf8');

function page({ clipboard, legacy = false } = {}) {
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
        toggle(name, on) { if (on) classes.add(name); else classes.delete(name); }
      },
      setAttribute(key, value) { attrs.set(key, String(value)); },
      getAttribute(key) { return attrs.get(key) || null; },
      addEventListener(key, callback) { events.set(key, callback); },
      fire(key, event = {}) { events.get(key)({ preventDefault() { event.prevented = true; }, ...event }); },
      focus() { document.activeElement = this; },
      select() { document.activeElement = this; },
      closest() { return this.scope || null; },
      insertAdjacentElement(position, status) { statuses.push(status); },
      getBoundingClientRect() { return this.bounds || { left: 0, right: 100 }; }
    };
  }
  const buttons = [element('Copy'), element('Copy')];
  buttons.forEach((button, i) => button.setAttribute('data-copy', 'command-' + i));
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
    querySelector: selector => selector === '#installer' ? installer : null,
    querySelectorAll: selector => selector === '.cmd__copy, .term-copy' ? buttons : [],
    getElementById() { return null; }
  };
  const window = {
    matchMedia: () => ({ matches: true }),
    addEventListener: (name, callback) => listeners.set(name, callback)
  };
  vm.runInNewContext(source, { document, window, navigator: { clipboard }, setTimeout() {}, clearTimeout() {} });
  return { buttons, methods, panels, statuses, document, rail, legacyCalls: () => legacyCalls, resize: () => listeners.get('resize')() };
}
const flush = () => new Promise(resolve => setImmediate(resolve));
function deferred() { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; }

async function main() {
  const tabletRules = styles.slice(styles.indexOf('@media (max-width: 960px)'), styles.indexOf('@media (max-width: 720px)'));
  assert.match(tabletRules, /\.nav__toggle\s*\{\s*display:\s*flex/, 'navigation toggle must appear before links overflow tablet widths');
  assert.match(tabletRules, /\.nav__links\s*\{\s*display:\s*none/, 'full navigation collapses at the tablet breakpoint');
  assert.match(tabletRules, /\.nav__links\.open\s*\{\s*display:\s*flex/, 'collapsed navigation remains available when opened');
  const pending = [];
  const ui = page({ clipboard: { writeText() { const result = deferred(); pending.push(result); return result.promise; } } });
  const [button, other] = ui.buttons;
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
