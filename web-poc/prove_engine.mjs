// Proof-of-concept: run the REAL Monster Battle Lua engine inside WASM (Wasmoon).
// If this runs in Node, the identical logic runs in a browser.
import { LuaFactory } from 'wasmoon';
import fs from 'fs';
import path from 'path';

const ROOT = path.resolve('..');
const factory = new LuaFactory();

// Mount the decrypted Lua source + plain CSVs into the WASM virtual filesystem.
async function mountDir(srcAbs, dstVfs) {
  for (const ent of fs.readdirSync(srcAbs, { withFileTypes: true })) {
    const s = path.join(srcAbs, ent.name);
    const d = dstVfs + '/' + ent.name;
    if (ent.isDirectory()) { await mountDir(s, d); }
    else if (ent.name.endsWith('.lua') || ent.name.endsWith('.csv')) {
      await factory.mountFile(d, fs.readFileSync(s));
    }
  }
}

const lua = await factory.createEngine();
await mountDir(path.join(ROOT, 'decrypted'), '/game');
await mountDir(path.join(ROOT, 'csv_plain'), '/csv');

// The platform-stub bootstrap (mirrors tests/campaign_battle_test.lua — the "device")
const bootstrap = `
package.path = "/game/?.lua;" .. package.path
-- bit stub
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
cc.FileUtils={getInstance=function() return {getWritablePath=function() return "/tmp/" end} end}
cc.UserDefault={getInstance=function() return {getStringForKey=function() return "" end,getIntegerForKey=function(_,d) return d or 0 end,getBoolForKey=function(_,d) return d or false end,setStringForKey=function() end,setIntegerForKey=function() end,setBoolForKey=function() end,setDoubleForKey=function() end,flush=function() end} end}
cc.Director={getInstance=function() return {getScheduler=function() return {scheduleScriptFunc=function() return 1 end} end,getRunningScene=function() return nil end,replaceScene=function() end,endToLua=function() end,getTextureCache=function() return {} end} end}
cc.size=function(w,h) return {width=w,height=h} end; cc.p=function(x,y) return {x=x,y=y} end
ccui={}

path = "res/data/"

local time = require "manager.time"; time:Init()
require "common.ext.init"
local data_template = require "manager.data_template"; data_template:Init()
local guard=0
while not data_template.is_load_complete and guard<50 do data_template:LoadFromCSV(); guard=guard+1 end

local campaign_data = require "manager.campaign_data"
local campaign_service = require "manager.campaign_service"

local nodes = campaign_data.all_nodes()
print("RESULT nodes="..#nodes)
print("RESULT w1_exists="..tostring(campaign_data.node_by_id("w1") ~= nil))
print("RESULT final_boss="..tostring(campaign_data.node_by_id("s4").final))
local cardcount=0
for _ in pairs(data_template.card_config) do cardcount=cardcount+1 end
print("RESULT cards_loaded="..cardcount)
print("OK engine booted in WASM")
`;

try {
  await lua.doString(bootstrap);
  console.log("\n>>> SUCCESS: your real Lua engine ran inside WebAssembly.");
} catch (e) {
  console.error("BOOT ERROR:", e.message);
  process.exitCode = 1;
} finally {
  lua.global.close();
}
