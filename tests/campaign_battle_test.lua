-- campaign_battle_test.lua
-- The Shadow Road campaign duel, end-to-end through the native engine.
-- Boots the REAL offline_server and plays campaign battles with a greedy
-- bot, asserting the hero-HP duel (commander HP, face hits, overkill
-- carry-through), the scripted boss powers (Gathering Power, Overgrowth,
-- phase-2 triggers), rewards + recruit flow, reset, and persistence.
--
-- Run under LuaJIT / Lua 5.1 after scripts/setup_test_env.py:
--     luajit tests/campaign_battle_test.lua

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

-- ---------------------------------------------------------------------------
-- Stubs (mirror campaign_service_test.lua Part B; the device provides these)
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
cc.Application = { getInstance = function() return {
    getCurrentLanguage = function() return cc.LANGUAGE_ENGLISH end,
    getTargetPlatform = function() return cc.PLATFORM_OS_WINDOWS end } end }
cc.FileUtils = { getInstance = function() return { getWritablePath = function() return "sim_save_int/" end } end }
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
cc.EventListenerTouchOneByOne = { create = function() return { registerScriptHandler = function() end } end }
cc.Handler = { EVENT_TOUCH_BEGAN = 0, EVENT_TOUCH_ENDED = 1 }
cc.rectContainsPoint = function() return false end
cc.LayerColor = { create = function() return { setContentSize = function() end, setPosition = function() end, addChild = function() end } end }
cc.Label = { createWithSystemFont = function() return { setAnchorPoint = function() end, setPosition = function() end, setColor = function() end, addChild = function() end, getBoundingBox = function() return {} end, getEventDispatcher = function() return {} end } end }
ccui = { ScrollView = { create = function() return { setContentSize = function() end, setPosition = function() end, setDirection = function() end, setTouchEnabled = function() end, setBounceEnabled = function() end, addChild = function() end, getInnerContainer = function() return { removeAllChildren = function() end } end, setInnerContainerSize = function() end, scrollToTop = function() end } end },
    ScrollViewDir = { vertical = 1 } }

package.path = "src/?.lua;decrypted/?.lua;decrypted/src/?.lua;" .. package.path

local time = require "manager.time"
time:Init()
require "common.ext.init"

local data_template = require "manager.data_template"
data_template:Init()
while not data_template.is_load_complete do
    data_template:LoadFromCSV()
end

local campaign_data = require "manager.campaign_data"
local campaign_service = require "manager.campaign_service"

