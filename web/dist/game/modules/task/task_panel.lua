local ui_helper = require "manager.ui_helper"

local task_logic = require "logic.task"
local constants = require "common.constants"


local TASKACHI_STATUS = constants["TASKACHI_STATUS"]

local meta = ui_helper:NewPanel("task_panel", "interface/task/task_panel.csb")

function meta:OnInit()
    self.ui_root = self:getChildByName("node")

    self.stage_node = self.ui_root:getChildByName("stage_node")

    self:RegisterWidgetEvent()
end


function meta:Update(elapsed_time)
    local waiting_panel = self.waiting_panel
    if waiting_panel and waiting_panel:isVisible() then
        waiting_panel:Update(elapsed_time)
    end
end

function meta:Show()
    self:setVisible(true)

    if self.normal_panel then
        self.normal_panel:Hide()
    end

    if self.waiting_panel then
        self.waiting_panel:Hide()
    end

    local task_staus = task_logic:GetTaskStage()
    if task_staus == TASKACHI_STATUS["begin"] or task_staus == TASKACHI_STATUS["can_award"] then
        if not self.normal_panel then
            self.normal_panel = require("modules.task.normal_panel").new()
            self.stage_node:addChild(self.normal_panel)
        end
        local task_info = task_logic.cur_task
        self.normal_panel:Show(task_info)
    elseif task_staus == nil then
        if not self.waiting_panel then
            self.waiting_panel = require("modules.task.waiting_panel").new()
            self.stage_node:addChild(self.waiting_panel)
        end
        self.waiting_panel:Show()
    end
end

function meta:Hide()
    self:setVisible(false)
end

function meta:RegisterEvent()
    self:RegisterGraphic("task_refresh_panel", function ()
        self:Show()
    end)
end

function meta:RegisterWidgetEvent()
    local ui_root = self.ui_root
    -- 关闭
    local close_btn = ui_root:getChildByName("close_btn")
    ui_helper:AddClick(close_btn, function ()
        self:DispatchGraphicEvent("pop_world_panel")
    end)
end

return meta
