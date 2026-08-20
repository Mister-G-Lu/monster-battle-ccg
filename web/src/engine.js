// engine.js — load the real Lua game engine into WebAssembly (wasmoon) and
// expose the web_bridge API to the rest of the app. No game logic lives here;
// this is the platform shim (the "device") the engine expects.

import { LuaFactory } from 'wasmoon';
// Let Vite resolve/serve the wasm binary and hand wasmoon an explicit URL,
// instead of relying on wasmoon's default path resolution in the browser.
import wasmUrl from 'wasmoon/dist/glue.wasm?url';
import { luaList } from './lua_list.js';

// The decrypted Lua tree + plain CSVs are copied into /public by
// scripts/prepare_web.py and served statically. We fetch a manifest of the
// files, mount them into the WASM VFS, then boot.

const BASE = import.meta.env.BASE_URL || '/';
function assetUrl(path) {
  const prefix = BASE.endsWith('/') ? BASE : `${BASE}/`;
  return prefix + String(path).replace(/^\//, '');
}

async function fetchText(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`fetch ${url} -> ${r.status}`);
  return r.text();
}

// The platform stubs (mirrors tests/campaign_battle_test.lua — the "device").
const PLATFORM_STUBS = `
package.path = "/game/?.lua;" .. package.path

local bit = {}
local function band(a,b) local r,p=0,1 while (a>0 or b>0) and p<=2^31 do if a%2==1 and b%2==1 then r=r+p end a=math.floor(a/2) b=math.floor(b/2) p=p*2 end return r end
bit.band=band
function bit.bor(a,b) local r,p=0,1 while (a>0 or b>0) and p<=2^31 do if a%2==1 or b%2==1 then r=r+p end a=math.floor(a/2) b=math.floor(b/2) p=p*2 end return r end
function bit.bxor(a,b) local r,p=0,1 while (a>0 or b>0) and p<=2^31 do if (a%2)~=(b%2) then r=r+p end a=math.floor(a/2) b=math.floor(b/2) p=p*2 end return r end
function bit.bnot(a) return 0xFFFFFFFF - band(a,0xFFFFFFFF) end
function bit.lshift(a,n) return band(a*2^n,0xFFFFFFFF) end
function bit.rshift(a,n) return math.floor(band(a,0xFFFFFFFF)/2^n) end
package.loaded["bit"]=bit

aandm = {}
function aandm.loadConfig(name)
  local base = string.match(name, "([^/\\\\]+)%.csv$") or name
  local f = io.open("/csv/"..base..".csv","r"); if not f then return "" end
  local c = f:read("*a"); f:close(); return c
end
function aandm.getDataFromFile() return nil end

socket={}; crypt={}
package.loaded["socket"]=socket; package.loaded["crypt"]=crypt
protobuf={register=function() end, encode=function() return "" end, decode2=function() return {} end}
package.loaded["utils.protobuf"]=protobuf

cc={}; cc.LANGUAGE_ENGLISH=0; cc.LANGUAGE_CHINESE=1; cc.PLATFORM_OS_WINDOWS=4
cc.Application={getInstance=function() return {getCurrentLanguage=function() return 0 end, getTargetPlatform=function() return 4 end} end}
cc.FileUtils={getInstance=function() return {getWritablePath=function() return "/save/" end} end}
-- localStorage-backed UserDefault so campaign progress persists across reloads
local _store = _WEB_STORE or {}
cc.UserDefault={getInstance=function() return {
  getStringForKey=function(_,k,d) return _store[k] or d or "" end,
  getIntegerForKey=function(_,k,d) return tonumber(_store[k]) or d or 0 end,
  getBoolForKey=function(_,k,d) if _store[k]==nil then return d or false end return _store[k]=="true" end,
  getDoubleForKey=function(_,k,d) return tonumber(_store[k]) or d or 0 end,
  setStringForKey=function(_,k,v) _store[k]=tostring(v); _WEB_STORE_DIRTY=true end,
  setIntegerForKey=function(_,k,v) _store[k]=tostring(v); _WEB_STORE_DIRTY=true end,
  setBoolForKey=function(_,k,v) _store[k]=tostring(v); _WEB_STORE_DIRTY=true end,
  setDoubleForKey=function(_,k,v) _store[k]=tostring(v); _WEB_STORE_DIRTY=true end,
  flush=function() _WEB_STORE_DIRTY=true end } end}
cc.Director={getInstance=function() return {getScheduler=function() return {scheduleScriptFunc=function() return 1 end, unscheduleScriptEntry=function() end} end,getRunningScene=function() return nil end,replaceScene=function() end,endToLua=function() end,getTextureCache=function() return {} end} end}
cc.size=function(w,h) return {width=w,height=h} end
cc.p=function(x,y) return {x=x,y=y} end
cc.DEGREES_TO_RADIANS=function(d) return d*math.pi/180 end
ccui={}
path = "res/data/"
`;

