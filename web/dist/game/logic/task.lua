local graphic = require "manager.graphic"
local network = require "manager.network"
local timer = require "manager.time"
local data_template = require "manager.data_template"
local text_loader = require "manager.text_loader"

local constants = require "common.constants"

local TASK_LIMIT_RESET_COUNT = constants["TASK_LIMIT_RESET_COUNT"]
local TASK_INIT_COUNT = constants["TASK_INIT_COUNT"]
local TASKACHI_STATUS = constants["TASKACHI_STATUS"]
local TASK_CONFIG


local meta = {}
-- 初始化
function meta:Init()
    self.req_refresh = false
    self.cur_min = 0
    self.next_refresh_task_count_time = 0 -- 天刷新
    self.task_count = 0
    self.task_reset_count = 0
    self.next_refresh_task_time = 0 -- 任务刷新

    TASK_CONFIG = data_template.task_config

    self:RegisterMsgHandler()
end

-- 获取任务状态
function meta:GetTaskStage()
    if self.cur_task then
        return self.cur_task.status
    end
    return nil
end

function meta:Update(elapsed_time)
    if self.req_refresh then
        return
    end
    self.cur_min = self.cur_min + elapsed_time
    local diff_time = self.next_refresh_task_count_time - timer:Now()
    if self.cur_min >= 1 and diff_time <= 0 then
        self.cur_min = 0
        self.req_refresh = true
        self:Query(
        function ()
            -- 通知日常刷新了
            self.req_refresh = false
        end,
        function ()
            self.req_refresh = false
        end
        )
    end
    self:CheckTaskRefresh()
end

function meta:CheckTaskRefresh()
    if self.next_refresh_task_time == 0 then
        return
    end
    
    local diff_time = self.next_refresh_task_time - timer:Now()
    if self.cur_min >= 1 and diff_time <= 0 then
        self.cur_min = 0
        self.req_refresh = true
        network:Send("req_task_info", function (result, recv_msg)
            if result ~= "success" then
                -- graphic:DispatchEvent("show_message", result)
                return
            end
            self.cur_task = recv_msg
            self.req_refresh = false
            graphic:DispatchEvent("task_refresh_panel")
        end)
    end
end


function meta:Query(compleate_func, error_func)
    self.next_refresh_task_count_time = self.next_refresh_task_count_time or 0
    local diff_time = self.next_refresh_task_count_time - timer:Now()

    if diff_time < 0 then
        network:Send("req_refresh_task", function (result, recv_msg)
            if result ~= "success" then
                if error_func then
                    error_func(result)
                end
                graphic:DispatchEvent("show_message", result)
                return
            end
            recv_msg = recv_msg or {}
            for k,v in pairs(recv_msg) do
                self[k] = v
            end
            if compleate_func then compleate_func() end
        end)
    end
end

-- 是否是初始任务
function meta:IsInitTask()
    if not self.cur_task then
        return true
    end
    if self.cur_task.id <= TASK_INIT_COUNT then
        return true
    end
    return false
end

-- 重置任务
function meta:ReqResetTask()
    if self.cur_task.id <= TASK_INIT_COUNT or self.task_reset_count >= TASK_LIMIT_RESET_COUNT then
        graphic:DispatchEvent("show_message", "task_reset_failed")
        return
    end

    network:Send("req_task_reset", function (result, recv_msg)
        if result ~= "success" then
            graphic:DispatchEvent("show_message", result)
            return
        end

        self.cur_task = recv_msg
        -- self.task_reset_count = self.task_reset_count + 1
        graphic:DispatchEvent("task_refresh_panel")
        graphic:DispatchEvent("refresh_new_task", false)
    end)

end

-- 任务奖励
function meta:ReqTaskReward()
    local status = self.cur_task.status
    if status ~= TASKACHI_STATUS["can_award"] then
        graphic:DispatchEvent("show_message", "task_reward_failed")
        return
    end

    local task_id = self.cur_task.id

    network:Send("req_task_reward", function (result, recv_msg)
        if result ~= "success" then
            graphic:DispatchEvent("show_message", result)
            return
        end
        local config = TASK_CONFIG[task_id]

        if recv_msg then
            self.cur_task = recv_msg
        end
        graphic:DispatchEvent("task_refresh_panel")

        local message = text_loader:GetText("task_reward_desc")
        graphic:DispatchEvent("show_reward_panel", config.reward_list, nil, message)
        graphic:DispatchEvent("refresh_new_task", false)
    end)

end

-- 显示任务面板
function meta:ShowTaskPanel()
    network:Send("req_task_info", function (result, recv_msg)
        if result ~= "success" then
            graphic:DispatchEvent("show_message", result)
            return
        end
        self.cur_task = recv_msg
        graphic:DispatchEvent("push_world_panel", "task", "task_panel")
    end)
end

-- 注册推送的协议包
function meta:RegisterMsgHandler()

    network:RegisterCommand("cmd_refresh_task", function (recv_msg)
        recv_msg = recv_msg or {}
        for k,v in pairs(recv_msg) do
            self[k] = v
        end
    end)

        -- 成就任务有更新提示
    network:RegisterCommand("cmd_task_achi_hint", function (recv_msg)
        if recv_msg == 1 then
            -- 任务
            graphic:DispatchEvent("refresh_new_task", true)
        elseif recv_msg == 2 then
            -- 成就
            graphic:DispatchEvent("refresh_new_achievement", true)
        end
    end)


end

return meta
