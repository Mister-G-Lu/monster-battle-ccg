-- integration_test.lua
-- Comprehensive integration tests for the offline single-player build.
-- Runs under real Lua 5.1 with the same mock layer as sim_test.lua.

-- Ensure save directory exists for test
os.execute("mkdir sim_save_int")  -- Windows/Linux compatible

local failures = 0
local passes = 0
local function check(cond, msg)
    if cond then passes = passes + 1; print("[PASS] " .. msg)
    else failures = failures + 1; print("[FAIL] " .. msg) end
end
local function section(name) print("\n=== " .. name .. " ===") end

-- ===========================================================================
-- MOCK LAYER
-- ===========================================================================
local bit_stub = {}
function bit_stub.band(a,b) local r,p=0,1 while(a>0 or b>0)and p<=2^31 do if a%2==1 and b%2==1 then r=r+p end a=math.floor(a/2);b=math.floor(b/2);p=p*2 end return r end
function bit_stub.bor(a,b) local r,p=0,1 while(a>0 or b>0)and p<=2^31 do if a%2==1 or b%2==1 then r=r+p end a=math.floor(a/2);b=math.floor(b/2);p=p*2 end return r end
function bit_stub.bxor(a,b) local r,p=0,1 while(a>0 or b>0)and p<=2^31 do if(a%2)~=(b%2)then r=r+p end a=math.floor(a/2);b=math.floor(b/2);p=p*2 end return r end
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

path = "res/data/"

cc = {}
cc.LANGUAGE_ENGLISH = 0; cc.LANGUAGE_CHINESE = 1
cc.PLATFORM_OS_WINDOWS = 4; cc.PLATFORM_OS_MAC = 5; cc.PLATFORM_OS_LINUX = 6
cc.PLATFORM_OS_ANDROID = 3; cc.PLATFORM_OS_IPHONE = 2; cc.PLATFORM_OS_IPAD = 1
local app = { getCurrentLanguage = function() return cc.LANGUAGE_ENGLISH end,
              getTargetPlatform = function() return cc.PLATFORM_OS_WINDOWS end }
cc.Application = { getInstance = function() return app end }
cc.FileUtils = { getInstance = function()
    return { getWritablePath = function() return "sim_save_int/" end }
end }
cc.UserDefault = { getInstance = function()
    return { getStringForKey = function() return "" end,
             getIntegerForKey = function(_,d) return d or 0 end,
             getBoolForKey = function(_,d) return d or false end,
             getDoubleForKey = function(_,d) return d or 0 end,
             setStringForKey = function() end, setIntegerForKey = function() end,
             setBoolForKey = function() end, setDoubleForKey = function() end,
             flush = function() end }
end }
cc.Director = { getInstance = function()
    return { getTextureCache = function() return {} end,
             getScheduler = function() return { scheduleScriptFunc = function() return 1 end } end,
             getRunningScene = function() return nil end,
             replaceScene = function() end, endToLua = function() end }
end }

package.path = "decrypted/src/?.lua;" .. "decrypted/?.lua;" .. package.path

-- ===========================================================================
-- Helper: play a battle to completion (same as sim_test.lua)
-- ===========================================================================
local function play_battle(b, max_turns)
    max_turns = max_turns or 60
    local turns = 0
    while not b.is_over and turns < max_turns do
        turns = turns + 1
        pcall(function()
            -- Sacrifice phase
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
            -- Deploy phase
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
            -- Combat + AI + next round
            b:HandleAttack({})
        end)
    end
    return turns
end

-- ===========================================================================
-- SECTION 1: CORE MODULES LOAD
-- ===========================================================================
section("1. Core modules load")

local time = require("manager.time")
time:Init()
check(time:Now() > 0, "manager.time loads and Now() works")

require("common.ext.init")

local config = require("manager.configuration")
check(type(config) == "table", "configuration module loads")

local data_mgr = require("manager.data_template")
data_mgr:Init()
local load_count = 0
while not data_mgr.is_load_complete and load_count < 200 do
    data_mgr:LoadFromCSV()
    load_count = load_count + 1
end
check(data_mgr.is_load_complete, "data_template loads CSVs (" .. load_count .. " iterations)")

local ok, network = pcall(require, "manager.network")
check(ok, "network module loads")