const BOOTSTRAP = `
local time = require "manager.time"; time:Init()
require "common.ext.init"
local data_template = require "manager.data_template"; data_template:Init()
local guard=0
while not data_template.is_load_complete and guard<50 do data_template:LoadFromCSV(); guard=guard+1 end
_G.__bridge = require "web_bridge"
_G.__bridge.boot()
return "ok"
`;

export class Engine {
  constructor() {
    this.lua = null;
    this.bridge = null;
  }

  async init(onProgress = () => {}) {
    onProgress('Loading WASM Lua runtime…');
    const factory = new LuaFactory(wasmUrl);
    this.lua = await factory.createEngine();

    onProgress('Fetching game files…');
    const manifest = await (await fetch(assetUrl('game-manifest.json'))).json();

    onProgress(`Mounting ${manifest.lua.length} Lua files…`);
    for (const rel of manifest.lua) {
      const content = await fetchText(assetUrl(`game/${rel}`));
      await factory.mountFile(`/game/${rel}`, content);
    }
    // the bridge itself
    await factory.mountFile('/game/web_bridge.lua', await fetchText(assetUrl('web_bridge.lua')));

    onProgress(`Mounting ${manifest.csv.length} data tables…`);
    for (const rel of manifest.csv) {
      const content = await fetchText(assetUrl(`csv/${rel}`));
      await factory.mountFile(`/csv/${rel}`, content);
    }

    // restore persisted save
    const saved = localStorage.getItem('mb_save');
    this.lua.global.set('_WEB_STORE', saved ? JSON.parse(saved) : {});

    onProgress('Installing platform shim…');
    await this.lua.doString(PLATFORM_STUBS);

    onProgress('Booting engine…');
    await this.lua.doString(BOOTSTRAP);

    this.bridge = this.lua.global.get('__bridge');
    onProgress('Ready');
    return this;
  }

  _persist() {
    // flush the localStorage-backed UserDefault if the engine wrote to it
    if (this.lua.global.get('_WEB_STORE_DIRTY')) {
      const store = this.lua.global.get('_WEB_STORE');
      localStorage.setItem('mb_save', JSON.stringify(store));
      this.lua.global.set('_WEB_STORE_DIRTY', false);
    }
  }

  campaignInfo() { const r = this.bridge.campaign_info(); this._persist(); return r; }
  startBattle(id) { const r = this.bridge.start_battle(id); this._persist(); return r; }
  battleState() { return this.bridge.battle_state(); }
  sacrifice(pos) { this.bridge.sacrifice(pos); }
  playCard(pos) { return this.bridge.play_card(pos); }
  endTurn() { this.bridge.end_turn(); this._persist(); }
  recruitOffers(id) { return luaList(this.bridge.recruit_offers(id)); }
  recruit(id, card) { const r = this.bridge.recruit(id, card); this._persist(); return r; }
  skipRecruit() { const r = this.bridge.skip_recruit(); this._persist(); return r; }
}
