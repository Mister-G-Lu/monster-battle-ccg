-- web_bridge.lua
-- Thin, UI-facing adapter over the REAL game engine (offline_server / offline_battle
-- / campaign_service). It exposes plain Lua tables that the JS/Canvas layer reads;
-- it adds NO game logic of its own. Same source of truth as the APK.
--
-- Loaded after the platform stubs (see boot.js) have installed cc/ccui/aandm/etc.

local network         = require "manager.network"
local campaign_data   = require "manager.campaign_data"
local campaign_service = require "manager.campaign_service"
local data_template   = require "manager.data_template"

local B = {}

-- ---------------------------------------------------------------------------
-- boot: log in through the offline server exactly like the client does
-- ---------------------------------------------------------------------------
local offline_server
local battle_log = {}   -- captured cmd_battle stream (for UI animation hooks)

function B.boot()
    network:RegisterProto()
    network:Connect("offline", 28800)

    local ok = false
    network:Send("req_login_game", {
        name = "web_player", token = "web", type = "debug",
        channel = "debug", language = "en-US", version = "1.4",
    }, function(result) ok = (result == "success") end)

    offline_server = require "manager.offline_server"

    network:RegisterCommand("cmd_battle", function(msg)
        battle_log[#battle_log + 1] = msg
    end)
    return ok
end

-- ---------------------------------------------------------------------------
-- campaign map snapshot
-- ---------------------------------------------------------------------------
function B.campaign_info()
    local save = offline_server:GetCampaignSave()
    local info = campaign_service.info(save)

    local regions = {}
    for _, region in ipairs(campaign_service.regions()) do
        local nodes = {}
        for _, node in ipairs(region.nodes) do
            nodes[#nodes + 1] = {
                id       = node.id,
                name     = node.name or node.id,
                type     = node.type or "battle",
                final    = node.final == true,
                kind     = node.kind and campaign_data.kind_name(node.kind) or nil,
                hp       = node.hp,
                cleared  = save.cleared[node.id] == true,
                playable = campaign_service.is_playable(save, node),
            }
        end
        regions[#regions + 1] = {
            id    = region.id,
            name  = region.name or region.id,
            kind  = region.kind and campaign_data.kind_name(region.kind) or nil,
            nodes = nodes,
        }
    end

    return {
        regions        = regions,
        current_node   = info.current_node,
        vitality       = info.vitality,
        wins           = info.wins,
        losses         = info.losses,
        bosses_slain   = info.bosses_slain,
        complete       = info.complete == true,
        pending_recruit = info.pending_recruit,
        collection_size = info.collection and #info.collection or 0,
    }
end

-- ---------------------------------------------------------------------------
-- battle: start + read a full snapshot the UI can render
-- ---------------------------------------------------------------------------
function B.start_battle(node_id)
    battle_log = {}
    local ok = false
    network:Send("req_campaign_battle_start", { node_id = node_id },
        function(result) ok = (result == "success") end)
    return ok
end

local function card_view(c)
    if not c then return nil end
    return {
        uid   = c.uid,
        name  = c.name,
        type  = c.type,
        cost  = c.cost or 0,
        hp    = c.hp or 0,
        kind  = c.kind,
        level = c.level or 1,
        quality = c.quality,
    }
end

local function slot_view(s)
    if not s or not s.monster then return nil end
    return {
        name   = s.monster.name,
        cur_hp = s.cur_hp or s.monster.hp,
        max_hp = s.monster.hp,
        cur_ad = s.cur_ad or 0,
        kind   = s.monster.kind,
        has_item = s.item ~= nil,
        item_name = s.item and s.item.name or nil,
    }
end

local function actor_view(actor)
    local hand = {}
    for p = 1, 4 do hand[p] = card_view(actor:GetHandCard(p)) end
    local board = {}
    for i = 1, 3 do board[i] = slot_view(actor:GetBattleCard(i)) end
    return {
        name        = actor.name,
        crystal     = actor.cur_crystal or 0,
        is_sacrifice = actor.is_sacrifice == true,
        deck_left   = actor.monster_len or 0,
        hand        = hand,
        board       = board,
    }
end

function B.battle_state()
    local b = offline_server.current_battle
    if not b then return { active = false } end
    return {
        active      = true,
        hero_mode   = b.hero_mode == true,
        round       = b.round or 0,
        is_over     = b.is_over == true,
        winner      = b.win_user_id,
        own_hp      = b.own_hp, own_max_hp = b.own_max_hp,
        enemy_hp    = b.enemy_hp, enemy_max_hp = b.enemy_max_hp,
        turn_of     = b.cur_oper_user_id,
        own         = actor_view(b.own),
        enemy       = actor_view(b.enemy),
    }
end

-- ---------------------------------------------------------------------------
-- battle: player actions (drive the REAL engine handlers)
-- ---------------------------------------------------------------------------
function B.sacrifice(hand_pos)
    local b = offline_server.current_battle
    if b and not b.is_over then b:HandleSacrifice({ is_hand = true, pos = hand_pos }) end
end

-- Deploy a monster from hand to the current free monster slot; equip/consume
-- cards target the first friendly monster on the board.
function B.play_card(hand_pos)
    local b = offline_server.current_battle
    if not b or b.is_over then return false end
    local c = b.own:GetHandCard(hand_pos)
    if not c or not c.cost or c.cost > b.own.cur_crystal then return false end
    if c.type == "monster" then
        local slot = b.own:GetCurMonsterSlotPos()
        if slot and slot > 0 then
            b:HandleMove({ src_pos = hand_pos, is_enemy = false, target_pos = slot })
            return true
        end
        return false
    else
        for s = 1, 3 do
            local slot = b.own:GetBattleCard(s)
            if slot and slot.monster then
                b:HandleMove({ src_pos = hand_pos, is_enemy = false, target_pos = s })
                return true
            end
        end
        return false
    end
end

function B.end_turn()
    local b = offline_server.current_battle
    if b and not b.is_over then b:HandleAttack({}) end
end

-- Recruit draft (after a first clear). Names come from data_template.card_config
-- (the same index the native campaign_panel uses) — never a nil card table.
local function card_snapshot(id)
    local key = tostring(id)
    local cfg = data_template.card_config and (data_template.card_config[key] or data_template.card_config[id])
    local n = campaign_service.normalize_card(cfg)
    if not n then
        return { id = tonumber(id) or id, name = "Card " .. key }
    end
    local name = n.name
    if not name or name == "" or name == key then
        name = "Card " .. key
    end
    return {
        id      = n.id,
        name    = name,
        type    = n.type,
        cost    = n.cost or 0,
        hp      = n.hp or 0,
        kind    = n.kind or "",
        quality = n.quality or "normal",
        attack  = n.attack or 0,
        level   = n.level or 1,
    }
end

function B.recruit_offers(node_id)
    local out = {}
    network:Send("req_campaign_recruit_offers", { node_id = node_id }, function(result, recv)
        if result == "success" and recv and recv.offers then
            for _, id in ipairs(recv.offers) do
                out[#out + 1] = card_snapshot(id)
            end
        end
    end)
    return out
end

function B.recruit(node_id, card_id)
    local ok = false
    network:Send("req_campaign_recruit", { node_id = node_id, card_id = card_id },
        function(result) ok = (result == "success") end)
    return ok
end

function B.skip_recruit()
    local ok = false
    network:Send("req_campaign_skip_recruit", {}, function(result)
        ok = (result == "success")
    end)
    return ok
end

return B
