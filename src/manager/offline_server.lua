-- offline_server.lua
-- In-process server that emulates the original mu77 game server so the game
-- can be played entirely offline as a single-player campaign.
--
-- The client modules call network:Send(req_name, data, callback). This module
-- answers those requests and pushes the same cmd_* / update_* messages the
-- client logic registers for. Player progress is persisted as JSON in the
-- writable path.

local bit = require "bit"
local bit_band = bit.band
local bit_bor = bit.bor
local bit_lshift = bit.lshift
local bit_bnot = bit.bnot
local network = require "manager.network"
local json = require "utils.json"
local constants = require "common.constants"
local data_template = require "manager.data_template"
local timer = require "manager.time"
local configuration = require "manager.configuration"
local offline_battle = require "manager.offline_battle"

local offline_server = {}

-- =====================================================================
-- Save / load
-- =====================================================================

function offline_server:GetSavePath()
    local path = cc.FileUtils:getInstance():getWritablePath()
    return path .. "offline_save.json"
end

function offline_server:LoadSave()
    local fp = io.open(self:GetSavePath(), "r")
    if not fp then
        return nil
    end
    local content = fp:read("*a")
    fp:close()
    if not content or string.len(content) == 0 then
        return nil
    end
    local ok, obj = pcall(function() return json:decode(content) end)
    if not ok or type(obj) ~= "table" then
        -- backup corrupt save so we don't silently wipe progress
        pcall(function()
            local bp = io.open(self:GetSavePath() .. ".bak", "w")
            if bp then bp:write(content); bp:close() end
        end)
        print("[offline_server] corrupt save backed up; starting fresh")
        return nil
    end
    return obj
end

