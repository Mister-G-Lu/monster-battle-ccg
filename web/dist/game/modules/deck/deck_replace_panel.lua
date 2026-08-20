local resouce = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local deck_logic = require "logic.deck"
local data_template = require "manager.data_template"
local reuse_scrollview = require "widget.reuse_scrollview"
local graphic = require "manager.graphic"


local meta = class("deck_replace_panel",function (node)
    return node
end)


function meta:ctor()
    self:setVisible(false)

    self.cur_card_item = require("modules.common.card_hand_item").new()
    self.cur_card_item:setScale(0.43)

    local card_node = self:getChildByName("arrow")
    local pos_x, pos_y = card_node:getPosition()
    self.cur_card_item:setPosition(pos_x, pos_y)
    self:addChild(self.cur_card_item)


    self:RegisterWidgetEvent()
    self:RegisterEvent()
end

function meta:Show(card_uid)
    self.cur_card_item:SetCardId(card_uid)
end

function meta:RegisterWidgetEvent()
    local cancel_btn = self:getChildByName("cancel_btn")
    ui_helper:AddClick(cancel_btn, function()
        graphic:DispatchEvent("hide_join_deck_panel")
    end)
end

function meta:RegisterEvent()

end

return meta
