-- campaign_service.lua
-- The Shadow Road campaign, served by the Android app's offline service.
--
-- The web shell used to ship the campaign as a parallel HTML app on top of
-- the Android build. This module is the consolidation: the SAME canonical
-- campaign (content/campaign_data.json -> manager.campaign_data) is now
-- served by offline_server.lua through req_campaign_* handlers, played on
-- the native battle engine, with rewards and progression persisted in the
-- player save. The HTML page no longer has to fake an Android frame over
-- the app — the campaign runs inside the app's own service.
--
-- Design notes
--   * Pure data/logic: no cocos, no network, no io. offline_server.lua
--     delegates its campaign handlers here, so the whole module is
--     testable with plain Lua 5.1/LuaJIT and no APK fixtures.
--   * The native engine is canonical: a battle ends when one side's
--     monster army is exhausted. node.hp (the web model's enemy commander
--     value) travels with the node as metadata for the UI; difficulty is
--     set by the node's deck (explicit deck_ids or resolved faction pool).
--   * Powers (muster/plunder/...) are data here (name/desc) for the client
--     to display; their mechanics remain a native-engine concern (PR E in
--     docs/NEXT_STEPS.md), not a web-only hook.

local campaign = require("manager.campaign_data")

local M = {}

M.BASE_VITALITY = 30
M.VITALITY_CAP = 38      -- 30 + 4 bosses * 2, same ceiling as the web shell
M.DRAFT_SIZE = 3
M.REPLAY_EXP = 5         -- replaying a cleared node
M.SKIP_RECRUIT_EXP = 15  -- taking EXP instead of a recruit

-- ---------------------------------------------------------------------------
-- Save
-- ---------------------------------------------------------------------------

function M.default_save()
    return {
        cleared = {},          -- node_id -> true
        collection = {},       -- card model ids (starter + recruits)
        exp = 0,
        wins = 0,
        losses = 0,
        vitality = M.BASE_VITALITY,
        bosses_slain = 0,
        complete = false,
        starter_granted = false,
        pending_recruit = nil, -- node id awaiting a recruit pick
        pending_offers = nil,  -- card ids offered for the pending recruit
    }
end

