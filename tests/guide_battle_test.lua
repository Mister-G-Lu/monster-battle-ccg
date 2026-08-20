-- guide_battle_test.lua
-- Headless end-to-end test of the TUTORIAL battle ("player" vs "Will").
--
-- The existing sim/integration suites drive offline_battle directly on the
-- server side, which completely bypasses the client's battle_logic state
-- machine (the command queue, cmd_battle_init side detection, the standby
-- handshake, turn windows).  That is exactly where the tutorial battle hung
-- on device: the match panel stayed on "loading" forever.
--
-- This test loads the REAL client logic (logic.battle + logic.guide) with a
-- mocked UI layer and replays the device flow frame by frame:
--   battle scene deferred panel init -> match_panel:Show() ->
--   "enter_battle" anim -> ReqBattleStandby -> server reply ->
--   cmd_battle_standby -> "exit_battle" frame events -> gold coin ready anim
--   -> anim_complete -> player turn -> auto-play the battle to completion
--   -> ExitBattle -> guide continues to the next step.
--
-- Run under real LuaJIT (same runtime family as the game):
--   luajit tests/guide_battle_test.lua
-- Requires: decrypted/ (game Lua tree) + csv_plain/ (see scripts/setup_test_env.py)

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
-- Mock layer (only what the loaded modules touch; the real device provides
-- these via the cocos2d-x native layer).  Same stubs as sim_test.lua.
-- ---------------------------------------------------------------------------
path = "res/data/"

local bit_stub = {}
function bit_stub.band(a,b) local r,p=0,1 while(a>0 or b>0)and p<=2^31 do if a%2==1 and b%2==1 then r=r+p end a=math.floor(a/2);b=math.floor(b/2);p=p*2 end return r end
function bit_stub.bor(a,b) local r,p=0,1 while(a>0 or b>0)and p<=2^31 do if a%2==1 or b%2==1 then r=r+p end a=math.floor(a/2);b=math.floor(b/2);p=p*2 end return r end
function bit_stub.bxor(a,b) local r,p=0,1 while(a>0 or b>0)and p<=2^31 do if (a%2)~=(b%2)then r=r+p end a=math.floor(a/2);b=math.floor(b/2);p=p*2 end return r end
function bit_stub.bnot(a) return 0xFFFFFFFF-bit_stub.band(a,0xFFFFFFFF) end
function bit_stub.lshift(a,n) return bit_stub.band(a*2^n,0xFFFFFFFF) end
function bit_stub.rshift(a,n) return math.floor(bit_stub.band(a,0xFFFFFFFF)/2^n) end
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
cc.FileUtils = { getInstance = function() return { getWritablePath = function() return "sim_save_guide/" end } end }
cc.UserDefault = { getInstance = function() return {
    getStringForKey = function() return "" end,
    getIntegerForKey = function(_,d) return d or 0 end,
    getBoolForKey = function(_,d) return d or false end,
    getDoubleForKey = function(_,d) return d or 0 end,
    setStringForKey = function() end, setIntegerForKey = function() end,
    setBoolForKey = function() end, setDoubleForKey = function() end,
    flush = function() end } end }
cc.Director = { getInstance = function() return {
    getTextureCache = function() return {} end,
    getScheduler = function() return { scheduleScriptFunc = function() return 1 end } end,
    getRunningScene = function() return nil end } end }

-- cocos2d-x provides a global dump(); stub it for headless runs
if not dump then function dump(...) end end

-- UI-side managers that logic.battle touches
local pushed_scenes = {}
package.loaded["manager.global"] = {
    PushScene = function(self, name) table.insert(pushed_scenes, name) end,
    PopScene = function(self) end,
    ChangeScene = function(self, name) table.insert(pushed_scenes, name) end,
}
package.loaded["manager.graphic"] = {
    DispatchEvent = function(...) end,
    RegisterEvent = function(...) end,
}
package.loaded["manager.analytics"] = {
    DoBattleStart = function() end, DoCasualMatchOver = function() end,
    DoBattleOver = function() end,
}
-- logic.user / logic.pve / logic.arena / logic.challenge stubs
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

