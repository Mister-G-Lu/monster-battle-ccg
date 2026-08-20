// ui.js — DOM rendering for the campaign map and battle screens.
// Reads snapshots from the engine bridge; sends player actions back.

const KIND_COLORS = {
  war: '#c0392b', fortune: '#f1c40f', balance: '#8e44ad',
  nature: '#27ae60', chaos: '#e67e22',
};
const el = (tag, cls, txt) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (txt != null) n.textContent = txt;
  return n;
};

export class UI {
  constructor(root, engine) {
    this.root = root;
    this.engine = engine;
    this.screen = 'campaign';
    this.activeNode = null;
  }

  render() {
    this.root.innerHTML = '';
    if (this.screen === 'campaign') this.renderCampaign();
    else if (this.screen === 'battle') this.renderBattle();
  }

  // ---- Campaign map ------------------------------------------------------
  renderCampaign() {
    const info = this.engine.campaignInfo();
    const wrap = el('div', 'campaign');

    const header = el('div', 'topbar');
    header.appendChild(el('div', 'title', 'The Shadow Road'));
    const stats = el('div', 'stats');
    stats.appendChild(el('span', 'stat', `❤ Vitality ${info.vitality}`));
    stats.appendChild(el('span', 'stat', `⚔ Wins ${info.wins}`));
    stats.appendChild(el('span', 'stat', `☠ Losses ${info.losses}`));
    stats.appendChild(el('span', 'stat', `👑 Bosses ${info.bosses_slain}`));
    header.appendChild(stats);
    wrap.appendChild(header);

    if (info.complete) {
      const banner = el('div', 'banner win', '🏆 The Shadow Road is complete — the Sovereign has fallen.');
      wrap.appendChild(banner);
    }

    for (const region of info.regions) {
      const rc = el('div', 'region');
      const color = KIND_COLORS[region.kind] || '#555';
      rc.style.borderLeftColor = color;
      const rh = el('div', 'region-head');
      rh.appendChild(el('span', 'region-name', region.name));
      if (region.kind) {
        const chip = el('span', 'kind-chip', region.kind);
        chip.style.background = color;
        rh.appendChild(chip);
      }
      rc.appendChild(rh);

      const track = el('div', 'node-track');
      region.nodes.forEach((node, i) => {
        if (i > 0) track.appendChild(el('div', 'connector'));
        const nc = el('button', 'node');
        nc.classList.add(node.cleared ? 'cleared' : (node.playable ? 'playable' : 'locked'));
        if (node.final) nc.classList.add('final');
        if (node.type === 'boss' || node.final) nc.appendChild(el('div', 'node-icon', '👑'));
        else nc.appendChild(el('div', 'node-icon', node.cleared ? '✓' : '⚔'));
        nc.appendChild(el('div', 'node-name', node.name));
        if (node.hp) nc.appendChild(el('div', 'node-hp', `HP ${node.hp}`));
        nc.disabled = !node.playable;
        nc.onclick = () => {
          if (this.engine.startBattle(node.id)) {
            this.activeNode = node;
            this.screen = 'battle';
            this.render();
          }
        };
        track.appendChild(nc);
      });
      rc.appendChild(track);
      wrap.appendChild(rc);
    }

    this.root.appendChild(wrap);
  }

