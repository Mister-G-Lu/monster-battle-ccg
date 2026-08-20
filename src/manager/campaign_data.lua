-- campaign_data.lua
-- Port of the web prototype's "The Shadow Road" campaign (build/web/game.html)
-- into the native Lua engine. Holds the 4-act / 19-node map, the scripted
-- boss & elite powers, token definitions, and deck/pool resolution helpers.
--
-- Node types: "skirmish" | "elite" | "boss".
-- Elite/boss nodes use `deck_ids` (real card model ids); skirmishes use a
-- `pool` resolved against data_template.card_config at battle start.

local bit = require "bit"
local constants = require "common.constants"
local data_template = require "manager.data_template"

local campaign_data = {}

-- faction flag bit (1 << CARD_KIND[<kind>])
local function kind_flag(kind)
    local tag = constants.CARD_KIND[kind]
    if not tag then return 0 end
    return bit.lshift(1, tag)
end

campaign_data.KIND_FLAG = kind_flag

-- =====================================================================
-- Tokens summoned by scripted powers (synthetic card configs)
-- =====================================================================

campaign_data.TOKENS = {
    whelp = {
        uid = "tok_whelp", name = "Beast Whelp", hp = 2, cost = 1,
        type = "monster", quality = "normal", kind = kind_flag("nature"),
        level = 1, score = 10, res_path = "",
        power_list = { { name = "melee", value = 1, target_type = "enemy", type = "passive" } },
    },
    sapling = {
        uid = "tok_sapling", name = "Sapling", hp = 1, cost = 1,
        type = "monster", quality = "normal", kind = kind_flag("nature"),
        level = 1, score = 8, res_path = "",
        power_list = { { name = "melee", value = 1, target_type = "enemy", type = "passive" } },
    },
    wraith = {
        uid = "tok_wraith", name = "Wraithguard", hp = 2, cost = 3,
        type = "monster", quality = "normal", kind = kind_flag("balance"),
        level = 1, score = 14, res_path = "",
        power_list = { { name = "melee", value = 2, target_type = "enemy", type = "passive" } },
    },
}

-- =====================================================================
-- Campaign map
-- =====================================================================

