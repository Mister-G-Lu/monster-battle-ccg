-- Server-side battle domain model.
-- Kept separate from the battle orchestration so Actor and Slot can be
-- tested and reused without loading the command/AI engine.
local constants = require "common.constants"
local CARD_TYPE = constants.CARD_TYPE
local POWER_NAME = constants.POWER_NAME
local STATUS_TYPE = constants.STATUS_TYPE
local BATTLE_SLOT_MAX = constants.BATTLE_SLOT_MAX

-- Actor / slot model (server-side)
-- =====================================================================

local Actor = {}
Actor.__index = Actor

function Actor.New(user_id, user_name)
    local self = setmetatable({}, Actor)
    self.user_id = user_id
    self.user_name = user_name or "Enemy"
    self.arena_level = 1
    self.strength = 0
    self.monster_len = 0
    self.item_len = 0
    self.cur_crystal = 0
    self.hand_card = {}      -- [1..4]
    self.battle_slot = {}    -- [1..3]
    self.monster_card = {}   -- draw pile (monsters)
    self.item_card = {}      -- draw pile (items)
    self.is_sacrifice = false
    self.is_ai = false
    self.dead_num = 0
    return self
end

function Actor:GetHandCard(pos)
    return self.hand_card[pos]
end

function Actor:SetHandCard(pos, card)
    self.hand_card[pos] = card
    if card then
        card.hand_pos = pos
    end
end

function Actor:GetBattleCard(pos)
    return self.battle_slot[pos]
end

function Actor:GetMonsterTotal()
    local total = 0
    for i = 1, 4 do
        local c = self.hand_card[i]
        if c and c.type == CARD_TYPE.monster then
            total = total + 1
        end
    end
    total = total + #self.monster_card
    for i = 1, BATTLE_SLOT_MAX do
        if self.battle_slot[i] and self.battle_slot[i].monster then
            total = total + 1
        end
    end
    return total
end

function Actor:GetItemTotal()
    local total = 0
    for i = 1, 4 do
        local c = self.hand_card[i]
        if c and c.type ~= CARD_TYPE.monster then
            total = total + 1
        end
    end
    total = total + #self.item_card
    for i = 1, BATTLE_SLOT_MAX do
        if self.battle_slot[i] and self.battle_slot[i].item then
            total = total + 1
        end
    end
    return total
end

-- first empty monster slot (fills 1,2,3 in order)
function Actor:GetCurMonsterSlotPos()
    for i = 1, BATTLE_SLOT_MAX do
        if not self.battle_slot[i] then
            return i
        end
    end
    return 0
end

-- draw the next card of a given type from the deck
function Actor:DrawCard(card_type)
    local pile = card_type == CARD_TYPE.monster and self.monster_card or self.item_card
    if #pile == 0 then
        return nil
    end
    local card = pile[1]
    table.remove(pile, 1)
    self.monster_len = #self.monster_card
    self.item_len = #self.item_card
    return card
end

-- shift slots to the left when a slot is destroyed
function Actor:CompactSlots()
    for pass = 1, BATTLE_SLOT_MAX - 1 do
        for i = 1, BATTLE_SLOT_MAX - 1 do
            if not self.battle_slot[i] and self.battle_slot[i + 1] then
                self.battle_slot[i] = self.battle_slot[i + 1]
                self.battle_slot[i].pos = i
                self.battle_slot[i + 1] = nil
            end
        end
    end
end

-- =====================================================================
-- Slot model
-- =====================================================================

local Slot = {}
Slot.__index = Slot

function Slot.New(actor, pos)
    local self = setmetatable({}, Slot)
    self.actor = actor
    self.pos = pos
    self.monster = nil
    self.item = nil
    self.cur_hp = 0
    self.cur_ad = 0
    self.status_map = {}   -- name -> {round, value}
    self.power_map = {}    -- name -> value (merged monster + item powers)
    self.attack_type = nil
    self.used_opportunity = false
    self.used_charge = false
    self.used_regenerate = false
    return self
