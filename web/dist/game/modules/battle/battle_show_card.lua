local global = require "manager.global"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local resource = require "manager.resource"
local audio_manager = require "manager.audio_manager"
local constants = require "common.constants"

local battle_logic = require "logic.battle"
local data_template = require "manager.data_template"
local CARD_CONFIG = data_template.card_config

-- 临时卡牌，用于献祭等效果显示
local meta = class("battle_show_card",function ()
    return ui_helper:LoadCocosUI("interface/battle/battle_showcard.csb")
end)


function meta:ctor()

    self.node_list = {}

    -- 战斗卡
    local battle_card_node = self:getChildByName("battlecard")
    battle_card_node:setVisible(false)
    local template = ui_helper:ExpandUI(battle_card_node, "template", "modules.battle.battle_slot_card")
    local titlebg = battle_card_node:getChildByName("titlebg")
    local title = titlebg:getChildByName("title")
    self.node_list["slot"] = {
        root = battle_card_node,
        template = template,
        titlebg = titlebg,
        title = title,
    }

    -- 手牌卡
    local hand_card_node = self:getChildByName("handcard")
    hand_card_node:setVisible(false)
    local template =  ui_helper:ExpandUI(hand_card_node, "template", "modules.battle.battle_hand_card")
    template:ResetTransform(1)
    local titlebg = hand_card_node:getChildByName("titlebg")
    local title = titlebg:getChildByName("title")
    self.node_list["card"] = {
        root = hand_card_node,
        template = template,
        titlebg = titlebg,
        title = title,
    }

    self:PlayAnimation("normal")
end

-- 克隆手牌
function meta:CloneHandCard(hand_card)
    self:setVisible(true)
    local card_node = self.node_list["card"]
    local root = card_node.root
    local template = card_node.template
    local titlebg_node = card_node.titlebg
    local title_txt = card_node.title

    local card_info = hand_card.card_info

    root:setVisible(true)

    local parent = hand_card:getParent()
    local parent_x, parent_y  = hand_card:getPosition()
    local p = parent:convertToWorldSpace({x = parent_x, y = parent_y})
    p.y = p.y - 20
    self:setPosition({ x = p.x, y = p.y})
    self:setRotation(hand_card:getRotation())
    template:setScale(hand_card:getScale())
    template:Show(card_info)
    template:setVisible(true)
    self:PlayAnimation("normal")
end

-- 克隆战牌
function meta:CloneSlotCard(slot_card)
    self:setVisible(true)
    local card_node = self.node_list["slot"]
    local root = card_node.root
    local template = card_node.template
    local titlebg_node = card_node.titlebg
    local title_txt = card_node.title

    local slot_info = slot_card.slot_info

    root:setVisible(true)

    self:setPosition(slot_card:getPosition())
    template:setScale(slot_card:getScale())

    template:SetEmptyNode(template, 1, false)

    template:SetMonsterCard(slot_info.monster)
    template:SetItemCard(slot_info.item, false)
    template:UpdateSlotInfo(slot_info)
    template:setVisible(true)    
    self:PlayAnimation("normal")

end

-- 执行战牌献祭动画
function meta:DoSlotSacrificeAnimation(is_own, callback)
    local move_act = cc.MoveTo:create(0.4, { x = 320 , y = 410 })
    local rotate_act = cc.RotateTo:create(0.4, 0)
    local curve_func = cc["EaseCubicActionInOut"]:create(move_act)
    self:PlayAnimation("enter")

    local card_node = self.node_list["slot"]
    local template = card_node.template
    local titlebg = card_node.titlebg
    titlebg:setVisible(false)

    local block = cc.CallFunc:create(function ()
        self:PlayAnimation("exit")
        template:DoSacrificeSlot(function ()
            callback()
            self:Hide()
        end)
    end)
    -- 移动，等待0.3，退出事件
    local actions = cc.Sequence:create(cc.Spawn:create(curve_func, rotate_act), cc.DelayTime:create(0.3), block)
    self:runAction(actions)
end

-- 执行手牌献祭动画
function meta:DoHandSacrificeAnimation(is_own, callback)
    local move_act = cc.MoveTo:create(0.4, { x = 320 , y = 410 })
    local rotate_act = cc.RotateTo:create(0.4, 0)
    local curve_func = cc["EaseCubicActionInOut"]:create(move_act)
    self:PlayAnimation("enter")

    local card_node = self.node_list["card"]
    local template = card_node.template
    local titlebg = card_node.titlebg
    titlebg:setVisible(false)

    local block = cc.CallFunc:create(function ()
        self:PlayAnimation("exit")
        template:DisCardAnimation(true, function ()
            callback()
            self:Hide()
        end)
    end)
    -- 移动，等待0.3，退出事件
    local actions = cc.Sequence:create(cc.Spawn:create(curve_func, rotate_act), cc.DelayTime:create(0.3), block)
    self:runAction(actions)
end

local DECK_POS = {
    [true] = { { x = 476, y = 516},{ x = 164, y = 516} },
    [false] = { { x = 476, y = 900},{ x = 164, y = 900} },
}
-- 献祭牌堆卡动画
function meta:DoSacrificeDeckCard(is_own, discard_card)
    self:setVisible(true)
    local card_node = self.node_list["card"]
    local root = card_node.root
    local template = card_node.template
    local titlebg_node = card_node.titlebg
    local title_txt = card_node.title

    root:setVisible(true)
    template:Show(discard_card)
    local pos = {}
    if discard_card.type == constants.CARD_TYPE.monster then
        pos = DECK_POS[is_own][1]
    else
        pos = DECK_POS[is_own][2]
    end

    if is_own then
        ui_helper:SetTextByKey(title_txt, "own_deck_penalty")
    else
        ui_helper:SetTextByKey(title_txt, "enemy_deck_penalty")
    end

    local _event = function ()
        self:PlayAnimation("exit", false, function ()
            template:DisDeckAnimation(discard_card.type, function ()
                self:Hide()
            end)
        end)
    end

    self:setPosition(pos)
    self:PlayAnimation("enter", false, function ()
        performWithDelay(self, _event, 0.5)
    end)
end

-- 隐藏
function meta:Hide()
    self:setVisible(false)
    for k,v in pairs(self.node_list) do
        v.root:setVisible(false)
        v.template:setScale(1)
    end

    self:setRotation(0)
end

return meta
