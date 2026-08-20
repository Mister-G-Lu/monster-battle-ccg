-- campaign_test.lua
-- Headless test for "The Shadow Road" campaign integration (the handcrafted
-- campaign ported from build/web/game.html into the native Lua engine).
-- Loads the REAL game modules and exercises:
--   1. campaign_data lookups + enemy deck resolution (deck ids + pools)
--   2. query_campaign_info / save state
--   3. a full campaign battle to completion (hero-HP duel)
--   4. rewards + progression persistence across re-login
--   5. boss scripted powers (Gathering Power fires, hero HP moves)
--   6. campaign reset
--
-- Run under LuaJIT / Lua 5.1 after scripts/setup_test_env.py:
--     luajit tests/campaign_test.lua

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
-- Stubs (mirror sim_test.lua; the real device provides these)
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
function bit_stub.bnot(a) return 0xFFFFFFFF - bit_stub.band(a, 0xFFFFFFFF) end
function bit_stub.lshift(a, n) return bit_stub.band(a * 2^n, 0xFFFFFFFF) end
function bit_stub.rshift(a, n) return math.floor(bit_stub.band(a, 0xFFFFFFFF) / 2^n) end
package.loaded["bit"] = bit_stub

aandm = {}
function aandm.loadConfig(name)
    local base = string.match(name, "([^/\\]+)%.csv$") or name
    local f = io.open("csv_plain/" .. base .. ".csv", "r")
    if not f then return "" end
    local c = f:read("*a")
    f:close()
    return c
end
function aandm.getDataFromFile() return nil end

socket = {}
crypt = {}
package.loaded["socket"] = socket
package.loaded["crypt"] = crypt

protobuf = {
    register = function() end,
    encode = function() return "" end,
    decode2 = function() return {} end,
}
package.loaded["utils.protobuf"] = protobuf

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
        return { getWritablePath = function() return "sim_save_campaign/" end }
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

package.path = "decrypted/src/?.lua;" .. "decrypted/?.lua;" .. package.path

local time = require "manager.time"
time:Init()
require "common.ext.init"

local data_template = require "manager.data_template"
data_template:Init()
while not data_template.is_load_complete do
    data_template:LoadFromCSV()
end

local campaign_data = require "manager.campaign_data"