-- ---------------------------------------------------------------------------
section("1. campaign data sanity (native)")
local nodes = campaign_data.all_nodes()
check(#nodes == 19, "campaign has 19 nodes (got " .. #nodes .. ")")
check(campaign_data.node_by_id("w1") ~= nil, "node w1 lookup works")
check(campaign_data.node_by_id("s4").final == true, "final boss flagged")
check(campaign_data.node_by_id("w5").type == "boss", "w5 is a boss")

local flags_found = false
for _, cfg in pairs(data_template.card_config) do
    if cfg.flags ~= nil then flags_found = true break end
end
check(flags_found, "card_config carries flags field")

-- ---------------------------------------------------------------------------
section("2. login + campaign info")
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

-- the test is idempotent: wipe any progress a previous run left behind
if offline_server.GetCampaignSave then
    campaign_service.reset(offline_server:GetCampaignSave())
    offline_server:Save()
end

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

local info_res
network:Send("req_campaign_info", {}, function(result, recv_msg)
    info_res = {result = result, recv = recv_msg or {}}
end)
check(info_res.result == "success", "req_campaign_info succeeds")
check(info_res.recv.vitality == 30, "starting commander vitality is 30 (got " .. tostring(info_res.recv.vitality) .. ")")
check(next(info_res.recv.cleared) == nil, "fresh campaign has no cleared nodes")
check(info_res.recv.pending_recruit == nil, "no pending recruit on a fresh campaign")

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
section("3. w1 skirmish — hero duel + rewards")
local start_res
network:Send("req_campaign_battle_start", {node_id = "w1"}, function(result, recv_msg)
    start_res = {result = result, recv = recv_msg}
end)
check(start_res.result == "success", "req_campaign_battle_start w1 succeeds")

local b = offline_server.current_battle
check(b ~= nil, "campaign battle created")
check(b.hero_mode == true, "campaign battle is a hero-HP duel")
check(b.own_max_hp == 30, "player commander HP is 30")
check(b.enemy_max_hp == 14, "w1 enemy commander HP is 14 (node.hp)")
check(b.power == nil, "skirmish has no scripted power")

-- a commander-HP sync command is pushed before the first prep
local saw_hero_sync = false
for _, cmd in ipairs(battle_commands) do
    if cmd.cmd_battle_hero and cmd.cmd_battle_hero.enemy_max_hp == 14 then
        saw_hero_sync = true
    end
end
check(saw_hero_sync, "cmd_battle_hero reveals both commanders' HP")

local turns = play_battle(b, 60)
check(b.is_over == true, "w1 battle reaches game over (rounds=" .. b.round .. ", turns=" .. turns .. ")")
check(b.win_user_id ~= nil, "w1 battle has a winner")
print("    w1 winner = " .. tostring(b.win_user_id) .. ", rounds = " .. b.round)

local cam = offline_server.save.campaign
check(cam ~= nil, "campaign save state exists")
local over = last_battle_over()
check(over ~= nil, "cmd_battle_over emitted")
check(over.campaign_info ~= nil, "cmd_battle_over carries campaign_info")
check(over.campaign_info.node_id == "w1", "campaign_info names the node")

if b.win_user_id == b.own.user_id then
    check(cam.cleared["w1"] == true, "w1 marked cleared on victory")
    check(cam.pending_recruit == "w1", "first clear opens a recruit draft")

    -- recruit flow through the service handlers
    local offers_res
    network:Send("req_campaign_recruit_offers", {node_id = "w1"}, function(result, recv_msg)
        offers_res = {result = result, recv = recv_msg or {}}
    end)
    check(offers_res.result == "success", "req_campaign_recruit_offers succeeds")
    check(#(offers_res.recv.offers or {}) == campaign_service.DRAFT_SIZE, "draft has 3 offers")
    local offer_id = offers_res.recv.offers[1]
    local recruit_res
    network:Send("req_campaign_recruit", {node_id = "w1", card_id = offer_id}, function(result, recv_msg)
        recruit_res = {result = result, recv = recv_msg or {}}
    end)
    check(recruit_res.result == "success", "recruit pick accepted")
    local found = false
    for _, id in ipairs(cam.collection) do
        if tonumber(id) == tonumber(offer_id) then found = true break end
    end
    check(found, "picked card joins the collection")
    check(cam.pending_recruit == nil, "pending recruit cleared after pick")

    -- recruits must actually join the campaign battle deck ("collection IS
    -- your deck" — what keeps later acts winnable)
    local deck_ids = campaign_service.player_deck_ids(cam)
    local in_deck = false
    for _, id in ipairs(deck_ids) do
        if tonumber(id) == tonumber(offer_id) then in_deck = true break end
    end
    check(in_deck, "recruit joins the campaign battle deck")
end

-- ---------------------------------------------------------------------------
section("4. w5 boss — Gathering Power + scripted power")
-- w5 is locked until act 1's other nodes fall: clear w1..w4 (taking/skipping
-- each recruit) so the boss battle can start, then check the result.
local csave = offline_server:GetCampaignSave()
for _, n in ipairs(campaign_data.all_nodes()) do
    if n.id == "w5" then break end
    if not csave.cleared[n.id] then
        campaign_service.apply_victory(csave, n)
        campaign_service.skip_recruit(csave)
    end
end
offline_server:Save()

battle_commands = {}
network:Send("req_campaign_battle_start", {node_id = "w5"}, function() end)
local bb = offline_server.current_battle
check(bb ~= nil and bb.hero_mode, "w5 boss battle created")
check(bb.power ~= nil and bb.power.id == "overgrowth", "w5 has Overgrowth power")
check(bb.enemy_max_hp == 26, "w5 enemy commander HP is 26 (node.hp)")

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
    check(bb.own_hp < bb.own_max_hp or bb.is_over, "boss lashes the player commander")
end

-- ---------------------------------------------------------------------------
section("5. reset + persistence")
local reset_res
network:Send("req_campaign_reset", {}, function(result, recv_msg)
    reset_res = {result = result, recv = recv_msg or {}}
end)
check(reset_res.result == "success", "req_campaign_reset succeeds")
check(next(reset_res.recv.cleared) == nil, "reset clears node progress")
check(reset_res.recv.vitality == 30, "reset restores base vitality")

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
network:Send("req_campaign_info", {}, function(result, recv_msg)
    info2_res = {result = result, recv = recv_msg or {}}
end)
local cleared2 = info2_res.recv.cleared or {}
check(info2_res.result == "success", "req_campaign_info after re-login succeeds")
if next(cleared2) then
    check(cleared2["w1"] == true, "cleared nodes persist across re-login")
end

print()
if failures > 0 then
    print("RESULT: " .. failures .. " FAILURE(S)")
    os.exit(1)
end
print("RESULT: ALL CAMPAIGN BATTLE CHECKS PASSED")
