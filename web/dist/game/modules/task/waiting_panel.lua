local ui_helper = require "manager.ui_helper"
local task_logic = require "logic.task"
local timer = require "manager.time"

local constants = require "common.constants"
local TASK_LIMIT_COUNT = constants["TASK_LIMIT_COUNT"]

local meta = ui_helper:NewPanel("waiting_panel", "interface/task/task_waiting_node.csb")


function meta:OnInit()

    local ui_root = self:getChildByName("waitting_node")
    self.time_txt = ui_root:getChildByName("time")
    self.desc_txt = ui_root:getChildByName("desc")

    self:RegisterWidgetEvent()
end

function meta:OnExit()
end

function meta:Update()
    local next_refresh_task_time = task_logic.next_refresh_task_time
    if next_refresh_task_time > 0 then
        local diff_time = task_logic.next_refresh_task_time - timer:Now()
        ui_helper:SetText(self.time_txt, timer:FormatTime(diff_time))
    end
end

function meta:Show()
    self:setVisible(true)

    self.task_count = TASK_LIMIT_COUNT - task_logic.task_count
    local task_count = self.task_count

    if task_count <= 0 then
        ui_helper:SetTextByKey(self.time_txt, "task_daily_clean")
    else
        self:Update(0.0)
    end

    ui_helper:SetTextByKey(self.desc_txt, "task_daily_last_num", task_count)
end

function meta:Hide()
    self:setVisible(false)
end

function meta:RegisterEvent()
end

function meta:RegisterWidgetEvent()

end

return meta
