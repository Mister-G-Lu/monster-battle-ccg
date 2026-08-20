#!/usr/bin/env node
/**
 * Regression tests for the game view around the campaign
 * (index.html / build/web/game.html).
 *
 * The page renders ONLY the game — no fake OS chrome. The fake Android
 * shell (phone frame, status bar, app bar, bottom nav, splash, gesture
 * pill) is gone; the campaign runs inside the real Android build's
 * service. What remains on the web is a slim in-game HUD (title + back
 * + menu) and a compact tab strip (Campaign / Deck / How to play).
 *
 * This file asserts that the fake chrome is gone, that the game HUD
 * reacts to navigation the way the game does, and that the installable
 * files (manifest + service worker + icons) are still present and
 * consistent. The campaign engine itself is covered by tests/campaign_sim.js.
 *
 * Usage: node tests/app_shell_test.js
 */
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..');
const HTML = path.join(ROOT, 'index.html');

const failures = [];
function assert(cond, msg) {
  if (cond) return;
  failures.push(msg);
  console.error('  FAIL: ' + msg);
}

// ---------------------------------------------------------------- fake DOM
function makeClassList(onChange) {
  const set = new Set();
  const api = {
    add: (...c) => { c.forEach(x => set.add(x)); onChange && onChange(set); },
    remove: (...c) => { c.forEach(x => set.delete(x)); onChange && onChange(set); },
    toggle: (c, force) => {
      if (force === undefined) { set.has(c) ? set.delete(c) : set.add(c); }
      else if (force) set.add(c); else set.delete(c);
      onChange && onChange(set);
    },
    contains: c => set.has(c),
    values: () => [...set],
  };
  return api;
}

function makeEl(tag) {
  const el = {
    tagName: (tag || 'div').toUpperCase(),
    children: [],
    style: {},
    dataset: {},
    classList: makeClassList(),
    textContent: '',
    title: '',
    src: '',
    hidden: false,
    disabled: false,
    scrollTop: 0,
    scrollHeight: 0,
    onclick: null,
    appendChild(ch) { this.children.push(ch); return ch; },
    after() {},
  };
  let html = '';
  Object.defineProperty(el, 'innerHTML', {
    get: () => html,
    set: v => { html = String(v); if (html === '') el.children = []; },
  });
  return el;
}

const elCache = new Map();
function $(id) { if (!elCache.has(id)) elCache.set(id, makeEl('div')); return elCache.get(id); }

const screenIds = ['world', 'battle'];
global.document = {
  head: makeEl('head'),
  body: makeEl('body'),
  getElementById: $,
  createElement: makeEl,
  querySelectorAll(sel) { return sel === '.screen' ? screenIds.map($) : []; },
};
global.localStorage = {
  _s: new Map(),
  getItem(k) { return this._s.has(k) ? this._s.get(k) : null; },
  setItem(k, v) { this._s.set(k, String(v)); },
  removeItem(k) { this._s.delete(k); },
};
const listeners = {};
global.window = {
  addEventListener: (ev, fn) => { (listeners[ev] = listeners[ev] || []).push(fn); },
  setInterval: () => 0,
  setTimeout: (fn) => { fn(); return 0; },
  history: { pushState() {} },
};
// Node 22 exposes a read-only global navigator; the page only reads
// navigator.serviceWorker, so shadow it non-destructively.
Object.defineProperty(global, 'navigator', { value: {}, configurable: true, writable: true });
global.history = global.window.history;
global.location = { pathname: '/index.html', protocol: 'file:' };
global.setTimeout = (fn) => { if (typeof fn === 'function') fn(); return 0; };
global.clearTimeout = () => {};
global.setInterval = () => 0;

// ---------------------------------------------------------------- load page
const html = fs.readFileSync(HTML, 'utf8');
const start = html.indexOf('<script>') + '<script>'.length;
const end = html.lastIndexOf('</script>');
if (start < 8 || end < 0) { console.error('FATAL: could not extract <script> from index.html'); process.exit(1); }
vm.runInThisContext(html.slice(start, end), { filename: 'index.html-inline.js' });

