local ui_helper = require "manager.ui_helper"

local meta = ui_helper:NewPanel("guide_panel", "interface/world/guide_panel.csb")

function meta:OnInit()
    self.root_node = self:getChildByName("bg")
    self.icon = self.root_node:getChildByName("icon")
    local desc_bg = self.root_node:getChildByName("desc_bg")
    self.name_txt = desc_bg:getChildByName("name")
    self.desc_txt = desc_bg:getChildByName("desc")
end

function meta:Show(callback)
    self.is_first = false
    self:setVisible(true)
    self:PlayAnimation("normal")
    if callback then callback() end
end

function meta:Hide(callback)
    self:setVisible(false)
    if callback then callback() end
end

function meta:OnExit()
end

function meta:RegisterEvent()
    self:RegisterGraphic("show_guide_chat", function (chat_value, callback)
        if not self.is_first then
            self:PlayAnimation("enter")
            self.is_first = true
        else
            self:PlayAnimation("change")
        end

        local data = string.split(chat_value, "@")
        ui_helper:SetText(self.name_txt, data[1])
        ui_helper:SetText(self.desc_txt, data[2])


        ui_helper:AddClick(self.root_node, function ()
            self:PlayAnimation("normal")
            self.root_node:setTouchEnabled(false)
            if callback then callback() end
        end)
    end)
end

return meta