function offline_server:Save()
    if not self.save then
        return
    end
    local str = json:encode(self.save)
    if not str then
        return
    end
    local base = self:GetSavePath()
    local tmp = base .. ".tmp"
    local fp = io.open(tmp, "w+")
    if not fp then
        -- fallback: try direct write if tmp fails
        fp = io.open(base, "w+")
    end
    if fp then
        fp:write(str)
        fp:close()
        -- atomic rename: tmp -> base (works on Android/Linux; on Windows
        -- the source must not already be an open handle, which it isn't)
        os.rename(tmp, base)
    end
end

-- =====================================================================
-- Initial player
-- =====================================================================

-- model ids of the starter deck (constants.INIT_CARD_LIST)
function offline_server:GetStarterDeck()
    local init = constants.INIT_CARD_LIST
    local monster_list = {}
    local item_list = {}
    if init and init[1] then
        local list = init[1]
        -- first 8 are monsters, next 8 are items
        for i = 1, 8 do
            table.insert(monster_list, list[i])
        end
        for i = 9, 16 do
            if list[i] then
                table.insert(item_list, list[i])
            end
        end
    end
    return monster_list, item_list
end

function offline_server:NewPlayer(user_id)
    local save = {}
    self.save = save   -- bind early: helpers (CalcDeckStrength etc.) read self.save
    save.version = 1
    save.user_id = user_id
    save.name = "Adventurer"
    save.level = 1
    save.exp = 0
    save.create_time = os.time()
    save.money = 200
    save.coin = 0
    save.items = {}          -- item_id -> num
    save.items["100001"] = 10 -- monster powder
    save.cards = {}          -- list of {id(uid), model_id, deck_flag, is_lock, group_id, level}
    save.next_card_uid = 1000000
    save.decks = {}
    save.cur_deck_id = 1
    save.chests = {}
    save.arena = {
        level = 1,
        stage = 1,
        elo_value = constants.INIT_ELO or 1000,
        next_refresh_chest = 0,
        last_reward_chest_num = 0,
        win_count = 0,
        loss_count = 0,
        draw_count = 0,
    }
    save.pve = {}            -- play_id -> {difficulty, image}
    save.adventure = { progress = 1, pass_ids = {} }
    save.daily = { next_refresh_time = 0, login_reward = 1 }
    save.tasks = {
        next_refresh_task_count_time = 0,
        task_count = 0,
        task_reset_count = 0,
        next_refresh_task_time = 0,
    }
    save.cur_task = { id = 1, progress = 0, status = 0 }
    save.achievements = { achi_points = 0, achi_list = {} }
    save.statistic = {}
    save.guide_flag = 0
    save.mails = {}
    save.mail_id_generator = 1
    save.wins = 0
    save.losses = 0
    save.pve_cleared = {}    -- play_id..difficulty -> true

    -- starter cards (uid == model_id so deck positions are unambiguous)
    local monster_models, item_models = self:GetStarterDeck()
    local deck = {
        id = 1,
        name = "Starter",
        type = "normal",
        strength = 0,
    }
    local deck_monster_uids = {}
    local deck_item_uids = {}
    local function add_card(model_id)
        local cfg = self:GetCardConfig(model_id)
        local uid = model_id
        local deck_flag = 0
        table.insert(save.cards, {
            id = uid,
            model_id = model_id,
            deck_flag = deck_flag,
            is_lock = false,
            group_id = cfg and cfg.group_id or 0,
            level = cfg and cfg.level or 1,
        })
        return uid
    end
    for _, m in ipairs(monster_models) do
        table.insert(deck_monster_uids, add_card(m))
    end
    for _, m in ipairs(item_models) do
        table.insert(deck_item_uids, add_card(m))
    end
    for i = 1, 8 do
        deck["monster_pos_" .. i] = deck_monster_uids[i]
    end
    for i = 1, 8 do
        deck["item_pos_" .. i] = deck_item_uids[i]
    end
    deck.strength = self:CalcDeckStrength(deck)
    save.decks[1] = deck

    -- starter chests
    save.chests["8"] = 2   -- wooden chest
    save.chests["1"] = 1   -- super rare

    return save
end

-- =====================================================================
-- Card helpers
-- =====================================================================

function offline_server:GetCardConfig(model_id)
    return data_template.card_config[tostring(model_id)]
end

function offline_server:CalcDeckStrength(deck)
    local s = 0
    for i = 1, 8 do
        local m = deck["monster_pos_" .. i]
        local it = deck["item_pos_" .. i]
        local cm = m and self:GetCardByUid(m)
        local ci = it and self:GetCardByUid(it)
        if cm then
            local cfg = self:GetCardConfig(cm.model_id)
            if cfg then s = s + (tonumber(cfg.score) or 0) end
        end
        if ci then
            local cfg = self:GetCardConfig(ci.model_id)
            if cfg then s = s + (tonumber(cfg.score) or 0) end
        end
    end
    return s
end

function offline_server:GetCardByUid(uid)
    for _, c in ipairs(self.save.cards) do
        if c.id == uid then
            return c
        end
    end
    return nil
end

-- build the CardInfo message for a saved card (uid, model_id)
function offline_server:CardInfoFromSaved(card, hand_pos)
    local cfg = self:GetCardConfig(card.model_id)
    return offline_battle.BuildCardInfo(cfg, card.id, hand_pos, self.save.user_id)
end

-- build CardInfo from a model id (used for PvE rental decks / AI decks)
function offline_server:CardInfoFromModel(model_id, uid, hand_pos, user_id)
    local cfg = self:GetCardConfig(model_id)
    if not cfg then
        return nil
    end
    return offline_battle.BuildCardInfo(cfg, uid or model_id, hand_pos, user_id)
end

-- parse "a|b|c" strings from CSVs
function offline_server:SplitList(str)
    local list = {}
    if not str then return list end
    for w in string.gmatch(str, "%d+") do
        table.insert(list, tonumber(w))
    end
    return list
end

-- =====================================================================
-- Player queries
-- =====================================================================

function offline_server:GetExpForLevel(level)
    local prof = data_template.proficiency_config[level]
    if prof then
        return tonumber(prof.exp) or 0
    end
    return level * 40
end

-- add exp, return level ups applied via cmd_update_proficient
function offline_server:AddExp(exp)
    if not exp or exp <= 0 then
        return
    end
    self.save.exp = self.save.exp + exp
    local leveled = false
    while true do
        local need = self:GetExpForLevel(self.save.level)
        if need <= 0 or self.save.exp < need then
            break
        end
        self.save.exp = self.save.exp - need
        self.save.level = self.save.level + 1
        leveled = true
    end
    if leveled then
        network:DispatchCommand("cmd_update_proficient", {
            level = self.save.level,
            exp = self.save.exp,
        })
    end
end

function offline_server:AddMoney(money)
    if not money or money <= 0 then return end
    self.save.money = self.save.money + money
    network:DispatchCommand("update_resource_money", self.save.money)
end

function offline_server:AddCoin(coin)
    if not coin or coin <= 0 then return end
    self.save.coin = self.save.coin + coin
    network:DispatchCommand("update_resource_coin", self.save.coin)
end

function offline_server:AddItem(item_id, num)
    item_id = tostring(item_id)
    num = num or 1
    local old = self.save.items[item_id] or 0
    self.save.items[item_id] = old + num
    network:DispatchCommand("update_item_list", {
        item_list = { { uid = tonumber(item_id), num = old + num } },
    })
end

-- add a new card to the bag; pushes cmd_card_update
function offline_server:AddCard(model_id, deck_flag)
    local cfg = self:GetCardConfig(model_id)
    if not cfg then
        return nil
    end
    local uid = self.save.next_card_uid
    self.save.next_card_uid = uid + 1
    local card = {
        id = uid,
        model_id = model_id,
        deck_flag = deck_flag or 0,
        is_lock = false,
        group_id = cfg.group_id or 0,
        level = cfg.level or 1,
    }
    table.insert(self.save.cards, card)
    network:DispatchCommand("cmd_card_update", card)
    return card
end

function offline_server:RemoveCard(uid)
    for i, c in ipairs(self.save.cards) do
        if c.id == uid then
            table.remove(self.save.cards, i)
            network:DispatchCommand("cmd_card_del", { card_id = uid })
            return c
        end
    end
    return nil
end

-- =====================================================================
-- Rewards
-- =====================================================================

-- apply a RewardInfo list {type, attr_id, value}; returns nothing
function offline_server:ApplyRewards(reward_list)
    for _, r in ipairs(reward_list or {}) do
        local rtype = r.type
        local attr_id = r.attr_id
        local value = r.value or 0
        if rtype == "resource" then
            if attr_id == constants.RESOURCE_ID.money then
                self:AddMoney(value)
            elseif attr_id == constants.RESOURCE_ID.coin then
                self:AddCoin(value)
            elseif attr_id == 400001 then
                self:AddExp(value)
            else
                self:AddItem(attr_id, value)
            end
        elseif rtype == "card" then
            self:AddCard(attr_id)
        end
    end
end

-- random card model pool for chests
local CHEST_CARD_POOL = {
    110011, 110021, 110031, 110041, 120011, 120021, 120031, 120041,
    130011, 130021, 130031, 130041, 140011, 140021, 140031, 140041,
    150011, 150021, 150031, 150041, 21001, 21002, 21003, 22001, 22006,
    22008, 23001, 23006, 31001, 31003, 32001, 32002, 33001, 33003,
    34001, 34003, 35001, 35003, 36001, 36003,
}

function offline_server:RandomCardFromPool()
    local pool = CHEST_CARD_POOL
    local model = pool[math.random(#pool)]
    -- chance of a higher-level version
    local r = math.random(100)
    local cfg = self:GetCardConfig(model)
    if r > 85 and cfg then
        -- find same group next level
        local group = cfg.group_id
        local best = model
        for k, v in pairs(data_template.card_config) do
            if tonumber(v.group_id) == tonumber(group) and v.type == cfg.type then
                if tonumber(v.level) > tonumber(cfg.level) then
                    best = tonumber(k)
                end
            end
        end
        if best ~= model and math.random(100) <= 30 then
            model = best
        end
    end
    return model
end

-- =====================================================================
-- Arena
-- =====================================================================

function offline_server:BuildArenaPanel()
    local a = self.save.arena
    return {
        level = a.level,
        stage = a.stage,
        elo_value = a.elo_value,
        next_refresh_chest = a.next_refresh_chest or 0,
        last_reward_chest_num = a.last_reward_chest_num or 0,
        win_count = a.win_count or 0,
        loss_count = a.loss_count or 0,
        draw_count = a.draw_count or 0,
    }
end

-- =====================================================================
-- PvE
-- =====================================================================

-- pick AI decks for a pve play/difficulty
function offline_server:PickPveEnemyDeck(play_id, difficulty)
    local cfg = nil
    for _, v in pairs(data_template.pve_play_config) do
        if tonumber(v.play_id) == tonumber(play_id) and tonumber(v.difficulty) == tonumber(difficulty) then
            cfg = v
            break
        end
    end
    if cfg then
        local deck = { monster_list = {}, item_list = {} }
        local uid = 1
        for _, m in ipairs(self:SplitList(cfg.ai_monster_list)) do
            local c = self:CardInfoFromModel(m, uid, nil, "enemy")
            if c then table.insert(deck.monster_list, c) end
            uid = uid + 1
        end
        for _, m in ipairs(self:SplitList(cfg.ai_item_list)) do
            local c = self:CardInfoFromModel(m, uid, nil, "enemy")
            if c then table.insert(deck.item_list, c) end
            uid = uid + 1
        end
        return deck, cfg
    end
    -- Fallback: generate a scaled enemy deck from the card pool
    local deck = { monster_list = {}, item_list = {} }
    local uid = 1
    local base_pool = { 110011, 110021, 120011, 130011, 140011 }
    local item_pool = { 21001, 22001, 31001, 34001 }
    local num_monsters = math.min(8, 4 + (difficulty or 1))
    for i = 1, num_monsters do
        local model = base_pool[math.random(#base_pool)]
        -- higher difficulty: pick stronger variants
        if (difficulty or 1) >= 2 and math.random(100) <= 30 then
            model = model + 10
        end
        local c = self:CardInfoFromModel(model, uid, nil, "enemy")
        if c then table.insert(deck.monster_list, c) end
        uid = uid + 1
    end
    for i = 1, math.min(6, 2 + (difficulty or 1)) do
        local model = item_pool[math.random(#item_pool)]
        local c = self:CardInfoFromModel(model, uid, nil, "enemy")
        if c then table.insert(deck.item_list, c) end
        uid = uid + 1
    end
    return deck, nil
end

-- build the player's deck for a battle (rental deck for pve, own deck otherwise)
function offline_server:BuildPlayerDeck(use_system_deck, play_id, difficulty)
    local deck = { monster_list = {}, item_list = {} }
    if use_system_deck then
        local cfg = nil
        for _, v in pairs(data_template.pve_play_config) do
            if tonumber(v.play_id) == tonumber(play_id) and tonumber(v.difficulty) == tonumber(difficulty) then
                cfg = v
                break
            end
        end
        if cfg then
            local uid = 1
            for _, m in ipairs(self:SplitList(cfg.employee_monster_list)) do
                local c = self:CardInfoFromModel(m, uid, nil, self.save.user_id)
                if c then table.insert(deck.monster_list, c) end
                uid = uid + 1
            end
            for _, m in ipairs(self:SplitList(cfg.employee_item_list)) do
                local c = self:CardInfoFromModel(m, uid, nil, self.save.user_id)
                if c then table.insert(deck.item_list, c) end
                uid = uid + 1
            end
        end
    else
        local d = self.save.decks[self.save.cur_deck_id] or self.save.decks[1]
        if d then
            for i = 1, 8 do
                local uid = d["monster_pos_" .. i]
                if uid then
                    local card = self:GetCardByUid(uid)
                    if card then
                        local c = self:CardInfoFromSaved(card)
                        if c then table.insert(deck.monster_list, c) end
                    end
                end
                local uid2 = d["item_pos_" .. i]
                if uid2 then
                    local card = self:GetCardByUid(uid2)
                    if card then
                        local c = self:CardInfoFromSaved(card)
                        if c then table.insert(deck.item_list, c) end
                    end
                end
            end
        end
    end
    if #deck.monster_list == 0 then
        -- fallback: starter deck
        local monster_models, item_models = self:GetStarterDeck()
        local uid = 1
        for _, m in ipairs(monster_models) do
            local c = self:CardInfoFromModel(m, uid, nil, self.save.user_id)
            if c then table.insert(deck.monster_list, c) end
            uid = uid + 1
        end
        for _, m in ipairs(item_models) do
            local c = self:CardInfoFromModel(m, uid, nil, self.save.user_id)
            if c then table.insert(deck.item_list, c) end
            uid = uid + 1
        end
    end
    return deck
end

-- =====================================================================
-- Login
-- =====================================================================

function offline_server:HandleLoginGame(req)
    local user_id = req.user_id
    if not user_id or user_id == "" then
        user_id = req.name
    end
    if not user_id or user_id == "" then
        user_id = "player_" .. math.random(100000, 999999)
    end

    local save = self:LoadSave()
    if save and save.user_id == user_id then
        self.save = save
    else
        -- new player (or guest login with a fresh id)
        self.save = self:NewPlayer(user_id)
        self:Save()
    end
    self.logged_in = true

    timer:SyncTime(os.time(), 0)

    -- welcome mail
    if not self.save.welcomed then
        self.save.welcomed = true
        self:SendWelcomeMail()
        self:Save()
    end

    return {
        result = "success",
        user_id = user_id,
        reconnect_token = "offline_" .. user_id,
        server_time = os.time(),
        time_zone = 0,
    }
end

function offline_server:SendWelcomeMail()
    local mail = {
        mail_id = self.save.mail_id_generator,
        type = 1,   -- notice
        stage = 1,  -- unread
        title = "welcome_mail_title",
        send_name = "System",
        desc = "welcome_mail_desc",
        time = os.time(),
        attachment_list = {},
        expire_time = 0,
    }
    self.save.mail_id_generator = self.save.mail_id_generator + 1
    table.insert(self.save.mails, mail)
    self:Save()
    network:DispatchCommand("cmd_new_mail", { new_mail = mail, del_mail_id = nil })
end

-- =====================================================================
-- Request dispatch
-- =====================================================================

function offline_server:HandleRequest(req_name, req_data, callback)
    local handler = self.handlers[req_name]
    if not handler then
        print("[offline_server] UNHANDLED request:", req_name)
        if callback then callback("unknown_request", {}) end
        return
    end
    local ok, result = pcall(handler, self, req_data or {})
    if not ok then
        print("[offline_server] error handling", req_name, result)
        if callback then callback("fail", {}) end
        return
    end
    if result == nil then
        if callback then callback("success", {}) end
    elseif type(result) == "table" then
        if callback then callback("success", result) end
    else
        -- error string
        if callback then callback(result) end
    end
end

offline_server.handlers = {}

-- =====================================================================
-- Handlers: account / system
-- =====================================================================

offline_server.handlers["req_login_game"] = function(self, req)
    return self:HandleLoginGame(req)
end

offline_server.handlers["req_reconnect_game"] = function(self, req)
    self.logged_in = true
    return {
        reconnect_token = "offline_" .. (self.save and self.save.user_id or "player"),
        server_time = os.time(),
        time_zone = 0,
    }
end

offline_server.handlers["heart_beat"] = function(self, req)
    return { push_number = req.push_number or 0 }
end

offline_server.handlers["req_sync_time"] = function(self, req)
    return { server_time = os.time(), time_zone = 0 }
end

offline_server.handlers["req_player_logout"] = function(self, req)
    self:Save()
    return nil
end

-- =====================================================================
-- Handlers: base info
-- =====================================================================

offline_server.handlers["query_base_info"] = function(self)
    return {
        name = self.save.name,
        level = self.save.level,
        exp = self.save.exp,
        cup_num = self.save.arena.elo_value,
        create_time = self.save.create_time,
    }
end

offline_server.handlers["query_overview_info"] = function(self)
    return {
        new_mail_num = self:GetNewMailNum(),
        battle_id = nil,
        room_number = nil,
        elo_value = self.save.arena.elo_value,
        arena_stage = self.save.arena.stage,
        task_hint = false,
        achi_hint = false,
        casual_level = self.save.arena.level,
    }
end

function offline_server:GetNewMailNum()
    local n = 0
    for _, m in ipairs(self.save.mails) do
        if m.stage == 1 then
            n = n + 1
        end
    end
    return n
end

offline_server.handlers["query_resource_info"] = function(self)
    return {
        money = self.save.money,
        coin = self.save.coin,
        item_list = self:BuildItemList(),
    }
end

function offline_server:BuildItemList()
    local list = {}
    for k, v in pairs(self.save.items) do
        if v > 0 then
            table.insert(list, { uid = tonumber(k), num = v })
        end
    end
    return list
end

-- =====================================================================
-- Handlers: deck & cards
-- =====================================================================

function offline_server:BuildDeckMessage(deck)
    local msg = {}
    for k, v in pairs(deck) do
        msg[k] = v
    end
    return msg
end

offline_server.handlers["req_deck_info_panel"] = function(self)
    local deck_info_list = {}
    for _, deck in pairs(self.save.decks) do
        table.insert(deck_info_list, self:BuildDeckMessage(deck))
    end
    return { deck_info_list = deck_info_list }
end

offline_server.handlers["req_card_info_panel"] = function(self)
    local card_info_list = {}
    for _, c in ipairs(self.save.cards) do
        table.insert(card_info_list, {
            id = c.id,
            model_id = c.model_id,
            deck_flag = c.deck_flag,
            is_lock = c.is_lock,
        })
    end
    return { card_info_list = card_info_list }
end

offline_server.handlers["req_deck_card_deploy"] = function(self, req)
    local deck = self.save.decks[req.deck_id]
    if not deck then
        return "deck_is_null"
    end
    local card = self:GetCardByUid(req.new_card_uid)
    if not card then
        return "card_is_null"
    end
    local cfg = self:GetCardConfig(card.model_id)
    local pos = req.target_pos
    if cfg and cfg.type == "monster" then
        -- remove from old position if present
        for i = 1, 8 do
            if deck["monster_pos_" .. i] == req.new_card_uid then
                deck["monster_pos_" .. i] = nil
            end
        end
        deck["monster_pos_" .. pos] = req.new_card_uid
        self:SetCardDeckFlag(req.new_card_uid, req.deck_id, true)
    else
        for i = 1, 8 do
            if deck["item_pos_" .. i] == req.new_card_uid then
                deck["item_pos_" .. i] = nil
            end
        end
        deck["item_pos_" .. pos] = req.new_card_uid
        self:SetCardDeckFlag(req.new_card_uid, req.deck_id, true)
    end
    deck.strength = self:CalcDeckStrength(deck)
    self:Save()
    return self:BuildDeckMessage(deck)
end

function offline_server:SetCardDeckFlag(uid, deck_id, is_in)
    local card = self:GetCardByUid(uid)
    if not card then return end
    local flag = card.deck_flag or 0
    local flag_bit = bit_lshift(1, deck_id)
    if is_in then
        card.deck_flag = bit_bor(flag, flag_bit)
    else
        card.deck_flag = bit_band(flag, bit_bnot(flag_bit))
    end
end

offline_server.handlers["req_card_upgrade"] = function(self, req)
    local card = self:GetCardByUid(req.card_id)
    if not card then
        return "card_is_null"
    end
    local cfg = self:GetCardConfig(card.model_id)
    local upgrade = data_template.card_upgrade_config[card.model_id]
    if not upgrade or not upgrade.next_card_id then
        return "card_is_max_level"
    end
    -- consume resources
    local req_money = tonumber(upgrade.req_money) or 0
    local req_coin = tonumber(upgrade.req_coin) or 0
    if self.save.money < req_money then
        return "resource_money_not_enough"
    end
    if self.save.coin < req_coin then
        return "resource_coin_not_enough"
    end
    -- consume materials (simplified: just check money)
    self.save.money = self.save.money - req_money
    self.save.coin = self.save.coin - req_coin
    network:DispatchCommand("update_resource_money", self.save.money)
    if self.save.coin ~= 0 then
        network:DispatchCommand("update_resource_coin", self.save.coin)
    end
    card.model_id = tonumber(upgrade.next_card_id)
    local new_cfg = self:GetCardConfig(card.model_id)
    card.group_id = new_cfg and new_cfg.group_id or card.group_id
    card.level = new_cfg and new_cfg.level or card.level
    self:Save()
    return {
        id = card.id,
        model_id = card.model_id,
        deck_flag = card.deck_flag,
        is_lock = card.is_lock,
    }
end

offline_server.handlers["req_card_resolve"] = function(self, req)
    local card = self:GetCardByUid(req.card_id)
    if not card then
        return "card_is_null"
    end
    -- resolve config: card_id -> item list
    local resolve = data_template.card_resolve_config
    local item_list = resolve[tostring(card.model_id)]
    if not item_list then
        -- try kind-based keys
        item_list = nil
    end
    if not item_list then
        item_list = { { item_id = 100001, item_num = 2 } }
    end
    -- grant items, remove card
    local out = {}
    local new_items = {}
    for _, it in ipairs(item_list) do
        local item_id = it.item_id
        local num = it.item_num
        if item_id and num then
            local old = self.save.items[tostring(item_id)] or 0
            self.save.items[tostring(item_id)] = old + num
            new_items[tostring(item_id)] = old + num
            table.insert(out, { uid = item_id, num = old + num })
        end
    end
    self:RemoveCard(card.id)
    if next(new_items) then
        local list = {}
        for k, v in pairs(new_items) do
            table.insert(list, { uid = tonumber(k), num = v })
        end
        network:DispatchCommand("update_item_list", { item_list = list })
    end
    self:Save()
    return { item_list = out }
end

offline_server.handlers["req_card_compose"] = function(self, req)
    local model_id = req.card_model_id
    local config = data_template.card_compose_config[model_id]
    if not config then
        return "card_compose_failed"
    end
    local item_id = config[1].item_id
    local item_num = config[1].item_num
    local have = self.save.items[tostring(item_id)] or 0
    if have < item_num then
        if item_id == 200001 then
            return "item_powder_not_enough"
        end
        return "powder_not_enough"
    end
    self.save.items[tostring(item_id)] = have - item_num
    network:DispatchCommand("update_item_list", {
        item_list = { { uid = item_id, num = have - item_num } },
    })
    self:AddCard(model_id)
    self:Save()
    return nil
end

offline_server.handlers["req_card_lock"] = function(self, req)
    local card = self:GetCardByUid(req.card_id)
    if card then
        card.is_lock = req.is_lock or false
        self:Save()
    end
    return nil
end

offline_server.handlers["req_card_group_panel"] = function(self)
    return { card_group_list = {} }
end

offline_server.handlers["req_card_group_open"] = function(self)
    return nil
end

-- =====================================================================
-- Handlers: arena (PvP vs AI)
-- =====================================================================

offline_server.handlers["query_arena_info"] = function(self)
    return self:BuildArenaPanel()
end

offline_server.handlers["req_arena_refresh_time"] = function(self)
    local next_time = os.time() + 2 * 3600
    self.save.arena.next_refresh_chest = next_time
    self.save.arena.last_reward_chest_num = 3
    self:Save()
    return {
        next_refresh_time = next_time,
        reward_chest_num = 3,
    }
end

-- start a casual battle against a bot
offline_server.handlers["req_arena_join_match"] = function(self)
    self:StartBotBattle("casual")
    return nil
end

offline_server.handlers["req_arena_cancel_match"] = function(self)
    return nil
end

-- =====================================================================
-- Handlers: chests
-- =====================================================================

offline_server.handlers["query_chest_info"] = function(self)
    local chest_list = {}
    for chest_id, num in pairs(self.save.chests) do
        if num > 0 then
            table.insert(chest_list, { chest_id = tonumber(chest_id), chest_num = num })
        end
    end
    return { chest_list = chest_list }
end

offline_server.handlers["req_open_chest"] = function(self, req)
    local chest_id = req.chest_id
    local num = self.save.chests[tostring(chest_id)]
    if not num or num <= 0 then
        return "chest_is_empty"
    end
    local cfg = data_template.chest_config[chest_id]
    local card_num = cfg and tonumber(cfg.card_num) or 2
    local harvert_list = {}
    for i = 1, card_num do
        local model_id = self:RandomCardFromPool()
        local card = self:AddCard(model_id)
        table.insert(harvert_list, {
            reward_card_id = model_id,
            is_resolve = false,
            item_list = {},
        })
    end
    -- money reward
    if cfg and cfg.reward_money then
        local money = cfg.reward_money
        local min = tonumber(money[1]) or 0
        local max = tonumber(money[2]) or 0
        local value = min
        if max > min then
            value = math.random(min, max)
        end
        self:AddMoney(value)
    end
    self.save.chests[tostring(chest_id)] = num - 1
    self:Save()
    return { harvert_list = harvert_list }
end

-- =====================================================================
-- Handlers: PvE campaign
-- =====================================================================

offline_server.handlers["req_pve_play_info"] = function(self)
    local list = {}
    for play_id, info in pairs(self.save.pve) do
        table.insert(list, {
            play_id = tostring(play_id),
            difficulty = info.difficulty,
            image = info.image or {},
        })
    end
    if #list == 0 then
        -- seed with play 1001
        table.insert(list, {
            play_id = "1001",
            difficulty = 1,
            image = {},
        })
        self.save.pve["1001"] = { difficulty = 1, image = {} }
        self:Save()
    end
    return list
end

offline_server.handlers["req_refresh_pve"] = function(self)
    local next_time = os.time() + 2 * 3600
    self.save.pve_next_refresh_time = next_time
    self:Save()
    return {
        next_refresh_time = next_time,
        pve_count = 0,
    }
end

offline_server.handlers["req_pve_battle_start"] = function(self, req)
    local play_id = req.play_id or 1001
    local difficulty = req.difficulty or 1
    local attack_type = req.attack_type or 2
    local use_system = (tonumber(attack_type) or 2) == 2

    -- update saved difficulty
    local info = self.save.pve[tostring(play_id)] or { difficulty = difficulty, image = {} }
    info.difficulty = difficulty
    self.save.pve[tostring(play_id)] = info

    local pcfg = nil
    for _, v in pairs(data_template.pve_play_config) do
        if tonumber(v.play_id) == tonumber(play_id) and tonumber(v.difficulty) == tonumber(difficulty) then
            pcfg = v
            break
        end
    end
    local win_target = pcfg and (tonumber(pcfg.win_target_value) or 10) or 10

    local own_deck = self:BuildPlayerDeck(use_system, play_id, difficulty)
    local enemy_deck, _ = self:PickPveEnemyDeck(play_id, difficulty)
    if not enemy_deck then
        return "pve_config_null"
    end

    self:Save()
    self:StartBattle({
        battle_type = "daily",
        battle_object_type = "pve",
        pve_info = { play_id = tonumber(play_id), difficulty = tonumber(difficulty), pve_win_cur_value = 0 },
        pve_win_target = win_target,
        own_deck = own_deck,
        enemy_deck = enemy_deck,
        enemy_name = "[AI] " .. (pcfg and pcfg.play_name or "Enemy"),
        on_battle_over = function(battle, cmd_over)
            self:OnPveOver(battle, cmd_over, play_id, difficulty, pcfg)
        end,
    })
    return nil
end

function offline_server:OnPveOver(battle, cmd_over, play_id, difficulty, pcfg)
    if battle.win_user_id == "player" then
        local key = tostring(play_id) .. tostring(difficulty)
        local first_clear = not self.save.pve_cleared[key]
        self.save.pve_cleared[key] = true

        -- base rewards: exp + random card drop
        local rewards = {}
        local exp_gain = 10 + (tonumber(difficulty) or 1) * 5
        table.insert(rewards, { type = "resource", attr_id = 400001, value = exp_gain })
        local drop = self:RandomCardFromPool()
        table.insert(rewards, { type = "card", attr_id = drop, value = 1 })
        -- config-defined rewards (if pcfg exists)
        if pcfg then
            if first_clear then
                for i = 1, 3 do
                    local t = pcfg["first_reward_type" .. i]
                    local id = pcfg["first_reward_id" .. i]
                    local n = pcfg["first_reward_num" .. i]
                    if id and tonumber(id) ~= 0 then
                        table.insert(rewards, { type = t, attr_id = tonumber(id), value = tonumber(n) })
                    end
                end
            else
                for i = 1, 3 do
                    local t = pcfg["reward_type" .. i]
                    local id = pcfg["reward_id" .. i]
                    local n = pcfg["reward_num" .. i]
                    if id and tonumber(id) ~= 0 then
                        table.insert(rewards, { type = t, attr_id = tonumber(id), value = tonumber(n) })
                    end
                end
            end
        end
        self:ApplyRewards(rewards)
        cmd_over.reward_info = rewards
        cmd_over.pve_info = { difficulty = tonumber(difficulty) }
    else
        cmd_over.pve_info = { difficulty = tonumber(difficulty) }
    end
    self:Save()
end

-- =====================================================================
-- Handlers: adventure (exam)
-- =====================================================================

offline_server.handlers["req_adventure_info"] = function(self)
    return {
        progress = self.save.adventure.progress or 1,
        pass_ids = self.save.adventure.pass_ids or {},
    }
end

offline_server.handlers["req_adventure_battle_start"] = function(self, req)
    local id = req.id or 1
    local cfg = data_template.adventure_config[id]
    if not cfg then
        return "adventure_config_null"
    end
    local own_deck = { monster_list = {}, item_list = {} }
    local enemy_deck = { monster_list = {}, item_list = {} }
    local uid = 1
    for _, m in ipairs(self:SplitList(cfg.employee_monster_list)) do
        local c = self:CardInfoFromModel(m, uid, nil, self.save.user_id)
        if c then table.insert(own_deck.monster_list, c) end
        uid = uid + 1
    end
    for _, m in ipairs(self:SplitList(cfg.employee_item_list)) do
        local c = self:CardInfoFromModel(m, uid, nil, self.save.user_id)
        if c then table.insert(own_deck.item_list, c) end
        uid = uid + 1
    end
    for _, m in ipairs(self:SplitList(cfg.ai_monster_list)) do
        local c = self:CardInfoFromModel(m, uid, nil, "enemy")
        if c then table.insert(enemy_deck.monster_list, c) end
        uid = uid + 1
    end
    for _, m in ipairs(self:SplitList(cfg.ai_item_list)) do
        local c = self:CardInfoFromModel(m, uid, nil, "enemy")
        if c then table.insert(enemy_deck.item_list, c) end
        uid = uid + 1
    end

    self:StartBattle({
        battle_type = "casual",
        battle_object_type = "pvp",
        pve_info = nil,
        own_deck = own_deck,
        enemy_deck = enemy_deck,
        enemy_name = "Examiner",
        on_battle_over = function(battle, cmd_over)
            self:OnAdventureOver(battle, cmd_over, id, cfg)
        end,
    })
    return nil
end

function offline_server:OnAdventureOver(battle, cmd_over, id, cfg)
    if battle.win_user_id == "player" then
        local adv = self.save.adventure
        local pass_ids = adv.pass_ids or {}
        local passed = false
        for _, v in ipairs(pass_ids) do
            if tonumber(v) == tonumber(id) then
                passed = true
                break
            end
        end
        if not passed then
            table.insert(pass_ids, tonumber(id))
        end
        adv.pass_ids = pass_ids
        -- progress to next exam level
        if tonumber(id) >= (adv.progress or 1) then
            adv.progress = (adv.progress or 1) + 1
        end
        -- rewards
        local rewards = {}
        local t = cfg.reward_type1
        local rid = cfg.reward_id1
        local rn = cfg.reward_num1
        if rid and tonumber(rid) ~= 0 then
            table.insert(rewards, { type = t, attr_id = tonumber(rid), value = tonumber(rn) })
        end
        self:ApplyRewards(rewards)
        cmd_over.reward_info = rewards
        cmd_over.adventure_info = {
            progress = adv.progress,
            pass_id = tonumber(id),
        }
    end
    self:Save()
end

-- =====================================================================
-- Handlers: daily & login reward
-- =====================================================================

offline_server.handlers["req_refresh_daily"] = function(self)
    local next_time = self.save.daily.next_refresh_time or 0
    if next_time < os.time() then
        next_time = self:GetNextDailyReset()
        self.save.daily.next_refresh_time = next_time
        self.save.daily.login_reward = 1
        self:Save()
    end
    return {
        next_refresh_time = next_time,
        login_reward = self.save.daily.login_reward or 0,
    }
end

function offline_server:GetNextDailyReset()
    -- next 4am local time
    local t = os.date("*t", os.time())
    local next_t = os.time({ year = t.year, month = t.month, day = t.day, hour = 4, min = 0, sec = 0 })
    if next_t <= os.time() then
        next_t = next_t + 86400
    end
    return next_t
end

offline_server.handlers["req_login_reward"] = function(self)
    if (self.save.daily.login_reward or 0) <= 0 then
        return { reward_list = {} }
    end
    self.save.daily.login_reward = 0
    local rewards = {
        { type = "resource", attr_id = 500001, value = 50 },
    }
    self:ApplyRewards(rewards)
    self:Save()
    return { reward_list = rewards }
end

-- =====================================================================
-- Handlers: mail
-- =====================================================================

offline_server.handlers["query_mail_info"] = function(self)
    return { mail_list = self.save.mails or {} }
end

offline_server.handlers["look_over_mail"] = function(self, req)
    for _, m in ipairs(self.save.mails) do
        if m.mail_id == req then
            m.stage = 2
            break
        end
    end
    self:Save()
    return nil
end

offline_server.handlers["receive_mail_attachment"] = function(self, req)
    local mail = nil
    for _, m in ipairs(self.save.mails) do
        if m.mail_id == req then
            mail = m
            break
        end
    end
    if not mail then
        return "mail_is_null"
    end
    local rewards = {}
    for _, att in ipairs(mail.attachment_list or {}) do
        if att.att_type == 2 and att.attr_id then
            table.insert(rewards, { type = "resource", attr_id = att.attr_id, value = att.value })
        end
    end
    self:ApplyRewards(rewards)
    mail.stage = 2
    mail.attachment_list = {}
    self:Save()
    return {
        update_mail = mail,
        reward_list = rewards,
    }
end

-- =====================================================================
-- Handlers: tasks / achievements / statistic
-- =====================================================================

offline_server.handlers["req_refresh_task"] = function(self)
    local t = self.save.tasks
    t.next_refresh_task_count_time = self:GetNextDailyReset()
    t.next_refresh_task_time = 0
    t.task_reset_count = 0
    self:Save()
    return {
        next_refresh_task_count_time = t.next_refresh_task_count_time,
        task_count = t.task_count or 0,
        task_reset_count = t.task_reset_count or 0,
        next_refresh_task_time = t.next_refresh_task_time,
    }
end

offline_server.handlers["req_task_info"] = function(self)
    local task = self.save.cur_task
    if not task then
        task = { id = 1, progress = 0, status = 0 }
        self.save.cur_task = task
    end
    return task
end

offline_server.handlers["req_task_reward"] = function(self)
    local task = self.save.cur_task
    if not task or task.status ~= 1 then
        return "task_reward_failed"
    end
    task.status = 2
    self:Save()
    return task
end

offline_server.handlers["req_task_reset"] = function(self)
    local t = self.save.tasks
    if t.task_reset_count >= 1 then
        return "task_reset_failed"
    end
    t.task_reset_count = (t.task_reset_count or 0) + 1
    local task = { id = math.random(100001, 100010), progress = 0, status = 0 }
    self.save.cur_task = task
    self:Save()
    return task
end

offline_server.handlers["req_achievement_info"] = function(self)
    return {
        achi_points = self.save.achievements.achi_points or 0,
        achi_list = self.save.achievements.achi_list or {},
    }
end

offline_server.handlers["req_achievement_reward"] = function(self, req)
    local list = self.save.achievements.achi_list or {}
    for _, a in ipairs(list) do
        if a.id == req.id then
            a.status = 2
            return a
        end
    end
    return { id = req.id, status = 2 }
end

offline_server.handlers["req_statistic_info"] = function(self)
    return {}
end

-- =====================================================================
-- Handlers: guide
-- =====================================================================

offline_server.handlers["req_guide_panel"] = function(self)
    return { guide_flag = self.save.guide_flag or 0 }
end

offline_server.handlers["req_guide_complete"] = function(self, req)
    local guide_id = req.guide_id
    if guide_id then
        local flag = self.save.guide_flag or 0
        self.save.guide_flag = bit_bor(flag, bit_lshift(1, guide_id))
        network:DispatchCommand("cmd_guide_info", { guide_flag = self.save.guide_flag })
        self:Save()
    end
    return nil
end

offline_server.handlers["req_guide_battle"] = function(self, req)
    local battle_process = req.battle_process or 1
    -- guide battle decks: player uses own deck, AI uses a scaled weak deck
    local own_deck = self:BuildPlayerDeck(false)
    local enemy_deck = { monster_list = {}, item_list = {} }
    if tonumber(battle_process) == 1 then
        -- Tutorial 1: easy war monsters (HP 3-5, cost 1-2)
        for _, m in ipairs({ 110011, 110011, 110012, 110012, 110013, 110013, 110014, 110015 }) do
            local card = self:CardInfoFromModel(m, "g1_" .. m, nil, "enemy")
            if card then table.insert(enemy_deck.monster_list, card) end
        end
        for _, m in ipairs({ 21001, 21002, 22001, 22002, 23001, 23002, 24001, 24002 }) do
            local card = self:CardInfoFromModel(m, "g1i_" .. m, nil, "enemy")
            if card then table.insert(enemy_deck.item_list, card) end
        end
    else
        -- Tutorial 2: slightly stronger mixed deck
        for _, m in ipairs({ 110011, 110013, 110015, 110021, 110023, 110025, 110031, 110033 }) do
            local card = self:CardInfoFromModel(m, "g2_" .. m, nil, "enemy")
            if card then table.insert(enemy_deck.monster_list, card) end
        end
        for _, m in ipairs({ 21001, 21002, 22001, 22002, 23001, 23002, 24001, 24002 }) do
            local card = self:CardInfoFromModel(m, "g2i_" .. m, nil, "enemy")
            if card then table.insert(enemy_deck.item_list, card) end
        end
    end
    -- Fallback: if no valid cards, generate a basic deck
    if #enemy_deck.monster_list == 0 then
        local fallback = self:PickPveEnemyDeck(1001, 1)
        if fallback then enemy_deck = fallback end
    end
    self:StartBattle({
        battle_type = "guide",
        battle_object_type = "pve",
        pve_info = { play_id = tonumber(battle_process), difficulty = 1, pve_win_cur_value = 0 },
        pve_win_target = 0,
        own_deck = own_deck,
        enemy_deck = enemy_deck,
        enemy_name = "[AI] Will",
        on_battle_over = function(battle, cmd_over)
            cmd_over.pve_info = { difficulty = 1 }
        end,
    })
    return nil
end

-- =====================================================================
-- Handlers: friends / chat / rank / challenge / cdkey (stubs)
-- =====================================================================

offline_server.handlers["req_friend_list"] = function(self)
    return { ret_friend_list = {} }
end

offline_server.handlers["req_friend_search"] = function(self)
    return { can_be_added = false }
end

offline_server.handlers["req_friend_add"] = function(self)
    return nil
end

offline_server.handlers["req_friend_add_list"] = function(self)
    return { can_be_added = true, add_list = {} }
end

offline_server.handlers["req_friend_add_accept"] = function(self)
    return nil
end

offline_server.handlers["req_friend_add_refuse"] = function(self)
    return nil
end

offline_server.handlers["req_friend_added_or_not"] = function(self)
    return { state = false }
end

offline_server.handlers["req_friend_invite_battle"] = function(self)
    return "friend_not_online"
end

offline_server.handlers["req_friend_cancel_invite"] = function(self)
    return nil
end

offline_server.handlers["req_chat_info"] = function(self)
    return nil
end

offline_server.handlers["req_chat_say"] = function(self)
    return nil
end

offline_server.handlers["req_chat_close"] = function(self)
    return nil
end

offline_server.handlers["req_rank_info"] = function(self)
    local rank_list = {}
    table.insert(rank_list, {
        user_id = self.save.user_id,
        user_name = self.save.name,
        win_count = self.save.wins or 0,
        loss_count = self.save.losses or 0,
        draw_count = 0,
        elo_value = self.save.arena.elo_value,
        global_rank = 1,
    })
    return {
        my_rank = 1,
        rank_list = rank_list,
    }
end

offline_server.handlers["query_challenge_info"] = function(self)
    return { cup_num = self.save.arena.elo_value }
end

offline_server.handlers["req_create_challenge"] = function(self, req)
    local number = math.random(100000, 999999)
    return {
        number = number,
        room_info = {
            { user_id = self.save.user_id, user_name = self.save.name, status = "wait", cup_num = self.save.arena.elo_value },
        },
    }
end

offline_server.handlers["req_join_challenge"] = function(self, req)
    return "challenge_room_not_found"
end

offline_server.handlers["req_exit_challenge"] = function(self)
    return nil
end

offline_server.handlers["req_start_battle"] = function(self)
    return nil
end

offline_server.handlers["req_wait_battle"] = function(self)
    return nil
end

offline_server.handlers["query_reconnect_challenge_info"] = function(self)
    return nil
end

offline_server.handlers["req_cdk_reward"] = function(self, req)
    local code = req.code or ""
    if string.lower(code) == "campaign" then
        local rewards = {
            { type = "resource", attr_id = 500001, value = 500 },
            { type = "resource", attr_id = 500002, value = 100 },
        }
        self:ApplyRewards(rewards)
        self:Save()
        return { reward_list = rewards }
    end
    return "cdk_not_valid"
end

-- =====================================================================
-- Battle plumbing
-- =====================================================================

-- (StartBattle defined below with SetCurrentBattle)

-- casual/periphery battle vs a bot built from pve-style decks scaled by level
function offline_server:StartBotBattle(battle_type)
    local own_deck = self:BuildPlayerDeck(false)
    local level = self.save.level or 1
    local diff = math.min(4, math.max(1, math.floor(level / 2) + 1))
    local enemy_deck = { monster_list = {}, item_list = {} }
    local uid = 1
    -- use the first pve play's AI deck at an appropriate difficulty
    local pcfg = nil
    local play_id = nil
    for _, v in pairs(data_template.pve_play_config) do
        if tonumber(v.play_id) == 1001 and tonumber(v.difficulty) == diff then
            pcfg = v
            play_id = v.play_id
            break
        end
    end
    if not pcfg then
        for _, v in pairs(data_template.pve_play_config) do
            if tonumber(v.difficulty) == 1 then
                pcfg = v
                play_id = v.play_id
                break
            end
        end
    end
    if pcfg then
        for _, m in ipairs(self:SplitList(pcfg.ai_monster_list)) do
            local c = self:CardInfoFromModel(m, uid, nil, "enemy")
            if c then table.insert(enemy_deck.monster_list, c) end
            uid = uid + 1
        end
        for _, m in ipairs(self:SplitList(pcfg.ai_item_list)) do
            local c = self:CardInfoFromModel(m, uid, nil, "enemy")
            if c then table.insert(enemy_deck.item_list, c) end
            uid = uid + 1
        end
    end

    self:StartBattle({
        battle_type = battle_type or "casual",
        battle_object_type = "pvp",
        pve_info = nil,
        own_deck = own_deck,
        enemy_deck = enemy_deck,
        enemy_name = "Bot",
        enemy_arena_level = level,
        on_battle_over = function(battle, cmd_over)
            self:OnArenaOver(battle, battle_type, cmd_over)
        end,
    })
end

function offline_server:OnArenaOver(battle, battle_type, cmd_over)
    local a = self.save.arena
    if battle.win_user_id == "player" then
        a.win_count = (a.win_count or 0) + 1
        a.elo_value = (a.elo_value or 1000) + 20
        self.save.wins = self.save.wins + 1
        local rewards = {
            { type = "resource", attr_id = 500001, value = 20 + a.level * 5 },
        }
        self:ApplyRewards(rewards)
        cmd_over.reward_info = rewards
    else
        a.loss_count = (a.loss_count or 0) + 1
        a.elo_value = math.max(100, (a.elo_value or 1000) - 15)
        self.save.losses = self.save.losses + 1
    end
    -- promote arena level every 3 wins
    local new_level = math.floor((a.win_count or 0) / 3) + 1
    if new_level > (a.level or 1) then
        a.level = new_level
    end
    cmd_over.arena_info = {
        stage = a.stage or 1,
        level = a.level or 1,
        elo_value = a.elo_value or 1000,
    }
    self:Save()
end

-- =====================================================================
-- req_battle sub-requests (battle actions)
-- =====================================================================

offline_server.handlers["req_battle"] = function(self, req)
    local current = self.current_battle
    if not current then
        return "battle_is_null"
    end
    for k, v in pairs(req or {}) do
        if k == "req_battle_move" then
            local err = current:HandleMove(v or {})
            if err then return err end
        elseif k == "req_battle_immolation" then
            local err = current:HandleSacrifice(v or {})
            if err then return err end
        elseif k == "req_battle_attack" then
            local err = current:HandleAttack(v or {})
            if err then return err end
        elseif k == "req_battle_standby" then
            current:HandleStandby()
        elseif k == "req_battle_surrender" then
            local err = current:HandleSurrender()
            if err then return err end
        elseif k == "req_battle_sync" or k == "req_battle_stage" or k == "req_battle_replay" then
            -- no-op
        end
    end
    return nil
end

-- track the current battle so req_battle sub-requests can reach it
function offline_server:SetCurrentBattle(battle)
    self.current_battle = battle
end

-- =====================================================================
-- Init
-- =====================================================================

function offline_server:Init()
    self.save = nil
    self.logged_in = false
    self.current_battle = nil
end

-- tie battle tracking into StartBattle
function offline_server:StartBattle(opts)
    opts.battle_id = opts.battle_id or ("battle_" .. os.time() .. "_" .. math.random(1000, 9999))
    local battle = offline_battle.New(opts, function(cmd)
        network:DispatchCommand("cmd_battle", cmd)
    end)
    self:SetCurrentBattle(battle)
    battle:Start()
end

return offline_server
