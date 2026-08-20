local network = require "manager.network"
local graphic = require "manager.graphic"

local constants = require "common.constants"
local data_template = require "manager.data_template"

local resource_logic = require "logic.resource"

local bit_extension = require "utils.bit_extension"

local CARD_CONFIG
local UPGRADE_CONFIG
local COMPOSE_CONFIG

local REWARD_TYPE = constants["REWARD_TYPE"]

local meta = {}
-- 初始化
function meta:Init()
    self.card_bag = {}
    self.deck_list = {}
    self.card_bag_num = 0

    self.cur_deck_id = 1

    CARD_CONFIG = data_template.card_config
    UPGRADE_CONFIG = data_template.card_upgrade_config
    COMPOSE_CONFIG = data_template.card_compose_config

    self.is_compose = false -- 默认不是造卡界面
    self:RegisterMsgHandler()
end

-- 设置卡本状态
-- 是否撰写
function meta:SetBookStage(is_compose)
    self.is_compose = is_compose
end

-- 获取卡组信息
function meta:GetDeckInfo(idx)
    return self.deck_list[idx]
end

-- 获取卡牌配置根据模板ID
function meta:GetCardConfigByModelId(model_id)
    if not model_id then
        return nil
    end
    return CARD_CONFIG[tostring(model_id)]
end

-- 获取卡牌配置根据卡牌信息
function meta:GetCardConfigByCardInfo(card_info)
    if not card_info then
        return nil
    end
    return self:GetCardConfigByModelId(card_info.model_id)
end

-- 获取卡牌配置根据卡牌唯一标示
function meta:GetCardConfigByCardId(id)
    local card_info = self:GetCardInfo(id)
    if not card_info then
        return nil
    end
    return self:GetCardConfigByCardInfo(card_info)
end

-- 获取卡牌组
function meta:GetCardInfo(uid)
    return self.card_bag[uid]
end

-- 根据卡牌组ID来获取卡牌组信息
function meta:GetAllCardGroupList(group_id)
    local group_list = {}
    for _, v in pairs(CARD_CONFIG) do
        if v.group_id == group_id  then
            -- local config = v
            -- group_list[tostring(v.uid)] = config
            table.insert(group_list, v)
        end
    end
    table.sort(group_list, function (a, b)
        return a.level < b.level
    end)
    return group_list
end

-- 获取卡牌数量
function meta:GetCardNumByModelId(model_id, is_get_all_num)
    local card_num = 0
    for _, v in pairs(self.card_bag) do
        if v.model_id == model_id then
            if (v.deck_flag == 0 or is_get_all_num) and v.is_lock == false then
                card_num = card_num + 1
            end
        end
    end
    return card_num
end

-- 初始化卡包
function meta:InitCardBag()
    self.card_bag = {}
    self.card_group_num = {}
    self.card_bag_num = 0
end

-- 添加卡牌
function meta:AddCard(card_info)
    if self.card_bag[card_info.id] then
        self.card_bag[card_info.id] = card_info
        return
    end
    self.card_bag[card_info.id] = card_info
    self.card_bag_num = self.card_bag_num + 1
    local card_config = self:GetCardConfigByCardInfo(card_info)
    local group_id = card_config.group_id
    local group_num = self.card_group_num[group_id] or 0
    group_num = group_num + 1
    self.card_group_num[group_id] = group_num
end

-- 删除卡牌
function meta:RemoveCard(card_uid)
    local card_info = self.card_bag[card_uid]
    self.card_bag[card_uid] = nil
    self.card_bag_num = self.card_bag_num - 1
    local card_config = self:GetCardConfigByCardInfo(card_info)
    local group_id = card_config.group_id
    local group_num = self.card_group_num[group_id] or 0
    group_num = group_num - 1
    self.card_group_num[group_id] = group_num
end

--这个是得到item_id
function meta:ComposePowder(uid)
    -- local item_id
    -- local item_num
    local config = {}
    for k,v in pairs(COMPOSE_CONFIG) do
        if uid == k then
            config = v
            -- for k,v in pairs(config) do
            --     item_id = v.item_id
            --     item_num = v.item_num
            -- end
        end
    end
    return config
end

-- 检查是否可升级
function meta:CheckCardLevel(uid)
    return UPGRADE_CONFIG[uid] ~= nil
end

-- 检查是否在卡组
function meta:CheckInDeck(card_id, deck_id)
    local card_info = self:GetCardInfo(card_id)
    if not card_info then
        return false
    end
    local deck_flag = card_info.deck_flag
    return bit_extension:GetBitNum(deck_flag, deck_id) == 1
end

-- 获取要过滤的列表
function meta:GetFilterList()
    -- local list = {}
    if self.is_compose == true then
        return self:GetComposeGroupList()
    else
        return self:GetCardGroupList()
    end
end

