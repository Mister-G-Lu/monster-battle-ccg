local global = require "manager.global"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local resource = require "manager.resource"
local text_loader = require "manager.text_loader"

local bit = require "utils.bit_extension"
local constants = require "common.constants"
local defines = require "manager.defines"

local data_template = require "manager.data_template"

local CARD_CONFIG = data_template.card_config
local CARD_KIND_COLOR = defines["CARD_KIND_COLOR"]

local meta = class("battle_card_template",function (node)
    if node then
        return node
    end
    return ui_helper:LoadCocosUI("interface/battle/card_battlefield_template.csb")
end)

function meta:ctor()
    local card_battleField = self:getChildByName("card_battlefield_template")
    -- 卡图
    self.card_img = card_battleField:getChildByName("card")
    -- 种类
    self.color_border1 = card_battleField:getChildByName("color_border1")
    self.color_border2 = card_battleField:getChildByName("color_border2")
    self.color_border2:setVisible(false)
    -- 种类图标
    self.color_icon1_img = card_battleField:getChildByName("color_icon1")
    self.color_icon2_img = card_battleField:getChildByName("color_icon2")


    self.equipment_empty = card_battleField:getChildByName("equipment_empty")

    local equipment = card_battleField:getChildByName("equipment")
    self.equipment_node = equipment
    self.equip_card_img = equipment:getChildByName("equip_card")

    self.card_battleField = card_battleField

end

function meta:SetCardId(uid)
    self.uid = uid
    self:SetCardInfo(CARD_CONFIG[uid])
end

function meta:SetCardInfo(card_info)
    if not card_info then
        return
    end
    local config = card_info
    self.card_img:loadTexture(resource:GetCardImage(config.type, config.kind, config.res_path))
    -- 种类
    local kind_list = {}
    for k,v in pairs(constants["CARD_KIND"]) do
        if bit:GetBitNum(config.kind, v) == 1 then
            table.insert(kind_list, k)
        end
    end

    local len = #kind_list
    self.color_border1:setColor(ui_helper:GetColor4B(CARD_KIND_COLOR[kind_list[1]]))

    self.color_icon1_img:loadTexture(resource:GetKindIcon(kind_list[1]))

    if len ~= 1 then
        self.color_border2:setVisible(true)
        self.color_border2:setColor(ui_helper:GetColor4B(CARD_KIND_COLOR[kind_list[2]]))
        self.color_icon2_img:loadTexture(resource:GetKindIcon(kind_list[2]))
    else
        self.color_border2:setVisible(false)
        self.color_icon2_img:loadTexture(resource:GetKindIcon(kind_list[1]))
    end

    self:SetEquipInfo(nil)
end

function meta:SetEquipInfo(equip_info)
    if not equip_info then
        self.equipment_node:setVisible(false)
        self.equipment_empty:setVisible(true)
        return
    end

    self.equipment_node:setVisible(true)
    self.equipment_empty:setVisible(false)

    local config = equip_info
    self.equip_card_img:setVisible(true)
    self.equip_card_img:loadTexture(resource:GetCardImage(config.type, config.kind, config.res_path))
end



return meta
