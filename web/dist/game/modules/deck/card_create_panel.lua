local global = require "manager.global"
local ui_helper = require "manager.ui_helper"
local constants = require "common.constants"
local resource = require "manager.resource"
local graphic = require "manager.graphic"
local text_loader = require "manager.text_loader"
local data_template = require "manager.data_template"
local deck_logic = require "logic.deck"
local resource_logic = require "logic.resource"
--local detail_panel = require "modules.deck.card_detail_panel"

local COMPOSE_CONFIG = data_template.card_compose_config

local meta = class("card_create_panel",function (node)
     return node
end)

function meta:ctor()
    local prop_bg =  self:getChildByName("bg2")
    self.prop_value = prop_bg:getChildByName("value1")
    --怪兽卡粉末
    local monster_bg = self:getChildByName("bg")
    self.monster_value = monster_bg:getChildByName("value1")

    self:RegisterEvent()
end

function meta:PowderShow()
    local prop_num = tonumber(resource_logic:GetItemNum(200001))
    local monster_num = tonumber(resource_logic:GetItemNum(100001))
    ui_helper:SetText(self.prop_value, prop_num)
    ui_helper:SetText(self.monster_value, monster_num)
end

function meta:RegisterEvent()
    graphic:RegisterEvent("show_powder_numer",function ()
        self:PowderShow()
    end)
end

return meta