-- ---------------------------------------------------------------------------
-- SECTION 1: load real modules + login
-- ---------------------------------------------------------------------------
section("1. Load modules + login")

require "common.ext.init"
local time = require "manager.time"
time:Init()

local network = require "manager.network"
network:RegisterProto()
network:Connect("guide-test", 28800)

local data_template = require "manager.data_template"
data_template:Init()
data_template:LoadFromCSV()

local text_loader = require "manager.text_loader"
text_loader:Init()

local login_user_id = nil
network:Send("req_login_game", {name=777001, token=777001, type="debug", channel="debug", language="en-US", version="1.4"},
    function(r, m)
        if r == "success" then login_user_id = m.user_id end
    end)
check(login_user_id ~= nil, "login succeeded, user_id=" .. tostring(login_user_id))
user_stub.user_id = login_user_id   -- logic/user.lua does this in user_logic:Init()

local offline_server = require "manager.offline_server"
local login_name = offline_server.save and offline_server.save.name or "?"

local battle_logic = require "logic.battle"
battle_logic:Init()

local guide_logic = require "logic.guide"
guide_logic:Init()

-- device login flow queries the guide panel (sets guide_flag)
guide_logic:Query(function() end)

-- the world scene would have walked the guide steps up to the battle:
-- steps 1_1..1_3 are dialogue, step 1_4 is req_battle_guide(1).  The battle
-- runs with guide_step_idx == 4, so after the win DoGuide() advances to
-- step 1_5 (hide_chat) and then on to guide 2.
guide_logic.cur_guide_id = 1
guide_logic.guide_step_idx = 4

-- ---------------------------------------------------------------------------
-- Shared battle-scene frame model (models battle_scene + match_panel + the
-- ready/gold-coin animations the way the device plays them).
-- ---------------------------------------------------------------------------
local frame_model = {}

function frame_model.new(opts)
    return {
        t = 0,
        dt = 1 / 30,
        frames = 0,
        scene_ready_frames = opts.scene_ready_frames or 6,
        panel_state = "hidden",   -- hidden | enter | loop | exit
        shown_at = nil,
        ready_end_at = nil,
        anim_events = {},         -- scheduled frame events {t=.., name=..}
        fire_ready_anim = opts.fire_ready_anim ~= false,  -- false => simulate broken anim (watchdog test)
        observed = {},
        battle_over_at = nil,
    }
end

function frame_model.register_panel_events(m)
    -- what the panels would observe
    battle_logic:RegisterEvent("init_player_info", function(own, enemy)
        m.observed.init_player_info = { own = own, enemy = enemy }
    end)
    battle_logic:RegisterEvent("battle_panel_standby", function()
        m.observed.battle_panel_standby = (m.observed.battle_panel_standby or 0) + 1
    end)
    battle_logic:RegisterEvent("battlefield_enter", function()
        m.observed.battlefield_enter = (m.observed.battlefield_enter or 0) + 1
    end)
    battle_logic:RegisterEvent("gold_coin_ready", function()
        m.observed.gold_coin_ready = (m.observed.gold_coin_ready or 0) + 1
    end)
    battle_logic:RegisterEvent("show_battle_null", function()
        m.observed.show_battle_null = true
    end)
    -- panel animation callbacks (character_panel-style):
    -- drop animation ends -> run callback, clear the deploy lock
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
    -- battle event sub-animations (character_panel/battle_slot_card drive
    -- these on device and then dispatch sub_event_complete; model them as
    -- instant completions)
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
                -- match_panel frame handler (start_type == nil, not replay)
                if battle_logic.start_type ~= "replay" or battle_logic.battle_status == 2 then
                    battle_logic:DispatchEvent("gold_coin_ready")
                    if m.fire_ready_anim then
                        m.ready_end_at = m.t + 0.8  -- RunReadyAnimation spine duration
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

