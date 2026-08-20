-- campaign_service_test.lua
-- The Shadow Road campaign, served by the Android offline service.
--
-- Part A (always runs, no fixtures): pure campaign-service logic against
-- the canonical data — starter grant, node gating, victory/defeat rewards,
-- boss vitality, recruit drafts, skip, reset, info payloads.
--
-- Part B (when setup_test_env.py fixtures exist): boots the real
-- offline_server and plays a campaign node end-to-end through the native
-- battle engine — req_campaign_info -> req_campaign_battle_start (w1) ->
-- battle to completion -> recruit -> reset.
--
-- Run: luajit tests/campaign_service_test.lua

package.path = "src/?.lua;decrypted/?.lua;decrypted/src/?.lua;" .. package.path

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

local campaign_service = require("manager.campaign_service")
local campaign = require("manager.campaign_data")

-- Normalized card index from the repo CSV (the device equivalent is
-- data_template.card_config -> CampaignCardIndex() in offline_server).
local csv_cards = campaign.load_cards_from_csv("csv_data/all_card_config.csv")
local cards = {}
for _, rec in pairs(csv_cards) do
    local c = campaign_service.normalize_card(rec)
    if c then cards[c.id] = c end
end
local function card_count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- ===========================================================================
section("1. Starter + defaults")
local save = campaign_service.default_save()
campaign_service.ensure_starter(save)
check(save.vitality == 30, "base vitality 30")
check(#save.collection == 21, "starter collection has 21 cards (" .. #save.collection .. ")")
check(save.starter_granted == true, "starter granted once")
campaign_service.ensure_starter(save)
check(#save.collection == 21, "ensure_starter is idempotent")
local w1 = campaign_service.node_by_id("w1")
local w5 = campaign_service.node_by_id("w5")
check(w1 ~= nil and w1.name == "Forest Trail", "w1 resolved from canonical data")
check(campaign_service.current_node(save).id == "w1", "fresh campaign starts at w1")

-- ===========================================================================
section("2. Node gating")
check(campaign_service.is_playable(save, w1), "w1 is playable on a fresh save")
check(not campaign_service.is_playable(save, campaign_service.node_by_id("w2")), "w2 is locked until w1 falls")
check(not campaign_service.is_playable(save, campaign_service.node_by_id("c1")), "act2 is locked until act1's boss falls")
save.cleared["w1"] = true
check(campaign_service.current_node(save).id == "w2", "clearing w1 advances to w2")
check(campaign_service.is_playable(save, campaign_service.node_by_id("w2")), "w2 playable after w1")

-- ===========================================================================
section("3. Victory rewards")
save = campaign_service.default_save()
campaign_service.ensure_starter(save)
local res = campaign_service.apply_victory(save, w1)
check(res.first_clear == true, "w1 first clear detected")
check(res.exp_gain == w1.exp, "w1 grants its EXP (" .. tostring(w1.exp) .. ")")
check(save.cleared["w1"] == true, "w1 marked cleared")
check(save.exp == w1.exp, "campaign EXP recorded")
check(save.pending_recruit == "w1", "first clear opens a recruit")
local offers = campaign_service.recruit_offers(save, w1, cards)
check(#offers == 3, "recruit draft offers 3 cards (" .. #offers .. ")")
for _, id in ipairs(offers) do
    check(cards[id] ~= nil, "offer " .. tostring(id) .. " is a known card")
end
local before = #save.collection
check(campaign_service.apply_recruit(save, offers[1]) == true, "valid recruit accepted")
check(#save.collection == before + 1, "collection grew by one")
check(save.pending_recruit == nil, "pending recruit cleared after pick")

-- replay: no recruit, small EXP
local res2 = campaign_service.apply_victory(save, w1)
check(res2.first_clear == false, "replay is not a first clear")
check(res2.exp_gain == campaign_service.REPLAY_EXP, "replay grants replay EXP (" .. tostring(res2.exp_gain) .. ")")
check(save.pending_recruit == nil, "replay does not open a recruit")

-- invalid recruit pick rejected
campaign_service.apply_victory(save, campaign_service.node_by_id("w2"))
local offers2 = campaign_service.recruit_offers(save, campaign_service.node_by_id("w2"), cards)
check(#offers2 == 3, "w2 draft generated")
check(campaign_service.apply_recruit(save, 999999) == false, "pick outside the offers is rejected")
check(save.pending_recruit ~= nil, "pending recruit survives a bad pick")

-- ===========================================================================
section("4. Boss rewards + vitality cap")
local boss_save = campaign_service.default_save()
campaign_service.ensure_starter(boss_save)
for i, id in ipairs(campaign_service.all_nodes()) do
    if id == w5 then break end
    boss_save.cleared[id.id] = true
end
local bres = campaign_service.apply_victory(boss_save, w5)
check(bres.boss_slain == true, "boss win flags boss_slain")
check(boss_save.vitality == 32, "boss win grants +2 vitality (got " .. boss_save.vitality .. ")")
check(boss_save.bosses_slain == 1, "bosses_slain increments")
boss_save.vitality = campaign_service.VITALITY_CAP
local bres2 = campaign_service.apply_victory(boss_save, w5)
check(boss_save.vitality == campaign_service.VITALITY_CAP, "vitality caps at " .. tostring(campaign_service.VITALITY_CAP))

-- final boss completes the campaign
local fin_save = campaign_service.default_save()
campaign_service.ensure_starter(fin_save)
-- clear every node except s4 (taking each recruit), then beat s4
for _, node in ipairs(campaign_service.all_nodes()) do
    if node.id ~= "s4" then
        campaign_service.apply_victory(fin_save, node)
        local o = campaign_service.recruit_offers(fin_save, node, cards)
        if o[1] then campaign_service.apply_recruit(fin_save, o[1]) end
    end
end
local s4 = campaign_service.node_by_id("s4")
local fres = campaign_service.apply_victory(fin_save, s4)
check(fres.complete == true, "final boss sets complete")
check(campaign_service.current_node(fin_save) == nil, "no current node after completion")

-- ===========================================================================
section("5. Recruit drafts")
-- drafts resolve against the faction pool and stay inside known cards
math.randomseed(7)
for _, node in ipairs(campaign_service.all_nodes()) do
    local s = campaign_service.default_save()
    campaign_service.ensure_starter(s)
    s.cleared[node.id] = nil
    -- make the node current by clearing everything before it
    local hit = false
    for _, n in ipairs(campaign_service.all_nodes()) do
        if n == node then hit = true break end
        if not hit then s.cleared[n.id] = true end
    end
    local offers = campaign_service.recruit_offers(s, node, cards)
    check(#offers == campaign_service.DRAFT_SIZE,
          node.id .. " draft has " .. campaign_service.DRAFT_SIZE .. " offers (" .. #offers .. ")")
    for _, id in ipairs(offers) do
        local c = cards[id]
        check(c ~= nil, node.id .. " offer " .. tostring(id) .. " is a known card")
        if c then
            check(c.flags == 1 or c.flags == "1", node.id .. " offer is a collectible card")
        end
    end
end

-- ===========================================================================
section("6. normalize_card (template-style records)")
local tpl = campaign_service.normalize_card({
    uid = "110051", type = "monster", level = "3", cost = "2", hp = "6",
    quality = "rare", kind_list = { "war" },
    power_list = { { name = "melee", value = 2 } },
})
check(tpl.id == 110051 and tpl.kind == "war", "template kind_list -> kind string")
check(tpl.attack == 2, "template power_list -> attack (got " .. tostring(tpl.attack) .. ")")
check(tpl.flags == 1, "template config defaults flags to 1")
local c2 = campaign_service.normalize_card({ id = 110052, type = "monster", level = 4, cost = 2, hp = 7, quality = "rare", kind = "war", attack = 3, flags = 1 })
check(c2.attack == 3 and c2.flags == 1, "csv-style record keeps attack/flags")

-- ===========================================================================
section("7. skip + reset")
local s = campaign_service.default_save()
campaign_service.ensure_starter(s)
campaign_service.apply_victory(s, w1)
check(campaign_service.skip_recruit(s) == true, "skip accepts a pending recruit")
check(s.exp == w1.exp + campaign_service.SKIP_RECRUIT_EXP, "skip grants +15 EXP")
check(campaign_service.skip_recruit(s) == false, "second skip rejected (nothing pending)")
campaign_service.reset(s)
check(s.vitality == 30 and #s.collection == 21 and s.wins == 0, "reset restores the fresh campaign")

-- ===========================================================================
section("8. info payload")
local is = campaign_service.info(save)
check(is.regions == campaign.REGIONS and #is.regions == 4, "info carries the 4 canonical regions")
check(type(is.cleared) == "table" and type(is.collection) == "table", "info carries progress + collection")
check(is.current_node == campaign_service.current_node(save).id, "info names the current node")

-- ===========================================================================
-- Part B — full service integration (fixtures only)
-- ===========================================================================
local fixtures_ready = io.open("csv_plain/all_card_config.csv", "r") or io.open("decrypted/manager/offline_server.lua", "r")
if fixtures_ready then
    section("B. offline_server campaign handlers (end-to-end)")

    -- --- mock layer (same as integration_test.lua) ---
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
    path = "res/data/"

    cc = {}
    cc.LANGUAGE_ENGLISH = 0; cc.LANGUAGE_CHINESE = 1
    cc.PLATFORM_OS_WINDOWS = 4
    cc.Application = { getInstance = function() return {
        getCurrentLanguage = function() return cc.LANGUAGE_ENGLISH end,
        getTargetPlatform = function() return cc.PLATFORM_OS_WINDOWS end } end }
    cc.FileUtils = { getInstance = function() return { getWritablePath = function() return "sim_save_int/" end } end }
    cc.UserDefault = { getInstance = function() return {
        getStringForKey = function() return "" end,
        getIntegerForKey = function(_,d) return d or 0 end,
        getBoolForKey = function(_,d) return d or false end,
        setStringForKey = function() end, setIntegerForKey = function() end,
        setBoolForKey = function() end, setDoubleForKey = function() end,
        flush = function() end } end }
    cc.Director = { getInstance = function() return {
        getTextureCache = function() return {} end,
        getScheduler = function() return { scheduleScriptFunc = function() return 1 end } end,
        getRunningScene = function() return nil end,
        replaceScene = function() end, endToLua = function() end } end }

    OFFLINE_MODE = true
    local time = require("manager.time")
    time:Init()
    require("common.ext.init")  -- string/table extensions used by data_template
    local data_mgr = require("manager.data_template")
    data_mgr:Init()
    local guard = 0
    while not data_mgr.is_load_complete and guard < 200 do
        data_mgr:LoadFromCSV()
        guard = guard + 1
    end
    check(data_mgr.is_load_complete, "data_template loads")

    local ok, network = pcall(require, "manager.network")
    check(ok, "network module loads")
    local ok2, server = pcall(require, "manager.offline_server")
    check(ok2, "offline_server module loads")

    local dispatched = {}
    network.DispatchCommand = function(_, kind, msg)  -- colon-style (self, name, content)
        dispatched[#dispatched + 1] = { kind = kind, msg = msg }
    end

    -- login as a guest
    server:HandleLoginGame({ user_id = "campaign_test_player" })
    check(server.save ~= nil, "logged in")

    -- campaign info
    local info = server.handlers["req_campaign_info"](server)
    check(info ~= nil and info.current_node == "w1", "req_campaign_info: starts at w1")
    check(#info.collection == 21, "req_campaign_info: starter collection present")
    check(info.vitality == 30, "req_campaign_info: vitality 30")

    -- a locked node refuses to start
    local err_locked = server.handlers["req_campaign_battle_start"](server, { node_id = "c1" })
    check(err_locked == "campaign_node_locked", "locked act2 node refused (got " .. tostring(err_locked) .. ")")

    -- start w1 through the service
    local err = server.handlers["req_campaign_battle_start"](server, { node_id = "w1" })
    check(err == nil, "req_campaign_battle_start w1 succeeds")
    local b = server.current_battle
    check(b ~= nil, "battle created")
    check(b.enemy.user_name == w1.enemy_name, "enemy named from the canonical node (" .. tostring(b.enemy.user_name) .. ")")

    -- play the battle greedily to completion
    local function play_greedy(battle, seed)
        math.randomseed(seed)
        local turns = 0
        while not battle.is_over and turns < 60 do
            turns = turns + 1
            local guard2 = 0
            while battle.own.is_sacrifice and guard2 < 8 do
                guard2 = guard2 + 1
                local sac = nil
                for p = 1, 4 do
                    if battle.own:GetHandCard(p) then sac = p break end
                end
                if not sac then break end
                battle:HandleSacrifice({ is_hand = true, pos = sac })
            end
            for p = 1, 4 do
                local c = battle.own:GetHandCard(p)
                if c and c.type == "monster" and c.cost and c.cost <= battle.own.cur_crystal then
                    local slot = battle.own:GetCurMonsterSlotPos()
                    if slot > 0 then
                        battle:HandleMove({ src_pos = p, is_enemy = false, target_pos = slot })
                    end
                end
            end
            battle:HandleAttack({})
        end
        return battle
    end

    -- retry until the player wins so the reward/recruit path is exercised
    local b = server.current_battle
    local attempt = 0
    while b.win_user_id ~= "player" and attempt < 5 do
        attempt = attempt + 1
        if b.is_over then
            server.handlers["req_campaign_battle_start"](server, { node_id = "w1" })
            b = server.current_battle
        end
        play_greedy(b, 3 + attempt)
    end
    check(b.is_over, "campaign battle reaches game over")
    check(b.win_user_id == "player", "campaign battle won by the player (" .. tostring(b.win_user_id) .. ")")

    -- the service applied the win rewards end-to-end
    local csave = server:GetCampaignSave()
    check(csave.cleared["w1"] == true, "w1 cleared by OnCampaignOver")
    check(csave.exp >= w1.exp, "campaign EXP applied (" .. csave.exp .. ")")
    check(csave.pending_recruit == "w1", "recruit pending after first clear")
    local offers = server.handlers["req_campaign_recruit_offers"](server, { node_id = "w1" })
    check(offers ~= nil and #offers.offers == 3, "recruit offers served (" .. tostring(offers and #offers.offers) .. ")")
    local rec = server.handlers["req_campaign_recruit"](server, { card_id = offers.offers[1] })
    check(rec ~= nil and #rec.collection == 22, "recruit applied server-side (collection " .. tostring(rec and #rec.collection) .. ")")

    -- cmd_battle_start carried the canonical node id
    local found_node = false
    for _, d in ipairs(dispatched) do
        if d.kind == "cmd_battle" and d.msg and d.msg.cmd_battle_start then
            local s = d.msg.cmd_battle_start
            if s.pve_battle_info and s.pve_battle_info.campaign_node_id == "w1" then
                found_node = true
            end
        end
    end
    check(found_node, "cmd_battle_start carried campaign_node_id")

    -- reset
    local reset_info = server.handlers["req_campaign_reset"](server)
    check(reset_info ~= nil and reset_info.current_node == "w1" and reset_info.vitality == 30,
          "req_campaign_reset restores the campaign")
else
    print("\n=== B. offline_server campaign handlers: SKIPPED (no fixtures) ===")
end

print()
if failures > 0 then
    print("RESULT: " .. failures .. " FAILURE(S)")
    os.exit(1)
end
print("RESULT: ALL CHECKS PASSED")
