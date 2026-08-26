-- battle_stall_test.lua
-- Regression: "battling stalls forever on the enemy's decision".
--
-- On a device whose battle animations do not report completion (a missing
-- spine/animation resource, or a Cocos timeline that never reaches its last
-- frame), logic.battle freezes:
--
--   * cmd_battle_attack sets sub_event_complete = false and only the
--     animation callback sets it back to true.  If the callback never fires,
--     the command at the head of battle_command_queue is re-dispatched every
--     frame and returns immediately -- the queue never advances.
--   * The player cannot act either: cur_stage is wait/enemy, so
--     ReqBattleAttack() is a no-op.  The screen sits on the enemy's turn
--     forever.
--
-- This test replays a real campaign battle (w1, through the real offline
-- server) with EVERY animation callback swallowed, exactly as the broken
-- device behaves, and asserts the battle still finishes and the player gets
-- their turn back.  Run under LuaJIT after scripts/setup_test_env.py:
--     luajit tests/battle_stall_test.lua

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
-- Stubs (same shape as campaign_client_test.lua; the device provides these)
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
cc.PLATFORM_OS_ANDROID = 3
cc.Application = { getInstance = function() return {
    getCurrentLanguage = function() return cc.LANGUAGE_ENGLISH end,
    getTargetPlatform = function() return cc.PLATFORM_OS_WINDOWS end } end }
cc.FileUtils = { getInstance = function() return {
    getWritablePath = function() return "sim_save_stall/" end } end }
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

