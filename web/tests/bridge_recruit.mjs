#!/usr/bin/env node
// Headless WASM parity: boot the real engine + web_bridge and exercise the
// recruit-draft API the browser chooser calls. Skips when fixtures / wasmoon
// are missing (run `python3 scripts/setup_test_env.py` and `npm install` in web/).
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const WEB = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const ROOT = path.dirname(WEB);
const DECRYPTED = path.join(ROOT, 'decrypted');
const CSV = path.join(ROOT, 'csv_plain');
const BRIDGE = path.join(WEB, 'lua', 'web_bridge.lua');

function skip(why) {
  console.log(`SKIP bridge_recruit.mjs (${why})`);
  process.exit(0);
}

if (!fs.existsSync(DECRYPTED) || !fs.existsSync(CSV)) {
  skip('no fixtures; run scripts/setup_test_env.py');
}

let LuaFactory;
try {
  ({ LuaFactory } = await import('wasmoon'));
} catch {
  skip('wasmoon not installed; run npm install in web/');
}

const factory = new LuaFactory();
async function mountDir(srcAbs, dstVfs, exts) {
  for (const ent of fs.readdirSync(srcAbs, { withFileTypes: true })) {
    const s = path.join(srcAbs, ent.name);
    const d = `${dstVfs}/${ent.name}`;
    if (ent.isDirectory()) await mountDir(s, d, exts);
    else if (exts.has(path.extname(ent.name))) {
      await factory.mountFile(d, fs.readFileSync(s));
    }
  }
}

const lua = await factory.createEngine();
await mountDir(DECRYPTED, '/game', new Set(['.lua']));
await mountDir(CSV, '/csv', new Set(['.csv']));
await factory.mountFile('/game/web_bridge.lua', fs.readFileSync(BRIDGE));

const bootstrap = `
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
  local base = string.match(name, "([^/\\\\\\\\]+)%.csv$") or name
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
cc.UserDefault={getInstance=function() return {
  getStringForKey=function() return "" end, getIntegerForKey=function(_,d) return d or 0 end,
  getBoolForKey=function(_,d) return d or false end, getDoubleForKey=function(_,d) return d or 0 end,
  setStringForKey=function() end, setIntegerForKey=function() end, setBoolForKey=function() end,
  setDoubleForKey=function() end, flush=function() end } end}
cc.Director={getInstance=function() return {getScheduler=function() return {scheduleScriptFunc=function() return 1 end} end,getRunningScene=function() return nil end,replaceScene=function() end,endToLua=function() end,getTextureCache=function() return {} end} end}
cc.size=function(w,h) return {width=w,height=h} end
cc.p=function(x,y) return {x=x,y=y} end
ccui={}
path = "res/data/"

local time = require "manager.time"; time:Init()
require "common.ext.init"
local data_template = require "manager.data_template"; data_template:Init()
local guard=0
while not data_template.is_load_complete and guard<50 do data_template:LoadFromCSV(); guard=guard+1 end
local campaign_service = require "manager.campaign_service"
local B = require "web_bridge"
assert(B.boot(), "boot failed")
local offline_server = require "manager.offline_server"
campaign_service.reset(offline_server:GetCampaignSave())
offline_server:Save()

assert(#B.recruit_offers("w1") == 0, "no offers before a first clear")
assert(B.skip_recruit() == false, "skip with nothing pending rejected")

local save = offline_server:GetCampaignSave()
campaign_service.apply_victory(save, campaign_service.node_by_id("w1"))
offline_server:Save()
local info = B.campaign_info()
assert(info.pending_recruit == "w1", "pending_recruit")
local offers = B.recruit_offers("w1")
assert(#offers == 3, "draft size "..tostring(#offers))
for i, o in ipairs(offers) do
  assert(type(o.name) == "string" and o.name ~= "" and not o.name:match("^Card "),
    "real name for offer "..i..": "..tostring(o.name))
  assert(o.type ~= nil and o.id ~= nil, "offer snapshot fields")
end
local before = info.collection_size
assert(B.recruit("w1", 999999) == false, "invalid pick rejected")
assert(B.campaign_info().pending_recruit == "w1", "pending survives a bad pick")
assert(B.recruit("w1", offers[1].id) == true, "recruit")
local after = B.campaign_info()
assert(after.pending_recruit == nil, "cleared")
assert(after.collection_size == before + 1, "collection grew")

campaign_service.apply_victory(offline_server:GetCampaignSave(), campaign_service.node_by_id("w2"))
offline_server:Save()
assert(B.campaign_info().pending_recruit == "w2", "w2 draft pending")
assert(B.skip_recruit() == true, "skip via server handler")
assert(B.campaign_info().pending_recruit == nil, "skip cleared pending")
assert(B.skip_recruit() == false, "second skip rejected")

assert(before == 12, "starter collection is 12")
print("RESULT offers=3 name="..offers[1].name.." collection="..after.collection_size)
print("OK web_bridge recruit draft in WASM")
`;

try {
  await lua.doString(bootstrap);
} catch (e) {
  console.error('BOOT ERROR:', e.message || e);
  process.exitCode = 1;
} finally {
  lua.global.close();
}