-- auto-play one player action per frame, modelling what a human does on
-- device each turn:
--   1. sacrifice phase (is_sacrifice is re-armed every round by
--      cmd_battle_prepa): sacrifice the first hand card, exactly like the
--      original game's flow (the only client-side way out of the sacrifice
--      phase is the optimistic clear inside ReqSacrificeCard)
--   2. deploy one affordable card (monster -> slot 1; item -> rotate slots)
--   3. otherwise hit the fight button
-- Gated on is_play_animation so we never act during the match-panel phase.
local function auto_play_turn(m)
    if battle_logic.is_play_animation then return end
    if battle_logic.cur_stage ~= battle_logic.STAGE.own then return end
    local own = battle_logic.own_player

    if own.is_sacrifice then
        for p = 1, 4 do
            if own:GetHandCard(p) then
                battle_logic:ReqSacrificeCard(true, p, function(is_success)
                    m.observed.sacrifice_result = is_success
                end)
                return
            end
        end
        -- empty hand: nothing to sacrifice, end the turn
        battle_logic:ReqBattleAttack("auto")
        return
    end

    -- try to deploy one card; give up after a few rejected attempts
    -- (e.g. equip kind mismatch with every slot monster) and attack instead
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
                    -- rotate the target slot so kind mismatches do not stall us
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
    -- no deployable cards (or enough failed attempts): attack
    m.move_attempts = 0
    battle_logic:ReqBattleAttack("auto")
end

function frame_model.step(m)
    m.frames = m.frames + 1
    m.t = m.t + m.dt
    frame_model.fire_frame_events(m)

    if m.frames == m.scene_ready_frames then
        -- battle_scene standby_cache drained -> match_panel:Show()
        m.panel_state = "enter"
        m.shown_at = m.t
    end

    if m.panel_state == "enter" and m.t >= m.shown_at + 0.75 then
        m.panel_state = "loop"
        battle_logic:ReqBattleStandby()
    end

    if m.observed.battle_panel_standby and m.panel_state ~= "exit" then
        m.panel_state = "exit"
        -- exit_battle frame events (device timings)
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
    if m.observed.battle_panel_standby and battle_logic.is_play_animation then
        m.blocked_since = m.blocked_since or m.t
    end
    if m.blocked_since and not battle_logic.is_play_animation and not m.recovered_at then
        m.recovered_at = m.t
    end
end

function frame_model.run(m, max_frames, stop_when, log_every)
    max_frames = max_frames or 3000
    log_every = log_every or 300
    for i = 1, max_frames do
        frame_model.step(m)
        if stop_when and stop_when(m) then return end
        if not battle_logic.is_battle_over then
            auto_play_turn(m)
        end
        if i % log_every == 0 then
            local b = offline_server.current_battle
            local own = battle_logic.own_player
            local hand_n = 0
            for p = 1, 4 do if own and own:GetHandCard(p) then hand_n = hand_n + 1 end end
            local function board_n(a)
                local n = 0
                for i = 1, 3 do if a and a.battle_slot[i] and a.battle_slot[i].monster then n = n + 1 end end
                return n
            end
            print(string.format("  [t=%5.2f] stage=%d round=%d own_board=%d enemy_board=%d own_total=%d enemy_total=%d hand=%d crystal=%d",
                m.t, battle_logic.cur_stage or -1, b and b.round or -1,
                board_n(b and b.own), board_n(b and b.enemy),
                b and b.own and b.own:GetMonsterTotal() or -1, b and b.enemy and b.enemy:GetMonsterTotal() or -1,
                hand_n, own and own.cur_crystal or -1))
        end
    end
end

-- ---------------------------------------------------------------------------
-- SECTION 2: tutorial battle start (battle_process = 1, "Will")
-- ---------------------------------------------------------------------------
section("2. Tutorial battle start")

