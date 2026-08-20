local ui_helper = require "manager.ui_helper"
local meta = ui_helper:NewPanel("waring_panel", "interface/common/signal_node.csb")

function meta:OnInit()
    self.signal_node = self:getChildByName("signal")
    self:setPosition(cc.p(100,100))
    self:setVisible(false)
end

function meta:Show()
    self:setVisible(true)
    self:PlayAnimation("enter", false, function ()
        self:PlayAnimation("loop",true)
    end)
end

function meta:Hide()
    self:PlayAnimation("exit",false,function()
        self:setVisible(false)
    end)
end

function meta:RegisterEvent()
    self:RegisterGraphic("show_waring_panel",function()
        self:Show()
    end)
    self:RegisterGraphic("hide_waring_panel",function()
        self:Hide()
    end)
end

return meta