local dispatched = {}
local pushed_scenes = {}
package.loaded["manager.global"] = {
    PushScene = function(self, name) table.insert(pushed_scenes, name) end,
    PopScene = function(self) end,
    ChangeScene = function(self, name) table.insert(pushed_scenes, name) end,
}
package.loaded["manager.graphic"] = {
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

local battle_logic = require "logic.battle"

-- ---------------------------------------------------------------------------
-- Frame model: identical to campaign_client_test.lua except that EVERY
-- animation callback is swallowed.  Nothing ever reports "animation done".
-- ---------------------------------------------------------------------------
local m = {
    t = 0,
    dt = 1 / 30,
    frames = 0,
    scene_ready_frames = 6,
    anim_events = {},
    longest_non_own = 0,   -- frames spent continuously off the player's turn
    cur_non_own = 0,
    sub_event_rescues = 0,
}

local function register_silent_panel_events()
    battle_logic:RegisterEvent("init_player_info", function(own, enemy)
        m.init_player_info = { own = own, enemy = enemy }
    end)
    battle_logic:RegisterEvent("battle_panel_standby", function()
        m.battle_panel_standby = (m.battle_panel_standby or 0) + 1
    end)
    -- Every animation event below is the shape the device's battle scene
    -- subscribes to.  A healthy device calls `callback()` (and, for power
    -- animations, dispatches "sub_event_complete") when the animation ends.
    -- This device never does.
    battle_logic:RegisterEvent("drop_hand_monster_card", function() end)
    battle_logic:RegisterEvent("item_hand_card", function() end)
    battle_logic:RegisterEvent("consume_hand_card", function() end)
    battle_logic:RegisterEvent("discard_hand_card", function() end)
    battle_logic:RegisterEvent("do_power_animation", function() end)
    battle_logic:RegisterEvent("do_hit_animation", function() end)
    battle_logic:RegisterEvent("do_dead_animation", function() end)
    battle_logic:RegisterEvent("do_status_animation", function() end)
    battle_logic:RegisterEvent("do_armor_block", function() end)
    battle_logic:RegisterEvent("move_battle_card", function() end)
end

local function fire_frame_events()
    local remaining = {}
    for _, ev in ipairs(m.anim_events) do
        if m.t >= ev.t then
            if ev.name == "battlefield_enter" then
                battle_logic:DispatchEvent("battlefield_enter")
            elseif ev.name == "handcard_enter" then
                battle_logic:DispatchEvent("handcard_enter")
            elseif ev.name == "gold_coin_ready" then
                battle_logic:DispatchEvent("gold_coin_ready")
                -- note: the "anim_complete" the match panel normally sends at
                -- the end of the coin flip is deliberately never dispatched
            end
        else
            table.insert(remaining, ev)
        end
    end
    m.anim_events = remaining
end

local function auto_play_turn()
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

local function step()
    m.frames = m.frames + 1
    m.t = m.t + m.dt
    fire_frame_events()

    if m.frames == m.scene_ready_frames then
        m.shown_at = m.t
    end
    if m.shown_at and m.t >= m.shown_at + 0.75 and not m.standby_sent then
        m.standby_sent = true
        battle_logic:ReqBattleStandby()
    end
    if m.battle_panel_standby and not m.entered then
        m.entered = true
        table.insert(m.anim_events, { t = m.t + 0.20, name = "battlefield_enter" })
        table.insert(m.anim_events, { t = m.t + 0.35, name = "handcard_enter" })
        table.insert(m.anim_events, { t = m.t + 0.45, name = "gold_coin_ready" })
    end

    if m.frames >= m.scene_ready_frames then
        battle_logic:Update(m.dt)
    end

    -- how long the player is locked out of their own turn, in one stretch
    if battle_logic.cur_stage == battle_logic.STAGE.own
        or battle_logic.cur_stage == battle_logic.STAGE.over then
        m.cur_non_own = 0
    else
        m.cur_non_own = m.cur_non_own + 1
        if m.cur_non_own > m.longest_non_own then
            m.longest_non_own = m.cur_non_own
        end
    end
end

local function run(max_frames, stop_when)
    for _ = 1, max_frames do
        step()
        if stop_when and stop_when() then return end
        if not battle_logic.is_battle_over then
            auto_play_turn()
        end
    end
end

-- ---------------------------------------------------------------------------
section("1. Boot the real engine + start a campaign battle")
require "common.ext.init"
local time = require "manager.time"
time:Init()

local network = require "manager.network"
network:RegisterProto()
network:Connect("battle-stall-test", 28800)

local data_template = require "manager.data_template"
data_template:Init()
data_template:LoadFromCSV()

local login_user_id
network:Send("req_login_game",
    { name = "stall", token = "sim", type = "debug", channel = "debug", language = "en-US", version = "1.4" },
    function(r, msg) if r == "success" then login_user_id = msg.user_id end end)
check(login_user_id ~= nil, "login succeeded, user_id=" .. tostring(login_user_id))
user_stub.user_id = login_user_id

local offline_server = require "manager.offline_server"
battle_logic:Init()

local campaign_service = require "manager.campaign_service"
campaign_service.reset(offline_server:GetCampaignSave())
offline_server:Save()

local start_res
network:Send("req_campaign_battle_start", { node_id = "w1" }, function(result, recv)
    start_res = { result = result, recv = recv }
end)
check(start_res and start_res.result == "success", "campaign battle w1 started")
register_silent_panel_events()

-- ---------------------------------------------------------------------------
section("2. Animations never report completion -> the battle must still finish")
run(600, function() return m.init_player_info ~= nil end)
check(m.init_player_info ~= nil, "cmd_battle_init processed (battle scene came up)")

-- 6000 frames = 200s of wall clock at 30fps.  A healthy client finishes w1 in
-- well under a second of simulated time; a stalled one never finishes at all.
run(6000, function() return battle_logic.is_battle_over end)
check(battle_logic.is_battle_over,
    "battle reached game over with every animation callback swallowed"
        .. " (frames=" .. m.frames .. ", round=" .. tostring(battle_logic.round) .. ")")

run(600, function() return #battle_logic.battle_command_queue == 0 end)
check(#battle_logic.battle_command_queue == 0,
    "command queue drained after game over (pending=" .. #battle_logic.battle_command_queue .. ")")

-- ---------------------------------------------------------------------------
section("3. The player is never locked out of their turn")
-- 30fps.  A long fight legitimately replays commands for several seconds
-- while the player waits, so this is a generous ceiling: a soft-lock shows up
-- as thousands of frames off-turn, healthy playback as a few hundred.
local budget_frames = 30 * 30
check(m.longest_non_own < budget_frames,
    string.format("longest stretch off the player's turn was %d frames (< %d, ~%.1fs)",
        m.longest_non_own, budget_frames, m.longest_non_own * m.dt))

-- ---------------------------------------------------------------------------
section("4. A second battle on the same client also finishes")
-- Init() -> Clean() rebuilds command_handler, so the scene re-subscribes
-- exactly as the device does when it re-enters the battle scene.
battle_logic:Init()
m.init_player_info = nil
m.battle_panel_standby = nil
m.entered = nil
m.standby_sent = nil
m.shown_at = nil
m.anim_events = {}
m.longest_non_own = 0
m.cur_non_own = 0

network:Send("req_campaign_battle_start", { node_id = "w1" }, function(result, recv)
    start_res = { result = result, recv = recv }
end)
check(start_res and start_res.result == "success", "second campaign battle w1 started")
register_silent_panel_events()
run(600, function() return m.init_player_info ~= nil end)
run(6000, function() return battle_logic.is_battle_over end)
check(battle_logic.is_battle_over, "second battle reached game over too (frames=" .. m.frames .. ")")
check(m.longest_non_own < 30 * 30,
    string.format("second battle: longest stretch off-turn was %d frames", m.longest_non_own))

-- ---------------------------------------------------------------------------
print("\n" .. string.rep("=", 60))
if failures == 0 then
    print("RESULT: ALL BATTLE STALL CHECKS PASSED")
else
    print("RESULT: " .. failures .. " FAILED")
end
os.exit(failures == 0 and 0 or 1)