local ok2, offline_server = pcall(require, "manager.offline_server")
check(ok2, "offline_server module loads")

local ok3, offline_battle = pcall(require, "manager.offline_battle")
check(ok3, "offline_battle module loads")

-- ===========================================================================
-- SECTION 2: OFFLINE MODE FLAG
-- ===========================================================================
section("2. Offline mode flag")
check(OFFLINE_MODE == true, "OFFLINE_MODE is true")

-- ===========================================================================
-- SECTION 3: DATA INTEGRITY
-- ===========================================================================
section("3. Data integrity")

local pve = data_mgr.pve_play_config[10011]
check(pve ~= nil, "PvE config 1001/1 exists (key=10011)")

local card_count = 0
for _ in pairs(data_mgr.card_config) do card_count = card_count + 1 end
check(card_count > 1000, "Card config has " .. card_count .. " cards")

local item_count = 0
for _ in pairs(data_mgr.item_config) do item_count = item_count + 1 end
check(item_count > 10, "Item config has " .. item_count .. " items")

local task_count = 0
for _ in pairs(data_mgr.task_config) do task_count = task_count + 1 end
check(task_count > 100, "Task config has " .. task_count .. " tasks")

-- ===========================================================================
-- SECTION 4: NETWORK CONNECT
-- ===========================================================================
section("4. Network connect")

network:Init()
network:RegisterProto()
local err, status = network:Connect("offline", 28800)
check(err == nil, "Connect returns nil error")
check(status == 3, "Connect returns connected (3)")
check(network:IsConnected(), "IsConnected() is true")

-- ===========================================================================
-- SECTION 5: LOGIN FLOW
-- ===========================================================================
section("5. Login flow")

local login_r, login_m, login_done = nil, nil, false
network:Send("req_login_game", {
    name=99999, token=88888, type="debug", channel="debug",
    language="en-US", version="1.4"
}, function(r, m) login_r = r; login_m = m; login_done = true end)

check(login_done, "Login callback fired")
check(login_r == "success", "Login result: " .. tostring(login_r))
check(type(login_m.user_id) == "number", "user_id: " .. tostring(login_m.user_id))
check(type(login_m.server_time) == "number", "server_time set")

-- ===========================================================================
-- SECTION 6: ALL STARTUP QUERIES
-- ===========================================================================
section("6. Startup queries")

local queries = {
    {"query_base_info", {}},
    {"query_resource_info", {}},
    {"req_deck_info_panel", {}},
    {"req_card_info_panel", {}},
    {"query_chest_info", {}},
    {"query_arena_info", {}},
    {"req_refresh_daily", {}},
    {"query_overview_info", {}},
    {"req_pve_play_info", {}},
    {"req_task_info", {}},
    {"req_guide_panel", {}},
}
for _, q in ipairs(queries) do
    local r, m
    network:Send(q[1], q[2], function(res, msg) r = res; m = msg end)
    check(r == "success", q[1] .. " -> success")
    check(m ~= nil, q[1] .. " -> non-nil response")
end

-- ===========================================================================
-- SECTION 7: RESPONSE SHAPES
-- ===========================================================================
section("7. Response shapes")

local base; network:Send("query_base_info", {}, function(_, m) base = m end)
check(type(base.name) == "string" or type(base.name) == "number", "base_info.name exists")
check(type(base.level) == "number" and base.level >= 1, "base_info.level >= 1")

local res; network:Send("query_resource_info", {}, function(_, m) res = m end)
check(res.money ~= nil, "resource has money")
check(res.coin ~= nil, "resource has coin")