-- 初始化撰写配置表
function meta:GetComposeGroupList()
    local card_group_list = {}
    for k, _ in pairs(COMPOSE_CONFIG) do
        local card_config = self:GetCardConfigByModelId(k)
        local group_id = card_config["group_id"]
        local group_list = card_group_list[group_id]
        if not group_list then
            group_list = {}
            card_group_list[group_id] = group_list
        end
        group_list[card_config.level] = card_config.uid
    end
    return card_group_list
end

-- 获取卡牌组列表
function meta:GetCardGroupList()
    local card_group_list = {}
    for _, v in pairs(self.card_bag) do
        local config = self:GetCardConfigByCardInfo(v)
        local group_id = config["group_id"]
        local group_list = card_group_list[group_id]
        if not group_list then
            group_list = {}
            card_group_list[group_id] = group_list
        end
        group_list[config.level] = config.uid
    end

    return card_group_list
end

-- 获取卡组ID
function meta:GetGroupIdByUid(model_id)
    model_id = tostring(model_id)
    local config = CARD_CONFIG[model_id]
    return config["group_id"]
end

--获取数量
function meta:GetNumByGroupId(group_id)
    return self.card_group_num[group_id] or 0
end

-- 获取卡牌明细根据组ID(包含出战的)
function meta:GetCardListByGroupId(group_id)
    local card_detail_list = {}
    for _, v in pairs(self.card_bag) do
        local config = self:GetCardConfigByCardInfo(v)
        if config.group_id == group_id then
            table.insert(card_detail_list, {config = config, card_info = v})
        end
    end
    return card_detail_list
end

-- 获取撰写列表
function meta:GetComposeCardListByGroupId(group_id)
    local card_detail_list = {}
    -- local compose_list = {}
    for k,v in pairs(COMPOSE_CONFIG) do
        local card_config = self:GetCardConfigByModelId(k)
        if card_config.group_id == group_id then
            table.insert(card_detail_list,{config = card_config, compose_config = v})
        end
    end
    return card_detail_list
end

-- 获取卡牌组ID在卡组中的数量
function meta:GetGroupNumInDeck(deck_id, group_id)
   local card_group_in_deck = self.card_group_num_by_deck[deck_id] or {}
   return card_group_in_deck[group_id] or 0
end

function meta:UpdateGroupNumInDeck(deck_id, group_id, offset)
   local card_group_in_deck = self.card_group_num_by_deck[deck_id] or {}
   local cur_num = card_group_in_deck[group_id] or 0
   card_group_in_deck[group_id] = cur_num + offset
   self.card_group_num_by_deck[deck_id] = card_group_in_deck
end

-- 加入卡组
function meta:JoinDeck(deck_id, join_card_uid, target_pos)
    -- 1. 检查卡组是否存在
    local deck_info = self.deck_list[deck_id]
    if not deck_info then
        graphic:DispatchEvent("show_message", "deck_is_null")
        return
    end
    -- 2. 检查卡牌是否存在
    local card_info = self:GetCardInfo(join_card_uid)
    if not card_info then
        graphic:DispatchEvent("show_message", "card_is_null")
        return
    end

    local card_config = self:GetCardConfigByCardInfo(card_info)

    -- 3.检查是否已经在卡组中
    local is_on_deck = bit_extension:GetBitNum(card_info.deck_flag, deck_id) == 1
    if is_on_deck then
        graphic:DispatchEvent("show_message", "card_already_deck")
        return
    end
    -- 4.检查这卡牌在卡组中是否超过上限
    local cur_num = self:GetGroupNumInDeck(deck_id, card_config.group_id)
    if cur_num >= card_config.deck_limit then
        graphic:DispatchEvent("show_message", "deck_limit_desc", card_config.name, card_config.deck_limit)
        return
    end

    local post_data = {deck_id = deck_id, new_card_uid = join_card_uid, target_pos = target_pos}
    network:Send("req_deck_card_deploy", post_data, function (result, recv_msg)
        if result ~= "success" then
            graphic:DispatchEvent("show_message", result, card_config.name, card_config.deck_limit)
            return
        end

        -- local deck_info = recv_msg
        self.deck_list[recv_msg.id] = recv_msg

        graphic:DispatchEvent("hide_join_deck_panel")
        graphic:DispatchEvent("deck_replace_success")
        graphic:DispatchEvent("card_book_refresh")
        graphic:DispatchEvent("card_detail_refresh", join_card_uid)
    end)

end

-- 查询卡组信息
function meta:QueryDeckInfo(compleate_func, error_func)
    network:Send("req_deck_info_panel",{},function (result, recv_msg)
        if result == "success" then

            self.card_group_num_by_deck = {}
            self.deck_list = recv_msg.deck_info_list or {}
            for deck_id, deck_info in pairs(self.deck_list) do

                for j = 1, 8 do
                    local monster_card_id = deck_info["monster_pos_"..j]
                    local monster_config = self:GetCardConfigByModelId(monster_card_id)
                    if monster_config then
                        self:UpdateGroupNumInDeck(deck_id, monster_config.group_id, 1)
                    end

                    local item_card_id = deck_info["item_pos_"..j]
                    local item_config = self:GetCardConfigByModelId(item_card_id)
                    if item_config then
                        self:UpdateGroupNumInDeck(deck_id, item_config.group_id, 1)
                    end
                end
            end

            if compleate_func then compleate_func() end
        else
            if error_func then error_func(result) end
        end
    end)
