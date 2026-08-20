-- web_bridge_test.lua
-- The browser build's UI-facing adapter (web/lua/web_bridge.lua) over the
-- REAL offline_server / campaign_service. Asserts the recruit-draft path the
-- web chooser depends on: real card names (not "Card 123"), pick grows the
-- collection, skip goes through the server handler, pending_recruit is
-- exposed on campaign_info.
--
-- Run after scripts/setup_test_env.py:
--     luajit tests/web_bridge_test.lua

local failures = 0
local function check(cond, msg)
    if cond then
        print("[PASS] " .. msg)
    else
        failures = failures + 1
        print("[FAIL] " .. msg)
    end
end
local function section(name) print("\n=== " .. name .. " ===") end

if not (io.open("csv_plain/all_card_config.csv", "r") and io.open("decrypted/manager/offline_server.lua", "r")) then
    print("SKIP web_bridge_test.lua (no fixtures; run scripts/setup_test_env.py)")
    os.exit(0)
end

-- ---------------------------------------------------------------------------
-- Stubs (mirror tests/campaign_battle_test.lua — the "device")
-- ---------------------------------------------------------------------------
path = "res/data/"

local bit_stub = {}
function bit_stub.band(a, b)
    local r, p = 0, 1
    while (a > 0 or b > 0) and p <= 2^31 do
        if a % 2 == 1 and b % 2 == 1 then r = r + p end
        a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2
    end
    return r
end
function bit_stub.bor(a, b)
    local r, p = 0, 1
    while (a > 0 or b > 0) and p <= 2^31 do
        if a % 2 == 1 or b % 2 == 1 then r = r + p end
        a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2
    end
    return r
end
function bit_stub.bxor(a, b)
    local r, p = 0, 1
    while (a > 0 or b > 0) and p <= 2^31 do
        if (a % 2) ~= (b % 2) then r = r + p end
        a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2
    end
    return r
end
function bit_stub.bnot(a) return 0xFFFFFFFF - bit_stub.band(a, 0xFFFFFFFF) end
function bit_stub.lshift(a, n) return bit_stub.band(a * 2^n, 0xFFFFFFFF) end
function bit_stub.rshift(a, n) return math.floor(bit_stub.band(a, 0xFFFFFFFF) / 2^n) end
package.loaded["bit"] = bit_stub

aandm = {}
function aandm.loadConfig(name)
    local base = string.match(name, "([^/\\]+)%.csv$") or name
    local f = io.open("csv_plain/" .. base .. ".csv", "r")
    if not f then return "" end
    local c = f:read("*a"); f:close(); return c
end
function aandm.getDataFromFile() return nil end

socket = {}; crypt = {}
package.loaded["socket"] = socket
package.loaded["crypt"] = crypt
protobuf = { register = function() end, encode = function() return "" end, decode2 = function() return {} end }
package.loaded["utils.protobuf"] = protobuf

cc = {}
cc.LANGUAGE_ENGLISH = 0; cc.LANGUAGE_CHINESE = 1; cc.PLATFORM_OS_WINDOWS = 4
cc.Application = { getInstance = function() return {
    getCurrentLanguage = function() return cc.LANGUAGE_ENGLISH end,
    getTargetPlatform = function() return cc.PLATFORM_OS_WINDOWS end } end }
cc.FileUtils = { getInstance = function() return { getWritablePath = function() return "sim_save_web/" end } end }
cc.UserDefault = { getInstance = function() return {
    getStringForKey = function() return "" end,
    getIntegerForKey = function(_, d) return d or 0 end,
    getBoolForKey = function(_, d) return d or false end,
    setStringForKey = function() end, setIntegerForKey = function() end,
    setBoolForKey = function() end, setDoubleForKey = function() end,
    flush = function() end } end }
cc.Director = { getInstance = function() return {
    getTextureCache = function() return {} end,
    getScheduler = function() return { scheduleScriptFunc = function() return 1 end } end,
    getRunningScene = function() return nil end,
    replaceScene = function() end, endToLua = function() end } end }
cc.DEGREES_TO_RADIANS = function(d) return d * math.pi / 180 end
cc.size = function(w, h) return { width = w, height = h } end
cc.p = function(x, y) return { x = x, y = y } end
ccui = {}

os.execute("mkdir -p sim_save_web")

package.path = "src/?.lua;decrypted/?.lua;decrypted/src/?.lua;web/lua/?.lua;" .. package.path

