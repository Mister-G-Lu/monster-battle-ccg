local global = require "manager.global"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local resource = require "manager.resource"
local text_loader = require "manager.text_loader"

local bit = require "utils.bit_extension"
local constants = require "common.constants"

local data_template = require "manager.data_template"
local defines = require "manager.defines"

local CARD_CONFIG = data_template.card_config

local deck_logic = require "logic.deck"

local meta = class("deck_group_panel",function (bing_node)
    ui_helper:SetCocosSetting(bing_node, "interface/deck/battlecard_group.csb")
    return bing_node
end)

local TAB_TYPE = defines.DECK_TAB_TYPE

function meta:ctor(node, rect)
    self.hand_card_list = {}
    self.small_card_list = {}

    -- 绑定动画
    ui_helper:BindTimeLine(self, "interface/deck/battlecard_group.csb")

    self.deck_select_panel = ui_helper:ExpandUI(self, "group_list", "modules.deck.deck_select_panel")

    -- 渲染队列
    self.render_queue = {}

    self.deck_max_num = #deck_logic.deck_list

    -- 卡组明细
    local group_detail = self:getChildByName("group_detail")
    self.group_detail_node = group_detail

    -- 小卡牌模型
    local card_small_node = group_detail:getChildByName("small")
    for i = 1, 8 do
        local card_node = card_small_node:getChildByName("template"..i)
        local sub_panel = require("modules.deck.card_small_item").new(card_node)
        self.small_card_list[i] = sub_panel
    end

    -- 卡牌模板
    local card_template_node = require("modules.common.card_hand_item").new()
    card_template_node:setVisible(false)
    card_template_node:setPosition(198, 252)
    self:addChild(card_template_node)

    -- 大卡牌模型
    local card_big_node = group_detail:getChildByName("big")
    for i = 1, 8 do
        local card_node = card_big_node:getChildByName("template"..i)
        local sub_panel = require("modules.deck.card_bag_item").new(card_node)
        sub_panel:InitCardTemplate(card_template_node)
        sub_panel.click_panel:setSwallowTouches(true)
        self.hand_card_list[i] = sub_panel
    end

    self.shadow1_node = self:getChildByName("shadow1")

    -- 待上阵的卡牌
    self.replace_card = ui_helper:ExpandUI(self, "add_card", "modules.deck.card_bag_item")
    self.replace_card:InitCardTemplate(card_template_node)

    -- 退出编辑状态
    self.back_btn = self:getChildByName("back_btn")

    -- 是否显示大卡
    self:SetDeckInfo(deck_logic.cur_deck_id)
    self:SetTabelType(TAB_TYPE.monster)
    self:SetDeckStyle(false)
    self:CloseReplaceStatus()

    self:RegisterWidgetEvent()
    self:RegisterEvent()
end

function meta:Update(elapsed_time)
    if #self.render_queue > 0 then
        local render = self.render_queue[1]
        render()
        table.remove(self.render_queue,1)
    end
end

-- 设置卡组信息
function meta:SetDeckInfo(deck_idx)
    if self.deck_idx == deck_idx then
        return
    end
    self.deck_idx = deck_idx
    self:RefreshDeckCard(self.deck_idx, self.cur_tab)
end

-- 设置卡牌状态
function meta:SetTabelType(tab_type, is_animation)
    is_animation = is_animation or 0
    if self.cur_tab == tab_type and not is_change then
        return
    end
    self.cur_tab = tab_type
    self:RefreshDeckCard(self.deck_idx, tab_type, is_animation)
end

-- 关闭替换状态
function meta:CloseReplaceStatus()
    for i = 1, 8 do
        local sub_panel = self.hand_card_list[i]
        sub_panel:PlayAnimation("normal", false)
        ui_helper:AddClick(sub_panel.click_panel,function ()
            local card_id = self.cur_card_list[i]
            local card_config = deck_logic:GetCardConfigByCardId(card_id)
            graphic:DispatchEvent("deck_card_detail_show", card_config.uid, card_id)
            self:SetDeckStyle(false)
        end)
    end
    self:PlayAnimation("exit_replace")
    self:SetDeckStyle(false)
end

-- 进入替换状态
function meta:ReplaceDeckCard(card_type, listener)
    local new_tab = nil
    if card_type == constants.CARD_TYPE.monster then
        new_tab = TAB_TYPE.monster
    else
        new_tab = TAB_TYPE.item
    end
    self:SetTabelType(new_tab, 1)

    for i = 1, 8 do
        local sub_panel = self.hand_card_list[i]
        ui_helper:AddClick(sub_panel.click_panel,function ()
            listener(i)
        end)

        sub_panel:PlayAnimation("replace", true)
    end

    self:PlayAnimation("enter_replace")
