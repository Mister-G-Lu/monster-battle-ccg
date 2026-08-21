-- campaign_client_test.lua
-- Client-side half of the Shadow Road battle button: req_campaign_battle_start
-- through the REAL offline server, with the client (logic.battle) consuming
-- the same command queue the device consumes.  Verifies what the Android
-- player sees when they tap Battle -> a campaign node:
--   * cmd_battle_start pushes the battle scene for battle_type "campaign"
--   * cmd_battle_init does NOT swap sides (own = logged-in user id)
--   * cmd_battle_hero syncs both commanders' HP -> "update_hero_hp"
--   * battle over dispatches "refresh_campaign" so the map refreshes
-- Run under LuaJIT after scripts/setup_test_env.py:
--     luajit tests/campaign_client_test.lua

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
-- Stubs (same shape as guide_battle_test; the device provides these)
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
cc.PLATFORM_OS_MAC = 5
cc.PLATFORM_OS_LINUX = 6
cc.PLATFORM_OS_ANDROID = 3
cc.PLATFORM_OS_IPHONE = 2
cc.PLATFORM_OS_IPAD = 1
cc.Application = { getInstance = function() return {
    getCurrentLanguage = function() return cc.LANGUAGE_ENGLISH end,
    getTargetPlatform = function() return cc.PLATFORM_OS_WINDOWS end } end }
cc.FileUtils = { getInstance = function() return {
    getWritablePath = function() return "sim_save_campaign_client/" end } end }
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

if not dump then function dump(...) end end

-- capture the graphic events the campaign panel / battle HUD subscribe to
local dispatched = {}
local pushed_scenes = {}
package.loaded["manager.global"] = {
    PushScene = function(self, name) table.insert(pushed_scenes, name) end,
    PopScene = function(self) end,
    ChangeScene = function(self, name) table.insert(pushed_scenes, name) end,
}
package.loaded["manager.graphic"] = {
    -- battle code calls graphic:DispatchEvent("name", ...) colon-style
    DispatchEvent = function(self, name, ...)
        dispatched[name] = dispatched[name] or {}
        table.insert(dispatched[name], { ... })
    end,
    RegisterEvent = function() end,
}
package.loaded["manager.analytics"] = {
    DoBattleStart = function() end, DoCasualMatchOver = function() end,
    DoBattleOver = function() end,
}

local user_stub = { user_id = nil }
package.loaded["logic.user"] = user_stub
package.loaded["logic.pve"] = {
    play_id = nil, difficulty = nil, cur_difficulty = nil,
    login_pve_data = {{}}, adv_passid = {}, adv_progress = nil,
}
package.loaded["logic.arena"] = {
    SetLastEloValue = function() end, GetEloValue = function() return 1000 end,
    SetLastLevel = function() end, GetLevel = function() return 1 end,
    SetEloValue = function() end, SetLevel = function() end, SetStage = function() end,
    arena_stage = nil,
}
package.loaded["logic.challenge"] = {}

package.path = "decrypted/src/?.lua;decrypted/?.lua;" .. package.path

-- loaded early so the frame-model closures below capture this local
local battle_logic = require "logic.battle"

-- ---------------------------------------------------------------------------
-- Shared battle-scene frame model (mirrors guide_battle_test: the device's
-- match panel + animation events drive the command queue forward).
-- ---------------------------------------------------------------------------
local frame_model = {}

function frame_model.new(opts)
    return {
        t = 0,
        dt = 1 / 30,
        frames = 0,
        scene_ready_frames = opts.scene_ready_frames or 6,
        panel_state = "hidden",
        shown_at = nil,
        ready_end_at = nil,
        anim_events = {},
        fire_ready_anim = opts.fire_ready_anim ~= false,
        observed = {},
        battle_over_at = nil,
    }
end

function frame_model.register_panel_events(m)
    battle_logic:RegisterEvent("init_player_info", function(own, enemy)
        m.observed.init_player_info = { own = own, enemy = enemy }
    end)
    battle_logic:RegisterEvent("battle_panel_standby", function()
        m.observed.battle_panel_standby = (m.observed.battle_panel_standby or 0) + 1
    end)
    battle_logic:RegisterEvent("gold_coin_ready", function()
        m.observed.gold_coin_ready = (m.observed.gold_coin_ready or 0) + 1
    end)
    battle_logic:RegisterEvent("drop_hand_monster_card", function(src_pos, tar_pos, callback)
        if callback then callback() end
        battle_logic.is_play_animation = false
    end)
    battle_logic:RegisterEvent("item_hand_card", function(src_pos, tar_pos, callback)
        if callback then callback() end
    end)
    battle_logic:RegisterEvent("consume_hand_card", function(src_pos, tar_pos, callback)
        if callback then callback() end
    end)
    battle_logic:RegisterEvent("discard_hand_card", function(is_own, pos, is_sacrifice, callback)
        if callback then callback() end
    end)
    battle_logic:RegisterEvent("do_power_animation", function(tar_user_id, tar_pos, tar_pos_list, power_name, src_user_id, src_pos, value, callback)
        if callback then callback() end
        battle_logic:DispatchEvent("sub_event_complete")
    end)
    battle_logic:RegisterEvent("do_hit_animation", function(is_own, tar_pos, callback)
        if callback then callback() end
    end)
    battle_logic:RegisterEvent("do_dead_animation", function(is_own, tar_pos, callback)
        if callback then callback() end
    end)
    battle_logic:RegisterEvent("do_status_animation", function(is_own, tar_pos, status_name, status_round, status_value, callback)
        if callback then callback() end
    end)
    battle_logic:RegisterEvent("do_armor_block", function(tar_user_id, tar_pos)
        battle_logic:DispatchEvent("sub_event_complete")
    end)
    battle_logic:RegisterEvent("move_battle_card", function(is_own, src_pos, tar_pos, callback)
        if callback then callback() end
    end)
