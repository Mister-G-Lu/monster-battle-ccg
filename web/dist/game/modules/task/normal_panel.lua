local ui_helper = require "manager.ui_helper"
local data_template = require "manager.data_template"
local task_logic = require "logic.task"

local constants = require "common.constants"

local TASK_CONFIG = data_template.task_config

local TASK_LIMIT_RESET_COUNT = constants["TASK_LIMIT_RESET_COUNT"]
local TASKACHI_STATUS = constants["TASKACHI_STATUS"]

local meta = ui_helper:NewPanel("normal_panel", "interface/task/task_normal_node.csb")

function meta:OnInit()

    local ui_root = self:getChildByName("normal_node")

    -- 刷新时间
    self.refresh_desc = ui_root:getChildByName("info_desc")
    -- 任务描述
    self.task_desc = ui_root:getChildByName("task_desc")
    -- 奖励节点
    self.reward_container_list = ui_root:getChildByName("reward_list")
    self.reward_node_list = {}

    self.transform_btn = ui_root:getChildByName("transform_btn")



    self:RegisterWidgetEvent(ui_root)
end



function meta:Show(info)
    self:setVisible(true)

    local config = TASK_CONFIG[info.id]

    local task_reset_count = TASK_LIMIT_RESET_COUNT - task_logic.task_reset_count

    -- 免费刷新时间
    ui_helper:SetTextByKey(self.refresh_desc, "task_free_refresh_desc", task_reset_count, TASK_LIMIT_RESET_COUNT)
    -- 任务进度
    if info.progress >= config.value then
        ui_helper:SetTextByKey(self.progress_desc_txt, "task_complete")
    else
        ui_helper:SetTextByKey(self.progress_desc_txt, "task_progress_desc", info.progress, config.value)
    end
    -- 任务描述
    ui_helper:SetText(self.task_desc, config.desc)

    if info.status == TASKACHI_STATUS["begin"] then
        self.confirm_btn:setEnabled(false)
    else
        self.confirm_btn:setEnabled(true)
    end

    if task_logic:IsInitTask() then
        self.refresh_desc:setVisible(false)
        self.transform_btn:setVisible(false)
    else
        self.refresh_desc:setVisible(true)
        self.transform_btn:setVisible(true)
    end

    local reward_info_list = config.reward_list
    local old_num = #self.reward_node_list

    local reward_num = #reward_info_list

    local start_idx = -(reward_num-1) / 2
    for i = 1, math.max(old_num, reward_num) do
        local reward_node = self.reward_node_list[i]
        if not reward_node then
            reward_node = require("modules.common.material_item").new()
            self.reward_node_list[i] = reward_node
            self.reward_container_list:addChild(reward_node)
        end

        local reward_info = reward_info_list[i]
        if not reward_info then
            reward_node:setVisible(false)
        else
            reward_node:setVisible(true)
            reward_node:ShowReward(reward_info)
            local xx = (start_idx + i - 1)  * 100
            reward_node:setPositionX(xx)
            reward_node:SetBackGroupVisible(true)
        end
    end
end

function meta:Hide()
    self:setVisible(false)
end

function meta:RegisterWidgetEvent(ui_root)

    local confirm_btn = ui_root:getChildByName("confirm_btn")
    ui_helper:AddClick(confirm_btn, function ()
        task_logic:ReqTaskReward()
    end)

    self.confirm_btn = confirm_btn
    self.progress_desc_txt = confirm_btn:getChildByName("desc")

    ui_helper:AddClick(self.transform_btn, function ()
        task_logic:ReqResetTask()
    end)

end

return meta
