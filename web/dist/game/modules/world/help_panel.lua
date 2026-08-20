
local resouce = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local graphic = require "manager.graphic"
local global = require "manager.global"


local meta = class("help_panel",function ()
    return ui_helper:LoadCocosUI("interface/world/help_panel.csb")
end)


function meta:ctor()

    self.back_btn = self:getChildByName("back_btn")


    self:RegisterWidgetEvent()
    self:RegisterEvent()
end

function meta:Update(elapsed_time)
end

function meta:Show()
    self:setVisible(true)
end

function meta:Hide()
    self:setVisible(false)
end

function meta:RegisterEvent()
end

function meta:RegisterWidgetEvent()
    ui_helper:AddClick(self.back_btn, function ()
        graphic:DispatchEvent("pop_world_panel")
    end)

end


return meta
