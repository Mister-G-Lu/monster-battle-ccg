local constants = require "common.constants"


local ATTACK_TYPE = constants.BATTLE_ATTACK_TYPE
local STATUS_TYPE = constants.STATUS_TYPE
local POWER_NAME = constants.POWER_NAME

local meta = {}
meta.__index = meta

-- 初始化
function meta.New()
    local data_origin = {}
    data_origin.monster = nil
    data_origin.item = nil
    data_origin.user_id = ""
    data_origin.pos = 0
    data_origin.cur_hp = 0
    data_origin.init_hp = 0
    data_origin.cur_ad = 0
    data_origin.init_ad = 0
    data_origin.power_name_list = {}
    data_origin.power_map = {}
    data_origin.status_map = {}
    data_origin.attacked_with_opportunity = false
    data_origin.attacked_with_antiair = false
    setmetatable(data_origin, meta)
    return data_origin
end

function meta:Init(user_id, pos)
    self.monster = nil
    self.item = nil
    self.user_id = user_id
    self.pos = pos
    self.cur_hp = 0
    self.init_hp = 0
    self.cur_ad = 0
    self.init_ad = 0
    self.power_name_list = {}
    self.power_map = {}
    self.status_map = {}
    self:Clean()
end

-- 清空数据
function meta:Clean()
    self.monster = nil
    self.item = nil
    self.cur_hp = 0
    self.init_hp = 0
    self.cur_ad = 0
    self.init_ad = 0
    self.power_name_list = {}
    self.power_map = {}
    self.status_map = {}

    -- 冲锋仅仅作用一次
    self.attacked_with_charge = false

    self.attacked_with_opportunity = false
    self.attacked_with_antiair = false
end

-- 状态是否存在
function meta:IsStatus(name)
    return self.status_map[name] ~= nil
end

function meta:DelStatus(name)
    local status = self.status_map[name]
    self.status_map[name] = nil
    if status then
        return status.value
    end
    return 0
end

-- 添加状态
function meta:PushStatus(name, round, value)
    if round == 0 then
        round = 1
    end
    local status = self.status_map[name]
    if not status then
        status = {}
        status.round = round
        status.value = value
    else
        status.round = round
        status.value = math.max(status.value, value)
    end
    self.status_map[name] = status
    return status.value
end

-- 获取状态
function meta:GetStatus(name)
    return self.status_map[name]
end

-- 获取状态值
function meta:GetStatusValue(name)
    local status = self.status_map[name]
    if status then
        return status.value
    end
    return 0
end

-- 获取状态值
function meta:SetStatusValue(name, value)
    local status = self.status_map[name]
    if status then
        status.value = value
    end
end

-- 获取技能
function meta:GetPower(name)
    return self.power_map[name]
end

-- 删除技能
function meta:DelPower(name)
    self.power_map[name] = nil
end

-- 获取数值
function meta:GetPowerValue(name)
    local p = self.power_map[name]
    if p then
        return p.value
    end
    return 0
end

-- 是否闪避
function meta:IsDodge(attack_slot, attack_type)
    local flying_power = self:GetPower(POWER_NAME.flying)
    if not flying_power then
        return false
    end

    local seed = math.random(100)

    if attack_type ~= ATTACK_TYPE.melee and attack_type ~= ATTACK_TYPE.ranged then
        return false
    end

    -- local attack_flying = attack_slot:GetPower(POWER_NAME.flying)
    -- if attack_type == ATTACK_TYPE.melee and attack_flying then
    --     -- 飞翔的近战攻击是无法被闪避的
    --     return false
    -- end

    local attack_antiair = attack_slot:GetPower(POWER_NAME.antiair)
    if attack_type == ATTACK_TYPE.ranged and attack_antiair then
        -- 防空的远程攻击是无法被闪避的
        return false
    end

    if not self:IsStatus(STATUS_TYPE.entangled) then
        -- 飞翔时的闪避加成
        if (attack_type == ATTACK_TYPE.melee and seed < 50) or (attack_type == ATTACK_TYPE.ranged and seed < 25) then
            return true
        end
    end
    return false
end

-- 是否可以潜行
function meta:IsStealth()
    if self.pos == 1 then
        return false
    end
    local stealth_power = self:GetPower(POWER_NAME.stealth)
    return stealth_power and not self:IsStatus(STATUS_TYPE.painted)
end

-- 重置技能状态
function meta:ResetPowers()
    self.attacked_with_opportunity = false
    self.attacked_with_antiair = false
end

-- 获取近战攻击力
function meta:GetMeleeStrength()
    local strength = 0
    strength = strength + self:GetPowerValue(POWER_NAME.melee)

    -- 鼓舞士气
    strength = strength + self:GetStatusValue(STATUS_TYPE.rallied)

    -- 恫吓
    strength = strength - self:GetStatusValue(STATUS_TYPE.demoralized)

    -- 冲锋
    strength = strength + self:GetStatusValue(STATUS_TYPE.charged)

    if strength < 0 then
        strength = 0
    end
    return strength
end

-- 获取魔法攻击力
function meta:GetMagicStrength()

    local value = self:GetPowerValue(POWER_NAME.magic)

    value = value - self:GetStatusValue(STATUS_TYPE.antimagicd)

    if value < 0 then
        value = 0
    end

    return value
end


-- 添加技能映射
-- @power 技能
-- @is_active 是否是主动
function meta:PushPowerMap(power, is_active)
    local name = power.name
    local old_power = self.power_map[name]
    if old_power then
        -- 相同的power数值叠加
        old_power.value = old_power.value + power.value
    else
        -- 必须克隆，不能直接引用，否则会破坏源数据
        local temp = table.clone(power)
        -- 加入power缓存列表
        self.power_map[name] = temp
        -- 如果是主动power就加入列表
        if is_active then
            table.insert(self.power_name_list, name)
        end
    end
end

-- 删除技能映射
-- @power 技能
-- @is_active 是否是主动
function meta:RemovePowerMap(power, is_active)
    local name = power.name
    local old_power = self.power_map[name]
    if old_power then
        local v = old_power.value - power.value
        old_power.value = v
        if v <= 0 then
            self.power_map[name] = nil
            if is_active then
                table.remove_arrays(self.power_name_list, name)
            end
        end
    end
end

-- 设置怪兽卡
function meta:SetMonster(monster)
    self:Clean()
    self.monster = monster
    if not monster then
        return
    end

    -- 初始化战斗位置信息
    self.cur_hp = monster.hp
    self.init_hp = monster.hp
    local power_list = monster.power_list or {}
    for _, p in pairs(power_list) do
        self:PushPowerMap(p, p.type == constants.POWER_TYPE.active)
    end
end

-- 清除道具信息
function meta:CleanItem()
    if not self.item then
        return
    end
    self.cur_ad = 0
    self.init_ad = 0
    self.item = nil

    -- local power_list = self.item.power_list or {}
    -- for _, p in pairs(power_list) do
    --     self:RemovePowerMap(p, p.type == constants.POWER_TYPE.active)
    -- end

    -- 重新生成技能映射
    self.power_name_list = {}
    self.power_map = {}
    local power_list = self.monster.power_list or {}
    for _, p in pairs(power_list) do
        self:PushPowerMap(p, p.type == constants.POWER_TYPE.active)
    end

end

-- 设置道具卡
function meta:SetItem(item)
    self:CleanItem()
    self.item = item
    if not item then
        return
    end

    self.cur_ad = item.hp
    self.init_ad = item.hp

    local power_list = item.power_list or {}
    for _, p in pairs(power_list) do
        self:PushPowerMap(p, p.type == constants.POWER_TYPE.active)
    end
end

return meta