end

function frame_model.fire_frame_events(m)
    local remaining = {}
    for _, ev in ipairs(m.anim_events) do
        if m.t >= ev.t then
            if ev.name == "battlefield_enter" then
                battle_logic:DispatchEvent("battlefield_enter")
            elseif ev.name == "handcard_enter" then
                battle_logic:DispatchEvent("handcard_enter")
            elseif ev.name == "gold_coin_ready" then
                if battle_logic.start_type ~= "replay" or battle_logic.battle_status == 2 then
                    battle_logic:DispatchEvent("gold_coin_ready")
                    if m.fire_ready_anim then
                        m.ready_end_at = m.t + 0.8
                    end
                else
                    battle_logic:DispatchEvent("anim_complete", "gold_coin_ready")
                end
            end
        else
            table.insert(remaining, ev)
        end
    end
    m.anim_events = remaining
    if m.ready_end_at and m.t >= m.ready_end_at then
        m.ready_end_at = nil
        battle_logic:DispatchEvent("anim_complete", "gold_coin_ourside")
    end
end

local function auto_play_turn(m)
    if battle_logic.is_play_animation then return end
    if battle_logic.cur_stage ~= battle_logic.STAGE.own then return end
    local own = battle_logic.own_player
    if own.is_sacrifice then
        for p = 1, 4 do
            if own:GetHandCard(p) then
                battle_logic:ReqSacrificeCard(true, p, function() end)
                return
            end
        end
        battle_logic:ReqBattleAttack("auto")
        return
    end
    if (m.move_attempts or 0) < 6 then
        for p = 1, 4 do
            local card = own:GetHandCard(p)
            if card and card.cost and card.cost <= own.cur_crystal then
                if card.type == "monster" then
                    local slot = own:GetCurMonsterSlotPos()
                    if slot and slot > 0 then
                        battle_logic:ReqBattleMove(p, false, slot, function() end)
                        m.move_attempts = (m.move_attempts or 0) + 1
                        return
                    end
                else
                    m.item_slot_cursor = (m.item_slot_cursor or 1)
                    local s = m.item_slot_cursor
                    m.item_slot_cursor = s % 3 + 1
                    local bs = own:GetBattleCard(s)
                    if bs and bs.monster then
                        battle_logic:ReqBattleMove(p, false, s, function() end)
                        m.move_attempts = (m.move_attempts or 0) + 1
                        return
                    end
                end
            end
        end
    end
    m.move_attempts = 0
    battle_logic:ReqBattleAttack("auto")
end

function frame_model.step(m)
    m.frames = m.frames + 1
    m.t = m.t + m.dt
    frame_model.fire_frame_events(m)

    if m.frames == m.scene_ready_frames then
        m.panel_state = "enter"
        m.shown_at = m.t
    end
    if m.panel_state == "enter" and m.t >= m.shown_at + 0.75 then
        m.panel_state = "loop"
        battle_logic:ReqBattleStandby()
    end
    if m.observed.battle_panel_standby and m.panel_state ~= "exit" then
        m.panel_state = "exit"
        table.insert(m.anim_events, { t = m.t + 0.20, name = "battlefield_enter" })
        table.insert(m.anim_events, { t = m.t + 0.35, name = "handcard_enter" })
        table.insert(m.anim_events, { t = m.t + 0.45, name = "gold_coin_ready" })
    end
    if m.frames >= m.scene_ready_frames then
        battle_logic:Update(m.dt)
    end
    if battle_logic.is_battle_over and m.battle_over_at == nil then
        m.battle_over_at = m.t
    end
end

function frame_model.run(m, max_frames, stop_when)
    max_frames = max_frames or 3000
    for i = 1, max_frames do
        frame_model.step(m)
        if stop_when and stop_when(m) then return end
        if not battle_logic.is_battle_over then
            auto_play_turn(m)
        end
    end
end