vm.runInThisContext(
  'globalThis.__shell = { get battle(){return battle;}, set battle(v){battle=v;},' +
  ' get save(){return save;}, set save(v){save=v;}, ALL_NODES, NODE_BY_ID,' +
  ' showScreen, navTo, setChrome, appBack, openMenu, toast, promptInstall,' +
  ' openOverlay, closeOverlay, startBattle, defaultSave, updateWorldStats };',
  { filename: 'shell-bridge.js' }
);
const S = globalThis.__shell;

console.log('== app_shell_test: ' + path.relative(ROOT, HTML) + ' ==');

// ---------------------------------------------------------------- markup
{
  const markup = html.slice(0, html.indexOf('<script>'));
  // the game's own chrome is present...
  for (const id of ['game-hud', 'hud-title', 'hud-sub', 'hud-back', 'hud-menu',
                    'app-body', 'game-tabs', 'tab-campaign', 'tab-deck', 'tab-help',
                    'deck-badge', 'hero-art', 'progress-fill', 'help-overlay', 'menu-overlay']) {
    assert(markup.includes(`id="${id}"`), `game HUD markup is missing #${id}`);
  }
  // ...and the fake Android OS chrome is gone
  for (const id of ['device', 'device-screen', 'sysbar', 'appbar', 'bottomnav',
                    'nav-campaign', 'nav-deck', 'nav-help', 'splash', 'navpill', 'stage']) {
    assert(!markup.includes(`id="${id}"`), `fake OS chrome #${id} must be removed`);
  }
  assert(!markup.includes('class="stage"'), 'the phone-frame stage must be gone');
  assert(markup.includes('rel="manifest"'), 'page must link a web app manifest');
  assert(markup.includes('name="theme-color"'), 'page must set a theme-color for the system bars');
  assert(markup.includes('viewport-fit=cover'), 'viewport must opt into the display cutout / safe areas');
  assert(/display-mode:\s*standalone/.test(markup), 'CSS must adapt to the installed standalone display mode');
  assert(markup.includes('safe-area-inset-bottom'), 'HUD must respect the bottom safe-area inset');
  assert(markup.includes('100dvh'), 'page must use dynamic viewport height so mobile chrome does not clip');
  assert(markup.includes('orientation: landscape'), 'CSS must compact the battle chrome in landscape');
  assert(markup.includes('touch-action: pan-x pan-y'), 'page must allow pan/drag when content still overflows');
  // the campaign engine script must stay the FIRST bare <script> (campaign_sim.js slices on it)
  assert(html.indexOf('<script>') > markup.indexOf('<script data-shell-icons>'),
         'the head bootstrap must not be a bare <script> before the game script');
}

// ---------------------------------------------------------------- HUD
{
  S.save = S.defaultSave();
  S.battle = null;
  S.showScreen('world');
  assert($('hud-title').textContent === 'The Shadow Road', 'HUD shows the campaign title on the map');
  assert($('hud-back').hidden === true, 'no back button on the top-level campaign screen');
  assert($('game-tabs').classList.contains('hidden') === false, 'tab strip is visible on the campaign screen');
  assert($('tab-campaign').classList.contains('active'), 'Campaign tab is selected on the map');

  S.startBattle(S.NODE_BY_ID['w1']);
  assert($('hud-title').textContent === 'Forest Trail', 'HUD retitles to the encounter during battle');
  assert($('hud-sub').textContent.startsWith('vs '), 'HUD subtitle names the opponent');
  assert($('hud-back').hidden === false, 'battle screen exposes the back affordance');
  assert($('game-tabs').classList.contains('hidden'), 'tab strip is hidden during a battle (immersive)');
  assert($('game-hud').classList.contains('battle-mode'), 'HUD switches to its battle treatment');

  S.battle = null;
  S.showScreen('world');
  assert($('game-tabs').classList.contains('hidden') === false, 'tab strip returns after the battle');
}

