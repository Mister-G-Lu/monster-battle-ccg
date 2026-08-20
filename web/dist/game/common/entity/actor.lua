local constants = require "common.constants"
local bit = require "utils.bit_extension"

local meta = {}
meta.__index = meta

-- 常量引用
local BATTLE_SLOT_MAX = constants.BATTLE_SLOT_MAX
local CARD_TYPE = constants.CARD_TYPE
local CARD_KIND = constants.CARD_KIND
local POWER_AREA = constants.POWER_AREA

-- 初始化
function meta.New()
    local data_origin = {}
    data_origin.user_source = 0
    data_origin.user_id = ""
    data_origin.user_name = ""
    data_origin.strength = 0
    data_origin.monster_len = 0
    data_origin.item_len = 0
    data_origin.hand_card = {}
    -- 出战卡牌@idx->{monster,item}
    data_origin.battle_slot = {}
    -- 当前水晶数量
    data_origin.cur_crystal = 0
    data_origin.consume_time = 0
    data_origin.begin_oper_time = 0
    -- 是否可以献祭
    data_origin.is_sacrifice = false
    data_origin.deploy_list = {}
    -- 已部署怪兽卡
    data_origin.deploy_monster_list = {}
    -- 已部署的装备卡
    data_origin.deploy_equip_list = {}
    -- 操作次数
    data_origin.oper_count = 1

    data_origin.round_dead_num = 0

    data_origin.init_monster_len = 0
    data_origin.init_item_len = 0
    -- 惩罚计数器
    data_origin.penalty_count = 0
    -- 日志统计
    data_origin.log_total_hurt = 0
    data_origin.log_round_hurt = 0
    data_origin.log_total_heal = 0
    data_origin.log_round_heal = 0

    data_origin.log_round_card = 0
    data_origin.log_round_immolation = 0

    data_origin.is_ai_mode = false

    setmetatable(data_origin, meta)
    return data_origin
end

-- 初始化手牌
function meta:Init()

    self.monster_len = 0
    self.item_len = 0
    self.deploy_list = {}
    self.deploy_monster_list = {}
    self.deploy_equip_list = {}
    self.card_stat_list = {}

    -- BUFF执行记录器(我方执行一次，敌方执行一次，算作一个结算回合)
    self.buff_record_count = 0

    -- 惩罚计数器
    self.penalty_count = 0

    -- 日志统计
    self.log_total_hurt = 0
    self.log_round_hurt = 0
    self.log_total_heal = 0
    self.log_round_heal = 0
    self.log_round_card = 0
    self.log_round_immolation = 0
    self.log_dead_list = {}
    self.log_use_list = {}
    if self.is_ai_mode then
        self.role_name = "ai"
    else
        self.role_name = "player"
    end
end

function meta:InitHandCard()
    local card1 = self.monster_card[1]
    local card2 = self.monster_card[2]
    local card3 = self.item_card[1]
    local card4 = self.item_card[2]

    table.remove(self.monster_card, 1)
    table.remove(self.monster_card, 1)
    table.remove(self.item_card, 1)
    table.remove(self.item_card, 1)

    self:SetHandCard(1, card1)
    self:SetHandCard(2, card2)
    self:SetHandCard(3, card3)
    self:SetHandCard(4, card4)

    self.monster_len = #self.monster_card
    self.item_len = #self.item_card
end

function meta:SetDeployNumberLimit(limit_info)
    self.limit_info = limit_info
end


-- 每回合重置的信息
function meta:DoResetRound()
    self.log_round_hurt = 0
    self.log_round_heal = 0
    self.log_round_card = 0
    self.log_round_immolation = 0
end

-- 记录伤血量
function meta:LogHurt(value)
    self.log_total_hurt = self.log_total_hurt + value
    self.log_round_hurt = self.log_round_hurt + value
end

