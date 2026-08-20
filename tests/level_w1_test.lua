-- level_w1_test.lua — proving slice: Forest Trail from canonical campaign data.
-- Data plumbing always runs. Full offline_battle play-through runs when
-- decrypted/ fixtures and the patched engine are on package.path.
package.path = "src/?.lua;decrypted/src/?.lua;decrypted/?.lua;" .. package.path

local failures = 0
local function check(cond, msg)
    if cond then
        print("[PASS] " .. msg)
    else
        failures = failures + 1
        print("[FAIL] " .. msg)
    end
end

local campaign = require("manager.campaign_data")
local w1 = campaign.node_by_id("w1")
check(w1 ~= nil, "canonical node w1")

local cards = campaign.load_cards_from_csv("csv_data/all_card_config.csv")
local enemy_ids = campaign.enemy_model_ids(w1, cards)
local own_m, own_i = campaign.split_collection(campaign.STARTER_COLLECTION, cards)
check(#enemy_ids == (w1.pool.size or 9), "enemy deck from nature pool")
check(#own_m >= 4, "player starter has monsters")
check(#own_i >= 1, "player starter has items")

local has_engine = io.open("src/manager/offline_battle.lua", "r")
if has_engine then has_engine:close() end

local function try_require(name)
    local ok, mod = pcall(require, name)
    return ok and mod or nil
end

-- Engine path: only when data_template can load (setup_test_env.py fixtures).
local data_template = nil
if io.open("csv_plain/all_card_config.csv", "r") or io.open("decrypted/src/manager/data_template.lua", "r") then
    -- Full mock layer (same as integration_test.lua) so data_template can boot.
    if not package.loaded.bit then
        local bit_stub = {}
        function bit_stub.band(a,b) local r,p=0,1 while(a>0 or b>0)and p<=2^31 do if a%2==1 and b%2==1 then r=r+p end a=math.floor(a/2);b=math.floor(b/2);p=p*2 end return r end
        function bit_stub.bor(a,b) local r,p=0,1 while(a>0 or b>0)and p<=2^31 do if a%2==1 or b%2==1 then r=r+p end a=math.floor(a/2);b=math.floor(b/2);p=p*2 end return r end
        function bit_stub.bxor(a,b) local r,p=0,1 while(a>0 or b>0)and p<=2^31 do if(a%2)~=(b%2)then r=r+p end a=math.floor(a/2);b=math.floor(b/2);p=p*2 end return r end
        function bit_stub.bnot(a) return 0xFFFFFFFF-bit_stub.band(a,0xFFFFFFFF) end
        function bit_stub.lshift(a,n) return bit_stub.band(a*2^n,0xFFFFFFFF) end
        function bit_stub.rshift(a,n) return math.floor(bit_stub.band(a,0xFFFFFFFF)/2^n) end
        package.loaded["bit"] = bit_stub
    end
    if not aandm then
        aandm = {}
        function aandm.loadConfig(name)
            local base = string.match(name, "([^/\\]+)%.csv$") or name
            local f = io.open("csv_plain/" .. base .. ".csv", "r")
            if not f then return "" end
            local c = f:read("*a"); f:close(); return c
        end
        function aandm.getDataFromFile() return nil end
    end
    if not socket then socket = {} end
    if not crypt then crypt = {} end
    package.loaded["socket"] = socket
    package.loaded["crypt"] = crypt
    if not protobuf then
        protobuf = { register = function() end, encode = function() return "" end, decode2 = function() return {} end }
    end
    package.loaded["utils.protobuf"] = protobuf
    path = path or "res/data/"
    if not cc then
        cc = {}
        cc.LANGUAGE_ENGLISH = 0; cc.LANGUAGE_CHINESE = 1
        cc.PLATFORM_OS_WINDOWS = 4; cc.PLATFORM_OS_ANDROID = 3
        local app = { getCurrentLanguage = function() return cc.LANGUAGE_ENGLISH end,
                      getTargetPlatform = function() return cc.PLATFORM_OS_ANDROID end }
        cc.Application = { getInstance = function() return app end }
        cc.FileUtils = { getInstance = function()
            return { getWritablePath = function() return "sim_save_int/" end }
        end }
        cc.UserDefault = { getInstance = function()
            return { getStringForKey = function() return "" end,
                     getIntegerForKey = function(_,d) return d or 0 end,
                     getBoolForKey = function(_,d) return d or false end,
                     setStringForKey = function() end, setIntegerForKey = function() end,
                     setBoolForKey = function() end, setDoubleForKey = function() end,
                     flush = function() end }
        end }
        cc.Director = { getInstance = function() return { getTextureCache = function() return {} end,
                     getScheduler = function() return { scheduleScriptFunc = function() return 1 end } end,
                     getRunningScene = function() return nil end, replaceScene = function() end,
                     endToLua = function() end } end }
    end
    pcall(require, "common.ext.init")
    data_template = try_require("manager.data_template")
    if data_template then
        data_template:Init()
        local load_count = 0
        while not data_template.is_load_complete and load_count < 200 do
            data_template:LoadFromCSV()
            load_count = load_count + 1
        end
    end
end

if not data_template then
    print("[SKIP] offline_battle fixtures not present — data plumbing only")
    print()
    if failures > 0 then os.exit(1) end
    print("RESULT: ALL CHECKS PASSED")
    return
end

local battle_mod = require("manager.offline_battle")

local function card_info(model_id, uid, user)
    local cfg = data_template.card_config[tostring(model_id)]
    if not cfg then return nil end
    return battle_mod.BuildCardInfo(cfg, uid, nil, user)
end

local function deck_from_ids(ids, user)
    local monster_list, item_list = {}, {}
    local uid = 1
    for _, id in ipairs(ids) do
        local c = card_info(id, uid, user)
        uid = uid + 1
        if c then
            if c.type == "monster" then
                monster_list[#monster_list + 1] = c
            else
                item_list[#item_list + 1] = c
            end
        end
    end
    return { monster_list = monster_list, item_list = item_list }
end

local function play(b, max_turns)
    local turns = 0
    while not b.is_over and turns < (max_turns or 40) do
        turns = turns + 1
        local guard = 0
        while b.own.is_sacrifice and guard < 8 do
            guard = guard + 1
            local sac
            for p = 1, 4 do
                if b.own:GetHandCard(p) then sac = p break end
            end
            if not sac then break end
            b:HandleSacrifice({ is_hand = true, pos = sac })
        end
        for p = 1, 4 do
            local c = b.own:GetHandCard(p)
            if c and c.type == "monster" and c.cost and c.cost <= b.own.cur_crystal then
                local slot = b.own:GetCurMonsterSlotPos()
                if slot > 0 then
                    b:HandleMove({ src_pos = p, is_enemy = false, target_pos = slot })
                end
            end
        end
        b:HandleAttack({})
    end
    return turns
end

-- Victory: player uses starter; enemy gets a single weak nature 1-drop if present.
local win_enemy = { monster_list = {}, item_list = {} }
for _, id in ipairs(enemy_ids) do
    local c = card_info(id, 1, "enemy")
    if c and (c.cost or 99) <= 2 then
        win_enemy.monster_list = { c }
        break
    end
end
if #win_enemy.monster_list == 0 then
    local c = card_info(enemy_ids[1], 1, "enemy")
    if c then win_enemy.monster_list = { c } end
end

math.randomseed(1)
local win_b = battle_mod.New({
    battle_type = "pve",
    battle_object_type = "pve",
    pve_info = { play_id = 0, difficulty = 1, pve_win_cur_value = 0 },
    pve_win_target = 1,
    own_deck = deck_from_ids(campaign.STARTER_COLLECTION, "player"),
    enemy_deck = win_enemy,
    enemy_name = w1.enemy_name or "Thicket Prowlers",
}, function() end)
win_b:Start()
play(win_b, 50)
check(win_b.is_over == true, "w1 victory scenario ends")
check(win_b.win_user_id == "player", "w1 victory: player wins (got " .. tostring(win_b.win_user_id) .. ")")

-- Defeat: empty player monster pile vs full enemy pool.
math.randomseed(2)
local lose_b = battle_mod.New({
    battle_type = "pve",
    battle_object_type = "pvp",
    own_deck = { monster_list = {}, item_list = {} },
    enemy_deck = deck_from_ids(enemy_ids, "enemy"),
    enemy_name = w1.enemy_name,
}, function() end)
lose_b:Start()
play(lose_b, 10)
check(lose_b.is_over == true, "w1 defeat scenario ends")
check(lose_b.win_user_id == "enemy", "w1 defeat: enemy wins")

print()
if failures > 0 then
    print("RESULT: " .. failures .. " FAILURE(S)")
    os.exit(1)
end
print("RESULT: ALL CHECKS PASSED")