local m1 = frame_model.new({})

network:Send("req_guide_battle", { battle_process = 1 })

-- cmd_battle_start is processed synchronously: scene pushed, fields set
check(#pushed_scenes == 1 and pushed_scenes[1] == "battle", "cmd_battle_start pushed battle scene")
check(battle_logic.battle_type == "guide", "battle_type is guide")
check(battle_logic.battle_object_type == "pve", "battle_object_type is pve")
check(guide_logic.guide_trigger_config ~= nil, "guide trigger config loaded for play_id 1")

-- panels are created by the battle scene AFTER cmd_battle_start's Clean(),
-- so register them now (same order as on device)
frame_model.register_panel_events(m1)

-- let the queue consume cmd_battle_init
frame_model.run(m1, 300, function(m) return m.observed.init_player_info ~= nil end)
check(m1.observed.init_player_info ~= nil, "cmd_battle_init consumed")

-- the critical side-detection check: the player must NOT be swapped
check(battle_logic.own_player ~= nil and battle_logic.own_player.user_id == login_user_id,
    "own_player is the logged-in player (no side swap), own=" .. tostring(battle_logic.own_player.user_id)
        .. " login=" .. tostring(login_user_id))
check(battle_logic.enemy_player ~= nil and battle_logic.enemy_player.user_id ~= login_user_id,
    "enemy_player is the AI side")
check(battle_logic.is_first == true, "player is first actor")
check(battle_logic.own_player.user_name == login_name,
    "own actor carries the player's name (" .. tostring(battle_logic.own_player.user_name) .. ")")

-- enemy name: the server sends "[AI] Will" (battle 1).  The match panel runs
-- it through text_loader:GetText, which passes non-keys through unchanged.
local raw_enemy_name = battle_logic.enemy_player.user_name
check(raw_enemy_name == "[AI] Will", "server sent enemy name, got " .. tostring(raw_enemy_name))
check(text_loader:GetText(raw_enemy_name) == "[AI] Will", "enemy name displays as-is (text_loader passthrough)")
check(text_loader:GetText("guide_name_1") == "Will", "text key guide_name_1 still resolves to Will")

-- ---------------------------------------------------------------------------
-- SECTION 3: standby handshake (the part that hung on "loading" forever)
-- ---------------------------------------------------------------------------
section("3. Standby handshake")

frame_model.run(m1, 300, function(m)
    -- the instant the handshake finished: panel exited, deploy lock cleared,
    -- player's prep phase reached, and NOTHING was auto-played yet
    return m.observed.gold_coin_ready ~= nil
        and m.observed.battle_panel_standby ~= nil
        and battle_logic.cur_stage == battle_logic.STAGE.own
        and not battle_logic.is_play_animation
end)

check(m1.observed.battle_panel_standby == 1, "battle_panel_standby fired exactly once (match panel exits)")
check(m1.observed.battlefield_enter ~= nil, "battlefield_enter frame event fired")
check(m1.observed.gold_coin_ready ~= nil, "gold_coin_ready fired")
check(battle_logic.is_play_animation == false, "is_play_animation cleared after ready anim")
check(#battle_logic.battle_command_queue == 0, "battle command queue drained (no stuck commands)")
check(battle_logic.cur_stage == battle_logic.STAGE.own, "client reached own stage")
check(battle_logic.own_player.is_sacrifice == true, "player sacrifice phase active")

-- ---------------------------------------------------------------------------
-- SECTION 4: turn window (client must NOT auto-attack instantly)
-- ---------------------------------------------------------------------------
section("4. Turn window")

local turn_seconds_left = time:GetDiffSecond(battle_logic.own_player.last_oper_time or 0)
check(turn_seconds_left > 3000, "server grants an effectively unlimited turn window (last_oper_time in the future, " .. turn_seconds_left .. "s left)")
check(battle_logic.cur_stage == battle_logic.STAGE.own, "no instant auto-attack (stage still own after prepa)")

-- ---------------------------------------------------------------------------
-- SECTION 5: play the tutorial battle to completion via the client API
-- ---------------------------------------------------------------------------
section("5. Battle plays to completion")

frame_model.run(m1, 3000, function(m) return battle_logic.battle_result ~= nil end)

check(battle_logic.is_battle_over, "battle reached game over")
check(battle_logic.battle_result ~= nil, "battle_result set (" .. tostring(battle_logic.battle_result) .. ")")
check(m1.observed.show_battle_null ~= true, "server never returned battle_is_null during play")

local constants = require "common.constants"
local result = battle_logic.battle_result

-- the tutorial AI deck (2x 110011 + 2x 140011) should lose to the starter
-- player deck; either way the client must reach a clean win/loss result
check(result == constants.BATTLE_RESULT.win or result == constants.BATTLE_RESULT.loss,
    "result is win or loss (got " .. tostring(result) .. ")")

-- player taps through the result -> ExitBattle -> guide continues
battle_logic:ExitBattle()

-- on a win the guide is marked complete (guide 1) and the next guide starts
if result == constants.BATTLE_RESULT.win then
    local flag = offline_server.save.guide_flag or 0
    check(bit_stub.band(flag, bit_stub.lshift(1, 1)) ~= 0, "server marked guide 1 complete")
    check(guide_logic.cur_guide_id == 2, "guide advanced to guide 2 (card pack demo), cur=" .. tostring(guide_logic.cur_guide_id))
else
    print("  (battle lost — guide will retry the battle; flow still verified)")
end

-- ---------------------------------------------------------------------------
-- SECTION 6: second tutorial battle + watchdog recovery (broken ready
-- animation must not hang the loading screen forever)
-- ---------------------------------------------------------------------------
section("6. Second battle + watchdog recovery")

local m2 = frame_model.new({ fire_ready_anim = false })  -- gold coin anim never completes

-- start the second tutorial battle (battle_process = 2, "Challenger")
network:Send("req_guide_battle", { battle_process = 2 })
frame_model.register_panel_events(m2)

check(battle_logic.battle_type == "guide", "second guide battle started")

frame_model.run(m2, 300, function(m) return m.observed.init_player_info ~= nil end)
check(battle_logic.own_player ~= nil and battle_logic.own_player.user_id == login_user_id,
    "second battle: no side swap")
local raw_enemy_name2 = battle_logic.enemy_player.user_name
check(raw_enemy_name2 == "[AI] Challenger", "second battle enemy name, got " .. tostring(raw_enemy_name2))
check(text_loader:GetText(raw_enemy_name2) == "[AI] Challenger", "second battle enemy displays as-is")

frame_model.run(m2, 6000, function(m) return battle_logic.battle_result ~= nil end)

check(m2.observed.battle_panel_standby ~= nil, "standby reply arrived in second battle")
check(battle_logic.is_play_animation == false, "is_play_animation unblocked despite broken ready anim")
check(m2.blocked_since ~= nil and m2.recovered_at ~= nil, "battle was blocked on the broken animation")
check(m2.recovered_at - m2.blocked_since < 10.0,
    "battle_logic watchdog unblocked within 10s (blocked at t=" .. tostring(m2.blocked_since)
        .. ", recovered at t=" .. tostring(m2.recovered_at) .. ")")
check(battle_logic.battle_result ~= nil, "second battle still played to a result despite broken anim")

-- ===========================================================================
-- RESULTS
-- ===========================================================================
print("\n" .. string.rep("=", 60))
print(string.format("RESULTS: %d FAILED", failures))
print(string.rep("=", 60))

if failures > 0 then
    print("SOME TESTS FAILED")
    os.exit(1)
else
    print("ALL GUIDE BATTLE TESTS PASSED")
end