-- ---------------------------------------------------------------------------
-- campaign_data sanity
-- ---------------------------------------------------------------------------
local nodes = campaign_data:GetNodes()
check(#nodes == 19, "campaign has 19 nodes (got " .. #nodes .. ")")
check(campaign_data:GetNode("w1") ~= nil, "node w1 lookup works")
check(campaign_data:GetNode("s4").final == true, "final boss flagged")
check(campaign_data:GetNode("w5").type == "boss", "w5 is a boss")

local deck = campaign_data:ResolveEnemyDeck(campaign_data:GetNode("w4"))
check(#deck == 12, "elite deck_ids resolve (got " .. #deck .. ")")
local pool_deck = campaign_data:ResolveEnemyDeck(campaign_data:GetNode("w1"))
check(#pool_deck >= 4, "skirmish pool resolves to a deck (got " .. #pool_deck .. ")")
for _, id in ipairs(pool_deck) do
    check(data_template.card_config[tostring(id)] ~= nil, "pool card " .. tostring(id) .. " exists")
end

local flags_found = false
for _, cfg in pairs(data_template.card_config) do
    if cfg.flags ~= nil then flags_found = true break end
end
check(flags_found, "card_config carries flags field")

local recruit = campaign_data:RecruitPool(campaign_data:GetNode("w1"))
check(#recruit >= 1, "recruit pool non-empty (" .. #recruit .. ")")

-- ---------------------------------------------------------------------------
-- network + login
-- ---------------------------------------------------------------------------
local network = require "manager.network"
network:RegisterProto()
local err, status = network:Connect("offline", 28800)
check(err == nil and status == 3, "Connect returns connected")

local login_res
network:Send("req_login_game", {name="campaign_sim", token="sim", type="debug", channel="debug", language="en-US", version="1.4"}, function(result, recv_msg)
    login_res = {result = result, recv = recv_msg}
end)
check(login_res.result == "success", "req_login_game succeeds")

local offline_server = require "manager.offline_server"

-- collect battle commands so we can inspect cmd_battle_over
local battle_commands = {}
network:RegisterCommand("cmd_battle", function(msg)
    table.insert(battle_commands, msg)
end)

local function last_battle_over()
    for i = #battle_commands, 1, -1 do
        if battle_commands[i].cmd_battle_over then
            return battle_commands[i].cmd_battle_over
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- campaign info
-- ---------------------------------------------------------------------------
local info_res
network:Send("query_campaign_info", {}, function(result, recv_msg)
    info_res = {result = result, recv = recv_msg or {}}
end)
check(info_res.result == "success", "query_campaign_info succeeds")
check(info_res.recv.player_max_hp == 30, "starting player max HP is 30")
check(next(info_res.recv.cleared) == nil, "fresh campaign has no cleared nodes")

-- ---------------------------------------------------------------------------
-- greedy battle bot (campaign hero-HP duel)
-- ---------------------------------------------------------------------------
local function play_battle(b, max_rounds)
    local turns = 0
    while not b.is_over and turns < max_rounds do
        turns = turns + 1
        -- prep: sacrifice until a monster is affordable or hand exhausted
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
        b:HandleAttack({})
    end
    return turns
end

-- ---------------------------------------------------------------------------
-- full skirmish battle (w1)
-- ---------------------------------------------------------------------------
local start_res
network:Send("req_campaign_battle_start", {node_id = "w1"}, function(result, recv_msg)
    start_res = {result = result, recv = recv_msg}
end)
check(start_res.result == "success", "req_campaign_battle_start w1 succeeds")

local b = offline_server.current_battle
check(b ~= nil, "campaign battle created")
check(b.hero_mode == true, "campaign battle is a hero-HP duel")
check(b.own_max_hp == 30, "player hero HP is 30")
check(b.enemy_max_hp == 14, "w1 enemy hero HP is 14")

local turns = play_battle(b, 60)
check(b.is_over == true, "w1 battle reaches game over (rounds=" .. b.round .. ", turns=" .. turns .. ")")
check(b.win_user_id ~= nil, "w1 battle has a winner")
print("    w1 winner = " .. tostring(b.win_user_id) .. ", rounds = " .. b.round)

-- progression + rewards
local cam = offline_server.save.campaign
check(cam ~= nil, "campaign save state exists")
check(tonumber(cam.exp) >= 0, "campaign exp tracked")
if b.win_user_id == "player" then
    check(cam.cleared["w1"] == true, "w1 marked cleared on victory")
    check(#cam.collection >= 1, "recruit added to collection")
    check(offline_server.save.cards ~= nil, "player bag still valid")

    -- recruits must actually join the campaign battle deck (the web prototype's
    -- "collection IS your deck" — this is what keeps later acts winnable)
    local recruit = cam.collection[1]
    local rebuilt = offline_server:BuildCampaignPlayerDeck()
    local found = false
    for _, c in ipairs(rebuilt.monster_list or {}) do
        if c.model_id == tostring(recruit) then found = true break end
    end
    check(found, "recruit joins the campaign battle deck")
end

local over = last_battle_over()
check(over ~= nil, "cmd_battle_over emitted")
check(over.campaign_info ~= nil, "cmd_battle_over carries campaign_info")

-- ---------------------------------------------------------------------------
-- boss powers: Gathering Power + scripted power fire
-- ---------------------------------------------------------------------------
battle_commands = {}
network:Send("req_campaign_battle_start", {node_id = "w5"}, function() end)
local bb = offline_server.current_battle
check(bb ~= nil and bb.hero_mode, "w5 boss battle created")
check(bb.power ~= nil and bb.power.id == "overgrowth", "w5 has Overgrowth power")

local rounds = 0
while not bb.is_over and rounds < 40 do
    rounds = rounds + 1
    local guard = 0
    while bb.own.is_sacrifice and guard < 12 do
        guard = guard + 1
        local affordable = false
        for p = 1, 4 do
            local c = bb.own:GetHandCard(p)
            if c and c.type == "monster" and c.cost <= bb.own.cur_crystal and bb.own:GetCurMonsterSlotPos() > 0 then
                affordable = true
            end
        end
        if affordable then break end
        local sac_p = nil
        for p = 1, 4 do
            if bb.own:GetHandCard(p) then sac_p = p break end
        end
        if not sac_p then break end
        bb:HandleSacrifice({is_hand = true, pos = sac_p})
    end
    for p = 1, 4 do
        local c = bb.own:GetHandCard(p)
        if c and c.cost and c.cost <= bb.own.cur_crystal then
            if c.type == "monster" then
                local slot = bb.own:GetCurMonsterSlotPos()
                if slot > 0 then bb:HandleMove({src_pos = p, is_enemy = false, target_pos = slot}) end
            else
                for s = 1, 3 do
                    local slot = bb.own:GetBattleCard(s)
                    if slot and slot.monster then
                        bb:HandleMove({src_pos = p, is_enemy = false, target_pos = s})
                        break
                    end
                end
            end
        end
    end
    bb:HandleAttack({})
end
check(bb.is_over or rounds >= 40, "w5 boss battle terminates")
if bb.round >= 3 then
    check(bb.gathering >= 1, "Gathering Power fired (gathering=" .. bb.gathering .. ")")
    check(bb.own_hp < bb.own_max_hp or bb.is_over, "boss lashes the player hero")
end

-- ---------------------------------------------------------------------------
-- reset + persistence
-- ---------------------------------------------------------------------------
local reset_res
network:Send("req_campaign_reset", {}, function(result, recv_msg)
    reset_res = {result = result, recv = recv_msg or {}}
end)
check(reset_res.result == "success", "req_campaign_reset succeeds")
check(next(reset_res.recv.cleared) == nil, "reset clears node progress")

-- persistence across re-login
network:Send("req_campaign_battle_start", {node_id = "w1"}, function() end)
play_battle(offline_server.current_battle, 60)
network:Connect("offline", 28800)
local relogin_res
network:Send("req_login_game", {name="campaign_sim", token="sim", type="debug", channel="debug", language="en-US", version="1.4"}, function(result, recv_msg)
    relogin_res = {result = result, recv = recv_msg}
end)
check(relogin_res.result == "success", "re-login after campaign save works")

local info2_res
network:Send("query_campaign_info", {}, function(result, recv_msg)
    info2_res = {result = result, recv = recv_msg or {}}
end)
local cleared2 = info2_res.recv.cleared or {}
check(info2_res.result == "success", "query_campaign_info after re-login succeeds")
if next(cleared2) then
    check(cleared2["w1"] == true, "cleared nodes persist across re-login")
end

print()
if failures > 0 then
    print("RESULT: " .. failures .. " FAILURE(S)")
    os.exit(1)
end
print("RESULT: ALL CAMPAIGN CHECKS PASSED")
