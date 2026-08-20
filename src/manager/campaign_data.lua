-- Native campaign module: adapters only. Node/deck/power literals live in
-- campaign_data_generated.lua (from content/campaign_data.json).
local gen = require("manager.campaign_data_generated")

local M = {}
M.REGIONS = gen.REGIONS
M.TOKENS = gen.TOKENS
M.STARTER_COLLECTION = gen.STARTER_COLLECTION

local KIND_FLAG = { war = 1, fortune = 2, balance = 4, nature = 8, chaos = 16 }
local KIND_NAME = { [1] = "war", [2] = "fortune", [4] = "balance", [8] = "nature", [16] = "chaos" }

function M.kind_flag(kind)
    if type(kind) == "number" then return kind end
    return KIND_FLAG[kind] or 0
end

function M.kind_name(flag)
    return KIND_NAME[tonumber(flag) or 0] or tostring(flag)
end

function M.node_by_id(id)
    for _, region in ipairs(M.REGIONS) do
        for _, node in ipairs(region.nodes) do
            if node.id == id then return node, region end
        end
    end
end

function M.all_nodes()
    local out = {}
    for _, region in ipairs(M.REGIONS) do
        for _, node in ipairs(region.nodes) do
            out[#out + 1] = node
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Card index: either data_template.card_config or csv_data/all_card_config.csv
-- ---------------------------------------------------------------------------

local function split_csv_line(line)
    local fields, cur, in_q = {}, "", false
    for i = 1, #line do
        local ch = line:sub(i, i)
        if ch == '"' then
            in_q = not in_q
        elseif ch == "," and not in_q then
            fields[#fields + 1] = cur
            cur = ""
        else
            cur = cur .. ch
        end
    end
    fields[#fields + 1] = cur
    return fields
end

function M.load_cards_from_csv(path)
    local f = io.open(path, "r")
    if not f then return {} end
    local header
    local cards = {}
    local row = 0
    for line in f:lines() do
        row = row + 1
        if row == 1 then
            header = split_csv_line(line)
        elseif row > 2 and line ~= "" and not line:match("^ID,") then
            local cols = split_csv_line(line)
            local rec = {}
            for i, key in ipairs(header) do
                rec[key] = cols[i]
            end
            local id = tonumber(rec.ID)
            if id then
                rec.id = id
                rec.level = tonumber(rec.level) or 1
                rec.cost = tonumber(rec.cost) or 0
                rec.hp = tonumber(rec.hp) or 0
                rec.flags = tonumber(rec.flags) or 0
                rec.kind = rec.kind or ""
                rec.type = rec.type or "monster"
                cards[id] = rec
            end
        end
    end
    f:close()
    return cards
end

local function card_kind_name(card)
    local k = card.kind
    if type(k) == "number" then return M.kind_name(k) end
    return tostring(k or "")
end

function M.resolve_pool(pool, cards)
    if not pool then return {} end
    local kinds = {}
    for _, k in ipairs(pool.kinds or {}) do kinds[k] = true end
    local lv_min = pool.lv_min or pool.lvMin or 1
    local lv_max = pool.lv_max or pool.lvMax or 99
    local size = pool.size or 9

    local function collect(pred)
        local list = {}
        for _, c in pairs(cards) do
            if c.type == "monster" and (c.flags == 1 or c.flags == "1") and pred(c) then
                list[#list + 1] = c
            end
        end
        table.sort(list, function(a, b) return a.id < b.id end)
        return list
    end

    local candidates = collect(function(c)
        return kinds[card_kind_name(c)] and c.level >= lv_min and c.level <= lv_max
    end)
    if #candidates < 4 then
        candidates = collect(function(c)
            return kinds[card_kind_name(c)] and c.level <= lv_max
        end)
    end
    if #candidates < 4 then
        candidates = collect(function(c) return kinds[card_kind_name(c)] end)
    end

    local picked = {}
    if #candidates == 0 then return picked end
    for i = 1, size do
        picked[#picked + 1] = candidates[((i - 1) % #candidates) + 1].id
    end
    return picked
end

function M.split_collection(ids, cards)
    local monsters, items = {}, {}
    for _, id in ipairs(ids) do
        local c = cards[id] or cards[tonumber(id)]
        if c and c.type == "monster" then
            monsters[#monsters + 1] = id
        else
            items[#items + 1] = id
        end
    end
    return monsters, items
end

-- Enemy model ids for a node (explicit deck or resolved pool).
function M.enemy_model_ids(node, cards)
    if node.deck_ids then return node.deck_ids end
    if node.pool then return M.resolve_pool(node.pool, cards) end
    return {}
end

return M
