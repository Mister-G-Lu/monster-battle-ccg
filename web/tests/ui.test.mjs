import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { UI } from '../src/ui.js';

// Minimal DOM so ui.js can run under node --test (no jsdom).
class FakeNode {
  constructor(tag) {
    this.tagName = String(tag).toUpperCase();
    this.children = [];
    this._class = '';
    this._text = '';
    this.style = {};
    this.disabled = false;
    this.onclick = null;
    this.dataset = {};
    const self = this;
    this.classList = {
      add(...xs) {
        for (const x of xs) {
          const parts = self._class.split(/\s+/).filter(Boolean);
          if (!parts.includes(x)) parts.push(x);
          self._class = parts.join(' ');
        }
      },
      contains(x) {
        return self._class.split(/\s+/).includes(x);
      },
    };
  }
  get className() { return this._class; }
  set className(v) { this._class = v || ''; }
  get textContent() {
    return this._text + this.children.map((c) => c.textContent).join('');
  }
  set textContent(v) {
    this._text = v == null ? '' : String(v);
    this.children = [];
  }
  set innerHTML(v) {
    if (v === '') {
      this.children = [];
      this._text = '';
    }
  }
  appendChild(n) {
    this.children.push(n);
    return n;
  }
}

function installDom() {
  globalThis.document = {
    createElement: (tag) => new FakeNode(tag),
  };
}

function find(node, pred, hits = []) {
  if (pred(node)) hits.push(node);
  for (const c of node.children) find(c, pred, hits);
  return hits;
}

function emptyActor() {
  return {
    crystal: 0,
    is_sacrifice: false,
    deck_left: 4,
    hand: [null, null, null, null],
    board: [null, null, null],
  };
}

const OFFERS = [
  { id: 140051, name: 'Oak Guard', type: 'monster', cost: 2, hp: 6, kind: 'nature', attack: 2 },
  { id: 140061, name: 'Vine Whip', type: 'monster', cost: 3, hp: 5, kind: 'nature', attack: 3 },
  { id: 21001, name: 'Bark Plate', type: 'armor', cost: 1, hp: 0, kind: 'nature', attack: 0 },
];

function mockEngine(overrides = {}) {
  const state = {
    info: {
      regions: [{
        id: 'woods', name: 'Whispering Woods', kind: 'nature',
        nodes: [
          { id: 'w1', name: 'Forest Trail', type: 'skirmish', playable: true, cleared: true, hp: 14 },
          { id: 'w2', name: 'Deep Thicket', type: 'skirmish', playable: true, cleared: false, hp: 16 },
        ],
      }],
      vitality: 30, wins: 1, losses: 0, bosses_slain: 0,
      complete: false, pending_recruit: 'w1', collection_size: 12,
    },
    battle: {
      is_over: true, winner: 'player', round: 5,
      own_hp: 20, own_max_hp: 30, enemy_hp: 0, enemy_max_hp: 14,
      own: emptyActor(), enemy: emptyActor(),
    },
    offers: OFFERS.slice(),
    recruited: null,
    skipped: false,
    startCalls: [],
  };
  const engine = {
    campaignInfo: () => state.info,
    battleState: () => state.battle,
    recruitOffers: (id) => {
      engine.lastOffersNode = id;
      return state.offers;
    },
    recruit: (nid, cid) => {
      state.recruited = { nid, cid };
      state.info.pending_recruit = null;
      state.info.collection_size += 1;
      return true;
    },
    skipRecruit: () => {
      state.skipped = true;
      state.info.pending_recruit = null;
    },
    startBattle: (id) => {
      state.startCalls.push(id);
      return true;
    },
    playCard: () => false,
    sacrifice: () => {},
    endTurn: () => {},
    _state: state,
    ...overrides,
  };
  return engine;
}

