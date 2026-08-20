#!/usr/bin/env node
/**
 * Headless simulation of the web prototype's handcrafted campaign
 * (build/web/game.html). Loads the page's real JavaScript with a stubbed
 * DOM, then plays the campaign over and over with a greedy strategy to
 * verify the engine and report per-node difficulty.
 *
 * Usage: node tests/campaign_sim.js [runs]
 */
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..');
const HTML = path.join(ROOT, 'build', 'web', 'game.html');

// ---------------------------------------------------------------- fake DOM
function makeClassList() {
  const set = new Set();
  return {
    add: (...c) => c.forEach(x => set.add(x)),
    remove: (...c) => c.forEach(x => set.delete(x)),
    toggle: (c, force) => { if (force === undefined) { set.has(c) ? set.delete(c) : set.add(c); } else if (force) set.add(c); else set.delete(c); },
    contains: c => set.has(c),
  };
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
    disabled: false,
    scrollTop: 0,
    scrollHeight: 0,
    onclick: null,
    appendChild(ch) { this.children.push(ch); return ch; },
    after(...nodes) { // DOM ChildNode.after — insert siblings (stub: no-op bookkeeping)
      for (const n of nodes) if (n && typeof n === 'object') n.__insertedViaAfter = true;
    },
  };
  let html = '';
  Object.defineProperty(el, 'innerHTML', {
    get: () => html,
    set: (v) => { html = String(v); if (html === '') el.children = []; }, // like a browser: '' drops the subtree
  });
  return el;
}
const elCache = new Map();
global.document = {
  getElementById(id) { if (!elCache.has(id)) elCache.set(id, makeEl('div')); return elCache.get(id); },
  createElement(tag) { return makeEl(tag); },
  querySelectorAll() { return []; },
};
global.localStorage = {
  _s: new Map(),
  getItem(k) { return this._s.has(k) ? this._s.get(k) : null; },
  setItem(k, v) { this._s.set(k, String(v)); },
  removeItem(k) { this._s.delete(k); },
};

// ---------------------------------------------------------------- load page
const html = fs.readFileSync(HTML, 'utf8');
const start = html.indexOf('<script>') + '<script>'.length;
const end = html.lastIndexOf('</script>');
if (start < 8 || end < 0) { console.error('FATAL: could not extract <script> from game.html'); process.exit(1); }
const script = html.slice(start, end);

vm.runInThisContext(script, { filename: 'game.html-inline.js' });

// expose module-level let bindings + direct function refs once
// (function declarations attach to globalThis; calling them directly avoids
// re-compiling a tiny script per simulated action, which OOMs over many runs)
vm.runInThisContext(
  'globalThis.__dbg = { get battle(){return battle;}, set battle(v){battle=v;},' +
  ' get save(){return save;}, set save(v){save=v;}, ALL_NODES, NODE_BY_ID, REGIONS, TOKENS,' +
  ' startBattle, deployCard, attackWith, endTurn, openReward, pickReward,' +
  ' loadSave, defaultSave, currentNodeId, get rewardOffers(){return rewardOffers;} };',
  { filename: 'debug-bridge.js' }
);
const D = globalThis.__dbg;

// ---------------------------------------------------------------- helpers
const failures = [];
function assert(cond, msg) {
  if (!cond) { failures.push(msg); console.error('  FAIL: ' + msg); }
}

function freshSave() {
  D.save = D.loadSave();
  global.localStorage.removeItem('mbccg_campaign_v1');
  D.save = D.defaultSave();
  D.battle = null;
}

function logText() {
  const el = elCache.get('battle-log');
  return (el.children || []).map(c => c.textContent).join('\n');
}