end

-- 刷新卡组卡牌
function meta:RefreshDeckCard(deck_idx, tab_type, is_animation)
    if not deck_idx or not tab_type then
        return
    end
    local deck_info = deck_logic:GetDeckInfo(deck_idx)
    if not deck_info then
        return
    end
    local card_list = {}
    local power_value = 0
    for i = 1, 8 do
        local monster_id = deck_info["monster_pos_"..i]
        local item_id = deck_info["item_pos_"..i]
        if monster_id then
            local config = deck_logic:GetCardConfigByCardId(monster_id)
            power_value = power_value + config.score
        end
        if item_id then
            local config = deck_logic:GetCardConfigByCardId(item_id)
            power_value = power_value + config.score
        end

        if tab_type == TAB_TYPE.monster then
            card_list[i] = monster_id
        else
            card_list[i] = item_id
        end

        local card_id = card_list[i]
        if card_id then
            local card_config = deck_logic:GetCardConfigByCardId(card_id)

            local big_node = self.hand_card_list[i]
            local small_node = self.small_card_list[i]
            big_node:setVisible(false)
            small_node:setVisible(false)

            local render = nil
            if self.is_big_style then
                -- 大卡渲染,
                render = function ()
                    big_node:ShowCardGroupInfo(i, card_config, true)
                    local tt = (i-1) % 4 + 1
                    -- -- 双行渲染
                    local block = cc.CallFunc:create(function ()
                        big_node:setVisible(true)
                        if is_animation == 0 then
                            big_node:PlayAnimation("enter")
                        end
                    end)
                    big_node:runAction(cc.Sequence:create(cc.DelayTime:create(tt * 0.02), block))
                end
            else
                -- 小卡渲染
                render = function ()
                    small_node:ShowCardGroupInfo(i, card_config, true)
                    local tt = i
                    -- 当行渲染
                    local block = cc.CallFunc:create(function ()
                        small_node:setVisible(true)
                        if is_animation == 0 then
                            small_node:PlayAnimation("enter")
                        end
                    end)
                    small_node:runAction(cc.Sequence:create(cc.DelayTime:create(tt * 0.01), block))
                end
            end
            table.insert(self.render_queue, render)
        end
    end

    self.cur_card_list = card_list
    self.deck_select_panel:SetPower(power_value)
    self.deck_select_panel.last_power_value = power_value 

    --设置套牌号
    self.deck_select_panel:SetGroupNum(deck_idx)
end

function meta:SetDeckStyle(is_big_style)
    if self.is_big_style == is_big_style then
        return
    end

    if is_big_style then
        self:PlayAnimation("small_to_big")
    else
        self:PlayAnimation("big_to_small")
    end

    table.insert(self.render_queue, function ()
        self.is_big_style = is_big_style
        self:RefreshDeckCard(self.deck_idx, self.cur_tab, 1)
    end)
end

function meta:RegisterEvent()

    graphic:RegisterEvent("deck_group_tab",function (cur_tab_type)
        self:SetTabelType(cur_tab_type)
    end)

    graphic:RegisterEvent("deck_replace_success",function ()
        self:CloseReplaceStatus()
    end)

    graphic:RegisterEvent("show_deck_group", function (is_big_style)
        self:SetDeckStyle(is_big_style)
    end)

    graphic:RegisterEvent("show_join_deck_panel",function (card_info, card_config)
        self.is_show_deck = true

        self:SetDeckStyle(true)
        local deck_idx = self.deck_idx
        local function _on_jon_deck(target_pos)
            deck_logic:JoinDeck(deck_idx, card_info.id, target_pos)
        end
        self:ReplaceDeckCard(card_config.type, _on_jon_deck)
        self.replace_card:ShowCardGroupInfo(1, card_config)
    end)

    graphic:RegisterEvent("hide_join_deck_panel",function ()
        self.is_show_deck = false
    end)

    graphic:RegisterEvent("deck_info_refresh", function ()
        self:RefreshDeckCard(self.deck_idx, self.cur_tab, 1)
    end)
end

function meta:RegisterWidgetEvent()

    local function pull_deck_event(widget, event_type)
        if event_type ~= ccui.TouchEventType.ended then
            return
        end
        if self.is_show_deck then
            return
        end
        self:SetDeckStyle(not self.is_big_style)
    end

    self.group_detail_node:setTouchEnabled(true)
    self.group_detail_node:addTouchEventListener(pull_deck_event)
    self.shadow1_node:addTouchEventListener(pull_deck_event)

    -- 退出编辑模式
    ui_helper:AddClick(self.back_btn, function ()
        self:CloseReplaceStatus()
        graphic:DispatchEvent("hide_join_deck_panel")
    end)

end


return meta
