local global = require "manager.global"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local battle_logic = require "logic.battle"
local constants = require "common.constants"

local POWER_NAME = constants.POWER_NAME

local hand_card_template = require("modules.common.card_hand_item")
local slot_card_template = require("modules.battle.battle_slot_card")

local CARD_IMMOLATION_CRYSTAL = constants["CARD_IMMOLATION_CRYSTAL"]

local meta = class("battle_sacrifice_panel",function ()
    return ui_helper:LoadCocosUI("interface/battle/sacrifice_panel.csb")
end)

function meta:ctor()
    self.battle_slot_list = {}
    self.sacrifice_hand_card_list = {}

    local sacrifice_panel = self:getChildByName("sacrifice_panel")

    local sacrifice_value_panel = sacrifice_panel:getChildByName("sacrifice_value_panel")
    local cards_panel = sacrifice_panel:getChildByName("cards_panel")

    self.desc1_txt = sacrifice_panel:getChildByName("desc1")
    for i = 1, 3 do
        local info = {}
        local root = cards_panel:getChildByName("battlefield_template"..i)
        root:setTouchEnabled(true)
        root:setTag(i)
        info.root_widget = root

        local battle_slot = slot_card_template.new()
        battle_slot:setScale(1.8)
        battle_slot:setPosition(170, 240)
        info.battle_slot_widget = battle_slot
        root:addChild(battle_slot)


        local crystal_widget = sacrifice_value_panel:getChildByName("slot_sacrifice_panel"..i)
        local num_txt = crystal_widget:getChildByName("value")
        info.num_widget = num_txt
        info.crystal_widget = crystal_widget

        self.battle_slot_list[i] = info
    end

    for i = 1, 4 do
        local info = {}
        local root = cards_panel:getChildByName("handcard_template"..i)
        root:setTouchEnabled(true)
        root:setTag(i)
        info.root_widget = root

        local crystal_widget = sacrifice_value_panel:getChildByName("hand_sacrifice_panel"..i)
        local num_txt = crystal_widget:getChildByName("value")
        info.num_widget = num_txt
        info.crystal_widget = crystal_widget

        self.sacrifice_hand_card_list[i] = info
    end
    self:RegisterWidgetEvent()
end

function meta:Show(hand_card_widget_list)
    self:setVisible(true)
    self:PlayAnimation("enter")

    local own_player = battle_logic.own_player
    local battle_card_list = own_player.battle_slot
    local hand_card_info_list = own_player.hand_card

    for i = 1, 3 do
        local root_widget = self.battle_slot_list[i].root_widget
        local crystal_widget = self.battle_slot_list[i].crystal_widget
        local card_info = battle_card_list[i]
        root_widget:setVisible(false)
        crystal_widget:setVisible(false)
        if card_info then
            performWithDelay(self, function()
                root_widget:setVisible(true)
                crystal_widget:setVisible(true)

                local battle_slot_widget = self.battle_slot_list[i].battle_slot_widget
                local slot_info = battle_logic.own_player:GetBattleCard(i)

                battle_slot_widget:SetMonsterCard(slot_info.monster)
                battle_slot_widget:SetItemCard(slot_info.item)
                battle_slot_widget:SetHp(slot_info.cur_hp - slot_info.init_hp)
                battle_slot_widget:SetArmor(slot_info.cur_ad - slot_info.init_ad)
                battle_slot_widget:UpdateSlotInfo(slot_info)

                local crystal_num = CARD_IMMOLATION_CRYSTAL["battle"]
                local num_widget = self.battle_slot_list[i].num_widget

                local crystal_power = card_info.power_map[POWER_NAME.crystal]
                if crystal_power then
                    crystal_num = crystal_num + crystal_power.value
                end

                ui_helper:SetText(num_widget, crystal_num)
            end, 0.1 * i)
        end
    end

    for i = 1, 4 do
        local root_widget = self.sacrifice_hand_card_list[i].root_widget
        local crystal_widget = self.sacrifice_hand_card_list[i].crystal_widget

        local card_info = hand_card_info_list[i]
        local hand_card_widget = hand_card_widget_list[i]
        if card_info then
            root_widget:setVisible(true)
            crystal_widget:setVisible(true)
            root_widget:removeChildByName("render_texture")
            local size = root_widget:getContentSize()
            local render_texture = hand_card_widget.card_texture
            if render_texture then
                local card_img = cc.Sprite:createWithTexture(render_texture)
                card_img:setFlippedY(true)
                card_img:setPosition({ x = size.width / 2, y = size.height /2})
                card_img:setName("render_texture")
                root_widget:addChild(card_img)
            end

            local crystal_num = CARD_IMMOLATION_CRYSTAL[card_info.type]
            local num_widget = self.sacrifice_hand_card_list[i].num_widget

            card_info.power_list = card_info.power_list or {}

            for k,v in pairs(card_info.power_list) do
                if v.name == POWER_NAME.crystal then
                    -- 额外水晶->转化这张卡的时候获得额外的能量水晶
                    crystal_num = crystal_num + v.value
                end
            end
            ui_helper:SetText(num_widget, crystal_num)
        else
            root_widget:setVisible(false)
            crystal_widget:setVisible(false)
        end
    end
end



function meta:Hide()
    self:PlayAnimation("exit", false, function ()
        self:setVisible(false)
    end)
end

function meta:DoExit()
    battle_logic:DispatchEvent("pop_battle_panel")
end

function meta:RegisterWidgetEvent()
    local exit_btn = self.desc1_txt:getChildByName("exit_btn")
    ui_helper:AddClick(exit_btn, function ()
        self:DoExit()
    end)
    for i = 1, 3 do
        local root = self.battle_slot_list[i].root_widget
        ui_helper:AddClick(root, function ()
            battle_logic:ReqSacrificeCard(false, i)
        end)
    end
    for i = 1, 4 do
        local root = self.sacrifice_hand_card_list[i].root_widget
        ui_helper:AddClick(root, function ()
            battle_logic:ReqSacrificeCard(true, i)
        end)
    end
end

return meta
