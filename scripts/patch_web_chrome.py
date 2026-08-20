#!/usr/bin/env python3
"""One-shot presentation-parity patches for index.html + build/web/game.html."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = [ROOT / "index.html", ROOT / "build" / "web" / "game.html"]

CSS_OLD = """\
.crystal-bar { display: flex; align-items: center; gap: 6px; justify-content: center; margin: 2px 0; }
.crystal { width: 18px; height: 18px; background: #e94560; border-radius: 50%; }
.crystal.empty { background: #2a2a3a; }

.card { width: 84px; height: 104px; border-radius: 9px; font-size: 0.72em; cursor: default; transition: transform 0.15s, box-shadow 0.15s; position: relative; border: 2px solid #333; overflow: hidden; background: #14142a; }
.card.hand { background: linear-gradient(135deg, #0f3460, #16213e); cursor: pointer; }
.card.hand:hover { transform: translateY(-4px) scale(1.04); }
.card.field-card { background: linear-gradient(135deg, #1a472a, #2d5a3f); }
.card.enemy-field { background: linear-gradient(135deg, #5a1a1a, #7a2a2a); }
.card.token { background: linear-gradient(135deg, #3a2a10, #57421a); }

/* Card art — the creature scene / item sprite fills the top, stats sit in a bar below */
.card .card-art { position: absolute; top: 0; left: 0; right: 0; bottom: 36px; background-size: cover; background-position: center 22%; background-repeat: no-repeat; }
.card .card-art.item-art { background-size: 62% auto; background-position: center 8px; }
.card .card-art.placeholder { background-size: 42% auto; background-position: center 10px; filter: drop-shadow(0 2px 3px rgba(0,0,0,.65)); }
.card .card-gem { position: absolute; top: 3px; right: 3px; width: 14px; height: 16px; background-size: contain; background-repeat: no-repeat; background-position: center; z-index: 3; filter: drop-shadow(0 1px 1px rgba(0,0,0,.6)); }
.card .card-cost { position: absolute; top: 2px; left: 4px; background: radial-gradient(circle at 30% 28%, #ff5c78, #8e1730); color: #fff; border: 1px solid rgba(255,255,255,.35); border-radius: 50%; width: 18px; height: 18px; display: flex; align-items: center; justify-content: center; font-size: 0.76em; font-weight: bold; z-index: 3; box-shadow: 0 1px 2px rgba(0,0,0,.6); }
.card .card-stats { position: absolute; left: 0; right: 0; bottom: 0; height: 36px; padding: 3px 4px 2px; background: linear-gradient(180deg, rgba(12,12,24,.5), rgba(6,6,16,.97)); display: flex; flex-direction: column; justify-content: flex-end; z-index: 2; }
.card .card-name { font-weight: 700; font-size: 0.74em; line-height: 1.15; max-width: 100%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; text-shadow: 0 1px 2px rgba(0,0,0,.85); }
.card .card-line { color: #f2f2f6; font-size: 0.76em; line-height: 1.2; white-space: nowrap; text-shadow: 0 1px 2px rgba(0,0,0,.85); }
.card .card-line .hp { color: #7ee692; margin-left: 3px; }
.card .card-kw { color: #b6b6cc; font-size: 0.68em; line-height: 1.15; max-width: 100%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.card .kicon { display: inline-block; width: 12px; height: 12px; background-size: contain; background-repeat: no-repeat; background-position: center; vertical-align: -2px; margin-right: 3px; }
"""

CSS_NEW = """\
.crystal-bar { display: flex; align-items: center; gap: 4px; justify-content: center; margin: 2px 0; }
.crystal { width: 16px; height: 16px; background: #e94560; border-radius: 50%; background-size: contain; background-repeat: no-repeat; background-position: center; }
.crystal.has-art { background-color: transparent; filter: drop-shadow(0 1px 1px rgba(0,0,0,.6)); }
.crystal.empty { background: #2a2a3a; opacity: .35; filter: grayscale(1); }

.card { width: 88px; height: 118px; border-radius: 6px; font-size: 0.72em; cursor: default; transition: transform 0.15s, box-shadow 0.15s; position: relative; border: none; overflow: hidden; background: #14142a; box-shadow: 0 2px 6px rgba(0,0,0,.55); }
.card.hand { cursor: pointer; }
.card.hand:hover { transform: translateY(-4px) scale(1.04); }
.card.token { filter: saturate(.85); }

/* Android card chrome: frame sprite layered over art */
.card .card-frame { position: absolute; inset: 0; pointer-events: none; z-index: 4; background-size: 100% 100%; background-repeat: no-repeat; }
.card .card-art { position: absolute; top: 10px; left: 6px; right: 6px; bottom: 34px; background-size: cover; background-position: center 18%; background-repeat: no-repeat; z-index: 1; background-color: #1a1428; }
.card .card-art.item-art { background-size: 70% auto; background-position: center 12px; }
.card .card-art.placeholder { background-size: 48% auto; background-position: center 14px; filter: drop-shadow(0 2px 3px rgba(0,0,0,.65)); }
.card .card-gem { position: absolute; top: 6px; right: 6px; width: 16px; height: 18px; background-size: contain; background-repeat: no-repeat; background-position: center; z-index: 5; filter: drop-shadow(0 1px 1px rgba(0,0,0,.6)); }
.card .card-cost { position: absolute; top: 4px; left: 4px; color: #fff; width: 22px; height: 22px; display: flex; align-items: center; justify-content: center; font-size: 0.78em; font-weight: bold; z-index: 5; text-shadow: 0 1px 2px #000; background-size: contain; background-repeat: no-repeat; background-position: center; }
.card .card-stats { position: absolute; left: 4px; right: 4px; bottom: 4px; height: 32px; padding: 2px 3px 1px; background: linear-gradient(180deg, rgba(12,12,24,.15), rgba(6,6,16,.92)); display: flex; flex-direction: column; justify-content: flex-end; z-index: 3; }
.card .card-name { font-weight: 700; font-size: 0.72em; line-height: 1.1; max-width: 100%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; text-shadow: 0 1px 2px rgba(0,0,0,.85); }
.card .card-line { color: #f2f2f6; font-size: 0.76em; line-height: 1.2; white-space: nowrap; text-shadow: 0 1px 2px rgba(0,0,0,.85); display: flex; align-items: center; gap: 4px; }
.card .card-line .stat { display: inline-flex; align-items: center; gap: 2px; }
.card .card-line .stat-ico { width: 11px; height: 11px; background-size: contain; background-repeat: no-repeat; display: inline-block; }
.card .card-line .hp { color: #7ee692; }
.card .card-kw { color: #b6b6cc; font-size: 0.68em; line-height: 1.15; max-width: 100%; overflow: hidden; display: flex; gap: 2px; align-items: center; }
.card .skicon { width: 12px; height: 12px; background-size: contain; background-repeat: no-repeat; flex: 0 0 auto; }
.card .kicon { display: inline-block; width: 12px; height: 12px; background-size: contain; background-repeat: no-repeat; background-position: center; vertical-align: -2px; margin-right: 3px; }
"""

INTRO_OLD = """.intro-portrait { font-size: 3.2em; line-height: 1.1; margin-bottom: 6px; }"""
INTRO_NEW = """.intro-portrait { font-size: 3.2em; line-height: 1.1; margin-bottom: 6px; width: 120px; height: 140px; margin-left: auto; margin-right: auto; background-size: cover; background-position: center; background-repeat: no-repeat; border-radius: 8px; box-shadow: 0 4px 16px rgba(0,0,0,.5); display: flex; align-items: center; justify-content: center; }
.intro-portrait.has-art { font-size: 0; }"""

JS_ART_OLD = """function cardArtUrl(card) {
  if (!card) return '';
  if (card.token) return card.kind ? ART_BASE + 'ui/faction/' + card.kind + '.png' : '';
  if (!card.res_path) return '';
  if (card.type === 'monster') return ART_BASE + 'cards/monster/' + card.kind + '/' + card.res_path + '.png';
  return ART_BASE + 'cards/item/' + card.res_path + '.png';
}"""

JS_ART_NEW = """function cardArtUrl(card) {
  if (!card) return '';
  if (card.token) return card.kind ? ART_BASE + 'ui/faction/' + card.kind + '.png' : '';
  if (!card.res_path) return '';
  if (card.type === 'monster') return ART_BASE + 'cards/monster/' + card.kind + '/' + card.res_path + '.png';
  return ART_BASE + 'cards/item/' + card.res_path + '.png';
}

function uiUrl(rel) { return ART_BASE + rel; }
function skillIconUrl(name) {
  if (!name) return '';
  const key = String(name).toLowerCase().replace(/[^a-z0-9_\\-]/g, '');
  return uiUrl('ui/skill/' + key + '.png');
}
function cardFrameUrl(card) {
  if (!card) return uiUrl('ui/border/card_border.png');
  if (card.type === 'equip' || card.type === 'armor') return uiUrl('ui/border/battlecard_equip1.png');
  if (card.type === 'consume') return uiUrl('frame/consumables_bg.png');
  return uiUrl('ui/border/card_border.png');
}
function encounterPortraitUrl(node) {
  if (!node) return '';
  if (node.deckIds) {
    for (const id of node.deckIds) {
      const c = GAME_DATA.cards[id];
      const u = cardArtUrl(c);
      if (u) return u;
    }
  }
  const region = node.regionId ? REGION_BY_ID[node.regionId] : null;
  const kind = (node.pool && node.pool.kinds && node.pool.kinds[0]) || (region && region.faction) || 'all';
  return uiUrl('ui/faction/' + kind + '.png');
}"""

JS_CRYSTAL_OLD = """function renderCrystals(id, current, max) {
  const el = document.getElementById(id);
  el.innerHTML = '';
  for (let i = 0; i < max; i++) {
    const c = document.createElement('div');
    c.className = 'crystal' + (i >= current ? ' empty' : '');
    el.appendChild(c);
  }
}"""

JS_CRYSTAL_NEW = """function renderCrystals(id, current, max) {
  const el = document.getElementById(id);
  el.innerHTML = '';
  for (let i = 0; i < max; i++) {
    const c = document.createElement('div');
    const empty = i >= current;
    c.className = 'crystal has-art' + (empty ? ' empty' : '');
    c.style.backgroundImage = \"url('\" + uiUrl('ui/crystal.png') + \"')\";
    el.appendChild(c);
  }
}"""

JS_CARD_OLD = """function keywordSummary(card) {
  return (card.powers || []).slice(0, 2).map(p => p.name + (p.value ? ' ' + p.value : '')).join(', ');
}

function createCardEl(card, className, owner, index) {
  const el = document.createElement('div');
  const isMon = card.type === 'monster';
  const typeSym = card.type === 'equip' ? '⚔' : card.type === 'armor' ? '🛡' : card.type === 'consume' ? '🧪' : '';
  el.className = 'card ' + className + (card.token ? ' token' : '') + (!isMon ? ' item-card' : '');
  if (card.currentHp <= 0) el.classList.add('dead');

  const kindColor = KIND_COLORS[card.kind] || '#888';
  el.style.borderColor = kindColor;
  const kw = keywordSummary(card);
  const nameStr = typeSym + card.name.substring(0, 9);

  // Art layer: painted creature scene, item sprite, or a faction emblem for tokens.
  let artEl;
  const art = cardArtUrl(card);
  if (art) {
    const isMonster = !card.token && card.type === 'monster';
    artEl = `<div class="card-art${isMonster ? '' : ' item-art'}" style="background-image:url('${art}')"></div>`;
  } else {
    artEl = `<div class="card-art placeholder"></div>`;
  }

  const gem = ART_BASE + 'ui/quality/' + (card.quality || 'normal') + '.png';
  const kicon = card.kind ? ART_BASE + 'ui/faction/' + card.kind + '.png' : '';
  const hpLine = card.hp > 0 ? `<span class="hp">&#10084;${card.currentHp || card.hp}/${card.hp}</span>` : '';

  el.innerHTML = `
    ${artEl}
    ${card.token ? '' : `<div class="card-gem" style="background-image:url('${gem}')"></div>`}
    <div class="card-cost">${card.cost}</div>
    <div class="card-stats">
      <div class="card-name" style="color:${kindColor};font-size:${isMon ? '0.82em' : '0.7em'}">${kicon ? `<span class="kicon" style="background-image:url('${kicon}')"></span>` : ''}${nameStr}</div>
      ${isMon ? `<div class="card-line">&#9876;${card.attack || 1}${hpLine}</div>` : `<div class="card-line">${card.type}</div>`}
      ${kw ? `<div class="card-kw">${kw.substring(0, 16)}</div>` : ''}
    </div>
  `;
  el.title = card.name + (kw ? ' — ' + kw : '');
"""

JS_CARD_NEW = """function keywordSummary(card) {
  return (card.powers || []).slice(0, 2).map(p => p.name + (p.value ? ' ' + p.value : '')).join(', ');
}

function createCardEl(card, className, owner, index) {
  const el = document.createElement('div');
  const isMon = card.type === 'monster';
  el.className = 'card ' + className + (card.token ? ' token' : '') + (!isMon ? ' item-card' : '');
  if (card.currentHp <= 0) el.classList.add('dead');

  const kindColor = KIND_COLORS[card.kind] || '#888';
  el.style.borderColor = kindColor;
  const kw = keywordSummary(card);
  const nameStr = card.name.substring(0, 10);

  let artEl;
  const art = cardArtUrl(card);
  const artClass = (!card.token && card.type === 'monster') ? '' : (art ? ' item-art' : ' placeholder');
  const artStyle = art ? \"background-image:url('\" + art + \"')\" : (card.kind ? \"background-image:url('\" + uiUrl('ui/faction/' + card.kind + '.png') + \"')\" : '');
  artEl = `<div class="card-art${artClass}" style="${artStyle}"></div>`;

  const gem = ART_BASE + 'ui/quality/' + (card.quality || 'normal') + '.png';
  const kicon = card.kind ? ART_BASE + 'ui/faction/' + card.kind + '.png' : '';
  const frame = cardFrameUrl(card);
  const crystalBg = uiUrl('ui/crystal.png');
  const hpBg = uiUrl('ui/border/hp_bg.png');
  const skills = (card.powers || []).slice(0, 3).map(p =>
    `<span class="skicon" title="${p.name}" style="background-image:url('${skillIconUrl(p.name)}')"></span>`
  ).join('');
  const hpLine = isMon ? `<span class="stat hp"><span class="stat-ico" style="background-image:url('${hpBg}')"></span>${card.currentHp || card.hp}/${card.hp}</span>` : '';
  const atkLine = isMon ? `<span class="stat"><span class="stat-ico" style="background-image:url('${crystalBg}')"></span>${card.attack || 1}</span>` : `<span class="stat">${card.type}</span>`;

  el.innerHTML = `
    ${artEl}
    <div class="card-frame" style="background-image:url('${frame}')"></div>
    ${card.token ? '' : `<div class="card-gem" style="background-image:url('${gem}')"></div>`}
    <div class="card-cost" style="background-image:url('${crystalBg}')">${card.cost}</div>
    <div class="card-stats">
      <div class="card-name" style="color:${kindColor};font-size:${isMon ? '0.82em' : '0.7em'}">${kicon ? `<span class="kicon" style="background-image:url('${kicon}')"></span>` : ''}${nameStr}</div>
      <div class="card-line">${atkLine}${hpLine}</div>
      ${skills ? `<div class="card-kw">${skills}</div>` : ''}
    </div>
  `;
  el.title = card.name + (kw ? ' — ' + kw : '');
"""

JS_INTRO_OLD = """  document.getElementById('intro-portrait').innerHTML = node.icon;"""
JS_INTRO_NEW = """  const port = document.getElementById('intro-portrait');
  const pUrl = encounterPortraitUrl(node);
  port.textContent = '';
  port.innerHTML = '';
  if (pUrl) {
    port.classList.add('has-art');
    port.style.backgroundImage = \"url('\" + pUrl + \"')\";
  } else {
    port.classList.remove('has-art');
    port.style.backgroundImage = '';
    port.textContent = node.icon || '';
  }"""


def main():
    for path in FILES:
        text = path.read_text(encoding="utf-8")
        orig = text
        for old, new, name in [
            (CSS_OLD, CSS_NEW, "css"),
            (INTRO_OLD, INTRO_NEW, "intro-css"),
            (JS_ART_OLD, JS_ART_NEW, "art-js"),
            (JS_CRYSTAL_OLD, JS_CRYSTAL_NEW, "crystal-js"),
            (JS_CARD_OLD, JS_CARD_NEW, "card-js"),
            (JS_INTRO_OLD, JS_INTRO_NEW, "intro-js"),
        ]:
            if old not in text:
                raise SystemExit(f"{path.name}: missing block {name}")
            text = text.replace(old, new, 1)
        if text == orig:
            raise SystemExit(f"{path.name}: no changes")
        path.write_text(text, encoding="utf-8")
        print("patched", path.relative_to(ROOT), "delta", len(text) - len(orig))


if __name__ == "__main__":
    main()