/** Greedy player: deploy best affordable creatures, attack with everything, end turn. */
function playOutBattle(maxRounds = 60) {
  let safety = 0;
  while (D.battle && !D.battle.isOver && safety++ < 400) {
    // deploy phase: keep deploying the best affordable card while a slot is free
    let deployed = true;
    while (deployed) {
      deployed = false;
      const b = D.battle;
      if (!b || b.isOver) break;
      const slot = b.playerField.findIndex(s => s === null);
      if (slot === -1) break;
      let best = -1, bestScore = -1;
      b.playerHand.forEach((c, i) => {
        if (c.cost <= b.playerCrystal) {
          const score = (c.attack || 1) * 2 + c.hp;
          if (score > bestScore) { bestScore = score; best = i; }
        }
      });
      if (best === -1) break;
      deployed = D.deployCard(best);
    }
    // attack phase: swing with everything that can
    for (let i = 0; i < 3; i++) {
      const c = D.battle && D.battle.playerField[i];
      if (c && c.canAttack && c.currentHp > 0) D.attackWith(i);
      if (!D.battle || D.battle.isOver) break;
    }
    if (!D.battle || D.battle.isOver) break;
    if (D.battle.round > maxRounds) throw new Error('battle exceeded round cap: ' + D.battle.round);
    D.endTurn();
  }
  if (!D.battle || !D.battle.isOver) throw new Error('battle never ended');
  return { won: D.battle.winner === 'player', rounds: D.battle.round, log: logText() };
}

/** Attempt a node until won (mirrors retries); returns attempts + log of the winning battle. */
function beatNode(nodeId, maxAttempts = 12) {
  let last = null;
  for (let a = 1; a <= maxAttempts; a++) {
    D.battle = null; D.startBattle(D.NODE_BY_ID[nodeId]);
    last = playOutBattle();
    if (last.won) {
      // claim reward like a real player: open draft, take the sharpest offer
      const before = D.save.collection.length;
      D.openReward(D.battle.node);
      const offers = D.rewardOffers;
      const pick = offers.reduce((bi, c, i) => (c.attack > offers[bi].attack ? i : bi), 0);
      D.pickReward(pick);
      assert(D.save.collection.length === before + 1, `reward draft should add exactly 1 card (${nodeId}, attempt ${a})`);
      return { attempts: a, ...last };
    }
    // defeat: reset overlays implicitly; startBattle next loop
  }
  return { attempts: maxAttempts, won: false, ...last };
}

// ---------------------------------------------------------------- tests
console.log('== campaign_sim: loading ' + path.relative(ROOT, HTML) + ' ==');

// 1) boot sanity + UI-path smoke (intro modal, map re-render, deck view)
freshSave();
assert(D.save.collection.length === 21, 'starter collection has 21 cards (16 monsters + 5 items)');
assert(D.currentNodeId() === 'w1', 'first current node is w1');
assert(typeof globalThis.openIntro === 'function', 'page functions are reachable on globalThis');
globalThis.openIntro('w1');       // exercises previewDeckNames + chip rendering
globalThis.openIntro('w5');       // boss intro renders the Gathering Power card
globalThis.renderCampaign();      // idempotent re-render
globalThis.updateWorldStats();
globalThis.openDeck();            // deck view builds from the collection
globalThis.closeOverlay('deck-overlay');

// 2) one attack per creature per turn (regression: no multi-strike trades)
D.battle = null; D.startBattle(D.NODE_BY_ID['w2']);
{
  const b = D.battle;
  // force a scenario: put a ready creature on both sides of lane 0
  b.playerHand = [{ id: 110011, type: 'monster', cost: 2, currentHp: 4, hp: 4, attack: 2, canAttack: true, name: 'Triglodite', kind: 'war', powers: [{name:'melee',value:2}] }];
  b.playerField = [null, null, null];
  b.enemyField = [{ id: 140021, type: 'monster', cost: 2, currentHp: 4, hp: 4, attack: 2, canAttack: false, name: 'Mushrhum', kind: 'nature', powers: [{name:'melee',value:2}] }, null, null];
  b.playerCrystal = 10;
  D.deployCard(0);
  assert(b.playerField[0].canAttack === false, 'deployed creature has summoning sickness');
  b.playerField[0].canAttack = true;
  D.attackWith(0);
  assert(b.playerField[0] === null || b.playerField[0].canAttack === false, 'creature cannot attack twice in one turn');
}

// 3) full campaign × N runs: stats + assertions
const RUNS = parseInt(process.argv[2] || '40', 10);
const stats = {}; // nodeId -> {wins, attempts, rounds, powerSeen}
for (const n of D.ALL_NODES) stats[n.id] = { name: n.name, type: n.type, wins: 0, attempts: 0, rounds: 0, wonFirstTry: 0, powerHits: 0, gatherHits: 0 };

