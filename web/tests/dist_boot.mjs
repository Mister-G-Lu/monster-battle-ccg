#!/usr/bin/env node
// Boot the SHIPPED browser build (web/dist) in wasmoon — not the decrypted/
// fixtures — so a stale or half-regenerated dist fails here.
//
// Guards two things the fixture-based tests cannot:
//   * every file game-manifest.json lists actually exists in dist
//   * the engine boots and a campaign battle starts from the shipped tree,
//     i.e. nothing archived (see scripts/archived_sources.py) is still
//     required at runtime
//
// Skips when dist or wasmoon is missing (run `npm run build` and
// `npm install` in web/).
import { execFileSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const WEB = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const DIST = path.join(WEB, 'dist');
const ROOT = path.dirname(WEB);

let failures = 0;
const check = (cond, msg) => {
  console.log(`${cond ? 'ok  ' : 'not ok'} - ${msg}`);
  if (!cond) failures++;
};

function skip(why) {
  console.log(`SKIP dist_boot.mjs (${why})`);
  process.exit(0);
}

if (!fs.existsSync(path.join(DIST, 'game-manifest.json'))) {
  skip('no web/dist; run npm run build in web/');
}
let LuaFactory;
try {
  ({ LuaFactory } = await import('wasmoon'));
} catch {
  skip('wasmoon not installed; run npm install in web/');
}

const manifest = JSON.parse(fs.readFileSync(path.join(DIST, 'game-manifest.json'), 'utf8'));

// ---- 1. the manifest matches the files on disk ----------------------------
const missing = [
  ...manifest.lua.filter((f) => !fs.existsSync(path.join(DIST, 'game', f))),
  ...manifest.csv.filter((f) => !fs.existsSync(path.join(DIST, 'csv', f))),
];
check(missing.length === 0, `every manifest entry exists in dist (${missing.length} missing)`);

// ---- 2. archived modules are not shipped ---------------------------------
// ask the single source of truth rather than keeping a second list here
let archived = [];
try {
  archived = execFileSync('python3', [path.join(ROOT, 'scripts', 'archived_sources.py')],
    { encoding: 'utf8' }).split('\n').map((l) => l.trim()).filter(Boolean);
} catch {
  archived = [];
}
check(archived.length > 0, 'archived_sources.py lists the archived modules');
for (const rel of archived) {
  check(!manifest.lua.includes(rel), `manifest does not list archived ${rel}`);
  check(!fs.existsSync(path.join(DIST, 'game', rel)), `dist does not contain archived ${rel}`);
}

// ---- 3. the shipped tree boots and a campaign battle starts --------------
const factory = new LuaFactory();
const lua = await factory.createEngine();
for (const rel of manifest.lua) {
  await factory.mountFile(`/game/${rel}`, fs.readFileSync(path.join(DIST, 'game', rel), 'utf8'));
}
await factory.mountFile('/game/web_bridge.lua', fs.readFileSync(path.join(DIST, 'web_bridge.lua'), 'utf8'));
for (const rel of manifest.csv) {
  await factory.mountFile(`/csv/${rel}`, fs.readFileSync(path.join(DIST, 'csv', rel), 'utf8'));
}

// the same platform shim engine.js installs (kept in sync by reading it back)
const engineSrc = fs.readFileSync(path.join(WEB, 'src', 'engine.js'), 'utf8');
const stub = engineSrc.match(/const PLATFORM_STUBS = `([\s\S]*?)`;/)[1]
  .replace(/\\\\/g, '\\');
await lua.doString(stub);

const booted = await lua.doString(`
  local time = require "manager.time"; time:Init()
  require "common.ext.init"
  local data_template = require "manager.data_template"; data_template:Init()
  local guard = 0
  while not data_template.is_load_complete and guard < 50 do data_template:LoadFromCSV(); guard = guard + 1 end
  _G.__bridge = require "web_bridge"
  _G.__bridge.boot()
  local info = _G.__bridge.campaign_info()
  local started = _G.__bridge.start_battle("w1")
  local st = _G.__bridge.battle_state()
  return string.format("%d|%s|%s", #info.regions, tostring(started), tostring(st.enemy_hp))
`);
const [regions, started, enemyHp] = booted.split('|');
check(regions === '4', `campaign_info reports 4 regions (got ${regions})`);
check(started === 'true', `start_battle("w1") succeeded from the shipped tree (got ${started})`);
check(enemyHp === '14', `w1 enemy commander HP is 14 (got ${enemyHp})`);

const stillThere = await lua.doString(
  'return pcall(require, "modules.pve.pve_gerbil_tide_panel") and "present" or "absent"',
);
check(stillThere === 'absent', 'the archived Gerbip Tide panel cannot be required at runtime');

console.log(failures === 0 ? 'DIST BOOT OK' : `DIST BOOT FAILED (${failures})`);
process.exit(failures === 0 ? 0 : 1);