end

function Slot:IsDead()
    return self.cur_hp <= 0
end

function Slot:GetPower(name)
    return self.power_map[name]
end

function Slot:GetPowerValue(name)
    local p = self.power_map[name]
    return (p and p) or 0
end

function Slot:HasPower(name)
    return self.power_map[name] ~= nil
end

function Slot:IsStatus(name)
    return self.status_map[name] ~= nil
end

function Slot:GetStatusValue(name)
    local s = self.status_map[name]
    return (s and s.value) or 0
end

function Slot:SetStatus(name, round, value)
    self.status_map[name] = { round = round or 1, value = value or 1 }
end

function Slot:DelStatus(name)
    self.status_map[name] = nil
end

-- melee attack strength
function Slot:GetMeleeStrength()
    local s = self:GetPowerValue(POWER_NAME.melee)
    s = s + self:GetStatusValue(STATUS_TYPE.rallied)
    s = s - self:GetStatusValue(STATUS_TYPE.demoralized)
    s = s + self:GetStatusValue(STATUS_TYPE.charged)
    if s < 0 then s = 0 end
    return s
end

function Slot:GetRangedStrength()
    local s = self:GetPowerValue(POWER_NAME.ranged)
    s = s + self:GetStatusValue(STATUS_TYPE.rallied)
    s = s - self:GetStatusValue(STATUS_TYPE.demoralized)
    s = s + self:GetStatusValue(STATUS_TYPE.charged)
    if s < 0 then s = 0 end
    return s
end

function Slot:GetMagicStrength()
    local s = self:GetPowerValue(POWER_NAME.magic)
    s = s - self:GetStatusValue(STATUS_TYPE.antimagicd)
    if s < 0 then s = 0 end
    return s
end

function Slot:CanAttack()
    if self:IsStatus(STATUS_TYPE.entangled) then
        return false, "entangled"
    end
    if self:IsStatus(STATUS_TYPE.diseased) then
        -- diseased loses rally/demoralize/reflect (already handled in strength calc via status)
    end
    return true
end

function Slot:IsDiseased()
    return self:IsStatus(STATUS_TYPE.diseased)
end

function Slot:IsSilenced()
    return self:IsStatus(STATUS_TYPE.silenced)
end

function Slot:IsCautious()
    return self:IsStatus(STATUS_TYPE.cautious)
end

-- merge monster + item powers into power_map
function Slot:RebuildPowers()
    self.power_map = {}
    if self.monster and self.monster.power_list then
        for _, p in ipairs(self.monster.power_list) do
            local name = p.name
            local v = tonumber(p.value) or 0
            self.power_map[name] = (self.power_map[name] or 0) + v
        end
    end
    if self.item and self.item.power_list then
        for _, p in ipairs(self.item.power_list) do
            local name = p.name
            local v = tonumber(p.value) or 0
            self.power_map[name] = (self.power_map[name] or 0) + v
        end
    end
    self.attack_type = self:HasPower(POWER_NAME.magic) and "magic"
        or (self:HasPower(POWER_NAME.melee) and "melee" or "ranged")
end

function Slot:SetMonster(card)
    self.monster = card
    self.cur_hp = card.hp
    self.item = nil
    self.cur_ad = 0
    self.status_map = {}
    self.used_opportunity = false
    self.used_charge = false
    self.used_regenerate = false
    self:RebuildPowers()
end

function Slot:SetItem(card)
    self.item = card
    self.cur_ad = card.hp
    self:RebuildPowers()
    -- boost: extra armor when equipped
    local boost = self:GetPowerValue(POWER_NAME.boost)
    if boost > 0 then
        self.cur_ad = self.cur_ad + boost
    end
end

function Slot:CleanItem()
    self.item = nil
    self.cur_ad = 0
    self:RebuildPowers()
end

-- =====================================================================

return { Actor = Actor, Slot = Slot }