describe('campaign map and recruit-draft UI', () => {
  let root;
  beforeEach(() => {
    installDom();
    root = new FakeNode('div');
  });

  it('renders a playable Adventure road and starts its selected encounter', () => {
    const engine = mockEngine();
    engine._state.info.pending_recruit = null;
    const ui = new UI(root, engine);
    ui.screen = 'campaign';
    ui.render();

    assert.match(root.textContent, /The Shadow Road/);
    assert.match(root.textContent, /Whispering Woods/);
    assert.match(root.textContent, /Forest Trail/);
    assert.match(root.textContent, /Deep Thicket/);
    const nodes = find(root, (n) => n.classList.contains('node'));
    assert.equal(nodes.length, 2);
    assert.equal(nodes[0].disabled, false);
    assert.equal(nodes[1].disabled, false);

    nodes[1].onclick();
    assert.deepEqual(engine._state.startCalls, ['w2']);
    assert.equal(ui.screen, 'battle');
    assert.match(root.textContent, /Victory/);
  });

  it('returns to the populated Adventure road after a post-battle result', () => {
    const engine = mockEngine();
    engine._state.info.pending_recruit = null;
    const ui = new UI(root, engine);
    ui.screen = 'battle';
    ui.activeNode = { id: 'w1', name: 'Forest Trail' };
    ui.render();

    const back = find(root, (n) => n.tagName === 'BUTTON' && /Return to the Road/.test(n.textContent))[0];
    assert.ok(back);
    back.onclick();

    assert.equal(ui.screen, 'campaign');
    assert.match(root.textContent, /Whispering Woods/);
    assert.equal(find(root, (n) => n.classList.contains('node')).length, 2);
  });

  it('shows the 3-card draft after a first-clear victory (does not auto-skip)', () => {
    const engine = mockEngine();
    const ui = new UI(root, engine);
    ui.screen = 'battle';
    ui.activeNode = { id: 'w1', name: 'Forest Trail' };
    ui.render();

    assert.match(root.textContent, /New recruit/);
    assert.match(root.textContent, /Oak Guard/);
    assert.match(root.textContent, /Vine Whip/);
    assert.match(root.textContent, /Bark Plate/);
    assert.match(root.textContent, /Skip \(\+15 EXP\)/);
    assert.equal(engine._state.skipped, false);
    assert.equal(engine.lastOffersNode, 'w1');
    const cards = find(root, (n) => n.classList.contains('recruit-card'));
    assert.equal(cards.length, 3);
    assert.equal(cards[0].dataset.cardId, '140051');
  });

  it('picking a card calls recruit and returns to the map with a bigger deck', () => {
    const engine = mockEngine();
    const ui = new UI(root, engine);
    ui.screen = 'battle';
    ui.activeNode = { id: 'w1' };
    ui.render();

    const oak = find(root, (n) => n.classList.contains('recruit-card'))[0];
    oak.onclick();

    assert.deepEqual(engine._state.recruited, { nid: 'w1', cid: 140051 });
    assert.equal(engine._state.skipped, false);
    assert.match(root.textContent, /The Shadow Road/);
    assert.match(root.textContent, /Deck 13/);
    assert.doesNotMatch(root.textContent, /New recruit/);
  });

  it('Skip takes +15 EXP instead of a card', () => {
    const engine = mockEngine();
    const ui = new UI(root, engine);
    ui.screen = 'battle';
    ui.activeNode = { id: 'w1' };
    ui.render();

    const skip = find(root, (n) => n.classList.contains('skip-recruit'))[0];
    skip.onclick();

    assert.equal(engine._state.skipped, true);
    assert.equal(engine._state.recruited, null);
    assert.match(root.textContent, /The Shadow Road/);
    assert.doesNotMatch(root.textContent, /New recruit/);
  });

  it('does not open a draft on defeat, and Return does not skip a recruit', () => {
    const engine = mockEngine();
    engine._state.battle.winner = 'enemy';
    engine._state.battle.own_hp = 0;
    engine._state.info.pending_recruit = null;
    const ui = new UI(root, engine);
    ui.screen = 'battle';
    ui.activeNode = { id: 'w1' };
    ui.render();

    assert.match(root.textContent, /Defeat/);
    assert.doesNotMatch(root.textContent, /New recruit/);
    const back = find(root, (n) => n.tagName === 'BUTTON' && /Return to the Road/.test(n.textContent))[0];
    assert.ok(back);
    back.onclick();
    assert.equal(engine._state.skipped, false);
  });

  it('does not open a draft on a replay victory (no pending recruit)', () => {
    const engine = mockEngine();
    engine._state.info.pending_recruit = null;
    const ui = new UI(root, engine);
    ui.screen = 'battle';
    ui.activeNode = { id: 'w1' };
    ui.render();

    assert.match(root.textContent, /Victory/);
    assert.doesNotMatch(root.textContent, /New recruit/);
    const back = find(root, (n) => n.tagName === 'BUTTON' && /Return to the Road/.test(n.textContent))[0];
    back.onclick();
    assert.equal(engine._state.skipped, false);
  });

  it('opens the draft from the campaign map when a recruit is still pending', () => {
    const engine = mockEngine();
    const ui = new UI(root, engine);
    ui.screen = 'campaign';
    ui.render();

    assert.match(root.textContent, /New recruit/);
    assert.match(root.textContent, /Oak Guard/);
    assert.equal(engine.lastOffersNode, 'w1');
  });

  it('empty offers still offer a Continue path that skips', () => {
    const engine = mockEngine();
    engine._state.offers = [];
    const ui = new UI(root, engine);
    ui.screen = 'battle';
    ui.activeNode = { id: 'w1' };
    ui.render();

    assert.match(root.textContent, /No recruits available/);
    const cont = find(root, (n) => n.tagName === 'BUTTON' && /Continue/.test(n.textContent))[0];
    cont.onclick();
    assert.equal(engine._state.skipped, true);
  });

  it('coerces 1-indexed Lua offer tables into cards', () => {
    const engine = mockEngine();
    engine.recruitOffers = () => ({ 1: OFFERS[0], 2: OFFERS[1], 3: OFFERS[2] });
    const ui = new UI(root, engine);
    ui.screen = 'battle';
    ui.activeNode = { id: 'w1' };
    ui.render();

    const cards = find(root, (n) => n.classList.contains('recruit-card'));
    assert.equal(cards.length, 3);
    assert.match(root.textContent, /Oak Guard/);
  });
});