  // ---- Battle ------------------------------------------------------------
  renderBattle() {
    const s = this.engine.battleState();
    const wrap = el('div', 'battle');

    // Enemy commander
    wrap.appendChild(this.commanderBar('enemy', this.activeNode?.name || 'Enemy', s.enemy_hp, s.enemy_max_hp, s.enemy));
    wrap.appendChild(this.boardRow(s.enemy.board, true));

    const mid = el('div', 'mid');
    mid.appendChild(el('div', 'round', `Round ${s.round}`));
    mid.appendChild(el('div', `crystal`, `💎 ${s.own.crystal}`));
    wrap.appendChild(mid);

    wrap.appendChild(this.boardRow(s.own.board, false));
    wrap.appendChild(this.commanderBar('own', 'You', s.own_hp, s.own_max_hp, s.own));

    // Hand
    const hand = el('div', 'hand');
    s.own.hand.forEach((c, idx) => {
      const pos = idx + 1;
      if (!c) { hand.appendChild(el('div', 'card empty')); return; }
      const card = el('button', 'card');
      card.classList.add(`k-${c.kind || 'none'}`);
      const affordable = c.cost <= s.own.crystal && !s.is_over;
      if (!affordable) card.classList.add('unaffordable');
      card.appendChild(el('div', 'card-cost', `💎${c.cost}`));
      card.appendChild(el('div', 'card-name', c.name || `#${c.uid}`));
      card.appendChild(el('div', 'card-type', c.type));
      if (c.type === 'monster') card.appendChild(el('div', 'card-hp', `❤${c.hp}`));
      card.onclick = () => {
        if (s.is_over) return;
        // if player must sacrifice and can't afford anything, sacrificing is the move
        this.engine.playCard(pos) || this.engine.sacrifice(pos);
        this.render();
      };
      hand.appendChild(card);
    });
    wrap.appendChild(hand);

    // Controls
    const controls = el('div', 'controls');
    if (s.is_over) {
      const won = s.winner === 'player';
      const banner = el('div', `banner ${won ? 'win' : 'lose'}`,
        won ? '🏆 Victory!' : '☠ Defeat');
      controls.appendChild(banner);
      const back = el('button', 'btn primary', 'Return to the Road');
      back.onclick = () => {
        // resolve any pending recruit by skipping for now (draft UI is a next step)
        try { this.engine.skipRecruit(); } catch (e) {}
        this.screen = 'campaign';
        this.render();
      };
      controls.appendChild(back);
    } else {
      const hint = el('div', 'hint',
        s.own.is_sacrifice
          ? 'Tap a card to sacrifice it for crystals, or deploy an affordable monster.'
          : 'Tap monsters to deploy, then end your turn to attack.');
      controls.appendChild(hint);
      const endTurn = el('button', 'btn primary', '⚔ End Turn (Attack)');
      endTurn.onclick = () => { this.engine.endTurn(); this.render(); };
      controls.appendChild(endTurn);
      const flee = el('button', 'btn ghost', 'Flee');
      flee.onclick = () => { this.screen = 'campaign'; this.render(); };
      controls.appendChild(flee);
    }
    wrap.appendChild(controls);

    this.root.appendChild(wrap);
  }

  commanderBar(side, name, hp, max, actor) {
    const bar = el('div', `commander ${side}`);
    bar.appendChild(el('div', 'commander-name', name));
    const hpwrap = el('div', 'hpbar');
    const fill = el('div', 'hpfill');
    const pct = max ? Math.max(0, Math.round((hp / max) * 100)) : 0;
    fill.style.width = `${pct}%`;
    hpwrap.appendChild(fill);
    hpwrap.appendChild(el('span', 'hptext', `${hp}/${max}`));
    bar.appendChild(hpwrap);
    bar.appendChild(el('div', 'commander-meta', `🂠 ${actor.deck_left} left`));
    return bar;
  }

  boardRow(board, isEnemy) {
    const row = el('div', `board ${isEnemy ? 'enemy' : 'own'}`);
    for (let i = 0; i < 3; i++) {
      const slot = board[i];
      const cell = el('div', 'slot');
      if (slot) {
        const m = el('div', 'monster');
        m.classList.add(`k-${slot.kind || 'none'}`);
        m.appendChild(el('div', 'monster-name', slot.name));
        const line = el('div', 'monster-stats');
        line.appendChild(el('span', 'atk', `⚔${slot.cur_ad}`));
        line.appendChild(el('span', 'hp', `❤${slot.cur_hp}`));
        m.appendChild(line);
        if (slot.has_item) m.appendChild(el('div', 'monster-item', `+${slot.item_name || 'item'}`));
        cell.appendChild(m);
      } else {
        cell.classList.add('empty');
      }
      row.appendChild(cell);
    }
    return row;
  }
}
