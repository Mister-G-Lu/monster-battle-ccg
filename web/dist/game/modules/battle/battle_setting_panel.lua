local global = require "manager.global"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local network = require "manager.network"

local battle_logic = require "logic.battle"

local meta = class("battle_setting_panel",function ()
    local animation = ui_helper:LoadCocosUI("interface/common/msgbox_animation_panel.csb")

    local msgbox_panel = animation:getChildByName("msgbox_panel")
    local ui_root = ui_helper:LoadCocosUI("interface/battle/setting_panel.csb")
    animation.ui_root = ui_root
    msgbox_panel:addChild(ui_root)
    return animation
end)

function meta:ctor()
    local msgbox_bg = self.ui_root:getChildByName("msgbox_panel")

    self.consume_btn = msgbox_bg:getChildByName("consume_btn")
    self.lose_btn = msgbox_bg:getChildByName("surrender_btn")
    self.back_btn = msgbox_bg:getChildByName("close_btn")

    self:RegisterWidgetEvent()
end

function meta:RegisterWidgetEvent()

    ui_helper:AddClick(self.consume_btn, function ()
        self:DoExit()
    end)
    ui_helper:AddClick(self.back_btn, function ()
        self:DoExit()
    end)
    ui_helper:AddClick(self.lose_btn, function ()
        battle_logic:ReqBattleSurrender()
    end)
end

function meta:Show(exit_callback)
    self:setVisible(true)
    self:PlayAnimation("enter")
    self.exit_callback = exit_callback
end

function meta:Hide()
    self:PlayAnimation("exit",false,function ( )
        self:setVisible(false)
        self.exit_callback()
    end)
end

function meta:DoExit()
    battle_logic:DispatchEvent("pop_battle_panel")
    if self.exit_callback then
        self.exit_callback()
    end
end

return meta