campaign_data.REGIONS = {
    {
        id = "act1", name = "Act I - Whispering Woods", sub = "The forest has grown teeth.",
        faction = "nature", icon = "\226\159\140\191",
        nodes = {
            { id = "w1", type = "skirmish", name = "Forest Trail", icon = "S", enemy_name = "Thicket Prowlers",
              pool = { kinds = { "nature" }, lv_min = 1, lv_max = 2, size = 9 }, hp = 14, exp = 10,
              desc = "Vines shift where no wind blows. Something is hunting travelers." },
            { id = "w2", type = "skirmish", name = "Wolf Den", icon = "S", enemy_name = "Gnarl Pack",
              pool = { kinds = { "nature" }, lv_min = 2, lv_max = 3, size = 9 }, hp = 16, exp = 12,
              desc = "Wolves with bark for hide circle the hollow oak." },
            { id = "w3", type = "skirmish", name = "Moonlit Grove", icon = "S", enemy_name = "Grove Wardens",
              pool = { kinds = { "nature" }, lv_min = 3, lv_max = 3, size = 9 }, hp = 18, exp = 14,
              desc = "The wardens no longer distinguish friend from intruder." },
            { id = "w4", type = "elite", name = "Boarlord's Camp", icon = "E", enemy_name = "Boarlord Gruff",
              deck_ids = { 140013, 140013, 140023, 140023, 140033, 140033, 140053, 140053, 140042, 140042, 140072, 140072 },
              hp = 30, exp = 22,
              desc = "A bristling war-camp in the ferns. The Boarlord never hunts alone.",
              power = { id = "muster", name = "Muster", desc = "On enemy turns 3 and 4, the Boarlord calls a Beast Whelp (1/2) into an empty lane." } },
            { id = "w5", type = "boss", name = "The Heartroot", icon = "B", enemy_name = "Verdant Tyrant", boss = true,
              deck_ids = { 140024, 140024, 140034, 140043, 140073, 140153, 140153, 140173, 140163, 140183 },
              hp = 26, exp = 40,
              desc = "The forest itself rises - a mountain of thorn and bloom that wants you gone.",
              power = { id = "overgrowth", name = "Overgrowth", desc = "While the Tyrant still holds cards it grows a Sapling (1/1) in an empty lane each enemy turn (two per turn from round 5). It heals 1 HP while any Sapling lives." } },
        },
    },
    {
        id = "act2", name = "Act II - Sunken Caverns", sub = "The bandits dug too deep.",
        faction = "chaos", icon = "\226\159\149\184",
        nodes = {
            { id = "c1", type = "skirmish", name = "Cave Mouth", icon = "S", enemy_name = "Scuttling Brood",
              pool = { kinds = { "chaos" }, lv_min = 2, lv_max = 3, size = 9 }, hp = 20, exp = 14,
              desc = "The dark between the stalagmites has eyes. Dozens of them." },
            { id = "c2", type = "skirmish", name = "Fungal Depths", icon = "S", enemy_name = "Spore Hosts",
              pool = { kinds = { "chaos" }, lv_min = 3, lv_max = 4, size = 9 }, hp = 22, exp = 16,
              desc = "Every breath tastes of rot. The mushrooms are wearing the miners." },
            { id = "c3", type = "skirmish", name = "Smugglers' Tunnel", icon = "S", enemy_name = "Gilded Fang Bandits",
              pool = { kinds = { "fortune" }, lv_min = 3, lv_max = 4, size = 9 }, hp = 24, exp = 18,
              desc = "The Fang found a shortcut through the caves - and a toll with your name on it." },
            { id = "c4", type = "elite", name = "Fangmaster Vault", icon = "E", enemy_name = "Fangmaster Vex",
              deck_ids = { 120023, 120023, 120033, 120033, 120043, 120043, 120103, 120103, 120053, 120053, 120061, 120061 },
              hp = 32, exp = 28,
              desc = "Vex counts your crystals with a knife-smile. Every coin you drop is his.",
              power = { id = "plunder", name = "Plunder", desc = "From enemy turn 2 onward, Vex steals 1 crystal from you at the start of each of his turns." } },
            { id = "c5", type = "boss", name = "The Drowned Throne", icon = "B", enemy_name = "Hollow King", boss = true,
              deck_ids = { 150013, 150013, 150063, 150063, 150053, 150053, 150103, 150103, 150033, 150173 },
              hp = 26, exp = 55,
              desc = "A crown floating on black water. What wears it is always, always hungry.",
              power = { id = "hunger", name = "Hungering Dark", desc = "From enemy turn 4, ALL of your creatures lose 1 HP each enemy turn, and for each one devoured the Hollow King heals 1 HP." } },
        },
    },
    {
        id = "act3", name = "Act III - Emberpeak", sub = "The mountain is a forge, and you are the ore.",
        faction = "war", icon = "\240\159\148\165",
        nodes = {
            { id = "e1", type = "skirmish", name = "Ash Foothills", icon = "S", enemy_name = "Ash Scouts",
              pool = { kinds = { "war" }, lv_min = 3, lv_max = 3, size = 9 }, hp = 26, exp = 18,
              desc = "Scouts in soot-grey armor. They have already lit the signal fires." },
            { id = "e2", type = "skirmish", name = "War Camp", icon = "S", enemy_name = "Ember Warband",
              pool = { kinds = { "war" }, lv_min = 3, lv_max = 4, size = 9 }, hp = 28, exp = 20,
              desc = "Drums, whetstones, and a hundred veterans who have never lost a pass." },
            { id = "e3", type = "skirmish", name = "Magma Bridges", icon = "S", enemy_name = "Flame Dancers",
              pool = { kinds = { "war" }, lv_min = 4, lv_max = 4, size = 9 }, hp = 30, exp = 22,
              desc = "They fight barefoot on liquid rock, and they never blink." },
            { id = "e4", type = "elite", name = "Alpha's Ridge", icon = "E", enemy_name = "Flamehide Alpha",
              deck_ids = { 110014, 110014, 110024, 110024, 110054, 110054, 110043, 110043, 110063, 110063, 110031, 110031 },
              hp = 34, exp = 34,
              desc = "The pack leader, scarred by a hundred forge-fires. Its roar sets blood boiling.",
              power = { id = "bloodlust", name = "Bloodlust", desc = "From round 4, the Alpha howls - every enemy creature permanently gains +1 ATK." } },
            { id = "e5", type = "boss", name = "The Caldera Gate", icon = "B", enemy_name = "Ember Colossus", boss = true,
              deck_ids = { 110054, 110054, 110103, 110103, 110063, 110063, 110031, 110031, 110171, 110171 },
              hp = 27, exp = 70,
              desc = "A siege engine that climbed out of the lava, wearing the mountain as armor.",
              power = { id = "flamewave", name = "Molten Core", desc = "Every 3rd enemy turn, a Flame Wave burns ALL your creatures for 2. Below half HP the Colossus ENRAGES: all its creatures permanently gain +1 ATK." } },
        },
    },
    {
        id = "act4", name = "Act IV - Shadowspire", sub = "The road ends where the light does.",
        faction = "balance", icon = "\240\159\140\145",
        nodes = {
            { id = "s1", type = "skirmish", name = "Broken Stair", icon = "S", enemy_name = "Vault Wardens",
              pool = { kinds = { "balance" }, lv_min = 4, lv_max = 4, size = 9 }, hp = 30, exp = 22,
              desc = "The stairs to the spire are guarded by things that were once statues." },
            { id = "s2", type = "skirmish", name = "Hall of Mirrors", icon = "S", enemy_name = "Shade Twins",
              pool = { kinds = { "balance", "chaos" }, lv_min = 4, lv_max = 4, size = 9 }, hp = 32, exp = 25,
              desc = "Every reflection moves a half-second before you do." },
            { id = "s3", type = "elite", name = "The Silent Gate", icon = "E", enemy_name = "Vault Sentinel",
              deck_ids = { 130012, 130012, 130022, 130022, 130032, 130032, 130042, 130042, 130052, 130052, 130061, 130061 },
              hp = 32, exp = 42,
              desc = "It has kept this gate since before the Shadow came. It will keep you, too.",
              power = { id = "warding", name = "Warding", desc = "The Sentinel's wards blunt heavy blows: its creatures take 1 less damage from attacks of 3 or more." } },
            { id = "s4", type = "boss", name = "The Shadow Throne", icon = "B", enemy_name = "Shadow Sovereign", boss = true, final = true,
              deck_ids = { 130191, 130191, 130061, 130043, 110103, 140155, 130092, 150023, 150172 },
              hp = 34, exp = 120,
              desc = "Every foe you cut down on this road casts a shadow here. They have been waiting to return the favor.",
              power = { id = "toll", name = "Umbral Toll", desc = "From enemy turn 3, the Sovereign drains 1 HP from you each turn and heals itself the same. Below half HP: ECLIPSE - it summons two Wraithguard (2/2)." } },
        },
    },
}

