-- sim_test.lua
-- Headless simulation of the offline single-player build, run under real
-- Lua 5.1 (the same language family as the game's LuaJIT). Loads the REAL
-- game modules (common.constants, utils.csv, manager.data_template,
-- manager.network, manager.offline_server, manager.offline_battle), then:
--   1. data_template:Init + LoadFromCSV   (real decrypted CSVs)
--   2. network:Connect (offline) + req_login_game
--   3. every startup query
--   4. a full PvE battle vs the AI, played to completion
--   5. save/re-login persistence

local failures = 0
local function check(cond, msg)
    if cond then
        print("[PASS] " .. msg)
    else
        failures = failures + 1
        print("[FAIL] " .. msg)
    end
end

-- ---------------------------------------------------------------------------
-- Stubs (only what the loaded modules touch; the real device provides these)
-- ---------------------------------------------------------------------------
path = "res/data/"

-- LuaJIT "bit" library, pure Lua (exact for 32-bit values)
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
function bit_stub.arshift(a, n)
    local v = bit_stub.band(a, 0xFFFFFFFF)
    if v < 2^31 then return math.floor(v / 2^n) end
    return math.floor((v - 2^32) / 2^n)
end
package.loaded["bit"] = bit_stub

-- aandm native module: loadConfig returns (decrypted) CSV text
aandm = {}
function aandm.loadConfig(name)
    local base = string.match(name, "([^/\\]+)%.csv$") or name
    local f = io.open("csv_plain/" .. base .. ".csv", "r")
    if not f then
        return ""
    end
    local c = f:read("*a")
    f:close()
    return c
end
function aandm.getDataFromFile() return nil end

-- stubs for the online transport only
socket = {}
crypt = {}
package.loaded["socket"] = socket
package.loaded["crypt"] = crypt

-- protobuf is unused in offline mode
protobuf = {
    register = function() end,
    encode = function() return "" end,
    decode2 = function() return {} end,
}
package.loaded["utils.protobuf"] = protobuf

-- cc (cocos2d-x) stub
cc = {}
cc.LANGUAGE_ENGLISH = 0
cc.LANGUAGE_CHINESE = 1
cc.PLATFORM_OS_WINDOWS = 4
cc.PLATFORM_OS_MAC = 5
cc.PLATFORM_OS_LINUX = 6
cc.PLATFORM_OS_ANDROID = 3
cc.PLATFORM_OS_IPHONE = 2
cc.PLATFORM_OS_IPAD = 1
local app = {
    getCurrentLanguage = function() return cc.LANGUAGE_ENGLISH end,
    getTargetPlatform = function() return cc.PLATFORM_OS_WINDOWS end,
}
cc.Application = { getInstance = function() return app end }
cc.FileUtils = {
    getInstance = function()
        return { getWritablePath = function() return "sim_save/" end }
    end,
}
cc.UserDefault = {
    getInstance = function()
        return {
            getStringForKey = function() return "" end,
            getIntegerForKey = function(_, d) return d or 0 end,
            getBoolForKey = function(_, d) return d or false end,
            getDoubleForKey = function(_, d) return d or 0 end,
            setStringForKey = function() end,
            setIntegerForKey = function() end,
            setBoolForKey = function() end,
            setDoubleForKey = function() end,
            flush = function() end,
        }
    end,
}
cc.Director = {
    getInstance = function()
        return {
            getTextureCache = function() return {} end,
            getScheduler = function()
                return { scheduleScriptFunc = function() return 1 end }
            end,
            getRunningScene = function() return nil end,
        }
    end,
}

-- ---------------------------------------------------------------------------
-- Load real game modules
-- ---------------------------------------------------------------------------
package.path = "decrypted/src/?.lua;" .. "decrypted/?.lua;" .. package.path

local time = require "manager.time"
time:Init()
check(time:Now() > 0, "manager.time loads and Now() works")

-- game boot extensions (string.split, table.*, class, etc.)
require "common.ext.init"

local data_template = require "manager.data_template"
data_template:Init()
-- the game loads one CSV per frame; loop until complete (same as global.lua scheduler)
while not data_template.is_load_complete do
    data_template:LoadFromCSV()
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
check(count(data_template.pve_play_config) > 0, "data_template loads PvE config (" .. count(data_template.pve_play_config) .. " rows)")
check(count(data_template.card_config) > 0, "data_template loads card config (" .. count(data_template.card_config) .. " rows)")
check(count(data_template.item_config) > 0, "data_template loads item config (" .. count(data_template.item_config) .. " rows)")
check(count(data_template.task_config) > 0, "data_template loads task config (" .. count(data_template.task_config) .. " rows)")

-- ---------------------------------------------------------------------------
-- network + login
-- ---------------------------------------------------------------------------
local network = require "manager.network"
network:RegisterProto()
local err, status = network:Connect("offline", 28800)
check(err == nil and status == 3, "Connect returns connected (err=" .. tostring(err) .. " status=" .. tostring(status) .. ")")

local login_res
network:Send("req_login_game", {name="sim_player", token="sim", type="debug", channel="debug", language="en-US", version="1.4"}, function(result, recv_msg)
    login_res = {result = result, recv = recv_msg}
end)
check(login_res.result == "success", "req_login_game succeeds")
check(login_res.recv.user_id == "sim_player", "login returns user_id")
check(login_res.recv.server_time ~= nil, "login returns server_time")

-- ---------------------------------------------------------------------------
-- startup queries (same as login.lua InitLoadingProgress)
-- ---------------------------------------------------------------------------
local queries = {
    {"query_base_info", "query_base_info"},
    {"query_resource_info", "resource_logic:Query"},
    {"req_deck_info_panel", "deck_logic:QueryDeckInfo"},
    {"req_card_info_panel", "deck_logic:QueryCardInfo"},
    {"query_chest_info", "chest_logic:Query"},
    {"query_arena_info", "arena_logic:Query"},
    {"req_refresh_daily", "daily_logic:Query"},
    {"query_overview_info", "user_logic:QueryOverviewInfo"},
    {"req_pve_play_info", "pve_logic:ReqPveInfoOnLogin"},
    {"req_task_info", "task_logic:Query"},
    {"req_guide_panel", "guide_logic:Query"},
}
local results = {}
for _, q in ipairs(queries) do
    local req = q[1]
    network:Send(req, {}, function(result, recv_msg)
        results[req] = {result = result, recv = recv_msg or {}}
    end)
    check(results[req].result == "success", q[2] .. " -> success")
end

check(results["query_base_info"].recv.name ~= nil and results["query_base_info"].recv.level ~= nil, "query_base_info has name/level")
check(results["query_resource_info"].recv.money ~= nil, "query_resource_info has money")
check(count(results["req_deck_info_panel"].recv.deck_info_list or {}) > 0, "req_deck_info_panel returns decks (" .. count(results["req_deck_info_panel"].recv.deck_info_list or {}) .. ")")
check(count(results["req_card_info_panel"].recv.card_info_list or {}) > 0, "req_card_info_panel returns cards (" .. count(results["req_card_info_panel"].recv.card_info_list or {}) .. ")")
check(results["query_overview_info"].recv.new_mail_num ~= nil, "query_overview_info has new_mail_num")

-- ---------------------------------------------------------------------------
-- full PvE battle vs AI
-- ---------------------------------------------------------------------------
local battle_events = {}
network:RegisterCommand("cmd_battle", function(msg)
    table.insert(battle_events, msg)
end)

local pve_start_res
network:Send("req_pve_battle_start", {play_id = 1001, difficulty = 1, attack_type = 2}, function(result, recv_msg)
    pve_start_res = {result = result, recv = recv_msg}
end)
check(pve_start_res.result == "success", "req_pve_battle_start succeeds")

local offline_server = require "manager.offline_server"
local b = offline_server.current_battle
assert(b, "no current battle after pve start")
local turns = 0
while not b.is_over and turns < 60 do
    turns = turns + 1
    -- prep: sacrifice hand cards until a monster is affordable (human-like)
    local guard = 0
    while b.own.is_sacrifice and guard < 12 do
        guard = guard + 1
        local affordable = false
        for p = 1, 4 do
            local c = b.own:GetHandCard(p)
            if c and c.type == "monster" and c.cost <= b.own.cur_crystal and b.own:GetCurMonsterSlotPos() > 0 then
                affordable = true
            end
        end
        if affordable then break end
        local sac_p = nil
        for p = 1, 4 do
            if b.own:GetHandCard(p) then sac_p = p break end
        end
        if not sac_p then break end
        b:HandleSacrifice({is_hand = true, pos = sac_p})
    end
    -- deploy everything affordable
    for p = 1, 4 do
        local c = b.own:GetHandCard(p)
        if c and c.cost and c.cost <= b.own.cur_crystal then
            if c.type == "monster" then
                local slot = b.own:GetCurMonsterSlotPos()
                if slot > 0 then
                    b:HandleMove({src_pos = p, is_enemy = false, target_pos = slot})
                end
            else
                for s = 1, 3 do
                    local slot = b.own:GetBattleCard(s)
                    if slot and slot.monster then
                        b:HandleMove({src_pos = p, is_enemy = false, target_pos = s})
                        break
                    end
                end
            end
        end
    end
    -- end turn -> enemy AI + combat
    b:HandleAttack({})
end
check(b.is_over == true, "battle reaches game over (rounds=" .. tostring(b.round) .. ", turns=" .. tostring(turns) .. ")")
print("    winner = " .. tostring(b.win_user_id))

-- ---------------------------------------------------------------------------
-- save persistence
-- ---------------------------------------------------------------------------
network:Connect("offline", 28800)
local relogin_res
network:Send("req_login_game", {name="sim_player", token="sim", type="debug", channel="debug", language="en-US", version="1.4"}, function(result, recv_msg)
    relogin_res = {result = result, recv = recv_msg}
end)
check(relogin_res.result == "success", "re-login after save works")

-- ---------------------------------------------------------------------------
-- expected battle commands were emitted
-- ---------------------------------------------------------------------------
local cmd_names = {}
for _, msg in ipairs(battle_events) do
    for k in pairs(msg) do
        cmd_names[k] = true
    end
end
for _, needed in ipairs({"cmd_battle_start", "cmd_battle_init", "cmd_battle_round", "cmd_battle_prepa", "cmd_battle_over"}) do
    check(cmd_names[needed] == true, "battle emitted " .. needed)
end

print()
if failures > 0 then
    print("RESULT: " .. failures .. " FAILURE(S)")
    os.exit(1)
end
print("RESULT: ALL CHECKS PASSED")