let completedRuns = 0;
for (let run = 0; run < RUNS; run++) {
  freshSave();
  let ok = true;
  for (const node of D.ALL_NODES) {
    const res = beatNode(node.id);
    const s = stats[node.id];
    if (res.won) {
      s.wins++; s.attempts += res.attempts; s.rounds += res.rounds;
      if (res.attempts === 1) s.wonFirstTry++;
      if (node.power) {
        const sig = { muster: 'Muster', plunder: 'Plunder', bloodlust: 'Bloodlust', warding: 'Warding',
                      overgrowth: 'Overgrowth', hunger: 'Hungering Dark', flamewave: 'Molten Core', toll: 'Umbral Toll' }[node.power.id];
        if (sig && res.log.includes(sig)) s.powerHits++;
      if (node.type === 'boss' && res.log.includes('GATHERS POWER')) s.gatherHits++;
      }
    } else { ok = false; break; }
  }
  if (ok) completedRuns++;
}

console.log(`\n== ${RUNS} simulated campaigns (greedy player, retries allowed) ==`);
console.log(`${completedRuns}/${RUNS} completed the full road\n`);
console.log('node  name                 type      1st-try%  avg tries  avg rounds  power fired');
for (const node of D.ALL_NODES) {
  const s = stats[node.id];
  const n = Math.max(1, s.wins);
  console.log(
    String(node.id).padEnd(6) + String(s.name).padEnd(21) + String(s.type).padEnd(10) +
    String(Math.round(100 * s.wonFirstTry / RUNS) + '%').padStart(8) +
    String((s.attempts / n).toFixed(2)).padStart(10) +
    String((s.rounds / n).toFixed(1)).padStart(12) +
    (node.power ? String(Math.round(100 * s.powerHits / Math.max(1, s.wins)) + '%').padStart(12) : '           —')
  );
}

// difficulty expectations: early nodes easy, bosses hard but beatable
assert(stats.w1.wonFirstTry / RUNS >= 0.90, 'w1 should be near-auto win for a greedy player (got ' + (100 * stats.w1.wonFirstTry / RUNS) + '%)');
for (const id of ['w5', 'c5', 'e5', 's4']) {
  assert(stats[id].wins > 0, id + ' should be beatable with retries (greedy player)');
  assert(stats[id].wins >= RUNS * 0.5, id + ' win-with-retries rate too low: ' + stats[id].wins + '/' + RUNS);
  assert(stats[id].powerHits > 0, id + ' boss power never fired in simulation');
  assert(stats[id].gatherHits > 0, id + ' Gathering Power never fired in simulation');
  // a boss the greedy player never loses to is a boss with no teeth
  assert(stats[id].wonFirstTry <= RUNS * 0.92, id + ' first-try rate too high (boss is trivial): ' + (100 * stats[id].wonFirstTry / RUNS) + '%');
}
// elites stay a real step up from skirmishes but must stay farmable
for (const id of ['w4', 'c4', 'e4', 's3']) {
  assert(stats[id].wins >= RUNS * 0.5, id + ' elite win-with-retries rate too low: ' + stats[id].wins + '/' + RUNS);
}

// 4) save/load round trip
freshSave();
D.battle = null; D.startBattle(D.NODE_BY_ID['w1']);
const r = playOutBattle();
assert(r.won, 'w1 win for save test');
D.openReward(D.battle.node); D.pickReward(0);
assert(D.save.collection.length === 22, 'reward card added to collection (started with 21, now 22)');
const snap = JSON.parse(JSON.stringify(D.save));
D.save = D.loadSave();
assert(JSON.stringify(D.save) === JSON.stringify(snap), 'save round-trips through localStorage');
assert(D.save.cleared.w1 === true, 'cleared node persists');
assert(D.save.collection.length > 16, 'reward card persisted');

// 5) node gating: only the current node chain is playable
freshSave();
assert(D.currentNodeId() === 'w1', 'fresh campaign starts at w1');
D.save.cleared.w1 = true; D.save.cleared.w2 = true;
assert(D.currentNodeId() === 'w3', 'clearing w1+w2 advances to w3');

console.log('');
if (failures.length) { console.error(`CAMPAIGN SIM FAILED — ${failures.length} failure(s)`); process.exit(1); }
console.log('CAMPAIGN SIM PASSED');
