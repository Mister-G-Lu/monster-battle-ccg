local network = require "manager.network"
local graphic = require "manager.graphic"
local data_template = require "manager.data_template"
local text_loader = require "manager.text_loader"


local constants = require "common.constants"

local meta = {}

local TASKACHI_STATUS = constants["TASKACHI_STATUS"]
local ACHIEVEMENT_CONFIG


meta.TAB_NAME = {
    achievement = "achievement",
    footprint = "footprint"
}

function meta:Init()
    self.cur_tab_name = self.TAB_NAME.achievement
    self.achievement_map = {}
    self.statistic_map = {}
    self.achi_points = 0

    ACHIEVEMENT_CONFIG = data_template.achievement_config

    self.is_refresh = true
end

function meta:GetType()
    return self.cur_tab_name
end

function meta:SetType(type)
    self.cur_tab_name = type
end

-- 获取成就列表
function meta:GetAchievementList()
    local list = {}
    for k,v in pairs(self.achievement_map) do
        table.insert(list, v)
    end

    local order = {
        [0] = 1,
        [1] = 0,
        [2] = 2,
    }

    table.sort(list, function (a, b)
        if order[a.status] == order[b.status] then
            return a.id < b.id
        end
        return order[a.status] < order[b.status]
    end)

    return list
end

-- 获取任务列表
function meta:GetStatisticList()
    local list = {}
    for k,v in pairs(self.statistic_map) do
        table.insert(list, v)
    end
    return list
end

-- 检查是否有奖励
function meta:CheckHaveReward()
    for k,v in pairs(self.achievement_map) do
        if v.status == TASKACHI_STATUS["can_award"] then
            return true
        end
    end
    return false
end

-- 请求成就奖励
function meta:ReqAchievementReward(achievement_id)
    local info = self.achievement_map[achievement_id]
    if info.status ~= TASKACHI_STATUS["can_award"] then
        return
    end

    network:Send("req_achievement_reward", { id = achievement_id }, function (result, recv_msg)
        if result ~= "success" then
            graphic:DispatchEvent("show_message", result)
            return
        end

        self.achievement_map[achievement_id].status = TASKACHI_STATUS["finish"]

        if not self:CheckHaveReward() then
            graphic:DispatchEvent("refresh_new_achievement", false)
        end

        local achievement_info = recv_msg
        if achievement_info then
            self.achievement_map[achievement_info.id] = achievement_info
        end

        local config = ACHIEVEMENT_CONFIG[achievement_id]
        local reward_list = config.reward_list

        local message = text_loader:GetText("achievement_reward_desc")
        graphic:DispatchEvent("show_reward_panel", config.reward_list, nil, message)

        graphic:DispatchEvent("achievement_refresh_panel")

    end)
end

function meta:Query()
    network:Send("req_achievement_info", function (result, recv_msg)
        if result ~= "success" then
            graphic:DispatchEvent("show_message", result)
            return
        end

        self.achi_points = recv_msg.achi_points
        local list = recv_msg.achi_list
        self.achievement_map = {}
        for k,v in pairs(list) do
            self.achievement_map[v.id] = v
        end

        if not self:CheckHaveReward() then
            graphic:DispatchEvent("refresh_new_achievement", false)
        end

        graphic:DispatchEvent("push_world_panel", "achievement", "achievement_panel")
    end)

    network:Send("req_statistic_info", function (result, recv_msg)
        if result ~= "success" then
            graphic:DispatchEvent("show_message", result)
            return
        end
        self.statistic_map = {}

        for k,v in pairs(recv_msg) do
            self.statistic_map[v.id] = v
        end

    end)
end


return meta
