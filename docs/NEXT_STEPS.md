# Next Steps — the Android-only Shadow Road

The consolidation is **complete**: the campaign is a native Android feature,
the web shell is scrapped, and the original PvE mission list is no longer the
Play destination. What remains is polish and hardening.

## Done

- **Native campaign engine** — `offline_battle.lua` hero-HP duel: commander
  HP, face hits, overkill carry-through, Gathering Power (turns 3/6/9), all
  eight scripted elite/boss powers, Warding, token summons (Sapling / Beast
  Whelp / Wraithguard), ENRAGE + ECLIPSE phase-2 triggers.
- **Native campaign service** — `campaign_service.lua` + `offline_server.lua`
  handlers: `req_campaign_info`, `req_campaign_battle_start`,
  `req_campaign_recruit_offers`, `req_campaign_recruit`,
  `req_campaign_skip_recruit`, `req_campaign_reset`; progression persisted in
  the game save.
- **Native campaign map** — `campaign_panel.lua` (programmatic Cocos scene):
  node list, lock/unlock, replay, boss powers, stats, reset, and the
  first-clear recruit draft chooser. The home **Play** button opens it.
- **Client battle wiring** — `cmd_battle_hero` → `update_hero_hp` HUD in the
  battle scene; `refresh_campaign` dispatch on campaign battle over.
- **Web scrapped** — `index.html` is a landing page pointing at the APK;
  `build/web/*`, PWA files, the JS engine/tests, and their generators were
  removed. `content/campaign_data.json` remains the single campaign source
  for the native module.
- **Tests** — `tests/campaign_battle_test.lua` plays w1 and w5 end-to-end
  (hero duel, powers, recruits, reset, persistence); all Lua suites pass
  under LuaJIT 2.1.

## Candidate next slices (none required for playability)

- **Presentation parity for the campaign map** — the map is a text list;
  layering the extracted UI art (region backdrops, node icons, boss
  portraits) onto the panel would make it match the battle scene's polish.
- **Encounter header** — show the node name / enemy name in the battle
  scene for campaign battles (`cmd_battle_start.pve_battle_info.campaign_node_id`
  is already carried through).
- **Result screen integration** — surface recruit drafts directly on the
  battle result panel instead of on return to the map.
- **Balance pass with the native duel** — re-tune node HP/exp using
  `campaign_balance_diag.lua` once real playtest data exists.

## Guardrails

- Android mechanics stay canonical; adding a level is a JSON edit only.
- No web shell resurrection; no WASM/Capacitor work without a concrete
  consumer.
- New mechanics go into the engine, gated by the canonical power `id`.