local time = require "manager.time"
time:Init()
require "common.ext.init"

local data_template = require "manager.data_template"
data_template:Init()
while not data_template.is_load_complete do
    data_template:LoadFromCSV()
end

local campaign_service = require "manager.campaign_service"
local B = require "web_bridge"

section("1. boot")
local ok = B.boot()
check(ok == true, "web_bridge.boot logs in")

local offline_server = require "manager.offline_server"
campaign_service.reset(offline_server:GetCampaignSave())
offline_server:Save()

local info = B.campaign_info()
check(info.pending_recruit == nil, "fresh campaign has no pending recruit")
check(info.collection_size == 12, "starter collection is 12 (got " .. tostring(info.collection_size) .. ")")

section("2. recruit_offers with nothing pending")
local empty = B.recruit_offers("w1")
check(#empty == 0, "offers without a pending recruit are empty")
check(B.skip_recruit() == false, "skip with nothing pending is rejected")

section("3. first-clear draft — real names")
local save = offline_server:GetCampaignSave()
local w1 = campaign_service.node_by_id("w1")
campaign_service.apply_victory(save, w1)
offline_server:Save()

info = B.campaign_info()
check(info.pending_recruit == "w1", "campaign_info exposes pending_recruit=w1")

local offers = B.recruit_offers("w1")
check(#offers == 3, "draft offers 3 cards (got " .. #offers .. ")")
for i, o in ipairs(offers) do
    check(o.id ~= nil, "offer " .. i .. " has an id")
    check(type(o.name) == "string" and o.name ~= "", "offer " .. i .. " has a name")
    check(not tostring(o.name):match("^Card "),
          "offer " .. i .. " resolved a real name (got '" .. tostring(o.name) .. "')")
    check(o.type ~= nil, "offer " .. i .. " has a type")
    local cfg = data_template.card_config[tostring(o.id)]
    check(cfg ~= nil, "offer " .. i .. " id " .. tostring(o.id) .. " is in card_config")
    if cfg and cfg.name then
        check(o.name == cfg.name, "offer " .. i .. " name matches card_config ('" .. tostring(cfg.name) .. "')")
    end
end

section("4. pick grows the collection (collection IS the deck)")
local before = info.collection_size
local pick = offers[1]
local rec_ok = B.recruit("w1", pick.id)
check(rec_ok == true, "recruit pick accepted")
local after = B.campaign_info()
check(after.pending_recruit == nil, "pending recruit cleared after pick")
check(after.collection_size == before + 1,
      "collection grew by one (got " .. tostring(after.collection_size) .. ")")
local in_deck = false
local cam = offline_server:GetCampaignSave()
for _, id in ipairs(campaign_service.player_deck_ids(cam)) do
    if tonumber(id) == tonumber(pick.id) then in_deck = true break end
end
check(in_deck, "picked card joins the campaign battle deck")

section("5. skip goes through the server handler")
local w2 = campaign_service.node_by_id("w2")
campaign_service.apply_victory(cam, w2)
offline_server:Save()
check(B.campaign_info().pending_recruit == "w2", "w2 first clear opens a recruit")
local exp_before = cam.exp
local skip_ok = B.skip_recruit()
check(skip_ok == true, "skip_recruit accepted via req_campaign_skip_recruit")
check(B.campaign_info().pending_recruit == nil, "pending recruit cleared after skip")
check(cam.exp == exp_before + campaign_service.SKIP_RECRUIT_EXP,
      "skip grants +15 campaign EXP (got " .. tostring(cam.exp - exp_before) .. ")")
check(B.skip_recruit() == false, "second skip is rejected")

section("6. invalid pick rejected")
local w3 = campaign_service.node_by_id("w3")
campaign_service.apply_victory(cam, w3)
offline_server:Save()
local offers3 = B.recruit_offers("w3")
check(#offers3 == 3, "w3 draft generated")
check(B.recruit("w3", 999999) == false, "pick outside the offers is rejected")
check(B.campaign_info().pending_recruit == "w3", "pending recruit survives a bad pick")
check(B.recruit("w3", offers3[2].id) == true, "valid pick after a bad one is accepted")

print()
if failures > 0 then
    print("RESULT: " .. failures .. " FAILURE(S)")
    os.exit(1)
end
print("RESULT: ALL WEB BRIDGE CHECKS PASSED")