-- =====================================================================
-- Lookups
-- =====================================================================

local ALL_NODES, NODE_BY_ID, REGION_BY_ID

local function build_lookups()
    if ALL_NODES then return end
    ALL_NODES = {}
    NODE_BY_ID = {}
    REGION_BY_ID = {}
    local idx = 0
    for _, region in ipairs(campaign_data.REGIONS) do
        REGION_BY_ID[region.id] = region
        for _, node in ipairs(region.nodes) do
            node.region_id = region.id
            node.act_index = idx
            ALL_NODES[#ALL_NODES + 1] = node
            NODE_BY_ID[node.id] = node
        end
        idx = idx + 1
    end
end

function campaign_data:GetNodes()
    build_lookups()
    return ALL_NODES
end

function campaign_data:GetNode(id)
    build_lookups()
    return NODE_BY_ID[id]
end

function campaign_data:GetRegion(id)
    build_lookups()
    return REGION_BY_ID[id]
end

-- =====================================================================
-- Deck resolution
-- =====================================================================

local function shuffle_copy(t)
    local out = {}
    for i, v in ipairs(t) do out[i] = v end
    for i = #out, 2, -1 do
        local j = math.random(i)
        out[i], out[j] = out[j], out[i]
    end
    return out
end

function campaign_data:KindMatches(cfg, kinds)
    if not cfg or not kinds then return false end
    for _, k in ipairs(kinds) do
        for _, ck in ipairs(cfg.kind_list or {}) do
            if ck == k then return true end
        end
    end
    return false
end

-- derive a card's attack value from its power list (melee/ranged/magic)
function campaign_data:CardAttack(cfg)
    if not cfg then return 1 end
    for _, p in ipairs(cfg.power_list or {}) do
        if p.name == "melee" or p.name == "ranged" or p.name == "magic" then
            return tonumber(p.value) or 1
        end
    end
    return 1
end

-- all collectible monster model ids
function campaign_data:CollectibleMonsters()
    build_lookups()
    local list = {}
    for id, cfg in pairs(data_template.card_config) do
        if cfg.type == "monster" and tonumber(cfg.flags or 1) == 1 then
            list[#list + 1] = id
        end
    end
    return list
end

-- resolve a node's enemy deck into a list of monster model ids
function campaign_data:ResolveEnemyDeck(node)
    local monsters = {}
    if node.deck_ids then
        for _, id in ipairs(node.deck_ids) do
            monsters[#monsters + 1] = id
        end
        return monsters
    end

    local pool = node.pool or {}
    local all = self:CollectibleMonsters()

    local candidates = {}
    for _, id in ipairs(all) do
        local cfg = data_template.card_config[id]
        if self:KindMatches(cfg, pool.kinds)
            and tonumber(cfg.level) >= (pool.lv_min or 0)
            and tonumber(cfg.level) <= (pool.lv_max or 99) then
            candidates[#candidates + 1] = id
        end
    end
    if #candidates < 4 then
        candidates = {}
        for _, id in ipairs(all) do
            local cfg = data_template.card_config[id]
            if self:KindMatches(cfg, pool.kinds) and tonumber(cfg.level) <= (pool.lv_max or 99) then
                candidates[#candidates + 1] = id
            end
        end
    end
    if #candidates < 4 then
        candidates = {}
        for _, id in ipairs(all) do
            if self:KindMatches(data_template.card_config[id], pool.kinds) then
                candidates[#candidates + 1] = id
            end
        end
    end

    local n = pool.size or 9
    local picked = {}
    for _ = 1, 8 do
        picked = shuffle_copy(candidates)
        while #picked > n do table.remove(picked) end
        local total = 0
        for _, id in ipairs(picked) do
            local cfg = data_template.card_config[id]
            total = total + (tonumber(cfg and cfg.cost) or 0)
        end
        if #picked == 0 or (total / #picked) <= 3.4 then break end
    end
    for _, id in ipairs(picked) do
        monsters[#monsters + 1] = id
    end
    return monsters
end

-- tiered recruit reward for a first-clear (mirrors the web reward ladder)
function campaign_data:RecruitPool(node)
    local tier = node.type == "boss" and 2 or (node.type == "elite" and 1 or 0)
    local act_idx = node.act_index or 0
    local lv_min = math.min(8, 2 + act_idx + tier)
    local lv_max = math.min(8, 2 + act_idx + tier * 2)
    local atk_cap = tier == 0 and 2 or (tier == 1 and 3 or 9)

    local region = self:GetRegion(node.region_id)
    local faction = region and region.faction

    local collectible = self:CollectibleMonsters()
    local pool = {}
    for _, id in ipairs(collectible) do
        local cfg = data_template.card_config[id]
        local ok_faction = false
        for _, k in ipairs(cfg.kind_list or {}) do
            if k == faction or math.random() < 0.34 then ok_faction = true break end
        end
        if ok_faction
            and tonumber(cfg.level) >= lv_min and tonumber(cfg.level) <= lv_max
            and self:CardAttack(cfg) <= atk_cap then
            pool[#pool + 1] = id
        end
    end
    if tier == 2 then
        local strong = {}
        for _, id in ipairs(pool) do
            local cfg = data_template.card_config[id]
            if cfg.quality == "epic" or self:CardAttack(cfg) >= 3 then
                strong[#strong + 1] = id
            end
        end
        if #strong >= 3 then pool = strong end
    end
    if #pool < 3 then
        pool = {}
        for _, id in ipairs(collectible) do
            local cfg = data_template.card_config[id]
            if tonumber(cfg.level) >= lv_min - 1 and tonumber(cfg.level) <= lv_max + 1
                and self:CardAttack(cfg) <= atk_cap then
                pool[#pool + 1] = id
            end
        end
    end
    if #pool < 3 then
        pool = {}
        for _, id in ipairs(collectible) do
            if self:CardAttack(data_template.card_config[id]) <= atk_cap then
                pool[#pool + 1] = id
            end
        end
    end
    if #pool < 3 then pool = collectible end

    -- sort toward the sharp end (attack*2 + hp/2), return the top half
    table.sort(pool, function(a, b)
        local ca, cb = data_template.card_config[a], data_template.card_config[b]
        local sa = self:CardAttack(ca) * 2 + (tonumber(ca and ca.hp) or 0) / 2
        local sb = self:CardAttack(cb) * 2 + (tonumber(cb and cb.hp) or 0) / 2
        return sa > sb
    end)
    local keep = math.max(4, math.ceil(#pool / 2))
    while #pool > keep do table.remove(pool) end
    return pool
end

return campaign_data