-- ---------------------------------------------------------------------------
section("1. Load modules + login")
require "common.ext.init"
local time = require "manager.time"
time:Init()

local network = require "manager.network"
network:RegisterProto()
network:Connect("campaign-client-test", 28800)

local data_template = require "manager.data_template"
data_template:Init()
data_template:LoadFromCSV()

local login_user_id = nil
network:Send("req_login_game",
    { name = "campaign_client", token = "sim", type = "debug", channel = "debug", language = "en-US", version = "1.4" },
    function(r, m)
        if r == "success" then login_user_id = m.user_id end
    end)
check(login_user_id ~= nil, "login succeeded, user_id=" .. tostring(login_user_id))
user_stub.user_id = login_user_id

local offline_server = require "manager.offline_server"
battle_logic:Init()

-- idempotent: wipe any progress a previous run left behind
local campaign_service = require "manager.campaign_service"
campaign_service.reset(offline_server:GetCampaignSave())
offline_server:Save()

-- the HUD event battle_ui_panel subscribes to for the commander HP labels
-- (registered AFTER the battle starts: cmd_battle_start -> Clean() rebuilds
-- the event table, exactly as the device scene does)
local observed = { hero = {} }

-- ---------------------------------------------------------------------------
section("2. Battle button: req_campaign_battle_start -> battle scene")
local start_res
network:Send("req_campaign_battle_start", { node_id = "w1" }, function(result, recv_msg)
    start_res = { result = result, recv = recv_msg }
end)
check(start_res and start_res.result == "success",
    "campaign battle start succeeds (" .. tostring(start_res and start_res.result) .. ")")
check(pushed_scenes[1] == "battle", "cmd_battle_start pushed the battle scene (got " .. tostring(pushed_scenes[1]) .. ")")
check(battle_logic.battle_type == "campaign", "battle_type is campaign (got " .. tostring(battle_logic.battle_type) .. ")")

local m = frame_model.new({})
frame_model.register_panel_events(m)
battle_logic:RegisterEvent("update_hero_hp", function(own_hp, own_max_hp, enemy_hp, enemy_max_hp)
    table.insert(observed.hero, { own_hp = own_hp, own_max_hp = own_max_hp, enemy_hp = enemy_hp, enemy_max_hp = enemy_max_hp })
end)

-- let the queue consume cmd_battle_init / round / hero / prepa
frame_model.run(m, 600, function(mm) return mm.observed.init_player_info ~= nil end)
check(battle_logic.own_player ~= nil and battle_logic.own_player.user_id == login_user_id,
    "no side swap: own_player is the logged-in player (own=" .. tostring(battle_logic.own_player and battle_logic.own_player.user_id)
        .. " login=" .. tostring(login_user_id) .. ")")
check(battle_logic.enemy_player ~= nil and battle_logic.enemy_player.user_id ~= login_user_id,
    "enemy_player is the AI side")
check(battle_logic.is_first == true, "player is the first actor")

-- ---------------------------------------------------------------------------
section("3. Commander HP shown: cmd_battle_hero -> update_hero_hp")
frame_model.run(m, 600, function() return #observed.hero >= 1 end)
check(#observed.hero >= 1, "update_hero_hp fired (" .. #observed.hero .. "x)")
if observed.hero[1] then
    local h = observed.hero[1]
    check(tostring(h.own_hp) == "30" and tostring(h.own_max_hp) == "30",
        "own commander HP 30/30 (got " .. tostring(h.own_hp) .. "/" .. tostring(h.own_max_hp) .. ")")
    check(tostring(h.enemy_hp) == "14" and tostring(h.enemy_max_hp) == "14",
        "w1 enemy commander HP 14/14 (got " .. tostring(h.enemy_hp) .. "/" .. tostring(h.enemy_max_hp) .. ")")
end

-- ---------------------------------------------------------------------------
section("4. Battle over -> campaign map refresh")
frame_model.run(m, 6000, function() return battle_logic.is_battle_over end)
check(battle_logic.is_battle_over, "campaign battle played to game over")
-- cmd_battle_over stays queued until its handler runs; let it drain
frame_model.run(m, 600, function() return #battle_logic.battle_command_queue == 0 end)
local last_refresh = dispatched["refresh_campaign"] and dispatched["refresh_campaign"][#dispatched["refresh_campaign"]]
check(last_refresh ~= nil, "refresh_campaign dispatched on battle over")
if last_refresh then
    local info = last_refresh[1] or {}
    check(info.node_id == "w1", "campaign_info carries node_id w1 (got " .. tostring(info.node_id) .. ")")
    check(info.victory == true or info.victory == false, "campaign_info has a victory flag")
end

-- ---------------------------------------------------------------------------
print("\n" .. string.rep("=", 60))
if failures == 0 then
    print("RESULT: ALL CAMPAIGN CLIENT CHECKS PASSED")
else
    print("RESULT: " .. failures .. " FAILED")
end
os.exit(failures == 0 and 0 or 1)