-- Idempotently seed the starter collection.
function M.ensure_starter(save)
    if save.starter_granted then
        return save.collection
    end
    save.collection = {}
    for _, id in ipairs(campaign.STARTER_COLLECTION) do
        save.collection[#save.collection + 1] = id
    end
    save.starter_granted = true
    return save.collection
end

function M.reset(save)
    local fresh = M.default_save()
    for k, v in pairs(fresh) do
        save[k] = v
    end
    M.ensure_starter(save)
    return save
end

-- ---------------------------------------------------------------------------
-- Campaign data access
-- ---------------------------------------------------------------------------

function M.node_by_id(id)
    local node = campaign.node_by_id(id)
    return node
end

function M.all_nodes()
    return campaign.all_nodes()
end

function M.regions()
    return campaign.REGIONS
end

function M.region_of(node)
    for _, region in ipairs(campaign.REGIONS) do
        for _, n in ipairs(region.nodes) do
            if n == node then
                return region
            end
        end
    end
    return nil
end

-- The node the player is currently fighting: the first uncleared node in
-- region order (nil when the road is complete).
function M.current_node(save)
    for _, region in ipairs(campaign.REGIONS) do
        for _, node in ipairs(region.nodes) do
            if not save.cleared[node.id] then
                return node
            end
        end
    end
    return nil
end

-- A node is playable when it is cleared (replay) or it is exactly the
-- current node of the campaign (sequential progression; a region only
-- unlocks after the previous region's boss falls).
function M.is_playable(save, node)
    if not node then return false end
    if save.cleared[node.id] then return true end
    local cur = M.current_node(save)
    return cur ~= nil and cur.id == node.id
end

-- ---------------------------------------------------------------------------
-- Card index
-- ---------------------------------------------------------------------------

-- Normalize a card record from either source the server can hand us:
--   * data_template.card_config (device): kind is a bitmask + kind_list,
--     attack is buried in power_list, no flags column.
--   * campaign_data.load_cards_from_csv() (tests): kind is a string, attack
--     derivable from the p1n/p1v columns, flags present.
-- The normalized shape is what the pool resolver and the recruit draft use.
function M.normalize_card(cfg)
    if not cfg then return nil end
    local id = tonumber(cfg.id) or tonumber(cfg.uid)
    if not id then return nil end

    local kind_name = nil
    if type(cfg.kind) == "string" and cfg.kind ~= "" then
        kind_name = cfg.kind
    elseif type(cfg.kind_list) == "table" and cfg.kind_list[1] then
        kind_name = cfg.kind_list[1]
    end

    local attack = tonumber(cfg.attack) or 0
    if attack == 0 then
        local function power_value(p)
            return p and (tonumber(p.value) or 0) or 0
        end
        local n1 = tostring(cfg.p1n or "")
        if n1 == "melee" or n1 == "ranged" or n1 == "magic" then
            attack = tonumber(cfg.p1v) or 0
        end
        if attack == 0 and type(cfg.power_list) == "table" then
            for _, p in ipairs(cfg.power_list) do
                local n = tostring(p.name or "")
                if n == "melee" or n == "ranged" or n == "magic" then
                    attack = power_value(p)
                    break
                end
            end
        end
    end

    local flags = tonumber(cfg.flags)
    if flags == nil then flags = 1 end  -- template config has no flags column

    return {
        id = id,
        type = cfg.type or "monster",
        kind = kind_name or "",
        level = tonumber(cfg.level) or 1,
        cost = tonumber(cfg.cost) or 0,
        hp = tonumber(cfg.hp) or 0,
        attack = attack,
        quality = cfg.quality or "normal",
        flags = flags,
        name = cfg.name or tostring(id),
    }
end

-- Build a normalized index (model_id -> record) from a raw config table.
function M.normalize_index(raw_cards)
    local idx = {}
    for _, cfg in pairs(raw_cards) do
        local c = M.normalize_card(cfg)
        if c then
            idx[c.id] = c
        end
    end
    return idx
end

function M.card(cards, id)
    if not cards then return nil end
    return cards[tonumber(id)] or cards[tostring(id)]
end

-- ---------------------------------------------------------------------------
-- Deck building
-- ---------------------------------------------------------------------------

-- Enemy card model ids for a node: explicit deck_ids, or a resolved pool.
function M.enemy_deck_ids(node, cards)
    return campaign.enemy_model_ids(node, cards)
end

-- The player's campaign deck: every collected card.
function M.player_deck_ids(save)
    local out = {}
    for _, id in ipairs(save.collection) do
        out[#out + 1] = id
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Progression
-- ---------------------------------------------------------------------------

-- Record a victory. Returns a summary for the client:
--   { exp_gain, first_clear, recruit_offers (nil unless first clear),
--     vitality_gain, boss_slain, complete }
function M.apply_victory(save, node)
    save.wins = save.wins + 1
    local first_clear = not save.cleared[node.id]
    local result = {
        exp_gain = node.exp,
        first_clear = first_clear,
        vitality_gain = 0,
        boss_slain = false,
        complete = save.complete,
        recruit_offers = nil,
    }
    if first_clear then
        save.cleared[node.id] = true
        save.exp = save.exp + node.exp
        if node.type == "boss" then
            save.bosses_slain = save.bosses_slain + 1
            result.boss_slain = true
            save.vitality = math.min(M.VITALITY_CAP, save.vitality + 2)
            result.vitality_gain = 2
        end
        if node.final then
            save.complete = true
            result.complete = true
        end
        -- every first victory grants a recruit draft (bosses: a champion)
        save.pending_recruit = node.id
    else
        -- replay: no recruit, but the road still pays a little
        save.exp = save.exp + M.REPLAY_EXP
        result.exp_gain = M.REPLAY_EXP
    end
    return result
end

function M.apply_defeat(save)
    save.losses = save.losses + 1
end

-- Build the recruit draft (card ids) for a first clear, and remember the
-- offers so the later pick can be validated server-side.
function M.recruit_offers(save, node, cards)
    local region = M.region_of(node)
    local act_idx = 0
    for i, r in ipairs(campaign.REGIONS) do
        if r == region then act_idx = i - 1 break end
    end
    local tier = node.type == "boss" and 2 or (node.type == "elite" and 1 or 0)
    local lv_min = math.min(8, 2 + act_idx + tier)
    local lv_max = math.min(8, 2 + act_idx + tier * 2)
    local atk_cap = tier == 0 and 2 or (tier == 1 and 3 or 9)

    local monsters, items = {}, {}
    for _, c in pairs(cards or {}) do
        if c.flags == 1 or c.flags == "1" then
            if c.type == "monster" then
                monsters[#monsters + 1] = c
            elseif tonumber(c.cost) <= 4 then
                items[#items + 1] = c
            end
        end
    end

    local kind = region and region.faction or nil
    local function matches_kind(c)
        return kind == nil or c.kind == kind or math.random() < 0.34
    end
    local pool = {}
    for _, c in ipairs(monsters) do
        if matches_kind(c) and c.level >= lv_min and c.level <= lv_max and c.attack <= atk_cap then
            pool[#pool + 1] = c
        end
    end
    if tier == 2 then
        local strong = {}
        for _, c in ipairs(pool) do
            if c.quality == "epic" or c.attack >= 3 then strong[#strong + 1] = c end
        end
        if #strong >= 3 then pool = strong end
    end
    if #pool < 3 then
        pool = {}
        for _, c in ipairs(monsters) do
            if c.kind == kind and c.level >= lv_min - 1 and c.level <= lv_max + 1 and c.attack <= atk_cap then
                pool[#pool + 1] = c
            end
        end
    end
    if #pool < 3 then
        pool = {}
        for _, c in ipairs(monsters) do
            if c.attack <= atk_cap then pool[#pool + 1] = c end
        end
    end
    if #pool < 3 then pool = monsters end

    local item_pool = {}
    for _, c in ipairs(items) do
        if c.level <= lv_max then item_pool[#item_pool + 1] = c end
    end
    if #item_pool < 3 then item_pool = items end

    local function score(c)
        return c.attack * 2 + c.hp / 2
    end
    table.sort(pool, function(a, b) return score(a) > score(b) end)
    table.sort(item_pool, function(a, b) return score(a) > score(b) end)

    -- one per cost band, then fill; items ride along for spice
    local offers = {}
    local used_band = {}
    local candidates = {}
    for _, c in ipairs(pool) do candidates[#candidates + 1] = c end
    for _, c in ipairs(item_pool) do candidates[#candidates + 1] = c end
    local function band(c)
        local cost = tonumber(c.cost) or 0
        return cost <= 2 and 1 or (cost <= 3 and 2 or 3)
    end
    for _, c in ipairs(candidates) do
        if not used_band[band(c)] then
            used_band[band(c)] = true
            offers[#offers + 1] = c.id
        end
        if #offers >= M.DRAFT_SIZE then break end
    end
    if #offers < M.DRAFT_SIZE then
        for _, c in ipairs(pool) do
            local dup = false
            for _, o in ipairs(offers) do if o == c.id then dup = true break end end
            if not dup then
                offers[#offers + 1] = c.id
            end
            if #offers >= M.DRAFT_SIZE then break end
        end
    end

    save.pending_offers = offers
    return offers
end

-- Validate and apply a recruit pick against the pending offers.
function M.apply_recruit(save, card_id)
    local offers = save.pending_offers
    if not offers or #offers == 0 then
        return false
    end
    local found = false
    for _, id in ipairs(offers) do
        if tonumber(id) == tonumber(card_id) then
            found = true
            break
        end
    end
    if not found then
        return false
    end
    save.collection[#save.collection + 1] = tonumber(card_id)
    save.pending_recruit = nil
    save.pending_offers = nil
    return true
end

-- Decline the recruit: take EXP instead (matches the web shell's skip).
function M.skip_recruit(save)
    if not save.pending_recruit then
        return false
    end
    save.exp = save.exp + M.SKIP_RECRUIT_EXP
    save.pending_recruit = nil
    save.pending_offers = nil
    return true
end

-- ---------------------------------------------------------------------------
-- Client payloads
-- ---------------------------------------------------------------------------

-- Progress + full canonical campaign, in one round trip.
function M.info(save)
    local current = M.current_node(save)
    return {
        regions = campaign.REGIONS,
        current_node = current and current.id or nil,
        cleared = save.cleared,
        collection = save.collection,
        exp = save.exp,
        wins = save.wins,
        losses = save.losses,
        vitality = save.vitality,
        bosses_slain = save.bosses_slain,
        complete = save.complete,
        -- a pending first-clear recruit blocks the next battle until picked
        -- or skipped (the campaign panel surfaces the draft chooser)
        pending_recruit = save.pending_recruit,
    }
end

return M