// ---------------------------------------------------------------- navigation
{
  S.navTo('deck');
  assert($('deck-overlay').classList.contains('active'), 'Deck tab opens the deck panel');
  assert($('tab-deck').classList.contains('active'), 'Deck tab is selected while its panel is open');

  assert(S.appBack() === true, 'back closes the open panel');
  assert($('deck-overlay').classList.contains('active') === false, 'deck panel closed by back');
  assert($('tab-campaign').classList.contains('active'), 'closing a panel reselects Campaign');

  S.navTo('help');
  assert($('help-overlay').classList.contains('active'), 'How to play tab opens the help panel');
  S.closeOverlay('help-overlay');

  S.openMenu();
  assert($('menu-overlay').classList.contains('active'), 'overflow menu opens');
  S.appBack();
  assert($('menu-overlay').classList.contains('active') === false, 'back dismisses the overflow menu');

  // back with nothing open and no battle: the shell reports "not handled"
  S.battle = null;
  assert(S.appBack() === false, 'back is a no-op on the root screen with no panels open');

  // back during a battle retreats rather than stranding the player
  S.startBattle(S.NODE_BY_ID['w1']);
  S.closeOverlay('result-overlay');
  assert(S.appBack() === true, 'back during a battle is handled (retreat)');
  S.battle = null;
  S.closeOverlay('result-overlay');
}

// ---------------------------------------------------------------- widgets
{
  S.save = S.defaultSave();
  S.showScreen('world');
  assert($('stat-progress').textContent === 0 || $('stat-progress').textContent === '0' || $('stat-progress').textContent === 0,
         'progress card starts at zero cleared nodes');
  assert($('stat-progress-total').textContent === S.ALL_NODES.length,
         'progress total is derived from the campaign data, not hard-coded');
  assert($('progress-fill').style.width === '0%', 'progress bar starts empty');
  assert($('progress-next').textContent.startsWith('Next: '), 'progress card names the next encounter');
  assert(String($('deck-badge').textContent) === String(S.save.collection.length),
         'Deck tab badge counts the collection');

  S.save.cleared[S.ALL_NODES[0].id] = true;
  S.showScreen('world');
  assert($('progress-fill').style.width !== '0%', 'progress bar advances as nodes are cleared');

  S.toast('hello');
  const bar = $('snackbar');
  assert(bar.textContent === 'hello' || elCache.get('snackbar').textContent === 'hello', 'snackbar shows a message');

  S.promptInstall();  // no deferred event in this environment: must not throw
}

// ---------------------------------------------------------------- PWA files
{
  const pairs = [
    { dir: ROOT, manifest: 'manifest.webmanifest', sw: 'sw.js', prefix: 'build/web/assets/' },
    { dir: path.join(ROOT, 'build', 'web'), manifest: 'manifest.webmanifest', sw: 'sw.js', prefix: 'assets/' },
  ];
  for (const p of pairs) {
    const mPath = path.join(p.dir, p.manifest);
    const swPath = path.join(p.dir, p.sw);
    assert(fs.existsSync(mPath), `${path.relative(ROOT, mPath)} must exist`);
    assert(fs.existsSync(swPath), `${path.relative(ROOT, swPath)} must exist`);
    if (!fs.existsSync(mPath)) continue;

    const m = JSON.parse(fs.readFileSync(mPath, 'utf8'));
    assert(m.display === 'standalone', `${p.manifest}: display must be standalone for an app-like launch`);
    assert(!!m.name && !!m.short_name, `${p.manifest}: needs name + short_name`);
    assert(!!m.theme_color && !!m.background_color, `${p.manifest}: needs theme + background colors`);
    assert(m.icons.some(i => i.purpose === 'maskable'),
           `${p.manifest}: needs a maskable icon (Android adaptive launcher icon)`);
    assert(m.icons.some(i => i.sizes === '512x512'), `${p.manifest}: needs a 512px icon`);
    for (const icon of m.icons) {
      assert(icon.src.startsWith(p.prefix), `${p.manifest}: icon ${icon.src} must resolve from this copy's directory`);
      const iconPath = path.join(p.dir, icon.src);
      assert(fs.existsSync(iconPath), `${p.manifest}: missing icon file ${icon.src}`);
    }
  }
}

console.log('');
if (failures.length) { console.error(`APP SHELL TEST FAILED — ${failures.length} failure(s)`); process.exit(1); }
console.log('APP SHELL TEST PASSED');