end

-- 查询卡牌信息
function meta:QueryCardInfo(compleate_func, error_func)
    network:Send("req_card_info_panel",{},function (result, recv_msg)
        local card_info_list = recv_msg.card_info_list or {}

        self:InitCardBag()
        for _, v in pairs(card_info_list) do
            self:AddCard(v)
        end

        if result == "success" then
            if compleate_func then compleate_func() end
        else
            if error_func then error_func(result) end
        end
    end)
end

-- 升级卡牌
function meta:UpgradeCard(select_card, _, success_func)

    -- 1. 检查卡牌升级配置
    local card_model_id = select_card.model_id
    local config = UPGRADE_CONFIG[card_model_id]
    if not config then
        graphic:DispatchEvent("show_message", "card_is_max_level")
        return
    end
    -- 2. 检查资源是否满足
    local req_money = config.req_money
    if req_money > resource_logic.money then
        graphic:DispatchEvent("show_message", "resource_money_not_enough")
        return
    end
    local req_coin = config.req_coin
    if req_coin > resource_logic.coin then
        graphic:DispatchEvent("show_message", "resource_coin_not_enough")
        return
    end
    local req_material_list = config.req_material_list
    for _, material in pairs(req_material_list) do
        local kind = material.kind
        local attr_id = material.attr_id
        local num = material.num
        if kind == "card" then
            if self:GetCardNumByModelId(attr_id) < num then
                graphic:DispatchEvent("show_message", "card_num_not_enough")
                return
            end
        elseif kind == "item" then
            if resource_logic:GetItemNum(attr_id) < num then
                graphic:DispatchEvent("show_message", "item_num_not_enough")
                return
            end
        end
    end

    network:Send("req_card_upgrade", { card_id = select_card.id},
        function (result, recv_msg)
            if result ~= "success" then
                graphic:DispatchEvent("show_message", result)
                return
            end
            self:AddCard(recv_msg)
            graphic:DispatchEvent("card_book_refresh")
            graphic:DispatchEvent("card_detail_refresh", select_card.id)
            success_func(recv_msg)

            if recv_msg.deck_flag ~= 0 then
                graphic:DispatchEvent("deck_info_refresh")
            end
        end
    )
end

-- 分解卡牌
function meta:ResolveCard(card_id, success_func)
    network:Send("req_card_resolve", { card_id = card_id }, function (result, recv_msg)
        if result ~= "success" then
            graphic:DispatchEvent("show_message", result)
            return
        end
        local item_list = recv_msg.item_list or {}
        local reward_list = {}
        for _, v in pairs(item_list) do
            local old_num = resource_logic:GetItemNum(v.uid)
            table.insert(reward_list, { type = REWARD_TYPE["resource"], attr_id = v.uid, value = v.num - old_num })
        end
        resource_logic:AddItemList(item_list)
        -- 分解后的素材。通知奖励界面。显示奖励数据
        graphic:DispatchEvent("card_detail_refresh")
        graphic:DispatchEvent("card_book_refresh")
        -- 转换reward_info类型才可以使用通用奖励框
        success_func(reward_list)
    end)
end

-- 卡片合成
function meta:ComposeCard(card_model_id)
    local config = COMPOSE_CONFIG[card_model_id]
    if not config then
        return
    end

    local item_id = config[1]["item_id"]
    local item_num = config[1]["item_num"]

    local prop_num = resource_logic:GetItemNum(item_id)
    if item_id == 200001  then
        if prop_num < item_num then
            graphic:DispatchEvent("show_message", "item_powder_not_enough") --粉末不够
            return
        end
    elseif item_id == 100001 then
        if prop_num < item_num then
            graphic:DispatchEvent("show_message", "powder_not_enough")
            return
        end
    end

    network:Send("req_card_compose", { card_model_id = card_model_id }, function (result)
        if result == "success" then
            graphic:DispatchEvent("show_powder_numer")
            graphic:DispatchEvent("card_book_refresh")
            graphic:DispatchEvent("card_compose_success", card_model_id)
            graphic:DispatchEvent("show_message", "card_compose_success")--合成成功
        else
            graphic:DispatchEvent("show_message",result)--合成成功
        end
    end)
end
-- 注册网络事件
function meta:RegisterMsgHandler()

    network:RegisterCommand("cmd_card_update", function (recv_msg)
        self:AddCard(recv_msg)
    end)

    network:RegisterCommand("cmd_deck_update", function (recv_msg)
        self.deck_list[recv_msg.id] = recv_msg
    end)

    network:RegisterCommand("cmd_card_del", function (recv_msg)
        local del_card_id = recv_msg.card_id
        self:RemoveCard(del_card_id)
    end)
end

return meta