-- 记录治疗量
function meta:LogHeal(value)
    self.log_round_heal = self.log_round_heal + value
    self.log_total_heal = self.log_total_heal + value
end

function meta:LogDead(card)
    table.insert(self.log_dead_list, card.uid)
end

function meta:LogUseCard(card)
    table.insert(self.log_use_list, card.uid)
end

-- 添加卡组
function meta:PushDeck(deck_info)
    -- self.user_name = deck_info.name
    -- self.strength = deck_info.strength

    local item_list = deck_info.item_list
    local monster_list = deck_info.monster_list
    -- 洗牌
    local item_size = #item_list
    self.init_item_len = item_size
    self.item_card = {}
    for i=1, item_size do
        local card = item_list[i]
        card.user_id = self.user_id
        table.insert(self.item_card, card)
    end

    local monster_size = #monster_list
    self.init_monster_len = monster_size
    self.monster_card = {}
    for i = 1, monster_size do
        local card = monster_list[i]
        card.user_id = self.user_id
        table.insert(self.monster_card, card)
    end
end

-- 卡组洗牌
function meta:ShuffleDeck()

    local item_list = self.item_card
    local monster_list = self.monster_card
    -- 洗牌
    local item_size = #item_list
    self.item_card = {}
    for i=1, item_size do
        local idx = math.random(1, #item_list)
        local card = item_list[idx]
        table.insert(self.item_card, card)
        table.remove(item_list, idx)
    end

    local monster_size = #monster_list
    self.monster_card = {}
    for i = 1, monster_size do
        local idx = math.random(1, #monster_list)
        local card = monster_list[idx]
        table.insert(self.monster_card, card)
        table.remove(monster_list, idx)
    end
end

-- 获取当前可以放怪兽位置
function meta:GetCurMonsterSlotPos()
    for i = 1, BATTLE_SLOT_MAX do
        local slot = self.battle_slot[i]
        if not slot then
            return i
        end
    end
    return 0
end

-- 是否可以对敌人使用卡牌
function meta:IsDoEnemy(src_pos)
    local card = self:GetHandCard(src_pos)
    if not card or bit:GetBitNum(card.kind, CARD_KIND.all) == 0 then

        return false
    end
    local power_list = card.power_list or {}
    for k,v in pairs(power_list) do
        if v.target_enemy == true then
            return true
        end
    end
    return false
end

-- 获取战斗卡牌
function meta:GetBattleCard(pos)
    local slot = self.battle_slot[pos]
    if slot and slot.pos ~= pos then
        print(">>>>>>>>>>>>>>>>>位置错乱，开始强制纠正 src_pos = "..slot.pos..",pos = "..pos)
    end
    return slot
end

-- 获取战场角色数量
function meta:GetBattleCardLenght()
    local len = 0
    for k,v in pairs(self.battle_slot) do
        if v then
            len = len + 1
        end
    end
    return len
end

-- 获取所有活着卡牌
function meta:GetAllSlot(selecter)
    local list = {}
    for i = BATTLE_SLOT_MAX, 1, -1 do
        local src_slot = self.battle_slot[i]
        if src_slot then
            if selecter == nil or selecter(src_slot) then
                table.insert(list, src_slot)
            end
        end
    end
    return list
end

-- 获取卡牌数量
function meta:GetCardCountByAllSlot()
    local count = 0
    for i = BATTLE_SLOT_MAX, 1, -1 do
        local src_slot = self.battle_slot[i]
        if src_slot then
            if src_slot.monster then
                count = count + 1
            end
            if src_slot.item then
                count = count + 1
            end
        end
    end
    return count
end

-- 获取手牌
function meta:GetHandCard(pos)
    local card = self.hand_card[pos]
    return card
end

-- 获取手牌
function meta:GetHandCardById(card_id)
    for _, card in pairs(self.hand_card) do
        if card.uid == card_id then
            return card
        end
    end
    return nil
end

-- 获取在手牌中获取怪兽卡
function meta:GetMonsterInHand()
    local cards = {}
    if self.hand_card[1] then
        table.insert(cards, self.hand_card[1])
    end
    if self.hand_card[2] then
        table.insert(cards, self.hand_card[2])
    end
    return cards
end

-- 获取在手牌中获取怪兽卡
function meta:GetItemInHand()
    local cards = {}
    if self.hand_card[3] then
        table.insert(cards, self.hand_card[3])
    end
    if self.hand_card[4] then
        table.insert(cards, self.hand_card[4])
    end
    return cards
end

-- 获取手牌数量
function meta:GetHandCardLenght()
    local len = 0
    for i = 1, 4 do
        if self.hand_card[i] then
            len = len + 1
        end
    end
    return len
end

-- 获取手牌中的怪兽数量
function meta:GetLenghtInCardByMonster()
    local len = 0
    if self.hand_card[1] ~= nil then
        len = len + 1
    end
    if self.hand_card[2] ~= nil then
        len = len + 1
    end
    return len
end

-- 获取手牌中的道具数量
function meta:GetLenghtInCardByItem()
    local len = 0
    if self.hand_card[3] ~= nil then
        len = len + 1
    end
    if self.hand_card[4] ~= nil then
        len = len + 1
    end
    return len
end

-- 设置手牌
function meta:SetHandCard(pos, card)
    self.hand_card[pos] = card
    if card then
        card.hand_pos = pos
    end
end

-- 获取总怪兽数量
function meta:GetAllMonsterLenght()
    local len = self:GetLenghtInCardByMonster()
    len = len + self.monster_len
    for k,v in pairs(self.battle_slot) do
        if v then
            len = len + 1
        end
    end
    return len
end

-- 获取总道具数量
function meta:GetAllItemLenght()
    local len = self:GetLenghtInCardByItem()
    len = len + self.item_len
    for k,v in pairs(self.battle_slot) do
        if v and v.item then
            len = len + 1
        end
    end
    return len
end

-- 获取当前总水晶数量
function meta:GetAllCrystalNum()
    local crystal_num = self.cur_crystal

        -- 获取手牌怪兽
    if self.hand_card[1] then
        crystal_num = crystal_num + self.hand_card[1].cost

    end
    if self.hand_card[2] then
        crystal_num = crystal_num + self.hand_card[2].cost
    end

    -- 获取牌堆的怪兽
    for k,v in pairs(self.monster_card) do
        crystal_num = crystal_num + v.cost
    end
    return crystal_num
end

-- 获取总怪兽数量 + 手牌+ 牌堆
function meta:GetTotalMonsterLenght()
    local len = self:GetLenghtInCardByMonster()
    return len + self.monster_len
end

-- 获取道具总数量
function meta:GetTotalItemLenght()
    local len = self:GetLenghtInCardByItem()
    return len + self.item_len
end

-- 获取总卡牌数量
function meta:GetTotalCardLenght()
    return self:GetTotalMonsterLenght() + self:GetTotalItemLenght()
end

-- 获取所有怪兽
function meta:GetAllMonsterList()
    local list = {}
    -- 获取战场怪兽
    for i = 1, 3 do
        local slot = self:GetBattleCard(i)
        if slot and slot.monster and not slot.item then
            table.insert(list, slot.monster)
        end
    end

    -- 获取手牌怪兽
    if self.hand_card[1] then
        table.insert(list, self.hand_card[1])
    end
    if self.hand_card[2] then
        table.insert(list, self.hand_card[2])
    end

    -- 获取牌堆的怪兽
    for k,v in pairs(self.monster_card) do
        table.insert(list, v)
    end
    return list
end

-- 交换卡牌位置
function meta:SwapSlotPos(pos1, pos2)
    local temp = self.battle_slot[pos1]
    self.battle_slot[pos1] = self.battle_slot[pos2]
    self.battle_slot[pos2] = temp

    if self.battle_slot[pos1] then
        self.battle_slot[pos1].pos = pos1
    end

    if self.battle_slot[pos2] then
        self.battle_slot[pos2].pos = pos2
    end

end

-- 部署怪兽卡
-- @card 怪兽卡
-- @target_pos 位置
function meta:DeployMonsterCard(card, target_pos)
    local slot = self.battle_slot[BATTLE_SLOT_MAX]
    if slot and slot.monster  then
        -- * 是否有空位可以继续上场
        -- 只检查最后一个即可
        print("没有空位了")
        return false
    end

    -- 规则：如果怪兽卡牌上阵，只能遵守，1，2，3的上阵
    local allow_pos = self:GetCurMonsterSlotPos()
    if allow_pos == 0 or target_pos > allow_pos then
        print("不满足部署规则")
        return false
    end


    -- * 部署怪兽卡
    local slot = self.battle_slot[target_pos]
    if slot and slot.monster then
        -- * 当前有怪兽要产生位置移动
        for i = BATTLE_SLOT_MAX - 1 , target_pos, -1 do
            if self.battle_slot[i] then
                self.battle_slot[i].pos = i + 1
                self.battle_slot[i + 1] = self.battle_slot[i]
            end
        end
    end
    -- * 立即部署怪兽卡
    slot = require("common.entity.slot").New()
    slot:Init(self.user_id, target_pos)
    slot:SetMonster(card)
    self.battle_slot[target_pos] = slot
    -- print(tostring(card))
    table.insert(self.deploy_list, card.uid)
    table.insert(self.deploy_monster_list, card.uid)
    table.insert(self.card_stat_list, card)


    for k,v in pairs(self.battle_slot) do
        if v  and v.pos ~= k then
            print("部署target_pos>>"..target_pos)
            print("部署完毕战场状态异常 "..self.user_id.."  v.pos = "..v.pos..", k = "..k)
        end
    end
    return true
end

-- 取消部署怪兽卡
function meta:UnDeployMonsterCard(target_pos)
    -- 取消部署位置
    self.battle_slot[target_pos] = nil
    -- 取消换位效果
    self:CheckSlotDead()
    -- 取消部署记录
    table.remove(self.deploy_list, #self.deploy_list)
    table.remove(self.deploy_monster_list, #self.deploy_monster_list)
end

-- 部署道具卡
-- @card
-- @target_pos
function meta:DeployItemCard(card, target_pos )
    local slot = self.battle_slot[target_pos]
    -- * 检查是否有怪兽
    if not slot or not slot.monster then
        print("battle_deploy_slot_is_null")
        return false
    end
    -- * 检查怪兽颜色是否相等
    if bit:GetBitNum(card.kind, CARD_KIND.all) == 0 then
        if not bit:CheckBitValue(slot.monster.kind, card.kind) then
            -- print("颜色不同")
            return false
        end
    end
    slot:SetItem(card)
    table.insert(self.deploy_list, card.uid)
    table.insert(self.deploy_equip_list, card.uid)
    return true
end

-- 取消部署装备卡
function meta:UnDeployItemCard(target_pos, src_card)
    local slot = self.battle_slot[target_pos]
    if slot then
        slot:CleanItem()
        table.remove(self.deploy_list, #self.deploy_list)
        table.remove(self.deploy_equip_list, #self.deploy_equip_list)
    end
end

-- 获取技能列表
function meta:GetSlotPowerMap(pos, power_name)
    local power_map = {}
    local slot = self.battle_slot[pos]
    if not slot then
        return
    end
    return slot.power_map[power_name]
end

-- 获取主动技能列表
-- @pos 战斗位置
function meta:GetActivePowerList(pos)
    local list = {}
    local slot = self.battle_slot[pos]
    if not slot then
        return list
    end
    local name_list = slot.power_name_list
    for _, name in ipairs(name_list) do
        local power = self:GetSlotPowerMap(pos, name)
        if power then
            table.insert(list, power)
        else
            print("技能异常 GetActivePowerList = "..name)
        end
    end

    return list
end

-- 使用卡牌技能
-- @card 卡牌
-- @target_list 使用对象列表
function meta:DoConsumeCardPower(card, target_list)

end

-- 检查卡牌死亡，自动补位
function meta:CheckSlotDead(callback)
    for j = 1, 3 do
        -- 1. 判断2位置，如果是空的。由3位置<如果是空的就放弃>进行补位
        for i = 1, BATTLE_SLOT_MAX - 1 do
            local slot = self.battle_slot[i]
            if slot == nil  then
                if self.battle_slot[i + 1] then
                    self.battle_slot[i] = self.battle_slot[i + 1]
                    if self.battle_slot[i] then
                        self.battle_slot[i].pos = i
                    end
                    self.battle_slot[i + 1] = nil
                    if callback then
                        callback(i + 1 , i)
                    end
                end
            end
        end
    end
end

-- 丢弃其中一张手牌
function meta:DiscardHandCard()
    local list = {}
    -- 1和2手牌是怪兽卡
    if self.hand_card[1] then
        table.insert(list, 1)
    end
    if self.hand_card[2] then
        table.insert(list, 2)
    end
    return math.randlist(list) or 0
end

-- 丢弃卡牌堆中一张
function meta:DiscardDeckCard()
    local monster_size = #self.monster_card
    local item_size = #self.item_card
    local max_size = monster_size + item_size
    if max_size == 0 then
        return 0
    end
    local card_idx = math.random(max_size)
    if card_idx <= monster_size then
        return card_idx, CARD_TYPE.monster
    else
        return card_idx - monster_size, CARD_TYPE.equip
    end
end

-- 获取牌堆的中的卡牌
function meta:GetDeckCard(card_type, idx, is_del)
    local card = nil
    if card_type == CARD_TYPE.monster then
        card = self.monster_card[idx]
        if is_del then
            table.remove(self.monster_card, idx)
        end
    else
        card = self.item_card[idx]
        if is_del then
            table.remove(self.item_card, idx)
        end
    end
    return card
end

-- 生成下一个卡牌
function meta:NextCard(last_type)
    if last_type == CARD_TYPE.monster then
        if #self.monster_card == 0 then
            return
        end
        local card = self.monster_card[1]
        table.remove(self.monster_card, 1)
        self.monster_len = #self.monster_card
        return card
    else
        if #self.item_card == 0 then
            return
        end
        local card = self.item_card[1]
        table.remove(self.item_card, 1)
        self.item_len = #self.item_card
        return card
    end
end

-- 获取支持卡位
function meta:GetSupportSlot()
    local support_slots = {}
    if self.battle_slot[2] ~= nil then
        table.insert(support_slots, self.battle_slot[2])
    end
    if self.battle_slot[3] ~= nil then
        table.insert(support_slots, self.battle_slot[3])
    end
    return support_slots
end

--获取随机目标
function meta:GetRandomSlot(selecter)
    local list = {}
    for _,v in pairs(self.battle_slot) do
        if v and (not selecter or selecter(v)) then
            table.insert(list, v)
        end
    end
    if #list == 0 then
        return nil
    end
    local idx = math.random(#list)
    return list[idx]
end

-- 直线目标
function meta:GetAlignedSlot(pos)
    return self.battle_slot[pos]
end

-- 交叉位置
function meta:GetAcrossSlot(pos)
    if pos == 2 then
        return self.battle_slot[3]
    elseif pos == 3 then
        return self.battle_slot[2]
    end
    return nil
end

function meta:PushCardToLibrary(card, pos)
    if not pos then
        pos = 1
    end

    -- print("PushCardToLibrary", tostring(self), tostring(self.monster_card))
    table.insert(self.monster_card, pos, card)
    self.monster_len = #self.monster_card
end

return meta
