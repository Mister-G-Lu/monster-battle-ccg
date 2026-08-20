local resource = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local graphic = require "manager.graphic"
local timer = require "manager.time"


local constants = require "common.constants"
local data_template = require "manager.data_template"
local CHEST_STAGE = constants.CHEST_STAGE

local meta = class("arena_chest_template",function (node)
    if node then
        return node
    end
    return ui_helper:LoadCocosUI("interface/world/cardbag_tab_template.csb")
end)

function meta:ctor()

    local bag_btn = self:getChildByName("bag_btn_template")
    self.icon_img = bag_btn:getChildByName("icon")
    self.time_txt = bag_btn:getChildByName("time")
    self.bag_btn = bag_btn

    ui_helper:BindTimeLine(self, "interface/world/cardbag_tab_template.csb")

    self:RegisterEvent()
    self:RegisterWidgetEvent()
end

function meta:Update(elapsed_time)
    if self.chest_info then
        local chest_info = self.chest_info
        if chest_info.stage == CHEST_STAGE.opening then
            local diff_time = math.floor(chest_info.open_time - timer:Now())
            if diff_time <= 0 then
                ui_helper:SetTextByKey(self.time_txt,"deck_chest_time_over")
            else
                ui_helper:SetText(self.time_txt, timer:GetLastTimeStr(diff_time))
            end
        end
    end

end

function meta:SetChestInfo(chest_info, is_active)
    self.chest_info = chest_info
    if chest_info.stage == CHEST_STAGE.empty then
        self:PlayAnimation("normal_empty")
    else
        if is_active then
            self:PlayAnimation("normal_active")
        else
            self:PlayAnimation("normal_inactive")
        end
        local chest_config = data_template.chest_config[chest_info.chest_id]
        local quality = chest_config.quality
        self.icon_img:loadTexture(resource:GetChestIcon(constants["CHEST_QUALITY"][quality]))

        if chest_info.stage == CHEST_STAGE.wait_open then
            if chest_info.open_time == 0 then
                ui_helper:SetTextByKey(self.time_txt,"deck_chest_time_over")
            else
                ui_helper:SetText(self.time_txt, timer:GetLastTimeStr(chest_info.open_time))
            end
        elseif chest_info.stage == CHEST_STAGE.opening then
            local diff_time = math.floor(chest_info.open_time - timer:Now())
            if diff_time == 0 then
                ui_helper:SetTextByKey(self.time_txt,"deck_chest_time_over")
            else
                ui_helper:SetText(self.time_txt, timer:GetLastTimeStr(diff_time))
            end
        end
    end
end

function meta:SetActive(is_active)
    if is_active then
        self:PlayAnimation("enter_active", false, function ()
            self:PlayAnimation("normal_active")
        end)
    else
        self:PlayAnimation("enter_inactive", false, function ()
            self:PlayAnimation("normal_inactive")
        end)
    end
end

function meta:AddClick(func)
    ui_helper:AddClick(self.bag_btn, func)
end

-- 注册渲染事件
function meta:RegisterEvent()

end

-- 注册UI事件
function meta:RegisterWidgetEvent()

end

return meta