local decks; network:Send("req_deck_info_panel", {}, function(_, m) decks = m end)
check(#decks.deck_info_list >= 1, "at least 1 deck")
check(type(decks.deck_info_list[1].strength) == "number", "deck has strength")
check(decks.deck_info_list[1].monster_pos_1 ~= nil, "deck has monster_pos_1")

local cards; network:Send("req_card_info_panel", {}, function(_, m) cards = m end)
check(#cards.card_info_list >= 10, ">= 10 cards (" .. #cards.card_info_list .. ")")
check(type(cards.card_info_list[1].id) == "number", "card has id")
check(type(cards.card_info_list[1].model_id) == "number", "card has model_id")

local overview; network:Send("query_overview_info", {}, function(_, m) overview = m end)
check(type(overview.new_mail_num) == "number", "new_mail_num is number")
check(overview.battle_id == nil, "battle_id is nil")
check(overview.room_number == nil, "room_number is nil")

-- ===========================================================================
-- SECTION 8: PVE BATTLE START
-- ===========================================================================
section("8. PvE battle start")

local br, bm; network:Send("req_pve_battle_start", {play_id=1001,difficulty=1}, function(r,m) br=r; bm=m end)
check(br == "success", "pve_battle_start -> success")
check(bm ~= nil, "pve_battle_start -> data")

-- ===========================================================================
-- SECTION 9: FULL BATTLE (with sacrifice/deploy/combat cycle)
-- ===========================================================================
section("9. Full battle (play to game over)")

local cmds, over, winner = {}, false, nil
network:RegisterCommand("cmd_battle", function(cmd)
    table.insert(cmds, cmd)
    if cmd.cmd_battle_over then over = true; winner = cmd.cmd_battle_over.win_user_id end
end)

-- Start a fresh battle
network:Send("req_pve_battle_start", {play_id=1001, difficulty=1}, function() end)
local b = offline_server.current_battle
check(b ~= nil, "current_battle exists after start")

local turns = play_battle(b, 100)

check(b.is_over == true, "battle reaches game over (turns=" .. turns .. ")")
check(winner ~= nil, "winner determined: " .. tostring(winner))
check(#cmds > 0, #cmds .. " battle commands emitted")

local cmd_names = {}
for _, cmd in ipairs(cmds) do
    for k in pairs(cmd) do cmd_names[k] = true end
end
check(cmd_names["cmd_battle_start"], "cmd_battle_start emitted")
check(cmd_names["cmd_battle_init"], "cmd_battle_init emitted")
check(cmd_names["cmd_battle_round"], "cmd_battle_round emitted")
check(cmd_names["cmd_battle_over"], "cmd_battle_over emitted")
check(cmd_names["cmd_battle_prepa"], "cmd_battle_prepa emitted")

-- ===========================================================================
-- SECTION 10: UNKNOWN REQUEST
-- ===========================================================================
section("10. Unknown request handling")

local ur; network:Send("fake_request_xyz", {}, function(r) ur = r end)
check(ur == "unknown_request", "Unknown request returns 'unknown_request'")

-- ===========================================================================
-- SECTION 11: RECONNECT CYCLE
-- ===========================================================================
section("11. Reconnect cycle")

-- In offline mode, Disconnect is a no-op — status stays "connected"
network:Disconnect()
local re = network:Reconnect()
check(re == nil, "Reconnect no error")
check(network:IsConnected(), "Still connected after reconnect (offline mode)")

-- ===========================================================================
-- SECTION 12: HEARTBEAT
-- ===========================================================================
section("12. Heartbeat")
local hb_ok = pcall(function() network:HeartBeat() end)
check(hb_ok, "HeartBeat() doesn't crash")

-- ===========================================================================
-- SECTION 13: PVE STAGE PROGRESSION
-- ===========================================================================
section("13. PvE stage progression")

for _, pid in ipairs({1001, 1002, 1003, 1004}) do
    local r; network:Send("req_pve_battle_start", {play_id=pid,difficulty=1}, function(res) r = res end)
    check(r == "success", "Stage " .. pid .. " battle start")
end

-- ===========================================================================
-- SECTION 14: MULTIPLE BATTLES (consistency)
-- ===========================================================================
section("14. Multiple battles (consistency)")

for game = 1, 5 do
    network:Send("req_pve_battle_start", {play_id = 1001+game-1, difficulty = 1}, function() end)
    local bg = offline_server.current_battle
    local turns = play_battle(bg, 60)
    check(bg.is_over, "Battle " .. game .. " ended (" .. turns .. " turns), winner=" .. tostring(bg.win_user_id))
end

-- ===========================================================================
-- SECTION 15: CARD / DECK CONSISTENCY
-- ===========================================================================
section("15. Card/deck consistency")

local c2; network:Send("req_card_info_panel", {}, function(_, m) c2 = m end)
local d2; network:Send("req_deck_info_panel", {}, function(_, m) d2 = m end)

local deck_has_monsters = false
for _, deck in ipairs(d2.deck_info_list) do
    if deck.monster_pos_1 and deck.monster_pos_1 > 0 then deck_has_monsters = true end
end
check(deck_has_monsters, "Deck has monster cards assigned")

-- ===========================================================================
-- SECTION 16: ARENA / DAILY / TASK / GUIDE
-- ===========================================================================
section("16. Arena / daily / task / guide")

local a; network:Send("query_arena_info", {}, function(_,m) a=m end)
check(type(a) == "table" and a ~= nil, "arena returns table")

local d; network:Send("req_refresh_daily", {}, function(_,m) d=m end)
check(type(d) == "table" and d ~= nil, "daily returns table")

local t; network:Send("req_task_info", {}, function(_,m) t=m end)
check(type(t) == "table" and t ~= nil, "task returns table")

local g; network:Send("req_guide_panel", {}, function(_,m) g=m end)
check(type(g) == "table" and g ~= nil, "guide returns table")

-- ===========================================================================
-- SECTION 17: BATTLE -- DIFFERENT DIFFICULTIES
-- ===========================================================================
section("17. Battle difficulties")

for _, diff in ipairs({1, 2, 3}) do
    network:Send("req_pve_battle_start", {play_id=1001, difficulty=diff}, function() end)
    local bd = offline_server.current_battle
    local turns = play_battle(bd, 60)
    check(bd.is_over, "Difficulty " .. diff .. " ends (" .. turns .. " turns), winner=" .. tostring(bd.win_user_id))
end

-- ===========================================================================
-- SECTION 18: SAVE PERSISTENCE
-- ===========================================================================
section("18. Save persistence")

local save_ok = false
for _, p in ipairs({"res/data/offline_save.json", "sim_save_int/offline_save.json", "offline_save.json"}) do
    local f = io.open(p, "r")
    if f then save_ok = true; f:close(); break end
end
check(save_ok, "Save file exists after battles")

-- ===========================================================================
-- SECTION 19: CHAIN: LOGIN -> QUERY -> BATTLE -> SAVE -> RE-LOGIN
-- ===========================================================================
section("19. Full chain: login -> query -> battle -> save -> re-login")

network:Clear()
network:RegisterProto()
network:Connect("fresh", 28800)

local lr2, lm2
network:Send("req_login_game", {name=77777,token=66666,type="debug",channel="debug",language="en-US",version="1.4"},
    function(r,m) lr2=r; lm2=m end)
check(lr2 == "success", "Re-login success")
check(lm2.user_id ~= nil, "Re-login user_id set")

local qr; network:Send("query_base_info", {}, function(r) qr=r end)
check(qr == "success", "query_base_info works after re-login")

local qr2; network:Send("query_resource_info", {}, function(r) qr2=r end)
check(qr2 == "success", "query_resource_info works after re-login")

local qr3; network:Send("req_card_info_panel", {}, function(r) qr3=r end)
check(qr3 == "success", "req_card_info_panel works after re-login")

-- ===========================================================================
-- SECTION 20: BATTLE EDGE CASES (initial state validation)
-- ===========================================================================
section("20. Battle edge cases")

network:Send("req_pve_battle_start", {play_id=1001, difficulty=3}, function() end)
local be = offline_server.current_battle
check(be ~= nil, "Hard battle starts")
check(be.is_over == false, "Battle not over at start")
check(be.round >= 1, "Round >= 1 at start")
check(be.own.cur_crystal > 0, "Player has crystal")
check(be.enemy.cur_crystal > 0, "Enemy has crystal")

-- ===========================================================================
-- SECTION 21: CORRUPTED SAVE RECOVERY
-- ===========================================================================
section("21. Corrupted save recovery")

-- Write garbage to save file
local save_path = "sim_save_int/offline_save.json"
local f = io.open(save_path, "w")
if f then
    f:write("NOT VALID JSON {{{")
    f:close()
end

-- Login should still work (creates new save or recovers)
network:Clear()
network:RegisterProto()
network:Connect("recover", 28800)
local rr, rm
network:Send("req_login_game", {name=88888,token=88888,type="debug",channel="debug",language="en-US",version="1.4"},
    function(r,m) rr=r; rm=m end)
check(rr == "success", "Login works with corrupted save")

-- ===========================================================================
-- SECTION 22: CONCURRENT SENDS (multiple requests in quick succession)
-- ===========================================================================
section("22. Concurrent sends")

local r1, r2, r3
network:Send("query_base_info", {}, function(r) r1 = r end)
network:Send("query_resource_info", {}, function(r) r2 = r end)
network:Send("query_overview_info", {}, function(r) r3 = r end)
check(r1 == "success", "Concurrent query_base_info")
check(r2 == "success", "Concurrent query_resource_info")
check(r3 == "success", "Concurrent query_overview_info")

-- ===========================================================================
-- SECTION 23: REPEATED LOGINS (session resets)
-- ===========================================================================
section("23. Repeated logins")

for i = 1, 3 do
    network:Clear()
    network:RegisterProto()
    network:Connect("test" .. i, 28800)
    local lr, lm
    network:Send("req_login_game", {name=50000+i,token=50000+i,type="debug",channel="debug",language="en-US",version="1.4"},
        function(r,m) lr=r; lm=m end)
    check(lr == "success", "Login " .. i .. " success")
    check(lm.user_id ~= nil, "Login " .. i .. " user_id set")
end

-- ===========================================================================
-- SECTION 24: CAMPAIGN ADVENTURE RETURN CONTRACT
-- ===========================================================================
section("24. Campaign Adventure round-trip")

-- Exercise the same server contract the native Adventure panel consumes after
-- a battle result. This is intentionally in the broad offline integration
-- suite: it catches a payload that may be valid for the battle engine but
-- unusable by the result UI / returned campaign map.
local campaign_service = require("manager.campaign_service")
campaign_service.reset(offline_server:GetCampaignSave())
offline_server:Save()

local campaign_info_before
network:Send("req_campaign_info", {}, function(_, message) campaign_info_before = message end)
check(campaign_info_before and campaign_info_before.current_node == "w1",
    "Adventure starts on campaign node w1")
check(campaign_info_before and #campaign_info_before.regions == 4,
    "Adventure response includes all 4 regions")

local commands_before_campaign = #cmds
local campaign_start
network:Send("req_campaign_battle_start", { node_id = "w1" },
    function(result, message) campaign_start = { result = result, message = message } end)
check(campaign_start and campaign_start.result == "success", "Adventure starts native w1 battle")
local campaign_battle = offline_server.current_battle
check(campaign_battle and campaign_battle.hero_mode, "Adventure battle uses campaign commander mode")

-- The detailed campaign suites play the battle; here finish through the real
-- server callback to assert the post-battle response and map refresh contract.
campaign_battle:FinishBattle(campaign_battle.own.user_id)
local campaign_over = nil
for i = #cmds, commands_before_campaign + 1, -1 do
    if cmds[i].cmd_battle_over then
        campaign_over = cmds[i].cmd_battle_over
        break
    end
end
check(campaign_over and campaign_over.campaign_info and campaign_over.campaign_info.node_id == "w1",
    "campaign result identifies w1 for map refresh")
check(campaign_over and type(campaign_over.mvp_card_info) == "table",
    "campaign result supplies an empty MVP table for the native result UI")
check(campaign_over and type(campaign_over.reward_info) == "table" and #campaign_over.reward_info == 1,
    "campaign victory supplies a displayable EXP reward")

local campaign_info_after
network:Send("req_campaign_info", {}, function(_, message) campaign_info_after = message end)
check(campaign_info_after and campaign_info_after.cleared.w1 == true,
    "Adventure map records w1 as cleared after its battle")
check(campaign_info_after and campaign_info_after.current_node == "w2",
    "Adventure map advances to w2 after its battle")
check(campaign_info_after and campaign_info_after.pending_recruit == "w1",
    "Adventure map exposes the pending recruit after first clear")

local campaign_offers
network:Send("req_campaign_recruit_offers", { node_id = "w1" }, function(_, message) campaign_offers = message end)
check(campaign_offers and #(campaign_offers.offers or {}) == 3,
    "Adventure recruit draft is available after returning from battle")

-- ===========================================================================
-- RESULTS
-- ===========================================================================
print("\n" .. string.rep("=", 60))
print(string.format("RESULTS: %d PASSED, %d FAILED, %d TOTAL", passes, failures, passes + failures))
print(string.rep("=", 60))

if failures > 0 then
    print("SOME TESTS FAILED")
    os.exit(1)
else
    print("ALL INTEGRATION TESTS PASSED")
end
